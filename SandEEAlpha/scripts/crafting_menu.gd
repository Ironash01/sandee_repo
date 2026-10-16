extends Control

# ── Theme ─────────────────────────────────────────────────────────
const C_PANEL     := Color(0.08, 0.10, 0.20, 0.97)
const C_BORDER    := Color(0.22, 0.32, 0.58, 1.00)
const C_TITLE     := Color(0.80, 0.90, 1.00, 1.00)
const C_MUTED     := Color(0.55, 0.65, 0.85, 1.00)
const C_DIVIDER   := Color(0.20, 0.28, 0.50, 1.00)
const C_TIP_BG    := Color(0.11, 0.15, 0.28, 1.00)
const C_EFFECT    := Color(0.55, 0.90, 0.60, 1.00)
const C_OVERLAY   := Color(0.00, 0.00, 0.00, 0.50)
const C_SEL       := Color(0.25, 0.40, 0.75, 1.00)
const C_TAB_BG    := Color(0.06, 0.08, 0.17, 1.00)
const C_CAN_CRAFT := Color(0.15, 0.45, 0.20, 1.00)
const C_NO_MAT    := Color(0.30, 0.20, 0.20, 1.00)
const C_RED       := Color(1.00, 0.35, 0.35, 1.00)

const CATEGORIES  := ["Materials", "Blocks", "Weapons & Tools", "Others"]
# preload (not class_name) so the name-argument completion works even before the
# editor has registered the helper's global class.
const NameComplete: GDScript = preload("res://scripts/lua_name_complete.gd")

# ── Auto-discovered recipe directory (no hardcoded list needed) ────
const RECIPE_DIR: String = "res://resources/recipes/"

# ── Mode ──────────────────────────────────────────────────────────
# false = unused (station always opens via open_as_station)
# true  = crafting station (station-required recipes only)
var _station_mode: bool = false

# ── State ─────────────────────────────────────────────────────────
var _tree:         SceneTree
var _recipes:      Array  = []
var _filtered:     Array  = []
var _active_cat:   String = "Materials"
var _selected_idx: int    = -1

# ── Station automation (Crafting / Automation / Programming) ──────
# `station` is set by CraftingStation before this menu enters the tree. The
# menu only READS/WRITES station state through the station's Automation API —
# it never crafts or validates anything itself.
enum Mode { CRAFTING, AUTOMATION, PROGRAMMING }
var _mode: int    = Mode.CRAFTING
var station: Node = null

var _craft_body:     Control
var _auto_body:      Control
var _prog_body:      Control
var _output_section: Control
var _mode_btns:      Dictionary = {}
# Full-screen programming overlay (AUTOMATION + PROGRAMMING + input/output),
# opened by the header's 🐍 PROGRAM button — same pattern as the furnace UI.
var _prog_overlay:   Control

var _auto_grid:     GridContainer
var _auto_selected: Label
var _auto_status:   Label

var _code_edit: TextEdit
var _prog_log:  RichTextLabel
var _name_popup: PopupPanel
var _name_list:  ItemList

var _output_slot:  Button
var _output_count: Label
var _output_hint:  Label

var _input_section: Control
var _input_slot:    Control   # station_input_slot.gd
var _input_hint:    Label

# ── Node refs ─────────────────────────────────────────────────────
var _recipe_list:   GridContainer
var _detail_panel:  Control
var _detail_name:   Label
var _detail_ing1:   HBoxContainer
var _detail_ing2:   HBoxContainer
var _detail_result: HBoxContainer
var _craft_btn:     Button
var _cat_btns:      Dictionary = {}
var _row_btns:      Array      = []
var _title_label:   Label

# ── Lifecycle ─────────────────────────────────────────────────────
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_tree = get_tree()
	if has_meta("station_mode"):
		_station_mode = get_meta("station_mode")
	station = get("station")
	if station != null and station.has_signal("station_state_changed"):
		station.station_state_changed.connect(_on_station_state_changed)
	_load_recipes()
	_build()
	Global.Inventory_updated.connect(_refresh_highlights)
	Global.Hotbar_updated.connect(_refresh_highlights)
	Global.ui_scale_changed.connect(_on_ui_scale)
	visible = false

func _on_ui_scale(_s: float) -> void:
	var was_visible: bool = visible
	var was_mode:    int  = _mode
	# Keep whatever the player typed — the editor widget is about to be rebuilt.
	_store_program_code()
	for child in get_children():
		child.queue_free()
	_cat_btns.clear()
	_row_btns.clear()
	_recipe_list  = null
	_detail_panel = null
	_selected_idx = -1
	_mode_btns.clear()
	if not is_inside_tree():
		return
	await get_tree().process_frame
	_build()
	_filter_and_refresh()
	# Restore the tab the player was on instead of snapping back to CRAFTING.
	_set_mode(was_mode)
	visible = was_visible

