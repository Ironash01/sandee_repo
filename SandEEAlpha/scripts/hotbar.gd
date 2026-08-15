extends Control

var slots: Array = []
var selected_index: int = 0

const C_SLOT_BG  := Color(0.11, 0.15, 0.26, 1.00)
const C_SLOT_SEL := Color(0.25, 0.40, 0.75, 1.00)

const C_HEALTH_FILL  := Color(0.85, 0.15, 0.15, 1.00)
const C_HEALTH_BG    := Color(0.22, 0.04, 0.04, 1.00)
const C_STAMINA_FILL := Color(0.85, 0.78, 0.15, 1.00)
const C_STAMINA_BG   := Color(0.26, 0.22, 0.04, 1.00)
# 9 slots × 40 px + 8 gaps × 4 px = 392 — must match the hotbar HBoxContainer width
const HOTBAR_PX := 392
const BAR_H     := 8

const SLOT_SIZE    := 40
const SLOT_SCRIPT  := preload("res://scripts/hotbar_slot.gd")

# ── Stat bars ─────────────────────────────────────────────────────
var _stat_container: Control  = null
var _health_fill:   ColorRect = null
var _stamina_fill:  ColorRect = null
var _health_bg:     Control   = null
var _stamina_bg:    Control   = null

# ── Build mode indicator ──────────────────────────────────────────
var _build_label: Label = null

# ── Pickup popup ──────────────────────────────────────────────────
var _popup_label: Label       = null
var _hover_label: Label       = null
var _item_tip_label: Label    = null
var _popup_tween:  Tween       = null
var _popup_timer:  float       = 0.0
const POPUP_DURATION := 1.8

# ── Lua-stuck alert ─────────────────────────────────────────────────
var _stuck_label: Label = null
var _stuck_tween: Tween = null
const STUCK_POPUP_DURATION := 3.0

func _ready() -> void:
	var hbox: HBoxContainer = $CanvasLayer/HBoxContainer as HBoxContainer
	hbox.add_theme_constant_override("separation", 4)

	var slot_idx: int = 0
	for child in hbox.get_children():
		if not (child is TextureRect):
			continue

		# Attach hotbar_slot.gd so the TextureRect can handle drops
		child.set_script(SLOT_SCRIPT)
		child.set("slot_index", slot_idx)
		slot_idx += 1

		slots.append(child)
		_style_slot(child as TextureRect)

		# TextureRect icon — auto-scales and centres
		var icon := TextureRect.new()
		icon.name         = "ItemIcon"
		icon.expand_mode  = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.set_anchors_preset(Control.PRESET_FULL_RECT)
		icon.offset_left   =  4
		icon.offset_top    =  4
		icon.offset_right  = -4
		icon.offset_bottom = -4
		icon.mouse_filter  = Control.MOUSE_FILTER_IGNORE
		icon.visible       = false
		child.add_child(icon)

		var label := Label.new()
		label.name = "Quantity"
		label.add_theme_font_size_override("font_size", 10)
		label.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
		label.offset_left  = -14
		label.offset_top   = -14
		label.visible      = false
		child.add_child(label)

		# Item-description tooltip on hover — read the slot's own index (the
		# loop counter is already incremented past it by this point).
		var this_idx: int = int(child.get("slot_index"))
		child.mouse_entered.connect(_on_slot_mouse_entered.bind(this_idx))
		child.mouse_exited.connect(_on_slot_mouse_exited)

	# ── Build Mode Label (above HBoxContainer) ────────────────────
	var canvas: CanvasLayer = $CanvasLayer as CanvasLayer
	_build_label = Label.new()
	_build_label.name = "BuildModeLabel"
	_build_label.text = "⚒ BUILD MODE"
	_build_label.add_theme_color_override("font_color", Color(0.85, 0.95, 1.0, 1.0))
	_build_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	_build_label.add_theme_constant_override("shadow_offset_x", 1)
	_build_label.add_theme_constant_override("shadow_offset_y", 1)
	_build_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_build_label.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_build_label.visible = false
	canvas.add_child(_build_label)

	# ── Pickup popup label ────────────────────────────────────────
	_popup_label = Label.new()
	_popup_label.name = "PickupPopup"
	_popup_label.add_theme_color_override("font_color", Color(1.0, 1.0, 0.8, 1.0))
	_popup_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	_popup_label.add_theme_constant_override("shadow_offset_x", 1)
	_popup_label.add_theme_constant_override("shadow_offset_y", 1)
	_popup_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_popup_label.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_popup_label.modulate.a = 0.0
	canvas.add_child(_popup_label)

	# ── Lua-stuck alert label (top-center) ────────────────────────
	_stuck_label = Label.new()
	_stuck_label.name = "LuaStuckPopup"
	_stuck_label.add_theme_color_override("font_color", Color(1.0, 0.35, 0.3, 1.0))
	_stuck_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	_stuck_label.add_theme_constant_override("shadow_offset_x", 1)
	_stuck_label.add_theme_constant_override("shadow_offset_y", 1)
	_stuck_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_stuck_label.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_stuck_label.modulate.a = 0.0
	canvas.add_child(_stuck_label)

	# ── Block hover label (bottom-left) ──────────────────────────
	_hover_label = Label.new()
	_hover_label.name = "BlockHoverLabel"
	_hover_label.add_theme_color_override("font_color", Color(1.0, 1.0, 0.9, 1.0))
	_hover_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	_hover_label.add_theme_constant_override("shadow_offset_x", 1)
	_hover_label.add_theme_constant_override("shadow_offset_y", 1)
	_hover_label.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_hover_label.visible = false
	canvas.add_child(_hover_label)

	# ── Item-description tooltip (bottom-left, above the block label) ──
	# Shown while hovering a hotbar slot with an item. Separate from
	# _hover_label so the block-aim label isn't clobbered.
	_item_tip_label = Label.new()
	_item_tip_label.name = "ItemTipLabel"
	_item_tip_label.add_theme_color_override("font_color", Color(1.0, 1.0, 0.8, 1.0))
	_item_tip_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	_item_tip_label.add_theme_constant_override("shadow_offset_x", 1)
	_item_tip_label.add_theme_constant_override("shadow_offset_y", 1)
	_item_tip_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_item_tip_label.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_item_tip_label.visible = false
	canvas.add_child(_item_tip_label)

	_build_stat_bars(canvas)
	_apply_label_scale()

	Global.ui_scale_changed.connect(func(_s: float) -> void: _apply_label_scale())
	Global.Hotbar_updated.connect(_refresh_hotbar)
	Global.hotbar_selection_changed.connect(_on_selection_changed)
	Global.inventory_toggled.connect(_on_inventory_toggled)
	Global.block_mode_changed.connect(_on_build_mode_changed)
	Global.item_picked_up.connect(_on_item_picked_up)
	Global.lua_stuck_notice.connect(_on_lua_stuck_notice)
	Global.hover_label_changed.connect(_on_hover_label_changed)
	Global.health_changed.connect(_on_health_changed)
	Global.stamina_changed.connect(_on_stamina_changed)

	_refresh_hotbar()
	_highlight_slot(0)

func _style_slot(slot: TextureRect) -> void:
	slot.texture               = null
	slot.custom_minimum_size   = Vector2(SLOT_SIZE, SLOT_SIZE)
	slot.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	slot.size_flags_vertical   = Control.SIZE_SHRINK_CENTER
	slot.expand_mode           = TextureRect.EXPAND_IGNORE_SIZE

	var bg := ColorRect.new()
	bg.name         = "SlotBG"
	bg.color        = C_SLOT_BG
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	slot.add_child(bg)
	slot.move_child(bg, 0)

func _on_inventory_toggled(_is_open: bool) -> void:
	pass  # hotbar stays fully visible when inventory is open

func _on_build_mode_changed(enabled: bool) -> void:
	if _build_label != null:
		_build_label.visible = enabled

func _on_item_picked_up(item_name: String, item_type: String) -> void:
	if _popup_label == null:
		return
	# Format: "Wood  [block]"
	var type_display: String = item_type.capitalize()
	_popup_label.text = "%s  [%s]" % [item_name, type_display]

	# Kill any running tween and restart
	if _popup_tween != null and _popup_tween.is_valid():
		_popup_tween.kill()

	_popup_tween = create_tween()
	# Fade in quickly, hold, then fade out
	_popup_tween.tween_property(_popup_label, "modulate:a", 1.0, 0.15)
	_popup_tween.tween_interval(POPUP_DURATION - 0.45)
	_popup_tween.tween_property(_popup_label, "modulate:a", 0.0, 0.30)

func _on_lua_stuck_notice(message: String) -> void:
	if _stuck_label == null:
		return
	_stuck_label.text = message

	if _stuck_tween != null and _stuck_tween.is_valid():
		_stuck_tween.kill()

	_stuck_tween = create_tween()
	_stuck_tween.tween_property(_stuck_label, "modulate:a", 1.0, 0.15)
	_stuck_tween.tween_interval(STUCK_POPUP_DURATION - 0.45)
	_stuck_tween.tween_property(_stuck_label, "modulate:a", 0.0, 0.30)

func _input(event: InputEvent) -> void:
	for i in range(9):
		if event.is_action_pressed("hotbar_%d" % (i + 1)):
			Global.set_hotbar_selection(i)
			return
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			Global.set_hotbar_selection((selected_index - 1 + 9) % 9)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			Global.set_hotbar_selection((selected_index + 1) % 9)

func _on_selection_changed(index: int) -> void:
	_highlight_slot(index)

func _highlight_slot(index: int) -> void:
	if selected_index < slots.size():
		var prev_bg: ColorRect = \
			(slots[selected_index] as TextureRect).get_node_or_null("SlotBG") as ColorRect
		if prev_bg != null:
			prev_bg.color = C_SLOT_BG

	selected_index = index

	if selected_index < slots.size():
		var bg: ColorRect = \
			(slots[selected_index] as TextureRect).get_node_or_null("SlotBG") as ColorRect
		if bg != null:
			bg.color = C_SLOT_SEL

func _apply_label_scale() -> void:
	var s: float = Global.ui_scale
	var fs_build: int = int(15 * s)
	var fs_popup: int = int(15 * s)
	var fs_hover: int = int(15 * s)
	var fs_stuck: int = int(20 * s)
	if _build_label != null:
		_build_label.add_theme_font_size_override("font_size", fs_build)
		_build_label.offset_top    = int(-80 * s)
		_build_label.offset_bottom = int(-56 * s)
	if _popup_label != null:
		_popup_label.add_theme_font_size_override("font_size", fs_popup)
		_popup_label.offset_top    = int(-108 * s)
		_popup_label.offset_bottom = int(-80  * s)
	if _hover_label != null:
		_hover_label.add_theme_font_size_override("font_size", fs_hover)
		_hover_label.offset_left   = int(14 * s)
		_hover_label.offset_top    = int(-44 * s)
		_hover_label.offset_right  = int(320 * s)
		_hover_label.offset_bottom = int(-12 * s)
	if _item_tip_label != null:
		_item_tip_label.add_theme_font_size_override("font_size", int(12 * s))
		_item_tip_label.offset_left   = int(14 * s)
		_item_tip_label.offset_top    = int(-72 * s)
		_item_tip_label.offset_right  = int(320 * s)
		_item_tip_label.offset_bottom = int(-48 * s)
	if _stuck_label != null:
		_stuck_label.add_theme_font_size_override("font_size", fs_stuck)
		_stuck_label.offset_top    = int(24 * s)
		_stuck_label.offset_bottom = int(56 * s)
	if _stat_container != null:
		_stat_container.offset_top    = -64
		_stat_container.offset_bottom = -44

func _on_hover_label_changed(text: String) -> void:
	if _hover_label == null:
		return
	_hover_label.text    = text
	_hover_label.visible = text != ""

# ── Item-description tooltip (hotbar hover) ────────────────────────
func _on_slot_mouse_entered(slot_idx: int) -> void:
	if slot_idx < 0 or slot_idx >= Global.Hotbar.size():
		return
	var item: Variant = Global.Hotbar[slot_idx]
	if item == null:
		_show_item_tip("")
		return
	var data: ItemData = (item as Dictionary)["data"] as ItemData
	# Prefer the real description; fall back to "Name [type]" so items
	# without a description still give hover feedback.
	var text: String = data.description
	if text == "":
		text = "%s [%s]" % [data.item_name, data.item_type.capitalize()]
	_show_item_tip(text)

