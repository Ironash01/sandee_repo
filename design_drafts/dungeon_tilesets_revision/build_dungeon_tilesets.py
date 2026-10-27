from __future__ import annotations

# Design-only generator for the revised dungeon art direction.
# It writes exclusively under design_drafts/dungeon_tilesets_revision and never
# touches production assets, scenes, scripts, or save data.
#
# All source art is native-resolution pixel art. Previews are enlarged with
# nearest-neighbour sampling only.

import math
import random
from collections import OrderedDict
from pathlib import Path

from PIL import Image, ImageChops, ImageDraw, ImageFilter, ImageFont

BASE = Path(__file__).resolve().parent
SPRITES = BASE / "sprites"
PREVIEWS = BASE / "previews"
PROJECT = BASE.parent.parent / "SandEEAlpha"
WAYPOINTS = BASE.parent / "waypoints" / "revised" / "sprites"

TILE = 32
TRANSPARENT = (0, 0, 0, 0)
PANEL_BG = (13, 14, 20, 255)
PANEL_BG_2 = (18, 20, 28, 255)
INK = (232, 236, 244, 255)
MUTED = (150, 158, 176, 255)
DIM = (92, 99, 116, 255)

FONT_REGULAR = "C:/Windows/Fonts/consola.ttf"
FONT_BOLD = "C:/Windows/Fonts/consolab.ttf"

LUA = {
    "name": "Lua",
    "title": "ANCIENT RUNE SANCTUM",
    "tag": "LUA DUNGEON - REVISION 01",
    "stone_deep": "#17131A",
    "stone_shadow": "#241E2A",
    "stone_dark": "#322A3A",
    "stone_base": "#403646",
    "stone_mid": "#4D4255",
    "stone_light": "#62546C",
    "stone_hi": "#806C8A",
    "floor_base": "#3B3347",
    "floor_light": "#554965",
    "floor_shadow": "#211A2A",
    "mortar": "#0B0810",
    "gold_dark": "#73562B",
    "gold": "#C09A55",
    "gold_hi": "#F1D692",
    "magic_deep": "#2B1855",
    "magic_dark": "#45298A",
    "magic": "#8064E0",
    "magic_hi": "#C0A6FF",
    "magic_glow": "#F0E8FF",
    "blue": "#7FD0FF",
    "moss": "#4D633B",
}

PYTHON = {
    "name": "Python",
    "title": "STONEGATE FOUNDRY",
    "tag": "PYTHON DUNGEON - REVISION 01",
    "stone_deep": "#111A22",
    "stone_shadow": "#18242D",
    "stone_dark": "#24323C",
    "stone_base": "#30414C",
    "stone_mid": "#3C4E59",
    "stone_light": "#526875",
    "stone_hi": "#708C98",
    "floor_base": "#2B3B45",
    "floor_light": "#415A65",
    "floor_shadow": "#14222A",
    "mortar": "#080E13",
    "gold_dark": "#73562B",
    "gold": "#C09A55",
    "gold_hi": "#F1D699",
    "magic_deep": "#0A3B3D",
    "magic_dark": "#0E5552",
    "magic": "#2FA9A0",
    "magic_hi": "#7DF0DF",
    "magic_glow": "#D8FFF7",
    "blue": "#4D78C4",
    "blue_hi": "#A4CDFF",
    "moss": "#536F44",
}

PALETTES = {"lua": LUA, "python": PYTHON}


def rgba(value: str, alpha: int = 255) -> tuple[int, int, int, int]:
    value = value.lstrip("#")
    return (int(value[0:2], 16), int(value[2:4], 16), int(value[4:6], 16), alpha)


def mix(a: str, b: str, t: float) -> tuple[int, int, int, int]:
    ca, cb = rgba(a), rgba(b)
    return tuple(int(ca[i] + (cb[i] - ca[i]) * t) for i in range(4))


def font(size: int, bold: bool = False) -> ImageFont.FreeTypeFont:
    return ImageFont.truetype(FONT_BOLD if bold else FONT_REGULAR, size)


def text(draw: ImageDraw.ImageDraw, xy, value: str, size: int = 18,
         color=INK, bold: bool = False, anchor: str | None = None):
    draw.text(xy, value, font=font(size, bold), fill=color, anchor=anchor)


def upscale(image: Image.Image, scale: int) -> Image.Image:
    return image.resize((image.width * scale, image.height * scale), Image.Resampling.NEAREST)