func _load_recipes() -> void:
	# ResourceLoader.list_directory (not DirAccess) so this survives export —
	# see Global._load_resource_dir for why DirAccess misses .tres there.
	for fname in ResourceLoader.list_directory(RECIPE_DIR):
		if fname.ends_with(".tres"):
			var res: Resource = load(RECIPE_DIR + fname) as Resource
			if res != null and res is CraftingRecipe:
				var recipe: CraftingRecipe = res as CraftingRecipe
				if recipe.result_item != null and recipe.result_item.is_craftable \
						and not recipe.result_item.is_dev_item:
					_recipes.append(recipe)

# ── Public: open this menu in station mode ─────────────────────────
func open_as_station() -> void:
	_station_mode = true
	if _title_label != null:
		_title_label.text = "CRAFTING STATION"
	_selected_idx = -1
	if _detail_panel != null:
		_detail_panel.visible = false
	_filter_and_refresh()
	_refresh_automation()
	_refresh_input()
	_refresh_output()
	show_menu()

# ── Build UI ──────────────────────────────────────────────────────
func _build() -> void:
	var s: float = Global.ui_scale

	var overlay := ColorRect.new()
	overlay.color        = C_OVERLAY
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(overlay)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var outer := HBoxContainer.new()
	outer.add_theme_constant_override("separation", 0)
	center.add_child(outer)

	# Single centred panel (no side tab strip) — same shape as the furnace UI.
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(1080 * s, 540 * s)
	var ps := _sb(C_PANEL, C_BORDER, 6, int(16*s), int(16*s), int(14*s), int(16*s))
	panel.add_theme_stylebox_override("panel", ps)
	outer.add_child(panel)

	# Inventory on the LEFT, station content on the RIGHT (furnace parity).
	var panel_row := HBoxContainer.new()
	panel_row.add_theme_constant_override("separation", int(14 * s))
	panel.add_child(panel_row)

	# Inventory only here — the player's on-screen hotbar stays reachable
	# (this menu's canvas sits below it), so no HOTBAR strip.
	var items := PlayerItemsPanel.new()
	items.show_hotbar = false
	panel_row.add_child(items)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", int(10 * s))
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel_row.add_child(vbox)

	# Header: title + 🐍 PROGRAM (opens the overlay) + close.
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", int(6 * s))
	vbox.add_child(header)
	_title_label = _lbl("CRAFTING STATION", int(16 * s), C_TITLE)
	_title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(_title_label)
	var prog_btn := Button.new()
	prog_btn.text = "🐍 PROGRAM"
	prog_btn.tooltip_text = "Write a Python/Lua program to automate this station."
	prog_btn.add_theme_font_size_override("font_size", int(12 * s))
	prog_btn.add_theme_color_override("font_color", C_TITLE)
	prog_btn.pressed.connect(func() -> void: _set_mode(Mode.PROGRAMMING))
	header.add_child(prog_btn)
	var close := Button.new()
	close.text = "✕"
	close.flat = true
	close.tooltip_text = "Close the crafting station."
	close.add_theme_color_override("font_color", C_MUTED)
	close.pressed.connect(hide_menu)
	header.add_child(close)

	_div(vbox)

	# The manual crafting view is always the main view.
	_craft_body = _build_craft_body(s)
	vbox.add_child(_craft_body)

	# Automation + Programming live in a separate overlay (furnace parity).
	_build_programming_overlay(s)

	_set_mode(Mode.CRAFTING)

# Programming overlay: the automation recipe selector, the input/output slots,
# and the code editor — opened by the header's 🐍 PROGRAM button, exactly like
# the furnace's PROGRAM panel.
func _build_programming_overlay(s: float) -> void:
	_prog_overlay = Control.new()
	_prog_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_prog_overlay.visible = false
	add_child(_prog_overlay)

	var dim := ColorRect.new()
	dim.color = C_OVERLAY
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_prog_overlay.add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_prog_overlay.add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(780 * s, 540 * s)
	var ps := _sb(C_PANEL, C_BORDER, 6, int(18*s), int(18*s), int(14*s), int(18*s))
	panel.add_theme_stylebox_override("panel", ps)
	center.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", int(8 * s))
	panel.add_child(vbox)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", int(6 * s))
	vbox.add_child(header)
	var title := _lbl("STATION PROGRAMMING", int(15 * s), C_TITLE)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	for entry in [
		{"mode": Mode.AUTOMATION,  "text": "AUTOMATION"},
		{"mode": Mode.PROGRAMMING, "text": "PROGRAMMING"},
	]:
		var btn := Button.new()
		btn.text = entry["text"]
		btn.add_theme_font_size_override("font_size", int(11 * s))
		var m: int = entry["mode"]
		btn.pressed.connect(func() -> void: _set_mode(m))
		header.add_child(btn)
		_mode_btns[m] = btn
	var close := Button.new()
	close.text = "✕"; close.flat = true
	close.add_theme_color_override("font_color", C_MUTED)
	close.pressed.connect(_close_programming)
	header.add_child(close)

	_auto_body = _build_automation_body(s)
	vbox.add_child(_auto_body)
	_prog_body = _build_programming_body(s)
	vbox.add_child(_prog_body)
	# Input + Output slots — shared by Automation and Programming.
	_input_section = _build_input_section(s)
	vbox.add_child(_input_section)
	_output_section = _build_output_section(s)
	vbox.add_child(_output_section)

