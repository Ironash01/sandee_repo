extends Node2D

# ── Block type flags ──────────────────────────────────────────────
# Set by world.gd after instantiation via setup()
var item_data: ItemData = null

# Wooden block — requires an axe to break
var requires_axe: bool = false

const HITS_TO_BREAK:  int = 3
const ITEM_SCENE: PackedScene = preload("res://scenes/ui/InventoryItem.tscn")

var _hit_count:     int  = 0
var _player_nearby: bool = false

@onready var _sprite:  Sprite2D = $Sprite2D
@onready var _interact: Area2D  = $InteractArea

func _ready() -> void:
	if item_data != null:
		_apply_sprite()
	_interact.body_entered.connect(_on_body_entered)
	_interact.body_exited.connect(_on_body_exited)

func setup(data: ItemData) -> void:
	item_data = data
	# Determine if this is a wooden block (requires axe)
	var name_lower: String = data.item_name.to_lower()
	requires_axe = name_lower.contains("wood") or name_lower.contains("plank")
	if _sprite != null:
		_apply_sprite()

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
	if requires_axe and not _player_has_axe():
		return   # silently block — no axe equipped
	_hit_count += 1
	if _hit_count >= HITS_TO_BREAK:
		_break()

func _player_has_axe() -> bool:
	# Check the currently selected hotbar slot first, then full hotbar
	var selected = Global.get_hotbar_item()
	if _is_axe(selected):
		return true
	# Also check rest of hotbar
	for slot in Global.Hotbar:
		if slot != null and _is_axe(slot):
			return true
	return false

func _is_axe(slot) -> bool:
	if slot == null:
		return false
	var data: ItemData = slot["data"] as ItemData
	if data == null:
		return false
	return data.item_type == "weapon" and data.item_name.to_lower().contains("axe")

func _break() -> void:
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