def checker(size: tuple[int, int], cell: int = 8,
            a=(34, 36, 44, 255), b=(43, 46, 56, 255)) -> Image.Image:
    img = Image.new("RGBA", size, a)
    d = ImageDraw.Draw(img)
    for y in range(0, size[1], cell):
        for x in range(0, size[0], cell):
            if ((x // cell) + (y // cell)) % 2:
                d.rectangle((x, y, x + cell - 1, y + cell - 1), fill=b)
    return img


def tile_from_sheet(path: Path, xy: tuple[int, int], size=(32, 32)) -> Image.Image:
    return Image.open(path).convert("RGBA").crop((xy[0], xy[1], xy[0] + size[0], xy[1] + size[1]))


def put_sprite(dst: Image.Image, sprite: Image.Image, xy: tuple[int, int]):
    dst.alpha_composite(sprite, (int(xy[0]), int(xy[1])))


# -- Tiles: walls -----------------------------------------------------------

def _brick_fill(pal, rnd: random.Random, course: int) -> str:
    roll = rnd.random()
    if roll < 0.20:
        return pal["stone_mid"]
    if roll < 0.36:
        return pal["stone_dark"]
    return pal["stone_base"]


def _wall_brick_base(pal, theme: str, variant: str, seed: int) -> Image.Image:
    rnd = random.Random(seed + sum(ord(c) * (i + 3) for i, c in enumerate(variant)))
    img = Image.new("RGBA", (TILE, TILE), TRANSPARENT)
    d = ImageDraw.Draw(img)
    d.rectangle((0, 0, 31, 31), fill=rgba(pal["stone_dark"]))

    # Block courses. Lua uses four finer courses like the waypoint's layered
    # masonry; Python uses two heavy ashlar courses to read as a different
    # construction tradition rather than a recolour.
    if theme == "lua":
        courses = [(1, 7), (9, 15), (17, 23), (25, 30)]
        joints = {
            0: [0, 13, 27],
            1: [6, 19, 31],
            2: [0, 16, 28],
            3: [8, 24],
        }
    else:
        courses = [(1, 15), (17, 30)]
        joints = {0: [0, 17], 1: [8, 25, 31]}

    for ci, (top, bottom) in enumerate(courses):
        for ji in range(len(joints[ci]) - 1):
            x0 = joints[ci][ji]
            x1 = joints[ci][ji + 1]
            # Skip fragments off the left edge; the wrapped course reads as cut
            # blocks in the same way the existing dungeon wall art does.
            fill = rgba(_brick_fill(pal, rnd, ci))
            d.rectangle((x0, top, x1, bottom), fill=fill)
            # Soft chiselled bevel: one-pixel light at the top/left and shadow
            # at the bottom/right. Kept subtle so the tile does not read noisy.
            d.line((x0 + 1, top + 1, x1 - 1, top + 1),
                   fill=rgba(pal["stone_light"]))
            d.line((x0 + 1, top + 1, x0 + 1, bottom - 1),
                   fill=rgba(pal["stone_mid"]))
            d.line((x0 + 1, bottom, x1, bottom),
                   fill=rgba(pal["stone_shadow"]))
            if theme == "python" and rnd.random() < 0.26:
                # Brass rivet at a chiselled brick corner.
                rx = x0 + 3
                ry = top + 3
                d.point((rx, ry), fill=rgba(pal["gold"]))
                d.point((rx + 1, ry), fill=rgba(pal["gold_dark"]))
            if theme == "lua" and rnd.random() < 0.10:
                # Tiny gold fleck, never large enough to become a repeated icon.
                fx = rnd.randrange(max(1, x0 + 2), max(2, x1 - 2))
                fy = rnd.randrange(top + 2, bottom - 1)
                d.point((fx, fy), fill=rgba(pal["gold"]))

    # Horizontal mortar aligns with the course boundaries.
    horizontal = [0]
    for _ci, (top, bottom) in enumerate(courses):
        horizontal.append(bottom + 1)
    horizontal.append(31)
    for y in sorted(set(horizontal)):
        d.line((0, y, 31, y), fill=rgba(pal["mortar"]))
    # Vertical joints.
    for ci, (top, bottom) in enumerate(courses):
        for x in joints[ci]:
            x = max(0, min(31, x))
            d.line((x, top, x, bottom), fill=rgba(pal["mortar"]))

    # Weathering / tiny masonry chips.
    for _ in range(5 if theme == "lua" else 4):
        x = rnd.randrange(2, 30)
        y = rnd.randrange(2, 30)
        c = pal["stone_shadow"] if rnd.random() < 0.6 else pal["stone_light"]
        d.point((x, y), fill=rgba(c))
    for _ in range(2):
        x = rnd.randrange(2, 30)
        y = rnd.randrange(2, 30)
        d.point((x, y), fill=rgba(pal["moss"], 190))

    if variant.startswith("top"):
        # Lit cap surface, with the thin gold line from the waypoint facades.
        d.rectangle((0, 0, 31, 5), fill=rgba(pal["stone_light"]))
        d.line((0, 0, 31, 0), fill=rgba(pal["mortar"]))
        d.line((1, 1, 30, 1), fill=rgba(pal["stone_hi"]))
        d.line((1, 6, 30, 6), fill=rgba(pal["gold_dark"]))
        d.line((2, 7, 29, 7), fill=rgba(pal["gold"], 220))
        if theme == "python":
            for sx in (7, 24):
                d.rectangle((sx, 2, sx + 2, 4), fill=rgba(pal["gold_dark"]))
                d.point((sx + 1, 3), fill=rgba(pal["gold_hi"]))
        else:
            d.line((4, 3, 12, 3), fill=rgba(pal["gold"], 185))
            d.line((20, 3, 27, 3), fill=rgba(pal["gold"], 185))

    if variant.startswith("bot"):
        # Heavy footing / front base, strongly shadowed so wall/floor reads.
        d.rectangle((0, 24, 31, 31), fill=rgba(pal["stone_shadow"]))
        d.line((1, 25, 30, 25), fill=rgba(pal["stone_dark"]))
        d.line((1, 26, 30, 26), fill=rgba(pal["stone_light"], 150))
        d.line((1, 30, 30, 30), fill=rgba(pal["mortar"]))
        if theme == "lua":
            d.line((2, 28, 29, 28), fill=rgba(pal["gold_dark"], 190))
        else:
            for sx in (6, 16, 26):
                d.point((sx, 28), fill=rgba(pal["gold"], 210))

    # Exposed sides / corner bevels.
    if variant.endswith("left") or variant == "mid_left":
        d.line((0, 0, 0, 31), fill=rgba(pal["mortar"]))
        d.line((1, 1, 1, 30), fill=rgba(pal["stone_shadow"]))
        d.line((2, 1, 2, 30), fill=rgba(pal["stone_dark"]))
    if variant.endswith("right") or variant == "mid_right":
        d.line((31, 0, 31, 31), fill=rgba(pal["mortar"]))
        d.line((30, 1, 30, 30), fill=rgba(pal["stone_shadow"]))
        d.line((29, 1, 29, 30), fill=rgba(pal["stone_dark"]))

    if variant in ("top_left", "bot_left"):
        d.point((0, 0), fill=rgba(pal["mortar"]))
        d.point((1, 0), fill=rgba(pal["mortar"]))
        d.point((0, 1), fill=rgba(pal["mortar"]))
    if variant in ("top_right", "bot_right"):
        d.point((31, 0), fill=rgba(pal["mortar"]))
        d.point((30, 0), fill=rgba(pal["mortar"]))
        d.point((31, 1), fill=rgba(pal["mortar"]))

    return img


def make_wall_set(theme: str) -> OrderedDict[str, Image.Image]:
    pal = PALETTES[theme]
    names = [
        "top_left", "top_mid", "top_right",
        "mid_left", "mid_mid", "mid_right",
        "bot_left", "bot_mid", "bot_right",
    ]
    out: OrderedDict[str, Image.Image] = OrderedDict()
    for i, name in enumerate(names):
        out[name] = _wall_brick_base(pal, theme, name, 700 + i)
    # Two readable alternates for future controlled variation. They are not
    # required to replace the primary autotile set.
    alt_a = _wall_brick_base(pal, theme, "alt_a", 912)
    da = ImageDraw.Draw(alt_a)
    if theme == "lua":
        # Sparse crescent carving across one brick.
        cy = 16
        for x, y in [(17, 12), (19, 12), (21, 13), (22, 15), (22, 17),
                     (21, 19), (19, 20), (17, 20)]:
            da.point((x, y), fill=rgba(pal["gold"]))
        da.point((20, 16), fill=rgba(pal["magic_hi"]))
        da.point((20, 17), fill=rgba(pal["magic"]))
    else:
        # Inlaid diamond in one block.
        for x, y in [(19, 12), (16, 16), (22, 16), (19, 20)]:
            da.point((x, y), fill=rgba(pal["gold"]))
        da.point((19, 16), fill=rgba(pal["magic_hi"]))
        da.point((18, 16), fill=rgba(pal["magic"]))
    out["alt_rune"] = alt_a

    alt_b = _wall_brick_base(pal, theme, "alt_b", 933)
    db = ImageDraw.Draw(alt_b)
    for x, y in [(5, 7), (6, 8), (25, 24), (24, 23), (18, 27)]:
        db.point((x, y), fill=rgba(pal["moss"]))
    if theme == "python":
        db.line((4, 13, 8, 13), fill=rgba(pal["stone_hi"]))
        db.line((4, 14, 7, 14), fill=rgba(pal["stone_shadow"]))
    out["alt_weathered"] = alt_b
    return out


# -- Tiles: floors ----------------------------------------------------------

def _floor_base(pal, theme: str, variant: int) -> Image.Image:
    rnd = random.Random(4000 + variant * 37 + (0 if theme == "lua" else 500))
    img = Image.new("RGBA", (TILE, TILE), rgba(pal["floor_base"]))
    d = ImageDraw.Draw(img)
    if theme == "lua":
        # Large bespoke flagstones, not a repeating brick course. One 32 px
        # slab per tile with a shallow bevel and sparse, hand-cut wear.
        slab_col = pal["floor_base"]
        if variant == 2:
            slab_col = mix(pal["floor_base"], pal["floor_light"], 0.34)
        elif variant == 3:
            slab_col = mix(pal["floor_base"], pal["floor_shadow"], 0.40)
        elif variant in (4, 5):
            slab_col = mix(pal["floor_base"], pal["floor_light"], 0.08)
        d.rectangle((0, 0, 31, 31),
                    fill=slab_col if isinstance(slab_col, tuple) else rgba(slab_col))
        d.line((0, 0, 31, 0), fill=rgba(pal["mortar"]))
        d.line((0, 0, 0, 31), fill=rgba(pal["mortar"]))
        d.line((1, 1, 30, 1), fill=rgba(pal["floor_light"], 190))
        d.line((1, 1, 1, 30), fill=rgba(pal["floor_light"], 160))
        d.line((0, 31, 31, 31), fill=rgba(pal["floor_shadow"]))
        d.line((31, 0, 31, 31), fill=rgba(pal["floor_shadow"]))
        # One fine crack / chiselled corner per variant.
        if variant == 1:
            for x, y in [(9, 22), (10, 21), (11, 20), (12, 20), (13, 19)]:
                d.point((x, y), fill=rgba(pal["floor_shadow"]))
        elif variant == 2:
            for x, y in [(26, 9), (25, 10), (24, 11), (23, 12)]:
                d.point((x, y), fill=rgba(pal["floor_shadow"]))
        elif variant == 3:
            for x, y in [(5, 11), (6, 10), (7, 9), (8, 8)]:
                d.point((x, y), fill=rgba(pal["floor_shadow"]))
        # Sparse, low-contrast dust and tiny gold/violet flecks.
        for _ in range(4):
            x = rnd.randrange(3, 29)
            y = rnd.randrange(3, 29)
            d.point((x, y), fill=rgba(pal["floor_light"] if rnd.random() < .5
                                      else pal["floor_shadow"], 130))
        if variant in (2, 4):
            d.point((rnd.randrange(4, 28), rnd.randrange(4, 28)),
                    fill=rgba(pal["magic_hi"], 170))
        if variant in (3, 5):
            d.point((rnd.randrange(4, 28), rnd.randrange(4, 28)),
                    fill=rgba(pal["gold"], 150))
        if variant == 2:
            for x, y in [(21, 24), (22, 23), (23, 22), (24, 22), (25, 23)]:
                d.point((x, y), fill=rgba(pal["magic"], 125))
        if variant == 3:
            d.line((19, 8, 22, 8), fill=rgba(pal["gold_dark"], 100))
    else:
        # Regular 16 px foundry slabs. Stronger grid + brass/teal accents make
        # this read as a different material and culture from the Lua floor.
        slab_col = pal["floor_base"]
        if variant == 2:
            slab_col = mix(pal["floor_base"], pal["floor_light"], 0.16)
        elif variant == 3:
            slab_col = mix(pal["floor_base"], pal["floor_shadow"], 0.22)
        elif variant in (4, 5):
            slab_col = mix(pal["floor_base"], pal["floor_light"], 0.07)
        d.rectangle((0, 0, 31, 31), fill=slab_col if isinstance(slab_col, tuple) else rgba(slab_col))
        for x in (0, 16):
            d.line((x, 0, x, 31), fill=rgba(pal["mortar"]))
            d.line((x + 1, 1, x + 1, 30), fill=rgba(pal["floor_light"], 170))
        for y in (0, 16):
            d.line((0, y, 31, y), fill=rgba(pal["mortar"]))
            d.line((1, y + 1, 30, y + 1), fill=rgba(pal["floor_light"], 170))
        for x, y in ((1, 1), (17, 1), (1, 17), (17, 17)):
            d.point((x, y), fill=rgba(pal["floor_light"], 200))
            d.point((x + 1, y + 1), fill=rgba(pal["floor_shadow"], 160))
        # Tiny brass corner pins and teal aggregate in the slabs.
        for x, y in ((14, 14), (30, 14), (14, 30), (30, 30)):
            d.point((x, y), fill=rgba(pal["gold"], 190))
        if variant in (1, 3):
            for x, y in [(7, 9), (8, 9), (24, 23)]:
                d.point((x, y), fill=rgba(pal["stone_dark"]))
        if variant == 2:
            for x, y in [(6, 24), (7, 23), (8, 22), (9, 23), (10, 24)]:
                d.point((x, y), fill=rgba(pal["gold"], 180))
            d.point((8, 23), fill=rgba(pal["magic"], 190))
        if variant == 3:
            for x, y in [(26, 7), (27, 8), (28, 9), (9, 26)]:
                d.point((x, y), fill=rgba(pal["moss"], 210))
        if variant in (4, 5):
            # Subtle diagonal wear / moss, still kept below icon-noise level.
            for x, y in [(5, 21), (6, 20), (7, 19), (25, 8), (26, 7)]:
                d.point((x, y), fill=rgba(pal["floor_light"], 150))
        for _ in range(3):
            x = rnd.randrange(3, 29)
            y = rnd.randrange(3, 29)
            d.point((x, y), fill=rgba(pal["floor_light"], 130))
    return img


def make_floor_set(theme: str) -> OrderedDict[str, Image.Image]:
    out: OrderedDict[str, Image.Image] = OrderedDict()
    for i in range(1, 4):
        out[f"floor_{i}"] = _floor_base(PALETTES[theme], theme, i)
    out["floor_alt_a"] = _floor_base(PALETTES[theme], theme, 4)
    out["floor_alt_b"] = _floor_base(PALETTES[theme], theme, 5)
    pal = PALETTES[theme]
    # Four edge transitions and four corners for raised platforms. They are
    # transparent outside the floor lip and only 4 px thick, so they can be
    # tested later without changing the main floor atlas.
    for side in ("n", "e", "s", "w"):
        img = Image.new("RGBA", (32, 32), TRANSPARENT)
        d = ImageDraw.Draw(img)
        d.rectangle((0, 0, 31, 31), fill=rgba(pal["stone_shadow"]))
        # Start from the main floor texture then cut the outer strip away.
        base = out["floor_1"].copy()
        img.alpha_composite(base)
        if side == "n":
            d.rectangle((0, 0, 31, 3), fill=TRANSPARENT)
            d.line((0, 4, 31, 4), fill=rgba(pal["mortar"]))
            d.line((0, 5, 31, 5), fill=rgba(pal["gold_dark"], 160))
        elif side == "e":
            d.rectangle((28, 0, 31, 31), fill=TRANSPARENT)
            d.line((27, 0, 27, 31), fill=rgba(pal["mortar"]))
            d.line((26, 0, 26, 31), fill=rgba(pal["gold_dark"], 160))
        elif side == "s":
            d.rectangle((0, 28, 31, 31), fill=TRANSPARENT)
            d.line((0, 27, 31, 27), fill=rgba(pal["mortar"]))
            d.line((0, 26, 31, 26), fill=rgba(pal["gold_dark"], 160))
        else:
            d.rectangle((0, 0, 3, 31), fill=TRANSPARENT)
            d.line((4, 0, 4, 31), fill=rgba(pal["mortar"]))
            d.line((5, 0, 5, 31), fill=rgba(pal["gold_dark"], 160))
        out[f"edge_{side}"] = img

    for name, xside, yside in (("nw", "w", "n"), ("ne", "e", "n"),
                               ("sw", "w", "s"), ("se", "e", "s")):
        img = Image.new("RGBA", (32, 32), TRANSPARENT)
        img.alpha_composite(out["floor_1"])
        d = ImageDraw.Draw(img)
        if yside == "n":
            d.rectangle((0, 0, 31, 3), fill=TRANSPARENT)
            d.line((0, 4, 31, 4), fill=rgba(pal["mortar"]))
        else:
            d.rectangle((0, 28, 31, 31), fill=TRANSPARENT)
            d.line((0, 27, 31, 27), fill=rgba(pal["mortar"]))
        if xside == "w":
            d.rectangle((0, 0, 3, 31), fill=TRANSPARENT)
            d.line((4, 0, 4, 31), fill=rgba(pal["mortar"]))
        else:
            d.rectangle((28, 0, 31, 31), fill=TRANSPARENT)
            d.line((27, 0, 27, 31), fill=rgba(pal["mortar"]))
        out[f"corner_{name}"] = img
    return out


# -- Architecture -----------------------------------------------------------

def _stone_rect(d, pal, box, top_hi=True, side_hi=True):
    x0, y0, x1, y1 = box
    d.rectangle(box, fill=rgba(pal["stone_base"]))
    d.rectangle(box, outline=rgba(pal["mortar"]))
    if top_hi:
        d.line((x0 + 1, y0 + 1, x1 - 1, y0 + 1), fill=rgba(pal["stone_light"]))
    if side_hi:
        d.line((x0 + 1, y0 + 1, x0 + 1, y1 - 1), fill=rgba(pal["stone_mid"]))
    d.line((x0 + 1, y1 - 1, x1 - 1, y1 - 1), fill=rgba(pal["stone_shadow"]))


def make_pillar(theme: str) -> Image.Image:
    pal = PALETTES[theme]
    img = Image.new("RGBA", (32, 96), TRANSPARENT)
    d = ImageDraw.Draw(img)
    # bottom plinth
    _stone_rect(d, pal, (1, 85, 30, 95))
    _stone_rect(d, pal, (4, 80, 27, 87))
    d.line((3, 82, 28, 82), fill=rgba(pal["gold"]))
    d.point((5, 84), fill=rgba(pal["gold_hi"]))
    # shaft
    _stone_rect(d, pal, (7, 19, 24, 81))
    d.rectangle((10, 21, 21, 79), fill=rgba(pal["stone_dark"]))
    d.line((11, 21, 11, 79), fill=rgba(pal["stone_mid"]))
    d.line((14, 21, 14, 79), fill=rgba(pal["stone_light"], 170))
    d.line((17, 21, 17, 79), fill=rgba(pal["stone_shadow"]))
    d.line((20, 21, 20, 79), fill=rgba(pal["stone_mid"], 160))
    # capitals and gold collars
    _stone_rect(d, pal, (2, 3, 29, 19))
    d.rectangle((6, 6, 26, 12), fill=rgba(pal["stone_mid"]))
    d.line((3, 15, 28, 15), fill=rgba(pal["gold_dark"]))
    d.line((3, 16, 28, 16), fill=rgba(pal["gold"]))
    d.line((4, 77, 27, 77), fill=rgba(pal["gold_dark"]))
    d.line((4, 78, 27, 78), fill=rgba(pal["gold"]))
    if theme == "lua":
        # narrow violet rune channel and crescent capital motif
        d.rectangle((14, 42, 17, 54), fill=rgba(pal["magic_deep"]))
        d.line((15, 43, 15, 53), fill=rgba(pal["magic"]))
        d.point((16, 47), fill=rgba(pal["magic_hi"]))
        d.point((16, 48), fill=rgba(pal["magic_glow"]))
        d.point((16, 49), fill=rgba(pal["magic_hi"]))
        for x, y in [(13, 8), (14, 7), (15, 7), (16, 8), (16, 9)]:
            d.point((x, y), fill=rgba(pal["gold"]))
        d.point((15, 8), fill=rgba(pal["blue"]))
    else:
        # square brass bands, diamond inlay and rivets
        for y in (34, 58):
            d.line((9, y, 23, y), fill=rgba(pal["gold_dark"]))
            d.line((9, y + 1, 23, y + 1), fill=rgba(pal["gold"]))
        for x, y in [(15, 45), (14, 46), (16, 46), (15, 47), (15, 48)]:
            d.point((x, y), fill=rgba(pal["magic"]))
        d.point((15, 46), fill=rgba(pal["magic_hi"]))
        for x in (9, 22):
            d.point((x, 17), fill=rgba(pal["gold_hi"]))
            d.point((x, 76), fill=rgba(pal["gold_hi"]))
    return img


def make_pilaster(theme: str) -> Image.Image:
    pal = PALETTES[theme]
    img = Image.new("RGBA", (32, 64), TRANSPARENT)
    d = ImageDraw.Draw(img)
    _stone_rect(d, pal, (3, 4, 28, 60))
    d.rectangle((8, 8, 23, 56), fill=rgba(pal["stone_dark"]))
    d.line((9, 8, 9, 56), fill=rgba(pal["stone_light"], 150))
    d.line((22, 8, 22, 56), fill=rgba(pal["stone_shadow"]))
    d.line((4, 7, 27, 7), fill=rgba(pal["gold_dark"]))
    d.line((4, 8, 27, 8), fill=rgba(pal["gold"]))
    d.line((4, 54, 27, 54), fill=rgba(pal["gold_dark"]))
    if theme == "lua":
        for y in (25, 30, 35):
            d.point((15, y), fill=rgba(pal["magic_hi"]))
        d.point((16, 30), fill=rgba(pal["blue"]))
    else:
        for y in (24, 38):
            d.line((10, y, 21, y), fill=rgba(pal["gold_dark"]))
        d.point((15, 31), fill=rgba(pal["magic_hi"]))
        d.point((14, 31), fill=rgba(pal["magic"]))
    return img


def make_arch_frame(theme: str, width: int = 96, height: int = 96,
                    transparent_opening: bool = True) -> Image.Image:
    pal = PALETTES[theme]
    img = Image.new("RGBA", (width, height), TRANSPARENT)
    d = ImageDraw.Draw(img)
    cx = width // 2
    outer = []
    inner = []
    for y in range(height):
        if theme == "lua":
            if y < 6:
                ow = max(0, y * 2)
            elif y < 52:
                ow = int(12 + (y - 6) * (width / 2 - 12) / 46)
            else:
                ow = width // 2
            if y < 24:
                iw = 0
            elif y < 64:
                iw = int((y - 24) * 30 / 40)
            else:
                iw = 30
        else:
            cy = 48
            R = width / 2 - 1
            if y < cy:
                ow = int(math.sqrt(max(0.0, R * R - (cy - y) ** 2)))
            else:
                ow = width // 2
            ri = 30
            ci = 50
            if y < 22:
                iw = 0
            elif y < ci:
                iw = int(math.sqrt(max(0.0, ri * ri - (ci - y) ** 2)))
            else:
                iw = ri
        outer.append(max(0, min(width // 2, ow)))
        inner.append(max(0, min(max(0, outer[-1] - 7), iw)))

    # Stone texture first, then clip it to the arch band.
    stone = Image.new("RGBA", (width, height), rgba(pal["stone_mid"]))
    sd = ImageDraw.Draw(stone)
    for y in range(0, height, 10):
        sd.line((0, y, width - 1, y), fill=rgba(pal["mortar"]))
        sd.line((0, y + 1, width - 1, y + 1), fill=rgba(pal["stone_light"], 185))
    for y in range(height):
        off = 0 if (y // 10) % 2 == 0 else 12
        for x in range(off, width, 24):
            sd.line((x, y - (y % 10), x, y - (y % 10) + 9),
                    fill=rgba(pal["mortar"]))
    for _ in range(90):
        x = random.Random(width * 901 + height * 37 + _).randrange(width)
        y = random.Random(width * 313 + height * 71 + _).randrange(height)
        sd.point((x, y), fill=rgba(pal["stone_base"] if _ % 2 else pal["stone_light"]))

    mask = Image.new("L", (width, height), 0)
    md = ImageDraw.Draw(mask)
    for y in range(height):
        ow = outer[y]
        iw = inner[y]
        if ow > 0:
            md.line((cx - ow, y, cx + ow, y), fill=255)
        if iw > 0:
            md.line((cx - iw, y, cx + iw, y), fill=0)
    if not transparent_opening:
        # Blind arch panel: dark masonry inside, still framed by the gold arch.
        inner_mask = Image.new("L", (width, height), 0)
        imd = ImageDraw.Draw(inner_mask)
        for y in range(height):
            iw = inner[y]
            if iw > 0:
                imd.line((cx - iw, y, cx + iw, y), fill=255)
                md.line((cx - iw, y, cx + iw, y), fill=255)
        inside = Image.new("RGBA", (width, height), rgba(pal["stone_shadow"]))
        masked_inside = Image.new("RGBA", (width, height), TRANSPARENT)
        masked_inside.paste(inside, (0, 0), inner_mask)
        stone = Image.alpha_composite(stone, masked_inside)
    img = Image.composite(stone, img, mask)
    d = ImageDraw.Draw(img)

    # Outer/inner mortar outlines. The gold is deliberately two pixels thick
    # so it stays legible at SandEE's normal camera zoom.
    for y in range(height):
        ow = outer[y]
        iw = inner[y]
        if ow > 0:
            d.point((cx - ow, y), fill=rgba(pal["mortar"]))
            d.point((cx + ow, y), fill=rgba(pal["mortar"]))
            if img.getpixel((cx - ow + 1, y))[3] > 0:
                d.point((cx - ow + 1, y), fill=rgba(pal["stone_hi"], 170))
            if img.getpixel((cx + ow - 1, y))[3] > 0:
                d.point((cx + ow - 1, y), fill=rgba(pal["stone_hi"], 170))
        if iw > 0:
            d.point((cx - iw, y), fill=rgba(pal["mortar"]))
            d.point((cx + iw, y), fill=rgba(pal["mortar"]))
            for off, col in ((1, pal["gold_hi"]), (2, pal["gold"]),
                             (3, pal["gold_dark"])):
                if y % 7 == 0 and off == 1:
                    col = pal["magic_hi"]
                d.point((cx - iw - off, y), fill=rgba(col))
                d.point((cx + iw + off, y), fill=rgba(col))
            if y % 9 == 0:
                d.point((cx - iw - 4, y), fill=rgba(pal["magic"], 180))
                d.point((cx + iw + 4, y), fill=rgba(pal["magic"], 180))

    # Side gold collars and brass studs.
    for y in range(44, height, 16):
        for x in (5, width - 6):
            d.point((x, y), fill=rgba(pal["gold_hi"]))
            d.point((x, y + 1), fill=rgba(pal["gold_dark"]))
    for y in range(0, height, 10):
        if img.getpixel((3, y))[3] > 0:
            d.line((1, y, 4, y), fill=rgba(pal["gold_dark"], 120))
        if img.getpixel((width - 4, y))[3] > 0:
            d.line((width - 5, y, width - 2, y), fill=rgba(pal["gold_dark"], 120))

    # Keystone / language mark at the crown.
    if theme == "lua":
        for x, y in [(cx - 5, 9), (cx - 4, 8), (cx - 3, 7), (cx - 2, 6),
                     (cx - 1, 7), (cx, 8), (cx + 1, 9), (cx + 2, 10)]:
            d.point((x, y), fill=rgba(pal["gold"]))
        d.rectangle((cx - 3, 12, cx + 3, 18), fill=rgba(pal["magic_deep"]))
        d.point((cx, 14), fill=rgba(pal["magic_hi"]))
        d.point((cx, 15), fill=rgba(pal["magic_glow"]))
        d.point((cx, 16), fill=rgba(pal["blue"]))
    else:
        for x, y in [(cx, 6), (cx - 4, 10), (cx + 4, 10),
                     (cx, 14), (cx - 2, 11), (cx + 2, 11)]:
            d.point((x, y), fill=rgba(pal["gold"]))
        d.rectangle((cx - 3, 9, cx + 3, 13), fill=rgba(pal["magic_deep"]))
        d.point((cx, 10), fill=rgba(pal["magic_hi"]))
        d.point((cx, 11), fill=rgba(pal["magic_glow"]))

    if not transparent_opening:
        # Blind-arch niche: a restrained carved focus inside the dark recess.
        cy = int(height * 0.62)
        if theme == "lua":
            for r in (13, 10):
                d.ellipse((cx - r, cy - r, cx + r, cy + r),
                          outline=rgba(pal["gold_dark"] if r == 13 else pal["gold"]))
            d.arc((cx - 7, cy - 7, cx + 7, cy + 7), 30, 215,
                  fill=rgba(pal["magic_hi"]))
            d.point((cx - 1, cy), fill=rgba(pal["magic_glow"]))
            d.point((cx + 2, cy + 3), fill=rgba(pal["blue"]))
            d.line((cx, cy + 13, cx, height - 6), fill=rgba(pal["gold_dark"]))
        else:
            pts = [(cx, cy - 14), (cx + 14, cy), (cx, cy + 14), (cx - 14, cy)]
            d.line(pts + [pts[0]], fill=rgba(pal["gold_dark"]))
            inner = [(cx, cy - 9), (cx + 9, cy), (cx, cy + 9), (cx - 9, cy)]
            d.line(inner + [inner[0]], fill=rgba(pal["magic"]))
            d.point((cx, cy), fill=rgba(pal["magic_glow"]))
            d.point((cx - 1, cy), fill=rgba(pal["magic_hi"]))
            d.line((cx, cy + 14, cx, height - 6), fill=rgba(pal["gold_dark"]))
    return img


def make_masonry_panel(theme: str) -> Image.Image:
    pal = PALETTES[theme]
    img = Image.new("RGBA", (64, 32), TRANSPARENT)
    d = ImageDraw.Draw(img)
    _stone_rect(d, pal, (0, 0, 63, 31))
    for x in (0, 16, 32, 48):
        d.line((x, 0, x, 31), fill=rgba(pal["mortar"]))
    for y in (0, 16, 31):
        d.line((0, y, 63, y), fill=rgba(pal["mortar"]))
    for x in (2, 18, 34, 50):
        d.line((x, 2, x, 14), fill=rgba(pal["stone_light"], 110))
    if theme == "lua":
        cx, cy = 32, 16
        for i, r in [(0, 12), (1, 10), (2, 8)]:
            d.ellipse((cx - r, cy - r, cx + r, cy + r), outline=rgba(pal["gold_dark"]))
        d.arc((cx - 8, cy - 8, cx + 8, cy + 8), 35, 220, fill=rgba(pal["magic"]))
        d.point((cx - 2, cy - 4), fill=rgba(pal["magic_hi"]))
        d.point((cx + 2, cy + 4), fill=rgba(pal["blue"]))
        d.point((cx, cy), fill=rgba(pal["magic_glow"]))
    else:
        diamond = [(32, 4), (44, 16), (32, 28), (20, 16)]
        d.line(diamond + [diamond[0]], fill=rgba(pal["gold_dark"]))
        inner = [(32, 7), (40, 16), (32, 25), (24, 16)]
        d.line(inner + [inner[0]], fill=rgba(pal["gold"]))
        d.point((32, 16), fill=rgba(pal["magic_hi"]))
        d.point((30, 16), fill=rgba(pal["blue"]))
        d.point((34, 16), fill=rgba(pal["blue_hi"]))
        d.line((8, 6, 14, 6), fill=rgba(pal["magic"], 180))
        d.line((50, 26, 56, 26), fill=rgba(pal["gold"], 150))
    return img


def make_sconce(theme: str) -> Image.Image:
    pal = PALETTES[theme]
    img = Image.new("RGBA", (16, 32), TRANSPARENT)
    d = ImageDraw.Draw(img)
    d.line((3, 28, 12, 28), fill=rgba(pal["mortar"]))
    d.line((4, 26, 11, 26), fill=rgba(pal["gold_dark"]))
    d.line((5, 23, 10, 23), fill=rgba(pal["gold"]))
    d.line((7, 21, 8, 23), fill=rgba(pal["gold_dark"]))
    if theme == "lua":
        d.polygon([(4, 15), (7, 8), (10, 15), (8, 21), (6, 21)],
                  fill=rgba(pal["magic_dark"]))
        d.line([(4, 15), (7, 8), (10, 15)], fill=rgba(pal["magic_hi"]))
        d.point((7, 12), fill=rgba(pal["magic_glow"]))
        d.point((7, 13), fill=rgba(pal["magic_hi"]))
        d.point((8, 14), fill=rgba(pal["blue"]))
    else:
        d.polygon([(4, 16), (7, 9), (11, 13), (10, 20), (6, 22)],
                  fill=rgba(pal["magic_deep"]))
        d.line([(4, 16), (7, 9), (11, 13)], fill=rgba(pal["magic_hi"]))
        d.point((7, 13), fill=rgba(pal["magic_glow"]))
        d.point((8, 14), fill=rgba(pal["magic_hi"]))
        d.point((6, 17), fill=rgba(pal["blue"]))
        d.point((7, 10), fill=rgba(pal["gold_hi"]))
    return img


def make_medallion(theme: str) -> Image.Image:
    pal = PALETTES[theme]
    img = Image.new("RGBA", (64, 64), TRANSPARENT)
    base = _floor_base(pal, theme, 1)
    for y in (0, 32):
        for x in (0, 32):
            put_sprite(img, base, (x, y))
    d = ImageDraw.Draw(img)
    cx = cy = 32
    if theme == "lua":
        for r, c in [(27, pal["mortar"]), (25, pal["gold_dark"]),
                     (22, pal["gold"]), (18, pal["magic_deep"]),
                     (14, pal["magic"]), (10, pal["magic_hi"])]:
            d.ellipse((cx - r, cy - r, cx + r, cy + r), outline=rgba(c))
        for x, y in [(32, 17), (34, 20), (36, 24), (37, 29), (35, 34),
                     (31, 37), (27, 35), (25, 31), (26, 26), (29, 22)]:
            d.point((x, y), fill=rgba(pal["gold_hi"]))
        d.point((31, 31), fill=rgba(pal["magic_glow"]))
        d.point((33, 31), fill=rgba(pal["blue"]))
        for x, y in [(13, 47), (14, 46), (15, 45), (16, 46), (17, 47)]:
            d.point((x, y), fill=rgba(pal["magic"], 160))
    else:
        for p in [(32, 4), (58, 32), (32, 60), (6, 32)]:
            pass
        d.polygon([(32, 4), (58, 32), (32, 60), (6, 32)], outline=rgba(pal["gold_dark"]))
        d.polygon([(32, 8), (53, 32), (32, 56), (11, 32)], outline=rgba(pal["gold"]))
        d.polygon([(32, 15), (47, 32), (32, 49), (17, 32)], outline=rgba(pal["magic"]))
        d.line((32, 8, 32, 56), fill=rgba(pal["magic"], 150))
        d.line((11, 32, 53, 32), fill=rgba(pal["gold"], 150))
        for x, y in [(32, 12), (32, 52), (12, 32), (52, 32)]:
            d.point((x, y), fill=rgba(pal["magic_hi"]))
        d.point((32, 31), fill=rgba(pal["magic_glow"]))
        d.point((32, 32), fill=rgba(pal["magic_hi"]))
        d.point((32, 33), fill=rgba(pal["blue"]))
    return img


def architecture(theme: str) -> OrderedDict[str, Image.Image]:
    return OrderedDict([
        ("pillar_32x96", make_pillar(theme)),
        ("pilaster_32x64", make_pilaster(theme)),
        ("door_frame_96x96", make_arch_frame(theme, 96, 96, True)),
        ("blind_arch_96x64", make_arch_frame(theme, 96, 64, False)),
        ("masonry_panel_64x32", make_masonry_panel(theme)),
        ("sconce_16x32", make_sconce(theme)),
        ("floor_medallion_64x64", make_medallion(theme)),
    ])


# -- Save isolated native assets --------------------------------------------

def save_palette_swatch(path: Path, pal):
    keys = ["stone_shadow", "stone_dark", "stone_base", "stone_light",
            "gold_dark", "gold", "gold_hi", "magic_deep", "magic",
            "magic_hi", "magic_glow", "moss"]
    img = Image.new("RGBA", (len(keys) * 28, 28), PANEL_BG)
    d = ImageDraw.Draw(img)
    for i, k in enumerate(keys):
        d.rectangle((i * 28, 0, i * 28 + 27, 27), fill=rgba(pal[k]))
    img.save(path)


def save_assets(theme: str):
    pal = PALETTES[theme]
    out_dir = SPRITES / theme
    out_dir.mkdir(parents=True, exist_ok=True)
    walls = make_wall_set(theme)
    floors = make_floor_set(theme)
    arch = architecture(theme)
    for name, img in walls.items():
        img.save(out_dir / f"wall_{name}.png")
    for name, img in floors.items():
        img.save(out_dir / f"{name}.png")
    for name, img in arch.items():
        img.save(out_dir / f"{name}.png")

    # Transparent review sheets.
    wall_floor = Image.new("RGBA", (TILE * 13, TILE * 2), TRANSPARENT)
    for i, (name, img) in enumerate(walls.items()):
        put_sprite(wall_floor, img, (i * TILE, 0))
    floor_names = list(floors.keys())
    for i, name in enumerate(floor_names):
        row = 1 + i // 13
        col = i % 13
        put_sprite(wall_floor, floors[name], (col * TILE, row * TILE))
    wall_floor.save(SPRITES / f"{theme}_walls_floors_transparent.png")

    arch_sheet = Image.new("RGBA", (160, 280), TRANSPARENT)
    put_sprite(arch_sheet, arch["pillar_32x96"], (0, 0))
    put_sprite(arch_sheet, arch["pilaster_32x64"], (36, 0))
    put_sprite(arch_sheet, arch["door_frame_96x96"], (0, 100))
    put_sprite(arch_sheet, arch["blind_arch_96x64"], (0, 200))
    put_sprite(arch_sheet, arch["masonry_panel_64x32"], (72, 0))
    put_sprite(arch_sheet, arch["sconce_16x32"], (72, 40))
    put_sprite(arch_sheet, arch["floor_medallion_64x64"], (72, 80))
    arch_sheet.save(SPRITES / f"{theme}_architecture_transparent.png")


# -- Presentation building blocks -------------------------------------------

def draw_panel(canvas, box, color=PANEL_BG_2, outline=(50, 56, 70, 255), radius=0):
    d = ImageDraw.Draw(canvas)
    d.rounded_rectangle(box, radius=radius, fill=color, outline=outline, width=2)


def draw_tile_grid(canvas, tiles, x, y, scale, cols, label_size=14,
                   label_color=MUTED, gap=8, cell_pad=4):
    d = ImageDraw.Draw(canvas)
    cell = TILE * scale + cell_pad * 2
    for i, (name, img) in enumerate(tiles.items()):
        col = i % cols
        row = i // cols
        cx = x + col * (cell + gap)
        cy = y + row * (cell + label_size + gap)
        draw_panel(canvas, (cx, cy, cx + cell, cy + cell), PANEL_BG,
                   outline=(43, 48, 61, 255), radius=3)
        bg = checker((cell - cell_pad * 2, cell - cell_pad * 2), 8,
                     (30, 32, 40, 255), (39, 42, 52, 255))
        put_sprite(canvas, bg, (cx + cell_pad, cy + cell_pad))
        tile = upscale(img, scale)
        put_sprite(canvas, tile, (cx + cell_pad, cy + cell_pad))
        short = {
            "alt_rune": "ALT RUNE", "alt_weathered": "ALT WEATHERED",
            "floor_alt_a": "ALT A", "floor_alt_b": "ALT B",
            "edge_n": "EDGE N", "edge_e": "EDGE E",
            "edge_s": "EDGE S", "edge_w": "EDGE W",
            "corner_nw": "CORNER NW", "corner_ne": "CORNER NE",
            "corner_sw": "CORNER SW", "corner_se": "CORNER SE",
        }.get(name, name.replace("_", " ").upper())
        text(d, (cx + cell // 2, cy + cell + 2 + label_size // 2),
             short, size=label_size, color=label_color, anchor="ma")


def assemble_wall_patch(theme: str, width: int = 9, height: int = 5,
                        with_floor: bool = True) -> Image.Image:
    walls = make_wall_set(theme)
    floors = make_floor_set(theme)
    pal = PALETTES[theme]
    img = Image.new("RGBA", (width * TILE, height * TILE), TRANSPARENT)
    wall_cells = set()
    for x in range(width):
        wall_cells.add((x, 0))
        wall_cells.add((x, height - 1))
    for y in range(height):
        wall_cells.add((0, y))
        wall_cells.add((width - 1, y))
    if with_floor:
        for y in range(height):
            for x in range(width):
                if (x, y) not in wall_cells:
                    im = floors[f"floor_{(x * 2 + y * 3) % 3 + 1}"]
                    put_sprite(img, im, (x * TILE, y * TILE))
    for x, y in wall_cells:
        up = (x, y - 1) in wall_cells
        down = (x, y + 1) in wall_cells
        left = (x - 1, y) in wall_cells
        right = (x + 1, y) in wall_cells
        if not up:
            v = "top_left" if not left else ("top_right" if not right else "top_mid")
        elif not down:
            v = "bot_left" if not left else ("bot_right" if not right else "bot_mid")
        elif not left:
            v = "mid_left"
        elif not right:
            v = "mid_right"
        else:
            v = "mid_mid"
        put_sprite(img, walls[v], (x * TILE, y * TILE))
    return img


def assemble_floor_edge_patch(theme: str) -> Image.Image:
    floors = make_floor_set(theme)
    img = Image.new("RGBA", (5 * TILE, 5 * TILE), TRANSPARENT)
    for y in range(1, 4):
        for x in range(1, 4):
            img.alpha_composite(floors[f"floor_{(x + y) % 3 + 1}"], (x * TILE, y * TILE))
    for x in range(1, 4):
        img.alpha_composite(floors["edge_n"], (x * TILE, 0))
        img.alpha_composite(floors["edge_s"], (x * TILE, 4 * TILE))
    for y in range(1, 4):
        img.alpha_composite(floors["edge_w"], (0, y * TILE))
        img.alpha_composite(floors["edge_e"], (4 * TILE, y * TILE))
    img.alpha_composite(floors["corner_nw"], (0, 0))
    img.alpha_composite(floors["corner_ne"], (4 * TILE, 0))
    img.alpha_composite(floors["corner_sw"], (0, 4 * TILE))
    img.alpha_composite(floors["corner_se"], (4 * TILE, 4 * TILE))
    return img


def compose_presentation(theme: str) -> Image.Image:
    pal = PALETTES[theme]
    walls = make_wall_set(theme)
    floors = make_floor_set(theme)
    arch = architecture(theme)
    W, H = 2200, 1800
    canvas = Image.new("RGBA", (W, H), PANEL_BG)
    d = ImageDraw.Draw(canvas)
    # subtle grid
    for x in range(0, W, 64):
        d.line((x, 0, x, H), fill=(20, 22, 30, 255))
    for y in range(0, H, 64):
        d.line((0, y, W, y), fill=(20, 22, 30, 255))
    draw_panel(canvas, (0, 0, W - 1, 112),
               color=(16, 18, 25, 255), outline=(55, 75, 76, 255), radius=0)
    accent = (pal["magic"] if theme == "lua" else pal["magic_hi"])
    d.rectangle((0, 108, W - 1, 111), fill=rgba(accent))
    text(d, (40, 24), pal["tag"], size=18, color=rgba(accent), bold=True)
    text(d, (40, 49), f"{pal['name'].upper()} DUNGEON", size=46, bold=True)
    text(d, (42, 94), f"{pal['title']} - tile, material and architecture direction",
         size=18, color=MUTED)
    text(d, (W - 40, 30), "DESIGN DRAFT - NOT IMPLEMENTED", size=16,
         color=(224, 170, 104, 255), bold=True, anchor="ra")
    text(d, (W - 40, 52), "32 px grid - pixel-art scale", size=15,
         color=MUTED, anchor="ra")

    # Waypoint reference thumbnail.
    wp_name = "portal_lua_ancient_animated_sheet.png" if theme == "lua" else "portal_python_stonegate_animated_sheet.png"
    wp = Image.open(WAYPOINTS / wp_name).convert("RGBA")
    frame_w, frame_h = (192, 160) if theme == "lua" else (160, 128)
    wp = wp.crop((0, 0, frame_w, frame_h))
    wp_scale = 2
    wp_big = upscale(wp, wp_scale)
    x0, y0 = W - 40 - wp_big.width, 132
    draw_panel(canvas, (x0 - 12, y0 - 12, x0 + wp_big.width + 12, y0 + wp_big.height + 58),
               color=(12, 13, 18, 255), outline=(64, 55, 78, 255), radius=6)
    text(d, (x0, y0 - 2), "WAYPOINT REFERENCE", size=15, color=MUTED, bold=True)
    put_sprite(canvas, wp_big, (x0, y0))
    text(d, (x0 + wp_big.width // 2, y0 + wp_big.height + 18),
         "approved waypoint draft", size=14, color=DIM, anchor="ma")

    # Palette.
    y = 305
    text(d, (40, y), "PALETTE / MATERIAL REFERENCE", size=20, color=INK, bold=True)
    y += 38
    swatches = ["stone_shadow", "stone_dark", "stone_base", "stone_light",
                "floor_base", "floor_light", "gold_dark", "gold", "gold_hi",
                "magic_deep", "magic", "magic_hi"]
    for i, key in enumerate(swatches):
        x = 40 + i * 86
        d.rectangle((x, y, x + 76, y + 38), fill=rgba(pal[key]),
                    outline=(70, 74, 88, 255))
        text(d, (x, y + 45), pal[key], size=13, color=MUTED)
        text(d, (x, y + 62), key.replace("_", " "), size=12, color=DIM)
    text(d, (40, y + 88),
         "MATERIALS  -  " + ("violet-lit basalt, black mortar, etched gold, cold crescent glints"
                             if theme == "lua" else
                             "blue-grey ashlar, black mortar, brass bands, teal crystal glints"),
         size=16, color=MUTED)

    # Walls and floors.
    y = 492
    text(d, (40, y), "WALL AUTOTILE SET", size=20, color=INK, bold=True)
    text(d, (430, y + 5),
         "3x3 face set + alternates  -  native 32x32", size=14, color=DIM)
    y += 34
    wall_items = list(walls.items())
    draw_tile_grid(canvas, dict(wall_items[:6]), 40, y, 3, 6)
    draw_tile_grid(canvas, dict(wall_items[6:]), 40, y + 130, 3, 6)
    # A small assembled sample on the right of the wall grid.
    sample_x = 900
    sample_y = y - 2
    draw_panel(canvas, (sample_x - 10, sample_y - 10, sample_x + 9 * 32 * 2 + 10,
                        sample_y + 5 * 32 * 2 + 46),
               color=(11, 12, 17, 255), outline=(52, 58, 70, 255), radius=5)
    sample = assemble_wall_patch(theme, 9, 5, True)
    put_sprite(canvas, upscale(sample, 2), (sample_x, sample_y))
    text(d, (sample_x, sample_y + 5 * 32 * 2 + 10),
         "ASSEMBLED PATCH  -  walls + floor variants", size=14, color=MUTED)

    y = 830
    text(d, (40, y), "FLOOR TILES + EDGE TRANSITIONS", size=20, color=INK, bold=True)
    text(d, (470, y + 5), "native 32x32 - 3 primary + 2 alternates + 8 edges",
         size=14, color=DIM)
    y += 34
    floor_items = list(floors.items())
    draw_tile_grid(canvas, dict(floor_items[:7]), 40, y, 3, 7)
    draw_tile_grid(canvas, dict(floor_items[7:]), 40, y + 130, 3, 7)
    # Edge/corner transition trial at native 32 px, shown at 2x on checker.
    edge_x, edge_y = 900, y - 2
    draw_panel(canvas, (edge_x - 10, edge_y - 30, edge_x + 5 * 32 * 2 + 10,
                        edge_y + 5 * 32 * 2 + 38), PANEL_BG,
               outline=(50, 58, 70, 255), radius=5)
    text(d, (edge_x, edge_y - 24), "EDGE TRANSITION TRIAL / 5 x 5 TILES", size=14,
         color=MUTED, bold=True)
    bg = checker((5 * 32 * 2, 5 * 32 * 2), 16, (30, 32, 40, 255), (39, 42, 52, 255))
    put_sprite(canvas, bg, (edge_x, edge_y))
    edge_patch = assemble_floor_edge_patch(theme)
    put_sprite(canvas, upscale(edge_patch, 2), (edge_x, edge_y))
    text(d, (edge_x, edge_y + 5 * 32 * 2 + 6),
         "transparent lips around a raised slab", size=13, color=DIM)

    # Architecture.
    y = 1250
    text(d, (40, y), "INTERIOR ARCHITECTURE", size=20, color=INK, bold=True)
    text(d, (430, y + 5),
         "draft props - transparent isolated sprites", size=14, color=DIM)
    y += 26
    positions = [
        ("pillar", arch["pillar_32x96"], 2, 32, 96),
        ("pilaster", arch["pilaster_32x64"], 2, 32, 64),
        ("door frame", arch["door_frame_96x96"], 2, 96, 96),
        ("blind arch", arch["blind_arch_96x64"], 2, 96, 64),
        ("masonry panel", arch["masonry_panel_64x32"], 2, 64, 32),
        ("sconce", arch["sconce_16x32"], 3, 16, 32),
        ("floor medallion", arch["floor_medallion_64x64"], 2, 64, 64),
    ]
    x = 40
    for label, sprite, scale, w, h in positions:
        big = upscale(sprite, scale)
        box_w = max(big.width + 16, 150)
        box_h = big.height + 54
        draw_panel(canvas, (x, y, x + box_w, y + box_h), PANEL_BG,
                   outline=(48, 54, 67, 255), radius=4)
        bg = checker((box_w - 8, box_h - 8), 8, (30, 32, 40, 255), (39, 42, 52, 255))
        put_sprite(canvas, bg, (x + 4, y + 4))
        put_sprite(canvas, big, (x + (box_w - big.width) // 2, y + 10))
        text(d, (x + box_w // 2, y + box_h - 29),
             f"{label.upper()}  {w}x{h}", size=12, color=MUTED, anchor="ma")
        x += box_w + 14
    # Design-intent notes fill the lower-right area beside the architecture.
    nx, ny = 1360, 1250
    draw_panel(canvas, (nx, ny, nx + 800, ny + 390), PANEL_BG_2,
               outline=(52, 62, 70, 255), radius=6)
    text(d, (nx + 24, ny + 22), "DESIGN INTENT", size=20, color=rgba(accent), bold=True)
    intent = [
        ("ARCHITECTURE", "", MUTED, 14),
        ("- pointed, elongated openings and clustered vertical supports", MUTED, 14),
        ("- thin gold rails; black mortar; sparse rune carving", MUTED, 14),
        ("- large processional floor flags around circular rune medallions", MUTED, 14),
        ("", "", MUTED, 14),
        ("MATERIAL / LIGHT", "", MUTED, 14),
        ("- warm charcoal-violet basalt, not a straight copy of the grey dungeon", MUTED, 14),
        ("- cold crescent-blue glints plus violet local light pools", MUTED, 14),
        ("- gold is reserved for thresholds, capitals and ritual inlays", MUTED, 14),
    ] if theme == "lua" else [
        ("ARCHITECTURE", "", MUTED, 14),
        ("- heavy rounded arches, broad square supports and stepped bases", MUTED, 14),
        ("- brass bands, square rivets and teal crystal insets", MUTED, 14),
        ("- regular foundry slabs with diamond medallions", MUTED, 14),
        ("", "", MUTED, 14),
        ("MATERIAL / LIGHT", "", MUTED, 14),
        ("- cool blue-grey ashlar with green moss weathering", MUTED, 14),
        ("- teal local light pools and restrained brass highlights", MUTED, 14),
        ("- heavier massing; no pointed-arch or crescent vocabulary", MUTED, 14),
    ]
    for i, item in enumerate(intent):
        if len(item) == 4:
            body, _unused, color, size = item
        else:
            body, color, size = item
        text(d, (nx + 24, ny + 60 + i * 30), body, size=size, color=color)
    text(d, (40, H - 34),
         "Draft only. Not imported into Godot; no existing tile, resource, script or save data was modified.",
         size=15, color=(202, 166, 106, 255))
    return canvas


def _apply_mockup_lighting(room: Image.Image, theme: str, lights) -> Image.Image:
    pal = PALETTES[theme]
    ambient = Image.new("RGBA", room.size, rgba(pal["magic_deep"], 22))
    room = Image.alpha_composite(room, ambient)
    rgb = room.convert("RGB")
    glow = Image.new("RGB", room.size, (0, 0, 0))
    gd = ImageDraw.Draw(glow)
    for lx, ly, radius, color, power in lights:
        for rr in range(radius, 0, -2):
            t = max(0.0, 1.0 - rr / float(radius)) ** 1.7
            c = tuple(min(255, int(ch * power * t)) for ch in color)
            gd.ellipse((lx - rr, ly - rr * 0.70, lx + rr, ly + rr * 0.70), fill=c)
    glow = glow.filter(ImageFilter.GaussianBlur(4))
    rgb = ImageChops.add(rgb, glow)
    # Darker edges keep the room framing readable without flattening the centre.
    mask_small = Image.new("L", (80, 48), 255)
    md = ImageDraw.Draw(mask_small)
    for gy in range(48):
        for gx in range(80):
            nx = (gx - 39.5) / 39.5
            ny = (gy - 23.5) / 23.5
            d = min(1.0, math.sqrt(nx * nx + ny * ny))
            v = 255 - int(max(0.0, d - 0.50) / 0.50 * 58)
            md.point((gx, gy), fill=v)
    mask = mask_small.resize(room.size, Image.Resampling.BICUBIC)
    rgb = ImageChops.multiply(rgb, Image.merge("RGB", (mask, mask, mask)))
    rgb = ImageChops.add(rgb, Image.new("RGB", rgb.size, (7, 5, 12)))
    room = Image.merge("RGBA", (*rgb.split(), room.getchannel("A")))
    # Sparse pixel motes; deliberately below projectile/icon contrast.
    mote = Image.new("RGBA", room.size, TRANSPARENT)
    md = ImageDraw.Draw(mote)
    for i in range(34):
        mx = (i * 167 + 37) % room.width
        my = (i * 97 + 59) % room.height
        md.point((mx, my), fill=rgba(pal["magic_hi"], 130 if i % 3 else 80))
    return Image.alpha_composite(room, mote)


def _draw_door_aperture(room: Image.Image, theme: str, door_center: int) -> None:
    pal = PALETTES[theme]
    d = ImageDraw.Draw(room)
    top = 34
    bottom = 142
    half = 30
    for y in range(top, bottom):
        if theme == "lua":
            if y < 58:
                hw = int((y - top) * half / 24)
            else:
                hw = half
        else:
            cy = 58
            if y < cy:
                hw = int(math.sqrt(max(0.0, half * half - (cy - y) ** 2)))
            else:
                hw = half
        if hw <= 0:
            continue
        d.line((door_center - hw, y, door_center + hw, y),
               fill=rgba(pal["stone_deep"]))
    # inner depth + rune glow along the opening lip
    for y in range(42, bottom):
        if theme == "lua":
            hw = half if y >= 58 else int((y - top) * half / 24)
        else:
            cy = 58
            hw = half if y >= cy else int(math.sqrt(max(0.0, half * half - (cy - y) ** 2)))
        if hw <= 0:
            continue
        d.point((door_center - hw + 1, y), fill=rgba(pal["magic_dark"]))
        d.point((door_center + hw - 1, y), fill=rgba(pal["magic_dark"]))
        if y % 8 == 0:
            d.point((door_center - hw + 2, y), fill=rgba(pal["magic"], 140))
            d.point((door_center + hw - 2, y), fill=rgba(pal["magic"], 140))


def compose_mockup(theme: str) -> Image.Image:
    pal = PALETTES[theme]
    W, H = 20, 12
    room = Image.new("RGBA", (W * TILE, H * TILE), (8, 9, 13, 255))
    walls_set = make_wall_set(theme)
    floors = make_floor_set(theme)
    wall_cells = set()
    for x in range(W):
        wall_cells.add((x, 0))
        wall_cells.add((x, H - 1))
    for y in range(H):
        wall_cells.add((0, y))
        wall_cells.add((W - 1, y))
    door_center = W * TILE // 2
    door_x = door_center // TILE
    for x in (door_x - 1, door_x):
        wall_cells.discard((x, 0))
    for y in range(H):
        for x in range(W):
            if (x, y) not in wall_cells:
                im = floors[f"floor_{(x * 5 + y * 3) % 3 + 1}"]
                room.alpha_composite(im, (x * TILE, y * TILE))
    for x, y in wall_cells:
        up = (x, y - 1) in wall_cells
        down = (x, y + 1) in wall_cells
        left = (x - 1, y) in wall_cells
        right = (x + 1, y) in wall_cells
        if not up:
            v = "top_left" if not left else ("top_right" if not right else "top_mid")
        elif not down:
            v = "bot_left" if not left else ("bot_right" if not right else "bot_mid")
        elif not left:
            v = "mid_left"
        elif not right:
            v = "mid_right"
        else:
            v = "mid_mid"
        room.alpha_composite(walls_set[v], (x * TILE, y * TILE))

    # Processional runner: a 3-tile-wide band of darker theme stone with a thin
    # language-metal edge. It gives the room an axis toward the doorway.
    runner_x0, runner_x1 = 9 * TILE, 12 * TILE
    for y in range(3, 10):
        for x in range(9, 12):
            room.alpha_composite(floors["floor_alt_b"], (x * TILE, y * TILE))
    d = ImageDraw.Draw(room)
    for x in (runner_x0 + 2, runner_x1 - 3):
        d.line((x, 3 * TILE, x, 10 * TILE), fill=rgba(pal["gold_dark"]))
        d.line((x + 1, 3 * TILE, x + 1, 10 * TILE), fill=rgba(pal["gold"] if theme == "lua" else pal["gold_dark"]))
    # Raised dais / threshold at the door.
    for y in (2, 3):
        for x in range(8, 13):
            room.alpha_composite(floors["floor_alt_a"], (x * TILE, y * TILE))
    d.line((8 * TILE + 2, 4 * TILE, 13 * TILE - 3, 4 * TILE), fill=rgba(pal["gold"]))
    d.line((8 * TILE + 3, 4 * TILE + 1, 13 * TILE - 4, 4 * TILE + 1),
           fill=rgba(pal["gold_dark"]))

    _draw_door_aperture(room, theme, door_center)
    door = architecture(theme)["door_frame_96x96"]
    put_sprite(room, door, (door_center - 48, 16))
    put_sprite(room, architecture(theme)["floor_medallion_64x64"],
               (door_center - 32, 7 * TILE - 8))
    # Four columns frame a shallow nave; capital/base silhouettes stay clear.
    for px, py in ((5 * TILE, 3 * TILE), (14 * TILE, 3 * TILE),
                   (5 * TILE, 7 * TILE), (14 * TILE, 7 * TILE)):
        put_sprite(room, architecture(theme)["pillar_32x96"], (px, py))
    for px in (1 * TILE + 8, 17 * TILE + 4):
        put_sprite(room, architecture(theme)["pilaster_32x64"], (px, 3 * TILE))
    put_sprite(room, architecture(theme)["masonry_panel_64x32"], (2 * TILE, 1 * TILE))
    put_sprite(room, architecture(theme)["masonry_panel_64x32"], (15 * TILE, 1 * TILE))
    put_sprite(room, architecture(theme)["sconce_16x32"], (2 * TILE + 8, 4 * TILE))
    put_sprite(room, architecture(theme)["sconce_16x32"], (16 * TILE + 8, 4 * TILE))

    light_magic = (118, 80, 214) if theme == "lua" else (44, 184, 164)
    light_gold = (156, 112, 42)
    lights = [
        (door_center, 4 * TILE + 6, 54, light_magic, 0.42),
        (door_center, 7 * TILE, 58, light_magic, 0.55),
        (2 * TILE + 16, 4 * TILE + 10, 50, light_magic, 0.65),
        (16 * TILE + 16, 4 * TILE + 10, 50, light_magic, 0.65),
        (door_center, 8 * TILE, 64, light_gold if theme == "lua" else light_magic, 0.46),
    ]
    return _apply_mockup_lighting(room, theme, lights)


def compose_mockup_preview(theme: str) -> Image.Image:
    pal = PALETTES[theme]
    native = compose_mockup(theme)
    room = upscale(native, 3)
    header = 94
    footer = 58
    W = room.width
    H = header + room.height + footer
    canvas = Image.new("RGBA", (W, H), PANEL_BG)
    d = ImageDraw.Draw(canvas)
    for x in range(0, W, 64):
        d.line((x, 0, x, H), fill=(20, 22, 30, 255))
    d.rectangle((0, 0, W, header - 2), fill=(16, 18, 25, 255))
    d.rectangle((0, header - 4, W, header - 1), fill=rgba(pal["magic"]))
    text(d, (28, 18), f"{pal['name'].upper()} DUNGEON - INTERIOR MOCKUP", size=17,
         color=rgba(pal["magic_hi"]), bold=True)
    text(d, (28, 45), f"{pal['title']} - assembled environment pass", size=30, bold=True)
    text(d, (W - 28, 22), "DESIGN DRAFT - NOT IN GAME", size=15,
         color=(230, 178, 108, 255), bold=True, anchor="ra")
    text(d, (W - 28, 44), "native 20x12 tiles - 3x nearest preview", size=13,
         color=MUTED, anchor="ra")
    canvas.alpha_composite(room, (0, header))
    # Footer scale reference + drafting note.
    footer_y = header + room.height + 12
    text(d, (28, footer_y + 2),
         "SCALE CHECK - 1 tile = 32 px - player sprite approx 20 x 32 px",
         size=14, color=MUTED)
    text(d, (W - 28, footer_y + 16),
         "Lighting is illustrative only; no light nodes, collision, resource or save data were changed.",
         size=13, color=(202, 166, 106, 255), anchor="ra")
    return canvas


def compose_comparison(theme: str) -> Image.Image:
    pal = PALETTES[theme]
    W, H = 1700, 980
    canvas = Image.new("RGBA", (W, H), PANEL_BG)
    d = ImageDraw.Draw(canvas)
    for x in range(0, W, 64):
        d.line((x, 0, x, H), fill=(20, 22, 30, 255))
    for y in range(0, H, 64):
        d.line((0, y, W, y), fill=(20, 22, 30, 255))
    d.rectangle((0, 0, W, 108), fill=(16, 18, 25, 255))
    d.rectangle((0, 104, W, 107), fill=rgba(pal["magic"]))
    text(d, (40, 18), f"{pal['name'].upper()} WAYPOINT -> DUNGEON", size=18,
         color=rgba(pal["magic_hi"]), bold=True)
    text(d, (40, 46), f"{pal['title']} - visual continuity", size=38, bold=True)
    text(d, (W - 40, 28), "SIDE-BY-SIDE REVIEW", size=16,
         color=(230, 178, 108, 255), bold=True, anchor="ra")
    text(d, (W - 40, 52), "reference left - proposed environment right", size=14,
         color=MUTED, anchor="ra")

    wp_name = "portal_lua_ancient_animated_sheet.png" if theme == "lua" else "portal_python_stonegate_animated_sheet.png"
    frame_w, frame_h = (192, 160) if theme == "lua" else (160, 128)
    wp = Image.open(WAYPOINTS / wp_name).convert("RGBA").crop((0, 0, frame_w, frame_h))
    wp = upscale(wp, 3)
    left_box = (60, 160, 60 + wp.width + 24, 160 + wp.height + 58)
    draw_panel(canvas, left_box, color=(12, 13, 18, 255),
               outline=(60, 58, 78, 255), radius=6)
    text(d, (80, 176), "WAYPOINT REFERENCE", size=16, color=MUTED, bold=True)
    put_sprite(canvas, wp, (72, 200))
    text(d, (left_box[0] + (left_box[2] - left_box[0]) // 2, left_box[3] + 22),
         "approved large portal draft", size=14, color=DIM, anchor="ma")

    interior = compose_mockup(theme)
    # Use a detailed crop around the door and one pillar.
    crop = interior.crop((2 * TILE, 0, 18 * TILE, 12 * TILE))
    crop = upscale(crop, 2)
    left = 640
    top = 160
    max_w = W - left - 60
    if crop.width > max_w:
        ratio = max_w / crop.width
        crop = crop.resize((int(crop.width * ratio), int(crop.height * ratio)),
                           Image.Resampling.NEAREST)
    draw_panel(canvas, (left - 12, top - 30, left + crop.width + 12,
                        top + crop.height + 24), PANEL_BG_2,
               outline=(52, 62, 70, 255), radius=6)
    text(d, (left, top - 26), "PROPOSED INTERIOR / MATERIAL PASS", size=16,
         color=MUTED, bold=True)
    put_sprite(canvas, crop, (left, top))

    # Palette and material callouts.
    y = 760
    text(d, (40, y), "PALETTE LINK", size=18, color=INK, bold=True)
    swatches = ["stone_shadow", "stone_base", "stone_light", "gold", "gold_hi",
                "magic_dark", "magic", "magic_hi", "magic_glow"]
    for i, key in enumerate(swatches):
        x = 40 + i * 72
        d.rectangle((x, y + 28, x + 62, y + 62), fill=rgba(pal[key]),
                    outline=(68, 72, 86, 255))
        text(d, (x, y + 68), pal[key], size=12, color=MUTED)
    note = ("Lua keeps the waypoint's warm charcoal masonry, thin gold rails and violet crescent magic. "
            "Interior forms are tall and pointed."
            if theme == "lua" else
            "Python keeps the waypoint's cool blue-grey masonry, brass bands and teal energy. "
            "Interior forms are heavy, square and rounded.")
    text(d, (40, y + 118), note, size=17, color=INK)
    text(d, (40, y + 150), "The tileset is a design draft only; no production assets were imported or changed.",
         size=14, color=(206, 168, 106, 255))
    return canvas


def compose_palette_materials() -> Image.Image:
    W, H = 1900, 1160
    canvas = Image.new("RGBA", (W, H), PANEL_BG)
    d = ImageDraw.Draw(canvas)
    for x in range(0, W, 64):
        d.line((x, 0, x, H), fill=(20, 22, 30, 255))
    for y in range(0, H, 64):
        d.line((0, y, W, y), fill=(20, 22, 30, 255))
    d.rectangle((0, 0, W, 108), fill=(16, 18, 25, 255))
    d.rectangle((0, 104, W, 107), fill=(128, 190, 176, 255))
    text(d, (40, 18), "DUNGEON MATERIAL BOARDS", size=18,
         color=(146, 220, 201, 255), bold=True)
    text(d, (40, 46), "Two language identities, one SandEE palette family", size=36,
         bold=True)
    text(d, (W - 40, 30), "PALETTE / MATERIAL REFERENCE", size=16,
         color=(232, 180, 110, 255), bold=True, anchor="ra")
    text(d, (W - 40, 54), "draft only - not in game", size=14, color=MUTED, anchor="ra")

    columns = [("lua", 40), ("python", W // 2 + 20)]
    for theme, x0 in columns:
        pal = PALETTES[theme]
        accent = pal["magic_hi"] if theme == "lua" else pal["magic_hi"]
        d.rectangle((x0, 132, x0 + W // 2 - 60, 148), fill=rgba(accent))
        text(d, (x0, 158), f"{pal['name'].upper()} - {pal['title']}", size=25, bold=True)
        text(d, (x0, 190), "MATERIALS", size=14, color=MUTED, bold=True)
        material = ("dark basalt / violet glow / etched gold / cold crescent-blue glints"
                    if theme == "lua" else
                    "blue-grey ashlar / teal glow / brass bands / green moss weathering")
        text(d, (x0, 212), material, size=14, color=INK)
        # Palette grid.
        swatches = ["stone_shadow", "stone_dark", "stone_base", "stone_light",
                    "stone_hi", "floor_base", "floor_light", "floor_shadow",
                    "gold_dark", "gold", "gold_hi", "magic_deep", "magic",
                    "magic_hi", "magic_glow", "moss"]
        for i, key in enumerate(swatches):
            sx = x0 + (i % 4) * 130
            sy = 256 + (i // 4) * 86
            d.rectangle((sx, sy, sx + 112, sy + 48), fill=rgba(pal[key]),
                        outline=(73, 78, 91, 255))
            text(d, (sx, sy + 54), pal[key], size=12, color=INK)
            text(d, (sx, sy + 69), key.replace("_", " "), size=11, color=DIM)
        # Material chips: actual wall and floor crops.
        walls = make_wall_set(theme)
        floors = make_floor_set(theme)
        chips = [
            ("WALL TOP", walls["top_mid"]),
            ("WALL BASE", walls["bot_mid"]),
            ("FLOOR", floors["floor_1"]),
            ("FLOOR ALT", floors["floor_alt_a"]),
        ]
        cy = 640
        text(d, (x0, cy - 28), "MATERIAL CHIPS / NATIVE 32 PX", size=14, color=MUTED, bold=True)
        for i, (label, img) in enumerate(chips):
            cx = x0 + i * 150
            d.rectangle((cx, cy, cx + 134, cy + 134), fill=(11, 12, 17, 255),
                        outline=(52, 58, 70, 255))
            bg = checker((128, 128), 8, (28, 30, 38, 255), (38, 41, 50, 255))
            put_sprite(canvas, bg, (cx + 3, cy + 3))
            put_sprite(canvas, upscale(img, 4), (cx + 3, cy + 3))
            text(d, (cx, cy + 142), label, size=12, color=MUTED)
        # Architectural motif swatch and notes.
        cy = 830
        text(d, (x0, cy), "MOTIF LANGUAGE", size=14, color=MUTED, bold=True)
        if theme == "lua":
            motif = make_medallion(theme)
            put_sprite(canvas, upscale(motif, 2), (x0, cy + 28))
            notes = [
                "pointed arch / crescent / concentric rune ring",
                "tall clustered supports; fine gold rails",
                "large processional flagstones with sparse carving",
            ]
        else:
            motif = architecture(theme)["floor_medallion_64x64"]
            put_sprite(canvas, upscale(motif, 2), (x0, cy + 28))
            notes = [
                "round arch / diamond shard / brass brackets",
                "heavy square supports; wide stepped bases",
                "regular foundry slabs with teal aggregate",
            ]
        for i, line in enumerate(notes):
            text(d, (x0 + 150, cy + 38 + i * 29), "- " + line, size=14, color=INK)
        # Colour block notes at bottom.
        text(d, (x0, 1030),
             "gold remains the common family thread; each language owns the light colour.",
             size=13, color=DIM)
    text(d, (40, H - 30),
         "Draft only - no production asset, scene, script, collision, lighting or save data was changed.",
         size=14, color=(204, 168, 108, 255))
    return canvas


def compose_organization() -> Image.Image:
    W, H = 1800, 1200
    canvas = Image.new("RGBA", (W, H), PANEL_BG)
    d = ImageDraw.Draw(canvas)
    for x in range(0, W, 64):
        d.line((x, 0, x, H), fill=(20, 22, 30, 255))
    for y in range(0, H, 64):
        d.line((0, y, W, y), fill=(20, 22, 30, 255))
    d.rectangle((0, 0, W, 108), fill=(16, 18, 25, 255))
    d.rectangle((0, 104, W, 107), fill=(118, 196, 184, 255))
    text(d, (40, 18), "PROPOSED TILESET ORGANIZATION", size=18,
         color=(144, 218, 199, 255), bold=True)
    text(d, (40, 46), "Based on the existing 32 px dungeon TileSet", size=38, bold=True)
    text(d, (W - 40, 28), "DIMENSIONS / ATLAS PLAN", size=16,
         color=(230, 178, 108, 255), bold=True, anchor="ra")
    text(d, (W - 40, 52), "draft only - no import path", size=14, color=MUTED, anchor="ra")

    def section(x, y, title, lines, color):
        draw_panel(canvas, (x, y, x + 520, y + 200), PANEL_BG_2,
                   outline=(50, 58, 70, 255), radius=6)
        text(d, (x + 20, y + 18), title, size=17, color=color, bold=True)
        for i, line in enumerate(lines):
            text(d, (x + 20, y + 52 + i * 25), line, size=14, color=MUTED)

    section(40, 150, "WALL FACE SET", [
        "8 primary autotile sprites + 1 buried center",
        "32x32 px each - black mortar seams - 1 px bevel",
        "after approval: 9 cells in one row of the atlas",
        "alternates: 2x 32x32 per theme",
    ], (180, 200, 235, 255))
    section(600, 150, "FLOOR SET", [
        "3 primary variants + 2 alternates",
        "32x32 px each - no smoothing",
        "4 edge strips + 4 corner transitions",
        "edge strips keep a 1 px floor lip",
    ], (180, 200, 235, 255))
    section(1160, 150, "ARCHITECTURE PROPS", [
        "pillar 32x96 - pilaster 32x64",
        "door frame 96x96 - blind arch 96x64",
        "masonry panel 64x32 - sconce 16x32",
        "floor medallion 64x64",
    ], (180, 200, 235, 255))

    # Atlas diagrams.
    y = 420
    text(d, (40, y), "PROPOSED ATLAS LAYOUT", size=22, color=INK, bold=True)
    text(d, (40, y + 30), "Primary tile cells can replace the existing wall/floor entries; architecture stays a separate prop sheet.",
         size=15, color=MUTED)
    def cell(x, y, label, color, w=1, h=1, size=26):
        d.rectangle((x, y, x + w * size, y + h * size), fill=color,
                    outline=(85, 90, 102, 255))
        text(d, (x + 3, y + 3), label, size=10, color=(12, 14, 18, 255))
    # Wall atlas
    x0, y0 = 60, 520
    text(d, (x0, y0 - 26), "WALL ATLAS - 11 x 1 cells", size=15, color=MUTED, bold=True)
    names = ["TL", "TM", "TR", "ML", "MM", "MR", "BL", "BM", "BR", "ALT A", "ALT B"]
    for i, n in enumerate(names):
        cell(x0 + i * 30, y0, n, (80 + i * 7, 103 + i * 4, 113, 255), size=28)
    # Floor atlas
    y0 = 650
    text(d, (x0, y0 - 26), "FLOOR ATLAS - 13 x 1 cells", size=15, color=MUTED, bold=True)
    fnames = ["F1", "F2", "F3", "ALT A", "ALT B", "N", "E", "S", "W", "NW", "NE", "SW", "SE"]
    for i, n in enumerate(fnames):
        cell(x0 + i * 30, y0, n, (70 + i * 3, 86 + i * 3, 97, 255), size=28)
    # Architecture
    x0, y0 = 60, 790
    text(d, (x0, y0 - 26), "ARCHITECTURE PROP SHEET - native sizes", size=15, color=MUTED, bold=True)
    props = [("PILLAR", 32, 96), ("PILASTER", 32, 64), ("DOOR", 96, 96),
             ("BLIND ARCH", 96, 64), ("PANEL", 64, 32), ("SCONCE", 16, 32),
             ("MEDALLION", 64, 64)]
    xx = x0
    for label, pw, ph in props:
        sc = min(0.8, 130 / max(pw, ph))
        ww, hh = int(pw * sc), int(ph * sc)
        d.rectangle((xx, y0 + 20 + (120 - hh), xx + ww, y0 + 140),
                    fill=(45, 58, 61, 255), outline=(79, 98, 96, 255))
        text(d, (xx, y0 + 148), f"{label} {pw}x{ph}", size=11, color=MUTED)
        xx += max(ww, 100) + 25

    # Notes.
    notes = [
        "RECOMMENDED TILESET FLOW",
        "1. Replace the existing 3x3 wall face cells with the themed primary set.",
        "2. Keep floor variants deterministic exactly as today; add edge variants only when a room platform needs them.",
        "3. Ship large architecture as a separate props layer; do not bake pillars/arches into the 32 x 32 atlas.",
        "4. Review at the in-game 32 px scale before importing or changing collision.",
    ]
    y = 1000
    text(d, (40, y), notes[0], size=18, color=(144, 218, 199, 255), bold=True)
    for i, line in enumerate(notes[1:]):
        text(d, (40, y + 30 + i * 25), line, size=14, color=MUTED)
    text(d, (40, H - 34),
         "No production tile, resource, scene, script, lighting or save data was modified; this is an atlas proposal only.",
         size=14, color=(208, 170, 108, 255))
    return canvas


def compose_existing_reference() -> Image.Image:
    src = Image.open(PROJECT / "sprites/dungeon/SandEE_alpha_dungeontilesets.png").convert("RGBA")
    wall_xy = {
        "TOP LEFT": (64, 0), "TOP MID": (96, 0), "TOP RIGHT": (128, 0),
        "MID LEFT": (64, 32), "MID RIGHT": (128, 32),
        "BOT LEFT": (64, 64), "BOT MID": (96, 64), "BOT RIGHT": (128, 64),
    }
    floor_xy = [("FLOOR 1", (192, 32)), ("FLOOR 2", (224, 32)),
                ("FLOOR 3", (256, 32))]
    W, H = 1800, 1120
    canvas = Image.new("RGBA", (W, H), PANEL_BG)
    d = ImageDraw.Draw(canvas)
    for x in range(0, W, 64):
        d.line((x, 0, x, H), fill=(20, 22, 30, 255))
    for y in range(0, H, 64):
        d.line((0, y, W, y), fill=(20, 22, 30, 255))
    d.rectangle((0, 0, W, 108), fill=(16, 18, 25, 255))
    d.rectangle((0, 104, W, 107), fill=(118, 150, 170, 255))
    text(d, (40, 18), "EXISTING STYLE REFERENCE", size=18,
         color=(156, 190, 206, 255), bold=True)
    text(d, (40, 46), "Shared 32 px dungeon TileSet - inspected, not modified", size=35, bold=True)
    text(d, (W - 40, 28), "PRODUCTION REFERENCE", size=15,
         color=(230, 178, 108, 255), bold=True, anchor="ra")
    text(d, (W - 40, 50), "read-only", size=13, color=MUTED, anchor="ra")
    text(d, (40, 132),
         "The project currently ships ONE shared dungeon tile sheet. No language-specific Lua/Python dungeon TileSet was found.",
         size=16, color=INK)
    text(d, (40, 158),
         "Source: SandEE_alpha_dungeontilesets.png (512x512) - 32x32 wall/floor regions; 8 wall variants; 3 floor variants; 32x32 altar/prop icons.",
         size=14, color=MUTED)

    text(d, (40, 220), "EXISTING WALL VARIANTS / 4x", size=16, color=MUTED, bold=True)
    for i, (label, xy) in enumerate(wall_xy.items()):
        tile = src.crop((xy[0], xy[1], xy[0] + 32, xy[1] + 32))
        x = 40 + i * 150
        y = 254
        d.rectangle((x, y, x + 134, y + 134), fill=(11, 12, 17, 255),
                    outline=(54, 60, 72, 255))
        bg = checker((128, 128), 8, (29, 31, 39, 255), (40, 43, 52, 255))
        put_sprite(canvas, bg, (x + 3, y + 3))
        put_sprite(canvas, upscale(tile, 4), (x + 3, y + 3))
        text(d, (x, y + 143), label, size=12, color=MUTED)
    text(d, (40, 470), "EXISTING FLOOR VARIANTS / 4x", size=16, color=MUTED, bold=True)
    for i, (label, xy) in enumerate(floor_xy):
        tile = src.crop((xy[0], xy[1], xy[0] + 32, xy[1] + 32))
        x = 40 + i * 150
        y = 504
        d.rectangle((x, y, x + 134, y + 134), fill=(11, 12, 17, 255),
                    outline=(54, 60, 72, 255))
        bg = checker((128, 128), 8, (29, 31, 39, 255), (40, 43, 52, 255))
        put_sprite(canvas, bg, (x + 3, y + 3))
        put_sprite(canvas, upscale(tile, 4), (x + 3, y + 3))
        text(d, (x, y + 143), label, size=12, color=MUTED)

    # Assembled reference patch.
    px, py = 640, 470
    patch = Image.new("RGBA", (9 * 32, 5 * 32), TRANSPARENT)
    for yy in range(5):
        for xx in range(9):
            if xx in (0, 8) or yy in (0, 4):
                continue
            fx, fy = floor_xy[(xx + yy * 2) % 3][1]
            patch.alpha_composite(src.crop((fx, fy, fx + 32, fy + 32)), (xx * 32, yy * 32))
    for yy in range(5):
        for xx in range(9):
            if not (xx in (0, 8) or yy in (0, 4)):
                continue
            up = yy > 0 and (xx in (0, 8) or yy - 1 in (0, 4))
            down = yy < 4 and (xx in (0, 8) or yy + 1 in (0, 4))
            left = xx > 0 and (yy in (0, 4) or xx - 1 in (0, 8))
            right = xx < 8 and (yy in (0, 4) or xx + 1 in (0, 8))
            if yy == 0:
                key = "TOP LEFT" if xx == 0 else ("TOP RIGHT" if xx == 8 else "TOP MID")
            elif yy == 4:
                key = "BOT LEFT" if xx == 0 else ("BOT RIGHT" if xx == 8 else "BOT MID")
            elif xx == 0:
                key = "MID LEFT"
            elif xx == 8:
                key = "MID RIGHT"
            else:
                continue
            xy = wall_xy[key]
            patch.alpha_composite(src.crop((xy[0], xy[1], xy[0] + 32, xy[1] + 32)), (xx * 32, yy * 32))
    draw_panel(canvas, (px - 12, py - 36, px + 9 * 32 * 2 + 12,
                        py + 5 * 32 * 2 + 38), PANEL_BG_2,
               outline=(55, 63, 75, 255), radius=5)
    text(d, (px, py - 30), "EXISTING WALL + FLOOR ASSEMBLY / 2x", size=15,
         color=MUTED, bold=True)
    put_sprite(canvas, upscale(patch, 2), (px, py))
    text(d, (640, 810),
         "The proposal keeps this 3x3 face-set logic, 32 px scale, black mortar and restrained",
         size=14, color=INK)
    text(d, (640, 834),
         "pixel density. It replaces the single grey material with two language-specific directions.",
         size=14, color=INK)

    # Foot line.
    text(d, (40, 880), "WHAT THE REVISION PRESERVES", size=18, color=INK, bold=True)
    notes = [
        "- 32 px grid and 1 px dark mortar/outline language",
        "- 8-variant wall face set and deterministic floor variation",
        "- sparse decoration budget so gameplay objects remain readable",
        "- gold as the shared metal; language-specific magic light",
    ]
    for i, line in enumerate(notes):
        text(d, (40, 918 + i * 30), line, size=15, color=MUTED)
    text(d, (40, H - 34),
         "Production reference is shown for inspection only; this file does not alter or import the shared TileSet.",
         size=14, color=(204, 168, 108, 255))
    return canvas


def build():
    for d in (SPRITES, PREVIEWS):
        d.mkdir(parents=True, exist_ok=True)
    for theme in ("lua", "python"):
        save_assets(theme)
        pal = PALETTES[theme]
        save_palette_swatch(SPRITES / f"{theme}_palette.png", pal)
        sheet = compose_presentation(theme)
        sheet.save(PREVIEWS / f"{theme}_tiles_and_architecture.png")
        mock = compose_mockup(theme)
        mock.save(SPRITES / f"{theme}_interior_mockup_native.png")
        compose_mockup_preview(theme).save(PREVIEWS / f"{theme}_interior_mockup.png")
        comp = compose_comparison(theme)
        comp.save(PREVIEWS / f"{theme}_waypoint_comparison.png")
    org = compose_organization()
    org.save(PREVIEWS / "tileset_organization.png")
    compose_existing_reference().save(PREVIEWS / "existing_style_reference.png")
    palette_board = compose_palette_materials()
    palette_board.save(PREVIEWS / "palette_materials.png")
    print("Draft assets written under", BASE)


if __name__ == "__main__":
    build()
