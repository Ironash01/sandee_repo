extends RefCounted
class_name ItemSource

# ── Item acquisition hints ──────────────────────────────────────────
# The crafting menu shows where each ingredient comes from. Authored entries
# cover the actual recipe materials; the recipe/smelting/mob fallbacks keep
# future items useful without requiring every new resource to be added here.

const RECIPE_DIR: String = "res://resources/recipes/"

const SOURCES: Dictionary = {
	"wood": "Chop trees in the plains and snowy biomes.",
	"birch_wood": "Chop birch trees in the plains biome.",
	"snowy_wood": "Chop snowy trees in the snowy biome.",
	"plains_planks": "Craft from Wood at a Crafting Station.",
	"birch_planks": "Craft from Birch Wood at a Crafting Station.",
	"snowy_planks": "Craft from Snowy Wood at a Crafting Station.",
	"stick": "Craft from Wood at a Crafting Station. Emberfox Kits and Mossback Nibs can also drop sticks.",
	"stone": "Mine natural stone blocks in the overworld or caves.",
	"coarse_sand": "Mine the coarse-sand patches on desert ground.",
	"charcoal": "Smelt Wood in a Furnace. Cinder Oozes and Gravebell Shamblers can also drop it.",
	"cactus": "Mine desert cacti, or defeat Desert Worms for a bundle of 5-10.",
	"copper_ore": "Mine copper ore in caves. Cinder Oozes can also drop it.",
	"iron_ore": "Mine iron ore in caves. Gravebell Shamblers can also drop it.",
	"silicon_ore": "Mine silicon ore in caves.",
	"diamond_ore": "Mine diamond ore in caves.",
	"copper": "Smelt Copper Ore in a Furnace. Brass Prowlers, Gravebell Shamblers and Rune Sentinels can also drop it.",
	"ironbar": "Smelt Iron Ore in a Furnace. Brass Prowlers can also drop iron bars.",
	"silicon": "Smelt Silicon Ore in a Furnace. Brass Prowlers, Cipher Wardens and Rune Sentinels can also drop silicon.",
	"diamond": "Smelt Diamond Ore in a Furnace. Cipher Wardens rarely drop diamonds.",
	"crystal_copper_ore": "Mine crystal copper ore in Pixie Caves.",
	"crystal_iron_ore": "Mine crystal iron ore in Pixie Caves.",
	"crystal_silicon_ore": "Mine crystal silicon ore in Pixie Caves. Several dungeon enemies can also drop it.",
	"crystal_diamond_ore": "Mine crystal diamond ore in Pixie Caves.",
	"wire": "Craft from Copper at a Crafting Station.",
	"ironrod": "Craft from Ironbar at a Crafting Station.",
	"torch": "Craft from Sticks and Charcoal at a Crafting Station.",
	"cpu": "Clear a dungeon Quiz Altar for a CPU, or craft one from Wire and Silicon.",
	"lua_core": "Clear a Lua dungeon's Quiz Altar.",
	"pixie_cave_stone": "Defeat Pixies in Pixie Caves.",
	"wheat": "Harvest ripe wheat from tilled soil. Wheat ripens in 3 minutes.",
	"wheat_seeds": "Cut grass, or defeat Mossback Nibs.",
	"dog_meat": "Defeat Wolves or Emberfox Kits.",
	"sheep_meat": "Defeat Sheep.",
	"cooked_dog_meat": "Cook Dog Meat in a Furnace.",
	"cooked_sheep_meat": "Cook Sheep Meat in a Furnace.",
	"white_fur": "Defeat Emberfox Kits, Mossback Nibs or Sheep.",
}

static var _fallback_sources: Dictionary = {}
static var _fallbacks_loaded: bool = false


static func where_to_get(item: ItemData) -> String:
	if item == null:
		return ""
	if item.is_color_block:
		return "Craft at a Color Crafter using RGB values and one Cactus per block."
	var id := item.item_id()
	if SOURCES.has(id):
		return str(SOURCES[id])
	_ensure_fallbacks()
	if _fallback_sources.has(id):
		return str(_fallback_sources[id])
	# Data-only fallbacks for items that have no authored hint yet.
	if item.is_wood:
		return "Chop trees for this wood."
	if item.is_seed:
		return "Cut grass, or find seeds in creature drops."
	if item.heal_amount > 0.0:
		return "Find it as food, or cook raw ingredients in a Furnace."
	if item.is_placeable or item.block_level > 0:
		return "Mine or gather it while exploring the world and caves."
	if item.is_craftable:
		return "Check the Crafting Station's recipe list."
	return "Explore, mine, fish or defeat creatures to find this item."


static func _ensure_fallbacks() -> void:
	if _fallbacks_loaded:
		return
	_fallbacks_loaded = true
	_fallback_sources.clear()
	for fname in ResourceLoader.list_directory(RECIPE_DIR):
		if not fname.ends_with(".tres"):
			continue
		var res: Resource = load(RECIPE_DIR + fname) as Resource
		if res is CraftingRecipe:
			var recipe := res as CraftingRecipe
			if recipe.result_item != null:
				_fallback_sources[recipe.result_item.item_id()] = _craft_text(recipe)
		elif res is SmeltingRecipe:
			var smelt := res as SmeltingRecipe
			if smelt.output_item != null and smelt.input_item != null:
				_fallback_sources[smelt.output_item.item_id()] = "Smelt %s in a Furnace." % smelt.input_item.item_name
	for entry in BestiaryCatalog.entries():
		var mob := entry as MobCombatData
		if mob == null:
			continue
		for drop_value in mob.drops:
			if not (drop_value is Dictionary):
				continue
			var drop := drop_value as Dictionary
			var path := str(drop.get("item_path", ""))
			if path.is_empty():
				continue
			var item := load(path) as ItemData
			if item == null:
				continue
			var id := item.item_id()
			if _fallback_sources.has(id):
				continue
			_fallback_sources[id] = "Drops from %s." % mob.mob_name


static func _craft_text(recipe: CraftingRecipe) -> String:
	var parts: Array[String] = []
	_append_ingredient(parts, recipe.ingredient_1, recipe.ingredient_1_quantity)
	_append_ingredient(parts, recipe.ingredient_2, recipe.ingredient_2_quantity)
	var where := "at a Crafting Station" if recipe.requires_station else "in the crafting menu"
	if parts.is_empty():
		return "Craft it %s." % where
	return "Craft from %s %s." % [", ".join(PackedStringArray(parts)), where]


static func _append_ingredient(parts: Array[String], item: ItemData, quantity: int) -> void:
	if item == null:
		return
	parts.append("%dx %s" % [maxi(1, quantity), item.item_name])
