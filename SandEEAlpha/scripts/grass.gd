extends Node2D
class_name GrassTuft

# A single grass tuft — everything about how one tuft looks/sizes/anchors
# lives here, separated out of world.gd (which only decides WHICH tiles get
# grass, not how a tuft renders itself). Instantiate via GRASS_SCENE, then
# call setup() once.
#
# Node structure: Node2D root (this script) + child Sprite2D (visual).
# Grass is WALKABLE — no StaticBody2D/CollisionShape2D anymore: the player
# wades through it with the blades covering their lower body (see the
# Walkable y-sort section below and world.gd's _update_grass_sort for how
# the layering works). Does NOT have its own InteractArea/Area2D like
# Tree.tscn does, on purpose — see Cutting below.

# ── Source art ────────────────────────────────────────────────────
const GRASS_TEX:    Texture2D = preload("res://sprites/ground/grass.png")
const GRASS_SHADER: Shader    = preload("res://shaders/grass_sway.gdshader")
const FRAME_COUNT:  int = 6   # grass.png is a 576x96 strip, 6 frames of 96x96
const FRAME_SIZE:   int = 96
# grass.png has real transparent padding below the visible roots within each
# 96px frame — measured directly from the PNG's alpha channel (not eyeballed):
# visible content is y[22..66] out of 0..95, i.e. 29px of empty space below
# the art and 22px above. Re-measure with the same alpha-scan approach if
# this texture is ever replaced.
const BOTTOM_PADDING_PX: float = 29.0

# ── Sizing / anchoring ──────────────────────────────────────────────
# Must match world.gd's own TILE_SIZE — duplicated here (not imported) since
# GDScript consts need a literal to compute FILL_SCALE below at parse time.
const TILE_SIZE: int = 32
# How many tiles wide a single tuft renders — deliberately bigger than its
# own tile so it overflows into neighbors instead of looking like a flat
# 1:1 grid stamp.
const SIZE_TILES:  float = 2.7
const FILL_SCALE:  float = (float(TILE_SIZE) * SIZE_TILES) / float(FRAME_SIZE)
# Measured alpha bounds of one 96x96 grass frame (grass.png / snowy_grass.png):
# visible art x[25..73], y[22..66]. The art's horizontal centre (~50) is NOT the
# frame centre (47.5), so the sprite is nudged sideways to sit exactly on the
# tile's centre line — otherwise each tuft looks shifted against the block grid.
const ART_CENTER_X_PX: float = 50.0
# Extra empirical nudge on top of the measured padding above, same idea as
# world.gd's TREE_BASE_EXTRA_OFFSET_PX. world.gd's debug marker
# (_draw_grass_tile_outline) also needs this exact value to compute the same
# ground_anchor point independently - reference GrassTuft.BASE_EXTRA_OFFSET_PX
# there rather than duplicating the number.
# Now 0: the visible root tips sit exactly on the tile's bottom grid line, the
# same line every block's bottom edge uses (the old +3 px pushed tufts into the
# tile below, which read as misaligned with the block grid).
const BASE_EXTRA_OFFSET_PX: float = 0.0

# ── Cutting ───────────────────────────────────────────────────────────
# Grass is solid (StaticBody2D above) instead of walkable — the player must
# cut it first, and only with a sword equipped. UNLIKE tree.gd's chopping,
# this tuft has NO Area2D/hover logic of its own — with thousands of tufts
# on screen at once, a per-tuft Area2D (even one whose monitoring is toggled
# on/off by proximity) turned into the dominant runtime cost: periodically
# scanning every tuft in the world 10x/second was fine at tree-scale
# (hundreds) but not at grass-scale (many thousands), especially with a
# mobile port in mind. Instead, world.gd drives cutting centrally — same
# O(1) dictionary-lookup pattern the _placed_blocks map already uses for
# placed blocks, no physics monitoring involved at all, and the swing is
# instant (no hold timer) so this tuft just exposes cut() (to remove
# itself). See world.gd's _on_swing_performed / _cut_grass_row.

