extends Node2D

# experimental tiling variables
const TILE_SIZE = 32
# Tree scene (loaded once, reused for all placements)
const TREE_SCENE: PackedScene = preload("res://scenes/objects/Tree.tscn")

enum Terrain { Water, Plain, Desert, Snowy }
@export var player: CharacterBody2D

# spawn center
var spawn_center: Vector2

# For Terrain Gen
const WATER_THRESHOLD: float = 0.33
const SNOW_THRESHOLD: float  = 0.38
const SAND_THRESHOLD: float  = 0.2
const FORCED_PLAINS_RADIUS: float = 128

# For Foliage Gen
const FOLIAGE_SPACING: float       = 16   # base Poisson min-distance (in tiles)
const SPAWN_CLEAR_TILES: int       = 8    # tree-free radius around map centre (tiles)
const REJECTION_THRESHOLD: int     = 30
const FOREST_CLUSTER_CHANCE: float = 0.70  # % of plain/snowy base trees that seed a cluster
const CLUSTER_EXTRA_MIN: int       = 3    # min extra trees per cluster
const CLUSTER_EXTRA_MAX: int       = 7    # max extra trees per cluster
const CLUSTER_RADIUS_TILES: int    = 4    # how many tiles out a cluster can spread

# For Large Forest Gen (plains and snowy only)
const LARGE_FOREST_MIN_SEP:   int   = 100  # minimum tile distance between forest centers
const LARGE_FOREST_R_MIN:     int   = 15   # min radius of a large forest (tiles)
const LARGE_FOREST_R_MAX:     int   = 30   # max radius of a large forest (tiles)
const LARGE_FOREST_COUNT_MIN: int   = 6    # fewest forests to place
const LARGE_FOREST_COUNT_MAX: int   = 12   # most forests to place
const LARGE_FOREST_ATTEMPTS:  int   = 600  # random placement tries before giving up
const LARGE_FOREST_D_CENTER:  float = 0.80 # tree probability at forest center
const LARGE_FOREST_D_EDGE:    float = 0.20 # tree probability at forest edge

# Exports
@export var random_seed: int = 1234
@export var width:  int = 1024
@export var height: int = 1024

# RNG
var rng: RandomNumberGenerator = RandomNumberGenerator.new()

# Noise maps
var humidity:    FastNoiseLite = FastNoiseLite.new()
var temperature: FastNoiseLite = FastNoiseLite.new()
var altitude:    FastNoiseLite = FastNoiseLite.new()

# Tilemaps
@onready var water_layer:    TileMapLayer = $Water
@onready var ground_layer:   TileMapLayer = $Ground
@onready var editable_layer: TileMapLayer = $Editable

# ── Block placement ──────────────────────────────────────────────
# Ghost highlight — shows a transparent preview of the block before placement
var ghost: Node2D = null
var ghost_sprite: Sprite2D = null
var ghost_last_type: String = ""  # tracks when item changes so we can rebuild sprite

var _grid_overlay:       Node2D = null
var _cursor_highlight:   Node2D = null

# Tracks occupied cells so we never double-place (cell → Node2D)
var _placed_blocks: Dictionary = {}
# Positions of trees destroyed this session (for save/load)
var _removed_trees: Array = []

# Valid item_type values that are allowed to be placed
const PLACEABLE_TYPES = ["block", "door"]

# ── Placement radius (3 tiles) ───────────────────────────────────
const PLACE_RADIUS_TILES:  int   = 6
const INTERACT_RADIUS_PX:  float = 64.0

func _ready() -> void:
	y_sort_enabled = true   # trees (and all Node2D children) sort by Y automatically
	# Keep terrain layers always behind trees/objects regardless of y position
	ground_layer.z_index = -1
	water_layer.z_index  = -1
	rng.set_seed(random_seed)
	_set_up_noise(humidity,    0.003)
	_set_up_noise(temperature, 0.002)
	_set_up_noise(altitude,    0.005)
	_generate_terrain()
	_place_foliage()
	Global.world_node = self
	if not Global.pending_world_data.is_empty():
		apply_world_save_data(Global.pending_world_data)
		Global.pending_world_data.clear()
	_setup_ghost()
	_setup_grid_overlay()
	_setup_cursor_highlight()
	# Listen for hotbar changes so ghost updates immediately on item switch
	Global.hotbar_selection_changed.connect(_on_hotbar_changed)
	Global.Hotbar_updated.connect(_on_hotbar_changed)

