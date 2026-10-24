extends Node2D
# ── Wheat crop ─────────────────────────────────────────────────────
# Planted on a Tilled Plot. Starts as the small sprout sprite and matures into
# the full wheat after GROW_SECONDS (3 minutes). A sword cut only harvests it
# once grown; cutting the sprout does nothing (it keeps growing).

const GROW_SECONDS: float = 180.0   # 3 minutes, per the farming spec
const SPRITE_UNGROWN: Texture2D = preload("res://sprites/items/wheat_ungrown.png")
const SPRITE_GROWN:   Texture2D = preload("res://sprites/items/wheat_grown.png")
const WHEAT_ITEM: ItemData = preload("res://resources/items/wheat.tres")
const SEEDS_ITEM: ItemData = preload("res://resources/items/wheat_seeds.tres")
const ITEM_SCENE: PackedScene = preload("res://scenes/ui/InventoryItem.tscn")
const HARVEST_SEEDS_CHANCE: float = 0.5

var cell: Vector2i = Vector2i.ZERO
var grown: bool = false
var elapsed: float = 0.0

@onready var _sprite: Sprite2D = $Sprite2D

func _ready() -> void:
	add_to_group("Crops")
	_refresh()
	# Same quantized Y-sort bucket the rest of the world uses.
	z_index = int(global_position.y / 32.0) + 1

func _process(delta: float) -> void:
	if grown:
		return
	elapsed += delta
	if elapsed >= GROW_SECONDS:
		grown = true
		_refresh()

func _refresh() -> void:
	if _sprite != null:
		_sprite.texture = SPRITE_GROWN if grown else SPRITE_UNGROWN

# Sword hit. Returns true when a MATURE crop was harvested (the caller then
# forgets the cell); a sprout is left alone.
func harvest() -> bool:
	if not grown:
		return false
	_drop(WHEAT_ITEM, randi_range(1, 3))
	if randf() < HARVEST_SEEDS_CHANCE:
		_drop(SEEDS_ITEM, 1)
	queue_free()
	return true

func _drop(data: ItemData, qty: int) -> void:
	var parent: Node = get_parent()
	if parent == null or not is_instance_valid(parent) or data == null:
		return
	var drop: Node = ITEM_SCENE.instantiate()
	if drop == null:
		return
	drop.set("item_data", data)
	drop.set("quantity", qty)
	parent.add_child(drop)
	(drop as Node2D).global_position = global_position + Vector2(randf_range(-5.0, 5.0), -4.0)
