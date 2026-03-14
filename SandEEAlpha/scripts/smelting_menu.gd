extends Control

#will avoid setting atlast texture for UI so we can modify as we go.
@export var bg: Texture
@onready var bg_node = $canvas/bg

# implement layerting of FG and BG in the future too.
@export var fg: Texture
@onready var fg_node = $canvas/fg

func _ready() -> void:
	pass
	
	
# IDK WHAT THE FUCK TO DO WITH THIS
func _process(delta: float) -> void:
	pass

func set_textures():
	bg_node = bg
