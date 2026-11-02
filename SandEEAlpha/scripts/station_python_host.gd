extends PythonState

# ── Crafting Station Python host ──────────────────────────────────
# A PythonState that lives on a Crafting Station and carries the station's
# programming base (res://resources/godot_station_base.gd). That base's
# craft()/get_recipe()/set_recipe()/output_*()/take_output() helpers call back
# into the station_* methods below, which forward to the station node.
#
# This is the ONLY bridge between a player's program and the station: the
# program cannot touch the station's fields directly, and every request goes
# through the station's own validation in craft_request().

var station: Node = null

# Per-run Algorithmica mission counters. The UI never reads these; they are
# reset when a program starts and summarized only after code_executed.
var _run_crafted: int = 0
var _run_had_craft: bool = false
var _run_recipe_read: bool = false
var _run_output_count_read: bool = false
var _run_item_before: bool = false
var _run_count_before: bool = false
var _run_item_after: bool = false
var _run_count_after: bool = false

func _ready() -> void:
	base_path = "res://resources/godot_station_base.gd"
	super()
	if not code_executed.is_connected(_on_run_ok):
		code_executed.connect(_on_run_ok)

func _reset_run_stats() -> void:
	_run_crafted = 0
	_run_had_craft = false
	_run_recipe_read = false
	_run_output_count_read = false
	_run_item_before = false
	_run_count_before = false
	_run_item_after = false
	_run_count_after = false

func _on_run_ok() -> void:
	Global.record_algo_station_run({
		"recipe_read": _run_recipe_read,
		"output_count_read": _run_output_count_read,
		"crafted_total": _run_crafted,
		"output_before": _run_item_before and _run_count_before,
		"output_after": _run_item_after and _run_count_after,
	})
	_reset_run_stats()

# Only crafting-station functions may run here. The interpreter knows the
# furnace API too, so without this a station program calling feed() would fail
# at runtime with a generic error — reject it up front with a clear message.
func run_code() -> void:
	_reset_run_stats()
	var foreign := AlgorithmicaAPI.foreign_calls(code, AlgorithmicaAPI.STATION)
	if not foreign.is_empty():
		var rejection := AlgorithmicaAPI.rejection_message(foreign, AlgorithmicaAPI.STATION)
		CrashLogger.code("python", "FAIL", "station: " + rejection)
		code_failed.emit(rejection)
		return
	super()

# ── Forwarders (called from godot_station_base.gd) ────────────────
func station_craft(amount) -> int:
	if not _station_valid():
		return 0
	var before: int = int(station.call("get_output_quantity"))
	var crafted: int = int(station.call("craft_request", int(amount)))
	if crafted > 0:
		var produced: int = int(station.call("get_output_quantity")) - before
		if produced <= 0:
			produced = crafted
		_run_crafted += produced
		_run_had_craft = true
		Global.record_algo_craft(station.call("get_output_item") as ItemData, produced)
	return crafted

func station_craft_color(r, g, b, amount) -> int:
	if not _station_valid():
		return 0
	var crafted: int = int(station.call("craft_color_request", r, g, b, amount))
	if crafted > 0:
		_run_crafted += crafted
		_run_had_craft = true
		Global.record_algo_color(int(r), int(g), int(b), crafted)
	return crafted

func station_get_recipe() -> String:
	if not _station_valid():
		return ""
	_run_recipe_read = true
	return str(station.call("get_automation_recipe_name"))

func station_set_recipe(name) -> bool:
	if not _station_valid():
		return false
	return bool(station.call("set_automation_recipe_by_name", str(name)))

func station_output_item() -> String:
	if not _station_valid():
		return ""
	if _run_had_craft:
		_run_item_after = true
	else:
		_run_item_before = true
	var data = station.call("get_output_item")
	if data == null:
		return ""
	return (data as ItemData).item_name

func station_output_count() -> int:
	if not _station_valid():
		return 0
	_run_output_count_read = true
	if _run_had_craft:
		_run_count_after = true
	else:
		_run_count_before = true
	return int(station.call("get_output_quantity"))

func station_take_output() -> int:
	if not _station_valid():
		return 0
	var data: ItemData = station.call("get_output_item") as ItemData
	var taken: int = int(station.call("take_output"))
	Global.record_algo_take_output(data, taken)
	return taken

func _station_valid() -> bool:
	return station != null and is_instance_valid(station)
