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
	_panel.add_child(vbox)

	_stars_label = Label.new()
	_stars_label.add_theme_font_size_override("font_size", int(14 * s))
	_stars_label.add_theme_color_override("font_color", C_STAR)
	_stars_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_stars_label.text = _stars_text()
	vbox.add_child(_stars_label)

	vbox.add_child(HSeparator.new())

	_rows_vbox = VBoxContainer.new()
	_rows_vbox.add_theme_constant_override("separation", int(8 * s))
	vbox.add_child(_rows_vbox)

	_rebuild_rows()

# ── Section label helper ──────────────────────────────────────────
func _add_section(text: String) -> void:
	var s: float = Global.ui_scale
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", int(11 * s))
	lbl.add_theme_color_override("font_color", C_SECTION)
	lbl.add_theme_constant_override("line_spacing", int(1 * s))
	_rows_vbox.add_child(lbl)

# ── Rebuild rows ──────────────────────────────────────────────────
func _rebuild_rows() -> void:
	# Freeing the rows below would leave any running send-off tween pointing
	# at dead nodes; stop it first.
	_cancel_completion()
	for child in _rows_vbox.get_children().duplicate():
		child.free()
	_row_data.clear()

	# --- Dungeons (sequential per language: the current mission of each) ---
	# Both entrances already stand in the world; these rows just track
	# progress. Completing one immediately reveals the next in that track.
	for lang in Global.DUNGEON_LANGUAGES:
		var current := Global.current_dungeon_mission(lang)
		if current.is_empty():
			continue
		_add_section(String(lang).to_upper())
		_add_dungeon_row(current)

	# --- Gameplay (3 active, any order) ---
	var gameplay := _active_gameplay()
	if not gameplay.is_empty():
		_add_section("MISSIONS")
		for m in gameplay:
			_add_gameplay_row(m)

	_stars_label.text = _stars_text()
	_refit()

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
# Informational only — there is no accept/Go step anymore. Each language's
# current dungeon entrance is already standing in the world (see world.gd's
# _ensure_current_dungeon_entrances), so the row shows progress: a star for
# the mission and a second star for clearing the dungeon.
func _add_dungeon_row(m: Dictionary) -> void:
	var s: float = Global.ui_scale
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", int(8 * s))
	_rows_vbox.add_child(row)

	var d_idx: int = int(m.get("dungeon_index", 0))
	var cleared: bool = d_idx > 0 and Global.is_dungeon_cleared(d_idx)

	var star_text: String = ("★" if m["completed"] else "☆") + ("★" if cleared else "☆")
	var star := Label.new()
	star.text = star_text
	star.add_theme_font_size_override("font_size", int(14 * s))
	star.add_theme_color_override("font_color",
			C_STAR if (m["completed"] or cleared) else C_MUTED)
	star.custom_minimum_size = Vector2(int(24 * s), 0)
	row.add_child(star)

	var lbl := Label.new()
	lbl.text = m["title"]
	lbl.add_theme_font_size_override("font_size", int(12 * s))
	lbl.add_theme_color_override("font_color", C_ACTIVE)
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(lbl)

	_row_data.append({"label": lbl, "m": m, "row": row})

# ── Add a gameplay mission row ─────────────────────────────────────
func _add_gameplay_row(m: Dictionary) -> void:
	var s: float = Global.ui_scale
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", int(8 * s))
	_rows_vbox.add_child(row)

	var star := Label.new()
	star.text = "★" if m["completed"] else "☆"
	star.add_theme_font_size_override("font_size", int(14 * s))
	star.add_theme_color_override("font_color",
			C_STAR if m["completed"] else C_MUTED)
	star.custom_minimum_size = Vector2(int(24 * s), 0)
	row.add_child(star)

	var lbl := Label.new()
	var title: String = str(m["title"])
	var goal: int = int(m.get("goal", 0))
	if goal > 1 and not m["completed"]:
		title += "  (%d/%d)" % [int(m.get("progress", 0)), goal]
	lbl.text = title
	lbl.add_theme_font_size_override("font_size", int(12 * s))
	lbl.add_theme_color_override("font_color",
			C_DONE if m["completed"] else C_ACTIVE)
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(lbl)

	_row_data.append({"label": lbl, "m": m, "row": row})

# ── Signal handlers ───────────────────────────────────────────────
func _on_mission_updated() -> void:
	_stars_label.text = _stars_text()
	if _completing:
		return   # the send-off animation rebuilds the list when it finishes
	_rebuild_rows()

func _on_mission_completed(id: String) -> void:
	_stars_label.text = _stars_text()
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
	_stars_label.text = _stars_text()
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
	_panel.position = Vector2(vp_w - PANEL_WIDTH * s - RIGHT_MARGIN * s, TOP_OFFSET * s)
	_panel.size = _panel.get_combined_minimum_size()

func _input(event: InputEvent) -> void:
	if _panel != null and _panel.visible:
		if event.is_action_pressed("escape"):
			pass  # panel is always visible, no close needed
