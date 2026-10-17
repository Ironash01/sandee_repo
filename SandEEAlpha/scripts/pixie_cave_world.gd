extends Node2D
class_name PixieCaveWorld

# A pixie-cave interior — swapped in for the overworld "World" node by
# game_instance.gd's enter_cave()/exit_cave() when the entered CavePortal is a
# pixie cave (portal.cave_type == "pixie"). Built entirely in code from
# PixieCaveGenerator's output at setup() time (no .tscn), same pattern as
# CaveWorld/DungeonWorld.
#
# Standalone (NOT extending CaveWorld) on purpose: CaveWorld caches its shared
# TileSet + wall/floor cell maps in *static* vars keyed to CaveGenerator.Tile,
# which a subclass would share (and clobber) with the regular cave. Pixie caves
# use their own tile types (pixie stone + crystal ores) and their own static
# cache, so this class duplicates the small tileset/painting/mining/lighting
# helpers rather than fighting that static-cache design.
#
# Layout (PixieCaveGenerator): randomly 32x24, 40x20, or 20x16 dungeon-like —
# small rooms joined by 2-wide corridors, walls of pixie stone, crystal ores
# housed inside rooms (copper/iron/silicon guaranteed, diamond a 5% gamble).
# A 128-tile band of pixie stone closes the void around the grid
# (SURROUND_BAND_TILES).

const TILE_SIZE:           int   = 32
const INTERACT_RADIUS_PX:  float = 64.0
const ITEM_DROP_SCENE:     PackedScene = preload("res://scenes/ui/InventoryItem.tscn")
const SURROUND_BAND_TILES: int   = 128  # solid pixie-stone band around the grid (matches cave/dungeon)

# ── Build mode (ghost preview + placement, mirrors CaveWorld) ─────────
# Only floor tiles are buildable (walls/ores are mineable instead). Z-index
# for placement guides is an arbitrary high value above the player's y-sort
# buckets (same idea as CaveWorld's PLACEMENT_GUIDE_Z_INDEX).
const PLACE_RADIUS_TILES:       int   = 6
const PLACEMENT_GUIDE_Z_INDEX:  int   = 900

var _placed_blocks: Dictionary = {}  # cell -> {"node": Node, "name": String}
var ghost:           Node2D   = null
var ghost_sprite:    Sprite2D = null
var ghost_last_type: String   = ""
var _grid_overlay: Node2D     = null
var _cursor_highlight: Node2D = null

# Wall/ore tile type -> the ItemData that renders it, drops when mined, and
# supplies block_level/min_pickaxe_level for the mining-duration formula
# (maxf(0.1, block_level - pickaxe_level), same as CaveWorld/placeable_block).
const WALL_ITEM_PATHS: Dictionary = {
	PixieCaveGenerator.Tile.WALL:            "res://resources/items/pixie_cave_stone.tres",
	PixieCaveGenerator.Tile.CRYSTAL_COPPER:  "res://resources/items/crystal_copper_ore.tres",
	PixieCaveGenerator.Tile.CRYSTAL_IRON:    "res://resources/items/crystal_iron_ore.tres",
	PixieCaveGenerator.Tile.CRYSTAL_SILICON: "res://resources/items/crystal_silicon_ore.tres",
	PixieCaveGenerator.Tile.CRYSTAL_DIAMOND: "res://resources/items/crystal_diamond_ore.tres",
}

const FLOOR_ITEM_PATHS: Array = [
	"res://resources/items/pixie_floor1.tres",
	"res://resources/items/pixie_floor2.tres",
	"res://resources/items/pixie_floor3.tres",
	"res://resources/items/pixie_floor4.tres",
	"res://resources/items/pixie_floor5.tres",
]

const SHADOW_TEXTURE_PATH: String = "res://sprites/shadow/shadow_base.png"

# ── Crystal ore regen/glow/dim ──────────────────────────────────────
# Crystal ores regenerate after mining: 1 in-game hour for copper/iron/silicon,
# 2 hours for diamond. While mined, the ore tile is dimmed (not removed). When
# available, the ore has a subtle glow (PointLight2D).
const ORE_REGEN_HOURS: Dictionary = {
	PixieCaveGenerator.Tile.CRYSTAL_COPPER:  1.0,
	PixieCaveGenerator.Tile.CRYSTAL_IRON:    1.0,
	PixieCaveGenerator.Tile.CRYSTAL_SILICON: 1.0,
	PixieCaveGenerator.Tile.CRYSTAL_DIAMOND: 2.0,
}
const ORE_GLOW_ENERGY: float = 0.4
const ORE_GLOW_RADIUS_PX: float = 48.0

