@icon("res://extension/python.svg")
class_name PythonState
extends Node

signal code_executed()
signal code_failed(error: String)
signal signal_print(output: String)
signal signal_create(object: String)

var transpiler: PythonTranspiler
var code: String
var _base: String
func _ready() -> void:
	transpiler = PythonTranspiler.new()
	_base = _load_godot_base("res://resources/godot_transpile_base.gd")

func _load_godot_base(path: String) -> String:
	var file = FileAccess.open(path, FileAccess.READ)
	return file.get_as_text()

func run_code():
	var result = transpiler.transpile(code)
	var is_ok = result[0]
	var transpiled = result[1]
	if is_ok:
		var script: GDScript = GDScript.new()
		script.source_code = _base + transpiled
		print("Transpiled:\n\n", script.source_code)
		var err: Error = script.reload(false)
		if err == Error.OK:
			var instance: Node = script.new()
			add_child(instance)
			instance.main()
			instance.queue_free()
			code_executed.emit()
		else:
			code_failed.emit("Error: " + error_string(err))
	else:
		code_failed.emit(transpiled)
