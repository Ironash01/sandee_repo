extends "res://resources/godot_transpile_base.gd"

# ── Crafting Station programming base ─────────────────────────────
# Prepended to every program run from a Crafting Station's Programming tab.
# Extends the shared Python-ish base (print/create/len/...) and adds the
# station automation API.
#
# Every function forwards to this script's PARENT — a StationPythonHost, which
# is a child of the Crafting Station. Keeping the forwarding in the host means
# the program never touches the station's internals directly and the UI never
# executes anything: the station is the only thing that validates and crafts.
#
# Outside a station host these are safe no-ops (they return the empty/zero
# value rather than erroring), so the same base can never hard-crash a program.

func _station_host() -> Node:
	var host := get_parent()
	if host != null and host.has_method("station_craft"):
		return host
	return null

# craft(amount) -> int
# Craft `amount` copies of the recipe selected in the Automation section.
# Returns how many were crafted (0 on any error — the reason is printed).
# Does NOT loop: one call is one request.
func craft(amount) -> int:
	var host := _station_host()
	if host == null:
		return 0
	return int(host.call("station_craft", amount))

# craft_color(r, g, b, amount) -> int
# Craft `amount` solid-color blocks using 8-bit RGB channels (0-255) and one
# Cactus per block, matching the Color Crafter station. Returns the number
# crafted, or 0 on failure; failures print the reason and consume nothing.
# Example:
#   craft_color(255, 0, 0, 2)   # two red blocks
#   take_output()               # move them into the player's inventory
# Insufficient Cactus prints "[craft_color] Insufficient Cactus" and consumes
# nothing.
func craft_color(r, g, b, amount) -> int:
	var host := _station_host()
	if host == null:
		return 0
	return int(host.call("station_craft_color", r, g, b, amount))

# get_recipe() -> str — the selected recipe's result item name ("" if none).
func get_recipe() -> String:
	var host := _station_host()
	if host == null:
		return ""
	return str(host.call("station_get_recipe"))

# set_recipe(name) -> bool — select a recipe by its result item name.
func set_recipe(name) -> bool:
	var host := _station_host()
	if host == null:
		return false
	return bool(host.call("station_set_recipe", str(name)))

# output_item() -> str — item name in the station's output slot ("" if empty).
func output_item() -> String:
	var host := _station_host()
	if host == null:
		return ""
	return str(host.call("station_output_item"))

# output_count() -> int — how many items sit in the output slot.
func output_count() -> int:
	var host := _station_host()
	if host == null:
		return 0
	return int(host.call("station_output_count"))

# take_output() -> int — move the output slot into the player's inventory.
# Returns how many were taken (0 when empty or the inventory is full).
func take_output() -> int:
	var host := _station_host()
	if host == null:
		return 0
	return int(host.call("station_take_output"))
