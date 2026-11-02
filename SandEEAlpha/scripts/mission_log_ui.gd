extends CanvasLayer
class_name MissionLogUI

# ── Full Mission Log ────────────────────────────────────────────────
# Opened from the compact mission tracker. Every mission gets an
# encyclopedia-style expandable section with its task, description, purpose,
# lesson and rewards. The live tracker stays compact (two side missions max).

const C_PANEL   := Color(0.08, 0.10, 0.20, 0.98)
const C_BORDER  := Color(0.30, 0.44, 0.72, 1.00)
const C_TITLE   := Color(0.80, 0.90, 1.00, 1.00)
const C_MUTED   := Color(0.55, 0.65, 0.85, 1.00)
const C_SECTION := Color(0.65, 0.75, 0.95, 1.00)
const C_OVERLAY := Color(0.00, 0.00, 0.00, 0.62)

var _ui_open: bool = false
var _root: Control = null
var _body: VBoxContainer = null

func _ready() -> void:
	layer = 60
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group("MissionLogUI")
	if not Global.ui_scale_changed.is_connected(_on_ui_scale):
		Global.ui_scale_changed.connect(_on_ui_scale)
	_build_ui()
	_open_ui()


func _on_ui_scale(_s: float) -> void:
	if _ui_open:
		_build_ui()


func _open_ui() -> void:
	if _ui_open:
		return
	if Global.any_ui_open() or Global.pause_menu_open:
		queue_free()
		return
	_ui_open = true
	Global.mission_log_open_count += 1
	Global.open_ui()
	Global.register_ui_back(self, Callable(self, "close"))
	Global.modal_hud_changed.emit(true)


## Public because it is also the registered Android Back / Escape action.
func close() -> void:
	if not _ui_open:
		queue_free()
		return
	_ui_open = false
	Global.unregister_ui_back(self)
	Global.close_ui()
	Global.modal_hud_changed.emit(false)
	queue_free()


func _exit_tree() -> void:
	if not _ui_open:
		return
	_ui_open = false
	Global.unregister_ui_back(self)
	Global.close_ui()
	Global.modal_hud_changed.emit(false)


func _build_ui() -> void:
	if _root != null and is_instance_valid(_root):
		remove_child(_root)
		_root.queue_free()
	var s: float = Global.ui_scale
	_root = Control.new()
	_root.name = "MissionLogRoot"
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_root)

	var dim := ColorRect.new()
	dim.color = C_OVERLAY
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	Global.apply_safe_area(center)
	_root.add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Global.ui_fit_min_size(Vector2(980, 620), 12.0)
	var ps := StyleBoxFlat.new()
	ps.bg_color = C_PANEL
	ps.border_color = C_BORDER
	ps.set_border_width_all(int(2 * s))
	ps.set_corner_radius_all(int(6 * s))
	ps.content_margin_left = int(18 * s)
	ps.content_margin_right = int(18 * s)
	ps.content_margin_top = int(14 * s)
	ps.content_margin_bottom = int(16 * s)
	panel.add_theme_stylebox_override("panel", ps)
	center.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", int(7 * s))
	panel.add_child(vbox)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", int(10 * s))
	vbox.add_child(header)
	var title := Label.new()
	title.text = "MISSION LOG"
	title.add_theme_font_size_override("font_size", Global.ui_font_size(18))
	title.add_theme_color_override("font_color", C_TITLE)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	var close_btn := Global.make_close_button()
	close_btn.tooltip_text = "Close the mission log."
	close_btn.pressed.connect(close)
	header.add_child(close_btn)

	var summary := Label.new()
	summary.text = "Active missions first. Completed missions move to the bottom. Side missions unlock after the dungeon story."
	summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	summary.add_theme_font_size_override("font_size", Global.ui_font_size(10))
	summary.add_theme_color_override("font_color", C_MUTED)
	vbox.add_child(summary)

	var div := ColorRect.new()
	div.color = Color(0.42, 0.28, 0.55, 1.0)
	div.custom_minimum_size = Vector2(0, maxi(1, int(1 * s)))
	vbox.add_child(div)

	var body_scroll := ScrollContainer.new()
	body_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	body_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	vbox.add_child(body_scroll)
	_body = VBoxContainer.new()
	_body.add_theme_constant_override("separation", int(7 * s))
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body_scroll.add_child(_body)

	_populate(s)


