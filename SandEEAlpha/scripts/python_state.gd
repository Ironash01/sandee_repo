@icon("res://extension/python.svg")
class_name PythonState
extends Node

signal code_executed()
signal code_failed(error: String)
signal signal_print(output: String)
signal signal_create(object: String)

# The GDScript "base" script every transpiled program EXTENDS — it supplies the
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
	# The generated program EXTENDS the base script instead of having the base's
	# SOURCE pasted in front of it.
	#
	# Reading a .gd as text only works in the editor. Exported builds store
	# scripts as tokenized/compressed bytecode behind a .remap, so FileAccess
	# cannot open the original path. When that read failed the prefix was empty,
	# the generated script referenced undefined builtins (godot_print / create /
	# len) and GDScript.reload() returned ERR_PARSE_ERROR — i.e. the exported
	# build reported "Parse Error" for every Python program.
	#
	# `extends` is resolved by ResourceLoader, which understands the export
	# remap, so this behaves identically in the editor and in a build.
	if ResourceLoader.exists(path):
		return 'extends "%s"\n\n' % path
	# Fallback: a base that only exists as plain text (e.g. an external mod).
	var file := FileAccess.open(path, FileAccess.READ)
	if file != null:
		return file.get_as_text() + "\n"
	push_error("PythonState: cannot open base script: " + path)
	return "extends Node\n\n"

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
	if not is_inside_tree():
		return
	var source: String = _ensure_main(code if code != null else "")
	_code_log("RUN", "chars=%d\n%s" % [source.length(), source])
	var result = transpiler.transpile(source)
	var is_ok = result[0]
	var transpiled = result[1]
	if is_ok:
		var script: GDScript = GDScript.new()
		script.source_code = _base + transpiled
		var err: Error = script.reload(false)
		if err == Error.OK:
			var instance: Node = script.new()
			add_child(instance)
			var crash_logger: Node = get_node_or_null("/root/CrashLogger")
			if crash_logger != null:
				crash_logger.call("begin_script_capture")
			instance.main()
			# User code can legitimately free nodes (create/destroy); never
			# touch the instance after main() without a validity check.
			if is_instance_valid(instance):
				instance.queue_free()
			if crash_logger != null and bool(crash_logger.call("end_script_capture")):
				var failure := "Runtime error in the generated program. See log: %s" \
					% str(crash_logger.call("get_current_log_path"))
				_code_log("FAIL", failure)
				code_failed.emit(failure)
			else:
				Global.add_mission_progress("side_python_automator", 1)
				_code_log("OK", "finished")
				code_executed.emit()
		else:
			var parse_error := "Error: " + error_string(err)
			_code_log("FAIL", parse_error)
			code_failed.emit(parse_error)
	else:
		_code_log("FAIL", "transpile error: " + str(transpiled))
		code_failed.emit(transpiled)

func _code_log(phase: String, detail: String) -> void:
	var logger: Node = get_node_or_null("/root/CrashLogger")
	if logger != null:
		logger.call("code", "python", phase, detail)
