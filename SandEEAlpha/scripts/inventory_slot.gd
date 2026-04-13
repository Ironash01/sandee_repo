extends Control

# Emitted when this slot is left-clicked
signal slot_clicked(index: int)

# ── Colors ────────────────────────────────────────────────────────
const C_SLOT_BG    := Color(0.10, 0.13, 0.24, 1.00)
const C_BORDER     := Color(0.22, 0.32, 0.58, 1.00)
const C_HOVER      := Color(0.50, 0.70, 1.00, 1.00)
const C_DRAG_OVER  := Color(1.00, 0.85, 0.25, 1.00)

# ── State ─────────────────────────────────────────────────────────
var slot_index: int = -1
var item: Variant = null

var _hovered:   bool = false
var _drag_over: bool = false

# ── Child nodes (built in _ready) ────────────────────────────────
var _bg:   ColorRect
var _icon: TextureRect
var _qty:  Label

func _ready() -> void:
	custom_minimum_size = Vector2(52, 52)
	mouse_filter        = Control.MOUSE_FILTER_STOP
	_build_visuals()

func _build_visuals() -> void:
	# Slot background
	_bg = ColorRect.new()
	_bg.color = C_SLOT_BG
	_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_bg)

	# Item icon
	_icon = TextureRect.new()
	_icon.expand_mode      = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	_icon.stretch_mode     = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_icon.mouse_filter     = Control.MOUSE_FILTER_IGNORE
	_icon.set_anchors_preset(Control.PRESET_FULL_RECT)
	_icon.offset_left   =  6
	_icon.offset_top    =  6
	_icon.offset_right  = -6
	_icon.offset_bottom = -6
	_icon.visible       = false
	add_child(_icon)

	# Quantity label (bottom-right)
	_qty = Label.new()
	_qty.add_theme_font_size_override("font_size", 10)
	_qty.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_qty.offset_left   = -22
	_qty.offset_top    = -14
	_qty.offset_right  = -2
	_qty.offset_bottom = -2
	_qty.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_qty.mouse_filter  = Control.MOUSE_FILTER_IGNORE
	_qty.visible       = false
	add_child(_qty)

# ── Data ──────────────────────────────────────────────────────────
func set_item(new_item: Dictionary) -> void:
	item = new_item
	var data: ItemData = new_item["data"] as ItemData
	_icon.texture = data.icon
	_icon.visible = true
	_qty.visible  = new_item["quantity"] > 1
	_qty.text     = str(new_item["quantity"]) if new_item["quantity"] > 1 else ""
	queue_redraw()

func set_empty() -> void:
	item          = null
	_icon.texture = null
	_icon.visible = false
	_qty.visible  = false
	_qty.text     = ""
	queue_redraw()

# ── Draw border ───────────────────────────────────────────────────
func _draw() -> void:
	var col := C_HOVER if _hovered else C_BORDER
	draw_rect(Rect2(Vector2.ZERO, size), col, false, 1.5)

# ── Mouse events ──────────────────────────────────────────────────
func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton \
			and event.pressed \
			and event.button_index == MOUSE_BUTTON_LEFT:
		slot_clicked.emit(slot_index)

func _mouse_enter() -> void:
	_hovered = true
	queue_redraw()

func _mouse_exit() -> void:
	_hovered = false
	queue_redraw()

# ── Drag & Drop ───────────────────────────────────────────────────
func _get_drag_data(_at_position: Vector2) -> Variant:
	if item == null:
		return null
	# Build a semi-transparent drag preview
	var preview := TextureRect.new()
	preview.texture             = (item["data"] as ItemData).icon
	preview.custom_minimum_size = Vector2(44, 44)
	preview.expand_mode         = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	preview.stretch_mode        = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	preview.modulate            = Color(1, 1, 1, 0.72)
	set_drag_preview(preview)
	return {"from_index": slot_index, "item": item, "source": "inventory"}

func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	if not (data is Dictionary and data.has("from_index")):
		return false
	_drag_over = true
	queue_redraw()
	return true

func _drop_data(_at_position: Vector2, data: Variant) -> void:
	_drag_over = false
	queue_redraw()
	var from_idx: int = data["from_index"]
	var source: String = data.get("source", "inventory")
	var to_idx: int = slot_index
	if source == "hotbar":
		# Swap hotbar slot with this inventory slot
		var tmp: Variant = Global.Inventory[to_idx]
		Global.Inventory[to_idx]  = Global.Hotbar[from_idx]
		Global.Hotbar[from_idx]   = tmp
		Global.Hotbar_updated.emit()
		Global.Inventory_updated.emit()
	else:
		# Swap within inventory
		if from_idx == to_idx:
			return
		var tmp: Variant = Global.Inventory[to_idx]
		Global.Inventory[to_idx]   = Global.Inventory[from_idx]
		Global.Inventory[from_idx] = tmp
		Global.Inventory_updated.emit()

# Clear drag-over highlight if drag exits without drop
func _notification(what: int) -> void:
	if what == NOTIFICATION_DRAG_END:
		_drag_over = false
		queue_redraw()
