#!/usr/bin/env python3
"""Design-only drafts for the in-game PC controls overlay.

Outputs live beside this script in design_drafts/ui/. Nothing here touches the
Godot project; it only renders review boards with PIL.

Concept A - Field Guide: a temporary left-side reference sheet that dims the
world while open.
Concept B - Quick Bar: a compact always-on strip for the essentials, with F1
opening the full guide.
"""

from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont

OUT = Path(__file__).resolve().parent
K = 2  # supersample factor; everything is drawn at 2x then downsampled.

FONT_DIR = Path("C:/Windows/Fonts")
FONT_FILES = {
    "body": "segoeui.ttf",
    "bold": "segoeuib.ttf",
    "mono": "consola.ttf",
    "monob": "consolab.ttf",
}

# ── Palette (matches the approved mobile HUD draft) ─────────────────────
C_BG_TOP = (8, 15, 25, 255)
C_BG_BOT = (4, 8, 14, 255)
C_GRID = (72, 108, 152, 12)
C_PANEL = (10, 17, 29, 240)
C_PANEL_SOFT = (14, 23, 38, 238)
C_PANEL_LIGHT = (19, 30, 49, 245)
C_BORDER = (54, 76, 112, 255)
C_BORDER_HI = (82, 118, 172, 255)
C_TEXT = (216, 230, 247, 255)
C_TEXT_SOFT = (172, 192, 218, 255)
C_MUTED = (126, 146, 173, 255)
C_DIM = (92, 109, 134, 255)
C_BLUE = (92, 178, 255, 255)
C_BLUE_SOFT = (146, 207, 255, 255)
C_AMBER = (242, 187, 82, 255)
C_AMBER_SOFT = (255, 214, 133, 255)
C_GREEN = (86, 216, 178, 255)
C_RED = (232, 104, 98, 255)
C_KEY_BG = (25, 38, 60, 255)
C_KEY_BORDER = (78, 106, 148, 255)
C_KEY_TEXT = (225, 238, 252, 255)

_font_cache: dict[tuple[str, int], ImageFont.FreeTypeFont] = {}


def F(kind: str, size: float, u: float = 1.0) -> ImageFont.FreeTypeFont:
    px = max(7, int(round(size * u * K)))
    key = (kind, px)
    if key not in _font_cache:
        _font_cache[key] = ImageFont.truetype(str(FONT_DIR / FONT_FILES[kind]), px)
    return _font_cache[key]


def sc(v: float) -> int:
    return int(round(v * K))


def box(b) -> list[int]:
    return [sc(b[0]), sc(b[1]), sc(b[2]), sc(b[3])]


def rr(d: ImageDraw.ImageDraw, b, radius: float, fill=None, outline=None,
       width: float = 1.0) -> None:
    d.rounded_rectangle(box(b), radius=max(0, sc(radius)), fill=fill,
                        outline=outline, width=max(1, sc(width)))


def txt(d: ImageDraw.ImageDraw, xy, s: str, font, fill, anchor="la",
        **kwargs) -> None:
    d.text((sc(xy[0]), sc(xy[1])), s, font=font, fill=fill, anchor=anchor,
           **kwargs)


def tw(d: ImageDraw.ImageDraw, s: str, font) -> float:
    return d.textlength(s, font=font) / K


def vgrad(w: float, h: float, top, bottom) -> Image.Image:
    ww, hh = sc(w), sc(h)
    im = Image.new("RGBA", (ww, hh))
    d = ImageDraw.Draw(im)
    for y in range(hh):
        t = y / max(1, hh - 1)
        col = tuple(int(top[i] + (bottom[i] - top[i]) * t) for i in range(4))
        d.line([(0, y), (ww, y)], fill=col)
    return im


