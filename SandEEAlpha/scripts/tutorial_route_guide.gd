extends Node2D
class_name TutorialRouteGuide

# Dotted route markers for the guided dungeon walk. The tutorial director
# computes a floor-only BFS path and hands it the turn/waypoint cells. Dots only
# — no numbers or text — so the trail reads as a clear path to follow.

const C_FILL: Color = Color(0.06, 0.13, 0.22, 0.86)
const C_RING: Color = Color(0.35, 0.96, 0.88, 1.0)
const C_LINE: Color = Color(0.35, 0.96, 0.88, 0.35)

var _points: Array = []
var _pulse: float = 0.0

func _ready() -> void:
	z_as_relative = false
	z_index = 4010
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_process(true)
	visible = false

func set_route(points: Array) -> void:
	_points = points.duplicate()
	visible = not _points.is_empty()
	queue_redraw()

func clear_route() -> void:
	_points.clear()
	visible = false
	queue_redraw()

func _process(delta: float) -> void:
	if not visible:
		return
	_pulse += delta
	queue_redraw()

func _draw() -> void:
	if _points.is_empty():
		return
	if Global.any_ui_open() or Global.pause_menu_open:
		return
	var s: float = Global.ui_scale
	var wave: float = 0.5 + 0.5 * sin(_pulse * 3.4)
	# Dotted connector first so the route discs stay legible.
	for i in range(1, _points.size()):
		var a: Vector2 = _points[i - 1] as Vector2
		var b: Vector2 = _points[i] as Vector2
		var seg := a.distance_to(b)
		var steps := maxi(1, int(ceil(seg / (18.0 * s))))
		for k in range(steps):
			var t := float(k) / float(steps)
			draw_circle(a.lerp(b, t), maxf(1.2, 1.8 * s), C_LINE)
	for i in range(_points.size()):
		var p: Vector2 = _points[i] as Vector2
		var is_last: bool = i == _points.size() - 1
		var r: float = (11.0 if is_last else 9.0) * s
		r += wave * 1.2 * s
		draw_circle(p, r, C_FILL)
		draw_arc(p, r, 0.0, TAU, 24, C_RING, (2.4 if is_last else 1.8) * s)
