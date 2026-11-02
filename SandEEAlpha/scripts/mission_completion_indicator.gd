extends CanvasLayer

# ── Global mission-complete notification ─────────────────────────────
# Persistent CanvasLayer above every scene/modal, mirroring AutosaveUI's
# top-centre pill. It listens to Global.mission_completed so dungeon (Lua/
# Python), Automatica, Algorithmica and side-mission completions all use one
# consistent notification. Multiple completions in the same frame are queued
# instead of overwriting one another.

const DISPLAY_SEC: float = 2.6
const AUTOSAVE_STACK_GAP: float = 50.0

const C_PANEL: Color = Color(0.06, 0.09, 0.17, 0.96)
const C_BORDER: Color = Color(0.34, 0.72, 0.44, 1.0)
const C_TITLE: Color = Color(0.80, 0.90, 1.00, 1.0)
const C_MUTED: Color = Color(0.55, 0.65, 0.85, 1.0)
const C_GOLD: Color = Color(1.00, 0.85, 0.30, 1.0)

var _root: Control = null
var _band: CenterContainer = null
var _panel: PanelContainer = null
var _title: Label = null
var _sub: Label = null
var _star: Label = null
var _timer: Timer = null
var _queue: Array = []
var _current: Dictionary = {}


func _ready() -> void:
	layer = 140  # same persistent band as AutosaveUI
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	_timer = Timer.new()
	_timer.one_shot = true
	_timer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_timer)
	_timer.timeout.connect(_on_timeout)
	_build()
	if not Global.mission_completed.is_connected(_on_mission_completed):
		Global.mission_completed.connect(_on_mission_completed)
	if not Global.ui_scale_changed.is_connected(_on_ui_scale):
		Global.ui_scale_changed.connect(_on_ui_scale)


func _build() -> void:
	if _root != null and is_instance_valid(_root):
		remove_child(_root)
		_root.queue_free()
	var s: float = Global.ui_scale
	_root = Control.new()
	_root.name = "MissionToastRoot"
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_root)

	# Full-width top band, so the pill stays horizontally centred while the
	# safe-area top inset keeps it below notches/system bars.
	_band = CenterContainer.new()
	_band.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_band.offset_left = 0.0
	_band.offset_right = 0.0
	_apply_band_offset(s)
	_band.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_band)

	_panel = PanelContainer.new()
	# A notification must never steal clicks/taps from the world or a panel
	# underneath it.
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = C_PANEL
	style.border_color = C_BORDER
	style.set_border_width_all(maxi(1, int(1.5 * s)))
	style.set_corner_radius_all(int(18 * s))
	style.content_margin_left = int(12 * s)
	style.content_margin_right = int(14 * s)
	style.content_margin_top = int(6 * s)
	style.content_margin_bottom = int(6 * s)
	_panel.add_theme_stylebox_override("panel", style)
	_band.add_child(_panel)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", int(8 * s))
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(row)

	_star = Label.new()
	_star.text = "★"
	_star.add_theme_font_size_override("font_size", Global.ui_font_size(15))
	_star.add_theme_color_override("font_color", C_GOLD)
	_star.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_star.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(_star)

	var text_col := VBoxContainer.new()
	text_col.add_theme_constant_override("separation", 0)
	text_col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(text_col)

	_title = Label.new()
	_title.add_theme_font_size_override("font_size", Global.ui_font_size(11))
	_title.add_theme_color_override("font_color", C_TITLE)
	_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	text_col.add_child(_title)

	_sub = Label.new()
	_sub.add_theme_font_size_override("font_size", Global.ui_font_size(9))
	_sub.add_theme_color_override("font_color", C_MUTED)
	_sub.mouse_filter = Control.MOUSE_FILTER_IGNORE
	text_col.add_child(_sub)

	_refresh_labels()


func _process(_delta: float) -> void:
	if visible and _band != null and is_instance_valid(_band):
		_apply_band_offset(Global.ui_scale)


# AutosaveUI and this pill share the same top-centre slot. If a save is on
# screen, stack the mission toast directly below it instead of overlapping.
func _apply_band_offset(s: float) -> void:
	if _band == null:
		return
	var top: float = Global.ui_safe_insets.y + 8.0 * s
	var autosave := get_node_or_null("/root/AutosaveUI")
	if autosave is CanvasItem and (autosave as CanvasItem).visible:
		top += AUTOSAVE_STACK_GAP * s
	_band.offset_top = top
	_band.offset_bottom = top + 42.0 * s


func _on_mission_completed(id: String) -> void:
	var mission := _mission_data(id)
	if mission.is_empty() or bool(mission.get("hidden", false)):
		return
	var entry := {
		"id": id,
		"title": str(mission.get("title", id)),
		"kind": _mission_kind(mission),
	}
	if not _current.is_empty() and str(_current.get("id", "")) == id:
		return
	for queued in _queue:
		if str((queued as Dictionary).get("id", "")) == id:
			return
	if _current.is_empty():
		_show_entry(entry)
	else:
		_queue.append(entry)


func _show_entry(entry: Dictionary) -> void:
	_current = entry
	_refresh_labels()
	visible = true
	if _timer != null and is_instance_valid(_timer):
		_timer.start(DISPLAY_SEC)


func _refresh_labels() -> void:
	var has_entry := not _current.is_empty()
	if _title != null and is_instance_valid(_title):
		_title.text = str(_current.get("title", "")) if has_entry else ""
	if _sub != null and is_instance_valid(_sub):
		var kind := str(_current.get("kind", "MISSION"))
		_sub.text = ("%s  •  MISSION COMPLETE" % kind) if has_entry else ""


func _on_timeout() -> void:
	if not _queue.is_empty():
		_show_entry(_queue.pop_front() as Dictionary)
		return
	_current = {}
	visible = false


func _mission_data(id: String) -> Dictionary:
	for value in Global.missions:
		var mission := value as Dictionary
		if str(mission.get("id", "")) == id:
			return mission
	return {}


func _mission_kind(mission: Dictionary) -> String:
	if bool(mission.get("side", false)):
		return "SIDE MISSION"
	if mission.has("dungeon_index"):
		var lang := Global.dungeon_language(int(mission["dungeon_index"]))
		if lang == "lua":
			return "LUA DUNGEON"
		if lang == "python":
			return "PYTHON DUNGEON"
		return "DUNGEON MISSION"
	var category := str(mission.get("category", "")).strip_edges()
	return category.to_upper() if not category.is_empty() else "MISSION"


func _on_ui_scale(_s: float) -> void:
	if _panel != null and is_instance_valid(_panel):
		_build()


# ── Test / call-site helpers ──────────────────────────────────────
func indicator_text() -> String:
	return _title.text if _title != null and is_instance_valid(_title) else ""


func indicator_subtext() -> String:
	return _sub.text if _sub != null and is_instance_valid(_sub) else ""


func queue_size() -> int:
	return _queue.size()


# Advance immediately instead of waiting for the display timer. Used by tests
# and by any future "dismiss" control.
func finish_current() -> void:
	if _timer != null and is_instance_valid(_timer):
		_timer.stop()
	_on_timeout()


func reset() -> void:
	_queue.clear()
	_current = {}
	if _timer != null and is_instance_valid(_timer):
		_timer.stop()
	visible = false
