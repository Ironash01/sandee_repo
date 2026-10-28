extends CanvasLayer

## PC-only floating control guide.
##
## The controls are visual guidance, not input widgets: every node has
## mouse_filter = IGNORE, so world clicks, aiming and the hotbar behave exactly
## as before. Keycaps poll the live InputMap bindings and light up on press.
## Hover is a purely visual poll of the mouse position.
##
## Presentation is deliberately minimal: no panels, no scrim, no backgrounds
## behind the clusters. Bottom-left = WASD/Shift. Bottom-right = contextual
## mouse actions. The bottom-centre hotbar and bars stay untouched.

const LAYER: int = 11
const KEY_SIZE_BASE: float = 30.0
const KEY_GAP_BASE: float = 4.0
const MARGIN_BASE: float = 22.0

const C_LABEL := Color(0.66, 0.74, 0.86, 0.78)
const C_LABEL_HOVER := Color(0.80, 0.93, 1.00, 1.00)

var _s: float = 1.0
var _open: bool = true
var _hud_suppressed: bool = false
var _was_blocked: bool = false
var _focus_lost: bool = false
var _mouse_active_until: int = 0
var _wheel_active_until: int = 0

var _movement_cluster: Control = null
var _action_cluster: Control = null
var _caps: Array = []    # [{"cap": KeyCap, "spec": Dictionary}]
var _chips: Array = []   # [{"control": Control, "caps": Array, "label": Label}]
var _lmb_label: Label = null
var _lmb_shift_cap: KeyCap = null
var _lmb_sep: Label = null
var _movement_shift_cap: KeyCap = null
var _movement_sprint_label: Label = null
var _context_label: String = "USE"
var _context_destroy: bool = false
var _next_context_scan: int = 0


class KeyCap extends Control:
	var label: String = ""
	var font_size: int = 14
	var height_px: int = 34
	var pad_x: int = 10

	var _normal_sb: StyleBoxFlat = null
	var _hover_sb: StyleBoxFlat = null
	var _press_sb: StyleBoxFlat = null
	var _pressed: bool = false
	var _hovered: bool = false

	var pressed: bool:
		get:
			return _pressed
		set(value):
			if _pressed == value:
				return
			_pressed = value
			queue_redraw()

	var hovered: bool:
		get:
			return _hovered
		set(value):
			if _hovered == value:
				return
			_hovered = value
			queue_redraw()

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		_build_styles()
		queue_redraw()

	func _build_styles() -> void:
		var radius: int = maxi(2, int(height_px * 0.18))
		_normal_sb = _make_style(Color(0.035, 0.055, 0.085, 0.58),
			Color(0.56, 0.69, 0.84, 0.52), 1, radius, 0.0)
		_hover_sb = _make_style(Color(0.08, 0.14, 0.22, 0.78),
			Color(0.70, 0.85, 0.98, 0.86), 1, radius, 0.0)
		_press_sb = _make_style(Color(0.13, 0.36, 0.54, 0.92),
			Color(0.64, 0.92, 1.00, 0.98), 2, radius, 0.30)

	func _make_style(fill: Color, border: Color, border_w: int, radius: int,
			glow: float) -> StyleBoxFlat:
		var sb := StyleBoxFlat.new()
		sb.bg_color = fill
		sb.border_color = border
		sb.set_border_width_all(border_w)
		sb.set_corner_radius_all(radius)
		sb.anti_aliasing = true
		if glow > 0.0:
			sb.shadow_color = Color(0.30, 0.72, 1.0, glow)
			sb.shadow_size = maxi(2, int(height_px * 0.14))
		return sb

	func _get_minimum_size() -> Vector2:
		var f: Font = get_theme_font("font")
		if f == null:
			f = ThemeDB.fallback_font
		var text_w: float = f.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1,
			font_size).x
		return Vector2(maxf(float(height_px), text_w + float(pad_x * 2)),
			float(height_px))

	func _draw() -> void:
		var sb: StyleBoxFlat = _press_sb if pressed else (
			_hover_sb if hovered else _normal_sb)
		if sb == null:
			return
		# Only a soft drop shadow, never a container/panel.
		var shadow := StyleBoxFlat.new()
		shadow.bg_color = Color(0, 0, 0, 0.30)
		shadow.set_corner_radius_all(maxi(2, int(height_px * 0.18)))
		draw_style_box(shadow, Rect2(Vector2(1.5, 2.0), size))
		draw_style_box(sb, Rect2(Vector2.ZERO, size))
		var f: Font = get_theme_font("font")
		if f == null:
			f = ThemeDB.fallback_font
		var text_w: float = f.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1,
			font_size).x
		var ascent: float = f.get_ascent(font_size)
		var descent: float = f.get_descent(font_size)
		var baseline: float = (size.y - (ascent + descent)) * 0.5 + ascent
		var pos := Vector2((size.x - text_w) * 0.5, baseline)
		# A one-pixel shadow keeps labels readable over bright grass.
		draw_string(f, pos + Vector2(1, 1), label, HORIZONTAL_ALIGNMENT_LEFT, -1,
			font_size, Color(0, 0, 0, 0.72))
		draw_string(f, pos, label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size,
			Color(1, 1, 1, 1) if pressed else Color(0.84, 0.91, 0.98, 0.92))