func _setup_ghost():
	# Ghost lives in world space (child of World node) so coordinates match editable_layer
	ghost = Node2D.new()
	ghost.visible = false
	ghost.z_index = 10
	add_child(ghost)
	ghost_sprite = Sprite2D.new()
	ghost_sprite.modulate = Color(1, 1, 1, 0.5)
	ghost.add_child(ghost_sprite)

# ── Grid overlay ─────────────────────────────────────────────────
func _setup_grid_overlay() -> void:
	_grid_overlay = Node2D.new()
	_grid_overlay.z_index = 0
	_grid_overlay.visible = false
	editable_layer.add_child(_grid_overlay)
	_grid_overlay.draw.connect(_on_grid_draw)
	Global.block_mode_changed.connect(func(enabled: bool) -> void:
		_grid_overlay.visible = enabled
		if enabled:
			_grid_overlay.queue_redraw()
	)

func _on_grid_draw() -> void:
	var p: Node2D = _get_player()
	if p == null:
		return
	var player_tile: Vector2i = editable_layer.local_to_map(editable_layer.to_local(p.global_position))
	var half: float = TILE_SIZE * 0.5
	for dx in range(-PLACE_RADIUS_TILES, PLACE_RADIUS_TILES + 1):
		for dy in range(-PLACE_RADIUS_TILES, PLACE_RADIUS_TILES + 1):
			var cell: Vector2i = player_tile + Vector2i(dx, dy)
			if not _is_cell_in_place_radius(cell):
				continue
			if _placed_blocks.has(cell) or editable_layer.get_cell_source_id(cell) != -1:
				continue
			var cp: Vector2 = editable_layer.map_to_local(cell)
			var rect := Rect2(cp.x - half, cp.y - half, TILE_SIZE, TILE_SIZE)
			var color: Color = Color(1.0, 0.2, 0.2, 0.55) if _cell_blocked_by_player(cell) \
				else Color(1.0, 1.0, 1.0, 0.45)
			_grid_overlay.draw_rect(rect, color, false, 1.0)

# ── Input ────────────────────────────────────────────────────────
func _input(event):
	# CTRL toggles block-placement mode on/off
	if event is InputEventKey and event.keycode == KEY_CTRL:
		if event.pressed and not event.echo:
			Global.block_mode = not Global.block_mode
			if not Global.block_mode:
				ghost.visible = false
			Global.block_mode_changed.emit(Global.block_mode)
		return

	# Only allow placement while block mode is active
	if not Global.block_mode:
		return

	if event.is_action_pressed("mouse_left"):
		place_block()

func _process(_delta: float) -> void:
	_update_ghost()
	_update_hover()
	_update_cursor_highlight()
	if Global.block_mode and _grid_overlay != null:
		_grid_overlay.queue_redraw()

func _setup_cursor_highlight() -> void:
	_cursor_highlight = Node2D.new()
	_cursor_highlight.z_index = 10
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
	var mouse_local: Vector2  = ground_layer.get_local_mouse_position()
	var cell:        Vector2i = ground_layer.local_to_map(mouse_local)
	var snapped:     Vector2  = ground_layer.map_to_local(cell)
	_cursor_highlight.global_position = ground_layer.to_global(snapped)
	_cursor_highlight.visible = true

func _update_hover() -> void:
	if Global.block_mode:
		Global.set_hover("")
		return
	var mouse_pos: Vector2 = get_global_mouse_position()
	var best_name: String  = ""
	var best_dist: float   = INTERACT_RADIUS_PX
	for entry in _placed_blocks.values():
		var node: Node2D = (entry as Dictionary)["node"] as Node2D
		if not is_instance_valid(node):
			continue
		var dist: float = mouse_pos.distance_to(node.global_position)
		if dist < best_dist:
			best_dist = dist
			best_name = (entry as Dictionary)["name"]
	Global.set_hover(best_name)

# ── Ghost highlight ──────────────────────────────────────────────
func _is_placeable_item(item) -> bool:
	if item == null or not (item is Dictionary) or not item.has("data"):
		return false
	return (item["data"] as ItemData).is_placeable

