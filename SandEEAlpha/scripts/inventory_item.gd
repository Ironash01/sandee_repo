@tool
extends Node2D

# item properties:
# type            - category (e.g. "block", "door", "weapon", "material")
# name            - display label
# effect          - what the item does
# texture         - visual
# scene_path      - scene to spawn when DROPPING this item back into the world
# place_scene_path - scene to spawn when PLACING this item on the map (blocks/doors only)

@export var item_type = ""
@export var item_name = ""
@export var item_texture: Texture2D
@export var item_effect = ""

# Scene used when this item is dropped from inventory back into the world
var scene_path: String = "res://scenes/ui/InventoryItem.tscn"

# Scene used when this item is placed on the map (set this for blocks/doors)
# Leave empty for non-placeable items like weapons and materials
@export var place_scene_path: String = ""

@onready var icon_sprite = $Sprite2D

var player_in_range = false

func _ready():
	if not Engine.is_editor_hint():
		icon_sprite.texture = item_texture

func _process(delta):
	if Engine.is_editor_hint():
		icon_sprite.texture = item_texture
		return
	if player_in_range:
		pickup_item()

func pickup_item():
	var item = {
		"quantity": 1,
		"type": item_type,
		"name": item_name,
		"effect": item_effect,
		"texture": item_texture,
		"scene_path": scene_path,
		"place_scene_path": place_scene_path
	}
	if Global.player_node:
		if Global.add_item(item):
			self.queue_free()

func _on_area_2d_body_entered(body: Node2D) -> void:
	if body.is_in_group("Player"):
		player_in_range = true

func _on_area_2d_body_exited(body: Node2D) -> void:
	if body.is_in_group("Player"):
		player_in_range = false

func set_item_data(data: Dictionary):
	item_type         = data.get("type", "")
	item_name         = data.get("name", "")
	item_effect       = data.get("effect", "")
	item_texture      = data.get("texture", null)
	scene_path        = data.get("scene_path", scene_path)
	place_scene_path  = data.get("place_scene_path", "")
	if icon_sprite:
		icon_sprite.texture = item_texture
