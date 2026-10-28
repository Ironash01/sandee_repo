extends CanvasLayer

# ── Android touch HUD ─────────────────────────────────────────────
# Adds the touch-only controls the desktop build doesn't need, WITHOUT owning
# any gameplay logic:
#   • a fixed-base touch joystick (lower-left) that feeds Global.mobile_move,
#     which player.gd blends with the keyboard vector;
#   • action buttons (lower-right): BUILD, SPRINT (hold), INTERACT (context)
#     and DONE (keyboard dismiss)
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
	Global.point_and_click_auto_sprint_changed.connect(_on_auto_sprint_changed)
	Global.gameplay_input_cancelled.connect(_reset_touch_state)

func _exit_tree() -> void:
	_release_bridged_touches()
	Global.clear_mobile_hud_controls()
	Global.mobile_move   = Vector2.ZERO
	Global.mobile_shift  = false
	Global.clear_touch_mouse()

# Android can suspend us with a finger down. Releases are then never delivered,
# so clear every gesture on focus/pause and on resume before accepting new
# touches. The joystick/button visuals are reset at the same time.
func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT \
			or what == NOTIFICATION_APPLICATION_PAUSED \
			or what == NOTIFICATION_APPLICATION_FOCUS_IN \
			or what == NOTIFICATION_APPLICATION_RESUMED \
			or what == NOTIFICATION_WM_WINDOW_FOCUS_OUT \
			or what == NOTIFICATION_WM_WINDOW_FOCUS_IN:
		_reset_touch_state()

func _on_ui_scale(_s: float) -> void:
	# Rebuild at the new scale, preserving toggle state (the buttons carry it).
	_reset_touch_state()
	for c in _root.get_children():
		c.queue_free()
	_build_controls()
	_on_block_mode_changed(Global.block_mode)

func _build_controls() -> void:
	Global.clear_mobile_hud_controls()
	var s: float = Global.ui_scale
	var m := _layout_metrics(s)
	var stick_size: float = m["stick_size"]
	var stick := JOYSTICK_SCRIPT.new() as Control
	stick.name = "Joystick"
	stick.size = Vector2(stick_size, stick_size)
	stick.position = Vector2(m["left_pad"], m["controls_bottom"] - stick_size)
	stick.connect("moved", _on_stick_moved)
	stick.connect("released", _on_stick_released)
	_root.add_child(stick)
	_stick = stick

	_btn_build = _mk_button("BUILD", m["btn_size"], s)
	_btn_build.pressed.connect(_on_build_pressed)
	_root.add_child(_btn_build)

	_btn_shift = _mk_button("SPRINT", m["btn_size"], s)
	_btn_shift.button_down.connect(func() -> void: Global.mobile_shift = true)
	_btn_shift.button_up.connect(func() -> void: Global.mobile_shift = false)
	_root.add_child(_btn_shift)

	_btn_interact = _mk_button("INTERACT", m["interact_size"], s)
	_btn_interact.tooltip_text = "Interact with a nearby chest, crafting station or furnace."
	_btn_interact.pressed.connect(_on_interact_pressed)
	_root.add_child(_btn_interact)

	# Keyboard dismiss (only while a text field is focused).
	_btn_done = _mk_button("DONE", m["btn_size"], s)
	_btn_done.visible = _text_focus
	_btn_done.pressed.connect(_dismiss_keyboard)
	_root.add_child(_btn_done)

	for control in [_stick, _btn_build, _btn_shift, _btn_interact, _btn_done]:
		Global.register_mobile_hud_control(control as Control)

	_set_controls_enabled(not _text_focus)

func _layout_metrics(s: float) -> Dictionary:
	var vp: Vector2 = get_viewport().get_visible_rect().size
	var insets: Vector4 = Global.ui_safe_insets
	var pad: float = SAFE_PAD * s
	var left_pad: float = maxf(pad, insets.x)
	var right_pad: float = maxf(pad, insets.z)
	var bottom_pad: float = maxf(pad, insets.w)
	var hotbar := _hotbar_bounds(s, vp)
	var btn_size: float = minf(BTN_MIN * s, maxf(54.0, vp.y * 0.15))
	var gap: float = 10.0 * s
	var stick_size: float = minf(236.0 * s, maxf(160.0, vp.y * 0.42))
	var interact_size: float = btn_size * 1.25
	var button_left: float = vp.x - right_pad - interact_size - btn_size - gap
	var controls_bottom: float = vp.y - bottom_pad
	if left_pad + stick_size > hotbar.position.x \
			or button_left < hotbar.end.x:
		controls_bottom = minf(controls_bottom, hotbar.position.y - gap)
	return {
		"s": s, "vp": vp, "left_pad": left_pad, "right_pad": right_pad,
		"bottom_pad": bottom_pad, "hotbar": hotbar, "btn_size": btn_size,
		"interact_size": interact_size, "gap": gap, "stick_size": stick_size,
		"controls_bottom": controls_bottom,
	}

