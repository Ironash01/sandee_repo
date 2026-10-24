extends Node2D
class_name PNCIndicator

# ── Point-and-click feedback marker ───────────────────────────────
# Owned by player.gd (one instance, desktop + Android alike). Draws:
#   • move order  → pulsing ring at the destination;
#   • act order   → amber ring where the character will stop to interact;
#   • mob target  → red ring at the mob's feet + a bobbing SWORD icon above it.
# `pulse()` is the quick click acknowledgement used when the action happens
# immediately; `show_at()`/`follow()` persist until the order ends.
#
# It is a top-level Node2D (the player sets top_level) with a high z_index, so
# it draws over the world regardless of y-sorting, and is freed with the player.

const C_MOVE   := Color(0.55, 0.90, 1.00, 1.00)
const C_ACT    := Color(1.00, 0.80, 0.35, 1.00)
const C_ATTACK := Color(1.00, 0.35, 0.35, 1.00)
const C_FISH   := Color(0.55, 0.80, 1.00, 1.00)
const SWORD_DATA: ItemData = preload("res://resources/items/iron_sword.tres")
const ROD_DATA:   ItemData = preload("res://resources/items/fishing_rod.tres")

const RING_RADIUS := 11.0
const SWORD_BOB    := 2.0
const SWORD_Y      := -42.0

var _mode: String      = "move"
var _follow: Node2D    = null
var _age: float        = 0.0
var _fade_time: float  = -1.0   # < 0 = stay until hidden
var _sword: Sprite2D   = null

func _ready() -> void:
	z_as_relative = false
	# 4096 is Godot's CANVAS_ITEM_Z_MAX; stay just under it so the marker draws
	# over y-sorted world sprites without an engine error.
	z_index       = 4000
	_sword = Sprite2D.new()
	_sword.texture        = SWORD_DATA.icon if SWORD_DATA != null else null
	_sword.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_sword.scale          = Vector2(0.8, 0.8)
	_sword.position       = Vector2(0.0, SWORD_Y)
	_sword.visible        = false
	add_child(_sword)
	visible = false

func show_at(world_pos: Vector2, mode: String = "move") -> void:
	_follow       = null
	_mode         = mode
	global_position = world_pos
	_age          = 0.0
	_fade_time    = -1.0
	visible       = true
	_apply_icon()
	queue_redraw()

func follow(target: Node2D) -> void:
	follow_mode(target, "attack")

func follow_mode(target: Node2D, mode: String = "act") -> void:
	_follow    = target
	_mode      = mode
	_age       = 0.0
	_fade_time = -1.0
	visible    = target != null and is_instance_valid(target)
	if visible:
		global_position = target.global_position
	_apply_icon()
	queue_redraw()

# Attack → sword icon; fishing → rod icon; everything else → ring only.
func _apply_icon() -> void:
	if _sword == null:
		return
	match _mode:
		"attack":
			_sword.texture = SWORD_DATA.icon if SWORD_DATA != null else null
			_sword.visible = true
		"fish":
			_sword.texture = ROD_DATA.icon if ROD_DATA != null else null
			_sword.visible = true
		_:
			_sword.visible = false

func pulse(world_pos: Vector2, mode: String = "act") -> void:
	show_at(world_pos, mode)
	_fade_time = 0.45

func hide_marker() -> void:
	_follow = null
	visible = false
	if _sword != null:
		_sword.visible = false
	queue_redraw()

func _process(delta: float) -> void:
	if not visible:
		return
	_age += delta
	if _follow != null:
		if is_instance_valid(_follow):
			global_position = _follow.global_position
		else:
			hide_marker()
			return
	if _fade_time > 0.0 and _age >= _fade_time:
		hide_marker()
		return
	if _sword != null and _sword.visible:
		_sword.position.y = SWORD_Y + sin(_age * 6.0) * SWORD_BOB
	queue_redraw()

func _draw() -> void:
	var col: Color = C_ATTACK if _mode == "attack" else (C_ACT if _mode == "act" else C_MOVE)
	var fade: float = 1.0
	if _fade_time > 0.0:
		fade = clampf(1.0 - _age / _fade_time, 0.0, 1.0)
	var pulse: float = 0.5 + 0.5 * sin(_age * 6.0)
	col.a = fade
	draw_arc(Vector2.ZERO, RING_RADIUS + pulse * 3.0, 0.0, TAU, 28, col, 2.0, true)
	draw_circle(Vector2.ZERO, 3.0, col)
