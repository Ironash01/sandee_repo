extends Resource
class_name GeneratedStructure

# A hand-drawn structure sprite made of a joined grid of 32x32 pixel cells.
# Each 32x32 cell is exactly ONE in-game tile (TILE_SIZE = 32), so a
# 64x96 sprite is a 2x3-tile structure and tile_width/tile_height must be
# set manually to match how many cells wide/tall the sprite really is.
# This is what lets the game drop the sprite into the world one tile at a
# time (per-cell AtlasTextures) instead of as one big unwieldy texture.

const TILE_PX: int = 32  # pixels per cell, equal to one in-game tile

# ── Identity ──────────────────────────────────────────────────────
@export var name: String = ""

# ── Sprite ────────────────────────────────────────────────────────
## Joined-grid sprite made of 32x32 cells (each cell = one in-game tile)
@export var sprite: Texture2D

# ── Type ──────────────────────────────────────────────────────────
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
func is_valid() -> bool:
	return sprite != null and tile_width > 0 and tile_height > 0
