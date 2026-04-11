extends Node

# array to hold inventory items
var Inventory = []
var hotbar_selected: int = 0  # tracks which hotbar slot is active (0-8)

var player_node: Node = null
@onready var inventory_slot_scene = preload("res://scenes/ui/InventorySlot.tscn")
signal Inventory_updated
signal hotbar_selection_changed(index)

func _ready():
	Inventory.resize(20)

func add_item(item):
	# First pass: try to stack with existing item of same type+effect
	for i in range(Inventory.size()):
		if Inventory[i] != null and Inventory[i]["type"] == item["type"] and Inventory[i]["effect"] == item["effect"]:
			Inventory[i]["quantity"] += item["quantity"]
			Inventory_updated.emit()
			return true
	# Second pass: find first empty slot
	for i in range(Inventory.size()):
		if Inventory[i] == null:
			Inventory[i] = item
			Inventory_updated.emit()
			return true
	return false  # inventory full

func remove_item(item_type, item_effect):
	for i in range(Inventory.size()):
		if Inventory[i] != null and Inventory[i]["type"] == item_type and Inventory[i]["effect"] == item_effect:
			Inventory[i]["quantity"] -= 1
			if Inventory[i]["quantity"] <= 0:
				Inventory[i] = null
			Inventory_updated.emit()
			return

func get_hotbar_item() -> Variant:
	# Returns the currently selected hotbar item (slots 0-8)
	if hotbar_selected < Inventory.size():
		return Inventory[hotbar_selected]
	return null

func set_hotbar_selection(index: int):
	hotbar_selected = clamp(index, 0, 8)
	hotbar_selection_changed.emit(hotbar_selected)

func increase_inventory_size():
	Inventory_updated.emit()

func set_player_reference(player):
	player_node = player

func adjust_drop_pos(pos):
	var rad = 100
	var near_item = get_tree().get_nodes_in_group("items")
	for item in near_item:
		if item.global_position.distance_to(pos) < rad:
			var random_offset = Vector2(randf_range(-rad, rad), randf_range(-rad, rad))
			pos += random_offset
			break
	return pos

func drop_item(item_data, drop_position):
	var item_scene = load(item_data["scene_path"])
	var item_instance = item_scene.instantiate()
	item_instance.set_item_data(item_data)
	drop_position = adjust_drop_pos(drop_position)
	item_instance.global_position = drop_position
	get_tree().current_scene.add_child(item_instance)
	item_instance.global_transform.origin = drop_position
