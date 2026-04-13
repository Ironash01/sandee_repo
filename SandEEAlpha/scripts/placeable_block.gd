extends Node2D

# Set automatically by world.gd after instantiation
var item_data: ItemData = null

@onready var _sprite: Sprite2D = $Sprite2D

func _ready() -> void:
	if item_data != null:
		_apply_sprite()

func setup(data: ItemData) -> void:
	item_data = data
	if _sprite != null:
		_apply_sprite()

func _apply_sprite() -> void:
	# Use placeable_sprite if set, otherwise fall back to icon
	var tex: Texture2D = item_data.placeable_sprite \
		if item_data.placeable_sprite != null \
		else item_data.icon
	_sprite.texture = tex
