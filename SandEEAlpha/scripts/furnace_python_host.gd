extends PythonState

# ── Furnace Python host ───────────────────────────────────────────
# A PythonState that lives on a furnace (scripts/object_item.gd) and carries
# the furnace programming base (res://resources/godot_furnace_base.gd). That
# base's load()/smelt()/take_output()/... helpers call back into the
# furnace_* methods below, which forward to the furnace node.
#
# This is the ONLY bridge between a player's program and the furnace; every
# request goes through the furnace's own validation in smelt_request().

var furnace: Node = null

# Per-run Algorithmica mission counters (reset when the program starts).
var _run_fed: bool = false
var _run_fueled: bool = false
var _run_input_status: bool = false
var _run_fuel_status: bool = false
var _run_smelted_iron: int = 0

func _ready() -> void:
	base_path = "res://resources/godot_furnace_base.gd"
	super()
	if not code_executed.is_connected(_on_run_ok):
		code_executed.connect(_on_run_ok)

func _reset_run_stats() -> void:
	_run_fed = false
	_run_fueled = false
	_run_input_status = false
	_run_fuel_status = false
	_run_smelted_iron = 0

func _on_run_ok() -> void:
	Global.record_algo_furnace_run(_run_smelted_iron,
		_run_input_status, _run_fuel_status)
	_reset_run_stats()

# Only furnace functions may run here (see StationPythonHost.run_code).
func run_code() -> void:
	_reset_run_stats()
	var foreign := AlgorithmicaAPI.foreign_calls(code, AlgorithmicaAPI.FURNACE)
	if not foreign.is_empty():
		var rejection := AlgorithmicaAPI.rejection_message(foreign, AlgorithmicaAPI.FURNACE)
		CrashLogger.code("python", "FAIL", "furnace: " + rejection)
		code_failed.emit(rejection)
		return
	super()

func _valid() -> bool:
	return furnace != null and is_instance_valid(furnace)

# ── Forwarders (called from godot_furnace_base.gd) ────────────────
func furnace_feed(name: String, amount: int) -> int:
	if not _valid():
		return 0
	var data: ItemData = Global.find_item_by_name(name)
	if data == null:
		emit_signal("signal_print", "[feed] unknown item \"%s\"" % name)
		return 0
	var accepted: int = int(furnace.call("load_input_named", data, amount))
	if accepted > 0:
		_run_fed = true
		Global.record_algo_feed(accepted)
	return accepted

func furnace_fuel(name: String, amount: int) -> int:
	if not _valid():
		return 0
	var data: ItemData = Global.find_item_by_name(name)
	if data == null:
		emit_signal("signal_print", "[fuel] unknown item \"%s\"" % name)
		return 0
	if not data.is_fuel:
		emit_signal("signal_print", "[fuel] \"%s\" is not a fuel" % name)
		return 0
	var accepted: int = int(furnace.call("load_fuel_named", data, amount))
	if accepted > 0:
		_run_fueled = true
		Global.record_algo_fuel(accepted)
	return accepted

func furnace_smelt(amount: int) -> int:
	if not _valid():
		return 0
	var input_data: ItemData = null
	var input_slot: Dictionary = furnace.call("get_input_stack")
	if not input_slot.is_empty():
		input_data = input_slot["data"] as ItemData
	var smelted: int = int(furnace.call("smelt_request", amount))
	if smelted > 0:
		var output_slot: Dictionary = furnace.call("get_output_stack")
		var output_data: ItemData = null
		if not output_slot.is_empty():
			output_data = output_slot["data"] as ItemData
		if output_data != null and output_data.item_id() == "ironbar":
			_run_smelted_iron += smelted
			Global.record_algo_smelt_iron(smelted)
		if input_data != null and input_data.item_id() == "crystal_iron_ore":
			Global.record_algo_crystal_smelt(smelted)
	return smelted

func furnace_take_output() -> int:
	if not _valid():
		return 0
	var data: ItemData = null
	var slot: Dictionary = furnace.call("get_output_stack")
	if not slot.is_empty():
		data = slot["data"] as ItemData
	var taken: int = int(furnace.call("take_output"))
	Global.record_algo_take_output(data, taken)
	return taken

func furnace_input_name() -> String:
	if not _valid():
		return ""
	_run_input_status = true
	var slot: Dictionary = furnace.call("get_input_stack")
	return "" if slot.is_empty() else (slot["data"] as ItemData).item_name

func furnace_input_count() -> int:
	if not _valid():
		return 0
	_run_input_status = true
	return int((furnace.call("get_input_stack") as Dictionary).get("quantity", 0))

func furnace_fuel_name() -> String:
	if not _valid():
		return ""
	_run_fuel_status = true
	var slot: Dictionary = furnace.call("get_fuel_stack")
	return "" if slot.is_empty() else (slot["data"] as ItemData).item_name

func furnace_fuel_count() -> int:
	if not _valid():
		return 0
	_run_fuel_status = true
	return int((furnace.call("get_fuel_stack") as Dictionary).get("quantity", 0))

func furnace_output_name() -> String:
	if not _valid():
		return ""
	var slot: Dictionary = furnace.call("get_output_stack")
	return "" if slot.is_empty() else (slot["data"] as ItemData).item_name

func furnace_output_count() -> int:
	if not _valid():
		return 0
	return int((furnace.call("get_output_stack") as Dictionary).get("quantity", 0))