# One baked 576x96 sheet per biome (6 frames in one texture). Sharing a single
# texture lets the renderer batch all grass tufts instead of splitting them by
# six separate frame textures, while Sprite2D.hframes still gives every tuft
# its original visual variety.
static var _sheet:        Texture2D    = null
static var _snowy_sheet:  Texture2D    = null
# Precomputed average visible colour per frame, keyed by source path. Grass
# cut particles reuse these instead of sampling images at cut time.
static var _sheet_colors: Dictionary = {}
static var _material: ShaderMaterial = null  # lazily built, shared by every instance

# ── Shadow ────────────────────────────────────────────────────────────
# Same round blob shadow the rest of the game uses (player/trees/mobs — see
# Global.make_shadow_sprite's callers), but NOT added as a per-tuft Sprite2D
# child — grass runs at thousands-of-instances scale (this exact file's own
# history is full of per-instance costs that had to be ripped back out, see
# the Cutting section above), so one more node per tuft is real, avoidable
# overhead. Instead it's baked ONCE into each of the 6 shared frame textures
# below — every tuft using that frame gets the shadow for free, at zero
# additional per-instance node/texture/draw-call cost over what already
# existed. Composited BEHIND the blade art (shadow drawn first, blades on
# top) rather than on top, since unlike cave_world.gd's fully-opaque ore
# icons, grass blades have real transparent gaps a background shadow will
# show through naturally.
const SHADOW_TEXTURE_PATH: String = "res://sprites/shadow/shadow_base.png"
static var _shadow_overlay_image: Image = null

# ── Biome sprite sets ──────────────────────────────────────────────
# The snowy biome uses its OWN sheet (snowy_grass.png) instead of shader-tinting
# the green one. Same layout (576x96 = 6 frames of 96x96, same bottom padding),
# so it's built and sliced identically, shadow and all.
const SNOWY_GRASS_TEX: Texture2D = preload("res://sprites/ground/snowy_grass.png")
static func get_grass_sheet() -> Texture2D:
	if _sheet == null:
		_sheet = _build_sheet(GRASS_TEX)
	return _sheet

static func get_snowy_grass_sheet() -> Texture2D:
	if _snowy_sheet == null:
		_snowy_sheet = _build_sheet(SNOWY_GRASS_TEX)
	return _snowy_sheet

# Bakes the ground shadow under all six frames and returns them as one
# horizontal texture sheet. Sprite2D.hframes then selects the frame with zero
# extra texture resources or render batches.
static func _build_sheet(tex: Texture2D) -> Texture2D:
	var full_img: Image = tex.get_image()
	full_img.convert(Image.FORMAT_RGBA8)
	var shadow: Image = _get_shadow_overlay_image()
	var out := Image.create_empty(FRAME_SIZE * FRAME_COUNT, FRAME_SIZE, false, Image.FORMAT_RGBA8)
	var colors: Array[Color] = []
	for i in range(FRAME_COUNT):
		var frame_img: Image = full_img.get_region(Rect2i(i * FRAME_SIZE, 0, FRAME_SIZE, FRAME_SIZE))
		frame_img.convert(Image.FORMAT_RGBA8)
		if shadow != null:
			var composite := Image.create_empty(FRAME_SIZE, FRAME_SIZE, false, Image.FORMAT_RGBA8)
			var shadow_pos := Vector2i(
				(FRAME_SIZE - shadow.get_width()) / 2,
				int(FRAME_SIZE - BOTTOM_PADDING_PX) - shadow.get_height() / 2
			)
			composite.blend_rect(shadow, Rect2i(Vector2i.ZERO, shadow.get_size()), shadow_pos)
			composite.blend_rect(frame_img, Rect2i(Vector2i.ZERO, Vector2i(FRAME_SIZE, FRAME_SIZE)), Vector2i.ZERO)
			frame_img = composite
		out.blit_rect(frame_img, Rect2i(Vector2i.ZERO, Vector2i(FRAME_SIZE, FRAME_SIZE)), Vector2i(i * FRAME_SIZE, 0))
		colors.append(_average_visible_color(frame_img))
	_sheet_colors[tex.resource_path] = colors
	return ImageTexture.create_from_image(out)

static func _average_visible_color(img: Image) -> Color:
	var total := Color(0.0, 0.0, 0.0, 0.0)
	var count := 0
	for y in range(0, img.get_height(), 2):
		for x in range(0, img.get_width(), 2):
			var c := img.get_pixel(x, y)
			if c.a < 0.55:
				continue
			total.r += c.r
			total.g += c.g
			total.b += c.b
			total.a += 1.0
			count += 1
	if count == 0:
		return Color(0.55, 1.0, 0.45, 1.0)
	return Color(total.r / count, total.g / count, total.b / count, 1.0)

