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

func _ready() -> void:
	base_path = "res://resources/godot_station_base.gd"
	super()

# ── Forwarders (called from godot_station_base.gd) ────────────────
func station_craft(amount) -> int:
	if not _station_valid():
		return 0
	return int(station.call("craft_request", int(amount)))

func station_get_recipe() -> String:
	if not _station_valid():
		return ""
	return str(station.call("get_automation_recipe_name"))

func station_set_recipe(name) -> bool:
	if not _station_valid():
		return false
	return bool(station.call("set_automation_recipe_by_name", str(name)))

func station_output_item() -> String:
	if not _station_valid():
		return ""
	var data = station.call("get_output_item")
	if data == null:
		return ""
	return (data as ItemData).item_name

func station_output_count() -> int:
	if not _station_valid():
		return 0
	return int(station.call("get_output_quantity"))

func station_take_output() -> int:
	if not _station_valid():
		return 0
	return int(station.call("take_output"))

func _station_valid() -> bool:
	return station != null and is_instance_valid(station)