func _ready() -> void:
	layer = LAYER
	process_mode = Node.PROCESS_MODE_ALWAYS
	_open = true
	visible = false
	_connect_signals()
	_rebuild()
	set_process(true)


func _exit_tree() -> void:
	if Global.ui_scale_changed.is_connected(_on_ui_scale_changed):
		Global.ui_scale_changed.disconnect(_on_ui_scale_changed)
	if Global.point_and_click_changed.is_connected(_on_point_and_click_changed):
		Global.point_and_click_changed.disconnect(_on_point_and_click_changed)
	if Global.modal_hud_changed.is_connected(_on_modal_hud_changed):
		Global.modal_hud_changed.disconnect(_on_modal_hud_changed)
	var vp: Viewport = get_viewport()
	if vp != null and vp.size_changed.is_connected(_on_viewport_resized):
		vp.size_changed.disconnect(_on_viewport_resized)


func _connect_signals() -> void:
	if not Global.ui_scale_changed.is_connected(_on_ui_scale_changed):
		Global.ui_scale_changed.connect(_on_ui_scale_changed)
	if not Global.point_and_click_changed.is_connected(_on_point_and_click_changed):
		Global.point_and_click_changed.connect(_on_point_and_click_changed)
	if not Global.modal_hud_changed.is_connected(_on_modal_hud_changed):
		Global.modal_hud_changed.connect(_on_modal_hud_changed)
	var vp: Viewport = get_viewport()
	if vp != null and not vp.size_changed.is_connected(_on_viewport_resized):
		vp.size_changed.connect(_on_viewport_resized)


func _on_ui_scale_changed(_scale: float) -> void:
	call_deferred("_rebuild")


func _on_point_and_click_changed(_enabled: bool) -> void:
	call_deferred("_rebuild")


func _on_modal_hud_changed(_open: bool) -> void:
	_refresh_visibility()


func _on_viewport_resized() -> void:
	call_deferred("_rebuild")


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT \
			or what == NOTIFICATION_APPLICATION_PAUSED \
			or what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		_focus_lost = true
		_clear_states()
	elif what == NOTIFICATION_APPLICATION_FOCUS_IN \
			or what == NOTIFICATION_APPLICATION_RESUMED \
			or what == NOTIFICATION_WM_WINDOW_FOCUS_IN:
		_focus_lost = false


func is_open() -> bool:
	return _open


func set_open(open: bool) -> void:
	_open = open
	if _open and not _blocked():
		_rebuild()
	_refresh_visibility()
	if _open:
		_update_caps()
		_update_hover()


