extends Control

# ── Shared dark navy theme (matches inventory) ────────────────────
const C_PANEL   := Color(0.08, 0.10, 0.20, 0.97)
const C_BORDER  := Color(0.22, 0.32, 0.58, 1.00)
const C_TITLE   := Color(0.80, 0.90, 1.00, 1.00)
const C_MUTED   := Color(0.55, 0.65, 0.85, 1.00)
const C_OVERLAY := Color(0.00, 0.00, 0.00, 0.55)

# ── Internal refs ─────────────────────────────────────────────────
var _overlay:         ColorRect
var _pause_center:    CenterContainer
var _settings_center: CenterContainer

# Live-update value labels keyed by setting name
var _val_labels: Dictionary = {}

# ── Lifecycle ─────────────────────────────────────────────────────
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_preset(Control.PRESET_FULL_RECT)

	_build_overlay()
	_build_pause_panel()
	_build_settings_panel()
	Global.ui_scale_changed.connect(_on_ui_scale)

	visible = false

func _on_ui_scale(s: float) -> void:
	if _pause_center != null:
		_pause_center.scale = Vector2(s, s)
	if _settings_center != null:
		_settings_center.scale = Vector2(s, s)

# ── Dark overlay ──────────────────────────────────────────────────
func _build_overlay() -> void:
	_overlay = ColorRect.new()
	_overlay.color = C_OVERLAY
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_overlay)

# ── Pause panel ───────────────────────────────────────────────────
func _build_pause_panel() -> void:
	_pause_center = CenterContainer.new()
	_pause_center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_pause_center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(280, 270)
	var ps1 := StyleBoxFlat.new()
	ps1.bg_color     = C_PANEL
	ps1.border_color = C_BORDER
	ps1.set_border_width_all(1)
	ps1.set_corner_radius_all(6)
	ps1.content_margin_left   = 24
	ps1.content_margin_right  = 24
	ps1.content_margin_top    = 24
	ps1.content_margin_bottom = 24
	panel.add_theme_stylebox_override("panel", ps1)
	_pause_center.add_child(panel)

	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 24)
	panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 12)
	margin.add_child(vbox)

	var title := Label.new()
	title.text = "— PAUSED —"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 26)
	title.add_theme_color_override("font_color", C_TITLE)
	vbox.add_child(title)

	_add_spacer(vbox, 10)
	_make_btn(vbox, "Resume",       _on_resume)
	_make_btn(vbox, "Settings",     _on_open_settings)
	_make_btn(vbox, "Quit to Menu", _on_quit)

# ── Settings panel ────────────────────────────────────────────────
func _build_settings_panel() -> void:
	_settings_center = CenterContainer.new()
	_settings_center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_settings_center.visible = false
	add_child(_settings_center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(420, 390)
	var ps2 := StyleBoxFlat.new()
	ps2.bg_color     = C_PANEL
	ps2.border_color = C_BORDER
	ps2.set_border_width_all(1)
	ps2.set_corner_radius_all(6)
	ps2.content_margin_left   = 24
	ps2.content_margin_right  = 24
	ps2.content_margin_top    = 20
	ps2.content_margin_bottom = 24
	panel.add_theme_stylebox_override("panel", ps2)
	_settings_center.add_child(panel)

	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 24)
	panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 14)
	margin.add_child(vbox)

	var title := Label.new()
	title.text = "SETTINGS"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", C_TITLE)
	vbox.add_child(title)

	_add_spacer(vbox, 6)

	_section_label(vbox, "Audio")
	_add_slider_row(vbox, "Master Volume", "master_volume", 0.0, 1.0, 0.05, Global.master_volume)
	_add_slider_row(vbox, "Music Volume",  "music_volume",  0.0, 1.0, 0.05, Global.music_volume)
	_add_slider_row(vbox, "SFX Volume",    "sfx_volume",    0.0, 1.0, 0.05, Global.sfx_volume)

	_add_spacer(vbox, 4)

	_section_label(vbox, "Display")
	_add_slider_row(vbox, "Camera Zoom", "camera_zoom", 0.5, 3.0, 0.1, Global.camera_zoom)
	_add_slider_row(vbox, "UI Scale",     "ui_scale",    0.5, 2.0, 0.1, Global.ui_scale)

	var fs_row := HBoxContainer.new()
	vbox.add_child(fs_row)
	var fs_lbl := Label.new()
	fs_lbl.text = "Fullscreen"
	fs_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	fs_lbl.add_theme_font_size_override("font_size", 13)
	fs_row.add_child(fs_lbl)
	var fs_btn := CheckButton.new()
	fs_btn.button_pressed = DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
	fs_btn.toggled.connect(_on_fullscreen_toggled)
	fs_row.add_child(fs_btn)

	# Pause on inventory toggle
	var pi_row := HBoxContainer.new()
	vbox.add_child(pi_row)
	var pi_lbl := Label.new()
	pi_lbl.text = "Pause on Inventory"
	pi_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pi_lbl.add_theme_font_size_override("font_size", 13)
	pi_row.add_child(pi_lbl)
	var pi_btn := CheckButton.new()
	pi_btn.button_pressed = Global.pause_on_inventory
	pi_btn.toggled.connect(_on_pause_inventory_toggled)
	pi_row.add_child(pi_btn)

	_add_spacer(vbox, 10)
	_make_btn(vbox, "< Back", _on_back)

