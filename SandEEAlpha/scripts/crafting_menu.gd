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

const CATEGORIES  := ["Materials", "Blocks", "Weapons & Tools", "Others"]

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

# ── Node refs ─────────────────────────────────────────────────────
var _recipe_list:   GridContainer
var _detail_panel:  Control
var _detail_name:   Label
var _detail_ing1:   Label
var _detail_ing2:   Label
var _detail_result: Label
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
	_load_recipes()
	_build()
	Global.Inventory_updated.connect(_refresh_highlights)
	Global.Hotbar_updated.connect(_refresh_highlights)
	Global.ui_scale_changed.connect(_on_ui_scale)
	visible = false

func _on_ui_scale(_s: float) -> void:
	var was_visible: bool = visible
	for child in get_children():
		child.queue_free()
	_cat_btns.clear()
	_row_btns.clear()
	_recipe_list  = null
	_detail_panel = null
	_selected_idx = -1
	await get_tree().process_frame
	_build()
	_filter_and_refresh()
	visible = was_visible

func _load_recipes() -> void:
	var dir := DirAccess.open(RECIPE_DIR)
	if dir == null:
		push_error("CraftingMenu: cannot open recipe dir: " + RECIPE_DIR)
		return
	dir.list_dir_begin()
	var fname: String = dir.get_next()
	while fname != "":
		if not dir.current_is_dir() and fname.ends_with(".tres"):
			var res: Resource = load(RECIPE_DIR + fname) as Resource
			if res != null and res is CraftingRecipe:
				var recipe: CraftingRecipe = res as CraftingRecipe
				if recipe.result_item != null and recipe.result_item.is_craftable:
					_recipes.append(recipe)
		fname = dir.get_next()
	dir.list_dir_end()

# ── Public: open this menu in station mode ─────────────────────────
func open_as_station() -> void:
	_station_mode = true
	if _title_label != null:
		_title_label.text = "CRAFTING STATION"
	_selected_idx = -1
	if _detail_panel != null:
		_detail_panel.visible = false
	_filter_and_refresh()
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

	# Left tab strip
	var tab_strip := PanelContainer.new()
	var ts_ps := _sb(C_TAB_BG, C_BORDER, 6, 0, 0, 0, 0)
	tab_strip.add_theme_stylebox_override("panel", ts_ps)
	tab_strip.custom_minimum_size = Vector2(40 * s, 0)
	outer.add_child(tab_strip)

	var tab_vbox := VBoxContainer.new()
	tab_vbox.add_theme_constant_override("separation", 2)
	tab_strip.add_child(tab_vbox)

	var icon_rect := TextureRect.new()
	icon_rect.custom_minimum_size  = Vector2(28 * s, 28 * s)
	icon_rect.stretch_mode         = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon_rect.expand_mode          = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	icon_rect.modulate             = C_MUTED
	tab_vbox.add_child(icon_rect)

	var tab_label_wrap := Control.new()
	tab_label_wrap.custom_minimum_size = Vector2(36 * s, 100 * s)
	tab_vbox.add_child(tab_label_wrap)
	var tab_lbl := Label.new()
	tab_lbl.text = "STATION"
	tab_lbl.add_theme_font_size_override("font_size", int(10 * s))
	tab_lbl.add_theme_color_override("font_color", C_TITLE)
	tab_lbl.rotation_degrees = 90.0
	tab_lbl.position         = Vector2(28 * s, 8 * s)
	tab_label_wrap.add_child(tab_lbl)

	# Main panel
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(600 * s, 420 * s)
	var ps := _sb(C_PANEL, C_BORDER, 6, int(16*s), int(16*s), int(14*s), int(16*s))
	panel.add_theme_stylebox_override("panel", ps)
	outer.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", int(10 * s))
	panel.add_child(vbox)

	# Header
	var header := HBoxContainer.new()
	vbox.add_child(header)
	_title_label = _lbl("CRAFTING STATION", int(16 * s), C_TITLE)
	_title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(_title_label)
	var close := Button.new()
	close.text = "✕"
	close.flat = true
	close.add_theme_color_override("font_color", C_MUTED)
	close.pressed.connect(hide_menu)
	header.add_child(close)

	_div(vbox)

	# Category tabs
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", int(6 * s))
	vbox.add_child(tabs)
	for cat in CATEGORIES:
		var btn := Button.new()
		btn.text                  = cat
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.custom_minimum_size   = Vector2(0, int(30 * s))
		btn.add_theme_font_size_override("font_size", int(12 * s))
		var c: String = cat as String
		btn.pressed.connect(func() -> void: _on_category(c))
		tabs.add_child(btn)
		_cat_btns[cat] = btn
	_highlight_tab("Materials")

	_div(vbox)

	# Body
	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", int(12 * s))
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(body)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size    = Vector2(int(200 * s), 0)
	scroll.size_flags_vertical    = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	body.add_child(scroll)

	_recipe_list = GridContainer.new()
	_recipe_list.columns = 3
	_recipe_list.add_theme_constant_override("h_separation", int(4 * s))
	_recipe_list.add_theme_constant_override("v_separation", int(4 * s))
	_recipe_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_recipe_list)

	_detail_panel = _build_detail(s)
	_detail_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_detail_panel.size_flags_vertical   = Control.SIZE_EXPAND_FILL
	body.add_child(_detail_panel)
	_detail_panel.visible = false

	_filter_and_refresh()

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
	_detail_ing1 = _lbl("", int(13 * s), C_TITLE)
	vbox.add_child(_detail_ing1)
	_detail_ing2 = _lbl("", int(13 * s), C_TITLE)
	vbox.add_child(_detail_ing2)
	_div(vbox)
	vbox.add_child(_lbl("RESULT", int(11 * s), C_MUTED))
	_detail_result = _lbl("", int(13 * s), C_EFFECT)
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
func _count_item(data: ItemData) -> int:
	var total: int = 0
	for slot in Global.Hotbar:
		if slot != null and (slot as Dictionary)["data"] == data:
			total += (slot as Dictionary)["quantity"]
	for slot in Global.Inventory:
		if slot != null and (slot as Dictionary)["data"] == data:
			total += (slot as Dictionary)["quantity"]
	return total

