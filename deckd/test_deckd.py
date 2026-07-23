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
        self.reset_count = 0
        self.closed = False

    def open(self): pass
    def reset(self):
        self.images = {}
        self.reset_count += 1
    def close(self): self.closed = True
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
    before = d._anim.get(0, {}).get("title", {}).get("scroll", 0)
    _check(before > 0, "title scroll should have advanced")
    # Re-render the identical scene — must NOT reset offsets.
    d.handle(_long_scene())
    after = d._anim.get(0, {}).get("title", {}).get("scroll", 0)
    _check(after == before, f"identical re-render reset anim: {before} -> {after}")


def test_long_branch_animates_and_scrolls_independently():
    d = _new_deckd()
    # Short repo (title fits) but long branch (should still animate + scroll).
    d.handle({"cmd": "render", "keys": [
        {"index": 0, "kind": "agent", "repo": "x",
         "branch": "feature/" + "y" * 40, "status": "working", "age": "1m"}]})
    _check(0 in d._animated, "key with long branch should be animated")
    for _ in range(6):
        with d._lock:
            d._animate_key(0, d._scene.get(0), d._frame)
            d._frame += 1
    branch_scroll = d._anim.get(0, {}).get("branch", {}).get("scroll", 0)
    _check(branch_scroll > 0, "branch scroll should advance even when title fits")


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


def test_shutdown_resets_and_closes_device():
    d = _new_deckd()
    d.handle(_long_scene())
    try:
        deckd._shutdown(d)
    except SystemExit:
        pass  # the handler exits the process; that's expected
    _check(d.deck.reset_count >= 1, "shutdown should reset the device")
    _check(d.deck.closed, "shutdown should close the device")


if __name__ == "__main__":
    test_render_marks_overflow_and_waiting_keys_animated()
    test_identical_rerender_preserves_animation_state()
    test_long_branch_animates_and_scrolls_independently()
    test_changed_scene_resets_animation_state()
    test_empty_render_shows_no_animated_keys()
    test_shutdown_resets_and_closes_device()
    print("deckd tests passed")
