from __future__ import annotations

# Implementation export for the approved dungeon art direction.
# Reads only the draft outputs in this folder and writes new production assets
# under SandEEAlpha/sprites/dungeon/<theme>/. Existing production assets are
# never overwritten.

import math
import json
import shutil
from pathlib import Path

from PIL import Image, ImageDraw

BASE = Path(__file__).resolve().parent
DRAFT_SPRITES = BASE / "sprites"
PROJECT = BASE.parent.parent / "SandEEAlpha"
OUT_ROOT = PROJECT / "sprites" / "dungeon"

TILE = 32
WALL_ORDER = [
    "top_left", "top_mid", "top_right",
    "mid_left", "mid_mid", "mid_right",
    "bot_left", "bot_mid", "bot_right",
    "alt_rune", "alt_weathered",
]
FLOOR_ORDER = ["floor_1", "floor_2", "floor_3", "floor_alt_a", "floor_alt_b"]
ARCH_ORDER = ["pillar_32x96", "pilaster_32x64", "door_frame_96x96",
              "blind_arch_96x64", "masonry_panel_64x32"]

PALETTES = {
    "lua": {
        "magic": (128, 100, 224),
        "magic_hi": (192, 166, 255),
        "magic_glow": (240, 232, 255),
        "blue": (127, 208, 255),
        "gold": (192, 154, 85),
        "gold_hi": (241, 214, 146),
    },
    "python": {
        "magic": (47, 169, 160),
        "magic_hi": (125, 240, 223),
        "magic_glow": (216, 255, 247),
        "blue": (77, 120, 196),
        "gold": (192, 154, 85),
        "gold_hi": (241, 214, 152),
    },
}


def save_packed(theme: str) -> None:
    out = OUT_ROOT / theme
    out.mkdir(parents=True, exist_ok=True)
    # Wall atlas: 11 x 32 px cells.
    wall_sheet = Image.new("RGBA", (len(WALL_ORDER) * TILE, TILE), (0, 0, 0, 0))
    for i, name in enumerate(WALL_ORDER):
        im = Image.open(DRAFT_SPRITES / theme / f"wall_{name}.png").convert("RGBA")
        wall_sheet.alpha_composite(im, (i * TILE, 0))
    wall_sheet.save(out / "walls.png")
    # Floor atlas: five deterministic variants.
    floor_sheet = Image.new("RGBA", (len(FLOOR_ORDER) * TILE, TILE), (0, 0, 0, 0))
    for i, name in enumerate(FLOOR_ORDER):
        im = Image.open(DRAFT_SPRITES / theme / f"{name}.png").convert("RGBA")
        floor_sheet.alpha_composite(im, (i * TILE, 0))
    floor_sheet.save(out / "floors.png")
    # Static architecture.
    for name in ARCH_ORDER:
        src = DRAFT_SPRITES / theme / f"{name}.png"
        shutil.copyfile(src, out / f"{name}.png")


def _is_magic_pixel(p: tuple[int, int, int, int], theme: str) -> bool:
    r, g, b, a = p
    if a < 24:
        return False
    if theme == "lua":
        return b > r + 12 and b > 45
    return g > r + 8 and b > r - 4 and g > 45


def _is_gold_pixel(p: tuple[int, int, int, int]) -> bool:
    r, g, b, a = p
    return a > 40 and r > 70 and g > 45 and b < g - 8 and r > b + 24


def build_sconce_sheet(theme: str) -> None:
    out = OUT_ROOT / theme
    src = Image.open(DRAFT_SPRITES / theme / "sconce_16x32.png").convert("RGBA")
    w, h = src.size
    frames = []
    phases = [0.0, 0.42, 0.90, 1.35, 0.62, 1.08, 0.28, 0.75]
    bbox_magic = None
    xs, ys = [], []
    for y in range(h):
        for x in range(w):
            if _is_magic_pixel(src.getpixel((x, y)), theme):
                xs.append(x)
                ys.append(y)
    if xs:
        bbox_magic = (min(xs), min(ys), max(xs), max(ys))
    rng = math.sin
    for i, phase in enumerate(phases):
        f = src.copy()
        d = ImageDraw.Draw(f)
        # Pulse the magic body without touching the metal bracket or stone.
        bright = 0.78 + 0.30 * (0.5 + 0.5 * rng(phase * math.pi * 2.0))
        for y in range(h):
            for x in range(w):
                p = src.getpixel((x, y))
                if _is_magic_pixel(p, theme):
                    r, g, b, a = p
                    f.putpixel((x, y), (
                        min(255, int(r * bright)),
                        min(255, int(g * bright)),
                        min(255, int(b * bright)),
                        a,
                    ))
        if bbox_magic is not None:
            bx0, by0, bx1, by1 = bbox_magic
            cx = (bx0 + bx1) // 2
            # Two small sparks around the top of the crystal; they travel with
            # the pulse but stay within the 16 px sprite.
            sx1 = cx + (-3 if i % 4 in (0, 1) else 3)
            sy1 = max(1, by0 - 1 - (i % 2))
            sx2 = cx + (3 if i % 3 == 0 else -2)
            sy2 = max(1, by0 + 2 + (i % 3))
            for (sx, sy, c) in ((sx1, sy1, PALETTES[theme]["magic_hi"]),
                                (sx2, sy2, PALETTES[theme]["blue"])):
                if 0 <= sx < w and 0 <= sy < h:
                    d.point((sx, sy), fill=(*c, 220))
        frames.append(f)
    sheet = Image.new("RGBA", (w * 8, h), (0, 0, 0, 0))
    for i, f in enumerate(frames):
        sheet.alpha_composite(f, (i * w, 0))
    sheet.save(out / "sconce_sheet.png")


