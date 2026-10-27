from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

BASE = Path(__file__).resolve().parent
OUT = BASE / "implementation_previews"
PROJECT = BASE.parent.parent / "SandEEAlpha"
FONT = "C:/Windows/Fonts/consolab.ttf"

def font(size):
    return ImageFont.truetype(FONT, size)

def checker(w, h, cell=8):
    im = Image.new("RGBA", (w, h), (28, 30, 39, 255))
    d = ImageDraw.Draw(im)
    for y in range(0, h, cell):
        for x in range(0, w, cell):
            if ((x // cell) + (y // cell)) % 2:
                d.rectangle((x, y, x + cell - 1, y + cell - 1), fill=(39, 42, 53, 255))
    return im

def build_prop_gif(theme):
    sconce = Image.open(PROJECT / "sprites/dungeon" / theme / "sconce_sheet.png").convert("RGBA")
    medallion = Image.open(PROJECT / "sprites/dungeon" / theme / "medallion_sheet.png").convert("RGBA")
    sw, sh = 16, 32
    mw, mh = 64, 64
    scale_s, scale_m = 4, 2
    canvas_w, canvas_h = 520, 270
    frames = []
    for i in range(8):
        canvas = checker(canvas_w, canvas_h)
        d = ImageDraw.Draw(canvas)
        d.rectangle((0, 0, canvas_w, 60), fill=(15, 17, 24, 255))
        accent = (180, 150, 245) if theme == "lua" else (115, 225, 210)
        d.text((20, 14), ("LUA" if theme == "lua" else "PYTHON") + " DUNGEON - ANIMATED PROPS",
               font=font(18), fill=accent)
        d.text((20, 37), "8 frames - 10 fps - production sheets", font=font(13), fill=(160, 170, 190, 255))
        # sconce panel
        d.text((44, 78), "SCONCE", font=font(14), fill=(170, 180, 200, 255))
        sframe = sconce.crop((i * sw, 0, (i + 1) * sw, sh))
        panel = checker(sw * scale_s, sh * scale_s)
        panel.alpha_composite(sframe.resize((sw * scale_s, sh * scale_s), Image.Resampling.NEAREST))
        canvas.alpha_composite(panel, (40, 102))
        d = ImageDraw.Draw(canvas)
        d.text((40, 242), "crystal flicker", font=font(12), fill=(140, 150, 170, 255))
        # medallion panel
        d.text((250, 78), "FLOOR MEDALLION", font=font(14), fill=(170, 180, 200, 255))
        mframe = medallion.crop((i * mw, 0, (i + 1) * mw, mh))
        panel2 = checker(mw * scale_m, mh * scale_m)
        panel2.alpha_composite(mframe.resize((mw * scale_m, mh * scale_m), Image.Resampling.NEAREST))
        canvas.alpha_composite(panel2, (248, 102))
        d = ImageDraw.Draw(canvas)
        d.text((248, 242), "rune travel / pulse", font=font(12), fill=(140, 150, 170, 255))
        frames.append(canvas.convert("P", palette=Image.Palette.ADAPTIVE, colors=128))
    frames[0].save(OUT / f"{theme}_animated_props.gif", save_all=True,
                   append_images=frames[1:], duration=100, loop=0,
                   disposal=2, optimize=False)

def build_overview():
    paths = [
        ("lua_first_dungeon_in_game.png", "LUA / FIRST DUNGEON"),
        ("python_first_dungeon_in_game.png", "PYTHON / FIRST DUNGEON"),
        ("lua_extra_dungeon_in_game.png", "LUA / EXTRA DUNGEON"),
        ("python_regular_dungeon_in_game.png", "PYTHON / REGULAR DUNGEON"),
    ]
    ims = []
    for name, label in paths:
        im = Image.open(OUT / name).convert("RGB")
        im.thumbnail((880, 500), Image.Resampling.LANCZOS)
        ims.append((im, label))
    W, H = 980, 2 * 560 + 90
    canvas = Image.new("RGBA", (W, H), (13, 14, 20, 255))
    d = ImageDraw.Draw(canvas)
    d.rectangle((0, 0, W, 64), fill=(16, 18, 25, 255))
    d.text((24, 18), "DUNGEON THEMES - IMPLEMENTATION CHECK", font=font(19), fill=(210, 220, 235, 255))
    for i, (im, label) in enumerate(ims):
        col = i % 2
        row = i // 2
        x = 24 + col * 490
        y = 80 + row * 560
        d.text((x, y), label, font=font(14), fill=(160, 172, 190, 255))
        canvas.alpha_composite(im.convert("RGBA"), (x, y + 22))
    canvas.convert("RGB").save(OUT / "in_game_theme_overview.png")

for theme in ("lua", "python"):
    build_prop_gif(theme)
build_overview()
print("Implementation previews written to", OUT)
