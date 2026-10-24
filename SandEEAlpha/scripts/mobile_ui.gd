extends CanvasLayer

# ── Android touch HUD ─────────────────────────────────────────────
# Adds the touch-only controls the desktop build doesn't need, WITHOUT owning
# any gameplay logic:
#   • a floating touch joystick (lower-left) that feeds Global.mobile_move,
#     which player.gd blends with the keyboard vector;
#   • action buttons (lower-right): BUILD, SHIFT (hold), RIGHT-CLICK mode and
#     MENU — each driving the existing Global state / existing systems;
#   • tap-anywhere world interaction: unhandled touches are converted to the
#     same mouse events the desktop code already consumes (position mapped
#     through the real canvas/camera transform), so mining, attacking,
#     placing, fishing, interacting with objects, etc. all keep their existing
#     range/collision/inventory validation;
#   • a DONE button while a text field is focused, which dismisses the Android
#     software keyboard.
#
# Created by game_instance.gd only when Global.is_mobile() is true, so the
# desktop HUD and keyboard/mouse behaviour are untouched.

const JOYSTICK_SCRIPT: GDScript = preload("res://scripts/mobile_joystick.gd")
const BTN_MIN: float = 64.0
const SAFE_PAD: float = 12.0

const C_PANEL  := Color(0.08, 0.10, 0.20, 0.82)
const C_BORDER := Color(0.22, 0.32, 0.58, 1.00)
const C_TITLE  := Color(0.80, 0.90, 1.00, 1.00)
const C_ACTIVE := Color(0.25, 0.45, 0.25, 0.95)
const C_MUTED  := Color(0.55, 0.65, 0.85, 1.00)

var _root:    Control = null
var _stick:   Control = null
var _btn_build: Button = null
var _btn_shift: Button = null
var _btn_done:  Button = null
var _btn_interact: Button = null
var _interact_target: Node = null
var _interact_scan: float = 0.0

var _text_focus: bool = false

func _ready() -> void:
	layer        = 9          # below the hotbar (10), above panels (2+)
	process_mode = Node.PROCESS_MODE_ALWAYS
	_root = Control.new()
	_root.name = "TouchHud"
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_root)
	_build_controls()
	Global.block_mode_changed.connect(_on_block_mode_changed)
	_on_block_mode_changed(Global.block_mode)
	Global.ui_scale_changed.connect(_on_ui_scale)
	Global.point_and_click_changed.connect(_on_point_and_click_changed)

func _exit_tree() -> void:
	Global.mobile_move   = Vector2.ZERO
	Global.mobile_shift  = false
	Global.clear_touch_mouse()

func _on_ui_scale(_s: float) -> void:
	# Rebuild at the new scale, preserving toggle state (the buttons carry it).
	Global.mobile_move  = Vector2.ZERO
	Global.mobile_shift = false
	for c in _root.get_children():
		c.queue_free()
	_build_controls()
	_on_block_mode_changed(Global.block_mode)

