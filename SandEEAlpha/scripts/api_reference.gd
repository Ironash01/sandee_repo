extends RefCounted
class_name APIReference

# ── In-game function reference (single source of truth) ─────────────
# Shared by the Programming Encyclopedia (player inventory tab +
# scripts/lua_editor_ui.gd), the Crafting Station's Programming tab
# (scripts/crafting_menu.gd) and the code editor's autocomplete/lint.
#
# The game has TWO automation systems, and this file keeps them apart:
#   • AUTOMATICA   — custom LUA functions used to program the LUA robot.
#   • ALGORITHMICA — custom PYTHON functions used to automate crafting
#                    stations and furnaces.
# Language documentation (the Lua / Python standard library) is kept in its
# own sections and never mixed with the game's automation APIs.
#
# Every entry is {"id", "sig", "desc"}:
#   id   — STABLE identifier. Discovery gating (scripts/encyclopedia_data.gd)
#          and save data key off this, so it must never be renamed casually.
#   sig  — the signature exactly as callable.
#   desc — one-line help.
# Keep these lists in sync with the real callable surface:
#   Lua    → extension/src/runner/lua.rs + the preamble in lua_editor_ui.gd
#   Python → resources/godot_station_base.gd + resources/godot_furnace_base.gd
#            (+ extension/src/transpiler/spec.rs for the language built-ins)

# ── Automatica: Lua robot ──────────────────────────────────────────
const CUSTOM_LUA_ROBOT: Array = [
	{"id": "automatica.auto_work", "sig": "auto_work()",
		"desc": "Full work cycle: chop all trees in radius → deposit collected items into the nearest chest → return to station."},
	{"id": "automatica.chop_trees", "sig": "chop_trees(radius)",
		"desc": "Chop every tree within radius blocks of the station (1-64 blocks, defaults to 20 if omitted). Collects dropped items after each tree, then walks home. The radius also draws as the blue ring (right-click the station to toggle it)."},
	{"id": "automatica.deposit_chest", "sig": "deposit_chest()",
		"desc": "Walk to the nearest chest within radius, deposit everything in the robot's inventory, then return to the station."},
	{"id": "automatica.chest_contents", "sig": "chest_contents()",
		"desc": "Print the contents of the nearest chest to the output panel. Outputs each item and quantity, or a message if the chest is empty or out of range."},
	{"id": "automatica.return_to_spawn", "sig": "return_to_spawn()",
		"desc": "Walk the robot directly back to the station and stop. Use this to abort a long task or reset position."},
	{"id": "automatica.craft_example", "sig": "craft_example()",
		"desc": "Minimal station example: select Planks, craft one, then collect it. The station needs the recipe's ingredients in its input slot or your inventory. Copy these calls into your program."},
	{"id": "automatica.move", "sig": "move(x, y)",
		"desc": "Set the robot's movement velocity to (x, y) pixels per second. Positive x = east, positive y = south. Call move(0, 0) to stop. Sequences of move() calls all fire instantly — only the last value takes effect."},
	{"id": "automatica.interact", "sig": "interact()",
		"desc": "Execute the pending action. With no sentinel move() before it, defaults to chopping all trees then returning home. Actions requested while the robot is busy are queued and run in order."},
	{"id": "automatica.attack", "sig": "attack()",
		"desc": "Perform the robot's attack action (swing its held weapon). REQUIRES a tool in the robot's tool slot — with none equipped it prints \"No tool equipped\" and does nothing."},
	{"id": "automatica.drop_item", "sig": "drop_item(qty)",
		"desc": "Drop up to qty copies from the Automatica's selected build slot, or from its general inventory when the slot is empty. The dropped stack is capped by what the robot actually carries."},
	{"id": "automatica.place_item", "sig": "place_item(dx = 0, dy = 0)",
		"desc": "Place one block from the selected build slot at a tile offset from the robot. With no offsets it places at the robot's own tile. The slot must hold a placeable block."},
	{"id": "automatica.mine", "sig": "mine(name)",
		"desc": "Mine every placed block matching a normalized block reference within the Automatica's current work radius. It paths around walls to reach each target, skips blocks it cannot reach, and shows the same break ring as player mining. References are lowercase snake_case: mine(\"stone_block\") matches Stone, mine(\"birch_wood\") matches Birch Wood. A trailing _block is optional. See 'Automatica — Mineable Block Names' below for the full copy-ready list. REQUIRES a tool in the robot's tool slot — with none equipped it prints \"No tool equipped\" and starts no work."},
	{"id": "automatica.rename", "sig": "rename(name)",
		"desc": "Give the robot a custom name. It is shown above the robot itself."},
	{"id": "automatica.combat_mode", "sig": "combat_mode(on)",
		"desc": "true: send this Automatica into COMBAT MODE — it abandons its station, follows you, and attacks nearby hostile mobs with its TOOL slot. It cannot run code while in combat and has HP (enemies can hurt it). false: return it to its station as a normal blue Automatica."},
	{"id": "automatica.list_items", "sig": "list_items()",
		"desc": "Return a sorted list of every item name in the game. Useful for building withdraw(\"name\", n) / put_input(\"name\", n) calls without guessing names."},
]

