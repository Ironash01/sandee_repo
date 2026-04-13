@tool
extends Node2D

@export var item_data: ItemData

var scene_path: String = "res://scenes/ui/InventoryItem.tscn"

@onready var icon_sprite: Sprite2D = $Sprite2D

var player_in_range: bool = false

func _ready() -> void:
	if not Engine.is_editor_hint():
		if item_data != null:
			icon_sprite.texture = item_data.icon

func _process(_delta: float) -> void:
	if Engine.is_editor_hint():
		if item_data != null:
			icon_sprite.texture = item_data.icon
		return
	if player_in_range:
		pickup_item()

func pickup_item() -> void:
	if item_data == null:
		return
	if Global.add_item({"quantity": 1, "data": item_data}):
		queue_free()

func set_item_data(data: ItemData) -> void:
	item_data = data
	if icon_sprite:
		icon_sprite.texture = data.icon

func _on_area_2d_body_entered(body: Node2D) -> void:
	if body.is_in_group("Player"):
		player_in_range = true

func _on_area_2d_body_exited(body: Node2D) -> void:
	if body.is_in_group("Player"):
		player_in_range = false
