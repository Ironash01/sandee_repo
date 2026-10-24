extends Control

# ── Colors ────────────────────────────────────────────────────────
const C_OVERLAY  := Color(0.00, 0.00, 0.00, 0.50)
const C_PANEL    := Color(0.08, 0.10, 0.20, 0.97)
const C_BORDER   := Color(0.22, 0.32, 0.58, 1.00)
const C_TITLE    := Color(0.80, 0.90, 1.00, 1.00)
const C_DIVIDER  := Color(0.20, 0.28, 0.50, 1.00)
const C_TIP_BG   := Color(0.11, 0.15, 0.28, 1.00)
const C_MUTED    := Color(0.55, 0.65, 0.85, 1.00)
const C_EFFECT   := Color(0.55, 0.90, 0.60, 1.00)
const C_TAB_ACT  := Color(0.08, 0.10, 0.20, 0.97)
const C_TAB_IDLE := Color(0.04, 0.06, 0.12, 0.97)
const C_CAN_CRAFT := Color(0.15, 0.45, 0.20, 1.00)
const C_NO_MAT   := Color(0.30, 0.20, 0.20, 1.00)
const C_RED      := Color(1.00, 0.35, 0.35, 1.00)
const C_SEL      := Color(0.25, 0.40, 0.75, 1.00)

const COLS       := 5
const SLOT_SCENE  := preload("res://scenes/ui/InventorySlot.tscn")
const TRASH_SCRIPT := preload("res://scripts/trash_slot.gd")

const CRAFT_CATEGORIES := ["Materials", "Blocks", "Weapons & Tools", "Others"]
const RECIPE_DIR: String = "res://resources/recipes/"

# ── Inventory refs ────────────────────────────────────────────────
var _slots:         Array   = []
var _tip_root:      Control = null
var _rebuild_ver:   int     = 0
var _tip_name:      Label
var _tip_type:      Label
var _tip_effect:    Label
var _tip_qty:       Label
var _tip_desc:      Label
var _active_idx:    int     = -1

# ── Tab panels ────────────────────────────────────────────────────
var _inv_panel:    Control
var _craft_panel:  Control
var _enc_panel:    Control
var _tab_inv_btn:  Button
var _tab_craft_btn: Button
var _tab_enc_btn:  Button
# Rebuilt whenever knowledge is discovered (see _refresh_encyclopedia).
var _enc_list:     VBoxContainer = null
# Section id -> expanded, kept across refreshes/rebuilds so a knowledge update
# or a UI-scale change never collapses what the player opened.
var _enc_open:     Dictionary = {}

# ── Crafting refs ─────────────────────────────────────────────────
var _recipes:       Array = []   # only no-station recipes
var _filtered:      Array = []
var _active_cat:    String = "Materials"
var _selected_idx:  int   = -1
var _craft_list:    GridContainer
var _craft_detail:  Control
var _craft_name:    Label
var _craft_ing1:    HBoxContainer
var _craft_ing2:    HBoxContainer
var _craft_result:  HBoxContainer
var _craft_btn:     Button
var _craft_cat_btns: Dictionary = {}
var _craft_row_btns: Array = []

# ── Lifecycle ─────────────────────────────────────────────────────
func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_load_recipes()
	_rebuild()
	Global.Inventory_updated.connect(_refresh_inv)
	Global.Hotbar_updated.connect(_refresh_crafting)
	Global.ui_scale_changed.connect(_on_ui_scale)
	# Dungeon discoveries change which encyclopedia entries are visible.
	Global.knowledge_updated.connect(_on_knowledge_updated)

# Closing via the same "inventory" key is handled here rather than relying
# on player.gd to see the press: once this panel's CanvasLayer is visible,
# its own UI tree gets input priority over the Player node, so the
# re-press was never reaching player.gd's _input(). Guarded on the parent
# CanvasLayer's visibility (which is what actually shows/hides the panel),
# so this is a no-op — not a double-toggle — if something else already
# closed it first.
func _input(event: InputEvent) -> void:
	if get_parent().visible and event.is_action_pressed("escape"):
		get_viewport().set_input_as_handled()
		if not Global.request_ui_back(event) and not Global.is_ui_back_event_consumed(event):
			dismiss_back()
		return
	if get_parent().visible and event.is_action_pressed("inventory") \
			and not Global.is_text_input_focused():
		get_viewport().set_input_as_handled()
		_close()
		Global.inventory_toggled.emit(false)

func _on_ui_scale(_s: float) -> void:
	_rebuild()

func _load_recipes() -> void:
	_recipes.clear()
	# ResourceLoader.list_directory (not DirAccess) so this survives export —
	# see Global._load_resource_dir for why DirAccess misses .tres there.
	for fname in ResourceLoader.list_directory(RECIPE_DIR):
		if fname.ends_with(".tres"):
			var res: Resource = load(RECIPE_DIR + fname) as Resource
			if res != null and res is CraftingRecipe:
				var r: CraftingRecipe = res as CraftingRecipe
				# Inventory crafting: only hand-craftable (no station required)
				if r.result_item != null and r.result_item.is_craftable and not r.requires_station:
					_recipes.append(r)

