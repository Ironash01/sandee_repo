from pathlib import Path
from PIL import Image, ImageDraw, ImageFont, ImageFilter

ROOT = Path(r"C:\Users\Krosis\Documents\github_repos\sandee_repo")
OUT = ROOT / "design_drafts" / "facebook_cover"
OUT.mkdir(parents=True, exist_ok=True)

W, H = 1640, 624
BG = (10, 14, 28)
BG_2 = (15, 20, 40)
PANEL = (20, 26, 51)
PANEL_2 = (27, 35, 66)
BORDER = (47, 63, 110)
BORDER_BRIGHT = (63, 90, 160)
INK = (232, 240, 255)
MUTED = (140, 166, 217)
DIM = (92, 111, 158)
ACCENT = (140, 230, 154)
BRAND = (99, 200, 240)
SAND = (230, 201, 138)
SHADOW = (5, 7, 15)

FONT_TICKET = ROOT / "SandEEAlpha" / "fonts" / "Ticketing.ttf"
FONT_MONO = ROOT / "SandEEAlpha" / "fonts" / "monogram-extended.ttf"


def font(path, size):
    return ImageFont.truetype(str(path), size)


def text_w(draw, text, f, spacing=0):
    if not text:
        return 0
    total = 0
    for ch in text:
        b = draw.textbbox((0, 0), ch, font=f)
        total += (b[2] - b[0]) + spacing
    return max(0, total - spacing)


def draw_spaced(draw, xy, text, f, fill, spacing=0):
    x, y = xy
    for ch in text:
        draw.text((x, y), ch, font=f, fill=fill)
        b = draw.textbbox((0, 0), ch, font=f)
        x += (b[2] - b[0]) + spacing


def text_block(draw, x, y, lines, f, fill, spacing=0, line_gap=0):
    cy = y
    for line in lines:
        draw_spaced(draw, (x, cy), line, f, fill, spacing)
        b = draw.textbbox((0, 0), line, font=f)
        cy += (b[3] - b[1]) + line_gap
    return cy


def tag(draw, x, y, text, f, fg, bg=PANEL, border=BORDER, pad_x=14, pad_y=8):
    tw = text_w(draw, text, f)
    b = draw.textbbox((0, 0), text, font=f)
    th = b[3] - b[1]
    w = tw + pad_x * 2
    h = th + pad_y * 2
    draw.rectangle((x, y, x + w, y + h), fill=bg, outline=border, width=2)
    draw_spaced(draw, (x + pad_x, y + pad_y - 1), text, f, fg)
    return w, h


# Background: vertical palette + subtle pixel grid.
bg = Image.new("RGB", (W, H), BG)
bd = ImageDraw.Draw(bg)
for yy in range(H):
    t = yy / max(1, H - 1)
    c = tuple(int(BG[i] * (1 - t) + BG_2[i] * t) for i in range(3))
    bd.line((0, yy, W, yy), fill=c)
for gx in range(0, W, 32):
    bd.line((gx, 0, gx, H), fill=(18, 24, 46), width=1)
for gy in range(0, H, 32):
    bd.line((0, gy, W, gy), fill=(18, 24, 46), width=1)

# Soft vignette / corner shading.
vignette = Image.new("L", (W, H), 0)
vd = ImageDraw.Draw(vignette)
vd.ellipse((-500, -380, W + 500, H + 420), fill=70)
vignette = vignette.filter(ImageFilter.GaussianBlur(120))
bg = Image.composite(Image.new("RGB", (W, H), (18, 25, 48)), bg, vignette)

d = ImageDraw.Draw(bg)

# Pixel spine at the far left.
spine = [(0, 0, 10, 180, ACCENT), (0, 180, 10, 360, SAND), (0, 360, 10, 540, BRAND), (0, 540, 10, H, BORDER)]
for x0, y0, x1, y1, col in spine:
    d.rectangle((x0, y0, x1 - 1, y1 - 1), fill=col)