## Used by game_instance while the fullscreen map or another HUD-owning screen
## is open. Keeps the remembered open state so F1 can bring it back later.
func set_hud_suppressed(suppressed: bool) -> void:
	_hud_suppressed = suppressed
	_refresh_visibility()


func _blocked() -> bool:
	return Global.any_ui_open() or Global.pause_menu_open \
		or Global.is_text_input_focused() or Global.player_is_dead \
		or _hud_suppressed


func _refresh_visibility() -> void:
	visible = _open and not _blocked()


func _input(event: InputEvent) -> void:
	if event is InputEventKey:
		var key := event as InputEventKey
		if key.pressed and not key.echo \
				and (key.physical_keycode == KEY_F1 or key.keycode == KEY_F1):
			if _blocked():
				return
			set_open(not _open)
			get_viewport().set_input_as_handled()
			return
	if event is InputEventMouseMotion:
		_mouse_active_until = Time.get_ticks_msec() + 180
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and (mb.button_index == MOUSE_BUTTON_WHEEL_UP
				or mb.button_index == MOUSE_BUTTON_WHEEL_DOWN):
			_wheel_active_until = Time.get_ticks_msec() + 150


func _process(_delta: float) -> void:
	if not _open:
		if visible:
			visible = false
		_was_blocked = false
		return
	var blocked: bool = _blocked()
	if _was_blocked and not blocked:
		call_deferred("_rebuild")
	_was_blocked = blocked
	if blocked:
		if visible:
			visible = false
		return
	if not visible:
		visible = true
	_update_caps()
	_update_hover()
	_update_context(Time.get_ticks_msec())


func _update_caps() -> void:
	if _focus_lost:
		_clear_states()
		return
	var now: int = Time.get_ticks_msec()
	for entry in _caps:
		var cap: KeyCap = entry.get("cap") as KeyCap
		if cap == null or not is_instance_valid(cap):
			continue
		var spec: Dictionary = entry.get("spec", {}) as Dictionary
		var active := false
		for action in spec.get("actions", []):
			if Input.is_action_pressed(str(action)):
				active = true
				break
		if not active:
			for binding in spec.get("bindings", []):
				if _binding_active(binding as Dictionary):
					active = true
					break
		if not active and int(spec.get("mouse", -1)) >= 0:
			active = Input.is_mouse_button_pressed(int(spec["mouse"]))
		if not active and bool(spec.get("motion", false)):
			active = now <= _mouse_active_until
		if not active and bool(spec.get("wheel", false)):
			active = now <= _wheel_active_until
		cap.pressed = active


func _update_hover() -> void:
	if _focus_lost:
		_clear_hover()
		return
	var mouse: Vector2 = get_viewport().get_mouse_position()
	for entry in _chips:
		var control: Control = entry.get("control") as Control
		if control == null or not is_instance_valid(control):
			continue
		var over: bool = control.is_visible_in_tree() \
			and control.get_global_rect().has_point(mouse)
		for cap in entry.get("caps", []):
			var kc := cap as KeyCap
			if kc != null:
				kc.hovered = over
		var lbl := entry.get("label") as Label
		if lbl != null and is_instance_valid(lbl):
			lbl.add_theme_color_override("font_color",
				C_LABEL_HOVER if over else C_LABEL)


func _clear_hover() -> void:
	for entry in _chips:
		for cap in entry.get("caps", []):
			var kc := cap as KeyCap
			if kc != null:
				kc.hovered = false
		var lbl := entry.get("label") as Label
		if lbl != null and is_instance_valid(lbl):
			lbl.add_theme_color_override("font_color", C_LABEL)


func _clear_states() -> void:
	for entry in _caps:
		var cap := entry.get("cap") as KeyCap
		if cap != null:
			cap.pressed = false
			cap.hovered = false
	_clear_hover()


