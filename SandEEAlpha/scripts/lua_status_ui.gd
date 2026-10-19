extends Control

# ── LUA status HUD (left-middle) ────────────────────────────────────
# Shows the 3 most recently-active placed LUAs and their current action
# ("Mining Stone", "Chopping trees", "Idle", …). Clicking the panel expands it
# into a full list of every LUA placed in the world. Reads each LuaNPC live via
# get_display_name()/get_status()/get_status_ms() (see lua_npc.gd).

const C_PANEL  := Color(0.08, 0.10, 0.20, 0.92)
const C_BORDER := Color(0.22, 0.32, 0.58, 0.80)
const C_TITLE  := Color(0.80, 0.90, 1.00, 1.00)
const C_MUTED  := Color(0.55, 0.65, 0.85, 0.80)
const C_ACTIVE := Color(0.95, 0.95, 0.80, 1.00)
const C_NAME   := Color(0.55, 0.85, 1.00, 1.00)

const LEFT_MARGIN := 12.0
const PANEL_WIDTH := 220.0
# Up to this many most-recently-active LUAs show in the collapsed panel. The
# expanded list (click the panel) still shows EVERY LUA.
const SHOWN       := 5
const POLL_SEC    := 0.25

var _panel:    PanelContainer = null
var _rows:     VBoxContainer  = null   # the 3 most-current rows
var _list:     VBoxContainer  = null   # expanded: every LUA
var _expanded: bool           = false
var _poll_accum: float        = 0.0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_build()
	if not Global.ui_scale_changed.is_connected(_on_ui_scale):
		Global.ui_scale_changed.connect(_on_ui_scale)
	# SAME background setting as the missions bar: this panel follows
	# Global.quest_opaque_bg so the two interfaces stay consistent.
	if not Global.quest_bg_changed.is_connected(_on_quest_bg):
		Global.quest_bg_changed.connect(_on_quest_bg)
	call_deferred("_refit")
	call_deferred("_refresh")

func _on_ui_scale(_s: float) -> void:
	if _panel != null:
		_panel.queue_free()
		_panel = null
	_build()
	_refit()
	_refresh()

# Rebuild when the shared "Opaque Quest Background" setting changes (the same
# signal the missions bar listens to).
func _on_quest_bg(_opaque: bool) -> void:
	if _panel != null:
		_panel.queue_free()
		_panel = null
	_build()
	_refit()
	_refresh()

# ── Build ─────────────────────────────────────────────────────────
func _build() -> void:
	var s: float = Global.ui_scale
	_panel = PanelContainer.new()
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	# Same presentation rule as the missions bar (mission_ui.gd): transparent by
	# default (text floats over the world) and a solid panel + border only while
	# the shared "Opaque Quest Background" setting is on.
	var opaque: bool = Global.quest_opaque_bg
	var sb := StyleBoxFlat.new()
	sb.bg_color = C_PANEL  if opaque else Color(0, 0, 0, 0)
	sb.border_color = C_BORDER if opaque else Color(0, 0, 0, 0)
	sb.set_border_width_all(1 if opaque else 0)
	sb.set_corner_radius_all(4 if opaque else 0)
	sb.content_margin_left   = int(8 * s)
	sb.content_margin_right  = int(8 * s)
	sb.content_margin_top    = int(6 * s)
	sb.content_margin_bottom = int(6 * s)
	_panel.add_theme_stylebox_override("panel", sb)
	_panel.custom_minimum_size = Vector2(int(PANEL_WIDTH * s), 0)
	_panel.gui_input.connect(_on_panel_input)
	add_child(_panel)

	var vbox := VBoxContainer.new()
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_theme_constant_override("separation", int(3 * s))
	_panel.add_child(vbox)

	var title := Label.new()
	title.text = "LUA STATUS  (click for all)"
	title.add_theme_font_size_override("font_size", int(10 * s))
	title.add_theme_color_override("font_color", C_TITLE)
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(title)

	_rows = VBoxContainer.new()
	_rows.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rows.add_theme_constant_override("separation", int(2 * s))
	vbox.add_child(_rows)

	_list = VBoxContainer.new()
	_list.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_list.add_theme_constant_override("separation", int(2 * s))
	_list.visible = _expanded
	vbox.add_child(_list)

func _refit() -> void:
	if _panel == null:
		return
	var s: float = Global.ui_scale
	var vp: Vector2 = get_viewport_rect().size
	_panel.size = _panel.get_combined_minimum_size()
	_panel.position = Vector2(LEFT_MARGIN * s, vp.y * 0.5 - _panel.size.y * 0.5)

func _process(delta: float) -> void:
	_poll_accum += delta
	if _poll_accum >= POLL_SEC:
		_poll_accum = 0.0
		_refresh()

# ── Data ──────────────────────────────────────────────────────────
# All live LUAs, most-recently-updated first (an actively-working LUA keeps
# bumping its status timestamp; an idle one falls to the bottom).
func _lua_list() -> Array:
	var out: Array = []
	for n in get_tree().get_nodes_in_group("LuaNPC"):
		if is_instance_valid(n):
			out.append(n)
	out.sort_custom(func(a, b) -> bool:
		return int(a.call("get_status_ms")) > int(b.call("get_status_ms")))
	return out

func _refresh() -> void:
	if _rows == null or _list == null:
		return
	var all: Array = _lua_list()
	# remove_child immediately (queue_free is deferred, so two _refresh calls in
	# the same frame — e.g. _process + a click — would double the rows).
	for c in _rows.get_children():
		_rows.remove_child(c)
		c.queue_free()
	for c in _list.get_children():
		_list.remove_child(c)
		c.queue_free()

	var shown: Array = all.slice(0, SHOWN)
	if shown.is_empty():
		_rows.add_child(_make_label("No LUAs placed", C_MUTED))
	else:
		for n in shown:
			_rows.add_child(_make_row(n))

	if _expanded:
		for n in all:
			_list.add_child(_make_row(n))
	_refit()

func _make_row(npc: Node) -> Control:
	var s: float = Global.ui_scale
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", int(4 * s))
	var name_lbl := _make_label(str(npc.call("get_display_name")), C_NAME)
	name_lbl.custom_minimum_size = Vector2(int(62 * s), 0)
	row.add_child(name_lbl)
	var combat: bool = npc.has_method("is_combat") and bool(npc.call("is_combat"))
	var status: String = str(npc.call("get_status"))
	if combat and npc.has_method("get_combat_hp"):
		status += "  HP %d/%d" % [int(npc.call("get_combat_hp")), int(npc.call("get_combat_max_hp"))]
	var st := _make_label(status, C_ACTIVE)
	st.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(st)
	# NOTE: there is deliberately NO terminate control here any more. Terminating
	# a LUA is now a menu action (pause menu -> LUA Management), where the player
	# picks the specific LUA from the active list. This panel is display-only.
	return row

func _make_label(text: String, col: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_font_size_override("font_size", int(10 * Global.ui_scale))
	l.add_theme_color_override("font_color", col)
	return l

func _on_panel_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed \
			and event.button_index == MOUSE_BUTTON_LEFT:
		_expanded = not _expanded
		_refresh()
		accept_event()