# App icon on a deliberate pixel plaque.
icon = Image.open(ROOT / "SandEEAlpha" / "icons" / "app_icon_1024.png").convert("RGBA")
icon = icon.resize((132, 132), Image.Resampling.LANCZOS)
d.rectangle((60, 62, 199, 201), fill=SHADOW)
d.rectangle((56, 58, 195, 197), fill=PANEL, outline=BORDER, width=3)
bg.paste(icon, (64, 66), icon)
d.rectangle((56, 58, 195, 197), outline=BORDER_BRIGHT, width=1)

# Wordmark.
title_f = font(FONT_TICKET, 104)
sub_f = font(FONT_TICKET, 26)
tag_f = font(FONT_MONO, 19)
small_f = font(FONT_TICKET, 17)
code_f = font(FONT_MONO, 16)

x_text = 222
wx, wy = x_text, 62
for i, ch in enumerate("SANDEE"):
    d.text((wx, wy), ch, font=title_f, fill=ACCENT if i >= 4 else INK)
    b = d.textbbox((0, 0), ch, font=title_f)
    wx += (b[2] - b[0]) + 3

draw_spaced(d, (x_text + 2, 186), "MINE. BUILD. CODE.", font(FONT_TICKET, 29), SAND, 3)
draw_spaced(d, (x_text + 2, 231), "AN EDUCATIONAL 2D OPEN-WORLD", sub_f, MUTED, 2)
draw_spaced(d, (x_text + 2, 263), "SURVIVAL CRAFTING GAME", sub_f, MUTED, 2)

# Divider.
d.rectangle((x_text + 2, 310, x_text + 560, 314), fill=BORDER_BRIGHT)
d.rectangle((x_text + 2, 310, x_text + 130, 314), fill=ACCENT)
d.rectangle((x_text + 134, 310, x_text + 206, 314), fill=SAND)

# Screenshot panel (right).
shot = Image.open(ROOT / "docu_thesis" / "manual_draft" / "screenshots" / "pc_overworld.png").convert("RGB")
# Crop a 16:9 region around the player and camp, inside the HUD corners.
shot = shot.crop((480, 270, 1440, 810))
panel_w, panel_h = 744, 418
shot = shot.resize((panel_w, panel_h), Image.Resampling.LANCZOS).filter(ImageFilter.SHARPEN)
px, py = 875, 74
# Hard pixel shadow.
d.rectangle((px + 9, py + 9, px + panel_w + 9, py + panel_h + 9), fill=SHADOW)
# Border and image.
d.rectangle((px - 4, py - 4, px + panel_w + 3, py + panel_h + 3), fill=BORDER)
bg.paste(shot, (px, py))
d.rectangle((px - 4, py - 4, px + panel_w + 3, py + panel_h + 3), outline=BORDER_BRIGHT, width=2)
# Accent tab.
tab_w, tab_h = 142, 28
d.rectangle((px, py - 34, px + tab_w, py - 6), fill=PANEL, outline=BORDER, width=2)
draw_spaced(d, (px + 12, py - 31), "IN-GAME", font(FONT_MONO, 14), ACCENT, 1)

# Feature tags and credit sit below the screenshot, away from the Page profile
# picture that covers the bottom-left of a Facebook cover.
tx = px
ty = py + panel_h + 24
w1, h1 = tag(d, tx, ty, "LUA + PYTHON", tag_f, BRAND)
tx2 = tx + w1 + 12
w2, h2 = tag(d, tx2, ty, "WINDOWS + ANDROID", tag_f, ACCENT)

draw_spaced(d, (px, ty + 48), "SANDEE DEVELOPERS", small_f, DIM, 2)
draw_spaced(d, (px + 190, ty + 48), "ALPHA v0.9.5.1", font(FONT_TICKET, 15), DIM, 2)

# Outer frame.
d.rectangle((0, 0, W - 1, H - 1), outline=(25, 32, 60), width=2)

# Save high-res and Facebook-size versions.
bg.save(OUT / "SandEE_facebook_cover_1640x624.png", optimize=True)
bg.resize((820, 312), Image.Resampling.LANCZOS).save(OUT / "SandEE_facebook_cover_820x312.png", optimize=True)
print("WROTE", OUT)
