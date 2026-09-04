@icon("res://extension/python.svg")
class_name PythonState
extends Node

signal code_executed()
signal code_failed(String)
signal signal_print(Array)


var transpiler: PythonTranspiler
var code: String
func _ready() -> void:
	transpiler = PythonTranspiler.new()

func run_code():
	var result = transpiler.transpile(code)
	var is_ok = result[0]
	var transpiled = result[1]
	if is_ok:
		var script: GDScript = GDScript.new()
		script.source_code = "extends Node\n\n" + transpiled
		var err: Error = script.reload(false)
		if err == Error.OK:
			var instance: Node = script.new()
			add_child(instance)
			instance.main()
			instance.queue_free()
			code_executed.emit()
		else:
			code_failed.emit("Godot error: " + error_string(err))
	else:
		code_failed.emit(transpiled)