func _update_ghost():
	# Ghost only shows when block mode is active AND a placeable item is selected
	if not Global.block_mode:
		ghost.visible = false
		return

	var item = Global.get_hotbar_item()
	if not _is_placeable_item(item):
		ghost.visible = false
		return

	# Rebuild sprite if the selected item changed
	var item_key: String = (item["data"] as ItemData).item_name
	if item_key != ghost_last_type:
		ghost_last_type = item_key
		_rebuild_ghost_sprite(item)

	# All tile lookups use editable_layer local space — get mouse pos in that space
	var mouse_local: Vector2  = editable_layer.get_local_mouse_position()
	var cell:        Vector2i = editable_layer.local_to_map(mouse_local)
	var world_pos:   Vector2  = editable_layer.map_to_local(cell)
	ghost.global_position = editable_layer.to_global(world_pos)

	# Out of range — hide ghost entirely
	if not _is_cell_in_place_radius(cell):
		ghost.visible = false
		return

	ghost.visible = true

	var occupied:    bool = _placed_blocks.has(cell) or editable_layer.get_cell_source_id(cell) != -1
	var player_here: bool = _cell_blocked_by_player(cell)
	if occupied or player_here:
		ghost_sprite.modulate = Color(1.0, 0.3, 0.3, 0.5)
	else:
		ghost_sprite.modulate = Color(1.0, 1.0, 1.0, 0.5)

func _rebuild_ghost_sprite(item: Dictionary) -> void:
	var data: ItemData = item["data"] as ItemData
	var tex: Texture2D = data.placeable_sprite if data.placeable_sprite != null else data.icon
	ghost_sprite.texture  = tex
	ghost_sprite.hframes  = 1
	ghost_sprite.vframes  = 1
	ghost_sprite.frame    = 0
	ghost_sprite.position = Vector2.ZERO

func _on_hotbar_changed(_idx = 0):
	_update_ghost()

# ── Block placement ──────────────────────────────────────────────
func place_block():
	var item = Global.get_hotbar_item()

	# Only allow blocks and doors
	if not _is_placeable_item(item):
		print("Cannot place '%s' — not a block or door." % item.get("type", "none") if item else "No item selected.")
		return

	var mouse_pos = editable_layer.get_local_mouse_position()
	var cell      = editable_layer.local_to_map(mouse_pos)

	# DEBUG — print what cells the player occupies vs what's being placed
	var _dbg_p: Node2D = _get_player()
	if _dbg_p != null:
		var half_w: float = 10.0 + 8.0
		var half_h: float = 16.5 + 8.0
		var pl: Vector2 = editable_layer.to_local(_dbg_p.global_position) + Vector2(0.0, 6.5)
		var tl: Vector2i = editable_layer.local_to_map(pl + Vector2(-half_w, -half_h))
		var br: Vector2i = editable_layer.local_to_map(pl + Vector2( half_w,  half_h))
		print("DEBUG place_block: click_cell=%s  player_local=%s  tl=%s  br=%s  blocked=%s" % [cell, pl, tl, br, _cell_blocked_by_player(cell)])

	# Enforce placement radius
	if not _is_cell_in_place_radius(cell):
		print("Cell is out of placement radius.")
		return

	# Block placement on tiles the player is currently standing on
	if _cell_blocked_by_player(cell):
		print("Cell is blocked by player.")
		return

	# Don't place on an already occupied cell
	if _placed_blocks.has(cell) or editable_layer.get_cell_source_id(cell) != -1:
		print("Cell already occupied.")
		return

	# Snap world position to tile center
	var world_pos = editable_layer.map_to_local(cell)

	var item_data: ItemData = item["data"] as ItemData
	if item_data == null:
		print("ERROR: ItemData is null")
		return

	var scene_path: String = item_data.place_scene_path
	if scene_path == "" or scene_path == null:
		print("ERROR: No place_scene_path set on item — cannot place.")
		return

	if not ResourceLoader.exists(scene_path):
		print("ERROR: Scene path does not exist: ", scene_path)
		return

	var obj_scene: PackedScene = load(scene_path)
	if obj_scene == null:
		print("ERROR: Failed to load scene: ", scene_path)
		return

	var obj: Node = obj_scene.instantiate()
	if obj == null:
		print("ERROR: Failed to instantiate scene: ", scene_path)
		return

	# Pass ItemData so generic PlaceableBlock can set its sprite
	if obj.has_method("setup"):
		obj.call("setup", item_data)
	else:
		print("WARNING: Object does not have 'setup' method: ", scene_path)

	# Register this cell so overlaps are blocked
	_placed_blocks[cell] = {"node": obj, "name": item_data.item_name}

	# Let the block unregister itself when broken
	if obj.has_method("set_world_cell"):
		obj.call("set_world_cell", cell, self)
	else:
		print("WARNING: Object does not have 'set_world_cell' method: ", scene_path)

	# Add to editable_layer BEFORE setting position
	editable_layer.add_child(obj)

	# Object may have freed itself during _ready() — guard before any further access
	if not is_instance_valid(obj):
		print("ERROR: Object freed itself during _ready(). Check the placed object's script.")
		_placed_blocks.erase(cell)
		return

	# obj is a child of editable_layer so world_pos (from map_to_local) is already local space
	obj.position = world_pos

	_fix_sprite_offset(obj)

	# Play placement animation if configured
	if item_data.has_place_animation and item_data.place_animation_name != "":
		var anim_player: AnimationPlayer = obj.get_node_or_null("AnimationPlayer") as AnimationPlayer
		if anim_player != null:
			anim_player.play(item_data.place_animation_name)
		else:
			print("WARNING: No AnimationPlayer found on object: ", scene_path)
	
	# Consume 1 from inventory
	Global.remove_item(item_data)
	print("Successfully placed block at cell: ", cell)

