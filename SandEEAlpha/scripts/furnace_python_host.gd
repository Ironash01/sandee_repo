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

func _ready() -> void:
	base_path = "res://resources/godot_furnace_base.gd"
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
	return int(furnace.call("load_input_named", data, amount))

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
	return int(furnace.call("load_fuel_named", data, amount))

func furnace_smelt(amount: int) -> int:
	if not _valid():
		return 0
	return int(furnace.call("smelt_request", amount))

func furnace_take_output() -> int:
	if not _valid():
		return 0
	return int(furnace.call("take_output"))

func furnace_input_name() -> String:
	if not _valid():
		return ""
	var slot: Dictionary = furnace.call("get_input_stack")
	return "" if slot.is_empty() else (slot["data"] as ItemData).item_name

func furnace_input_count() -> int:
	if not _valid():
		return 0
	return int((furnace.call("get_input_stack") as Dictionary).get("quantity", 0))

func furnace_fuel_name() -> String:
	if not _valid():
		return ""
	var slot: Dictionary = furnace.call("get_fuel_stack")
	return "" if slot.is_empty() else (slot["data"] as ItemData).item_name

func furnace_fuel_count() -> int:
	if not _valid():
		return 0
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
