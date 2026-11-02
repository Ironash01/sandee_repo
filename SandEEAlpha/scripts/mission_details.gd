extends RefCounted
class_name MissionDetails

# ── Mission log content ─────────────────────────────────────────────
# The compact tracker only shows active rows. The full Mission Log uses this
# catalog so every mission can explain its task, purpose, lesson and rewards
# without bloating the mission dictionaries or the HUD.

const MAIN_REWARDS := "1 yellow quest star"
const SIDE_REWARDS := "1 yellow quest star"

const MAIN: Dictionary = {
	"auto_boot": {
		"description": "Run a Lua program on Automatica for the first time.",
		"why": "Running code is how you give the robot orders. Without a program, Automatica just waits at its station.",
		"learn": "How to open an Automatica editor, run Lua, and read the output.",
	},
	"auto_nameplate": {
		"description": "Give an Automatica a custom name with rename().",
		"why": "Clear names let you pick the right robot when several are working.",
		"learn": "Using rename() and identifying robots by name.",
	},
	"auto_timber": {
		"description": "Program the robot to chop trees with chop_trees(20).",
		"why": "Wood is the base material for tools, buildings and fuel.",
		"learn": "Automating repeated harvesting and collecting drops.",
	},
	"auto_work_cycle": {
		"description": "Run one complete auto_work() cycle.",
		"why": "The work cycle combines several robot actions into a repeatable routine.",
		"learn": "How Automatica sequences gathering jobs.",
	},
	"auto_chest_logistics": {
		"description": "Withdraw 16 Wood from a chest and print its contents.",
		"why": "Automation needs resources moved from storage to the work site.",
		"learn": "Reading chests, withdrawing items and printing state.",
	},
	"auto_line": {
		"description": "Place a 12-block line with build_line().",
		"why": "Lines are the foundation of walls, paths and patterns.",
		"learn": "Passing block names and coordinates to a build helper.",
	},
	"auto_frame": {
		"description": "Build a hollow 6x6 frame with build_rect().",
		"why": "Frames are the basic shell for rooms and structures.",
		"learn": "Building enclosed shapes with loops.",
	},
	"auto_ring": {
		"description": "Build a 20-block ring with build_ring().",
		"why": "Rings practise distance and circular placement.",
		"learn": "Using radius-based geometry in code.",
	},
	"auto_pattern": {
		"description": "Build a 16-block wave and a 12-step staircase.",
		"why": "Patterns combine loops with changing coordinates.",
		"learn": "Generating procedural shapes.",
	},
	"auto_spiral": {
		"description": "Build a 30-block spiral with build_spiral().",
		"why": "A spiral tests loop control and incremental movement.",
		"learn": "Nested loops and growing coordinates.",
	},
	"auto_miner": {
		"description": "Mine 10 Stone blocks with mine(\"stone_block\").",
		"why": "Mining automation gathers bulk materials without manual grinding.",
		"learn": "Finding blocks and controlling the robot's mining path.",
	},
	"auto_combat": {
		"description": "Enter combat_mode(true) and defeat 3 mobs with the robot.",
		"why": "A combat Automatica can defend your builds and gathering trips.",
		"learn": "Robot combat mode, targeting and support.",
	},
	"algo_boot": {
		"description": "Run a Python program on Algorithmica.",
		"why": "Algorithmica uses Python to automate crafting stations and furnaces.",
		"learn": "Opening the Python editor and running a machine program.",
	},
	"algo_recipe_reader": {
		"description": "Print the selected recipe and output count.",
		"why": "A program must read machine state before it can make decisions.",
		"learn": "Reading recipe and output data.",
	},
	"algo_planks": {
		"description": "Craft and collect 16 Planks.",
		"why": "Planks are a core building material and a simple production loop.",
		"learn": "A complete craft-and-collect automation program.",
	},
	"algo_batch": {
		"description": "Craft 16 items in one program.",
		"why": "Batch production is where automation saves the most time.",
		"learn": "Loops and repeated machine jobs.",
	},
	"algo_output_audit": {
		"description": "Inspect the output item and count before and after crafting.",
		"why": "Checking output prevents mistakes and item loss.",
		"learn": "Validating machine state.",
	},
	"algo_color_starter": {
		"description": "Craft 2 red blocks with craft_color().",
		"why": "Color crafting introduces RGB parameters and custom outputs.",
		"learn": "Calling craft_color with RGB values.",
	},
	"algo_color_wheel": {
		"description": "Craft 2 red, 2 green and 2 blue blocks.",
		"why": "Mixing colors is a practical parameter exercise.",
		"learn": "Multiple RGB combinations.",
	},
	"algo_palette": {
		"description": "Craft 16 colored blocks.",
		"why": "A palette stockpile supports larger decorative builds.",
		"learn": "Looping through color recipes.",
	},
	"algo_furnace_primer": {
		"description": "Feed, fuel, smelt and collect 5 Iron Bars.",
		"why": "Furnaces turn ore into tools, machines and building parts.",
		"learn": "A complete furnace automation cycle.",
	},
	"algo_furnace_status": {
		"description": "Print input/fuel status, then smelt 4 Iron Bars.",
		"why": "Status checks make furnace programs reliable.",
		"learn": "Reading input, fuel and output state.",
	},
	"algo_iron_line": {
		"description": "Smelt 10 Iron Bars in one program.",
		"why": "Iron production scales tools and automation.",
		"learn": "Batch smelting and fuel management.",
	},
	"algo_crystal_run": {
		"description": "Smelt 6 Crystal Iron Ore into Iron Bars.",
		"why": "Pixie Cave ores are advanced furnace inputs.",
		"learn": "Handling special ore types in a program.",
	},
}

