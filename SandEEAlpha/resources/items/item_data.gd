extends Resource
class_name ItemData

# ── Identity ──────────────────────────────────────────────────────
@export var item_name:    String     = ""
@export var description:  String     = ""

# ── Type ──────────────────────────────────────────────────────────
@export_enum("material", "block", "door", "weapon", "consumable") var item_type: String = "material"
@export var effect: String = ""

# ── Dev items ─────────────────────────────────────────────────────
## World-gen/game-placed only (e.g. cave ore placeholders) — never appears
## in any player-facing UI (Hotbar, Inventory, crafting menu) and can never
## be picked up, mined, or crafted into the inventory. Enforced centrally in
## Global.add_item(), the single funnel every acquisition path goes through.
@export var is_dev_item: bool = false

# ── Weapon ────────────────────────────────────────────────────────
## Enable to allow this weapon to cut solid grass tufts (grass is otherwise uncuttable)
@export var is_sword: bool = false

## Sword tier: base damage = sword_level + 3, and every 3 levels the grass
## slash grows one tile taller (one above + one below the tile in front),
## capping at 2 tiles each side — damage keeps scaling past the cap.
@export_range(1, 100) var sword_level: int = 1

## Sword attack damage: LV1 = 4, +1 per level, uncapped.
func sword_damage() -> int:
	return sword_level + 3

## Vertical grass-slash radius (tiles above AND below the tile in front of
## the player): LV1-3 = 0 (single tile), +1 every 3 levels, capped at 2 each.
func sword_slash_radius() -> int:
	return mini(2, (sword_level - 1) / 3)

# ── Inventory icon ────────────────────────────────────────────────
@export var icon: Texture2D

# ── Inventory stacking ─────────────────────────────────────────────
## Whether this item can stack in inventory slots
@export var stackable: bool = true

## Maximum number of items per stack (1-999)
@export_range(1, 999) var max_stack_size: int = 99

# ── Placement (block / door only) ────────────────────────────────
## Enable to allow this item to be placed in the world
@export var is_placeable: bool = false

## Separate sprite shown when placed in the world (leave blank to reuse icon)
@export var placeable_sprite: Texture2D

## Enable if the placed sprite has an animation to play
@export var has_place_animation: bool = false

## Name of the animation to play on the placed object
@export var place_animation_name: String = ""

## 1:x HORIZONTAL sprite-sheet (each frame 32x32) that animates the placed
## object when has_place_animation is on. When set, this takes over from
## place_animation_name (the placed block plays the sheet instead of needing a
## scene with an AnimationPlayer). Frames are always 32x32.
@export var place_animation_sheet: Texture2D

## How many frames are in place_animation_sheet (the "x" in the 1:x sheet).
@export_range(1, 64) var place_animation_frame_count: int = 1

## Playback speed of the placed-object animation, in frames per second.
@export_range(1, 60) var place_animation_fps: float = 8.0

## When placed, this item emits a warm flickering torch glow (PointLight2D).
## Visible at night and inside caves where the ambient light is dark.
@export var is_torch: bool = false

# ── Furnace fuel ────────────────────────────────────────────────────
## Enable to allow this item to be loaded into a furnace's fuel slot.
@export var is_fuel: bool = false

## How much smelting fuel this item provides (one fuel level = one smelt).
## A recipe with fuel_level_required = N can be smelted by a single fuel
## whose fuel_level >= N (e.g. a LV1 recipe smelts with one LV1-or-better fuel).
@export_range(1, 10) var fuel_level: int = 1

# ── Crafting ─────────────────────────────────────────────────────
## Enable to make this item appear in the crafting menu
@export var is_craftable: bool = false

# ── Block breaking ────────────────────────────────────────────────
## For block items: hardness 0-10; break duration = block_level - pickaxe_level (seconds, min 0.1)
@export_range(0, 10) var block_level: int = 0

## Minimum pickaxe_level required to break this block (0 = any pickaxe works)
@export_range(0, 10) var min_pickaxe_level: int = 0

# ── Pickaxe tier ──────────────────────────────────────────────────
## For pickaxe items: mining tier (0 = wooden, higher = faster / unlocks harder blocks)
@export_range(0, 10) var pickaxe_level: int = 0

# ── World scene ───────────────────────────────────────────────────
## Scene instantiated when this item is placed on the map
@export var place_scene_path: String = ""

# ── Validation: tools cannot stack ──────────────────────────────────
func _validate_property(property: Dictionary) -> void:
	if property["name"] == "stackable" and stackable:
		# Tools (weapons, pickaxes, swords) cannot stack
		if is_sword or sword_level > 0 or pickaxe_level > 0:
			property["value"] = false

# ── Helper: build the inventory dict the game uses internally ─────
# Returns the canonical {"data": ItemData, "quantity": int} slot format
# used by Global.Hotbar / Global.Inventory / chest_block etc.
func to_dict(quantity: int = 1) -> Dictionary:
	return {
		"data":     self,
		"quantity": quantity,
	}