# ── Contextual LMB label ───────────────────────────────────────────────
func _update_context(now: int) -> void:
	if _focus_lost or not visible:
		return
	if now < _next_context_scan:
		return
	_next_context_scan = now + 120
	var mouse: Vector2 = get_viewport().get_mouse_position()
	var ctx: Array = _resolve_context(mouse)
	if ctx.is_empty():
		return
	var label: String = str(ctx[0])
	var destroy: bool = bool(ctx[1])
	if label == _context_label and destroy == _context_destroy:
		return
	_apply_context(label, destroy)


func _apply_context(label: String, destroy: bool) -> void:
	_context_label = label
	_context_destroy = destroy
	if _lmb_label != null and is_instance_valid(_lmb_label):
		_lmb_label.text = label
	if _lmb_shift_cap != null and is_instance_valid(_lmb_shift_cap):
		_lmb_shift_cap.visible = destroy
	if _lmb_sep != null and is_instance_valid(_lmb_sep):
		_lmb_sep.visible = destroy
	# Keep exactly one Shift visible for the destroy combo. In manual mode the
	# left cluster keeps WASD but its sprint Shift/SPRINT label step aside; in
	# point-and-click mode the whole left cluster is only Shift, so hide it.
	if Global.point_and_click:
		if _movement_cluster != null and is_instance_valid(_movement_cluster):
			_movement_cluster.visible = not destroy
	elif _movement_shift_cap != null and is_instance_valid(_movement_shift_cap):
		_movement_shift_cap.visible = not destroy
		if _movement_sprint_label != null and is_instance_valid(_movement_sprint_label):
			_movement_sprint_label.visible = not destroy
	call_deferred("_layout_clusters")


func _resolve_context(mouse: Vector2) -> Array:
	var fallback: String = "MOVE" if Global.point_and_click else "USE"
	var vp := get_viewport()
	if vp == null or not vp.get_visible_rect().has_point(mouse):
		return [fallback, false]
	if Global.is_point_over_ui(mouse):
		return [fallback, false]
	if Global.world_node == null or not is_instance_valid(Global.world_node):
		return [fallback, false]
	var world: Vector2 = vp.get_canvas_transform().affine_inverse() * mouse
	var player: Node = Global.player_node
	if player == null or not is_instance_valid(player):
		return [fallback, false]
	var shift: bool = Input.is_key_pressed(KEY_SHIFT)

	if player.has_method("_pnc_mob_near"):
		var mob: Variant = player.call("_pnc_mob_near", world)
		if mob is Node:
			if Global.point_and_click and mob.is_in_group("Wolf") \
					and not mob.is_in_group("Sheep"):
				return ["MOVE", false]
			return ["CHASE", false] if Global.point_and_click else ["ATTACK", false]

	if player.has_method("_pnc_tree_at"):
		var tree: Variant = player.call("_pnc_tree_at", world)
		if tree != null:
			return ["CHOP", false]

	if player.has_method("_pnc_interact_target_at"):
		var target: Variant = player.call("_pnc_interact_target_at", world)
		if target != null:
			if shift:
				return ["DESTROY", true]
			return ["INTERACT", false] if Global.point_and_click \
				else ["USE", false]

	if player.has_method("_pnc_point_has_target") \
			and bool(player.call("_pnc_point_has_target", world)):
		if shift:
			return ["DESTROY", true]
		return ["MINE", false]

	return [fallback, false]


# ── Build ───────────────────────────────────────────────────────────────
func _rebuild() -> void:
	if not is_inside_tree():
		return
	for child in get_children():
		remove_child(child)
		child.queue_free()
	_caps.clear()
	_chips.clear()
	_lmb_label = null
	_lmb_shift_cap = null
	_lmb_sep = null
	_movement_shift_cap = null
	_movement_sprint_label = null
	_context_label = "MOVE" if Global.point_and_click else "USE"
	_context_destroy = false
	_next_context_scan = 0

	var vp: Vector2 = get_viewport().get_visible_rect().size
	_s = clampf(minf(Global.ui_scale, vp.x / 1024.0), 0.75, 1.8)
	_movement_cluster = _build_movement_cluster()
	_movement_cluster.name = "MovementCluster"
	add_child(_movement_cluster)
	_action_cluster = _build_action_cluster(Global.point_and_click)
	_action_cluster.name = "ActionCluster"
	add_child(_action_cluster)
	call_deferred("_layout_clusters")
	_refresh_visibility()