# Circular MOBA-style layout. BUILD stays on the right when the fixed joystick
# is active, and takes the joystick slot at lower-left when PnC hides it.
func _layout_action_controls() -> void:
	if _btn_build == null or _btn_shift == null or _btn_interact == null:
		return
	var s: float = Global.ui_scale
	var m := _layout_metrics(s)
	var vp: Vector2 = m["vp"]
	var left_pad: float = m["left_pad"]
	var right_pad: float = m["right_pad"]
	var gap: float = m["gap"]
	var bottom: float = m["controls_bottom"]
	var btn_size: float = m["btn_size"]
	var interact_size: float = m["interact_size"]
	var stick_size: float = m["stick_size"]

	if _stick != null:
		_stick.size = Vector2(stick_size, stick_size)
		_stick.position = Vector2(left_pad, bottom - stick_size)

	var interact_pos := Vector2(vp.x - right_pad - interact_size,
		bottom - interact_size)
	var sprint_pos := Vector2(interact_pos.x - btn_size - gap,
		interact_pos.y + (interact_size - btn_size) * 0.5)
	var build_pos := Vector2(interact_pos.x + (interact_size - btn_size) * 0.5,
		interact_pos.y - btn_size - gap)
	_place_circle(_btn_interact, interact_pos, interact_size,
		Color(0.27, 0.58, 0.52, 0.96), Color(0.50, 0.95, 0.82, 1.0))
	_place_circle(_btn_shift, sprint_pos, btn_size,
		Color(0.22, 0.42, 0.66, 0.96), Color(0.55, 0.80, 1.0, 1.0))

	if Global.point_and_click:
		# PnC hides the stick; BUILD occupies the same lower-left slot.
		var left_size: float = minf(btn_size * 1.35, stick_size * 0.55)
		var left_center := Vector2(left_pad + stick_size * 0.5,
			bottom - stick_size * 0.5)
		_place_circle(_btn_build, left_center - Vector2(left_size, left_size) * 0.5,
			left_size, Color(0.46, 0.32, 0.10, 0.96), Color(1.0, 0.78, 0.30, 1.0))
	else:
		_place_circle(_btn_build, build_pos, btn_size,
			Color(0.46, 0.32, 0.10, 0.96), Color(1.0, 0.78, 0.30, 1.0))

	var done_pos := Vector2(vp.x - right_pad - btn_size,
		build_pos.y - btn_size - gap)
	_btn_done.position = done_pos
	_btn_done.size = Vector2(btn_size, btn_size)
	_place_circle(_btn_done, done_pos, btn_size,
		Color(0.14, 0.20, 0.32, 0.96), Color(0.55, 0.68, 0.88, 1.0))
	_on_block_mode_changed(Global.block_mode)

func _place_circle(btn: Button, pos: Vector2, diameter: float,
		fill: Color, border: Color) -> void:
	if btn == null:
		return
	var s: float = Global.ui_scale
	btn.position = pos
	btn.custom_minimum_size = Vector2(diameter, diameter)
	btn.size = Vector2(diameter, diameter)
	btn.clip_text = true
	btn.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	btn.add_theme_font_size_override("font_size",
		Global.ui_font_size(12 if diameter < 108.0 else 13))
	var sb := StyleBoxFlat.new()
	sb.bg_color = fill
	sb.border_color = border
	sb.set_border_width_all(maxi(1, int(2 * s)))
	sb.set_corner_radius_all(int(diameter * 0.5))
	sb.content_margin_left = 0
	sb.content_margin_right = 0
	sb.content_margin_top = 0
	sb.content_margin_bottom = 0
	var pressed := sb.duplicate() as StyleBoxFlat
	pressed.bg_color = fill.lightened(0.10)
	btn.add_theme_stylebox_override("normal", sb)
	btn.add_theme_stylebox_override("hover", sb)
	btn.add_theme_stylebox_override("pressed", pressed)
	btn.add_theme_color_override("font_color", Color(0.88, 0.96, 1.0, 1.0))
	btn.add_theme_color_override("font_pressed_color", Color(0.85, 1.0, 0.85, 1.0))