const SIDE: Dictionary = {
	"side_worm_slayer": {
		"why": "Desert Worms are a dangerous source of Cactus and combat practice.",
		"learn": "Fighting Desert Worms and surviving the deep desert.",
	},
	"side_wolf_slayer": {
		"why": "Wolf packs threaten travellers and drop meat.",
		"learn": "Fighting groups of wolves.",
	},
	"side_pixie_slayer": {
		"why": "Pixies guard crystal caves and rare ore.",
		"learn": "Fighting Pixies in tight crystal caves.",
	},
	"side_headless_angler": {
		"why": "Headless Fish are night threats with useful fish drops.",
		"learn": "Night combat and aerial enemies.",
	},
	"side_stone_quarry": {
		"why": "Stone is needed in bulk for building and tools.",
		"learn": "Efficient stone mining.",
	},
	"side_iron_bars": {
		"why": "Iron Bars unlock stronger tools and machines.",
		"learn": "Large-scale furnace production.",
	},
	"side_diamond_prospector": {
		"why": "Diamonds are the rarest tool material.",
		"learn": "Deep cave exploration and rare ore mining.",
	},
	"side_master_builder": {
		"why": "Building is a core creative and survival activity.",
		"learn": "Planning and placing larger structures.",
	},
	"side_torchbearer": {
		"why": "Light keeps caves and nights safe.",
		"learn": "Lighting routes and builds.",
	},
	"side_cave_explorer": {
		"why": "Caves hold ores and rare chests.",
		"learn": "Finding and entering cave networks.",
	},
	"side_master_angler": {
		"why": "Fishing provides food and rare catches.",
		"learn": "Timing and patience at fishing spots.",
	},
	"side_chef": {
		"why": "Cooked food restores more health.",
		"learn": "Furnace cooking and food management.",
	},
	"side_cactus_grower": {
		"why": "Cactus is required for Color Crafter recipes.",
		"learn": "Harvesting desert cacti.",
	},
	"side_rare_chests": {
		"why": "Rare dungeon chests hold high-value loot.",
		"learn": "Recognising and opening rare caches.",
	},
	"side_chest_collector": {
		"why": "Chests organise resources and enable automation logistics.",
		"learn": "Using storage and chest networks.",
	},
	"side_lua_automator": {
		"why": "Repeated robot programs build automation fluency.",
		"learn": "Writing and running reliable Automatica jobs.",
	},
	"side_python_automator": {
		"why": "Repeated Python programs build machine automation fluency.",
		"learn": "Writing and running reliable Algorithmica jobs.",
	},
	"side_world_explorer": {
		"why": "Exploration reveals resources, dungeons and waypoints.",
		"learn": "Reading the map and covering the world.",
	},
	"side_survivor": {
		"why": "Survival tests your food, combat and planning.",
		"learn": "Long-term survival planning.",
	},
	"side_woodcutter": {
		"why": "Wood is the base resource for tools and building.",
		"learn": "Efficient tree harvesting.",
	},
}