var _mined_ores: Dictionary = {}  # cell -> {"ore_type": int, "time_mined": float}
var _ore_lights: Dictionary = {}  # cell -> PointLight2D
var _ore_fireflies: Dictionary = {}  # cell -> GPUParticles2D (fireflies around an available ore)
var _dimmed_ore_layer: TileMapLayer = null
static var _dimmed_ore_cells: Dictionary = {}  # ore_type -> {"source": id, "coord": Vector2i}

# ── Fireflies (glowing orbs near ores + cave wall edges) ──────────────
# A customized firefly effect: one 32x32 frame of glowing_orbs_sample.png used
# as a tiny (~8px) particle sprite, spawned in multiples around available
# crystal ores AND along the edges of cave-stone walls that border open path
# (rooms/corridors). GPUParticles2D never collide, so fireflies pass through
# everything. Kept light for mobile: bounded emitters/amounts, tiny sprites,
# and off-screen emitters are culled by Godot automatically.
const ORE_ORBS_TEX: Texture2D = preload("res://sprites/particles_effects/glowing_orbs_sample.png")
const ORE_ORBS_FRAME_SIZE: int = 32

const FIREFLY_SCALE_MIN: float = 0.18   # ~6px on a 32px frame
const FIREFLY_SCALE_MAX: float = 0.30   # ~10px
const FIREFLY_AMOUNT_ORE:  int = 5      # per glowing ore
const FIREFLY_AMOUNT_WALL: int = 3      # per wall-edge emitter
const WALL_FIREFLY_MAX_EMITTERS: int = 40  # perf cap on wall-edge emitters

static var _orb_texture: Texture2D = null

# ── Pixie mobs (roam the cave, guard the ores) ─────────────────────
const PIXIE_SCENE:       PackedScene = preload("res://scenes/mobs/Pixie.tscn")
const PIXIE_SPAWN_COUNT: int = 4  # spawned near crystal ores, any time (cave has no day/night)

var _seed: int = 0  # stored so pixie placement can be deterministic per cave

# ── Mystical darkness / player light ────────────────────────────────────
# A purple-violet ambient instead of CaveWorld's near-black blue — the start
# of the "mystical" pixie-cave mood (full glow/fireflies are wired in a later
# task). Same CanvasModulate + glow WorldEnvironment + player PointLight2D
# recipe CaveWorld uses, so torches/ore glow slot in for free later.
const PIXIE_AMBIENT_COLOR:     Color = Color(0.08, 0.05, 0.13, 1.0)  # dim mystical violet
const LIGHT_TEXTURE_SIZE:      int   = 512

static var _shared_tile_set: TileSet = null
static var _wall_cells:  Dictionary = {}  # Tile enum -> {"source": id, "coord": Vector2i}
static var _wall_items:  Dictionary = {}  # Tile enum -> ItemData
static var _floor_cells: Array      = []  # [{"source": id, "coord": Vector2i}, ...]
static var _shadow_overlay_image: Image = null

var generator: PixieCaveGenerator = null
var overworld_return_position: Vector2 = Vector2.ZERO
var _tilemap: TileMapLayer = null

func setup(seed_value: int, return_position: Vector2) -> void:
	overworld_return_position = return_position
	_seed = seed_value
	generator = PixieCaveGenerator.new()
	generator.generate(seed_value)

	_tilemap = TileMapLayer.new()
	_tilemap.name     = "PixieCaveTiles"
	_tilemap.tile_set = _get_shared_tile_set()
	# z_index = -300 keeps the tilemap below the player's quantized
	# int(y / TILE_SIZE) Y-sort buckets (which go negative north of the
	# grid's center, since the grid is centered on the origin). Same fix
	# CaveWorld applies — without it the player renders behind walls.
	_tilemap.z_index = -300
	add_child(_tilemap)

	# Dimmed ore layer (for mined crystal ores that are regenerating)
	_dimmed_ore_layer = TileMapLayer.new()
	_dimmed_ore_layer.name = "DimmedOres"
	_dimmed_ore_layer.tile_set = _get_dimmed_ore_tile_set()
	_dimmed_ore_layer.z_index = -300
	add_child(_dimmed_ore_layer)

	_paint_tiles()
	_spawn_wall_fireflies()
	_spawn_pixies()
	_spawn_exit_marker()
	_setup_darkness()
	_setup_ghost()
	_setup_grid_overlay()
	_setup_cursor_highlight()

func _process(delta: float) -> void:
	_update_mining(delta)
	_update_ghost()
	_update_cursor_highlight()
	_check_ore_regeneration()
	# The build-mode grid follows the player — redraw every frame while it's
	# visible so it tracks movement.
	if _grid_overlay != null and _grid_overlay.visible:
		_grid_overlay.queue_redraw()

func _check_ore_regeneration() -> void:
	if _mined_ores.is_empty():
		return
	
	var current_time: float = Global.time_of_day
	var to_remove: Array = []
	
	for cell in _mined_ores:
		var mined_data: Dictionary = _mined_ores[cell]
		var ore_type: int = mined_data["ore_type"]
		var time_mined: float = mined_data["time_mined"]
		var regen_hours: float = ORE_REGEN_HOURS.get(ore_type, 1.0)
		var regen_fraction: float = regen_hours / 24.0  # Convert hours to fraction of day
		
		# Calculate elapsed time (handle day wrap)
		var elapsed: float = current_time - time_mined
		if elapsed < 0:
			elapsed += 1.0  # Wrapped around midnight
		
		if elapsed >= regen_fraction:
			# Regenerate the ore
			to_remove.append(cell)
			
			# Remove from dimmed layer
			_dimmed_ore_layer.erase_cell(cell)
			
			# Repaint on main layer
			_paint_cell(cell, ore_type, _cell_to_grid(cell))
			
			# Show the glow light + orbs animation
			var light: PointLight2D = _ore_lights.get(cell)
			if light != null:
				light.visible = true
			var firefly: GPUParticles2D = _ore_fireflies.get(cell)
			if firefly != null:
				firefly.emitting = true
				firefly.visible = true
	
	for cell in to_remove:
		_mined_ores.erase(cell)

# ── Mining (pixie-stone walls / crystal ores) ───────────────────────────
# Centralized (no per-tile Area2D), same reasoning as CaveWorld. Pickaxe-
# gated identically: duration = maxf(0.1, block_level - pickaxe_level).
# NOTE: this is the basic break-to-floor path for now; a later task adds the
# crystal-ore specifics — glow while minable, dim-not-remove on break, and
# 1h/2h in-game regen — by branching _break_tile on the ore type.
var _mine_tile:     Vector2i = Vector2i.ZERO
var _mining:        bool     = false
var _mine_elapsed:  float    = 0.0
var _mine_duration: float    = 1.0
# Global tap-to-break (see cave_world.gd): a fresh click is worth this much
# break work, so tapping chips the wall down instead of needing one long hold.
const CLICK_BREAK_SECONDS: float = 0.5
# Wobbling Sprite2D copy of the mined tile (see cave_world.gd for why).
var _mine_overlay: Sprite2D = null

func _input(event: InputEvent) -> void:
	if Global.any_ui_open() or Global.pause_menu_open:
		return
	# Build mode: place blocks on floor tiles (walls/ores are mineable).
	if Global.block_mode:
		if event.is_action_pressed("mouse_left"):
			place_block()
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_try_start_mining()
		else:
			_cancel_mining()

func _try_start_mining() -> void:
	var mouse_cell: Vector2i = _mouse_cell()
	var grid_pos: Vector2i   = _cell_to_grid(mouse_cell)
	if not _grid_in_bounds(grid_pos):
		return
	var tile_type: int = generator.grid[grid_pos.x][grid_pos.y]
	if tile_type == PixieCaveGenerator.Tile.FLOOR:
		return
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
	# Global tap-to-break: a fresh click is worth CLICK_BREAK_SECONDS of work.
	_mine_elapsed  = minf(_mine_elapsed + CLICK_BREAK_SECONDS, _mine_duration)
	queue_redraw()
	if _mine_elapsed >= _mine_duration:
		_finish_break()

func _cancel_mining() -> void:
	if not _mining:
		return
	_mining = false
	# Progress is deliberately KEPT so the next tap on this tile continues.
	# The real tile comes back (the wobble overlay goes away).
	_destroy_mine_overlay(true)
	queue_redraw()

# Mine complete: drop the overlay WITHOUT restoring the tile (it becomes floor).
func _finish_break() -> void:
	_mining = false
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
	# Hide the real tile so the rotated overlay can't double-image against it.
	_tilemap.set_cell(cell, -1)

