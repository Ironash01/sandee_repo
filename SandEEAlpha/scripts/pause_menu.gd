extends Control

# ── Shared dark navy theme (matches inventory) ────────────────────
const C_PANEL   := Color(0.08, 0.10, 0.20, 0.97)
const C_BORDER  := Color(0.22, 0.32, 0.58, 1.00)
const C_TITLE   := Color(0.80, 0.90, 1.00, 1.00)
const C_MUTED   := Color(0.55, 0.65, 0.85, 1.00)
const C_OVERLAY := Color(0.00, 0.00, 0.00, 0.55)
# One settings implementation shared with the main menu.
const SETTINGS_PANEL_SCRIPT: Script = preload("res://scripts/settings_panel.gd")
const HELP_PANEL_SCRIPT: Script = preload("res://scripts/help_panel.gd")

# ── Internal refs ─────────────────────────────────────────────────
var _overlay:         ColorRect
var _pause_center:    ScrollContainer
var _settings_center: CenterContainer
var _help_center:     CenterContainer
# LUA Management panel (pause menu -> LUA Management). This is the ONLY
# player-facing way to terminate a LUA now, so the player always has to pick the
# specific LUA out of the list of currently-active ones.
var _lua_center:      CenterContainer
var _lua_rows:        VBoxContainer
var _lua_confirm:     PanelContainer
var _lua_confirm_lbl: Label
var _lua_pending:     Node = null
var _lua_poll:        float = 0.0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_build_overlay()
	_build_pause_panel()
	_build_settings_panel()
	_build_help_panel()
	_build_lua_panel()
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
	if _help_center != null:
		_help_center.queue_free()
		_help_center = null
	if _lua_center != null:
		_lua_center.queue_free()
		_lua_center = null
	_lua_pending = null
	_build_pause_panel()
	_build_settings_panel()
	_build_help_panel()
	_build_lua_panel()

# ── Dark overlay ──────────────────────────────────────────────────
func _build_overlay() -> void:
	_overlay = ColorRect.new()
	_overlay.color = C_OVERLAY
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_overlay)

# ── Pause panel ───────────────────────────────────────────────────
func _build_pause_panel() -> void:
	var s: float = Global.ui_scale
	# The pause strip is short: wrap the centred card in a scroll root so a
	# small landscape window can still reach Help/Settings/Quit instead of
	# clipping the bottom button below the safe area.
	_pause_center = ScrollContainer.new()
	_pause_center.set_anchors_preset(Control.PRESET_FULL_RECT)
	Global.apply_safe_area(_pause_center)
	_pause_center.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_pause_center.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	add_child(_pause_center)

	var center := CenterContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	center.custom_minimum_size = Global.ui_content_rect().size
	_pause_center.add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Global.ui_fit_min_size(Vector2(300, 300))
	var ps1 := StyleBoxFlat.new()
	ps1.bg_color     = C_PANEL
	ps1.border_color = C_BORDER
	ps1.set_border_width_all(1)
	ps1.set_corner_radius_all(6)
	ps1.content_margin_left   = int(24 * s)
	ps1.content_margin_right  = int(24 * s)
	ps1.content_margin_top    = int(24 * s)
	ps1.content_margin_bottom = int(24 * s)
	panel.add_theme_stylebox_override("panel", ps1)
	center.add_child(panel)

	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, int(20 * s))
	panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", int(12 * s))
	margin.add_child(vbox)

	var title := Label.new()
	title.text = "— PAUSED —"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", Global.ui_type_size(Global.UI_TYPE_HEADING))
	title.add_theme_color_override("font_color", C_TITLE)
	vbox.add_child(title)

	_add_spacer(vbox, int(10 * s))
	_make_btn(vbox, "Resume",       _on_resume).tooltip_text       = "Return to the game."
	_make_btn(vbox, "Help & Documentation", _on_open_help).tooltip_text = "Complete controls, systems and progression reference."
	_make_btn(vbox, "Settings",     _on_open_settings).tooltip_text = "Audio, display, gameplay and controls."
	_make_btn(vbox, "Automatica Management", _on_open_lua).tooltip_text = "List the active Automaticas and terminate one."
	_make_btn(vbox, "Quit to Menu", _on_quit).tooltip_text         = "Save and return to the main menu."

# Help & Documentation panel (category sidebar + scrollable reference)
func _build_help_panel() -> void:
	_help_center = CenterContainer.new()
	_help_center.set_anchors_preset(Control.PRESET_FULL_RECT)
	Global.apply_safe_area(_help_center)
	_help_center.visible = false
	add_child(_help_center)

	var panel: Control = HELP_PANEL_SCRIPT.new()
	panel.name = "HelpPanel"
	panel.connect("close_requested", _on_help_back)
	_help_center.add_child(panel)