func _layout_clusters() -> void:
	if _movement_cluster == null or _action_cluster == null:
		return
	_movement_cluster.reset_size()
	_action_cluster.reset_size()
	var vp: Vector2 = get_viewport().get_visible_rect().size
	var safe: Vector4 = Global.ui_safe_insets
	var margin: int = maxi(12, int(MARGIN_BASE * _s))
	var bottom: int = int(vp.y - safe.w) - margin
	# On very narrow windows the two clusters are lifted above the centred
	# hotbar rather than covering it.
	var lift: int = int(140.0 * _s) if vp.x < 780.0 else 0
	_movement_cluster.position = Vector2(
		int(safe.x) + margin, bottom - int(_movement_cluster.size.y) - lift)
	_action_cluster.position = Vector2(
		int(vp.x - safe.z) - margin - int(_action_cluster.size.x),
		bottom - int(_action_cluster.size.y) - lift)


func _key_px() -> int:
	return maxi(18, int(KEY_SIZE_BASE * _s))


func _gap_px() -> int:
	return maxi(2, int(KEY_GAP_BASE * _s))


func _build_movement_cluster() -> Control:
	if Global.point_and_click:
		return _build_standalone_shift()
	var key: int = _key_px()
	var gap: int = _gap_px()
	var shift_h: int = maxi(16, int(key * 0.68))
	var label_h: int = maxi(9, int(10 * _s))
	var labels: Dictionary = _movement_labels()
	var widths: Array = []
	for d in ["up", "left", "down", "right"]:
		var l: String = str((labels.get(d, {}) as Dictionary).get("label", "?"))
		widths.append(maxi(key, _measure_key(l)))
	var key_w: int = int(widths.max()) if not widths.is_empty() else key
	var shift_w: int = key_w * 2 + gap
	var cluster := Control.new()
	cluster.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cluster.custom_minimum_size = Vector2(
		key_w * 3 + gap * 2,
		key_w * 2 + gap + int(4 * _s) + shift_h + label_h)
	cluster.size = cluster.custom_minimum_size

	var positions := {
		"up": Vector2(key_w + gap, 0),
		"left": Vector2(0, key_w + gap),
		"down": Vector2(key_w + gap, key_w + gap),
		"right": Vector2((key_w + gap) * 2, key_w + gap),
	}
	for d in ["up", "left", "down", "right"]:
		var info: Dictionary = labels.get(d, {}) as Dictionary
		var cap := _make_keycap(str(info.get("label", "?")),
			info.get("spec", {}) as Dictionary)
		cap.position = positions[d]
		cap.size = Vector2(key_w, key_w)
		cap.custom_minimum_size = cap.size
		cluster.add_child(cap)
		_chips.append({"control": cap, "caps": [cap], "label": null})

	var shift_y: int = key_w * 2 + gap + int(4 * _s)
	var shift := _make_keycap("SHIFT", _raw_spec(KEY_SHIFT))
	shift.position = Vector2(0, shift_y)
	shift.size = Vector2(shift_w, shift_h)
	shift.custom_minimum_size = shift.size
	cluster.add_child(shift)
	_movement_shift_cap = shift
	var sprint := _small_label("SPRINT", shift_w)
	sprint.position = Vector2(0, shift_y + shift_h + int(1 * _s))
	cluster.add_child(sprint)
	_movement_sprint_label = sprint
	_chips.append({"control": shift, "caps": [shift], "label": sprint})
	return cluster


