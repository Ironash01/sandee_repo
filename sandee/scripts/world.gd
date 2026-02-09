extends Node2D

enum Terrain { Water, Plain, Desert, Snowy }

@export var seed: int = 1234
@export var width: int = 1024
@export var height: int = 1024

var random := rand_from_seed(seed)
var humidity: FastNoiseLite = FastNoiseLite.new()
var temperature: FastNoiseLite = FastNoiseLite.new()

@onready var water_layer: TileMapLayer = $Water
@onready var ground_layer: TileMapLayer = $Ground

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	set_up_noise(humidity, random[0], 0.003, FastNoiseLite.FRACTAL_RIDGED)
	set_up_noise(temperature, random[1], 0.01)
	
	for x in range(width):
		for y in range(height):
			var cell = Vector2i(x, y)
			var humid = humidity.get_noise_2d(x, y)
			var temp = temperature.get_noise_2d(x, y)
			
			match get_tile_type(humid, temp):
				Terrain.Plain:
					ground_layer.set_cell(cell, 0, Vector2i(0, 1))
				Terrain.Desert:
					ground_layer.set_cell(cell, 0, Vector2i(1, 0))
				Terrain.Snowy:
					ground_layer.set_cell(cell, 0, Vector2i(1, 1))
				_:
					water_layer.set_cell(cell, 0, Vector2i.ZERO)

func set_up_noise(noise: FastNoiseLite, seed: int, frequency: float, type: FastNoiseLite.FractalType = 1):
	noise.fractal_type = type
	noise.seed = seed
	noise.frequency = frequency

func get_tile_type(humidity: float, temperature: float) -> Terrain:
	var result: Terrain = Terrain.Plain
	if humidity < 0:
		if temperature < -0.2:
			result = Terrain.Desert
		elif temperature > 0.2:
			result = Terrain.Snowy
	elif humidity < 0.5:
		if temperature > 0.4:
			result = Terrain.Snowy
	else:
		result = Terrain.Water
	return result

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass
