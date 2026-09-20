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
const GRASS_CUT_BURST_SCRIPT: GDScript = preload("res://scripts/grass_cut_burst.gd")
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
# Extra empirical nudge on top of the measured padding above, same idea as
# world.gd's TREE_BASE_EXTRA_OFFSET_PX. world.gd's debug marker
# (_draw_grass_tile_outline) also needs this exact value to compute the same
# ground_anchor point independently — reference GrassTuft.BASE_EXTRA_OFFSET_PX
# there rather than duplicating the number.
const BASE_EXTRA_OFFSET_PX: float = 3.0

# ── Y-sort reference point ───────────────────────────────────────────
# The point used for z_index/Y-sort purposes is deliberately NOT the same
# as ground_anchor above (which is the *visual* base the sprite is pinned
# to, near the tile's bottom edge, for correct grounding). Value found by
# the user directly in the Godot editor: they added a test TileMapLayer with
# grass tiles and used its native "Y Sort Origin" property (a pixel offset
# from a cell's top edge, exactly this same concept) — 15px is what visually
# looked correct there. Re-tune this the same way (test a value live
# in-editor, report the new number) rather than re-deriving it from theory;
# it's a feel/appearance value, not a measured one like BOTTOM_PADDING_PX.
const SORT_ORIGIN_OFFSET_PX: float = 15.0

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

static var _frames:   Array          = []    # Array[ImageTexture], lazily built, shared
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
static var _snowy_frames: Array = []

static func get_grass_frames() -> Array:
	if _frames.is_empty():
		_frames = _build_frame_textures(GRASS_TEX)
	return _frames

static func get_snowy_grass_frames() -> Array:
	if _snowy_frames.is_empty():
		_snowy_frames = _build_frame_textures(SNOWY_GRASS_TEX)
	return _snowy_frames

# Slices a horizontal sheet into FRAME_SIZE frames and bakes the ground shadow
# under each. Shared by the plains and snowy sheets.
static func _build_frame_textures(tex: Texture2D) -> Array:
	var out: Array = []
	var full_img: Image = tex.get_image()
	var shadow: Image   = _get_shadow_overlay_image()
	for i in range(FRAME_COUNT):
		var region := Rect2i(i * FRAME_SIZE, 0, FRAME_SIZE, FRAME_SIZE)
		var frame_img: Image = full_img.get_region(region)
		frame_img.convert(Image.FORMAT_RGBA8)
		if shadow != null:
			var composite := Image.create_empty(FRAME_SIZE, FRAME_SIZE, false, Image.FORMAT_RGBA8)
			# Centered on the frame's visible root line (FRAME_SIZE -
			# BOTTOM_PADDING_PX), the same point setup() anchors to the
			# tile's ground line — keeps the shadow under the roots
			# regardless of how the padding measurement is ever re-tuned.
			var shadow_pos := Vector2i(
				(FRAME_SIZE - shadow.get_width()) / 2,
				int(FRAME_SIZE - BOTTOM_PADDING_PX) - shadow.get_height() / 2
			)
			composite.blend_rect(shadow, Rect2i(Vector2i.ZERO, shadow.get_size()), shadow_pos)
			composite.blend_rect(frame_img, Rect2i(Vector2i.ZERO, Vector2i(FRAME_SIZE, FRAME_SIZE)), Vector2i.ZERO)
			frame_img = composite
		out.append(ImageTexture.create_from_image(frame_img))
	return out

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
# static_z otherwise. static_z is the bucket this tuft sorts at vs
# trees/blocks/other tufts whenever the player is not overlapping it.
var static_z: int = 0

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
	var frames: Array = get_snowy_grass_frames() if snowy else get_grass_frames()
	var h: int = int(tile.x) * 374761393 ^ int(tile.y) * 668265263
	_sprite.texture  = frames[absi(h) % frames.size()] as Texture2D
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
	_sprite.offset = Vector2(0.0, -shift_up)

	global_position = ground_anchor
	# Same quantized-bucket scheme player/trees/placed blocks all use
	# (z_index = int(y / TILE_SIZE)) — but the Y fed into it is the tile's
	# top edge + SORT_ORIGIN_OFFSET_PX, not ground_anchor's own (visual,
	# bottom-edge) Y. ground_anchor = tile_top + TILE_SIZE + BASE_EXTRA_OFFSET_PX
	# (see world.gd's _spawn_grass_at), so back that out to reach tile_top.
	var tile_top_y: float = ground_anchor.y - TILE_SIZE - BASE_EXTRA_OFFSET_PX
	var sort_y:     float = tile_top_y + SORT_ORIGIN_OFFSET_PX
	z_index = int(sort_y / TILE_SIZE)
	static_z = z_index

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
	_sprite.texture  = get_grass_frames()[0] as Texture2D
	_sprite.material = get_grass_material()
	_sprite.scale    = Vector2(FILL_SCALE, FILL_SCALE)
	call_deferred("_finish_placed_block")

func _finish_placed_block() -> void:
	if not is_instance_valid(_sprite):
		return
	var cell := Vector2i(floori(global_position.x / TILE_SIZE), floori(global_position.y / TILE_SIZE))
	var h: int = int(cell.x) * 374761393 ^ int(cell.y) * 668265263
	var snowy: bool = _tile_biome() == 2
	var frames: Array = get_snowy_grass_frames() if snowy else get_grass_frames()
	_sprite.texture = frames[absi(h) % frames.size()] as Texture2D
	_sprite.flip_h  = absi(h >> 8) % 2 == 1
	z_index = int(global_position.y / TILE_SIZE)
	static_z = z_index

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
func cut() -> void:
	# Green blade burst at the tuft (spawned as a sibling so it survives this
	# tuft's free). Snowy tufts burst white-blue to match their snow cover.
	var burst: Node2D = GRASS_CUT_BURST_SCRIPT.new() as Node2D
	if burst != null and get_parent() != null:
		burst.set("snow", _tile_biome() == 2)
		get_parent().add_child(burst)
		burst.global_position = global_position + Vector2(0.0, -12.0)
	# Use the global reference rather than get_parent() to avoid coupling to
	# scene structure — same convention tree.gd uses.
	var world: Node = Global.world_node
	if is_instance_valid(world) and world.has_method("notify_grass_removed"):
		world.call("notify_grass_removed", _tile)
	queue_free()
