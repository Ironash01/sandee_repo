extends Node2D

@onready var settings_button = $CanvasLayer/Settings

func _on_paused_pressed() -> void:
	settings_button.visible = true
	
func _input(event):
	if event.is_action_pressed("escape"):
		settings_button.visible = false