## Point-and-click hides WASD (movement is click-driven), but Shift still
## sprints. Keep it as a single floating key in the bottom-left corner.
func _build_standalone_shift() -> Control:
	var key: int = _key_px()
	var shift_h: int = maxi(16, int(key * 0.68))
	var label_h: int = maxi(9, int(10 * _s))
	var shift_w: int = maxi(key * 2, _measure_key("SHIFT") + int(8 * _s))
	var cluster := Control.new()
	cluster.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cluster.custom_minimum_size = Vector2(shift_w, shift_h + label_h)
	cluster.size = cluster.custom_minimum_size
	var shift := _make_keycap("SHIFT", _raw_spec(KEY_SHIFT))
	shift.position = Vector2.ZERO
	shift.size = Vector2(shift_w, shift_h)
	shift.custom_minimum_size = shift.size
	cluster.add_child(shift)
	_movement_shift_cap = shift
	var sprint := _small_label("SPRINT", shift_w)
	sprint.position = Vector2(0, shift_h + int(1 * _s))
	cluster.add_child(sprint)
	_movement_sprint_label = sprint
	_chips.append({"control": shift, "caps": [shift], "label": sprint})
	return cluster


func _build_action_cluster(on: bool) -> Control:
	var cluster := HBoxContainer.new()
	cluster.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cluster.add_theme_constant_override("separation", int(14 * _s))
	cluster.alignment = BoxContainer.ALIGNMENT_END
	cluster.add_child(_build_lmb_chip())
	cluster.add_child(_action_chip(
		[_cap_token("CTRL", _raw_spec(KEY_CTRL))], "BUILD"))
	return cluster


## One LMB chip for every left-click context. The label follows the hovered
## target; Shift is attached only for the contextual DESTROY action.
func _build_lmb_chip() -> Control:
	var chip := VBoxContainer.new()
	chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chip.add_theme_constant_override("separation", int(1 * _s))
	var caps_row := HBoxContainer.new()
	caps_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	caps_row.add_theme_constant_override("separation", int(3 * _s))
	caps_row.alignment = BoxContainer.ALIGNMENT_CENTER
	chip.add_child(caps_row)

	_lmb_shift_cap = _make_keycap("SHIFT", _raw_spec(KEY_SHIFT))
	_lmb_shift_cap.visible = _context_destroy
	caps_row.add_child(_lmb_shift_cap)
	_lmb_sep = Label.new()
	_lmb_sep.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_lmb_sep.text = "+"
	_lmb_sep.add_theme_font_size_override("font_size", _font_size(7.4))
	_lmb_sep.add_theme_color_override("font_color", C_LABEL)
	_lmb_sep.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_lmb_sep.visible = _context_destroy
	caps_row.add_child(_lmb_sep)
	var lmb := _make_keycap("LMB", _mouse_spec(MOUSE_BUTTON_LEFT))
	caps_row.add_child(lmb)

	_lmb_label = _small_label(_context_label, 0)
	_lmb_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_lmb_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	chip.add_child(_lmb_label)
	_chips.append({"control": chip, "caps": [_lmb_shift_cap, lmb],
		"label": _lmb_label})
	return chip


func _action_chip(tokens: Array, text: String) -> Control:
	var chip := VBoxContainer.new()
	chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chip.add_theme_constant_override("separation", int(1 * _s))
	var caps_row := HBoxContainer.new()
	caps_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	caps_row.add_theme_constant_override("separation", int(3 * _s))
	caps_row.alignment = BoxContainer.ALIGNMENT_CENTER
	chip.add_child(caps_row)
	var caps: Array = []
	for token in tokens:
		if token is String:
			var sep := Label.new()
			sep.mouse_filter = Control.MOUSE_FILTER_IGNORE
			sep.text = str(token)
			sep.add_theme_font_size_override("font_size", _font_size(7.4))
			sep.add_theme_color_override("font_color", C_LABEL)
			sep.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			caps_row.add_child(sep)
		else:
			var tok: Dictionary = token as Dictionary
			var cap := _make_keycap(str(tok.get("label", "?")),
				tok.get("spec", {}) as Dictionary)
			caps_row.add_child(cap)
			caps.append(cap)
	var lbl := _small_label(text, 0)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	chip.add_child(lbl)
	_chips.append({"control": chip, "caps": caps, "label": lbl})
	return chip


