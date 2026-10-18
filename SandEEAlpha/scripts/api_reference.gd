extends RefCounted
class_name APIReference

# ── In-game function reference (single source of truth) ─────────────
# Shared by the Lua robot editor's Encyclopedia (scripts/lua_editor_ui.gd)
# and the Crafting Station's Programming tab (scripts/crafting_menu.gd).
#
# It deliberately separates two things that used to be listed together:
#   • CUSTOM functions — the ones THIS GAME adds (robot movement, station
#     crafting). These are the "block" APIs the player programs against.
#   • BUILT-IN functions — the ones that belong to the programming language
#     itself (the Lua / Python standard library).
# and never mixes Lua with Python.
#
# Every entry is {"sig": "<signature>", "desc": "<one-line help>"}.
# Keep these lists in sync with the real callable surface:
#   Lua    → extension/src/runner/lua.rs + lua_editor_ui.gd's preamble
#   Python → resources/godot_station_base.gd + transpiler/src/spec.rs

# ── Custom: Lua robot ──────────────────────────────────────────────
const CUSTOM_LUA_ROBOT: Array = [
	{"sig": "auto_work()",
		"desc": "Full work cycle: chop all trees in radius → deposit collected items into the nearest chest → return to station."},
	{"sig": "chop_trees(radius)",
		"desc": "Chop every tree within radius blocks of the station (defaults to 20 if omitted). Collects dropped items after each tree, then walks home."},
	{"sig": "deposit_chest()",
		"desc": "Walk to the nearest chest within radius, deposit everything in the robot's inventory, then return to the station."},
	{"sig": "chest_contents()",
		"desc": "Print the contents of the nearest chest to the output panel. Outputs each item and quantity, or a message if the chest is empty or out of range."},
	{"sig": "return_to_spawn()",
		"desc": "Walk the robot directly back to the station and stop. Use this to abort a long task or reset position."},
	{"sig": "craft_example()",
		"desc": "Worked example: chop + deliver wood, then craft 2 chests at the nearest station. Use it as a template for your own programs."},
	{"sig": "move(x, y)",
		"desc": "Set the robot's movement velocity to (x, y) pixels per second. Positive x = east, positive y = south. Call move(0, 0) to stop. Sequences of move() calls all fire instantly — only the last value takes effect."},
	{"sig": "interact()",
		"desc": "Execute the pending action. With no sentinel move() before it, defaults to chopping all trees then returning home. Only one action runs at a time — calls while the robot is busy are ignored."},
	{"sig": "attack()",
		"desc": "Perform the robot's attack action (swing its held weapon)."},
	{"sig": "drop_item(qty)",
		"desc": "Drop qty copies of the held item at the robot's current position. The item must be in the robot's inventory."},
	{"sig": "place_item()",
		"desc": "Place the robot's currently held placeable item at its position."},
	{"sig": "mine(name, radius)",
		"desc": "Mine every placed block whose name matches within radius blocks of the station, walking to each and storing the drops, e.g. mine(\"Stone\"). Radius defaults to 20."},
	{"sig": "rename(name)",
		"desc": "Give the robot a custom name. It is shown above the robot itself."},
	{"sig": "combat_mode(on)",
		"desc": "true: send this LUA into COMBAT MODE — it abandons its station, follows you, and attacks whatever you attack with its TOOL slot. A combat LUA cannot run code, has HP (enemies can hurt it), and can be terminated for good (remote, or STOP on its station). false: leave combat mode."},
]

# ── Custom: Lua crafting-station API ───────────────────────────────
const CUSTOM_LUA_STATION: Array = [
	{"sig": "craft(n)",
		"desc": "Craft n of the station's currently selected automation recipe."},
	{"sig": "set_recipe(name)",
		"desc": "Select the automation recipe by output name, e.g. set_recipe(\"Planks\")."},
	{"sig": "take_output()",
		"desc": "Move the station's finished output into the robot's inventory."},
	{"sig": "put_input(\"name\", n)",
		"desc": "Walk to the nearest station and load n of the named item into its INPUT slot for automatic crafting, e.g. put_input(\"Wood\", 10)."},
	{"sig": "input_slot(n)",
		"desc": "Walk to the nearest station and load n of the SELECTED build-slot item into its INPUT slot (no item name needed)."},
	{"sig": "held_item",
		"desc": "Variable: a table {name, quantity} for the item the robot is holding, or nil."},
	{"sig": "station_recipe",
		"desc": "Variable: the name of the station's selected recipe (read-only)."},
	{"sig": "station_output_item / station_output_count",
		"desc": "Variables: the station's pending output item name and quantity (read-only)."},
]

# ── Custom: Python crafting-station API ────────────────────────────
const CUSTOM_PYTHON_STATION: Array = [
	{"sig": "craft(amount)",
		"desc": "Craft amount of the station's currently selected automation recipe."},
	{"sig": "get_recipe()",
		"desc": "Return the name of the station's selected recipe."},
	{"sig": "set_recipe(name)",
		"desc": "Select the automation recipe by output name, e.g. set_recipe(\"Planks\")."},
	{"sig": "output_item()",
		"desc": "Return the name of the station's pending output item."},
	{"sig": "output_count()",
		"desc": "Return how many of the pending output item are ready."},
	{"sig": "take_output()",
		"desc": "Move the station's finished output into the player's inventory."},
]

# ── Custom: Lua building API ───────────────────────────────────────
const CUSTOM_LUA_BUILD: Array = [
	{"sig": "select_block(i)",
		"desc": "Choose which build slot (0, 1 or 2) place_item() places from."},
	{"sig": "place_item(dx, dy)",
		"desc": "Place one block from the selected build slot at a tile offset from the robot. Returns nothing; one block per call."},
	{"sig": "place_at(x, y)",
		"desc": "Place one block at absolute tile coordinates (x, y)."},
	{"sig": "withdraw(\"name\", n)",
		"desc": "Walk to the nearest chest and take n of the named item into the build palette, e.g. withdraw(\"Wood\", 10)."},
	{"sig": "build_line(x0, y0, x1, y1)",
		"desc": "Gap-free straight line of blocks between two offsets (uses Bresenham, so diagonals don't skip tiles)."},
	{"sig": "build_rect(x0, y0, w, h, filled)",
		"desc": "Rectangle w by h at offset (x0, y0); filled = solid slab, otherwise just the border."},
	{"sig": "build_circle(r, filled)",
		"desc": "Circle of radius r centred on the robot; filled = disc, otherwise an outline."},
	{"sig": "build_ring(r)",
		"desc": "Hollow ring of radius r."},
	{"sig": "build_spiral(r, turns)",
		"desc": "Archimedean spiral out to radius r over `turns` turns."},
	{"sig": "build_wave(len, amp)",
		"desc": "Sine-wave fence `len` tiles long and `amp` tiles tall."},
	{"sig": "build_stairs(n)",
		"desc": "Diagonal staircase of n steps."},
]

# ── Built-in: Lua standard library ─────────────────────────────────
const BUILTIN_LUA: Array = [
	{"sig": "print(val, ...)",
		"desc": "Print a value to the output panel. Accepts strings, numbers, and booleans."},
	{"sig": "type(v)",
		"desc": "Return the type name of v, e.g. \"number\", \"string\", \"table\"."},
	{"sig": "tostring(v) / tonumber(v)",
		"desc": "Convert a value to a string / to a number (returns nil if it can't)."},
	{"sig": "pairs(t) / ipairs(t)",
		"desc": "Iterate a table in for loops — pairs() over all keys, ipairs() over the array part in order."},
	{"sig": "math.floor(x) / math.ceil(x)",
		"desc": "Round x down / up to a whole number."},
	{"sig": "math.abs(x) / math.sqrt(x)",
		"desc": "Absolute value / square root of x."},
	{"sig": "math.min(a, b) / math.max(a, b)",
		"desc": "Smaller / larger of two numbers."},
	{"sig": "math.random(m, n)",
		"desc": "Random number: integer in m..n, or a float in 0..1 with no arguments."},
	{"sig": "string.format(fmt, ...)",
		"desc": "Build a formatted string, e.g. string.format(\"%d apples\", 3)."},
	{"sig": "string.len(s) / string.upper(s) / string.lower(s)",
		"desc": "Length / upper-case / lower-case of a string."},
	{"sig": "table.insert(t, v) / table.remove(t, i)",
		"desc": "Add v to the end of table t / remove the element at index i."},
	{"sig": "table.sort(t) / table.concat(t, sep)",
		"desc": "Sort table t in place / join its elements into a string with sep."},
	{"sig": "vector",
		"desc": "Built-in vector helper (vector(x, y)) for positions and directions."},
]

