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

# LuaNPC owns the rename cap; the editor field uses the same constant so the UI
# and rename() can never drift apart.
const LUA_NPC_SCRIPT: GDScript = preload("res://scripts/lua_npc.gd")
const CODE_SAFETY: GDScript = preload("res://scripts/code_safety.gd")

# ── Refs ──────────────────────────────────────────────────────────
var _code_edit: CodeEdit
var _output:    RichTextLabel
var _run_btn:   Button
var _stop_btn:  Button
var _name_edit: LineEdit   # rename field (reflects in the robot label + status HUD)
var _enc_btn: Button = null # explicit CODE / ENCYCLOPEDIA toggle
var _tool_slot: Control = null      # the LUA's tool slot (lua_tool_slot.gd)
var _tabs: TabContainer = null      # CODE / INVENTORY / ENCYCLOPEDIA pages
var _combat_btn: Button = null      # combat-mode toggle
# NOTE: there is deliberately no per-station TERMINATE button. Terminating a
# LUA is a menu action (pause menu -> LUA Management) so the player has to pick
# the specific LUA from the active list.
var _body:      Control   # the CODE / INVENTORY / ENCYCLOPEDIA TabContainer
var _encycl:    Control   # the ENCYCLOPEDIA tab page
var _panel_scroll: ScrollContainer = null  # keyboard-aware scroll area
var _panel_center: CenterContainer = null   # keyboard-aware centring area
var _enc_func_box: VBoxContainer   # the four Programming Encyclopedia sections
# Section id -> expanded, kept across refreshes so a knowledge update or a UI
# scale change never collapses what the player opened.
var _enc_open: Dictionary = {}
var _knowledge_box: VBoxContainer   # unlocked dungeon-knowledge entries
# entry id -> its keyword Label, so the "just learned" emphasis can target the
# right label when the encyclopedia is (re)opened. Rebuilt by _refresh_knowledge_section.
var _knowledge_keyword_labels: Dictionary = {}
# entry id -> its "NEW" badge, hidden once the emphasis has played.
var _knowledge_new_badges:     Dictionary = {}
var _lua_state: Node
var _running:   bool = false
# Tutorial verification: true only after the current run finishes cleanly.
var _last_run_ok: bool = false
# True between RUN and the settle check: the chunk has finished but its queued
# signals may not have started a job yet, so _process must not re-pause early.
var _awaiting_settle: bool = false
var _build_slots: Array = []   # the 3 lua_build_slot.gd Controls