# ── Automatica: Lua building (robot build slots) ───────────────────
const CUSTOM_LUA_BUILD: Array = [
	{"id": "automatica.select_block", "sig": "select_block(i)",
		"desc": "Choose which build slot (0, 1 or 2) place_item() places from."},
	{"id": "automatica.place_item_at", "sig": "place_item(dx, dy)",
		"desc": "Place one block from the selected build slot at a tile offset from the robot. The same call as the optional-offset form above; one block per call."},
	{"id": "automatica.place_at", "sig": "place_at(x, y)",
		"desc": "Place one block at absolute tile coordinates (x, y)."},
	{"id": "automatica.withdraw", "sig": "withdraw(\"name\", n)",
		"desc": "Walk to the nearest chest holding the named item and take up to n, e.g. withdraw(\"Wood\", 10) or withdraw(\"Iron Ore\", 5). Item display names and scripting ids both work; placeable blocks go to the build palette, other items to the robot inventory."},
	{"id": "automatica.build_line", "sig": "build_line(x0, y0, x1, y1)",
		"desc": "Gap-free straight line of blocks between two offsets (uses Bresenham, so diagonals don't skip tiles)."},
	{"id": "automatica.build_rect", "sig": "build_rect(x0, y0, w, h, filled)",
		"desc": "Rectangle w by h at offset (x0, y0); filled = solid slab, otherwise just the border."},
	{"id": "automatica.build_circle", "sig": "build_circle(r, filled)",
		"desc": "Circle of radius r centred on the robot; filled = disc, otherwise an outline."},
	{"id": "automatica.build_ring", "sig": "build_ring(r)",
		"desc": "Hollow ring of radius r."},
	{"id": "automatica.build_spiral", "sig": "build_spiral(r, turns)",
		"desc": "Archimedean spiral out to radius r over `turns` turns."},
	{"id": "automatica.build_wave", "sig": "build_wave(len, amp)",
		"desc": "Sine-wave fence `len` tiles long and `amp` tiles tall."},
	{"id": "automatica.build_stairs", "sig": "build_stairs(n)",
		"desc": "Diagonal staircase of n steps."},
]

# ── Automatica: Lua station helpers (still robot functions) ─────────
const CUSTOM_LUA_STATION: Array = [
	{"id": "automatica.station.craft", "sig": "craft(n)",
		"desc": "Craft n of the station's currently selected automation recipe."},
	{"id": "automatica.station.set_recipe", "sig": "set_recipe(name)",
		"desc": "Select the automation recipe by output name, e.g. set_recipe(\"Planks\")."},
	{"id": "automatica.station.take_output", "sig": "take_output()",
		"desc": "Move the station's finished output into the robot's stores: placeable outputs go to its build palette, other outputs to its general inventory."},
	{"id": "automatica.station.put_input", "sig": "put_input(\"name\", n)",
		"desc": "Walk to the nearest station and load n of the named item into its INPUT slot for automatic crafting, e.g. put_input(\"Wood\", 10)."},
	{"id": "automatica.station.input_slot", "sig": "input_slot(n)",
		"desc": "Walk to the nearest station and load n of the SELECTED build-slot item into its INPUT slot (no item name needed)."},
	{"id": "automatica.station.held_item", "sig": "held_item",
		"desc": "Variable: a table {name, quantity} for the item the robot is holding, or nil."},
	{"id": "automatica.station.station_recipe", "sig": "station_recipe",
		"desc": "Variable: the name of the station's selected recipe (read-only)."},
	{"id": "automatica.station.station_output", "sig": "station_output_item / station_output_count",
		"desc": "Variables: the station's pending output item name and quantity (read-only)."},
]

