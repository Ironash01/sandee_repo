"""Build the in-game four-direction mob sheets for the Bestiary creatures.

The concept art lives in this draft folder.  This script reads the approved
concept sprites as the south/front view, derives north and side silhouettes in
the same limited palette, and writes one gameplay sheet per mob plus an icon
used by the Bestiary tab.

Output:
    SandEEAlpha/sprites/mobs/bestiary/<mob>_sheet.png
    SandEEAlpha/sprites/mobs/bestiary/<mob>_icon.png
    design_drafts/sprite_concepts_2026/previews/directional_sheets.png

Sheet layout (no spacing):
    rows: south, north, east, west
    columns: idle, walk_a, walk_b

This is an art-generation utility only. The game loads the PNG sheets; it does
not run this script.
"""
from __future__ import annotations

import importlib.util
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont, ImageOps

ROOT = Path(__file__).resolve().parent
REPO = ROOT.parent.parent
CONCEPT = ROOT / "build_sprite_concepts.py"
OUT = REPO / "SandEEAlpha" / "sprites" / "mobs" / "bestiary"
PREVIEW = ROOT / "previews" / "directional_sheets.png"
OUT.mkdir(parents=True, exist_ok=True)

spec = importlib.util.spec_from_file_location("concept_art", CONCEPT)
m = importlib.util.module_from_spec(spec)
assert spec.loader is not None
sys.modules[spec.name] = m
spec.loader.exec_module(m)

OUTLINE = m.OUTLINE
INK = m.INK
WHITE = m.WHITE
CREAM = m.CREAM
CREAM_HI = m.CREAM_HI
GOLD = m.GOLD
GOLD_HI = m.GOLD_HI
GOLD_DK = m.GOLD_DK
TEAL = m.TEAL
TEAL_HI = m.TEAL_HI
TEAL_DK = m.TEAL_DK
VIOLET = m.VIOLET
VIOLET_HI = m.VIOLET_HI
VIOLET_DK = m.VIOLET_DK
RUST = m.RUST
RUST_HI = m.RUST_HI
RUST_DK = m.RUST_DK
MOSS = m.MOSS
MOSS_HI = m.MOSS_HI
MOSS_DK = m.MOSS_DK
AMBER = m.AMBER
AMBER_HI = m.AMBER_HI
BONE = m.BONE
BONE_HI = m.BONE_HI
BLUE = m.BLUE
BLUE_HI = m.BLUE_HI
BLUE_DK = m.BLUE_DK
BRASS = m.BRASS
BRASS_HI = m.BRASS_HI
BRASS_DK = m.BRASS_DK
CHAR = m.CHAR
CHAR_HI = m.CHAR_HI
SKIN_Z = m.SKIN_Z
SKIN_Z_HI = m.SKIN_Z_HI
SKIN_Z_DK = m.SKIN_Z_DK


def new(w: int, h: int) -> Image.Image:
    return Image.new("RGBA", (w, h), (0, 0, 0, 0))


def mirror(im: Image.Image) -> Image.Image:
    return ImageOps.mirror(im)


def shift(im: Image.Image, dx: int, dy: int) -> Image.Image:
    out = new(*im.size)
    out.alpha_composite(im, (dx, dy))
    return out


WALK_FRAMES: int = 4

def generic_walk_frames(base: Image.Image) -> list[Image.Image]:
    """Four-frame body cycle used by slimes, robes and floating constructs.

    The bottom band stays planted while the upper silhouette breathes and
    sways. Legged creatures override this with a dedicated gait below.
    """
    out: list[Image.Image] = []
    body_h = max(4, base.height - 8)
    upper = base.crop((0, 0, base.width, body_h))
    lower = base.crop((0, body_h, base.width, base.height))
    offsets = [(0, 0), (1, -1), (0, 0), (-1, -1)]
    for dx, dy in offsets:
        frame = new(*base.size)
        frame.alpha_composite(upper, (dx, dy))
        frame.alpha_composite(lower, (0, body_h))
        out.append(frame)
    return out


# ?? Emberfox proper four-frame gait ???????????????????????????????????
# The idle portrait is a sitting kit. Walking switches to a standing pose:
# four separate legs alternate through a contact/pass cycle while the upper
# body and tail bob. East/west use the side profile; south/north use the
# face/back head.
_EMBER_LEG_PHASES: list[list[tuple[int, int]]] = [
    [(-1, 0), (1, 0), (1, 0), (-1, 0)],
    [(0, -1), (0, 0), (0, 0), (0, -1)],
    [(1, 0), (-1, 0), (-1, 0), (1, 0)],
    [(0, 0), (0, -1), (0, -1), (0, 0)],
]
_EMBER_BOB = [0, -1, 0, -1]


def _emberfox_leg(d: ImageDraw.ImageDraw, x: int, y: int, lift: int = 0) -> None:
    # Four-pixel leg with a cream paw; the upper half sits behind the torso.
    d.rectangle((x, y + lift, x + 4, 45), fill=RUST_DK, outline=OUTLINE)
    d.rectangle((x, 42 + lift, x + 5, 46), fill=CREAM, outline=OUTLINE)
    d.point((x + 1, 43 + lift), fill=CREAM_HI)


