"""deckd — the Stream Deck Mini device server for Claude Deck Mini.

A thin USB-HID helper with no app logic. It:
  • opens the first Stream Deck,
  • reads line-delimited JSON commands on stdin (render / brightness / clear),
  • paints keys via render.paint_key and pushes them to the device,
  • emits line-delimited JSON events on stdout (ready / keydown / error).

The Swift app (DeckdBridge) is the only client. Run with --selftest to paint a
fixed demo layout and exit (manual hardware check, no stdin needed).
"""

from __future__ import annotations

import json
import sys
import threading

from StreamDeck.DeviceManager import DeviceManager
from StreamDeck.ImageHelpers import PILHelper

import render


def _emit(obj: dict) -> None:
    sys.stdout.write(json.dumps(obj) + "\n")
    sys.stdout.flush()


class Deckd:
    def __init__(self, deck):
        self.deck = deck
        self._lock = threading.Lock()

    def open(self):
        self.deck.open()
        self.deck.reset()
        self.deck.set_brightness(60)
        self.deck.set_key_callback(self._on_key)
        _emit({
            "event": "ready",
            "serial": self._safe_serial(),
            "keyCount": self.deck.key_count(),
        })

    def _safe_serial(self):
        try:
            return self.deck.get_serial_number()
        except Exception:
            return None

    def _on_key(self, deck, key, pressed):
        # Report presses (key-down) only; the app decides what a press means.
        if pressed:
            _emit({"event": "keydown", "index": key})

    def _set_key(self, index, spec):
        if index < 0 or index >= self.deck.key_count():
            return
        image = render.paint_key(spec, size=self.deck.key_image_format()["size"])
        native = PILHelper.to_native_format(self.deck, image)
        with self._lock:
            self.deck.set_key_image(index, native)

    def render(self, cmd):
        brightness = cmd.get("brightness")
        if isinstance(brightness, int):
            self.deck.set_brightness(max(0, min(100, brightness)))
        keys = {k["index"]: k for k in cmd.get("keys", []) if "index" in k}
        for i in range(self.deck.key_count()):
            self._set_key(i, keys.get(i, {"kind": "blank"}))

    def clear(self):
        with self._lock:
            self.deck.reset()

    def handle(self, cmd: dict):
        kind = cmd.get("cmd")
        if kind == "render":
            self.render(cmd)
        elif kind == "brightness":
            self.deck.set_brightness(max(0, min(100, int(cmd.get("value", 60)))))
        elif kind == "clear":
            self.clear()

    def run_stdin_loop(self):
        for line in sys.stdin:
            line = line.strip()
            if not line:
                continue
            try:
                self.handle(json.loads(line))
            except Exception as exc:  # never die on one bad command
                _emit({"event": "error", "message": str(exc)})
        self.close()

    def close(self):
        try:
            self.deck.reset()
            self.deck.close()
        except Exception:
            pass


def first_deck():
    decks = DeviceManager().enumerate()
    if not decks:
        _emit({"event": "error", "message": "no Stream Deck found"})
        sys.exit(1)
    return decks[0]


def selftest(d: Deckd):
    demo = {
        "cmd": "render",
        "brightness": 70,
        "keys": [
            {"index": 0, "kind": "agent", "repo": "residently",
             "branch": "feature/foo", "status": "waiting", "age": "2m ago"},
            {"index": 1, "kind": "agent", "repo": "claude-deck",
             "branch": "main", "status": "working", "age": "just now"},
            {"index": 2, "kind": "agent", "label": "notes",
             "status": "idle", "age": "41h ago"},
            {"index": 3, "kind": "blank"},
            {"index": 4, "kind": "blank"},
            {"index": 5, "kind": "more", "remaining": 3},
        ],
    }
    d.handle(demo)


def main():
    d = Deckd(first_deck())
    d.open()
    if "--selftest" in sys.argv:
        selftest(d)
        return
    try:
        d.run_stdin_loop()
    except KeyboardInterrupt:
        d.close()


if __name__ == "__main__":
    main()
