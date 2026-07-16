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


if __name__ == "__main__":
    test_all_kinds_paint_a_correct_sized_image()
    test_status_band_color_matches_status()
    test_long_repo_is_truncated_not_crashing()
    print("render tests passed")
