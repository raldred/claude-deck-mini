"""Paints Stream Deck key images with Pillow.

The Swift app owns *what* to show; this module owns *how it's painted*. Each key
is a small square image: a colored status band at the top, then the session's
repo/branch (or a single label), then a relative-time "age" line.
"""

from __future__ import annotations

from PIL import Image, ImageDraw, ImageFont

# Status → accent color. Red = needs you, green = working, grey = idle.
STATUS_COLORS = {
    "waiting": (220, 60, 60),
    "working": (60, 180, 90),
    "idle": (120, 120, 120),
    "finished": (70, 70, 70),
}
BG = (24, 24, 27)
FG = (235, 235, 235)
DIM = (120, 120, 130)


def _font(size: int) -> ImageFont.FreeTypeFont:
    for path in (
        "/System/Library/Fonts/SFNSRounded.ttf",
        "/System/Library/Fonts/Helvetica.ttc",
        "/Library/Fonts/Arial.ttf",
    ):
        try:
            return ImageFont.truetype(path, size)
        except OSError:
            continue
    return ImageFont.load_default()


def _truncate(draw, text, font, max_width):
    if draw.textlength(text, font=font) <= max_width:
        return text
    while text and draw.textlength(text + "…", font=font) > max_width:
        text = text[:-1]
    return text + "…" if text else ""


def _blank(size):
    return Image.new("RGB", size, BG)


def paint_key(spec: dict, size=(80, 80)) -> Image.Image:
    """Render one key from its JSON spec.

    Recognised specs:
      {"kind":"agent","repo":..,"branch":..,"status":..,"age":..}
      {"kind":"agent","label":..,"status":..,"age":..}
      {"kind":"more","remaining":n}
      {"kind":"blank"}  (or missing)
    """
    kind = spec.get("kind", "blank")
    img = _blank(size)
    draw = ImageDraw.Draw(img)
    w, h = size
    pad = 6

    if kind == "blank":
        return img

    if kind == "more":
        f = _font(15)
        n = spec.get("remaining", 0)
        text = f"▶ {n} more"
        tw = draw.textlength(text, font=f)
        draw.text(((w - tw) / 2, h / 2 - 10), text, font=f, fill=FG)
        return img

    # agent
    color = STATUS_COLORS.get(spec.get("status", "idle"), DIM)
    draw.rectangle([0, 0, w, 5], fill=color)

    title_font = _font(14)
    sub_font = _font(11)
    age_font = _font(10)

    repo = spec.get("repo")
    branch = spec.get("branch")
    label = spec.get("label")

    y = pad + 4
    if repo is not None:
        draw.text((pad, y), _truncate(draw, str(repo), title_font, w - 2 * pad),
                  font=title_font, fill=FG)
        y += 18
        if branch:
            draw.text((pad, y), _truncate(draw, str(branch), sub_font, w - 2 * pad),
                      font=sub_font, fill=DIM)
            y += 15
    else:
        draw.text((pad, y), _truncate(draw, str(label or "?"), title_font, w - 2 * pad),
                  font=title_font, fill=FG)
        y += 18

    age = spec.get("age")
    if age:
        draw.text((pad, h - 16), _truncate(draw, str(age), age_font, w - 2 * pad),
                  font=age_font, fill=DIM)

    return img
