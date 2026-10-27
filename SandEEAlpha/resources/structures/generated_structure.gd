extends Resource
class_name GeneratedStructure

# A structure resource used by the overworld/cave/dungeon structure backend.
#
# Sprite-backed structures (decor_kind == "sprite") use a hand-drawn joined
# grid of 32x32 pixel cells. Each cell is exactly ONE in-game tile
# (TILE_SIZE = 32), so a 64x96 sprite is a 2x3-tile structure and
# tile_width/tile_height must be set manually. The game drops the sprite into
# the world one tile at a time (per-cell AtlasTextures).
#
# Procedural templates (decor_kind == "house"/"pillar") have no sprite. They
# describe dimensions and existing block palettes; build_layout(seed) produces
# a deterministic cell map that the overworld structure pass turns into real
# placeable-block nodes.

const TILE_PX: int = 32  # pixels per cell, equal to one in-game tile

# ── Identity ──────────────────────────────────────────────────────
@export var name: String = ""

# ── Sprite ────────────────────────────────────────────────────────
## Joined-grid sprite made of 32x32 cells (each cell = one in-game tile)
@export var sprite: Texture2D

# ── Type / procedural decor definition ────────────────────────────
@export_enum("sprite", "house", "pillar") var decor_kind: String = "sprite"
@export_enum("any", "plain", "desert", "snowy") var biome: String = "any"
@export_range(1, 24) var min_width:  int = 1
@export_range(1, 24) var max_width:  int = 1
@export_range(1, 24) var min_height: int = 1
@export_range(1, 24) var max_height: int = 1
## ItemData resource paths. The builder picks a random valid entry from each
## list, so one template produces several palettes/variants.
@export var wall_blocks:   Array = []
@export var floor_blocks:  Array = []
@export var roof_blocks:   Array = []
@export var accent_blocks: Array = []
## Relative frequency when several templates support the same biome.
@export var decor_weight: float = 1.0

@export_enum("dungeon entrances", "structures", "cave1", "cave2", "cave3", "pixie cave") var type: String = "structures"

# ── Where it spawns ───────────────────────────────────────────────
## Which world this structure is dropped into during generation:
##   overworld — rolled per-chunk at overworld world-gen (chunk priority:
##               dungeon > cave > structures > natural stuff; never on
##               all-ocean chunks)
##   cave / dungeon — reserved for those worlds' own generators
@export_enum("overworld", "cave", "dungeon") var spawn_world: String = "overworld"

# ── Manual tile count ─────────────────────────────────────────────
## How many 32x32 cells the sprite is wide (columns) — set manually so a
## sprite with transparent padding or odd aspect never mis-slices.
@export_range(1, 64) var tile_width:  int = 1
## How many 32x32 cells the sprite is tall (rows)
@export_range(1, 64) var tile_height: int = 1

# ── Walkable opening ──────────────────────────────────────────────────
# Cells (in the sprite grid) that form the structure's entrance opening.
# The spawner anchors the structure so this opening lands on the entry
# portal's tile, and the opening marks the clickable/door area. Structures
# with no opening (e.g. dungeon entrances are fully solid) leave this
# invalid (x < 0).
@export var door_rect: Rect2i = Rect2i(-1, -1, 0, 0)

# ── Optional painted highlight mask ──────────────────────────────────────
# When set, THIS replaces the door_rect highlight: a tiny mask texture of
# exactly tile_width x tile_height pixels (one pixel per structure cell) that
# you paint in any pixel editor / Godot texture editor — each painted
# (non-transparent) pixel marks that cell to be highlighted when the player is
# near the entrance. Lets you hand-pick an arbitrary highlight shape (a blob,
# a path, a doorway arch...) instead of the whole door_rect rectangle. Leave
# null to keep the default door_rect highlight.
@export var highlight_mask: Texture2D = null

var _tile_textures: Dictionary = {}  # Vector2i -> AtlasTexture (cached)

