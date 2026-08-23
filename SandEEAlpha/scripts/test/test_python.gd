extends Node2D

@onready var code_editor: CodeEditor = $Control/CodeEditor
@onready var stats_label: Label = $Control/StatsLabel

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	pass # Replace with function body.


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	stats_label.text = "FPS: %.3f" % Engine.get_frames_per_second()

func _on_button_pressed() -> void:
	var script = GDScript.new()
	script.source_code = "var lol = 0.0\n\nfunc test() -> void:\n\tprint(100.0 / lol)"
	var err = script.reload()
	print(err)
