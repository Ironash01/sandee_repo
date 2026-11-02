extends Control

# ── Palworld-style mission tracker (right side) ─────────────────────
# • Lua/Python dungeons: only the NEXT incomplete mission per language shows.
#   Once completed the next one replaces it; stars are retained.
# • Gameplay missions: up to 3 active at a time, any order.
#   Completed missions fade out and are replaced by the next in pool.

const C_PANEL   := Color(0.08, 0.10, 0.20, 0.92)
const C_BORDER  := Color(0.22, 0.32, 0.58, 0.80)
const C_TITLE   := Color(0.80, 0.90, 1.00, 1.00)
const C_MUTED   := Color(0.55, 0.65, 0.85, 0.80)
const C_DONE    := Color(0.40, 0.85, 0.50, 1.00)
const C_STAR    := Color(1.00, 0.85, 0.20, 1.00)
const C_ACTIVE  := Color(0.95, 0.95, 0.80, 1.00)
const C_SECTION := Color(0.65, 0.75, 0.95, 1.00)
const MISSION_LOG_SCRIPT: GDScript = preload("res://scripts/mission_log_ui.gd")

const RIGHT_MARGIN  := 12.0
const TOP_OFFSET    := 30.0
const PANEL_WIDTH   := 250.0
const FADE_DURATION := 0.4

# Which gameplay missions are currently "active" (shown to the player).
const GAMEPLAY_POOL_SIZE := 3

# The live tracker stays compact: the full Mission Log shows the rest.
const SIDE_TRACKER_LIMIT := 2

var _panel:        PanelContainer
var _rows_vbox:    VBoxContainer
var _view_all_btn: Button
var _row_data:     Array = []    # [{label, m, row_node}]
var _fade_tween:   Tween = null
var _active_pool:  Array = []    # currently shown gameplay mission ids
# True while a completed row is playing its send-off animation, so the
# mission_updated rebuild doesn't wipe the row mid-animation.
var _completing:   bool = false
# The in-flight send-off tween. It must be killed before its row is freed,
# otherwise its callbacks/property steps run on a dead node and crash
# ("Invalid assignment ... on a base object of type 'Nil'").
var _complete_tween: Tween = null

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_build_panel()
	Global.mission_updated.connect(_on_mission_updated)
	Global.mission_completed.connect(_on_mission_completed)
	Global.dungeon_cleared.connect(_on_dungeon_cleared)
	Global.ui_scale_changed.connect(_on_ui_scale)
	Global.quest_bg_changed.connect(_on_quest_bg_changed)
	call_deferred("_refit")
	call_deferred("_refill_pool")

# Rebuild when the opaque-background setting changes.
func _on_quest_bg_changed(_opaque: bool) -> void:
	if _panel != null:
		_panel.queue_free()
		_panel = null
	_row_data.clear()
	_build_panel()

# Rebuild the tracker at the new scale so the font/size change applies live.
func _on_ui_scale(_s: float) -> void:
	if _panel != null:
		_panel.queue_free()
		_panel = null
	_row_data.clear()
	_build_panel()