def _diamond_point(t: float, cx: int, cy: int, radius: int) -> tuple[int, int]:
    # t in [0,4); trace the four diamond edges.
    edge = int(t) % 4
    f = t - math.floor(t)
    pts = [(cx, cy - radius), (cx + radius, cy),
           (cx, cy + radius), (cx - radius, cy)]
    a = pts[edge]
    b = pts[(edge + 1) % 4]
    return (int(a[0] + (b[0] - a[0]) * f),
            int(a[1] + (b[1] - a[1]) * f))


def build_medallion_sheet(theme: str) -> None:
    out = OUT_ROOT / theme
    src = Image.open(DRAFT_SPRITES / theme / "floor_medallion_64x64.png").convert("RGBA")
    w, h = src.size
    frames = []
    for i in range(8):
        f = src.copy()
        d = ImageDraw.Draw(f)
        phase = i / 8.0
        bright = 0.94 + 0.13 * math.sin(phase * math.tau)
        for y in range(h):
            for x in range(w):
                p = src.getpixel((x, y))
                if _is_magic_pixel(p, theme):
                    r, g, b, a = p
                    f.putpixel((x, y), (min(255, int(r * bright)),
                                        min(255, int(g * bright)),
                                        min(255, int(b * bright)), a))
                elif _is_gold_pixel(p) and i in (1, 4, 6):
                    r, g, b, a = p
                    f.putpixel((x, y), (min(255, int(r * 1.06)),
                                        min(255, int(g * 1.04)),
                                        min(255, int(b * 1.02)), a))
        cx, cy = w // 2, h // 2
        if theme == "lua":
            radius = 22
            ang = phase * math.tau
            sx = int(cx + math.cos(ang) * radius)
            sy = int(cy + math.sin(ang) * radius)
        else:
            sx, sy = _diamond_point(phase * 4.0, cx, cy, 24)
        d.rectangle((sx, sy, sx + 1, sy + 1), fill=(*PALETTES[theme]["magic_hi"], 230))
        d.point((sx, sy), fill=(*PALETTES[theme]["magic_glow"], 255))
        # Counter-rotating single mote for depth, kept sparse.
        if i % 2 == 0:
            ax = phase * -math.tau + math.pi
            tx = int(cx + math.cos(ax) * 17)
            ty = int(cy + math.sin(ax) * 17)
            d.point((tx, ty), fill=(*PALETTES[theme]["blue"], 180))
        frames.append(f)
    sheet = Image.new("RGBA", (w * 8, h), (0, 0, 0, 0))
    for i, f in enumerate(frames):
        sheet.alpha_composite(f, (i * w, 0))
    sheet.save(out / "medallion_sheet.png")


def write_manifest() -> None:
    rows = {}
    for theme in ("lua", "python"):
        rows[theme] = {
            "wall_sheet": f"res://sprites/dungeon/{theme}/walls.png",
            "wall_cells": WALL_ORDER,
            "wall_cell_size": [32, 32],
            "floor_sheet": f"res://sprites/dungeon/{theme}/floors.png",
            "floor_cells": FLOOR_ORDER,
            "floor_cell_size": [32, 32],
            "pillar": f"res://sprites/dungeon/{theme}/pillar_32x96.png",
            "pilaster": f"res://sprites/dungeon/{theme}/pilaster_32x64.png",
            "door_frame": f"res://sprites/dungeon/{theme}/door_frame_96x96.png",
            "blind_arch": f"res://sprites/dungeon/{theme}/blind_arch_96x64.png",
            "masonry_panel": f"res://sprites/dungeon/{theme}/masonry_panel_64x32.png",
            "sconce_sheet": f"res://sprites/dungeon/{theme}/sconce_sheet.png",
            "sconce_frame_size": [16, 32],
            "sconce_frames": 8,
            "medallion_sheet": f"res://sprites/dungeon/{theme}/medallion_sheet.png",
            "medallion_frame_size": [64, 64],
            "medallion_frames": 8,
            "fps": 10.0,
        }
    (OUT_ROOT / "themed_runtime_manifest.json").write_text(
        json.dumps(rows, indent=2), encoding="utf-8")


def main() -> None:
    for theme in ("lua", "python"):
        save_packed(theme)
        build_sconce_sheet(theme)
        build_medallion_sheet(theme)
    write_manifest()
    print("Wrote themed runtime assets under", OUT_ROOT)


if __name__ == "__main__":
    main()
