import math
import os
import sys

from PIL import Image, ImageDraw

HERE = os.path.dirname(os.path.abspath(__file__))
if HERE not in sys.path:
    sys.path.insert(0, HERE)
import build_waypoint_drafts as b

ROOT = os.path.join(HERE, "revised")
SPRITES = os.path.join(ROOT, "sprites")
FRAMES = os.path.join(ROOT, "frames")
os.makedirs(SPRITES, exist_ok=True)
os.makedirs(FRAMES, exist_ok=True)

# Language palette references:
# Python editor colours come from extension/python.svg + language_spec.gd.
# Lua editor colours come from extension/lua.svg.
PY_BLUE_DARK = (70, 100, 170, 255)
PY_BLUE = (138, 173, 244, 255)
PY_BLUE_LIGHT = (207, 227, 255, 255)
PY_GOLD_DARK = (143, 104, 44, 255)
PY_GOLD = (238, 212, 159, 255)
PY_GOLD_LIGHT = (255, 243, 206, 255)
LUA_BLUE_DARK = (20, 48, 112, 255)
LUA_BLUE = (30, 102, 245, 255)
LUA_BLUE_LIGHT = (137, 180, 250, 255)
LUA_PALE = (212, 231, 255, 255)
LUA_SLATE = (76, 79, 105, 255)


def make_python_mark():
    """Two interlocking crystal shards using Python's blue/gold mark colours."""
    img = b.transparent((18, 18))
    d = ImageDraw.Draw(img)
    # Left blue shard.
    d.polygon([(8, 1), (3, 4), (2, 10), (7, 16), (9, 12), (6, 9), (9, 5)],
              fill=PY_BLUE_DARK)
    d.polygon([(8, 3), (4, 5), (4, 9), (7, 13), (8, 10), (6, 8), (8, 5)],
              fill=PY_BLUE)
    d.polygon([(6, 4), (4, 6), (5, 8), (7, 10)], fill=PY_BLUE_LIGHT)
    # Right gold shard.
    d.polygon([(10, 1), (15, 4), (16, 10), (11, 16), (9, 12), (12, 9), (9, 5)],
              fill=PY_GOLD_DARK)
    d.polygon([(10, 3), (14, 5), (14, 9), (11, 13), (10, 10), (12, 8), (10, 5)],
              fill=PY_GOLD)
    d.polygon([(12, 4), (14, 6), (13, 8), (11, 10)], fill=PY_GOLD_LIGHT)
    # Interlock notch.
    d.line([(9, 6), (9, 11)], fill=b.OUTLINE)
    d.point((8, 4), fill=PY_GOLD_LIGHT)
    d.point((10, 13), fill=PY_BLUE_LIGHT)
    return b.add_outline(img)


def make_lua_mark():
    """A faceted blue orb + crescent + tiny satellite, using Lua mark colours."""
    img = b.transparent((18, 18))
    d = ImageDraw.Draw(img)
    # Orb.
    d.ellipse([1, 2, 16, 17], fill=LUA_BLUE_DARK)
    d.ellipse([3, 4, 14, 15], fill=LUA_BLUE)
    d.arc([4, 5, 13, 14], 100, 250, fill=LUA_BLUE_LIGHT, width=1)
    # Crescent cutout (transparent), then a pale inner rim.
    d.ellipse([6, 2, 17, 13], fill=(0, 0, 0, 0))
    d.arc([4, 5, 13, 14], 125, 235, fill=LUA_PALE, width=1)
    # Small satellite crystal.
    d.polygon([(14, 0), (17, 3), (14, 6), (11, 3)], fill=LUA_BLUE_DARK)
    d.polygon([(14, 1), (16, 3), (14, 5), (12, 3)], fill=LUA_BLUE_LIGHT)
    d.point((14, 2), fill=LUA_PALE)
    d.point((7, 9), fill=LUA_PALE)
    return b.add_outline(img)


