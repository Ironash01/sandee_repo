extends Node2D

@onready var lua_runner: LuaRunner = $LuaRunner
@onready var code_editor: Control = $Control/CodeEditor

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	pass # Replace with function body.


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass

func _on_button_pressed() -> void:
	lua_runner.run_lua_code(code_editor.get_code())
