extends Control

const C_BG      := Color(0.04, 0.06, 0.12, 1.00)
const C_PANEL   := Color(0.08, 0.10, 0.20, 0.97)
const C_BORDER  := Color(0.22, 0.32, 0.58, 1.00)
const C_TITLE   := Color(0.80, 0.90, 1.00, 1.00)
const C_MUTED   := Color(0.55, 0.65, 0.85, 1.00)
const C_OVERLAY := Color(0.00, 0.00, 0.00, 0.60)
const C_DIVIDER := Color(0.20, 0.28, 0.50, 1.00)
const C_BTN_H   := Color(0.12, 0.18, 0.36, 1.00)

var _slot_overlay:     Control = null
var _settings_overlay: Control = null

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_build_background()
	_build_main_ui()
	_build_slot_overlay()
	_build_settings_overlay()

# ── Background ────────────────────────────────────────────────────
func _build_background() -> void:
	var bg := ColorRect.new()
	bg.color = C_BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

# ── Main menu ─────────────────────────────────────────────────────
func _build_main_ui() -> void:
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var vbox := VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 10)
	vbox.custom_minimum_size = Vector2(320, 0)
	center.add_child(vbox)

	var title := Label.new()
	title.text = "SandEE"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 72)
	title.add_theme_color_override("font_color", C_TITLE)
	vbox.add_child(title)

	var sub := Label.new()
	sub.text = "Alpha"
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.add_theme_font_size_override("font_size", 16)
	sub.add_theme_color_override("font_color", C_MUTED)
	vbox.add_child(sub)

	_add_spacer(vbox, 16)
	var div := ColorRect.new()
	div.color = C_DIVIDER
	div.custom_minimum_size = Vector2(0, 1)
	vbox.add_child(div)
	_add_spacer(vbox, 16)

	var continue_btn := _make_menu_btn("Continue", _on_continue)
	if Global.get_last_slot() == -1:
		continue_btn.disabled = true
	vbox.add_child(continue_btn)

	_add_menu_btn(vbox, "Start Game", _on_start_game)
	_add_menu_btn(vbox, "Settings",   _on_settings)
	_add_spacer(vbox, 8)

	var quit_btn := _make_menu_btn("Quit", _on_quit)
	var qs := StyleBoxFlat.new()
	qs.bg_color = Color(0.18, 0.08, 0.08, 0.97)
	qs.border_color = Color(0.55, 0.22, 0.22, 1.0)
	qs.set_border_width_all(1); qs.set_corner_radius_all(4)
	qs.content_margin_top = 8; qs.content_margin_bottom = 8
	var qsh := StyleBoxFlat.new()
	qsh.bg_color = Color(0.28, 0.12, 0.12, 0.97)
	qsh.border_color = Color(1.0, 0.45, 0.45, 1.0)
	qsh.set_border_width_all(1); qsh.set_corner_radius_all(4)
	qsh.content_margin_top = 8; qsh.content_margin_bottom = 8
	quit_btn.add_theme_stylebox_override("normal",  qs)
	quit_btn.add_theme_stylebox_override("hover",   qsh)
	quit_btn.add_theme_stylebox_override("pressed", qs)
	quit_btn.add_theme_color_override("font_color",       Color(1.0, 0.55, 0.55, 1.0))
	quit_btn.add_theme_color_override("font_hover_color", Color(1.0, 0.40, 0.40, 1.0))
	vbox.add_child(quit_btn)

# ── Slot selection overlay ────────────────────────────────────────
func _build_slot_overlay() -> void:
	_slot_overlay = _make_overlay()
	add_child(_slot_overlay)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_slot_overlay.add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(380, 0)
	_style_panel(panel)
	center.add_child(panel)

	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 24)
	panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	margin.add_child(vbox)

	var title := Label.new()
	title.text = "Select Save Slot"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 20)
	title.add_theme_color_override("font_color", C_TITLE)
	vbox.add_child(title)

	var div := ColorRect.new()
	div.color = C_DIVIDER
	div.custom_minimum_size = Vector2(0, 1)
	vbox.add_child(div)

	for i in range(1, 4):
		vbox.add_child(_make_slot_row(i))

	_add_spacer(vbox, 4)
	_add_menu_btn(vbox, "< Back", func() -> void: _slot_overlay.visible = false)

