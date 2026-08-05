extends Node2D
class_name MissionGuideArrow
# ── Mission guide arrow ────────────────────────────────────────────
# A small gold arrow hovering above the player's head that points at the
# accepted dungeon's entrance portal and shows the straight-line distance
# (in blocks/tiles). Added as a child of the player in player.gd.
#
# The target comes from the ACTIVE world: the overworld exposes
# get_dungeon_guide_target() (world.gd) and the arrow queries it via a
# has_method() guard, so inside a cave/dungeon (whose worlds don't have that
# method) the arrow simply hides. It also hides when there's no accepted
# dungeon mission, when the portal is gone (dungeon cleared), or once the
# player is right on top of the portal.

const COLOR:    Color = Color(1.0, 0.85, 0.20, 1.0)
const OUTLINE:  Color = Color(0.20, 0.15, 0.00, 0.85)
const TEXT_COL: Color = Color(1.0, 0.95, 0.60, 1.0)

const ARROW_LEN:     float = 22.0
const ARROW_W:       float = 11.0
const STALK_LEN:     float = 10.0
const HOVER_OFFSET:  float = -46.0      # px above the player's origin
const BOB_AMPLITUDE: float = 4.0
const BOB_SPEED:     float = 3.2
const ARRIVE_RADIUS_PX: float = 90.0    # within this distance the arrow hides
const FONT_SIZE: int = 12

var _active:   bool = false
var _dir:      Vector2 = Vector2.RIGHT
var _distance: float = 0.0
var _bob_time: float = 0.0

func _ready() -> void:
	z_index = 500
	visible = false

func _process(delta: float) -> void:
	_bob_time += delta
	_update_target()

func _update_target() -> void:
	var player := Global.player_node as Node2D
	if player == null or not player.is_inside_tree():
		_set_active(false)
		return
	var world := _get_world_node()
	var target: Vector2 = Vector2.INF
	if world != null and world.has_method("get_dungeon_guide_target"):
		target = world.call("get_dungeon_guide_target") as Vector2
	if target == Vector2.INF:
		_set_active(false)
		return
	var to_target: Vector2 = target - player.global_position
	_distance = to_target.length()
	if _distance < ARRIVE_RADIUS_PX:
		_set_active(false)
		return
	_dir = to_target.normalized()
	global_position = player.global_position + Vector2(0.0, HOVER_OFFSET) \
		+ Vector2(0.0, sin(_bob_time * BOB_SPEED) * BOB_AMPLITUDE)
	_set_active(true)

# Mirrors player.gd's world lookup — the currently active world, which is the
# overworld normally and the cave/dungeon while inside one.
func _get_world_node() -> Node:
	var scene := get_tree().current_scene
	if scene == null:
		return null
	var world := scene.get_node_or_null("world_gen")
	if world == null:
		world = scene.get_node_or_null("World")
	if world == null and scene.has_node("Water"):
		world = scene
	return world

# Called every process frame. CanvasItem redraws are NOT automatic on
# transform change — without an unconditional queue_redraw() here the cached
# _draw() result (initial arrow direction + distance) would render forever.
func _set_active(active: bool) -> void:
	_active = active
	visible = active
	queue_redraw()

# The triangle is drawn relative to _dir rather than rotating this node, so
# the distance label beneath it always stays upright.
func _draw() -> void:
	if not _active:
		return
	var tip := _dir * ARROW_LEN
	var perp := _dir.orthogonal() * ARROW_W
	var back := -_dir * ARROW_LEN
	draw_colored_polygon(PackedVector2Array([tip, back + perp, back - perp]), COLOR)
	draw_line(back, back - _dir * STALK_LEN, OUTLINE, 2.0)
	var d_text := "%d blocks" % int(round(_distance / 32.0))
	var font: Font = ThemeDB.fallback_font
	var tw := font.get_string_size(d_text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE).x
	draw_string(font, Vector2(-tw * 0.5, STALK_LEN + 16.0), d_text,
		HORIZONTAL_ALIGNMENT_CENTER, -1, FONT_SIZE, TEXT_COL)