func unregister_block(cell: Vector2i) -> void:
	_placed_blocks.erase(cell)

func _get_player() -> Node2D:
	if player != null:
		return player as Node2D
	return Global.player_node as Node2D

# Returns true if the given editable_layer cell is within PLACE_RADIUS_TILES of the player
func _is_cell_in_place_radius(cell: Vector2i) -> bool:
	var p: Node2D = _get_player()
	if p == null:
		return true
	var cell_local:   Vector2 = editable_layer.map_to_local(cell)
	var player_local: Vector2 = editable_layer.to_local(p.global_position)
	return player_local.distance_to(cell_local) <= PLACE_RADIUS_TILES * TILE_SIZE

# Returns true if the cell overlaps the player's body footprint.
# Everything stays in editable_layer local space to match local_to_map.
func _cell_blocked_by_player(cell: Vector2i) -> bool:
	var p: Node2D = _get_player()
	if p == null:
		return false

	# Player collision rect: 20 wide × 33 tall, offset (0, 6.5), plus padding
	var half_w: float = 10.0 + 8.0   # 18 px
	var half_h: float = 16.5 + 8.0   # 24.5 px
	var player_local: Vector2 = editable_layer.to_local(p.global_position) + Vector2(0.0, 6.5)

	# Get tile span the rect covers, all in editable_layer local space
	var tl: Vector2i = editable_layer.local_to_map(player_local + Vector2(-half_w, -half_h))
	var br: Vector2i = editable_layer.local_to_map(player_local + Vector2( half_w,  half_h))

	return cell.x >= mini(tl.x, br.x) and cell.x <= maxi(tl.x, br.x) \
		and cell.y >= mini(tl.y, br.y) and cell.y <= maxi(tl.y, br.y)

# ── Terrain Generation ───────────────────────────────────────────
func _generate_terrain():
	var cell_offset = Vector2i(width, height) / 2
	for x in width:
		for y in height:
			var cell = Vector2i(x, y)
			var distance_from_spawn  = cell.distance_to(cell_offset)
			var plains_spawn_circle  = clampf(1 - distance_from_spawn / FORCED_PLAINS_RADIUS, 0, 1)
			var water_circle         = smoothstep(width / 2 - 50, width / 2, distance_from_spawn)
			var humid = humidity.get_noise_2d(x, y)    * 0.5 + 0.5
			var temp  = temperature.get_noise_2d(x, y) * 0.5 + 0.5
			var alt   = altitude.get_noise_2d(x, y)    * 0.5 + 0.5 + plains_spawn_circle * WATER_THRESHOLD

			alt   = 0.0 if water_circle >= 1 else alt - water_circle * WATER_THRESHOLD
			humid += temp  * plains_spawn_circle
			temp  += SNOW_THRESHOLD * plains_spawn_circle
			humid += (SNOW_THRESHOLD - SAND_THRESHOLD) * plains_spawn_circle

			match _get_tile_type(humid, temp, alt):
				Terrain.Plain:
					ground_layer.set_cell(cell - cell_offset, 0, Vector2i(0, 0))
				Terrain.Desert:
					ground_layer.set_cell(cell - cell_offset, 0, Vector2i(1, 0))
				Terrain.Snowy:
					ground_layer.set_cell(cell - cell_offset, 0, Vector2i(1, 1))
				_:
					water_layer.set_cell(cell - cell_offset, 0, Vector2i(0, 1))

func _set_up_noise(noise: FastNoiseLite, frequency: float, type: FastNoiseLite.FractalType = FastNoiseLite.FractalType.FRACTAL_FBM):
	noise.fractal_type = type
	noise.seed        = rng.randi()
	noise.frequency   = frequency

