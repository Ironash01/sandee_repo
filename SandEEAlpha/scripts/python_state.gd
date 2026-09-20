@icon("res://extension/python.svg")
class_name PythonState
extends Node

signal code_executed()
signal code_failed(error: String)
signal signal_print(output: String)
signal signal_create(object: String)

# The GDScript "base" prepended to every transpiled program — it supplies the
# Python-ish builtins (print/create/len/...). Swappable so a host that needs a
# richer API (e.g. the Crafting Station's StationPythonHost) can point at its
# own base script that extends this one.
const DEFAULT_BASE_PATH: String = "res://resources/godot_transpile_base.gd"

var transpiler: PythonTranspiler
var code: String
var base_path: String = DEFAULT_BASE_PATH
var _base: String
func _ready() -> void:
	transpiler = PythonTranspiler.new()
	_base = _load_godot_base(base_path)

func _load_godot_base(path: String) -> String:
	var file = FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("PythonState: cannot open base script: " + path)
		return ""
	return file.get_as_text()

# The transpiler requires a main() function. Dungeon questions are written as
# bare statements (e.g. print("Hi")), so wrap top-level code in a main() when
# the player didn't define one. 4-space indent keeps it valid alongside the
# starter code, which also uses 4 spaces.
func _ensure_main(source: String) -> String:
	if source.find("def main") != -1:
		return source
	var out := "def main():\n"
	var wrote := false
	for raw in source.split("\n"):
		if raw.strip_edges().is_empty():
			out += "\n"
		else:
			out += "    " + raw + "\n"
			wrote = true
	if not wrote:
		out += "    pass\n"
	return out

func run_code():
	var result = transpiler.transpile(_ensure_main(code if code != null else ""))
	var is_ok = result[0]
	var transpiled = result[1]
	if is_ok:
		var script: GDScript = GDScript.new()
		script.source_code = _base + transpiled
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