# ── Algorithmica: Python crafting-station API ───────────────────────
# "target" is the machine the function actually acts on — taken from the
# implementation (resources/godot_station_base.gd → StationPythonHost).
const CUSTOM_PYTHON_STATION: Array = [
	{"id": "algorithmica.station.craft", "sig": "craft(amount)", "target": "Crafting Station",
		"desc": "Craft amount of the station's currently selected automation recipe."},
	{"id": "algorithmica.station.craft_color", "sig": "craft_color(r, g, b, amount)", "target": "Crafting Station",
		"desc": "Craft amount (1-32) solid-color blocks from 8-bit RGB integers r,g,b (0-255; pure black/white rejected), using 1 Cactus per block. Output goes to the station slot; call take_output() to collect. Returns crafted count, or 0 with a printed reason (e.g. \"[craft_color] Insufficient Cactus\") without consuming materials. Example: craft_color(255, 0, 0, 2) then take_output()."},
	{"id": "algorithmica.station.get_recipe", "sig": "get_recipe()", "target": "Crafting Station",
		"desc": "Return the name of the station's selected recipe."},
	{"id": "algorithmica.station.set_recipe", "sig": "set_recipe(name)", "target": "Crafting Station",
		"desc": "Select the automation recipe by output name, e.g. set_recipe(\"Planks\")."},
	{"id": "algorithmica.station.output_item", "sig": "output_item()", "target": "Crafting Station",
		"desc": "Return the name of the station's pending output item."},
	{"id": "algorithmica.station.output_count", "sig": "output_count()", "target": "Crafting Station",
		"desc": "Return how many of the pending output item are ready."},
	{"id": "algorithmica.station.take_output", "sig": "take_output()", "target": "Crafting Station",
		"desc": "Move the station's finished output into the player's inventory."},
]

# ── Algorithmica: Python furnace API ────────────────────────────────
# "target" comes from resources/godot_furnace_base.gd → FurnacePythonHost.
const CUSTOM_PYTHON_FURNACE: Array = [
	{"id": "algorithmica.furnace.feed", "sig": "feed(name, n)", "target": "Furnace",
		"desc": "Move up to n of the named item from your inventory into the INPUT (smeltable) slot. Returns how many were loaded."},
	{"id": "algorithmica.furnace.fuel", "sig": "fuel(name, n)", "target": "Furnace",
		"desc": "Move up to n of the named FUEL item from your inventory into the FUEL slot. Returns how many were loaded."},
	{"id": "algorithmica.furnace.smelt", "sig": "smelt(n)", "target": "Furnace",
		"desc": "Smelt up to n, consuming input AND one fuel each. Fuel must already be in the fuel slot (never auto-consumed). Returns how many were smelted."},
	{"id": "algorithmica.furnace.take_output", "sig": "take_output()", "target": "Furnace",
		"desc": "Move the furnace's output slot into your inventory. Returns how many were taken."},
	{"id": "algorithmica.furnace.input_name", "sig": "input_name() / input_count()", "target": "Furnace",
		"desc": "Read the input slot's item name / quantity (\"\" / 0 when empty)."},
	{"id": "algorithmica.furnace.fuel_name", "sig": "fuel_name() / fuel_count()", "target": "Furnace",
		"desc": "Read the fuel slot's item name / quantity (\"\" / 0 when empty)."},
	{"id": "algorithmica.furnace.output_name", "sig": "output_name() / output_count()", "target": "Furnace",
		"desc": "Read the output slot's item name / quantity (\"\" / 0 when empty)."},
]