def emberfox_walk_frame(direction: str, phase: int) -> Image.Image:
    im = new(48, 48)
    d = ImageDraw.Draw(im)
    if direction == "south":
        source = m.draw_emberfox(0)
    elif direction == "north":
        source = emberfox_north()
    elif direction == "east":
        source = emberfox_side()
    else:
        # Defensive fallback; walk_frames_for mirrors the east cycle for west.
        source = emberfox_side()

    bob = _EMBER_BOB[phase % 4]
    gait = _EMBER_LEG_PHASES[phase % 4]
    if direction in ("south", "north"):
        leg_x = (12, 20, 28, 35)
    else:
        leg_x = (11, 19, 29, 36)

    # Legs are drawn first so the torso hides their roots.
    for i, x in enumerate(leg_x):
        dx, lift = gait[i]
        _emberfox_leg(d, x + dx, 31 + bob, lift)
    # Rebuild the standing lower torso for every facing. The source crop ends
    # above the old sitting legs, so without this the four new legs look like
    # disconnected stilts.
    if direction in ("east", "west"):
        d.ellipse((9, 27 + bob, 37, 40 + bob), fill=RUST, outline=OUTLINE)
        d.ellipse((14, 31 + bob, 31, 39 + bob), fill=CREAM_HI)
    else:
        d.ellipse((10, 27 + bob, 36, 40 + bob), fill=RUST, outline=OUTLINE)
        if direction == "south":
            d.ellipse((15, 31 + bob, 31, 39 + bob), fill=CREAM_HI)
        else:
            d.ellipse((15, 31 + bob, 31, 39 + bob), fill=RUST_HI)

    top_h = 33
    top = source.crop((0, 0, 48, top_h))
    im.alpha_composite(top, (0, bob))
    # Restore the side chest/scarf edge above the new standing underline.
    if direction in ("east", "west"):
        d.line((18, 23 + bob, 33, 26 + bob), fill=TEAL, width=2)
        d.rectangle((17, 24 + bob, 31, 26 + bob), fill=TEAL)
    return m.outline_image(im)


_MOSS_LEG_PHASES: list[list[tuple[int, int]]] = [
    [(-1, 0), (1, 0), (1, 0), (-1, 0)],
    [(0, -1), (0, 0), (0, 0), (0, -1)],
    [(1, 0), (-1, 0), (-1, 0), (1, 0)],
    [(0, 0), (0, -1), (0, -1), (0, 0)],
]


def _mossback_leg(d: ImageDraw.ImageDraw, x: int, phase: int, index: int) -> None:
    dx, lift = _MOSS_LEG_PHASES[phase % 4][index]
    d.rectangle((x + dx, 23 + lift, x + 2 + dx, 28), fill=MOSS_DK, outline=OUTLINE)
    d.rectangle((x + dx, 27, x + 3 + dx, 28), fill=MOSS, outline=OUTLINE)


