extends Control

var game = load ("res://scenes/game_instance.tscn")

func _on_button_play_pressed() -> void:
	load_scene()

func load_scene() -> void:
	get_tree().change_scene_to_file("res://scenes/game_instance.tscn")
	
