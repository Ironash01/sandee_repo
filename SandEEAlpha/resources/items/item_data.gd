extends Resource
class_name ItemData

# ── Identity ──────────────────────────────────────────────────────
@export var item_name:    String     = ""
@export var description:  String     = ""

# ── Type ──────────────────────────────────────────────────────────
@export_enum("material", "block", "door", "weapon", "consumable") var item_type: String = "material"
@export var effect: String = ""

# ── Fishing rod ───────────────────────────────────────────────────
## True for the fishing rod: selecting it and left-clicking a body of water
## casts a fishing attempt (see scripts/fishing_controller.gd).
@export var is_fishing_rod: bool = false

# ── Food ──────────────────────────────────────────────────────────
## Health restored when this item is eaten (left-click while selected). 0 = not
## food. Consumption is handled by player.gd.
@export var heal_amount: float = 0.0

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

## Maximum number of items per stack (hard-capped at Global.MAX_STACK)
@export_range(1, 32) var max_stack_size: int = 32

# ── Placement (block / door only) ────────────────────────────────
## Enable to allow this item to be placed in the world
@export var is_placeable: bool = false

## Separate sprite shown when placed in the world (leave blank to reuse icon)
@export var placeable_sprite: Texture2D

## True for a FLOOR block: WALKABLE (no collision) and rendered as a floor tile
## beneath the player/walls (low z-index). Floors form a house's interior.
@export var is_floor: bool = false

## True for a DOOR block: has open/closed sprites and the player toggles it with
## a click. Doors are part of a house's sealed boundary in EITHER state.
@export var is_door: bool = false

## Door: the sprite shown when the door is CLOSED (the default state).
@export var door_closed_sprite: Texture2D = null

## Door: the sprite shown when the door is OPEN.
@export var door_open_sprite: Texture2D = null

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

## Torch only: the animation sheet used when this torch is placed directly
## beside a solid block (a wall-mounted "connected" look). The art is authored
## for a block on the LEFT; it's flipped horizontally for a block on the right.
## Null = always use the centred place_animation_sheet.
@export var torch_connected_sheet: Texture2D = null

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

## True for wooden blocks (Wood, Planks). Axes chop these without needing a
## pickaxe tier and get the hidden axe wooden-block speed bonus below.
@export var wooden_block: bool = false

# ── Pickaxe tier ──────────────────────────────────────────────────
## For pickaxe items: mining tier (0 = wooden, higher = faster / unlocks harder blocks)
@export_range(0, 10) var pickaxe_level: int = 0

# ── Axe tier ──────────────────────────────────────────────────────
## For axe items: chopping tier (0 = not an axe). Trees and Wood blocks break
## base / (axe_level + 1) faster — LV1 = 2x, LV2 = 3x, LV3 = 4x.
@export_range(0, 10) var axe_level: int = 0

# Hidden wooden-block speed bonus — deliberately NOT an inspector field, so all
# three tiers sit in one easy-to-track table. Keyed by axe_level:
#   LV1 wooden axe  = +0.30x
#   LV2 iron axe    = +0.60x
#   LV3 diamond axe = +1.00x
# A wooden block's break duration is base / (1 + bonus).
const AXE_WOOD_BLOCK_BONUS: Dictionary = {1: 0.3, 2: 0.6, 3: 1.0}

## Extra chopping speed vs wooden blocks for this axe (0.0 for non-axes).
func axe_wood_block_bonus() -> float:
	return float(AXE_WOOD_BLOCK_BONUS.get(axe_level, 0.0))

# ── World scene ───────────────────────────────────────────────────
## Scene instantiated when this item is placed on the map
@export var place_scene_path: String = ""

# ── Color blocks (generated at runtime by the Color Crafter) ──────
## True for a runtime-generated solid-color block. Such items have NO .tres on
## disk, so Global's save/load serializes block_color instead of a path and
## rebuilds the item via ColorBlock on load.
@export var is_color_block: bool = false
## The solid fill colour of a color block (ignored for every other item).
@export var block_color: Color = Color(0, 0, 0)

# ── Validation: tools cannot stack ──────────────────────────────────
func _validate_property(property: Dictionary) -> void:
	if property["name"] == "stackable" and stackable:
		# Tools (weapons, pickaxes, swords) cannot stack
		if is_sword or sword_level > 0 or pickaxe_level > 0 or axe_level > 0:
			property["value"] = false

# ── Helper: build the inventory dict the game uses internally ─────
# Returns the canonical {"data": ItemData, "quantity": int} slot format
# used by Global.Hotbar / Global.Inventory / chest_block etc.
func to_dict(quantity: int = 1) -> Dictionary:
	return {
		"data":     self,
		"quantity": quantity,
	}
