extends Node2D
class_name CaveWorld

# A single cave interior — swapped in for the overworld "World" node by
# game_instance.gd's enter_cave()/exit_cave(). This whole thing, tilemap
# included, is built from CaveGenerator's seeded output at setup() time (no
# .tscn). game_instance keeps visited instances alive off-tree, and the
# snapshot_state()/apply_state() pair persists mined tiles and placed blocks
# across save/load without rebuilding unrelated player or overworld state.
#
# Rendering: one TileMapLayer, real ItemData sprites (stone/ore/cave-floor
# resources authored in resources/items/) instead of the original flat-color
# placeholder squares. Each ItemData's icon is its own AtlasTexture region
# into a shared spritesheet, and those regions do NOT all land on one common
# 32px grid (e.g. cave_floor2's region starts at x=190) — so instead of one
# shared grid atlas source, every item gets its own dedicated
# TileSetAtlasSource sized/margined to its exact icon region (see
# _add_icon_source). Collision lives on the TileSet itself (Godot's native
# per-tile physics) — no per-tile nodes at all, since a 256x256 cave is
# 65,536 tiles, more than grass ever reached, and per-tile nodes were
# already proven to be a severe perf problem at that scale (see project
# memory on the grass system).
#
# Overworld parity: block placement, the debug hitbox overlay, and the
# build-mode grid all now work here too, same rules as world.gd (see each
# section below for what's shared via Global vs. reimplemented for the
# cave's single-TileMapLayer/floor-vs-wall model instead of world.gd's
# separate ground/editable layers). Debug shortcut KEYS (Ctrl+Shift+H/C/T,
# block-mode Ctrl) are detected once, centrally, in Global._input() now —
# see its comment — so this script only implements the toggle_*() methods
# Global dispatches to, not the key-detection itself.

const TILE_SIZE:                int = 32
const PLACEMENT_GUIDE_Z_INDEX:  int = 2000  # matches world.gd's own constant
const PLACE_RADIUS_TILES:       int = 6     # matches world.gd's own constant
const INTERACT_RADIUS_PX:       float       = 64.0
const ITEM_DROP_SCENE:          PackedScene = preload("res://scenes/ui/InventoryItem.tscn")

# Thickness (in tiles) of the solid stone band painted around the generated
# cave grid — matches dungeon_world.gd's SURROUND_BAND_TILES.
const SURROUND_BAND_TILES: int = 128
# Camera bounds extend this many tiles into the surrounding wall band so the
# camera can still centre the player near the outer edge of the generated grid.
# The 128-tile band behind it guarantees this padding never exposes void.
const CAMERA_WALL_PADDING_TILES: int = 20

# Wall/ore tile type -> the ItemData that renders it, drops when mined, and
# supplies block_level/min_pickaxe_level for the mining duration formula
# (same formula placeable_block.gd already uses for placed blocks).
const WALL_ITEM_PATHS: Dictionary = {
	CaveGenerator.Tile.STONE:   "res://resources/items/stone.tres",
	CaveGenerator.Tile.COPPER:  "res://resources/items/copper_ore.tres",
	CaveGenerator.Tile.SILICON: "res://resources/items/silicon_ore.tres",
	CaveGenerator.Tile.IRON:    "res://resources/items/iron_ore.tres",
	CaveGenerator.Tile.DIAMOND: "res://resources/items/diamond_ore.tres",
	CaveGenerator.Tile.DIORITE: "res://resources/items/diorite.tres",
	CaveGenerator.Tile.GRANITE: "res://resources/items/granite.tres",
}

# Floor tiles pick one of these at random (deterministically, by tile
# position — see _floor_variant_index) purely for visual variety. Entries
# whose ItemData has no icon set yet (still true for cave_floor3-5 as of
# writing) are skipped rather than rendered blank.
const FLOOR_ITEM_PATHS: Array = [
	"res://resources/items/cave_floor1.tres",
	"res://resources/items/cave_floor2.tres",
	"res://resources/items/cave_floor3.tres",
	"res://resources/items/cave_floor4.tres",
	"res://resources/items/cave_floor5.tres",
]

static var _shared_tile_set: TileSet = null
static var _wall_cells:  Dictionary = {}  # Tile enum -> {"source": id, "coord": Vector2i}
static var _wall_items:  Dictionary = {}  # Tile enum -> ItemData (mining: drop + block_level/min_pickaxe_level)
static var _floor_cells: Array      = []  # [{"source": id, "coord": Vector2i}, ...]

const CHUNK_BORDER_COLOR: Color = Color(1.0, 0.55, 0.0, 0.9)   # orange, matches world.gd's overlay
const HITBOX_WALL_COLOR:  Color = Color(0.65, 0.45, 0.20, 0.9) # brown — distinct from block/mob colors
const HITBOX_BLOCK_COLOR: Color = Color(0.15, 0.55, 1.0, 0.9)  # matches world.gd's blue

# Same shadow texture the rest of the game uses for entity blob-shadows
# (player/trees/mobs — see Global.make_shadow_sprite's callers). Wall/ore
# tiles have no per-tile node to hang a Sprite2D shadow off of (see file
# header on why — TileSet collision, not nodes, at this scale), so it gets
# baked directly into each wall item's own tile texture instead — see
# _build_wall_tile_image().
const SHADOW_TEXTURE_PATH: String = "res://sprites/shadow/shadow_base.png"

# ── Cave darkness ───────────────────────────────────────────────────────
# A CanvasModulate darkens the whole cave scene uniformly; light only comes
# from light-emitting placeables the player puts down (torches etc.), whose
# PointLight2Ds slot into the cave's WorldEnvironment glow automatically.
# No player-following light — the darkness is ambient and torches matter.
# Both are children of CaveWorld, so they're created/destroyed with it
# automatically (queue_free() on cave exit) — nothing to clean up in
# game_instance.gd's enter_cave()/exit_cave().
const CAVE_AMBIENT_COLOR: Color = Color(0.33, 0.33, 0.40, 1.0)  # dim but visible; ~13% darker than before to push torch use
# Rare single chest in a large cave's open floor pocket. Low chance per cave;
# the cell/content RNG is seeded from the cave seed, so first visits and
# save-game restores agree without storing a second layout.
const RARE_CHEST_CHANCE: float = 0.15
const RARE_CHEST_DATA: ItemData = preload("res://resources/items/rare_dungeon_chest.tres")
const RARE_CHEST_SCENE: PackedScene = preload("res://scenes/objects/ChestBlock.tscn")

var generator: CaveGenerator = null
var overworld_return_position: Vector2 = Vector2.ZERO
# Deterministic layout identity + pristine generated grid used to store only
# the player's changes (mined tiles / placed blocks) in the world save.
var _seed: int = 0
var _base_grid: Array = []
var _rare_chest_cell: Vector2i = Vector2i(-2147483648, -2147483648)
var _rare_chest_spawned: bool = false
var _rare_chest_removed: bool = false

var _tilemap: TileMapLayer = null
var _chunk_border_overlay: Node2D = null
var _show_chunk_borders:   bool   = false
var _hitbox_overlay: Node2D = null
var _show_hitboxes:  bool   = false
var _ambient:        CanvasModulate = null
var _shaq_dark:      bool   = false

func _enter_tree() -> void:
	if not Global.gameplay_input_cancelled.is_connected(_cancel_mining):
		Global.gameplay_input_cancelled.connect(_cancel_mining)

func _exit_tree() -> void:
	if Global.gameplay_input_cancelled.is_connected(_cancel_mining):
		Global.gameplay_input_cancelled.disconnect(_cancel_mining)