# Total tiles in the structure
func tile_count() -> int:
	return tile_width * tile_height

# Pixel rect of a single cell in the sprite's texture space.
# col/row are 0-based; returns an empty Rect2 if out of bounds.
func get_tile_rect(col: int, row: int) -> Rect2:
	if col < 0 or row < 0 or col >= tile_width or row >= tile_height:
		return Rect2()
	return Rect2(col * TILE_PX, row * TILE_PX, TILE_PX, TILE_PX)

# True when the cell (col/row 0-based) is inside the walkable opening.
func is_door_cell(col: int, row: int) -> bool:
	return door_rect.has_point(Vector2i(col, row))

# Center cell of the walkable opening (the cell the entry portal should sit
# on). Falls back to the structure's center when no door_rect is set.
func door_center_cell() -> Vector2i:
	if door_rect.position.x >= 0:
		return door_rect.position + Vector2i(door_rect.size.x / 2, door_rect.size.y / 2)
	return Vector2i(tile_width / 2, tile_height / 2)

# AtlasTexture for one cell (col/row 0-based). Cached; null if the cell is
# out of bounds or the sprite is missing.
func get_tile_texture(col: int, row: int) -> AtlasTexture:
	if sprite == null:
		return null
	var key := Vector2i(col, row)
	if _tile_textures.has(key):
		return _tile_textures[key] as AtlasTexture
	var rect := get_tile_rect(col, row)
	if rect.size == Vector2.ZERO:
		return null
	var atlas := AtlasTexture.new()
	atlas.atlas  = sprite
	atlas.region = rect
	_tile_textures[key] = atlas
	return atlas

# The sprite is expected to be exactly tile_width x tile_height 32x32 cells.
# Procedural templates intentionally have no sprite; their layout comes from
# build_layout(), which uses the existing placeable block resources.
func is_valid() -> bool:
	if decor_kind == "house":
		return min_width >= 3 and max_width >= min_width \
			and min_height >= 3 and max_height >= min_height \
			and not wall_blocks.is_empty() and not floor_blocks.is_empty() \
			and not roof_blocks.is_empty()
	if decor_kind == "pillar":
		return min_width >= 1 and max_width >= min_width \
			and min_height >= 2 and max_height >= min_height \
			and not wall_blocks.is_empty()
	return sprite != null and tile_width > 0 and tile_height > 0


# Build one deterministic layout for this procedural template. The returned
# dictionary is {"cells": {Vector2i: item_path}, "size": Vector2i}. Coordinates
# are normalized so the top-left of the footprint is (0, 0). Sprite-backed
# resources return an empty dictionary.
func build_layout(seed: int) -> Dictionary:
	if decor_kind != "house" and decor_kind != "pillar":
		return {}
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	if decor_kind == "house":
		return _build_house_layout(rng)
	return _build_pillar_layout(rng)


func _pick_block(blocks: Array, rng: RandomNumberGenerator) -> String:
	var valid: Array[String] = []
	for path_value in blocks:
		var path := str(path_value).strip_edges()
		if not path.is_empty() and ResourceLoader.exists(path):
			valid.append(path)
	if valid.is_empty():
		return ""
	return valid[rng.randi_range(0, valid.size() - 1)]


func _normalized_layout(cells: Dictionary) -> Dictionary:
	if cells.is_empty():
		return {}
	var min_p := Vector2i(1 << 20, 1 << 20)
	var max_p := Vector2i(-(1 << 20), -(1 << 20))
	for cell_value in cells.keys():
		if not (cell_value is Vector2i):
			continue
		var cell := cell_value as Vector2i
		min_p.x = mini(min_p.x, cell.x)
		min_p.y = mini(min_p.y, cell.y)
		max_p.x = maxi(max_p.x, cell.x)
		max_p.y = maxi(max_p.y, cell.y)
	if max_p.x < min_p.x or max_p.y < min_p.y:
		return {}
	var normalized: Dictionary = {}
	for cell_value in cells.keys():
		if cell_value is Vector2i:
			normalized[(cell_value as Vector2i) - min_p] = cells[cell_value]
	return {
		"cells": normalized,
		"size": max_p - min_p + Vector2i.ONE,
	}