func _close_programming() -> void:
	_set_mode(Mode.CRAFTING)

# ── Mode switch ───────────────────────────────────────────────────
func _build_mode_row(parent: Node, s: float) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", int(6 * s))
	parent.add_child(row)
	for entry in [
		{"mode": Mode.CRAFTING,    "text": "CRAFTING"},
		{"mode": Mode.AUTOMATION,  "text": "AUTOMATION"},
		{"mode": Mode.PROGRAMMING, "text": "PROGRAMMING"},
	]:
		var btn := Button.new()
		btn.text                  = entry["text"]
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.custom_minimum_size   = Vector2(0, int(30 * s))
		btn.add_theme_font_size_override("font_size", int(12 * s))
		var m: int = entry["mode"]
		btn.pressed.connect(func() -> void: _set_mode(m))
		row.add_child(btn)
		_mode_btns[m] = btn

func _update_mode_btns() -> void:
	for m in _mode_btns:
		var btn: Button  = _mode_btns[m] as Button
		var active: bool = m == _mode
		var ps := _sb(C_SEL if active else C_PANEL,
			C_TITLE if active else C_BORDER, 4, 8, 8, 6, 6)
		btn.add_theme_stylebox_override("normal",  ps)
		btn.add_theme_stylebox_override("hover",   ps)
		btn.add_theme_stylebox_override("pressed", ps)
		btn.add_theme_color_override("font_color", C_TITLE if active else C_MUTED)

func _set_mode(mode: int) -> void:
	_mode = mode
	# The overlay hosts automation + programming; the main panel always shows
	# the manual crafting body.
	if _prog_overlay != null:   _prog_overlay.visible   = mode != Mode.CRAFTING
	if _craft_body != null:     _craft_body.visible     = mode == Mode.CRAFTING
	if _auto_body != null:      _auto_body.visible      = mode == Mode.AUTOMATION
	if _prog_body != null:      _prog_body.visible      = mode == Mode.PROGRAMMING
	if _input_section != null:  _input_section.visible  = mode != Mode.CRAFTING
	if _output_section != null: _output_section.visible = mode != Mode.CRAFTING
	_update_mode_btns()
	# Leaving the Programming tab keeps the editor text on the station.
	if mode != Mode.PROGRAMMING:
		_store_program_code()
	if mode == Mode.AUTOMATION:
		_refresh_automation()
	if mode == Mode.PROGRAMMING:
		_ensure_program_host()

# ── Crafting body (the original manual crafting view) ─────────────
func _build_craft_body(s: float) -> Control:
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", int(10 * s))
	root.size_flags_vertical = Control.SIZE_EXPAND_FILL

	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", int(6 * s))
	root.add_child(tabs)
	for cat in CATEGORIES:
		var btn := Button.new()
		btn.text                  = cat
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.custom_minimum_size   = Vector2(0, int(30 * s))
		btn.add_theme_font_size_override("font_size", int(12 * s))
		btn.tooltip_text = "Show the %s recipes." % cat
		var c: String = cat as String
		btn.pressed.connect(func() -> void: _on_category(c))
		tabs.add_child(btn)
		_cat_btns[cat] = btn
	_highlight_tab(_active_cat)

	_div(root)

	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", int(12 * s))
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(body)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size    = Vector2(int(320 * s), 0)
	scroll.size_flags_vertical    = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	body.add_child(scroll)

	_recipe_list = GridContainer.new()
	_recipe_list.columns = 4
	_recipe_list.add_theme_constant_override("h_separation", int(8 * s))
	_recipe_list.add_theme_constant_override("v_separation", int(8 * s))
	_recipe_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_recipe_list)

	_detail_panel = _build_detail(s)
	_detail_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_detail_panel.size_flags_vertical   = Control.SIZE_EXPAND_FILL
	body.add_child(_detail_panel)
	_detail_panel.visible = false

	_filter_and_refresh()
	return root

# ── Automation body (configuration only) ──────────────────────────
func _build_automation_body(s: float) -> Control:
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", int(8 * s))
	root.size_flags_vertical = Control.SIZE_EXPAND_FILL

	root.add_child(_lbl("SELECT AUTOMATION RECIPE", int(11 * s), C_MUTED))
	var hint := _lbl("Selecting a recipe does not craft anything — run a program in the PROGRAMMING tab.",
		int(10 * s), C_MUTED)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(hint)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical    = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(scroll)

	_auto_grid = GridContainer.new()
	_auto_grid.columns = 6
	_auto_grid.add_theme_constant_override("h_separation", int(8 * s))
	_auto_grid.add_theme_constant_override("v_separation", int(8 * s))
	scroll.add_child(_auto_grid)

	_div(root)

	var sel_row := HBoxContainer.new()
	sel_row.add_theme_constant_override("separation", int(8 * s))
	root.add_child(sel_row)
	sel_row.add_child(_lbl("Selected Recipe:", int(12 * s), C_MUTED))
	_auto_selected = _lbl("(none)", int(12 * s), C_TITLE)
	_auto_selected.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sel_row.add_child(_auto_selected)

	_auto_status = _lbl("Status: No recipe selected", int(11 * s), C_EFFECT)
	root.add_child(_auto_status)
	return root

