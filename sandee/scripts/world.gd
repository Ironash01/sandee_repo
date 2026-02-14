extends Node2D

enum Terrain { Water, Plain, Desert, Snowy }

# For Terrain Gen
const WATER_THRESHOLD: float = 0.33
const SNOW_THRESHOLD: float = 0.38
const SAND_THRESHOLD: float = 0.2
const FORCED_PLAINS_RADIUS: float = 128 # range of forced plains area

# For Foliage Gen
const FOLIAGE_SPACING: float = 16 # average spacing between foliage
const REJECTION_THRESHOLD: int = 30 # samples before rejection

# Exports
@export var seed: int = 1234
@export var width: int = 1024
@export var height: int = 1024

# Initialize RNG
var rng: RandomNumberGenerator = RandomNumberGenerator.new()

# Initialize noise maps for Terrain Gen
var humidity: FastNoiseLite = FastNoiseLite.new()
var temperature: FastNoiseLite = FastNoiseLite.new()
var altitude: FastNoiseLite = FastNoiseLite.new()

# Load tilemaps
@onready var water_layer: TileMapLayer = $Water
@onready var ground_layer: TileMapLayer = $Ground
@onready var editable_layer: TileMapLayer = $Editable

func _ready() -> void:
	rng.set_seed(seed)
	
	# Setup noise maps
	_set_up_noise(humidity, 0.003)
	_set_up_noise(temperature, 0.002)
	_set_up_noise(altitude, 0.005)
	
	_generate_terrain()
	_place_foliage()

### Step 1: Terrain Generation
func _generate_terrain():
	var cell_offset = Vector2i(width, height) / 2 # Tilemap center
	
	# Iterate through all cells
	for x in width:
		for y in height:
			var cell = Vector2i(x, y)
			var distance_from_spawn = clampf(1 - (cell.distance_to(cell_offset) / FORCED_PLAINS_RADIUS), 0, 1)
			var humid = humidity.get_noise_2d(x, y) * 0.5 + 0.5
			var temp = temperature.get_noise_2d(x, y) * 0.5 + 0.5
			var alt = altitude.get_noise_2d(x, y) * 0.5 + 0.5 + distance_from_spawn * WATER_THRESHOLD
			
			humid += temp * distance_from_spawn
			temp += SNOW_THRESHOLD * distance_from_spawn
			humid += (SNOW_THRESHOLD - SAND_THRESHOLD) * distance_from_spawn
			
			match _get_tile_type(humid, temp, alt):
				Terrain.Plain:
					ground_layer.set_cell(cell - cell_offset, 0, Vector2i(0, 1))
				Terrain.Desert:
					ground_layer.set_cell(cell - cell_offset, 0, Vector2i(1, 0))
				Terrain.Snowy:
					ground_layer.set_cell(cell - cell_offset, 0, Vector2i(1, 1))
				_:
					water_layer.set_cell(cell - cell_offset, 0, Vector2i.ZERO)

func _set_up_noise(noise: FastNoiseLite, frequency: float, type: FastNoiseLite.FractalType = 1):
	noise.fractal_type = type
	noise.seed = rng.randi()
	noise.frequency = frequency

func _get_tile_type(humidity: float, temperature: float, altitude: float) -> Terrain:	
	var terrain: Terrain = Terrain.Plain
	if altitude < WATER_THRESHOLD:
		terrain = Terrain.Water
	else:
		var temperament = temperature - humidity
		if temperament > SAND_THRESHOLD:
			terrain = Terrain.Desert
		if temperature < SNOW_THRESHOLD:
			terrain = Terrain.Snowy
	return terrain

func _place_foliage():
	var points: PackedVector2Array = _generate_points()
	
	for point in points:
		var int_point = Vector2i(point)
		var cell_offset = Vector2i(width, height) / 2 # Tilemap center
		
		editable_layer.set_cell(int_point - cell_offset, 0, Vector2i.ZERO)