def mossback_walk_frame(direction: str, phase: int) -> Image.Image:
    im = new(32, 32)
    d = ImageDraw.Draw(im)
    bob = [0, -1, 0, -1][phase % 4]
    if direction in ("south", "north"):
        for i, x in enumerate((7, 13, 19, 25)):
            _mossback_leg(d, x, phase, i)
        d.ellipse((5, 6 + bob, 27, 24 + bob), fill=MOSS, outline=OUTLINE)
        d.ellipse((8, 8 + bob, 21, 15 + bob), fill=MOSS_HI)
        d.arc((7, 10 + bob, 25, 24 + bob), 195, 345, fill=MOSS_DK, width=2)
        d.rectangle((21, 10 + bob, 22, 11 + bob), fill=GOLD_HI)
        d.rectangle((9, 17 + bob, 10, 18 + bob), fill=MOSS_DK)
        d.rectangle((23, 15 + bob, 24, 16 + bob), fill=MOSS_DK)
        d.rectangle((15, 5 + bob, 16, 8 + bob), fill=CREAM)
        d.rectangle((14, 3 + bob, 18, 5 + bob), fill=GOLD_HI, outline=OUTLINE)
        d.rectangle((15, 4 + bob, 16, 6 + bob), fill=GOLD_DK)
        d.line((13, 8 + bob, 10, 3 + bob), fill=MOSS_DK)
        d.line((19, 8 + bob, 22, 3 + bob), fill=MOSS_DK)
        d.rectangle((9, 2 + bob, 10, 3 + bob), fill=GOLD_HI)
        d.rectangle((22, 2 + bob, 23, 3 + bob), fill=GOLD_HI)
        if direction == "south":
            d.ellipse((11, 16 + bob, 22, 28 + bob), fill=(216, 187, 130, 255), outline=OUTLINE)
            d.ellipse((10, 17 + bob, 14, 21 + bob), fill=(216, 187, 130, 255), outline=OUTLINE)
            d.ellipse((19, 17 + bob, 23, 21 + bob), fill=(216, 187, 130, 255), outline=OUTLINE)
            d.rectangle((12, 20 + bob, 16, 23 + bob), fill=WHITE)
            d.rectangle((18, 20 + bob, 22, 23 + bob), fill=WHITE)
            d.rectangle((14, 21 + bob, 15, 23 + bob), fill=(48, 38, 39, 255))
            d.rectangle((20, 21 + bob, 21, 23 + bob), fill=(48, 38, 39, 255))
            d.point((14, 21 + bob), fill=WHITE); d.point((20, 21 + bob), fill=WHITE)
            d.rectangle((13, 19 + bob, 16, 20 + bob), fill=MOSS_DK)
            d.rectangle((18, 19 + bob, 21, 20 + bob), fill=MOSS_DK)
            d.rectangle((11, 23 + bob, 12, 24 + bob), fill=(211, 132, 105, 255))
            d.rectangle((21, 23 + bob, 22, 24 + bob), fill=(211, 132, 105, 255))
            d.ellipse((15, 23 + bob, 19, 26 + bob), fill=CREAM_HI)
            d.point((17, 24 + bob), fill=(84, 56, 43, 255))
            d.arc((15, 25 + bob, 20, 27 + bob), 20, 160, fill=OUTLINE, width=1)
            d.rectangle((10, 25 + bob, 12, 28 + bob), fill=(216, 187, 130, 255), outline=OUTLINE)
            d.rectangle((21, 25 + bob, 23, 28 + bob), fill=(216, 187, 130, 255), outline=OUTLINE)
            d.polygon([(26, 21 + bob), (30, 18 + bob), (29, 24 + bob), (25, 24 + bob)],
                      fill=MOSS_HI, outline=OUTLINE)
        else:
            d.arc((10, 13 + bob, 23, 26 + bob), 200, 340, fill=MOSS_DK, width=1)
            d.rectangle((15, 18 + bob, 18, 22 + bob), fill=MOSS_HI)
            d.polygon([(26, 21 + bob), (30, 18 + bob), (29, 24 + bob), (25, 24 + bob)],
                      fill=MOSS_HI, outline=OUTLINE)
    else:
        for i, x in enumerate((7, 13, 20)):
            _mossback_leg(d, x, phase, i)
        d.polygon([(5, 20 + bob), (1, 16 + bob), (5, 15 + bob), (8, 19 + bob)],
                  fill=MOSS_HI, outline=OUTLINE)
        d.ellipse((4, 6 + bob, 25, 24 + bob), fill=MOSS, outline=OUTLINE)
        d.ellipse((7, 8 + bob, 19, 15 + bob), fill=MOSS_HI)
        d.arc((6, 10 + bob, 23, 24 + bob), 195, 345, fill=MOSS_DK, width=2)
        d.rectangle((17, 10 + bob, 18, 11 + bob), fill=GOLD_HI)
        d.rectangle((8, 17 + bob, 9, 18 + bob), fill=MOSS_DK)
        d.rectangle((20, 15 + bob, 21, 16 + bob), fill=MOSS_DK)
        d.rectangle((15, 5 + bob, 16, 8 + bob), fill=CREAM)
        d.rectangle((14, 3 + bob, 18, 5 + bob), fill=GOLD_HI, outline=OUTLINE)
        d.rectangle((15, 4 + bob, 16, 6 + bob), fill=GOLD_DK)
        d.ellipse((20, 16 + bob, 29, 27 + bob), fill=(216, 187, 130, 255), outline=OUTLINE)
        d.rectangle((23, 20 + bob, 26, 23 + bob), fill=WHITE)
        d.rectangle((25, 21 + bob, 26, 23 + bob), fill=(48, 38, 39, 255))
        d.point((25, 21 + bob), fill=WHITE)
        d.rectangle((22, 19 + bob, 25, 20 + bob), fill=MOSS_DK)
        d.rectangle((22, 24 + bob, 24, 25 + bob), fill=(211, 132, 105, 255))
        d.point((26, 24 + bob), fill=(84, 56, 43, 255))
        d.arc((23, 25 + bob, 28, 27 + bob), 20, 160, fill=OUTLINE, width=1)
        d.line((15, 8 + bob, 12, 3 + bob), fill=MOSS_DK)
        d.line((19, 8 + bob, 23, 3 + bob), fill=MOSS_DK)
        d.rectangle((11, 2 + bob, 12, 3 + bob), fill=GOLD_HI)
        d.rectangle((23, 2 + bob, 24, 3 + bob), fill=GOLD_HI)
    return m.outline_image(im)


_PROWLER_BOB = [0, -1, 0, -1]


def _prowler_leg(d: ImageDraw.ImageDraw, x: int, phase: int, index: int) -> None:
    dx, lift = _MOSS_LEG_PHASES[phase % 4][index]
    d.line((x, 31 + lift, x - 4 + dx, 38 + lift, x - 1 + dx, 46),
           fill=BRASS_DK, width=3)
    d.rectangle((x - 4 + dx, 44 + lift, x + 1 + dx, 47 + lift),
                fill=BRASS, outline=OUTLINE)
    d.point((x - 2 + dx, 39 + lift), fill=BRASS_HI)


def prowler_walk_frame(direction: str, phase: int) -> Image.Image:
    im = new(64, 48)
    d = ImageDraw.Draw(im)
    bob = _PROWLER_BOB[phase % 4]
    if direction == "south":
        source = prowler_front()
        leg_x = (12, 23, 40, 51)
    elif direction == "north":
        source = prowler_north()
        leg_x = (12, 23, 40, 51)
    elif direction == "east":
        source = mirror(m.draw_prowler(0))
        leg_x = (15, 26, 40, 51)
    else:
        source = m.draw_prowler(0)
        leg_x = (15, 26, 40, 51)
    for i, x in enumerate(leg_x):
        _prowler_leg(d, x, phase, i)
    # Rebuild the lower body so the four animated legs have a solid attachment.
    d.ellipse((12, 25 + bob, 52, 38 + bob), fill=BLUE, outline=OUTLINE)
    d.rectangle((17, 27 + bob, 45, 34 + bob), fill=BLUE_HI)
    d.line((18, 32 + bob, 43, 32 + bob), fill=BRASS_DK, width=2)
    top_h = 32
    top = source.crop((0, 0, 64, top_h))
    im.alpha_composite(top, (0, bob))
    return m.outline_image(im)


