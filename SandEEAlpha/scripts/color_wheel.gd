extends Control
class_name ColorWheel

# ── Hue/Saturation colour wheel ────────────────────────────────────
# Angle = hue, radius = saturation. Brightness (value) comes from the owner
# via set_value(); the wheel is rendered at full value (the standard wheel
# look) and the owner applies the value to the picked colour. Emits `picked`
# whenever the user clicks/drags, and draws a selector dot at the current h/s.

signal picked(hue: float, sat: float)

const WHEEL_PX: int = 128

var hue: float = 0.0
var sat: float = 1.0
var _value: float = 1.0
var _tex: ImageTexture = null

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build_wheel()

func _build_wheel() -> void:
	var img := Image.create_empty(WHEEL_PX, WHEEL_PX, false, Image.FORMAT_RGBA8)
	var c: float = float(WHEEL_PX) * 0.5
	var maxr: float = c - 1.0
	for y in range(WHEEL_PX):
		for x in range(WHEEL_PX):
			var dx: float = float(x) + 0.5 - c
			var dy: float = float(y) + 0.5 - c
			var r: float = sqrt(dx * dx + dy * dy)
			if r > maxr:
				img.set_pixel(x, y, Color(0, 0, 0, 0))
				continue
			var h: float = fposmod(atan2(dy, dx) / TAU, 1.0)
			var s: float = clampf(r / maxr, 0.0, 1.0)
			var col: Color = Color.from_hsv(h, s, 1.0)
			col.a = clampf((maxr - r) / 1.5, 0.0, 1.0)   # 1px soft edge
			img.set_pixel(x, y, col)
	_tex = ImageTexture.create_from_image(img)

func set_value(v: float) -> void:
	_value = clampf(v, 0.0, 1.0)
	queue_redraw()

func set_hs(h: float, s: float) -> void:
	hue = fposmod(h, 1.0)
	sat = clampf(s, 0.0, 1.0)
	queue_redraw()

func _draw() -> void:
	if _tex == null:
		return
	draw_texture_rect(_tex, Rect2(Vector2.ZERO, size), false)
	var s: float = Global.ui_scale
	var c: Vector2 = size * 0.5
	var maxr: float = minf(size.x, size.y) * 0.5 - 1.0
	var pos: Vector2 = c + Vector2(cos(hue * TAU), sin(hue * TAU)) * sat * maxr
	draw_circle(pos, 4.0 * s, Color(1, 1, 1, 0.9))
	draw_arc(pos, 4.0 * s, 0.0, TAU, 20, Color(0, 0, 0, 0.9), 1.5 * s)

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		_pick(event.position)
		accept_event()
	elif event is InputEventMouseMotion and (event.button_mask & MOUSE_BUTTON_MASK_LEFT) != 0:
		_pick(event.position)
		accept_event()

func _pick(pos: Vector2) -> void:
	var c: Vector2 = size * 0.5
	var d: Vector2 = pos - c
	var maxr: float = minf(size.x, size.y) * 0.5 - 1.0
	sat = clampf(d.length() / maxr, 0.0, 1.0)
	hue = fposmod(atan2(d.y, d.x) / TAU, 1.0)
	queue_redraw()
	picked.emit(hue, sat)