# restore=true repaints the real wall tile (cancel); false leaves it hidden.
func _destroy_mine_overlay(restore: bool) -> void:
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
		and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) \
		and not Global.any_ui_open() and not Global.pause_menu_open
	if not still_valid:
		_cancel_mining()
		return
	_mine_elapsed = minf(_mine_elapsed + delta, _mine_duration)
	# Same shake the overworld's placed blocks use.
	if is_instance_valid(_mine_overlay):
		_mine_overlay.rotation = Global.block_wobble_rotation()
	queue_redraw()
	if _mine_elapsed >= _mine_duration:
		_finish_break()

func _draw() -> void:
	if not _mining:
		return
	var tile_world: Vector2 = _tilemap.to_global(_tilemap.map_to_local(_mine_tile))
	var pos: Vector2        = to_local(tile_world)
	var progress: float     = _mine_elapsed / _mine_duration if _mine_duration > 0.0 else 1.0
	var s: float            = Global.ui_scale
	var bar_w: float        = Global.BREAK_BAR_WIDTH * s
	var bar_h: float        = Global.BREAK_BAR_HEIGHT * s
	var half_w: float       = bar_w * 0.5
	var y_offset: float     = -20.0 * s
	draw_rect(Rect2(pos.x - half_w, pos.y + y_offset, bar_w, bar_h), Global.BREAK_BAR_BG)
	draw_rect(Rect2(pos.x - half_w, pos.y + y_offset, bar_w * clampf(progress, 0.0, 1.0), bar_h), Global.BREAK_BAR_FILL)

func _break_tile(cell: Vector2i) -> void:
	var grid_pos: Vector2i = _cell_to_grid(cell)
	if not _grid_in_bounds(grid_pos):
		return
	var tile_type: int = generator.grid[grid_pos.x][grid_pos.y]
	var item: ItemData = _wall_items.get(tile_type)
	
	# Check if this is a crystal ore (regenerates)
	var is_crystal_ore = tile_type in [
		PixieCaveGenerator.Tile.CRYSTAL_COPPER,
		PixieCaveGenerator.Tile.CRYSTAL_IRON,
		PixieCaveGenerator.Tile.CRYSTAL_SILICON,
		PixieCaveGenerator.Tile.CRYSTAL_DIAMOND
	]
	
	if is_crystal_ore:
		# Dim the ore (move to dimmed layer) instead of removing
		generator.grid[grid_pos.x][grid_pos.y] = PixieCaveGenerator.Tile.FLOOR
		_tilemap.erase_cell(cell)
		
		# Paint on dimmed layer
		var dimmed_cell: Dictionary = _dimmed_ore_cells.get(tile_type, {})
		if not dimmed_cell.is_empty():
			_dimmed_ore_layer.set_cell(cell, dimmed_cell["source"], dimmed_cell["coord"])
		
		# Hide the glow light + orbs animation
		var light: PointLight2D = _ore_lights.get(cell)
		if light != null:
			light.visible = false
		var firefly: GPUParticles2D = _ore_fireflies.get(cell)
		if firefly != null:
			firefly.emitting = false
			firefly.visible = false
		
		# Store mined ore with current in-game time
		_mined_ores[cell] = {
			"ore_type": tile_type,
			"time_mined": Global.time_of_day
		}
	else:
		# Regular wall/stone: break to floor as before
		generator.grid[grid_pos.x][grid_pos.y] = PixieCaveGenerator.Tile.FLOOR
		_paint_cell(cell, PixieCaveGenerator.Tile.FLOOR, grid_pos)
	
	if item == null:
		return
	Global.track_mining(item)
	var drop: Node = ITEM_DROP_SCENE.instantiate()
	drop.call("set_item_data", item)
	add_child(drop)
	var offset := Vector2(randf_range(-8, 8), randf_range(-8, 8))
	drop.global_position = _tilemap.to_global(_tilemap.map_to_local(cell)) + offset

func _get_held_pickaxe_level() -> int:
	var slot = Global.get_hotbar_item()
	if slot == null:
		return -1
	var data: ItemData = slot["data"] as ItemData
	if data == null or not data.item_name.to_lower().contains("pickaxe"):
		return -1
	return data.pickaxe_level

# ── Build mode (ghost preview + placement, mirrors CaveWorld) ──────────
# Only FLOOR tiles are buildable — walls/ores are the mineable resource here.
# Placement is position-gated off the player (place radius + waist-high
# footprint) exactly like CaveWorld/world.gd, so the rules match across
# every world backend.
func _setup_ghost() -> void:
	ghost = Node2D.new()
	ghost.visible = false
	ghost.z_index = PLACEMENT_GUIDE_Z_INDEX
	add_child(ghost)
	ghost_sprite = Sprite2D.new()
	ghost_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
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
	var cell: Vector2i = _mouse_cell()
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
	var item = Global.get_hotbar_item()
	if not _is_placeable_item(item):
		return
	var cell: Vector2i = _mouse_cell()
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