def walk_frames_for(slug: str, direction: str, base: Image.Image) -> list[Image.Image]:
    if slug == "mossback_nib":
        if direction == "west":
            return [mirror(mossback_walk_frame("east", i)) for i in range(WALK_FRAMES)]
        return [mossback_walk_frame(direction, i) for i in range(WALK_FRAMES)]
    if slug == "brass_prowler":
        return [prowler_walk_frame(direction, i) for i in range(WALK_FRAMES)]
    if slug == "emberfox_kit":
        if direction == "west":
            return [mirror(emberfox_walk_frame("east", i)) for i in range(WALK_FRAMES)]
        return [emberfox_walk_frame(direction, i) for i in range(WALK_FRAMES)]
    return generic_walk_frames(base)



# ── Mossback Nib ─────────────────────────────────────────────────────────
def mossback_north() -> Image.Image:
    im = new(32, 32)
    d = ImageDraw.Draw(im)
    for x in (8, 13, 19, 24):
        d.rectangle((x, 23, x + 2, 28), fill=MOSS_DK, outline=OUTLINE)
    d.ellipse((5, 6, 27, 24), fill=MOSS, outline=OUTLINE)
    d.ellipse((8, 8, 21, 15), fill=MOSS_HI)
    d.arc((7, 10, 25, 24), 195, 345, fill=MOSS_DK, width=2)
    d.rectangle((21, 10, 22, 11), fill=GOLD_HI)
    d.rectangle((9, 17, 10, 18), fill=MOSS_DK)
    d.rectangle((23, 15, 24, 16), fill=MOSS_DK)
    d.rectangle((16, 5, 17, 8), fill=CREAM)
    d.rectangle((15, 3, 19, 5), fill=GOLD_HI, outline=OUTLINE)
    d.rectangle((16, 4, 17, 6), fill=GOLD_DK)
    d.line((13, 8, 10, 3), fill=MOSS_DK)
    d.line((19, 8, 22, 3), fill=MOSS_DK)
    d.rectangle((9, 2, 10, 3), fill=GOLD_HI)
    d.rectangle((22, 2, 23, 3), fill=GOLD_HI)
    # Back plate: a soft mossy seam instead of a face.
    d.arc((10, 13, 23, 26), 200, 340, fill=MOSS_DK, width=1)
    d.rectangle((15, 18, 18, 22), fill=MOSS_HI)
    d.rectangle((16, 19, 17, 21), fill=MOSS_DK)
    d.polygon([(26, 21), (30, 18), (29, 24), (25, 24)], fill=MOSS_HI, outline=OUTLINE)
    return m.outline_image(im)


def mossback_side() -> Image.Image:
    im = new(32, 32)
    d = ImageDraw.Draw(im)
    # feet
    for x in (7, 13, 20):
        d.rectangle((x, 23, x + 2, 28), fill=MOSS_DK, outline=OUTLINE)
    # leaf tail on the west side
    d.polygon([(5, 20), (1, 16), (5, 15), (8, 19)], fill=MOSS_HI, outline=OUTLINE)
    # shell
    d.ellipse((4, 6, 25, 24), fill=MOSS, outline=OUTLINE)
    d.ellipse((7, 8, 19, 15), fill=MOSS_HI)
    d.arc((6, 10, 23, 24), 195, 345, fill=MOSS_DK, width=2)
    d.rectangle((17, 10, 18, 11), fill=GOLD_HI)
    d.rectangle((8, 17, 9, 18), fill=MOSS_DK)
    d.rectangle((20, 15, 21, 16), fill=MOSS_DK)
    d.rectangle((15, 5, 16, 8), fill=CREAM)
    d.rectangle((14, 3, 18, 5), fill=GOLD_HI, outline=OUTLINE)
    d.rectangle((15, 4, 16, 6), fill=GOLD_DK)
    # head on the east side, one friendly eye
    d.ellipse((20, 16, 29, 27), fill=(216, 187, 130, 255), outline=OUTLINE)
    d.ellipse((20, 17, 24, 21), fill=(216, 187, 130, 255), outline=OUTLINE)
    d.rectangle((23, 20, 26, 23), fill=WHITE)
    d.rectangle((25, 21, 26, 23), fill=(48, 38, 39, 255))
    d.point((25, 21), fill=WHITE)
    d.rectangle((22, 19, 25, 20), fill=MOSS_DK)
    d.rectangle((22, 24, 24, 25), fill=(211, 132, 105, 255))
    d.point((26, 24), fill=(84, 56, 43, 255))
    d.arc((23, 25, 28, 27), 20, 160, fill=OUTLINE, width=1)
    # antennae still visible over the shell
    d.line((15, 8, 12, 3), fill=MOSS_DK)
    d.line((19, 8, 23, 3), fill=MOSS_DK)
    d.rectangle((11, 2, 12, 3), fill=GOLD_HI)
    d.rectangle((23, 2, 24, 3), fill=GOLD_HI)
    return m.outline_image(im)


