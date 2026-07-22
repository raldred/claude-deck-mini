"""Headless tests for render.paint_key — no Stream Deck needed.

Run: python3 deckd/test_render.py
"""

import sys

from PIL import Image

import render


def _check(cond, msg):
    if not cond:
        print(f"FAIL: {msg}")
        sys.exit(1)


def test_all_kinds_paint_a_correct_sized_image():
    specs = [
        {"kind": "agent", "repo": "residently", "branch": "feature/foo",
         "status": "waiting", "age": "2m ago"},
        {"kind": "agent", "label": "notes", "status": "idle", "age": "41h ago"},
        {"kind": "more", "remaining": 3},
        {"kind": "blank"},
        {},  # missing kind → blank
    ]
    for spec in specs:
        img = render.paint_key(spec, size=(80, 80))
        _check(isinstance(img, Image.Image), f"not an image for {spec}")
        _check(img.size == (80, 80), f"wrong size for {spec}")


def test_status_band_color_matches_status():
    img = render.paint_key(
        {"kind": "agent", "repo": "r", "branch": "b", "status": "waiting", "age": "1m"},
        size=(80, 80))
    # Top-left pixel is inside the status band → should be the waiting red.
    _check(img.getpixel((2, 1)) == render.STATUS_COLORS["waiting"],
           "status band color mismatch")


def test_long_repo_is_truncated_not_crashing():
    img = render.paint_key(
        {"kind": "agent", "repo": "a" * 200, "branch": "b" * 200,
         "status": "working", "age": "just now"}, size=(80, 80))
    _check(img.size == (80, 80), "truncation changed image size")


def test_banner_cells_are_correct_size_and_differ_by_index():
    cell0 = render.paint_banner_cell("No active sessions", 0, size=(80, 80))
    cell5 = render.paint_banner_cell("No active sessions", 5, size=(80, 80))
    _check(cell0.size == (80, 80), "banner cell 0 wrong size")
    _check(cell5.size == (80, 80), "banner cell 5 wrong size")
    _check(cell0.tobytes() != cell5.tobytes(),
           "banner cells 0 and 5 should not be identical")


def test_banner_kind_routes_through_paint_key():
    img = render.paint_key(
        {"kind": "banner", "index": 2, "text": "No active sessions"}, size=(80, 80))
    _check(img.size == (80, 80), "banner paint_key wrong size")


def test_title_overflow_true_for_long_false_for_short():
    long_over, long_w = render.title_overflow(
        {"kind": "agent", "repo": "a" * 40, "status": "working", "age": "1m"}, size=(80, 80))
    short_over, short_w = render.title_overflow(
        {"kind": "agent", "repo": "ab", "status": "working", "age": "1m"}, size=(80, 80))
    _check(long_over is True, "long title should overflow")
    _check(short_over is False, "short title should not overflow")
    _check(long_w > short_w, "long title width should exceed short")


def test_non_agent_never_overflows():
    over, width = render.title_overflow({"kind": "blank"}, size=(80, 80))
    _check(over is False and width == 0, "blank should not overflow")


def test_marquee_paints_correct_size():
    img = render.paint_key(
        {"kind": "agent", "repo": "residently/feature-x", "status": "working", "age": "1m"},
        size=(80, 80), marquee=True, scroll_x=12)
    _check(img.size == (80, 80), "marquee changed image size")


def test_pulse_dims_the_waiting_band():
    spec = {"kind": "agent", "repo": "r", "branch": "b", "status": "waiting", "age": "1m"}
    full = render.paint_key(spec, size=(80, 80), pulse=1.0).getpixel((2, 1))
    dim = render.paint_key(spec, size=(80, 80), pulse=0.5).getpixel((2, 1))
    _check(sum(dim) < sum(full), "pulse=0.5 band should be dimmer than pulse=1.0")


if __name__ == "__main__":
    test_all_kinds_paint_a_correct_sized_image()
    test_status_band_color_matches_status()
    test_long_repo_is_truncated_not_crashing()
    test_banner_cells_are_correct_size_and_differ_by_index()
    test_banner_kind_routes_through_paint_key()
    test_title_overflow_true_for_long_false_for_short()
    test_non_agent_never_overflows()
    test_marquee_paints_correct_size()
    test_pulse_dims_the_waiting_band()
    print("render tests passed")