func unregister_block(cell: Vector2i) -> void:
	_placed_blocks.erase(cell)
	_refresh_neighbor_u_collision(cell)

# True when a player-placed block occupies this cell (PlaceableBlock's
# U-collider toggle checks vertical neighbours via this).
func has_placed_block(cell: Vector2i) -> bool:
	return _placed_blocks.has(cell)

# A torch mounts to a solid neighbour: a placed block OR a solid cave wall.
# Cave rock is TileMapLayer cells, NOT placed blocks, so without this a torch
# placed against a wall never used its connected sprite (unlike the overworld,
# where world-gen stone/charcoal live in _placed_blocks).
func torch_support(cell: Vector2i) -> bool:
	return _placed_blocks.has(cell) or _cell_is_wall(cell)

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
		var n: Node = (_placed_blocks[c] as Dictionary).get("node")
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

# Same waist-high player-footprint dims CaveWorld's own
# _cell_blocked_by_player uses (PlayerCol: 20x12 at y 17) — keep in sync.
func _cell_blocked_by_player(cell: Vector2i) -> bool:
	var player: Node2D = Global.player_node as Node2D
	if player == null:
		return false
	# Waist-high player-footprint dims (PlayerCol: 20x12 at y 17) — keep in sync.
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
			var color := Color(1.0, 1.0, 1.0, 0.45) \
				if not (_cell_blocked_by_player(cell)) \
				else Color(1.0, 0.3, 0.3, 0.45)
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
	var mouse_local: Vector2 = _tilemap.get_local_mouse_position()
	var cell:        Vector2i = _tilemap.local_to_map(mouse_local)
	_cursor_highlight.position = _tilemap.map_to_local(cell)
	_cursor_highlight.queue_redraw()
	_cursor_highlight.visible = true

func _mouse_cell() -> Vector2i:
	return _tilemap.local_to_map(_tilemap.to_local(get_global_mouse_position()))

func _grid_in_bounds(grid_pos: Vector2i) -> bool:
	return grid_pos.x >= 0 and grid_pos.y >= 0 \
		and grid_pos.x < generator.width and grid_pos.y < generator.height

func _cell_is_wall(cell: Vector2i) -> bool:
	var grid_pos: Vector2i = _cell_to_grid(cell)
	if not _grid_in_bounds(grid_pos):
		return true
	return generator.grid[grid_pos.x][grid_pos.y] != PixieCaveGenerator.Tile.FLOOR

# 2 tiles north of the entrance/exit tile, not on top of it (matches
# CaveWorld); PixieCaveGenerator._carve_entrance guarantees this column is open.
func get_player_spawn_position() -> Vector2:
	var tile: Vector2i = generator.entrance_tile - Vector2i(0, 2)
	return _tilemap.to_global(_tilemap.map_to_local(_grid_to_cell(tile)))

# Grid indices run 0..width-1 / 0..height-1; the map is centered on the origin
# (non-square, unlike CaveWorld's size/2 for both axes), so every grid<->cell
# conversion uses separate width/2 and height/2 offsets.
func _grid_to_cell(tile: Vector2i) -> Vector2i:
	return tile - Vector2i(generator.width / 2, generator.height / 2)

func _cell_to_grid(cell: Vector2i) -> Vector2i:
	return cell + Vector2i(generator.width / 2, generator.height / 2)

# ── Shared tileset (built once, reused by every pixie cave) ─────────────
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
			push_warning("PixieCaveWorld: missing item resource for tile type %s" % tile_type)
			continue
		_wall_items[tile_type] = item
		var cell: Dictionary = _add_wall_icon_source(ts, item.icon)
		if cell.is_empty():
			push_warning("PixieCaveWorld: '%s' has no icon — wall tile invisible" % item.item_name)
			continue
		var src: TileSetAtlasSource = ts.get_source(cell["source"]) as TileSetAtlasSource
		var td: TileData = src.get_tile_data(cell["coord"], 0)
		td.add_collision_polygon(0)
		td.set_collision_polygon_points(0, 0, poly)
		_wall_cells[tile_type] = cell
	for path in FLOOR_ITEM_PATHS:
		var item: ItemData = load(path) as ItemData
		if item == null or item.icon == null:
			continue
		var cell: Dictionary = _add_icon_source(ts, item.icon)
		if not cell.is_empty():
			_floor_cells.append(cell)
	if _floor_cells.is_empty():
		push_warning("PixieCaveWorld: no pixie_floor item has an icon set — floor invisible")
	_shared_tile_set = ts
	return ts

