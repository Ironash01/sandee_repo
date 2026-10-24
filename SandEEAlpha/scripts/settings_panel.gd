extends PanelContainer

## Shared settings panel used by BOTH the pause menu and the main menu.
## Keeping one implementation means every option (audio, display, gameplay,
## controls, key rebinds, FPS) appears in both places and stays in sync.

signal close_requested
signal credits_requested

const C_PANEL   := Color(0.08, 0.10, 0.20, 0.97)
const C_BORDER  := Color(0.22, 0.32, 0.58, 1.00)
const C_TITLE   := Color(0.80, 0.90, 1.00, 1.00)
const C_MUTED   := Color(0.55, 0.65, 0.85, 1.00)

const CATEGORIES: Array = ["Audio", "Display", "Gameplay", "Controls"]
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

## Set by the main menu before adding the panel (it owns the credits overlay).
var show_credits: bool = false

var _settings_content: VBoxContainer = null
var _category_btns: Dictionary = {}
var _settings_category: String = "Audio"
var _val_labels: Dictionary = {}
var _rebind_action: String = ""
var _rebind_buttons: Dictionary = {}
var _rebind_warning: Label = null

func _ready() -> void:
	_build()

func set_show_credits(on: bool) -> void:
	show_credits = on
	if is_inside_tree():
		_build()

func is_rebinding() -> bool:
	return _rebind_action != ""

func _build() -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	_category_btns.clear()
	_val_labels.clear()
	_rebind_action = ""
	_rebind_buttons.clear()

	var s: float = Global.ui_scale
	custom_minimum_size = Vector2(int(640 * s), int(440 * s))
	var style := StyleBoxFlat.new()
	style.bg_color = C_PANEL
	style.border_color = C_BORDER
	style.set_border_width_all(1)
	style.set_corner_radius_all(6)
	style.content_margin_left   = int(24 * s)
	style.content_margin_right  = int(24 * s)
	style.content_margin_top    = int(20 * s)
	style.content_margin_bottom = int(24 * s)
	add_theme_stylebox_override("panel", style)

	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, int(20 * s))
	add_child(margin)

	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", int(12 * s))
	margin.add_child(outer)

	var title := Label.new()
	title.text = "SETTINGS"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", int(22 * s))
	title.add_theme_color_override("font_color", C_TITLE)
	outer.add_child(title)

	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", int(16 * s))
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	outer.add_child(body)

	var sidebar := VBoxContainer.new()
	sidebar.add_theme_constant_override("separation", int(6 * s))
	sidebar.custom_minimum_size = Vector2(int(150 * s), 0)
	body.add_child(sidebar)
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
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	body.add_child(scroll)
	_settings_content = VBoxContainer.new()
	_settings_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_settings_content.add_theme_constant_override("separation", int(10 * s))
	scroll.add_child(_settings_content)

	var footer := HBoxContainer.new()
	footer.alignment = BoxContainer.ALIGNMENT_CENTER
	footer.add_theme_constant_override("separation", int(8 * s))
	outer.add_child(footer)
	if show_credits:
		var credits := _footer_btn("Credits", func() -> void:
			_cancel_rebind()
			credits_requested.emit())
		footer.add_child(credits)
	var back := _footer_btn("< Back", _on_back)
	footer.add_child(back)

	_show_settings_category(_settings_category)

func _on_back() -> void:
	_cancel_rebind()
	close_requested.emit()

func _footer_btn(text: String, callback: Callable) -> Button:
	var s: float = Global.ui_scale
	var btn := Button.new()
	btn.text = text
	btn.custom_minimum_size = Vector2(int(120 * s), int(34 * s))
	btn.add_theme_font_size_override("font_size", int(12 * s))
	btn.pressed.connect(callback)
	return btn

# ── Categories ─────────────────────────────────────────────────────────────

func _show_settings_category(cat: String) -> void:
	_settings_category = cat
	_rebind_action = ""
	_rebind_buttons.clear()
	for c in _settings_content.get_children():
		_settings_content.remove_child(c)
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
	_add_slider_row(_settings_content, "Music Volume", "music_volume", 0.0, 1.0, 0.05, Global.music_volume,
		"Background music volume.")
	_add_slider_row(_settings_content, "SFX Volume", "sfx_volume", 0.0, 1.0, 0.05, Global.sfx_volume,
		"Sound effects volume (mining, footsteps, mobs).")