def place_language_mark(portal, mark, cx, cy, accent, secondary):
    d = ImageDraw.Draw(portal)
    # Stone-and-gold setting for the language crystal.
    r = 12
    d.polygon([(cx, cy - r), (cx + r, cy), (cx, cy + r), (cx - r, cy)], fill=b.OUTLINE)
    d.polygon([(cx, cy - r + 1), (cx + r - 1, cy), (cx, cy + r - 1), (cx - r + 1, cy)],
              fill=b.GOLD_DARK)
    d.polygon([(cx, cy - r + 2), (cx + r - 2, cy), (cx, cy + r - 2), (cx - r + 2, cy)],
              fill=b.GOLD)
    d.polygon([(cx, cy - r + 4), (cx + r - 4, cy), (cx, cy + r - 4), (cx - r + 4, cy)],
              fill=b.STONE_DARK)
    d.polygon([(cx, cy - r + 5), (cx + r - 5, cy), (cx, cy + r - 5), (cx - r + 5, cy)],
              fill=b.STONE_BASE)
    portal.alpha_composite(mark, (cx - 9, cy - 9))
    # Sparse language-coloured motes make the mark readable at 1.9x.
    for x, y, col in [(cx - 16, cy - 7, accent), (cx + 15, cy - 4, secondary),
                      (cx - 11, cy + 14, secondary), (cx + 12, cy + 13, accent),
                      (cx - 18, cy + 2, secondary), (cx + 18, cy + 5, accent)]:
        d.point((x, y), fill=col)


def make_python_portal():
    portal = b.make_portal_primary()
    place_language_mark(portal, make_python_mark(), 80, 11,
                        PY_BLUE_LIGHT, PY_GOLD_LIGHT)
    return portal


def make_lua_portal():
    portal = b.make_portal_alt()
    place_language_mark(portal, make_lua_mark(), 86, 13,
                        LUA_BLUE_LIGHT, LUA_PALE)
    return portal


def animate_python_portal(portal, phase):
    """Animated cyan/green veil, blue/gold mark aura and crystal glints."""
    img = portal.copy()
    W, H = img.size
    two_pi = math.pi * 2.0
    mask = b.mask_inset_arch((W, H), 54, 28, 106, 120, 6)
    layer = b.transparent((W, H))
    d = ImageDraw.Draw(layer)
    cx, cy = 80, 84
    pulse = (math.sin(phase * two_pi) + 1.0) * 0.5
    # Thin rotating veil arcs.
    for k, col in enumerate([b.TEAL, b.CYAN, b.PALE_CYAN]):
        rx = 12 + k * 4
        ry = 20 + k * 5
        start = 20 + phase * 360.0 + k * 42
        d.arc([cx - rx, cy - ry, cx + rx, cy + ry], start, start + 95,
              fill=col, width=1)
    # Pulsing bright core.
    core = 8 + round(pulse * 4)
    d.ellipse([cx - 4, cy - core, cx + 4, cy + core], fill=b.TEAL)
    d.ellipse([cx - 2, cy - core + 3, cx + 2, cy + core - 3], fill=b.PALE_CYAN)
    d.line([(cx, cy - 3), (cx, cy + 5)], fill=b.WHITE_GLOW)
    # Wandering energy strands.
    for i in range(3):
        phase_i = phase * two_pi + i * 2.1
        for yy in range(-20, 21, 3):
            x = cx + int(math.sin(phase_i + yy * 0.18) * (7 + i * 3))
            y = cy + yy
            d.point((x, y), fill=[b.TEAL, b.CYAN, b.PALE_CYAN][i])
    # Motes drifting through the opening.
    for i in range(9):
        ang = phase * two_pi + i * math.pi * 2 / 9
        x = cx + int(math.cos(ang) * (9 + (i % 3) * 5))
        y = cy + int(math.sin(ang) * (19 + (i % 2) * 5))
        d.point((x, y), fill=b.PALE_CYAN if i % 2 else b.CYAN)
    b.composite_mask(img, layer, mask)

    # Python mark aura + side-crystal glints (not clipped by the doorway).
    d = ImageDraw.Draw(img)
    for i in range(6):
        ang = phase * two_pi + i * math.pi / 3
        x = 80 + int(math.cos(ang) * 15)
        y = 11 + int(math.sin(ang) * 12)
        d.point((x, y), fill=PY_BLUE_LIGHT if i % 2 else PY_GOLD_LIGHT)
    glint = int(phase * 8)
    d.point((21, 75 + (glint % 3)), fill=PY_BLUE_LIGHT)
    d.point((139, 81 - (glint % 2)), fill=PY_GOLD_LIGHT)
    d.point((80, 116), fill=b.CYAN if glint % 2 else b.PALE_CYAN)
    return img


