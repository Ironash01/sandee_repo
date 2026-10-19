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

# ── Categorised settings (sidebar + content pane) ─────────────────
var _settings_content: VBoxContainer
var _category_btns:    Dictionary = {}   # category name -> sidebar Button
var _settings_category: String = "Audio"
const CATEGORIES: Array = ["Audio", "Display", "Gameplay", "Controls"]

# ── Key rebinding ─────────────────────────────────────────────────
# action -> human label. Keyboard actions only (mouse/escape stay fixed).
const REBINDABLE: Array = [
	["gameplay_up",    "Move Up"],
	["gameplay_down",  "Move Down"],
	["gameplay_left",  "Move Left"],
	["gameplay_right", "Move Right"],
	["inventory",      "Inventory"],
	["hotbar_1", "Hotbar 1"], ["hotbar_2", "Hotbar 2"], ["hotbar_3", "Hotbar 3"],
	["hotbar_4", "Hotbar 4"], ["hotbar_5", "Hotbar 5"], ["hotbar_6", "Hotbar 6"],
	["hotbar_7", "Hotbar 7"], ["hotbar_8", "Hotbar 8"], ["hotbar_9", "Hotbar 9"],
]
var _rebind_action:  String = ""
var _rebind_buttons: Dictionary = {}   # action -> Button

# ── Lifecycle ─────────────────────────────────────────────────────
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_build_overlay()
	_build_pause_panel()
	_build_settings_panel()
	Global.ui_scale_changed.connect(_on_ui_scale)
	visible = false

func _on_ui_scale(_s: float) -> void:
	# Rebuild panels with new scale
	if _pause_center != null:
		_pause_center.queue_free()
		_pause_center = null
	if _settings_center != null:
		_settings_center.queue_free()
		_settings_center = null
	_val_labels.clear()
	_build_pause_panel()
	_build_settings_panel()

# ── Dark overlay ──────────────────────────────────────────────────
func _build_overlay() -> void:
	_overlay = ColorRect.new()
	_overlay.color = C_OVERLAY
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_overlay)

# ── Pause panel ───────────────────────────────────────────────────
func _build_pause_panel() -> void:
	var s: float = Global.ui_scale
	_pause_center = CenterContainer.new()
	_pause_center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_pause_center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(280 * s, 270 * s)
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
	title.add_theme_font_size_override("font_size", int(26 * s))
	title.add_theme_color_override("font_color", C_TITLE)
	vbox.add_child(title)

	_add_spacer(vbox, int(10 * s))
	_make_btn(vbox, "Resume",       _on_resume).tooltip_text       = "Return to the game."
	_make_btn(vbox, "Settings",     _on_open_settings).tooltip_text = "Audio, display, gameplay and controls."
	_make_btn(vbox, "Quit to Menu", _on_quit).tooltip_text         = "Save and return to the main menu."