func _build_settings_display() -> void:
	var s: float = Global.ui_scale
	_section_label(_settings_content, "Display")
	_add_slider_row(_settings_content, "Camera Zoom", "camera_zoom", 0.5, 3.0, 0.1, Global.camera_zoom,
		"How far the camera is zoomed out. Higher = see more of the world.")

	var ui_row := HBoxContainer.new()
	ui_row.add_theme_constant_override("separation", int(6 * s))
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
	fs_lbl.tooltip_text = "Play in fullscreen mode. Saved for the next launch."
	fs_row.add_child(fs_lbl)
	var fs_btn := CheckButton.new()
	fs_btn.button_pressed = Global.fullscreen
	fs_btn.disabled = Global.is_mobile()
	fs_btn.tooltip_text = fs_lbl.tooltip_text
	fs_btn.toggled.connect(func(on: bool) -> void: Global.set_fullscreen(on))
	fs_row.add_child(fs_btn)

	var limit_row := HBoxContainer.new()
	_settings_content.add_child(limit_row)
	var limit_lbl := Label.new()
	limit_lbl.text = "FPS Limit"
	limit_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	limit_lbl.add_theme_font_size_override("font_size", int(13 * s))
	limit_lbl.tooltip_text = "Maximum frames per second. Lower values reduce heat and battery use; Unlimited removes the cap."
	limit_row.add_child(limit_lbl)
	var limit_opt := OptionButton.new()
	limit_opt.custom_minimum_size = Vector2(int(132 * s), 0)
	limit_opt.add_theme_font_size_override("font_size", int(12 * s))
	limit_opt.tooltip_text = limit_lbl.tooltip_text
	for raw_limit in Global.FPS_LIMIT_OPTIONS:
		var limit_value := int(raw_limit)
		limit_opt.add_item("Unlimited" if limit_value == 0 else str(limit_value))
		limit_opt.set_item_id(limit_opt.item_count - 1, limit_value)
	for i in range(limit_opt.item_count):
		if limit_opt.get_item_id(i) == Global.fps_limit:
			limit_opt.select(i)
			break
	limit_opt.item_selected.connect(func(index: int) -> void:
		Global.set_fps_limit(limit_opt.get_item_id(index)))
	limit_row.add_child(limit_opt)

	# VSync is desktop-only: Android's compositor owns presentation timing.
	if not Global.is_mobile():
		var vsync_row := HBoxContainer.new()
		_settings_content.add_child(vsync_row)
		var vsync_lbl := Label.new()
		vsync_lbl.text = "VSync"
		vsync_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		vsync_lbl.add_theme_font_size_override("font_size", int(13 * s))
		vsync_lbl.tooltip_text = "Sync presentation to the monitor refresh rate. Turn off for lower input latency; the FPS Limit still applies."
		vsync_row.add_child(vsync_lbl)
		var vsync_btn := CheckButton.new()
		vsync_btn.button_pressed = Global.vsync_enabled
		vsync_btn.tooltip_text = vsync_lbl.tooltip_text
		vsync_btn.toggled.connect(func(on: bool) -> void: Global.set_vsync(on))
		vsync_row.add_child(vsync_btn)

	var fps_row := HBoxContainer.new()
	_settings_content.add_child(fps_row)
	var fps_lbl := Label.new()
	fps_lbl.text = "Show FPS"
	fps_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	fps_lbl.add_theme_font_size_override("font_size", int(13 * s))
	fps_lbl.tooltip_text = "Show a small FPS counter in the top-right corner during gameplay. Saved for the next launch."
	fps_row.add_child(fps_lbl)
	var fps_btn := CheckButton.new()
	fps_btn.button_pressed = Global.show_fps
	fps_btn.tooltip_text = fps_lbl.tooltip_text
	fps_btn.toggled.connect(func(on: bool) -> void: Global.set_show_fps(on))
	fps_row.add_child(fps_btn)

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
	pi_btn.tooltip_text = pi_lbl.tooltip_text
	pi_btn.toggled.connect(func(on: bool) -> void: Global.pause_on_inventory = on)
	pi_row.add_child(pi_btn)

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
	qb_btn.tooltip_text = qb_lbl.tooltip_text
	qb_btn.toggled.connect(func(on: bool) -> void:
		Global.quest_opaque_bg = on
		Global.quest_bg_changed.emit(on))
	qb_row.add_child(qb_btn)

func _build_settings_controls() -> void:
	var s: float = Global.ui_scale
	_section_label(_settings_content, "Movement")
	if Global.is_point_and_click_available():
		var pnc_row := HBoxContainer.new()
		_settings_content.add_child(pnc_row)
		var pnc_lbl := Label.new()
		pnc_lbl.text = "Point-and-Click Movement"
		pnc_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		pnc_lbl.add_theme_font_size_override("font_size", int(13 * s))
		pnc_lbl.tooltip_text = "Left-click / tap the world to walk there. Right-click, build mode, inventory and the keyboard/joystick controls are unchanged."
		pnc_row.add_child(pnc_lbl)
		var pnc_btn := CheckButton.new()
		pnc_btn.button_pressed = Global.point_and_click
		pnc_btn.tooltip_text = pnc_lbl.tooltip_text
		pnc_btn.toggled.connect(func(on: bool) -> void: Global.set_point_and_click(on))
		pnc_row.add_child(pnc_btn)
		var pnc_hint := Label.new()
		pnc_hint.text = "Click ground to move, a target to walk into range and act, a mob to chase and attack. WASD/joystick always cancels."
		pnc_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		pnc_hint.add_theme_font_size_override("font_size", int(10 * s))
		pnc_hint.add_theme_color_override("font_color", C_MUTED)
		_settings_content.add_child(pnc_hint)

	_section_label(_settings_content, "Keyboard")
	var hint := Label.new()
	hint.text = "Click a binding, then press a key. Esc cancels."
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.add_theme_font_size_override("font_size", int(11 * s))
	hint.add_theme_color_override("font_color", C_MUTED)
	_settings_content.add_child(hint)
	_rebind_warning = Label.new()
	_rebind_warning.text = ""
	_rebind_warning.visible = false
	_rebind_warning.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_rebind_warning.add_theme_font_size_override("font_size", int(11 * s))
	_rebind_warning.add_theme_color_override("font_color", Color(1.0, 0.45, 0.45))
	_settings_content.add_child(_rebind_warning)
	for entry in REBINDABLE:
		_add_rebind_row(_settings_content, str(entry[0]), str(entry[1]))

