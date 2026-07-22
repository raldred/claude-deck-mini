"""deckd — the Stream Deck Mini device server for Claude Deck Mini.

A thin USB-HID helper with no app logic. It:
  • opens the first Stream Deck,
  • reads line-delimited JSON commands on stdin (render / brightness / clear),
  • paints keys via render.paint_key and pushes them to the device,
  • animates keys at a low frame rate (marquee titles, pulsing waiting bands),
  • emits line-delimited JSON events on stdout (ready / keydown / error).

The Swift app (DeckdBridge) is the only client. Run with --selftest to paint a
fixed demo layout, animate briefly, and exit (manual hardware check).
"""

from __future__ import annotations

import json
import math
import os
import sys
import threading
import time


def _ensure_hidapi_prefix() -> None:
    """Point the streamdeck lib at a libhidapi.dylib it can load.

    The lib reads HOMEBREW_PREFIX and loads `<prefix>/lib/libhidapi.dylib`.
    When launched from Finder the app inherits no PATH and no HOMEBREW_PREFIX,
    so the lib's own `brew --prefix` fallback can't run. Prefer a copy vendored
    inside the app bundle (so downloads need no Homebrew), then fall back to a
    local Homebrew install for dev.
    """
    if os.environ.get("HOMEBREW_PREFIX"):
        return
    here = os.path.dirname(os.path.abspath(__file__))
    candidates = (os.path.join(here, "vendor"), "/opt/homebrew", "/usr/local")
    for prefix in candidates:
        if os.path.exists(os.path.join(prefix, "lib", "libhidapi.dylib")):
            os.environ["HOMEBREW_PREFIX"] = prefix
            return


_ensure_hidapi_prefix()

from StreamDeck.DeviceManager import DeviceManager
from StreamDeck.ImageHelpers import PILHelper

import render

FRAME_INTERVAL = 0.33          # ~3fps — coarse but easy on USB
SCROLL_STRIDE = 4              # px advanced per frame (larger to read at low fps)
SCROLL_HOLD_FRAMES = 2         # frames to hold at the start of each scroll cycle
PULSE_PERIOD_FRAMES = 5        # ~1.5s breathe at 3fps


def _emit(obj: dict) -> None:
    sys.stdout.write(json.dumps(obj) + "\n")
    sys.stdout.flush()


