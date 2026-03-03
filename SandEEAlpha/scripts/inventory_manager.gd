extends Node 

var inventory_data: Array[ItemData] = []

func _ready():
	inventory_data.resize(20)
func add_item(item: ItemData):
	for i in range(inventory_data.size()):
		if inventory_data[i] == null:
			inventory_data[i] = item 
			return true                               
	
	print("Inventory is full!")
	return false