# ── Rebinding ──────────────────────────────────────────────────────────────

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
	if _rebind_warning != null:
		_rebind_warning.visible = false
	for a in _rebind_buttons:
		(_rebind_buttons[a] as Button).text = "Press a key…" if a == action else _key_text(a)

func _action_using_key(keycode: int, except_action: String) -> String:
	if keycode == 0:
		return ""
	for entry in REBINDABLE:
		var other: String = str(entry[0])
		if other == except_action:
			continue
		for e in InputMap.action_get_events(other):
			if e is InputEventKey and (e as InputEventKey).physical_keycode == keycode:
				return str(entry[1])
	return ""

func _apply_rebind(key_event: InputEventKey) -> void:
	var action: String = _rebind_action
	_rebind_action = ""
	if action.is_empty():
		return
	var keycode: int = key_event.physical_keycode
	var conflict: String = _action_using_key(keycode, action)
	if not conflict.is_empty():
		if _rebind_warning != null:
			_rebind_warning.text = "%s is already bound to \"%s\". Choose another key." % [
				OS.get_keycode_string(keycode), conflict]
			_rebind_warning.visible = true
		for a in _rebind_buttons:
			(_rebind_buttons[a] as Button).text = _key_text(a)
		return
	InputMap.action_erase_events(action)
	var ev := InputEventKey.new()
	ev.physical_keycode = keycode
	InputMap.action_add_event(action, ev)
	if _rebind_warning != null:
		_rebind_warning.visible = false
	for a in _rebind_buttons:
		(_rebind_buttons[a] as Button).text = _key_text(a)
	var actions: Array = []
	for entry in REBINDABLE:
		actions.append(entry[0])
	Global.save_keybinds(actions)

func _cancel_rebind() -> void:
	_rebind_action = ""
	if _rebind_warning != null:
		_rebind_warning.visible = false
	for a in _rebind_buttons:
		(_rebind_buttons[a] as Button).text = _key_text(a)

func _input(event: InputEvent) -> void:
	if _rebind_action == "":
		return
	Global.consume_ui_back_event(event)
	if event is InputEventKey and event.pressed and not event.echo:
		if (event as InputEventKey).keycode == KEY_ESCAPE:
			_cancel_rebind()
		else:
			_apply_rebind(event as InputEventKey)
		get_viewport().set_input_as_handled()

# ── Helpers ────────────────────────────────────────────────────────────────

func _section_label(parent: Node, text: String) -> void:
	var lbl := Label.new()
	lbl.text = text.to_upper()
	lbl.add_theme_font_size_override("font_size", int(11 * Global.ui_scale))
	lbl.add_theme_color_override("font_color", C_MUTED)
	parent.add_child(lbl)

func _add_slider_row(parent: Node, label_text: String, key: String,
		min_v: float, max_v: float, step_v: float, init_v: float,
		tooltip: String = "") -> void:
	var s: float = Global.ui_scale
	var row := HBoxContainer.new()
	parent.add_child(row)
	var lbl := Label.new()
	lbl.text = label_text
	lbl.custom_minimum_size = Vector2(int(140 * s), 0)
	lbl.add_theme_font_size_override("font_size", int(13 * s))
	lbl.tooltip_text = tooltip
	row.add_child(lbl)
	var slider := HSlider.new()
	slider.min_value = min_v
	slider.max_value = max_v
	slider.step = step_v
	slider.value = init_v
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.tooltip_text = tooltip
	slider.value_changed.connect(func(v: float) -> void: _on_setting_changed(key, v))
	row.add_child(slider)
	var val_lbl := Label.new()
	val_lbl.text = _fmt(init_v, key)
	val_lbl.custom_minimum_size = Vector2(int(46 * s), 0)
	val_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	val_lbl.tooltip_text = tooltip
	row.add_child(val_lbl)
	_val_labels[key] = val_lbl

func _on_setting_changed(key: String, value: float) -> void:
	match key:
		"master_volume":
			Global.master_volume = value
			AudioServer.set_bus_volume_db(AudioServer.get_bus_index("Master"),
				linear_to_db(maxf(value, 0.0001)))
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

func _on_ui_scale_preset(scale_val: float) -> void:
	Global.ui_scale = scale_val
	Global.ui_scale_set = true
	Global.ui_scale_changed.emit(scale_val)
