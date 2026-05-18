extends Node2D

enum TreeType { Plain, Desert, Snowy }

@export var tree_type: TreeType = TreeType.Plain

const TILE_SIZE:       int        = 32
const HITS_TO_DESTROY: int        = 5
const WOOD_DROP_COUNT: int        = 4
const ITEM_SCENE:  PackedScene = preload("res://scenes/ui/InventoryItem.tscn")
const WOOD_DATA:   ItemData    = preload("res://resources/items/wood.tres")

var _hit_count:     int  = 0
var _player_nearby: bool = false
var _hovered:       bool = false

@onready var _sprite:   Sprite2D         = $Sprite2D
@onready var _interact: Area2D           = $InteractArea
@onready var _anim:     AnimationPlayer  = $tree_shake

func _ready() -> void:
	set_process(false)   # enabled only while player is within interact range
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

	# Sprite2D is center-anchored — shift up so its bottom aligns with tile bottom.
	if _sprite.texture:
		var frame_h: float = float(_sprite.texture.get_height())
		_sprite.position.y = (TILE_SIZE / 2.0) - (frame_h / 2.0)

# ── Hover tracking — only runs while player is nearby ─────────────
# Sets _hovered so _input knows which tile the cursor is on.
# The visual highlight is drawn globally by world.gd.
func _process(_delta: float) -> void:
	var mouse_local: Vector2 = to_local(get_global_mouse_position())
	var half: float          = TILE_SIZE * 0.5
	_hovered = abs(mouse_local.x) <= half and abs(mouse_local.y) <= half \
		and not Global.block_mode

# ── Input ─────────────────────────────────────────────────────────
func _input(event: InputEvent) -> void:
	if not _player_nearby or not _hovered or Global.block_mode:
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		get_viewport().set_input_as_handled()
		hit()

# ── Public — called by player click OR LuaNPC ─────────────────────
func hit() -> void:
	_hit_count += 1
	if _anim != null:
		_anim.stop()
		_anim.play("plain_shake")
	if _hit_count >= HITS_TO_DESTROY:
		_destroy()

func _destroy() -> void:
	var world: Node = get_parent()
	if is_instance_valid(world) and world.has_method("notify_tree_removed"):
		world.call("notify_tree_removed", global_position)
	_drop_wood()
	queue_free()

func _drop_wood() -> void:
	for i in range(WOOD_DROP_COUNT):
		var item: Node      = ITEM_SCENE.instantiate()
		var offset: Vector2 = Vector2(randf_range(-24, 24), randf_range(-24, 24))
		item.global_position = global_position + offset
		item.call("set_item_data", WOOD_DATA)
		get_parent().add_child(item)

# ── Proximity ─────────────────────────────────────────────────────
func _on_body_entered(body: Node) -> void:
	if body.is_in_group("Player"):
		_player_nearby = true
		set_process(true)

func _on_body_exited(body: Node) -> void:
	if body.is_in_group("Player"):
		_player_nearby = false
		_hovered       = false
		set_process(false)
