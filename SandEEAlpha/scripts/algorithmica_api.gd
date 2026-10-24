extends RefCounted
class_name AlgorithmicaAPI

# ── Per-machine Algorithmica surface ──────────────────────────────
# The Python API is split by machine: a crafting-station program may only use
# the station's functions and a furnace program only the furnace's. The
# interpreter (interpreter.dll) knows BOTH sets, so without this check a
# furnace program could call craft() and only fail at runtime with a confusing
# "Invalid call" error. The hosts call foreign_calls() before running a program
# and refuse it with a clear message instead.
#
# This list is the enforcement mirror of APIReference.CUSTOM_PYTHON_STATION /
# CUSTOM_PYTHON_FURNACE. Keep them in sync.

const STATION := "Crafting Station"
const FURNACE := "Furnace"

const STATION_FUNCTIONS: Array = [
	"craft", "craft_color", "get_recipe", "set_recipe", "output_item", "output_count",
	"take_output",
]

const FURNACE_FUNCTIONS: Array = [
	"feed", "fuel", "smelt", "take_output",
	"input_name", "input_count", "fuel_name", "fuel_count",
	"output_name", "output_count",
]

static func functions_for(target: String) -> Array:
	return STATION_FUNCTIONS if target == STATION else FURNACE_FUNCTIONS

# Names that belong to the OTHER machine (excluding shared ones), found in
# `code`. Comments are ignored so a comment mentioning feed() doesn't block a
# station program.
static func foreign_calls(code: String, target: String) -> PackedStringArray:
	var mine: Array = functions_for(target)
	var other: Array = functions_for(FURNACE if target == STATION else STATION)
	var re := RegEx.new()
	re.compile("\\b(" + "|".join(PackedStringArray(other)) + ")\\s*\\(")
	var found := PackedStringArray()
	for line in code.split("\n"):
		var code_only: String = line
		var hash_at: int = code_only.find("#")
		if hash_at >= 0:
			code_only = code_only.substr(0, hash_at)
		for m in re.search_all(code_only):
			var n: String = m.get_string(1)
			if mine.has(n) or found.has(n):
				continue
			found.append(n)
	return found

# Human-readable refusal message (used by both hosts + the editors).
static func rejection_message(names: PackedStringArray, target: String) -> String:
	var allowed: String = ", ".join(PackedStringArray(functions_for(target)))
	return "%s programs cannot use %s. Allowed here: %s" % [
		target, ", ".join(names), allowed]