# ── Settings panel (sidebar categories + content) ─────────────────
func _build_settings_panel() -> void:
	var s: float = Global.ui_scale
	_settings_center = CenterContainer.new()
	_settings_center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_settings_center.visible = false
	add_child(_settings_center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(640 * s, 440 * s)
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
		margin.add_theme_constant_override("margin_" + side, 20)
	panel.add_child(margin)

	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", int(12 * s))
	margin.add_child(outer)

	var title := Label.new()
	title.text = "SETTINGS"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", int(22 * s))
	title.add_theme_color_override("font_color", C_TITLE)
	outer.add_child(title)

	# Sidebar (categories) + content pane.
	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", int(16 * s))
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	outer.add_child(body)

	var sidebar := VBoxContainer.new()
	sidebar.add_theme_constant_override("separation", int(6 * s))
	sidebar.custom_minimum_size = Vector2(int(150 * s), 0)
	body.add_child(sidebar)
	_category_btns.clear()
	for cat in CATEGORIES:
		var b := Button.new()
		b.text = cat
		b.custom_minimum_size = Vector2(0, int(34 * s))
		b.add_theme_font_size_override("font_size", int(13 * s))
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.tooltip_text = "Show the %s settings." % cat
		var c: String = cat
		b.pressed.connect(func() -> void: _show_settings_category(c))
		sidebar.add_child(b)
		_category_btns[cat] = b

	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical   = Control.SIZE_EXPAND_FILL
	body.add_child(scroll)
	_settings_content = VBoxContainer.new()
	_settings_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_settings_content.add_theme_constant_override("separation", int(10 * s))
	scroll.add_child(_settings_content)

	# Back to the pause panel.
	var back := Button.new()
	back.text = "< Back"
	back.custom_minimum_size = Vector2(int(120 * s), int(34 * s))
	back.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	back.pressed.connect(_on_back)
	outer.add_child(back)

	_show_settings_category(_settings_category)

# Build the content pane for one category.
func _show_settings_category(cat: String) -> void:
	_settings_category = cat
	_rebind_action = ""
	_rebind_buttons.clear()
	for c in _settings_content.get_children():
		c.queue_free()
	for k in _category_btns:
		(_category_btns[k] as Button).modulate = Color(1, 1, 1, 1) if k == cat else Color(0.65, 0.72, 0.85, 1)
	match cat:
		"Audio":    _build_settings_audio()
		"Display":  _build_settings_display()
		"Gameplay": _build_settings_gameplay()
		"Controls": _build_settings_controls()

func _build_settings_audio() -> void:
	_section_label(_settings_content, "Audio")
	_add_slider_row(_settings_content, "Master Volume", "master_volume", 0.0, 1.0, 0.05, Global.master_volume,
		"Overall game volume (music + sound effects).")
	_add_slider_row(_settings_content, "Music Volume",  "music_volume",  0.0, 1.0, 0.05, Global.music_volume,
		"Background music volume.")
	_add_slider_row(_settings_content, "SFX Volume",    "sfx_volume",    0.0, 1.0, 0.05, Global.sfx_volume,
		"Sound effects volume (mining, footsteps, mobs).")

func _build_settings_display() -> void:
	var s: float = Global.ui_scale
	_section_label(_settings_content, "Display")
	_add_slider_row(_settings_content, "Camera Zoom", "camera_zoom", 0.5, 3.0, 0.1, Global.camera_zoom,
		"How far the camera is zoomed out. Higher = see more of the world.")

	var ui_row := HBoxContainer.new()
	ui_row.add_theme_constant_override("separation", 6)
	ui_row.tooltip_text = "Size of every interface element (menus, text, slots)."
	_settings_content.add_child(ui_row)
	var ui_lbl := Label.new()
	ui_lbl.text = "UI Scale"
	ui_lbl.custom_minimum_size = Vector2(int(140 * s), 0)
	ui_lbl.add_theme_font_size_override("font_size", int(13 * s))
	ui_lbl.tooltip_text = ui_row.tooltip_text
	ui_row.add_child(ui_lbl)
	for entry in [["S", 0.75], ["M", 1.0], ["L", 1.5]]:
		var scale_btn := Button.new()
		scale_btn.text = entry[0] as String
		scale_btn.custom_minimum_size = Vector2(int(38 * s), 0)
		scale_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		scale_btn.tooltip_text = "UI scale: " + ("Small" if entry[0] == "S" else "Medium" if entry[0] == "M" else "Large")
		var scale_val: float = entry[1] as float
		scale_btn.pressed.connect(func() -> void: _on_ui_scale_preset(scale_val))
		ui_row.add_child(scale_btn)

	var fs_row := HBoxContainer.new()
	_settings_content.add_child(fs_row)
	var fs_lbl := Label.new()
	fs_lbl.text = "Fullscreen"
	fs_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	fs_lbl.add_theme_font_size_override("font_size", int(13 * s))
	fs_lbl.tooltip_text = "Play in fullscreen mode."
	fs_row.add_child(fs_lbl)
	var fs_btn := CheckButton.new()
	fs_btn.button_pressed = DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
	fs_btn.tooltip_text = "Play in fullscreen mode."
	fs_btn.toggled.connect(_on_fullscreen_toggled)
	fs_row.add_child(fs_btn)

func _build_settings_gameplay() -> void:
	var s: float = Global.ui_scale
	_section_label(_settings_content, "Gameplay")
	var pi_row := HBoxContainer.new()
	_settings_content.add_child(pi_row)
	var pi_lbl := Label.new()
	pi_lbl.text = "Pause on Inventory"
	pi_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pi_lbl.add_theme_font_size_override("font_size", int(13 * s))
	pi_lbl.tooltip_text = "Pause the game while your inventory is open."
	pi_row.add_child(pi_lbl)
	var pi_btn := CheckButton.new()
	pi_btn.button_pressed = Global.pause_on_inventory
	pi_btn.tooltip_text = "Pause the game while your inventory is open."
	pi_btn.toggled.connect(_on_pause_inventory_toggled)
	pi_row.add_child(pi_btn)

	# Opaque quest-tracker background.
	var qb_row := HBoxContainer.new()
	_settings_content.add_child(qb_row)
	var qb_lbl := Label.new()
	qb_lbl.text = "Opaque Quest Background"
	qb_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	qb_lbl.add_theme_font_size_override("font_size", int(13 * s))
	qb_lbl.tooltip_text = "Draw the quest tracker on a solid panel instead of floating text."
	qb_row.add_child(qb_lbl)
	var qb_btn := CheckButton.new()
	qb_btn.button_pressed = Global.quest_opaque_bg
	qb_btn.tooltip_text = "Draw the quest tracker on a solid panel instead of floating text."
	qb_btn.toggled.connect(_on_quest_bg_toggled)
	qb_row.add_child(qb_btn)

func _on_quest_bg_toggled(pressed: bool) -> void:
	Global.quest_opaque_bg = pressed
	Global.quest_bg_changed.emit(pressed)

func _build_settings_controls() -> void:
	var s: float = Global.ui_scale
	_section_label(_settings_content, "Keyboard")
	var hint := Label.new()
	hint.text = "Click a binding, then press a key. Esc cancels."
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.add_theme_font_size_override("font_size", int(11 * s))
	hint.add_theme_color_override("font_color", C_MUTED)
	_settings_content.add_child(hint)
	for entry in REBINDABLE:
		_add_rebind_row(_settings_content, str(entry[0]), str(entry[1]))

func _add_rebind_row(parent: Node, action: String, label_text: String) -> void:
	var s: float = Global.ui_scale
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", int(8 * s))
	parent.add_child(row)
	var lbl := Label.new()
	lbl.text = label_text
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbl.add_theme_font_size_override("font_size", int(13 * s))
	row.add_child(lbl)
	var btn := Button.new()
	btn.text = _key_text(action)
	btn.custom_minimum_size = Vector2(int(130 * s), int(30 * s))
	btn.add_theme_font_size_override("font_size", int(12 * s))
	btn.tooltip_text = "Click, then press a key to rebind \"%s\"." % label_text
	btn.pressed.connect(func() -> void: _start_rebind(action))
	row.add_child(btn)
	_rebind_buttons[action] = btn

func _key_text(action: String) -> String:
	var names := PackedStringArray()
	for e in InputMap.action_get_events(action):
		if e is InputEventKey:
			names.append(OS.get_keycode_string((e as InputEventKey).physical_keycode))
	return ", ".join(names) if not names.is_empty() else "—"

func _start_rebind(action: String) -> void:
	_rebind_action = action
	for a in _rebind_buttons:
		(_rebind_buttons[a] as Button).text = "Press a key…" if a == action else _key_text(a)

func _apply_rebind(key_event: InputEventKey) -> void:
	var action: String = _rebind_action
	_rebind_action = ""
	if action.is_empty():
		return
	InputMap.action_erase_events(action)
	var ev := InputEventKey.new()
	ev.physical_keycode = key_event.physical_keycode
	InputMap.action_add_event(action, ev)
	for a in _rebind_buttons:
		(_rebind_buttons[a] as Button).text = _key_text(a)
	var actions: Array = []
	for entry in REBINDABLE:
		actions.append(entry[0])
	Global.save_keybinds(actions)

func _cancel_rebind() -> void:
	_rebind_action = ""
	for a in _rebind_buttons:
		(_rebind_buttons[a] as Button).text = _key_text(a)

# ── Builder helpers ───────────────────────────────────────────────
func _make_btn(parent: Node, label: String, callback: Callable) -> Button:
	var btn := Button.new()
	btn.text = label
	btn.custom_minimum_size = Vector2(240 * Global.ui_scale, 42 * Global.ui_scale)
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
		min_v: float, max_v: float, step_v: float, init_v: float,
		tooltip: String = "") -> void:
	var row := HBoxContainer.new()
	parent.add_child(row)

	var lbl := Label.new()
	lbl.text = label_text
	lbl.custom_minimum_size = Vector2(140, 0)
	lbl.add_theme_font_size_override("font_size", 13)
	lbl.tooltip_text = tooltip
	row.add_child(lbl)

	var slider := HSlider.new()
	slider.min_value = min_v
	slider.max_value = max_v
	slider.step      = step_v
	slider.value     = init_v
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.tooltip_text = tooltip
	slider.value_changed.connect(func(v: float) -> void: _on_setting_changed(key, v))
	row.add_child(slider)

	var val_lbl := Label.new()
	val_lbl.text = _fmt(init_v, key)
	val_lbl.custom_minimum_size = Vector2(46, 0)
	val_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	val_lbl.tooltip_text = tooltip
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
	if key in _val_labels:
		(_val_labels[key] as Label).text = _fmt(value, key)

