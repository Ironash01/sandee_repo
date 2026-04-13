extends Node2D

enum TreeType { Plain, Desert, Snowy }

@export var tree_type: TreeType = TreeType.Plain

const HITS_TO_DESTROY: int = 5
const WOOD_DROP_COUNT: int  = 4
const ITEM_SCENE:  PackedScene = preload("res://scenes/ui/InventoryItem.tscn")
const WOOD_DATA:   ItemData    = preload("res://resources/items/wood.tres")

var _hit_count:     int  = 0
var _player_nearby: bool = false

@onready var _sprite:  Sprite2D        = $Sprite2D
@onready var _interact: Area2D         = $InteractArea
@onready var _anim:     AnimationPlayer = $tree_shake

func _ready() -> void:
	_apply_sprite()
	_interact.body_entered.connect(_on_body_entered)
	_interact.body_exited.connect(_on_body_exited)

func _apply_sprite() -> void:
	_sprite.texture = load("res://sprites/tree/basictree_alpha.png")
	match tree_type:
		TreeType.Snowy:
			_sprite.modulate = Color(0.75, 0.88, 1.0, 1.0)
		TreeType.Desert:
			_sprite.modulate = Color(1.0, 0.85, 0.55, 1.0)
		_:
			_sprite.modulate = Color(1.0, 1.0, 1.0, 1.0)

func _input(event: InputEvent) -> void:
	if not _player_nearby:
		return
	if event is InputEventMouseButton \
			and event.pressed \
			and event.button_index == MOUSE_BUTTON_LEFT:
		_on_hit()

func _on_hit() -> void:
	_hit_count += 1
	if _anim != null:
		_anim.stop()
		_anim.play("plain_shake")
	if _hit_count >= HITS_TO_DESTROY:
		_destroy()

func _destroy() -> void:
	_drop_wood()
	queue_free()

func _drop_wood() -> void:
	for i in range(WOOD_DROP_COUNT):
		var item: Node  = ITEM_SCENE.instantiate()
		var offset: Vector2 = Vector2(randf_range(-24, 24), randf_range(-24, 24))
		item.global_position = global_position + offset
		item.call("set_item_data", WOOD_DATA)
		get_parent().add_child(item)

func _on_body_entered(body: Node) -> void:
	if body.is_in_group("Player"):
		_player_nearby = true

func _on_body_exited(body: Node) -> void:
	if body.is_in_group("Player"):
		_player_nearby = false