func _refresh_automation() -> void:
	if _auto_grid == null or station == null:
		return
	for child in _auto_grid.get_children():
		child.queue_free()
	var s: float = Global.ui_scale
	var recipes: Array = station.call("get_station_recipes") if station.has_method("get_station_recipes") else []
	for r in recipes:
		var recipe: CraftingRecipe = r as CraftingRecipe
		var btn := Button.new()
		btn.custom_minimum_size     = Vector2(Global.ITEM_SLOT_SIZE * s, Global.ITEM_SLOT_SIZE * s)
		btn.icon                    = recipe.result_item.icon
		btn.expand_icon             = true
		btn.icon_alignment          = HORIZONTAL_ALIGNMENT_CENTER
		btn.vertical_icon_alignment = VERTICAL_ALIGNMENT_CENTER
		btn.tooltip_text            = recipe.result_item.item_name
		var res: ItemData = recipe.result_item
		btn.mouse_entered.connect(func() -> void: Global.show_item_tooltip({"data": res, "quantity": 1}))
		btn.mouse_exited.connect(func() -> void: Global.hide_item_tooltip())
		var rec := recipe
		btn.pressed.connect(func() -> void: _on_auto_pick(rec))
		var ps := _sb(C_TIP_BG, C_BORDER, 4, 4, 4, 4, 4)
		btn.add_theme_stylebox_override("normal",  ps)
		btn.add_theme_stylebox_override("hover",   ps)
		btn.add_theme_stylebox_override("pressed", ps)
		_auto_grid.add_child(btn)
	_refresh_automation_selection()

func _on_auto_pick(recipe: CraftingRecipe) -> void:
	if station == null:
		return
	station.call("set_automation_recipe", recipe)
	_refresh_automation_selection()

func _refresh_automation_selection() -> void:
	if station == null:
		return
	var name: String = str(station.call("get_automation_recipe_name"))
	if _auto_selected != null:
		_auto_selected.text = name if not name.is_empty() else "(none)"
	if _auto_status != null:
		_auto_status.text = "Status: Waiting for program" if not name.is_empty() \
			else "Status: No recipe selected"

# ── Programming body ──────────────────────────────────────────────
func _build_programming_body(s: float) -> Control:
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", int(8 * s))
	root.size_flags_vertical = Control.SIZE_EXPAND_FILL

	root.add_child(_lbl("PYTHON PROGRAM", int(11 * s), C_MUTED))
	# Custom (game) API only here — the language's own built-ins are listed in
	# the Lua robot editor's Encyclopedia, and the two are deliberately kept
	# apart. Source of truth: scripts/api_reference.gd.
	var custom: Array = APIReference.CUSTOM_PYTHON_STATION
	var lines: PackedStringArray = []
	for e in custom:
		lines.append("%s — %s" % [str(e["sig"]), str(e["desc"])])
	var hint := _lbl("Station API:\n" + "\n".join(lines),
		int(10 * s), C_MUTED)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(hint)

	_code_edit = TextEdit.new()
	_code_edit.custom_minimum_size   = Vector2(0, int(140 * s))
	_code_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_code_edit.size_flags_vertical   = Control.SIZE_EXPAND_FILL
	_code_edit.add_theme_font_size_override("font_size", int(13 * s))
	_code_edit.placeholder_text      = "craft(1)"
	if station != null:
		_code_edit.text = str(station.get("program_code"))
	# Item-name popup: when the caret sits inside a name-argument function's
	# parentheses, offer the list of valid items to pick from.
	_code_edit.text_changed.connect(_on_program_text_changed)
	root.add_child(_code_edit)

	_name_popup = PopupPanel.new()
	var name_list := ItemList.new()
	name_list.custom_minimum_size = Vector2(int(200 * s), int(180 * s))
	name_list.add_theme_font_size_override("font_size", int(12 * s))
	name_list.item_selected.connect(_on_name_item_selected)
	_name_popup.add_child(name_list)
	_name_list = name_list
	add_child(_name_popup)

	var btn_row := HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", int(8 * s))
	root.add_child(btn_row)
	btn_row.add_child(_make_action_btn("▶  RUN", Color(0.15, 0.45, 0.20, 1.0),
		Color(0.80, 1.0, 0.80, 1.0), _on_run_program, s))
	btn_row.add_child(_make_action_btn("CLEAR", Color(0.20, 0.22, 0.34, 1.0),
		C_TITLE, _on_clear_program, s))

	_prog_log = RichTextLabel.new()
	_prog_log.bbcode_enabled      = true
	_prog_log.scroll_following    = true
	_prog_log.custom_minimum_size = Vector2(0, int(90 * s))
	_prog_log.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_prog_log.add_theme_font_size_override("font_size", int(12 * s))
	_prog_log.add_theme_color_override("default_color", C_MUTED)
	root.add_child(_prog_log)
	return root

