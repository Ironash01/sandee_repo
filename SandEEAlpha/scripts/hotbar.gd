extends Control

var slots: Array = []
var selected_index: int = 0

const C_SLOT_BG  := Color(0.11, 0.15, 0.26, 1.00)
const C_SLOT_SEL := Color(0.25, 0.40, 0.75, 1.00)

const SLOT_SIZE    := 40
const SLOT_SCRIPT  := preload("res://scripts/hotbar_slot.gd")

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

	Global.Hotbar_updated.connect(_refresh_hotbar)
	Global.hotbar_selection_changed.connect(_on_selection_changed)
	Global.inventory_toggled.connect(_on_inventory_toggled)

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
