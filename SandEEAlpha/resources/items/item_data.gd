extends Resource
class_name ItemData

# ── Identity ──────────────────────────────────────────────────────
@export var item_name:    String     = ""
@export var description:  String     = ""

# ── Type ──────────────────────────────────────────────────────────
@export_enum("material", "block", "door", "weapon", "consumable") var item_type: String = "material"
@export var effect: String = ""

# ── Inventory icon ────────────────────────────────────────────────
@export var icon: Texture2D

# ── Placement (block / door only) ────────────────────────────────
## Enable to allow this item to be placed in the world
@export var is_placeable: bool = false

## Separate sprite shown when placed in the world (leave blank to reuse icon)
@export var placeable_sprite: Texture2D

## Enable if the placed sprite has an animation to play
@export var has_place_animation: bool = false

## Name of the animation to play on the placed object
@export var place_animation_name: String = ""

# ── Crafting ─────────────────────────────────────────────────────
## Enable to make this item appear in the crafting menu
@export var is_craftable: bool = false

# ── World scene ───────────────────────────────────────────────────
## Scene instantiated when this item is placed on the map
@export var place_scene_path: String = ""

# ── Helper: build the inventory dict the game uses internally ─────
func to_dict() -> Dictionary:
	return {
		"quantity":          1,
		"type":              item_type,
		"name":              item_name,
		"effect":            effect,
		"texture":           icon,
		"scene_path":        "res://scenes/ui/InventoryItem.tscn",
		"place_scene_path":  place_scene_path if is_placeable else "",
	}
