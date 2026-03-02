extends Button


func _on_pressed() -> void:
	print("Button was clicked")
	get_tree().change_scene_to_file("res://scenes//Demo.tscn")
	pass # Replace with function body.