func _generate_points() -> PackedVector2Array:
	# use poisson disc sampling to place foliage
	# based on https://www.cs.ubc.ca/~rbridson/docs/bridson-siggraph07-poissondisk.pdf
	var cell_size: float = FOLIAGE_SPACING / sqrt(2)
	
	# Spatial grid for quick distance checks
	var grid_width: int = ceili(width / cell_size)
	var grid_height: int = ceili(height / cell_size)
	print("grid_width: ", grid_width, " grid_height: ", grid_height)
	var grid: PackedInt32Array = PackedInt32Array()
	grid.resize(grid_width * grid_height)
	grid.fill(-1)
	
	# Points generated
	var points: PackedVector2Array = PackedVector2Array()
	var spawn_points: PackedInt32Array = PackedInt32Array() # points to generate new points from
	
	# Initial point
	var initial_point: Vector2 = Vector2(rng.randf_range(0, width), rng.randf_range(0, height))
	points.append(initial_point)
	spawn_points.append(0)
	grid[_point_to_cell_index(initial_point, cell_size, grid_width, grid_height)] = 0
		
	while not spawn_points.is_empty(): # while there's still points to generate from
		# pick random point from spawn points
		var spawn_point_index: int = rng.randi_range(0, spawn_points.size() - 1)
		var spawn_center: Vector2 = points[spawn_points[spawn_point_index]]
		var point_accepted: bool = false
		
		# until rejection
		for i in REJECTION_THRESHOLD:
			# generate random point r ~ 2r away from spawn point
			var r: float = rng.randf_range(FOLIAGE_SPACING, FOLIAGE_SPACING * 2)
			var a: float = rng.randf() * TAU
			var new_point: Vector2 = spawn_center + Vector2.from_angle(a) * r
			
			if _is_valid_point(new_point, cell_size, grid_width, grid_height, points, grid):
				# add point in if valid and also add as spawn point
				spawn_points.append(points.size())
				grid[_point_to_cell_index(new_point, cell_size, grid_width, grid_height)] = points.size()
				points.append(new_point)
				point_accepted = true
				break
		
		# remove spawn point if nothing was accepted
		if not point_accepted:
			spawn_points.remove_at(spawn_point_index)
				
	return points

func _is_valid_point(point: Vector2, cell_size: float, grid_width: int, grid_height: int, points: PackedVector2Array, grid: PackedInt32Array) -> bool:
	if point.x >= 0 and point.x < width and point.y >= 0 and point.y < height: # check if inside
		# check if in water
		var cell_offset = Vector2i(width, height) / 2
		if ground_layer.get_cell_source_id(Vector2i(point) - cell_offset) == -1:
			return false
		
		# convert to cell coords to get search space
		var cell_x: int = floori(point.x / cell_size)
		var cell_y: int = floori(point.y / cell_size)
		
		var search_start_x: int = maxi(0, cell_x - 2)
		var search_end_x: int = mini(cell_x + 2, grid_width - 1)
		var search_start_y: int = maxi(0, cell_y - 2)
		var search_end_y: int = mini(cell_y + 2, grid_height - 1)
		
		# discard if points are too close
		for x in range(search_start_x, search_end_x + 1):
			for y in range(search_start_y, search_end_y + 1):
				var point_index: int = grid[x + y * grid_width]
				if point_index != -1:
					var dist: float = point.distance_squared_to(points[point_index])
					if dist < FOLIAGE_SPACING * FOLIAGE_SPACING:
						return false
		
		return true
	else: # not inside. not valid
		return false

func _point_to_cell_index(point: Vector2, cell_size: float, grid_width: int, grid_height: int) -> int:
	# Returns the corresponding index for the point
	var x: int = floori(point.x / cell_size)
	var y: int = floori(point.y / cell_size)
	assert(x < grid_width, "Out of bounds: x")
	assert(y < grid_height, "Out of bounds. y = %.3f. grid_y = %f. cell_size = %f" % [point.y, point.y / cell_size, cell_size])
	return x + y * grid_width
