@tool
extends Node2D

@export var item_data: ItemData

var scene_path: String = "res://scenes/ui/InventoryItem.tscn"

@onready var icon_sprite: Sprite2D = $Sprite2D

var player_in_range: bool = false
var npc_in_range:    Node  = null   # LuaNPC that is close enough to collect

# ── Wobble ────────────────────────────────────────────────────────
const WOBBLE_SPEED:      float = 3.0   # rotations per second (radians)
const WOBBLE_AMPLITUDE:  float = 0.18  # radians (~10°)
const DROP_SCALE:        float = 0.55  # dropped items are smaller than full size
var   _wobble_time:      float = 0.0

func _ready() -> void:
	# Smaller scale for dropped items in the world
	scale = Vector2(DROP_SCALE, DROP_SCALE)
	# Random phase offset so items don't all wobble in sync
	_wobble_time = randf_range(0.0, TAU)

	if not Engine.is_editor_hint():
		if item_data != null:
			icon_sprite.texture = item_data.icon

func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		if item_data != null:
			icon_sprite.texture = item_data.icon
		return

	# Wobble rotation
	_wobble_time += delta * WOBBLE_SPEED
	rotation = sin(_wobble_time) * WOBBLE_AMPLITUDE

	if player_in_range:
		pickup_item()

# ── Player pickup ─────────────────────────────────────────────────
func pickup_item() -> void:
	if item_data == null:
		return
	if Global.add_item({"quantity": 1, "data": item_data}):
		queue_free()

# ── NPC pickup — called directly by LuaNPC after interact ─────────
func npc_pickup(npc: Node) -> bool:
	if item_data == null:
		return false
	# Set the item directly on LuaState so Lua can read held_item next run
	var lua_state: Node = npc.get_node_or_null("LuaState")
	if lua_state == null:
		return false
	lua_state.set("held_item", item_data.item_name)
	lua_state.set("held_item_quantity", 1)
	queue_free()
	return true

func set_item_data(data: ItemData) -> void:
	item_data = data
	if icon_sprite:
		icon_sprite.texture = data.icon

func _on_area_2d_body_entered(body: Node2D) -> void:
	if body.is_in_group("Player"):
		player_in_range = true

func _on_area_2d_body_exited(body: Node2D) -> void:
	if body.is_in_group("Player"):
		player_in_range = false