# ── Build the right-side panel ──────────────────────────────────────
func _build_panel() -> void:
	var s: float = Global.ui_scale
	_panel = PanelContainer.new()
	_panel.custom_minimum_size = Vector2(PANEL_WIDTH * s, 0)
	# Transparent by default (text floats over the world); the Gameplay
	# setting "Opaque Quest Background" turns on a solid panel + border.
	var opaque: bool = Global.quest_opaque_bg
	var bg:     Color = C_PANEL  if opaque else Color(0, 0, 0, 0)
	var border: Color = C_BORDER if opaque else Color(0, 0, 0, 0)
	_panel.add_theme_stylebox_override("panel",
			_make_sb(bg, border, 1 if opaque else 0, 6 if opaque else 0,
				int(10 * s), int(10 * s), int(8 * s), int(8 * s)))
	add_child(_panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", int(6 * s))
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(vbox)

	var title := Label.new()
	title.text = "MISSIONS"
	title.add_theme_font_size_override("font_size", Global.ui_font_size(13))
	title.add_theme_color_override("font_color", C_TITLE)
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(title)
	var sep := HSeparator.new()
	sep.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(sep)

	_rows_vbox = VBoxContainer.new()
	_rows_vbox.add_theme_constant_override("separation", int(8 * s))
	_rows_vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(_rows_vbox)

	# The compact list is a shortcut into the full log. The whole panel is
	# clickable too, so tapping any mission row opens the same screen.
	var open_btn := Button.new()
	open_btn.text = "VIEW ALL MISSIONS"
	open_btn.tooltip_text = "Open the full Mission Log."
	open_btn.focus_mode = Control.FOCUS_NONE
	open_btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	open_btn.add_theme_font_size_override("font_size", Global.ui_font_size(10))
	var btn_sb := _make_sb(Color(0.12, 0.18, 0.32, 0.92),
			C_BORDER if opaque else Color(0.30, 0.42, 0.68, 0.70),
			1, 4, int(8 * s), int(8 * s), int(4 * s), int(4 * s))
	var btn_hover := btn_sb.duplicate() as StyleBoxFlat
	btn_hover.bg_color = Color(0.18, 0.27, 0.48, 0.98)
	open_btn.add_theme_stylebox_override("normal", btn_sb)
	open_btn.add_theme_stylebox_override("hover", btn_hover)
	open_btn.add_theme_stylebox_override("pressed", btn_hover)
	open_btn.pressed.connect(_open_mission_log)
	vbox.add_child(open_btn)
	_view_all_btn = open_btn

	_panel.mouse_filter = Control.MOUSE_FILTER_PASS
	_panel.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	if not _panel.gui_input.is_connected(_on_panel_gui_input):
		_panel.gui_input.connect(_on_panel_gui_input)

	_rebuild_rows()

# ── Section label helper ──────────────────────────────────────────
func _add_section(text: String) -> void:
	var s: float = Global.ui_scale
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", Global.ui_font_size(11))
	lbl.add_theme_color_override("font_color", C_SECTION)
	lbl.add_theme_constant_override("line_spacing", int(1 * s))
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rows_vbox.add_child(lbl)

# ── Rebuild rows ──────────────────────────────────────────────────
func _rebuild_rows() -> void:
	# Freeing the rows below would leave any running send-off tween pointing
	# at dead nodes; stop it first.
	_cancel_completion()
	for child in _rows_vbox.get_children().duplicate():
		child.free()
	_row_data.clear()

	# --- Dungeons (main language tracks -> final boss -> extra track) ---
	# The entrances already stand in the world; these rows only track progress.
	for row in Global.current_dungeon_rows():
		_add_section(str(row.get("section", "DUNGEON")))
		_add_dungeon_row(row.get("mission", {}) as Dictionary)

	# --- Gameplay (3 active, any order) ---
	var gameplay := _active_gameplay()
	if not gameplay.is_empty():
		_add_section("MISSIONS")
		for m in gameplay:
			_add_gameplay_row(m)

	# --- Side missions (unlocked after the complete dungeon progression) ---
	if Global.side_missions_unlocked():
		var sides := Global.active_side_missions(SIDE_TRACKER_LIMIT)
		if not sides.is_empty():
			_add_section("SIDE MISSIONS")
			for m in sides:
				_add_gameplay_row(m)

	_refit()

# ── Get up to GAMEPLAY_POOL_SIZE active gameplay missions ──────────
func _active_gameplay() -> Array:
	# Missions the player has already STARTED (progress > 0) come FIRST within
	# each track. Automatica and Algorithmica are then interleaved so the three
	# visible slots always represent both automation systems instead of hiding
	# all 12 Algorithmica missions until every Automatica one is done.
	var lanes: Dictionary = {}
	for category in ["Automatica", "Algorithmica"]:
		lanes[category] = {"started": [], "unstarted": []}
	for m in Global.missions:
		if m["completed"]:
			continue
		if m.has("dungeon_index"):
			continue  # dungeon missions handled separately
		if bool(m.get("side", false)):
			continue  # side missions have their own section
		if bool(m.get("hidden", false)):
			continue  # retired legacy objectives
		var category := str(m.get("category", ""))
		if not lanes.has(category):
			lanes[category] = {"started": [], "unstarted": []}
		if int(m.get("progress", 0)) > 0:
			(lanes[category]["started"] as Array).append(m)
		else:
			(lanes[category]["unstarted"] as Array).append(m)
	var ordered: Array = []
	for category in ["Automatica", "Algorithmica"]:
		if lanes.has(category):
			var lane: Dictionary = lanes[category]
			ordered.append((lane["started"] as Array) + (lane["unstarted"] as Array))
	for category in lanes:
		if category == "Automatica" or category == "Algorithmica":
			continue
		var lane: Dictionary = lanes[category]
		ordered.append((lane["started"] as Array) + (lane["unstarted"] as Array))

	var result: Array = []
	var indexes: Array = []
	for _lane in ordered:
		indexes.append(0)
	while result.size() < GAMEPLAY_POOL_SIZE:
		var added: bool = false
		for li in range(ordered.size()):
			if result.size() >= GAMEPLAY_POOL_SIZE:
				break
			var lane: Array = ordered[li]
			var idx: int = int(indexes[li])
			if idx >= lane.size():
				continue
			result.append(lane[idx])
			indexes[li] = idx + 1
			added = true
		if not added:
			break
	return result

# ── Add a dungeon mission row ──────────────────────────────────────
# Informational only — there is no accept/Go step anymore. Each language's
# current dungeon entrance is already standing in the world (see world.gd's
# _ensure_current_dungeon_entrances). Every dungeon has THREE blue-star slots:
# each hint (except the first dungeon) or wrong code run removes one; zero stars
# still counts as a completed dungeon.
func _add_dungeon_row(m: Dictionary) -> void:
	var s: float = Global.ui_scale
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", int(8 * s))
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rows_vbox.add_child(row)

	var d_idx: int = int(m.get("dungeon_index", 0))
	var earned: int = Global.dungeon_stars_for(d_idx) if d_idx > 0 else 0
	var star_text: String = ""
	for i in range(3):
		star_text += "★" if i < earned else "☆"
	var star := Label.new()
	star.text = star_text
	star.add_theme_font_size_override("font_size", Global.ui_font_size(14))
	star.add_theme_color_override("font_color",
			C_STAR if earned > 0 else C_MUTED)
	star.custom_minimum_size = Vector2(int(48 * s), 0)
	star.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(star)

	var lbl := Label.new()
	var m_title := str(m["title"])
	if d_idx > 0:
		m_title += " — " + Global.dungeon_difficulty(d_idx)
	lbl.text = m_title
	lbl.add_theme_font_size_override("font_size", Global.ui_font_size(12))
	lbl.add_theme_color_override("font_color", C_ACTIVE)
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(lbl)

	_row_data.append({"label": lbl, "m": m, "row": row})

# ── Add a gameplay mission row ─────────────────────────────────────
func _add_gameplay_row(m: Dictionary) -> void:
	var s: float = Global.ui_scale
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", int(8 * s))
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rows_vbox.add_child(row)

	var star := Label.new()
	star.text = "★" if m["completed"] else "☆"
	star.add_theme_font_size_override("font_size", Global.ui_font_size(14))
	star.add_theme_color_override("font_color",
			C_STAR if m["completed"] else C_MUTED)
	star.custom_minimum_size = Vector2(int(24 * s), 0)
	star.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(star)

	var lbl := Label.new()
	var title: String = str(m["title"])
	var goal: int = int(m.get("goal", 0))
	if goal > 1 and not m["completed"]:
		title += "  (%d/%d)" % [int(m.get("progress", 0)), goal]
	lbl.text = title
	lbl.add_theme_font_size_override("font_size", Global.ui_font_size(12))
	lbl.add_theme_color_override("font_color",
			C_DONE if m["completed"] else C_ACTIVE)
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(lbl)

	_row_data.append({"label": lbl, "m": m, "row": row})

# ── Signal handlers ───────────────────────────────────────────────
# ── Full mission log ──────────────────────────────────────────────────
# The tracker only has room for the most relevant rows. Clicking it opens a
# separate modal CanvasLayer listing every mission, so hiding the HUD for that
# modal does not hide the log itself.
func _open_mission_log() -> void:
	if Global.any_ui_open() or Global.pause_menu_open:
		return
	var log_ui: Node = MISSION_LOG_SCRIPT.new()
	var host: Node = Global.game_node
	if host == null or not is_instance_valid(host):
		host = get_tree().current_scene
	if host == null:
		log_ui.free()
		return
	host.add_child(log_ui)

## Tutorial hook: the Automatica mission lesson highlights this button.
func tutorial_view_all_button() -> Control:
	if _view_all_btn != null and is_instance_valid(_view_all_btn):
		return _view_all_btn
	return null


func _on_panel_gui_input(event: InputEvent) -> void:
	var pressed := false
	if event is InputEventMouseButton:
		pressed = event.button_index == MOUSE_BUTTON_LEFT and event.pressed
	elif event is InputEventScreenTouch:
		pressed = event.pressed
	if pressed:
		_open_mission_log()


func _on_mission_updated() -> void:
	if _completing:
		return   # the send-off animation rebuilds the list when it finishes
	_rebuild_rows()

func _on_mission_completed(id: String) -> void:
	for entry in _row_data:
		if entry["m"]["id"] == id:
			_completing = true
			var lbl = entry["label"]
			var row = entry["row"]
			lbl.add_theme_color_override("font_color", C_DONE)
			lbl.text = "✓ " + str(lbl.text)
			# Send-off: pop + green flash, hold, then fade away. mission_updated
			# is suppressed while _completing, so this row survives the rebuild.
			row.pivot_offset = row.size * 0.5
			var tw := create_tween()
			_complete_tween = tw
			tw.tween_property(row, "scale", Vector2(1.12, 1.12), 0.14) \
				.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			tw.tween_callback(func() -> void:
				if is_instance_valid(row):
					row.modulate = Color(0.6, 1.35, 0.6, 1.0))
			tw.tween_property(row, "scale", Vector2.ONE, 0.14)
			tw.tween_interval(0.7)
			tw.tween_property(row, "modulate:a", 0.0, FADE_DURATION)
			tw.tween_callback(_finish_completion)
			return

func _finish_completion() -> void:
	# The tween has ended on its own; drop the handle before rebuilding so
	# _cancel_completion() doesn't try to kill it again.
	_complete_tween = null
	_completing = false
	_rebuild_rows()

# Stop a running send-off tween and reset the completing flag.
func _cancel_completion() -> void:
	if _complete_tween != null and _complete_tween.is_valid():
		_complete_tween.kill()
	_complete_tween = null
	_completing = false

func _on_dungeon_cleared(_index: int) -> void:
	if _completing:
		return   # let the send-off finish; its rebuild will pick up the change
	_rebuild_rows()

# ── Refill gameplay pool when missions complete ────────────────────
func _refill_pool() -> void:
	_active_pool.clear()
	for m in Global.missions:
		if m["completed"]:
			continue
		if m.has("dungeon_index"):
			continue
		if bool(m.get("side", false)):
			continue
		if bool(m.get("hidden", false)):
			continue
		_active_pool.append(m["id"])
		if _active_pool.size() >= GAMEPLAY_POOL_SIZE:
			break

# ── Helpers ───────────────────────────────────────────────────────
func _make_sb(bg: Color, border: Color, bw: int, cr: int,
		ml: int, mr: int, mt: int, mb: int) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(bw)
	sb.set_corner_radius_all(cr)
	sb.content_margin_left = ml
	sb.content_margin_right = mr
	sb.content_margin_top = mt
	sb.content_margin_bottom = mb
	return sb

func _refit() -> void:
	if _panel == null:
		return
	var s: float = Global.ui_scale
	var vp_w := get_viewport_rect().size.x
	var right := Global.ui_safe_insets.z + RIGHT_MARGIN * s
	var top := Global.ui_safe_insets.y + TOP_OFFSET * s
	# Stay clear of the top-right pause button. A fixed offset stopped being
	# enough once the responsive UI scale began growing the button's height;
	# start one small gap below its real bottom edge instead.
	if Global.ui_pause_bottom > 0.0:
		top = maxf(top, Global.ui_pause_bottom + 4.0 * s)
	_panel.position = Vector2(maxf(0.0, vp_w - PANEL_WIDTH * s - right), top)
	_panel.size = _panel.get_combined_minimum_size()

func _input(event: InputEvent) -> void:
	if _panel != null and _panel.visible:
		if event.is_action_pressed("escape"):
			pass  # panel is always visible, no close needed