class Deckd:
    def __init__(self, deck):
        self.deck = deck
        # Re-entrant: a locked frame tick calls _push_key, which re-locks.
        self._lock = threading.RLock()
        self._size = (80, 80)
        self._scene = {}        # index -> spec (full 0..key_count, incl. blank/banner)
        self._scene_keys = None  # last incoming "keys" list; None until first render
        self._anim = {}         # index -> {"scroll": int, "hold": int}
        self._animated = set()  # indices that need per-frame repaint
        self._frame = 0
        self._stop = threading.Event()
        self._thread = None

    def open(self):
        self.deck.open()
        self.deck.reset()
        self.deck.set_brightness(60)
        self.deck.set_key_callback(self._on_key)
        self._size = self.deck.key_image_format()["size"]
        _emit({
            "event": "ready",
            "serial": self._safe_serial(),
            "keyCount": self.deck.key_count(),
        })

    def start_frames(self):
        if self._thread is None:
            self._thread = threading.Thread(target=self._run_frames, daemon=True)
            self._thread.start()

    def _safe_serial(self):
        try:
            return self.deck.get_serial_number()
        except Exception:
            return None

    def _on_key(self, deck, key, pressed):
        # Report presses (key-down) only; the app decides what a press means.
        if pressed:
            _emit({"event": "keydown", "index": key})

    # MARK: - scene

    def _push_key(self, index, spec, scroll_x=0, marquee=False, pulse=1.0):
        if index < 0 or index >= self.deck.key_count():
            return
        image = render.paint_key(spec, size=self._size,
                                 scroll_x=scroll_x, marquee=marquee, pulse=pulse)
        native = PILHelper.to_native_format(self.deck, image)
        with self._lock:
            self.deck.set_key_image(index, native)

    def _render_static(self, index, spec):
        """Paint a key in its resting state (start of any animation cycle)."""
        marquee, _ = render.title_overflow(spec, self._size)
        self._push_key(index, spec, scroll_x=0, marquee=marquee, pulse=1.0)

    def render(self, cmd):
        # One lock for the whole swap: brightness + scene state + device writes
        # stay consistent against the frame thread and never interleave.
        with self._lock:
            brightness = cmd.get("brightness")
            if isinstance(brightness, int):
                self.deck.set_brightness(max(0, min(100, brightness)))

            incoming = [k for k in cmd.get("keys", []) if "index" in k]
            if incoming == self._scene_keys:
                return  # identical scene — keep animating, don't reset offsets

            self._scene_keys = incoming
            keys = {k["index"]: k for k in incoming}
            self._scene = {i: keys.get(i, {"kind": "blank"})
                           for i in range(self.deck.key_count())}
            self._anim = {}
            self._animated = set()
            for i, spec in self._scene.items():
                overflows, _ = render.title_overflow(spec, self._size)
                if overflows or spec.get("status") == "waiting":
                    self._animated.add(i)
                self._render_static(i, spec)

    def _run_frames(self):
        while not self._stop.wait(FRAME_INTERVAL):
            # Hold the lock across the whole tick so per-key _anim state and the
            # device writes stay consistent with any concurrent render()/clear().
            with self._lock:
                self._frame += 1
                for index in list(self._animated):
                    self._animate_key(index, self._scene.get(index, {"kind": "blank"}),
                                      self._frame)

    def _animate_key(self, index, spec, frame):
        overflows, text_w = render.title_overflow(spec, self._size)
        scroll_x = 0
        marquee = overflows
        if overflows:
            st = self._anim.setdefault(index, {"scroll": 0, "hold": 0})
            period = text_w + render.SCROLL_GAP
            if st["hold"] < SCROLL_HOLD_FRAMES:
                st["hold"] += 1
            else:
                st["scroll"] += SCROLL_STRIDE
                if st["scroll"] >= period:
                    st["scroll"] = 0
                    st["hold"] = 0
            scroll_x = st["scroll"]

        pulse = 1.0
        if spec.get("status") == "waiting":
            phase = 2 * math.pi * (frame % PULSE_PERIOD_FRAMES) / PULSE_PERIOD_FRAMES
            pulse = 0.5 + 0.5 * (0.5 + 0.5 * math.sin(phase))

        self._push_key(index, spec, scroll_x=scroll_x, marquee=marquee, pulse=pulse)

    def clear(self):
        with self._lock:
            self._scene = {}
            self._scene_keys = None
            self._anim = {}
            self._animated = set()
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
        self._stop.set()
        # Wait for any in-flight paint to finish before resetting the device,
        # so the frame thread never writes to a closed deck.
        if self._thread is not None and self._thread is not threading.current_thread():
            self._thread.join(timeout=FRAME_INTERVAL * 2)
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
            {"index": 1, "kind": "agent", "repo": "claude-deck-mini-long-name",
             "branch": "main", "status": "working", "age": "just now"},
            {"index": 2, "kind": "agent", "label": "notes",
             "status": "idle", "age": "41h ago"},
            {"index": 3, "kind": "blank"},
            {"index": 4, "kind": "blank"},
            {"index": 5, "kind": "more", "remaining": 3},
        ],
    }
    d.handle(demo)
    d.start_frames()
    time.sleep(6)  # let the marquee scroll and the waiting band pulse
    d.close()


def main():
    d = Deckd(first_deck())
    d.open()
    if "--selftest" in sys.argv:
        selftest(d)
        return
    d.start_frames()
    try:
        d.run_stdin_loop()
    except KeyboardInterrupt:
        d.close()


if __name__ == "__main__":
    main()
