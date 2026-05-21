extends Node2D

var item_data: ItemData = null

const ITEM_SCENE:         PackedScene = preload("res://scenes/ui/InventoryItem.tscn")
const INTERACT_RADIUS_PX: float       = 64.0

var _player_nearby: bool     = false
var _world_cell:    Vector2i = Vector2i(-99999, -99999)
var _world_ref:     Node     = null

# ── Breaking state ────────────────────────────────────────────────
var _breaking:       bool  = false
var _break_duration: float = 1.0
var _break_elapsed:  float = 0.0
var _break_progress: float = 0.0
var _mouse_held:     bool  = false

@onready var _sprite:   Sprite2D = $Sprite2D
@onready var _interact: Area2D   = $InteractArea

func _ready() -> void:
	set_process(false)
	if item_data != null:
		_apply_sprite()
	_interact.body_entered.connect(_on_body_entered)
	_interact.body_exited.connect(_on_body_exited)

func setup(data: ItemData) -> void:
	item_data = data
	if _sprite != null:
		_apply_sprite()

func set_world_cell(cell: Vector2i, world: Node) -> void:
	_world_cell = cell
	_world_ref  = world

func _apply_sprite() -> void:
	var tex: Texture2D = item_data.placeable_sprite \
		if item_data.placeable_sprite != null \
		else item_data.icon
	_sprite.texture = tex

# ── Breaking timer + progress bar ────────────────────────────────
func _process(delta: float) -> void:
	if not _mouse_held or not _player_within_radius():
		_cancel_breaking()
		return
	_break_elapsed  = minf(_break_elapsed + delta, _break_duration)
	_break_progress = _break_elapsed / _break_duration if _break_duration > 0.0 else 1.0
	queue_redraw()
	if _break_elapsed >= _break_duration:
		_break()

func _draw() -> void:
	if not _breaking:
		return
	const W := 32.0
	const H := 5.0
	const Y := -20.0
	draw_rect(Rect2(-W * 0.5, Y, W,                    H), Color(0.10, 0.10, 0.10, 0.85))
	draw_rect(Rect2(-W * 0.5, Y, W * _break_progress,  H), Color(0.30, 0.90, 0.30, 1.00))

# ── Input ─────────────────────────────────────────────────────────
func _input(event: InputEvent) -> void:
	if not _player_nearby or Global.block_mode or Global.any_ui_open() or Global.pause_menu_open:
		return
	if not _player_within_radius():
		if _breaking:
			_cancel_breaking()
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_mouse_held = true
			_try_start_breaking()
		else:
			_mouse_held = false
			if _breaking:
				_cancel_breaking()

func _player_within_radius() -> bool:
	if Global.player_node == null:
		return true
	return (Global.player_node as Node2D).global_position.distance_to(global_position) <= INTERACT_RADIUS_PX

func _try_start_breaking() -> void:
	if _breaking:
		return
	var pick_lvl := _get_held_pickaxe_level()
	if pick_lvl < 0:
		return  # no pickaxe held
	var min_lvl  := item_data.min_pickaxe_level if item_data != null else 0
	if pick_lvl < min_lvl:
		return  # pickaxe tier too low for this block
	var block_lvl := item_data.block_level if item_data != null else 0
	_break_duration = maxf(0.1, float(block_lvl - pick_lvl))
	_break_elapsed  = 0.0
	_break_progress = 0.0
	_breaking       = true
	set_process(true)
	queue_redraw()

func _cancel_breaking() -> void:
	_breaking       = false
	_break_elapsed  = 0.0
	_break_progress = 0.0
	set_process(false)
	queue_redraw()

func _get_held_pickaxe_level() -> int:
	var slot = Global.get_hotbar_item()
	if slot == null:
		return -1
	var data: ItemData = slot["data"] as ItemData
	if data == null or not data.item_name.to_lower().contains("pickaxe"):
		return -1
	return data.pickaxe_level

func _break() -> void:
	_breaking = false
	set_process(false)
	if _world_ref != null and _world_ref.has_method("unregister_block"):
		_world_ref.call("unregister_block", _world_cell)
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
		if _breaking:
			_cancel_breaking()
