extends Node2D

@onready var code_editor: CodeEditor = $Control/CodeEditor
@onready var stats_label: Label = $Control/StatsLabel
@onready var python_state: PythonState = $PythonState

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	pass # Replace with function body.


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(_delta: float) -> void:
	stats_label.text = "FPS: %.3f" % Engine.get_frames_per_second()
	
func foo():
	print("foo")

func _on_button_pressed() -> void:
	python_state.code = code_editor.get_code()
	python_state.run_code()


func _on_python_state_signal_print(output: String) -> void:
	print(output)


func _on_python_state_code_failed(error: String) -> void:
	print("[Error] ", error)
