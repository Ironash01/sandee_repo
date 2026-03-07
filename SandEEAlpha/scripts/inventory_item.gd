@tool
extends Node2D


# item property 
# type - castegory
# identifier - label
# effect - what the item does
# texture - visual	

@export var item_type = ""
@export var item_name = ""
@export var item_texture: Texture
@export var item_effect = ""

var scene_path: String = "res://scenes/ui/InventoryItem.tscn"

@onready var icon_sprite = $Sprite2D

# check if player collides with the area2d
var player_in_range = false

func _ready():
	if not Engine.is_editor_hint():
		icon_sprite.texture = item_texture
		
func _process(delta):
	if Engine.is_editor_hint():
		icon_sprite.texture = item_texture
		
	if player_in_range:
		pickup_item()
		
func pickup_item():
	var item = {
		"quantity": 1, # amount of item to be passed
		"type": item_type,
		"name": item_name,
		"effect": item_effect,
		"texture": item_texture,
		"scene_path": scene_path
	}
	if Global.player_node:
		Global.add_item(item)
		self.queue_free()


func _on_area_2d_body_entered(body: Node2D) -> void:
	if body.is_in_group("Player"):
		print("col")
		player_in_range = true


func _on_area_2d_body_exited(body: Node2D) -> void:
	if body.is_in_group("Player"):
		print("col")
		player_in_range = false