# Each icon is its own AtlasTexture region into the shared item spritesheet,
# not on one common 32px grid, so every item gets its own dedicated source
# sized to its exact region (mirrors CaveWorld._add_icon_source).
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

# Wall/ore tiles get the standard shadow baked into their own tile texture
# (compositing needs a real pixel buffer, not just a region reference) — same
# approach as CaveWorld._add_wall_icon_source / _build_wall_tile_image.
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

# Creates a TileSet with dimmed versions of crystal ore tiles (for the regen system)
static func _get_dimmed_ore_tile_set() -> TileSet:
	var ts := TileSet.new()
	ts.tile_size = Vector2i(TILE_SIZE, TILE_SIZE)
	ts.add_physics_layer()
	ts.set_physics_layer_collision_layer(0, 1)
	ts.set_physics_layer_collision_mask(0, 1)
	
	var crystal_ores = [
		PixieCaveGenerator.Tile.CRYSTAL_COPPER,
		PixieCaveGenerator.Tile.CRYSTAL_IRON,
		PixieCaveGenerator.Tile.CRYSTAL_SILICON,
		PixieCaveGenerator.Tile.CRYSTAL_DIAMOND,
	]
	
	for ore_type in crystal_ores:
		var item: ItemData = load(WALL_ITEM_PATHS[ore_type]) as ItemData
		if item == null or item.icon == null:
			continue
		
		# Create dimmed version of the icon
		var icon_img: Image
		var atlas_tex := item.icon as AtlasTexture
		if atlas_tex != null and atlas_tex.atlas != null:
			var full_img: Image = atlas_tex.atlas.get_image()
			var region := Rect2i(Vector2i(atlas_tex.region.position.round()), Vector2i(atlas_tex.region.size.round()))
			icon_img = full_img.get_region(region)
		else:
			icon_img = item.icon.get_image()
		
		icon_img = icon_img.duplicate()
		icon_img.convert(Image.FORMAT_RGBA8)
		
		# Darken the image (multiply RGB by 0.3)
		for y in range(icon_img.get_height()):
			for x in range(icon_img.get_width()):
				var c: Color = icon_img.get_pixel(x, y)
				c.r *= 0.3
				c.g *= 0.3
				c.b *= 0.3
				icon_img.set_pixel(x, y, c)
		
		var tex := ImageTexture.create_from_image(icon_img)
		var src := TileSetAtlasSource.new()
		src.texture = tex
		src.texture_region_size = Vector2i(TILE_SIZE, TILE_SIZE)
		src.create_tile(Vector2i.ZERO)
		var source_id: int = ts.add_source(src)
		
		_dimmed_ore_cells[ore_type] = {"source": source_id, "coord": Vector2i.ZERO}
	
	return ts

# ── Paint the generated grid into the TileMapLayer ─────────────────────
func _paint_tiles() -> void:
	for x in range(generator.width):
		for y in range(generator.height):
			var grid_pos := Vector2i(x, y)
			_paint_cell(_grid_to_cell(grid_pos), generator.grid[x][y], grid_pos)
			# Add glow light for crystal ores
			var tile_type: int = generator.grid[x][y]
			if tile_type in [PixieCaveGenerator.Tile.CRYSTAL_COPPER, PixieCaveGenerator.Tile.CRYSTAL_IRON, PixieCaveGenerator.Tile.CRYSTAL_SILICON, PixieCaveGenerator.Tile.CRYSTAL_DIAMOND]:
				_add_ore_light(_grid_to_cell(grid_pos), tile_type)
	_paint_surrounding_walls()

# One 32x32 frame of the glowing orbs strip, extracted as a standalone texture
# (the particle sprite). Cached once and shared by every firefly emitter.
static func _get_orb_texture() -> Texture2D:
	if _orb_texture != null:
		return _orb_texture
	var img: Image = ORE_ORBS_TEX.get_image()
	if img == null:
		return null
	img = img.get_region(Rect2i(0, 0, ORE_ORBS_FRAME_SIZE, ORE_ORBS_FRAME_SIZE))
	_orb_texture = ImageTexture.create_from_image(img)
	return _orb_texture