# ── Emberfox Kit ─────────────────────────────────────────────────────────
def emberfox_north() -> Image.Image:
    im = new(48, 48)
    d = ImageDraw.Draw(im)
    d.ellipse((28, 25, 45, 44), fill=RUST, outline=OUTLINE)
    d.ellipse((35, 31, 44, 43), fill=CREAM, outline=OUTLINE)
    d.rectangle((13, 34, 20, 45), fill=RUST_DK)
    d.rectangle((26, 34, 33, 45), fill=RUST_DK)
    d.rectangle((12, 42, 21, 46), fill=CREAM, outline=OUTLINE)
    d.rectangle((25, 42, 34, 46), fill=CREAM, outline=OUTLINE)
    d.ellipse((11, 18, 36, 42), fill=RUST, outline=OUTLINE)
    d.ellipse((16, 24, 31, 40), fill=RUST_HI)
    d.rectangle((16, 23, 32, 26), fill=TEAL, outline=OUTLINE)
    d.polygon([(28, 25), (34, 29), (30, 30), (27, 27)], fill=TEAL_DK, outline=OUTLINE)
    d.polygon([(12, 12), (9, 2), (18, 9)], fill=RUST, outline=OUTLINE)
    d.polygon([(29, 9), (38, 2), (35, 13)], fill=RUST, outline=OUTLINE)
    d.polygon([(13, 10), (11, 4), (16, 9)], fill=RUST_DK)
    d.polygon([(31, 9), (36, 4), (34, 11)], fill=RUST_DK)
    d.ellipse((11, 7, 37, 27), fill=RUST, outline=OUTLINE)
    d.ellipse((15, 9, 31, 15), fill=RUST_HI)
    # Back-of-head fur seam and scarf knot; no eyes or muzzle.
    d.arc((18, 11, 29, 25), 30, 150, fill=RUST_DK, width=2)
    d.ellipse((23, 15, 27, 20), fill=RUST_HI)
    d.rectangle((20, 23, 28, 25), fill=TEAL_HI)
    d.rectangle((23, 30, 25, 33), fill=CREAM)
    return m.outline_image(im)


def emberfox_side() -> Image.Image:
    im = new(48, 48)
    d = ImageDraw.Draw(im)
    # tail
    d.ellipse((2, 24, 20, 44), fill=RUST, outline=OUTLINE)
    d.ellipse((4, 30, 14, 43), fill=CREAM, outline=OUTLINE)
    # legs
    d.rectangle((11, 33, 16, 45), fill=RUST_DK)
    d.rectangle((21, 33, 26, 45), fill=RUST_DK)
    d.rectangle((31, 33, 36, 45), fill=RUST_DK)
    d.rectangle((10, 42, 17, 46), fill=CREAM, outline=OUTLINE)
    d.rectangle((20, 42, 27, 46), fill=CREAM, outline=OUTLINE)
    d.rectangle((30, 42, 37, 46), fill=CREAM, outline=OUTLINE)
    # body
    d.ellipse((9, 20, 37, 40), fill=RUST, outline=OUTLINE)
    d.ellipse((14, 24, 31, 38), fill=CREAM_HI)
    # scarf
    d.rectangle((17, 23, 33, 26), fill=TEAL, outline=OUTLINE)
    d.polygon([(30, 25), (36, 29), (32, 30), (29, 27)], fill=TEAL_DK, outline=OUTLINE)
    # head at the east edge, one eye
    d.polygon([(31, 14), (32, 3), (39, 11)], fill=RUST, outline=OUTLINE)
    d.polygon([(33, 11), (34, 6), (37, 11)], fill=RUST_HI)
    d.ellipse((28, 8, 46, 27), fill=RUST, outline=OUTLINE)
    d.ellipse((31, 10, 43, 16), fill=RUST_HI)
    d.ellipse((35, 16, 45, 25), fill=CREAM, outline=OUTLINE)
    d.ellipse((34, 12, 39, 17), fill=AMBER, outline=OUTLINE)
    d.rectangle((36, 14, 37, 16), fill=INK)
    d.point((36, 14), fill=WHITE)
    d.polygon([(42, 18), (46, 20), (42, 21)], fill=INK)
    d.arc((38, 21, 44, 25), 20, 160, fill=OUTLINE, width=1)
    return m.outline_image(im)


# ── Cinder Ooze ──────────────────────────────────────────────────────────
def cinder_north() -> Image.Image:
    im = m.draw_cinder_ooze(0).copy()
    d = ImageDraw.Draw(im)
    # Cover the eyes and core with cooled crust; back view is all charcoal.
    d.polygon([(14, 24), (22, 21), (28, 24), (35, 23), (34, 30), (26, 31), (17, 30)],
              fill=CHAR, outline=OUTLINE)
    d.rectangle((17, 25, 28, 30), fill=CHAR)
    d.line((17, 24, 19, 27), fill=CHAR_HI)
    d.line((31, 22, 33, 27), fill=CHAR_HI)
    d.line((22, 31, 25, 35), fill=(114, 50, 39, 255))
    d.point((20, 18), fill=AMBER)
    d.point((34, 30), fill=RUST_HI)
    return m.outline_image(im)


# ── Gravebell Shambler ───────────────────────────────────────────────────
def gravebell_north() -> Image.Image:
    im = m.draw_gravebell(0).copy()
    d = ImageDraw.Draw(im)
    # Fill the face and eye sockets with the back of the head.
    d.polygon([(14, 7), (29, 5), (36, 13), (33, 24), (21, 27), (13, 20)],
              fill=(91, 103, 79, 255), outline=OUTLINE)
    d.rectangle((15, 9, 28, 14), fill=(110, 120, 88, 255))
    d.line((17, 11, 28, 12), fill=(65, 76, 58, 255), width=2)
    for x in (19, 23, 27):
        d.line((x, 15, x + 1, 20), fill=(72, 86, 62, 255))
    # Ragged hood/back collar.
    d.polygon([(13, 19), (19, 18), (24, 25), (31, 19), (35, 23), (30, 30), (17, 28)],
              fill=(67, 55, 47, 255), outline=OUTLINE)
    d.rectangle((28, 35, 38, 39), fill=BRASS_DK)
    return m.outline_image(im)


