extends Control

@export var slot_scene: PackedScene 
@onready var grid = $GridContainer

func _ready():
	create_inventory_slots(20) 
	
	# Wait for one frame to ensure nodes are inside the Tree
	await get_tree().process_frame 
	
	var test_item = load("res://resources/items/furnace.tres")
	InventoryManager.add_item(test_item)
	update_inventory_ui()

func create_inventory_slots(amount: int):
	for child in grid.get_children():
		child.queue_free()
	for i in range(amount):
		var new_slot = slot_scene.instantiate()
		grid.add_child(new_slot)

func update_inventory_ui():
	var slots = grid.get_children()
	
	for i in range(slots.size()):
		if i < InventoryManager.inventory_data.size():
			slots[i].display_item(InventoryManager.inventory_data[i])