func _make_action_btn(text: String, bg: Color, fg: Color, cb: Callable, s: float) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.custom_minimum_size   = Vector2(0, int(36 * s))
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.add_theme_font_size_override("font_size", int(13 * s))
	var ps := _sb(bg, C_BORDER, 4, 8, 8, 6, 6)
	btn.add_theme_stylebox_override("normal",  ps)
	btn.add_theme_stylebox_override("hover",   ps)
	btn.add_theme_stylebox_override("pressed", ps)
	btn.add_theme_color_override("font_color", fg)
	btn.pressed.connect(cb)
	return btn

# Connects to the station's Python host (the same PythonState the quiz altar
# uses). is_connected() guards keep this idempotent across UI rebuilds.
func _ensure_program_host() -> void:
	if station == null or not station.has_method("get_program_host"):
		return
	var host: Node = station.call("get_program_host")
	if host == null:
		return
	if not host.is_connected("signal_print", _on_program_print):
		host.connect("signal_print", _on_program_print)
	if not host.is_connected("code_failed", _on_program_error):
		host.connect("code_failed", _on_program_error)
	if not host.is_connected("code_executed", _on_program_done):
		host.connect("code_executed", _on_program_done)

func _on_run_program() -> void:
	if station == null or _code_edit == null:
		return
	var code: String = _code_edit.text.strip_edges()
	if code.is_empty():
		return
	_ensure_program_host()
	if _prog_log != null:
		_prog_log.clear()
	station.call("run_program", code)
	_refresh_output()

func _on_clear_program() -> void:
	if _code_edit != null:
		_code_edit.text = ""
	_store_program_code()

func _store_program_code() -> void:
	if station != null and _code_edit != null:
		station.set("program_code", _code_edit.text)

# ── Item-name popup ───────────────────────────────────────────────
# Show the popup when the caret sits inside a name-argument function's
# parentheses (craft-style set_recipe / put_input / …); hide it otherwise.
func _caret_index() -> int:
	var idx: int = 0
	for ln in range(_code_edit.get_caret_line()):
		idx += _code_edit.get_line(ln).length() + 1
	return idx + _code_edit.get_caret_column()

func _on_program_text_changed() -> void:
	if _code_edit == null or _name_popup == null:
		return
	if NameComplete.name_arg_open(_code_edit.text, _caret_index()):
		_open_name_popup()
	else:
		_name_popup.hide()

func _open_name_popup() -> void:
	if _name_popup.visible:
		return
	_name_list.clear()
	for n in NameComplete.item_names():
		_name_list.add_item(str(n))
	var local: Vector2 = _code_edit.get_caret_draw_pos()
	_name_popup.position = Vector2i(_code_edit.get_screen_position() + local) + Vector2i(0, 22)
	_name_popup.popup()

func _on_name_item_selected(idx: int) -> void:
	var name: String = _name_list.get_item_text(idx)
	_code_edit.insert_text_at_caret("\"%s\"" % name)
	_name_popup.hide()
	_code_edit.grab_focus()

func _on_program_print(text: String) -> void:
	if _prog_log != null:
		_prog_log.append_text("[color=#aaddff]» %s[/color]\n" % text)

func _on_program_error(error: String) -> void:
	if _prog_log != null:
		_prog_log.append_text("[color=#ff8888]✗ %s[/color]\n" % error)

func _on_program_done() -> void:
	if _prog_log != null:
		_prog_log.append_text("[color=#88ffaa]✓ Program finished[/color]\n")
	_refresh_output()

# ── Input slot (single) ───────────────────────────────────────────
# Feed slot for automatic crafting: drag items in (or the Lua robot loads it
# with put_input()). craft_request() consumes from here before the inventory.
func _build_input_section(s: float) -> Control:
	var root := HBoxContainer.new()
	root.add_theme_constant_override("separation", int(10 * s))
	root.add_child(_lbl("INPUT", int(11 * s), C_MUTED))

	var slot_script: GDScript = load("res://scripts/station_input_slot.gd")
	_input_slot = slot_script.new()
	_input_slot.set("station", station)
	_input_slot.connect("changed", _on_input_slot_changed)
	root.add_child(_input_slot)

	_input_hint = _lbl("", int(11 * s), C_MUTED)
	_input_hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_input_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(_input_hint)

	_refresh_input()
	return root

func _on_station_state_changed() -> void:
	_refresh_input()
	_refresh_output()

func _on_input_slot_changed() -> void:
	_refresh_input()

func _refresh_input() -> void:
	if _input_slot != null and is_instance_valid(_input_slot):
		_input_slot.call("refresh")
	if _input_hint == null or station == null:
		return
	var stack: Dictionary = station.call("get_input_stack") if station.has_method("get_input_stack") else {}
	if stack.is_empty():
		_input_hint.text = "Empty — drag an ingredient here (or use put_input)"
	else:
		var item: ItemData = stack["data"] as ItemData
		_input_hint.text = "%s ×%d — feeds automatic crafting" % [item.item_name, int(stack["quantity"])]