# ── Example programs (shown in the TEMPLATES column) ──────────────
# Click one to drop its code into the editor. The first is BOUND TO A MISSION
# ("run_program") so it works as a tutorial: inserting it arms the mission, and
# a successful run completes it via the normal mission system.
const SNIPPETS: Array = [
	{"name": "1. Build a line (tutorial)", "mission": "",
		"code": "-- Automatica can build for you. This uses the 32 Wood in BUILD SLOT 1.\nselect_block(0)\nbuild_line(-15, -8, 16, -8)"},
	{"name": "2. Combat mode (tutorial)", "mission": "",
		"code": "-- combat_mode(true) follows and fights; combat_mode(false) returns to the blue station robot.\ncombat_mode(true)"},
	{"name": "3. Auto work", "mission": "",
		"code": "-- Chop nearby trees, deliver the wood to a chest, then return home.\nauto_work()"},
	{"name": "4. Craft planks", "mission": "",
		"code": "-- Load 5 of the selected build-slot item into the station, then craft\n-- planks and collect them. Give the robot wood first (drag it into BUILD\n-- SLOTS, or withdraw/chop it).\nselect_block(0)\ninput_slot(5)\nset_recipe(\"Planks\")\ncraft(5)\ntake_output()"},
	{"name": "5. Build a wall", "mission": "",
		"code": "-- Place a wall of blocks from build slot 0.\nselect_block(0)\nbuild_line(0, 1, 5, 1)"},
	{"name": "6. Chest contents", "mission": "",
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

# The built-in Automatica helper library (prepended to every Lua run and
# shared with the QA suite). Keep every helper listed in APIReference.
const LUA_PREAMBLE: String = """
-- Built-in helpers
-- place_item() is the no-offset form of place_item(dx, dy).
local __place_item = place_item
function place_item(dx, dy)
    __place_item(dx or 0, dy or 0)
end

-- mine() now uses the Automatica's own work radius. The Rust bridge still
-- accepts a legacy second argument for compatibility; GDScript ignores it.
local __mine = mine
function mine(name)
	__mine(name, 0)
end

function chop_trees(radius)
	move(radius or 20, -1000001)
	interact()
end
function auto_work()
	move(0, -1000002)
	interact()
end
function deposit_chest()
	move(0, -1000004)
	interact()
end
function return_to_spawn()
	move(0, -1000003)
	interact()
end
function chest_contents()
	move(0, -1000005)
	interact()
end
function craft_example()
	-- Minimal station example. The station must already have the recipe's
	-- ingredients (or a robot/player must have loaded its input slot).
	-- Copy these three calls into your own program and change the recipe.
	set_recipe("Planks")
	craft(1)
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
	x0, y0, x1, y1 = x0 or 0, y0 or 0, x1 or 0, y1 or 0
	move(0, -1000006)
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
	x0, y0 = x0 or 0, y0 or 0
	w, h = w or 1, h or 1
	filled = filled or false
	move(0, filled and -1000012 or -1000007)
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
	r = r or 0
	filled = filled or false
	if r <= 0 then return end
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
	move(0, -1000008)
	build_circle(r, false)
end

-- Archimedean spiral r = a + b*angle, out to radius r over `turns` turns.
function build_spiral(r, turns)
	r, turns = r or 1, turns or 1
	if r <= 0 or turns <= 0 then return end
	move(0, -1000011)
	local total = turns * 2 * math.pi
	local steps = math.max(1, math.floor(r * turns * 10))
	for i = 0, steps do
		local ang = total * (i / steps)
		local rad = r * (ang / total)
		place_item(math.floor(math.cos(ang) * rad + 0.5), math.floor(math.sin(ang) * rad + 0.5))
	end
end

-- Sine-wave fence: `len` tiles long, `amp` tiles tall.
function build_wave(len, amp)
	len, amp = len or 1, amp or 1
	move(0, -1000009)
	for x = 0, len - 1 do
		place_item(x, math.floor(amp * math.sin(x * 0.5) + 0.5))
	end
end

-- Diagonal staircase of n steps.
function build_stairs(n)
	n = n or 1
	move(0, -1000010)
	for i = 0, n - 1 do
		place_item(i, i)
	end
end
"""

# ── Lifecycle ─────────────────────────────────────────────────────
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_build()
	call_deferred("_find_lua_state")
	call_deferred("_wire_build_palette")
	Global.ui_scale_changed.connect(_on_ui_scale)
	Global.knowledge_updated.connect(_on_knowledge_updated)

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
	var was_tab: String = "CODE"
	if _tabs != null and is_instance_valid(_tabs) and _tabs.get_tab_count() > 0:
		was_tab = _tabs.get_tab_title(_tabs.current_tab)
	_panel_scroll = null
	_panel_center = null
	for child in get_children():
		child.queue_free()
	await get_tree().process_frame
	_build()
	_code_edit.text = saved_code
	_sync_run_state()
	_wire_build_palette()
	# Re-select the same tab by NAME so a UI-scale rebuild never jumps the
	# player out of the page they were using.
	if _tabs != null:
		for i in range(_tabs.get_tab_count()):
			if _tabs.get_tab_title(i) == was_tab:
				_tabs.current_tab = i
				break
	visible = was_visible

# Walks up from this UI to the LuaNPC (the node exposing stop_work), so the
# lookup doesn't depend on a fixed parent depth.
func _find_npc() -> Node:
	var n: Node = get_parent()
	while n != null and not n.has_method("stop_work"):
		n = n.get_parent()
	return n

# Rename the NPC — its label above the robot AND the LUA status HUD both update.
func _on_rename_submitted(new_name: String) -> void:
	var npc: Node = _find_npc()
	if npc != null and npc.has_method("rename_to"):
		npc.call("rename_to", new_name)
	if _name_edit != null:
		_name_edit.release_focus()

# ── Run state ─────────────────────────────────────────────────────
# Re-syncs RUN / STOP / editability AND the shared pause with the robot's REAL
# activity. `has_active_work()` is true while a job is dispatched, a station job
# is queued, or a move() velocity is still set — only then does STOP mean
# anything, and only then may the world keep simulating behind the panel.
# Anything else (a finished script, an idle robot) re-asserts the UI pause, so
# the player can never regain control while the editor is in front.
func _sync_run_state(manage_pause: bool = true) -> void:
	var npc: Node = _find_npc()
	var active: bool = false
	if npc != null:
		if npc.has_method("has_active_work"):
			active = bool(npc.call("has_active_work"))
		elif npc.has_method("is_working"):
			active = bool(npc.call("is_working"))
	var in_combat: bool = npc != null and npc.has_method("is_combat") \
		and bool(npc.call("is_combat"))
	_running = active
	_update_combat_button(in_combat)
	if _run_btn != null:
		_run_btn.disabled = active or in_combat
	if _stop_btn != null:
		_stop_btn.disabled = in_combat or not active
		_stop_btn.tooltip_text = "Stop the robot's current work." if active and not in_combat \
			else "Nothing is running — STOP is only available while the robot is working."
	if _code_edit != null:
		_code_edit.editable = not active and not in_combat
	# Suspending the panel's pause is what lets the robot move; it is keyed by
	# this node, so the shared refcount stays balanced and a second UI still
	# pauses the game. Combat keeps the pause in place so the player can safely
	# use EXIT COMBAT.
	if not manage_pause:
		return
	if active and not in_combat:
		Global.suspend_ui_pause(self)
	else:
		Global.resume_ui_pause(self)

# Work can start or finish at any moment while the panel is open (a job ends,
# STOP takes effect, a queued station job begins), so keep the buttons and the
# pause in step every frame. PROCESS_MODE_ALWAYS (set in _ready) keeps this
# running while the tree is paused.
func _process(_delta: float) -> void:
	if not visible:
		return
	_fit_keyboard()
	if _awaiting_settle:
		return
	_sync_run_state()

# Android: shrink the scroll area by the software keyboard's height so the
# focused code field and the RUN/STOP row stay above it. No-op on desktop
# (mobile_keyboard_height() returns 0).
func _fit_keyboard() -> void:
	if _panel_scroll == null:
		return
	var inset: float = Global.keyboard_panel_inset()
	var want: float = -(Global.ui_safe_insets.w + inset)
	if not is_equal_approx(_panel_scroll.offset_bottom, want):
		_panel_scroll.offset_bottom = want
		if _code_edit != null and is_instance_valid(_code_edit) and _code_edit.has_focus():
			_panel_scroll.call_deferred("ensure_control_visible", _code_edit)

# Called by the LuaNPC when the player clicks the station.
func open_panel() -> void:
	visible = true
	# Re-entering a station always starts on CODE, never on the reference tab
	# that happened to be open when the panel was closed.
	if _tabs != null and _encycl != null and _tabs.current_tab == _encycl.get_index():
		_tabs.current_tab = 0
	SFX.play_ui("sfx_lua_station", 0)
	_last_run_ok = false
	_awaiting_settle = false
	_sync_run_state()
	_refresh_build_palette()
	_load_saved_code()
	Global.register_ui_back(self, Callable(self, "_back"))
	if _name_edit != null:
		var npc: Node = _find_npc()
		if npc != null and npc.has_method("get_display_name"):
			_name_edit.text = str(npc.call("get_display_name"))
	_update_combat_ui()

# Restore the LUA's saved program into the editor (persisted on the NPC with the
# world save, so the code survives a reload).
func _load_saved_code() -> void:
	if _code_edit == null:
		return
	var npc: Node = _find_npc()
	if npc == null:
		return
	var code: String = str(npc.get("program_code"))
	if not code.is_empty():
		_code_edit.text = code

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

	# Keyboard-aware scroll area, matching Algorithmica's editors: the panel
	# can be taller than a phone in landscape, and a focused CodeEdit must be
	# scrolled above the software keyboard.
	var scroll := ScrollContainer.new()
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	Global.apply_safe_area(scroll)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	add_child(scroll)
	_panel_scroll = scroll

	var center := CenterContainer.new()
	var content := Global.ui_content_rect().size
	center.custom_minimum_size = Vector2(content.x, maxf(1.0, content.y))
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.add_child(center)
	_panel_center = center

	var panel := PanelContainer.new()
	# Same weight and proportions as the Algorithmica station/furnace editor:
	# a wide code page with the reference alongside it.
	panel.custom_minimum_size = Global.ui_fit_min_size(Vector2(900, 560))
	var ps := StyleBoxFlat.new()
	ps.bg_color = C_PANEL; ps.border_color = C_BORDER
	ps.set_border_width_all(1); ps.set_corner_radius_all(6)
	ps.content_margin_left = i(18, s); ps.content_margin_right  = i(18, s)
	ps.content_margin_top  = i(14, s); ps.content_margin_bottom = i(18, s)
	panel.add_theme_stylebox_override("panel", ps)
	center.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", i(8, s))
	panel.add_child(vbox)

	# ── Header ───────────────────────────────────────────────────
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", i(8, s))
	vbox.add_child(header)

	var title := Label.new()
	title.text = "AUTOMATICA — LUA ROBOT"
	title.add_theme_font_size_override("font_size", Global.ui_font_size(16))
	title.add_theme_color_override("font_color", C_TITLE)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)

	# Rename field — the new name shows above the robot AND in the LUA status
	# HUD (lua_status_ui.gd reads get_display_name()).
	_name_edit = LineEdit.new()
	_name_edit.placeholder_text = "NAME"
	# Hard 12-character cap shared with LuaNPC.rename_to()/rename().
	_name_edit.max_length = LUA_NPC_SCRIPT.MAX_CUSTOM_NAME_LENGTH
	_name_edit.tooltip_text = "Automatica names are limited to %d characters." \
		% LUA_NPC_SCRIPT.MAX_CUSTOM_NAME_LENGTH
	_name_edit.add_theme_font_size_override("font_size", Global.ui_font_size(12))
	_name_edit.custom_minimum_size = Vector2(i(120, s), 0)
	var npc_now: Node = _find_npc()
	if npc_now != null and npc_now.has_method("get_display_name"):
		_name_edit.text = str(npc_now.call("get_display_name"))
	_name_edit.text_submitted.connect(_on_rename_submitted)
	header.add_child(_name_edit)

	var rename_btn := Button.new()
	rename_btn.text = "RENAME"
	rename_btn.add_theme_font_size_override("font_size", Global.ui_font_size(12))
	var rbs := StyleBoxFlat.new()
	rbs.bg_color = Color(0.12, 0.18, 0.36, 1.0)
	rbs.border_color = C_BORDER
	rbs.set_border_width_all(1); rbs.set_corner_radius_all(4)
	rbs.content_margin_left = i(10, s); rbs.content_margin_right  = i(10, s)
	rbs.content_margin_top  = i(4, s);  rbs.content_margin_bottom = i(4, s)
	rename_btn.add_theme_stylebox_override("normal",  rbs)
	rename_btn.add_theme_stylebox_override("hover",   rbs)
	rename_btn.add_theme_stylebox_override("pressed", rbs)
	rename_btn.add_theme_color_override("font_color", C_TITLE)
	rename_btn.pressed.connect(func() -> void: _on_rename_submitted(_name_edit.text))
	header.add_child(rename_btn)

	# Explicit reference toggle: the tabs remain, but this makes the
	# Encyclopedia entry point obvious and returns to CODE with the same click.
	_enc_btn = Button.new()
	_enc_btn.add_theme_font_size_override("font_size", Global.ui_font_size(12))
	var eb := StyleBoxFlat.new()
	eb.bg_color = Color(0.12, 0.18, 0.36, 1.0)
	eb.border_color = C_BORDER
	eb.set_border_width_all(1); eb.set_corner_radius_all(4)
	eb.content_margin_left = i(10, s); eb.content_margin_right = i(10, s)
	eb.content_margin_top = i(4, s); eb.content_margin_bottom = i(4, s)
	_enc_btn.add_theme_stylebox_override("normal", eb)
	_enc_btn.add_theme_stylebox_override("hover", eb)
	_enc_btn.add_theme_stylebox_override("pressed", eb)
	_enc_btn.add_theme_color_override("font_color", C_TITLE)
	_enc_btn.pressed.connect(_toggle_encyclopedia)
	header.add_child(_enc_btn)
	_update_encyclopedia_button(false)

	var close_btn := Global.make_close_button()
	close_btn.tooltip_text = "Close the Automatica editor."
	close_btn.pressed.connect(_close)
	header.add_child(close_btn)

	_divider(vbox)

	# ── Main body: CODE / INVENTORY / ENCYCLOPEDIA tabs ──────────
	# Same navigation model as Algorithmica's editor: the reference is a tab,
	# not a separate overlay, and the program log sits under the code.
	_body = _build_body(s)
	_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(_body)

# ── Body: code editor + output ────────────────────────────────────
# Mirrors the Algorithmica editor's tab layout:
#   CODE          — templates + editor + RUN/STOP/CLEAR/COMBAT + inline log
#   INVENTORY     — the player's items/hotbar + the robot's TOOL/3 BUILD slots
#   ENCYCLOPEDIA  — the full Programming Encyclopedia, read-only
# Each tab is its own container, so the inventory and coding areas are separate
# components navigated independently. They share no state of their own: the
# slots are views of the NPC's authoritative palette/tool.
func _build_body(s: float) -> Control:
	var tabs := TabContainer.new()
	_tabs = tabs
	tabs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tabs.size_flags_vertical   = Control.SIZE_EXPAND_FILL
	tabs.add_theme_font_size_override("font_size", Global.ui_font_size(13))
	tabs.clip_tabs = false
	tabs.tab_changed.connect(_on_tab_changed)

	# ── CODE tab ──
	var code_page := HBoxContainer.new()
	code_page.name = "CODE"
	code_page.add_theme_constant_override("separation", i(10, s))

	# TEMPLATES column (left of the code editor), same as Algorithmica.
	code_page.add_child(_build_snippets(s))

	var ed_wrap := VBoxContainer.new()
	ed_wrap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ed_wrap.size_flags_vertical   = Control.SIZE_EXPAND_FILL
	ed_wrap.add_theme_constant_override("separation", i(8, s))
	code_page.add_child(ed_wrap)

	_code_edit = CodeEdit.new()
	_code_edit.custom_minimum_size  = Vector2(0, i(140, s))
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
	_code_edit.add_theme_font_size_override("font_size", Global.ui_font_size(13))
	ed_wrap.add_child(_code_edit)

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

	# Combat mode (see lua_npc.gd combat section). Termination lives in the pause
	# menu's LUA Management list.
	_combat_btn = _make_btn("⚔ COMBAT", Color(1.0, 0.85, 0.6, 1.0), C_STOP, _toggle_combat, s)
	_combat_btn.tooltip_text = "Send this Automatica into combat mode: it abandons its station, follows you and fights. While in combat it cannot run code. Use EXIT COMBAT to return it to its station as a normal Automatica."
	btn_row.add_child(_combat_btn)

	# Inline program log below the action row, exactly like Algorithmica's
	# station/furnace editor. It stays visible while the CODE tab is open.
	var out_panel := PanelContainer.new()
	out_panel.custom_minimum_size = Vector2(0, i(90, s))
	out_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var op := StyleBoxFlat.new()
	op.bg_color = C_OUTPUT; op.border_color = C_BORDER
	op.set_border_width_all(1); op.set_corner_radius_all(4)
	op.content_margin_left = i(8, s); op.content_margin_right  = i(8, s)
	op.content_margin_top  = i(8, s); op.content_margin_bottom = i(8, s)
	out_panel.add_theme_stylebox_override("panel", op)
	ed_wrap.add_child(out_panel)

	var scroll := ScrollContainer.new()
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	out_panel.add_child(scroll)

	_output = RichTextLabel.new()
	_output.bbcode_enabled        = true
	_output.scroll_following      = true
	_output.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_output.size_flags_vertical   = Control.SIZE_EXPAND_FILL
	_output.add_theme_font_size_override("font_size", Global.ui_font_size(12))
	_output.add_theme_color_override("default_color", C_TITLE)
	scroll.add_child(_output)

	tabs.add_child(code_page)

	# ── INVENTORY tab ──
	var inv_page := HBoxContainer.new()
	inv_page.name = "INVENTORY"
	inv_page.add_theme_constant_override("separation", i(10, s))

	# Player inventory + hotbar (drag items straight into the BUILD SLOTS).
	inv_page.add_child(_build_player_items(s))

	var pal_wrap := VBoxContainer.new()
	pal_wrap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pal_wrap.add_theme_constant_override("separation", i(6, s))
	inv_page.add_child(pal_wrap)

	var pal_lbl := Label.new()
	pal_lbl.text = "TOOL + BUILD SLOTS"
	pal_lbl.add_theme_font_size_override("font_size", Global.ui_font_size(11))
	pal_lbl.add_theme_color_override("font_color", C_MUTED)
	pal_wrap.add_child(pal_lbl)

	# Build palette — the 3 slots the robot places FROM. Drag a block from the
	# inventory/hotbar into a slot to give it to the robot; the robot also fills
	# them itself (chopping wood, or withdraw() from a chest).
	pal_wrap.add_child(_build_palette_row(s))

	var hint := Label.new()
	hint.text = "Drag a tool into the left slot and blocks into the build slots."
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.add_theme_font_size_override("font_size", Global.ui_font_size(11))
	hint.add_theme_color_override("font_color", C_MUTED)
	pal_wrap.add_child(hint)

	tabs.add_child(inv_page)

	# ── ENCYCLOPEDIA tab ──
	_encycl = _build_encyclopedia(s)
	_encycl.name = "ENCYCLOPEDIA"
	_encycl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_encycl.size_flags_vertical   = Control.SIZE_EXPAND_FILL
	tabs.add_child(_encycl)

	return tabs

# ── Templates column ──────────────────────────────────────────────
# A narrow column of example programs, styled like Algorithmica's TEMPLATES
# column. Clicking one replaces the editor's contents with that example (the
# tutorial one also arms its mission).
func _build_snippets(s: float) -> Control:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", i(6, s))
	col.custom_minimum_size = Vector2(i(160, s), 0)

	var lbl := Label.new()
	lbl.text = "TEMPLATES"
	lbl.add_theme_font_size_override("font_size", Global.ui_font_size(11))
	lbl.add_theme_color_override("font_color", C_MUTED)
	col.add_child(lbl)

	var hint := Label.new()
	hint.text = "Click to load an example into the editor."
	hint.add_theme_font_size_override("font_size", Global.ui_font_size(9))
	hint.add_theme_color_override("font_color", C_MUTED)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(hint)

	for i in range(SNIPPETS.size()):
		var snip: Dictionary = SNIPPETS[i]
		var btn := Button.new()
		btn.text = str(snip["name"])
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.add_theme_font_size_override("font_size", Global.ui_font_size(11))
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
	inv_lbl.add_theme_font_size_override("font_size", Global.ui_font_size(11))
	inv_lbl.add_theme_color_override("font_color", C_MUTED)
	col.add_child(inv_lbl)

	var inv_hint := Label.new()
	inv_hint.text = "Drag items into the BUILD SLOTS."
	inv_hint.add_theme_font_size_override("font_size", Global.ui_font_size(9))
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
	hb_lbl.add_theme_font_size_override("font_size", Global.ui_font_size(11))
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
		bg.name = "SlotBG"
		bg.color = Color(0.11, 0.15, 0.26, 1.0)
		bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bg.set_anchors_preset(Control.PRESET_FULL_RECT)
		tslot.add_child(bg)
		# The ICON is a CHILD so it draws OVER the opaque bg — setting the slot's
		# OWN texture hid it behind the bg, so the hotbar looked empty/out of
		# sync with the real one.
		var icon := TextureRect.new()
		icon.name = "ItemIcon"
		icon.expand_mode  = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.set_anchors_preset(Control.PRESET_FULL_RECT)
		icon.offset_left = i(4, s); icon.offset_top = i(4, s)
		icon.offset_right = -i(4, s); icon.offset_bottom = -i(4, s)
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		icon.visible = false
		tslot.add_child(icon)
		var qty := Label.new()
		qty.name = "Quantity"
		qty.add_theme_font_size_override("font_size", Global.ui_font_size(10))
		qty.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
		qty.offset_left = -i(16, s); qty.offset_top = -i(14, s)
		qty.offset_right = -i(2, s); qty.offset_bottom = -i(2, s)
		qty.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		qty.mouse_filter = Control.MOUSE_FILTER_IGNORE
		qty.visible = false
		tslot.add_child(qty)
		# Click a slot to make it the player's ACTIVE hotbar slot.
		tslot.gui_input.connect(func(ev: InputEvent) -> void: _on_editor_hotbar_click(ev, idx))
		hb_row.add_child(tslot)
		_hotbar_slots.append(tslot)

	if not Global.Inventory_updated.is_connected(_refresh_player_items):
		Global.Inventory_updated.connect(_refresh_player_items)
	if not Global.Hotbar_updated.is_connected(_refresh_player_items):
		Global.Hotbar_updated.connect(_refresh_player_items)
	if not Global.hotbar_selection_changed.is_connected(_on_hotbar_selection_changed):
		Global.hotbar_selection_changed.connect(_on_hotbar_selection_changed)
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
		var icon: TextureRect = slot.get_node_or_null("ItemIcon") as TextureRect
		var qty:  Label       = slot.get_node_or_null("Quantity") as Label
		var bg:   ColorRect   = slot.get_node_or_null("SlotBG") as ColorRect
		var item: Variant = Global.Hotbar[i] if i < Global.Hotbar.size() else null
		if icon != null:
			if item != null:
				icon.texture = ((item as Dictionary)["data"] as ItemData).icon
				icon.visible = true
				var q: int = int((item as Dictionary)["quantity"])
				if qty != null:
					qty.text = str(q)
					qty.visible = q > 1
			else:
				icon.texture = null
				icon.visible = false
				if qty != null:
					qty.visible = false
		# Mirror the real hotbar's selected-slot highlight.
		if bg != null:
			bg.color = Color(0.25, 0.40, 0.75, 1.0) if i == Global.hotbar_selected \
				else Color(0.11, 0.15, 0.26, 1.0)

func _on_hotbar_selection_changed(_i: int) -> void:
	_refresh_player_items()

func _on_editor_hotbar_click(ev: InputEvent, idx: int) -> void:
	if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
		Global.set_hotbar_selection(idx)
		_refresh_player_items()

# ── Build palette row (robot's 3 block slots) ─────────────────────
func _build_palette_row(s: float) -> Control:
	var row := VBoxContainer.new()
	row.add_theme_constant_override("separation", i(4, s))

	var lbl := Label.new()
	lbl.text = "BUILD SLOTS  (drag blocks in — the robot places from these)"
	lbl.add_theme_font_size_override("font_size", Global.ui_font_size(10))
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

	# TOOL slot — the item the robot swings for its tasks (and its combat weapon).
	var tool_lbl := Label.new()
	tool_lbl.text = "TOOL  (the robot swings this)"
	tool_lbl.add_theme_font_size_override("font_size", Global.ui_font_size(10))
	tool_lbl.add_theme_color_override("font_color", C_MUTED)
	row.add_child(tool_lbl)
	var tool_row := HBoxContainer.new()
	tool_row.add_theme_constant_override("separation", i(6, s))
	row.add_child(tool_row)
	var tool_script: GDScript = load("res://scripts/lua_tool_slot.gd")
	_tool_slot = tool_script.new()
	_tool_slot.connect("slot_changed", _on_build_slot_changed)
	tool_row.add_child(_tool_slot)
	return row

func _on_build_slot_changed() -> void:
	_refresh_build_palette()

# Pushes the robot's current palette + tool contents into the slot visuals.
func _refresh_build_palette() -> void:
	var npc: Node = _find_npc()
	for slot in _build_slots:
		if is_instance_valid(slot):
			slot.set("_npc", npc)
			slot.call("refresh")
	if _tool_slot != null and is_instance_valid(_tool_slot):
		_tool_slot.set("_npc", npc)
		_tool_slot.call("refresh")
	_update_combat_ui()

func _on_build_palette_changed() -> void:
	_refresh_build_palette()

# ── Combat mode UI ────────────────────────────────────────────────
# The button is a toggle: COMBAT sends the robot out as a follower, EXIT
# COMBAT returns it to its station as a normal (blue) Automatica.
func _toggle_combat() -> void:
	var npc: Node = _find_npc()
	if npc == null or not npc.has_method("is_combat"):
		return
	if bool(npc.call("is_combat")):
		npc.call("_exit_combat")
	else:
		npc.call("_enter_combat")
	_update_combat_ui()

# Terminating a LUA is a MENU action now: pause menu -> LUA Management, where
# the player picks the specific LUA from the active list. There is deliberately
# no per-station terminate control any more.
func _update_combat_ui() -> void:
	var npc: Node = _find_npc()
	var combat: bool = npc != null and npc.has_method("is_combat") and bool(npc.call("is_combat"))
	_update_combat_button(combat)
	_sync_run_state()

# Keep the label/tooltip in step with the live combat state (the state can also
# change from Lua's combat_mode() while this panel is open).
func _update_combat_button(combat: bool) -> void:
	if _combat_btn == null:
		return
	_combat_btn.visible = true
	_combat_btn.text = "⚔ EXIT COMBAT" if combat else "⚔ COMBAT"
	_combat_btn.tooltip_text = ("Return this Automatica to its station as a normal Automatica. Combat HP, target and sprite are reset." if combat
		else "Send this Automatica into combat mode: it abandons its station, follows you and fights. While in combat it cannot run code. Use EXIT COMBAT to return it to its station as a normal Automatica.")

# ── Encyclopedia ──────────────────────────────────────────────────
# Four independently expandable sections, in this order:
#   1. LUA Programming Language        3. Python Programming Language
#   2. Automatica (LUA robot)          4. Algorithmica (Python automation)
# Language sections reveal entries through dungeon discovery; the two function
# sections list their complete API immediately (scripts/encyclopedia_data.gd).
# The learned dungeon concepts are listed underneath, as before.
func _build_encyclopedia(s: float) -> Control:
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", i(10, s))

	var hdr := Label.new()
	hdr.text = "PROGRAMMING ENCYCLOPEDIA"
	hdr.add_theme_font_size_override("font_size", Global.ui_font_size(14))
	hdr.add_theme_color_override("font_color", C_TITLE)
	root.add_child(hdr)

	var hint := Label.new()
	hint.text = "Read-only reference. Switch to CODE to write a program."
	hint.add_theme_font_size_override("font_size", Global.ui_font_size(10))
	hint.add_theme_color_override("font_color", C_MUTED)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(hint)

	_divider(root)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(scroll)

	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", i(14, s))
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)

	_enc_func_box = VBoxContainer.new()
	_enc_func_box.add_theme_constant_override("separation", i(14, s))
	_enc_func_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_child(_enc_func_box)
	_refresh_encyclopedia_sections()

	_divider(list)
	_enc_section(list, "DUNGEON KNOWLEDGE (unlocked)", s)
	_knowledge_box = VBoxContainer.new()
	_knowledge_box.add_theme_constant_override("separation", i(14, s))
	list.add_child(_knowledge_box)
	_refresh_knowledge_section()

	return root

# Rebuilds the encyclopedia accordion sections. Language sections list only
# what the player has discovered; Automatica / Algorithmica are always fully
# listed. Called on open so a dungeon cleared since the last look shows up.
func _refresh_encyclopedia_sections() -> void:
	if _enc_func_box == null:
		return
	for child in _enc_func_box.get_children().duplicate():
		if child is EncyclopediaSection:
			_enc_open[(child as EncyclopediaSection).section_id] = (child as EncyclopediaSection).expanded
		_enc_func_box.remove_child(child)
		child.free()
	var s: float = Global.ui_scale
	for section in APIReference.encyclopedia_sections():
		var sec: Dictionary = section as Dictionary
		var always: bool = EncyclopediaData.section_is_always_available(sec)
		var start_open: bool = bool(sec.get("start_expanded", always))
		var entries: Array = EncyclopediaData.entries_for_section(sec)
		var acc := EncyclopediaSection.new()
		acc.setup(sec, s)
		acc.set_counts(entries.size(), EncyclopediaData.section_total(sec), always)
		if entries.is_empty():
			var none := Label.new()
			none.text = "Nothing discovered yet — clear dungeons to reveal entries here."
			none.add_theme_font_size_override("font_size", Global.ui_font_size(11))
			none.add_theme_color_override("font_color", C_MUTED)
			none.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			acc.body().add_child(none)
		else:
			for e in entries:
				acc.add_entry(e as Dictionary, s)
		_enc_func_box.add_child(acc)
		# Function sections open by default; language sections stay collapsed
		# until something has been discovered. The mineable-block list opts out
		# with start_expanded = false so it does not bury the function list.
		acc.set_expanded(bool(_enc_open.get(acc.section_id, start_open)), false)
		acc.expansion_changed.connect(_on_encyclopedia_section_expanded)

func _on_encyclopedia_section_expanded(id: String, on: bool) -> void:
	_enc_open[id] = on

# Knowledge changed (a dungeon altar was used): refresh both the discovered
# function sections and the learned-concept list.
func _on_knowledge_updated() -> void:
	_refresh_encyclopedia_sections()
	_refresh_knowledge_section()

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
		none.add_theme_font_size_override("font_size", Global.ui_font_size(12))
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
# deferred to _on_tab_changed when the reference actually becomes visible.
func _enc_knowledge_entry(parent: Node, e: KnowledgeEntry, s: float) -> void:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", i(4, s))
	parent.add_child(box)

	var name_row := HBoxContainer.new()
	name_row.add_theme_constant_override("separation", i(6, s))
	box.add_child(name_row)

	var name_lbl := Label.new()
	name_lbl.text = e.entry_name
	name_lbl.add_theme_font_size_override("font_size", Global.ui_font_size(14))
	name_lbl.add_theme_color_override("font_color", Color(0.55, 0.90, 1.00, 1.0))
	name_row.add_child(name_lbl)

	var unseen: bool = Global.is_entry_unseen(e)
	if unseen:
		var badge := Label.new()
		badge.text = "NEW"
		badge.add_theme_font_size_override("font_size", Global.ui_font_size(9))
		badge.add_theme_color_override("font_color", Global.KEYWORD_FLASH)
		name_row.add_child(badge)
		_knowledge_new_badges[e.id()] = badge

	var desc_lbl := Label.new()
	desc_lbl.text = e.description
	desc_lbl.add_theme_font_size_override("font_size", Global.ui_font_size(12))
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
	lbl.add_theme_font_size_override("font_size", Global.ui_font_size(10))
	lbl.add_theme_color_override("font_color", C_MUTED)
	parent.add_child(lbl)

# ── Actions ───────────────────────────────────────────────────────
# Select the ENCYCLOPEDIA tab (or return to CODE when it is already active).
# Kept as a helper for Back/Escape and the former header button.
func _toggle_encyclopedia() -> void:
	if _tabs == null or _encycl == null:
		return
	var idx: int = _encycl.get_index()
	_tabs.current_tab = 0 if _tabs.current_tab == idx else idx

# Refresh the reference when its tab becomes visible, so dungeon knowledge
# learned since the last look appears without rebuilding the editor.
func _on_tab_changed(tab: int) -> void:
	var on_reference: bool = _encycl != null and tab == _encycl.get_index()
	_update_encyclopedia_button(on_reference)
	if not on_reference:
		return
	_refresh_encyclopedia_sections()
	_refresh_knowledge_section()
	_emphasize_unseen_knowledge.call_deferred()

func _update_encyclopedia_button(on_reference: bool) -> void:
	if _enc_btn == null or not is_instance_valid(_enc_btn):
		return
	_enc_btn.text = "↩  CODE" if on_reference else "📖  ENCYCLOPEDIA"
	_enc_btn.tooltip_text = ("Return to the code editor." if on_reference
		else "Open the Programming Encyclopedia. Click again to return to CODE.")

# ── Code editor: syntax highlight + autocomplete ──────────────────
# Custom API names + Lua keywords are highlighted, and the completion popup is
# built from APIReference (custom + built-in). A light lint warns about
# `name(` calls that aren't in the API before the program is even run.
var _completion_filled: bool = false

func _setup_code_editor() -> void:
	var ce := _code_edit
	var hl := CodeHighlighter.new()
	# CodeHighlighter's DEFAULT number/symbol/function/member colours are pure
	# BLACK — unreadable on the dark editor. Set them all to light tones.
	hl.number_color          = Color(0.98, 0.70, 0.53)   # peach
	hl.symbol_color          = Color(0.53, 0.86, 0.92)   # sky
	hl.function_color        = Color(0.45, 0.85, 1.00)   # blue
	hl.member_variable_color = Color(0.89, 0.75, 0.98)   # lavender
	for kw in ["function", "end", "if", "then", "elseif", "else", "for", "while",
			"do", "repeat", "until", "return", "local", "and", "or", "not", "in",
			"break", "true", "false", "nil"]:
		hl.add_keyword_color(kw, Color(0.85, 0.55, 0.95))
	for fn in _api_function_names():
		hl.add_keyword_color(fn, Color(0.45, 0.85, 1.0))
	ce.syntax_highlighter = hl
	ce.set_code_completion_enabled(true)
	ce.code_completion_requested.connect(_on_code_completion_requested)
	# Light editor-chrome colours (line numbers, caret, selection, current line).
	LanguageSpecification.style_code_edit(ce, C_TITLE, C_MUTED)

# Every callable name from the API reference (custom + built-in Lua), deduped.
func _api_function_names() -> PackedStringArray:
	var seen: Dictionary = {}
	var out := PackedStringArray()
	for group in APIReference.groups():
		for lang in (group["languages"] as Array):
			var group_name := str(lang["name"])
			if not (group_name.begins_with("LUA") or group_name.begins_with("AUTOMATICA")):
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
	# Combat LUAs cannot run code (see lua_npc.gd combat section).
	var npc_c: Node = _find_npc()
	if npc_c != null and npc_c.has_method("is_combat") and bool(npc_c.call("is_combat")):
		_print_output("[color=#ff8888]This Automatica is in combat mode — use EXIT COMBAT before running code.[/color]")
		return
	if _lua_state == null:
		_print_output("[color=#ff8888]No LuaState connected.[/color]")
		return
	var code: String = _code_edit.text.strip_edges()
	if code.is_empty():
		return
	_last_run_ok = false
	# Hard pre-run guard: Lua executes synchronously, so an obvious infinite
	# loop would freeze the game before any runtime timeout could run.
	var unsafe: String = CODE_SAFETY.lua_issue(code)
	if not unsafe.is_empty():
		_print_output("[color=#ff8888]✗ %s[/color]" % unsafe)
		SFX.play_ui("sfx_lua_run", 2, -2.0)
		return
	SFX.play_ui("sfx_lua_run", 0)
	_lint(code)
	# Persist the program on the NPC so it survives a reload.
	if npc_c != null:
		npc_c.set("program_code", code)
	CrashLogger.code("lua", "RUN", "%s | chars=%d\n%s" % [
		npc_c.call("get_display_name") if npc_c != null and npc_c.has_method("get_display_name") else "editor",
		code.length(), code])

	var preamble: String = LUA_PREAMBLE
	# Announce and arm the run BEFORE calling into Lua: run_code() executes the
	# chunk synchronously, so code_executed / code_failed arrive inside the call.
	_print_output("[color=#88ffaa]▶ Running...[/color]")
	_running = true
	_awaiting_settle = true
	_run_btn.disabled   = true
	_stop_btn.disabled  = false
	_code_edit.editable = false
	# Let the world simulate while the robot works. This SUSPENDS the panel's
	# pause only — the shared refcount is untouched, so closing still releases
	# exactly once and a second UI still keeps the game paused.
	Global.suspend_ui_pause(self)

	# Publish the nearest station's automation state before the Lua chunk runs.
	# Rust exposes these as read-only globals; without this snapshot an
	# Automatica always read station_recipe/station_output_* as empty.
	var station: Node = null
	if npc_c != null and npc_c.has_method("nearest_crafting_station"):
		station = npc_c.call("nearest_crafting_station") as Node
	if station != null and is_instance_valid(station):
		_lua_state.set("station_recipe", str(station.call("get_automation_recipe_name")))
		var out_data = station.call("get_output_item")
		_lua_state.set("station_output_item",
			(out_data as ItemData).item_name if out_data is ItemData else "")
		_lua_state.set("station_output_count", int(station.call("get_output_quantity")))
	else:
		_lua_state.set("station_recipe", "")
		_lua_state.set("station_output_item", "")
		_lua_state.set("station_output_count", 0)
	_lua_state.set("code", preamble + code)
	_lua_state.call("run_code")

	# The chunk has finished. Continuous jobs are dispatched from queued signals
	# on the next physics frames, so decide what is still running after them.
	_settle_after_chunk.call_deferred()

# Waits for the queued Lua signals to be dispatched, then hands over to
# _sync_run_state(): continuous work keeps the world running and STOP enabled;
# a script that finished and left nothing running re-pauses the game and
# disables STOP. _process stays out of the way until this settles, so the pause
# cannot flip back on for the single frame before a job starts.
func _settle_after_chunk() -> void:
	if not is_inside_tree():
		_awaiting_settle = false
		return
	await get_tree().process_frame
	await get_tree().physics_frame
	await get_tree().process_frame
	_awaiting_settle = false
	if not visible:
		return
	_sync_run_state()

func _stop_code() -> void:
	# STOP is only meaningful while something is actually running (see
	# _sync_run_state) — after a script finishes the button is disabled and this
	# guard keeps a stray click from printing a misleading "Stopped".
	if _stop_btn != null and _stop_btn.disabled:
		return
	var npc: Node = _find_npc()
	if npc != null:
		npc.call("stop_work")

	_print_output("[color=#ffaa44]■ Stopped.[/color]")
	# stop_work() clears velocity immediately; a dispatched job notices on its
	# next await. _process keeps polling, so the buttons settle by themselves.
	_sync_run_state()

func _clear_code() -> void:
	_code_edit.text = ""

# Close the panel. The robot keeps working if it was working; the panel's pause
# token and any pause suspension are released exactly once either way.
func close_panel() -> void:
	if not visible:
		return
	# Leaving the station returns the hidden panel to CODE so the reference
	# cannot re-open by itself the next time the player interacts.
	if _tabs != null and _encycl != null and _tabs.current_tab == _encycl.get_index():
		_tabs.current_tab = 0
	_awaiting_settle = false
	# Persist the current editor draft before closing so Escape/Back can never
	# silently discard code the player has not run yet.
	if _code_edit != null:
		var npc: Node = _find_npc()
		if npc != null:
			npc.set("program_code", _code_edit.text)
	Global.unregister_ui_back(self)
	Global.resume_ui_pause(self)
	Global.close_ui()
	visible = false
	# The editor is itself a full-screen modal that hides the HUD. Closing it
	# from its own X button/Escape bypasses LuaUI.close_editor(), so this signal
	# must be emitted here or the hotbar/minimap/pause strip stay hidden.
	Global.modal_hud_changed.emit(false)
	# manage_pause = false: the panel is closed, so it must not re-suspend the
	# pause for a robot that keeps working without it.
	_sync_run_state(false)

func _close() -> void:
	close_panel()

# Escape/Android Back leaves the API encyclopedia tab first, then closes the
# editor. Mirrors Algorithmica's layered back behaviour.
func _back() -> void:
	if _tabs != null and _encycl != null \
			and _tabs.current_tab == _encycl.get_index():
		_tabs.current_tab = 0
		if visible:
			Global.register_ui_back(self, Callable(self, "_back"))
		return
	close_panel()

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("escape") and visible:
		get_viewport().set_input_as_handled()
		if not Global.request_ui_back(event) and not Global.is_ui_back_event_consumed(event):
			_back()

# ── Lua signal handlers ───────────────────────────────────────────
func _on_lua_print(text: String) -> void:
	_print_output("[color=#aaddff]» %s[/color]" % text)

func _on_lua_move(vec: Vector2) -> void:
	_print_output("[color=#88ffaa]move → (%.1f, %.1f)[/color]" % [vec.x, vec.y])

func _on_code_executed() -> void:
	CrashLogger.code("lua", "OK", "chunk finished")
	SFX.play_ui("sfx_lua_run", 1)
	_last_run_ok = true
	# The Lua chunk itself is done. Anything it dispatched (walking, chopping,
	# crafting) is still queued as signals, so this is the point where the
	# output box reports the script finished — _settle_after_chunk() then
	# decides whether continuous work keeps running.
	_print_output("[color=#88ffaa]✓ Finished running.[/color]")
	# Tutorial snippet ran cleanly → complete its mission (idempotent).
	# Any clean run counts as "Run your first Lua program" (idempotent), not
	# just the tutorial snippet.
	Global.record_auto_run()
	# Legacy key retained for old saves/tests, hidden from the tracker.
	Global.complete_mission("run_program")
	Global.add_mission_progress("side_lua_automator", 1)
	if not _pending_mission.is_empty():
		Global.complete_mission(_pending_mission)
		_print_output("[color=#ffd76a]★ Tutorial complete![/color]")
		_pending_mission = ""

func _on_code_failed(error: String) -> void:
	CrashLogger.code("lua", "FAIL", error)
	SFX.play_ui("sfx_lua_run", 2, -2.0)
	_last_run_ok = false
	_print_output("[color=#ff8888]✗ %s[/color]" % error)
	# Nothing was dispatched, so hand the pause straight back and re-enable
	# editing; STOP must not stay clickable for code that never ran.
	_awaiting_settle = false
	_running = false
	Global.resume_ui_pause(self)
	_sync_run_state()

func _print_output(line: String) -> void:
	if _output == null: return
	_output.append_text(line + "\n")

# ── Helpers ───────────────────────────────────────────────────────
func i(base: int, s: float) -> int: return int(base * s)

func _make_btn(label: String, font_col: Color, bg: Color, cb: Callable, s: float) -> Button:
	var btn := Button.new()
	btn.text = label
	btn.custom_minimum_size = Vector2(0, i(38, s))
	btn.add_theme_font_size_override("font_size", Global.ui_font_size(13))
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

# ── Tutorial focus API ──────────────────────────────────────────────
func tutorial_code_editor() -> Control:
	return _code_edit

func tutorial_tool_slot() -> Control:
	return _tool_slot

func tutorial_show_tab(tab_name: String) -> void:
	if _tabs == null or not is_instance_valid(_tabs):
		return
	for i in range(_tabs.get_tab_count()):
		if _tabs.get_tab_title(i) == tab_name:
			_tabs.current_tab = i
			return

func tutorial_show_code_tab() -> void:
	tutorial_show_tab("CODE")

func tutorial_show_inventory_tab() -> void:
	tutorial_show_tab("INVENTORY")

func tutorial_run_button() -> Control:
	return _run_btn

func tutorial_run_succeeded() -> bool:
	return _last_run_ok

func tutorial_code_text() -> String:
	return _code_edit.text if _code_edit != null else ""

func tutorial_output_text() -> String:
	return _output.get_parsed_text() if _output != null else ""

func tutorial_snippet_button(prefix: String) -> Control:
	for node in find_children("*", "Button", true, false):
		var b := node as Button
		if b != null and b.text.begins_with(prefix):
			return b
	return null

func tutorial_hello_button() -> Control:
	return tutorial_snippet_button("1. Build a line")
