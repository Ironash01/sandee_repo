extends Control

const C_PANEL  := Color(0.08, 0.10, 0.20, 0.97)
const C_BORDER := Color(0.22, 0.32, 0.58, 1.00)
const C_TITLE  := Color(0.80, 0.90, 1.00, 1.00)
const C_MUTED  := Color(0.55, 0.65, 0.85, 1.00)

const BASE_TITLE_SIZE: int = 28
const BASE_LABEL_SIZE: int = 17

var _ui_scale_lbl: Label  = null
var _cam_zoom_lbl: Label  = null
var _content:      Control = null
var _rebuilding:   bool    = false

func _ready() -> void:
	var panel: ColorRect = $ColorRect
	panel.color = C_PANEL
	for child in panel.get_children():
		child.queue_free()
	await get_tree().process_frame
	_build_settings(panel)
	Global.ui_scale_changed.connect(_on_ui_scale_rebuild)

# Rebuild whenever ui_scale changes so font sizes stay in sync.
func _on_ui_scale_rebuild(_v: float) -> void:
	if _rebuilding:
		return
	_rebuilding = true
	var panel: ColorRect = $ColorRect
	if _content != null and is_instance_valid(_content):
		_content.queue_free()
		_content = null
	await get_tree().process_frame
	_rebuilding = false
	if is_instance_valid(panel):
		_build_settings(panel)

func _build_settings(panel: ColorRect) -> void:
	var s: float = Global.ui_scale

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left",   int(40 * s))
	margin.add_theme_constant_override("margin_right",  int(40 * s))
	margin.add_theme_constant_override("margin_top",    int(30 * s))
	margin.add_theme_constant_override("margin_bottom", int(30 * s))
	panel.add_child(margin)
	_content = margin

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", int(14 * s))
	margin.add_child(vbox)

	# Title
	var title := Label.new()
	title.text = "Settings"
	title.add_theme_font_size_override("font_size", int(BASE_TITLE_SIZE * s))
	title.add_theme_color_override("font_color", C_TITLE)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	var div := ColorRect.new()
	div.color = C_BORDER
	div.custom_minimum_size = Vector2(0, 1)
	vbox.add_child(div)

	# ── Fullscreen ────────────────────────────────────────────────
	vbox.add_child(_lbl("Fullscreen", s))
	var fs_btn := CheckButton.new()
	fs_btn.button_pressed = \
		DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
	fs_btn.add_theme_font_size_override("font_size", int(BASE_LABEL_SIZE * s))
	fs_btn.add_theme_color_override("font_color", C_MUTED)
	fs_btn.toggled.connect(func(on: bool) -> void:
		DisplayServer.window_set_mode(
			DisplayServer.WINDOW_MODE_FULLSCREEN if on \
			else DisplayServer.WINDOW_MODE_WINDOWED
		)
	)
	vbox.add_child(fs_btn)

	if Global.is_point_and_click_available():
		# ── Point-and-Click Movement (optional, OFF by default) ──────
		var pnc_btn := CheckButton.new()
		pnc_btn.text = "Point-and-Click Movement"
		pnc_btn.button_pressed = Global.point_and_click
		pnc_btn.add_theme_font_size_override("font_size", int(BASE_LABEL_SIZE * s))
		pnc_btn.add_theme_color_override("font_color", C_MUTED)
		pnc_btn.tooltip_text = "Left-click / tap the world to walk there. Existing keyboard, mouse and joystick controls are unchanged."
		pnc_btn.toggled.connect(func(on: bool) -> void: Global.set_point_and_click(on))
		vbox.add_child(pnc_btn)

	# ── UI Scale ─────────────────────────────────────────────────
	_ui_scale_lbl = _lbl("UI Scale:  %.2f×" % Global.ui_scale, s)
	vbox.add_child(_ui_scale_lbl)
	var ui_slider := _make_slider(0.5, 2.0, 0.25, Global.ui_scale, s)
	ui_slider.value_changed.connect(_on_ui_scale_changed)
	vbox.add_child(ui_slider)

	# ── Camera Zoom ───────────────────────────────────────────────
	_cam_zoom_lbl = _lbl("Camera Zoom:  %.1f×" % Global.camera_zoom, s)
	vbox.add_child(_cam_zoom_lbl)
	var cam_slider := _make_slider(1.0, 4.0, 0.1, Global.camera_zoom, s)
	cam_slider.value_changed.connect(_on_cam_zoom_changed)
	vbox.add_child(cam_slider)

# ── Handlers ──────────────────────────────────────────────────────
func _on_ui_scale_changed(v: float) -> void:
	Global.ui_scale     = v
	Global.ui_scale_set = true
	Global.ui_scale_changed.emit(v)
	if _ui_scale_lbl != null and is_instance_valid(_ui_scale_lbl):
		_ui_scale_lbl.text = "UI Scale:  %.2f×" % v

func _on_cam_zoom_changed(v: float) -> void:
	Global.camera_zoom = v
	Global.camera_zoom_changed.emit(v)
	if _cam_zoom_lbl != null and is_instance_valid(_cam_zoom_lbl):
		_cam_zoom_lbl.text = "Camera Zoom:  %.1f×" % v

# Kept so the scene file's existing connection doesn't error on load.
func _on_cam_slider_value_changed(value: float) -> void:
	_on_cam_zoom_changed(value)

# ── Helpers ───────────────────────────────────────────────────────
func _lbl(text: String, s: float = 1.0) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", int(BASE_LABEL_SIZE * s))
	l.add_theme_color_override("font_color", C_TITLE)
	return l

func _make_slider(min_v: float, max_v: float, step: float, current: float, s: float = 1.0) -> HSlider:
	var sl := HSlider.new()
	sl.min_value = min_v
	sl.max_value = max_v
	sl.step      = step
	sl.value     = current
	sl.custom_minimum_size = Vector2(int(300 * s), int(26 * s))
	return sl