# ── Build ─────────────────────────────────────────────────────────
func _rebuild() -> void:
	_rebuild_ver += 1
	var my_ver: int = _rebuild_ver
	_slots = []; _tip_root = null; _craft_list = null; _craft_detail = null
	_craft_cat_btns.clear(); _craft_row_btns.clear()
	_tip_name = null; _tip_type = null; _tip_effect = null; _tip_qty = null; _tip_desc = null
	_active_idx = -1; _selected_idx = -1
	# The chest's data survives the rebuild; only its views are recreated below.
	_chest_section = null; _chest_slots = []; _chest_title = null
	_enc_list = null
	for child in get_children():
		child.queue_free()
	if not is_inside_tree():
		return
	await get_tree().process_frame
	if _rebuild_ver != my_ver:
		return
	_build()
	_refresh_inv()
	_switch_tab("inventory")
	# Re-dock the open chest after a scale rebuild (its data is untouched).
	if _chest != null and is_instance_valid(_chest):
		_rebuild_chest_slots()

func _build() -> void:
	var s: float = Global.ui_scale

	var overlay := ColorRect.new()
	overlay.color = C_OVERLAY
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(overlay)

	# Scroll the whole panel when the screen is too short for it (e.g. a chest is
	# docked under the inventory on a small display) instead of clipping the
	# trash row or the bottom of the storage section off-screen.
	var scroll := ScrollContainer.new()
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode   = ScrollContainer.SCROLL_MODE_AUTO
	add_child(scroll)

	var center := CenterContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.size_flags_vertical   = Control.SIZE_EXPAND_FILL
	scroll.add_child(center)

	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 0)
	center.add_child(outer)

	# ── Tab row ───────────────────────────────────────────────────
	var tab_row := HBoxContainer.new()
	tab_row.add_theme_constant_override("separation", 2)
	outer.add_child(tab_row)

	_tab_inv_btn   = _make_tab("INVENTORY", true,  s, func(): _switch_tab("inventory"))
	_tab_craft_btn = _make_tab("✦ CRAFT",  false, s, func(): _switch_tab("craft"))
	# The Programming Encyclopedia: always available (no section unlock), but
	# each entry inside it is revealed only by its dungeon.
	_tab_enc_btn   = _make_tab("📖 PROGRAMMING ENCYCLOPEDIA", false, s,
		func(): _switch_tab("encyclopedia"))
	_tab_enc_btn.custom_minimum_size = Vector2(i(250, s), i(28, s))
	tab_row.add_child(_tab_inv_btn)
	tab_row.add_child(_tab_craft_btn)
	tab_row.add_child(_tab_enc_btn)

	var ts := Control.new()
	ts.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tab_row.add_child(ts)

	var close := Button.new()
	close.text = "✕"; close.flat = true
	close.add_theme_font_size_override("font_size", i(13, s))
	close.add_theme_color_override("font_color", C_MUTED)
	close.custom_minimum_size = Vector2(i(28,s), i(28,s))
	close.pressed.connect(_close)
	tab_row.add_child(close)

	# ── Shared panel ──────────────────────────────────────────────
	var panel := PanelContainer.new()
	var ps    := StyleBoxFlat.new()
	ps.bg_color = C_PANEL; ps.border_color = C_BORDER
	ps.set_border_width_all(1)
	ps.corner_radius_top_left = 0
	ps.corner_radius_top_right  = i(6, s)
	ps.corner_radius_bottom_left  = i(6, s)
	ps.corner_radius_bottom_right = i(6, s)
	ps.content_margin_left = i(18,s); ps.content_margin_right  = i(18,s)
	ps.content_margin_top  = i(14,s); ps.content_margin_bottom = i(18,s)
	panel.add_theme_stylebox_override("panel", ps)
	outer.add_child(panel)

	var stack := Control.new()
	stack.custom_minimum_size = Vector2(i(620,s), i(460,s))
	panel.add_child(stack)

	# ── Inventory tab content ─────────────────────────────────────
	_inv_panel = _build_inv_content(s)
	_inv_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	stack.add_child(_inv_panel)

	# ── Crafting tab content ──────────────────────────────────────
	_craft_panel = _build_craft_content(s)
	_craft_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	stack.add_child(_craft_panel)

	# ── Programming Encyclopedia tab content ──────────────────────
	_enc_panel = _build_encyclopedia_content(s)
	_enc_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	stack.add_child(_enc_panel)
	_enc_panel.visible = false

	# ── Trash slot (bottom of UI) — drag an item here to delete it ──
	var trash_spacer := Control.new()
	trash_spacer.custom_minimum_size = Vector2(0, i(10, s))
	outer.add_child(trash_spacer)

	var trash_row := HBoxContainer.new()
	trash_row.alignment = BoxContainer.ALIGNMENT_CENTER
	trash_row.add_theme_constant_override("separation", i(8, s))
	outer.add_child(trash_row)

	var trash_lbl := _lbl("DRAG HERE TO DELETE", i(10, s), C_MUTED)
	trash_row.add_child(trash_lbl)

	var trash: Control = TRASH_SCRIPT.new()
	trash_row.add_child(trash)

