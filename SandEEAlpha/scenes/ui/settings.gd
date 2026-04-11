extends Control

@onready var cam_slider = $ColorRect/cam_slider



func _on_cam_slider_value_changed(value: float) -> void:
	var zoom_level = Vector2(value, value)
	$mainCam.zoom = zoom_level