func _get_tile_type(hum: float, temp: float, alt: float) -> Terrain:
	if alt < WATER_THRESHOLD:
		return Terrain.Water
	var temperament = temp - hum
	if temperament > SAND_THRESHOLD:
		return Terrain.Desert
	if temp < SNOW_THRESHOLD:
		return Terrain.Snowy
	return Terrain.Plain

# ── Foliage ──────────────────────────────────────────────────────
func _place_foliage() -> void:
	var cell_offset: Vector2i = Vector2i(width, height) / 2
	var occupied_tiles: Dictionary = {}

	# ── 1. Large forests (plains and snowy only, one per 100-tile radius) ──
	var forest_centers: Array[Vector2i] = _generate_forest_centers()
	for fc: Vector2i in forest_centers:
		_spawn_dense_forest(fc, occupied_tiles)

	# ── 2. Singular scattered trees (one per Poisson sample, no clusters) ──
	var points: PackedVector2Array = _generate_points()

	for point in points:
		var int_point:  Vector2i = Vector2i(point)
		var tile_coord: Vector2i = int_point - cell_offset
		var src_id: int = ground_layer.get_cell_source_id(tile_coord)
		if src_id == -1:
			continue  # water — skip
		var atlas_coord: Vector2i = ground_layer.get_cell_atlas_coords(tile_coord)

		# ── Biome filter: only Plain and Snowy get trees ─────────
		var tree_type_val: int
		if atlas_coord == Vector2i(0, 0):
			tree_type_val = 0  # Plain
		elif atlas_coord == Vector2i(1, 1):
			tree_type_val = 2  # Snowy
		else:
			continue           # Desert (1,0) or unknown — no trees

		if occupied_tiles.has(tile_coord):
			continue
		if tile_coord.distance_to(Vector2i.ZERO) <= SPAWN_CLEAR_TILES:
			continue
		if _has_water_nearby(tile_coord, 3):
			continue
		occupied_tiles[tile_coord] = true

		var local_pos: Vector2 = ground_layer.map_to_local(tile_coord)
		var world_pos: Vector2 = ground_layer.to_global(local_pos)
		_spawn_tree(world_pos, tree_type_val)
		# Each Poisson point seeds a small random group (1–10 trees total)
		_spawn_scattered_group(tile_coord, tree_type_val, rng.randi_range(0, 9), occupied_tiles)

func _has_water_nearby(tile: Vector2i, radius: int) -> bool:
	var r_sq: int = radius * radius
	for dx in range(-radius, radius + 1):
		for dy in range(-radius, radius + 1):
			if dx * dx + dy * dy > r_sq:
				continue
			if water_layer.get_cell_source_id(tile + Vector2i(dx, dy)) != -1:
				return true
	return false

func _generate_forest_centers() -> Array[Vector2i]:
	var centers: Array[Vector2i] = []
	var target: int  = rng.randi_range(LARGE_FOREST_COUNT_MIN, LARGE_FOREST_COUNT_MAX)
	var half_w: int  = width  / 2
	var half_h: int  = height / 2
	var margin: int  = LARGE_FOREST_R_MAX + 20

	for _attempt in range(LARGE_FOREST_ATTEMPTS):
		if centers.size() >= target:
			break
		var tx: int        = rng.randi_range(-half_w + margin, half_w - margin)
		var ty: int        = rng.randi_range(-half_h + margin, half_h - margin)
		var tile: Vector2i = Vector2i(tx, ty)

		var src_id: int = ground_layer.get_cell_source_id(tile)
		if src_id == -1:
			continue
		var atlas: Vector2i = ground_layer.get_cell_atlas_coords(tile)
		if atlas != Vector2i(0, 0) and atlas != Vector2i(1, 1):
			continue  # desert or unknown — no large forests

		if _has_water_nearby(tile, LARGE_FOREST_R_MAX + 10):
			continue  # forest edge must be ≥10 tiles from water

		if tile.distance_to(Vector2i.ZERO) < SPAWN_CLEAR_TILES + LARGE_FOREST_R_MAX:
			continue

		var too_close: bool = false
		for c: Vector2i in centers:
			if tile.distance_to(c) < LARGE_FOREST_MIN_SEP:
				too_close = true
				break
		if too_close:
			continue

		centers.append(tile)

	return centers