func _make_tab(label: String, active: bool, s: float, cb: Callable) -> Button:
	var btn := Button.new()
	btn.text = label
	btn.add_theme_font_size_override("font_size", i(12, s))
	btn.custom_minimum_size = Vector2(i(100, s), i(28, s))
	var ps := StyleBoxFlat.new()
	ps.bg_color     = C_TAB_ACT if active else C_TAB_IDLE
	ps.border_color = C_BORDER if active else Color(C_BORDER, 0.4)
	ps.border_width_top = 1; ps.border_width_left = 1; ps.border_width_right = 1
	ps.border_width_bottom = 0
	ps.corner_radius_top_left  = i(4, s); ps.corner_radius_top_right = i(4, s)
	ps.content_margin_left = i(10,s); ps.content_margin_right  = i(10,s)
	ps.content_margin_top  = i(4, s); ps.content_margin_bottom = i(4, s)
	btn.add_theme_stylebox_override("normal",  ps)
	btn.add_theme_stylebox_override("hover",   ps)
	btn.add_theme_stylebox_override("pressed", ps)
	btn.add_theme_color_override("font_color", C_TITLE if active else C_MUTED)
	btn.pressed.connect(cb)
	return btn

func _switch_tab(which: String) -> void:
	if _inv_panel == null or _craft_panel == null:
		return
	var inv_active   := which == "inventory"
	var craft_active := which == "craft"
	var enc_active   := which == "encyclopedia"
	_inv_panel.visible   = inv_active
	_craft_panel.visible = craft_active
	if _enc_panel != null:
		_enc_panel.visible = enc_active
	_style_tab_btn(_tab_inv_btn,   inv_active)
	_style_tab_btn(_tab_craft_btn, craft_active)
	_style_tab_btn(_tab_enc_btn,   enc_active)
	if craft_active:
		_active_cat   = "Materials"
		_selected_idx = -1
		_craft_filter_refresh()
	if enc_active:
		# Rebuild so anything discovered since the last look is present.
		_refresh_encyclopedia()

func _style_tab_btn(btn: Button, active: bool) -> void:
	if btn == null: return
	var s: float = Global.ui_scale
	var ps := StyleBoxFlat.new()
	ps.bg_color     = C_TAB_ACT if active else C_TAB_IDLE
	ps.border_color = C_BORDER if active else Color(C_BORDER, 0.4)
	ps.border_width_top = 1; ps.border_width_left = 1; ps.border_width_right = 1
	ps.border_width_bottom = 0
	ps.corner_radius_top_left  = i(4, s); ps.corner_radius_top_right = i(4, s)
	ps.content_margin_left = i(10,s); ps.content_margin_right  = i(10,s)
	ps.content_margin_top  = i(4, s); ps.content_margin_bottom = i(4, s)
	btn.add_theme_stylebox_override("normal",  ps)
	btn.add_theme_stylebox_override("hover",   ps)
	btn.add_theme_stylebox_override("pressed", ps)
	btn.add_theme_color_override("font_color", C_TITLE if active else C_MUTED)

# ── Programming Encyclopedia ──────────────────────────────────────
# Four independently expandable sections, in this order:
#   1. LUA Programming Language        3. Python Programming Language
#   2. Automatica (LUA robot)          4. Algorithmica (Python automation)
# Language sections reveal entries through dungeon discovery; the two function
# sections list their complete API immediately (see scripts/encyclopedia_data.gd).
# This is a read-only reference: it grants no execution rights and bypasses no
# tool requirements.
func _build_encyclopedia_content(s: float) -> Control:
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", i(8, s))

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", i(8, s))
	root.add_child(head)
	var title := _lbl("PROGRAMMING ENCYCLOPEDIA", i(14, s), C_TITLE)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	head.add_child(_lbl("Language entries unlock in dungeons — functions are always available.",
		i(10, s), C_MUTED))
	_div(root)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical    = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(scroll)

	_enc_list = VBoxContainer.new()
	_enc_list.add_theme_constant_override("separation", i(10, s))
	_enc_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_enc_list)
	_refresh_encyclopedia()
	return root

