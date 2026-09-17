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
var _tab_inv_btn:  Button
var _tab_craft_btn: Button

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

# Closing via the same "inventory" key is handled here rather than relying
# on player.gd to see the press: once this panel's CanvasLayer is visible,
# its own UI tree gets input priority over the Player node, so the
# re-press was never reaching player.gd's _input(). Guarded on the parent
# CanvasLayer's visibility (which is what actually shows/hides the panel),
# so this is a no-op — not a double-toggle — if something else already
# closed it first.
func _input(event: InputEvent) -> void:
	if get_parent().visible and event.is_action_pressed("inventory"):
		get_viewport().set_input_as_handled()
		_close()
		Global.inventory_toggled.emit(false)

func _on_ui_scale(_s: float) -> void:
	_rebuild()

func _load_recipes() -> void:
	_recipes.clear()
	var dir := DirAccess.open(RECIPE_DIR)
	if dir == null:
		push_error("InventoryUI: cannot open recipe dir: " + RECIPE_DIR)
		return
	dir.list_dir_begin()
	var fname: String = dir.get_next()
	while fname != "":
		if not dir.current_is_dir() and fname.ends_with(".tres"):
			var res: Resource = load(RECIPE_DIR + fname) as Resource
			if res != null and res is CraftingRecipe:
				var r: CraftingRecipe = res as CraftingRecipe
				# Inventory crafting: only hand-craftable (no station required)
				if r.result_item != null and r.result_item.is_craftable and not r.requires_station:
					_recipes.append(r)
		fname = dir.get_next()
	dir.list_dir_end()

# ── Build ─────────────────────────────────────────────────────────
func _rebuild() -> void:
	_rebuild_ver += 1
	var my_ver: int = _rebuild_ver
	_slots = []; _tip_root = null; _craft_list = null; _craft_detail = null
	_craft_cat_btns.clear(); _craft_row_btns.clear()
	_tip_name = null; _tip_type = null; _tip_effect = null; _tip_qty = null; _tip_desc = null
	_active_idx = -1; _selected_idx = -1
	for child in get_children():
		child.queue_free()
	await get_tree().process_frame
	if _rebuild_ver != my_ver:
		return
	_build()
	_refresh_inv()
	_switch_tab("inventory")

func _build() -> void:
	var s: float = Global.ui_scale

	var overlay := ColorRect.new()
	overlay.color = C_OVERLAY
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(overlay)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 0)
	center.add_child(outer)

	# ── Tab row ───────────────────────────────────────────────────
	var tab_row := HBoxContainer.new()
	tab_row.add_theme_constant_override("separation", 2)
	outer.add_child(tab_row)

	_tab_inv_btn   = _make_tab("INVENTORY", true,  s, func(): _switch_tab("inventory"))
	_tab_craft_btn = _make_tab("✦ CRAFT",  false, s, func(): _switch_tab("craft"))
	tab_row.add_child(_tab_inv_btn)
	tab_row.add_child(_tab_craft_btn)

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
	_inv_panel.visible   = inv_active
	_craft_panel.visible = craft_active
	_style_tab_btn(_tab_inv_btn,   inv_active)
	_style_tab_btn(_tab_craft_btn, craft_active)
	if craft_active:
		_active_cat   = "Materials"
		_selected_idx = -1
		_craft_filter_refresh()

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

# ── Inventory content ─────────────────────────────────────────────
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

func _close() -> void:
	get_parent().visible = false
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