func _build_house_layout(rng: RandomNumberGenerator) -> Dictionary:
	var wall := _pick_block(wall_blocks, rng)
	var floor := _pick_block(floor_blocks, rng)
	var roof := _pick_block(roof_blocks, rng)
	var accent := _pick_block(accent_blocks, rng)
	if wall.is_empty() or floor.is_empty() or roof.is_empty():
		return {}
	if accent.is_empty():
		accent = wall
	var w := rng.randi_range(maxi(4, min_width), maxi(maxi(4, min_width), max_width))
	var h := rng.randi_range(maxi(3, min_height), maxi(maxi(3, min_height), max_height))
	var cells: Dictionary = {}

	# Interior floor first; the perimeter layer overwrites its edges where
	# walls sit, except for the central doorway.
	for x in range(1, w - 1):
		for y in range(1, h):
			cells[Vector2i(x, y)] = floor

	# Front wall with a one-tile doorway in the centre. The accent block makes
	# the front boundary read clearly even when the chosen wall and floor
	# palettes are close in value.
	var door_x: int = w / 2
	for x in range(1, w - 1):
		if x != door_x:
			cells[Vector2i(x, h - 1)] = accent
	# Corner posts give the silhouette a readable frame.
	cells[Vector2i(0, h - 1)] = accent
	cells[Vector2i(w - 1, h - 1)] = accent
	cells[Vector2i(0, 1)] = accent
	cells[Vector2i(w - 1, 1)] = accent
	for y in range(1, h - 1):
		cells[Vector2i(0, y)] = wall
		cells[Vector2i(w - 1, y)] = wall
	# Re-apply the upper corner posts after the side-wall loop.
	cells[Vector2i(0, 1)] = accent
	cells[Vector2i(w - 1, 1)] = accent

	# Roof ridge + optional eave. The eave is part of the footprint, so world
	# validation reserves the overhang cells before anything is placed.
	for x in range(w):
		cells[Vector2i(x, 0)] = roof
	var has_eave := rng.randi_range(0, 2) != 0
	if has_eave:
		for x in range(-1, w + 1):
			cells[Vector2i(x, -1)] = roof

	# Some houses get a short chimney for a distinct skyline. It occupies the
	# cell above the roof/eave and is validated as part of the footprint.
	if rng.randi_range(0, 2) != 0:
		var chimney_x := w - 2 if rng.randi_range(0, 1) == 0 else 1
		cells[Vector2i(chimney_x, -2 if has_eave else -1)] = accent

	# Keep the doorway on walkable floor and add a single front-door step.
	cells[Vector2i(door_x, h - 1)] = floor
	cells[Vector2i(door_x, h)] = floor
	return _normalized_layout(cells)


func _build_pillar_layout(rng: RandomNumberGenerator) -> Dictionary:
	var wall := _pick_block(wall_blocks, rng)
	var accent := _pick_block(accent_blocks, rng)
	if wall.is_empty():
		return {}
	if accent.is_empty():
		accent = wall
	# Mostly single columns; occasionally a heavier two-wide pillar.
	var w := maxi(1, min_width)
	if max_width > w and rng.randf() < 0.15:
		w = mini(max_width, w + 1)
	var h := rng.randi_range(maxi(2, min_height), maxi(maxi(2, min_height), max_height))
	var cells: Dictionary = {}
	for x in range(w):
		cells[Vector2i(x, 0)] = accent
		cells[Vector2i(x, h - 1)] = accent
		for y in range(1, h - 1):
			cells[Vector2i(x, y)] = wall
	return _normalized_layout(cells)
