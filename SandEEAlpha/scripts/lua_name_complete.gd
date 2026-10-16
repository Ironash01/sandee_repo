extends RefCounted
class_name LuaNameComplete

# ── Name-argument completion ──────────────────────────────────────
# Shared helper for the program editors. When the cursor sits inside the
# parentheses of a function whose argument is an item NAME (craft-style /
# station / furnace / robot APIs), it pops the list of valid item names so the
# player picks one instead of typing it.
#
# Item names come from the extension's list_items() when available (reads the
# actual ItemData resources); otherwise the passed fallback list is used.

const NAME_FUNCS: Array = [
	"set_recipe",  # crafting station
	"put_input",   # station / robot -> station input
	"withdraw",    # robot -> take from chest
	"feed",        # furnace input
	"fuel",        # furnace fuel slot
	"mine",        # robot -> mine a block by name
]

const API_FUNCS: Array = [
	"craft", "get_recipe", "set_recipe", "output_item", "output_count", "take_output",
	"feed", "fuel", "smelt", "input_name", "input_count", "fuel_name", "fuel_count",
	"output_name", "load", "load_items", "list_items",
	"interact", "auto_work", "chop_trees", "deposit_chest", "chest_contents",
	"return_to_spawn", "craft_example", "move", "attack", "drop_item", "place_item",
	"place_at", "select_block", "input_slot", "mine", "rename",
	"build_line", "build_rect", "build_circle", "build_ring", "build_spiral",
	"build_wave", "build_stairs",
]

static var _items_cache: Array = []
static var _items_loaded: bool = false

# Item display names, read once from the ItemData resources (via the
# extension's list_items() Lua global when the interpreter is loaded, else by
# scanning res://resources/items/ directly).
static func item_names() -> Array:
	if _items_loaded:
		return _items_cache
	_items_loaded = true
	# Prefer the interpreter's list_items() (authoritative ItemData names).
	if ClassDB.class_exists("LuaState"):
		var probe = LuaState.new()
		var names: Variant = probe.call("run_list_items")
		probe.free()
		if names is Array and not (names as Array).is_empty():
			_items_cache = names as Array
			return _items_cache
	_items_cache = _fallback_items()
	return _items_cache

static func _fallback_items() -> Array:
	var out: Array = []
	const DIR := "res://resources/items/"
	for f in ResourceLoader.list_directory(DIR):
		if f.ends_with(".tres"):
			var r = load(DIR + f)
			if r is ItemData and not (r as ItemData).item_name.is_empty():
				out.append((r as ItemData).item_name)
	out.sort()
	return out

static func _is_ident(c: String) -> bool:
	return c == "_" or (c >= "a" and c <= "z") or (c >= "A" and c <= "Z") or (c >= "0" and c <= "9")

# True when the text caret is inside `funcname(`'s argument list. `caret` is
# the index in `text` of the character the caret sits BEFORE — so we search for
# the "(" up to and including the last typed character.
static func name_arg_open(text: String, caret: int) -> bool:
	var up_to: int = maxi(0, mini(caret, text.length()))
	# Look for the nearest "(" at or before the caret.
	var open: int = -1
	for i in range(up_to - 1, -1, -1):
		var c: String = text[i]
		if c == ")" or c == "\n":
			return false   # a closed paren / new line ends the argument window
		if c == "(":
			open = i
			break
	if open < 0:
		return false
	var name_start := open
	while name_start > 0 and _is_ident(text[name_start - 1]):
		name_start -= 1
	var fname := text.substr(name_start, open - name_start)
	return NAME_FUNCS.has(fname)
