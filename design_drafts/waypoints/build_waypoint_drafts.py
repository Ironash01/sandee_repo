from PIL import Image, ImageDraw, ImageFont, ImageChops, ImageFilter
import math
import os
import random

ROOT = os.path.dirname(os.path.abspath(__file__))
SPRITE_DIR = os.path.join(ROOT, "sprites")
GAME = r"C:\Users\Krosis\Documents\github_repos\sandee_repo\SandEEAlpha"
FONT = os.path.join(GAME, "fonts", "monogram-extended.ttf")
os.makedirs(SPRITE_DIR, exist_ok=True)

# Palette sampled/refined from SandEE's stone, wood, cave and dungeon art.
OUTLINE = (18, 16, 14, 255)
MORTAR = (30, 30, 28, 255)
STONE_DARK = (44, 44, 42, 255)
STONE_BASE = (57, 56, 56, 255)
STONE_MID = (72, 72, 68, 255)
STONE_LIGHT = (105, 106, 106, 255)
STONE_HI = (145, 142, 122, 255)
STONE_WARM = (166, 148, 110, 255)
STONE_WARM_HI = (201, 181, 134, 255)
GRANITE_DARK = (91, 72, 73, 255)
GRANITE = (145, 125, 125, 255)
GRANITE_HI = (183, 162, 162, 255)
DIORITE_DARK = (72, 80, 85, 255)
DIORITE = (109, 118, 123, 255)
DIORITE_HI = (147, 165, 175, 255)
WOOD_DARK = (58, 38, 28, 255)
WOOD = (112, 66, 44, 255)
WOOD_LIGHT = (157, 98, 62, 255)
MOSS_DARK = (45, 75, 36, 255)
MOSS = (77, 116, 48, 255)
MOSS_LIGHT = (124, 158, 73, 255)
GOLD_DARK = (107, 82, 42, 255)
GOLD = (190, 157, 86, 255)
GOLD_LIGHT = (235, 211, 138, 255)
TEAL_DARK = (7, 24, 27, 255)
TEAL_DEEP = (13, 47, 49, 255)
TEAL = (31, 112, 104, 255)
CYAN = (85, 198, 180, 255)
PALE_CYAN = (158, 245, 213, 255)
WHITE_GLOW = (232, 255, 247, 255)
VIOLET_DARK = (27, 21, 47, 255)
VIOLET_DEEP = (53, 42, 91, 255)
VIOLET = (108, 91, 174, 255)
LILAC = (157, 139, 226, 255)
PALE_LILAC = (218, 204, 255, 255)
AMBER_DARK = (92, 49, 23, 255)
AMBER = (191, 105, 38, 255)
AMBER_LIGHT = (255, 181, 76, 255)
AMBER_PALE = (255, 231, 158, 255)
IRON_DARK = (31, 33, 34, 255)
IRON = (64, 68, 69, 255)
IRON_LIGHT = (108, 111, 106, 255)
RUBBLE = (72, 69, 62, 255)


def rgba(c):
    return c


def transparent(size):
    return Image.new("RGBA", size, (0, 0, 0, 0))


def empty_mask(size):
    return Image.new("L", size, 0)


def new_draw(img):
    return ImageDraw.Draw(img)


def rect_mask(size, boxes):
    mask = empty_mask(size)
    d = ImageDraw.Draw(mask)
    for b in boxes:
        d.rectangle(tuple(int(v) for v in b), fill=255)
    return mask


def poly_mask(size, points):
    mask = empty_mask(size)
    ImageDraw.Draw(mask).polygon([(int(x), int(y)) for x, y in points], fill=255)
    return mask


def arch_mask(size, x0, y0, x1, y1, pointed=False):
    """Arch whose spring line is y0 + width/2. y0 is the top."""
    mask = empty_mask(size)
    d = ImageDraw.Draw(mask)
    w = x1 - x0
    radius = w / 2.0
    spring = y0 + radius
    if pointed:
        # Slightly gothic: broad lower shoulders, tapered point.
        points = [
            (x0, y1), (x0, spring), (x0 + int(w * 0.30), y0 + int(w * 0.20)),
            (x0 + int(w * 0.50), y0), (x0 + int(w * 0.70), y0 + int(w * 0.20)),
            (x1, spring), (x1, y1),
        ]
        d.polygon(points, fill=255)
    else:
        d.rectangle([x0, spring, x1, y1], fill=255)
        d.ellipse([x0, y0, x1, y0 + int(radius * 2)], fill=255)
    return mask


def mask_union(*masks):
    out = masks[0].copy()
    for m in masks[1:]:
        out = ImageChops.lighter(out, m)
    return out


def mask_inset_arch(size, x0, y0, x1, y1, inset, pointed=False):
    return arch_mask(size, x0 + inset, y0 + inset, x1 - inset, y1 - inset, pointed)


def composite_mask(img, layer, mask):
    img.alpha_composite(Image.composite(layer, transparent(img.size), mask))


def fill_mask(img, mask, color):
    layer = Image.new("RGBA", img.size, color)
    composite_mask(img, layer, mask)