static func get_frame_color(frame: int, snowy: bool = false) -> Color:
	var key: String = SNOWY_GRASS_TEX.resource_path if snowy else GRASS_TEX.resource_path
	if not _sheet_colors.has(key):
		get_snowy_grass_sheet() if snowy else get_grass_sheet()
	var colors: Array = _sheet_colors.get(key, []) as Array
	if colors.is_empty():
		return Color(0.70, 0.90, 1.0, 1.0) if snowy else Color(0.55, 1.0, 0.45, 1.0)
	return colors[absi(frame) % colors.size()] as Color

# Built once and cached — scaled down to a flat oval sized for a single
# grass frame (not a full tile, since a tuft's visible root cluster is
# narrower than its 2.7-tile-wide overall sprite) and knocked back in alpha
# so it reads as ground shading rather than a hard black patch.
static func _get_shadow_overlay_image() -> Image:
	if _shadow_overlay_image != null:
		return _shadow_overlay_image
	var tex: Texture2D = load(SHADOW_TEXTURE_PATH) as Texture2D
	if tex == null:
		return null
	var img: Image = tex.get_image()
	img = img.duplicate()
	img.convert(Image.FORMAT_RGBA8)
	img.resize(int(FRAME_SIZE * 0.6), int(FRAME_SIZE * 0.22), Image.INTERPOLATE_BILINEAR)
	for y in range(img.get_height()):
		for x in range(img.get_width()):
			var c: Color = img.get_pixel(x, y)
			c.a *= 0.55
			img.set_pixel(x, y, c)
	_shadow_overlay_image = img
	return _shadow_overlay_image

# Named get_grass_material() (not get_material()) — CanvasItem already
# defines an instance get_material()/set_material() pair as the accessor
# for its "material" property; a static method of the same name but
# different signature crashes with "function signature does not match
# the parent".
static func get_grass_material() -> ShaderMaterial:
	if _material != null:
		return _material
	var mat := ShaderMaterial.new()
	mat.shader = GRASS_SHADER
	_material = mat
	return _material

@onready var _sprite: Sprite2D = $Sprite2D

var _tile: Vector2i = Vector2i.ZERO

# ── Walkable y-sort (driven by world.gd's _update_grass_sort) ─────────
# Grass has NO collision — the player wades through it, blades covering
# their lower body. Instead of a StaticBody2D, the world temporarily
# raises a tuft's z_index above the player's while the player's feet are
# inside this tuft's blade band AND north of its root line, and restores
# static_z otherwise. All grass shares one static bucket (0), which lets the
# renderer batch it; grass is ground foliage and never needs to draw over a
# tree, block or mob. The dynamic raise above the player remains exact.
var static_z: int = 0
# Average colour of this tuft's frame, cached when the grass sheet was built.
var cut_color: Color = Color(0.55, 1.0, 0.45, 1.0)

# World-space Y of the visible root line — the sort reference the world
# compares the player's feet against. World tufts are anchored with their
# origin AT the ground anchor (see _setup_world_tuft); placed grass is
# centered on its tile, so its roots sit half a tile lower.
func root_y() -> float:
	return global_position.y + (TILE_SIZE * 0.5 if item_data != null else 0.0)

# Set on the block-placement path only — lets world.gd's save/load serialize
# a player-placed grass tuft like any other placed block (node.get("item_data")).
# Null for world-gen tufts, which aren't tracked in _placed_blocks at all.
var item_data: ItemData = null

# Called by world.gd right after instantiating this scene and add_child-ing
# it. Two call paths share this entry point:
#   • World-gen fill:   setup(ground_anchor: Vector2, tile: Vector2i)
#   • Block placement:  setup(item_data: ItemData) — from place_block()
#     (world.gd / cave_world.gd), which anchors the node itself at a tile
#     center and runs _fix_sprite_offset() for the standard bottom-center
#     block anchor. The tuft keeps its 6-frame look variety + sway shader,
#     with frame/flip picked from the cell once the caller's position lands.
func setup(ground_anchor: Variant, tile: Vector2i = Vector2i.ZERO) -> void:
	add_to_group("Grass")   # sword-swing hitbox cuts anything in this group
	if ground_anchor is ItemData:
		_setup_placed_block(ground_anchor as ItemData)
		return
	_setup_world_tuft(ground_anchor as Vector2, tile)