static func details_for(mission: Dictionary) -> Dictionary:
	if mission.has("dungeon_index"):
		return _dungeon_details(mission)
	var id := str(mission.get("id", ""))
	var is_side: bool = bool(mission.get("side", false))
	var meta: Dictionary = SIDE.get(id, {}) if is_side else MAIN.get(id, {})
	var objective := str(mission.get("objective", "")).strip_edges()
	var description := str(meta.get("description", "")).strip_edges()
	if description.is_empty():
		description = str(mission.get("description", "")).strip_edges()
	if description.is_empty():
		description = objective
	var why := str(meta.get("why", "")).strip_edges()
	if why.is_empty():
		why = ("Side missions are optional challenges that deepen your mastery after the main story."
			if is_side else "This mission is part of the Automation path and unlocks the next system or tool.")
	var learn := str(meta.get("learn", "")).strip_edges()
	if learn.is_empty():
		learn = "You'll practise: %s" % objective
	return {
		"task": objective,
		"description": description,
		"why": why,
		"learn": learn,
		"rewards": SIDE_REWARDS if is_side else MAIN_REWARDS,
	}


static func _dungeon_details(mission: Dictionary) -> Dictionary:
	var idx: int = int(mission.get("dungeon_index", 0))
	var dm := Global.get_dungeon_mission_for_index(idx)
	var entry: KnowledgeEntry = dm.entry() if dm != null else null
	var task := "Read the Knowledge Altar, then answer every Quiz Altar question."
	var why := "Dungeons teach one programming idea and then prove you can use it."
	var learn := "The concept taught by this dungeon's Knowledge Altar."
	if dm != null:
		if dm.is_boss():
			task = "Enter the two-room arena and defeat the Hitman Miniboss."
			why = "The finale tests combat, navigation and preparation before the extra dungeons unlock."
			learn = "Surviving a boss arena and defeating the Hitman Miniboss."
		elif dm.is_extra():
			task = "Clear both Quiz Altars without a Knowledge Altar."
			why = "Extra dungeons are optional mastery challenges for experienced players."
			learn = "Applying programming knowledge without a fresh teaching room."
		if entry != null:
			learn = "You'll learn %s and unlock it in the Programming Encyclopedia." % entry.entry_name
	var rewards := "Up to 3 blue dungeon stars."
	var reward_item: ItemData = null
	if dm != null and not dm.reward_item_path.is_empty():
		reward_item = load(dm.reward_item_path) as ItemData
	if reward_item != null:
		rewards = "%s + up to 3 blue dungeon stars." % reward_item.item_name
	if not Global.is_dungeon_cleared(idx):
		rewards += "\nFirst clear: Life Crystal + Stamina Crystal."
	else:
		rewards += "\nEarned %d/3 blue stars." % Global.dungeon_stars_for(idx)
	return {
		"task": task,
		"description": dm.mission_description if dm != null else "A generated programming dungeon.",
		"why": why,
		"learn": learn,
		"rewards": rewards,
	}
