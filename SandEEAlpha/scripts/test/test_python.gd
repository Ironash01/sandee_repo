extends Node2D

@onready var code_editor: CodeEditor = $Control/CodeEditor
@onready var stats_label: Label = $Control/StatsLabel

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	pass # Replace with function body.


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(_delta: float) -> void:
	stats_label.text = "FPS: %.3f" % Engine.get_frames_per_second()
	
func foo():
	print("foo")

func _on_button_pressed() -> void:
	var script: GDScript = GDScript.new()
	script.source_code = "extends Node\nfunc main():\n\tprint(\"test\")\n\tfoo()"
	var err = script.reload()
	var instance: Node = script.new()
	add_child(instance)
	instance.main()
	instance.queue_free()
