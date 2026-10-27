extends Control
# ── Crafting-station INPUT slot ───────────────────────────────────
# The single feed slot for automatic crafting. Drop an item from the player's
# inventory/hotbar here to load it; left-click to take it back. The Lua robot
# loads it via put_input(). Visuals mirror inventory_slot.gd.

signal changed

const C_SLOT_BG   := Color(0.05, 0.07, 0.16, 1.00)
const C_BORDER    := Color(0.22, 0.32, 0.58, 1.00)
const C_HOVER     := Color(0.50, 0.70, 1.00, 1.00)
const C_DRAG_OVER := Color(1.00, 0.85, 0.25, 1.00)

var station: Node = null
var _icon:    TextureRect
var _qty:     Label
var _hovered:   bool = false
var _drag_over: bool = false

func _ready() -> void:
	var sz: float = Global.ITEM_SLOT_SIZE * Global.ui_scale
	custom_minimum_size = Vector2(sz, sz)
	mouse_filter        = Control.MOUSE_FILTER_STOP

	var bg := ColorRect.new()
	bg.color = C_SLOT_BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	_icon = TextureRect.new()
	_icon.expand_mode  = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_icon.set_anchors_preset(Control.PRESET_FULL_RECT)
	var m: float = 6.0 * Global.ui_scale
	_icon.offset_left = m; _icon.offset_top = m; _icon.offset_right = -m; _icon.offset_bottom = -m
	_icon.visible = false
	add_child(_icon)

	_qty = Label.new()
	_qty.add_theme_font_size_override("font_size", Global.ui_font_size(11))
	_qty.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_qty.offset_left = -int(24 * Global.ui_scale); _qty.offset_top = -int(15 * Global.ui_scale)
	_qty.offset_right = -int(2 * Global.ui_scale); _qty.offset_bottom = -int(2 * Global.ui_scale)
	_qty.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_qty.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_qty.visible = false
	add_child(_qty)

	refresh()

func refresh() -> void:
	if _icon == null:
		return
	var stack: Dictionary = {}
	if station != null and is_instance_valid(station) and station.has_method("get_input_stack"):
		stack = station.call("get_input_stack")
	if stack.is_empty():
		_icon.texture = null
		_icon.visible = false
		_qty.visible  = false
	else:
		var data: ItemData = stack["data"] as ItemData
		_icon.texture = data.icon if data != null else null
		_icon.visible = true
		var q: int = int(stack["quantity"])
		_qty.visible = q > 1
		_qty.text    = str(q)
	queue_redraw()

func _draw() -> void:
	var col := C_BORDER
	if _drag_over:
		col = C_DRAG_OVER
	elif _hovered:
		col = C_HOVER
	draw_rect(Rect2(Vector2.ZERO, size), col, false, 1.5)

func _mouse_enter() -> void:
	_hovered = true; queue_redraw()

func _mouse_exit() -> void:
	_hovered = false; queue_redraw()

# Left-click: take the loaded stack back into the player's inventory.
func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if station == null or not is_instance_valid(station):
			return
		var stack: Dictionary = station.call("get_input_stack")
		if stack.is_empty():
			return
		var data: ItemData = stack["data"] as ItemData
		var qty: int = int(station.call("take_input", data, int(stack["quantity"])))
		if qty > 0 and data != null:
			Global.add_item({"data": data, "quantity": qty})
		changed.emit()

func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	if station == null or not is_instance_valid(station):
		return false
	if not (data is Dictionary) or not data.has("from_index") or data["item"] == null:
		return false
	var src: String = str(data.get("source", ""))
	if src != "inventory" and src != "hotbar":
		return false
	_drag_over = true
	queue_redraw()
	return true

func _drop_data(_at_position: Vector2, data: Variant) -> void:
	_drag_over = false
	queue_redraw()
	if station == null or not is_instance_valid(station):
		return
	var item: Dictionary = data["item"]
	var data_obj: ItemData = item["data"] as ItemData
	if data_obj == null:
		return
	var accepted: int = int(station.call("put_input", data_obj, int(item["quantity"])))
	# Remove only what the station accepted from the player's source slot.
	var from_idx: int = int(data["from_index"])
	var src: String = str(data.get("source", "inventory"))
	var arr: Array = Global.Hotbar if src == "hotbar" else Global.Inventory
	if accepted > 0 and from_idx >= 0 and from_idx < arr.size() and arr[from_idx] != null:
		var remaining: int = int(arr[from_idx]["quantity"]) - accepted
		if remaining <= 0:
			arr[from_idx] = null
		else:
			arr[from_idx]["quantity"] = remaining
	if src == "hotbar":
		Global.Hotbar_updated.emit()
	else:
		Global.Inventory_updated.emit()
	changed.emit()

func _notification(what: int) -> void:
	if what == NOTIFICATION_DRAG_END:
		_drag_over = false
		queue_redraw()