# ── Builder helpers ───────────────────────────────────────────────
func _make_btn(parent: Node, label: String, callback: Callable) -> Button:
	var btn := Button.new()
	btn.text = label
	btn.custom_minimum_size = Vector2(240, 42)
	btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	btn.pressed.connect(callback)
	parent.add_child(btn)
	return btn

func _add_spacer(parent: Node, height: int) -> void:
	var s := Control.new()
	s.custom_minimum_size = Vector2(0, height)
	parent.add_child(s)

func _section_label(parent: Node, text: String) -> void:
	var lbl := Label.new()
	lbl.text = text.to_upper()
	lbl.add_theme_font_size_override("font_size", 11)
	lbl.add_theme_color_override("font_color", C_MUTED)
	parent.add_child(lbl)

func _add_slider_row(parent: Node, label_text: String, key: String,
		min_v: float, max_v: float, step_v: float, init_v: float) -> void:
	var row := HBoxContainer.new()
	parent.add_child(row)

	var lbl := Label.new()
	lbl.text = label_text
	lbl.custom_minimum_size = Vector2(140, 0)
	lbl.add_theme_font_size_override("font_size", 13)
	row.add_child(lbl)

	var slider := HSlider.new()
	slider.min_value = min_v
	slider.max_value = max_v
	slider.step      = step_v
	slider.value     = init_v
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.value_changed.connect(func(v: float) -> void: _on_setting_changed(key, v))
	row.add_child(slider)

	var val_lbl := Label.new()
	val_lbl.text = _fmt(init_v, key)
	val_lbl.custom_minimum_size = Vector2(46, 0)
	val_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(val_lbl)
	_val_labels[key] = val_lbl

# ── Setting changes ───────────────────────────────────────────────
func _on_setting_changed(key: String, value: float) -> void:
	match key:
		"master_volume":
			Global.master_volume = value
			AudioServer.set_bus_volume_db(
				AudioServer.get_bus_index("Master"),
				linear_to_db(maxf(value, 0.0001))
			)
		"music_volume":
			Global.music_volume = value
			var idx := AudioServer.get_bus_index("Music")
			if idx != -1:
				AudioServer.set_bus_volume_db(idx, linear_to_db(maxf(value, 0.0001)))
		"sfx_volume":
			Global.sfx_volume = value
			var idx := AudioServer.get_bus_index("SFX")
			if idx != -1:
				AudioServer.set_bus_volume_db(idx, linear_to_db(maxf(value, 0.0001)))
		"camera_zoom":
			Global.camera_zoom = value
			Global.camera_zoom_changed.emit(value)
		"ui_scale":
			Global.ui_scale = value
			Global.ui_scale_changed.emit(value)
	if key in _val_labels:
		(_val_labels[key] as Label).text = _fmt(value, key)

func _fmt(value: float, key: String) -> String:
	if key in ["camera_zoom", "ui_scale"]:
		return "%.1fx" % value
	return "%d%%" % int(value * 100.0)

func _on_pause_inventory_toggled(pressed: bool) -> void:
	Global.pause_on_inventory = pressed

func _on_fullscreen_toggled(pressed: bool) -> void:
	if pressed:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)

# ── Panel navigation ──────────────────────────────────────────────
func show_menu() -> void:
	visible = true
	_pause_center.visible    = true
	_settings_center.visible = false
	get_tree().paused = true

func hide_menu() -> void:
	visible = false
	get_tree().paused = false

func _on_resume() -> void:
	hide_menu()

func _on_open_settings() -> void:
	_pause_center.visible    = false
	_settings_center.visible = true

func _on_back() -> void:
	_settings_center.visible = false
	_pause_center.visible    = true

func _on_quit() -> void:
	get_tree().paused = false
	get_tree().change_scene_to_file("res://scenes/ui/main_menu_ver.tscn")

# ── Escape key ────────────────────────────────────────────────────
func _input(event: InputEvent) -> void:
	if event.is_action_pressed("escape"):
		if visible and _settings_center.visible:
			_on_back()
		elif visible:
			hide_menu()
		else:
			show_menu()