func setup(seed_value: int, return_position: Vector2) -> void:
	overworld_return_position = return_position
	_seed = seed_value
	generator = CaveGenerator.new()
	generator.generate(seed_value)
	_base_grid = generator.grid.duplicate(true)

	_tilemap = TileMapLayer.new()
	_tilemap.name     = "CaveTiles"
	_tilemap.tile_set = _get_shared_tile_set()
	# Same convention world.gd uses for the overworld's ground/water layers
	# (z_index = -300 there too) — the player/portals use a small quantized
	# int(y / TILE_SIZE) bucket for Y-sort, which goes NEGATIVE once they're
	# north of the cave's center (the grid is centered on the origin, so
	# most of a 128-256 tile cave sits at negative Y). Without this, the
	# tilemap's default z_index of 0 sat ABOVE that negative bucket range,
	# so the player rendered behind cave walls/ore past exactly that point.
	_tilemap.z_index = -300
	add_child(_tilemap)

	_paint_tiles()
	_spawn_rare_chest()
	_spawn_exit_marker()
	_setup_chunk_border_overlay()
	_setup_hitbox_overlay()
	_setup_ghost()
	_setup_grid_overlay()
	_setup_cursor_highlight()
	_setup_darkness()

func _process(delta: float) -> void:
	_update_mining(delta)
	_update_ghost()
	_update_cursor_highlight()
	_update_hover()
	# The build-mode grid follows the player — redraw every frame while it's
	# visible so it tracks movement (the toggle handler alone leaves it frozen
	# at the position build mode was enabled).
	if _grid_overlay != null and _grid_overlay.visible:
		_grid_overlay.queue_redraw()

func _input(event: InputEvent) -> void:
	if Global.is_mouse_event_over_ui(event):
		return
	if Global.any_ui_open() or Global.pause_menu_open:
		return
	if Global.block_mode:
		if event.is_action_pressed("mouse_left"):
			place_block()
		return
	# Left-click (hold): mining — needs press AND release, so this checks the
	# raw mouse event rather than just is_action_pressed().
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_try_start_mining()
		elif not Global.pnc_hold_active:
			# Keep the synthetic tap-to-control hold alive after finger-up.
			_cancel_mining()

# ── Mining (stone/ore walls) ────────────────────────────────────────────
# Centralized here rather than a per-tile node/Area2D, same reasoning as
# world.gd's grass cutting — tile-grid scale, not sprite-instance scale.
# Pickaxe-gated exactly like placeable_block.gd's block breaking: duration
# = block_level - pickaxe_level (min 0.1s), requires min_pickaxe_level.
var _mine_tile:     Vector2i = Vector2i.ZERO
var _mining:        bool     = false
var _mine_elapsed:  float    = 0.0
var _mine_duration: float    = 1.0
# Global tap-to-break: a fresh click is worth this much break work (same value
# placed_block.gd uses), so tapping repeatedly chips a wall down instead of
# requiring one long hold. Progress persists across clicks on the SAME tile
# and resets when the target tile changes.
const CLICK_BREAK_SECONDS: float = 0.5
# A wobbling Sprite2D copy of the mined wall tile. Tiles have no per-tile node
# to rotate (unlike the overworld's PlaceableBlock), so mining hides the real
# tile and shakes this overlay — giving cave mining the same wobble the
# overworld has, from the shared Global.block_wobble_rotation().
var _mine_overlay: Sprite2D = null
# Temporary solid body that preserves the mined tile's collision while the
# real TileMap cell is hidden under the wobble overlay. Without it the player
# could walk through an intact wall mid-mine.
var _mine_blocker: StaticBody2D = null

func _try_start_mining() -> void:
	var mouse_cell: Vector2i = _mouse_cell()
	var grid_pos: Vector2i   = _cell_to_grid(mouse_cell)
	if not _grid_in_bounds(grid_pos):
		return
	var tile_type: int = generator.grid[grid_pos.x][grid_pos.y]
	if tile_type == CaveGenerator.Tile.FLOOR:
		return  # nothing to mine
	var item: ItemData = _wall_items.get(tile_type)
	if item == null:
		return
	var player: Node2D = Global.player_node as Node2D
	if player == null:
		return
	var tile_world: Vector2 = _tilemap.to_global(_tilemap.map_to_local(mouse_cell))
	if player.global_position.distance_to(tile_world) > INTERACT_RADIUS_PX:
		return
	var pick_lvl: int = _get_held_pickaxe_level()
	if pick_lvl < 0 or pick_lvl < item.min_pickaxe_level:
		return
	# The swing plays for ANY item use — mining consumes the click (below), so
	# route the swing through the player explicitly or the player's own _input
	# may never see it (input-order dependent).
	if Global.player_node != null and Global.player_node.has_method("swing_held_item"):
		Global.player_node.call("swing_held_item")
	get_viewport().set_input_as_handled()
	if _mine_tile != mouse_cell:
		_mine_elapsed = 0.0   # new target — drop any progress from the old tile
		_destroy_mine_overlay(true)
	_mine_tile     = mouse_cell
	_mine_duration = maxf(0.1, float(item.block_level - pick_lvl))
	_mining        = true
	if not is_instance_valid(_mine_overlay):
		_spawn_mine_overlay(item, mouse_cell)
	# A fresh click is worth CLICK_BREAK_SECONDS of work (tap-to-break).
	_mine_elapsed  = minf(_mine_elapsed + CLICK_BREAK_SECONDS, _mine_duration)
	queue_redraw()
	if _mine_elapsed >= _mine_duration:
		_finish_break()

func _cancel_mining() -> void:
	if not _mining:
		return
	_mining = false
	Global.clear_break_progress(self)
	# Progress is deliberately KEPT so the next tap on this tile continues —
	# it is reset only when the target tile changes (see _try_start_mining).
	# The real tile comes back (the wobble overlay goes away).
	_destroy_mine_overlay(true)
	queue_redraw()

# Mine complete: drop the overlay WITHOUT restoring the tile (it becomes floor).
func _finish_break() -> void:
	_mining = false
	Global.clear_break_progress(self)
	_destroy_mine_overlay(false)
	_break_tile(_mine_tile)
	_mine_elapsed = 0.0
	queue_redraw()

func _spawn_mine_overlay(item: ItemData, cell: Vector2i) -> void:
	if item == null:
		return
	var tex: Texture2D = item.placeable_sprite if item.placeable_sprite != null else item.icon
	if tex == null:
		return
	var spr := Sprite2D.new()
	spr.texture        = tex
	spr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	# Above the TileMapLayer (-300) but below world sprites/the player — a wall.
	spr.z_index = _tilemap.z_index + 1
	add_child(spr)
	spr.global_position = _tilemap.to_global(_tilemap.map_to_local(cell))
	_mine_overlay = spr
	# Hide the real tile so the rotated overlay can't double-image against it,
	# but keep the tile solid with a temporary blocker until the break succeeds
	# (or the mine is cancelled and the tile is restored).
	_make_mine_blocker(cell)
	_tilemap.set_cell(cell, -1)


func _make_mine_blocker(cell: Vector2i) -> void:
	_destroy_mine_blocker()
	var body := StaticBody2D.new()
	body.collision_layer = 1
	body.collision_mask  = 0
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(TILE_SIZE, TILE_SIZE)
	shape.shape = rect
	body.add_child(shape)
	add_child(body)
	body.global_position = _tilemap.to_global(_tilemap.map_to_local(cell))
	_mine_blocker = body


func _destroy_mine_blocker() -> void:
	if is_instance_valid(_mine_blocker):
		_mine_blocker.queue_free()
	_mine_blocker = null

# restore=true repaints the real wall tile (cancel); false leaves it hidden
# (the caller is about to paint FLOOR over it).
func _destroy_mine_overlay(restore: bool) -> void:
	_destroy_mine_blocker()
	if restore:
		var gp: Vector2i = _cell_to_grid(_mine_tile)
		if _grid_in_bounds(gp):
			_paint_cell(_mine_tile, generator.grid[gp.x][gp.y], gp)
	if is_instance_valid(_mine_overlay):
		_mine_overlay.queue_free()
	_mine_overlay = null

