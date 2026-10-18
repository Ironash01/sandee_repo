extends Node2D
class_name AttackRing

# ── Attack ring ───────────────────────────────────────────────────
# A one-shot expanding ring drawn where a combat LUA swings — the visual
# indicator of its 3x3 AoE. Pure draw (no art): it grows from a small radius to
# the full attack radius while fading out, then frees itself.

const COLOR: Color      = Color(0.85, 0.70, 1.00, 0.95)   # arcane violet
const DURATION: float   = 0.35
const WIDTH: float      = 3.0
const START_SCALE: float = 0.25

var _radius: float = 48.0
var _t:      float = 0.0
var _s:      float = 1.0

static func spawn(parent: Node, pos: Vector2, radius: float) -> Node2D:
	if parent == null or not is_instance_valid(parent):
		return null
	var fx := AttackRing.new()
	fx._radius = maxf(radius, 1.0)
	parent.add_child(fx)
	fx.global_position = pos
	fx.z_index = int(pos.y / 32.0)
	return fx

func _ready() -> void:
	_s = Global.ui_scale
	set_process(true)

func _process(delta: float) -> void:
	_t += delta
	queue_redraw()
	if _t >= DURATION:
		queue_free()

func _draw() -> void:
	var p: float = clampf(_t / DURATION, 0.0, 1.0)
	var r: float = lerpf(_radius * START_SCALE, _radius, ease(p, 2.0))
	var col: Color = COLOR
	col.a *= 1.0 - p
	draw_arc(Vector2.ZERO, r, 0.0, TAU, 40, col, maxf(1.0, WIDTH * _s), true)
	var fill: Color = COLOR
	fill.a *= (1.0 - p) * 0.12
	draw_circle(Vector2.ZERO, r, fill)
