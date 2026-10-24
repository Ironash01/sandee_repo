extends "res://resources/godot_transpile_base.gd"

# ── Furnace programming base ──────────────────────────────────────
# Prepended to every program run from a furnace's Programming tab. Extends the
# shared Python-ish base (print/create/len/...) and adds the smelting API.
#
# Like the Crafting Station base, every call forwards to this script's PARENT —
# a FurnacePythonHost, a child of the furnace object. The program never touches
# the furnace's fields directly; the furnace validates everything. Outside a
# furnace host these are safe no-ops (empty/zero), so a stray program can't
# hard-crash.

func _furnace_host() -> Node:
	var host := get_parent()
	if host != null and host.has_method("furnace_feed"):
		return host
	return null

# feed(name, amount) -> int
# Move up to `amount` of the named item from the player's inventory into the
# INPUT (smeltable) slot. Returns how many were actually loaded.
func feed(name, amount) -> int:
	var host := _furnace_host()
	if host == null:
		return 0
	return int(host.call("furnace_feed", str(name), int(amount)))

# fuel(name, amount) -> int
# Move up to `amount` of the named FUEL item from the player's inventory into
# the FUEL slot. Fuel is slot-only — smelt() never auto-pulls it.
func fuel(name, amount) -> int:
	var host := _furnace_host()
	if host == null:
		return 0
	return int(host.call("furnace_fuel", str(name), int(amount)))

# smelt(amount) -> int
# Smelt up to `amount`, consuming input AND one fuel each. Fuel must already be
# in the fuel slot — it is never auto-pulled from the inventory. Returns how
# many were smelted (0 on any error; the reason is printed).
func smelt(amount) -> int:
	var host := _furnace_host()
	if host == null:
		return 0
	return int(host.call("furnace_smelt", int(amount)))

# take_output() -> int — move the output slot into the player's inventory.
func take_output() -> int:
	var host := _furnace_host()
	if host == null:
		return 0
	return int(host.call("furnace_take_output"))

# ── Read-only slot state ──
func input_name() -> String:
	var host := _furnace_host()
	return "" if host == null else str(host.call("furnace_input_name"))

func input_count() -> int:
	var host := _furnace_host()
	return 0 if host == null else int(host.call("furnace_input_count"))

func fuel_name() -> String:
	var host := _furnace_host()
	return "" if host == null else str(host.call("furnace_fuel_name"))

func fuel_count() -> int:
	var host := _furnace_host()
	return 0 if host == null else int(host.call("furnace_fuel_count"))

# output_name() / output_count() — read the output slot ("" / 0 when empty).
func output_name() -> String:
	var host := _furnace_host()
	return "" if host == null else str(host.call("furnace_output_name"))

func output_count() -> int:
	var host := _furnace_host()
	return 0 if host == null else int(host.call("furnace_output_count"))