def grid_layer(w: float, h: float, step: float = 40.0, alpha: int = 12,
               color=(78, 118, 168)) -> Image.Image:
    layer = Image.new("RGBA", (sc(w), sc(h)), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    x = 0.0
    while x <= w:
        d.line([(sc(x), 0), (sc(x), sc(h))], fill=color + (alpha,), width=K)
        x += step
    y = 0.0
    while y <= h:
        d.line([(0, sc(y)), (sc(w), sc(y))], fill=color + (alpha,), width=K)
        y += step
    return layer


def panel(w: float, h: float, radius: float = 8.0, fill=C_PANEL,
          border=C_BORDER, accent=None) -> Image.Image:
    im = Image.new("RGBA", (sc(w), sc(h)), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    rr(d, (0.5, 0.5, w - 0.5, h - 0.5), radius, fill=fill, outline=border,
       width=1.0)
    if accent is not None:
        # Thin state accent along the top edge.
        rr(d, (7, 1.0, w - 7, 4.0), 1.5, fill=accent)
    return im


def paste_shadow(dst: Image.Image, src: Image.Image, x: float, y: float,
                 blur: float = 7.0, opacity: float = 0.62) -> None:
    alpha = src.getchannel("A").point(lambda a: int(a * opacity))
    shadow = Image.new("RGBA", src.size, (0, 0, 0, 255))
    shadow.putalpha(alpha)
    shadow = shadow.filter(ImageFilter.GaussianBlur(sc(blur)))
    dst.alpha_composite(shadow, (sc(x + 3.0), sc(y + 5.0)))
    dst.alpha_composite(src, (sc(x), sc(y)))


# ── Small icon primitives ───────────────────────────────────────────────
def star_points(cx: float, cy: float, r: float) -> list[tuple[float, float]]:
    pts = []
    import math
    for i in range(10):
        ang = -math.pi * 0.5 + i * math.pi / 5.0
        rad = r if i % 2 == 0 else r * 0.43
        pts.append((cx + math.cos(ang) * rad, cy + math.sin(ang) * rad))
    return pts


def draw_star(d: ImageDraw.ImageDraw, cx: float, cy: float, r: float, color) -> None:
    d.polygon([(sc(px), sc(py)) for px, py in star_points(cx, cy, r)], fill=color)


def state_badge(d: ImageDraw.ImageDraw, x: float, y: float, on: bool,
                u: float = 1.0, right: float | None = None) -> tuple[float, float]:
    label = "POINT & CLICK ON" if on else "POINT & CLICK OFF"
    f = F("monob", 8.2, u)
    w = tw(d, label, f) + 16.0 * u
    h = 19.0 * u
    if right is not None:
        x = right - w
    if on:
        rr(d, (x, y, x + w, y + h), h * 0.5, fill=C_AMBER, outline=C_AMBER_SOFT,
           width=1.0)
        txt(d, (x + w * 0.5, y + h * 0.5 + 0.5 * u), label, f,
            (32, 22, 5, 255), anchor="mm")
    else:
        rr(d, (x, y, x + w, y + h), h * 0.5, fill=(21, 35, 56, 255),
           outline=(63, 92, 133, 255), width=1.0)
        txt(d, (x + w * 0.5, y + h * 0.5 + 0.5 * u), label, f,
            C_BLUE_SOFT, anchor="mm")
    return w, h


def keycap_width(d: ImageDraw.ImageDraw, label: str, u: float, h: float) -> float:
    f = F("monob", 9.0, u)
    return max(h, tw(d, label, f) + 12.0 * u)


def draw_keycap(d: ImageDraw.ImageDraw, x: float, y: float, label: str,
                u: float, h: float = 20.0, accent: bool = False) -> float:
    w = keycap_width(d, label, u, h)
    fill = (44, 34, 17, 255) if accent else C_KEY_BG
    border = C_AMBER if accent else C_KEY_BORDER
    text_col = C_AMBER_SOFT if accent else C_KEY_TEXT
    rr(d, (x, y, x + w, y + h), 4.0 * u, fill=fill, outline=border, width=1.0)
    # A 1px lower lip sells the keycap without a second sprite.
    d.line([(sc(x + 3.0 * u), sc(y + h - 2.0 * u)),
            (sc(x + w - 3.0 * u), sc(y + h - 2.0 * u))],
           fill=(8, 13, 22, 110), width=K)
    txt(d, (x + w * 0.5, y + h * 0.5 + 0.2 * u), label, F("monob", 9.0, u),
        text_col, anchor="mm")
    return w


def key_sequence_width(d: ImageDraw.ImageDraw, tokens: list[str], u: float,
                       h: float = 20.0) -> float:
    total = 0.0
    for i, tok in enumerate(tokens):
        if tok in ("+", "/"):
            total += 10.0 * u if i else 0.0
        else:
            total += keycap_width(d, tok, u, h)
            total += 3.5 * u
    return max(0.0, total - 3.5 * u)


def draw_key_sequence(d: ImageDraw.ImageDraw, x: float, y: float,
                      tokens: list[str], u: float, h: float = 20.0,
                      accent: bool = False) -> float:
    cx = x
    for tok in tokens:
        if tok in ("+", "/"):
            txt(d, (cx + 1.5 * u, y + h * 0.5), tok, F("body", 9.0, u),
                C_MUTED, anchor="lm")
            cx += 10.0 * u
        else:
            cx += draw_keycap(d, cx, y, tok, u, h, accent)
            cx += 3.5 * u
    return cx - x - 3.5 * u


# ── World mockup ────────────────────────────────────────────────────────
def draw_tree(d: ImageDraw.ImageDraw, x: float, y: float, s: float = 1.0) -> None:
    # Ground shadow.
    d.ellipse([sc(x - 20 * s), sc(y + 22 * s), sc(x + 20 * s), sc(y + 31 * s)],
              fill=(2, 6, 7, 90))
    # Trunk.
    rr(d, (x - 4 * s, y + 2 * s, x + 4 * s, y + 30 * s), 2 * s,
       fill=(45, 35, 27, 255))
    # Three overlapping canopy lobes.
    blobs = [
        (x - 15 * s, y - 1 * s, 16 * s, (24, 63, 57, 255)),
        (x + 14 * s, y - 2 * s, 15 * s, (28, 72, 63, 255)),
        (x, y - 17 * s, 20 * s, (27, 69, 60, 255)),
        (x - 3 * s, y - 8 * s, 18 * s, (34, 83, 70, 255)),
    ]
    for bx, by, br, col in blobs:
        d.ellipse([sc(bx - br), sc(by - br), sc(bx + br), sc(by + br)], fill=col)
    # Small top-left rim light.
    d.arc([sc(x - 18 * s), sc(y - 34 * s), sc(x + 14 * s), sc(y - 2 * s)],
          195, 265, fill=(64, 122, 102, 160), width=sc(1.2 * s))


def draw_bush(d: ImageDraw.ImageDraw, x: float, y: float, s: float = 1.0) -> None:
    for bx, by, br, col in [
        (x - 9 * s, y, 10 * s, (24, 58, 49, 255)),
        (x + 8 * s, y + 1 * s, 9 * s, (29, 67, 55, 255)),
        (x, y - 6 * s, 11 * s, (31, 73, 59, 255)),
    ]:
        d.ellipse([sc(bx - br), sc(by - br), sc(bx + br), sc(by + br)], fill=col)


def draw_rock(d: ImageDraw.ImageDraw, x: float, y: float, s: float = 1.0) -> None:
    d.ellipse([sc(x - 18 * s), sc(y + 8 * s), sc(x + 18 * s), sc(y + 15 * s)],
              fill=(2, 6, 7, 90))
    pts = [(x - 17 * s, y + 9 * s), (x - 11 * s, y - 8 * s),
           (x + 2 * s, y - 13 * s), (x + 15 * s, y - 3 * s),
           (x + 17 * s, y + 9 * s)]
    d.polygon([(sc(px), sc(py)) for px, py in pts], fill=(35, 47, 60, 255))
    d.line([(sc(x - 9 * s), sc(y - 4 * s)), (sc(x + 3 * s), sc(y - 9 * s))],
           fill=(66, 84, 102, 255), width=K)


def draw_grass_tuft(d: ImageDraw.ImageDraw, x: float, y: float, s: float = 1.0) -> None:
    for dx, hgt in [(-3, 7), (0, 10), (3, 6)]:
        d.line([(sc(x + dx * s), sc(y)), (sc(x + dx * 1.5 * s), sc(y - hgt * s))],
               fill=(43, 93, 80, 230), width=max(1, sc(1.0 * s)))


def draw_player(d: ImageDraw.ImageDraw, x: float, y: float) -> None:
    # Shadow.
    d.ellipse([sc(x - 19), sc(y + 23), sc(x + 19), sc(y + 31)],
              fill=(0, 0, 0, 115))
    # Backpack.
    rr(d, (x - 17, y - 17, x - 5, y + 12), 4, fill=(62, 82, 106, 255),
       outline=(96, 121, 148, 255), width=1.0)
    # Legs.
    rr(d, (x - 6, y + 10, x - 1, y + 26), 2.5, fill=(166, 187, 210, 255))
    rr(d, (x + 3, y + 10, x + 8, y + 26), 2.5, fill=(146, 169, 195, 255))
    # Body.
    rr(d, (x - 9, y - 17, x + 10, y + 13), 6, fill=(210, 224, 239, 255),
       outline=(240, 248, 255, 255), width=1.0)
    # Chest light.
    d.ellipse([sc(x - 3), sc(y - 7), sc(x + 4), sc(y)], fill=(86, 216, 178, 255))
    # Arm.
    rr(d, (x + 7, y - 10, x + 13, y + 8), 3, fill=(186, 204, 224, 255))
    # Helmet.
    d.ellipse([sc(x - 8), sc(y - 35), sc(x + 14), sc(y - 13)],
              fill=(232, 242, 252, 255), outline=(255, 255, 255, 255), width=K)
    # Visor.
    rr(d, (x + 0, y - 31, x + 12, y - 21), 3, fill=(38, 70, 101, 255),
       outline=(112, 168, 210, 255), width=1.0)
    d.line([(sc(x + 2), sc(y - 28)), (sc(x + 7), sc(y - 28))],
           fill=(127, 198, 242, 255), width=K)


def draw_cursor_arrow(d: ImageDraw.ImageDraw, x: float, y: float, color) -> None:
    pts = [(x, y), (x + 2, y + 22), (x + 8, y + 16), (x + 13, y + 24),
           (x + 17, y + 22), (x + 12, y + 14), (x + 20, y + 13)]
    d.polygon([(sc(px), sc(py)) for px, py in pts], fill=color,
              outline=(5, 8, 12, 255))
    d.polygon([(sc(px), sc(py)) for px, py in pts], outline=(5, 8, 12, 255),
              width=K)


def draw_crosshair(d: ImageDraw.ImageDraw, x: float, y: float, color) -> None:
    d.ellipse([sc(x - 9), sc(y - 9), sc(x + 9), sc(y + 9)],
              outline=color, width=sc(1.4))
    d.line([(sc(x - 15), sc(y)), (sc(x - 5), sc(y))], fill=color, width=sc(1.2))
    d.line([(sc(x + 5), sc(y)), (sc(x + 15), sc(y))], fill=color, width=sc(1.2))
    d.line([(sc(x), sc(y - 15)), (sc(x), sc(y - 5))], fill=color, width=sc(1.2))
    d.line([(sc(x), sc(y + 5)), (sc(x), sc(y + 15))], fill=color, width=sc(1.2))
    d.ellipse([sc(x - 1.5), sc(y - 1.5), sc(x + 1.5), sc(y + 1.5)], fill=color)


def draw_walk_path(d: ImageDraw.ImageDraw, start: tuple[float, float],
                   end: tuple[float, float]) -> None:
    import math
    x1, y1 = start
    x2, y2 = end
    dist = math.hypot(x2 - x1, y2 - y1)
    steps = max(1, int(dist / 16.0))
    for i in range(1, steps):
        t = i / steps
        px = x1 + (x2 - x1) * t
        py = y1 + (y2 - y1) * t
        r = 2.0 if i % 2 == 0 else 1.6
        d.ellipse([sc(px - r), sc(py - r), sc(px + r), sc(py + r)],
                  fill=(242, 187, 82, 210))
    # Destination ring.
    d.ellipse([sc(x2 - 20), sc(y2 - 12), sc(x2 + 20), sc(y2 + 12)],
              outline=(242, 187, 82, 230), width=sc(1.6))
    d.ellipse([sc(x2 - 12), sc(y2 - 7), sc(x2 + 12), sc(y2 + 7)],
              outline=(255, 214, 133, 150), width=K)


def draw_world(w: float, h: float, on: bool) -> Image.Image:
    im = vgrad(w, h, (12, 25, 40, 255), (5, 10, 16, 255))
    im.alpha_composite(grid_layer(w, h, 40.0, 10))
    d = ImageDraw.Draw(im)

    # Sky particles.
    for px, py, r, a in [(0.18, 0.18, 1.1, 110), (0.31, 0.10, 0.8, 80),
                          (0.52, 0.16, 1.0, 100), (0.68, 0.08, 0.7, 70),
                          (0.79, 0.20, 1.2, 110), (0.91, 0.12, 0.8, 80)]:
        d.ellipse([sc(w * px - r), sc(h * py - r), sc(w * px + r), sc(h * py + r)],
                  fill=(150, 205, 240, a))

    # Layered hills.
    d.polygon([(0, sc(h * 0.55)), (sc(w * 0.13), sc(h * 0.47)),
               (sc(w * 0.27), sc(h * 0.53)), (sc(w * 0.42), sc(h * 0.45)),
               (sc(w * 0.60), sc(h * 0.52)), (sc(w * 0.76), sc(h * 0.44)),
               (sc(w), sc(h * 0.51)), (sc(w), sc(h)), (0, sc(h))],
              fill=(12, 31, 35, 255))
    d.polygon([(0, sc(h * 0.61)), (sc(w * 0.20), sc(h * 0.54)),
               (sc(w * 0.38), sc(h * 0.60)), (sc(w * 0.56), sc(h * 0.53)),
               (sc(w * 0.74), sc(h * 0.59)), (sc(w), sc(h * 0.55)),
               (sc(w), sc(h)), (0, sc(h))],
              fill=(9, 25, 26, 255))
    d.polygon([(0, sc(h * 0.68)), (sc(w * 0.18), sc(h * 0.63)),
               (sc(w * 0.39), sc(h * 0.67)), (sc(w * 0.61), sc(h * 0.62)),
               (sc(w * 0.83), sc(h * 0.66)), (sc(w), sc(h * 0.64)),
               (sc(w), sc(h)), (0, sc(h))],
              fill=(7, 20, 20, 255))

    # Scenery.
    draw_tree(d, w * 0.075, h * 0.63, 1.0)
    draw_tree(d, w * 0.145, h * 0.60, 0.78)
    draw_tree(d, w * 0.555, h * 0.60, 0.9)
    draw_tree(d, w * 0.90, h * 0.61, 0.72)
    draw_bush(d, w * 0.22, h * 0.70, 0.9)
    draw_bush(d, w * 0.49, h * 0.66, 0.75)
    draw_bush(d, w * 0.67, h * 0.71, 0.8)
    draw_rock(d, w * 0.035, h * 0.76, 0.75)
    draw_rock(d, w * 0.58, h * 0.78, 0.55)
    for gx, gy, gs in [(0.25, 0.76, 1.0), (0.33, 0.80, 0.8), (0.46, 0.73, 0.9),
                       (0.63, 0.82, 1.0), (0.71, 0.75, 0.8), (0.86, 0.79, 0.9),
                       (0.94, 0.72, 0.8), (0.40, 0.88, 1.0), (0.77, 0.89, 0.8)]:
        draw_grass_tuft(d, w * gx, h * gy, gs)

    # Player and state-specific cursor/order.
    px, py = w * 0.40, h * 0.72
    if on:
        px, py = w * 0.45, h * 0.71
    draw_player(d, px, py)

    if on:
        dest = (w * 0.70, h * 0.73)
        draw_walk_path(d, (px + 8, py + 22), dest)
        draw_cursor_arrow(d, dest[0] + 8, dest[1] - 2, C_AMBER)
        chip_w = 82.0
        rr(d, (dest[0] - chip_w * 0.5, dest[1] + 18,
               dest[0] + chip_w * 0.5, dest[1] + 38), 5,
           fill=(30, 24, 12, 235), outline=(120, 92, 38, 255), width=1.0)
        txt(d, (dest[0], dest[1] + 28), "WALK HERE", F("monob", 7.6),
            C_AMBER_SOFT, anchor="mm")
        # A distant hostile silhouette demonstrates the chase target.
        mx, my = w * 0.82, h * 0.67
        d.ellipse([sc(mx - 17), sc(my + 12), sc(mx + 17), sc(my + 19)],
                  fill=(0, 0, 0, 100))
        d.polygon([(sc(mx - 16), sc(my + 12)), (sc(mx - 9), sc(my - 4)),
                   (sc(mx + 8), sc(my - 6)), (sc(mx + 17), sc(my + 4)),
                   (sc(mx + 13), sc(my + 12))], fill=(35, 30, 38, 255))
        d.ellipse([sc(mx - 8), sc(my - 12), sc(mx + 6), sc(my - 1)],
                  fill=(43, 37, 47, 255))
        d.polygon([(sc(mx - 6), sc(my - 10)), (sc(mx - 2), sc(my - 22)),
                   (sc(mx + 2), sc(my - 10))], fill=(43, 37, 47, 255))
        d.ellipse([sc(mx - 5), sc(my - 8), sc(mx - 2), sc(my - 5)], fill=C_RED)
        d.ellipse([sc(mx + 1), sc(my - 8), sc(mx + 4), sc(my - 5)], fill=C_RED)
    else:
        cx, cy = w * 0.70, h * 0.64
        draw_crosshair(d, cx, cy, (205, 225, 245, 210))
        rr(d, (cx + 16, cy - 12, cx + 52, cy + 4), 5,
           fill=(12, 20, 33, 220), outline=(57, 80, 114, 230), width=1.0)
        txt(d, (cx + 34, cy - 4), "AIM", F("monob", 7.2), C_TEXT_SOFT,
            anchor="mm")

    return im


# ── Miniature HUD (context only) ────────────────────────────────────────
def hud_panel(d: ImageDraw.ImageDraw, b, radius: float = 6.0,
              fill=(9, 15, 26, 210), border=(45, 63, 93, 225)) -> None:
    rr(d, b, radius, fill=fill, outline=border, width=1.0)


def draw_hud(w: float, h: float, on: bool) -> Image.Image:
    im = Image.new("RGBA", (sc(w), sc(h)), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)

    # Star summary + pause.
    sx, sy, sw, sh = w - 258, 14, 186, 28
    hud_panel(d, (sx, sy, sx + sw, sy + sh))
    draw_star(d, sx + 13, sy + 14, 7, (95, 170, 255, 255))
    txt(d, (sx + 23, sy + 14), "12", F("body", 8.0), C_TEXT, anchor="lm")
    draw_star(d, sx + 51, sy + 14, 7, (247, 208, 88, 255))
    txt(d, (sx + 61, sy + 14), "8", F("body", 8.0), C_TEXT, anchor="lm")
    txt(d, (sx + 86, sy + 14), "LOCAL", F("monob", 6.0), C_MUTED, anchor="lm")
    px, py, pw, ph = w - 64, 14, 50, 28
    hud_panel(d, (px, py, px + pw, py + ph), 5)
    txt(d, (px + pw * 0.5, py + ph * 0.5), "PAUSE", F("body", 6.8),
        C_TEXT, anchor="mm")

    # Mission tracker.
    mx, my, mw, mh = w - 258, 50, 232, 150
    hud_panel(d, (mx, my, mx + mw, my + mh))
    txt(d, (mx + 10, my + 8), "MISSIONS", F("bold", 8.0), C_TEXT)
    d.line([(sc(mx + 10), sc(my + 22)), (sc(mx + mw - 10), sc(my + 22))],
           fill=(58, 82, 118, 220), width=K)
    txt(d, (mx + 10, my + 30), "DUNGEON", F("monob", 5.8), (138, 166, 205, 255))
    txt(d, (mx + 10, my + 43), "Lua Track 01", F("body", 6.4), C_TEXT_SOFT)
    for i in range(3):
        draw_star(d, mx + mw - 28 + i * 8, my + 46, 2.8, (95, 170, 255, 255))
    txt(d, (mx + 10, my + 56), "Python Track 01", F("body", 6.4), C_TEXT_SOFT)
    for i in range(2):
        draw_star(d, mx + mw - 28 + i * 8, my + 59, 2.8, (95, 170, 255, 255))
    txt(d, (mx + 10, my + 72), "GAMEPLAY", F("monob", 5.8), (138, 166, 205, 255))
    for row, label, value in [
        (86, "Collect 20 Wood", "12 / 20"),
        (99, "Mine 10 Stone", "4 / 10"),
        (112, "Craft a Station", "complete"),
    ]:
        txt(d, (mx + 10, my + row), label, F("body", 6.2), C_TEXT_SOFT)
        txt(d, (mx + mw - 10, my + row), value, F("body", 6.0),
            C_GREEN if value == "complete" else C_MUTED, anchor="ra")

    # Automatica status.
    ax, ay, aw, ah = 26, h * 0.40, 214, 92
    hud_panel(d, (ax, ay, ax + aw, ay + ah))
    txt(d, (ax + 10, ay + 8), "AUTOMATICA STATUS", F("bold", 7.0), C_TEXT)
    for i, (name, task) in enumerate([("LUA 0", "Mining Stone"),
                                      ("LUA 1", "Chopping tree"),
                                      ("LUA 2", "Idle")]):
        yy = ay + 28 + i * 18
        txt(d, (ax + 10, yy), name, F("monob", 5.8), C_MUTED)
        txt(d, (ax + 48, yy), task, F("body", 6.0), C_TEXT_SOFT)
        d.ellipse([sc(ax + aw - 18), sc(yy + 1), sc(ax + aw - 13), sc(yy + 6)],
                  fill=C_GREEN if task != "Idle" else C_AMBER)

    # Minimap.
    mmx, mmy, mmw, mmh = 26, h - 170, 142, 146
    hud_panel(d, (mmx, mmy, mmx + mmw, mmy + mmh), 8,
              fill=(8, 14, 24, 225), border=(54, 80, 116, 235))
    d.rectangle([sc(mmx + 8), sc(mmy + 22), sc(mmx + mmw - 8), sc(mmy + mmh - 8)],
                fill=(10, 22, 24, 255), outline=(38, 58, 82, 255), width=K)
    for gx in range(1, 4):
        d.line([(sc(mmx + 8 + gx * 31), sc(mmy + 22)),
                (sc(mmx + 8 + gx * 31), sc(mmy + mmh - 8))],
               fill=(50, 78, 100, 90), width=K)
    for gy in range(1, 4):
        d.line([(sc(mmx + 8), sc(mmy + 22 + gy * 28)),
                (sc(mmx + mmw - 8), sc(mmy + 22 + gy * 28))],
               fill=(50, 78, 100, 90), width=K)
    for tx, ty, tw_, th_, col in [
        (20, 44, 20, 15, (38, 82, 63, 255)),
        (52, 37, 15, 22, (29, 64, 53, 255)),
        (92, 60, 22, 14, (42, 74, 58, 255)),
        (36, 86, 26, 13, (30, 62, 70, 255)),
        (78, 92, 18, 18, (35, 68, 55, 255)),
    ]:
        d.rectangle([sc(mmx + tx), sc(mmy + ty),
                     sc(mmx + tx + tw_), sc(mmy + ty + th_)], fill=col)
    d.ellipse([sc(mmx + 68), sc(mmy + 66), sc(mmx + 76), sc(mmy + 74)],
              fill=(236, 246, 255, 255), outline=(80, 148, 210, 255), width=K)
    txt(d, (mmx + 10, mmy + 7), "MAP", F("monob", 6.0), C_MUTED)
    txt(d, (mmx + mmw - 10, mmy + 7), "M", F("monob", 6.0), C_MUTED,
        anchor="ra")

    # Hotbar + stat bars.
    slot, gap = 25.0, 4.0
    total = 9 * slot + 8 * gap
    hx = w * 0.5 - total * 0.5
    hy = h - 42
    bar_w = total
    bx = hx
    # HP.
    rr(d, (bx, hy - 44, bx + bar_w, hy - 33), 3, fill=(55, 12, 15, 255))
    rr(d, (bx, hy - 44, bx + bar_w * 0.83, hy - 33), 3, fill=(198, 55, 53, 255))
    txt(d, (bx + bar_w * 0.5, hy - 38.5), "HP  100 / 100", F("monob", 5.8),
        (255, 236, 236, 255), anchor="mm")
    # Stamina.
    rr(d, (bx, hy - 29, bx + bar_w, hy - 20), 3, fill=(55, 47, 10, 255))
    rr(d, (bx, hy - 29, bx + bar_w * 0.55, hy - 20), 3, fill=(204, 184, 52, 255))
    txt(d, (bx + bar_w * 0.5, hy - 24.5), "STAMINA  50 / 50", F("monob", 5.6),
        (255, 248, 218, 255), anchor="mm")
    for i in range(9):
        x = hx + i * (slot + gap)
        selected = i == 0
        rr(d, (x, hy, x + slot, hy + slot), 4,
           fill=(22, 33, 52, 245) if not selected else (35, 54, 88, 255),
           outline=(73, 101, 142, 255) if not selected else C_BLUE,
           width=1.0)
        if i < 5:
            col = [(120, 96, 58, 255), (85, 120, 84, 255), (80, 102, 140, 255),
                   (150, 92, 66, 255), (94, 136, 132, 255)][i]
            d.rectangle([sc(x + 6), sc(hy + 6), sc(x + slot - 6), sc(hy + slot - 6)],
                        fill=col)
        txt(d, (x + 3, hy + 2), str(i + 1), F("monob", 4.8),
            C_TEXT_SOFT if selected else C_DIM)

    return im


def frame_mockup(im: Image.Image, w: float, h: float, on: bool) -> None:
    d = ImageDraw.Draw(im)
    rr(d, (0.5, 0.5, w - 0.5, h - 0.5), 8, outline=C_BORDER_HI, width=1.0)
    rr(d, (7, 1, w - 7, 3.5), 1.0, fill=C_AMBER if on else C_BLUE)


# ── Concept A: Field Guide ──────────────────────────────────────────────
FG_W = 392.0


def fg_sections(on: bool) -> list[tuple[str, list[tuple[list[str], str]]]]:
    if not on:
        return [("", [
            (["WASD", "/", "ARROWS"], "Move"),
            (["SHIFT"], "Sprint (hold)"),
            (["LMB"], "Use / mine / attack"),
            (["MOUSE"], "Aim swings"),
            (["SHIFT", "+", "LMB"], "Destroy placed object"),
            (["CTRL"], "Build mode"),
            (["E"], "Inventory"),
            (["1–9", "/", "WHEEL"], "Hotbar"),
            (["M"], "Map"),
            (["ESC"], "Pause / close"),
            (["ENTER", "/", "SPACE"], "Dialogue"),
        ])]
    return [
        ("CLICK ACTIONS", [
            (["LMB"], "Ground: walk there"),
            (["LMB"], "Object: walk + interact"),
            (["LMB"], "Enemy: chase + attack"),
            (["WASD"], "Cancel order + move"),
            (["ESC"], "Cancel move order"),
        ]),
        ("ALWAYS AVAILABLE", [
            (["SHIFT"], "Sprint (hold)"),
            (["SHIFT", "+", "LMB"], "Destroy placed object"),
            (["CTRL"], "Build mode"),
            (["E"], "Inventory"),
            (["1–9", "/", "WHEEL"], "Hotbar"),
            (["M"], "Map"),
            (["ESC"], "Pause / close"),
            (["MOUSE"], "Aim swings"),
            (["ENTER", "/", "SPACE"], "Dialogue"),
        ]),
    ]


def render_field_guide(on: bool, u: float = 1.0) -> Image.Image:
    pad = 16.0 * u
    row_h = 28.0 * u
    section_gap = 10.0 * u
    header_h = 28.0 * u
    footer_h = 28.0 * u
    note_h = (17.0 * u) if on else 0.0
    sections = fg_sections(on)

    height = pad + header_h + 7.0 * u
    for i, (title, rows) in enumerate(sections):
        if title:
            height += (section_gap if i else 3.0 * u) + 15.0 * u + 5.0 * u
        height += len(rows) * row_h
    height += note_h + section_gap + footer_h + pad

    im = panel(FG_W * u, height, 8.0 * u, fill=C_PANEL,
               border=(92, 68, 33, 255) if on else C_BORDER,
               accent=C_AMBER if on else C_BLUE)
    d = ImageDraw.Draw(im)

    # Header.
    txt(d, (pad, pad + 1.0 * u), "PC CONTROLS", F("bold", 16.5, u), C_TEXT)
    state_badge(d, 0, pad + 2.0 * u, on, u, right=FG_W * u - pad)
    d.line([(sc(pad), sc(pad + header_h)), (sc(FG_W * u - pad), sc(pad + header_h))],
           fill=(52, 73, 105, 230), width=K)

    y = pad + header_h + 7.0 * u
    for i, (section, rows) in enumerate(sections):
        if section:
            y += (section_gap if i else 3.0 * u)
            col = C_AMBER if (on and i == 0) else (132, 164, 202, 255)
            txt(d, (pad, y), section, F("monob", 7.4, u), col)
            line_x = pad + tw(d, section, F("monob", 7.4, u)) + 8.0 * u
            d.line([(sc(line_x), sc(y + 5.0 * u)), (sc(FG_W * u - pad), sc(y + 5.0 * u))],
                   fill=(45, 64, 93, 180), width=K)
            y += 15.0 * u + 5.0 * u

        for j, (keys, action) in enumerate(rows):
            accent = on and i == 0
            key_h = 21.0 * u
            draw_key_sequence(d, pad, y + (row_h - key_h) * 0.5, keys, u, key_h, accent)
            action_x = pad + 148.0 * u
            if accent:
                d.ellipse([sc(action_x - 8.0 * u), sc(y + row_h * 0.5 - 1.7 * u),
                           sc(action_x - 4.4 * u), sc(y + row_h * 0.5 + 1.7 * u)],
                          fill=C_AMBER)
                txt(d, (action_x, y + row_h * 0.5), action, F("body", 11.2, u),
                    (246, 225, 185, 255), anchor="lm")
            else:
                txt(d, (action_x, y + row_h * 0.5), action, F("body", 11.2, u),
                    C_TEXT_SOFT, anchor="lm")
            if j < len(rows) - 1:
                d.line([(sc(pad), sc(y + row_h)), (sc(FG_W * u - pad), sc(y + row_h))],
                       fill=(38, 53, 77, 110), width=K)
            y += row_h

    if on:
        y += 2.0 * u
        d.ellipse([sc(pad + 1.0 * u), sc(y + 5.0 * u),
                   sc(pad + 3.8 * u), sc(y + 7.8 * u)], fill=C_AMBER)
        txt(d, (pad + 9.0 * u, y + 6.4 * u),
            "RMB / build mode / open panels never intercepted",
            F("body", 7.8, u), (176, 158, 122, 255), anchor="lm")

    # Footer.
    y += section_gap
    d.line([(sc(pad), sc(y)), (sc(FG_W * u - pad), sc(y))],
           fill=(52, 73, 105, 230), width=K)
    fy = y + 8.0 * u
    draw_keycap(d, pad, fy - 1.0 * u, "F1", u, 15.0 * u)
    txt(d, (pad + 30.0 * u, fy + 6.5 * u), "HIDE / SHOW", F("monob", 6.6, u),
        C_MUTED, anchor="lm")
    right = "AUTO-SPRINT: SETTINGS" if on else "SETTINGS → CONTROLS"
    txt(d, (FG_W * u - pad, fy + 6.5 * u), right, F("body", 7.2, u),
        C_DIM, anchor="rm")

    return im


# ── Concept B: Quick Bar ────────────────────────────────────────────────
QB_W = 840.0


def qb_groups(on: bool) -> list[tuple[list[str], str]]:
    if on:
        return [
            (["WASD"], "Move / cancel"),
            (["SHIFT"], "Sprint"),
            (["LMB"], "Move / act"),
            (["CTRL"], "Build"),
            (["E"], "Inventory"),
            (["1–9"], "Hotbar"),
            (["M"], "Map"),
            (["ESC"], "Pause"),
        ]
    return [
        (["WASD"], "Move"),
        (["SHIFT"], "Sprint"),
        (["LMB"], "Use / mine"),
        (["CTRL"], "Build"),
        (["E"], "Inventory"),
        (["1–9"], "Hotbar"),
        (["M"], "Map"),
        (["ESC"], "Pause"),
    ]


def render_quick_bar(on: bool, u: float = 1.0) -> Image.Image:
    height = (112.0 if on else 86.0) * u
    im = panel(QB_W * u, height, 10.0 * u, fill=(9, 16, 28, 242),
               border=(92, 68, 33, 255) if on else C_BORDER,
               accent=C_AMBER if on else C_BLUE)
    d = ImageDraw.Draw(im)
    pad = 14.0 * u

    # Header.
    txt(d, (pad, 9.0 * u), "PC CONTROLS", F("bold", 12.0, u), C_TEXT)
    title_w = tw(d, "PC CONTROLS", F("bold", 12.0, u))
    state_badge(d, pad + title_w + 10.0 * u, 7.0 * u, on, u)
    hint = "F1  FULL GUIDE"
    txt(d, (QB_W * u - pad, 13.0 * u), hint, F("monob", 6.6, u), C_MUTED,
        anchor="rm")
    d.line([(sc(pad), sc(31.0 * u)), (sc(QB_W * u - pad), sc(31.0 * u))],
           fill=(52, 73, 105, 220), width=K)

    # Key groups.
    groups = qb_groups(on)
    key_h = 19.0 * u
    label_font = F("body", 8.8, u)
    widths = []
    for keys, label in groups:
        kw = key_sequence_width(d, keys, u, key_h)
        widths.append(kw + 6.0 * u + tw(d, label, label_font))
    gap = 15.0 * u
    total = sum(widths) + gap * (len(groups) - 1)
    x = (QB_W * u - total) * 0.5
    y = 38.0 * u
    for i, ((keys, label), gw) in enumerate(zip(groups, widths)):
        accent = on and keys == ["LMB"]
        draw_key_sequence(d, x, y, keys, u, key_h, accent)
        txt(d, (x + key_sequence_width(d, keys, u, key_h) + 6.0 * u,
                y + key_h * 0.5), label, label_font,
            C_AMBER_SOFT if accent else C_TEXT_SOFT, anchor="lm")
        if i < len(groups) - 1:
            sx = x + gw + gap * 0.5
            d.line([(sc(sx), sc(y + 3.0 * u)), (sc(sx), sc(y + key_h - 3.0 * u))],
                   fill=(50, 70, 101, 180), width=K)
        x += gw + gap

    # PnC-specific guidance row.
    if on:
        yy = 76.0 * u
        draw_keycap(d, pad, yy - 7.0 * u, "LMB", u, 17.0 * u, True)
        txt(d, (pad + 40.0 * u, yy + 1.5 * u),
            "GROUND → WALK    OBJECT → INTERACT    ENEMY → CHASE",
            F("body", 8.4, u), (246, 225, 185, 255), anchor="lm")
        txt(d, (QB_W * u - pad, yy + 1.5 * u), "WASD CANCELS · RMB FREE",
            F("monob", 6.4, u), C_MUTED, anchor="rm")
    return im


# ── Concept C: Split Wings ──────────────────────────────────────────────
SPLIT_W = 330.0


def split_sections(on: bool):
    if not on:
        left = [
            ("MOVEMENT", [
                (["WASD", "/", "ARROWS"], "Move"),
                (["SHIFT"], "Sprint (hold)"),
            ]),
            ("WORLD ACTION", [
                (["LMB"], "Use / mine / attack · hold"),
                (["MOUSE"], "Aim swings"),
                (["SHIFT", "+", "LMB"], "Destroy placed object"),
            ]),
        ]
        right = [
            ("BUILD & ITEMS", [
                (["CTRL"], "Build mode"),
                (["E"], "Inventory"),
                (["1–9", "/", "WHEEL"], "Hotbar"),
            ]),
            ("NAVIGATION", [
                (["M"], "Map"),
                (["ESC"], "Pause / close"),
                (["ENTER", "/", "SPACE"], "Dialogue"),
            ]),
        ]
    else:
        left = [
            ("CLICK ACTIONS", [
                (["LMB"], "Ground: walk there"),
                (["LMB"], "Object: walk + interact"),
                (["LMB"], "Enemy: chase + attack"),
            ]),
            ("MOVE & AIM", [
                (["WASD"], "Cancel order + move"),
                (["SHIFT"], "Sprint (hold)"),
                (["MOUSE"], "Aim swings"),
            ]),
        ]
        right = [
            ("WORLD", [
                (["SHIFT", "+", "LMB"], "Destroy placed object"),
                (["CTRL"], "Build mode"),
            ]),
            ("INTERFACE", [
                (["E"], "Inventory"),
                (["1–9", "/", "WHEEL"], "Hotbar"),
                (["M"], "Map"),
                (["ESC"], "Pause / close"),
                (["ENTER", "/", "SPACE"], "Dialogue"),
            ]),
        ]
    return left, right


def render_split_wing(side: str, on: bool, u: float = 1.0) -> Image.Image:
    pad = 14.0 * u
    row_h = 27.0 * u
    section_gap = 8.0 * u
    header_h = 31.0 * u
    footer_h = 27.0 * u
    note_h = 16.0 * u if (side == "right" and on) else 0.0
    left_sections, right_sections = split_sections(on)
    sections = left_sections if side == "left" else right_sections

    height = pad + header_h + 5.0 * u
    for i, (title, rows) in enumerate(sections):
        height += (section_gap if i else 2.0 * u) + 14.0 * u + 4.0 * u
        height += len(rows) * row_h
    height += note_h + section_gap + footer_h + pad

    is_left = side == "left"
    border = (92, 68, 33, 255) if (on and is_left) else C_BORDER
    accent = C_AMBER if (on and is_left) else (C_BLUE if is_left else (94, 125, 166, 255))
    im = panel(SPLIT_W * u, height, 8.0 * u, fill=C_PANEL, border=border,
               accent=accent)
    d = ImageDraw.Draw(im)

    # Header.
    title = ("MOVE & ACT" if not on else "CLICK & MOVE") if is_left else \
            ("SYSTEMS" if not on else "ALWAYS AVAILABLE")
    txt(d, (pad, pad), title, F("bold", 13.5, u), C_TEXT)
    if is_left:
        state_badge(d, 0, pad + 1.0 * u, on, u, right=SPLIT_W * u - pad)
    else:
        sub = "interface & world" if not on else "independent of clicks"
        txt(d, (pad, pad + 18.0 * u), sub, F("body", 7.6, u), C_DIM)
    d.line([(sc(pad), sc(pad + header_h)), (sc(SPLIT_W * u - pad), sc(pad + header_h))],
           fill=(52, 73, 105, 230), width=K)

    y = pad + header_h + 5.0 * u
    for i, (section, rows) in enumerate(sections):
        if section:
            y += section_gap if i else 2.0 * u
            col = C_AMBER if (on and is_left and i == 0) else (132, 164, 202, 255)
            txt(d, (pad, y), section, F("monob", 7.0, u), col)
            line_x = pad + tw(d, section, F("monob", 7.0, u)) + 7.0 * u
            d.line([(sc(line_x), sc(y + 4.5 * u)), (sc(SPLIT_W * u - pad), sc(y + 4.5 * u))],
                   fill=(45, 64, 93, 180), width=K)
            y += 14.0 * u + 4.0 * u

        for j, (keys, action) in enumerate(rows):
            accent_row = on and is_left and i == 0
            key_h = 20.0 * u
            draw_key_sequence(d, pad, y + (row_h - key_h) * 0.5, keys, u, key_h, accent_row)
            action_x = pad + 132.0 * u
            if accent_row:
                d.ellipse([sc(action_x - 7.0 * u), sc(y + row_h * 0.5 - 1.5 * u),
                           sc(action_x - 4.0 * u), sc(y + row_h * 0.5 + 1.5 * u)],
                          fill=C_AMBER)
                txt(d, (action_x, y + row_h * 0.5), action, F("body", 10.4, u),
                    (246, 225, 185, 255), anchor="lm")
            else:
                txt(d, (action_x, y + row_h * 0.5), action, F("body", 10.4, u),
                    C_TEXT_SOFT, anchor="lm")
            if j < len(rows) - 1:
                d.line([(sc(pad), sc(y + row_h)), (sc(SPLIT_W * u - pad), sc(y + row_h))],
                       fill=(38, 53, 77, 105), width=K)
            y += row_h

    if side == "right" and on:
        y += 1.0 * u
        d.ellipse([sc(pad + 1.0 * u), sc(y + 5.0 * u),
                   sc(pad + 3.6 * u), sc(y + 7.6 * u)], fill=C_AMBER)
        txt(d, (pad + 9.0 * u, y + 6.2 * u),
            "RMB / build / UI never intercepted",
            F("body", 7.4, u), (176, 158, 122, 255), anchor="lm")

    # Footer.
    y += section_gap
    d.line([(sc(pad), sc(y)), (sc(SPLIT_W * u - pad), sc(y))],
           fill=(52, 73, 105, 230), width=K)
    fy = y + 8.0 * u
    if is_left:
        draw_keycap(d, pad, fy - 1.0 * u, "F1", u, 15.0 * u)
        txt(d, (pad + 30.0 * u, fy + 6.5 * u), "HIDE / SHOW", F("monob", 6.4, u),
            C_MUTED, anchor="lm")
        right_note = "ESC CANCELS ORDER" if on else "HOLD LMB REPEATS"
        txt(d, (SPLIT_W * u - pad, fy + 6.5 * u), right_note, F("monob", 6.0, u),
            C_DIM, anchor="rm")
    else:
        right_note = "AUTO-SPRINT: SETTINGS" if on else "SETTINGS → CONTROLS"
        txt(d, (SPLIT_W * u - pad, fy + 6.5 * u), right_note, F("body", 6.8, u),
            C_DIM, anchor="rm")

    return im


def render_split_mockup(on: bool) -> Image.Image:
    im = draw_world(MW, MH, on)
    im.alpha_composite(draw_hud(MW, MH, on))
    scrim = Image.new("RGBA", im.size, (2, 6, 12, 82))
    im.alpha_composite(scrim)
    left = render_split_wing("left", on, 1.0)
    right = render_split_wing("right", on, 1.0)
    lh = left.height / K
    rh = right.height / K
    paste_shadow(im, left, 22.0, (MH - lh) * 0.5, 7.0, 0.60)
    paste_shadow(im, right, MW - 22.0 - SPLIT_W, (MH - rh) * 0.5, 7.0, 0.60)
    frame_mockup(im, MW, MH, on)
    return im


def render_split_board() -> Image.Image:
    W, H = 2400.0, 1100.0
    im = vgrad(W, H, C_BG_TOP, C_BG_BOT)
    im.alpha_composite(grid_layer(W, H, 40.0, 12))
    d = ImageDraw.Draw(im)
    draw_board_title(d, 40, 26, "SANDEE PC CONTROLS OVERLAY — SPLIT WINGS",
                     "DRAFT ONLY · controls stacked in vertical left/right wings · centre stays clear")
    txt(d, (W - 40, 34), "F1 TOGGLE PROPOSED", F("monob", 10.0), C_AMBER,
        anchor="ra")
    txt(d, (W - 40, 52), "bindings shown are defaults", F("body", 9.0),
        C_DIM, anchor="ra")

    for i, (on, title, sub, caption) in enumerate([
        (False, "SPLIT WINGS · P&C OFF",
         "Left: move & act · Right: systems",
         "Standard layout. The centre of the screen stays open for the world; F1 hides both wings."),
        (True, "SPLIT WINGS · P&C ON",
         "Left: click actions · Right: always available",
         "Click behaviour moves to the left wing. Systems stay on the right; the centre remains clear."),
    ]):
        x = 40.0 + i * 1200.0
        draw_section_label(d, x, 118, title, sub, on)
        im.alpha_composite(render_split_mockup(on), (sc(x), sc(166)))
        txt(d, (x, 166 + MH + 10), caption, F("body", 10.2), C_DIM)

    fy = 940.0
    d.line([(sc(40), sc(fy - 20)), (sc(W - 40), sc(fy - 20))],
           fill=(52, 73, 105, 200), width=K)
    notes = [
        ("LAYOUT", "Both wings are edge-anchored and vertically centred; the middle third is never covered."),
        ("TOGGLE", "F1 show / hide (proposed). The world keeps running; the overlay never captures clicks."),
        ("PNC ON", "Left wing leads with click actions; Esc cancels a move order before opening pause."),
        ("BINDINGS", "Read live from Settings → Controls; keys shown are defaults."),
    ]
    col_w = (W - 80) / 4.0
    for i, (head, body) in enumerate(notes):
        x = 40 + i * col_w
        txt(d, (x, fy), head, F("monob", 8.0), C_BLUE_SOFT)
        txt(d, (x, fy + 16), body, F("body", 8.4), C_MUTED)

    return im.resize((sc(W // K), sc(H // K)), Image.LANCZOS)


def render_split_closeup() -> Image.Image:
    W, H = 2000.0, 1200.0
    im = vgrad(W, H, C_BG_TOP, C_BG_BOT)
    im.alpha_composite(grid_layer(W, H, 40.0, 12))
    d = ImageDraw.Draw(im)
    draw_board_title(d, 50, 28, "CONCEPT C — SPLIT WINGS",
                     "Vertical left/right stacks · P&C OFF / ON · enlarged for copy review")
    u = 1.38
    pw = SPLIT_W * u
    for row, (on, label) in enumerate([(False, "P&C OFF"), (True, "P&C ON")]):
        y = 120.0 + row * 520.0
        draw_section_label(d, 70, y, label,
                           "Left wing" if not on else "Left wing · click actions", on)
        draw_section_label(d, W - 70 - pw, y,
                           "Right wing" if not on else "Right wing · always available",
                           "systems & interface", False)
        left = render_split_wing("left", on, u)
        right = render_split_wing("right", on, u)
        paste_shadow(im, left, 70, y + 48, 9.0, 0.6)
        paste_shadow(im, right, W - 70 - pw, y + 48, 9.0, 0.6)
        # Centre marker: illustrates the intentionally clear middle.
        cx = W * 0.5
        d.line([(sc(cx), sc(y + 82)), (sc(cx), sc(y + 420))],
               fill=(72, 100, 138, 120), width=K)
        txt(d, (cx, y + 238), "CENTRE\nSTAYS\nCLEAR", F("monob", 8.6),
            (102, 126, 158, 240), anchor="mm", align="center", spacing=7 * K)
    txt(d, (50, H - 44),
        "Wings ~460 px wide at 1080p · centre third free for the world · F1 hides both wings together.",
        F("body", 9.5), C_DIM)
    return im.resize((sc(W // K), sc(H // K)), Image.LANCZOS)


# ── Bottom-cluster concept (current request) ─────────────────────────
def _float_key(d: ImageDraw.ImageDraw, x: float, y: float, label: str,
               u: float, w: float, h: float = 28.0,
               state: int = 0) -> None:
    """state: 0 normal, 1 hover, 2 pressed. No panel behind the cluster."""
    shadow_off = 2.0 * u
    rr(d, (x + shadow_off, y + shadow_off, x + w + shadow_off, y + h + shadow_off),
       4.0 * u, fill=(0, 0, 0, 90))
    if state == 2:
        fill = (24, 62, 96, 220)
        border = (122, 214, 255, 235)
        text_col = (245, 252, 255, 255)
    elif state == 1:
        fill = (16, 27, 43, 200)
        border = (152, 188, 232, 210)
        text_col = (238, 247, 255, 255)
    else:
        fill = (7, 12, 20, 145)
        border = (125, 150, 184, 135)
        text_col = (207, 222, 238, 235)
    rr(d, (x, y, x + w, y + h), 4.0 * u, fill=fill, outline=border, width=1.0)
    txt(d, (x + w * 0.5, y + h * 0.5 + 0.2 * u), label,
        F("monob", 8.2 * u), text_col, anchor="mm")
    if state != 0:
        # A restrained rim light, not a container.
        rr(d, (x + 1.0 * u, y + 1.0 * u, x + w - 1.0 * u, y + h - 1.0 * u),
           3.0 * u, outline=(180, 225, 255, 55), width=1.0)


def _chip_label(d: ImageDraw.ImageDraw, cx: float, y: float, text: str,
                u: float, active: bool = False) -> None:
    txt(d, (cx, y), text, F("monob", 6.4 * u),
        (142, 223, 255, 245) if active else (170, 187, 207, 210), anchor="ma")


def _draw_movement_cluster(d: ImageDraw.ImageDraw, w: float, h: float,
                           u: float, on: bool) -> None:
    key = 34.0 * u
    gap = 4.0 * u
    shift_w = 82.0 * u
    shift_h = 25.0 * u
    x0 = 26.0 * u
    bottom = h - 24.0 * u
    if on:
        # Point-and-click hides WASD; Shift remains for sprint.
        y = bottom - shift_h
        _float_key(d, x0, y, "SHIFT", u, shift_w, shift_h, 0)
        _chip_label(d, x0 + shift_w * 0.5, y + shift_h + 2.0 * u,
                    "SPRINT", u)
        return
    row2_y = bottom - shift_h
    row1_y = row2_y - gap - key
    row0_y = row1_y - gap - key
    # W on top, A S D below, Shift underneath.
    _float_key(d, x0 + key + gap, row0_y, "W", u, key, key, 2)
    _float_key(d, x0, row1_y, "A", u, key, key, 0)
    _float_key(d, x0 + key + gap, row1_y, "S", u, key, key, 0)
    _float_key(d, x0 + (key + gap) * 2, row1_y, "D", u, key, key, 0)
    _float_key(d, x0, row2_y, "SHIFT", u, shift_w, shift_h, 0)
    _chip_label(d, x0 + shift_w * 0.5, row2_y + shift_h + 2.0 * u,
                "SPRINT", u)


def _action_chip(d: ImageDraw.ImageDraw, x: float, y: float,
                 keys: list[str], label: str, u: float,
                 active: bool = False) -> float:
    key_h = 26.0 * u
    gap = 3.0 * u
    sep_w = 8.0 * u
    cap_widths = []
    total_w = 0.0
    for k in keys:
        if k in ("+", "/"):
            total_w += sep_w
            cap_widths.append(0.0)
            continue
        w = max(key_h, tw(d, k, F("monob", 7.8 * u)) + 10.0 * u)
        cap_widths.append(w)
        total_w += w
    total_w += gap * max(0, len(keys) - 1)
    label_w = tw(d, label, F("monob", 6.4 * u))
    width = max(total_w, label_w)
    cx = x + (width - total_w) * 0.5
    for i, k in enumerate(keys):
        if k in ("+", "/"):
            txt(d, (cx + sep_w * 0.5, y + key_h * 0.5), k, F("body", 8.0 * u),
                C_MUTED, anchor="mm")
            cx += sep_w + gap
            continue
        state = 2 if active and i == len(keys) - 1 else 0
        _float_key(d, cx, y, k, u, cap_widths[i], key_h, state)
        cx += cap_widths[i] + gap
    _chip_label(d, x + width * 0.5, y + key_h + 3.0 * u, label, u, active)
    return width


def _draw_action_cluster(d: ImageDraw.ImageDraw, w: float, h: float,
                         u: float, on: bool) -> None:
    bottom = h - 22.0 * u
    label_h = 11.0 * u
    # One merged LMB chip; Ctrl build stays as the second key.
    row = [(["LMB"], "MOVE" if on else "USE", True),
           (["CTRL"], "BUILD", False)]
    key_h = 26.0 * u
    gap = 14.0 * u
    widths = []
    for keys, label, _active in row:
        caps = 0.0
        for k in keys:
            caps += max(key_h, tw(d, k, F("monob", 7.8 * u)) + 10.0 * u)
        widths.append(max(caps, tw(d, label, F("monob", 6.4 * u))))
    total_w = sum(widths) + gap * (len(row) - 1)
    x = w - 24.0 * u - total_w
    y = bottom - key_h - label_h
    for i, (keys, label, active) in enumerate(row):
        _action_chip(d, x, y, keys, label, u, active)
        x += widths[i] + gap


def draw_hud_bottom(w: float, h: float, on: bool) -> Image.Image:
    """Actual PC HUD context: minimap top-left, missions/pause top-right,
    Automatica left-middle, hotbar bottom-centre."""
    im = Image.new("RGBA", (sc(w), sc(h)), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)

    # Star summary + pause.
    sx, sy, sw, sh = w - 258, 14, 186, 28
    hud_panel(d, (sx, sy, sx + sw, sy + sh))
    draw_star(d, sx + 13, sy + 14, 7, (95, 170, 255, 255))
    txt(d, (sx + 23, sy + 14), "12", F("body", 8.0), C_TEXT, anchor="lm")
    draw_star(d, sx + 51, sy + 14, 7, (247, 208, 88, 255))
    txt(d, (sx + 61, sy + 14), "8", F("body", 8.0), C_TEXT, anchor="lm")
    txt(d, (sx + 86, sy + 14), "LOCAL", F("monob", 6.0), C_MUTED, anchor="lm")
    px, py, pw, ph = w - 64, 14, 50, 28
    hud_panel(d, (px, py, px + pw, py + ph), 5)
    txt(d, (px + pw * 0.5, py + ph * 0.5), "PAUSE", F("body", 6.8),
        C_TEXT, anchor="mm")

    # Mission tracker.
    mx, my, mw, mh = w - 258, 50, 232, 142
    hud_panel(d, (mx, my, mx + mw, my + mh))
    txt(d, (mx + 10, my + 8), "MISSIONS", F("bold", 8.0), C_TEXT)
    d.line([(sc(mx + 10), sc(my + 22)), (sc(mx + mw - 10), sc(my + 22))],
           fill=(58, 82, 118, 220), width=K)
    txt(d, (mx + 10, my + 30), "DUNGEON", F("monob", 5.8), (138, 166, 205, 255))
    txt(d, (mx + 10, my + 43), "Lua Track 01", F("body", 6.4), C_TEXT_SOFT)
    for i in range(3):
        draw_star(d, mx + mw - 28 + i * 8, my + 46, 2.8, (95, 170, 255, 255))
    txt(d, (mx + 10, my + 56), "Python Track 01", F("body", 6.4), C_TEXT_SOFT)
    for i in range(2):
        draw_star(d, mx + mw - 28 + i * 8, my + 59, 2.8, (95, 170, 255, 255))
    txt(d, (mx + 10, my + 72), "GAMEPLAY", F("monob", 5.8), (138, 166, 205, 255))
    for row, label, value in [
        (86, "Collect 20 Wood", "12 / 20"),
        (99, "Mine 10 Stone", "4 / 10"),
        (112, "Craft a Station", "complete"),
    ]:
        txt(d, (mx + 10, my + row), label, F("body", 6.2), C_TEXT_SOFT)
        txt(d, (mx + mw - 10, my + row), value, F("body", 6.0),
            C_GREEN if value == "complete" else C_MUTED, anchor="ra")

    # Minimap (actual PC position: top-left).
    mmx, mmy, mmw, mmh = 26, 20, 136, 136
    hud_panel(d, (mmx, mmy, mmx + mmw, mmy + mmh), 8,
              fill=(8, 14, 24, 225), border=(54, 80, 116, 235))
    d.rectangle([sc(mmx + 8), sc(mmy + 22), sc(mmx + mmw - 8), sc(mmy + mmh - 8)],
                fill=(10, 22, 24, 255), outline=(38, 58, 82, 255), width=K)
    for gx in range(1, 4):
        d.line([(sc(mmx + 8 + gx * 30), sc(mmy + 22)),
                (sc(mmx + 8 + gx * 30), sc(mmy + mmh - 8))],
               fill=(50, 78, 100, 90), width=K)
    for gy in range(1, 4):
        d.line([(sc(mmx + 8), sc(mmy + 22 + gy * 27)),
                (sc(mmx + mmw - 8), sc(mmy + 22 + gy * 27))],
               fill=(50, 78, 100, 90), width=K)
    for tx, ty, tw_, th_, col in [
        (18, 40, 20, 15, (38, 82, 63, 255)),
        (50, 34, 15, 22, (29, 64, 53, 255)),
        (90, 58, 22, 14, (42, 74, 58, 255)),
        (34, 84, 26, 13, (30, 62, 70, 255)),
        (78, 90, 18, 18, (35, 68, 55, 255)),
    ]:
        d.rectangle([sc(mmx + tx), sc(mmy + ty),
                     sc(mmx + tx + tw_), sc(mmy + ty + th_)], fill=col)
    d.ellipse([sc(mmx + 66), sc(mmy + 64), sc(mmx + 74), sc(mmy + 72)],
              fill=(236, 246, 255, 255), outline=(80, 148, 210, 255), width=K)
    txt(d, (mmx + 10, mmy + 7), "MAP", F("monob", 6.0), C_MUTED)
    txt(d, (mmx + mmw - 10, mmy + 7), "M", F("monob", 6.0), C_MUTED,
        anchor="ra")

    # Automatica status (left-middle).
    ax, ay, aw, ah = 26, h * 0.40, 214, 86
    hud_panel(d, (ax, ay, ax + aw, ay + ah))
    txt(d, (ax + 10, ay + 8), "AUTOMATICA STATUS", F("bold", 7.0), C_TEXT)
    for i, (name, task) in enumerate([("LUA 0", "Mining Stone"),
                                      ("LUA 1", "Chopping tree"),
                                      ("LUA 2", "Idle")]):
        yy = ay + 28 + i * 17
        txt(d, (ax + 10, yy), name, F("monob", 5.8), C_MUTED)
        txt(d, (ax + 48, yy), task, F("body", 6.0), C_TEXT_SOFT)
        d.ellipse([sc(ax + aw - 18), sc(yy + 1), sc(ax + aw - 13), sc(yy + 6)],
                  fill=C_GREEN if task != "Idle" else C_AMBER)

    # Hotbar + bars (bottom centre), untouched.
    slot, gap = 25.0, 4.0
    total = 9 * slot + 8 * gap
    hx = w * 0.5 - total * 0.5
    hy = h - 42
    bar_w = total
    rr(d, (hx, hy - 44, hx + bar_w, hy - 33), 3, fill=(55, 12, 15, 255))
    rr(d, (hx, hy - 44, hx + bar_w * 0.83, hy - 33), 3, fill=(198, 55, 53, 255))
    txt(d, (hx + bar_w * 0.5, hy - 38.5), "HP  100 / 100", F("monob", 5.8),
        (255, 236, 236, 255), anchor="mm")
    rr(d, (hx, hy - 29, hx + bar_w, hy - 20), 3, fill=(55, 47, 10, 255))
    rr(d, (hx, hy - 29, hx + bar_w * 0.55, hy - 20), 3, fill=(204, 184, 52, 255))
    txt(d, (hx + bar_w * 0.5, hy - 24.5), "STAMINA  50 / 50", F("monob", 5.6),
        (255, 248, 218, 255), anchor="mm")
    for i in range(9):
        x = hx + i * (slot + gap)
        selected = i == 0
        rr(d, (x, hy, x + slot, hy + slot), 4,
           fill=(22, 33, 52, 245) if not selected else (35, 54, 88, 255),
           outline=(73, 101, 142, 255) if not selected else C_BLUE,
           width=1.0)
        if i < 5:
            col = [(120, 96, 58, 255), (85, 120, 84, 255), (80, 102, 140, 255),
                   (150, 92, 66, 255), (94, 136, 132, 255)][i]
            d.rectangle([sc(x + 6), sc(hy + 6), sc(x + slot - 6), sc(hy + slot - 6)],
                        fill=col)
        txt(d, (x + 3, hy + 2), str(i + 1), F("monob", 4.8),
            C_TEXT_SOFT if selected else C_DIM)

    return im


MW, MH = 1160.0, 653.0


def render_bottom_mockup(on: bool) -> Image.Image:
    im = draw_world(MW, MH, on)
    im.alpha_composite(draw_hud_bottom(MW, MH, on))
    u = 0.92
    _draw_movement_cluster(ImageDraw.Draw(im), MW, MH, u, on)
    _draw_action_cluster(ImageDraw.Draw(im), MW, MH, u, on)
    frame_mockup(im, MW, MH, on)
    return im


def render_bottom_board() -> Image.Image:
    W, H = 2400.0, 1100.0
    im = vgrad(W, H, C_BG_TOP, C_BG_BOT)
    im.alpha_composite(grid_layer(W, H, 40.0, 12))
    d = ImageDraw.Draw(im)
    draw_board_title(d, 40, 26, "SANDEE PC CONTROLS — BOTTOM CLUSTERS",
                     "DRAFT ONLY · minimal floating keycaps · no panels · existing HUD untouched")
    txt(d, (W - 40, 34), "GUIDANCE ONLY · CLICKS PASS THROUGH",
        F("monob", 9.0), C_AMBER, anchor="ra")
    for i, (on, title, sub, caption) in enumerate([
        (False, "P&C OFF · STANDARD",
         "WASD + Shift left · one contextual LMB chip right",
         "LMB reads USE / MINE / ATTACK from the hovered target; Shift+DESTROY appears on removable targets."),
        (True, "P&C ON · CLICK MOVEMENT",
         "Shift only left · one contextual LMB chip right",
         "WASD is hidden. LMB reads MOVE / INTERACT / CHASE; Shift+DESTROY appears on removable targets."),
    ]):
        x = 40.0 + i * 1200.0
        draw_section_label(d, x, 118, title, sub, on)
        im.alpha_composite(render_bottom_mockup(on), (sc(x), sc(166)))
        txt(d, (x, 166 + MH + 10), caption, F("body", 10.2), C_DIM)
    fy = 900.0
    d.line([(sc(40), sc(fy - 20)), (sc(W - 40), sc(fy - 20))],
           fill=(52, 73, 105, 200), width=K)
    notes = [
        ("NO PANELS", "Keycaps and labels float directly over the world; no scrim or container."),
        ("HOVER / PRESS", "The relevant key lights up, then returns to its subdued state."),
        ("BOTTOM HUD", "Movement is above the bottom-left corner; actions sit right of the hotbar."),
        ("PLATFORM", "Desktop only. Android touch controls are untouched."),
    ]
    col_w = (W - 80) / 4.0
    for i, (head, body) in enumerate(notes):
        x = 40 + i * col_w
        txt(d, (x, fy), head, F("monob", 8.0), C_BLUE_SOFT)
        txt(d, (x, fy + 16), body, F("body", 8.4), C_MUTED)
    return im.resize((sc(W // K), sc(H // K)), Image.LANCZOS)



def render_mockup(concept: str, on: bool) -> Image.Image:
    im = draw_world(MW, MH, on)
    im.alpha_composite(draw_hud(MW, MH, on))

    if concept == "A":
        scrim = Image.new("RGBA", im.size, (2, 6, 12, 126))
        im.alpha_composite(scrim)
        fg = render_field_guide(on, 1.0)
        paste_shadow(im, fg, 24.0, 22.0, 8.0, 0.68)
    else:
        qb = render_quick_bar(on, 1.0)
        paste_shadow(im, qb, 24.0, 18.0, 7.0, 0.58)

    frame_mockup(im, MW, MH, on)
    return im


# ── Review boards ───────────────────────────────────────────────────────
def draw_board_title(d: ImageDraw.ImageDraw, x: float, y: float,
                     title: str, subtitle: str) -> None:
    txt(d, (x, y), title, F("bold", 29.0), C_TEXT)
    txt(d, (x, y + 38.0), subtitle, F("mono", 12.0), C_MUTED)


def draw_section_label(d: ImageDraw.ImageDraw, x: float, y: float,
                       title: str, subtitle: str, on: bool) -> None:
    accent = C_AMBER if on else C_BLUE
    rr(d, (x, y + 1, x + 4, y + 27), 1.5, fill=accent)
    txt(d, (x + 13, y), title, F("bold", 16.0), C_TEXT)
    txt(d, (x + 13, y + 23), subtitle, F("body", 10.4), C_MUTED)


def render_board() -> Image.Image:
    W, H = 2400.0, 1800.0
    im = vgrad(W, H, C_BG_TOP, C_BG_BOT)
    im.alpha_composite(grid_layer(W, H, 40.0, 12))
    d = ImageDraw.Draw(im)

    draw_board_title(d, 40, 26,
                     "SANDEE PC CONTROLS OVERLAY — ALL STATE VARIANTS",
                     "DRAFT ONLY · two overlay concepts × point-and-click off/on · no implementation")
    txt(d, (W - 40, 34), "F1 TOGGLE PROPOSED", F("monob", 10.0), C_AMBER,
        anchor="ra")
    txt(d, (W - 40, 52), "bindings shown are defaults", F("body", 9.0),
        C_DIM, anchor="ra")

    panels = [
        (40.0, 118.0, "A", False, "FIELD GUIDE · P&C OFF",
         "Temporary left-side sheet · full reference",
         "Dims the world while open. Standard movement and mouse-first actions."),
        (1240.0, 118.0, "A", True, "FIELD GUIDE · P&C ON",
         "Same sheet, click actions lead",
         "LMB rows gain an amber accent; always-available keys stay below."),
        (40.0, 858.0, "B", False, "QUICK BAR · P&C OFF",
         "Always-on compact strip · F1 opens the full guide",
         "One line of essentials; no world dimming and no input capture."),
        (1240.0, 858.0, "B", True, "QUICK BAR · P&C ON",
         "Adds one PnC guidance line",
         "LMB is highlighted; the third line explains ground/object/enemy clicks."),
    ]
    for x, y, concept, on, title, subtitle, caption in panels:
        draw_section_label(d, x, y, title, subtitle, on)
        mock = render_mockup(concept, on)
        im.alpha_composite(mock, (sc(x), sc(y + 48)))
        txt(d, (x, y + 48 + MH + 10), caption, F("body", 10.2), C_DIM)

    # Footer notes.
    fy = 1640.0
    d.line([(sc(40), sc(fy - 20)), (sc(W - 40), sc(fy - 20))],
           fill=(52, 73, 105, 200), width=K)
    notes = [
        ("TOGGLE", "F1 show / hide (proposed; not bound yet). Overlay does not pause the world."),
        ("BINDINGS", "Read live from Settings → Controls; the keys shown here are defaults."),
        ("PNC ON", "Right-click, build mode and open UI panels are never intercepted."),
        ("AUTO-SPRINT", "Optional setting; when ON, PnC movement needs no Shift."),
    ]
    col_w = (W - 80) / 4.0
    for i, (head, body) in enumerate(notes):
        x = 40 + i * col_w
        txt(d, (x, fy), head, F("monob", 8.0), C_BLUE_SOFT)
        txt(d, (x, fy + 16), body, F("body", 8.2), C_MUTED)

    return im.resize((sc(W // K), sc(H // K)), Image.LANCZOS)


def render_a_closeup() -> Image.Image:
    W, H = 1800.0, 1120.0
    im = vgrad(W, H, C_BG_TOP, C_BG_BOT)
    im.alpha_composite(grid_layer(W, H, 40.0, 12))
    d = ImageDraw.Draw(im)
    draw_board_title(d, 50, 28, "CONCEPT A — FIELD GUIDE",
                     "Temporary left-side overlay · P&C OFF / ON · enlarged for copy review")
    u = 1.45
    panels = [(False, 70.0, "P&C OFF", "Standard keyboard + mouse reference"),
              (True, 940.0, "P&C ON", "Click actions lead; always-available keys follow")]
    for on, x, title, subtitle in panels:
        draw_section_label(d, x, 122, title, subtitle, on)
        fg = render_field_guide(on, u)
        paste_shadow(im, fg, x, 176, 10.0, 0.6)
    txt(d, (70, H - 52), "Panel width ~630 px at 1080p · body text ~19 px · footer carries the toggle and auto-sprint note.",
        F("body", 9.5), C_DIM)
    return im.resize((sc(W // K), sc(H // K)), Image.LANCZOS)


def render_b_closeup() -> Image.Image:
    W, H = 1800.0, 760.0
    im = vgrad(W, H, C_BG_TOP, C_BG_BOT)
    im.alpha_composite(grid_layer(W, H, 40.0, 12))
    d = ImageDraw.Draw(im)
    draw_board_title(d, 50, 28, "CONCEPT B — QUICK BAR",
                     "Always-on compact strip · P&C OFF / ON · enlarged for copy review")
    u = 1.55
    for on, y, title, subtitle in [
        (False, 120, "P&C OFF", "One line · essentials only · no dimming"),
        (True, 400, "P&C ON", "Third line explains click behavior; LMB highlighted"),
    ]:
        draw_section_label(d, 66, y, title, subtitle, on)
        qb = render_quick_bar(on, u)
        paste_shadow(im, qb, 66, y + 50, 9.0, 0.6)
    txt(d, (66, H - 46),
        "Bar width ~1390 px at 1080p · collapses below 1280 px to two rows (draft recommendation).",
        F("body", 9.5), C_DIM)
    return im.resize((sc(W // K), sc(H // K)), Image.LANCZOS)


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    render_board().save(OUT / "pc_controls_overlay_all_variants_v1.png")
    render_a_closeup().save(OUT / "pc_controls_overlay_concept_a_closeup_v1.png")
    render_b_closeup().save(OUT / "pc_controls_overlay_concept_b_closeup_v1.png")
    render_split_board().save(OUT / "pc_controls_overlay_split_wings_v1.png")
    render_split_closeup().save(OUT / "pc_controls_overlay_split_wings_closeup_v1.png")
    render_bottom_board().save(OUT / "pc_controls_overlay_bottom_clusters_v1.png")
    print("wrote 6 drafts to", OUT)


if __name__ == "__main__":
    main()