func _spawn_dense_forest(center: Vector2i, occupied_tiles: Dictionary) -> void:
	var src_id: int = ground_layer.get_cell_source_id(center)
	if src_id == -1:
		return
	var biome: Vector2i  = ground_layer.get_cell_atlas_coords(center)
	var tree_type_val: int = 0 if biome == Vector2i(0, 0) else 2
	var radius: int      = rng.randi_range(LARGE_FOREST_R_MIN, LARGE_FOREST_R_MAX)
	var r_sq: float      = float(radius * radius)

	for dx in range(-radius, radius + 1):
		for dy in range(-radius, radius + 1):
			var dist_sq: float = float(dx * dx + dy * dy)
			if dist_sq > r_sq:
				continue
			var tile: Vector2i = center + Vector2i(dx, dy)
			if occupied_tiles.has(tile):
				continue
			if tile.distance_to(Vector2i.ZERO) <= SPAWN_CLEAR_TILES:
				continue
			var t_src: int = ground_layer.get_cell_source_id(tile)
			if t_src == -1:
				continue
			if ground_layer.get_cell_atlas_coords(tile) != biome:
				continue
			if _has_water_nearby(tile, 10):
				continue
			var prob: float = lerp(LARGE_FOREST_D_CENTER, LARGE_FOREST_D_EDGE,
				sqrt(dist_sq) / float(radius))
			if rng.randf() > prob:
				continue
			occupied_tiles[tile] = true
			var local_pos: Vector2 = ground_layer.map_to_local(tile)
			var world_pos: Vector2 = ground_layer.to_global(local_pos)
			_spawn_tree(world_pos, tree_type_val)

func _spawn_tree(world_pos: Vector2, tree_type_val: int) -> void:
	var tree: Node2D = TREE_SCENE.instantiate() as Node2D
	if tree == null:
		print("ERROR: Failed to instantiate tree from TREE_SCENE")
		return
	tree.set("tree_type", tree_type_val)
	tree.global_position = world_pos
	add_child(tree)

# Places `extra` additional trees within a small radius of `origin`.
# Used by the scatter pass so isolated trees form natural-looking groups.
func _spawn_scattered_group(origin: Vector2i, tree_type_val: int, extra: int, occupied_tiles: Dictionary) -> void:
	if extra <= 0:
		return
	const SPREAD: int = 3
	var placed: int   = 0
	var tries:  int   = 0
	while placed < extra and tries < extra * 10:
		tries += 1
		var tile: Vector2i = origin + Vector2i(
			rng.randi_range(-SPREAD, SPREAD),
			rng.randi_range(-SPREAD, SPREAD)
		)
		if tile == origin or occupied_tiles.has(tile):
			continue
		if tile.distance_to(Vector2i.ZERO) <= SPAWN_CLEAR_TILES:
			continue
		if ground_layer.get_cell_source_id(tile) == -1:
			continue
		if _has_water_nearby(tile, 3):
			continue
		occupied_tiles[tile] = true
		var local_pos: Vector2 = ground_layer.map_to_local(tile)
		var world_pos: Vector2 = ground_layer.to_global(local_pos)
		_spawn_tree(world_pos, tree_type_val)
		placed += 1

# Places extra trees on adjacent tile cells around a seed tile.
# All positions are snapped to the tile grid — guarantees one tree per tile.
func _spawn_forest_cluster(seed_tile: Vector2i, tree_type_val: int, occupied: Dictionary) -> void:
	var count: int = rng.randi_range(CLUSTER_EXTRA_MIN, CLUSTER_EXTRA_MAX)
	var radius: int = CLUSTER_RADIUS_TILES

	# Gather candidate tiles in the cluster radius
	var candidates: Array = []
	for dx in range(-radius, radius + 1):
		for dy in range(-radius, radius + 1):
			if dx == 0 and dy == 0:
				continue
			var candidate: Vector2i = seed_tile + Vector2i(dx, dy)
			if occupied.has(candidate):
				continue
			if candidate.distance_to(Vector2i.ZERO) <= SPAWN_CLEAR_TILES:
				continue
			var src_id: int = ground_layer.get_cell_source_id(candidate)
			if src_id == -1:
				continue  # water
			var atlas: Vector2i = ground_layer.get_cell_atlas_coords(candidate)
			# Only allow same biome (plain stays plain, snowy stays snowy)
			if tree_type_val == 0 and atlas != Vector2i(0, 0):
				continue
			if tree_type_val == 2 and atlas != Vector2i(1, 1):
				continue
			candidates.append(candidate)

	# Shuffle candidates and pick up to `count`
	for i in range(candidates.size() - 1, 0, -1):
		var j: int = rng.randi_range(0, i)
		var tmp = candidates[i]
		candidates[i] = candidates[j]
		candidates[j] = tmp

	var placed: int = 0
	for tile in candidates:
		if placed >= count:
			break
		occupied[tile] = true
		var local_pos: Vector2 = ground_layer.map_to_local(tile as Vector2i)
		var world_pos: Vector2 = ground_layer.to_global(local_pos)
		_spawn_tree(world_pos, tree_type_val)
		placed += 1

