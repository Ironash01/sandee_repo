extends Node2D

enum Terrain { Water, Plain, Desert, Snowy }

# Thresholds for Terrain Gen
const WATER_THRESHOLD: float = 0.33
const SNOW_THRESHOLD: float = 0.38
const SAND_THRESHOLD: float = 0.2

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
	for x in range(width):
		for y in range(height):
			var cell = Vector2i(x, y)
			var distance_from_spawn = clampf(1 - (cell.distance_to(cell_offset) / 128), 0, 1)
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
	pass