# ── Algorithmica: copy-ready code templates ────────────────────────
# Shared by the encyclopedia and the editors' TEMPLATE/COLOR buttons so the
# examples can never drift from each other. Comment-free by design: the code
# is meant to be pressed RUN immediately.
const ALGORITHMICA_STATION_TEMPLATE: String = """set_recipe("Planks")
craft(1)
take_output()
"""
const ALGORITHMICA_FURNACE_TEMPLATE: String = """feed("iron_ore", 5)
fuel("charcoal", 3)
smelt(5)
take_output()
"""
const ALGORITHMICA_FURNACE_FOOD_TEMPLATE: String = """feed("sheep_meat", 4)
fuel("charcoal", 2)
smelt(4)
take_output()
"""
const ALGORITHMICA_COLOR_TEMPLATE: String = """craft_color(255, 0, 0, 2)
take_output()
"""

static func algorithmica_template_entries() -> Array:
	return [
		{
			"id": "algorithmica.template.station",
			"name": "1. Craft planks",
			"target": "Crafting Station",
			"sig": "Crafting Station",
			"desc": "Select Planks, craft one, then collect it. Change the recipe or amount for other station recipes.",
			"code": ALGORITHMICA_STATION_TEMPLATE,
		},
		{
			"id": "algorithmica.template.color",
			"name": "2. Color block",
			"target": "Crafting Station",
			"sig": "Color Crafter (craft_color)",
			"desc": "Craft two red Color Blocks at a Crafting Station. craft_color uses 1 Cactus per block; pure black and pure white are rejected.",
			"code": ALGORITHMICA_COLOR_TEMPLATE,
		},
		{
			"id": "algorithmica.template.furnace",
			"name": "1. Smelt iron",
			"target": "Furnace",
			"sig": "Furnace",
			"desc": "Load iron ore and charcoal, smelt five bars, then collect them. Fuel is never consumed automatically.",
			"code": ALGORITHMICA_FURNACE_TEMPLATE,
		},
		{
			"id": "algorithmica.template.furnace_food",
			"name": "2. Cook sheep meat",
			"target": "Furnace",
			"sig": "Furnace — cooking",
			"desc": "Cook four raw sheep meat into cooked sheep meat. Use any smeltable food and its matching fuel.",
			"code": ALGORITHMICA_FURNACE_FOOD_TEMPLATE,
		},
	]

# Templates relevant to one editor target, in list order.
static func templates_for(target: String) -> Array:
	var out: Array = []
	for entry in algorithmica_template_entries():
		if str((entry as Dictionary).get("target", "")) == target:
			out.append(entry)
	return out

# ── Lua programming language (standard library) ────────────────────
const BUILTIN_LUA: Array = [
	{"id": "lua.print", "sig": "print(val, ...)",
		"desc": "Print a value to the output panel. Accepts strings, numbers, and booleans."},
	{"id": "lua.type", "sig": "type(v)",
		"desc": "Return the type name of v, e.g. \"number\", \"string\", \"table\"."},
	{"id": "lua.tostring", "sig": "tostring(v) / tonumber(v)",
		"desc": "Convert a value to a string / to a number (returns nil if it can't)."},
	{"id": "lua.pairs", "sig": "pairs(t) / ipairs(t)",
		"desc": "Iterate a table in for loops — pairs() over all keys, ipairs() over the array part in order."},
	{"id": "lua.math_floor", "sig": "math.floor(x) / math.ceil(x)",
		"desc": "Round x down / up to a whole number."},
	{"id": "lua.math_abs", "sig": "math.abs(x) / math.sqrt(x)",
		"desc": "Absolute value / square root of x."},
	{"id": "lua.math_min", "sig": "math.min(a, b) / math.max(a, b)",
		"desc": "Smaller / larger of two numbers."},
	{"id": "lua.math_random", "sig": "math.random(m, n)",
		"desc": "Random number: integer in m..n, or a float in 0..1 with no arguments."},
	{"id": "lua.string_format", "sig": "string.format(fmt, ...)",
		"desc": "Build a formatted string, e.g. string.format(\"%d apples\", 3)."},
	{"id": "lua.string_len", "sig": "string.len(s) / string.upper(s) / string.lower(s)",
		"desc": "Length / upper-case / lower-case of a string."},
	{"id": "lua.table_insert", "sig": "table.insert(t, v) / table.remove(t, i)",
		"desc": "Add v to the end of table t / remove the element at index i."},
	{"id": "lua.table_sort", "sig": "table.sort(t) / table.concat(t, sep)",
		"desc": "Sort table t in place / join its elements into a string with sep."},
	{"id": "lua.error_handling", "sig": "pcall(f, ...) / xpcall(f, handler) / error(msg) / assert(cond)",
		"desc": "Protected calls and errors: pcall runs f and returns ok, result; error raises a message; assert stops when cond is false."},
	{"id": "lua.metatable", "sig": "setmetatable(t, mt) / getmetatable(t)",
		"desc": "Attach or read a metatable — the basis of Lua's object-oriented patterns."},
	{"id": "lua.vector", "sig": "vector",
		"desc": "Built-in vector value with x / y fields and methods: vector.new(x, y), vector.from_angle(a), vector.mag(), vector.normalized(), vector.dot(other), vector.with_mag(m)."},
]

