extends Node2D

enum Terrain { Water, Plain, Desert, Snowy }

const WATER_THRESHOLD: float = 0.33
const SNOW_THRESHOLD: float = 0.38
const SAND_THRESHOLD: float = 0.2

@export var seed: int = 1234
@export var width: int = 1024
@export var height: int = 1024

var current_seed: int:
	get:
		current_seed = rand_from_seed(current_seed)[0]
		return current_seed
var humidity: FastNoiseLite = FastNoiseLite.new()
var temperature: FastNoiseLite = FastNoiseLite.new()
var altitude: FastNoiseLite = FastNoiseLite.new()

@onready var water_layer: TileMapLayer = $Water
@onready var ground_layer: TileMapLayer = $Ground

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	current_seed = seed
	_set_up_noise(humidity, current_seed, 0.003)
	_set_up_noise(temperature, current_seed, 0.001)
	_set_up_noise(altitude, current_seed, 0.005)
	
	var cell_offset = Vector2i(width, height) / 2
	for x in range(width):
		for y in range(height):
			var cell = Vector2i(x, y)
			var distance_from_spawn = clampf(1 - (cell.distance_to(cell_offset) / 128), 0, 1)
			var humid = humidity.get_noise_2d(x, y) * 0.5 + 0.5
			var temp = temperature.get_noise_2d(x, y) * 0.5 + 0.5 + distance_from_spawn * SNOW_THRESHOLD
			var alt = altitude.get_noise_2d(x, y) * 0.5 + 0.5 + distance_from_spawn * WATER_THRESHOLD
			
			match _get_tile_type(humid, temp, alt):
				Terrain.Plain:
					ground_layer.set_cell(cell - cell_offset, 0, Vector2i(0, 1))
				Terrain.Desert:
					ground_layer.set_cell(cell - cell_offset, 0, Vector2i(1, 0))
				Terrain.Snowy:
					ground_layer.set_cell(cell - cell_offset, 0, Vector2i(1, 1))
				_:
					water_layer.set_cell(cell - cell_offset, 0, Vector2i.ZERO)

func _set_up_noise(noise: FastNoiseLite, seed: int, frequency: float, type: FastNoiseLite.FractalType = 1):
	noise.fractal_type = type
	noise.seed = seed
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

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass
