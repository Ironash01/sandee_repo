extends Control

# ── Theme ─────────────────────────────────────────────────────────
const C_PANEL   := Color(0.08, 0.10, 0.20, 0.97)
const C_BORDER  := Color(0.22, 0.32, 0.58, 1.00)
const C_TITLE   := Color(0.80, 0.90, 1.00, 1.00)
const C_MUTED   := Color(0.55, 0.65, 0.85, 1.00)
const C_DIVIDER := Color(0.20, 0.28, 0.50, 1.00)
const C_EDITOR  := Color(0.05, 0.07, 0.13, 1.00)
const C_OUTPUT  := Color(0.04, 0.06, 0.10, 1.00)
const C_OK      := Color(0.15, 0.45, 0.20, 1.00)
const C_STOP    := Color(0.50, 0.20, 0.08, 1.00)
const C_ERR     := Color(0.45, 0.12, 0.12, 1.00)
const C_OVERLAY := Color(0.00, 0.00, 0.00, 0.50)

# ── Refs ──────────────────────────────────────────────────────────
var _code_edit: CodeEdit
var _output:    RichTextLabel
var _run_btn:   Button
var _stop_btn:  Button
var _body:      Control   # code + output view
var _encycl:    Control   # encyclopedia view
var _knowledge_box: VBoxContainer   # unlocked dungeon-knowledge entries
# entry id -> its keyword Label, so the "just learned" emphasis can target the
# right label when the encyclopedia is (re)opened. Rebuilt by _refresh_knowledge_section.
var _knowledge_keyword_labels: Dictionary = {}
# entry id -> its "NEW" badge, hidden once the emphasis has played.
var _knowledge_new_badges:     Dictionary = {}
var _lua_state: Node
var _running:   bool = false
var _build_slots: Array = []   # the 3 lua_build_slot.gd Controls

# ── Example snippets (shown in the SNIPPETS column) ───────────────
# Click one to drop its code into the editor. The first is BOUND TO A MISSION
# ("run_program") so it works as a tutorial: inserting it arms the mission, and
# a successful run completes it via the normal mission system.
const SNIPPETS: Array = [
	{"name": "1. Hello (tutorial)", "mission": "run_program",
		"code": "-- Tutorial: make the robot say something.\nprint(\"Hello, SandEE!\")"},
	{"name": "2. Auto work", "mission": "",
		"code": "-- Chop nearby trees, deliver the wood to a chest, then return home.\nauto_work()"},
	{"name": "3. Craft planks", "mission": "",
		"code": "-- Load 5 of the selected build-slot item into the station, then craft\n-- planks and collect them. Give the robot wood first (drag it into BUILD\n-- SLOTS, or withdraw/chop it).\nselect_block(0)\ninput_slot(5)\nset_recipe(\"Planks\")\ncraft(5)\ntake_output()"},
	{"name": "4. Build a wall", "mission": "",
		"code": "-- Place a wall of blocks from build slot 0.\nselect_block(0)\nbuild_line(0, 1, 5, 1)"},
	{"name": "5. Chest contents", "mission": "",
		"code": "-- Print what is inside the nearest chest.\nchest_contents()"},
]

# Mission armed by the tutorial snippet; completed on a successful run.
var _pending_mission: String = ""

# Player item panels shown INSIDE this editor (the full-screen overlay blocks
# the on-screen hotbar/inventory, so drag sources must live here).
const INVENTORY_SLOT_SCENE: PackedScene = preload("res://scenes/ui/InventorySlot.tscn")
const HOTBAR_SLOT_SCRIPT:   GDScript    = preload("res://scripts/hotbar_slot.gd")
const INV_COLUMNS: int = 4
var _inv_slots:    Array = []
var _hotbar_slots: Array = []

# ── Lifecycle ─────────────────────────────────────────────────────
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_build()
	call_deferred("_find_lua_state")
	call_deferred("_wire_build_palette")
	Global.ui_scale_changed.connect(_on_ui_scale)
	Global.knowledge_updated.connect(_refresh_knowledge_section)

# Connects the robot's build-palette signal (so slots update when the robot
# fills them itself) and paints the current contents. Deferred because the
# NPC parent is resolved by walking up the tree.
func _wire_build_palette() -> void:
	var npc: Node = _find_npc()
	if npc != null and npc.has_signal("build_palette_changed") \
			and not npc.is_connected("build_palette_changed", _on_build_palette_changed):
		npc.connect("build_palette_changed", _on_build_palette_changed)
	_refresh_build_palette()

func _on_ui_scale(_s: float) -> void:
	# The overworld (and this editor) is OFF-TREE while the player is inside a
	# cave/dungeon, but ui_scale_changed still fires on off-tree nodes — and
	# get_tree() is null there, so the await below would crash.
	if not is_inside_tree():
		return
	var saved_code: String = _code_edit.text if _code_edit != null else ""
	var was_visible: bool  = visible
	var was_encycl: bool   = _encycl != null and _encycl.visible
	for child in get_children():
		child.queue_free()
	await get_tree().process_frame
	_build()
	_code_edit.text = saved_code
	_sync_running_from_npc()
	_wire_build_palette()
	if was_encycl:
		_toggle_encyclopedia()
	visible = was_visible

# Walks up from this UI to the LuaNPC (the node exposing stop_work), so the
# lookup doesn't depend on a fixed parent depth.
func _find_npc() -> Node:
	var n: Node = get_parent()
	while n != null and not n.has_method("stop_work"):
		n = n.get_parent()
	return n

# Re-syncs the RUN/STOP buttons (and editor editability) with the robot's
# ACTUAL running state. _running only remembers what THIS panel session did,
# but closing the panel deliberately leaves the robot working — without this,
# reopening showed STOP disabled and a running robot could not be stopped.
func _sync_running_from_npc() -> void:
	var npc: Node = _find_npc()
	_running = npc != null and npc.has_method("is_working") and bool(npc.call("is_working"))
	_run_btn.disabled   = _running
	_stop_btn.disabled  = not _running
	_code_edit.editable = not _running

# Called by the LuaNPC when the player clicks the station.
func open_panel() -> void:
	visible = true
	_sync_running_from_npc()
	_refresh_build_palette()

func _find_lua_state() -> void:
	var npc: Node = _find_npc()
	if npc == null:
		_print_output("[color=#ff8888]LuaNPC not found.[/color]")
		return
	_lua_state = npc.get_node_or_null("LuaState")
	if _lua_state == null:
		_print_output("[color=#ff8888]LuaState not found on NPC.[/color]")
		return
	_lua_state.connect("signal_print",  _on_lua_print)
	_lua_state.connect("signal_move",   _on_lua_move)
	_lua_state.connect("code_executed", _on_code_executed)
	_lua_state.connect("code_failed",   _on_code_failed)
	_print_output("[color=#88ffaa]Robot ready. See Encyclopedia for available functions.[/color]")

# ── Build ─────────────────────────────────────────────────────────
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

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(i(1280, s), i(720, s))
	var ps := StyleBoxFlat.new()
	ps.bg_color = C_PANEL; ps.border_color = C_BORDER
	ps.set_border_width_all(1); ps.set_corner_radius_all(6)
	ps.content_margin_left = i(18, s); ps.content_margin_right  = i(18, s)
	ps.content_margin_top  = i(14, s); ps.content_margin_bottom = i(18, s)
	panel.add_theme_stylebox_override("panel", ps)
	center.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", i(10, s))
	panel.add_child(vbox)

	# ── Header ───────────────────────────────────────────────────
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", i(6, s))
	vbox.add_child(header)

	var icon := Label.new()
	icon.text = "🤖"
	icon.add_theme_font_size_override("font_size", i(20, s))
	header.add_child(icon)

	var title := Label.new()
	title.text = "  LUA — Code Editor"
	title.add_theme_font_size_override("font_size", i(16, s))
	title.add_theme_color_override("font_color", C_TITLE)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)

	var enc_btn := Button.new()
	enc_btn.text = "📖  Encyclopedia"
	enc_btn.add_theme_font_size_override("font_size", i(12, s))
	var ebs := StyleBoxFlat.new()
	ebs.bg_color = Color(0.12, 0.18, 0.36, 1.0)
	ebs.border_color = C_BORDER
	ebs.set_border_width_all(1); ebs.set_corner_radius_all(4)
	ebs.content_margin_left = i(10, s); ebs.content_margin_right  = i(10, s)
	ebs.content_margin_top  = i(4, s);  ebs.content_margin_bottom = i(4, s)
	enc_btn.add_theme_stylebox_override("normal",  ebs)
	enc_btn.add_theme_stylebox_override("hover",   ebs)
	enc_btn.add_theme_stylebox_override("pressed", ebs)
	enc_btn.add_theme_color_override("font_color", C_TITLE)
	enc_btn.pressed.connect(_toggle_encyclopedia)
	header.add_child(enc_btn)

	var close_btn := Button.new()
	close_btn.text = "✕"; close_btn.flat = true
	close_btn.add_theme_font_size_override("font_size", i(13, s))
	close_btn.add_theme_color_override("font_color", C_MUTED)
	close_btn.custom_minimum_size = Vector2(i(28, s), i(28, s))
	close_btn.pressed.connect(_close)
	header.add_child(close_btn)

	_divider(vbox)

	# ── Main body (code + output) ────────────────────────────────
	_body = _build_body(s)
	_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(_body)

	# ── Encyclopedia (hidden by default) ─────────────────────────
	_encycl = _build_encyclopedia(s)
	_encycl.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_encycl.visible = false
	vbox.add_child(_encycl)

# ── Body: code editor + output ────────────────────────────────────
func _build_body(s: float) -> Control:
	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", i(14, s))

	# Snippets column (left of the code editor).
	body.add_child(_build_snippets(s))

	# Player inventory + hotbar (drag items straight into the BUILD SLOTS).
	body.add_child(_build_player_items(s))

	# Code editor
	var ed_wrap := VBoxContainer.new()
	ed_wrap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ed_wrap.add_theme_constant_override("separation", i(6, s))
	body.add_child(ed_wrap)

	var ed_lbl := Label.new()
	ed_lbl.text = "CODE"
	ed_lbl.add_theme_font_size_override("font_size", i(11, s))
	ed_lbl.add_theme_color_override("font_color", C_MUTED)
	ed_wrap.add_child(ed_lbl)

	_code_edit = CodeEdit.new()
	_code_edit.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_code_edit.placeholder_text    = "-- write your Lua code here\ninteract()"
	_setup_code_editor()
	var es := StyleBoxFlat.new()
	es.bg_color = C_EDITOR; es.border_color = C_BORDER
	es.set_border_width_all(1); es.set_corner_radius_all(4)
	es.content_margin_left = i(8, s); es.content_margin_right  = i(8, s)
	es.content_margin_top  = i(8, s); es.content_margin_bottom = i(8, s)
	_code_edit.add_theme_stylebox_override("normal", es)
	_code_edit.add_theme_stylebox_override("focus",  es)
	_code_edit.add_theme_color_override("font_color", C_TITLE)
	_code_edit.add_theme_font_size_override("font_size", i(14, s))
	ed_wrap.add_child(_code_edit)

	# Build palette — the 3 slots the robot places FROM. Drag a block from the
	# inventory/hotbar into a slot to give it to the robot; the robot also
	# fills them itself (chopping wood, or withdraw() from a chest).
	ed_wrap.add_child(_build_palette_row(s))

	# Buttons: RUN  STOP  CLEAR
	var btn_row := HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", i(6, s))
	ed_wrap.add_child(btn_row)

	_run_btn = _make_btn("▶  RUN",  Color(0.8, 1.0, 0.8, 1.0), C_OK,  _run_code, s)
	_run_btn.tooltip_text = "Run the program on the robot."
	_run_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn_row.add_child(_run_btn)

	_stop_btn = _make_btn("■  STOP", Color(1.0, 0.8, 0.6, 1.0), C_STOP, _stop_code, s)
	_stop_btn.tooltip_text = "Stop the running program."
	_stop_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_stop_btn.disabled = true
	btn_row.add_child(_stop_btn)

	var clear_btn := _make_btn("✕ CLEAR", Color(1.0, 0.8, 0.8, 1.0), C_ERR, _clear_code, s)
	clear_btn.tooltip_text = "Clear the editor."
	btn_row.add_child(clear_btn)

	# Output panel
	var out_wrap := VBoxContainer.new()
	out_wrap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	out_wrap.add_theme_constant_override("separation", i(6, s))
	body.add_child(out_wrap)

	var out_lbl := Label.new()
	out_lbl.text = "OUTPUT"
	out_lbl.add_theme_font_size_override("font_size", i(11, s))
	out_lbl.add_theme_color_override("font_color", C_MUTED)
	out_wrap.add_child(out_lbl)

	var out_panel := PanelContainer.new()
	out_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var op := StyleBoxFlat.new()
	op.bg_color = C_OUTPUT; op.border_color = C_BORDER
	op.set_border_width_all(1); op.set_corner_radius_all(4)
	op.content_margin_left = i(8, s); op.content_margin_right  = i(8, s)
	op.content_margin_top  = i(8, s); op.content_margin_bottom = i(8, s)
	out_panel.add_theme_stylebox_override("panel", op)
	out_wrap.add_child(out_panel)

	var scroll := ScrollContainer.new()
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	out_panel.add_child(scroll)

	_output = RichTextLabel.new()
	_output.bbcode_enabled        = true
	_output.scroll_following      = true
	_output.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_output.size_flags_vertical   = Control.SIZE_EXPAND_FILL
	_output.add_theme_font_size_override("font_size", i(13, s))
	_output.add_theme_color_override("default_color", C_TITLE)
	scroll.add_child(_output)

	return body

# ── Snippets column ───────────────────────────────────────────────
# A narrow column of example programs. Clicking one replaces the editor's
# contents with that example (the tutorial one also arms its mission).
func _build_snippets(s: float) -> Control:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", i(6, s))
	col.custom_minimum_size = Vector2(i(160, s), 0)

	var lbl := Label.new()
	lbl.text = "SNIPPETS"
	lbl.add_theme_font_size_override("font_size", i(11, s))
	lbl.add_theme_color_override("font_color", C_MUTED)
	col.add_child(lbl)

	var hint := Label.new()
	hint.text = "Click to load an example into the editor."
	hint.add_theme_font_size_override("font_size", i(9, s))
	hint.add_theme_color_override("font_color", C_MUTED)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(hint)

	for i in range(SNIPPETS.size()):
		var snip: Dictionary = SNIPPETS[i]
		var btn := Button.new()
		btn.text = str(snip["name"])
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.add_theme_font_size_override("font_size", i(11, s))
		btn.custom_minimum_size = Vector2(0, i(30, s))
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.12, 0.16, 0.32, 1.0); sb.border_color = C_BORDER
		sb.set_border_width_all(1); sb.set_corner_radius_all(4)
		sb.content_margin_left = i(8, s); sb.content_margin_right = i(8, s)
		btn.add_theme_stylebox_override("normal",  sb)
		btn.add_theme_stylebox_override("hover",   sb)
		btn.add_theme_stylebox_override("pressed", sb)
		btn.add_theme_color_override("font_color", C_TITLE)
		btn.tooltip_text = str(snip["code"])
		btn.pressed.connect(_on_snippet_pressed.bind(i))
		col.add_child(btn)
	return col

func _on_snippet_pressed(index: int) -> void:
	if index < 0 or index >= SNIPPETS.size():
		return
	var snip: Dictionary = SNIPPETS[index]
	# The example is placed in the editor as-is; _run_code prepends the helper
	# preamble at run time, so examples that call chop_trees()/auto_work() etc.
	# still resolve.
	_code_edit.text = str(snip["code"])
	var mission: String = str(snip.get("mission", ""))
	if not mission.is_empty():
		_pending_mission = mission
		_print_output("[color=#88ffaa]Tutorial loaded — run it to complete \"%s\".[/color]" % mission)
	else:
		_pending_mission = ""
	_print_output("[color=#aaddff]Loaded snippet: %s[/color]" % str(snip["name"]))

# ── Player items column (inventory + hotbar) ──────────────────────
# Both are DRAG SOURCES for the build slots. The editor's full-screen overlay
# covers the in-world hotbar, so a copy lives here too. Slots are the same
# controls the inventory/hotbar use, so their drag data ("inventory"/"hotbar")
# is exactly what lua_build_slot.gd accepts.
func _build_player_items(s: float) -> Control:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", i(6, s))
	col.custom_minimum_size = Vector2(i(INV_COLUMNS * (Global.ITEM_SLOT_SIZE + 12) + 8, s), 0)

	var inv_lbl := Label.new()
	inv_lbl.text = "INVENTORY"
	inv_lbl.add_theme_font_size_override("font_size", i(11, s))
	inv_lbl.add_theme_color_override("font_color", C_MUTED)
	col.add_child(inv_lbl)

	var inv_hint := Label.new()
	inv_hint.text = "Drag items into the BUILD SLOTS."
	inv_hint.add_theme_font_size_override("font_size", i(9, s))
	inv_hint.add_theme_color_override("font_color", C_MUTED)
	inv_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(inv_hint)

	var grid := GridContainer.new()
	grid.columns = INV_COLUMNS
	grid.add_theme_constant_override("h_separation", i(6, s))
	grid.add_theme_constant_override("v_separation", i(6, s))
	col.add_child(grid)
	_inv_slots.clear()
	for idx in range(Global.INVENTORY_SIZE):
		var slot: Control = INVENTORY_SLOT_SCENE.instantiate()
		slot.set("slot_index", idx)
		grid.add_child(slot)
		_inv_slots.append(slot)

	var hb_lbl := Label.new()
	hb_lbl.text = "HOTBAR"
	hb_lbl.add_theme_font_size_override("font_size", i(11, s))
	hb_lbl.add_theme_color_override("font_color", C_MUTED)
	col.add_child(hb_lbl)

	var hb_row := HBoxContainer.new()
	hb_row.add_theme_constant_override("separation", i(4, s))
	col.add_child(hb_row)
	_hotbar_slots.clear()
	for idx in range(Global.HOTBAR_SIZE):
		var tslot := TextureRect.new()
		tslot.set_script(HOTBAR_SLOT_SCRIPT)
		tslot.set("slot_index", idx)
		tslot.custom_minimum_size = Vector2(i(34, s), i(34, s))
		tslot.expand_mode         = TextureRect.EXPAND_IGNORE_SIZE
		tslot.stretch_mode        = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		var bg := ColorRect.new()
		bg.color = Color(0.11, 0.15, 0.26, 1.0)
		bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bg.set_anchors_preset(Control.PRESET_FULL_RECT)
		tslot.add_child(bg)
		tslot.move_child(bg, 0)
		hb_row.add_child(tslot)
		_hotbar_slots.append(tslot)

	if not Global.Inventory_updated.is_connected(_refresh_player_items):
		Global.Inventory_updated.connect(_refresh_player_items)
	if not Global.Hotbar_updated.is_connected(_refresh_player_items):
		Global.Hotbar_updated.connect(_refresh_player_items)
	# Deferred: the freshly instantiated slots build their child visuals in
	# _ready, which hasn't run at the point this column is assembled.
	_refresh_player_items.call_deferred()
	return col

func _refresh_player_items() -> void:
	for i in range(_inv_slots.size()):
		var slot: Control = _inv_slots[i]
		if not is_instance_valid(slot):
			continue
		var item: Variant = Global.Inventory[i] if i < Global.Inventory.size() else null
		if item == null:
			slot.call("set_empty")
		else:
			slot.call("set_item", item)
	for i in range(_hotbar_slots.size()):
		var slot: TextureRect = _hotbar_slots[i]
		if not is_instance_valid(slot):
			continue
		var item: Variant = Global.Hotbar[i] if i < Global.Hotbar.size() else null
		slot.texture = ((item as Dictionary)["data"] as ItemData).icon if item != null else null

# ── Build palette row (robot's 3 block slots) ─────────────────────
func _build_palette_row(s: float) -> Control:
	var row := VBoxContainer.new()
	row.add_theme_constant_override("separation", i(4, s))

	var lbl := Label.new()
	lbl.text = "BUILD SLOTS  (drag blocks in — the robot places from these)"
	lbl.add_theme_font_size_override("font_size", i(10, s))
	lbl.add_theme_color_override("font_color", C_MUTED)
	row.add_child(lbl)

	var slots := HBoxContainer.new()
	slots.add_theme_constant_override("separation", i(6, s))
	row.add_child(slots)

	_build_slots.clear()
	var slot_script: GDScript = load("res://scripts/lua_build_slot.gd")
	for i in range(3):
		var slot: Control = slot_script.new()
		slot.set("slot_index", i)
		slot.connect("slot_changed", _on_build_slot_changed)
		slots.add_child(slot)
		_build_slots.append(slot)
	return row

func _on_build_slot_changed() -> void:
	_refresh_build_palette()

# Pushes the robot's current palette contents into the slot visuals.
func _refresh_build_palette() -> void:
	var npc: Node = _find_npc()
	for slot in _build_slots:
		if is_instance_valid(slot):
			slot.set("_npc", npc)
			slot.call("refresh")

func _on_build_palette_changed() -> void:
	_refresh_build_palette()

# ── Encyclopedia ──────────────────────────────────────────────────
# Two clearly separated groups (see APIReference):
#   • CUSTOM FUNCTIONS — THIS GAME  (robot + station APIs), split by language
#   • BUILT-IN FUNCTIONS — LANGUAGE (standard library), split by language
# so the game's own API is never mixed in with the language's built-ins.
func _build_encyclopedia(s: float) -> Control:
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", i(10, s))

	var hdr := Label.new()
	hdr.text = "FUNCTION REFERENCE"
	hdr.add_theme_font_size_override("font_size", i(14, s))
	hdr.add_theme_color_override("font_color", C_TITLE)
	root.add_child(hdr)

	_divider(root)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(scroll)

	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", i(14, s))
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)

	for group in APIReference.groups():
		_enc_group_header(list, str(group["title"]), str(group["note"]), s)
		for lang in group["languages"]:
			_enc_section(list, str(lang["name"]), s)
			for e in lang["entries"]:
				_enc_entry(list, str(e["sig"]), str(e["desc"]), s)
		_divider(list)

	_enc_section(list, "DUNGEON KNOWLEDGE (unlocked)", s)
	_knowledge_box = VBoxContainer.new()
	_knowledge_box.add_theme_constant_override("separation", i(14, s))
	list.add_child(_knowledge_box)
	_refresh_knowledge_section()

	return root

# Big group banner (CUSTOM vs BUILT-IN) — brighter than a language heading so
# the two top-level categories read as distinct at a glance.
func _enc_group_header(parent: Node, text: String, note: String, s: float) -> void:
	var title := Label.new()
	title.text = text
	title.add_theme_font_size_override("font_size", i(13, s))
	title.add_theme_color_override("font_color", C_TITLE)
	parent.add_child(title)
	if not note.is_empty():
		var sub := Label.new()
		sub.text = note
		sub.add_theme_font_size_override("font_size", i(11, s))
		sub.add_theme_color_override("font_color", C_MUTED)
		sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		parent.add_child(sub)

func _refresh_knowledge_section() -> void:
	if _knowledge_box == null:
		return
	for child in _knowledge_box.get_children().duplicate():
		child.free()
	_knowledge_keyword_labels.clear()
	_knowledge_new_badges.clear()
	var entries := Global.all_learned_entries()
	if entries.is_empty():
		var none := Label.new()
		none.text = "None yet — find a dungeon knowledge altar to unlock concepts here."
		none.add_theme_font_size_override("font_size", i(12, Global.ui_scale))
		none.add_theme_color_override("font_color", C_MUTED)
		none.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_knowledge_box.add_child(none)
		return
	for e in entries:
		_enc_knowledge_entry(_knowledge_box, e, Global.ui_scale)

# A learned-entry block: entry name (+ optional NEW badge) and description. The
# entry name doubles as the keyword label targeted by the first-time emphasis
# (see _emphasize_unseen_knowledge). The animation is NOT played here — the
# section is built while hidden, so playing it now would run off-screen; it's
# deferred to _toggle_encyclopedia when the view actually becomes visible.
func _enc_knowledge_entry(parent: Node, e: KnowledgeEntry, s: float) -> void:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", i(4, s))
	parent.add_child(box)

	var name_row := HBoxContainer.new()
	name_row.add_theme_constant_override("separation", i(6, s))
	box.add_child(name_row)

	var name_lbl := Label.new()
	name_lbl.text = e.entry_name
	name_lbl.add_theme_font_size_override("font_size", i(14, s))
	name_lbl.add_theme_color_override("font_color", Color(0.55, 0.90, 1.00, 1.0))
	name_row.add_child(name_lbl)

	var unseen: bool = Global.is_entry_unseen(e)
	if unseen:
		var badge := Label.new()
		badge.text = "NEW"
		badge.add_theme_font_size_override("font_size", i(9, s))
		badge.add_theme_color_override("font_color", Global.KEYWORD_FLASH)
		name_row.add_child(badge)
		_knowledge_new_badges[e.id()] = badge

	var desc_lbl := Label.new()
	desc_lbl.text = e.description
	desc_lbl.add_theme_font_size_override("font_size", i(12, s))
	desc_lbl.add_theme_color_override("font_color", C_MUTED)
	desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(desc_lbl)

	if unseen:
		_knowledge_keyword_labels[e.id()] = name_lbl

# Plays the emphasis for every entry learned since it was last viewed, then
# marks them seen (and hides their NEW badges). Called when the encyclopedia
# becomes visible so the tween runs on laid-out, on-screen labels.
func _emphasize_unseen_knowledge() -> void:
	if _knowledge_keyword_labels.is_empty():
		return
	for e in Global.all_learned_entries():
		var lbl: Label = _knowledge_keyword_labels.get(e.id()) as Label
		if lbl == null or not is_instance_valid(lbl):
			continue
		Global.emphasize_keyword(lbl, lbl.get_theme_color("font_color"))
		var badge: Label = _knowledge_new_badges.get(e.id()) as Label
		if badge != null and is_instance_valid(badge):
			badge.visible = false
		Global.mark_entry_seen(e)
	_knowledge_keyword_labels.clear()
	_knowledge_new_badges.clear()

func _enc_section(parent: Node, text: String, s: float) -> void:
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", i(10, s))
	lbl.add_theme_color_override("font_color", C_MUTED)
	parent.add_child(lbl)

func _enc_entry(parent: Node, sig: String, desc: String, s: float) -> void:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", i(4, s))
	parent.add_child(box)

	var sig_lbl := Label.new()
	sig_lbl.text = sig
	sig_lbl.add_theme_font_size_override("font_size", i(14, s))
	sig_lbl.add_theme_color_override("font_color", Color(0.55, 0.90, 1.00, 1.0))
	box.add_child(sig_lbl)

	var desc_lbl := Label.new()
	desc_lbl.text = desc
	desc_lbl.add_theme_font_size_override("font_size", i(12, s))
	desc_lbl.add_theme_color_override("font_color", C_MUTED)
	desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(desc_lbl)

# ── Actions ───────────────────────────────────────────────────────
func _toggle_encyclopedia() -> void:
	_encycl.visible = not _encycl.visible
	_body.visible   = not _encycl.visible
	if _encycl.visible:
		# Rebuild so any entry learned since the last look is present, then
		# (after a frame, so labels are laid out) play the first-time emphasis.
		_refresh_knowledge_section()
		_emphasize_unseen_knowledge.call_deferred()

# ── Code editor: syntax highlight + autocomplete ──────────────────
# Custom API names + Lua keywords are highlighted, and the completion popup is
# built from APIReference (custom + built-in). A light lint warns about
# `name(` calls that aren't in the API before the program is even run.
var _completion_filled: bool = false

func _setup_code_editor() -> void:
	var ce := _code_edit
	var hl := CodeHighlighter.new()
	for kw in ["function", "end", "if", "then", "elseif", "else", "for", "while",
			"do", "repeat", "until", "return", "local", "and", "or", "not", "in",
			"break", "true", "false", "nil"]:
		hl.add_keyword_color(kw, Color(0.85, 0.55, 0.95))
	for fn in _api_function_names():
		hl.add_keyword_color(fn, Color(0.45, 0.85, 1.0))
	ce.syntax_highlighter = hl
	ce.set_code_completion_enabled(true)
	ce.code_completion_requested.connect(_on_code_completion_requested)

# Every callable name from the API reference (custom + built-in Lua), deduped.
func _api_function_names() -> PackedStringArray:
	var seen: Dictionary = {}
	var out := PackedStringArray()
	for group in APIReference.groups():
		for lang in (group["languages"] as Array):
			if not str(lang["name"]).begins_with("LUA"):
				continue
			for e in (lang["entries"] as Array):
				var name: String = str(e["sig"]).split("(")[0].split("/")[0].strip_edges()
				if name.is_empty() or name.contains(" ") or seen.has(name):
					continue
				seen[name] = true
				out.append(name)
	return out

func _on_code_completion_requested() -> void:
	var ce := _code_edit
	if not _completion_filled:
		_completion_filled = true
		for name in _api_function_names():
			ce.add_code_completion_option(CodeEdit.KIND_FUNCTION, name, name + "(", Color(0.6, 0.85, 1.0))
	ce.update_code_completion_options(true)

# Warn (don't block) about `name(` calls that aren't in the API, so a typo is
# visible before running. Real syntax/runtime errors still come from Lua.
func _lint(code: String) -> void:
	var allowed: Dictionary = {}
	for n in _api_function_names():
		allowed[n] = true
	var re := RegEx.new()
	re.compile("([A-Za-z_][A-Za-z0-9_]*)\\s*\\(")
	var unknown: Dictionary = {}
	for m in re.search_all(code):
		var name: String = m.get_string(1)
		if allowed.has(name):
			continue
		if name in ["if", "for", "while", "function", "return", "and", "or", "not"]:
			continue
		unknown[name] = true
	if not unknown.is_empty():
		_print_output("[color=#ffcc66]Warning: unknown function(s): %s — see the Encyclopedia.[/color]" % ", ".join(PackedStringArray(unknown.keys())))

func _run_code() -> void:
	if _lua_state == null:
		_print_output("[color=#ff8888]No LuaState connected.[/color]")
		return
	var code: String = _code_edit.text.strip_edges()
	if code.is_empty():
		return
	_lint(code)

	var preamble: String = """
-- Built-in helpers
function chop_trees(radius)
    move(radius or 20, -1)
    interact()
end
function auto_work()
    move(0, -2)
    interact()
end
function deposit_chest()
    move(0, -4)
    interact()
end
function return_to_spawn()
    move(0, -3)
    interact()
end
function chest_contents()
    move(0, -5)
    interact()
end
function craft_example()
    -- Chops trees, delivers the wood, then turns it into 2 chests at the
    -- nearest Crafting Station. 2 chests = 20 planks = 5 wood, so it only
    -- ever requests 5 planks-crafts and 2 chest-crafts -- never more.
    chop_trees()
    deposit_chest()
    return_to_spawn()
	set_recipe("Planks")
    craft(5)
    take_output()
	set_recipe("Chest")
    craft(2)
    take_output()
end

-- ── BUILD HELPERS ────────────────────────────────────────────────
-- The robot places from its 3 build slots. select_block(i) picks the slot
-- (0, 1 or 2); place_item(dx, dy) places one block at a tile offset from the
-- robot; place_at(x, y) uses absolute tile coords. Fill the slots by dragging
-- blocks in, by chopping (wood), or with withdraw("Wood", 10) from a chest.
-- Each place_* call is one block, played out a frame at a time, so a loop of
-- 40 calls visibly builds over ~40 frames.

-- Gap-free straight line between two offsets (Bresenham). A plain y = m*x
-- would skip tiles on diagonals; this steps one tile at a time.
function build_line(x0, y0, x1, y1)
    local dx = math.abs(x1 - x0)
    local dy = -math.abs(y1 - y0)
    local sx = (x0 < x1) and 1 or -1
    local sy = (y0 < y1) and 1 or -1
    local err = dx + dy
    while true do
        place_item(x0, y0)
        if x0 == x1 and y0 == y1 then break end
        local e2 = 2 * err
        if e2 >= dy then err = err + dy; x0 = x0 + sx end
        if e2 <= dx then err = err + dx; y0 = y0 + sy end
    end
end

-- Rectangle: w by h tiles, top-left at offset (x0, y0). filled = solid slab,
-- otherwise just the border.
function build_rect(x0, y0, w, h, filled)
    for x = 0, w - 1 do
        for y = 0, h - 1 do
            if filled or x == 0 or y == 0 or x == w - 1 or y == h - 1 then
                place_item(x0 + x, y0 + y)
            end
        end
    end
end

-- Circle centred on the robot: filled disc (filled = true) or outline.
-- Uses the integer distance test x*x + y*y <= r*r, so no trig and no gaps.
function build_circle(r, filled)
    for x = -r, r do
        for y = -r, r do
            local d2 = x * x + y * y
            if d2 <= r * r and (filled or d2 > (r - 1) * (r - 1)) then
                place_item(x, y)
            end
        end
    end
end

-- Hollow ring of radius r.
function build_ring(r)
    build_circle(r, false)
end

-- Archimedean spiral r = a + b*angle, out to radius r over `turns` turns.
function build_spiral(r, turns)
    local total = turns * 2 * math.pi
    local steps = math.floor(r * turns * 10)
    for i = 0, steps do
        local ang = total * (i / steps)
        local rad = r * (ang / total)
        place_item(math.floor(math.cos(ang) * rad + 0.5), math.floor(math.sin(ang) * rad + 0.5))
    end
end

-- Sine-wave fence: `len` tiles long, `amp` tiles tall.
function build_wave(len, amp)
    for x = 0, len - 1 do
        place_item(x, math.floor(amp * math.sin(x * 0.5) + 0.5))
    end
end

-- Diagonal staircase of n steps.
function build_stairs(n)
    for i = 0, n - 1 do
        place_item(i, i)
    end
end
"""
	_lua_state.set("code", preamble + code)
	_lua_state.call("run_code")

	# Unpause so the robot can move, but keep the panel open
	_running = true
	get_tree().paused  = false
	_run_btn.disabled  = true
	_stop_btn.disabled = false
	_code_edit.editable = false
	_print_output("[color=#88ffaa]▶ Running...[/color]")

func _stop_code() -> void:
	var npc: Node = _find_npc()
	if npc != null:
		npc.call("stop_work")

	_running = false
	get_tree().paused   = true   # re-pause for editing
	_run_btn.disabled   = false
	_stop_btn.disabled  = true
	_code_edit.editable = true
	_print_output("[color=#ffaa44]■ Stopped.[/color]")

func _clear_code() -> void:
	_code_edit.text = ""

func _close() -> void:
	# Closing does NOT stop the robot — it keeps running — so re-sync rather
	# than forcing STOP disabled; open_panel() re-syncs again on reopen.
	Global.close_ui()
	visible = false
	_sync_running_from_npc()

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("escape") and visible:
		get_viewport().set_input_as_handled()
		_close()

# ── Lua signal handlers ───────────────────────────────────────────
func _on_lua_print(text: String) -> void:
	_print_output("[color=#aaddff]» %s[/color]" % text)

func _on_lua_move(vec: Vector2) -> void:
	_print_output("[color=#88ffaa]move → (%.1f, %.1f)[/color]" % [vec.x, vec.y])

func _on_code_executed() -> void:
	_print_output("[color=#88ffaa]✓ Code executed[/color]")
	# Tutorial snippet ran cleanly → complete its mission (idempotent).
	if not _pending_mission.is_empty():
		Global.complete_mission(_pending_mission)
		_print_output("[color=#ffd76a]★ Tutorial complete![/color]")
		_pending_mission = ""

func _on_code_failed(error: String) -> void:
	_print_output("[color=#ff8888]✗ %s[/color]" % error)
	# Re-enable editing on error
	if _running:
		_running = false
		get_tree().paused   = true
		_run_btn.disabled   = false
		_stop_btn.disabled  = true
		_code_edit.editable = true

func _print_output(line: String) -> void:
	if _output == null: return
	_output.append_text(line + "\n")

# ── Helpers ───────────────────────────────────────────────────────
func i(base: int, s: float) -> int: return int(base * s)

func _make_btn(label: String, font_col: Color, bg: Color, cb: Callable, s: float) -> Button:
	var btn := Button.new()
	btn.text = label
	btn.custom_minimum_size = Vector2(0, i(38, s))
	btn.add_theme_font_size_override("font_size", i(13, s))
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg; sb.border_color = C_BORDER
	sb.set_border_width_all(1); sb.set_corner_radius_all(4)
	sb.content_margin_top = i(6, s); sb.content_margin_bottom = i(6, s)
	btn.add_theme_stylebox_override("normal",  sb)
	btn.add_theme_stylebox_override("hover",   sb)
	btn.add_theme_stylebox_override("pressed", sb)
	btn.add_theme_color_override("font_color", font_col)
	btn.pressed.connect(cb)
	return btn

func _divider(parent: Node) -> void:
	var d := ColorRect.new()
	d.color = C_DIVIDER; d.custom_minimum_size = Vector2(0, 1)
	parent.add_child(d)
