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

PAD = 6
TITLE_SIZE = 14
BANNER_SIZE = 26
SCROLL_GAP = 16
LINE_H = 18


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


def title_of(spec: dict):
    """The title line text for an agent spec (repo, else label), or None."""
    if spec.get("kind") != "agent":
        return None
    repo = spec.get("repo")
    if repo is not None:
        return str(repo)
    label = spec.get("label")
    return str(label) if label is not None else "?"


def _text_width(text: str, font) -> int:
    draw = ImageDraw.Draw(Image.new("RGB", (1, 1)))
    return int(draw.textlength(text, font=font))


def title_overflow(spec: dict, size=(80, 80)):
    """(overflows, text_width_px) for an agent's title line; (False, 0) otherwise."""
    text = title_of(spec)
    if text is None:
        return (False, 0)
    max_w = size[0] - 2 * PAD
    tw = _text_width(text, _font(TITLE_SIZE))
    return (tw > max_w, tw)


def _draw_title_marquee(base_img, text, font, x0, y, max_width, scroll_x):
    """Paste a horizontally-scrolling, wrap-around copy of `text` into the title band."""
    tw = _text_width(text, font)
    period = tw + SCROLL_GAP
    off = scroll_x % period if period else 0
    strip = Image.new("RGB", (max_width, LINE_H), BG)
    d = ImageDraw.Draw(strip)
    x = -off
    while x < max_width:
        d.text((x, 0), text, font=font, fill=FG)
        x += period
    base_img.paste(strip, (x0, y))


def _blank(size):
    return Image.new("RGB", size, BG)


def paint_banner_cell(text: str, index: int, size=(80, 80), cols=3, rows=2) -> Image.Image:
    """Render one wide banner across cols x rows keys and return the cell for `index`."""
    w, h = size
    full = Image.new("RGB", (w * cols, h * rows), BG)
    draw = ImageDraw.Draw(full)
    font = _font(BANNER_SIZE)
    bbox = draw.textbbox((0, 0), text, font=font)
    tw = bbox[2] - bbox[0]
    th = bbox[3] - bbox[1]
    draw.text(((w * cols - tw) / 2 - bbox[0], (h * rows - th) / 2 - bbox[1]),
              text, font=font, fill=FG)
    col = index % cols
    row = index // cols
    return full.crop((col * w, row * h, col * w + w, row * h + h))


def paint_key(spec: dict, size=(80, 80), scroll_x=0, marquee=False, pulse=1.0) -> Image.Image:
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
    pad = PAD

    if kind == "blank":
        return img

    if kind == "banner":
        return paint_banner_cell(spec.get("text", ""), int(spec.get("index", 0)), size)

    if kind == "more":
        f = _font(15)
        n = spec.get("remaining", 0)
        text = f"▶ {n} more"
        tw = draw.textlength(text, font=f)
        draw.text(((w - tw) / 2, h / 2 - 10), text, font=f, fill=FG)
        return img

    # agent
    color = STATUS_COLORS.get(spec.get("status", "idle"), DIM)
    if pulse != 1.0:
        color = tuple(int(c * pulse) for c in color)
    draw.rectangle([0, 0, w, 5], fill=color)

    title_font = _font(14)
    sub_font = _font(11)
    age_font = _font(10)

    repo = spec.get("repo")
    branch = spec.get("branch")
    label = spec.get("label")

    y = pad + 4
    title = str(repo) if repo is not None else str(label or "?")
    if marquee:
        _draw_title_marquee(img, title, title_font, pad, y, w - 2 * pad, scroll_x)
    else:
        draw.text((pad, y), _truncate(draw, title, title_font, w - 2 * pad),
                  font=title_font, fill=FG)
    y += 18
    if repo is not None and branch:
        draw.text((pad, y), _truncate(draw, str(branch), sub_font, w - 2 * pad),
                  font=sub_font, fill=DIM)
        y += 15

    age = spec.get("age")
    if age:
        draw.text((pad, h - 16), _truncate(draw, str(age), age_font, w - 2 * pad),
                  font=age_font, fill=DIM)

    return img
