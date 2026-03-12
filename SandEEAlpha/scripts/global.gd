extends Node

# array to hold inventory items

var Inventory = []

var player_node: Node = null
@onready var inventory_slot_scene = preload("res://scenes/ui/InventorySlot.tscn")
signal Inventory_updated

func _ready():
	Inventory.resize(20) 
	pass

func _process(delta: float) -> void:
	pass

func add_item(item):
	for i in range(Inventory.size()):
		if Inventory[i] != null and Inventory[i]["type"] == item["type"] and Inventory[i]["effect"] == item["effect"]:
			Inventory[i]["quantity"] += item["quantity"]
			Inventory_updated.emit()
			return true
		elif Inventory[i] == null:
			Inventory[i] = item
			Inventory_updated.emit()
			return true
		return false # should not add if any property dos not matc
	
func remove_item(item_type, item_effect):
	for i in range(Inventory.size()):
		if Inventory[i] != null and Inventory[i]["type"] == item_type and Inventory[i]["effect"] == item_effect:
			Inventory[i]["quantity"] -= 1
			if Inventory[i]["quantity"] <= 0:
				Inventory[i] = null
	Inventory_updated.emit()

func increase_inventory_size():
	Inventory_updated.emit()
	
func set_player_reference(player):
	player_node = player
	
func adjust_drop_pos(pos):
	var rad = 100
	var near_item = get_tree().get_nodes_in_group("items")
	for item in near_item:
		if item.global.position.distance_to(pos) < rad:
			var random_offset = Vector2(randf_range(-rad, rad), randf_range(-rad, rad))
			pos += random_offset
			break
	return pos
	