def masonry(img, mask, seed, base=STONE_BASE, course=10, block=20):
    rng = random.Random(seed)
    fill_mask(img, mask, base)
    layer = transparent(img.size)
    d = ImageDraw.Draw(layer)
    colors = [base, (base[0] + 4, base[1] + 4, base[2] + 3, 255),
              (base[0] - 6, base[1] - 6, base[2] - 5, 255)]
    for row, y in enumerate(range(-course, img.height + course, course)):
        offset = (row % 2) * (block // 2)
        for x in range(-block, img.width + block, block):
            x0 = x + offset
            y0 = y
            x1 = x0 + block - 1
            y1 = y0 + course - 1
            col = colors[rng.randrange(len(colors))]
            d.rectangle([x0, y0, x1, y1], fill=col)
            d.line([(x0, y0), (x1, y0)], fill=STONE_HI, width=1)
            d.line([(x0, y0), (x0, y1)], fill=STONE_LIGHT, width=1)
            d.line([(x0, y1), (x1, y1)], fill=STONE_DARK, width=1)
            d.line([(x1, y0), (x1, y1)], fill=MORTAR, width=1)
            # small chipped highlights inside the brick
            for _ in range(rng.randint(0, 3)):
                px = rng.randint(x0 + 2, max(x0 + 2, x1 - 2))
                py = rng.randint(y0 + 2, max(y0 + 2, y1 - 2))
                d.point((px, py), fill=STONE_HI if rng.random() < 0.55 else STONE_DARK)
        d.line([(0, y), (img.width, y)], fill=MORTAR, width=1)
    # Long cracks and weathering. Kept sparse so the silhouette reads cleanly.
    for _ in range(max(3, (img.width * img.height) // 5000)):
        x = rng.randint(0, img.width - 1)
        y = rng.randint(0, img.height - 1)
        length = rng.randint(2, 6)
        for i in range(length):
            if rng.random() < 0.7:
                d.point((x + i, y + rng.randint(-1, 1)), fill=MORTAR)
        if rng.random() < 0.35:
            d.point((x + 1, y + 1), fill=STONE_HI)
    composite_mask(img, layer, mask)


def add_outline(img, color=OUTLINE):
    alpha = img.getchannel("A")
    dil = alpha.filter(ImageFilter.MaxFilter(3))
    edge = ImageChops.subtract(dil, alpha)
    outline = Image.new("RGBA", img.size, color)
    outline.putalpha(edge)
    base = transparent(img.size)
    base.alpha_composite(outline)
    base.alpha_composite(img)
    return base


def add_moss(img, mask, seed, count=24, bounds=None):
    rng = random.Random(seed)
    d = ImageDraw.Draw(img)
    x0, y0, x1, y1 = bounds if bounds else (0, 0, img.width, img.height)
    points = []
    for y in range(y0, y1):
        for x in range(x0, x1):
            if mask.getpixel((x, y)) > 0:
                points.append((x, y))
    if not points:
        return
    for _ in range(count):
        x, y = points[rng.randrange(len(points))]
        if rng.random() < 0.55:
            d.point((x, y), fill=MOSS)
        else:
            d.rectangle([x, y, x + rng.randint(0, 1), y + rng.randint(0, 1)], fill=MOSS_DARK)
        if rng.random() < 0.25:
            d.point((x, max(0, y - 1)), fill=MOSS_LIGHT)


RUNES = {
    "diamond": ["010", "101", "010"],
    "eye": ["111", "101", "111"],
    "arrow": ["010", "111", "010", "010"],
    "fork": ["101", "111", "010", "010"],
    "crown": ["101", "111", "111"],
    "spiral": ["110", "001", "011", "100"],
}


def draw_rune(d, x, y, kind, color=GOLD, shadow=GOLD_DARK, scale=1):
    pat = RUNES[kind]
    for yy, row in enumerate(pat):
        for xx, c in enumerate(row):
            if c == "1":
                d.rectangle([x + xx * scale + scale, y + yy * scale + scale,
                             x + xx * scale + scale * 2 - 1,
                             y + yy * scale + scale * 2 - 1], fill=shadow)
    for yy, row in enumerate(pat):
        for xx, c in enumerate(row):
            if c == "1":
                d.rectangle([x + xx * scale, y + yy * scale,
                             x + xx * scale + scale - 1,
                             y + yy * scale + scale - 1], fill=color)


def draw_diamond(d, cx, cy, rx, ry, outer, inner=None, highlight=None):
    if inner is None:
        inner = outer
    d.polygon([(cx, cy - ry), (cx + rx, cy), (cx, cy + ry), (cx - rx, cy)], fill=outer)
    d.polygon([(cx, cy - ry + 2), (cx + max(1, rx - 2), cy), (cx, cy + ry - 2),
               (cx - max(1, rx - 2), cy)], fill=inner)
    if highlight:
        d.point((cx - 1, cy - 2), fill=highlight)
        d.point((cx, cy - 2), fill=highlight)


def draw_portal_energy(img, mask, cx, cy, rx, ry, palette="teal", seed=1):
    rng = random.Random(seed)
    layer = transparent(img.size)
    d = ImageDraw.Draw(layer)
    if palette == "teal":
        cols = [TEAL_DARK, TEAL_DEEP, TEAL, CYAN, PALE_CYAN, WHITE_GLOW]
    else:
        cols = [VIOLET_DARK, VIOLET_DEEP, VIOLET, LILAC, PALE_LILAC, (251, 246, 255, 255)]
    # Keep most of the doorway dark. The energy is a narrow vertical veil,
    # not a bright filled disc, so it still reads as an opening at 1.9x zoom.
    d.ellipse([cx - rx + 2, cy - ry + 2, cx + rx - 2, cy + ry - 2], fill=cols[0])
    vrx, vry = max(8, int(rx * 0.58)), max(14, int(ry * 0.76))
    d.ellipse([cx - vrx, cy - vry, cx + vrx, cy + vry], fill=cols[1])
    d.ellipse([cx - vrx + 3, cy - vry + 4, cx + vrx - 3, cy + vry - 4], fill=cols[2])
    d.ellipse([cx - max(3, vrx - 8), cy - vry + 9,
               cx + max(3, vrx - 8), cy + vry - 9], fill=cols[3])
    d.ellipse([cx - 2, cy - 8, cx + 2, cy + 8], fill=cols[4])
    d.line([(cx, cy - 6), (cx, cy + 8)], fill=cols[5])
    # Arc fragments echo the arch silhouette and keep the glow pixel-sized.
    for arc in ((cx - rx + 7, cy - ry + 8, cx + rx - 7, cy + ry - 8),
                (cx - vrx - 4, cy - vry - 2, cx + vrx + 4, cy + vry + 2)):
        start = rng.choice([190, 205, 220])
        d.arc(arc, start, start + 120, fill=cols[3], width=1)
        d.arc((arc[0] + 2, arc[1] + 2, arc[2] - 2, arc[3] - 2), start + 14,
              start + 104, fill=cols[4], width=1)
    for _ in range(18):
        x = rng.randint(cx - vrx + 4, cx + vrx - 4)
        y = rng.randint(cy - vry + 6, cy + vry - 6)
        length = rng.randint(1, 3)
        d.line([(x, y), (x, y + length)], fill=cols[rng.choice([2, 3, 4])], width=1)
    for _ in range(7):
        x = rng.randint(cx - vrx + 5, cx + vrx - 5)
        y = rng.randint(cy - vry + 6, cy + vry - 6)
        d.point((x, y), fill=cols[5])
    composite_mask(img, layer, mask)


def draw_glow_motes(img, points, color=PALE_CYAN, faint=CYAN):
    d = ImageDraw.Draw(img)
    for x, y in points:
        d.point((x, y), fill=color)
        if (x + y) % 3 == 0:
            d.point((x + 1, y), fill=faint)


# ---------------------------------------------------------------------------
# 1. Dungeon waypoint: Stonegate Portal (primary), 5x4 tiles.
# ---------------------------------------------------------------------------

def make_portal_primary():
    W, H = 160, 128
    img = transparent((W, H))
    d = ImageDraw.Draw(img)
    opening = arch_mask((W, H), 54, 28, 106, 120, pointed=False)
    outer = mask_union(
        rect_mask((W, H), [(14, 12, 146, 120), (10, 106, 150, 123), (4, 120, 156, 126),
                           (20, 4, 46, 20), (114, 4, 140, 20), (62, 0, 98, 18),
                           (6, 100, 18, 121), (142, 100, 154, 121)]),
    )
    frame = ImageChops.subtract(outer, opening)
    masonry(img, frame, 101, base=STONE_BASE, course=10, block=20)

    # Warm edge stones and recessed grooves on the pillars.
    d = ImageDraw.Draw(img)
    d.rectangle([16, 34, 17, 104], fill=STONE_WARM)
    d.rectangle([142, 34, 143, 104], fill=STONE_WARM_HI)
    d.rectangle([18, 34, 19, 104], fill=STONE_DARK)
    d.rectangle([140, 34, 141, 104], fill=STONE_DARK)
    for y in (48, 76, 100):
        d.line([(16, y), (51, y)], fill=STONE_WARM, width=1)
        d.line([(109, y), (144, y)], fill=STONE_WARM, width=1)
    # Alternating quoin highlights and deep pillar recesses.
    for y in (36, 60, 88):
        d.rectangle([18, y, 26, y + 7], fill=STONE_MID)
        d.line([(18, y), (25, y)], fill=STONE_WARM_HI)
        d.rectangle([134, y, 142, y + 7], fill=STONE_MID)
        d.line([(134, y), (141, y)], fill=STONE_WARM_HI)
    d.line([(18, 13), (142, 13)], fill=STONE_WARM)
    d.line([(6, 121), (154, 121)], fill=STONE_WARM_HI)
    d.line([(6, 122), (154, 122)], fill=STONE_DARK)
    # Front steps, drawn as distinct risers rather than one flat base.
    for x0, x1, col, line_col in ((30, 130, STONE_MID, STONE_WARM),
                                   (38, 122, STONE_BASE, STONE_WARM_HI),
                                   (48, 112, STONE_DARK, STONE_LIGHT)):
        d.rectangle([x0, 117, x1, 126], fill=col)
        d.line([(x0, 117), (x1, 117)], fill=line_col)
        d.line([(x0, 126), (x1, 126)], fill=MORTAR)

    # Central keystone and crest.
    d.polygon([(72, 17), (88, 17), (91, 30), (69, 30)], fill=STONE_WARM)
    d.polygon([(74, 19), (86, 19), (88, 28), (72, 28)], fill=STONE_BASE)
    draw_rune(d, 76, 21, "diamond", GOLD_LIGHT, GOLD_DARK, 2)
    d.rectangle([64, 2, 96, 16], fill=STONE_MID)
    d.rectangle([66, 4, 94, 14], fill=STONE_BASE)
    d.polygon([(80, 1), (88, 8), (80, 16), (72, 8)], fill=GOLD_DARK)
    d.polygon([(80, 3), (85, 8), (80, 13), (75, 8)], fill=GOLD)
    draw_diamond(d, 80, 8, 3, 4, GOLD_LIGHT, CYAN, WHITE_GLOW)
    for sx in (24, 130):
        d.rectangle([sx, 5, sx + 8, 15], fill=STONE_DARK)
        d.rectangle([sx + 1, 6, sx + 7, 13], fill=STONE_MID)
        d.point((sx + 4, 9), fill=GOLD)

    # Opening bands: warm stone edge, violet magic frame, dark void.
    trim = opening
    fill_mask(img, trim, STONE_WARM)
    d = ImageDraw.Draw(img)
    inner2 = mask_inset_arch((W, H), 54, 28, 106, 120, 2)
    fill_mask(img, inner2, VIOLET_DARK)
    inner3 = mask_inset_arch((W, H), 54, 28, 106, 120, 3)
    fill_mask(img, inner3, VIOLET)
    inner4 = mask_inset_arch((W, H), 54, 28, 106, 120, 4)
    fill_mask(img, inner4, TEAL_DARK)
    inner5 = mask_inset_arch((W, H), 54, 28, 106, 120, 5)
    fill_mask(img, inner5, CYAN)
    inner6 = mask_inset_arch((W, H), 54, 28, 106, 120, 6)
    fill_mask(img, inner6, TEAL_DARK)
    draw_portal_energy(img, inner6, 80, 84, 22, 33, "teal", 11)

    # Threshold: a low lintel with a bright centre, plus carved runes.
    d = ImageDraw.Draw(img)
    d.rectangle([50, 112, 110, 121], fill=STONE_DARK)
    d.rectangle([52, 113, 108, 117], fill=STONE_BASE)
    d.line([(58, 116), (102, 116)], fill=CYAN)
    d.line([(64, 117), (96, 117)], fill=TEAL)
    for x, kind, y in [(25, "eye", 54), (25, "fork", 78), (127, "eye", 54), (127, "fork", 78)]:
        draw_rune(d, x, y, kind, GOLD, GOLD_DARK, 2)

    # Side crystals embedded in the outer pillars.
    for cx in (21, 139):
        d.polygon([(cx, 72), (cx + 4, 78), (cx + 2, 88), (cx - 2, 88), (cx - 4, 78)],
                  fill=TEAL_DEEP)
        d.polygon([(cx, 75), (cx + 2, 79), (cx + 1, 85), (cx - 1, 85), (cx - 2, 79)],
                  fill=CYAN)
        d.point((cx, 77), fill=WHITE_GLOW)
        d.point((cx + 3, 88), fill=TEAL)

    # Outline the architecture, then add highlights that should not be outlined.
    img = add_outline(img)
    add_moss(img, frame, 14, count=34, bounds=(4, 100, 156, 128))
    draw_glow_motes(img, [(66, 36), (95, 45), (72, 108), (90, 101), (82, 24),
                          (58, 90), (103, 81), (48, 114), (112, 114)])
    return img


# ---------------------------------------------------------------------------
# 2. Dungeon waypoint: Ancient Rune Gate (alternative), 6x5 tiles.
# ---------------------------------------------------------------------------

def make_portal_alt():
    W, H = 192, 160
    img = transparent((W, H))
    opening = arch_mask((W, H), 68, 34, 124, 146, pointed=True)
    outer = mask_union(
        poly_mask((W, H), [(10, 138), (13, 54), (28, 26), (53, 18), (61, 46), (58, 139)]),
        poly_mask((W, H), [(182, 138), (179, 54), (164, 24), (142, 18), (132, 46), (136, 139)]),
        rect_mask((W, H), [(28, 42, 164, 70), (38, 30, 154, 52), (12, 138, 180, 150),
                           (2, 150, 190, 158), (54, 136, 138, 149),
                           (6, 94, 24, 142), (168, 92, 186, 142)]),
    )
    # Break the upper-right lintel and add a jagged crown.
    damage = poly_mask((W, H), [(108, 20), (154, 20), (154, 38), (135, 33), (121, 45),
                                (104, 34)])
    outer = ImageChops.subtract(outer, damage)
    outer = mask_union(outer, poly_mask((W, H), [(64, 18), (86, 10), (96, 24), (80, 32)]))
    frame = ImageChops.subtract(outer, opening)
    masonry(img, frame, 202, base=(61, 59, 56, 255), course=9, block=19)

    d = ImageDraw.Draw(img)
    # Warm ancient trim and deep inset cracks.
    d.rectangle([32, 39, 160, 40], fill=STONE_WARM)
    d.rectangle([30, 41, 162, 42], fill=STONE_DARK)
    for x in (22, 48, 144, 168):
        d.line([(x, 50), (x, 132)], fill=STONE_DARK)
        d.line([(x + 1, 50), (x + 1, 132)], fill=STONE_LIGHT)
    for y in (78, 112):
        d.line([(16, y), (62, y)], fill=STONE_WARM)
        d.line([(130, y), (176, y)], fill=STONE_WARM)
    # Jagged cracks.
    for pts in [[(34, 60), (40, 66), (38, 76)], [(158, 58), (151, 68), (154, 82)],
                [(46, 104), (55, 110), (51, 124)], [(146, 102), (138, 112), (141, 126)]]:
        d.line(pts, fill=MORTAR, width=1)

    # Opening: ochre trim, violet ring, dark void.
    fill_mask(img, opening, STONE_WARM)
    d = ImageDraw.Draw(img)
    for inset, col in [(3, VIOLET_DARK), (5, VIOLET), (7, TEAL_DARK)]:
        fill_mask(img, mask_inset_arch((W, H), 68, 34, 124, 146, inset, True), col)
    energy_mask = mask_inset_arch((W, H), 68, 34, 124, 146, 9, True)
    draw_portal_energy(img, energy_mask, 96, 93, 21, 37, "violet", 22)
    # Inner gold rune ring.
    d = ImageDraw.Draw(img)
    d.arc([78, 52, 114, 110], 200, 520, fill=GOLD_DARK, width=1)
    d.arc([80, 54, 112, 108], 200, 520, fill=GOLD, width=1)
    for ang in (210, 250, 290, 330):
        x = 96 + int(math.cos(math.radians(ang)) * 16)
        y = 81 + int(math.sin(math.radians(ang)) * 23)
        d.point((x, y), fill=GOLD_LIGHT)

    # Broken crown crest + side crystal obelisks.
    d.polygon([(76, 10), (86, 2), (96, 12), (88, 24), (76, 18)], fill=STONE_DARK)
    d.polygon([(78, 10), (86, 5), (92, 12), (86, 20), (79, 16)], fill=STONE_MID)
    draw_diamond(d, 86, 12, 4, 6, GOLD, VIOLET, PALE_LILAC)
    for cx, base_y in [(15, 96), (177, 96)]:
        d.rectangle([cx - 6, base_y, cx + 6, base_y + 34], fill=STONE_DARK)
        d.rectangle([cx - 5, base_y + 2, cx + 5, base_y + 33], fill=STONE_BASE)
        d.polygon([(cx, 64), (cx + 6, 84), (cx + 3, 100), (cx - 3, 100), (cx - 6, 84)],
                  fill=VIOLET_DEEP)
        d.polygon([(cx, 68), (cx + 3, 84), (cx + 1, 95), (cx - 1, 95), (cx - 3, 84)],
                  fill=LILAC)
        d.point((cx, 74), fill=PALE_LILAC)
    for x, y, kind in [(30, 82, "spiral"), (150, 82, "spiral"), (42, 118, "fork"),
                       (138, 118, "fork"), (70, 28, "crown"), (114, 28, "crown")]:
        draw_rune(d, x, y, kind, GOLD, GOLD_DARK)

    # Base rubble and fallen stones.
    d.rectangle([4, 146, 26, 157], fill=RUBBLE)
    d.rectangle([158, 144, 186, 158], fill=RUBBLE)
    d.rectangle([166, 150, 182, 157], fill=STONE_DARK)
    d.rectangle([9, 150, 20, 157], fill=STONE_DARK)

    img = add_outline(img)
    add_moss(img, frame, 33, count=52, bounds=(0, 80, 192, 160))
    draw_glow_motes(img, [(66, 50), (124, 52), (84, 132), (108, 134), (96, 26),
                          (50, 70), (142, 74), (24, 92), (166, 92)])

    # A few dangling vines on the left pylon.
    d = ImageDraw.Draw(img)
    for x, y, n in [(20, 104, 13), (24, 112, 8), (156, 98, 16), (149, 106, 9)]:
        for i in range(n):
            d.point((x + (1 if i % 4 == 0 else 0), y + i), fill=MOSS if i % 3 else MOSS_DARK)
    return img


# ---------------------------------------------------------------------------
# 3. World waypoint: Beacon Tower (primary), 4x7 tiles.
# ---------------------------------------------------------------------------

def make_tower_primary():
    W, H = 128, 224
    img = transparent((W, H))
    d = ImageDraw.Draw(img)
    base = mask_union(
        rect_mask((W, H), [(2, 216, 126, 223), (10, 204, 118, 218), (18, 194, 110, 208)]),
        rect_mask((W, H), [(26, 132, 102, 198), (22, 120, 106, 136), (34, 78, 94, 128)]),
        rect_mask((W, H), [(14, 64, 114, 79), (14, 54, 26, 68), (32, 54, 44, 68),
                           (84, 54, 96, 68), (102, 54, 114, 68)]),
        rect_mask((W, H), [(34, 24, 94, 68)]),
        rect_mask((W, H), [(26, 12, 102, 28), (40, 4, 88, 16), (60, 0, 68, 8)]),
    )
    masonry(img, base, 303, base=STONE_BASE, course=10, block=19)

    d = ImageDraw.Draw(img)
    # Structural bands, quoin accents and wood supports.
    for y in (194, 132, 78, 28):
        d.line([(20, y), (108, y)], fill=STONE_DARK)
        d.line([(20, y - 1), (108, y - 1)], fill=STONE_WARM)
    for x in (26, 34, 94, 102):
        d.line([(x, 78), (x, 194)], fill=STONE_DARK)
    d.line([(32, 128), (96, 128)], fill=STONE_WARM)
    d.line([(34, 68), (94, 68)], fill=STONE_WARM)
    # Pale granite/diorite quoins break up the long dark shaft.
    for y, col in ((196, GRANITE), (166, DIORITE), (138, GRANITE), (108, DIORITE),
                   (84, GRANITE), (146, DIORITE), (170, GRANITE)):
        d.rectangle([24, y, 31, y + 6], fill=col)
        d.rectangle([97, y, 104, y + 6], fill=col)
        d.line([(24, y), (31, y)], fill=STONE_WARM_HI)
    # Balcony brackets.
    for x in (18, 106):
        d.polygon([(x, 79), (x + 8, 79), (x + 2, 93)], fill=WOOD_DARK)
        d.line([(x + 2, 82), (x + 6, 82)], fill=WOOD)
    d.line([(15, 63), (113, 63)], fill=STONE_WARM_HI)
    d.line([(15, 64), (113, 64)], fill=STONE_DARK)
    # Roof cap and spire, with slate courses and a gold beacon finial.
    d.rectangle([27, 13, 101, 27], fill=STONE_MID)
    d.line([(27, 13), (101, 13)], fill=STONE_WARM_HI)
    d.line([(27, 27), (101, 27)], fill=MORTAR)
    for y in (18, 23):
        d.line([(30, y), (98, y)], fill=STONE_DARK)
        d.line([(34, y + 1), (94, y + 1)], fill=STONE_LIGHT)
    d.polygon([(40, 12), (50, 4), (62, 0), (66, 0), (78, 4), (88, 12)],
              fill=STONE_MID)
    d.line([(42, 12), (50, 5), (62, 1)], fill=STONE_WARM_HI)
    d.line([(86, 12), (78, 5), (66, 1)], fill=STONE_DARK)
    d.polygon([(60, 0), (68, 0), (70, 7), (58, 7)], fill=STONE_DARK)
    d.line([(63, 1), (66, 1)], fill=STONE_WARM_HI)
    d.polygon([(64, 0), (66, 3), (64, 6), (62, 3)], fill=GOLD)
    d.point((64, 2), fill=AMBER_PALE)

    # Hanging teal waypoint pennant on the shaft.
    d.rectangle([52, 83, 76, 86], fill=WOOD_DARK)
    d.line([(52, 83), (76, 83)], fill=WOOD_LIGHT)
    d.polygon([(56, 86), (72, 86), (72, 112), (64, 118), (56, 112)], fill=TEAL_DEEP)
    d.line([(56, 86), (56, 112)], fill=GOLD_DARK)
    d.line([(71, 86), (71, 112)], fill=GOLD_DARK)
    draw_diamond(d, 64, 98, 5, 6, GOLD, PALE_CYAN, WHITE_GLOW)

    # Carved base panel and waypoint sigil.
    d.rectangle([46, 174, 82, 204], fill=STONE_DARK)
    d.rectangle([48, 176, 80, 202], fill=STONE_MID)
    d.rectangle([51, 179, 77, 199], fill=STONE_BASE)
    draw_diamond(d, 64, 188, 13, 12, GOLD_DARK)
    draw_diamond(d, 64, 188, 10, 9, GOLD)
    draw_diamond(d, 64, 188, 4, 3, CYAN, WHITE_GLOW)
    for ang in range(0, 360, 90):
        x = 64 + int(math.cos(math.radians(ang)) * 14)
        y = 188 + int(math.sin(math.radians(ang)) * 12)
        d.point((x, y), fill=GOLD_LIGHT)
    # Small central stair.
    d.rectangle([48, 205, 80, 223], fill=STONE_DARK)
    for i, y in enumerate((210, 215, 220)):
        d.rectangle([48 + i * 3, y, 80 - i * 3, y + 2], fill=STONE_BASE)
        d.line([(48 + i * 3, y), (80 - i * 3, y)], fill=STONE_WARM)

    # Slit windows with warm interior light.
    for x, y, h in [(42, 146, 24), (79, 146, 24), (46, 94, 18), (74, 94, 18)]:
        d.rectangle([x - 2, y - 2, x + 4, y + h + 2], fill=STONE_DARK)
        d.rectangle([x, y, x + 2, y + h], fill=AMBER_DARK)
        d.rectangle([x, y + 2, x + 1, y + h - 2], fill=AMBER)
        d.point((x, y + h - 4), fill=AMBER_PALE)

    # Belfry: an arched dark opening with a hanging beacon lantern rather than
    # a rectangular lit window.
    belfry_out = arch_mask((W, H), 43, 26, 85, 65, pointed=False)
    fill_mask(img, belfry_out, STONE_WARM)
    belfry_in = mask_inset_arch((W, H), 43, 26, 85, 65, 2)
    fill_mask(img, belfry_in, STONE_DARK)
    belfry_void = mask_inset_arch((W, H), 43, 26, 85, 65, 4)
    fill_mask(img, belfry_void, (27, 23, 20, 255))
    d = ImageDraw.Draw(img)
    d.line([(64, 28), (64, 33)], fill=IRON_LIGHT)
    d.rectangle([53, 33, 75, 62], fill=IRON_DARK)
    d.rectangle([56, 36, 72, 59], fill=AMBER_DARK)
    d.rectangle([58, 38, 70, 57], fill=AMBER)
    d.rectangle([60, 41, 68, 54], fill=AMBER_LIGHT)
    d.point((62, 45), fill=AMBER_PALE)
    d.point((65, 47), fill=WHITE_GLOW)
    d.line([(53, 47), (75, 47)], fill=IRON)
    d.line([(64, 33), (64, 62)], fill=IRON)
    d.rectangle([50, 60, 78, 64], fill=IRON)
    d.polygon([(51, 33), (64, 27), (77, 33)], fill=IRON_DARK)
    d.point((64, 30), fill=GOLD)
    # Warm rim glow around the belfry arch.
    for x, y in [(45, 30), (43, 40), (44, 54), (84, 30), (86, 40), (85, 54),
                 (52, 25), (76, 25), (64, 24)]:
        d.point((x, y), fill=AMBER)

    img = add_outline(img)
    add_moss(img, base, 44, count=32, bounds=(4, 186, 124, 224))
    # Warm halo motes around the lantern, sparse enough to remain pixel-readable.
    draw_glow_motes(img, [(48, 38), (80, 36), (50, 55), (77, 58), (60, 24),
                          (70, 24), (43, 46), (84, 47)], AMBER_PALE, AMBER_LIGHT)
    return img


# ---------------------------------------------------------------------------
# 4. World waypoint: Ruined Skyglass Tower (alternative), 5x7 tiles.
# ---------------------------------------------------------------------------

def draw_skyglass_beacon(img, phase=0.0):
    """Draw the animated floating crystal / shards / glow for one frame.

    phase is 0..1. The tower body is static; this overlay is the animated part.
    """
    W, H = img.size
    d = ImageDraw.Draw(img)
    two_pi = math.pi * 2.0
    bob = round(math.sin(phase * two_pi) * 2)
    cx = 82
    cy = 50 + bob

    # Rune ring: mostly static, with a traveling brighter rune.
    for i, ang in enumerate(range(0, 360, 45)):
        x = 82 + int(math.cos(math.radians(ang)) * 17)
        y = 50 + int(math.sin(math.radians(ang)) * 22)
        if 58 < y < 78:
            active = (i + int(phase * 8)) % 4 == 0
            d.point((x, y), fill=GOLD_LIGHT if active else GOLD)

    # Four shards orbit the crystal in opposite visual directions.
    for i in range(4):
        ang = phase * two_pi + i * math.pi / 2
        sx = int(82 + math.cos(ang) * 21)
        sy = int(50 + math.sin(ang) * 26)
        d.polygon([(sx, sy - 5), (sx + 3, sy), (sx, sy + 5), (sx - 3, sy)],
                  fill=OUTLINE)
        d.polygon([(sx, sy - 4), (sx + 2, sy), (sx, sy + 4), (sx - 2, sy)],
                  fill=TEAL if i % 2 == 0 else CYAN)
        d.point((sx, sy - 1), fill=PALE_CYAN)

    # Crystal silhouette and facets.
    outer = [(cx, cy - 26), (cx + 11, cy - 8), (cx + 8, cy + 16),
             (cx, cy + 26), (cx - 8, cy + 16), (cx - 11, cy - 8)]
    inner = [(cx, cy - 23), (cx + 8, cy - 7), (cx + 6, cy + 14),
             (cx, cy + 23), (cx - 6, cy + 14), (cx - 8, cy - 7)]
    d.polygon(outer, fill=OUTLINE)
    d.polygon(inner, fill=TEAL_DEEP)
    d.polygon([(cx, cy - 21), (cx - 7, cy - 7), (cx - 4, cy + 11), (cx, cy + 19)],
              fill=TEAL)
    d.polygon([(cx, cy - 21), (cx + 7, cy - 7), (cx + 4, cy + 11), (cx, cy + 19)],
              fill=CYAN)
    shimmer = int(phase * 8)
    if shimmer % 2 == 0:
        d.polygon([(cx, cy - 17), (cx + 2, cy - 2), (cx, cy + 12), (cx - 2, cy - 2)],
                  fill=PALE_CYAN)
        d.point((cx, cy - 10), fill=WHITE_GLOW)
    else:
        d.polygon([(cx, cy - 12), (cx + 3, cy), (cx, cy + 16), (cx - 3, cy)],
                  fill=PALE_CYAN)
        d.point((cx, cy + 6), fill=WHITE_GLOW)
    # A faint one-pixel aura, kept inside the crown area.
    for i in range(8):
        ang = phase * two_pi + i * math.pi / 4
        gx = int(82 + math.cos(ang) * 25)
        gy = int(50 + math.sin(ang) * 29)
        d.point((gx, gy), fill=PALE_CYAN if i % 2 == 0 else TEAL)
    for i in range(4):
        ang = phase * two_pi + i * math.pi / 2 + 0.4
        gx = int(82 + math.cos(ang) * 29)
        gy = int(50 + math.sin(ang) * 33)
        d.point((gx, gy), fill=TEAL)


def make_tower_alt(include_beacon=True, phase=0.0):
    W, H = 160, 224
    img = transparent((W, H))
    opening = empty_mask((W, H))
    body = mask_union(
        # lower mass and collapsed plinth
        poly_mask((W, H), [(4, 214), (14, 194), (24, 150), (38, 140), (42, 198),
                           (52, 208), (124, 208), (136, 192), (146, 148), (126, 142),
                           (120, 194), (44, 198), (28, 214)]),
        # central front wall, still standing below the broken crown
        rect_mask((W, H), [(40, 100, 124, 202), (32, 154, 136, 204)]),
        # jagged left and right upper walls
        poly_mask((W, H), [(40, 100), (40, 44), (48, 28), (58, 42), (66, 24),
                           (72, 56), (68, 100)]),
        poly_mask((W, H), [(98, 100), (98, 82), (108, 68), (118, 86), (128, 74),
                           (132, 100)]),
        rect_mask((W, H), [(30, 150, 44, 204), (128, 144, 142, 202)]),
    )
    # break out the crown between the two upper walls, above the front wall
    body = ImageChops.subtract(body, rect_mask((W, H), [(68, 54, 96, 100)]))
    # big arched window is drawn as an opaque recess, not transparent
    masonry(img, body, 404, base=(57, 58, 57, 255), course=10, block=18)
    d = ImageDraw.Draw(img)

    # Broken masonry bands and buttress details.
    for x in (26, 40, 96, 120):
        d.line([(x, 148), (x, 205)], fill=STONE_DARK)
    for y in (160, 198):
        d.line([(18, y), (140, y)], fill=STONE_WARM if y == 198 else STONE_DARK)
    d.line([(40, 101), (124, 101)], fill=STONE_WARM)
    d.line([(40, 152), (124, 152)], fill=STONE_DARK)
    for y, x in ((168, 34), (184, 126), (144, 30), (188, 136), (116, 44)):
        d.rectangle([x, y, x + 7, y + 5], fill=GRANITE if (x + y) % 2 else DIORITE)
        d.line([(x, y), (x + 7, y)], fill=STONE_WARM_HI)
    for pts in [[(46, 62), (54, 70), (50, 82), (60, 90)], [(116, 120), (108, 132), (112, 142)],
                [(34, 168), (42, 176), (38, 190)], [(82, 194), (92, 200), (88, 207)]]:
        d.line(pts, fill=MORTAR)

    # Large broken window with teal inner glow.
    d.rectangle([66, 120, 98, 170], fill=STONE_DARK)
    d.rectangle([69, 124, 95, 168], fill=(16, 29, 29, 255))
    d.polygon([(69, 124), (82, 110), (95, 124)], fill=STONE_DARK)
    d.polygon([(72, 124), (82, 113), (92, 124)], fill=(21, 43, 42, 255))
    d.line([(82, 118), (82, 166)], fill=IRON)
    d.line([(70, 146), (94, 146)], fill=IRON)
    d.point((78, 140), fill=CYAN)
    d.point((86, 150), fill=PALE_CYAN)
    d.point((80, 158), fill=TEAL)
    draw_rune(d, 76, 178, "eye", GOLD, GOLD_DARK, 2)
    d.point((82, 181), fill=GOLD_LIGHT)

    # Base rubble and collapsed side buttress.
    d.rectangle([4, 214, 156, 223], fill=RUBBLE)
    d.rectangle([2, 218, 38, 223], fill=STONE_DARK)
    d.rectangle([124, 214, 158, 222], fill=STONE_DARK)
    d.rectangle([44, 206, 118, 222], fill=STONE_DARK)
    for x, y, w in [(8, 210, 10), (22, 206, 8), (130, 210, 12), (146, 205, 8)]:
        d.rectangle([x, y, x + w, y + 4], fill=STONE_BASE)
        d.line([(x, y), (x + w, y)], fill=STONE_WARM)
    # Wooden brace on the broken side.
    d.line([(112, 146), (136, 190)], fill=WOOD_DARK, width=3)
    d.line([(113, 147), (134, 188)], fill=WOOD, width=1)
    d.line([(122, 164), (130, 164)], fill=WOOD_LIGHT, width=1)

    # Static broken stone ring in the crown; the floating crystal itself is
    # drawn by draw_skyglass_beacon() so it can animate independently.
    d.arc([64, 22, 100, 70], 195, 510, fill=STONE_MID, width=2)
    d.arc([66, 24, 98, 68], 195, 510, fill=STONE_WARM, width=1)

    img = add_outline(img)
    add_moss(img, body, 55, count=50, bounds=(2, 54, 158, 224))
    # Vines down the left broken wall.
    d = ImageDraw.Draw(img)
    for x, y, n in [(48, 74, 32), (52, 112, 20), (28, 154, 18)]:
        for i in range(n):
            d.point((x + (1 if i % 5 == 0 else 0), y + i),
                    fill=MOSS if i % 3 else MOSS_DARK)
    if include_beacon:
        draw_skyglass_beacon(img, phase)
    return img


# ---------------------------------------------------------------------------
# Preview helpers
# ---------------------------------------------------------------------------

def load_font(size):
    return ImageFont.truetype(FONT, size)


def checkerboard(size, cell=8, a=(36, 39, 44, 255), b=(44, 48, 54, 255)):
    img = Image.new("RGBA", size, a)
    d = ImageDraw.Draw(img)
    for y in range(0, size[1], cell):
        for x in range(0, size[0], cell):
            if ((x // cell) + (y // cell)) % 2:
                d.rectangle([x, y, x + cell - 1, y + cell - 1], fill=b)
    return img


def shadowed_scaled(img, scale):
    nw, nh = int(img.width * scale), int(img.height * scale)
    return img.resize((nw, nh), Image.Resampling.NEAREST)


def label(draw, xy, text, size=18, fill=(235, 229, 210, 255)):
    draw.text(xy, text, font=load_font(size), fill=fill)


def make_closeup_sheet(portal_p, portal_a, tower_p, tower_a):
    W, H = 1800, 1540
    img = checkerboard((W, H), 10)
    d = ImageDraw.Draw(img)
    d.rectangle([0, 0, W, 86], fill=(20, 23, 27, 255))
    label(d, (36, 22), "SandEE — Waypoint Sprite Draft", 40, (245, 238, 216, 255))
    label(d, (W - 560, 30), "CONCEPT / NOT IMPLEMENTED", 26, (255, 181, 76, 255))

    cells = [
        (30, 110, 850, 630, portal_p, "1. Dungeon Waypoint — Stonegate Portal", "Primary · 5×4 tiles · 160×128 px", 4.0),
        (900, 110, 870, 630, portal_a, "2. Dungeon Waypoint — Ancient Rune Gate", "Alternative · 6×5 tiles · 192×160 px", 3.8),
        (30, 760, 850, 650, tower_p, "3. World Waypoint — Beacon Tower", "Primary · 4×7 tiles · 128×224 px", 2.4),
        (900, 760, 870, 650, tower_a, "4. World Waypoint — Ruined Skyglass Tower", "Alternative · 5×7 tiles · 160×224 px", 2.2),
    ]
    for x, y, cw, ch, sprite, title, sub, scale in cells:
        d.rectangle([x, y, x + cw, y + ch], fill=(28, 32, 38, 235), outline=(75, 81, 89, 255))
        label(d, (x + 24, y + 18), title, 27)
        label(d, (x + 24, y + 52), sub, 20, (188, 181, 157, 255))
        up = shadowed_scaled(sprite, scale)
        max_w = cw - 52
        max_h = ch - 130
        if up.width > max_w or up.height > max_h:
            factor = min(max_w / up.width, max_h / up.height)
            up = up.resize((max(1, int(up.width * factor)), max(1, int(up.height * factor))),
                           Image.Resampling.NEAREST)
        px = x + (cw - up.width) // 2
        py = y + ch - up.height - 30
        sh = Image.new("RGBA", up.size, (0, 0, 0, 70))
        img.alpha_composite(sh, (px + 8, py + 10))
        img.alpha_composite(up, (px, py))

    # Existing material reference strip with real block swatches.
    atlas = Image.open(os.path.join(GAME, "sprites/items/item_atlas.png")).convert("RGBA")
    refs = [("Stone", atlas.crop((64, 0, 96, 32))),
            ("Granite", Image.open(os.path.join(GAME, "sprites/items/granite.png")).convert("RGBA")),
            ("Diorite", Image.open(os.path.join(GAME, "sprites/items/diorite.png")).convert("RGBA")),
            ("Sandstone", Image.open(os.path.join(GAME, "sprites/items/sandstone.png")).convert("RGBA")),
            ("Wood", atlas.crop((0, 0, 32, 32)))]
    d.rectangle([18, H - 148, W - 18, H - 12], fill=(20, 23, 27, 255))
    label(d, (36, H - 140), "Existing block materials referenced", 20, (238, 230, 208, 255))
    x = 36
    for name, tex in refs:
        label(d, (x, H - 114), name, 15, (188, 181, 157, 255))
        tex = tex.resize((64, 64), Image.Resampling.NEAREST)
        img.alpha_composite(tex, (x, H - 96))
        x += 104
    label(d, (W - 640, H - 32), "Standalone draft PNGs; existing assets are reference-only.",
          16, (145, 140, 124, 255))
    return img


def make_world_preview(portal_p, portal_a, tower_p, tower_a):
    # Build an in-world mock at approximately the game's 1.9x camera zoom.
    scale = 1.9
    W, H = 1640, 1370
    grass = (136, 190, 33, 255)
    grass_dark = (104, 179, 28, 255)
    grass_light = (154, 214, 55, 255)
    img = Image.new("RGBA", (W, H), grass)
    rng = random.Random(909)
    d = ImageDraw.Draw(img)
    # Subtle ground flecks, matching the screenshot palette.
    for _ in range(5600):
        x = rng.randrange(W)
        y = rng.randrange(H)
        c = grass_dark if rng.random() < 0.55 else grass_light
        d.point((x, y), fill=c)
    for _ in range(1100):
        x = rng.randrange(W)
        y = rng.randrange(H)
        d.line([(x, y), (x + 2, y - 2)], fill=grass_dark)
    d.rectangle([0, 0, W, 88], fill=(21, 24, 27, 255))
    label(d, (32, 20), "SandEE — Waypoint World-Scale Mock", 36, (245, 238, 216, 255))
    label(d, (W - 670, 27), "Approx. 1.9× zoom · transparent sprite drafts", 22, (198, 190, 167, 255))

    tree = Image.open(os.path.join(GAME, "sprites/tree/tree.png")).convert("RGBA")
    player = Image.open(os.path.join(GAME, "sprites/char/steve/rotations/south.png")).convert("RGBA")
    grass_tex = Image.open(os.path.join(GAME, "sprites/ground/grass.png")).convert("RGBA").crop((0, 0, 96, 96))

    def place_sprite(sprite, cx, foot_y, sc=scale):
        up = shadowed_scaled(sprite, sc)
        px = int(cx - up.width / 2)
        py = int(foot_y - up.height)
        img.alpha_composite(up, (px, py))

    def put_player(x, feet):
        up = shadowed_scaled(player, 1.5 * scale)
        img.alpha_composite(up, (int(x - up.width / 2), int(feet - up.height)))

    # Scenes in a 2-column layout; the tower row gets more headroom.
    scenes = [
        (30, 100, 780, 500, portal_p, "1 · Stonegate Portal — Primary", "Dungeon waypoint · 5×4 tiles"),
        (830, 100, 780, 500, portal_a, "2 · Ancient Rune Gate — Alternative", "Dungeon waypoint · 6×5 tiles"),
        (30, 640, 780, 650, tower_p, "3 · Beacon Tower — Primary", "World waypoint · 4×7 tiles"),
        (830, 640, 780, 650, tower_a, "4 · Ruined Skyglass Tower — Alternative", "World waypoint · 5×7 tiles"),
    ]
    for idx, (sx, sy, sw, sh, sprite, title, sub) in enumerate(scenes):
        d.rectangle([sx, sy, sx + sw, sy + 42], fill=(21, 24, 27, 190))
        label(d, (sx + 14, sy + 8), title, 21, (245, 238, 216, 255))
        label(d, (sx + sw - 245, sy + 11), sub, 16, (198, 190, 167, 255))
        base_x = sx + sw // 2
        foot = sy + sh - 44
        # grass tufts, kept clear of the structure base
        for gx, gy, sc in [(sx + 80, sy + sh - 65, 1.9), (sx + 120, sy + sh - 30, 1.9),
                           (sx + sw - 100, sy + sh - 50, 1.9), (sx + sw - 50, sy + sh - 20, 1.9)]:
            up = shadowed_scaled(grass_tex, sc)
            img.alpha_composite(up, (int(gx - up.width / 2), int(gy - up.height)))
        # tree at the side/back, avoiding the title band
        tree_up = shadowed_scaled(tree, scale)
        tx = sx + 110 if idx % 2 == 0 else sx + sw - 115
        ty = sy + sh - 30
        img.alpha_composite(tree_up, (int(tx - tree_up.width / 2), int(ty - tree_up.height)))
        # shadow under the structure
        shadow = Image.new("RGBA", (int(sprite.width * scale * 0.7), int(26 * scale)), (0, 0, 0, 0))
        sd = ImageDraw.Draw(shadow)
        sd.ellipse([0, 0, shadow.width - 1, shadow.height - 1], fill=(0, 0, 0, 40))
        img.alpha_composite(shadow, (int(base_x - shadow.width / 2), int(foot - shadow.height / 2)))
        # draft structure at game scale
        place_sprite(sprite, base_x, foot)
        # player for scale, in front
        px = base_x - sw * 0.35 if idx < 2 else base_x + sw * 0.36
        put_player(px, foot + 8)
    # footer
    d.rectangle([0, H - 46, W, H], fill=(21, 24, 27, 255))
    label(d, (30, H - 38), "Draft only — no gameplay, spawning, teleportation, or production asset changes.", 19,
          (198, 190, 167, 255))
    return img


def make_comparison_sheet(portal_p, portal_a, tower_p, tower_a):
    W, H = 1480, 820
    img = checkerboard((W, H), 10, (40, 44, 49, 255), (47, 52, 58, 255))
    d = ImageDraw.Draw(img)
    d.rectangle([0, 0, W, 74], fill=(20, 23, 27, 255))
    label(d, (24, 16), "Waypoint silhouettes — common 2× preview", 30, (245, 238, 216, 255))
    label(d, (W - 340, 24), "Draft / not implemented", 20, (255, 181, 76, 255))
    items = [(portal_p, "Stonegate Portal", 2.0), (portal_a, "Ancient Rune Gate", 2.0),
             (tower_p, "Beacon Tower", 2.0), (tower_a, "Skyglass Ruin", 2.0)]
    x = 34
    baseline = 710
    for sprite, name, sc in items:
        up = shadowed_scaled(sprite, sc)
        y = baseline - up.height
        img.alpha_composite(up, (x, y))
        d.rectangle([x, baseline + 8, x + up.width, baseline + 11], fill=(130, 124, 108, 255))
        label(d, (x + 4, baseline + 18), name, 20, (238, 230, 208, 255))
        label(d, (x + 4, baseline + 44), f"{sprite.width}×{sprite.height} px", 16,
              (165, 160, 144, 255))
        x += up.width + 36
    label(d, (34, H - 34), "Drawn at 32 px per world tile · same scale across all four silhouettes.",
          16, (165, 160, 144, 255))
    return img


def main():
    portal_p = make_portal_primary()
    portal_a = make_portal_alt()
    tower_p = make_tower_primary()
    tower_a = make_tower_alt()

    names = {
        "portal_primary.png": portal_p,
        "portal_alt_ancient.png": portal_a,
        "tower_primary.png": tower_p,
        "tower_alt_ruined.png": tower_a,
    }
    for name, sprite in names.items():
        sprite.save(os.path.join(SPRITE_DIR, name))
        shadowed_scaled(sprite, 4).save(os.path.join(SPRITE_DIR, name.replace(".png", "_x4.png")))

    make_closeup_sheet(portal_p, portal_a, tower_p, tower_a).save(os.path.join(ROOT, "waypoint_closeups.png"))
    make_world_preview(portal_p, portal_a, tower_p, tower_a).save(os.path.join(ROOT, "waypoint_world_mock.png"))
    make_comparison_sheet(portal_p, portal_a, tower_p, tower_a).save(os.path.join(ROOT, "waypoint_silhouettes.png"))



if __name__ == "__main__":
    main()
