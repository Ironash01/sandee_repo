extends Node2D

@onready var code_editor: CodeEditor = $Control/CodeEditor
@onready var stats_label: Label = $Control/StatsLabel

var agent_scene: PackedScene = preload("uid://bvpfyk0rj6ag8")
var agents: Array = []
# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	pass # Replace with function body.


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MouseButton.MOUSE_BUTTON_RIGHT:
			if event.pressed:
				var agent: TestAgent = agent_scene.instantiate()
				agent.position = event.position
				add_child(agent)
				agents.push_back(agent)

func _process(_delta: float) -> void:
	stats_label.text = "FPS: %.3f\nAgents: %d" % [Engine.get_frames_per_second(), agents.size()]
	for agent: TestAgent in agents:
		agent.run_code()

func _on_button_pressed() -> void:
	for agent: TestAgent in agents:
		agent.code = code_editor.get_code()