# ── Output slot (single) ──────────────────────────────────────────
func _build_output_section(s: float) -> Control:
	var root := HBoxContainer.new()
	root.add_theme_constant_override("separation", int(10 * s))
	root.add_child(_lbl("OUTPUT", int(11 * s), C_MUTED))

	var slot_wrap := Control.new()
	slot_wrap.custom_minimum_size = Vector2(Global.ITEM_SLOT_SIZE * s, Global.ITEM_SLOT_SIZE * s)
	root.add_child(slot_wrap)

	_output_slot = Button.new()
	_output_slot.custom_minimum_size     = Vector2(Global.ITEM_SLOT_SIZE * s, Global.ITEM_SLOT_SIZE * s)
	_output_slot.expand_icon             = true
	_output_slot.icon_alignment          = HORIZONTAL_ALIGNMENT_CENTER
	_output_slot.vertical_icon_alignment = VERTICAL_ALIGNMENT_CENTER
	_output_slot.tooltip_text            = "Click to take the crafted items"
	_output_slot.pressed.connect(_on_take_output)
	var ps := _sb(C_TIP_BG, C_BORDER, 4, 4, 4, 4, 4)
	_output_slot.add_theme_stylebox_override("normal",  ps)
	_output_slot.add_theme_stylebox_override("hover",   ps)
	_output_slot.add_theme_stylebox_override("pressed", ps)
	slot_wrap.add_child(_output_slot)

	_output_count = Label.new()
	_output_count.add_theme_font_size_override("font_size", int(13 * s))
	_output_count.add_theme_color_override("font_color", C_EFFECT)
	_output_count.position = Vector2(Global.ITEM_SLOT_SIZE * s - 30 * s,
		Global.ITEM_SLOT_SIZE * s - 22 * s)
	slot_wrap.add_child(_output_count)

	_output_hint = _lbl("", int(11 * s), C_MUTED)
	_output_hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.add_child(_output_hint)

	_refresh_output()
	return root

func _refresh_output() -> void:
	if _output_slot == null or station == null:
		return
	var data = station.call("get_output_item")
	var qty: int = int(station.call("get_output_quantity"))
	if data == null or qty <= 0:
		_output_slot.icon     = null
		_output_slot.disabled = true
		if _output_count != null: _output_count.text = ""
		if _output_hint  != null: _output_hint.text  = "Empty — nothing crafted yet"
	else:
		var item: ItemData = data as ItemData
		_output_slot.icon     = item.icon
		_output_slot.disabled = false
		if _output_count != null: _output_count.text = "×%d" % qty
		if _output_hint  != null: _output_hint.text  = "%s ×%d — click to take" % [item.item_name, qty]
	_refresh_automation_selection()

func _on_take_output() -> void:
	if station == null:
		return
	var taken: int = int(station.call("take_output"))
	if _prog_log != null and taken > 0:
		_prog_log.append_text("[color=#88ffaa]Took %d item(s) into your inventory[/color]\n" % taken)
	_refresh_output()

func _build_detail(s: float) -> Control:
	var root := PanelContainer.new()
	var ps   := _sb(C_TIP_BG, C_BORDER, 4, int(14*s), int(14*s), int(14*s), int(14*s))
	root.add_theme_stylebox_override("panel", ps)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", int(8 * s))
	root.add_child(vbox)

	_detail_name = _lbl("", int(15 * s), C_TITLE)
	vbox.add_child(_detail_name)
	_div(vbox)
	vbox.add_child(_lbl("INGREDIENTS", int(11 * s), C_MUTED))
	_detail_ing1 = _build_icon_row(s)
	vbox.add_child(_detail_ing1)
	_detail_ing2 = _build_icon_row(s)
	vbox.add_child(_detail_ing2)
	_div(vbox)
	vbox.add_child(_lbl("RESULT", int(11 * s), C_MUTED))
	_detail_result = _build_icon_row(s)
	vbox.add_child(_detail_result)

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(spacer)

	_craft_btn = Button.new()
	_craft_btn.text                = "CRAFT"
	_craft_btn.custom_minimum_size = Vector2(0, int(40 * s))
	_craft_btn.add_theme_font_size_override("font_size", int(13 * s))
	_craft_btn.pressed.connect(_on_craft)
	vbox.add_child(_craft_btn)

	return root

# A single icon row: a material/result icon followed by a "have/needed" count
# (e.g. "3/10"). The icon is shown normally when the player has the material,
# darkened when they have none, and the count is RED when they don't have
# enough to craft (have < needed). Reused for both ingredients and the result.
func _build_icon_row(s: float) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", int(8 * s))
	row.add_theme_constant_override("alignment", BoxContainer.ALIGNMENT_CENTER)

	var icon := TextureRect.new()
	icon.custom_minimum_size = Vector2(26 * s, 26 * s)
	icon.stretch_mode         = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.expand_mode          = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	row.add_child(icon)

	var qty := Label.new()
	qty.add_theme_font_size_override("font_size", int(13 * s))
	row.add_child(qty)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	# Stash the refs on the row so the filler functions can use them.
	row.set_meta("icon", icon)
	row.set_meta("qty", qty)
	return row

# ── Helpers ───────────────────────────────────────────────────────
func _sb(bg: Color, border: Color, r: int,
		ml: int, mr: int, mt: int, mb: int) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color              = bg
	s.border_color          = border
	s.set_border_width_all(1)
	s.set_corner_radius_all(r)
	s.content_margin_left   = ml
	s.content_margin_right  = mr
	s.content_margin_top    = mt
	s.content_margin_bottom = mb
	return s