# Rebuild the four accordion sections from the registries + discovery state.
func _refresh_encyclopedia() -> void:
	if _enc_list == null or not is_instance_valid(_enc_list):
		return
	for child in _enc_list.get_children():
		if child is EncyclopediaSection:
			_enc_open[(child as EncyclopediaSection).section_id] = (child as EncyclopediaSection).expanded
		_enc_list.remove_child(child)
		child.queue_free()
	var s: float = Global.ui_scale
	for section in APIReference.encyclopedia_sections():
		var sec: Dictionary = section as Dictionary
		var always: bool = EncyclopediaData.section_is_always_available(sec)
		var entries: Array = EncyclopediaData.entries_for_section(sec)
		var acc := EncyclopediaSection.new()
		acc.setup(sec, s)
		acc.set_counts(entries.size(), EncyclopediaData.section_total(sec), always)
		if entries.is_empty():
			acc.body().add_child(_encyclopedia_empty(s))
		else:
			for e in entries:
				acc.add_entry(e as Dictionary, s)
		_enc_list.add_child(acc)
		# Function sections start open (their API is available from the start);
		# language sections start collapsed until something has been discovered.
		acc.set_expanded(bool(_enc_open.get(acc.section_id, always)), false)
		acc.expansion_changed.connect(_on_encyclopedia_section_expanded)

func _on_encyclopedia_section_expanded(id: String, on: bool) -> void:
	_enc_open[id] = on

func _encyclopedia_empty(s: float) -> Control:
	var none := _lbl("Nothing discovered yet — clear dungeons to reveal entries here.",
		i(11, s), C_MUTED)
	none.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return none

# Knowledge is per-world and persisted by Global's save data; refresh the tab
# so an entry learned while the panel is open appears immediately.
func _on_knowledge_updated() -> void:
	_refresh_encyclopedia()

# ── Inventory content ─────────────────────────────────────────────
# ── Chest section (docked beneath the player inventory) ────────────
# While a chest is open this panel hosts that chest's own storage directly
# under the player grid. Both halves use the SAME slot scene (InventorySlot),
# so slot size, spacing, icons, stack counts, hover tooltips, selection
# highlight and drag behaviour are identical by construction — nothing here
# re-implements them. The chest remains the only owner of its data
# (`chest.slots`): nothing is copied into a temporary inventory, and closing
# never rewrites it.
const CHEST_COLS: int = 4

var _chest_section: VBoxContainer = null
var _chest:         Node          = null
var _chest_slots:   Array         = []
var _chest_title:   Label         = null

# Show `chest`'s storage in this panel. Safe to call repeatedly: a previous
# chest's views are torn down first, so reopening never duplicates UI.
func attach_chest(chest: Node) -> void:
	if _chest != null and _chest != chest:
		detach_chest()
	_chest = chest
	# Player slots must accept stacks dragged out of the chest.
	for slot in _slots:
		if is_instance_valid(slot):
			slot.set("chest_link", chest)
	_rebuild_chest_slots()
	# Storage is only visible on the inventory tab.
	_switch_tab("inventory")
	Global.register_ui_back(self, Callable(self, "dismiss_back"))

func detach_chest() -> void:
	_chest = null
	for slot in _slots:
		if is_instance_valid(slot):
			slot.set("chest_link", null)
	_clear_chest_slots()

func opened_chest() -> Node:
	return _chest

# Called by the chest when it wants the combined panel closed (player walked
# out of range, chest broken, request_close_all_ui). Idempotent, and a no-op
# when a different chest is the one currently attached.
func close_chest(chest: Node) -> void:
	if _chest != null and _chest != chest:
		return
	_close()

func _clear_chest_slots() -> void:
	_chest_slots.clear()
	_chest_title = null
	if _chest_section == null:
		return
	for c in _chest_section.get_children():
		_chest_section.remove_child(c)
		c.queue_free()
	_chest_section.visible = false

func _rebuild_chest_slots() -> void:
	if _chest_section == null:
		return
	_clear_chest_slots()
	if _chest == null or not is_instance_valid(_chest):
		return
	var slots: Array = _chest.get("slots") as Array
	if slots.is_empty():
		return
	var s: float = Global.ui_scale
	_chest_section.visible = true

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", i(8, s))
	_chest_section.add_child(header)

	_chest_title = _lbl("CHEST", i(11, s), C_MUTED)
	header.add_child(_chest_title)

	var hint := _lbl("click to take • drag to move", i(10, s), Color(C_MUTED, 0.7))
	hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hint.horizontal_alignment  = HORIZONTAL_ALIGNMENT_RIGHT
	header.add_child(hint)

	# Cap the storage area's height so a chest with a large configured capacity
	# can never push the player inventory or the panel off-screen — it scrolls.
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode   = ScrollContainer.SCROLL_MODE_AUTO
	var rows: int  = int(ceil(float(slots.size()) / float(CHEST_COLS)))
	var row_h: int = int(Global.ITEM_SLOT_SIZE * s) + i(10, s)
	scroll.custom_minimum_size = Vector2(0, float(mini(row_h * rows, row_h * 3)))
	_chest_section.add_child(scroll)

	var grid := GridContainer.new()
	grid.columns = CHEST_COLS
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", i(10, s))
	grid.add_theme_constant_override("v_separation", i(10, s))
	scroll.add_child(grid)

	for idx in range(slots.size()):
		var slot = SLOT_SCENE.instantiate()
		slot.slot_index    = idx
		slot.is_chest_slot = true
		slot.chest_link    = _chest
		slot.slot_clicked.connect(_on_chest_slot_clicked)
		grid.add_child(slot)
		_chest_slots.append(slot)

	refresh_chest_slots()

# Redraws the chest views from the chest's authoritative slot array.
func refresh_chest_slots() -> void:
	if _chest == null or not is_instance_valid(_chest):
		return
	var slots: Array = _chest.get("slots") as Array
	for idx in range(_chest_slots.size()):
		var slot = _chest_slots[idx]
		if not is_instance_valid(slot):
			continue
		var item_v: Variant = slots[idx] if idx < slots.size() else null
		if item_v == null:
			slot.call("set_empty")
		else:
			slot.call("set_item", item_v)
	if _chest_title != null:
		var chest_name := "CHEST"
		var chest_data: Variant = _chest.get("item_data")
		if chest_data is ItemData and not (chest_data as ItemData).item_name.is_empty():
			chest_name = (chest_data as ItemData).item_name.to_upper()
		_chest_title.text = "%s  (%d)" % [chest_name, slots.size()]

# Clicking a chest slot takes that whole stack into the player inventory —
# the same click convention the rest of the inventory uses.
func _on_chest_slot_clicked(idx: int) -> void:
	if _chest == null or not is_instance_valid(_chest):
		return
	var slots: Array = _chest.get("slots") as Array
	if idx < 0 or idx >= slots.size() or slots[idx] == null:
		return
	if Global.add_item(slots[idx] as Dictionary):
		slots[idx] = null
		Global.Hotbar_updated.emit()
		Global.Inventory_updated.emit()
		if _chest.has_method("notify_contents_changed"):
			_chest.call("notify_contents_changed")

func _build_inv_content(s: float) -> Control:
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", i(10, s))

	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", i(20, s))
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(body)

	var grid_wrap := CenterContainer.new()
	grid_wrap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid_wrap.size_flags_vertical   = Control.SIZE_EXPAND_FILL
	body.add_child(grid_wrap)

	var grid := GridContainer.new()
	grid.columns = COLS
	grid.add_theme_constant_override("h_separation", i(10, s))
	grid.add_theme_constant_override("v_separation",  i(10, s))
	grid_wrap.add_child(grid)

	for idx in range(Global.INVENTORY_SIZE):
		var slot = SLOT_SCENE.instantiate()
		slot.slot_index = idx
		slot.slot_clicked.connect(_on_slot_clicked)
		grid.add_child(slot)
		_slots.append(slot)

	_tip_root = _build_tooltip(s)
	body.add_child(_tip_root)

	# Chest storage sits UNDER the player inventory. Hidden unless a chest is
	# attached, so ordinary inventory opening is completely unchanged.
	_chest_section = VBoxContainer.new()
	_chest_section.visible = false
	_chest_section.add_theme_constant_override("separation", i(6, s))
	root.add_child(_chest_section)

	return root

# Permanent sidebar — always visible, shows the selected item's info or a
# placeholder when nothing is selected.
func _build_tooltip(s: float) -> Control:
	var root := Control.new()
	root.custom_minimum_size   = Vector2(i(220,s), 0)
	root.size_flags_horizontal = Control.SIZE_SHRINK_END
	root.size_flags_vertical   = Control.SIZE_EXPAND_FILL

	var panel := PanelContainer.new()
	var ps    := _sb(C_TIP_BG, C_BORDER, 4, i(12,s), i(12,s), i(12,s), i(12,s))
	panel.add_theme_stylebox_override("panel", ps)
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", i(5, s))
	panel.add_child(vbox)

	_tip_name = _lbl("", i(14,s), C_TITLE)
	_tip_name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(_tip_name)
	_tip_qty    = _lbl("", i(11,s), C_MUTED);  vbox.add_child(_tip_qty)
	_tip_type   = _lbl("", i(11,s), C_MUTED);  vbox.add_child(_tip_type)
	_tip_effect = _lbl("", i(11,s), C_EFFECT); vbox.add_child(_tip_effect)
	_div(vbox)
	_tip_desc = _lbl("", i(11,s), C_MUTED)
	_tip_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(_tip_desc)
	_show_tip_empty()
	return root

func _show_tip_empty() -> void:
	if _tip_name == null: return
	_tip_name.text   = "No item selected"
	_tip_qty.text    = ""
	_tip_type.text   = ""
	_tip_effect.text = ""
	_tip_desc.text   = ""

# ── Crafting content ──────────────────────────────────────────────
func _build_craft_content(s: float) -> Control:
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", i(8, s))

	# Category tabs
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", i(4, s))
	root.add_child(tabs)
	_craft_cat_btns.clear()
	for cat in CRAFT_CATEGORIES:
		var btn := Button.new()
		btn.text = cat
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.add_theme_font_size_override("font_size", i(11, s))
		btn.custom_minimum_size = Vector2(0, i(26, s))
		var c: String = cat as String
		btn.pressed.connect(func() -> void: _craft_on_cat(c))
		tabs.add_child(btn)
		_craft_cat_btns[cat] = btn

	_div(root)

	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", i(10, s))
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(body)

	# Recipe list
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size    = Vector2(i(300, s), 0)
	scroll.size_flags_vertical    = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	body.add_child(scroll)

	_craft_list = GridContainer.new()
	_craft_list.columns = 4
	_craft_list.add_theme_constant_override("h_separation", i(8, s))
	_craft_list.add_theme_constant_override("v_separation", i(8, s))
	_craft_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_craft_list)

	# Detail panel
	_craft_detail = _build_craft_detail(s)
	_craft_detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_craft_detail.size_flags_vertical   = Control.SIZE_EXPAND_FILL
	body.add_child(_craft_detail)
	_craft_detail.visible = false

	return root

func _build_craft_detail(s: float) -> Control:
	var root := PanelContainer.new()
	var ps   := _sb(C_TIP_BG, C_BORDER, 4, i(12,s), i(12,s), i(12,s), i(12,s))
	root.add_theme_stylebox_override("panel", ps)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", i(6, s))
	root.add_child(vbox)

	_craft_name   = _lbl("", i(14,s), C_TITLE); vbox.add_child(_craft_name)
	_div(vbox)
	vbox.add_child(_lbl("INGREDIENTS", i(10,s), C_MUTED))
	_craft_ing1   = _build_craft_icon_row(s); vbox.add_child(_craft_ing1)
	_craft_ing2   = _build_craft_icon_row(s); vbox.add_child(_craft_ing2)
	_div(vbox)
	vbox.add_child(_lbl("RESULT", i(10,s), C_MUTED))
	_craft_result = _build_craft_icon_row(s); vbox.add_child(_craft_result)

	var sp := Control.new(); sp.size_flags_vertical = Control.SIZE_EXPAND_FILL; vbox.add_child(sp)

	_craft_btn = Button.new()
	_craft_btn.text = "CRAFT"
	_craft_btn.custom_minimum_size = Vector2(0, i(36, s))
	_craft_btn.add_theme_font_size_override("font_size", i(12, s))
	_craft_btn.pressed.connect(_on_craft)
	vbox.add_child(_craft_btn)

	return root

# A single icon row (ingredient/result): item icon + a count text. Ref meta
# "icon"/"qty" hold the child nodes for _fill_craft_icon_row.
func _build_craft_icon_row(s: float) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", i(8, s))
	row.add_theme_constant_override("alignment", BoxContainer.ALIGNMENT_CENTER)
	var icon := TextureRect.new()
	icon.custom_minimum_size = Vector2(i(24, s), i(24, s))
	icon.stretch_mode         = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.expand_mode          = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	row.add_child(icon)
	var qty := Label.new()
	qty.add_theme_font_size_override("font_size", i(12, s))
	row.add_child(qty)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.set_meta("icon", icon)
	row.set_meta("qty", qty)
	return row

# Fills an icon row: icon + count. For ingredients (is_ingredient) the icon is
# darkened when the player has none and the count is RED when they don't have
# enough; for the result it stays full-colour with a ×quantity count.
func _fill_craft_icon_row(row: HBoxContainer, data: ItemData, needed: int, is_ingredient: bool) -> void:
	var icon := row.get_meta("icon") as TextureRect
	var qty  := row.get_meta("qty") as Label
	if icon == null or qty == null or data == null:
		return
	icon.texture = data.icon if data.icon != null else null
	var have: int = _count_item(data) if is_ingredient else needed
	icon.modulate = Color(0.35, 0.35, 0.35, 1.0) if (is_ingredient and have <= 0) else Color.WHITE
	if is_ingredient:
		qty.text = "%d/%d" % [have, needed]
		qty.add_theme_color_override("font_color",
			C_RED if have < needed else C_MUTED)
	else:
		qty.text = "×%d" % needed
		qty.add_theme_color_override("font_color", C_EFFECT)

# ── Crafting logic ────────────────────────────────────────────────
func _craft_on_cat(cat: String) -> void:
	_active_cat = cat; _selected_idx = -1
	if _craft_detail != null: _craft_detail.visible = false
	_craft_highlight_tabs()
	_craft_filter_refresh()

func _craft_highlight_tabs() -> void:
	for c in _craft_cat_btns:
		var btn: Button = _craft_cat_btns[c] as Button
		var act: bool   = c == _active_cat
		var ps := _sb(C_SEL if act else C_TIP_BG, C_BORDER, 3, 8, 8, 4, 4)
		btn.add_theme_stylebox_override("normal",  ps)
		btn.add_theme_stylebox_override("hover",   ps)
		btn.add_theme_stylebox_override("pressed", ps)
		btn.add_theme_color_override("font_color", C_TITLE if act else C_MUTED)

func _craft_filter_refresh() -> void:
	_filtered = []; _craft_row_btns = []
	for r in _recipes:
		# _recipes already excludes requires_station; just filter by category
		if (r as CraftingRecipe).category == _active_cat:
			_filtered.append(r)
	if _craft_list == null: return
	for child in _craft_list.get_children():
		child.queue_free()
	if _filtered.is_empty():
		_craft_list.add_child(_lbl("No recipes.", 11, C_MUTED)); return
	var s: float = Global.ui_scale
	for idx in range(_filtered.size()):
		var r: CraftingRecipe = _filtered[idx] as CraftingRecipe
		var btn := Button.new()
		btn.custom_minimum_size     = Vector2(Global.ITEM_SLOT_SIZE * s, Global.ITEM_SLOT_SIZE * s)
		btn.icon                    = r.result_item.icon
		btn.expand_icon             = true
		btn.icon_alignment          = HORIZONTAL_ALIGNMENT_CENTER
		btn.vertical_icon_alignment = VERTICAL_ALIGNMENT_CENTER
		btn.tooltip_text            = r.result_item.item_name
		var res: ItemData = r.result_item
		btn.mouse_entered.connect(func() -> void: Global.show_item_tooltip({"data": res, "quantity": 1}))
		btn.mouse_exited.connect(func() -> void: Global.hide_item_tooltip())
		var i2 := idx
		btn.pressed.connect(func() -> void: _craft_select(i2))
		_craft_list.add_child(btn)
		_craft_row_btns.append(btn)
	_refresh_crafting()
	_craft_highlight_tabs()

func _count_item(data: ItemData) -> int:
	var n: int = 0
	for slot in Global.Hotbar:
		if slot != null and (slot as Dictionary)["data"] == data:
			n += (slot as Dictionary)["quantity"]
	for slot in Global.Inventory:
		if slot != null and (slot as Dictionary)["data"] == data:
			n += (slot as Dictionary)["quantity"]
	return n

enum CraftState { CAN, NO_MATS }

func _craft_state(r: CraftingRecipe) -> CraftState:
	var ok: bool = _count_item(r.ingredient_1) >= r.ingredient_1_quantity
	if r.ingredient_2 != null:
		ok = ok and _count_item(r.ingredient_2) >= r.ingredient_2_quantity
	return CraftState.CAN if ok else CraftState.NO_MATS

func _refresh_crafting() -> void:
	for idx in range(_craft_row_btns.size()):
		if idx >= _filtered.size(): break
		var r: CraftingRecipe = _filtered[idx] as CraftingRecipe
		var state: CraftState = _craft_state(r)
		var btn: Button       = _craft_row_btns[idx] as Button
		var bg: Color; var fc: Color; var mod: float
		match state:
			CraftState.CAN:     bg = C_TIP_BG; fc = C_TITLE; mod = 1.0
			CraftState.NO_MATS: bg = C_TIP_BG; fc = C_MUTED; mod = 0.55
		var ps := _sb(bg, C_BORDER, 4, 4, 4, 4, 4)
		btn.add_theme_stylebox_override("normal",  ps)
		btn.add_theme_stylebox_override("hover",   ps)
		btn.add_theme_stylebox_override("pressed", ps)
		btn.add_theme_color_override("font_color", fc)
		btn.modulate = Color(mod, mod, mod, 1.0)
	if _selected_idx >= 0 and _selected_idx < _filtered.size():
		_update_craft_btn(_filtered[_selected_idx] as CraftingRecipe)

func _craft_select(idx: int) -> void:
	_selected_idx = idx
	var r: CraftingRecipe = _filtered[idx] as CraftingRecipe
	_craft_name.text  = r.result_item.item_name
	_fill_craft_icon_row(_craft_ing1, r.ingredient_1, r.ingredient_1_quantity, true)
	if r.ingredient_2 != null:
		_fill_craft_icon_row(_craft_ing2, r.ingredient_2, r.ingredient_2_quantity, true)
		_craft_ing2.visible = true
	else:
		_craft_ing2.visible = false
	_fill_craft_icon_row(_craft_result, r.result_item, r.result_quantity, false)
	_craft_detail.visible = true
	_update_craft_btn(r)

func _update_craft_btn(r: CraftingRecipe) -> void:
	var state: CraftState = _craft_state(r)
	match state:
		CraftState.CAN:
			_craft_btn.text = "CRAFT"; _craft_btn.disabled = false
			var ps := _sb(C_CAN_CRAFT, C_BORDER, 4, 8, 8, 6, 6)
			_craft_btn.add_theme_stylebox_override("normal", ps)
			_craft_btn.add_theme_color_override("font_color", Color(0.8, 1.0, 0.8, 1.0))
		CraftState.NO_MATS:
			_craft_btn.text = "MISSING MATERIALS"; _craft_btn.disabled = true
			var ps := _sb(C_NO_MAT, C_BORDER, 4, 8, 8, 6, 6)
			_craft_btn.add_theme_stylebox_override("normal", ps)
			_craft_btn.add_theme_color_override("font_color", Color(1.0, 0.7, 0.7, 1.0))

