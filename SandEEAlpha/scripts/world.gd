extends Node2D

# experimental tiling variables
const TILE_SIZE = 32
@export var object: PackedScene

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
const FOLIAGE_SPACING: float   = 16
const REJECTION_THRESHOLD: int = 30

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

# Valid item_type values that are allowed to be placed
const PLACEABLE_TYPES = ["block", "door"]

func _ready() -> void:
	rng.set_seed(random_seed)
	_set_up_noise(humidity,    0.003)
	_set_up_noise(temperature, 0.002)
	_set_up_noise(altitude,    0.005)
	_generate_terrain()
	_place_foliage()
	_setup_ghost()
	# Listen for hotbar changes so ghost updates immediately on item switch
	Global.hotbar_selection_changed.connect(_on_hotbar_changed)
	Global.Inventory_updated.connect(_on_hotbar_changed)

func _setup_ghost():
	# Ghost lives in world space (child of World node) so coordinates match editable_layer
	ghost = Node2D.new()
	ghost.visible = false
	ghost.z_index = 10
	add_child(ghost)
	ghost_sprite = Sprite2D.new()
	ghost_sprite.modulate = Color(1, 1, 1, 0.5)
	ghost.add_child(ghost_sprite)

# ── Input ────────────────────────────────────────────────────────
func _input(event):
	if event.is_action_pressed("mouse_left"):
		place_block()

func _process(_delta):
	_update_ghost()

# ── Ghost highlight ──────────────────────────────────────────────
func _is_placeable_item(item) -> bool:
	if item == null:
		return false
	var t = item.get("type", "").to_lower()
	return t in PLACEABLE_TYPES

func _update_ghost():
	var item = Global.get_hotbar_item()
	if not _is_placeable_item(item):
		ghost.visible = false
		return

	# Rebuild sprite if the selected item changed
	var item_key = item.get("type", "") + item.get("name", "")
	if item_key != ghost_last_type:
		ghost_last_type = item_key
		_rebuild_ghost_sprite(item)

	ghost.visible = true

	# Snap to tile grid in world space
	var mouse_world = get_local_mouse_position()
	var cell        = editable_layer.local_to_map(mouse_world)
	var world_pos   = editable_layer.map_to_local(cell)
	ghost.global_position = editable_layer.to_global(world_pos)

	# Tint: red if occupied, white-transparent if free
	var occupied = editable_layer.get_cell_source_id(cell) != -1
	if occupied:
		ghost_sprite.modulate = Color(1.0, 0.3, 0.3, 0.5)
	else:
		ghost_sprite.modulate = Color(1.0, 1.0, 1.0, 0.5)

func _rebuild_ghost_sprite(item):
	var place_path = item.get("place_scene_path", "")
	if place_path == "" or not ResourceLoader.exists(place_path):
		ghost_sprite.texture = item.get("texture", null)
		ghost_sprite.hframes = 1
		ghost_sprite.vframes = 1
		ghost_sprite.frame   = 0
		ghost_sprite.position = Vector2.ZERO
		return
	var packed = load(place_path)
	if packed == null:
		return
	# Instantiate temporarily to read sprite properties then discard
	var temp = packed.instantiate()
	var src  = temp.get_node_or_null("Sprite2D")
	if src:
		ghost_sprite.texture  = src.texture
		ghost_sprite.hframes  = src.hframes
		ghost_sprite.vframes  = src.vframes
		ghost_sprite.frame    = src.frame
		# Match the same y-offset used in place_block so ghost aligns exactly
		var frame_height = src.texture.get_height() / max(src.vframes, 1)
		var y_offset = (TILE_SIZE / 2.0) - (frame_height / 2.0)
		ghost_sprite.position = Vector2(0, y_offset)
	temp.queue_free()

func _on_hotbar_changed(_idx = 0):
	_update_ghost()

# ── Block placement ──────────────────────────────────────────────
func place_block():
	var item = Global.get_hotbar_item()

	# Only allow blocks and doors
	if not _is_placeable_item(item):
		print("Cannot place '%s' — not a block or door." % item.get("type", "none") if item else "No item selected.")
		return

	var mouse_pos = get_local_mouse_position()
	var cell      = editable_layer.local_to_map(mouse_pos)

	# Don't place on an already occupied cell
	if editable_layer.get_cell_source_id(cell) != -1:
		print("Cell already occupied.")
		return

	# Snap world position to tile center
	var world_pos = editable_layer.map_to_local(cell)

	# Instantiate from the item's place_scene_path (the world object scene)
	var scene_path = item.get("place_scene_path", "")
	if scene_path == "" or not ResourceLoader.exists(scene_path):
		print("No place_scene_path set on item — cannot place.")
		return

	var obj_scene = load(scene_path)
	if obj_scene == null:
		print("Failed to load scene: ", scene_path)
		return

	var obj = obj_scene.instantiate()
	# Add to editable_layer so coordinates match the tilemap space
	editable_layer.add_child(obj)
	# map_to_local returns the tile CENTER in Godot TileMapLayer.
	# Sprite2D is also center-anchored, so global_position = tile center = perfect alignment.
	# We just need to strip out the hand-placed offset on the Sprite2D child (the +8 y shift).
	obj.global_position = editable_layer.to_global(world_pos)
	# Correct the sprite child offset so it sits flush on the grid cell.
	# Sprite2D is center-anchored. For sprites taller than TILE_SIZE,
	# shift up so the bottom of the sprite aligns with the bottom of the tile.
	var sprite = obj.get_node_or_null("Sprite2D")
	if sprite:
		var frame_height = sprite.texture.get_height() / max(sprite.vframes, 1)
		var y_offset = (TILE_SIZE / 2.0) - (frame_height / 2.0)
		sprite.position = Vector2(0, y_offset)

	# Consume 1 from inventory
	Global.remove_item(item["type"], item["effect"])

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
func _place_foliage():
	var points      = _generate_points()
	var cell_offset = Vector2i(width, height) / 2
	for point in points:
		var int_point    = Vector2i(point)
		var terrain_cell = ground_layer.get_cell_tile_data(int_point - cell_offset)
		if terrain_cell != null:
			var terrain_type: Terrain = terrain_cell.get_custom_data("terrain_type")
			match terrain_type:
				Terrain.Plain:
					editable_layer.set_cell(int_point - cell_offset, 0, Vector2i.ZERO)
				Terrain.Desert:
					editable_layer.set_cell(int_point - cell_offset, 0, Vector2i.ZERO)
				Terrain.Snowy:
					editable_layer.set_cell(int_point - cell_offset, 0, Vector2i.ZERO)

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