# ── Python programming language (what the transpiler supports) ─────
const BUILTIN_PYTHON: Array = [
	{"id": "python.print", "sig": "print(...)",
		"desc": "Print values to the output panel. Multiple arguments are separated by spaces."},
	{"id": "python.len", "sig": "len(obj)",
		"desc": "Return the number of items in a string, list, or dictionary."},
	{"id": "python.range", "sig": "range(n)",
		"desc": "Return the numbers 0..n-1, for use in for loops."},
	{"id": "python.int", "sig": "int(v) / float(v)",
		"desc": "Convert v to an integer / floating-point number."},
	{"id": "python.bool", "sig": "bool(v)",
		"desc": "Convert v to a boolean."},
	{"id": "python.abs", "sig": "abs(v) / pow(a, b)",
		"desc": "Absolute value of v / a raised to the power b."},
	{"id": "python.min", "sig": "min(a, b) / max(a, b)",
		"desc": "Smaller / larger of two numbers."},
]

# ── Encyclopedia sections (order matters) ──────────────────────────
const SECTION_LUA_LANGUAGE := "lua_language"
const SECTION_AUTOMATICA   := "automatica"
const SECTION_AUTOMATICA_BLOCKS := "automatica_blocks"
const SECTION_PYTHON       := "python_language"
const SECTION_ALGORITHMICA := "algorithmica"
const SECTION_ALGORITHMICA_TEMPLATES := "algorithmica_templates"

# The six sections of the Programming Encyclopedia, in display order:
#   1. LUA Programming Language      (language concepts, discovered in dungeons)
#   2. Automatica                    (LUA robot functions, available immediately)
#   3. Automatica — Mineable Blocks  (copy-ready mine() references, collapsed)
#   4. Python Programming Language   (language concepts, discovered in dungeons)
#   5. Algorithmica                  (Python automation functions, available immediately)
#   6. Algorithmica — Code Templates (complete station/furnace/color programs)
# "kind" drives the UI: language sections reveal entries through dungeon
# discovery, function sections are always fully listed. "start_expanded"
# overrides the initial accordion state for a function section.
# Language documentation stays separate from the game's automation APIs.
static func encyclopedia_sections() -> Array:
	return [
		{
			"id": SECTION_LUA_LANGUAGE,
			"kind": "language",
			"title": "LUA Programming Language",
			"note": "The Lua language itself — syntax and standard library, learned in dungeons.",
			"entries": BUILTIN_LUA,
		},
		{
			"id": SECTION_AUTOMATICA,
			"kind": "functions",
			"title": "Automatica — LUA Functions",
			"note": "Custom Lua functions used to program Automatica: movement, navigation, combat, building and station work.",
			"entries": automatica_entries(),
		},
		{
			"id": SECTION_AUTOMATICA_BLOCKS,
			"kind": "functions",
			"title": "Automatica — Mineable Block Names",
			"note": "Copy-ready mine() references for every placeable block. Names are lowercase snake_case: spaces and punctuation become _, and a trailing _block is optional — mine(\"stone_block\") and mine(\"stone\") both mine Stone. The block's display name also works, e.g. mine(\"Birch Wood\").",
			"start_expanded": false,
			"entries": mineable_block_entries(),
		},
		{
			"id": SECTION_PYTHON,
			"kind": "language",
			"title": "Python Programming Language",
			"note": "The Python language itself — syntax and built-ins supported by the transpiler.",
			"entries": BUILTIN_PYTHON,
		},
		{
			"id": SECTION_ALGORITHMICA,
			"kind": "functions",
			"title": "Algorithmica — Python Automation Functions",
			"note": "Custom Python functions that imbue regular items with automation at crafting stations and furnaces. Every entry is tagged with the machine it drives.",
			"entries": algorithmica_entries(),
		},
		{
			"id": SECTION_ALGORITHMICA_TEMPLATES,
			"kind": "functions",
			"title": "Algorithmica — Code Templates",
			"note": "Complete, comment-free programs. Copy the calls into a machine's CODE tab and press RUN.",
			"start_expanded": false,
			"entries": algorithmica_template_entries(),
		},
	]