func _generate_points() -> PackedVector2Array:
	var cell_size   = FOLIAGE_SPACING / sqrt(2)
	var grid_width  = ceili(width  / cell_size)
	var grid_height = ceili(height / cell_size)
	print("grid_width: ", grid_width, " grid_height: ", grid_height)

	var grid: PackedInt32Array = PackedInt32Array()
	grid.resize(grid_width * grid_height)
	grid.fill(-1)

	var points:       PackedVector2Array = PackedVector2Array()
	var spawn_points: PackedInt32Array   = PackedInt32Array()

	var initial_point = Vector2(rng.randf_range(0, width), rng.randf_range(0, height))
	points.append(initial_point)
	spawn_points.append(0)
	grid[_point_to_cell_index(initial_point, cell_size, grid_width, grid_height)] = 0

	while not spawn_points.is_empty():
		var spawn_point_index = rng.randi_range(0, spawn_points.size() - 1)
		spawn_center          = points[spawn_points[spawn_point_index]]
		var point_accepted    = false

		for i in REJECTION_THRESHOLD:
			var r         = rng.randf_range(FOLIAGE_SPACING, FOLIAGE_SPACING * 2)
			var a         = rng.randf() * TAU
			var new_point = spawn_center + Vector2.from_angle(a) * r
			if _is_valid_point(new_point, cell_size, grid_width, grid_height, points, grid):
				spawn_points.append(points.size())
				grid[_point_to_cell_index(new_point, cell_size, grid_width, grid_height)] = points.size()
				points.append(new_point)
				point_accepted = true
				break

		if not point_accepted:
			spawn_points.remove_at(spawn_point_index)

	return points

func _is_valid_point(point: Vector2, cell_size: float, grid_width: int, grid_height: int, points: PackedVector2Array, grid: PackedInt32Array) -> bool:
	if point.x >= 0 and point.x < width and point.y >= 0 and point.y < height:
		var cell_offset = Vector2i(width, height) / 2
		if ground_layer.get_cell_source_id(Vector2i(point) - cell_offset) == -1:
			return false
		var cell_x = floori(point.x / cell_size)
		var cell_y = floori(point.y / cell_size)
		var search_start_x = maxi(0, cell_x - 2)
		var search_end_x   = mini(cell_x + 2, grid_width - 1)
		var search_start_y = maxi(0, cell_y - 2)
		var search_end_y   = mini(cell_y + 2, grid_height - 1)
		for x in range(search_start_x, search_end_x + 1):
			for y in range(search_start_y, search_end_y + 1):
				var point_index = grid[x + y * grid_width]
				if point_index != -1:
					var dist = point.distance_squared_to(points[point_index])
					if dist < FOLIAGE_SPACING * FOLIAGE_SPACING:
						return false
		return true
	return false

func _point_to_cell_index(point: Vector2, cell_size: float, grid_width: int, grid_height: int) -> int:
	var x = floori(point.x / cell_size)
	var y = floori(point.y / cell_size)
	assert(x < grid_width,  "Out of bounds: x")
	assert(y < grid_height, "Out of bounds. y = %.3f. grid_y = %f. cell_size = %f" % [point.y, point.y / cell_size, cell_size])
	return x + y * grid_width

func spawn_player():
	player.position = Vector2(spawn_center)

# ── Tree removal tracking ─────────────────────────────────────────
func notify_tree_removed(world_pos: Vector2) -> void:
	_removed_trees.append({"x": world_pos.x, "y": world_pos.y})

# ── Sprite offset helper (shared by place_block and restore) ──────
func _fix_sprite_offset(obj: Node) -> void:
	var sprite: Node = obj.get_node_or_null("Sprite2D")
	if sprite == null:
		sprite = obj.get_node_or_null("AnimatedSprite2D")
	if sprite == null:
		return
	var frame_height := 0.0
	if sprite is Sprite2D and (sprite as Sprite2D).texture != null:
		frame_height = (sprite as Sprite2D).texture.get_height() \
			/ max((sprite as Sprite2D).vframes, 1)
	elif sprite is AnimatedSprite2D \
			and (sprite as AnimatedSprite2D).sprite_frames != null:
		var frames: SpriteFrames = (sprite as AnimatedSprite2D).sprite_frames
		var anim: StringName     = (sprite as AnimatedSprite2D).animation
		if frames.has_animation(anim) and frames.get_frame_count(anim) > 0:
			var tex: Texture2D = frames.get_frame_texture(anim, 0)
			if tex != null:
				frame_height = tex.get_height()
	if frame_height > 0.0:
		sprite.position = Vector2(0.0, (TILE_SIZE / 2.0) - (frame_height / 2.0))

