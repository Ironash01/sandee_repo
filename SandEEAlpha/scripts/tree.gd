extends Node2D

enum TreeType { Plain, Snowy, NewTree }

@export var tree_type: TreeType = TreeType.Plain

const TILE_SIZE:       int        = 32
const WOOD_DROP_COUNT: int        = 4
const ITEM_SCENE:  PackedScene = preload("res://scenes/ui/InventoryItem.tscn")
const WOOD_DATA:   ItemData    = preload("res://resources/items/wood.tres")
# Tree's local origin (0,0) is the trunk's visual base, with the canopy
# sprite extending UPWARD (negative y) from there — anywhere in that negative
# range sits inside/behind the canopy, which is what made the old -24.0
# value look like it was drawing behind the tree. Canopy height also differs
# per tree type (NewTree ~96px vs Snowy ~64px), so a fixed negative offset
# can't reliably clear it for every tree anyway. Positive y (below the trunk
# base, on the ground) is always clear regardless of tree type/size, and
# matches how the block break bar sits close to the sprite's base.
const BREAK_BAR_Y_OFFSET: float = 10.0

var _player_nearby: bool = false
var _hovered:       bool = false

# ── Breaking state — continuous hold, same pattern as placeable_block.gd.
# Not tool-gated: chopping works from the start of the game, no axe needed.
# Duration comes straight from WOOD_DATA.block_level (no level to subtract).
var _breaking:       bool  = false
var _break_duration: float = 1.0
var _break_elapsed:  float = 0.0
var _break_progress: float = 0.0
var _mouse_held:     bool  = false

@onready var _sprite:   Sprite2D = $Sprite2D
@onready var _interact: Area2D   = $InteractArea

func _ready() -> void:
	set_process(false)
	_interact.body_entered.connect(_on_body_entered)
	_interact.body_exited.connect(_on_body_exited)

# ── Process: hover tracking + breaking timer ─────────────────────
func _process(delta: float) -> void:
	if not _player_nearby:
		return
	_update_hover()
	if not _mouse_held or not _hovered:
		_cancel_breaking()
		return
	_break_elapsed  = minf(_break_elapsed + delta, _break_duration)
	_break_progress = _break_elapsed / _break_duration if _break_duration > 0.0 else 1.0
	queue_redraw()
	if _break_elapsed >= _break_duration:
		_destroy()

func _update_hover() -> void:
	if _sprite.texture == null:
		_hovered = false
		return
	var mouse_local: Vector2 = to_local(get_global_mouse_position())
	# Hover box matches the sprite's actual frame bounds, centred on the sprite
	# position offset (sprite.position.y = -(texture_height/2) set at spawn time).
	var half_w: float = (_sprite.texture.get_width()  / float(maxi(_sprite.hframes, 1))) * 0.5
	var half_h: float = (_sprite.texture.get_height() / float(maxi(_sprite.vframes, 1))) * 0.5
	_hovered = abs(mouse_local.x - _sprite.position.x) <= half_w \
		   and abs(mouse_local.y - _sprite.position.y) <= half_h \
		   and not Global.block_mode

func _draw() -> void:
	if not _breaking:
		return
	Global.draw_break_bar(self, _break_progress, BREAK_BAR_Y_OFFSET)

# ── Input ─────────────────────────────────────────────────────────
func _input(event: InputEvent) -> void:
	if not _player_nearby or Global.block_mode or Global.any_ui_open() or Global.pause_menu_open:
		return
	if not _hovered:
		if _breaking:
			_cancel_breaking()
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			get_viewport().set_input_as_handled()
			_mouse_held = true
			_try_start_breaking()
		else:
			_mouse_held = false
			if _breaking:
				_cancel_breaking()

func _try_start_breaking() -> void:
	if _breaking:
		return
	_break_duration = maxf(0.1, float(WOOD_DATA.block_level))
	_break_elapsed  = 0.0
	_break_progress = 0.0
	_breaking       = true
	queue_redraw()

# ── Public: autonomous chopping (Lua NPC) ─────────────────────────
# Advances the same timer the player's hold-to-break uses, in fixed
# increments called on a delay loop rather than driven by mouse input.
func chop(amount: float) -> void:
	if not _breaking:
		_break_duration = maxf(0.1, float(WOOD_DATA.block_level))
		_breaking       = true
	_break_elapsed  = minf(_break_elapsed + amount, _break_duration)
	_break_progress = _break_elapsed / _break_duration if _break_duration > 0.0 else 1.0
	queue_redraw()
	if _break_elapsed >= _break_duration:
		_destroy()

func _cancel_breaking() -> void:
	if not _breaking:
		return
	_breaking       = false
	_break_elapsed  = 0.0
	_break_progress = 0.0
	queue_redraw()

# ── Destroy ───────────────────────────────────────────────────────
func _destroy() -> void:
	_breaking = false
	# Use the global reference rather than get_parent() to avoid coupling to scene structure.
	var world: Node = Global.world_node
	if is_instance_valid(world) and world.has_method("notify_tree_removed"):
		world.call("notify_tree_removed", self)
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
		_mouse_held    = false
		_cancel_breaking()
		set_process(false)
