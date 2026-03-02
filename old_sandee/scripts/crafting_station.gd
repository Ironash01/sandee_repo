extends Area2D

@export var ui_scene: PackedScene

func highlight():
	modulate = Color(1.2, 1.2, 1.2)
	
func unhighlight():
	modulate = Color(1, 1, 1)
	
func interact():
	print("Opening Crafting UI")
	if ui_scene:
		var menu = ui_scene.instantiate()
		get_tree().root.add_child(menu)