def animate_lua_portal(portal, phase):
    """Animated violet veil, rotating gold rune points and Lua mark aura."""
    img = portal.copy()
    W, H = img.size
    two_pi = math.pi * 2.0
    mask = b.mask_inset_arch((W, H), 68, 34, 124, 146, 9, True)
    layer = b.transparent((W, H))
    d = ImageDraw.Draw(layer)
    cx, cy = 96, 93
    pulse = (math.sin(phase * two_pi) + 1.0) * 0.5
    for k, col in enumerate([b.VIOLET_DEEP, b.VIOLET, b.LILAC]):
        rx = 11 + k * 4
        ry = 21 + k * 6
        start = 24 + phase * 360.0 + k * 46
        d.arc([cx - rx, cy - ry, cx + rx, cy + ry], start, start + 100,
              fill=col, width=1)
    core = 9 + round(pulse * 4)
    d.ellipse([cx - 4, cy - core, cx + 4, cy + core], fill=b.VIOLET_DEEP)
    d.ellipse([cx - 2, cy - core + 3, cx + 2, cy + core - 3], fill=b.PALE_LILAC)
    d.line([(cx, cy - 3), (cx, cy + 5)], fill=(251, 246, 255, 255))
    # Gold rune points travel around the inner ring.
    for i in range(8):
        ang = phase * two_pi + i * math.pi / 4
        x = cx + int(math.cos(ang) * 17)
        y = cy + int(math.sin(ang) * 23)
        d.point((x, y), fill=b.GOLD_LIGHT if i % 2 == 0 else b.GOLD)
    for i in range(7):
        ang = phase * two_pi + i * math.pi * 2 / 7
        x = cx + int(math.cos(ang) * (8 + (i % 2) * 6))
        y = cy + int(math.sin(ang) * (18 + (i % 3) * 4))
        d.point((x, y), fill=b.PALE_LILAC if i % 2 else b.LILAC)
    b.composite_mask(img, layer, mask)

    d = ImageDraw.Draw(img)
    for i in range(6):
        ang = phase * two_pi + i * math.pi / 3
        x = 86 + int(math.cos(ang) * 14)
        y = 13 + int(math.sin(ang) * 11)
        d.point((x, y), fill=LUA_BLUE_LIGHT if i % 2 else LUA_PALE)
    # A tiny satellite shard visibly orbits the Lua mark.
    ang = phase * two_pi
    sx = 86 + int(math.cos(ang) * 14)
    sy = 13 + int(math.sin(ang) * 10)
    d.polygon([(sx, sy - 2), (sx + 2, sy), (sx, sy + 2), (sx - 2, sy)], fill=LUA_BLUE)
    d.point((sx, sy), fill=LUA_PALE)
    glint = int(phase * 8)
    d.point((15, 80 + (glint % 3)), fill=LUA_BLUE_LIGHT)
    d.point((177, 80 - (glint % 2)), fill=LUA_PALE)
    d.point((96, 140), fill=b.LILAC if glint % 2 else b.PALE_LILAC)
    return img


def make_portal_frames(base, kind, count=8):
    frames = []
    for i in range(count):
        phase = i / float(count)
        frames.append(animate_python_portal(base, phase) if kind == "python"
                      else animate_lua_portal(base, phase))
    return frames


def make_tower_frames(count=8):
    base = b.make_tower_alt(include_beacon=False)
    frames = []
    for i in range(count):
        frame = base.copy()
        b.draw_skyglass_beacon(frame, i / float(count))
        frames.append(frame)
    return frames


def save_portal_animation(frames, base_name, title):
    frames[0].save(os.path.join(ROOT, base_name + "_loop.png"),
                   save_all=True, append_images=frames[1:],
                   duration=100, loop=0, disposal=2, blend=0)
    frames[0].save(os.path.join(ROOT, base_name + "_loop.apng"),
                   save_all=True, append_images=frames[1:],
                   duration=100, loop=0, disposal=2, blend=0)
    sheet = b.transparent((frames[0].width * len(frames), frames[0].height))
    for i, frame in enumerate(frames):
        sheet.alpha_composite(frame, (i * frame.width, 0))
    sheet.save(os.path.join(SPRITES, base_name + "_animated_sheet.png"))
    for i, frame in enumerate(frames):
        frame.save(os.path.join(FRAMES, f"{base_name}_{i:02d}.png"))

    W = frames[0].width * 3 + 80
    H = frames[0].height * 3 + 110
    gif_frames = []
    for i, frame in enumerate(frames):
        bg = b.checkerboard((W, H), 12)
        d = ImageDraw.Draw(bg)
        d.rectangle([0, 0, W, 48], fill=(20, 23, 27, 255))
        b.label(d, (20, 12), title, 20, (245, 238, 216, 255))
        b.label(d, (20, H - 34), f"frame {i} · {frame.width}×{frame.height} px · transparent source",
                15, (174, 169, 148, 255))
        bg.alpha_composite(b.shadowed_scaled(frame, 3.0), (40, 60))
        gif_frames.append(bg.convert("RGB"))
    gif_frames[0].save(os.path.join(ROOT, base_name + "_loop.gif"),
                       save_all=True, append_images=gif_frames[1:],
                       duration=100, loop=0, optimize=False)