# Settings panel (sidebar categories + content)
func _build_settings_panel() -> void:
	_settings_center = CenterContainer.new()
	_settings_center.set_anchors_preset(Control.PRESET_FULL_RECT)
	Global.apply_safe_area(_settings_center)
	_settings_center.visible = false
	add_child(_settings_center)

	# Same panel the main menu uses, so both settings screens always expose the
	# same categories and values.
	var panel: Control = SETTINGS_PANEL_SCRIPT.new()
	panel.name = "SettingsPanel"
	panel.call("set_show_credits", false)
	panel.connect("close_requested", _on_back)
	_settings_center.add_child(panel)

# Build the content pane for one category.
func _make_btn(parent: Node, label: String, callback: Callable) -> Button:
	var btn := Button.new()
	btn.text = label
	btn.custom_minimum_size = Vector2(
		maxf(240.0 * Global.ui_scale, 220.0),
		maxf(44.0 * Global.ui_scale, float(Global.ui_type_size(Global.UI_TYPE_BODY) + 20)))
	btn.add_theme_font_size_override("font_size", Global.ui_type_size(Global.UI_TYPE_BODY))
	btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	btn.pressed.connect(callback)
	parent.add_child(btn)
	return btn

func _add_spacer(parent: Node, height: int) -> void:
	var s := Control.new()
	s.custom_minimum_size = Vector2(0, height)
	parent.add_child(s)

func show_menu() -> void:
	if Global.any_ui_open():
		return
	Global.pause_menu_open = true
	visible = true
	_pause_center.visible    = true
	_pause_center.scroll_vertical = 0
	_settings_center.visible = false
	if _help_center != null:
		_help_center.visible = false
	if _lua_center != null:
		_lua_center.visible = false
	if _lua_confirm != null:
		_lua_confirm.visible = false
	_lua_pending = null
	Global.register_ui_back(self, Callable(self, "_pause_back"))
	# Pause is opened directly (not through Global.open_ui), so it must cancel
	# touch/PNC/attack state explicitly before the tree stops processing it.
	Global.cancel_gameplay_input()
	get_tree().paused = true

func hide_menu() -> void:
	Global.pause_menu_open = false
	Global.unregister_ui_back(self)
	visible = false
	# Resume only when NOTHING else still needs the game paused ΓÇö the same rule
	# Global.close_ui() uses. Writing paused = false unconditionally here would
	# resume gameplay while another UI/dialog was still open.
	if not Global.any_ui_open():
		get_tree().paused = false

func _on_resume() -> void:
	hide_menu()

func _on_open_settings() -> void:
	_pause_center.visible    = false
	_settings_center.visible = true
	if _help_center != null:
		_help_center.visible = false

func _on_open_help() -> void:
	_pause_center.visible    = false
	_settings_center.visible = false
	if _lua_center != null:
		_lua_center.visible = false
	if _lua_confirm != null:
		_lua_confirm.visible = false
	_lua_pending = null
	_help_center.visible = true

func _on_help_back() -> void:
	if _help_center != null:
		_help_center.visible = false
	_pause_center.visible = true

func _on_back() -> void:
	_settings_center.visible = false
	_pause_center.visible    = true