# ── Settings overlay ──────────────────────────────────────────────
func _build_settings_overlay() -> void:
	_settings_overlay = _make_overlay()
	add_child(_settings_overlay)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_settings_overlay.add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(380, 0)
	_style_panel(panel)
	center.add_child(panel)

	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 24)
	panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 14)
	margin.add_child(vbox)

	var title := Label.new()
	title.text = "Settings"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 20)
	title.add_theme_color_override("font_color", C_TITLE)
	vbox.add_child(title)

	var div := ColorRect.new()
	div.color = C_DIVIDER
	div.custom_minimum_size = Vector2(0, 1)
	vbox.add_child(div)

	_add_spacer(vbox, 4)

	_add_slider_row(vbox, "Music Volume", Global.music_volume,
		func(v: float) -> void:
			Global.music_volume = v
			var idx := AudioServer.get_bus_index("Music")
			if idx != -1:
				AudioServer.set_bus_volume_db(idx, linear_to_db(maxf(v, 0.0001))))

	_add_slider_row(vbox, "Sound Volume", Global.sfx_volume,
		func(v: float) -> void:
			Global.sfx_volume = v
			var idx := AudioServer.get_bus_index("SFX")
			if idx != -1:
				AudioServer.set_bus_volume_db(idx, linear_to_db(maxf(v, 0.0001))))

	_add_spacer(vbox, 8)
	_add_menu_btn(vbox, "< Back", func() -> void: _settings_overlay.visible = false)

# ── Builder helpers ───────────────────────────────────────────────
func _make_overlay() -> Control:
	var ctrl := Control.new()
	ctrl.set_anchors_preset(Control.PRESET_FULL_RECT)
	ctrl.visible = false
	var dim := ColorRect.new()
	dim.color = C_OVERLAY
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	ctrl.add_child(dim)
	return ctrl

func _style_panel(panel: PanelContainer) -> void:
	var ps := StyleBoxFlat.new()
	ps.bg_color     = C_PANEL
	ps.border_color = C_BORDER
	ps.set_border_width_all(1)
	ps.set_corner_radius_all(6)
	panel.add_theme_stylebox_override("panel", ps)

func _make_menu_btn(label: String, callback: Callable) -> Button:
	var btn := Button.new()
	btn.text = label
	btn.custom_minimum_size = Vector2(280, 44)
	btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	btn.add_theme_font_size_override("font_size", 15)
	btn.add_theme_color_override("font_color",         C_TITLE)
	btn.add_theme_color_override("font_hover_color",   C_TITLE)
	btn.add_theme_color_override("font_pressed_color", C_MUTED)
	var normal := StyleBoxFlat.new()
	normal.bg_color = C_PANEL; normal.border_color = C_BORDER
	normal.set_border_width_all(1); normal.set_corner_radius_all(4)
	normal.content_margin_top = 8; normal.content_margin_bottom = 8
	var hover := StyleBoxFlat.new()
	hover.bg_color = C_BTN_H; hover.border_color = C_TITLE
	hover.set_border_width_all(1); hover.set_corner_radius_all(4)
	hover.content_margin_top = 8; hover.content_margin_bottom = 8
	btn.add_theme_stylebox_override("normal",  normal)
	btn.add_theme_stylebox_override("hover",   hover)
	btn.add_theme_stylebox_override("pressed", normal)
	btn.pressed.connect(callback)
	return btn

func _add_menu_btn(parent: Node, label: String, callback: Callable) -> void:
	parent.add_child(_make_menu_btn(label, callback))

func _add_spacer(parent: Node, height: int) -> void:
	var s := Control.new()
	s.custom_minimum_size = Vector2(0, height)
	parent.add_child(s)

