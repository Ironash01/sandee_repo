extends RefCounted
class_name ColorBlock

# ── Color Block factory ─────────────────────────────────────────────
# The Color Crafter produces solid-color blocks. Authoring one sprite per
# possible color is impossible (16.7M of them), so the 32x32 art is GENERATED
# at runtime: a flat fill of the chosen color with the SAME 1px black outline
# every other block in the game uses (see SandEE_itemsprites.png — wood/stone
# are a solid interior with a 1px pure-black border on the outer edge).
#
# Textures AND ItemData are cached by color, so the same color always returns
# the SAME ItemData instance. That reference identity is what lets identical
# color blocks stack: Global.add_item()/remove_item() compare slots by
# `slot["data"] == data` (reference equality for Resources).

const SIZE:    int   = 32
const OUTLINE: Color = Color(0.0, 0.0, 0.0, 1.0)

static var _cache: Dictionary = {}   # "RRGGBB" -> ItemData

# (0,0,0) and (255,255,255) are disallowed (pure black / pure white).
static func is_forbidden(r: int, g: int, b: int) -> bool:
	var rr: int = clampi(r, 0, 255)
	var gg: int = clampi(g, 0, 255)
	var bb: int = clampi(b, 0, 255)
	return (rr == 0 and gg == 0 and bb == 0) or (rr == 255 and gg == 255 and bb == 255)

static func key_for(r: int, g: int, b: int) -> String:
	return "%02X%02X%02X" % [clampi(r, 0, 255), clampi(g, 0, 255), clampi(b, 0, 255)]

static func key_of(c: Color) -> String:
	return key_for(int(round(c.r * 255.0)), int(round(c.g * 255.0)), int(round(c.b * 255.0)))

static func from_key(key: String) -> ItemData:
	if key.length() != 6:
		return null
	return get_block(key.substr(0, 2).hex_to_int(), key.substr(2, 2).hex_to_int(), key.substr(4, 2).hex_to_int())

static func get_block(r: int, g: int, b: int) -> ItemData:
	var key: String = key_for(r, g, b)
	if _cache.has(key):
		return _cache[key] as ItemData
	var col: Color = Color8(clampi(r, 0, 255), clampi(g, 0, 255), clampi(b, 0, 255), 255)
	var tex: ImageTexture = _make_texture(col)
	var rr: int = clampi(r, 0, 255)
	var gg: int = clampi(g, 0, 255)
	var bb: int = clampi(b, 0, 255)
	var d := ItemData.new()
	d.item_name        = "Color Block (%d, %d, %d)" % [rr, gg, bb]
	d.description      = "A block of solid colour (#%s)." % key
	d.item_type        = "block"
	d.icon             = tex
	d.placeable_sprite = tex
	d.is_placeable     = true
	d.block_level      = 5
	d.min_pickaxe_level = 1
	d.place_scene_path = "res://scenes/objects/PlaceableBlock.tscn"
	d.is_color_block   = true
	d.block_color      = col
	_cache[key] = d
	return d

# A flat SIZE x SIZE fill with a 1px black border on all four outer edges.
static func _make_texture(col: Color) -> ImageTexture:
	var img := Image.create_empty(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	img.fill(col)
	for i in range(SIZE):
		img.set_pixel(i, 0, OUTLINE)
		img.set_pixel(i, SIZE - 1, OUTLINE)
		img.set_pixel(0, i, OUTLINE)
		img.set_pixel(SIZE - 1, i, OUTLINE)
	return ImageTexture.create_from_image(img)