func _fmt(value: float, key: String) -> String:
	if key == "camera_zoom":
		return "%.1fx" % value
	return "%d%%" % int(value * 100.0)

func _on_pause_inventory_toggled(pressed: bool) -> void:
	Global.pause_on_inventory = pressed

func _on_ui_scale_preset(scale_val: float) -> void:
	Global.ui_scale     = scale_val
	Global.ui_scale_set = true
	Global.ui_scale_changed.emit(scale_val)

func _on_fullscreen_toggled(pressed: bool) -> void:
	if pressed:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)

# ── Panel navigation ──────────────────────────────────────────────
func show_menu() -> void:
	if Global.any_ui_open():
		return
	Global.pause_menu_open = true
	visible = true
	_pause_center.visible    = true
	_settings_center.visible = false
	get_tree().paused = true

func hide_menu() -> void:
	Global.pause_menu_open = false
	visible = false
	# Resume only when NOTHING else still needs the game paused — the same rule
	# Global.close_ui() uses. Writing paused = false unconditionally here would
	# resume gameplay while another UI/dialog was still open.
	if not Global.any_ui_open():
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
	# Leave any active cave/pixie cave/dungeon first so the cave's node tree is
	# torn down cleanly and the overworld is restored — otherwise change_scene
	# freeing the cave mid-pause can hang (quit-to-menu inside caves).
	if Global.game_node != null and Global.game_node.has_method("cleanup_for_menu"):
		Global.game_node.call("cleanup_for_menu")
	if Global.active_save_slot > 0:
		Global.save_game(Global.active_save_slot)
	Global.pause_menu_open = false
	get_tree().paused = false
	get_tree().change_scene_to_file("res://scenes/ui/main_menu_ver.tscn")

# ── Escape key ────────────────────────────────────────────────────
func _input(event: InputEvent) -> void:
	# While listening for a rebind, the next key press becomes the new binding
	# (Esc cancels). Swallow everything so it doesn't also toggle the menu.
	if _rebind_action != "":
		if event is InputEventKey and event.pressed and not event.echo:
			if (event as InputEventKey).keycode == KEY_ESCAPE:
				_cancel_rebind()
			else:
				_apply_rebind(event as InputEventKey)
			get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("escape"):
		if visible and _settings_center.visible:
			_on_back()
		elif visible:
			hide_menu()
		elif not Global.any_ui_open():
			show_menu()
