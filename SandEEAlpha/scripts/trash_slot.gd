extends Control

# ── Colors ────────────────────────────────────────────────────────
const C_BG      := Color(0.20, 0.09, 0.09, 1.00)
const C_BORDER  := Color(0.55, 0.20, 0.20, 1.00)
const C_HOVER   := Color(0.95, 0.40, 0.35, 1.00)
const C_ICON    := Color(0.85, 0.55, 0.50, 1.00)

var _hovered:   bool = false
var _drag_over: bool = false

func _ready() -> void:
	var sz: float = Global.ITEM_SLOT_SIZE * Global.ui_scale
	custom_minimum_size = Vector2(sz, sz)
	mouse_filter        = Control.MOUSE_FILTER_STOP
	tooltip_text        = "Drag an item here to delete it"

func _mouse_enter() -> void:
	_hovered = true
	queue_redraw()

func _mouse_exit() -> void:
	_hovered = false
	queue_redraw()

func _draw() -> void:
	var active: bool = _hovered or _drag_over
	var border: Color = C_HOVER if active else C_BORDER
	draw_rect(Rect2(Vector2.ZERO, size), C_BG, true)
	draw_rect(Rect2(Vector2.ZERO, size), border, false, 1.5)
	_draw_trash_icon(C_HOVER if _drag_over else C_ICON)

func _draw_trash_icon(col: Color) -> void:
	var c: Vector2 = size * 0.5
	var w: float   = size.x * 0.20
	var top: float = c.y - size.y * 0.16

	# Lid
	draw_line(Vector2(c.x - w, top), Vector2(c.x + w, top), col, 2.0)
	draw_line(Vector2(c.x - w * 0.5, top), Vector2(c.x - w * 0.3, top - 5), col, 2.0)
	draw_line(Vector2(c.x + w * 0.5, top), Vector2(c.x + w * 0.3, top - 5), col, 2.0)
	draw_line(Vector2(c.x - w * 0.3, top - 5), Vector2(c.x + w * 0.3, top - 5), col, 2.0)

	# Body
	var bottom: float = top + size.y * 0.32
	var body_top_l  := Vector2(c.x - w * 0.9, top + 2)
	var body_top_r  := Vector2(c.x + w * 0.9, top + 2)
	var body_bot_l  := Vector2(c.x - w * 0.65, bottom)
	var body_bot_r  := Vector2(c.x + w * 0.65, bottom)
	draw_line(body_top_l, body_bot_l, col, 2.0)
	draw_line(body_top_r, body_bot_r, col, 2.0)
	draw_line(body_bot_l, body_bot_r, col, 2.0)

	# Ribs
	draw_line(Vector2(c.x, top + 6), Vector2(c.x, bottom - 3), col, 1.5)
	draw_line(Vector2(c.x - w * 0.35, top + 6), Vector2(c.x - w * 0.25, bottom - 3), col, 1.5)
	draw_line(Vector2(c.x + w * 0.35, top + 6), Vector2(c.x + w * 0.25, bottom - 3), col, 1.5)

# ── Drag & Drop ───────────────────────────────────────────────────
func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	if not (data is Dictionary and data.has("from_index")):
		return false
	_drag_over = true
	queue_redraw()
	return true

func _drop_data(_at_position: Vector2, data: Variant) -> void:
	_drag_over = false
	queue_redraw()
	var from_idx: int  = data["from_index"]
	var source: String = data.get("source", "inventory")

	# A stack dragged out of the docked chest is owned by the chest array, not
	# Global.Inventory. Deleting the wrong array would either lose a player item
	# or leave the chest display stale.
	if source == "chest":
		var ui := _open_inventory_ui()
		if ui == null:
			return
		var chest: Variant = ui.call("opened_chest")
		if chest == null or not is_instance_valid(chest):
			return
		var slots: Array = chest.get("slots") as Array
		if from_idx < 0 or from_idx >= slots.size():
			return
		slots[from_idx] = null
		if chest.has_method("notify_contents_changed"):
			chest.call("notify_contents_changed")
		if ui.has_method("refresh_chest_slots"):
			ui.call("refresh_chest_slots")
		return

	if source == "hotbar":
		if from_idx < 0 or from_idx >= Global.Hotbar.size():
			return
		Global.Hotbar[from_idx] = null
		Global.Hotbar_updated.emit()
	else:
		if from_idx < 0 or from_idx >= Global.Inventory.size():
			return
		Global.Inventory[from_idx] = null
		Global.Inventory_updated.emit()


func _open_inventory_ui() -> Node:
	if Global.player_node == null or not is_instance_valid(Global.player_node):
		return null
	var layer: Node = Global.player_node.get_node_or_null("InventoryUI")
	if layer == null:
		return null
	for child in layer.get_children():
		if child.has_method("opened_chest"):
			return child
	return null

func _notification(what: int) -> void:
	if what == NOTIFICATION_DRAG_END:
		_drag_over = false
		queue_redraw()
