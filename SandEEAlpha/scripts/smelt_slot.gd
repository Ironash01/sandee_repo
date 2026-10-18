extends Control
class_name SmeltSlot

# A single furnace slot on the inventory's Smelting tab. The input slot accepts
# inventory/hotbar drag-drops (item_dropped); both slots report left-clicks so
# the inventory UI can place the input / take the output.

signal item_dropped(data: Dictionary)
signal item_clicked

var accept_drops: bool = true

const SLOT_ICON_MARGIN: float = 8.0

var _icon: TextureRect = null
var _qty:  Label       = null
# The item currently shown (for the hover tooltip).
var item_data: ItemData = null

func _init() -> void:
	# Build the icon here (not _ready) so set_icon() works even before this
	# slot enters the tree — _build_smelt_content sets icons at build time.
	_icon = TextureRect.new()
	_icon.expand_mode  = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_icon.set_anchors_preset(Control.PRESET_FULL_RECT)
	var m: float = SLOT_ICON_MARGIN * Global.ui_scale
	_icon.offset_left   = int(m)
	_icon.offset_top    = int(m)
	_icon.offset_right  = -int(m)
	_icon.offset_bottom = -int(m)
	add_child(_icon)

	# Stack count (bottom-right), matching the inventory/hotbar slots — so a
	# loaded stack of 20 shows "20" instead of just the icon.
	_qty = Label.new()
	_qty.add_theme_font_size_override("font_size", int(11 * Global.ui_scale))
	_qty.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_qty.offset_left   = -int(24 * Global.ui_scale)
	_qty.offset_top    = -int(15 * Global.ui_scale)
	_qty.offset_right  = -int(2 * Global.ui_scale)
	_qty.offset_bottom = -int(2 * Global.ui_scale)
	_qty.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_qty.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_qty.visible = false
	add_child(_qty)

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	var sz: float = Global.ITEM_SLOT_SIZE * Global.ui_scale
	custom_minimum_size = Vector2(sz, sz)
	# Keep the slot a SQUARE. The furnace row is a tall HBox (input+fuel stack
	# sets its height), so without these the output slot stretches along the
	# cross axis into a rectangle and the icon/sprite no longer fits.
	size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	size_flags_vertical   = Control.SIZE_SHRINK_CENTER
	mouse_entered.connect(_on_hover_in)
	mouse_exited.connect(_on_hover_out)

func _on_hover_in() -> void:
	if item_data != null:
		Global.show_item_tooltip({"data": item_data, "quantity": 1})

func _on_hover_out() -> void:
	Global.hide_item_tooltip()

func set_icon(tex: Texture2D, alpha: float = 1.0, data: ItemData = null, quantity: int = 1) -> void:
	_icon.texture  = tex
	_icon.modulate = Color(1, 1, 1, alpha)
	item_data      = data
	if _qty != null:
		_qty.visible = data != null and quantity > 1
		_qty.text    = str(quantity)

func _draw() -> void:
	# Draw the border box to FIT the item square: the icon is inset by
	# SLOT_ICON_MARGIN on each side, so drawing the box at the same inset
	# makes it hug the item instead of leaving a gap around it.
	var m: float = _icon_margin()
	draw_rect(Rect2(Vector2(m, m), size - Vector2(m, m) * 2.0),
		Color(0.22, 0.32, 0.58, 1.0), false, 1.5)

func _icon_margin() -> float:
	return SLOT_ICON_MARGIN * Global.ui_scale

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			if item_data != null:
				Global.item_hold_start({"data": item_data, "quantity": 1})
			item_clicked.emit()
		else:
			Global.item_hold_end()

func _get_drag_data(_at_position: Vector2) -> Variant:
	return null

func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	if not accept_drops:
		return false
	return data is Dictionary and data.has("item") and data.has("source") and data.has("from_index")

func _drop_data(_at_position: Vector2, data: Variant) -> void:
	item_dropped.emit(data)