# ── World save / load ─────────────────────────────────────────────
func get_world_save_data() -> Dictionary:
	var data: Dictionary = {
		"placed_blocks": [],
		"removed_trees": _removed_trees.duplicate(),
	}
	for cell in _placed_blocks:
		var entry: Dictionary = _placed_blocks[cell] as Dictionary
		var node: Node        = entry["node"] as Node
		if not is_instance_valid(node):
			continue
		var idata: ItemData = node.get("item_data") as ItemData
		if idata == null or idata.resource_path.is_empty():
			continue
		var block_entry: Dictionary = {
			"cell_x":       (cell as Vector2i).x,
			"cell_y":       (cell as Vector2i).y,
			"item_path":    idata.resource_path,
			"chest_slots":  null,
			"dungeon_index": null,
		}
		# Chest contents
		if node.has_method("get_items"):
			var slots: Array = node.call("get_items") as Array
			var saved: Array = []
			for slot in slots:
				if slot == null:
					saved.append(null)
				else:
					var sd: ItemData = (slot as Dictionary)["data"] as ItemData
					if sd != null and not sd.resource_path.is_empty():
						saved.append({"path": sd.resource_path, "quantity": (slot as Dictionary)["quantity"]})
					else:
						saved.append(null)
			block_entry["chest_slots"] = saved
		# Dungeon index
		var di = node.get("dungeon_index")
		if di != null:
			block_entry["dungeon_index"] = int(di)
		data["placed_blocks"].append(block_entry)
	return data

func apply_world_save_data(data: Dictionary) -> void:
	# Remove trees that were cut before the last save
	if data.has("removed_trees"):
		for entry in (data["removed_trees"] as Array):
			if not (entry is Dictionary):
				continue
			var pos := Vector2(float(entry["x"]), float(entry["y"]))
			for node in get_tree().get_nodes_in_group("Tree"):
				if not (node is Node2D):
					continue
				if (node as Node2D).global_position.distance_to(pos) < 8.0:
					node.queue_free()
					break
	# Re-place blocks that were placed before the last save
	if not data.has("placed_blocks"):
		return
	for block_data in (data["placed_blocks"] as Array):
		if not (block_data is Dictionary):
			continue
		var bd: Dictionary = block_data as Dictionary
		var cell := Vector2i(int(bd["cell_x"]), int(bd["cell_y"]))
		if _placed_blocks.has(cell):
			continue
		var item_path: String = str(bd.get("item_path", ""))
		if item_path.is_empty() or not ResourceLoader.exists(item_path):
			continue
		var idata: ItemData = load(item_path) as ItemData
		if idata == null:
			continue
		var scene_path: String = idata.place_scene_path
		if scene_path.is_empty() or not ResourceLoader.exists(scene_path):
			continue
		var obj_scene: PackedScene = load(scene_path) as PackedScene
		if obj_scene == null:
			continue
		var obj: Node = obj_scene.instantiate()
		if obj == null:
			continue
		if obj.has_method("setup"):
			obj.call("setup", idata)
		_placed_blocks[cell] = {"node": obj, "name": idata.item_name}
		if obj.has_method("set_world_cell"):
			obj.call("set_world_cell", cell, self)
		editable_layer.add_child(obj)
		if not is_instance_valid(obj):
			_placed_blocks.erase(cell)
			continue
		obj.position = editable_layer.map_to_local(cell)
		_fix_sprite_offset(obj)
		# Restore chest slots
		var chest_slots = bd.get("chest_slots", null)
		if chest_slots is Array:
			var slots_ref = obj.get("slots")
			if slots_ref is Array:
				for i in range(mini((chest_slots as Array).size(), (slots_ref as Array).size())):
					var se = (chest_slots as Array)[i]
					if not (se is Dictionary):
						continue
					var spath: String = str((se as Dictionary).get("path", ""))
					if spath.is_empty() or not ResourceLoader.exists(spath):
						continue
					var res: ItemData = load(spath) as ItemData
					if res != null:
						(slots_ref as Array)[i] = {"data": res, "quantity": int((se as Dictionary).get("quantity", 1))}
			if obj.has_method("_refresh_ui"):
				obj.call("_refresh_ui")
		# Restore dungeon index
		var di = bd.get("dungeon_index", null)
		if di != null:
			obj.set("dungeon_index", int(di))