func _setup_world_tuft(ground_anchor: Vector2, tile: Vector2i) -> void:
	_tile = tile
	# The snowy biome uses its OWN sprite sheet (snowy_grass.png).
	var snowy: bool = _tile_biome() == 2
	var sheet: Texture2D = get_snowy_grass_sheet() if snowy else get_grass_sheet()
	var h: int = int(tile.x) * 374761393 ^ int(tile.y) * 668265263
	_sprite.texture  = sheet
	_sprite.hframes = FRAME_COUNT
	_sprite.vframes = 1
	_sprite.frame    = absi(h) % FRAME_COUNT
	cut_color        = get_frame_color(_sprite.frame, snowy)
	_sprite.material = get_grass_material()
	_sprite.scale    = Vector2(FILL_SCALE, FILL_SCALE)
	_sprite.flip_h   = absi(h >> 8) % 2 == 1

	# Base-anchored like a tree's trunk, not center-anchored: Sprite2D is
	# centered by default, which put half the tuft's height (the roots)
	# below the tile's actual ground line — nothing visually tied it to the
	# ground, which read as floating. The texture's VISIBLE root tips (not
	# the raw frame edge, which has real transparent padding below the art)
	# need to render at ground_anchor, with blades extending upward from
	# there. Shift is via _sprite.offset (rendered pixels only) so this
	# root's own global_position can stay exactly equal to ground_anchor.
	var shift_up: float = (FRAME_SIZE * 0.5 - BOTTOM_PADDING_PX) * FILL_SCALE
	# Exact grid alignment: the visible art is ~2.5 px right of the frame centre,
	# so nudge it back (mirrored for flipped frames) to sit on the tile's centre
	# line like a block does.
	var side_fix: float = (ART_CENTER_X_PX - FRAME_SIZE * 0.5) * FILL_SCALE
	if _sprite.flip_h:
		side_fix = -side_fix
	_sprite.offset = Vector2(-side_fix, -shift_up)

	global_position = ground_anchor
	# One shared static bucket keeps all grass batchable. world.gd's nearby
	# grass-sort pass raises only tufts that must cover the player.
	z_index = 0
	static_z = 0

# Block-placement path (place_block in world.gd/cave_world.gd). The caller
# anchors this node at the tile center and runs _fix_sprite_offset() for the
# standard bottom-center block anchor, so no world-tuft anchoring happens
# here. The 6-frame look variety + sway shader are kept, with frame/flip
# derived from the cell (deferred until after this frame, once the caller
# has set our position) so placed grass reads the same as world grass and
# stays deterministic per cell.
func _setup_placed_block(data: ItemData) -> void:
	item_data = data
	_tile = Vector2i.ZERO
	_sprite.texture  = get_grass_sheet()
	_sprite.hframes  = FRAME_COUNT
	_sprite.vframes  = 1
	_sprite.frame     = 0
	cut_color         = get_frame_color(0, false)
	_sprite.material = get_grass_material()
	_sprite.scale    = Vector2(FILL_SCALE, FILL_SCALE)
	call_deferred("_finish_placed_block")

func _finish_placed_block() -> void:
	if not is_instance_valid(_sprite):
		return
	var cell := Vector2i(floori(global_position.x / TILE_SIZE), floori(global_position.y / TILE_SIZE))
	var h: int = int(cell.x) * 374761393 ^ int(cell.y) * 668265263
	var snowy: bool = _tile_biome() == 2
	_sprite.texture = get_snowy_grass_sheet() if snowy else get_grass_sheet()
	_sprite.hframes = FRAME_COUNT
	_sprite.vframes = 1
	_sprite.frame    = absi(h) % FRAME_COUNT
	cut_color        = get_frame_color(_sprite.frame, snowy)
	_sprite.flip_h  = absi(h >> 8) % 2 == 1
	# Same horizontal grid fix as world-gen tufts (keep the placement anchor's y).
	var side_fix: float = (ART_CENTER_X_PX - FRAME_SIZE * 0.5) * FILL_SCALE
	if _sprite.flip_h:
		side_fix = -side_fix
	_sprite.offset.x = -side_fix
	z_index = 0
	static_z = 0