func _make_slot_row(slot_idx: int) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	# ── Main slot button ──────────────────────────────────────────
	var btn := Button.new()
	btn.text = ""
	btn.custom_minimum_size = Vector2(0, 70)
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var normal := StyleBoxFlat.new()
	normal.bg_color = C_PANEL; normal.border_color = C_BORDER
	normal.set_border_width_all(1); normal.set_corner_radius_all(4)
	var hover := StyleBoxFlat.new()
	hover.bg_color = C_BTN_H; hover.border_color = C_TITLE
	hover.set_border_width_all(1); hover.set_corner_radius_all(4)
	btn.add_theme_stylebox_override("normal",  normal)
	btn.add_theme_stylebox_override("hover",   hover)
	btn.add_theme_stylebox_override("pressed", normal)
	btn.pressed.connect(func() -> void: _on_slot_selected(slot_idx))

	var content := VBoxContainer.new()
	content.set_anchors_preset(Control.PRESET_FULL_RECT)
	content.alignment = BoxContainer.ALIGNMENT_CENTER
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn.add_child(content)

	var info := Global.get_save_info(slot_idx)
	if info.is_empty():
		var lbl := Label.new()
		lbl.text = "New Game"
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.add_theme_font_size_override("font_size", 15)
		lbl.add_theme_color_override("font_color", C_MUTED)
		lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		content.add_child(lbl)
	else:
		var name_lbl := Label.new()
		name_lbl.text = "Slot %d" % slot_idx
		name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		name_lbl.add_theme_font_size_override("font_size", 15)
		name_lbl.add_theme_color_override("font_color", C_TITLE)
		name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		content.add_child(name_lbl)

		var ts: int = int(float(info.get("timestamp", 0)))
		var dt: Dictionary = Time.get_datetime_dict_from_unix_time(ts)
		var date_str := "%04d-%02d-%02d  %02d:%02d" % [
			int(dt["year"]), int(dt["month"]), int(dt["day"]),
			int(dt["hour"]), int(dt["minute"])]
		var date_lbl := Label.new()
		date_lbl.text = date_str
		date_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		date_lbl.add_theme_font_size_override("font_size", 11)
		date_lbl.add_theme_color_override("font_color", C_MUTED)
		date_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		content.add_child(date_lbl)

	row.add_child(btn)

	# ── Delete button (only for existing saves) ───────────────────
	if not info.is_empty():
		var del_btn := Button.new()
		del_btn.text = "X"
		del_btn.custom_minimum_size = Vector2(44, 70)
		del_btn.size_flags_horizontal = Control.SIZE_SHRINK_END
		del_btn.add_theme_font_size_override("font_size", 13)
		var ds := StyleBoxFlat.new()
		ds.bg_color     = Color(0.18, 0.06, 0.06, 0.97)
		ds.border_color = Color(0.55, 0.22, 0.22, 1.0)
		ds.set_border_width_all(1); ds.set_corner_radius_all(4)
		var dsh := StyleBoxFlat.new()
		dsh.bg_color     = Color(0.38, 0.10, 0.10, 0.97)
		dsh.border_color = Color(1.0, 0.40, 0.40, 1.0)
		dsh.set_border_width_all(1); dsh.set_corner_radius_all(4)
		del_btn.add_theme_stylebox_override("normal",  ds)
		del_btn.add_theme_stylebox_override("hover",   dsh)
		del_btn.add_theme_stylebox_override("pressed", ds)
		del_btn.add_theme_color_override("font_color",       Color(1.0, 0.55, 0.55, 1.0))
		del_btn.add_theme_color_override("font_hover_color", Color(1.0, 0.35, 0.35, 1.0))
		del_btn.pressed.connect(func() -> void: call_deferred("_delete_save", slot_idx))
		row.add_child(del_btn)

	return row

func _add_slider_row(parent: Node, label_text: String, init_v: float, callback: Callable) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	parent.add_child(row)

	var lbl := Label.new()
	lbl.text = label_text
	lbl.custom_minimum_size = Vector2(140, 0)
	lbl.add_theme_font_size_override("font_size", 13)
	lbl.add_theme_color_override("font_color", C_TITLE)
	row.add_child(lbl)

	var val_lbl := Label.new()
	val_lbl.text = "%d%%" % int(init_v * 100.0)
	val_lbl.custom_minimum_size = Vector2(44, 0)
	val_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	val_lbl.add_theme_font_size_override("font_size", 13)
	val_lbl.add_theme_color_override("font_color", C_MUTED)

	var slider := HSlider.new()
	slider.min_value = 0.0
	slider.max_value = 1.0
	slider.step      = 0.05
	slider.value     = init_v
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.value_changed.connect(func(v: float) -> void:
		val_lbl.text = "%d%%" % int(v * 100.0)
		callback.call(v))
	row.add_child(slider)
	row.add_child(val_lbl)

# ── Actions ───────────────────────────────────────────────────────
func _on_continue() -> void:
	var slot := Global.get_last_slot()
	if slot == -1:
		return
	Global.load_game(slot)
	get_tree().change_scene_to_file("res://scenes/game_instance.tscn")

func _on_start_game() -> void:
	_slot_overlay.visible = true

func _on_settings() -> void:
	_settings_overlay.visible = true

func _on_slot_selected(slot: int) -> void:
	if Global.has_save(slot):
		Global.load_game(slot)
	else:
		Global.active_save_slot    = slot
		Global.Hotbar.fill(null)
		Global.Inventory.fill(null)
		Global.has_pending_pos     = false
		Global.pending_world_data.clear()
		Global.reset_missions()
	get_tree().change_scene_to_file("res://scenes/game_instance.tscn")

func _delete_save(slot: int) -> void:
	var dir := DirAccess.open("user://")
	if dir != null:
		dir.remove("save_slot_%d.json" % slot)
	# Rebuild the slot overlay to reflect the deletion
	_slot_overlay.queue_free()
	_slot_overlay = null
	_build_slot_overlay()
	add_child(_slot_overlay)
	_slot_overlay.visible = true

func _on_quit() -> void:
	get_tree().quit()
