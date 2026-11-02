extends Control

# Small circular spinner for the autosave notification. Drawn in code so it
# scales cleanly at every UI scale and needs no texture import.

var _angle: float = 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	process_mode = Node.PROCESS_MODE_ALWAYS


func _process(delta: float) -> void:
	_angle = fmod(_angle + delta * 6.0, TAU)
	queue_redraw()


func _draw() -> void:
	var centre := size * 0.5
	var radius := maxf(4.0, minf(size.x, size.y) * 0.34)
	var width := maxf(1.5, 2.0 * Global.ui_scale)
	draw_arc(centre, radius, 0.0, TAU, 28,
		Color(0.75, 0.88, 1.0, 0.18), width, true)
	draw_arc(centre, radius, _angle, _angle + 1.7, 18,
		Color(0.55, 0.90, 1.0, 1.0), maxf(2.0, 2.6 * Global.ui_scale), true)