func _update_mining(delta: float) -> void:
	if not _mining:
		return
	var still_valid: bool = _mouse_cell() == _mine_tile \
		and Global.is_left_action_held() \
		and not Global.any_ui_open() and not Global.pause_menu_open
	if not still_valid:
		_cancel_mining()
		return
	# Continuous manual/PNC mining keeps swinging the held pickaxe; the player
	# ignores this while the previous swing is still playing.
	Global.swing_player_item()
	_mine_elapsed = minf(_mine_elapsed + delta, _mine_duration)
	var progress: float = _mine_elapsed / _mine_duration if _mine_duration > 0.0 else 1.0
	var tile_world: Vector2 = _tilemap.to_global(_tilemap.map_to_local(_mine_tile))
	Global.report_break_progress(progress, tile_world, -26.0, self)
	# Same shake the overworld's placed blocks use.
	if is_instance_valid(_mine_overlay):
		_mine_overlay.rotation = Global.block_wobble_rotation()
	queue_redraw()
	if _mine_elapsed >= _mine_duration:
		_finish_break()

# No visual feedback at all while mining (no progress bar) was the actual
# bug behind "can't break blocks" reports — mining requires holding the
# mouse down for block_level - pickaxe_level seconds (4s+ for stone with a
# wooden pickaxe), and with zero on-screen indication a normal click (or
# even a few seconds of holding without realizing more is needed) looks
# indistinguishable from mining being completely broken. CaveWorld spans the
# whole map, so its progress is reported with the mined tile position
# to the shared BreakProgressOverlay.
func _draw() -> void:
	# Ring is drawn by BreakProgressOverlay above the world.
	pass

func _break_tile(cell: Vector2i) -> void:
	var grid_pos: Vector2i = _cell_to_grid(cell)
	if not _grid_in_bounds(grid_pos):
		return
	var tile_type: int = generator.grid[grid_pos.x][grid_pos.y]
	var item: ItemData = _wall_items.get(tile_type)
	generator.grid[grid_pos.x][grid_pos.y] = CaveGenerator.Tile.FLOOR
	_paint_cell(cell, CaveGenerator.Tile.FLOOR, grid_pos)
	# A wall that supported an adjacent torch is gone: re-evaluate its mount.
	_refresh_neighbor_u_collision(cell)
	if item == null:
		return
	Global.track_mining(item)
	CrashLogger.event("WORLD", "mine cave %s cell=(%d, %d)" % [
		item.item_name, cell.x, cell.y])
	var drop: Node = ITEM_DROP_SCENE.instantiate()
	drop.call("set_item_data", item)
	add_child(drop)
	var offset := Vector2(randf_range(-8, 8), randf_range(-8, 8))
	drop.global_position = _tilemap.to_global(_tilemap.map_to_local(cell)) + offset

# The held PICKAXE's mining tier, or -1 when none is in hand. Delegates to
# Global so every break path shares one definition (see Global.held_pickaxe_level).
func _get_held_pickaxe_level() -> int:
	return Global.held_pickaxe_level()

func _mouse_cell() -> Vector2i:
	return _tilemap.local_to_map(_tilemap.to_local(Global.mouse_world(self)))

func _grid_in_bounds(grid_pos: Vector2i) -> bool:
	return grid_pos.x >= 0 and grid_pos.y >= 0 and grid_pos.x < generator.size and grid_pos.y < generator.size

func _cell_is_wall(cell: Vector2i) -> bool:
	var grid_pos: Vector2i = _cell_to_grid(cell)
	if not _grid_in_bounds(grid_pos):
		return true  # off the generated map entirely — treat as solid
	return generator.grid[grid_pos.x][grid_pos.y] != CaveGenerator.Tile.FLOOR

# ── Block placement — same rules as world.gd's place_block()/ghost/grid,
# adapted for one TileMapLayer (floor vs. wall) instead of separate
# ground/editable layers. No water or tree checks (caves have neither);
# "already painted" becomes "is a wall/ore tile" (_cell_is_wall). ─────────
var _placed_blocks: Dictionary = {}  # cell -> {"node": Node, "name": String}
var ghost:           Node2D   = null
var ghost_sprite:    Sprite2D = null
var ghost_last_type: String   = ""
var _grid_overlay: Node2D = null
var _cursor_highlight: Node2D = null

func _setup_ghost() -> void:
	ghost = Node2D.new()
	ghost.visible = false
	ghost.z_index = PLACEMENT_GUIDE_Z_INDEX
	add_child(ghost)
	ghost_sprite = Sprite2D.new()
	ghost_sprite.modulate = Color(1, 1, 1, 0.5)
	ghost.add_child(ghost_sprite)

func _is_placeable_item(item) -> bool:
	if item == null or not (item is Dictionary) or not item.has("data"):
		return false
	return (item["data"] as ItemData).is_placeable

func _update_ghost() -> void:
	if not Global.block_mode:
		ghost.visible = false
		return
	var item = Global.get_hotbar_item()
	if not _is_placeable_item(item):
		ghost.visible = false
		return
	var item_key: String = (item["data"] as ItemData).item_name
	if item_key != ghost_last_type:
		ghost_last_type = item_key
		_rebuild_ghost_sprite(item)
	var mouse_local: Vector2 = _tilemap.to_local(Global.mouse_world(self))
	var cell:        Vector2i = _tilemap.local_to_map(mouse_local)
	# _tilemap and ghost are both direct children of CaveWorld with no
	# relative offset, so _tilemap's local space IS CaveWorld's local space
	# — same implicit assumption world.gd's own place_block()/ghost code
	# relies on for editable_layer.
	ghost.position = _tilemap.map_to_local(cell)
	if not _is_cell_in_place_radius(cell):
		ghost.visible = false
		return
	ghost.visible = true
	var occupied:    bool = _placed_blocks.has(cell) or _cell_is_wall(cell)
	var player_here: bool = _cell_blocked_by_player(cell)
	ghost_sprite.modulate = Color(1.0, 0.3, 0.3, 0.5) if (occupied or player_here) \
		else Color(1.0, 1.0, 1.0, 0.5)

func _rebuild_ghost_sprite(item: Dictionary) -> void:
	var data: ItemData = item["data"] as ItemData
	var tex: Texture2D = data.placeable_sprite if data.placeable_sprite != null else data.icon
	ghost_sprite.texture  = tex
	ghost_sprite.hframes  = 1
	ghost_sprite.vframes  = 1
	ghost_sprite.frame    = 0
	ghost_sprite.position = Vector2.ZERO

func place_block() -> void:
	# A DEAD player must not place blocks (see world.gd:place_block()).
	if Global.player_is_dead:
		return
	var item = Global.get_hotbar_item()
	if not _is_placeable_item(item):
		return
	var cell: Vector2i = _tilemap.local_to_map(_tilemap.to_local(Global.mouse_world(self)))
	if not _is_cell_in_place_radius(cell):
		return
	if _cell_blocked_by_player(cell):
		return
	if _placed_blocks.has(cell) or _cell_is_wall(cell):
		return
	var item_data: ItemData = item["data"] as ItemData
	if item_data == null or item_data.place_scene_path == "":
		return
	if not ResourceLoader.exists(item_data.place_scene_path):
		return
	var obj_scene: PackedScene = load(item_data.place_scene_path)
	if obj_scene == null:
		return
	var obj: Node = obj_scene.instantiate()
	if obj == null:
		return
	if obj.has_method("setup"):
		obj.call("setup", item_data)
	_placed_blocks[cell] = {"node": obj, "name": item_data.item_name}
	if obj.has_method("set_world_cell"):
		obj.call("set_world_cell", cell, self)
	add_child(obj)
	if not is_instance_valid(obj):
		_placed_blocks.erase(cell)
		return
	var world_pos: Vector2 = _tilemap.map_to_local(cell)
	obj.position = world_pos
	obj.z_index  = int(world_pos.y / TILE_SIZE)
	_fix_sprite_offset(obj)
	_refresh_neighbor_u_collision(cell)
	if item_data.has_place_animation and item_data.place_animation_name != "":
		var ap: AnimationPlayer = obj.get_node_or_null("AnimationPlayer") as AnimationPlayer
		if ap != null:
			ap.play(item_data.place_animation_name)
	Global.remove_item(item_data)
	Global.record_block_placed(item_data)