# Biome code at this tuft's tile (0=Plain, 1=Desert, 2=Snowy, -1=none/water)
# via the world's own _cell_biome_type, so grass.gd doesn't duplicate the
# atlas-coordinate lookup. Defaults to plain (0) when there is no world or the
# world predates this method.
func _tile_biome() -> int:
	var world: Node = Global.world_node
	if world == null or not world.has_method("_cell_biome_type"):
		return 0
	var tile: Vector2i = _tile
	if tile == Vector2i.ZERO and item_data != null:
		tile = Vector2i(floori(global_position.x / TILE_SIZE), floori(global_position.y / TILE_SIZE))
	return int(world.call("_cell_biome_type", tile))

# ── Cutting surface (driven externally by world.gd) ───────────────────
# The grid tile this tuft is registered under (world-gen tufts know it; placed
# grass derives it from its tile-centered position). Used by tap-to-cut and the
# swing's whole-tile grass test.
func tile_index() -> Vector2i:
	if _tile != Vector2i.ZERO:
		return _tile
	return Vector2i(floori(global_position.x / TILE_SIZE),
		floori((global_position.y - TILE_SIZE * 0.5) / TILE_SIZE))

# World-space rect of the tile this tuft occupies. World-gen tufts are anchored
# on the tile's BOTTOM edge; player-placed ones sit at the tile center.
func tile_rect() -> Rect2:
	var center: Vector2 = global_position - Vector2(0.0, TILE_SIZE * 0.5) \
		if item_data == null else global_position
	return Rect2(center - Vector2(TILE_SIZE, TILE_SIZE) * 0.5,
		Vector2(TILE_SIZE, TILE_SIZE))

# World-space bounds of the VISIBLE art (the measured alpha bounds of the
# frame), excluding the transparent padding. Used so the blades above/sideways
# count as the tuft while the empty ground below it does not.
func visible_rect() -> Rect2:
	if _sprite == null or _sprite.texture == null:
		return Rect2(global_position, Vector2.ZERO)
	var tex_size: Vector2 = _sprite.texture.get_size()
	var frame_size := Vector2(
		tex_size.x / float(maxi(_sprite.hframes, 1)),
		tex_size.y / float(maxi(_sprite.vframes, 1)))
	var sc: Vector2 = _sprite.scale
	# Measured alpha bounds inside one frame (grass.png / snowy_grass.png).
	var art_min := Vector2(25.0, 22.0)
	var art_max := Vector2(73.0, 66.0)
	# Sprite2D draws the texture centred at global_position + offset; `offset`
	# itself is NOT scaled by the sprite scale.
	var center: Vector2 = global_position + _sprite.offset
	var x0: float
	var x1: float
	if _sprite.flip_h:
		x0 = center.x + (frame_size.x - art_max.x - frame_size.x * 0.5) * sc.x
		x1 = center.x + (frame_size.x - art_min.x - frame_size.x * 0.5) * sc.x
	else:
		x0 = center.x + (art_min.x - frame_size.x * 0.5) * sc.x
		x1 = center.x + (art_max.x - frame_size.x * 0.5) * sc.x
	var y0: float = center.y + (art_min.y - frame_size.y * 0.5) * sc.y
	var y1: float = center.y + (art_max.y - frame_size.y * 0.5) * sc.y
	return Rect2(Vector2(minf(x0, x1), y0), Vector2(absf(x1 - x0), y1 - y0))

# The cuttable area: the tuft's whole tile UNION the visible blades. This is
# what tap-to-cut and the sword sweep test against, so clicking the ground
# below the tuft no longer cuts it.
func grass_rect() -> Rect2:
	return tile_rect().merge(visible_rect())

func cut() -> void:
	# The world spawns one shared cut burst per swing; spawning a full
	# GPUParticles2D per tuft caused visible hitching when a sword cut a 3x3
	# grass patch. This method only unregisters and frees the tuft.
	# Use the global reference rather than get_parent() to avoid coupling to
	# scene structure — same convention tree.gd uses.
	var world: Node = Global.world_node
	if is_instance_valid(world) and world.has_method("notify_grass_removed"):
		world.call("notify_grass_removed", _tile)
	queue_free()