# Builds one firefly emitter. The particles flow AROUND the emitter (a slight
# tangential acceleration curls them into a short orbit around the ore/wall
# point instead of lingering in place), and each one PULSES — growing then
# shrinking in size and opacity over its lifetime — for a breathing, flowing
# look. GPUParticles2D have no collision, so fireflies pass through everything.
func _make_firefly_emitter(amount: int) -> GPUParticles2D:
	var f := GPUParticles2D.new()
	f.texture = _get_orb_texture()
	f.amount = amount
	f.lifetime = 2.0
	f.preprocess = 0.8
	f.local_coords = false
	f.z_index = -298  # above the tilemap/light
	f.emitting = true
	var fm := ParticleProcessMaterial.new()
	fm.direction = Vector3(0, -1, 0)
	fm.spread = 180.0
	fm.gravity = Vector3.ZERO
	# Flow AROUND the ore: particles spawn on a ring around the emitter and
	# drift gently outward — never lingering on the tile itself.
	fm.initial_velocity_min = 4.0
	fm.initial_velocity_max = 9.0
	fm.scale_min = FIREFLY_SCALE_MIN
	fm.scale_max = FIREFLY_SCALE_MAX
	# Pulsating flow: each particle grows then shrinks over its lifetime.
	var curve := Curve.new()
	curve.add_point(Vector2(0.0, 0.45))
	curve.add_point(Vector2(0.5, 1.0))
	curve.add_point(Vector2(1.0, 0.45))
	var curve_tex := CurveTexture.new()
	curve_tex.curve = curve
	fm.scale_curve = curve_tex
	var grad := Gradient.new()
	grad.colors  = PackedColorArray([Color(1, 1, 1, 0.15), Color(1, 1, 1, 1.0), Color(1, 1, 1, 0.15)])
	grad.offsets = PackedFloat32Array([0.0, 0.5, 1.0])
	var ramp := GradientTexture1D.new()
	ramp.gradient = grad
	fm.color_ramp = ramp
	fm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
	fm.emission_ring_radius = 10.0
	f.process_material = fm
	return f

# Fireflies hugging the cave's interior wall surfaces: every pixie-stone wall
# tile that borders an open floor cell gets a chance to host a tiny emitter.
# Sampled down to WALL_FIREFLY_MAX_EMITTERS so node/particle counts stay
# mobile-friendly.
func _spawn_wall_fireflies() -> void:
	var edge_cells: Array = []
	for x in range(generator.width):
		for y in range(generator.height):
			if generator.grid[x][y] == PixieCaveGenerator.Tile.WALL and _has_floor_neighbor(x, y):
				edge_cells.append(_grid_to_cell(Vector2i(x, y)))
	if edge_cells.is_empty():
		return
	var step: int = maxi(1, ceili(float(edge_cells.size()) / WALL_FIREFLY_MAX_EMITTERS))
	var count := 0
	var i := 0
	while i < edge_cells.size() and count < WALL_FIREFLY_MAX_EMITTERS:
		var f := _make_firefly_emitter(FIREFLY_AMOUNT_WALL)
		add_child(f)
		f.global_position = _tilemap.to_global(_tilemap.map_to_local(edge_cells[i] as Vector2i))
		count += 1
		i += step

func _has_floor_neighbor(x: int, y: int) -> bool:
	for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var nx: int = x + d.x
		var ny: int = y + d.y
		if nx < 0 or ny < 0 or nx >= generator.width or ny >= generator.height:
			continue
		if generator.grid[nx][ny] == PixieCaveGenerator.Tile.FLOOR:
			return true
	return false

func _add_ore_light(cell_pos: Vector2i, ore_type: int) -> void:
	var light := PointLight2D.new()
	light.texture = _get_light_texture()
	light.texture_scale = (ORE_GLOW_RADIUS_PX * 2.0) / float(LIGHT_TEXTURE_SIZE)
	light.energy = ORE_GLOW_ENERGY
	# Color the light based on ore type
	match ore_type:
		PixieCaveGenerator.Tile.CRYSTAL_COPPER:
			light.color = Color(0.9, 0.6, 0.3)  # copper orange
		PixieCaveGenerator.Tile.CRYSTAL_IRON:
			light.color = Color(0.7, 0.7, 0.8)  # iron blue-gray
		PixieCaveGenerator.Tile.CRYSTAL_SILICON:
			light.color = Color(0.4, 0.8, 0.9)  # silicon cyan
		PixieCaveGenerator.Tile.CRYSTAL_DIAMOND:
			light.color = Color(0.9, 0.9, 1.0)  # diamond white-blue
	light.z_index = -299  # just above the tilemap
	add_child(light)
	light.global_position = _tilemap.to_global(_tilemap.map_to_local(cell_pos))
	_ore_lights[cell_pos] = light

	# Fireflies drifting around the available ore (tiny 8px glowing specks).
	var f := _make_firefly_emitter(FIREFLY_AMOUNT_ORE)
	add_child(f)
	f.global_position = _tilemap.to_global(_tilemap.map_to_local(cell_pos))
	_ore_fireflies[cell_pos] = f

