extends Control
class_name SmeltSlot

# A single furnace slot on the inventory's Smelting tab. The input slot accepts
# inventory/hotbar drag-drops (item_dropped); both slots report left-clicks so
# the inventory UI can place the input / take the output.

signal item_dropped(data: Dictionary)
signal item_clicked

var accept_drops: bool = true

var _icon: TextureRect = null

func _init() -> void:
	# Build the icon here (not _ready) so set_icon() works even before this
	# slot enters the tree — _build_smelt_content sets icons at build time.
	_icon = TextureRect.new()
	_icon.expand_mode  = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_icon.set_anchors_preset(Control.PRESET_FULL_RECT)
	var m: float = 8.0 * Global.ui_scale
	_icon.offset_left   = int(m)
	_icon.offset_top    = int(m)
	_icon.offset_right  = -int(m)
	_icon.offset_bottom = -int(m)
	add_child(_icon)

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	var sz: float = Global.ITEM_SLOT_SIZE * Global.ui_scale
	custom_minimum_size = Vector2(sz, sz)

func set_icon(tex: Texture2D, alpha: float = 1.0) -> void:
	_icon.texture  = tex
	_icon.modulate = Color(1, 1, 1, alpha)

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.22, 0.32, 0.58, 1.0), false, 1.5)

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton \
			and event.pressed \
			and event.button_index == MOUSE_BUTTON_LEFT:
		item_clicked.emit()

func _get_drag_data(_at_position: Vector2) -> Variant:
	return null

func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	if not accept_drops:
		return false
	return data is Dictionary and data.has("item") and data.has("source") and data.has("from_index")

func _drop_data(_at_position: Vector2, data: Variant) -> void:
	item_dropped.emit(data)
