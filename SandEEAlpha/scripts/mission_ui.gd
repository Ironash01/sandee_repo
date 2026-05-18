extends Control

const C_PANEL        := Color(0.08, 0.10, 0.20, 0.95)
const C_BORDER       := Color(0.22, 0.32, 0.58, 1.00)
const C_TITLE        := Color(0.80, 0.90, 1.00, 1.00)
const C_MUTED        := Color(0.55, 0.65, 0.85, 1.00)
const C_DONE         := Color(0.40, 0.85, 0.50, 1.00)
const C_STAR         := Color(1.00, 0.85, 0.20, 1.00)
const C_POPUP_BG     := Color(0.06, 0.08, 0.18, 0.97)
const C_POPUP_BORDER := Color(0.70, 0.60, 0.10, 1.00)

const COMPACT_WIDTH := 230.0
const RIGHT_MARGIN  := 8.0
const TOP_OFFSET    := 44.0   # below pause button (bottom=34) + 10px gap

var _compact_panel:       PanelContainer
var _compact_stars_label: Label
var _list_panel:          PanelContainer
var _list_rows_vbox:      VBoxContainer
var _list_stars_label:    Label
var _popup_panel:         PanelContainer
var _popup_title_label:   Label
var _popup_timer:         Timer

# ── Lifecycle ─────────────────────────────────────────────────────
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_build_compact()
	_build_list_panel()
	_build_popup()
	Global.mission_updated.connect(_on_mission_updated)
	Global.mission_completed.connect(_on_mission_completed)
	call_deferred("_refit_compact")
	call_deferred("_center_panels")

# ── Compact panel (always visible, top-right) ─────────────────────
func _build_compact() -> void:
	_compact_panel = PanelContainer.new()
	_compact_panel.add_theme_stylebox_override("panel",
			_make_sb(C_PANEL, C_BORDER, 1, 6, 12, 12, 10, 12))
	add_child(_compact_panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	_compact_panel.add_child(vbox)

	var btn := Button.new()
	btn.text = "★  MISSIONS"
	btn.flat = true
	btn.add_theme_font_size_override("font_size", 16)
	btn.add_theme_color_override("font_color",         C_TITLE)
	btn.add_theme_color_override("font_hover_color",   C_STAR)
	btn.add_theme_color_override("font_pressed_color", C_STAR)
	btn.alignment = HORIZONTAL_ALIGNMENT_CENTER
	btn.pressed.connect(_open_list)
	vbox.add_child(btn)

	_compact_stars_label = Label.new()
	_compact_stars_label.add_theme_font_size_override("font_size", 14)
	_compact_stars_label.add_theme_color_override("font_color", C_STAR)
	_compact_stars_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_compact_stars_label.text = _stars_text()
	vbox.add_child(_compact_stars_label)

# ── Full mission list panel (centered modal) ──────────────────────
func _build_list_panel() -> void:
	_list_panel = PanelContainer.new()
	_list_panel.custom_minimum_size = Vector2(380, 0)
	_list_panel.add_theme_stylebox_override("panel",
			_make_sb(C_PANEL, C_BORDER, 1, 6, 24, 24, 20, 20))
	_list_panel.visible = false
	add_child(_list_panel)

	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 14)
	_list_panel.add_child(outer)

	var title := Label.new()
	title.text = "MISSIONS"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 24)
	title.add_theme_color_override("font_color", C_TITLE)
	outer.add_child(title)

	outer.add_child(_hsep())

	_list_rows_vbox = VBoxContainer.new()
	_list_rows_vbox.add_theme_constant_override("separation", 12)
	outer.add_child(_list_rows_vbox)

	outer.add_child(_hsep())

	_list_stars_label = Label.new()
	_list_stars_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_list_stars_label.add_theme_font_size_override("font_size", 17)
	_list_stars_label.add_theme_color_override("font_color", C_STAR)
	outer.add_child(_list_stars_label)

	var close_btn := Button.new()
	close_btn.text = "Close"
	close_btn.custom_minimum_size = Vector2(140, 40)
	close_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	close_btn.pressed.connect(_close_list)
	outer.add_child(close_btn)

	_rebuild_list_rows()

# ── Completion popup ──────────────────────────────────────────────
func _build_popup() -> void:
	_popup_panel = PanelContainer.new()
	_popup_panel.custom_minimum_size = Vector2(340, 0)
	_popup_panel.add_theme_stylebox_override("panel",
			_make_sb(C_POPUP_BG, C_POPUP_BORDER, 2, 8, 30, 30, 24, 24))
	_popup_panel.visible = false
	add_child(_popup_panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	_popup_panel.add_child(vbox)

	var header := Label.new()
	header.text = "✦  MISSION COMPLETE  ✦"
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	header.add_theme_font_size_override("font_size", 18)
	header.add_theme_color_override("font_color", C_STAR)
	vbox.add_child(header)

	vbox.add_child(_hsep())

	_popup_title_label = Label.new()
	_popup_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_popup_title_label.add_theme_font_size_override("font_size", 15)
	_popup_title_label.add_theme_color_override("font_color", C_TITLE)
	_popup_title_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(_popup_title_label)

	var star_lbl := Label.new()
	star_lbl.text = "★  +1 Star"
	star_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	star_lbl.add_theme_font_size_override("font_size", 18)
	star_lbl.add_theme_color_override("font_color", C_STAR)
	vbox.add_child(star_lbl)

	_popup_timer = Timer.new()
	_popup_timer.wait_time = 3.0
	_popup_timer.one_shot  = true
	_popup_timer.timeout.connect(_hide_popup)
	add_child(_popup_timer)

# ── Signal handlers ───────────────────────────────────────────────
func _open_list() -> void:
	_rebuild_list_rows()
	_list_panel.visible = true
	Global.open_ui()
	call_deferred("_center_panels")

func _close_list() -> void:
	_list_panel.visible = false
	Global.close_ui()

func _on_mission_updated() -> void:
	_compact_stars_label.text = _stars_text()
	if _list_panel.visible:
		_rebuild_list_rows()

func _on_mission_completed(id: String) -> void:
	for m in Global.missions:
		if m["id"] == id:
			_popup_title_label.text = m["title"]
			break
	_popup_panel.visible = true
	_popup_timer.start()
	call_deferred("_center_panels")

func _hide_popup() -> void:
	_popup_panel.visible = false

func _input(event: InputEvent) -> void:
	if _list_panel != null and _list_panel.visible:
		if event.is_action_pressed("escape"):
			_close_list()
			get_viewport().set_input_as_handled()

# ── Helpers ───────────────────────────────────────────────────────
func _stars_text() -> String:
	var done := 0
	for m in Global.missions:
		if m["completed"]:
			done += 1
	return "★  %d / %d  Stars" % [done, Global.missions.size()]

func _rebuild_list_rows() -> void:
	for child in _list_rows_vbox.get_children().duplicate():
		child.free()
	for m in Global.missions:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		_list_rows_vbox.add_child(row)

		var star := Label.new()
		star.text  = "★" if m["completed"] else "☆"
		star.add_theme_font_size_override("font_size", 18)
		star.add_theme_color_override("font_color",
				C_STAR if m["completed"] else C_MUTED)
		star.custom_minimum_size = Vector2(22, 0)
		row.add_child(star)

		var lbl := Label.new()
		lbl.text = m["title"]
		lbl.add_theme_font_size_override("font_size", 14)
		lbl.add_theme_color_override("font_color",
				C_DONE if m["completed"] else C_MUTED)
		lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(lbl)

	_list_stars_label.text = _stars_text()
	call_deferred("_center_panels")

func _make_sb(bg: Color, border: Color, bw: int, cr: int,
		ml: int, mr: int, mt: int, mb: int) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color     = bg
	sb.border_color = border
	sb.set_border_width_all(bw)
	sb.set_corner_radius_all(cr)
	sb.content_margin_left   = ml
	sb.content_margin_right  = mr
	sb.content_margin_top    = mt
	sb.content_margin_bottom = mb
	return sb

func _hsep() -> HSeparator:
	return HSeparator.new()

func _refit_compact() -> void:
	if _compact_panel == null:
		return
	var min_size := _compact_panel.get_combined_minimum_size()
	min_size.x = maxf(min_size.x, COMPACT_WIDTH)
	var vp_w := get_viewport_rect().size.x
	_compact_panel.position = Vector2(vp_w - min_size.x - RIGHT_MARGIN, TOP_OFFSET)
	_compact_panel.size = min_size

func _center_panels() -> void:
	var vp := get_viewport_rect().size
	if _list_panel != null:
		var ms := _list_panel.get_combined_minimum_size()
		_list_panel.position = (vp - ms) * 0.5
		_list_panel.size = ms
	if _popup_panel != null:
		var ms := _popup_panel.get_combined_minimum_size()
		_popup_panel.position = (vp - ms) * 0.5
		_popup_panel.size = ms
