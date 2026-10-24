extends Control
class_name MobileJoystick

# ── Touch joystick (Android) ──────────────────────────────────────
# A fixed base in the lower-left with a floating thumb: touching anywhere inside
# the control's generous hit area re-centres the stick under the finger, which
# makes it usable on small phones without looking. Emits a normalized direction
# with magnitude 0..1; the player blends it with the keyboard vector, so all
# movement speed / collision / animation rules stay in player.gd.
#
# Drawn with simple shapes (base ring + knob) in the HUD palette — no new art
# asset needed, and it scales with Global.ui_scale.

signal moved(direction: Vector2)
signal released

const BASE_RADIUS := 74.0
const KNOB_RADIUS := 34.0
const DEAD_ZONE   := 0.15
const COLOR_RING  := Color(0.80, 0.90, 1.00, 0.35)
const COLOR_FILL  := Color(0.10, 0.14, 0.24, 0.55)
const COLOR_KNOB  := Color(0.55, 0.75, 1.00, 0.85)

var _touch_id: int = -1
var _center: Vector2 = Vector2.ZERO
var _value: Vector2 = Vector2.ZERO
var _knob: Vector2 = Vector2.ZERO

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode   = Control.FOCUS_NONE
	set_process_input(false)
	resized.connect(_recenter)
	_recenter()

func _recenter() -> void:
	_center = size * 0.5
	_knob   = _center
	queue_redraw()

# Called by the owner when the game pauses / another UI opens.
func reset_stick() -> void:
	_touch_id = -1
	_value    = Vector2.ZERO
	_knob     = _center
	queue_redraw()
	released.emit()

func _gui_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		var t := event as InputEventScreenTouch
		if t.pressed:
			if _touch_id != -1:
				return
			_touch_id = t.index
			# Floating behaviour: the stick centres on the touch inside the pad.
			_center = t.position
			_knob   = _center
			_update_value(_center)
		elif t.index == _touch_id:
			reset_stick()
		get_viewport().set_input_as_handled()
	elif event is InputEventScreenDrag:
		var d := event as InputEventScreenDrag
		if d.index == _touch_id:
			_knob = d.position
			_update_value(d.position)
			get_viewport().set_input_as_handled()
	# Mouse fallback (desktop testing / Android with a mouse) so the control can
	# be exercised without a touchscreen, without changing the touch path.
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed and _touch_id == -1:
				_touch_id = 0
				_center = mb.position
				_knob   = _center
				_update_value(_center)
			elif not mb.pressed and _touch_id == 0:
				reset_stick()
			get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion and _touch_id == 0:
		_knob = (event as InputEventMouseMotion).position
		_update_value(_knob)
		get_viewport().set_input_as_handled()

func _update_value(pos: Vector2) -> void:
	var v: Vector2 = (pos - _center) / BASE_RADIUS
	if v.length() > 1.0:
		v = v.normalized()
		_knob = _center + v * BASE_RADIUS
	if v.length() < DEAD_ZONE:
		v = Vector2.ZERO
	_value = v
	queue_redraw()
	moved.emit(v)

func value() -> Vector2:
	return _value

func _draw() -> void:
	draw_circle(_center, BASE_RADIUS, COLOR_FILL)
	draw_arc(_center, BASE_RADIUS, 0.0, TAU, 48, COLOR_RING, 3.0, true)
	draw_circle(_knob, KNOB_RADIUS, COLOR_KNOB)
	draw_arc(_knob, KNOB_RADIUS, 0.0, TAU, 32, COLOR_RING, 2.0, true)
