extends Node2D

@onready var code_editor: CodeEditor = $Control/CodeEditor
@onready var python_state: PythonState = $PythonState
@onready var stats_label: Label = $Control/StatsLabel

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	pass # Replace with function body.


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	stats_label.text = "FPS: %.3f" % Engine.get_frames_per_second()
	python_state.code = code_editor.get_code()

func _on_python_state_signal_print(string: String) -> void:
	print(string)

func _on_python_state_code_failed(error: String) -> void:
	print("ERROR: " + error)


func _on_button_pressed() -> void:
	python_state.run_code()