func _on_slot_mouse_exited() -> void:
	_show_item_tip("")

func _show_item_tip(text: String) -> void:
	if _item_tip_label == null:
		return
	_item_tip_label.text    = text
	_item_tip_label.visible = text != ""

# ── Stat bar builders ─────────────────────────────────────────────
func _build_stat_bars(canvas: CanvasLayer) -> void:
	_stat_container = CenterContainer.new()
	_stat_container.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	canvas.add_child(_stat_container)

	# Fixed width matches the hotbar exactly so bar edges align
	var outer := HBoxContainer.new()
	outer.custom_minimum_size = Vector2(HOTBAR_PX, 0)
	outer.add_theme_constant_override("separation", 8)
	_stat_container.add_child(outer)

	var hp_data := _make_stat_row("HP", C_HEALTH_BG, C_HEALTH_FILL)
	_health_bg   = hp_data[0] as Control
	_health_fill = hp_data[1] as ColorRect
	outer.add_child(hp_data[2] as Node)

	var sp_data := _make_stat_row("SP", C_STAMINA_BG, C_STAMINA_FILL)
	_stamina_bg   = sp_data[0] as Control
	_stamina_fill = sp_data[1] as ColorRect
	outer.add_child(sp_data[2] as Node)

func _make_stat_row(lbl_text: String, bg_col: Color, fill_col: Color) -> Array:
	var row := HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 4)

	var lbl := Label.new()
	lbl.text = lbl_text
	lbl.add_theme_font_size_override("font_size", 11)
	lbl.add_theme_color_override("font_color", Color(0.80, 0.90, 1.00, 1.00))
	lbl.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	lbl.add_theme_constant_override("shadow_offset_x", 1)
	lbl.add_theme_constant_override("shadow_offset_y", 1)
	lbl.custom_minimum_size = Vector2(20, 0)
	lbl.vertical_alignment  = VERTICAL_ALIGNMENT_CENTER
	row.add_child(lbl)

	# Expands to fill its share of HOTBAR_PX — no fixed width needed
	var bar_bg := Control.new()
	bar_bg.custom_minimum_size   = Vector2(0, BAR_H)
	bar_bg.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar_bg.size_flags_vertical   = Control.SIZE_SHRINK_CENTER
	row.add_child(bar_bg)

	var bg_rect := ColorRect.new()
	bg_rect.color = bg_col
	bg_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	bar_bg.add_child(bg_rect)

	var fill := ColorRect.new()
	fill.color         = fill_col
	fill.anchor_left   = 0.0;  fill.anchor_top    = 0.0
	fill.anchor_right  = 1.0;  fill.anchor_bottom = 1.0
	fill.offset_left   = 0;    fill.offset_top    = 0
	fill.offset_right  = 0;    fill.offset_bottom = 0
	bar_bg.add_child(fill)

	return [bar_bg, fill, row]

func _on_health_changed(value: float, max_v: float) -> void:
	if _health_fill != null:
		_health_fill.anchor_right = clampf(value / max_v, 0.0, 1.0) if max_v > 0.0 else 0.0

func _on_stamina_changed(value: float, max_v: float) -> void:
	if _stamina_fill != null:
		_stamina_fill.anchor_right = clampf(value / max_v, 0.0, 1.0) if max_v > 0.0 else 0.0

func _refresh_hotbar() -> void:
	for i in range(min(slots.size(), Global.HOTBAR_SIZE)):
		var slot:  TextureRect = slots[i] as TextureRect
		var icon:  TextureRect = slot.get_node_or_null("ItemIcon") as TextureRect
		var label: Label       = slot.get_node_or_null("Quantity") as Label
		if icon == null or label == null:
			continue
		var item: Variant = Global.Hotbar[i]
		if item != null:
			var data: ItemData = (item as Dictionary)["data"] as ItemData
			icon.texture  = data.icon
			icon.visible  = true
			label.text    = str((item as Dictionary)["quantity"])
			label.visible = (item as Dictionary)["quantity"] > 1
		else:
			icon.texture  = null
			icon.visible  = false
			label.visible = false
