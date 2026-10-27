extends Node2D
class_name TutorialArrow

# A world-space compass arrow above the player, pointing at the current tutorial
# target. It complements the target tile marker: the marker says WHAT to use,
# while this arrow says WHERE it is when it is off to the side or off-screen.
#
# The arrow never blocks input and is removed with the tutorial. It follows the
# player through world swaps because the guide attaches it to the persistent
# player node.

const COLOR: Color = Color(0.40, 0.96, 0.88, 1.0)
const OUTLINE: Color = Color(0.03, 0.18, 0.20, 0.95)
const TEXT_COL: Color = Color(0.82, 1.0, 0.98, 1.0)
const ARROW_LEN: float = 24.0
const ARROW_W: float = 11.0
const HOVER_OFFSET: float = -82.0
const BOB_AMPLITUDE: float = 4.0
const BOB_SPEED: float = 3.4
const ARRIVE_RADIUS_PX: float = 44.0

var _target: Vector2 = Vector2.INF
var _label: String = ""
var _bob_time: float = 0.0
var _dir: Vector2 = Vector2.RIGHT
var _distance: float = 0.0
var _active: bool = false

func _ready() -> void:
	top_level = true
	z_as_relative = false
	z_index = 4050
	visible = false
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_process(true)

func set_target(world_pos: Vector2, label: String = "") -> void:
	_target = world_pos
	_label = label
	if _target == Vector2.INF:
		_set_active(false)

func clear_target() -> void:
	_target = Vector2.INF
	_label = ""
	_set_active(false)

func _process(delta: float) -> void:
	_bob_time += delta
	if Global.any_ui_open() or Global.pause_menu_open:
		_set_active(false)
		return
	var player := Global.player_node as Node2D
	if player == null or not is_instance_valid(player) or _target == Vector2.INF:
		_set_active(false)
		return
	var to_target: Vector2 = _target - player.global_position
	_distance = to_target.length()
	if _distance <= ARRIVE_RADIUS_PX:
		_set_active(false)
		return
	_dir = to_target.normalized()
	global_position = player.global_position + Vector2(0.0, HOVER_OFFSET) \
		+ Vector2(0.0, sin(_bob_time * BOB_SPEED) * BOB_AMPLITUDE)
	_set_active(true)
	queue_redraw()

func _set_active(active: bool) -> void:
	if visible == active and _active == active:
		return
	_active = active
	visible = active
	queue_redraw()

func _draw() -> void:
	if not _active:
		return
	var s: float = Global.ui_scale
	var tip: Vector2 = _dir * ARROW_LEN * s
	var back: Vector2 = -_dir * ARROW_LEN * s
	var perp: Vector2 = _dir.orthogonal() * ARROW_W * s
	draw_colored_polygon(PackedVector2Array([tip, back + perp, back - perp]), COLOR)
	draw_polyline(PackedVector2Array([tip, back + perp, back - perp, tip]), OUTLINE, 1.5 * s)
	draw_line(Vector2.ZERO, back - _dir * 5.0 * s, OUTLINE, 2.5 * s)
	var d_text: String = "%d blocks" % maxi(1, int(round(_distance / 32.0)))
	if not _label.is_empty():
		d_text = "%s  •  %s" % [_label, d_text]
	var font := ThemeDB.fallback_font
	var fs: int = Global.ui_font_size(10.0)
	var tw: float = font.get_string_size(d_text, HORIZONTAL_ALIGNMENT_CENTER, -1, fs).x
	var pos := Vector2(-tw * 0.5, ARROW_LEN * s + 17.0 * s)
	for ox in [-1.0, 0.0, 1.0]:
		for oy in [-1.0, 0.0, 1.0]:
			if ox == 0.0 and oy == 0.0:
				continue
			draw_string(font, pos + Vector2(ox, oy), d_text,
				HORIZONTAL_ALIGNMENT_CENTER, -1, fs, Color(0.0, 0.0, 0.0, 0.9))
	draw_string(font, pos, d_text, HORIZONTAL_ALIGNMENT_CENTER, -1, fs, TEXT_COL)
