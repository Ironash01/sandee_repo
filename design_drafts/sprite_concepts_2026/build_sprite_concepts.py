from pathlib import Path
from PIL import Image, ImageDraw, ImageFont, ImageFilter, ImageChops
import math, random

BASE = Path(__file__).resolve().parent
SPR = BASE / "sprites"
PREV = BASE / "previews"
FONT_PATH = "C:/Windows/Fonts/consolab.ttf"

OUTLINE = (18, 16, 26, 255)
INK = (13, 12, 19, 255)
WHITE = (245, 242, 226, 255)
CREAM = (232, 215, 174, 255)
CREAM_HI = (250, 241, 208, 255)
GOLD = (197, 157, 72, 255)
GOLD_HI = (244, 214, 129, 255)
GOLD_DK = (120, 88, 39, 255)
TEAL = (49, 181, 172, 255)
TEAL_HI = (156, 249, 231, 255)
TEAL_DK = (25, 91, 92, 255)
VIOLET = (128, 93, 214, 255)
VIOLET_HI = (220, 192, 255, 255)
VIOLET_DK = (70, 45, 118, 255)
RUST = (180, 82, 48, 255)
RUST_HI = (243, 142, 77, 255)
RUST_DK = (101, 47, 35, 255)
MOSS = (83, 121, 62, 255)
MOSS_HI = (145, 174, 91, 255)
MOSS_DK = (44, 73, 43, 255)
AMBER = (241, 169, 61, 255)
AMBER_HI = (255, 224, 125, 255)
BONE = (198, 188, 152, 255)
BONE_HI = (235, 227, 193, 255)
BLUE = (58, 91, 116, 255)
BLUE_HI = (104, 151, 166, 255)
BLUE_DK = (31, 49, 71, 255)
BRASS = (177, 123, 54, 255)
BRASS_HI = (238, 192, 101, 255)
BRASS_DK = (99, 65, 37, 255)
CHAR = (48, 42, 49, 255)
CHAR_HI = (82, 70, 77, 255)
SKIN_Z = (122, 137, 103, 255)
SKIN_Z_HI = (170, 181, 137, 255)
SKIN_Z_DK = (76, 91, 68, 255)

def new(w,h):
    return Image.new("RGBA",(w,h),(0,0,0,0))

def outline_image(im, color=OUTLINE, thickness=1):
    if thickness <= 0: return im
    mask = im.getchannel("A")
    grown = mask.filter(ImageFilter.MaxFilter(1 + 2*thickness))
    out = Image.new("RGBA", im.size, (0,0,0,0))
    under = Image.new("RGBA", im.size, color)
    under.putalpha(grown)
    out.alpha_composite(under)
    out.alpha_composite(im)
    return out

def put(im, draw_fn):
    draw_fn(ImageDraw.Draw(im))