enum CraftState { CAN_CRAFT, NO_MATS }

func _craft_state(recipe: CraftingRecipe) -> CraftState:
	var has_mats: bool = _count_item(recipe.ingredient_1) >= recipe.ingredient_1_quantity
	if recipe.ingredient_2 != null:
		has_mats = has_mats and \
			_count_item(recipe.ingredient_2) >= recipe.ingredient_2_quantity
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
		btn.custom_minimum_size     = Vector2(int(56 * s), int(56 * s))
		btn.icon                    = recipe.result_item.icon
		btn.expand_icon             = true
		btn.icon_alignment          = HORIZONTAL_ALIGNMENT_CENTER
		btn.vertical_icon_alignment = VERTICAL_ALIGNMENT_CENTER
		btn.tooltip_text            = recipe.result_item.item_name
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
	_detail_ing1.text    = "• %s ×%d" % [recipe.ingredient_1.item_name, recipe.ingredient_1_quantity]
	if recipe.ingredient_2 != null:
		_detail_ing2.text    = "• %s ×%d" % [recipe.ingredient_2.item_name, recipe.ingredient_2_quantity]
		_detail_ing2.visible = true
	else:
		_detail_ing2.visible = false
	_detail_result.text   = "%s ×%d" % [recipe.result_item.item_name, recipe.result_quantity]
	_detail_panel.visible = true
	_update_craft_btn(recipe)

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
	_update_craft_btn(recipe)
	_refresh_highlights()

# ── Show / Hide ───────────────────────────────────────────────────
func show_menu() -> void:
	visible = true
	Global.open_ui()

func hide_menu() -> void:
	if not visible:
		return
	visible = false
	Global.close_ui()

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("escape") and visible:
		get_viewport().set_input_as_handled()
		hide_menu()