func _hotbar_bounds(s: float, vp: Vector2) -> Rect2:
	var slot_px: float = maxf(36.0 * s, 44.0)
	var gap_px: int = maxi(4, int(round(4.0 * s)))
	var total: float = Global.HOTBAR_SIZE * slot_px \
		+ maxi(0, Global.HOTBAR_SIZE - 1) * gap_px
	var bottom_margin: float = 8.0 * s + Global.ui_safe_insets.w
	return Rect2(
		Vector2(vp.x * 0.5 - total * 0.5, vp.y - bottom_margin - slot_px),
		Vector2(total, slot_px))

func _mk_button(text: String, size_px: float, s: float) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(size_px, size_px)
	b.size = Vector2(size_px, size_px)
	b.focus_mode = Control.FOCUS_NONE
	# Keep the action cluster's fixed square footprint even when the long
	# INTERACT label would otherwise force the button wider than its column.
	b.clip_text = true
	b.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	b.add_theme_font_size_override("font_size", Global.ui_font_size(13))
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
	var d: float = maxf(1.0, _btn_build.size.x)
	var fill := Color(0.18, 0.45, 0.24, 0.96) if active \
		else Color(0.46, 0.32, 0.10, 0.96)
	var border := Color(0.55, 0.95, 0.55, 1.0) if active \
		else Color(1.0, 0.78, 0.30, 1.0)
	_place_circle(_btn_build, _btn_build.position, d, fill, border)
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
		# Point-and-click mode replaces manual joystick movement on Android;
		# hide the stick so it cannot steal the tap that should move the player.
		# Joystick mode keeps it visible, and the saved preference is untouched.
		_stick.visible = on and not Global.point_and_click
	if _btn_build != null:
		_btn_build.visible = on
	if _btn_shift != null:
		# Auto-sprint replaces the hold button entirely.
		_btn_shift.visible = on and not Global.point_and_click_auto_sprint
	if _btn_interact != null:
		_btn_interact.visible = on
		if not on:
			_interact_target = null
	if not on:
		_reset_touch_state()
	_layout_action_controls()

# Hidden joystick must not leave stale movement behind; restore on disable.
func _on_point_and_click_changed(_enabled: bool) -> void:
	_reset_touch_state()
	_set_controls_enabled(not _text_focus)

func _on_auto_sprint_changed(_enabled: bool) -> void:
	if _enabled:
		Global.mobile_shift = false
	_set_controls_enabled(not _text_focus)

# Godot emulates only the FIRST touch as a mouse. On Android that first touch
# drives all normal UI/world input. Additional simultaneous fingers are bridged
# here so moving with the joystick while tapping the action button or a hotbar
# slot keeps working.
var _primary_touch: int = -1
var _primary_world: bool = false
var _primary_pos: Vector2 = Vector2.ZERO
# Secondary touches bridged to mouse input, with the last screen position so a
# modal opening mid-gesture can release every synthetic button it owns.
var _bridged_touches: Dictionary = {}
var _bridged_ui: Dictionary = {}

func _reset_touch_state() -> void:
	_release_bridged_touches()
	# The primary touch is normally released by Godot's emulated mouse, but a
	# release swallowed by a freshly opened modal would leave the virtual left
	# button latched. Send an explicit release at its last position.
	if _primary_touch != -1:
		_emit_mouse_button(_primary_pos, false)
	_primary_touch = -1
	_primary_world = false
	_bridged_ui.clear()
	Global.mobile_move = Vector2.ZERO
	Global.mobile_shift = false
	if _stick != null and is_instance_valid(_stick) and _stick.has_method("reset_stick"):
		_stick.call("reset_stick")

func _release_bridged_touches() -> void:
	if _bridged_touches.is_empty():
		return
	for touch_id in _bridged_touches.keys():
		var at: Vector2 = _bridged_touches[touch_id] as Vector2
		var ui_owned := bool(_bridged_ui.get(touch_id, false))
		_emit_mouse_button(at, false, ui_owned)
	_bridged_touches.clear()
	_bridged_ui.clear()

func _over_stick(screen_pos: Vector2) -> bool:
	return _stick != null and is_instance_valid(_stick) and _stick.visible \
		and _stick.get_global_rect().has_point(screen_pos)

func _is_ui_touch(screen_pos: Vector2) -> bool:
	if Global.is_point_over_ui(screen_pos):
		return true
	for control in [_btn_build, _btn_shift, _btn_interact, _btn_done]:
		var c := control as Control
		if c != null and is_instance_valid(c) and c.is_visible_in_tree() \
				and c.get_global_rect().has_point(screen_pos):
			return true
	return Global.hotbar_slot_at(screen_pos) >= 0 or _over_stick(screen_pos)

