"""Headless tests for deckd scene handling — a fake deck, no hardware.

Run: python3 deckd/test_deckd.py
"""

import sys

import deckd


class FakeDeck:
    """Minimal stand-in for a StreamDeck: records writes, no USB."""

    def __init__(self, keys=6, size=(80, 80)):
        self._keys = keys
        self._size = size
        self.images = {}
        self.brightness = None

    def open(self): pass
    def reset(self): self.images = {}
    def close(self): pass
    def set_brightness(self, v): self.brightness = v
    def set_key_callback(self, cb): pass
    def key_count(self): return self._keys
    def key_image_format(self):
        return {"size": self._size, "rotation": 0, "flip": (False, False),
                "format": "JPEG"}
    def get_serial_number(self): return "FAKE"
    def set_key_image(self, index, image): self.images[index] = image


def _check(cond, msg):
    if not cond:
        print(f"FAIL: {msg}")
        sys.exit(1)


def _new_deckd():
    d = deckd.Deckd(FakeDeck())
    d.open()
    return d


def _long_scene():
    # One overflowing title + one waiting key → both animate.
    return {
        "cmd": "render",
        "keys": [
            {"index": 0, "kind": "agent", "repo": "a-really-long-repo-name",
             "status": "working", "age": "1m"},
            {"index": 1, "kind": "agent", "repo": "x", "status": "waiting", "age": "2m"},
        ],
    }


def test_render_marks_overflow_and_waiting_keys_animated():
    d = _new_deckd()
    d.handle(_long_scene())
    _check(d._animated == {0, 1}, f"expected keys 0,1 animated, got {d._animated}")


def test_identical_rerender_preserves_animation_state():
    d = _new_deckd()
    d.handle(_long_scene())
    # Advance the marquee a few frames, mutating _anim for key 0.
    for _ in range(6):
        with d._lock:
            for i in list(d._animated):
                d._animate_key(i, d._scene.get(i), d._frame)
                d._frame += 1
    before = dict(d._anim.get(0, {}))
    _check(before.get("scroll", 0) > 0, "scroll should have advanced")
    # Re-render the identical scene — must NOT reset offsets.
    d.handle(_long_scene())
    after = d._anim.get(0, {})
    _check(after == before, f"identical re-render reset anim: {before} -> {after}")


def test_changed_scene_resets_animation_state():
    d = _new_deckd()
    d.handle(_long_scene())
    with d._lock:
        d._animate_key(0, d._scene.get(0), 1)  # seed some scroll on key 0
    _check(d._anim, "expected anim state before change")
    # A genuinely different scene resets _anim and recomputes _animated.
    d.handle({"cmd": "render", "keys": [
        {"index": 0, "kind": "agent", "repo": "y", "status": "idle", "age": "3m"}]})
    _check(d._anim == {}, f"changed scene should clear _anim, got {d._anim}")
    _check(d._animated == set(), f"short idle scene animates nothing, got {d._animated}")


def test_empty_render_shows_no_animated_keys():
    d = _new_deckd()
    d.handle({"cmd": "render", "keys": []})
    _check(d._animated == set(), "empty scene animates nothing")
    _check(len(d._scene) == d.deck.key_count(), "scene should cover every key")


if __name__ == "__main__":
    test_render_marks_overflow_and_waiting_keys_animated()
    test_identical_rerender_preserves_animation_state()
    test_changed_scene_resets_animation_state()
    test_empty_render_shows_no_animated_keys()
    print("deckd tests passed")