func _build_controls() -> void:
	var s: float = Global.ui_scale
	var safe: Rect2i = DisplayServer.get_display_safe_area()
	var vp: Vector2   = get_viewport().get_visible_rect().size
	# DisplayServer reports the safe area in physical screen pixels, while all
	# Control coordinates are in the stretched viewport. Convert through the
	# viewport's screen transform before using the insets.
	var screen_xf: Transform2D = get_viewport().get_screen_transform()
	var safe_start: Vector2 = screen_xf.affine_inverse() * Vector2(safe.position)
	var safe_end: Vector2 = screen_xf.affine_inverse() \
		* Vector2(safe.position + safe.size)
	var pad: float    = SAFE_PAD * s
	var left_pad: float   = pad
	var right_pad: float  = pad
	var bottom_pad: float = pad
	# Only applied when the converted rect is plausible for this viewport, so a
	# desktop/odd report can never shove controls off-screen.
	if safe.size.x > 0 and safe.size.y > 0 \
			and safe_end.x > safe_start.x and safe_end.y > safe_start.y \
			and safe_end.x <= vp.x + 2.0 and safe_end.y <= vp.y + 2.0:
		left_pad   = maxf(pad, safe_start.x)
		right_pad  = maxf(pad, vp.x - safe_end.x)
		bottom_pad = maxf(pad, vp.y - safe_end.y)

	# ── Joystick ────────────────────────────────────────────────
	var stick := JOYSTICK_SCRIPT.new() as Control
	stick.name = "Joystick"
	var size_px: float = 236.0 * s
	stick.size = Vector2(size_px, size_px)
	stick.position = Vector2(left_pad, vp.y - bottom_pad - size_px)
	stick.connect("moved", _on_stick_moved)
	stick.connect("released", _on_stick_released)
	_root.add_child(stick)
	_stick = stick

	# ── Action buttons (lower-right cluster) ────────────────────
	var btn_size: float = BTN_MIN * s
	var gap: float = 10.0 * s
	# BUILD + SPRINT on the bottom row, INTERACT above them.
	var row2_y: float = vp.y - bottom_pad - btn_size
	var row1_y: float = row2_y - btn_size - gap

	_btn_build = _mk_button("BUILD", btn_size, s)
	_btn_build.position = Vector2(vp.x - right_pad - btn_size * 2.0 - gap, row2_y)
	_btn_build.pressed.connect(_on_build_pressed)
	_root.add_child(_btn_build)

	_btn_shift = _mk_button("SPRINT", btn_size, s)
	_btn_shift.position = Vector2(vp.x - right_pad - btn_size, row2_y)
	_btn_shift.button_down.connect(func() -> void: Global.mobile_shift = true)
	_btn_shift.button_up.connect(func() -> void: Global.mobile_shift = false)
	_root.add_child(_btn_shift)



	_btn_interact = _mk_button("INTERACT", btn_size, s)
	_btn_interact.position = Vector2(vp.x - right_pad - btn_size,
		row1_y - btn_size - gap)
	_btn_interact.pressed.connect(_on_interact_pressed)
	_root.add_child(_btn_interact)

	# ── Keyboard dismiss (only while a text field is focused) ───
	_btn_done = _mk_button("DONE", btn_size, s)
	_btn_done.position = Vector2(vp.x - right_pad - btn_size, row1_y - btn_size - gap)
	_btn_done.visible = false
	_btn_done.pressed.connect(_dismiss_keyboard)
	_root.add_child(_btn_done)

	# Apply the saved scheme immediately (joystick hidden if point-and-click is
	# already ON when this HUD is built / rebuilt at a new UI scale).
	_set_controls_enabled(not _text_focus)

func _mk_button(text: String, size_px: float, s: float) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(size_px, size_px)
	b.size = Vector2(size_px, size_px)
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", int(13 * s))
	var sb := StyleBoxFlat.new()
	sb.bg_color     = C_PANEL
	sb.border_color = C_BORDER
	sb.set_border_width_all(maxi(1, int(2 * s)))
	sb.set_corner_radius_all(int(10 * s))
	var pressed := sb.duplicate() as StyleBoxFlat
	pressed.bg_color = C_ACTIVE
	b.add_theme_stylebox_override("normal",  sb)
	b.add_theme_stylebox_override("hover",   sb)
	b.add_theme_stylebox_override("pressed", pressed)
	b.add_theme_color_override("font_color", C_TITLE)
	b.add_theme_color_override("font_pressed_color", Color(0.85, 1.0, 0.85))
	return b

# ── State wiring ──────────────────────────────────────────────────
func _on_stick_moved(dir: Vector2) -> void:
	Global.mobile_move = dir

func _on_stick_released() -> void:
	Global.mobile_move = Vector2.ZERO

func _on_build_pressed() -> void:
	Global.toggle_build_mode()

func _on_block_mode_changed(active: bool) -> void:
	if _btn_build == null:
		return
	_btn_build.text = "BUILD ON" if active else "BUILD"
	var sb := _btn_build.get_theme_stylebox("normal").duplicate() as StyleBoxFlat
	sb.bg_color = C_ACTIVE if active else C_PANEL
	sb.border_color = Color(0.55, 0.95, 0.55, 1.0) if active else C_BORDER
	_btn_build.add_theme_stylebox_override("normal", sb)
	_btn_build.add_theme_stylebox_override("hover", sb)
	_btn_build.tooltip_text = "Build mode is ON — tap the world to place blocks." if active \
		else "Toggle build mode."

# Context-sensitive touch interaction. Only a nearby TouchInteractable (crafting
# station, furnace or chest) can be opened; the button never taps the world or
# reaches a remote object.
func _on_interact_pressed() -> void:
	_refresh_interact_target()
	if _interact_target != null and is_instance_valid(_interact_target) \
			and _interact_target.has_method("open_from_touch"):
		_interact_target.call("open_from_touch")

