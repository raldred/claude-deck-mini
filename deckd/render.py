"""Paints Stream Deck key images with Pillow.

The Swift app owns *what* to show; this module owns *how it's painted*. Each key
is a small square image: a colored status band at the top, then the session's
repo/branch (or a single label), then a relative-time "age" line.
"""

from __future__ import annotations

from PIL import Image, ImageDraw, ImageFont

# Status → accent color + which states are "needs you" (pulse-eligible).
STATUS_COLORS = {
    "permission": (220, 60, 60),    # red — blocked on a yes/no
    "turn_done": (235, 150, 40),    # amber — finished its turn
    "idle": (205, 180, 70),         # gold — idle nudge
    "thinking": (60, 180, 90),      # green — working
    "compacting": (70, 130, 220),   # blue — compacting context
    "ended": (70, 70, 70),          # grey tombstone
}
NEEDS_YOU = {"permission", "turn_done", "idle"}
GLYPH_STATUSES = {"permission", "turn_done", "idle", "compacting"}
GLYPH_GUTTER = 16   # right-side space reserved on the title line for the glyph
BG = (24, 24, 27)
FG = (235, 235, 235)
DIM = (120, 120, 130)
# Claude's accent purple — reserved for the "background agents running" badge.
PURPLE = (155, 125, 245)

PAD = 6
TITLE_SIZE = 14
SUB_SIZE = 11
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
    max_w = size[0] - 2 * PAD - GLYPH_GUTTER
    tw = _text_width(text, _font(TITLE_SIZE))
    return (tw > max_w, tw)


def branch_of(spec: dict):
    """The subtitle line: branch when there's a repo, else nothing (the single
    `label` case has no second line). Returns None when there's no subtitle."""
    if spec.get("kind") != "agent":
        return None
    branch = spec.get("branch")
    if spec.get("repo") is not None and branch:
        return str(branch)
    return None


def branch_overflow(spec: dict, size=(80, 80)):
    """(overflows, text_width_px) for an agent's branch line; (False, 0) otherwise."""
    text = branch_of(spec)
    if text is None:
        return (False, 0)
    max_w = size[0] - 2 * PAD
    tw = _text_width(text, _font(SUB_SIZE))
    return (tw > max_w, tw)


def _draw_marquee(base_img, text, font, x0, y, max_width, scroll_x, fill=FG):
    """Paste a horizontally-scrolling, wrap-around copy of `text` into a line band."""
    tw = _text_width(text, font)
    period = tw + SCROLL_GAP
    off = scroll_x % period if period else 0
    strip = Image.new("RGB", (max_width, LINE_H), BG)
    d = ImageDraw.Draw(strip)
    x = -off
    while x < max_width:
        d.text((x, 0), text, font=font, fill=fill)
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


def paint_key(spec: dict, size=(80, 80), scroll_x=0, marquee=False, pulse=1.0,
              branch_scroll_x=0, branch_marquee=False) -> Image.Image:
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
    if pulse < 1.0:
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
    title_w = w - 2 * pad - GLYPH_GUTTER
    if marquee:
        _draw_marquee(img, title, title_font, pad, y, title_w, scroll_x)
    else:
        draw.text((pad, y), _truncate(draw, title, title_font, title_w),
                  font=title_font, fill=FG)
    y += 18
    if repo is not None and branch:
        if branch_marquee:
            _draw_marquee(img, str(branch), sub_font, pad, y, w - 2 * pad,
                          branch_scroll_x, fill=DIM)
        else:
            draw.text((pad, y), _truncate(draw, str(branch), sub_font, w - 2 * pad),
                      font=sub_font, fill=DIM)
        y += 15

    age = spec.get("age")
    if age:
        draw.text((pad, h - 16), _truncate(draw, str(age), age_font, w - 2 * pad),
                  font=age_font, fill=DIM)

    subagents = int(spec.get("subagents", 0) or 0)
    if subagents > 0:
        _draw_subagent_badge(draw, subagents, w, h)

    if kind == "agent" and spec.get("status") in GLYPH_STATUSES:
        _draw_status_glyph(draw, spec.get("status"), w, h)

    return img


def _draw_subagent_badge(draw, count, w, h):
    """A small purple pill in the bottom-right showing running background agents."""
    label = str(count)
    font = _font(11)
    tw = draw.textlength(label, font=font)
    bw = int(tw) + 12
    bh = 15
    x1, y1 = w - PAD, h - PAD
    x0, y0 = x1 - bw, y1 - bh
    draw.rounded_rectangle([x0, y0, x1, y1], radius=bh // 2, fill=PURPLE)
    draw.text((x0 + (bw - tw) / 2, y0 + 1), label, font=font, fill=(255, 255, 255))


def _draw_status_glyph(draw, status, w, h):
    """A small white glyph, top-right, distinguishing states that share a band
    colour family. Drawn with primitives — no emoji font needed."""
    white = (255, 255, 255)
    x1, y0 = w - 5, 7
    x0 = x1 - 14
    if status == "permission":                      # padlock
        draw.arc([x0 + 3, y0, x1 - 3, y0 + 11], start=180, end=360, fill=white, width=2)
        draw.rectangle([x0 + 1, y0 + 6, x1 - 1, y0 + 14], fill=white)
    elif status == "turn_done":                     # checkmark
        draw.line([(x0 + 1, y0 + 7), (x0 + 5, y0 + 12), (x1, y0 + 1)], fill=white, width=2)
    elif status == "idle":                          # three dots
        for i in range(3):
            cx = x0 + 2 + i * 5
            draw.ellipse([cx, y0 + 9, cx + 2, y0 + 11], fill=white)
    elif status == "compacting":                    # double down-chevron
        for dy in (0, 4):
            draw.line([(x0 + 1, y0 + dy + 2), (x0 + 7, y0 + dy + 7), (x1 - 1, y0 + dy + 2)],
                      fill=white, width=2)
