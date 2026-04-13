extends Resource
class_name CraftingRecipe

# ── Result ────────────────────────────────────────────────────────
@export var result_item:     ItemData
@export var result_quantity: int = 1

# ── Ingredients (max 2) ───────────────────────────────────────────
@export var ingredient_1:          ItemData
@export var ingredient_1_quantity: int = 1

@export var ingredient_2:          ItemData
@export var ingredient_2_quantity: int = 1

# ── Category (drives which tab this appears under) ────────────────
@export_enum("Materials", "Blocks", "Weapons", "Others") var category: String = "Materials"

# ── Station requirement ───────────────────────────────────────────
## If true, player must be near a Crafting Station to craft this
@export var requires_station: bool = false