# ΓöÇΓöÇ LUA Management panel ΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇ
# Lists every currently-active LUA. Terminating one from here is the ONLY
# player-facing way to remove a LUA: the status-HUD Γÿá button, the per-station
# TERMINATE button and STOP-on-a-combat-LUA were all removed. The list is rebuilt
# from the live "LuaNPC" group, never a cached copy, so it can't hold a stale
# entry.
func _build_lua_panel() -> void:
	var s: float = Global.ui_scale
	_lua_center = CenterContainer.new()
	_lua_center.set_anchors_preset(Control.PRESET_FULL_RECT)
	Global.apply_safe_area(_lua_center)
	_lua_center.visible = false
	add_child(_lua_center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Global.ui_fit_min_size(Vector2(480, 380))
	var ps := StyleBoxFlat.new()
	ps.bg_color     = C_PANEL
	ps.border_color = C_BORDER
	ps.set_border_width_all(1)
	ps.set_corner_radius_all(6)
	ps.content_margin_left   = int(24 * s)
	ps.content_margin_right  = int(24 * s)
	ps.content_margin_top    = int(20 * s)
	ps.content_margin_bottom = int(24 * s)
	panel.add_theme_stylebox_override("panel", ps)
	_lua_center.add_child(panel)

	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", int(10 * s))
	panel.add_child(outer)

	var title := Label.new()
	title.text = "LUA MANAGEMENT"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", Global.ui_type_size(Global.UI_TYPE_HEADING))
	title.add_theme_color_override("font_color", C_TITLE)
	outer.add_child(title)

	var hint := Label.new()
	hint.text = "Select a LUA to terminate it permanently."
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", Global.ui_type_size(Global.UI_TYPE_CAPTION))
	hint.add_theme_color_override("font_color", C_MUTED)
	outer.add_child(hint)

	# Scrollable so a long list can't overflow the panel.
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size = Vector2(0, int(230 * s))
	outer.add_child(scroll)

	_lua_rows = VBoxContainer.new()
	_lua_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_lua_rows.add_theme_constant_override("separation", int(6 * s))
	scroll.add_child(_lua_rows)

	# Destructive-action confirmation ΓÇö the same centred-panel convention the
	# cave / dungeon portal confirm dialogs use.
	_lua_confirm = PanelContainer.new()
	_lua_confirm.visible = false
	var cs := StyleBoxFlat.new()
	cs.bg_color     = C_PANEL
	cs.border_color = Color(1.0, 0.45, 0.45, 1.0)
	cs.set_border_width_all(2)
	cs.set_corner_radius_all(6)
	cs.content_margin_left   = int(16 * s)
	cs.content_margin_right  = int(16 * s)
	cs.content_margin_top    = int(12 * s)
	cs.content_margin_bottom = int(12 * s)
	_lua_confirm.add_theme_stylebox_override("panel", cs)
	outer.add_child(_lua_confirm)

	var cv := VBoxContainer.new()
	cv.add_theme_constant_override("separation", int(8 * s))
	_lua_confirm.add_child(cv)

	_lua_confirm_lbl = Label.new()
	_lua_confirm_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_lua_confirm_lbl.add_theme_font_size_override("font_size", Global.ui_type_size(Global.UI_TYPE_BODY))
	_lua_confirm_lbl.add_theme_color_override("font_color", Color(1.0, 0.7, 0.7, 1.0))
	cv.add_child(_lua_confirm_lbl)

	var crow := HBoxContainer.new()
	crow.alignment = BoxContainer.ALIGNMENT_CENTER
	crow.add_theme_constant_override("separation", int(12 * s))
	cv.add_child(crow)
	var yes := Button.new()
	yes.text = "Terminate"
	yes.pressed.connect(_confirm_terminate)
	crow.add_child(yes)
	var no := Button.new()
	no.text = "Cancel"
	no.pressed.connect(_cancel_terminate)
	crow.add_child(no)

	_add_spacer(outer, int(4 * s))
	_make_btn(outer, "Back", _on_lua_back).tooltip_text = "Return to the pause menu."

func _on_open_lua() -> void:
	_pause_center.visible    = false
	_settings_center.visible = false
	if _help_center != null:
		_help_center.visible = false
	_lua_center.visible      = true
	_lua_confirm.visible     = false
	_lua_pending             = null
	_refresh_lua_list()

func _on_lua_back() -> void:
	_lua_confirm.visible  = false
	_lua_pending          = null
	_lua_center.visible   = false
	_pause_center.visible = true

# Keeps the open list in step with the world (a LUA can be removed by combat
# death). Cheap: only runs while the panel is actually showing.
func _process(delta: float) -> void:
	if _lua_center == null or not _lua_center.visible:
		return
	_lua_poll += delta
	if _lua_poll < 0.5:
		return
	_lua_poll = 0.0
	# A pending confirmation whose LUA vanished must not stay armed.
	if _lua_pending != null and (not is_instance_valid(_lua_pending) or _lua_pending.is_queued_for_deletion()):
		_lua_confirm.visible = false
		_lua_pending         = null
	_refresh_lua_list()

# Rebuild from the live registry: skip freed / terminating / terminated nodes so
# nothing stale or already-gone is ever listed.
func _refresh_lua_list() -> void:
	if _lua_rows == null:
		return
	for c in _lua_rows.get_children():
		_lua_rows.remove_child(c)
		c.queue_free()

	var all: Array = []
	for n in get_tree().get_nodes_in_group("LuaNPC"):
		if not is_instance_valid(n) or n.is_queued_for_deletion():
			continue
		if n.has_method("is_terminated") and bool(n.call("is_terminated")):
			continue
		all.append(n)
	all.sort_custom(func(a, b) -> bool:
		return int(a.call("get_status_ms")) > int(b.call("get_status_ms")))

	if all.is_empty():
		var empty := Label.new()
		empty.text = "No active LUAs."
		empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty.add_theme_font_size_override("font_size", Global.ui_type_size(Global.UI_TYPE_LABEL))
		empty.add_theme_color_override("font_color", C_MUTED)
		_lua_rows.add_child(empty)
		return

	for n in all:
		_lua_rows.add_child(_make_lua_row(n))

func _make_lua_row(npc: Node) -> Control:
	var s: float = Global.ui_scale
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", int(8 * s))

	var name_lbl := Label.new()
	name_lbl.text = str(npc.call("get_display_name"))
	name_lbl.custom_minimum_size = Vector2(int(96 * s), 0)
	name_lbl.add_theme_font_size_override("font_size", Global.ui_type_size(Global.UI_TYPE_LABEL))
	name_lbl.add_theme_color_override("font_color", C_TITLE)
	row.add_child(name_lbl)

	var combat: bool = npc.has_method("is_combat") and bool(npc.call("is_combat"))
	var status: String = str(npc.call("get_status"))
	if combat and npc.has_method("get_combat_hp"):
		status += "  HP %d/%d" % [int(npc.call("get_combat_hp")), int(npc.call("get_combat_max_hp"))]
	var st := Label.new()
	st.text = status
	st.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	st.add_theme_font_size_override("font_size", Global.ui_type_size(Global.UI_TYPE_LABEL))
	st.add_theme_color_override("font_color", Color(0.95, 0.95, 0.80, 1.0))
	row.add_child(st)

	# Only COMBAT LUAs are terminable ΓÇö the same rule the removed controls used
	# (a normal LUA is stopped, not destroyed). The button stays visible so the
	# list still shows every active LUA.
	var term := Button.new()
	term.text = "Terminate"
	term.add_theme_font_size_override("font_size", Global.ui_type_size(Global.UI_TYPE_CAPTION))
	term.disabled = not combat
	term.tooltip_text = ("Terminate %s permanently." % str(npc.call("get_display_name"))) if combat \
		else "Only combat LUAs can be terminated."
	term.pressed.connect(func() -> void: _ask_terminate(npc))
	row.add_child(term)
	return row

# Ask first. The pending node is re-validated at confirm time, so a list change
# between opening and confirming can never terminate a different LUA.
func _ask_terminate(npc: Node) -> void:
	if not is_instance_valid(npc) or npc.is_queued_for_deletion():
		_refresh_lua_list()
		return
	_lua_pending = npc
	_lua_confirm_lbl.text = "Terminate %s permanently?" % str(npc.call("get_display_name"))
	_lua_confirm.visible = true

func _cancel_terminate() -> void:
	_lua_confirm.visible = false
	_lua_pending         = null

func _confirm_terminate() -> void:
	var npc: Node = _lua_pending
	_lua_confirm.visible = false
	_lua_pending         = null
	if npc == null or not is_instance_valid(npc) or npc.is_queued_for_deletion():
		_refresh_lua_list()
		return
	# Reuse the existing safe termination path (see lua_npc.terminate()).
	if npc.has_method("terminate"):
		npc.call("terminate")
	_refresh_lua_list()

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
# Back out of the innermost pause layer first: termination confirm, Automatica
# management, settings, then the pause menu itself.
func _pause_back() -> void:
	if _lua_confirm != null and _lua_confirm.visible:
		_cancel_terminate()
	elif _lua_center != null and _lua_center.visible:
		_on_lua_back()
	elif _settings_center.visible:
		_on_back()
	elif _help_center != null and _help_center.visible:
		_on_help_back()
	else:
		hide_menu()
		return
	# request_ui_back() pops before invoking; we only went back one layer.
	if visible:
		Global.register_ui_back(self, Callable(self, "_pause_back"))

func _input(event: InputEvent) -> void:
	# The shared settings panel owns its own rebind listener; don't let this
	# parent handle Escape or the menu while it is waiting for a key.
	var settings_panel := _settings_center.get_node_or_null("SettingsPanel") if _settings_center != null else null
	if settings_panel != null and settings_panel.has_method("is_rebinding") \
			and bool(settings_panel.call("is_rebinding")):
		return
	if event.is_action_pressed("escape"):
		get_viewport().set_input_as_handled()
		if visible:
			if not Global.request_ui_back(event) and not Global.is_ui_back_event_consumed(event):
				_pause_back()
		elif not Global.any_ui_open():
			show_menu()