def gravebell_side() -> Image.Image:
    im = new(48, 48)
    d = ImageDraw.Draw(im)
    # back legs
    d.rectangle((17, 35, 22, 46), fill=(59, 52, 43, 255), outline=OUTLINE)
    d.rectangle((29, 35, 34, 46), fill=(74, 63, 49, 255), outline=OUTLINE)
    d.rectangle((15, 43, 23, 47), fill=(45, 39, 37, 255), outline=OUTLINE)
    d.rectangle((28, 43, 37, 47), fill=(45, 39, 37, 255), outline=OUTLINE)
    # coat side profile
    d.polygon([(15, 18), (31, 16), (38, 34), (34, 41), (29, 37), (24, 42),
               (19, 38), (13, 35)], fill=(82, 69, 57, 255), outline=OUTLINE)
    d.rectangle((18, 20, 28, 32), fill=(105, 83, 62, 255))
    d.line((20, 32, 33, 33), fill=(72, 49, 35, 255), width=2)
    # head in profile, one bright eye
    d.polygon([(22, 9), (34, 8), (40, 14), (37, 24), (29, 27), (21, 20)],
              fill=SKIN_Z, outline=OUTLINE)
    d.rectangle((23, 10, 32, 13), fill=SKIN_Z_HI)
    d.rectangle((38, 14, 42, 18), fill=SKIN_Z_DK)
    d.rectangle((33, 15, 37, 18), fill=INK)
    d.rectangle((34, 16, 36, 17), fill=AMBER_HI)
    d.line((27, 21, 34, 22), fill=OUTLINE)
    d.line((16, 7, 13, 2), fill=(43, 44, 37, 255), width=2)
    d.line((24, 5, 26, 1), fill=(43, 44, 37, 255), width=2)
    # arm and bell on the front side
    d.line((29, 23, 34, 31, 33, 37), fill=SKIN_Z_DK, width=4)
    d.line((29, 24, 33, 30), fill=SKIN_Z, width=2)
    d.rectangle((32, 35, 35, 38), fill=SKIN_Z_HI, outline=OUTLINE)
    d.polygon([(35, 29), (43, 30), (42, 38), (36, 38)], fill=BRASS, outline=OUTLINE)
    d.line((37, 33, 42, 33), fill=TEAL)
    d.rectangle((38, 38, 41, 40), fill=BRASS_HI, outline=OUTLINE)
    d.rectangle((39, 39, 40, 40), fill=AMBER)
    return m.outline_image(im)


# ── Rune Sentinel ────────────────────────────────────────────────────────
def sentinel_north() -> Image.Image:
    im = m.draw_rune_sentinel(0).copy()
    d = ImageDraw.Draw(im)
    # Cover the face and chest heart with a rune-carved backplate.
    d.polygon([(25, 7), (33, 5), (39, 9), (41, 18), (37, 23), (28, 23), (23, 16)],
              fill=(106, 96, 119, 255), outline=OUTLINE)
    d.polygon([(28, 9), (34, 8), (37, 13), (33, 18), (27, 16)],
              fill=(70, 61, 87, 255))
    d.line((32, 9, 32, 19), fill=GOLD)
    d.line((28, 13, 36, 13), fill=GOLD)
    d.polygon([(24, 26), (40, 26), (44, 34), (38, 45), (32, 48), (25, 44), (20, 34)],
              fill=(58, 50, 77, 255), outline=OUTLINE)
    d.polygon([(32, 28), (39, 35), (32, 43), (25, 35)], fill=(44, 36, 64, 255), outline=GOLD)
    d.polygon([(32, 31), (36, 35), (32, 40), (28, 35)], fill=VIOLET_DK)
    d.rectangle((31, 34, 33, 37), fill=VIOLET)
    d.line((23, 43, 30, 47), fill=GOLD_DK)
    d.line((41, 43, 34, 47), fill=GOLD_DK)
    return m.outline_image(im)


# ── Vesper Acolyte ───────────────────────────────────────────────────────
def vesper_north() -> Image.Image:
    im = m.draw_vesper(0).copy()
    d = ImageDraw.Draw(im)
    # Fill the void face with the back of the hood; keep only a dark hood seam.
    d.polygon([(18, 11), (25, 7), (31, 11), (30, 21), (23, 24), (17, 19)],
              fill=(64, 49, 82, 255), outline=OUTLINE)
    d.polygon([(21, 11), (25, 9), (28, 12), (27, 18), (24, 20), (20, 17)],
              fill=(49, 36, 65, 255))
    d.line((24, 9, 24, 20), fill=GOLD_DK)
    d.line((20, 28, 28, 28), fill=GOLD_DK)
    d.rectangle((23, 48, 25, 51), fill=VIOLET_DK)
    return m.outline_image(im)