func _refresh_interact_target() -> void:
	_interact_target = null
	var player: Node2D = Global.player_node as Node2D
	if player == null or not is_instance_valid(player):
		return
	var best: Node = null
	var best_d: float = 56.0
	for node in get_tree().get_nodes_in_group("TouchInteractable"):
		if not (node is Node2D):
			continue
		var n := node as Node2D
		var d := n.global_position.distance_to(player.global_position)
		if d <= best_d:
			best = n
			best_d = d
	_interact_target = best
	if _btn_interact == null:
		return
	if best == null:
		_btn_interact.text = "INTERACT"
		_btn_interact.disabled = true
	elif best.is_in_group("CraftingStation"):
		_btn_interact.text = "CRAFT"
		_btn_interact.disabled = false
	elif best.has_method("smelt_request"):
		_btn_interact.text = "SMELT"
		_btn_interact.disabled = false
	else:
		_btn_interact.text = "OPEN"
		_btn_interact.disabled = false

func _dismiss_keyboard() -> void:
	DisplayServer.virtual_keyboard_hide()
	get_viewport().gui_release_focus()

# ── Per-frame availability ────────────────────────────────────────
func _process(delta: float) -> void:
	var focused: bool = Global.is_text_input_focused()
	if focused != _text_focus:
		_text_focus = focused
		_set_controls_enabled(not focused)
		if _btn_done != null:
			_btn_done.visible = focused
		if focused:
			Global.mobile_move  = Vector2.ZERO
			Global.mobile_shift = false
			if _stick != null and _stick.has_method("reset_stick"):
				_stick.call("reset_stick")
	if _btn_done != null and _btn_done.visible and not focused:
		_btn_done.visible = false
	_interact_scan -= delta
	if not focused and _interact_scan <= 0.0:
		_interact_scan = 0.2
		_refresh_interact_target()

func _set_controls_enabled(on: bool) -> void:
	if _stick != null:
		# Keep manual joystick control available even with tap-to-control ON;
		# any joystick input cancels the automated move order in player.gd.
		_stick.visible = on
	if _btn_build != null:
		_btn_build.visible = on
	if _btn_shift != null:
		_btn_shift.visible = on
	if _btn_interact != null:
		_btn_interact.visible = on
		if not on:
			_interact_target = null

# Hidden joystick must not leave stale movement behind; restore on disable.
func _on_point_and_click_changed(_enabled: bool) -> void:
	Global.mobile_move = Vector2.ZERO
	if _stick != null and _stick.has_method("reset_stick"):
		_stick.call("reset_stick")
	_set_controls_enabled(not _text_focus)

# Godot emulates only the FIRST touch as a mouse. On Android that first touch
# drives all normal UI/world input. Additional simultaneous fingers are bridged
# here so moving with the joystick while tapping the action button or a hotbar
# slot keeps working.
var _primary_touch: int = -1

func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		var t := event as InputEventScreenTouch
		if t.pressed:
			if _primary_touch == -1:
				_primary_touch = t.index
				return
			_emit_mouse_button(t.position, true)
		else:
			if t.index == _primary_touch:
				_primary_touch = -1
				return
			_emit_mouse_button(t.position, false)
	elif event is InputEventScreenDrag:
		var d := event as InputEventScreenDrag
		if d.index != _primary_touch:
			_emit_mouse_motion(d.position)

func _emit_mouse_button(screen_pos: Vector2, pressed: bool) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index    = MOUSE_BUTTON_LEFT
	ev.pressed         = pressed
	ev.position        = screen_pos
	ev.global_position = screen_pos
	ev.button_mask     = MOUSE_BUTTON_MASK_LEFT if pressed else 0
	Input.parse_input_event(ev)

func _emit_mouse_motion(screen_pos: Vector2) -> void:
	var ev := InputEventMouseMotion.new()
	ev.position        = screen_pos
	ev.global_position = screen_pos
	ev.button_mask     = MOUSE_BUTTON_MASK_LEFT
	Input.parse_input_event(ev)

func _set_world_pos(screen_pos: Vector2) -> void:
	var canvas: Transform2D = get_viewport().get_canvas_transform()
	Global.set_touch_mouse(canvas.affine_inverse() * screen_pos)