func _on_craft() -> void:
	if _selected_idx < 0: return
	var r: CraftingRecipe = _filtered[_selected_idx] as CraftingRecipe
	if _craft_state(r) != CraftState.CAN: return
	for _n in range(r.ingredient_1_quantity):
		Global.remove_item(r.ingredient_1)
	if r.ingredient_2 != null:
		for _n in range(r.ingredient_2_quantity):
			Global.remove_item(r.ingredient_2)
	Global.add_item({"quantity": r.result_quantity, "data": r.result_item})
	Global.complete_mission("craft_item")
	_update_craft_btn(r)
	_refresh_crafting()

# ── Inventory logic ───────────────────────────────────────────────
func _refresh_inv() -> void:
	# The chest section (when one is docked) renders from the chest's own array,
	# but it must follow the same refresh signal as the player grid.
	refresh_chest_slots()
	if _slots.is_empty(): return
	for idx in range(_slots.size()):
		var item = Global.Inventory[idx] if idx < Global.Inventory.size() else null
		if item != null: _slots[idx].set_item(item)
		else:            _slots[idx].set_empty()
	if _active_idx < 0: return
	var active_item: Variant = Global.Inventory[_active_idx] \
		if _active_idx < Global.Inventory.size() else null
	if active_item == null:
		_active_idx = -1
		_show_tip_empty()
	elif _tip_qty != null:
		var data = active_item["data"] as ItemData
		var limit = data.max_stack_size if data != null and data.max_stack_size > 0 else Global.MAX_STACK
		_tip_qty.text = "Qty: %d / %d" % [active_item["quantity"], limit]

func _on_slot_clicked(idx: int) -> void:
	if _tip_root == null: return
	var item = Global.Inventory[idx] if idx < Global.Inventory.size() else null
	if item == null:
		_active_idx = -1
		_show_tip_empty()
		return
	_active_idx = idx
	var data: ItemData = item["data"] as ItemData
	var limit = data.max_stack_size if data != null and data.max_stack_size > 0 else Global.MAX_STACK
	_tip_name.text   = data.item_name
	_tip_qty.text    = "Qty: %d / %d" % [item["quantity"], limit]
	_tip_type.text   = data.item_type.capitalize()
	_tip_effect.text = ("+ " + data.effect) if data.effect != "" else ""
	_tip_desc.text   = data.description

func dismiss_back() -> void:
	var was_open: bool = false
	var layer: Node = get_parent()
	if layer != null:
		was_open = bool(layer.get("visible"))
	_close()
	if was_open:
		Global.inventory_toggled.emit(false)

func _close() -> void:
	Global.unregister_ui_back(self)
	# Idempotent: releasing the pause twice for one open would underflow the
	# shared refcount and resume gameplay while another UI was still open.
	#
	# NOTE: the parent is a CanvasLayer — it HAS a `visible` property but is NOT
	# a CanvasItem. Casting it to CanvasItem yields null, so the access must be
	# duck-typed (this is what crashed every close with
	# "Invalid access to property or key 'visible' on a base object of type 'Nil'").
	#
	# Any chest docked into this panel is released FIRST, even when something
	# else already hid the layer (the player's close-all path): otherwise the
	# chest would keep believing its UI is open and refuse to reopen. The chest
	# keeps its contents — closing only tears down the views.
	if _chest != null:
		if is_instance_valid(_chest) and _chest.has_method("on_inventory_ui_closed"):
			_chest.call("on_inventory_ui_closed")
		detach_chest()
	var layer: Node = get_parent()
	if layer == null:
		Global.close_ui()
		return
	if not bool(layer.get("visible")):
		return
	layer.set("visible", false)
	Global.close_ui()

# ── Helpers ───────────────────────────────────────────────────────
func i(base: int, s: float) -> int: return int(base * s)

func _sb(bg: Color, border: Color, r: int, ml: int, mr: int, mt: int, mb: int) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg; sb.border_color = border
	sb.set_border_width_all(1); sb.set_corner_radius_all(r)
	sb.content_margin_left = ml; sb.content_margin_right  = mr
	sb.content_margin_top  = mt; sb.content_margin_bottom = mb
	return sb

func _lbl(text: String, size: int, col: Color) -> Label:
	var l := Label.new(); l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	return l

func _div(parent: Node) -> void:
	var d := ColorRect.new()
	d.color = C_DIVIDER; d.custom_minimum_size = Vector2(0, 1)
	parent.add_child(d)
