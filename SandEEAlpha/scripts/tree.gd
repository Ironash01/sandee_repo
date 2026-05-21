extends Node2D

enum TreeType { Plain, Snowy, NewTree }

@export var tree_type: TreeType = TreeType.Plain

const TILE_SIZE:       int        = 32
const HITS_TO_DESTROY: int        = 5
const WOOD_DROP_COUNT: int        = 4
const ITEM_SCENE:  PackedScene = preload("res://scenes/ui/InventoryItem.tscn")
const WOOD_DATA:   ItemData    = preload("res://resources/items/wood.tres")

var _hit_count:     int   = 0
var _player_nearby: bool  = false
var _hovered:       bool  = false
var _shake_tween:   Tween = null

@onready var _sprite:   Sprite2D = $Sprite2D
@onready var _interact: Area2D   = $InteractArea

func _ready() -> void:
	set_process(false)
	_interact.body_entered.connect(_on_body_entered)
	_interact.body_exited.connect(_on_body_exited)


# ── Process: hover tracking only ─────────────────────────────────
func _process(_delta: float) -> void:
	if not _player_nearby:
		return
	if _sprite.texture == null:
		_hovered = false
		return
	var mouse_local: Vector2 = to_local(get_global_mouse_position())
	# Hover box matches the sprite's actual frame bounds, centred on the sprite
	# position offset (sprite.position.y = -(texture_height/2) set at spawn time).
	# The old code used TILE_SIZE*0.5 at origin, which only covered the bottom
	# 16px sliver of a 96px-tall tree.
	var half_w: float = (_sprite.texture.get_width()  / float(maxi(_sprite.hframes, 1))) * 0.5
	var half_h: float = (_sprite.texture.get_height() / float(maxi(_sprite.vframes, 1))) * 0.5
	_hovered = abs(mouse_local.x - _sprite.position.x) <= half_w \
		   and abs(mouse_local.y - _sprite.position.y) <= half_h \
		   and not Global.block_mode

# ── Input ─────────────────────────────────────────────────────────
func _input(event: InputEvent) -> void:
	if not _player_nearby or not _hovered or Global.block_mode:
		return
	if event is InputEventMouseButton and event.pressed \
			and event.button_index == MOUSE_BUTTON_LEFT:
		get_viewport().set_input_as_handled()
		hit()

# ── Hit & shake ───────────────────────────────────────────────────
func hit() -> void:
	_hit_count += 1
	_play_shake()
	if _hit_count >= HITS_TO_DESTROY:
		_destroy()

func _play_shake() -> void:
	if _shake_tween != null and _shake_tween.is_running():
		_shake_tween.kill()
	_sprite.position.x = 0.0
	_shake_tween = create_tween()
	_shake_tween.tween_property(_sprite, "position:x",  5.0, 0.05)
	_shake_tween.tween_property(_sprite, "position:x", -5.0, 0.08)
	_shake_tween.tween_property(_sprite, "position:x",  3.5, 0.06)
	_shake_tween.tween_property(_sprite, "position:x", -2.0, 0.05)
	_shake_tween.tween_property(_sprite, "position:x",  0.0, 0.05)

# ── Destroy ───────────────────────────────────────────────────────
func _destroy() -> void:
	# Use the global reference rather than get_parent() to avoid coupling to scene structure.
	var world: Node = Global.world_node
	if is_instance_valid(world) and world.has_method("notify_tree_removed"):
		world.call("notify_tree_removed", global_position)
	Global.complete_mission("cut_tree")
	_drop_wood()
	queue_free()

func _drop_wood() -> void:
	for i in range(WOOD_DROP_COUNT):
		var item: Node      = ITEM_SCENE.instantiate()
		var offset: Vector2 = Vector2(randf_range(-24, 24), randf_range(-24, 24))
		item.call("set_item_data", WOOD_DATA)
		get_parent().add_child(item)
		item.global_position = global_position + offset

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
