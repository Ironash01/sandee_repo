extends Resource
class_name SmeltingRecipe

# ── Smelting recipe (used by the furnace) ─────────────────────────
# One file per recipe under resources/recipes/. Field 1 = the INPUT item that
# goes in the furnace's left slot; field 2 = the OUTPUT item it smelts into
# (previewed in the right slot before Smelt is clicked); smelt_time = how many
# seconds the smelt takes. fuel_level_required = how many fuel levels one
# smelt needs — a fuel item qualifies if its fuel_level >= this value, and
# one fuel is consumed per smelt.

@export var input_item:  ItemData
@export var output_item: ItemData
@export var smelt_time:  float = 5.0
@export var fuel_level_required: int = 1
## Optional mission id credited once per successfully smelted output item.
## Kept on the recipe so production tracking is data-driven rather than
## depending on display-name spelling (e.g. the "Ironbar" item name).
@export var mission_id: String = ""