def checker(w,h,cell=8,a=(26,28,37,255),b=(37,40,51,255)):
    im=Image.new("RGBA",(w,h),a); d=ImageDraw.Draw(im)
    for y in range(0,h,cell):
        for x in range(0,w,cell):
            if ((x//cell)+(y//cell))%2: d.rectangle((x,y,x+cell-1,y+cell-1),fill=b)
    return im

def font(sz):
    return ImageFont.truetype(FONT_PATH, sz)

def scale_nn(im, k):
    return im.resize((im.width*k, im.height*k), Image.Resampling.NEAREST)

def save_sprite(im, path):
    path.parent.mkdir(parents=True, exist_ok=True)
    im.save(path)

def save_frames(frames, path):
    if not frames: return
    w,h=frames[0].size
    sheet=Image.new("RGBA",(w*len(frames),h),(0,0,0,0))
    for i,fr in enumerate(frames): sheet.alpha_composite(fr,(i*w,0))
    path.parent.mkdir(parents=True, exist_ok=True)
    sheet.save(path)

def shadow_ellipse(w=0,h=0,scale=1.0,alpha=100):
    im=Image.new("RGBA",(w,h),(0,0,0,0)); d=ImageDraw.Draw(im)
    d.ellipse((2,2,w-3,h-3),fill=(0,0,0,alpha)); return im

# -- friendly: Mossback Nib --------------------------------------------
def draw_mossback(phase=0):
    im=new(32,32); d=ImageDraw.Draw(im)
    bob = -1 if phase in (1,2) else 0
    # legs and little feet
    for x in (8,13,19,24):
        d.rectangle((x, 23+bob, x+2, 28+bob), fill=MOSS_DK, outline=OUTLINE)
    # shell body
    d.ellipse((5,6+bob,27,24+bob), fill=MOSS, outline=OUTLINE, width=1)
    d.ellipse((8,8+bob,21,15+bob), fill=MOSS_HI)
    d.arc((7,10+bob,25,24+bob), 195, 345, fill=MOSS_DK, width=2)
    # shell moss spots / tiny mushrooms
    d.rectangle((21,10+bob,22,11+bob), fill=GOLD_HI)
    d.rectangle((9,17+bob,10,18+bob), fill=MOSS_DK)
    d.rectangle((23,15+bob,24,16+bob), fill=MOSS_DK)
    d.rectangle((16,5+bob,17,8+bob), fill=CREAM)
    d.rectangle((15,3+bob,19,5+bob), fill=GOLD_HI, outline=OUTLINE)
    d.rectangle((16,4+bob,17,6+bob), fill=GOLD_DK)
    # antennae
    d.line((13,8+bob,10,3+bob), fill=MOSS_DK)
    d.line((19,8+bob,22,3+bob), fill=MOSS_DK)
    d.rectangle((9,2+bob,10,3+bob), fill=GOLD_HI)
    d.rectangle((22,2+bob,23,3+bob), fill=GOLD_HI)
    # warm tan face, soft ears and friendly eyes rather than hollow sockets
    d.ellipse((11,16+bob,22,28+bob), fill=(216,187,130,255), outline=OUTLINE, width=1)
    d.ellipse((10,17+bob,14,21+bob), fill=(216,187,130,255), outline=OUTLINE)
    d.ellipse((19,17+bob,23,21+bob), fill=(216,187,130,255), outline=OUTLINE)
    d.rectangle((12,20+bob,16,23+bob), fill=WHITE)
    d.rectangle((18,20+bob,22,23+bob), fill=WHITE)
    d.rectangle((14,21+bob,15,23+bob), fill=(48,38,39,255))
    d.rectangle((20,21+bob,21,23+bob), fill=(48,38,39,255))
    d.point((14,21+bob), fill=WHITE); d.point((20,21+bob), fill=WHITE)
    d.rectangle((13,19+bob,16,20+bob), fill=MOSS_DK)
    d.rectangle((18,19+bob,21,20+bob), fill=MOSS_DK)
    d.rectangle((11,23+bob,12,24+bob), fill=(211,132,105,255))
    d.rectangle((21,23+bob,22,24+bob), fill=(211,132,105,255))
    d.ellipse((15,23+bob,19,26+bob), fill=CREAM_HI)
    d.point((17,24+bob), fill=(84,56,43,255))
    d.arc((15,25+bob,20,27+bob), 20, 160, fill=OUTLINE, width=1)
    # tiny front paws
    d.rectangle((10,25+bob,12,28+bob), fill=(216,187,130,255), outline=OUTLINE)
    d.rectangle((21,25+bob,23,28+bob), fill=(216,187,130,255), outline=OUTLINE)
    # soft leaf tail
    d.polygon([(26,21+bob),(30,18+bob),(29,24+bob),(25,24+bob)], fill=MOSS_HI, outline=OUTLINE)
    return outline_image(im)

# -- friendly: Emberfox Pup -------------------------------------------
def draw_emberfox(phase=0):
    im=new(48,48); d=ImageDraw.Draw(im)
    bob=-1 if phase in (1,2) else 0
    sway=1 if phase in (2,3) else 0
    # big curled tail behind
    d.ellipse((28,25+bob,45,44+bob), fill=RUST, outline=OUTLINE, width=1)
    d.ellipse((35,31+bob,44,43+bob), fill=CREAM, outline=OUTLINE, width=1)
    # back legs / paws
    d.rectangle((13,34+bob,20,45+bob), fill=RUST_DK)
    d.rectangle((26,34+bob,33,45+bob), fill=RUST_DK)
    d.rectangle((12,42+bob,21,46+bob), fill=CREAM, outline=OUTLINE)
    d.rectangle((25,42+bob,34,46+bob), fill=CREAM, outline=OUTLINE)
    # sitting body
    d.ellipse((11,18+bob,36,42+bob), fill=RUST, outline=OUTLINE, width=1)
    d.ellipse((17,24+bob,30,40+bob), fill=CREAM_HI)
    # chest fluff
    d.polygon([(19,25+bob),(24,32+bob),(29,25+bob),(26,36+bob),(22,36+bob)], fill=CREAM)
    # scarf
    d.rectangle((16,23+bob,32,26+bob), fill=TEAL, outline=OUTLINE)
    d.polygon([(28,25+bob),(34,29+bob),(30,30+bob),(27,27+bob)], fill=TEAL_DK, outline=OUTLINE)
    d.rectangle((18,24+bob,22,25+bob), fill=TEAL_HI)
    # head + ears
    d.polygon([(12,12+bob),(9,2+bob),(18,9+bob)], fill=RUST, outline=OUTLINE)
    d.polygon([(29,9+bob),(38,2+bob),(35,13+bob)], fill=RUST, outline=OUTLINE)
    d.polygon([(13,10+bob),(11,4+bob),(16,9+bob)], fill=RUST_HI)
    d.polygon([(31,9+bob),(36,4+bob),(34,11+bob)], fill=RUST_HI)
    d.ellipse((11,7+bob,37,27+bob), fill=RUST, outline=OUTLINE, width=1)
    d.ellipse((15,9+bob,31,15+bob), fill=RUST_HI)
    # muzzle and face
    d.ellipse((18,16+bob,31,25+bob), fill=CREAM, outline=OUTLINE)
    d.polygon([(23,18+bob),(28,18+bob),(26,21+bob)], fill=INK)
    d.line((25,21+bob,25,22+bob), fill=OUTLINE)
    d.arc((21,21+bob,29,25+bob), 20, 160, fill=OUTLINE, width=1)
    # eyes with friendly catchlights
    d.ellipse((16,12+bob,22,17+bob), fill=AMBER, outline=OUTLINE)
    d.ellipse((27,12+bob,33,17+bob), fill=AMBER, outline=OUTLINE)
    d.rectangle((18,14+bob,19,16+bob), fill=INK)
    d.rectangle((29,14+bob,30,16+bob), fill=INK)
    d.point((18,14+bob), fill=WHITE); d.point((29,14+bob), fill=WHITE)
    d.rectangle((17,13+bob,18,14+bob), fill=GOLD_HI)
    d.rectangle((28,13+bob,29,14+bob), fill=GOLD_HI)
    # whisker pixels
    d.point((17,20+bob), fill=CREAM_HI); d.point((33,20+bob), fill=CREAM_HI)
    return outline_image(im)


# -- overworld enemy: Cinder Ooze -------------------------------------
def draw_cinder_ooze(phase=0):
    im=new(48,48); d=ImageDraw.Draw(im)
    squeeze=1 if phase in (1,3) else 0
    y0=15-squeeze; x0=6+squeeze; x1=42-squeeze
    blob=[(x0+2,30),(x0,25),(x0+5,18),(x0+9,16),(x0+12,9),
          (x0+18,13),(x0+21,7),(x0+27,14),(x0+32,11),(x0+36,19),
          (x1,23),(x1-1,32),(x1-5,39),(x1-13,43),(x0+11,42),(x0+4,35)]
    d.polygon(blob, fill=CHAR, outline=OUTLINE)
    # hardened crust plates across the top
    d.polygon([(14,y0+1),(22,y0-2),(27,y0+4),(22,y0+9),(15,y0+7)], fill=(91,49,48,255), outline=OUTLINE)
    d.polygon([(28,y0+3),(35,y0+1),(39,y0+8),(34,y0+12),(29,y0+9)], fill=(72,42,48,255), outline=OUTLINE)
    d.polygon([(21,12),(28,8),(32,14),(27,17),(22,16)], fill=(128,57,45,255))
    # magma cracks
    for pts in [[(15,18),(20,22),(18,28)],[(22,16),(29,21),(34,19)],
                [(32,26),(38,30),(36,36)],[(12,31),(17,34),(16,39)]]:
        d.line(pts, fill=(114,50,39,255), width=2)
        d.line(pts[:2], fill=RUST_HI, width=1)
    d.ellipse((19,27,33,37), fill=(96,48,43,255), outline=(54,31,33,255))
    d.ellipse((22,30,30,35), fill=RUST, outline=AMBER)
    # angry eyes
    d.line((16,25,22,27), fill=OUTLINE, width=2)
    d.line((27,27,33,24), fill=OUTLINE, width=2)
    d.rectangle((17,27,21,29), fill=AMBER_HI)
    d.rectangle((28,26,32,28), fill=AMBER_HI)
    d.rectangle((18,27,19,28), fill=WHITE)
    d.rectangle((29,26,30,27), fill=WHITE)
    # small ember flecks / drips
    d.rectangle((10,34,12,36), fill=CHAR_HI, outline=OUTLINE)
    d.rectangle((37,34,39,38), fill=CHAR_HI, outline=OUTLINE)
    d.rectangle((33,39,35,42), fill=RUST, outline=OUTLINE)
    d.line((11,38,18,41,26,40,35,42,39,38), fill=(134,58,42,255), width=1)
    d.line((17,39,24,41,31,40), fill=RUST_HI, width=1)
    d.polygon([(15,14),(18,7),(21,14)], fill=(72,43,45,255), outline=OUTLINE)
    d.polygon([(30,12),(34,5),(37,14)], fill=(98,50,43,255), outline=OUTLINE)
    d.point((16,9), fill=RUST_HI); d.point((35,8), fill=AMBER_HI)
    d.point((12,23), fill=AMBER_HI); d.point((41,22), fill=RUST_HI)
    return outline_image(im)

# -- overworld enemy: Gravebell Shambler ------------------------------
def draw_gravebell(phase=0):
    im=new(48,48); d=ImageDraw.Draw(im)
    bob=-1 if phase in (1,2) else 0
    tilt=1 if phase in (2,3) else 0
    # feet / legs
    d.rectangle((14,36+bob,20,46+bob), fill=(59,52,43,255), outline=OUTLINE)
    d.rectangle((28,36+bob,34,46+bob), fill=(74,63,49,255), outline=OUTLINE)
    d.rectangle((12,43+bob,21,47+bob), fill=(45,39,37,255), outline=OUTLINE)
    d.rectangle((27,43+bob,36,47+bob), fill=(45,39,37,255), outline=OUTLINE)
    # long ragged coat
    d.polygon([(13,18+bob),(35,18+bob),(39,36+bob),(36,41+bob),(31,37+bob),
               (27,42+bob),(22,38+bob),(17,41+bob),(12,36+bob)], fill=(82,69,57,255), outline=OUTLINE)
    d.rectangle((18,18+bob,30,32+bob), fill=(105,83,62,255))
    # exposed ribs
    for y in range(23,31,3):
        d.line((20,y+bob,29,y+bob), fill=BONE, width=1)
    d.line((24,20+bob,24,33+bob), fill=BONE_HI, width=1)
    # belt / rope
    d.line((14,32+bob,34,33+bob), fill=(72,49,35,255), width=2)
    d.point((22,33+bob), fill=GOLD)
    # left long arm
    d.line((13,23+bob,8,34+bob,10,42+bob), fill=SKIN_Z_DK, width=4)
    d.line((12,23+bob,9,33+bob,11,40+bob), fill=SKIN_Z, width=2)
    d.polygon([(7,40+bob),(11,39+bob),(12,44+bob),(8,45+bob)], fill=SKIN_Z, outline=OUTLINE)
    # head
    d.polygon([(15,8+bob),(29,6+bob),(35,13+bob),(33,23+bob),(22,26+bob),(14,20+bob)],
              fill=SKIN_Z, outline=OUTLINE)
    d.rectangle((17,9+bob,27,13+bob), fill=SKIN_Z_HI)
    d.rectangle((16,17+bob,20,20+bob), fill=SKIN_Z_DK)
    d.rectangle((27,12+bob,30,16+bob), fill=SKIN_Z_DK)
    # one bright eye + hollow socket
    d.rectangle((19,15+bob,23,18+bob), fill=INK)
    d.rectangle((20,16+bob,22,17+bob), fill=AMBER_HI)
    d.rectangle((27,15+bob,31,18+bob), fill=INK)
    d.point((28,16+bob), fill=VIOLET_HI)
    # stitched jaw
    d.line((19,21+bob,29,22+bob), fill=OUTLINE, width=1)
    for x in (21,24,27): d.line((x,21+bob,x,24+bob), fill=BONE, width=1)
    # dark hair strands
    d.line((17,7+bob,14,3+bob), fill=(43,44,37,255), width=2)
    d.line((24,6+bob,25,2+bob), fill=(43,44,37,255), width=2)
    # right arm holding the bell
    d.line((34,23+bob,38,32+bob,37,37+bob), fill=SKIN_Z_DK, width=4)
    d.line((34,24+bob,37,31+bob), fill=SKIN_Z, width=2)
    d.rectangle((35,35+bob,37,38+bob), fill=SKIN_Z_HI, outline=OUTLINE)
    # hand bell
    d.line((38,36+bob,42,29+bob), fill=BRASS_DK, width=2)
    d.polygon([(34,29+bob),(43,29+bob),(42,37+bob),(35,37+bob)], fill=BRASS, outline=OUTLINE)
    d.line((35,32+bob,42,32+bob), fill=TEAL, width=1)
    d.rectangle((37,37+bob,40,39+bob), fill=BRASS_HI, outline=OUTLINE)
    d.rectangle((38,38+bob,39,39+bob), fill=AMBER)
    d.point((42,28+bob), fill=GOLD_HI)
    return outline_image(im)

# -- Lua enemy: Rune Sentinel -----------------------------------------
def draw_rune_sentinel(phase=0):
    im=new(64,64); d=ImageDraw.Draw(im)
    bob=-1 if phase in (1,2) else 0
    pulse=VIOLET_HI if phase in (0,1) else VIOLET
    # thin arch halo behind the armour, echoing Lua's pointed masonry
    d.arc((17,3+bob,47,34+bob), 200, 340, fill=GOLD_DK, width=2)
    d.point((32,2+bob), fill=GOLD_HI)
    # lower tattered shrine cloth
    cape=[(20,35+bob),(44,35+bob),(48,54+bob),(42,51+bob),(39,59+bob),
          (34,53+bob),(30,60+bob),(26,53+bob),(21,59+bob),(17,51+bob),(12,55+bob)]
    d.polygon(cape, fill=(40,32,59,255), outline=OUTLINE)
    d.line((23,49+bob,41,49+bob), fill=GOLD_DK, width=1)
    # angular pauldrons with outward spikes
    d.polygon([(8,25+bob),(15,17+bob),(24,16+bob),(30,23+bob),(27,34+bob),(14,38+bob),(9,33+bob)],
              fill=(58,50,77,255), outline=OUTLINE)
    d.polygon([(56,25+bob),(49,17+bob),(40,16+bob),(34,23+bob),(37,34+bob),(50,38+bob),(55,33+bob)],
              fill=(58,50,77,255), outline=OUTLINE)
    d.polygon([(7,25+bob),(11,15+bob),(15,20+bob),(12,30+bob)], fill=(78,67,96,255), outline=OUTLINE)
    d.polygon([(57,25+bob),(53,15+bob),(49,20+bob),(52,30+bob)], fill=(78,67,96,255), outline=OUTLINE)
    d.line((10,29+bob,21,20+bob), fill=GOLD_HI, width=2)
    d.line((54,29+bob,43,20+bob), fill=GOLD_HI, width=2)
    d.point((9,24+bob), fill=GOLD_HI); d.point((55,24+bob), fill=GOLD_HI)
    # broad chest plate
    d.polygon([(23,22+bob),(41,22+bob),(46,31+bob),(40,45+bob),(33,49+bob),
               (31,49+bob),(24,45+bob),(18,31+bob)], fill=(50,43,68,255), outline=OUTLINE)
    d.polygon([(25,24+bob),(39,24+bob),(42,30+bob),(35,29+bob),(29,29+bob),(22,30+bob)],
              fill=(83,73,104,255))
    d.line((20,31+bob,26,24+bob), fill=GOLD_HI, width=1)
    d.line((44,31+bob,38,24+bob), fill=GOLD_HI, width=1)
    d.line((22,43+bob,30,47+bob), fill=GOLD, width=1)
    d.line((42,43+bob,34,47+bob), fill=GOLD, width=1)
    # central diamond rune heart
    d.polygon([(32,27+bob),(40,35+bob),(32,44+bob),(24,35+bob)], fill=VIOLET_DK, outline=GOLD_HI)
    d.polygon([(32,30+bob),(37,35+bob),(32,41+bob),(27,35+bob)], fill=VIOLET)
    d.polygon([(32,32+bob),(34,35+bob),(32,38+bob),(30,35+bob)], fill=pulse)
    d.rectangle((31,34+bob,33,36+bob), fill=WHITE)
    # pointed mask/helmet
    d.polygon([(25,6+bob),(32,2+bob),(39,6+bob),(42,14+bob),(39,22+bob),
               (32,25+bob),(25,22+bob),(22,14+bob)], fill=(135,123,145,255), outline=OUTLINE)
    d.polygon([(27,7+bob),(32,4+bob),(37,8+bob),(38,13+bob),(32,12+bob),(26,13+bob)],
              fill=(190,180,188,255))
    d.polygon([(26,12+bob),(38,12+bob),(36,18+bob),(32,21+bob),(28,18+bob)],
              fill=(26,21,34,255), outline=OUTLINE)
    d.rectangle((28,14+bob,30,16+bob), fill=pulse)
    d.rectangle((34,14+bob,36,16+bob), fill=pulse)
    d.point((29,15+bob), fill=WHITE); d.point((35,15+bob), fill=WHITE)
    d.line((24,9+bob,29,5+bob), fill=GOLD, width=1)
    d.line((40,9+bob,35,5+bob), fill=GOLD, width=1)
    d.point((32,2+bob), fill=GOLD_HI)
    d.point((25,19+bob), fill=GOLD_DK); d.point((39,19+bob), fill=GOLD_DK)
    # floating claw gauntlets
    d.polygon([(6,26+bob),(16,25+bob),(20,33+bob),(17,42+bob),(9,41+bob),(5,35+bob)],
              fill=(70,62,89,255), outline=OUTLINE)
    d.polygon([(58,26+bob),(48,25+bob),(44,33+bob),(47,42+bob),(55,41+bob),(59,35+bob)],
              fill=(70,62,89,255), outline=OUTLINE)
    d.line((8,33+bob,16,37+bob), fill=GOLD_HI, width=1)
    d.line((56,33+bob,48,37+bob), fill=GOLD_HI, width=1)
    for x in (9,13,17): d.line((x,40+bob,x,45+bob), fill=(161,150,171,255), width=1)
    for x in (47,51,55): d.line((x,40+bob,x,45+bob), fill=(161,150,171,255), width=1)
    # hovering rune motes
    d.point((5,20+bob), fill=pulse); d.point((59,20+bob), fill=pulse)
    d.point((11,52+bob), fill=VIOLET); d.point((53,52+bob), fill=VIOLET)
    return outline_image(im)


def draw_vesper(phase=0):
    im=new(48,64); d=ImageDraw.Draw(im)
    bob=-1 if phase in (1,2) else 0
    flame_shift=1 if phase in (2,3) else 0
    # staff
    d.line((9,18+bob,9,55+bob), fill=(68,45,57,255), width=2)
    d.line((6,18+bob,12,18+bob), fill=GOLD, width=2)
    d.arc((5,10+bob,13,21+bob), 200, 340, fill=GOLD_HI, width=2)
    # floating candle flame
    d.polygon([(9,17+bob),(6,11+bob),(9,4+bob),(12,10+bob)], fill=VIOLET_DK, outline=OUTLINE)
    d.polygon([(9,15+bob),(7,11+bob),(9,7+bob),(11,11+bob)], fill=VIOLET)
    d.rectangle((9,10+bob,10,13+bob), fill=VIOLET_HI)
    # robe body
    d.polygon([(16,20+bob),(32,20+bob),(36,37+bob),(39,55+bob),(32,52+bob),
               (28,59+bob),(24,52+bob),(17,56+bob),(13,52+bob),(15,35+bob)],
              fill=(53,41,67,255), outline=OUTLINE)
    d.polygon([(19,22+bob),(29,22+bob),(31,34+bob),(25,31+bob),(18,35+bob)],
              fill=(79,61,94,255))
    d.line((24,24+bob,24,45+bob), fill=GOLD_DK, width=1)
    d.line((20,30+bob,28,30+bob), fill=GOLD)
    # hood / head
    d.polygon([(15,16+bob),(20,5+bob),(28,3+bob),(35,10+bob),(31,22+bob),
               (25,26+bob),(18,23+bob)], fill=(64,49,82,255), outline=OUTLINE)
    d.polygon([(19,12+bob),(25,8+bob),(31,12+bob),(29,20+bob),(23,23+bob),(18,18+bob)],
              fill=(24,20,31,255), outline=OUTLINE)
    d.rectangle((21,14+bob,23,16+bob), fill=WHITE)
    d.rectangle((27,14+bob,29,16+bob), fill=WHITE)
    d.point((22,14+bob), fill=VIOLET_HI); d.point((28,14+bob), fill=VIOLET_HI)
    d.polygon([(24,17+bob),(26,19+bob),(24,21+bob),(22,19+bob)], fill=GOLD)
    # sleeves / hands
    d.line((17,24+bob,10,34+bob,12,40+bob), fill=(71,54,87,255), width=5)
    d.line((31,24+bob,38,33+bob,35,41+bob), fill=(71,54,87,255), width=5)
    d.rectangle((10,38+bob,13,42+bob), fill=(166,146,160,255), outline=OUTLINE)
    d.rectangle((33,39+bob,36,43+bob), fill=(166,146,160,255), outline=OUTLINE)
    # trim + rune hem
    d.line((18,49+bob,30,49+bob), fill=GOLD, width=1)
    d.rectangle((23,48+bob,25,50+bob), fill=VIOLET_HI)
    d.point((16,24+bob), fill=VIOLET_HI); d.point((32,26+bob), fill=VIOLET)
    return outline_image(im)

# -- Python enemy: Brass Prowler --------------------------------------
def draw_prowler(phase=0):
    im=new(64,48); d=ImageDraw.Draw(im)
    bob=-1 if phase in (1,2) else 0
    # four jointed legs
    for side in (0,1):
        x0=16 if side==0 else 44
        d.line((x0,31+bob,x0-5,39+bob,x0-2,46+bob), fill=BRASS_DK, width=3)
        d.line((x0+8,31+bob,x0+12,39+bob,x0+9,46+bob), fill=BRASS_DK, width=3)
        d.rectangle((x0-4,44+bob,x0+1,47+bob), fill=BRASS, outline=OUTLINE)
        d.rectangle((x0+8,44+bob,x0+13,47+bob), fill=BRASS, outline=OUTLINE)
    # low armoured body
    d.ellipse((12,19+bob,52,37+bob), fill=BLUE, outline=OUTLINE)
    d.rectangle((17,21+bob,45,29+bob), fill=BLUE_HI)
    d.polygon([(18,18+bob),(29,15+bob),(40,18+bob),(36,24+bob),(23,24+bob)],
              fill=BRASS, outline=OUTLINE)
    d.line((18,30+bob,43,30+bob), fill=BRASS_DK, width=2)
    for x in (20,28,36,44): d.point((x,26+bob), fill=BRASS_HI)
    # head (hound/crab)
    d.polygon([(5,23+bob),(18,20+bob),(24,25+bob),(20,35+bob),(10,37+bob)],
              fill=BRASS, outline=OUTLINE)
    d.rectangle((8,29+bob,19,32+bob), fill=TEAL_DK, outline=OUTLINE)
    d.rectangle((10,30+bob,17,31+bob), fill=TEAL_HI)
    d.polygon([(6,34+bob),(12,34+bob),(8,40+bob),(4,39+bob)], fill=BRASS_DK, outline=OUTLINE)
    d.polygon([(17,35+bob),(22,33+bob),(23,39+bob),(18,40+bob)], fill=BRASS_DK, outline=OUTLINE)
    d.rectangle((7,22+bob,10,24+bob), fill=BRASS_HI)
    # back crystal + gear
    d.ellipse((35,12+bob,48,28+bob), fill=BRASS_DK, outline=OUTLINE)
    d.arc((35,12+bob,48,28+bob), 20, 340, fill=BRASS_HI, width=1)
    d.polygon([(41,10+bob),(47,18+bob),(41,26+bob),(36,18+bob)],
              fill=TEAL_DK, outline=OUTLINE)
    d.polygon([(41,13+bob),(44,18+bob),(41,23+bob),(38,18+bob)], fill=TEAL_HI)
    d.rectangle((40,16+bob,42,20+bob), fill=WHITE)
    # tail pipe
    d.line((51,27+bob,58,23+bob,62,26+bob), fill=BRASS_DK, width=3)
    d.rectangle((57,21+bob,61,24+bob), fill=BRASS, outline=OUTLINE)
    d.point((7,31+bob), fill=TEAL_HI)
    return outline_image(im)

# -- Python enemy: Cipher Warden --------------------------------------
def draw_warden(phase=0):
    im=new(64,64); d=ImageDraw.Draw(im)
    bob=-1 if phase in (1,2) else 0
    # back brass halo ring
    d.ellipse((15,13+bob,49,47+bob), fill=(0,0,0,0), outline=BRASS_DK, width=4)
    d.arc((15,13+bob,49,47+bob), 20, 320, fill=BRASS, width=2)
    for ax,ay in ((32,12),(50,30),(32,48),(14,30)):
        d.polygon([(ax,ay-2+bob),(ax+2,ay+bob),(ax,ay+2+bob),(ax-2,ay+bob)], fill=BRASS_HI, outline=OUTLINE)
    # lower obelisk body
    d.polygon([(24,33+bob),(40,33+bob),(44,54+bob),(39,59+bob),(33,55+bob),
               (28,60+bob),(22,55+bob),(19,50+bob)], fill=BLUE_DK, outline=OUTLINE)
    d.polygon([(26,35+bob),(38,35+bob),(40,49+bob),(34,47+bob),(28,51+bob),(23,47+bob)],
              fill=BLUE)
    d.line((21,47+bob,43,47+bob), fill=BRASS, width=2)
    d.line((24,52+bob,40,52+bob), fill=BRASS_DK, width=1)
    # chest diamond core
    d.polygon([(32,20+bob),(45,33+bob),(32,47+bob),(19,33+bob)], fill=BRASS_DK, outline=OUTLINE)
    d.polygon([(32,23+bob),(41,33+bob),(32,44+bob),(23,33+bob)], fill=BRASS)
    d.polygon([(32,26+bob),(38,33+bob),(32,41+bob),(26,33+bob)], fill=TEAL_DK)
    d.polygon([(32,28+bob),(35,33+bob),(32,38+bob),(29,33+bob)], fill=TEAL_HI)
    d.rectangle((31,31+bob,33,35+bob), fill=WHITE)
    # head mask above
    d.polygon([(25,8+bob),(32,4+bob),(39,8+bob),(38,19+bob),(32,23+bob),(26,19+bob)],
              fill=BRASS, outline=OUTLINE)
    d.polygon([(28,9+bob),(32,6+bob),(36,10+bob),(35,15+bob),(32,18+bob),(29,15+bob)],
              fill=BLUE_DK, outline=OUTLINE)
    d.rectangle((31,10+bob,33,16+bob), fill=TEAL_HI)
    d.rectangle((32,11+bob,32,15+bob), fill=WHITE)
    d.point((28,8+bob), fill=GOLD_HI); d.point((36,8+bob), fill=GOLD_HI)
    # floating arm clamps
    d.polygon([(8,27+bob),(15,24+bob),(19,30+bob),(15,38+bob),(9,36+bob)],
              fill=BRASS_DK, outline=OUTLINE)
    d.polygon([(56,27+bob),(49,24+bob),(45,30+bob),(49,38+bob),(55,36+bob)],
              fill=BRASS_DK, outline=OUTLINE)
    d.line((9,31+bob,15,33+bob), fill=TEAL, width=1)
    d.line((55,31+bob,49,33+bob), fill=TEAL, width=1)
    d.rectangle((12,20+bob,14,24+bob), fill=TEAL_DK)
    d.rectangle((50,20+bob,52,24+bob), fill=TEAL_DK)
    return outline_image(im)


# -- atmospheric birds ------------------------------------------------
def draw_finch(wing=0, phase=0):
    im=new(24,24); d=ImageDraw.Draw(im)
    yoff=-1 if phase%2 else 0
    # wings: wide, coral-tipped, viewed from above
    if wing==0:
        left=[(11,12+yoff),(3,8+yoff),(4,15+yoff),(9,17+yoff)]
        right=[(13,12+yoff),(21,7+yoff),(20,15+yoff),(15,17+yoff)]
    else:
        left=[(11,12+yoff),(5,14+yoff),(7,19+yoff),(11,17+yoff)]
        right=[(13,12+yoff),(19,13+yoff),(17,19+yoff),(13,17+yoff)]
    d.polygon(left, fill=(211,111,67,255), outline=OUTLINE)
    d.polygon(right, fill=(211,111,67,255), outline=OUTLINE)
    d.polygon(left[:3]+[(left[2][0]-2,left[2][1]-2)], fill=(245,156,90,255))
    d.polygon(right[:3]+[(right[2][0]+2,right[2][1]-2)], fill=(245,156,90,255))
    # body + head
    d.ellipse((8,8+yoff,17,20+yoff), fill=GOLD, outline=OUTLINE)
    d.ellipse((10,5+yoff,15,11+yoff), fill=GOLD_HI, outline=OUTLINE)
    d.polygon([(11,6+yoff),(13,3+yoff),(15,6+yoff)], fill=AMBER_HI)
    d.rectangle((10,8+yoff,11,9+yoff), fill=INK)
    d.point((11,8+yoff), fill=WHITE)
    d.polygon([(15,8+yoff),(18,10+yoff),(15,11+yoff)], fill=(242,130,56,255))
    # tail feathers
    d.polygon([(11,18+yoff),(16,18+yoff),(14,23+yoff),(12,22+yoff)], fill=RUST, outline=OUTLINE)
    d.line((12,19+yoff,12,22+yoff), fill=GOLD_HI)
    return outline_image(im)

def draw_kite(wing=0, phase=0):
    im=new(32,32); d=ImageDraw.Draw(im)
    yoff=-1 if phase%2 else 0
    dark=(42,51,78,255); hi=(72,92,122,255); teal=(63,162,165,255)
    if wing==0:
        left=[(14,16+yoff),(2,9+yoff),(4,18+yoff),(12,21+yoff)]
        right=[(18,16+yoff),(30,8+yoff),(28,18+yoff),(20,21+yoff)]
    else:
        left=[(14,16+yoff),(4,18+yoff),(8,24+yoff),(14,22+yoff)]
        right=[(18,16+yoff),(28,18+yoff),(24,24+yoff),(18,22+yoff)]
    d.polygon(left, fill=dark, outline=OUTLINE)
    d.polygon(right, fill=dark, outline=OUTLINE)
    d.polygon([left[0],left[1],(left[1][0]+5,left[1][1]+3)], fill=hi)
    d.polygon([right[0],right[1],(right[1][0]-5,right[1][1]+3)], fill=hi)
    d.point((6,12+yoff), fill=teal); d.point((26,11+yoff), fill=teal)
    # body/head
    d.ellipse((12,10+yoff,20,23+yoff), fill=dark, outline=OUTLINE)
    d.ellipse((14,7+yoff,18,13+yoff), fill=hi, outline=OUTLINE)
    d.polygon([(14,8+yoff),(16,5+yoff),(18,8+yoff)], fill=dark, outline=OUTLINE)
    d.rectangle((14,9+yoff,15,10+yoff), fill=WHITE)
    d.point((15,9+yoff), fill=teal)
    # forked tail
    d.polygon([(13,21+yoff),(19,21+yoff),(23,29+yoff),(16,26+yoff),(15,29+yoff)],
              fill=dark, outline=OUTLINE)
    d.point((17,24+yoff), fill=teal)
    return outline_image(im)

# -- will-o'-the-wisp -------------------------------------------------
def draw_wisp(phase=0):
    im=new(32,32); d=ImageDraw.Draw(im)
    shift=[(0,0),(1,-1),(-1,0),(0,1)][phase%4]
    # irregular flame body, deliberately asymmetric
    outer=[(16+shift[0],3+shift[1]),(21,10),(19,13),(25,19),(22,23),
           (27,28),(19,25),(16,30),(13,25),(6,27),(10,20),(7,15),
           (12,12),(10,7)]
    d.polygon(outer, fill=(35,66,78,255), outline=OUTLINE)
    d.polygon([(16+shift[0],7+shift[1]),(20,13),(18,16),(23,21),(19,23),
               (22,26),(16,23),(14,26),(10,22),(12,17),(9,13),(13,10)],
              fill=(46,118,125,255))
    d.polygon([(16,11),(20,15),(18,20),(22,23),(17,25),(14,21),(12,17),(13,14)],
              fill=TEAL)
    d.ellipse((13,15,19,22), fill=TEAL_HI)
    d.ellipse((15,17,18,20), fill=WHITE)
    # eye-like hollow + trailing motes (reads as spectral, not a torch)
    d.rectangle((15,17,16,18), fill=(30,74,82,255))
    d.point((16,18), fill=WHITE)
    d.rectangle((7,25,8,26), fill=TEAL_DK)
    d.rectangle((24,8,25,9), fill=TEAL_DK)
    d.point((5,18), fill=TEAL_HI); d.point((27,23), fill=TEAL_HI)
    d.point((11,29), fill=TEAL); d.point((24,29), fill=TEAL)
    return outline_image(im)

# -- point-and-click cursors (native 24x24) ---------------------------
def cursor_common(im):
    return outline_image(im, OUTLINE, 1)

def draw_cursor_movement():
    im=new(24,24); d=ImageDraw.Draw(im)
    # diagonal arrow with two trailing afterglow pixels
    pts=[(4,4),(11,6),(9,11),(17,16),(14,20),(7,14),(4,17)]
    d.polygon(pts, fill=TEAL, outline=OUTLINE)
    d.polygon([(5,5),(10,7),(8,10),(7,8)], fill=TEAL_HI)
    d.rectangle((17,18,19,20), fill=GOLD)
    d.rectangle((20,14,22,16), fill=TEAL_DK)
    d.rectangle((22,20,23,21), fill=TEAL_HI)
    return cursor_common(im)

def draw_cursor_chest():
    im=new(24,24); d=ImageDraw.Draw(im)
    # tiny common pointer notch
    d.polygon([(2,2),(7,3),(4,7)], fill=WHITE, outline=OUTLINE)
    d.rectangle((7,11,21,21), fill=RUST_DK, outline=OUTLINE)
    d.rectangle((7,14,21,20), fill=RUST, outline=OUTLINE)
    d.arc((7,8,21,17), 180, 360, fill=GOLD, width=3)
    d.rectangle((12,8,16,14), fill=GOLD_DK, outline=OUTLINE)
    d.line((12,9,16,13), fill=GOLD_HI)
    d.rectangle((11,16,13,20), fill=GOLD_HI)
    d.point((20,7), fill=GOLD_HI); d.point((22,5), fill=GOLD)
    return cursor_common(im)

def draw_cursor_crafting():
    im=new(24,24); d=ImageDraw.Draw(im)
    d.polygon([(2,2),(7,3),(4,7)], fill=WHITE, outline=OUTLINE)
    steel=(163,173,181,255); steel_hi=(230,236,238,255); steel_dk=(83,95,108,255)
    # anvil
    d.polygon([(5,20),(19,20),(17,22),(15,22),(15,23),(9,23),(9,22),(7,22)], fill=steel_dk, outline=OUTLINE)
    d.rectangle((7,18,17,20), fill=steel, outline=OUTLINE)
    d.polygon([(5,16),(19,16),(17,19),(7,19)], fill=steel_hi, outline=OUTLINE)
    d.line((7,17,17,17), fill=WHITE)
    # hammer
    d.line((9,19,16,8), fill=RUST_DK, width=2)
    d.polygon([(14,5),(21,7),(18,12),(12,10)], fill=steel, outline=OUTLINE)
    d.line((15,7,19,8), fill=WHITE)
    d.point((20,5), fill=GOLD_HI); d.point((4,13), fill=GOLD)
    return cursor_common(im)

def draw_cursor_furnace():
    im=new(24,24); d=ImageDraw.Draw(im)
    d.polygon([(2,2),(7,3),(4,7)], fill=WHITE, outline=OUTLINE)
    brick=(105,68,52,255); brick_hi=(151,99,69,255); brick_dk=(66,45,39,255)
    # chimney and smoke
    d.rectangle((15,5,20,13), fill=brick, outline=OUTLINE)
    d.rectangle((15,5,20,7), fill=brick_dk, outline=OUTLINE)
    d.rectangle((17,2,18,3), fill=(172,177,181,255), outline=OUTLINE)
    d.rectangle((19,3,21,4), fill=(142,150,157,255))
    # furnace body
    d.rectangle((4,11,21,23), fill=brick, outline=OUTLINE)
    d.rectangle((4,11,21,12), fill=brick_dk)
    d.arc((6,8,19,17), 180, 360, fill=brick_hi, width=2)
    # arched fire mouth
    d.pieslice((7,14,19,25), 180, 360, fill=(37,28,30,255), outline=OUTLINE)
    d.rectangle((7,19,19,22), fill=(37,28,30,255), outline=OUTLINE)
    d.polygon([(12,22),(10,18),(12,15),(15,18),(13,20),(14,22)], fill=AMBER, outline=OUTLINE)
    d.polygon([(13,21),(12,18),(13,17),(14,19)], fill=AMBER_HI)
    # grate and brick joints
    for x in (9,12,15,18): d.line((x,19,x,22), fill=(91,67,58,255))
    for y in (14,16): d.line((5,y,8,y), fill=brick_hi)
    for y in (14,16): d.line((19,y,21,y), fill=brick_hi)
    d.point((6,12), fill=brick_hi); d.point((21,12), fill=brick_hi)
    return cursor_common(im)

def draw_cursor_color_crafter():
    im=new(24,24); d=ImageDraw.Draw(im)
    d.polygon([(2,2),(7,3),(4,7)], fill=WHITE, outline=OUTLINE)
    # palette
    d.ellipse((4,8,21,20), fill=(91,59,67,255), outline=OUTLINE)
    d.ellipse((7,10,18,18), fill=(115,76,82,255), outline=OUTLINE)
    d.rectangle((8,14,10,17), fill=(45,34,42,255))
    for p,c in [((7,11),VIOLET),((11,10),TEAL),((15,11),AMBER),((18,13),RUST_HI)]:
        d.ellipse((p[0],p[1],p[0]+2,p[1]+2), fill=c, outline=OUTLINE)
    # brush
    d.line((14,20,20,9), fill=RUST_DK, width=2)
    d.polygon([(19,9),(22,6),(23,9),(20,12)], fill=GOLD_HI, outline=OUTLINE)
    d.point((21,7), fill=TEAL_HI)
    return cursor_common(im)

def draw_cursor_generic():
    im=new(24,24); d=ImageDraw.Draw(im)
    d.polygon([(2,2),(7,3),(4,7)], fill=WHITE, outline=OUTLINE)
    # gloved hand / interaction
    d.polygon([(7,18),(7,12),(9,12),(9,9),(11,9),(11,8),(13,8),(13,12),
               (16,10),(18,11),(18,14),(17,18),(14,21),(9,21)],
              fill=CREAM, outline=OUTLINE)
    d.line((8,13,11,13), fill=CREAM_HI)
    d.line((8,16,14,16), fill=CREAM_HI)
    d.rectangle((15,5,17,7), fill=TEAL_HI, outline=OUTLINE)
    d.point((20,7), fill=TEAL); d.point((4,19), fill=GOLD_HI)
    return cursor_common(im)

CURSORS = {
    "movement": ("Movement", draw_cursor_movement),
    "open_chest": ("Open Chest", draw_cursor_chest),
    "open_crafting": ("Open Crafting", draw_cursor_crafting),
    "open_furnace": ("Open Furnace", draw_cursor_furnace),
    "open_color_crafter": ("Open Color Crafter", draw_cursor_color_crafter),
    "generic_interact": ("Generic Interact", draw_cursor_generic),
}

# -- legendary items (32x32) ------------------------------------------
def draw_starfall_prism():
    im=new(32,32); d=ImageDraw.Draw(im)
    # gold crescent cradle
    d.arc((6,14,26,29), 195, 345, fill=GOLD_DK, width=4)
    d.arc((7,15,25,28), 200, 340, fill=GOLD, width=2)
    d.arc((6,15,17,26), 200, 310, fill=GOLD_HI, width=1)
    # tall faceted prism
    d.polygon([(16,2),(22,8),(20,20),(16,26),(12,20),(10,8)], fill=(157,191,227,255), outline=OUTLINE)
    d.polygon([(16,4),(19,9),(18,18),(16,23),(14,18),(13,9)], fill=(220,238,255,255))
    d.polygon([(16,4),(16,23),(13,18),(13,9)], fill=(122,157,198,255))
    d.line((16,5,16,21), fill=WHITE)
    d.point((16,7), fill=VIOLET_HI); d.point((18,14), fill=TEAL_HI)
    d.rectangle((6,26,26,27), fill=GOLD_HI)
    # tiny stars
    for x,y in ((4,8),(28,7),(27,20),(4,20),(25,29)):
        d.point((x,y), fill=GOLD_HI)
    return outline_image(im)

def draw_rootbound_crown():
    im=new(32,32); d=ImageDraw.Draw(im)
    # living wood circlet
    d.arc((5,14,27,28), 180, 360, fill=(79,55,37,255), width=4)
    d.arc((7,16,25,27), 185, 355, fill=(129,92,54,255), width=2)
    # leaf prongs
    d.polygon([(8,17),(3,9),(9,7),(13,15)], fill=MOSS, outline=OUTLINE)
    d.polygon([(24,17),(29,8),(23,6),(19,15)], fill=MOSS, outline=OUTLINE)
    d.polygon([(16,13),(13,3),(16,5),(19,2),(20,13)], fill=MOSS_HI, outline=OUTLINE)
    d.line((7,11,10,8), fill=MOSS_HI); d.line((25,10,22,7), fill=MOSS_HI)
    # central amber gem
    d.polygon([(16,17),(20,21),(16,26),(12,21)], fill=AMBER, outline=OUTLINE)
    d.polygon([(16,19),(18,21),(16,24),(14,21)], fill=AMBER_HI)
    d.point((15,20), fill=WHITE)
    # root tendrils
    d.line((9,27,7,30), fill=(92,63,39,255)); d.line((23,27,25,30), fill=(92,63,39,255))
    return outline_image(im)

def draw_eclipse_fang():
    im=new(32,32); d=ImageDraw.Draw(im)
    # dark curved blade (diagonal like existing swords)
    d.polygon([(7,25),(9,22),(20,5),(24,7),(13,24)], fill=(54,42,68,255), outline=OUTLINE)
    d.polygon([(10,23),(19,7),(22,8),(13,24)], fill=(87,67,109,255))
    d.line((12,22,20,8), fill=VIOLET_HI)
    # crescent guard
    d.arc((2,18,16,31), 200, 340, fill=BONE, width=2)
    d.arc((3,19,15,30), 205, 335, fill=WHITE, width=1)
    # gold hilt
    d.line((7,25,3,29), fill=GOLD_DK, width=4)
    d.line((7,25,4,28), fill=GOLD_HI, width=2)
    d.polygon([(2,27),(5,30),(3,32),(0,29)], fill=GOLD, outline=OUTLINE)
    # ember pommel
    d.polygon([(4,28),(7,30),(5,31),(2,30)], fill=RUST, outline=OUTLINE)
    d.point((22,6), fill=TEAL_HI)
    return outline_image(im)

def draw_tideglass_compass():
    im=new(32,32); d=ImageDraw.Draw(im)
    # brass ring
    d.ellipse((3,5,29,31), fill=BRASS_DK, outline=OUTLINE)
    d.ellipse((5,7,27,29), fill=BRASS)
    d.ellipse((7,9,25,27), fill=BLUE_DK, outline=OUTLINE)
    d.ellipse((9,11,23,25), fill=(45,121,151,255), outline=TEAL_DK)
    d.ellipse((11,13,21,23), fill=(91,190,194,255))
    # needle
    d.polygon([(16,11),(19,17),(16,22),(13,17)], fill=(237,229,196,255), outline=OUTLINE)
    d.polygon([(16,11),(16,17),(13,17)], fill=RUST_HI)
    d.point((16,13), fill=WHITE)
    # cardinal notches and crown ring
    d.rectangle((14,1,18,6), fill=BRASS, outline=OUTLINE)
    d.ellipse((14,1,18,4), fill=GOLD_HI, outline=OUTLINE)
    for p in ((16,6),(16,28),(6,17),(26,17)):
        d.point(p, fill=GOLD_HI)
    d.point((11,13), fill=TEAL_HI); d.point((21,23), fill=TEAL_HI)
    return outline_image(im)

def draw_ashen_bell():
    im=new(32,32); d=ImageDraw.Draw(im)
    # handle
    d.arc((12,2,20,12), 180, 360, fill=BRASS_DK, width=3)
    d.arc((13,4,19,11), 180, 360, fill=GOLD, width=1)
    # bell body
    d.polygon([(10,12),(22,12),(28,25),(23,27),(21,29),(11,29),(9,27),(4,25)],
              fill=(70,61,57,255), outline=OUTLINE)
    d.polygon([(12,14),(20,14),(25,24),(18,23),(14,25),(7,24)],
              fill=(105,88,67,255))
    d.line((8,23,24,23), fill=TEAL, width=2)
    d.line((9,20,23,20), fill=GOLD_DK, width=1)
    for x in (10,14,18,22):
        d.point((x,22), fill=TEAL_HI)
    # clapper + ash cracks
    d.rectangle((15,29,18,32), fill=BRASS, outline=OUTLINE)
    d.rectangle((16,30,17,31), fill=AMBER)
    d.line((12,15,12,18), fill=(43,38,38,255))
    d.line((13,18,15,20), fill=(43,38,38,255))
    d.point((7,14), fill=(157,135,99,255)); d.point((25,15), fill=(157,135,99,255))
    d.point((5,27), fill=GOLD_HI); d.point((27,28), fill=GOLD_HI)
    return outline_image(im)

LEGENDARY = [
    ("starfall_prism","Starfall Prism","Legendary artifact",
     "A faceted sky-crystal cradled in a thin gold crescent. Pale blue, white and a single violet facet keep the shape readable; very restrained sparkles."),
    ("rootbound_crown","Rootbound Crown","Legendary accessory",
     "A living circlet of dark roots, three moss-green leaves and a warm amber heart-gem. Compact, organic silhouette with no glow dependence."),
    ("eclipse_fang","Eclipse Fang","Legendary weapon",
     "A curved obsidian fang with a bone-white crescent guard and gold hilt. The deep violet blade catches one pale edge highlight and a tiny teal glint."),
    ("tideglass_compass","Tideglass Compass","Legendary tool / relic",
     "A brass compass holding a blue tideglass lens and a coral-and-ivory needle. Readable rings and cardinal notches, rare brass rather than magical bloom."),
    ("ashen_bell","Ashen Bell","Legendary relic",
     "A blackened bronze bell with a teal rune band, ember clapper and ash-grey cracks. Mysterious rather than glowing, with a small gold handle."),
]
LEGENDARY_DRAW = {
    "starfall_prism":draw_starfall_prism,
    "rootbound_crown":draw_rootbound_crown,
    "eclipse_fang":draw_eclipse_fang,
    "tideglass_compass":draw_tideglass_compass,
    "ashen_bell":draw_ashen_bell,
}


# ----------------------------------------------------------------------
# Presentation helpers
# ----------------------------------------------------------------------
BG_DARK=(17,19,27,255); BG_PANEL=(25,28,40,255); BG_PANEL2=(32,36,49,255)
BORDER=(67,80,112,255); MUTED=(154,166,190,255); TITLE=(220,230,247,255)
ACCENT=(93,213,199,255); ACCENT2=(239,199,104,255)
PREV.mkdir(parents=True,exist_ok=True)
(PREV/"isolated_large").mkdir(parents=True,exist_ok=True)

def wrap(d,text,fnt,maxw,fill):
    words=text.split()
    lines=[]; cur=""
    for w in words:
        test=(cur+" "+w).strip()
        if d.textlength(test,font=fnt)<=maxw:
            cur=test
        else:
            if cur: lines.append(cur)
            cur=w
    if cur: lines.append(cur)
    y=0
    for line in lines:
        d.text((0,y),line,font=fnt,fill=fill)
        y+=fnt.size+5
    return y

def large_on_checker(sprite, scale=8, margin=20, label=None):
    sw,sh=sprite.size
    w=sw*scale+margin*2; h=sh*scale+margin*2+(28 if label else 0)
    bg=checker(w,h,16)
    bg.alpha_composite(scale_nn(sprite,scale),(margin,margin))
    if label:
        d=ImageDraw.Draw(bg); d.text((margin,h-24),label,font=font(13),fill=MUTED)
    return bg

def save_large(sprite,name):
    img=large_on_checker(sprite,8,20,name)
    img.save(PREV/"isolated_large"/(name+".png"))

def category_sheet(title,subtitle,entries,out_name,card_scale=5,cols=2):
    cw=770; ch=680; header=110
    rows=(len(entries)+cols-1)//cols
    W=cols*cw+30; H=header+rows*ch+20
    canvas=Image.new("RGBA",(W,H),BG_DARK)
    d=ImageDraw.Draw(canvas)
    d.rectangle((0,0,W,82),fill=(13,15,23,255))
    d.text((26,20),title,font=font(26),fill=TITLE)
    d.text((28,55),subtitle,font=font(13),fill=MUTED)
    for i,e in enumerate(entries):
        x=20+(i%cols)*cw; y=header+(i//cols)*ch
        d.rounded_rectangle((x,y,x+cw-20,y+ch-20),radius=8,fill=BG_PANEL,outline=BORDER,width=1)
        sprite=e["sprite"]; fnt=e.get("font_size",13)
        prev_h=360
        d.text((x+18,y+16),e["name"],font=font(20),fill=TITLE)
        d.text((x+18,y+43),e.get("tag",""),font=font(11),fill=ACCENT)
        d.text((x+18,y+61),e.get("dims",""),font=font(11),fill=MUTED)
        # checker display area
        cb=checker(cw-56,prev_h,16); canvas.alpha_composite(cb,(x+28,y+84))
        sc=card_scale
        sw,sh=sprite.size
        while sw*sc>cw-110 or sh*sc>prev_h-40:
            sc-=1
        disp=scale_nn(sprite,max(1,sc))
        canvas.alpha_composite(disp,(x+28+(cw-56-disp.width)//2,
                                  y+84+(prev_h-disp.height)//2))
        d.rectangle((x+28,y+84,x+cw-28,y+84+prev_h),outline=BORDER,width=1)
        d.text((x+28,y+84+prev_h+8),f"nearest-neighbour preview {max(1,sc)}x",font=font(10),fill=MUTED)
        desc_y=y+84+prev_h+30
        # palette swatches
        px=x+28
        for col in e.get("palette",[]):
            d.rectangle((px,desc_y,px+14,desc_y+14),fill=col,outline=OUTLINE)
            px+=19
        desc_y+=24
        # description wrapped
        fnt=font(12)
        words=e.get("desc","").split(); cur=""; lines=[]
        for word in words:
            test=(cur+" "+word).strip()
            if d.textlength(test,font=fnt)<=cw-60: cur=test
            else:
                if cur: lines.append(cur)
                cur=word
        if cur: lines.append(cur)
        for line in lines[:5]:
            d.text((x+28,desc_y),line,font=fnt,fill=(195,204,220,255)); desc_y+=18
        # animation strip
        frames=e.get("frames")
        if frames:
            d.text((x+28,desc_y+4),e.get("frame_label","IDLE CONCEPT"),font=font(10),fill=MUTED)
            fx=x+150
            for fr in frames:
                thumb=scale_nn(fr,2 if max(fr.size)<=32 else 1)
                canvas.alpha_composite(thumb,(fx,desc_y-4))
                d.rectangle((fx,desc_y-4,fx+thumb.width,desc_y-4+thumb.height),outline=BORDER)
                fx+=thumb.width+6
    canvas.save(PREV/out_name)

def static_sheet(raw_items,out_name,title,subtitle,scale=6,cols=4):
    cw=380; ch=330; header=100
    rows=(len(raw_items)+cols-1)//cols
    W=cols*cw+20; H=header+rows*ch+20
    canvas=Image.new("RGBA",(W,H),BG_DARK); d=ImageDraw.Draw(canvas)
    d.rectangle((0,0,W,76),fill=(13,15,23,255))
    d.text((22,16),title,font=font(23),fill=TITLE)
    d.text((24,49),subtitle,font=font(12),fill=MUTED)
    for i,(name,sprite,desc) in enumerate(raw_items):
        x=10+(i%cols)*cw; y=header+(i//cols)*ch
        d.rounded_rectangle((x,y,x+cw-10,y+ch-10),radius=6,fill=BG_PANEL,outline=BORDER)
        d.text((x+14,y+12),name,font=font(15),fill=TITLE)
        cb=checker(cw-28,200,12); canvas.alpha_composite(cb,(x+14,y+38))
        im=scale_nn(sprite,scale)
        if im.width>cw-50 or im.height>190:
            im=sprite.copy(); im.thumbnail((cw-50,190),Image.Resampling.NEAREST)
        canvas.alpha_composite(im,(x+14+(cw-28-im.width)//2,y+38+(200-im.height)//2))
        d.rectangle((x+14,y+38,x+cw-14,y+238),outline=BORDER)
        fnt=font(11); words=desc.split(); cur=""; yy=y+250
        for word in words:
            test=(cur+" "+word).strip()
            if d.textlength(test,font=fnt)<=cw-30: cur=test
            else:
                d.text((x+14,yy),cur,font=fnt,fill=(190,200,218,255)); yy+=15; cur=word
            if yy>y+ch-20: break
        if cur and yy<=y+ch-20: d.text((x+14,yy),cur,font=fnt,fill=(190,200,218,255))
    canvas.save(PREV/out_name)

# ----------------------------------------------------------------------
# Sprite files + concept sheets
# ----------------------------------------------------------------------
FRIENDLY=[
    ("mossback_nib","Mossback Nib","FRIENDLY GRAZER - 32x32",
     "A low, round moss-shelled grazer with a cream face, stubby feet and a tiny mushroom sprout. The huge friendly eyes and soft leaf tail keep it clearly non-hostile beside the sheep.",
     [MOSS,MOSS_HI,CREAM,GOLD,GOLD_HI],"draw_mossback"),
    ("emberfox_kit","Emberfox Kit","FRIENDLY COMPANION - 48x48",
     "A sitting rust-orange fox kit with oversized ears, cream chest fluff, a curled tail and a teal neckerchief. Its silhouette is taller and more alert than the sheep, but the rounded paws and warm face read friendly.",
     [RUST,RUST_HI,CREAM,TEAL,AMBER],"draw_emberfox"),
]
OVERWORLD_ENEMIES=[
    ("cinder_ooze","Cinder Ooze","OVERWORLD HOSTILE - 48x48",
     "An irregular tar-dark ooze with a jagged cooled crust, glowing orange magma seams and narrowed ember eyes. Distinct from the smooth cyan slime through its cracked, spiky silhouette and volcanic palette.",
     [CHAR,CHAR_HI,RUST,RUST_HI,AMBER],"draw_cinder_ooze"),
    ("gravebell_shambler","Gravebell Shambler","OVERWORLD HOSTILE - 48x48",
     "A gaunt green-grey undead bell-ringer in a ragged coat, with exposed ribs, one amber eye and a corroded handbell. No existing zombie sprite was found, so this follows the hostile humanoid proportions of the dungeon Hitman while staying organic and overworld-scaled.",
     [SKIN_Z,SKIN_Z_HI,(82,69,57,255),BONE,BRASS],"draw_gravebell"),
]
LUA_ENEMIES=[
    ("rune_sentinel","Rune Sentinel","LUA DUNGEON HOSTILE - 64x64",
     "A floating armour shrine: pointed stone pauldrons, a pale mask with violet eyes, gold trim and a diamond rune heart. It contrasts with the dark purple masonry through pale stone and warm gold, with violet magic reserved for the core.",
     [(65,57,85,255),(131,120,145,255),GOLD,GOLD_HI,VIOLET],"draw_rune_sentinel"),
    ("vesper_acolyte","Vesper Acolyte","LUA DUNGEON HOSTILE - 48x64",
     "A tall, hooded candle-cultist with a void face, two bright eyes, gold trim and a violet flame staff. The pointed hood and long robe are deliberately unlike the Sentinel's broad armour silhouette.",
     [(53,41,67,255),(79,61,94,255),GOLD,VIOLET,VIOLET_HI],"draw_vesper"),
]
PYTHON_ENEMIES=[
    ("brass_prowler","Brass Prowler","PYTHON DUNGEON HOSTILE - 64x48",
     "A low four-legged foundry automaton in blue-grey steel and warm brass, with a teal visor, jointed legs and a diamond crystal generator on its back. Its wide, predatory silhouette is unlike the floating Python Warden.",
     [BLUE,BLUE_HI,BRASS,BRASS_HI,TEAL],"draw_prowler"),
    ("cipher_warden","Cipher Warden","PYTHON DUNGEON HOSTILE - 64x64",
     "A tall floating brass-and-basalt warden with a diamond teal core, a ring halo, clamp arms and an obelisk lower body. The arrangement echoes Python's diamond motifs without reusing the Lua enemies' colours.",
     [BLUE_DK,BLUE,BRASS,BRASS_HI,TEAL],"draw_warden"),
]
BIRDS=[
    ("sunshard_finch","Sunshard Finch","ATMOSPHERIC BIRD - 24x24",
     "A plump golden finch with coral-tipped wings, a bright crest and a tiny rust tail. Two wing poses are supplied for a future flap; the bird is deliberately readable as a 12-pixel body and two wing shapes.",
     [GOLD,GOLD_HI,RUST_HI,AMBER_HI,WHITE],"draw_finch"),
    ("dusk_kite","Dusk Kite","ATMOSPHERIC BIRD - 32x32",
     "A larger indigo kite with swept wings, a pale throat, teal wing glints and a forked tail. Its dark silhouette reads as a raptor against the bright overworld, while the teal marks separate it from ordinary crows.",
     [(42,51,78,255),(72,92,122,255),TEAL,(156,249,231,255),WHITE],"draw_kite"),
]
WISP=[
    ("morrow_wisp","Morrow Wisp","ATMOSPHERIC SPECTRE - 32x32",
     "A small floating will-o'-the-wisp with an irregular teal flame, pale-white heart and a dark empty eye mark. Four flame frames vary the silhouette without turning it into a torch or a generic particle.",
     [(35,66,78,255),(46,118,125,255),TEAL,TEAL_HI,WHITE],"draw_wisp"),
]

def make_mob_outputs():
    entries=[]
    for folder,items,fnmap in [
        ("friendly_mobs",FRIENDLY,{"draw_mossback":draw_mossback,"draw_emberfox":draw_emberfox}),
        ("overworld_enemies",OVERWORLD_ENEMIES,{"draw_cinder_ooze":draw_cinder_ooze,"draw_gravebell":draw_gravebell}),
        ("lua_enemies",LUA_ENEMIES,{"draw_rune_sentinel":draw_rune_sentinel,"draw_vesper":draw_vesper}),
        ("python_enemies",PYTHON_ENEMIES,{"draw_prowler":draw_prowler,"draw_warden":draw_warden}),
    ]:
        for slug,name,tag,desc,pal,draw_name in items:
            fn=fnmap[draw_name]
            base=fn(0)
            save_sprite(base,SPR/folder/(slug+".png"))
            frames=[fn(i) for i in range(4)]
            save_frames(frames,SPR/folder/(slug+"_idle_4f.png"))
            save_large(base,slug)
            entries.append({"name":name,"tag":tag,"dims":f"native {base.width}x{base.height}px","desc":desc,
                            "palette":pal,"sprite":base,"frames":frames,"slug":slug,"folder":folder,
                            "frame_label":"IDLE CONCEPT"})
    return entries

def make_bird_outputs():
    for slug,name,tag,desc,pal,draw_name in BIRDS:
        fn=draw_finch if draw_name=="draw_finch" else draw_kite
        base=fn(0,0)
        save_sprite(base,SPR/"birds"/(slug+".png"))
        frames=[fn(0,0),fn(1,0),fn(0,1),fn(1,1)]
        save_frames(frames,SPR/"birds"/(slug+"_wing_4f.png"))
        save_large(base,slug)
    return BIRDS

def make_wisp_outputs():
    slug,name,tag,desc,pal,draw_name=WISP[0]
    base=draw_wisp(0); save_sprite(base,SPR/"wisp"/(slug+".png"))
    frames=[draw_wisp(i) for i in range(4)]
    save_frames(frames,SPR/"wisp"/(slug+"_frames_4f.png"))
    save_large(base,slug)
    return WISP


# ----------------------------------------------------------------------
# Mockups
# ----------------------------------------------------------------------
def load_overworld_crop(w=640,h=320):
    ref=Image.open(BASE/"reference"/"overworld_game_reference.png").convert("RGBA")
    # A representative clearing with grass, trees and stone in the reference
    # panorama. The crop is scaled 2x so the 2x sprite mockups keep the same
    # relative scale as gameplay.
    x=0; y=max(0,(ref.height-h)//2)
    crop=ref.crop((x,y,min(ref.width,x+w),min(ref.height,y+h)))
    if crop.size!=(w,h):
        tmp=Image.new("RGBA",(w,h),(65,152,36,255)); tmp.alpha_composite(crop); crop=tmp
    return crop.resize((w*2,h*2),Image.Resampling.NEAREST)

def paste_actor(canvas,sprite,scale,foot_x,foot_y,label=None,shadow=True):
    im=scale_nn(sprite,scale)
    if shadow:
        sw=max(18,int(im.width*0.68)); sh=max(6,int(im.height*0.17))
        shd=Image.new("RGBA",(sw,sh),(0,0,0,0)); dd=ImageDraw.Draw(shd)
        dd.ellipse((2,2,sw-3,sh-3),fill=(0,0,0,95))
        canvas.alpha_composite(shd,(int(foot_x-sw/2),int(foot_y-sh/2)))
    x=int(foot_x-im.width/2); y=int(foot_y-im.height)
    canvas.alpha_composite(im,(x,y))
    if label:
        d=ImageDraw.Draw(canvas); fnt=font(13)
        tw=d.textlength(label,font=fnt)
        box=(int(foot_x-tw/2-7),int(foot_y+7),int(foot_x+tw/2+7),int(foot_y+26))
        d.rounded_rectangle(box,radius=4,fill=(12,14,21,205),outline=BORDER)
        d.text((box[0]+7,box[1]+4),label,font=fnt,fill=TITLE)

def mockup_banner(canvas,title,subtitle):
    d=ImageDraw.Draw(canvas)
    d.rectangle((0,canvas.height-86,canvas.width,canvas.height),fill=(12,14,21,242))
    d.line((0,canvas.height-86,canvas.width,canvas.height-86),fill=BORDER,width=1)
    d.text((24,canvas.height-72),title,font=font(20),fill=TITLE)
    d.text((25,canvas.height-40),subtitle,font=font(12),fill=MUTED)

def make_overworld_mockup(title,subtitle,actors,out_name,mode="actors"):
    canvas=load_overworld_crop(640,320)
    # crop is already 1280x640
    for act in actors:
        sprite=act["sprite"]; scale=act.get("scale",2)
        paste_actor(canvas,sprite,scale,act["x"],act["y"],act.get("label"),act.get("shadow",True))
    out=Image.new("RGBA",(1280,720),BG_DARK); out.alpha_composite(canvas,(0,0))
    mockup_banner(out,title,subtitle)
    out.save(PREV/out_name)

# -- themed dungeon room mockup base ---------------------------------
def dungeon_room_native(theme):
    wall=Image.open(BASE.parent.parent/"SandEEAlpha"/"sprites"/"dungeon"/theme/"walls.png").convert("RGBA")
    floors=Image.open(BASE.parent.parent/"SandEEAlpha"/"sprites"/"dungeon"/theme/"floors.png").convert("RGBA")
    arch=Image.open(BASE.parent.parent/"SandEEAlpha"/"sprites"/"dungeon"/theme/"blind_arch_96x64.png").convert("RGBA")
    pillar=Image.open(BASE.parent.parent/"SandEEAlpha"/"sprites"/"dungeon"/theme/"pillar_32x96.png").convert("RGBA")
    sconce=Image.open(BASE.parent.parent/"SandEEAlpha"/"sprites"/"dungeon"/theme/"sconce_sheet.png").convert("RGBA").crop((0,0,16,32))
    medallion=Image.open(BASE.parent.parent/"SandEEAlpha"/"sprites"/"dungeon"/theme/"medallion_sheet.png").convert("RGBA").crop((0,0,64,64))
    W,H=640,360; im=Image.new("RGBA",(W,H),(9,10,15,255))
    ox,oy=0,4
    wall_top=[0,1,2]; wall_side=[3,5]; wall_bottom=[6,7,8]
    # floor field
    for y in range(1,10):
        for x in range(1,19):
            idx=(x*3+y*5)%5
            im.alpha_composite(floors.crop((idx*32,0,idx*32+32,32)).convert("RGBA"),(ox+x*32,oy+y*32))
    # top / bottom / side walls
    for x in range(20):
        if x==0: ti=0
        elif x==19: ti=2
        else: ti=1
        im.alpha_composite(wall.crop((ti*32,0,ti*32+32,32)).convert("RGBA"),(ox+x*32,oy))
        bi=6 if x==0 else (8 if x==19 else 7)
        im.alpha_composite(wall.crop((bi*32,0,bi*32+32,32)).convert("RGBA"),(ox+x*32,oy+10*32))
    for y in range(1,10):
        for side,idx in [((0),3),(19,5)]:
            im.alpha_composite(wall.crop((idx*32,0,idx*32+32,32)).convert("RGBA"),(ox+side*32,oy+y*32))
    # architecture: focal blind arch, pillars and sconces
    im.alpha_composite(arch,(272,8))
    im.alpha_composite(pillar,(103,190))
    im.alpha_composite(pillar,(505,190))
    im.alpha_composite(sconce,(208,12)); im.alpha_composite(sconce,(416,12))
    im.alpha_composite(medallion,(288,184))
    return im

def make_dungeon_mockup(theme,title,subtitle,actors,out_name):
    base=dungeon_room_native(theme)
    base=base.resize((1280,720),Image.Resampling.NEAREST)
    for act in actors:
        sprite=act["sprite"]; scale=act.get("scale",2)
        paste_actor(base,sprite,scale,act["x"],act["y"],act.get("label"),True)
    mockup_banner(base,title,subtitle)
    base.save(PREV/out_name)

# ----------------------------------------------------------------------
# Cursors
# ----------------------------------------------------------------------
def make_cursor_outputs():
    for slug,(label,fn) in CURSORS.items():
        sprite=fn()
        save_sprite(sprite,SPR/"cursors"/(slug+".png"))
        save_large(sprite,slug)
    ref=Image.open(BASE/"reference"/"overworld_game_reference.png").convert("RGBA")
    light=ref.crop((500,0,1100,205))
    dark=Image.new("RGBA",(600,205),BG_PANEL); dd=ImageDraw.Draw(dark)
    for y in range(0,205,32): dd.line((0,y,600,y),fill=(38,43,58,255))
    for x in range(0,600,32): dd.line((x,0,x,205),fill=(38,43,58,255))
    W=1600; header=110; row=235; H=header+len(CURSORS)*row+30
    canvas=Image.new("RGBA",(W,H),BG_DARK); d=ImageDraw.Draw(canvas)
    d.rectangle((0,0,W,80),fill=(13,15,23,255))
    d.text((24,16),"POINT-AND-CLICK CURSOR CONCEPTS",font=font(24),fill=TITLE)
    d.text((26,50),"Native 24x24 - light overworld and dark UI backgrounds - nearest-neighbour 6x review",font=font(12),fill=MUTED)
    for i,(slug,(label,fn)) in enumerate(CURSORS.items()):
        y=header+i*row
        spr=fn()
        d.text((24,y+34),label,font=font(15),fill=TITLE)
        d.text((24,y+58),"24x24  -  " + ("pointer / move" if slug=="movement" else "object interaction"),font=font(10),fill=MUTED)
        d.text((24,y+82),"shared: dark 1px silhouette + ivory pointer notch",font=font(9),fill=(120,132,153,255))
        for x0,bg,title2 in [(290,light,"LIGHT GROUND"),(890,dark,"DARK UI")]:
            canvas.alpha_composite(bg,(x0,y+18))
            d.rectangle((x0,y+18,x0+600,y+18+205),outline=BORDER)
            d.rectangle((x0+8,y+26,x0+150,y+44),fill=(12,14,21,190))
            d.text((x0+14,y+30),title2,font=font(9),fill=(230,235,245,255))
            native=Image.new("RGBA",(44,44),(0,0,0,0)); native.alpha_composite(spr,(10,10))
            canvas.alpha_composite(native,(x0+55,y+105))
            d.text((x0+55,y+155),"native 24px",font=font(9),fill=(235,240,248,255))
            big=scale_nn(spr,6)
            canvas.alpha_composite(big,(x0+190,y+48))
            d.text((x0+190,y+205),"6x nearest",font=font(9),fill=(235,240,248,255))
    canvas.save(PREV/"cursors.png")


# Legendary item preview
# ----------------------------------------------------------------------
def make_legendary_outputs():
    entries=[]
    for slug,name,tag,desc in LEGENDARY:
        fn=LEGENDARY_DRAW[slug]
        base=fn()
        save_sprite(base,SPR/"legendary_items"/(slug+".png"))
        save_large(base,slug)
        entries.append((slug,name,tag,desc,base))
    W=1600; cardw=500; cardh=455; header=110; cols=3
    H=header+2*cardh+30
    canvas=Image.new("RGBA",(W,H),BG_DARK); d=ImageDraw.Draw(canvas)
    d.rectangle((0,0,W,82),fill=(13,15,23,255))
    d.text((25,18),"LEGENDARY ITEM CONCEPTS",font=font(25),fill=TITLE)
    d.text((27,53),"Five rare-chest concepts - native 32x32 icons - nearest-neighbour 8x review",font=font(12),fill=MUTED)
    for i,(slug,name,tag,desc,spr) in enumerate(entries):
        x=20+(i%cols)*cardw; y=header+(i//cols)*cardh
        d.rounded_rectangle((x,y,x+cardw-16,y+cardh-18),radius=7,fill=BG_PANEL,outline=BORDER)
        d.text((x+16,y+14),name,font=font(17),fill=TITLE)
        d.text((x+16,y+38),tag,font=font(10),fill=ACCENT2)
        cb=checker(205,205,12); canvas.alpha_composite(cb,(x+16,y+62))
        big=scale_nn(spr,6); canvas.alpha_composite(big,(x+16+(205-big.width)//2,y+62+(205-big.height)//2))
        d.rectangle((x+16,y+62,x+221,y+267),outline=BORDER)
        # palette based on dominant colors from image
        cols2=[]
        for px in spr.getdata():
            if px[3]>120:
                c=(px[0]//24*24,px[1]//24*24,px[2]//24*24,255)
                if c not in cols2: cols2.append(c)
        px=x+16
        for c in cols2[:8]:
            d.rectangle((px,y+282,px+13,y+295),fill=c,outline=OUTLINE); px+=18
        fnt=font(11); yy=y+308; words=desc.split(); cur=""
        for word in words:
            test=(cur+" "+word).strip()
            if d.textlength(test,font=fnt)<=cardw-50: cur=test
            else:
                d.text((x+16,yy),cur,font=fnt,fill=(195,205,222,255)); yy+=15; cur=word
            if yy>y+cardh-22: break
        if cur and yy<=y+cardh-22: d.text((x+16,yy),cur,font=fnt,fill=(195,205,222,255))
    canvas.save(PREV/"legendary_items.png")
    return entries

# ----------------------------------------------------------------------
# Build everything
# ----------------------------------------------------------------------
def make_reference_sheet():
    from PIL import Image as PILImage
    root=BASE.parent.parent/"SandEEAlpha"
    refs=[]
    def add(name,path,dims,scale=None,crop_frame=False):
        p=root/path
        im=PILImage.open(p).convert("RGBA")
        if crop_frame and im.width>im.height:
            im=im.crop((0,0,im.height,im.height))
        refs.append((name,im,dims))
    add("Sheep south","sprites/mobs/sheep/rotations/south.png","32x32")
    add("Wolf south","sprites/mobs/wolf/32x32_Simple_white_wolf_with_pixelated_art_style_a/rotations/south.png","48x48")
    add("Slime phase 1","sprites/mobs/slimy/slimy_phase1.png","96x96 frame",crop_frame=True)
    add("Pixie","sprites/mobs/pixie/pixie.png","64x64 frame",crop_frame=True)
    add("Hitman","sprites/mobs/hitman/hitman_bottom.png","64x64 frame",crop_frame=True)
    add("Headless fish","sprites/mobs/headless fih/headless_fih.png","49px high frame",crop_frame=True)
    add("World waypoint","sprites/waypoints/world_waypoint_tower_sheet.png","224x224 frame",crop_frame=True)
    W=1600; H=1080
    canvas=Image.new("RGBA",(W,H),BG_DARK); d=ImageDraw.Draw(canvas)
    d.rectangle((0,0,W,94),fill=(13,15,23,255))
    d.text((24,18),"REFERENCE INSPECTION - EXISTING SANDEE ART",font=font(24),fill=TITLE)
    d.text((26,53),"Actual in-project sprites, item icons, environment and waypoint; used before drafting the new concepts",font=font(12),fill=MUTED)
    # cards 4x2
    cw=365; ch=285; ox=30; oy=115
    for i,(name,im,dims) in enumerate(refs[:8]):
        x=ox+(i%4)*cw; y=oy+(i//4)*ch
        d.rounded_rectangle((x,y,x+cw-18,y+ch-18),radius=6,fill=BG_PANEL,outline=BORDER)
        d.text((x+12,y+10),name,font=font(14),fill=TITLE)
        d.text((x+12,y+31),dims,font=font(10),fill=ACCENT)
        cb=checker(cw-40,190,12); canvas.alpha_composite(cb,(x+12,y+50))
        bb=im.getbbox()
        if bb: im=im.crop(bb)
        sc=max(1,min(8,int(min((cw-60)/max(1,im.width),175/max(1,im.height)))))
        disp=scale_nn(im,sc)
        canvas.alpha_composite(disp,(x+12+(cw-40-disp.width)//2,y+50+(190-disp.height)//2))
        d.rectangle((x+12,y+50,x+cw-28,y+240),outline=BORDER)
    # item icon row in fourth card? add separate strip under cards
    item_y=oy+2*ch-4
    d.text((30,item_y),"Existing 32x32 inventory icons (style reference)",font=font(14),fill=TITLE)
    item_names=[("Apple","sprites/items/apple.png"),("Template sword","sprites/items/SandEE_TemplateSword.png"),("Iron hoe","sprites/items/iron_hoe.png"),("Torch","sprites/items/torch_animation.png")]
    iy=item_y+30
    for i,(nm,rel) in enumerate(item_names):
        im=Image.open(root/rel).convert("RGBA")
        if im.width>32 and im.height==32:
            im=im.crop((0,0,32,32))
        cardx=30+i*275
        d.rounded_rectangle((cardx,iy,cardx+250,iy+126),radius=5,fill=BG_PANEL,outline=BORDER)
        d.text((cardx+10,iy+8),nm,font=font(12),fill=TITLE)
        cb=checker(70,70,10); canvas.alpha_composite(cb,(cardx+10,iy+32))
        big=scale_nn(im,3); canvas.alpha_composite(big,(cardx+10+(70-big.width)//2,iy+32+(70-big.height)//2))
        d.text((cardx+92,iy+44),"32x32 native",font=font(10),fill=MUTED)
        d.text((cardx+92,iy+62),"black outline,",font=font(10),fill=MUTED)
        d.text((cardx+92,iy+78),"3-4 tone shape",font=font(10),fill=MUTED)
    # notes columns
    notes=[
        ("SCALE + STYLE","Grid is 32px. Existing mob frame canvases vary: sheep 32x32, wolf 48x48, pixie and Hitman 64x64, slime 96x96. Inventory icons are 32x32. New mob concepts use 32, 48 and 64 size classes with 1px dark outlines, flat limited palettes and restrained highlights."),
        ("DUNGEON IDENTITIES","Lua: near-black violet masonry, pointed arches, gold edging, violet rune light. Python: slate-blue ashlar, brass machinery, teal diamond crystals. The world waypoint uses dark stone and a teal diamond crystal; the Python palette echoes that metal-and-crystal language."),
        ("MISSING REFERENCES","No zombie sprite or zombie scene was found in the project; Gravebell Shambler borrows hostile-humanoid proportions from Hitman and organic palette cues from the worm/fish. No custom cursor asset was found either: only the default OS pointer and CURSOR_POINTING_HAND are used."),
        ("OVERWORLD","The mockups use a crop of the project's actual title-panorama capture (bright grass, simple trees, stone ruins, small sheep) as a representative sandbox; no scene or asset was modified."),
    ]
    ny=item_y+150
    for i,(head,body) in enumerate(notes):
        x=30+(i%2)*780; y=ny+(i//2)*155
        d.rectangle((x,y,x+750,y+138),fill=BG_PANEL2,outline=BORDER)
        d.text((x+14,y+10),head,font=font(12),fill=ACCENT2)
        words=body.split(); cur=""; yy=y+34; fnt=font(11)
        for w in words:
            test=(cur+" "+w).strip()
            if d.textlength(test,font=fnt)<=720: cur=test
            else:
                d.text((x+14,yy),cur,font=fnt,fill=(193,202,218,255)); yy+=16; cur=w
                if yy>y+125: break
        if cur and yy<=y+125: d.text((x+14,yy),cur,font=fnt,fill=(193,202,218,255))
    canvas.save(BASE/"reference"/"existing_style_inspection.png")

def main():
    make_reference_sheet()
    mob_entries=make_mob_outputs()
    by_slug={e["slug"]:e for e in mob_entries}
    # category concept sheets
    friendly=[by_slug["mossback_nib"],by_slug["emberfox_kit"]]
    category_sheet("FRIENDLY MOBS","2 new friendly overworld creatures - isolated transparent sprites and idle-frame concepts",
                   friendly,"friendly_mobs.png",card_scale=5)
    overworld=[by_slug["cinder_ooze"],by_slug["gravebell_shambler"]]
    category_sheet("OVERWORLD ENEMIES","Slime and zombie variants - native gameplay silhouettes and palettes",
                   overworld,"overworld_enemies.png",card_scale=5)
    lua=[by_slug["rune_sentinel"],by_slug["vesper_acolyte"]]
    category_sheet("LUA DUNGEON ENEMIES","Ancient Rune Sanctum hostiles - stone, gold and violet magic",
                   lua,"lua_enemies.png",card_scale=5)
    py=[by_slug["brass_prowler"],by_slug["cipher_warden"]]
    category_sheet("PYTHON DUNGEON ENEMIES","Stonegate Foundry hostiles - blue steel, brass and teal crystal",
                   py,"python_enemies.png",card_scale=5)

    make_bird_outputs()
    bird_entries=[]
    for slug,name,tag,desc,pal,draw_name in BIRDS:
        fn=draw_finch if draw_name=="draw_finch" else draw_kite
        bird_entries.append({"name":name,"tag":tag,"dims":f"native {fn(0,0).width}x{fn(0,0).height}px",
                             "desc":desc,"palette":pal,"sprite":fn(0,0),"frames":[fn(0,0),fn(1,0),fn(0,1),fn(1,1)],
                             "slug":slug,"frame_label":"WING POSES"})
    category_sheet("ATMOSPHERIC BIRDS","Two silhouettes with optional wing poses for a future ambient-flight loop",
                   bird_entries,"birds.png",card_scale=8)

    make_wisp_outputs()
    wisp_entry={"name":WISP[0][1],"tag":WISP[0][2],"dims":"native 32x32px","desc":WISP[0][3],
                "palette":WISP[0][4],"sprite":draw_wisp(0),"frames":[draw_wisp(i) for i in range(4)],
                "slug":"morrow_wisp","frame_label":"FLAME FRAMES"}
    category_sheet("WILL-O'-THE-WISP","A spectral atmospheric light with irregular flame frames",
                   [wisp_entry],"wisp.png",card_scale=8,cols=1)

    make_cursor_outputs()
    make_legendary_outputs()

    # individual overworld mockups
    make_overworld_mockup("FRIENDLY MOBS - OVERWORLD MOCKUP","Mossback Nib and Emberfox Kit at 2- gameplay scale against the actual overworld tiles",
        [{"sprite":by_slug["mossback_nib"]["sprite"],"x":360,"y":485,"scale":2,"label":"Mossback Nib"},
         {"sprite":by_slug["emberfox_kit"]["sprite"],"x":820,"y":500,"scale":2,"label":"Emberfox Kit"}],
        "friendly_mobs_overworld_mockup.png")
    make_overworld_mockup("OVERWORLD ENEMIES - MOCKUP","Cinder Ooze and Gravebell Shambler at 2- gameplay scale",
        [{"sprite":by_slug["cinder_ooze"]["sprite"],"x":420,"y":500,"scale":2,"label":"Cinder Ooze"},
         {"sprite":by_slug["gravebell_shambler"]["sprite"],"x":840,"y":500,"scale":2,"label":"Gravebell Shambler"}],
        "overworld_enemies_mockup.png")
    make_overworld_mockup("ATMOSPHERIC BIRDS - MOCKUP","Sunshard Finch and Dusk Kite at 2- scale with wing variation",
        [{"sprite":draw_finch(0,0),"x":300,"y":255,"scale":2,"shadow":False,"label":"Sunshard Finch"},
         {"sprite":draw_kite(1,0),"x":930,"y":230,"scale":2,"shadow":False,"label":"Dusk Kite"},
         {"sprite":draw_kite(0,1),"x":700,"y":170,"scale":2,"shadow":False},
         {"sprite":draw_finch(1,1),"x":1030,"y":330,"scale":2,"shadow":False}],
        "birds_overworld_mockup.png")

    # individual friendly / overworld enemy assembled previews
    make_overworld_mockup("FRIENDLY MOB - MOSSBACK NIB - OVERWORLD MOCKUP","Singleton assembled preview at 2x gameplay scale against the actual overworld tiles",
        [{"sprite":by_slug["mossback_nib"]["sprite"],"x":640,"y":520,"scale":2,"label":"Mossback Nib"}],
        "friendly_mossback_nib_overworld_mockup.png")
    make_overworld_mockup("FRIENDLY MOB - EMBERFOX KIT - OVERWORLD MOCKUP","Singleton assembled preview at 2x gameplay scale against the actual overworld tiles",
        [{"sprite":by_slug["emberfox_kit"]["sprite"],"x":640,"y":520,"scale":2,"label":"Emberfox Kit"}],
        "friendly_emberfox_kit_overworld_mockup.png")
    make_overworld_mockup("OVERWORLD ENEMY - CINDER OOZE - MOCKUP","Singleton assembled preview at 2x gameplay scale against the actual overworld tiles",
        [{"sprite":by_slug["cinder_ooze"]["sprite"],"x":640,"y":520,"scale":2,"label":"Cinder Ooze"}],
        "overworld_cinder_ooze_mockup.png")
    make_overworld_mockup("OVERWORLD ENEMY - GRAVEBELL SHAMBLER - MOCKUP","Singleton assembled preview at 2x gameplay scale against the actual overworld tiles",
        [{"sprite":by_slug["gravebell_shambler"]["sprite"],"x":640,"y":520,"scale":2,"label":"Gravebell Shambler"}],
        "overworld_gravebell_shambler_mockup.png")

    # individual dungeon mockups
    make_dungeon_mockup("lua","LUA DUNGEON - RUNE SENTINEL","Ancient Rune Sanctum hostiles - 2- room mockup",
        [{"sprite":by_slug["rune_sentinel"]["sprite"],"x":820,"y":540,"scale":2,"label":"Rune Sentinel"}],
        "lua_rune_sentinel_mockup.png")
    make_dungeon_mockup("lua","LUA DUNGEON - VESPER ACOLYTE","Ancient Rune Sanctum hostiles - 2- room mockup",
        [{"sprite":by_slug["vesper_acolyte"]["sprite"],"x":800,"y":560,"scale":2,"label":"Vesper Acolyte"}],
        "lua_vesper_acolyte_mockup.png")
    make_dungeon_mockup("lua","LUA DUNGEON - ENEMY LINEUP","Both Lua hostiles in the same representative room",
        [{"sprite":by_slug["rune_sentinel"]["sprite"],"x":650,"y":560,"scale":2,"label":"Rune Sentinel"},
         {"sprite":by_slug["vesper_acolyte"]["sprite"],"x":940,"y":570,"scale":2,"label":"Vesper Acolyte"}],
        "lua_enemies_mockup.png")
    make_dungeon_mockup("python","PYTHON DUNGEON - BRASS PROWLER","Stonegate Foundry hostiles - 2- room mockup",
        [{"sprite":by_slug["brass_prowler"]["sprite"],"x":820,"y":560,"scale":2,"label":"Brass Prowler"}],
        "python_brass_prowler_mockup.png")
    make_dungeon_mockup("python","PYTHON DUNGEON - CIPHER WARDEN","Stonegate Foundry hostiles - 2- room mockup",
        [{"sprite":by_slug["cipher_warden"]["sprite"],"x":820,"y":560,"scale":2,"label":"Cipher Warden"}],
        "python_cipher_warden_mockup.png")
    make_dungeon_mockup("python","PYTHON DUNGEON - ENEMY LINEUP","Both Python hostiles in the same representative room",
        [{"sprite":by_slug["brass_prowler"]["sprite"],"x":650,"y":570,"scale":2,"label":"Brass Prowler"},
         {"sprite":by_slug["cipher_warden"]["sprite"],"x":940,"y":570,"scale":2,"label":"Cipher Warden"}],
        "python_enemies_mockup.png")

    # wisp dark/light background review
    ref=Image.open(BASE/"reference"/"overworld_game_reference.png").convert("RGBA")
    light_panel=ref.crop((500,0,1140,360)).resize((1280,720),Image.Resampling.NEAREST).crop((0,0,640,720))
    dark_panel=dungeon_room_native("lua").resize((1280,720),Image.Resampling.NEAREST).crop((0,0,640,720))
    wisp=draw_wisp(1)
    canvas=Image.new("RGBA",(1280,720),BG_DARK)
    canvas.alpha_composite(dark_panel,(0,0)); canvas.alpha_composite(light_panel,(640,0))
    big=scale_nn(wisp,5)
    for x0,lab in [(0,"DARK LUA DUNGEON"),(640,"LIGHT OVERWORLD")]:
        d=ImageDraw.Draw(canvas)
        d.rectangle((x0+18,18,x0+260,46),fill=(12,14,21,190))
        d.text((x0+28,24),lab,font=font(12),fill=TITLE)
        canvas.alpha_composite(big,(x0+240,300))
        d.text((x0+329,466),"5x",font=font(10),fill=(225,234,244,255))
    mockup_banner(canvas,"WILL-O'-THE-WISP - BACKGROUND REVIEW","Same sprite against dark masonry and bright overworld terrain - 5x preview")
    canvas.save(PREV/"wisp_backgrounds.png")

if __name__=="__main__":
    main()