func _populate(s: float) -> void:
	if _body == null:
		return
	for child in _body.get_children():
		_body.remove_child(child)
		child.queue_free()
	var main: Array = []
	var side: Array = []
	var dungeons: Array = []
	var completed: Array = []
	for m_value in Global.missions:
		var m := m_value as Dictionary
		if bool(m.get("hidden", false)):
			continue
		# Finished missions leave their category list and collect at the bottom.
		# Dungeon rows also count as completed when the clear flag is set, which
		# keeps old saves and manually-cleared content consistent.
		if _is_completed(m):
			completed.append(m)
			continue
		if m.has("dungeon_index"):
			dungeons.append(m)
		elif bool(m.get("side", false)):
			side.append(m)
		else:
			main.append(m)
	dungeons.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a.get("dungeon_index", 0)) < int(b.get("dungeon_index", 0)))
	_add_group("MAIN MISSIONS", main, s)
	_add_group("DUNGEONS", dungeons, s)
	_add_group("SIDE MISSIONS", side, s)
	if not completed.is_empty():
		_add_group("COMPLETED MISSIONS", completed, s)


func _is_completed(m: Dictionary) -> bool:
	if bool(m.get("completed", false)):
		return true
	if m.has("dungeon_index"):
		return Global.is_dungeon_cleared(int(m.get("dungeon_index", 0)))
	return false


func _add_group(title: String, missions: Array, s: float) -> void:
	var lbl := Label.new()
	lbl.text = "%s  (%d)" % [title, missions.size()]
	lbl.add_theme_font_size_override("font_size", Global.ui_font_size(12))
	lbl.add_theme_color_override("font_color", C_SECTION)
	_body.add_child(lbl)
	if missions.is_empty():
		var none := Label.new()
		none.text = "None available."
		none.add_theme_font_size_override("font_size", Global.ui_font_size(10))
		none.add_theme_color_override("font_color", C_MUTED)
		_body.add_child(none)
		return
	for m_value in missions:
		_add_mission_section(m_value as Dictionary, s)


func _add_mission_section(m: Dictionary, s: float) -> void:
	var details := MissionDetails.details_for(m)
	var title := str(m.get("title", "Mission"))
	var status := _status_text(m)
	var note := _category_line(m) + status
	var sec := EncyclopediaSection.new()
	sec.setup({"id": str(m.get("id", title)), "title": title, "note": note}, s)
	sec.add_entry({"sig": "TASK", "desc": str(details.get("task", ""))}, s)
	sec.add_entry({"sig": "DESCRIPTION", "desc": str(details.get("description", ""))}, s)
	sec.add_entry({"sig": "WHY DO IT", "desc": str(details.get("why", ""))}, s)
	sec.add_entry({"sig": "WHAT YOU'LL LEARN", "desc": str(details.get("learn", ""))}, s)
	sec.add_entry({"sig": "REWARDS", "desc": str(details.get("rewards", ""))}, s)
	sec.set_expanded(false, false)
	_body.add_child(sec)


func _category_line(m: Dictionary) -> String:
	if m.has("dungeon_index"):
		var idx := int(m.get("dungeon_index", 0))
		var language := Global.dungeon_language(idx).capitalize()
		return "Dungeon • %s • " % language
	if bool(m.get("side", false)):
		return "Side mission • "
	return "%s • " % str(m.get("category", "Mission"))


func _status_text(m: Dictionary) -> String:
	if m.has("dungeon_index"):
		var idx := int(m.get("dungeon_index", 0))
		if Global.is_dungeon_cleared(idx):
			return "Completed • %d/3 blue stars" % Global.dungeon_stars_for(idx)
		return "Not cleared"
	if bool(m.get("completed", false)):
		return "Completed • 1 yellow quest star"
	if bool(m.get("side", false)) and not Global.side_missions_unlocked():
		return "Locked • clear all dungeons and the Hitman finale"
	var goal := int(m.get("goal", 0))
	var progress := int(m.get("progress", 0))
	if goal > 1 and progress > 0:
		return "In progress • %d/%d" % [progress, goal]
	return "Not started"