def make_portal_animation_strip(py_frames, lua_frames):
    W, H = 1800, 760
    img = b.checkerboard((W, H), 10, (35, 39, 45, 255), (42, 47, 54, 255))
    d = ImageDraw.Draw(img)
    d.rectangle([0, 0, W, 70], fill=(20, 23, 27, 255))
    b.label(d, (24, 16), "Python / Lua portal animation — key frames", 27,
            (245, 238, 216, 255))
    b.label(d, (W - 300, 24), "100 ms/frame · 1.0 s loop", 17, (198, 190, 167, 255))
    rows = [("Python — Stonegate", py_frames, 2.0, 95),
            ("Lua — Ancient Rune Gate", lua_frames, 1.65, 400)]
    for title, frames, sc, y in rows:
        b.label(d, (32, y), title, 19, (238, 230, 208, 255))
        for i, fi in enumerate([0, 2, 4, 6]):
            up = b.shadowed_scaled(frames[fi], sc)
            x = 32 + i * 440
            d.rectangle([x, y + 28, x + 420, y + 28 + up.height + 24],
                        fill=(27, 31, 37, 230), outline=(70, 76, 84, 255))
            img.alpha_composite(up, (x + (420 - up.width) // 2, y + 34))
            b.label(d, (x + 10, y + 28 + up.height + 4), f"F{fi}", 15,
                    (218, 211, 188, 255))
    return img


def make_selected_world_loop(py_frames, lua_frames, tower_frames):
    W, H = 1400, 800
    grass = (136, 190, 33, 255)
    dark = (104, 179, 28, 255)
    light = (154, 214, 55, 255)
    bg = Image.new("RGBA", (W, H), grass)
    rng = __import__("random").Random(707)
    d = ImageDraw.Draw(bg)
    for _ in range(5200):
        x = rng.randrange(W)
        y = rng.randrange(H)
        d.point((x, y), fill=dark if rng.random() < 0.55 else light)
    for _ in range(850):
        x = rng.randrange(W)
        y = rng.randrange(H)
        d.line([(x, y), (x + 2, y - 2)], fill=dark)
    d.rectangle([0, 0, W, 74], fill=(21, 24, 27, 255))
    b.label(d, (24, 18), "Selected waypoint set — animated loop", 30, (245, 238, 216, 255))
    b.label(d, (W - 330, 25), "Python · Lua · world tower", 18, (198, 190, 167, 255))
    # Labels / separators.
    labels = [
        (270, "Python — Stonegate Portal"),
        (700, "Lua — Ancient Rune Gate"),
        (1130, "World — Ruined Skyglass Tower"),
    ]
    for x, text in labels:
        b.label(d, (x - 140, 92), text, 17, (245, 238, 216, 255))
    player = Image.open(os.path.join(b.GAME, "sprites/char/steve/rotations/south.png")).convert("RGBA")
    player_up = b.shadowed_scaled(player, 1.5 * 1.9)
    bg.alpha_composite(player_up, (40, 585))
    grass_tex = Image.open(os.path.join(b.GAME, "sprites/ground/grass.png")).convert("RGBA").crop((0, 0, 96, 96))
    for gx, gy in [(170, 720), (960, 735)]:
        gu = b.shadowed_scaled(grass_tex, 1.9)
        bg.alpha_composite(gu, (gx - gu.width // 2, gy - gu.height))
    foot = 715
    positions = [(270, py_frames), (700, lua_frames), (1130, tower_frames)]
    gif_frames = []
    for frame_i in range(8):
        canvas = bg.copy()
        for x, frames in positions:
            up = b.shadowed_scaled(frames[frame_i], 1.9)
            canvas.alpha_composite(up, (x - up.width // 2, foot - up.height))
        gif_frames.append(canvas.convert("RGB"))
    gif_frames[0].save(os.path.join(ROOT, "waypoint_selected_world_loop.gif"),
                       save_all=True, append_images=gif_frames[1:],
                       duration=100, loop=0, optimize=False)
    gif_frames[0].save(os.path.join(ROOT, "waypoint_selected_world.png"))
    return gif_frames


def save_tower_animation(frames):
    # Transparent animated PNG.
    frames[0].save(os.path.join(ROOT, "tower_skyglass_loop.png"),
                   save_all=True, append_images=frames[1:],
                   duration=100, loop=0, disposal=2, blend=0)
    frames[0].save(os.path.join(ROOT, "tower_skyglass_loop.apng"),
                   save_all=True, append_images=frames[1:],
                   duration=100, loop=0, disposal=2, blend=0)
    # Transparent horizontal sprite sheet.
    sheet = b.transparent((frames[0].width * len(frames), frames[0].height))
    for i, frame in enumerate(frames):
        sheet.alpha_composite(frame, (i * frame.width, 0))
    sheet.save(os.path.join(SPRITES, "tower_skyglass_animated_sheet.png"))
    for i, frame in enumerate(frames):
        frame.save(os.path.join(FRAMES, f"tower_skyglass_{i:02d}.png"))

    # Checkerboard GIF preview at 3x.
    W = frames[0].width * 3 + 80
    H = frames[0].height * 3 + 110
    gif_frames = []
    for i, frame in enumerate(frames):
        bg = b.checkerboard((W, H), 12)
        d = ImageDraw.Draw(bg)
        d.rectangle([0, 0, W, 48], fill=(20, 23, 27, 255))
        b.label(d, (20, 12), "Ruined Skyglass Tower — 8-frame loop", 20,
                (245, 238, 216, 255))
        b.label(d, (20, H - 34), f"frame {i} · 160×224 px · transparent source frame",
                15, (174, 169, 148, 255))
        up = b.shadowed_scaled(frame, 3.0)
        bg.alpha_composite(up, (40, 60))
        gif_frames.append(bg.convert("RGB"))
    gif_frames[0].save(os.path.join(ROOT, "tower_skyglass_loop.gif"),
                       save_all=True, append_images=gif_frames[1:],
                       duration=100, loop=0, optimize=False)


def make_world_animation(frames):
    W, H = 900, 820
    grass = (136, 190, 33, 255)
    dark = (104, 179, 28, 255)
    light = (154, 214, 55, 255)
    bg = Image.new("RGBA", (W, H), grass)
    rng = __import__("random").Random(1221)
    d = ImageDraw.Draw(bg)
    for _ in range(4200):
        x = rng.randrange(W)
        y = rng.randrange(H)
        d.point((x, y), fill=dark if rng.random() < 0.55 else light)
    for _ in range(650):
        x = rng.randrange(W)
        y = rng.randrange(H)
        d.line([(x, y), (x + 2, y - 2)], fill=dark)
    d.rectangle([0, 0, W, 70], fill=(21, 24, 27, 255))
    b.label(d, (24, 18), "Ruined Skyglass Tower — world-scale animation", 28,
            (245, 238, 216, 255))
    b.label(d, (W - 340, 24), "Approx. 1.9× zoom", 18, (198, 190, 167, 255))
    tree = Image.open(os.path.join(b.GAME, "sprites/tree/tree.png")).convert("RGBA")
    player = Image.open(os.path.join(b.GAME, "sprites/char/steve/rotations/south.png")).convert("RGBA")
    grass_tex = Image.open(os.path.join(b.GAME, "sprites/ground/grass.png")).convert("RGBA").crop((0, 0, 96, 96))
    scale = 1.9
    tree_up = b.shadowed_scaled(tree, scale)
    bg.alpha_composite(tree_up, (70, 400))
    player_up = b.shadowed_scaled(player, 1.5 * scale)
    bg.alpha_composite(player_up, (730, 555))
    for gx, gy in [(300, 735), (835, 760)]:
        gu = b.shadowed_scaled(grass_tex, scale)
        bg.alpha_composite(gu, (gx - gu.width // 2, gy - gu.height))
    # Tower position / foot.
    foot_y = 755
    cx = W // 2
    # Shadow.
    shadow = Image.new("RGBA", (260, 48), (0, 0, 0, 0))
    sd = ImageDraw.Draw(shadow)
    sd.ellipse([0, 0, 259, 47], fill=(0, 0, 0, 48))
    world_frames = []
    for frame in frames:
        canvas = bg.copy()
        canvas.alpha_composite(shadow, (cx - 130, foot_y - 24))
        up = b.shadowed_scaled(frame, scale)
        canvas.alpha_composite(up, (cx - up.width // 2, foot_y - up.height))
        world_frames.append(canvas.convert("RGB"))
    world_frames[0].save(os.path.join(ROOT, "tower_skyglass_world_loop.gif"),
                         save_all=True, append_images=world_frames[1:],
                         duration=100, loop=0, optimize=False)
    # Static first frame for the placement sheet.
    still = world_frames[0].convert("RGBA")
    still.save(os.path.join(ROOT, "tower_skyglass_world_preview.png"))


def make_language_mark_sheet():
    W, H = 1050, 440
    img = b.checkerboard((W, H), 10)
    d = ImageDraw.Draw(img)
    d.rectangle([0, 0, W, 70], fill=(20, 23, 27, 255))
    b.label(d, (24, 16), "Language crystal marks — top-of-portal emblems", 27,
            (245, 238, 216, 255))
    b.label(d, (W - 310, 24), "Draft / not implemented", 17, (255, 181, 76, 255))
    py = make_python_mark()
    lua = make_lua_mark()
    for x, mark, title, sub, accent in [
        (55, py, "Python mark", "blue + gold crystal pair · #8aadf4 / #eed49f", PY_BLUE_LIGHT),
        (545, lua, "Lua mark", "blue orb + crescent + satellite · #1e66f5 / #89b4fa", LUA_BLUE_LIGHT),
    ]:
        d.rectangle([x - 20, 105, x + 440, H - 25], fill=(28, 32, 38, 235),
                    outline=(75, 81, 89, 255))
        b.label(d, (x, 124), title, 22, (238, 230, 208, 255))
        b.label(d, (x, 156), sub, 15, (174, 169, 148, 255))
        up = b.shadowed_scaled(mark, 12.0)
        img.alpha_composite(up, (x + 90, 190))
        # palette swatches
        for i, col in enumerate([PY_BLUE, PY_BLUE_LIGHT, PY_GOLD, PY_GOLD_LIGHT] if x == 55
                                else [LUA_BLUE, LUA_BLUE_LIGHT, LUA_PALE, LUA_SLATE]):
            d.rectangle([x + 30 + i * 28, H - 72, x + 52 + i * 28, H - 50], fill=col,
                        outline=(20, 23, 27, 255))
    return img


def make_revised_closeups(py, lua, tower_frame, frames):
    W, H = 1800, 1540
    img = b.checkerboard((W, H), 10)
    d = ImageDraw.Draw(img)
    d.rectangle([0, 0, W, 88], fill=(20, 23, 27, 255))
    b.label(d, (36, 20), "SandEE — Revised Waypoint Draft", 38, (245, 238, 216, 255))
    b.label(d, (W - 505, 28), "Python / Lua / animated world waypoint", 21,
            (255, 181, 76, 255))
    cells = [
        (30, 110, 850, 630, py, "1. Python — Stonegate Portal",
         "Dungeon waypoint · 5×4 tiles · 160×128 px · animated veil", 4.0),
        (900, 110, 870, 630, lua, "2. Lua — Ancient Rune Gate",
         "Dungeon waypoint · 6×5 tiles · 192×160 px · animated veil", 3.6),
        (30, 760, 850, 650, tower_frame, "3. World — Ruined Skyglass Tower",
         "Only world waypoint · 5×7 tiles · 160×224 px · animated beacon", 2.4),
    ]
    for x, y, cw, ch, sprite, title, sub, scale in cells:
        d.rectangle([x, y, x + cw, y + ch], fill=(28, 32, 38, 235),
                    outline=(75, 81, 89, 255))
        b.label(d, (x + 24, y + 18), title, 25)
        b.label(d, (x + 24, y + 50), sub, 17, (188, 181, 157, 255))
        up = b.shadowed_scaled(sprite, scale)
        max_w, max_h = cw - 52, ch - 126
        if up.width > max_w or up.height > max_h:
            fac = min(max_w / up.width, max_h / up.height)
            up = up.resize((max(1, int(up.width * fac)), max(1, int(up.height * fac))),
                           Image.Resampling.NEAREST)
        px = x + (cw - up.width) // 2
        py = y + ch - up.height - 30
        img.alpha_composite(up, (px, py))

    # Animation contact strip, 4 representative frames.
    ax, ay, aw, ah = 900, 760, 870, 650
    d.rectangle([ax, ay, ax + aw, ay + ah], fill=(28, 32, 38, 235),
                outline=(75, 81, 89, 255))
    b.label(d, (ax + 24, ay + 18), "4. Tower animation — key frames", 25)
    b.label(d, (ax + 24, ay + 50), "8-frame loop · 10 fps · crystal bob / shard orbit / rune pulse",
            16, (188, 181, 157, 255))
    key = [0, 2, 4, 6]
    for idx, fi in enumerate(key):
        frame = frames[fi]
        up = b.shadowed_scaled(frame, 1.2)
        px = ax + 28 + idx * 204
        py = ay + 105
        d.rectangle([px - 6, py - 6, px + up.width + 6, py + up.height + 30],
                    fill=(24, 27, 32, 255), outline=(66, 72, 80, 255))
        img.alpha_composite(up, (px, py))
        b.label(d, (px + 2, py + up.height + 6), f"F{fi}", 15, (218, 211, 188, 255))

    # Language crystal closeups.
    for x, mark, title in [(30, make_python_mark(), "Python mark"),
                           (392, make_lua_mark(), "Lua mark")]:
        up = b.shadowed_scaled(mark, 4.0)
        d.rectangle([x, 1418, x + 330, H - 18], fill=(20, 23, 27, 235),
                    outline=(75, 81, 89, 255))
        b.label(d, (x + 12, 1426), title, 17, (238, 230, 208, 255))
        img.alpha_composite(up, (x + 118, 1446))
    b.label(d, (760, 1438),
            "Python mark: blue/gold shards · Lua mark: blue orb + crescent + satellite",
            16, (188, 181, 157, 255))
    b.label(d, (760, 1466),
            "All portal / tower art remains draft-only. Animated tower files are in this folder.",
            16, (145, 140, 124, 255))
    return img


def make_animation_strip(frames):
    W, H = 1800, 760
    img = b.checkerboard((W, H), 10, (35, 39, 45, 255), (42, 47, 54, 255))
    d = ImageDraw.Draw(img)
    d.rectangle([0, 0, W, 70], fill=(20, 23, 27, 255))
    b.label(d, (24, 16), "Ruined Skyglass Tower — 8-frame animation sheet", 27,
            (245, 238, 216, 255))
    b.label(d, (W - 335, 24), "100 ms/frame · 1.0 s loop", 17, (198, 190, 167, 255))
    for i, frame in enumerate(frames):
        col = i % 4
        row = i // 4
        x = 32 + col * 440
        y = 95 + row * 325
        up = b.shadowed_scaled(frame, 1.35)
        d.rectangle([x, y, x + 405, y + 300], fill=(27, 31, 37, 230),
                    outline=(70, 76, 84, 255))
        img.alpha_composite(up, (x + (405 - up.width) // 2, y + 12))
        b.label(d, (x + 12, y + 272), f"F{i}", 18, (238, 230, 208, 255))
    return img


def make_revised_world(py, lua, tower):
    scale = 1.9
    W, H = 1720, 800
    grass = (136, 190, 33, 255)
    dark = (104, 179, 28, 255)
    light = (154, 214, 55, 255)
    img = Image.new("RGBA", (W, H), grass)
    rng = __import__("random").Random(2004)
    d = ImageDraw.Draw(img)
    for _ in range(5400):
        x = rng.randrange(W)
        y = rng.randrange(H)
        d.point((x, y), fill=dark if rng.random() < 0.55 else light)
    for _ in range(900):
        x = rng.randrange(W)
        y = rng.randrange(H)
        d.line([(x, y), (x + 2, y - 2)], fill=dark)
    d.rectangle([0, 0, W, 84], fill=(21, 24, 27, 255))
    b.label(d, (28, 18), "SandEE — Selected Waypoint Set", 34, (245, 238, 216, 255))
    b.label(d, (W - 650, 25), "Python portal · Lua portal · animated world tower", 20,
            (198, 190, 167, 255))
    player = Image.open(os.path.join(b.GAME, "sprites/char/steve/rotations/south.png")).convert("RGBA")
    grass_tex = Image.open(os.path.join(b.GAME, "sprites/ground/grass.png")).convert("RGBA").crop((0, 0, 96, 96))
    scenes = [
        (30, 105, 540, 610, py, "Python — Stonegate Portal", "Dungeon · 5×4 tiles"),
        (590, 105, 540, 610, lua, "Lua — Ancient Rune Gate", "Dungeon · 6×5 tiles"),
        (1150, 105, 540, 610, tower, "World — Ruined Skyglass Tower", "World · 5×7 tiles · animated"),
    ]
    for idx, (sx, sy, sw, sh, sprite, title, sub) in enumerate(scenes):
        d.rectangle([sx, sy, sx + sw, sy + 46], fill=(21, 24, 27, 195))
        b.label(d, (sx + 12, sy + 8), title, 19, (245, 238, 216, 255))
        b.label(d, (sx + 12, sy + 32), sub, 15, (198, 190, 167, 255))
        foot = sy + sh - 38
        base_x = sx + sw // 2
        # A few grass tufts at the edges; no tree, so the waypoint silhouette
        # and its scale remain the focus.
        for gx, gy in [(sx + 24, foot + 8), (sx + sw - 28, foot + 18)]:
            gu = b.shadowed_scaled(grass_tex, 1.9)
            img.alpha_composite(gu, (gx - gu.width // 2, gy - gu.height))
        up = b.shadowed_scaled(sprite, scale)
        img.alpha_composite(up, (base_x - up.width // 2, foot - up.height))
        # Player reference in front-left of each base.
        player_up = b.shadowed_scaled(player, 1.5 * scale)
        img.alpha_composite(player_up, (base_x - up.width // 2 - 30, foot - player_up.height + 14))
    d.rectangle([0, H - 46, W, H], fill=(21, 24, 27, 255))
    b.label(d, (28, H - 38), "Draft only — selected set for review; not implemented in gameplay.",
            18, (198, 190, 167, 255))
    return img


def main():
    py_frames = make_portal_frames(make_python_portal(), "python")
    lua_frames = make_portal_frames(make_lua_portal(), "lua")
    py = py_frames[0]
    lua = lua_frames[0]
    frames = make_tower_frames()
    tower_static = frames[0]

    py.save(os.path.join(SPRITES, "portal_python_stonegate.png"))
    lua.save(os.path.join(SPRITES, "portal_lua_ancient.png"))
    tower_static.save(os.path.join(SPRITES, "tower_skyglass_ruined.png"))
    b.shadowed_scaled(py, 4).save(os.path.join(SPRITES, "portal_python_stonegate_x4.png"))
    b.shadowed_scaled(lua, 4).save(os.path.join(SPRITES, "portal_lua_ancient_x4.png"))
    b.shadowed_scaled(tower_static, 4).save(os.path.join(SPRITES, "tower_skyglass_ruined_x4.png"))
    make_python_mark().save(os.path.join(SPRITES, "python_crystal_mark.png"))
    make_lua_mark().save(os.path.join(SPRITES, "lua_crystal_mark.png"))

    save_portal_animation(py_frames, "portal_python_stonegate",
                          "Python Stonegate Portal — 8-frame loop")
    save_portal_animation(lua_frames, "portal_lua_ancient",
                          "Lua Ancient Rune Gate — 8-frame loop")
    save_tower_animation(frames)
    make_world_animation(frames)
    make_language_mark_sheet().save(os.path.join(ROOT, "language_crystals.png"))
    make_portal_animation_strip(py_frames, lua_frames).save(
        os.path.join(ROOT, "portal_animation_strip.png"))
    make_revised_closeups(py, lua, tower_static, frames).save(
        os.path.join(ROOT, "waypoint_revised_closeups.png"))
    make_animation_strip(frames).save(os.path.join(ROOT, "tower_animation_strip.png"))
    make_revised_world(py, lua, tower_static).save(
        os.path.join(ROOT, "waypoint_revised_world.png"))
    make_selected_world_loop(py_frames, lua_frames, frames)


if __name__ == "__main__":
    main()