# Automatica = every custom LUA function the robot can call.
static func automatica_entries() -> Array:
	return CUSTOM_LUA_ROBOT + CUSTOM_LUA_BUILD + CUSTOM_LUA_STATION

# ── Mineable block references ──────────────────────────────────────
# Shared by mine() and the encyclopedia so the displayed reference can never
# drift from the matcher. Lowercase snake_case, punctuation runs become _, and
# a trailing _block is optional: "Stone Block" -> "stone", "Birch Wood" ->
# "birch_wood", "Wheat (Grown)" -> "wheat_grown".
static func block_reference(value: String) -> String:
	var input: String = value.strip_edges().to_lower()
	var out: String = ""
	var last_sep: bool = false
	for i in range(input.length()):
		var c: String = input[i]
		var is_letter: bool = c >= "a" and c <= "z"
		var is_digit: bool = c >= "0" and c <= "9"
		if is_letter or is_digit:
			out += c
			last_sep = false
		elif not out.is_empty() and not last_sep:
			out += "_"
			last_sep = true
	while out.ends_with("_"):
		out = out.substr(0, out.length() - 1)
	if out.ends_with("_block"):
		out = out.substr(0, out.length() - 6)
	return out

# Every placeable block in the catalogue, as a copy-ready mine() reference.
# Generated from ItemData so new blocks appear automatically. Deduplicated by
# reference because the connected-torch variant shares the Torch item id.
static func mineable_block_entries() -> Array:
	var out: Array = []
	var seen: Dictionary = {}
	for data in Global.list_all_items():
		if data == null or not data.is_placeable or data.place_scene_path.is_empty():
			continue
		var ref: String = block_reference(data.item_id())
		if ref.is_empty() or seen.has(ref):
			continue
		seen[ref] = true
		out.append({
			"id": "automatica.mine_block.%s" % ref,
			"sig": "mine(\"%s_block\")" % ref,
			"desc": data.item_name,
		})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return str(a["desc"]) < str(b["desc"]))
	return out

# Algorithmica = every custom PYTHON function the automation hosts expose.
static func algorithmica_entries() -> Array:
	return CUSTOM_PYTHON_STATION + CUSTOM_PYTHON_FURNACE

# Flat lookup by stable id (used by discovery gating + tests).
static func entry_by_id(id: String) -> Dictionary:
	for section in encyclopedia_sections():
		for e in (section["entries"] as Array):
			if str(e.get("id", "")) == id:
				return e as Dictionary
	return {}

# ── Editor-facing grouping ─────────────────────────────────────────
# Kept for the code editor's autocomplete/lint, which only needs to know
# "which language does this name belong to". The Programming Encyclopedia
# itself uses encyclopedia_sections() above.
static func groups() -> Array:
	return [
		{
			"title": "CUSTOM FUNCTIONS — THIS GAME",
			"note": "The robot and station APIs this world adds. Program against these.",
			"languages": [
				{"name": "AUTOMATICA — ROBOT", "entries": CUSTOM_LUA_ROBOT},
				{"name": "AUTOMATICA — BUILDING", "entries": CUSTOM_LUA_BUILD},
				{"name": "AUTOMATICA — STATION HELPERS", "entries": CUSTOM_LUA_STATION},
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
