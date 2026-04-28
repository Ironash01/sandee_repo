extends Node2D

# ── Block type flags ──────────────────────────────────────────────
var item_data: ItemData = null

const HITS_TO_BREAK:  int = 3
const ITEM_SCENE: PackedScene = preload("res://scenes/ui/InventoryItem.tscn")

var _hit_count:     int      = 0
var _player_nearby: bool     = false
var _world_cell:    Vector2i = Vector2i(-99999, -99999)
var _world_ref:     Node     = null

@onready var _sprite:   Sprite2D = $Sprite2D
@onready var _interact: Area2D   = $InteractArea

func _ready() -> void:
	if item_data != null:
		_apply_sprite()
	_interact.body_entered.connect(_on_body_entered)
	_interact.body_exited.connect(_on_body_exited)

func setup(data: ItemData) -> void:
	item_data = data
	if _sprite != null:
		_apply_sprite()

# Called by world.gd after placement so we can unregister on break
func set_world_cell(cell: Vector2i, world: Node) -> void:
	_world_cell = cell
	_world_ref  = world

func _apply_sprite() -> void:
	var tex: Texture2D = item_data.placeable_sprite \
		if item_data.placeable_sprite != null \
		else item_data.icon
	_sprite.texture = tex

# ── Interaction ───────────────────────────────────────────────────
func _input(event: InputEvent) -> void:
	if not _player_nearby:
		return
	if event is InputEventMouseButton \
			and event.pressed \
			and event.button_index == MOUSE_BUTTON_LEFT:
		_try_hit()

func _try_hit() -> void:
	# All blocks require a pickaxe
	if not _player_has_pickaxe():
		return   # silently block — no pickaxe equipped
	_hit_count += 1
	if _hit_count >= HITS_TO_BREAK:
		_break()

func _player_has_pickaxe() -> bool:
	var selected = Global.get_hotbar_item()
	if _is_pickaxe(selected):
		return true
	for slot in Global.Hotbar:
		if slot != null and _is_pickaxe(slot):
			return true
	return false

func _is_pickaxe(slot) -> bool:
	if slot == null:
		return false
	var data: ItemData = slot["data"] as ItemData
	if data == null:
		return false
	return data.item_name.to_lower().contains("pickaxe")

func _break() -> void:
	# Unregister this cell from the world so the spot can be re-used
	if _world_ref != null and _world_ref.has_method("unregister_block"):
		_world_ref.call("unregister_block", _world_cell)
	# Drop the item back into the world
	if item_data != null:
		var drop: Node = ITEM_SCENE.instantiate() as Node
		drop.call("set_item_data", item_data)
		get_parent().add_child(drop)
		drop.global_position = global_position + Vector2(0, -16)
	queue_free()

func _on_body_entered(body: Node) -> void:
	if body.is_in_group("Player"):
		_player_nearby = true

func _on_body_exited(body: Node) -> void:
	if body.is_in_group("Player"):
		_player_nearby = false