def vesper_side() -> Image.Image:
    im = new(48, 64)
    d = ImageDraw.Draw(im)
    # staff on the west side
    d.line((9, 18, 9, 55), fill=(68, 45, 57, 255), width=2)
    d.line((6, 18, 12, 18), fill=GOLD, width=2)
    d.arc((5, 10, 13, 21), 200, 340, fill=GOLD_HI, width=2)
    d.polygon([(9, 17), (6, 11), (9, 4), (12, 10)], fill=VIOLET_DK, outline=OUTLINE)
    d.polygon([(9, 15), (7, 11), (9, 7), (11, 11)], fill=VIOLET)
    d.rectangle((9, 10, 10, 13), fill=VIOLET_HI)
    # side hood and robe
    d.polygon([(16, 20), (30, 20), (36, 37), (39, 55), (32, 52),
               (28, 59), (23, 52), (17, 56), (13, 52), (15, 35)],
              fill=(53, 41, 67, 255), outline=OUTLINE)
    d.polygon([(18, 18), (29, 11), (36, 13), (38, 20), (31, 24), (22, 26), (15, 23)],
              fill=(64, 49, 82, 255), outline=OUTLINE)
    d.polygon([(22, 13), (29, 12), (34, 16), (32, 21), (26, 23), (20, 19)],
              fill=(24, 20, 31, 255), outline=OUTLINE)
    d.rectangle((28, 15, 31, 17), fill=WHITE)
    d.point((29, 15), fill=VIOLET_HI)
    d.polygon([(31, 20), (33, 22), (31, 24), (29, 22)], fill=GOLD)
    d.line((18, 30, 30, 30), fill=GOLD)
    d.line((18, 49, 30, 49), fill=GOLD)
    d.rectangle((23, 48, 25, 50), fill=VIOLET_HI)
    # side sleeve and hand
    d.line((31, 25, 38, 33, 35, 41), fill=(71, 54, 87, 255), width=5)
    d.rectangle((33, 39, 36, 43), fill=(166, 146, 160, 255), outline=OUTLINE)
    return m.outline_image(im)


# ── Brass Prowler ────────────────────────────────────────────────────────
def prowler_front() -> Image.Image:
    im = new(64, 48)
    d = ImageDraw.Draw(im)
    for x in (13, 24, 39, 50):
        d.line((x, 31, x - 4, 39, x - 1, 46), fill=BRASS_DK, width=3)
        d.rectangle((x - 4, 44, x + 1, 47), fill=BRASS, outline=OUTLINE)
    d.ellipse((12, 19, 52, 37), fill=BLUE, outline=OUTLINE)
    d.rectangle((17, 21, 45, 29), fill=BLUE_HI)
    d.polygon([(18, 18), (29, 15), (40, 18), (36, 24), (23, 24)], fill=BRASS, outline=OUTLINE)
    d.line((18, 30, 43, 30), fill=BRASS_DK, width=2)
    for x in (20, 28, 36, 44):
        d.point((x, 26), fill=BRASS_HI)
    # head-on brass mask
    d.polygon([(22, 21), (42, 21), (47, 28), (40, 38), (24, 38), (17, 28)],
              fill=BRASS, outline=OUTLINE)
    d.rectangle((23, 27, 41, 31), fill=TEAL_DK, outline=OUTLINE)
    d.rectangle((26, 28, 38, 29), fill=TEAL_HI)
    d.polygon([(21, 35), (27, 34), (23, 41), (18, 39)], fill=BRASS_DK, outline=OUTLINE)
    d.polygon([(37, 34), (44, 35), (45, 39), (39, 41)], fill=BRASS_DK, outline=OUTLINE)
    d.rectangle((28, 22, 34, 24), fill=BRASS_HI)
    # back crystal
    d.polygon([(32, 10), (42, 18), (32, 27), (22, 18)], fill=TEAL_DK, outline=OUTLINE)
    d.polygon([(32, 13), (39, 18), (32, 24), (25, 18)], fill=TEAL_HI)
    d.rectangle((31, 16, 33, 20), fill=WHITE)
    return m.outline_image(im)


def prowler_north() -> Image.Image:
    im = new(64, 48)
    d = ImageDraw.Draw(im)
    for x in (13, 24, 39, 50):
        d.line((x, 31, x - 4, 39, x - 1, 46), fill=BRASS_DK, width=3)
        d.rectangle((x - 4, 44, x + 1, 47), fill=BRASS, outline=OUTLINE)
    d.ellipse((12, 19, 52, 37), fill=BLUE, outline=OUTLINE)
    d.rectangle((17, 21, 45, 29), fill=BLUE_HI)
    d.polygon([(18, 18), (29, 15), (40, 18), (36, 24), (23, 24)], fill=BRASS, outline=OUTLINE)
    d.line((18, 30, 43, 30), fill=BRASS_DK, width=2)
    # Back plate: no visor, exposed brass spine and crystal.
    d.polygon([(22, 21), (42, 21), (46, 29), (39, 37), (25, 37), (18, 29)],
              fill=BRASS_DK, outline=OUTLINE)
    d.rectangle((28, 22, 36, 35), fill=BRASS, outline=OUTLINE)
    d.line((28, 25, 36, 25), fill=GOLD_HI)
    d.line((28, 30, 36, 30), fill=GOLD_DK)
    d.polygon([(32, 10), (42, 18), (32, 27), (22, 18)], fill=TEAL_DK, outline=OUTLINE)
    d.polygon([(32, 13), (39, 18), (32, 24), (25, 18)], fill=TEAL_HI)
    d.point((32, 17), fill=WHITE)
    return m.outline_image(im)