func unregister_block(cell: Vector2i) -> void:
	if cell == _rare_chest_cell:
		_rare_chest_removed = true
		_rare_chest_spawned = false
	_placed_blocks.erase(cell)
	_refresh_neighbor_u_collision(cell)

# True when a player-placed block occupies this cell (PlaceableBlock's
# U-collider toggle checks vertical neighbours via this).
func has_placed_block(cell: Vector2i) -> bool:
	return _placed_blocks.has(cell)

# A torch mounts to a solid neighbour: a placed block OR a solid cave wall.
# Cave rock is TileMapLayer cells, NOT placed blocks, so without this a torch
# placed against a wall never used its connected sprite (unlike the overworld,
# where world-gen stone/charcoal live in _placed_blocks). A placed FLOOR is
# walkable decor, not a wall, so it never counts as support.
func torch_support(cell: Vector2i) -> bool:
	if not _grid_in_bounds(_cell_to_grid(cell)):
		return false   # off-map is not a visible wall to mount a torch on
	if _cell_is_wall(cell):
		return true
	var e: Variant = _placed_blocks.get(cell)
	if e == null:
		return false
	var n: Variant = (e as Dictionary).get("node")
	if not is_instance_valid(n):
		return false
	var d = n.get("item_data")
	return d != null and not d.is_floor and not d.is_torch

# Not the overworld — a Bonfire here must not set the respawn point.
func is_overworld() -> bool:
	return false