# ── Built-in: Python standard library (what the transpiler supports) ─
const BUILTIN_PYTHON: Array = [
	{"sig": "print(...)",
		"desc": "Print values to the output panel. Multiple arguments are separated by spaces."},
	{"sig": "len(obj)",
		"desc": "Return the number of items in a string, list, or dictionary."},
	{"sig": "range(n)",
		"desc": "Return the numbers 0..n-1, for use in for loops."},
	{"sig": "int(v) / float(v)",
		"desc": "Convert v to an integer / floating-point number."},
	{"sig": "str(v) / bool(v)",
		"desc": "Convert v to a string / to a boolean."},
	{"sig": "abs(v) / pow(a, b)",
		"desc": "Absolute value of v / a raised to the power b."},
	{"sig": "min(a, b) / max(a, b)",
		"desc": "Smaller / larger of two numbers."},
	{"sig": "list(...) / dict(...)",
		"desc": "Build a list / dictionary from the given values."},
]

# ── Custom: Python furnace API ─────────────────────────────────────
const CUSTOM_PYTHON_FURNACE: Array = [
	{"sig": "feed(name, n)",
		"desc": "Move up to n of the named item from your inventory into the INPUT (smeltable) slot. Returns how many were loaded."},
	{"sig": "fuel(name, n)",
		"desc": "Move up to n of the named FUEL item from your inventory into the FUEL slot. Returns how many were loaded."},
	{"sig": "smelt(n)",
		"desc": "Smelt up to n, consuming input AND one fuel each. Fuel must already be in the fuel slot (never auto-consumed). Returns how many were smelted."},
	{"sig": "take_output()",
		"desc": "Move the furnace's output slot into your inventory. Returns how many were taken."},
	{"sig": "input_name() / input_count()",
		"desc": "Read the input slot's item name / quantity (\"\" / 0 when empty)."},
	{"sig": "fuel_name() / fuel_count()",
		"desc": "Read the fuel slot's item name / quantity (\"\" / 0 when empty)."},
	{"sig": "output_name() / output_count()",
		"desc": "Read the output slot's item name / quantity (\"\" / 0 when empty)."},
]

# ── Grouped view ───────────────────────────────────────────────────
# Two top-level groups so CUSTOM (this game) is never mixed with BUILT-IN
# (the language), each split by language. Returns an Array of:
#   { "title": String, "note": String,
#     "languages": [ {"name": String, "entries": Array}, ... ] }
static func groups() -> Array:
	return [
		{
			"title": "CUSTOM FUNCTIONS — THIS GAME",
			"note": "The robot and station APIs this world adds. Program against these.",
			"languages": [
				{"name": "LUA — ROBOT", "entries": CUSTOM_LUA_ROBOT},
				{"name": "LUA — BUILDING", "entries": CUSTOM_LUA_BUILD},
				{"name": "LUA — CRAFTING STATION", "entries": CUSTOM_LUA_STATION},
				{"name": "PYTHON — CRAFTING STATION", "entries": CUSTOM_PYTHON_STATION},
				{"name": "PYTHON — FURNACE", "entries": CUSTOM_PYTHON_FURNACE},
			],
		},
		{
			"title": "BUILT-IN FUNCTIONS — LANGUAGE",
			"note": "Standard functions that ship with the programming language itself.",
			"languages": [
				{"name": "LUA", "entries": BUILTIN_LUA},
				{"name": "PYTHON", "entries": BUILTIN_PYTHON},
			],
		},
	]

# One compact line per entry, for tight hint labels (station tab).
static func summary_lines(entries: Array) -> PackedStringArray:
	var out := PackedStringArray()
	for e in entries:
		out.append("%s — %s" % [str(e["sig"]), str(e["desc"])])
	return out