# 128-tile band of pixie stone on all four sides closes the void around the
# (non-square) grid — the generator already treats out-of-bounds as solid
# (_cell_is_wall), so this is purely visual. Matches CaveWorld/DungeonWorld.
func _paint_surrounding_walls() -> void:
	var cell: Dictionary = _wall_cells.get(PixieCaveGenerator.Tile.WALL, {})
	if cell.is_empty():
		return
	var half_x: int = generator.width / 2
	var half_y: int = generator.height / 2
	var band:  int = SURROUND_BAND_TILES
	for cx in range(-(half_x + band), half_x + band):
		for cy in range(-(half_y + band), half_y + band):
			if cx >= -half_x and cx < half_x and cy >= -half_y and cy < half_y:
				continue  # inside the generated grid — already painted
			_tilemap.set_cell(Vector2i(cx, cy), cell["source"], cell["coord"])

func _paint_cell(cell_pos: Vector2i, tile_type: int, grid_pos: Vector2i) -> void:
	var cell: Dictionary
	if tile_type == PixieCaveGenerator.Tile.FLOOR:
		cell = _floor_cells[_floor_variant_index(grid_pos)] if not _floor_cells.is_empty() else {}
	else:
		cell = _wall_cells.get(tile_type, {})
	if cell.is_empty():
		return
	_tilemap.set_cell(cell_pos, cell["source"], cell["coord"])

func _floor_variant_index(grid_pos: Vector2i) -> int:
	var h: int = (grid_pos.x * 92821) ^ (grid_pos.y * 68917)
	return absi(h) % _floor_cells.size()

# ── Pixie mobs ─────────────────────────────────────────────────────
# Spawns a few pixies on the cave's PATHWAY (floor) tiles. The cave has no
# day/night cycle, so they're present regardless of the time of day — this is
# what "spawn near pixie caves regardless of the day and time" means.
# Placement is deterministic per cave (seeded from _seed) and picks distinct
# floor cells so pixies never start inside the ore walls.
func _spawn_pixies() -> void:
	var path_cells: Array = []
	for x in range(generator.width):
		for y in range(generator.height):
			if generator.grid[x][y] == PixieCaveGenerator.Tile.FLOOR:
				path_cells.append(_grid_to_cell(Vector2i(x, y)))
	if path_cells.is_empty():
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = _seed
	var chosen: Array = path_cells.duplicate()
	var count: int = mini(PIXIE_SPAWN_COUNT, chosen.size())
	for i in range(count):
		# Pick a distinct floor cell (partial Fisher-Yates on the copy).
		var idx: int = rng.randi_range(i, chosen.size() - 1)
		var tmp = chosen[i]
		chosen[i] = chosen[idx]
		chosen[idx] = tmp
		var path_cell: Vector2i = chosen[i] as Vector2i
		var inst: Node2D = PIXIE_SCENE.instantiate()
		add_child(inst)
		inst.global_position = _tilemap.to_global(_tilemap.map_to_local(path_cell)) \
			+ Vector2(rng.randf_range(-6.0, 6.0), rng.randf_range(-6.0, 6.0))

func _spawn_exit_marker() -> void:
	var exit_portal := CavePortal.new()
	exit_portal.mode = CavePortal.Mode.EXIT
	add_child(exit_portal)
	exit_portal.global_position = _tilemap.to_global(
		_tilemap.map_to_local(_grid_to_cell(generator.entrance_tile)))

# ── Mystical darkness (dim ambient only) ───────────────
func _setup_darkness() -> void:
	var ambient := CanvasModulate.new()
	ambient.color = PIXIE_AMBIENT_COLOR
	add_child(ambient)
	add_child(_build_glow_environment())

func _build_glow_environment() -> WorldEnvironment:
	var world_env := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode   = Environment.BG_CANVAS
	env.glow_enabled       = true
	env.glow_intensity     = 0.9
	env.glow_strength      = 1.1
	env.glow_bloom         = 0.15
	env.glow_hdr_threshold = 0.85
	env.glow_blend_mode    = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	world_env.environment = env
	return world_env

static func _get_light_texture() -> Texture2D:
	return Global.get_pixelated_light_texture(LIGHT_TEXTURE_SIZE)