# ── Cipher Warden ────────────────────────────────────────────────────────
def warden_north() -> Image.Image:
    im = m.draw_warden(0).copy()
    d = ImageDraw.Draw(im)
    # Back mask plate; cover visor and core with closed brass.
    d.polygon([(26, 8), (32, 5), (38, 8), (38, 18), (32, 22), (26, 18)],
              fill=BRASS_DK, outline=OUTLINE)
    d.polygon([(29, 9), (32, 7), (35, 9), (35, 15), (32, 18), (29, 15)],
              fill=BRASS, outline=OUTLINE)
    d.line((32, 9, 32, 17), fill=GOLD_HI)
    d.polygon([(32, 22), (43, 33), (32, 45), (21, 33)], fill=BRASS_DK, outline=OUTLINE)
    d.polygon([(32, 25), (39, 33), (32, 41), (25, 33)], fill=BRASS)
    d.polygon([(32, 28), (36, 33), (32, 38), (28, 33)], fill=(45, 61, 77, 255), outline=OUTLINE)
    d.line((28, 35, 36, 35), fill=GOLD_DK)
    return m.outline_image(im)


# ── Sheet assembly ───────────────────────────────────────────────────────
# id: (south base, north base, east base, west base, icon scale metadata)
def mob_specs() -> dict:
    return {
        "mossback_nib": {
            "name": "Mossback Nib",
            "south": m.draw_mossback(0),
            "north": mossback_north(),
            "east": mossback_side(),
            "west": mirror(mossback_side()),
        },
        "emberfox_kit": {
            "name": "Emberfox Kit",
            "south": m.draw_emberfox(0),
            "north": emberfox_north(),
            "east": emberfox_side(),
            "west": mirror(emberfox_side()),
        },
        "cinder_ooze": {
            "name": "Cinder Ooze",
            "south": m.draw_cinder_ooze(0),
            "north": cinder_north(),
            "east": m.draw_cinder_ooze(0),
            "west": mirror(m.draw_cinder_ooze(0)),
        },
        "gravebell_shambler": {
            "name": "Gravebell Shambler",
            "south": m.draw_gravebell(0),
            "north": gravebell_north(),
            "east": gravebell_side(),
            "west": mirror(gravebell_side()),
        },
        "rune_sentinel": {
            "name": "Rune Sentinel",
            "south": m.draw_rune_sentinel(0),
            "north": sentinel_north(),
            "east": m.draw_rune_sentinel(0),
            "west": mirror(m.draw_rune_sentinel(0)),
        },
        "vesper_acolyte": {
            "name": "Vesper Acolyte",
            "south": m.draw_vesper(0),
            "north": vesper_north(),
            "east": vesper_side(),
            "west": mirror(vesper_side()),
        },
        "brass_prowler": {
            "name": "Brass Prowler",
            "south": prowler_front(),
            "north": prowler_north(),
            "east": mirror(m.draw_prowler(0)),
            "west": m.draw_prowler(0),
        },
        "cipher_warden": {
            "name": "Cipher Warden",
            "south": m.draw_warden(0),
            "north": warden_north(),
            "east": m.draw_warden(0),
            "west": mirror(m.draw_warden(0)),
        },
    }


ROWS = ("south", "north", "east", "west")


def build() -> None:
    specs = mob_specs()
    labels = []
    for slug, spec in specs.items():
        south = spec["south"]
        w, h = south.size
        # Normalize every direction to the south canvas so the sheet rows are
        # exactly the same cell size.
        dirs = {}
        for dname in ROWS:
            im = spec[dname]
            if im.size != (w, h):
                canvas = new(w, h)
                canvas.alpha_composite(im, ((w - im.width) // 2, h - im.height))
                im = canvas
            dirs[dname] = im
        sheet = new(w * (1 + WALK_FRAMES), h * 4)
        for row, dname in enumerate(ROWS):
            base = dirs[dname]
            frames = [base] + walk_frames_for(slug, dname, base)
            for col, frame in enumerate(frames):
                sheet.alpha_composite(frame, (col * w, row * h))
        sheet.save(OUT / f"{slug}_sheet.png")
        dirs["south"].save(OUT / f"{slug}_icon.png")
        labels.append((slug, sheet, w, h))
        print(f"{slug}: {w}x{h} -> sheet {sheet.size}")

    # Review contact sheet, 4x nearest, with labels.
    cell_w = max(sheet.width for _, sheet, _, _ in labels) * 4 + 28
    cell_h = max(sheet.height for _, sheet, _, _ in labels) * 4 + 42
    cols = 4
    rows = (len(labels) + cols - 1) // cols
    canvas = Image.new("RGBA", (cols * cell_w, rows * cell_h), (22, 24, 32, 255))
    d = ImageDraw.Draw(canvas)
    font = ImageFont.truetype("C:/Windows/Fonts/consolab.ttf", 15)
    small = ImageFont.truetype("C:/Windows/Fonts/consolab.ttf", 11)
    for i, (slug, sheet, w, h) in enumerate(labels):
        x = (i % cols) * cell_w + 10
        y = (i // cols) * cell_h + 10
        big = sheet.resize((sheet.width * 4, sheet.height * 4), Image.Resampling.NEAREST)
        canvas.alpha_composite(big, (x, y))
        d.text((x, y + big.height + 5), slug, font=font, fill=(230, 236, 248, 255))
        d.text((x, y + big.height + 23), "rows S/N/E/W, cols idle + 4 walk frames",
               font=small, fill=(145, 158, 184, 255))
    PREVIEW.parent.mkdir(parents=True, exist_ok=True)
    canvas.save(PREVIEW)
    print("saved", PREVIEW)


if __name__ == "__main__":
    build()
