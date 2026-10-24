extends Node
## Crash/diagnostic logger.
##
## Captures every engine message (prints, warnings, errors and GDScript
## backtraces) into a flushed log file so the last lines survive a hard crash.
## Gameplay systems also add structured EVENT and CODE entries through
## event()/code() so saves, world transitions, automation and Lua/Python runs
## are traceable without grepping raw engine output.
## A `session.active` marker is written at startup and removed on a clean exit;
## if it is still present on the next launch, the previous run ended abruptly.
##
## Location:
##   * exported Windows/Linux/macOS: <executable folder>/logs/
##   * Android/iOS: user://logs/ (app-private; pull with adb)
##   * editor/headless: user://logs/
## If the executable folder is not writable (Program Files, read-only install),
## it falls back to user://logs/ automatically.
##
## Native crash *minidumps* require a platform-specific handler (Windows DBGHELP
## / Android tombstone). This logger provides the persistent application log and
## the script backtraces that are available from GDScript's Logger API.

const MAX_LOG_FILES := 10
const MAX_STACK_FRAMES := 24
# Keep a single code/event entry bounded so a runaway program cannot turn the
# log into hundreds of megabytes.
const MAX_EVENT_CHARS := 6000

var log_dir: String = ""
var log_path: String = ""
var last_script_error: String = ""
var script_error_count: int = 0

var _file: FileAccess = null
var _sink: Logger = null
var _marker_path: String = ""
var _writing: bool = false


class Sink extends Logger:
	var owner_node: Node

	func _log_message(message: String, error: bool) -> void:
		if owner_node == null or not is_instance_valid(owner_node):
			return
		owner_node.call("_write", "ERROR" if error else "INFO", message)

	func _log_error(function: String, file: String, line: int, code: String,
			rationale: String, editor_notify: bool, error_type: int,
			script_backtraces: Array) -> void:
		if owner_node == null or not is_instance_valid(owner_node):
			return
		var text := "%s:%d  in %s  [%s] %s" % [file, line, function, code, rationale]
		for backtrace in script_backtraces:
			text += "\n" + str(backtrace)
		owner_node.call("_on_script_error", text)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	log_dir = _choose_dir()
	DirAccess.make_dir_recursive_absolute(log_dir)
	_rotate()
	var stamp := Time.get_datetime_string_from_system().replace(":", "-")
	log_path = log_dir.path_join("sandee_%s.log" % stamp)
	_file = FileAccess.open(log_path, FileAccess.WRITE)
	if _file == null:
		# Last-resort fallback: app-private storage.
		log_dir = ProjectSettings.globalize_path("user://logs")
		DirAccess.make_dir_recursive_absolute(log_dir)
		log_path = log_dir.path_join("sandee_%s.log" % stamp)
		_file = FileAccess.open(log_path, FileAccess.WRITE)
	if _file == null:
		push_warning("CrashLogger: could not open a log file; logging disabled")
		return

	_marker_path = log_dir.path_join("session.active")
	_sink = Sink.new()
	(_sink as Sink).owner_node = self
	OS.add_logger(_sink)

	_write("SESSION", "SandEE %s | %s | %s | user_dir=%s" % [
		str(ProjectSettings.get_setting("application/config/version", "unknown")),
		OS.get_name(), OS.get_processor_name(), OS.get_user_data_dir()])
	if FileAccess.file_exists(_marker_path):
		var previous := FileAccess.get_file_as_string(_marker_path).strip_edges()
		_write("CRASH", "PREVIOUS SESSION DID NOT EXIT CLEANLY (last log: %s)" % previous)
		# Keep the previous log intact; the new log explains the unclean start.
	var marker := FileAccess.open(_marker_path, FileAccess.WRITE)
	if marker != null:
		marker.store_string(log_path)
		marker.close()
	print("[CrashLogger] writing to ", log_path)
	if OS.has_feature("android") or OS.has_feature("ios"):
		print("[CrashLogger] Android/iOS log folder: ", OS.get_user_data_dir().path_join("logs"))


func _choose_dir() -> String:
	if OS.has_feature("android") or OS.has_feature("ios") or OS.has_feature("editor"):
		return ProjectSettings.globalize_path("user://logs")
	var exe_logs := OS.get_executable_path().get_base_dir().path_join("logs")
	DirAccess.make_dir_recursive_absolute(exe_logs)
	# Probe writability: a temp file is the only reliable check on Windows.
	var probe := exe_logs.path_join(".write_test")
	var f := FileAccess.open(probe, FileAccess.WRITE)
	if f != null:
		f.store_string("ok")
		f.close()
		DirAccess.remove_absolute(probe)
		return exe_logs
	return ProjectSettings.globalize_path("user://logs")


func _write(tag: String, text: String) -> void:
	if _file == null or _writing:
		return
	_writing = true
	var line := "[%s] %-11s | %s\n" % [Time.get_datetime_string_from_system(), tag, text]
	_file.store_string(line)
	_file.flush()   # survive a hard crash / power loss
	_writing = false


func _on_script_error(text: String) -> void:
	last_script_error = text
	script_error_count += 1
	_write("SCRIPT_ERROR", text)


## Structured gameplay/code event. Unlike report(), this deliberately has no
## stack: it is meant for high-value actions (save/load, world transitions,
## Lua/Python runs, block changes, automation) that are cheap to log and easy
## to scan in the session log. Output goes to the same logs/sandee_*.log file.
func event(category: String, message: String) -> void:
	_write("EVENT", "[%s] %s" % [category.to_upper(), _clip_event(message)])

## Code-oriented event for the Lua/Python runners: RUN/OUT/OK/FAIL plus the
## source or output that produced it. Kept separate from EVENT so code activity
## can be grepped quickly without hiding normal gameplay events.
func code(language: String, phase: String, detail: String = "") -> void:
	_write("CODE", "[%s/%s] %s" % [
		language.to_upper(), phase.to_upper(), _clip_event(detail)])

func _clip_event(message: String) -> String:
	if message.length() <= MAX_EVENT_CHARS:
		return message
	return message.substr(0, MAX_EVENT_CHARS) \
		+ "\n...[truncated %d chars]" % (message.length() - MAX_EVENT_CHARS)

## Manual diagnostic with the caller's GDScript stack. Use for QA-visible
## "why did this action not work" cases (pause/build toggles, automation).
func report(message: String) -> void:
	var stack := ""
	var frames := get_stack()
	for i in range(mini(frames.size(), MAX_STACK_FRAMES)):
		var frame: Dictionary = frames[i]
		stack += "\n    at %s (%s:%d)" % [
			str(frame.get("function", "?")),
			str(frame.get("source", "?")),
			int(frame.get("line", 0))]
	_write("REPORT", message + stack)


func begin_script_capture() -> void:
	script_error_count = 0
	last_script_error = ""


func end_script_capture() -> bool:
	return script_error_count > 0


func get_current_log_path() -> String:
	return log_path


func _rotate() -> void:
	var dir := DirAccess.open(log_dir)
	if dir == null:
		return
	var logs: Array = []
	for fname in dir.get_files():
		if fname.begins_with("sandee_") and fname.ends_with(".log"):
			logs.append(fname)
	logs.sort()
	while logs.size() >= MAX_LOG_FILES:
		dir.remove(str(logs.pop_front()))


func _exit_tree() -> void:
	if _sink != null:
		OS.remove_logger(_sink)
		_sink = null
	if _file != null:
		_write("SESSION", "clean exit")
		_file.flush()
		_file.close()
		_file = null
	if _marker_path != "":
		DirAccess.remove_absolute(_marker_path)
