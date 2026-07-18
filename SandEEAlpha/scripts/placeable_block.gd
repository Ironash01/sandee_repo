extends Node2D

var item_data: ItemData = null

const ITEM_SCENE:         PackedScene = preload("res://scenes/ui/InventoryItem.tscn")
const INTERACT_RADIUS_PX: float       = 64.0
const SHADOW_TEXTURE:     Texture2D   = preload("res://sprites/shadow/shadow_blockbase.png")

var _player_nearby: bool     = false
var _hovered:       bool     = false
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
	add_child(Global.make_shadow_sprite(SHADOW_TEXTURE, Vector2(0.0, 10.0), Vector2(0.8, 0.4), 0.35))
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

# ── Process: hover tracking + breaking timer ─────────────────────
# InteractArea's radius (64px) covers a 4-tile-wide circle, so several
# adjacent placed blocks can ALL have _player_nearby true at once. Without
# an actual mouse-hover check, one click used to start breaking on every
# nearby block simultaneously. _hovered (checked against this block's own
# sprite bounds, same approach as tree.gd) scopes the click to only the
# block actually under the cursor.
func _process(delta: float) -> void:
	if not _player_nearby:
		return
	_update_hover()
	if not _mouse_held or not _hovered or not _player_within_radius():
		_cancel_breaking()
		return
	_break_elapsed  = minf(_break_elapsed + delta, _break_duration)
	_break_progress = _break_elapsed / _break_duration if _break_duration > 0.0 else 1.0
	queue_redraw()
	if _break_elapsed >= _break_duration:
		_break()

func _update_hover() -> void:
	if _sprite.texture == null:
		_hovered = false
		return
	var mouse_local: Vector2 = to_local(get_global_mouse_position())
	var half_w: float = (_sprite.texture.get_width()  / float(maxi(_sprite.hframes, 1))) * 0.5
	var half_h: float = (_sprite.texture.get_height() / float(maxi(_sprite.vframes, 1))) * 0.5
	_hovered = abs(mouse_local.x - _sprite.position.x) <= half_w \
		   and abs(mouse_local.y - _sprite.position.y) <= half_h \
		   and not Global.block_mode

func _draw() -> void:
	if not _breaking:
		return
	Global.draw_break_bar(self, _break_progress)

# ── Input ─────────────────────────────────────────────────────────
func _input(event: InputEvent) -> void:
	if not _player_nearby or Global.block_mode or Global.any_ui_open() or Global.pause_menu_open:
		return
	if not _hovered or not _player_within_radius():
		if _breaking:
			_cancel_breaking()
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			# Extra safety alongside _hovered: if two blocks' sprites ever
			# overlap (large placeable art), only the first one in node
			# order consumes the click instead of both reacting to it.
			if get_viewport().is_input_handled():
				return
			get_viewport().set_input_as_handled()
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
	queue_redraw()

func _cancel_breaking() -> void:
	if not _breaking:
		return
	_breaking       = false
	_break_elapsed  = 0.0
	_break_progress = 0.0
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
		set_process(true)

func _on_body_exited(body: Node) -> void:
	if body.is_in_group("Player"):
		_player_nearby = false
		_hovered       = false
		_mouse_held    = false
		_cancel_breaking()
		set_process(false)
