extends Node2D
class_name TestAgent

@onready var lua_state: LuaState = $LuaState
@export var code: String:
	get:
		return lua_state.code
	set(value):
		_set_code(value)
var velocity: Vector2

func run_code():
	lua_state.run_code()
	
func _set_code(value: String):
	lua_state.code = value

func _physics_process(delta: float) -> void:
	position += velocity * delta

func _on_lua_state_signal_print(string: String) -> void:
	print("[Agent %d] %s" % [get_instance_id(), string])


func _on_lua_state_signal_move(vector: Vector2) -> void:
	velocity = vector


func _on_lua_state_code_failed(error: String) -> void:
	print("Error on Agent %d: %s" % [get_instance_id(), error])
