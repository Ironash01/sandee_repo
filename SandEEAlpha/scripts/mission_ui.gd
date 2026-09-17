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

const RIGHT_MARGIN  := 12.0
const TOP_OFFSET    := 44.0
const PANEL_WIDTH   := 250.0
const FADE_DURATION := 0.4

# Which gameplay missions are currently "active" (shown to the player).
const GAMEPLAY_POOL_SIZE := 3

var _panel:        PanelContainer
var _stars_label:  Label
var _rows_vbox:    VBoxContainer
var _row_data:     Array = []    # [{label, m, row_node}]
var _fade_tween:   Tween = null
var _active_pool:  Array = []    # currently shown gameplay mission ids

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_build_panel()
	Global.mission_updated.connect(_on_mission_updated)
	Global.mission_completed.connect(_on_mission_completed)
	Global.dungeon_cleared.connect(_on_dungeon_cleared)
	call_deferred("_refit")
	call_deferred("_refill_pool")

# ── Build the right-side panel ──────────────────────────────────────
func _build_panel() -> void:
	_panel = PanelContainer.new()
	_panel.custom_minimum_size = Vector2(PANEL_WIDTH, 0)
	# No panel background / border — the tracker's text floats over the world.
	_panel.add_theme_stylebox_override("panel",
			_make_sb(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 0, 0, 10, 10, 8, 8))
	add_child(_panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	_panel.add_child(vbox)

	_stars_label = Label.new()
	_stars_label.add_theme_font_size_override("font_size", 14)
	_stars_label.add_theme_color_override("font_color", C_STAR)
	_stars_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_stars_label.text = _stars_text()
	vbox.add_child(_stars_label)

	vbox.add_child(HSeparator.new())

	_rows_vbox = VBoxContainer.new()
	_rows_vbox.add_theme_constant_override("separation", 8)
	vbox.add_child(_rows_vbox)

	_rebuild_rows()

# ── Section label helper ──────────────────────────────────────────
func _add_section(text: String) -> void:
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", 11)
	lbl.add_theme_color_override("font_color", C_SECTION)
	lbl.add_theme_constant_override("line_spacing", 1)
	_rows_vbox.add_child(lbl)

# ── Rebuild rows ──────────────────────────────────────────────────
func _rebuild_rows() -> void:
	for child in _rows_vbox.get_children().duplicate():
		child.free()
	_row_data.clear()

	# --- Lua (sequential: show next incomplete) ---
	var lua_next := _next_dungeon_mission("lua")
	if lua_next != null:
		_add_section("LUA")
		_add_dungeon_row(lua_next)

	# --- Python (sequential: show next incomplete) ---
	var py_next := _next_dungeon_mission("python")
	if py_next != null:
		_add_section("PYTHON")
		_add_dungeon_row(py_next)

	# --- Gameplay (3 active, any order) ---
	var gameplay := _active_gameplay()
	if not gameplay.is_empty():
		_add_section("MISSIONS")
		for m in gameplay:
			_add_gameplay_row(m)

	_stars_label.text = _stars_text()
	_refit()

# ── Find the next incomplete dungeon mission for a language ────────
# Missions are sequential: only the lowest-index incomplete mission
# is shown. Once completed, the next one appears.
func _next_dungeon_mission(lang: String) -> Dictionary:
	for m in Global.missions:
		if m["completed"]:
			continue
		var d_idx: int = int(m.get("dungeon_index", 0))
		if d_idx <= 0:
			continue
		if _mission_language(m) != lang:
			continue
		if Global.is_dungeon_mission_ready(d_idx):
			return m
		# Not ready yet — skip but don't show future locked ones
		break
	return {}

# ── Get up to GAMEPLAY_POOL_SIZE active gameplay missions ──────────
func _active_gameplay() -> Array:
	var result: Array = []
	for m in Global.missions:
		if m["completed"]:
			continue
		if m.has("dungeon_index"):
			continue  # dungeon missions handled separately
		if result.size() >= GAMEPLAY_POOL_SIZE:
			break
		result.append(m)
	return result

# ── Add a dungeon mission row ──────────────────────────────────────
func _add_dungeon_row(m: Dictionary) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	_rows_vbox.add_child(row)

	var d_idx: int = int(m.get("dungeon_index", 0))
	var cleared: bool = d_idx > 0 and Global.is_dungeon_cleared(d_idx)

	var star_text: String
	if d_idx > 0:
		star_text = ("★" if m["completed"] else "☆") + ("★" if cleared else "☆")
	else:
		star_text = "★" if m["completed"] else "☆"
	var star := Label.new()
	star.text = star_text
	star.add_theme_font_size_override("font_size", 14)
	star.add_theme_color_override("font_color",
			C_STAR if (m["completed"] or cleared) else C_MUTED)
	star.custom_minimum_size = Vector2(24, 0)
	row.add_child(star)

	var lbl := Label.new()
	lbl.text = m["title"]
	lbl.add_theme_font_size_override("font_size", 12)
	lbl.add_theme_color_override("font_color", C_ACTIVE)
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(lbl)

	var btn := Button.new()
	btn.custom_minimum_size = Vector2(56, 0)
	btn.add_theme_font_size_override("font_size", 10)
	if m["id"] == Global.accepted_mission_id:
		btn.text = "Active"
		btn.disabled = true
	elif d_idx > 0 and not Global.is_dungeon_mission_ready(d_idx):
		btn.text = "Locked"
		btn.disabled = true
	else:
		btn.text = "Go"
		btn.pressed.connect(Global.accept_mission.bind(m["id"]))
	row.add_child(btn)

	_row_data.append({"label": lbl, "m": m, "row": row})

# ── Add a gameplay mission row ─────────────────────────────────────
func _add_gameplay_row(m: Dictionary) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	_rows_vbox.add_child(row)

	var star := Label.new()
	star.text = "★" if m["completed"] else "☆"
	star.add_theme_font_size_override("font_size", 14)
	star.add_theme_color_override("font_color",
			C_STAR if m["completed"] else C_MUTED)
	star.custom_minimum_size = Vector2(24, 0)
	row.add_child(star)

	var lbl := Label.new()
	lbl.text = m["title"]
	lbl.add_theme_font_size_override("font_size", 12)
	lbl.add_theme_color_override("font_color",
			C_DONE if m["completed"] else C_ACTIVE)
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(lbl)

	_row_data.append({"label": lbl, "m": m, "row": row})

# ── Signal handlers ───────────────────────────────────────────────
func _on_mission_updated() -> void:
	_stars_label.text = _stars_text()
	_rebuild_rows()

func _on_mission_completed(id: String) -> void:
	for entry in _row_data:
		if entry["m"]["id"] == id:
			var lbl = entry["label"]
			# Strikethrough + completion marker
			lbl.add_theme_color_override("font_color", C_DONE)
			lbl.text = "✓ " + entry["m"]["title"]
			# Wait 2 seconds then fade out
			var row = entry["row"]
			var tw := create_tween()
			tw.tween_interval(2.0)
			tw.tween_property(row, "modulate:a", 0.0, FADE_DURATION)
			tw.tween_callback(row.queue_free)
			break
	_stars_label.text = _stars_text()
	call_deferred("_rebuild_rows")

func _on_dungeon_cleared(_index: int) -> void:
	_stars_label.text = _stars_text()
	_rebuild_rows()

# ── Refill gameplay pool when missions complete ────────────────────
func _refill_pool() -> void:
	_active_pool.clear()
	for m in Global.missions:
		if m["completed"]:
			continue
		if m.has("dungeon_index"):
			continue
		_active_pool.append(m["id"])
		if _active_pool.size() >= GAMEPLAY_POOL_SIZE:
			break

# ── Helpers ───────────────────────────────────────────────────────
func _stars_text() -> String:
	var done := 0
	for m in Global.missions:
		if m["completed"]:
			done += 1
	done += Global.cleared_dungeons.size()
	var total: int = Global.missions.size() + Global.clearable_dungeon_count()
	return "★ %d / %d" % [done, total]

func _mission_language(m: Dictionary) -> String:
	var d_idx: int = int(m.get("dungeon_index", 0))
	if d_idx <= 0:
		return ""
	var dm := Global.get_dungeon_mission_for_index(d_idx)
	if dm == null:
		return ""
	var fname: String = dm.entry_resource_file if dm != null else ""
	if fname.is_empty() and dm != null:
		fname = dm.resource_path
	if fname.contains("_lua"):
		return "lua"
	if fname.contains("_python"):
		return "python"
	return ""

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
	var vp_w := get_viewport_rect().size.x
	_panel.position = Vector2(vp_w - PANEL_WIDTH - RIGHT_MARGIN, TOP_OFFSET)
	_panel.size = _panel.get_combined_minimum_size()

func _input(event: InputEvent) -> void:
	if _panel != null and _panel.visible:
		if event.is_action_pressed("escape"):
			pass  # panel is always visible, no close needed