func _input(event: InputEvent) -> void:
	# Never bridge secondary touches into a paused/modal UI world. Primary touch
	# still reaches the GUI through Godot's normal touch->mouse emulation, so
	# buttons and text fields remain usable while the world is protected.
	if Global.any_ui_open() or Global.pause_menu_open \
			or Global.is_text_input_focused():
		_reset_touch_state()
		return
	if event is InputEventScreenTouch:
		var t := event as InputEventScreenTouch
		if t.pressed:
			if _primary_touch == -1:
				_primary_touch = t.index
				_primary_pos = t.position
				var over_ui := _is_ui_touch(t.position)
				if over_ui:
					Global.guard_mobile_ui_touch()
				_primary_world = not over_ui
				if _primary_world:
					_set_world_pos(t.position)
				return
			# Secondary finger: the joystick owns its own touches. Let the real
			# ScreenTouch reach the joystick instead of duplicating it as mouse.
			if _over_stick(t.position):
				Global.guard_mobile_ui_touch()
				return
			# Hotbar taps are resolved directly. A synthetic mouse press can be
			# captured by the joystick's active mouse focus and reset the stick,
			# which made switching items while walking unreliable. Directly
			# selecting the slot keeps the held joystick touch untouched.
			var hotbar_slot: int = Global.hotbar_slot_at(t.position)
			if hotbar_slot >= 0 and hotbar_slot < Global.hotbar_item_slots():
				Global.guard_mobile_ui_touch()
				Global.set_hotbar_selection(hotbar_slot)
				get_viewport().set_input_as_handled()
				return
			# One synthetic left button can only represent one extra finger. A
			# third finger must not press/release the same virtual mouse while the
			# first secondary gesture is still down (its release would cancel the
			# other gesture). Swallow it as UI-owned input.
			if not _bridged_touches.is_empty():
				Global.guard_mobile_ui_touch()
				get_viewport().set_input_as_handled()
				return
			var over_ui := _is_ui_touch(t.position)
			if over_ui:
				Global.guard_mobile_ui_touch()
			else:
				_set_world_pos(t.position)
			_bridged_touches[t.index] = t.position
			_bridged_ui[t.index] = over_ui
			_emit_mouse_button(t.position, true, over_ui)
			get_viewport().set_input_as_handled()
		else:
			if t.index == _primary_touch:
				_primary_touch = -1
				_primary_world = false
				return
			if _bridged_touches.has(t.index):
				var ui_owned := bool(_bridged_ui.get(t.index, false))
				if not ui_owned and not Global.is_point_over_ui(t.position):
					_set_world_pos(t.position)
				_bridged_touches.erase(t.index)
				_bridged_ui.erase(t.index)
				_emit_mouse_button(t.position, false, ui_owned)
				get_viewport().set_input_as_handled()
	elif event is InputEventScreenDrag:
		var d := event as InputEventScreenDrag
		if d.index == _primary_touch:
			_primary_pos = d.position
			if _primary_world and not Global.is_point_over_ui(d.position):
				_set_world_pos(d.position)
			return
		if _bridged_touches.has(d.index):
			_bridged_touches[d.index] = d.position
			if not _over_stick(d.position) and not Global.is_point_over_ui(d.position):
				_set_world_pos(d.position)
			_emit_mouse_motion(d.position)
			get_viewport().set_input_as_handled()

func _emit_mouse_button(screen_pos: Vector2, pressed: bool, ui_owned: bool = false) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index    = MOUSE_BUTTON_LEFT
	ev.pressed         = pressed
	ev.position        = screen_pos
	ev.global_position = screen_pos
	ev.button_mask     = MOUSE_BUTTON_MASK_LEFT if pressed else 0
	ev.set_meta("mobile_touch_bridge", true)
	if ui_owned and pressed:
		# Presses synthesized for a UI-owned secondary touch must never reach
		# world mining/attacking, even if the UI hit-test misses on a device.
		ev.set_meta("mobile_ui_touch", true)
	Input.parse_input_event(ev)

func _emit_mouse_motion(screen_pos: Vector2) -> void:
	var ev := InputEventMouseMotion.new()
	ev.position        = screen_pos
	ev.global_position = screen_pos
	ev.button_mask     = MOUSE_BUTTON_MASK_LEFT
	ev.set_meta("mobile_touch_bridge", true)
	Input.parse_input_event(ev)

func _set_world_pos(screen_pos: Vector2) -> void:
	var canvas: Transform2D = get_viewport().get_canvas_transform()
	Global.set_touch_mouse(canvas.affine_inverse() * screen_pos)