func _lbl(text: String, size: int, col: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	return l

func _div(parent: Node) -> void:
	var d := ColorRect.new()
	d.color               = C_DIVIDER
	d.custom_minimum_size = Vector2(0, 1)
	parent.add_child(d)

func _highlight_tab(cat: String) -> void:
	for c in _cat_btns:
		var btn: Button  = _cat_btns[c] as Button
		var active: bool = c == cat
		var ps := _sb(C_SEL if active else C_PANEL,
			C_TITLE if active else C_BORDER, 4, 8, 8, 6, 6)
		btn.add_theme_stylebox_override("normal",  ps)
		btn.add_theme_stylebox_override("hover",   ps)
		btn.add_theme_stylebox_override("pressed", ps)
		btn.add_theme_color_override("font_color", C_TITLE if active else C_MUTED)

# ── Crafting state ────────────────────────────────────────────────
enum CraftState { CAN_CRAFT, NO_MATS }

func _craft_state(recipe: CraftingRecipe) -> CraftState:
	var has_mats: bool = Global.count_item(recipe.ingredient_1) >= recipe.ingredient_1_quantity
	if recipe.ingredient_2 != null:
		has_mats = has_mats and \
			Global.count_item(recipe.ingredient_2) >= recipe.ingredient_2_quantity
	return CraftState.CAN_CRAFT if has_mats else CraftState.NO_MATS

# ── Category ──────────────────────────────────────────────────────
func _on_category(cat: String) -> void:
	_active_cat   = cat
	_selected_idx = -1
	_detail_panel.visible = false
	_highlight_tab(cat)
	_filter_and_refresh()

func _filter_and_refresh() -> void:
	_filtered = []
	_row_btns = []
	for r in _recipes:
		var recipe: CraftingRecipe = r as CraftingRecipe
		if recipe.category != _active_cat:
			continue
		# Station UI: only recipes that require a station
		if recipe.requires_station:
			_filtered.append(recipe)

	for child in _recipe_list.get_children():
		child.queue_free()

	if _filtered.is_empty():
		_recipe_list.add_child(_lbl("No recipes yet.", 12, C_MUTED))
		return

	var s: float = Global.ui_scale
	for i in range(_filtered.size()):
		var recipe: CraftingRecipe = _filtered[i] as CraftingRecipe
		var btn    := Button.new()
		btn.custom_minimum_size     = Vector2(Global.ITEM_SLOT_SIZE * s, Global.ITEM_SLOT_SIZE * s)
		btn.icon                    = recipe.result_item.icon
		btn.expand_icon             = true
		btn.icon_alignment          = HORIZONTAL_ALIGNMENT_CENTER
		btn.vertical_icon_alignment = VERTICAL_ALIGNMENT_CENTER
		btn.tooltip_text            = recipe.result_item.item_name
		var res: ItemData = recipe.result_item
		btn.mouse_entered.connect(func() -> void: Global.show_item_tooltip({"data": res, "quantity": 1}))
		btn.mouse_exited.connect(func() -> void: Global.hide_item_tooltip())
		var idx := i
		btn.pressed.connect(func() -> void: _on_select(idx))
		_recipe_list.add_child(btn)
		_row_btns.append(btn)

	_refresh_highlights()

func _refresh_highlights() -> void:
	for i in range(_row_btns.size()):
		if i >= _filtered.size():
			break
		var recipe: CraftingRecipe = _filtered[i] as CraftingRecipe
		var state: CraftState      = _craft_state(recipe)
		var btn: Button            = _row_btns[i] as Button
		var bg_col: Color
		var txt_col: Color
		var mod: float
		match state:
			CraftState.CAN_CRAFT:
				bg_col  = C_TIP_BG;  txt_col = C_TITLE;  mod = 1.0
			CraftState.NO_MATS:
				bg_col  = C_TIP_BG;  txt_col = C_MUTED;  mod = 0.55
		var ps := _sb(bg_col, C_BORDER, 4, 4, 4, 4, 4)
		btn.add_theme_stylebox_override("normal",  ps)
		btn.add_theme_stylebox_override("hover",   ps)
		btn.add_theme_stylebox_override("pressed", ps)
		btn.add_theme_color_override("font_color", txt_col)
		btn.modulate = Color(mod, mod, mod, 1.0)

	if _selected_idx >= 0 and _selected_idx < _filtered.size():
		_update_craft_btn(_filtered[_selected_idx] as CraftingRecipe)

# ── Recipe selection ──────────────────────────────────────────────
func _on_select(idx: int) -> void:
	_selected_idx        = idx
	var recipe: CraftingRecipe = _filtered[idx] as CraftingRecipe
	_detail_name.text    = recipe.result_item.item_name
	_fill_icon_row(_detail_ing1, recipe.ingredient_1, recipe.ingredient_1_quantity, true)
	if recipe.ingredient_2 != null:
		_fill_icon_row(_detail_ing2, recipe.ingredient_2, recipe.ingredient_2_quantity, true)
		_detail_ing2.visible = true
	else:
		_detail_ing2.visible = false
	# Result is a plain icon + "×quantity" count (always green, no shortage).
	_fill_icon_row(_detail_result, recipe.result_item, recipe.result_quantity, false)
	_detail_panel.visible = true
	_update_craft_btn(recipe)

# Fills an icon row: item icon + a count text. For ingredients (is_ingredient)
# the icon is shown at full colour when the player has the material and
# darkened when they have none, and the count is RED when the player doesn't
# have enough (have < needed); otherwise muted. For the result the icon stays
# full-colour and the count is always the "×quantity".
func _fill_icon_row(row: HBoxContainer, data: ItemData, needed: int, is_ingredient: bool) -> void:
	var icon := row.get_meta("icon") as TextureRect
	var qty  := row.get_meta("qty") as Label
	if icon == null or qty == null or data == null:
		return
	icon.texture = data.icon if data.icon != null else null
	var have: int = Global.count_item(data) if is_ingredient else needed
	icon.modulate = Color(0.35, 0.35, 0.35, 1.0) if (is_ingredient and have <= 0) else Color.WHITE
	if is_ingredient:
		qty.text = "%d/%d" % [have, needed]
		qty.add_theme_color_override("font_color",
			C_RED if have < needed else C_MUTED)
	else:
		qty.text = "×%d" % needed
		qty.add_theme_color_override("font_color", C_EFFECT)

func _update_craft_btn(recipe: CraftingRecipe) -> void:
	var state: CraftState = _craft_state(recipe)
	match state:
		CraftState.CAN_CRAFT:
			_craft_btn.text     = "CRAFT"
			_craft_btn.disabled = false
			var ps := _sb(C_CAN_CRAFT, C_BORDER, 4, 8, 8, 8, 8)
			_craft_btn.add_theme_stylebox_override("normal",  ps)
			_craft_btn.add_theme_stylebox_override("hover",   ps)
			_craft_btn.add_theme_color_override("font_color", Color(0.8, 1.0, 0.8, 1.0))
		CraftState.NO_MATS:
			_craft_btn.text     = "NOT ENOUGH MATERIALS"
			_craft_btn.disabled = true
			var ps := _sb(C_NO_MAT, C_BORDER, 4, 8, 8, 8, 8)
			_craft_btn.add_theme_stylebox_override("normal",  ps)
			_craft_btn.add_theme_color_override("font_color", Color(1.0, 0.7, 0.7, 1.0))

# ── Craft ─────────────────────────────────────────────────────────
func _on_craft() -> void:
	if _selected_idx < 0:
		return
	var recipe: CraftingRecipe = _filtered[_selected_idx] as CraftingRecipe
	if _craft_state(recipe) != CraftState.CAN_CRAFT:
		return
	for _i in range(recipe.ingredient_1_quantity):
		Global.remove_item(recipe.ingredient_1)
	if recipe.ingredient_2 != null:
		for _i in range(recipe.ingredient_2_quantity):
			Global.remove_item(recipe.ingredient_2)
	Global.add_item({"quantity": recipe.result_quantity, "data": recipe.result_item})
	Global.complete_mission("craft_item")
	# Check for specific craft missions
	var item_name: String = recipe.result_item.item_name.to_lower()
	if item_name.contains("sword"):
		Global.complete_mission("craft_sword")
		if item_name.contains("iron"):
			Global.complete_mission("craft_iron_sword")
		elif item_name.contains("diamond"):
			Global.complete_mission("craft_diamond_sword")
	if item_name.contains("pickaxe"):
		Global.complete_mission("craft_pickaxe")
		if item_name.contains("iron"):
			Global.complete_mission("craft_iron_pickaxe")
		elif item_name.contains("diamond"):
			Global.complete_mission("craft_diamond_pickaxe")
	if item_name.contains("axe"):
		if item_name.contains("iron"):
			Global.complete_mission("craft_iron_axe")
		elif item_name.contains("diamond"):
			Global.complete_mission("craft_diamond_axe")
	if item_name == "chest":
		Global.complete_mission("craft_chest")
	_update_craft_btn(recipe)
	_refresh_highlights()

# ── Show / Hide ───────────────────────────────────────────────────
func show_menu() -> void:
	visible = true
	Global.open_ui()

func hide_menu() -> void:
	if not visible:
		return
	# Keep the program text on the station so reopening restores it.
	_store_program_code()
	visible = false
	Global.close_ui()

# E (the "inventory" action) also closes the station menu here — unlike the
# inventory panel, this menu isn't a child of the player, so player.gd never
# sees the re-press to close it (any_ui_open() is already true while this is
# open, so its own E-toggle branch is a no-op) — it must close itself.
# The E branch is guarded by is_text_input_focused() so typing "e" into the
# PROGRAMMING tab's TextEdit doesn't close the panel. Escape is NOT gated: it
# isn't a typed character, so it stays a universal "close" key.
func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("escape"):
		get_viewport().set_input_as_handled()
		hide_menu()
	elif event.is_action_pressed("inventory") and not Global.is_text_input_focused():
		get_viewport().set_input_as_handled()
		hide_menu()