func _make_keycap(label: String, spec: Dictionary) -> KeyCap:
	var cap := KeyCap.new()
	cap.label = label
	cap.font_size = _font_size(8.2)
	cap.height_px = _key_px()
	cap.pad_x = maxi(4, int(5 * _s))
	_caps.append({"cap": cap, "spec": spec})
	return cap


func _small_label(text: String, width: int) -> Label:
	var lbl := Label.new()
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", _font_size(6.4))
	lbl.add_theme_color_override("font_color", C_LABEL)
	lbl.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.75))
	lbl.add_theme_constant_override("shadow_offset_x", 1)
	lbl.add_theme_constant_override("shadow_offset_y", 1)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	if width > 0:
		lbl.custom_minimum_size = Vector2(width, maxi(9, int(10 * _s)))
		lbl.size = lbl.custom_minimum_size
	return lbl


func _measure_key(label: String) -> int:
	var probe := KeyCap.new()
	probe.label = label
	probe.font_size = _font_size(8.2)
	probe.height_px = _key_px()
	probe.pad_x = maxi(4, int(5 * _s))
	var f: Font = probe.get_theme_font("font")
	if f == null:
		f = ThemeDB.fallback_font
	var text_w: float = f.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1,
		probe.font_size).x
	var result: int = maxi(probe.height_px, int(text_w) + probe.pad_x * 2)
	probe.free()
	return result


func _font_size(base: float) -> int:
	return maxi(8, int(round(Global.ui_font_size(base))))


# ── Input specs ─────────────────────────────────────────────────────────
func _movement_labels() -> Dictionary:
	var out := {}
	for pair in [["up", "gameplay_up", "W"], ["left", "gameplay_left", "A"],
			["down", "gameplay_down", "S"], ["right", "gameplay_right", "D"]]:
		var dir := str(pair[0])
		var action := str(pair[1])
		var fallback := str(pair[2])
		var ev := _first_key_event(action)
		var label := _key_label_from_event(ev) if ev != null else fallback
		var spec := {"bindings": [_binding_from_event(ev)]} if ev != null \
			else {"bindings": []}
		out[dir] = {"label": label, "spec": spec}
	return out


func _cap_token(label: String, spec: Dictionary) -> Dictionary:
	return {"label": label, "spec": spec}


func _raw_binding(code: int) -> Dictionary:
	return {"physical": code, "keycode": code}


func _raw_spec(code: int) -> Dictionary:
	return {"bindings": [_raw_binding(code)]}


func _mouse_spec(button: int) -> Dictionary:
	return {"mouse": button}


func _first_key_event(action: String) -> InputEventKey:
	for event in InputMap.action_get_events(action):
		if event is InputEventKey:
			return event as InputEventKey
	return null


func _key_label_from_event(event: InputEventKey) -> String:
	var code: int = event.physical_keycode if event.physical_keycode != 0 \
		else event.keycode
	if code == 0:
		return "?"
	return OS.get_keycode_string(code).to_upper()


func _binding_from_event(event: InputEventKey) -> Dictionary:
	var physical: int = int(event.physical_keycode)
	var logical: int = int(event.keycode)
	if physical == 0:
		physical = logical
	if logical == 0:
		logical = physical
	return {"physical": physical, "keycode": logical}


func _binding_active(binding: Dictionary) -> bool:
	var physical: int = int(binding.get("physical", 0))
	var logical: int = int(binding.get("keycode", 0))
	if physical != 0 and Input.is_physical_key_pressed(physical):
		return true
	if logical != 0 and Input.is_key_pressed(logical):
		return true
	return false