# Re-evaluate the U-collider of `cell` plus its 8 neighbours so a vertical
# column (above/below) or a diagonal pair gains/loses its side walls when a
# block appears/disappears.
func _refresh_neighbor_u_collision(cell: Vector2i) -> void:
	for off in [Vector2i.ZERO, Vector2i(0, -1), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(1, 0),
			Vector2i(-1, -1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(1, 1)]:
		var c: Vector2i = cell + (off as Vector2i)
		if not _placed_blocks.has(c):
			continue
		var n: Variant = (_placed_blocks[c] as Dictionary).get("node")
		if is_instance_valid(n) and n.has_method("refresh_u_collision"):
			n.call("refresh_u_collision")
		if is_instance_valid(n) and n.has_method("refresh_torch_connection"):
			n.call("refresh_torch_connection")

func _is_cell_in_place_radius(cell: Vector2i) -> bool:
	var player: Node2D = Global.player_node as Node2D
	if player == null:
		return true
	var cell_local:   Vector2 = _tilemap.map_to_local(cell)
	var player_local: Vector2 = _tilemap.to_local(player.global_position)
	return player_local.distance_to(cell_local) <= PLACE_RADIUS_TILES * TILE_SIZE

func _cell_blocked_by_player(cell: Vector2i) -> bool:
	var player: Node2D = Global.player_node as Node2D
	if player == null:
		return false
	# Same waist-high player-footprint dims world.gd's own
	# _cell_blocked_by_player uses (PlayerCol: 20x12 at y 17) — keep in sync.
	const S: float = 0.980
	var half_w: float = 10.0 * S + 8.0
	var half_h: float = 6.0 * S + 8.0
	var player_local: Vector2 = _tilemap.to_local(player.global_position) + Vector2(0.0, 17.0 * S)
	var tl: Vector2i = _tilemap.local_to_map(player_local + Vector2(-half_w, -half_h))
	var br: Vector2i = _tilemap.local_to_map(player_local + Vector2( half_w,  half_h))
	return cell.x >= mini(tl.x, br.x) and cell.x <= maxi(tl.x, br.x) \
		and cell.y >= mini(tl.y, br.y) and cell.y <= maxi(tl.y, br.y)

func _fix_sprite_offset(obj: Node) -> void:
	var sprite: Node = obj.get_node_or_null("Sprite2D")
	if sprite == null:
		sprite = obj.get_node_or_null("AnimatedSprite2D")
	if sprite == null:
		return
	var frame_height := 0.0
	if sprite is Sprite2D and (sprite as Sprite2D).texture != null:
		frame_height = (sprite as Sprite2D).texture.get_height() / max((sprite as Sprite2D).vframes, 1)
	elif sprite is AnimatedSprite2D and (sprite as AnimatedSprite2D).sprite_frames != null:
		var frames: SpriteFrames = (sprite as AnimatedSprite2D).sprite_frames
		var anim: StringName     = (sprite as AnimatedSprite2D).animation
		if frames.has_animation(anim) and frames.get_frame_count(anim) > 0:
			var tex: Texture2D = frames.get_frame_texture(anim, 0)
			if tex != null:
				frame_height = tex.get_height()
	if frame_height > 0.0:
		sprite.position = Vector2(0.0, (TILE_SIZE / 2.0) - (frame_height / 2.0))

func _setup_grid_overlay() -> void:
	_grid_overlay = Node2D.new()
	_grid_overlay.z_index = PLACEMENT_GUIDE_Z_INDEX
	_grid_overlay.visible = false
	add_child(_grid_overlay)
	_grid_overlay.draw.connect(_on_grid_draw)
	Global.block_mode_changed.connect(func(enabled: bool) -> void:
		_grid_overlay.visible = enabled
		if enabled:
			_grid_overlay.queue_redraw()
	)

func _on_grid_draw() -> void:
	var player: Node2D = Global.player_node as Node2D
	if player == null:
		return
	var player_cell: Vector2i = _tilemap.local_to_map(_tilemap.to_local(player.global_position))
	var half: float = TILE_SIZE * 0.5
	for dx in range(-PLACE_RADIUS_TILES, PLACE_RADIUS_TILES + 1):
		for dy in range(-PLACE_RADIUS_TILES, PLACE_RADIUS_TILES + 1):
			var cell: Vector2i = player_cell + Vector2i(dx, dy)
			if not _is_cell_in_place_radius(cell):
				continue
			if _placed_blocks.has(cell) or _cell_is_wall(cell):
				continue
			var cp: Vector2 = _tilemap.map_to_local(cell)
			var rect := Rect2(cp.x - half, cp.y - half, TILE_SIZE, TILE_SIZE)
			var color: Color = Color(1.0, 0.2, 0.2, 0.55) if _cell_blocked_by_player(cell) \
				else Color(1.0, 1.0, 1.0, 0.45)
			_grid_overlay.draw_rect(rect, color, false, 1.0)

func _setup_cursor_highlight() -> void:
	_cursor_highlight = Node2D.new()
	_cursor_highlight.z_index = PLACEMENT_GUIDE_Z_INDEX
	_cursor_highlight.visible = false
	_cursor_highlight.draw.connect(func() -> void:
		var half: float = TILE_SIZE * 0.5
		_cursor_highlight.draw_rect(
			Rect2(-half, -half, TILE_SIZE, TILE_SIZE),
			Color(1.0, 1.0, 1.0, 0.28), true)
	)
	add_child(_cursor_highlight)
	_cursor_highlight.queue_redraw()

func _update_cursor_highlight() -> void:
	if _cursor_highlight == null or Global.block_mode:
		if _cursor_highlight != null:
			_cursor_highlight.visible = false
		return
	var mouse_local: Vector2 = _tilemap.to_local(Global.mouse_world(self))
	var cell:        Vector2i = _tilemap.local_to_map(mouse_local)
	_cursor_highlight.position = _tilemap.map_to_local(cell)
	_cursor_highlight.queue_redraw()
	_cursor_highlight.visible = true

func _update_hover() -> void:
	if Global.block_mode:
		Global.set_hover("")
		return
	var mouse_pos: Vector2 = Global.mouse_world(self)
	var best_name: String  = ""
	var best_name_dist: float = INTERACT_RADIUS_PX
	for entry in _placed_blocks.values():
		var node_ref: Variant = (entry as Dictionary)["node"]
		if not is_instance_valid(node_ref):
			continue
		var node: Node2D = node_ref as Node2D
		if node == null:
			continue
		var name_dist: float = mouse_pos.distance_to(node.global_position)
		if name_dist < best_name_dist:
			best_name_dist = name_dist
			best_name = (entry as Dictionary)["name"]
	Global.set_hover(best_name)

# ── Chunk border debug overlay — mirrors world.gd's own, same chunk-grid
# concept (CaveGenerator.CHUNK_SIZE = 20 instead of the overworld's 25) ────
func _setup_chunk_border_overlay() -> void:
	_chunk_border_overlay = Node2D.new()
	_chunk_border_overlay.z_index = PLACEMENT_GUIDE_Z_INDEX
	_chunk_border_overlay.visible = false
	add_child(_chunk_border_overlay)
	_chunk_border_overlay.draw.connect(_on_chunk_border_draw)

func toggle_chunk_borders() -> void:
	_show_chunk_borders = not _show_chunk_borders
	_chunk_border_overlay.visible = _show_chunk_borders
	if _show_chunk_borders:
		_chunk_border_overlay.queue_redraw()

func _on_chunk_border_draw() -> void:
	for cx in range(generator.chunk_cols):
		for cy in range(generator.chunk_rows):
			var r: Rect2 = _chunk_world_rect(Vector2i(cx, cy))
			var local_rect := Rect2(_chunk_border_overlay.to_local(r.position), r.size)
			_chunk_border_overlay.draw_rect(local_rect, CHUNK_BORDER_COLOR, false, 2.0)

func _chunk_world_rect(chunk: Vector2i) -> Rect2:
	var tile_tl: Vector2i = _grid_to_cell(Vector2i(chunk.x * CaveGenerator.CHUNK_SIZE, chunk.y * CaveGenerator.CHUNK_SIZE))
	var world_tl: Vector2 = _tilemap.to_global(_tilemap.map_to_local(tile_tl)) - Vector2(TILE_SIZE, TILE_SIZE) * 0.5
	# Last row/col of chunks is smaller than CHUNK_SIZE whenever `size`
	# isn't an exact multiple of it (e.g. 128 / 20 = 6.4 -> 7 chunks, last
	# one narrower) — clamp so the border rect doesn't overshoot the map edge.
	var chunk_w: int = mini(CaveGenerator.CHUNK_SIZE, generator.size - chunk.x * CaveGenerator.CHUNK_SIZE)
	var chunk_h: int = mini(CaveGenerator.CHUNK_SIZE, generator.size - chunk.y * CaveGenerator.CHUNK_SIZE)
	var size_px: Vector2 = Vector2(chunk_w, chunk_h) * TILE_SIZE
	return Rect2(world_tl, size_px)

# ── Hitbox debug overlay — wall/ore tile outlines (no per-tile nodes to
# walk, unlike world.gd's node-tree approach, since collision lives on the
# TileSet — see file header) plus cave-placed-block hitboxes via the same
# Global.draw_body_hitboxes() helper world.gd now also uses. ───────────────
func _setup_hitbox_overlay() -> void:
	_hitbox_overlay = Node2D.new()
	_hitbox_overlay.z_index = PLACEMENT_GUIDE_Z_INDEX + 100
	_hitbox_overlay.visible = false
	add_child(_hitbox_overlay)
	_hitbox_overlay.draw.connect(_on_hitbox_draw)

func toggle_hitboxes() -> void:
	_show_hitboxes = not _show_hitboxes
	_hitbox_overlay.visible = _show_hitboxes
	if _show_hitboxes:
		_hitbox_overlay.queue_redraw()

func _debug_visible_world_rect() -> Rect2:
	var cam: Camera2D = get_viewport().get_camera_2d()
	if cam == null:
		return Rect2(Vector2(-1e6, -1e6), Vector2(2e6, 2e6))
	var margin: float = TILE_SIZE * 4.0
	var visible_size: Vector2 = get_viewport().get_visible_rect().size / cam.zoom
	var half: Vector2 = visible_size * 0.5 + Vector2(margin, margin)
	var center: Vector2 = cam.get_screen_center_position()
	return Rect2(center - half, half * 2.0)

func _on_hitbox_draw() -> void:
	var view_rect: Rect2 = _debug_visible_world_rect()

	var tl_grid: Vector2i = _cell_to_grid(_tilemap.local_to_map(_tilemap.to_local(view_rect.position)))
	var br_grid: Vector2i = _cell_to_grid(_tilemap.local_to_map(_tilemap.to_local(view_rect.position + view_rect.size)))
	for x in range(maxi(mini(tl_grid.x, br_grid.x), 0), mini(maxi(tl_grid.x, br_grid.x) + 1, generator.size)):
		for y in range(maxi(mini(tl_grid.y, br_grid.y), 0), mini(maxi(tl_grid.y, br_grid.y) + 1, generator.size)):
			if generator.grid[x][y] == CaveGenerator.Tile.FLOOR:
				continue
			var cell_pos: Vector2i = _grid_to_cell(Vector2i(x, y))
			var world_pos: Vector2 = _tilemap.to_global(_tilemap.map_to_local(cell_pos))
			var half: float = TILE_SIZE * 0.5
			var local: Vector2 = _hitbox_overlay.to_local(world_pos)
			_hitbox_overlay.draw_rect(Rect2(local - Vector2(half, half), Vector2(TILE_SIZE, TILE_SIZE)), HITBOX_WALL_COLOR, false, 2.0)

	for entry in _placed_blocks.values():
		var node_ref: Variant = (entry as Dictionary)["node"]
		if not is_instance_valid(node_ref):
			continue
		var node: Node = node_ref as Node
		if node == null:
			continue
		if view_rect.has_point((node as Node2D).global_position):
			Global.draw_body_hitboxes(_hitbox_overlay, node, HITBOX_BLOCK_COLOR)

# 2 tiles north of the entrance/exit tile, not on top of it — CaveGenerator
# guarantees this exact column is carved open (see _carve_entrance_vestibule),
# so there's always real floor here instead of whatever the CA generated,
# and it keeps the player off the exact tile the EXIT CavePortal sits on.
func get_player_spawn_position() -> Vector2:
	var tile: Vector2i = generator.entrance_tile - Vector2i(0, 2)
	return _tilemap.to_global(_tilemap.map_to_local(_grid_to_cell(tile)))

# ── Persistent cave state ─────────────────────────────────────────
# Only the DIFF from the generated base grid is stored, plus placed blocks.
# Damage/levels/unrelated player state are not touched.
func snapshot_state() -> Dictionary:
	var tiles: Array = []
	if _base_grid.size() == generator.size:
		for x in range(generator.size):
			for y in range(generator.size):
				if generator.grid[x][y] != _base_grid[x][y]:
					tiles.append([x, y, int(generator.grid[x][y])])
	var blocks: Array = []
	for cell in _placed_blocks:
		var entry: Dictionary = _placed_blocks[cell] as Dictionary
		var path := ""
		var color := ""
		var node_ref: Variant = entry.get("node")
		if node_ref != null and not is_instance_valid(node_ref):
			continue   # a broken/despawned block must not be resurrected
		var block: Dictionary = {
			"x": int((cell as Vector2i).x),
			"y": int((cell as Vector2i).y),
			"name": str(entry.get("name", "")),
			"path": path,
			"color": color,
		}
		if is_instance_valid(node_ref):
			var node := node_ref as Node
			var idata: Variant = node.get("item_data")
			if idata is ItemData:
				if (idata as ItemData).is_color_block:
					color = ColorBlock.key_of((idata as ItemData).block_color)
				else:
					path = (idata as ItemData).resource_path
				block["path"] = path
				block["color"] = color
			if node.has_method("get_items"):
				var slot_save: Array = []
				var items = node.call("get_items")
				if items is Array:
					for slot in (items as Array):
						slot_save.append(Global.serialize_item(slot))
				block["chest_slots"] = slot_save
			var dungeon_index = node.get("dungeon_index")
			if dungeon_index != null:
				block["dungeon_index"] = int(dungeon_index)
			if node.has_method("get_station_save_data"):
				block["station"] = node.call("get_station_save_data")
			if node.has_method("get_furnace_save_data"):
				block["furnace"] = node.call("get_furnace_save_data")
			if node.has_method("get_lua_save_data"):
				block["lua"] = node.call("get_lua_save_data")
			if idata is ItemData and (idata as ItemData).is_door \
					and node.has_method("get_door_save_data"):
				block["door"] = node.call("get_door_save_data")
		blocks.append(block)
	return {
		"version": 1,
		"seed": _seed,
		"tiles": tiles,
		"blocks": blocks,
		"rare_chest": _rare_chest_state(),
	}

func apply_state(state: Dictionary) -> void:
	if state.is_empty():
		return
	# Never apply a snapshot to a different generated layout.
	if state.has("seed") and int(state.get("seed", _seed)) != _seed:
		return
	for t in state.get("tiles", []):
		if not (t is Array) or (t as Array).size() < 3:
			continue
		var grid_pos := Vector2i(int(t[0]), int(t[1]))
		if not _grid_in_bounds(grid_pos):
			continue
		var tile := int(t[2])
		generator.grid[grid_pos.x][grid_pos.y] = tile
		_paint_cell(_grid_to_cell(grid_pos), tile, grid_pos)
	for b in state.get("blocks", []):
		if b is Dictionary:
			_restore_placed_block(
				Vector2i(int((b as Dictionary).get("x", 0)), int((b as Dictionary).get("y", 0))),
				b as Dictionary)
	if state.has("rare_chest") and state["rare_chest"] is Dictionary:
		_apply_rare_chest_state(state["rare_chest"] as Dictionary)

func _restore_placed_block(cell: Vector2i, block: Dictionary) -> void:
	var name := str(block.get("name", ""))
	var path := str(block.get("path", ""))
	var color := str(block.get("color", ""))
	if _placed_blocks.has(cell) or (name.is_empty() and path.is_empty() and color.is_empty()):
		return
	var data: ItemData = null
	if not color.is_empty():
		data = ColorBlock.from_key(color)
	elif not path.is_empty() and ResourceLoader.exists(path):
		data = load(path) as ItemData
	if data == null:
		data = Global.find_item_by_name(name)
	if data == null or data.place_scene_path.is_empty():
		return
	if not ResourceLoader.exists(data.place_scene_path):
		return
	var obj_scene: PackedScene = load(data.place_scene_path) as PackedScene
	if obj_scene == null:
		return
	var obj: Node = obj_scene.instantiate()
	if obj == null:
		return
	# ChestBlock caches its @onready sprite, so its item texture must be applied
	# after add_child(). Other placeables keep the existing setup-before-add
	# order.
	var chest_like := data.place_scene_path.ends_with("ChestBlock.tscn")
	if not chest_like and obj.has_method("setup"):
		obj.call("setup", data)
	_placed_blocks[cell] = {"node": obj, "name": data.item_name}
	if obj.has_method("set_world_cell"):
		obj.call("set_world_cell", cell, self)
	add_child(obj)
	if chest_like and obj.has_method("setup"):
		obj.call("setup", data)
	var world_pos: Vector2 = _tilemap.map_to_local(cell)
	obj.position = world_pos
	obj.z_index = int(world_pos.y / TILE_SIZE)
	_fix_sprite_offset(obj)
	_refresh_neighbor_u_collision(cell)
	_restore_block_contents(obj, data, block)

func _restore_block_contents(obj: Node, data: ItemData, block: Dictionary) -> void:
	var slots = block.get("chest_slots", null)
	if slots is Array:
		var slots_ref = obj.get("slots")
		if slots_ref is Array:
			for i in range(mini((slots as Array).size(), (slots_ref as Array).size())):
				var slot: Variant = Global.deserialize_item((slots as Array)[i])
				if slot != null:
					(slots_ref as Array)[i] = slot
		if obj.has_method("_refresh_ui"):
			obj.call("_refresh_ui")
	var dungeon_index = block.get("dungeon_index", null)
	if dungeon_index != null:
		obj.set("dungeon_index", int(dungeon_index))
	var station_data = block.get("station", null)
	if station_data is Dictionary and obj.has_method("set_station_save_data"):
		obj.call("set_station_save_data", station_data)
	var furnace_data = block.get("furnace", null)
	if furnace_data is Dictionary and obj.has_method("set_furnace_save_data"):
		obj.call("set_furnace_save_data", furnace_data)
	var lua_data = block.get("lua", null)
	if lua_data is Dictionary and obj.has_method("set_lua_save_data"):
		obj.call("set_lua_save_data", lua_data)
	var door_data = block.get("door", null)
	if data.is_door and door_data is Dictionary and obj.has_method("set_door_save_data"):
		obj.call("set_door_save_data", door_data)

# Generator grid indices run 0..size-1; centering the map on the origin
# (matching how the overworld's own chunk coordinates are centered around
# Vector2i.ZERO) means every grid->cell conversion needs this same offset —
# painting, mining, placement, and spawn position must all agree on it.
# ── Camera bounds ───────────────────────────────────────────────────
# The playable rect of THIS cave, in world coordinates. The cave grid is centred
# on the origin (see _grid_to_cell), so the bounds are simply the grid extent —
# deliberately NOT the overworld's limits. Guarded for the moment before
# setup() has built the generator.
func camera_bounds() -> Rect2:
	if generator == null:
		return Rect2()
	var half: int = generator.size / 2
	var span: float = float(generator.size * TILE_SIZE)
	var base := Rect2(Vector2(-half * TILE_SIZE, -half * TILE_SIZE), Vector2(span, span))
	return base.grow(float(CAMERA_WALL_PADDING_TILES) * float(TILE_SIZE))

func _grid_to_cell(tile: Vector2i) -> Vector2i:
	var half: int = generator.size / 2
	return tile - Vector2i(half, half)

func _cell_to_grid(cell: Vector2i) -> Vector2i:
	var half: int = generator.size / 2
	return cell + Vector2i(half, half)

# ── Shared tileset (built once, reused by every cave) ──────────────────
static func _get_shared_tile_set() -> TileSet:
	if _shared_tile_set != null:
		return _shared_tile_set

	var ts := TileSet.new()
	ts.tile_size = Vector2i(TILE_SIZE, TILE_SIZE)
	ts.add_physics_layer()
	ts.set_physics_layer_collision_layer(0, 1)
	ts.set_physics_layer_collision_mask(0, 1)

	var poly := PackedVector2Array([
		Vector2(-TILE_SIZE / 2.0, -TILE_SIZE / 2.0),
		Vector2(TILE_SIZE / 2.0, -TILE_SIZE / 2.0),
		Vector2(TILE_SIZE / 2.0, TILE_SIZE / 2.0),
		Vector2(-TILE_SIZE / 2.0, TILE_SIZE / 2.0),
	])

	for tile_type in WALL_ITEM_PATHS.keys():
		var item: ItemData = load(WALL_ITEM_PATHS[tile_type]) as ItemData
		if item == null:
			push_warning("CaveWorld: missing item resource for wall tile type %s" % tile_type)
			continue
		_wall_items[tile_type] = item
		var cell: Dictionary = _add_wall_icon_source(ts, item.icon)
		if cell.is_empty():
			push_warning("CaveWorld: '%s' has no icon set — wall tile will be invisible" % item.item_name)
			continue
		var src: TileSetAtlasSource = ts.get_source(cell["source"]) as TileSetAtlasSource
		var td: TileData = src.get_tile_data(cell["coord"], 0)
		td.add_collision_polygon(0)
		td.set_collision_polygon_points(0, 0, poly)
		_wall_cells[tile_type] = cell

	for path in FLOOR_ITEM_PATHS:
		var item: ItemData = load(path) as ItemData
		if item == null or item.icon == null:
			continue  # cave_floor3-5 have no icon set yet — skip rather than render blank
		var cell: Dictionary = _add_icon_source(ts, item.icon)
		if not cell.is_empty():
			_floor_cells.append(cell)
	if _floor_cells.is_empty():
		push_warning("CaveWorld: no cave_floor item has an icon set — floor will be invisible")

	_shared_tile_set = ts
	return ts

# Adds a dedicated 1-tile TileSetAtlasSource for a single ItemData icon.
# Each icon is its own AtlasTexture region into the shared item spritesheet,
# and those regions don't all land on one common 32px grid (cave_floor2's
# starts at x=190) — so rather than assume a shared atlas grid, every item
# gets its own source sized/margined to its EXACT region, read directly off
# the icon itself (region.position as margins, region.size as the cell
# size), with its one tile always at coordinate (0,0).
static func _add_icon_source(ts: TileSet, icon: Texture2D) -> Dictionary:
	if icon == null:
		return {}
	var tex: Texture2D
	var region: Rect2
	var atlas_tex := icon as AtlasTexture
	if atlas_tex != null:
		tex    = atlas_tex.atlas
		region = atlas_tex.region
	else:
		tex    = icon
		region = Rect2(Vector2.ZERO, icon.get_size())
	if tex == null:
		return {}
	var src := TileSetAtlasSource.new()
	src.texture             = tex
	src.margins             = Vector2i(region.position.round())
	src.texture_region_size = Vector2i(region.size.round())
	src.create_tile(Vector2i.ZERO)
	var source_id: int = ts.add_source(src)
	return {"source": source_id, "coord": Vector2i.ZERO}

# Wall/ore tiles get the shadow baked directly into their own tile texture
# (see _build_wall_tile_image) instead of reusing the shared spritesheet
# in-place like _add_icon_source does — compositing needs an actual pixel
# buffer to draw into, not just a texture-region reference. Floor tiles
# don't get this (only "the stones inside the caves" were asked for).
static func _add_wall_icon_source(ts: TileSet, icon: Texture2D) -> Dictionary:
	var composite: Image = _build_wall_tile_image(icon)
	if composite == null:
		return {}
	var tex := ImageTexture.create_from_image(composite)
	var src := TileSetAtlasSource.new()
	src.texture             = tex
	src.texture_region_size = composite.get_size()
	src.create_tile(Vector2i.ZERO)
	var source_id: int = ts.add_source(src)
	return {"source": source_id, "coord": Vector2i.ZERO}

# Crops the icon's exact pixels out of the shared spritesheet, then blends a
# scaled-down, alpha-reduced copy of the game's standard shadow texture
# (sprites/shadow/shadow_base.png — same one player/trees/mobs use) ON TOP
# of the icon at its bottom edge. The source ore/stone art is fully opaque
# with no transparent margin, so a shadow drawn BEHIND it would never show
# at all — drawing it on top at ~45% alpha instead darkens that bottom
# strip, reading as a soft base shadow grounding the block rather than
# fully obscuring the art underneath.
static func _build_wall_tile_image(icon: Texture2D) -> Image:
	if icon == null:
		return null
	var icon_img: Image
	var atlas_tex := icon as AtlasTexture
	if atlas_tex != null and atlas_tex.atlas != null:
		var full_img: Image = atlas_tex.atlas.get_image()
		var region := Rect2i(Vector2i(atlas_tex.region.position.round()), Vector2i(atlas_tex.region.size.round()))
		icon_img = full_img.get_region(region)
	else:
		icon_img = icon.get_image()
	icon_img = icon_img.duplicate()
	icon_img.convert(Image.FORMAT_RGBA8)

	var shadow: Image = _get_shadow_overlay_image()
	if shadow == null:
		return icon_img

	var composite: Image = icon_img.duplicate()
	var pos := Vector2i((composite.get_width() - shadow.get_width()) / 2, composite.get_height() - shadow.get_height())
	composite.blend_rect(shadow, Rect2i(Vector2i.ZERO, shadow.get_size()), pos)
	return composite

static var _shadow_overlay_image: Image = null

# Built once and cached — the source PNG is a solid ellipse meant to sit
# fully opaque under a small standalone sprite (player, trees); scaled down
# to a flat strip and knocked back to ~45% alpha so, baked onto a full-tile
# wall texture, it reads as subtle base shading instead of covering the art.
static func _get_shadow_overlay_image() -> Image:
	if _shadow_overlay_image != null:
		return _shadow_overlay_image
	var tex: Texture2D = load(SHADOW_TEXTURE_PATH) as Texture2D
	if tex == null:
		return null
	var img: Image = tex.get_image()
	img = img.duplicate()
	img.convert(Image.FORMAT_RGBA8)
	img.resize(int(TILE_SIZE * 0.85), int(TILE_SIZE * 0.30), Image.INTERPOLATE_BILINEAR)
	for y in range(img.get_height()):
		for x in range(img.get_width()):
			var c: Color = img.get_pixel(x, y)
			c.a *= 0.45
			img.set_pixel(x, y, c)
	_shadow_overlay_image = img
	return _shadow_overlay_image

# ── Paint the generated grid into the TileMapLayer ─────────────────────
func _paint_tiles() -> void:
	for x in range(generator.size):
		for y in range(generator.size):
			var grid_pos := Vector2i(x, y)
			_paint_cell(_grid_to_cell(grid_pos), generator.grid[x][y], grid_pos)
	_paint_surrounding_walls()

# Fills the void around the generated cave with a solid band of stone walls —
# the cave grid is fully populated, but the TileMapLayer beyond its border was
# empty, so the map edge showed through as black void. A band of stone on all
# four sides closes that off; the generator already treats out-of-bounds as
# solid (see _cell_is_wall), so this is purely visual. Thickness matches the
# dungeon world's SURROUND_BAND_TILES.
func _paint_surrounding_walls() -> void:
	var cell: Dictionary = _wall_cells.get(CaveGenerator.Tile.STONE, {})
	if cell.is_empty():
		return
	var half: int = generator.size / 2
	var band: int = SURROUND_BAND_TILES
	var x0 := -(half + band)
	var x1 := half + band
	for cx in range(x0, x1):
		for cy in range(x0, x1):
			if cx >= -half and cx < half and cy >= -half and cy < half:
				continue  # inside the generated grid — already painted
			_tilemap.set_cell(Vector2i(cx, cy), cell["source"], cell["coord"])

func _paint_cell(cell_pos: Vector2i, tile_type: int, grid_pos: Vector2i) -> void:
	var cell: Dictionary
	if tile_type == CaveGenerator.Tile.FLOOR:
		cell = _floor_cells[_floor_variant_index(grid_pos)] if not _floor_cells.is_empty() else {}
	else:
		cell = _wall_cells.get(tile_type, {})
	if cell.is_empty():
		return
	_tilemap.set_cell(cell_pos, cell["source"], cell["coord"])

# Deterministic pick (pure function of tile position, no RNG needed) so a
# cave's visuals stay identical across repeat visits, same as its layout.
func _floor_variant_index(grid_pos: Vector2i) -> int:
	var h: int = (grid_pos.x * 92821) ^ (grid_pos.y * 68917)
	return absi(h) % _floor_cells.size()

# ── Rare cave chest ─────────────────────────────────────────────────
# One low-probability chest in a clear 3x3 floor pocket, kept away from the
# entrance/exit and player spawn. Large caves have no room list, so the pocket
# itself is the room-equivalent eligibility check.
func _spawn_rare_chest() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = _seed + 0x51A7E
	if rng.randf() >= RARE_CHEST_CHANCE:
		return
	var candidates: Array = []
	for x in range(2, generator.size - 2):
		for y in range(2, generator.size - 2):
			var grid_pos := Vector2i(x, y)
			if generator.grid[x][y] != CaveGenerator.Tile.FLOOR:
				continue
			if _dist_to_grid(generator.entrance_tile, grid_pos) < 10.0:
				continue
			if not _floor_patch_clear(grid_pos, 1):
				continue
			var cell := _grid_to_cell(grid_pos)
			if _placed_blocks.has(cell):
				continue
			candidates.append(cell)
	if candidates.is_empty():
		return
	var chosen: Vector2i = candidates[rng.randi_range(0, candidates.size() - 1)]
	_spawn_rare_chest_at(chosen)

func _floor_patch_clear(center: Vector2i, radius: int) -> bool:
	for x in range(center.x - radius, center.x + radius + 1):
		for y in range(center.y - radius, center.y + radius + 1):
			if x < 1 or y < 1 or x >= generator.size - 1 or y >= generator.size - 1:
				return false
			if generator.grid[x][y] != CaveGenerator.Tile.FLOOR:
				return false
	return true

func _dist_to_grid(a: Vector2i, b: Vector2i) -> float:
	return Vector2(a).distance_to(Vector2(b))

func _spawn_rare_chest_at(cell: Vector2i, saved_slots: Array = []) -> Node:
	if _placed_blocks.has(cell) or _cell_is_wall(cell):
		return null
	var chest: Node = RARE_CHEST_SCENE.instantiate()
	if chest == null:
		return null
	add_child(chest)
	chest.call("setup", RARE_CHEST_DATA)
	chest.call("set_world_cell", cell, self)
	var world_pos: Vector2 = _tilemap.map_to_local(cell)
	chest.position = world_pos
	chest.z_index = int(world_pos.y / TILE_SIZE)
	if not saved_slots.is_empty():
		_restore_chest_slots(chest, saved_slots)
	else:
		var rng := RandomNumberGenerator.new()
		rng.seed = _seed + cell.x * 73856093 + cell.y * 19349663
		RareChestLoot.fill(chest, rng)
	_placed_blocks[cell] = {"node": chest, "name": RARE_CHEST_DATA.item_name}
	_rare_chest_cell = cell
	_rare_chest_spawned = true
	_rare_chest_removed = false
	_refresh_neighbor_u_collision(cell)
	return chest

func _restore_chest_slots(chest: Node, saved_slots: Array) -> void:
	var slots_ref: Variant = chest.get("slots")
	if not (slots_ref is Array):
		return
	var slots: Array = slots_ref as Array
	for i in range(slots.size()):
		slots[i] = null
	for i in range(mini(saved_slots.size(), slots.size())):
		var slot: Variant = Global.deserialize_item(saved_slots[i])
		if slot != null:
			slots[i] = slot
	if chest.has_method("_refresh_ui"):
		chest.call("_refresh_ui")

func _rare_chest_state() -> Dictionary:
	if _rare_chest_removed:
		return {"removed": true,
			"cell": [_rare_chest_cell.x, _rare_chest_cell.y]}
	if not _rare_chest_spawned:
		return {"none": true}
	var entry: Variant = _placed_blocks.get(_rare_chest_cell)
	if not (entry is Dictionary):
		return {"none": true}
	var node_ref: Variant = (entry as Dictionary).get("node")
	if not is_instance_valid(node_ref):
		return {"none": true}
	var slots_ref: Variant = (node_ref as Node).get("slots")
	var slots: Array = []
	if slots_ref is Array:
		for slot in (slots_ref as Array):
			slots.append(Global.serialize_item(slot))
	return {"cell": [_rare_chest_cell.x, _rare_chest_cell.y], "slots": slots}

func _apply_rare_chest_state(state: Dictionary) -> void:
	if bool(state.get("removed", false)) or bool(state.get("none", false)):
		_remove_rare_chest()
		_rare_chest_removed = bool(state.get("removed", false))
		_rare_chest_spawned = false
		return
	var raw_cell: Variant = state.get("cell", null)
	if not (raw_cell is Array) or (raw_cell as Array).size() < 2:
		return
	var saved_cell := Vector2i(int((raw_cell as Array)[0]), int((raw_cell as Array)[1]))
	if saved_cell != _rare_chest_cell:
		_remove_rare_chest()
	var existing: Variant = _placed_blocks.get(saved_cell)
	if existing is Dictionary:
		var node_ref: Variant = (existing as Dictionary).get("node")
		if is_instance_valid(node_ref) and node_ref.has_method("notify_contents_changed"):
			_restore_chest_slots(node_ref, state.get("slots", []) as Array)
			_rare_chest_cell = saved_cell
			_rare_chest_spawned = true
			_rare_chest_removed = false
			return
	_spawn_rare_chest_at(saved_cell, state.get("slots", []) as Array)

func _remove_rare_chest() -> void:
	var entry: Variant = _placed_blocks.get(_rare_chest_cell)
	if entry is Dictionary:
		var node_ref: Variant = (entry as Dictionary).get("node")
		if is_instance_valid(node_ref):
			(node_ref as Node).queue_free()
		_placed_blocks.erase(_rare_chest_cell)


func _spawn_exit_marker() -> void:
	var exit_portal := CavePortal.new()
	exit_portal.mode = CavePortal.Mode.EXIT
	add_child(exit_portal)
	# The marker itself sits on the actual entrance tile — the player spawns
	# 2 tiles away from it (see get_player_spawn_position()), not on top of it.
	exit_portal.global_position = _tilemap.to_global(_tilemap.map_to_local(_grid_to_cell(generator.entrance_tile)))

# ── Cave darkness ────────────────────────────────────────────────────────
func _setup_darkness() -> void:
	_ambient = CanvasModulate.new()
	_ambient.color = CAVE_AMBIENT_COLOR
	add_child(_ambient)

	add_child(_build_glow_environment())

# /shaq cheat: flip the whole cave to pitch black (only PointLight2Ds — torches
# — light anything). Running it again restores the normal dim ambient.
func toggle_shaq_dark() -> void:
	_shaq_dark = not _shaq_dark
	if _ambient != null:
		_ambient.color = Color(0.0, 0.0, 0.0, 1.0) if _shaq_dark else CAVE_AMBIENT_COLOR

# Glow is most of what separates a flat radial-gradient light from the
# punchy, bloom-heavy look of top-down arcade games (Soul Knight etc.) —
# scoped to CaveWorld itself (not any one light) so every light the player
# places in here (torches, etc.) blooms automatically, no extra wiring.
func _build_glow_environment() -> WorldEnvironment:
	var world_env := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode   = Environment.BG_CANVAS  # keep normal 2D rendering, no 3D sky/clear color
	env.glow_enabled       = true
	env.glow_intensity     = 0.9
	env.glow_strength      = 1.1
	env.glow_bloom         = 0.15
	env.glow_hdr_threshold = 0.85  # light energy (1.6+) clears this, tile/sprite art at normal brightness doesn't
	env.glow_blend_mode    = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	world_env.environment = env
	return world_env
