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
# The main inventory has its own item-details sidebar, so it suppresses the
# floating tooltip (which would cover the grid). Other item panels keep it.
var suppress_floating_tooltip: bool = false

# ── Chest binding (combined chest + inventory panel) ──────────────
# The SAME slot scene is used for the chest's storage when a chest is open.
# `is_chest_slot` makes this slot present `chest_link.slots[index]` instead of
# Global.Inventory[index]; `chest_link` alone (player slots) is just the bridge
# that lets a stack dragged out of the chest land in the player inventory.
# The chest stays the only owner of that data — nothing is copied here.
var chest_link:    Node = null
var is_chest_slot: bool = false

var _hovered:      bool = false
var _drag_over:    bool = false
var _is_drag_source: bool = false

# ── Child nodes (built in _ready) ────────────────────────────────
var _bg:   ColorRect
var _icon: TextureRect
var _qty:  Label

func _ready() -> void:
	var sz: float = Global.ITEM_SLOT_SIZE * Global.ui_scale
	custom_minimum_size = Vector2(sz, sz)
	mouse_filter        = Control.MOUSE_FILTER_STOP
	_build_visuals()
	# Floating item tooltip on hover (shared popup).
	mouse_entered.connect(_on_hover_in)
	mouse_exited.connect(_on_hover_out)

func _on_hover_in() -> void:
	_hovered = true
	queue_redraw()
	if item != null and not suppress_floating_tooltip:
		Global.show_item_tooltip(item as Dictionary)

func _on_hover_out() -> void:
	_hovered = false
	queue_redraw()
	Global.hide_item_tooltip()

# Press-and-hold to inspect (touch screens have no hover). A mouse press that
# turns into a drag cancels the hold; releasing always ends it.
func _on_press() -> void:
	if item != null and not suppress_floating_tooltip:
		Global.item_hold_start(item as Dictionary)

func _on_release() -> void:
	Global.item_hold_end()

func _build_visuals() -> void:
	var s: float = Global.ui_scale

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
	_icon.offset_left   =  int(8 * s)
	_icon.offset_top    =  int(8 * s)
	_icon.offset_right  = -int(8 * s)
	_icon.offset_bottom = -int(8 * s)
	_icon.visible       = false
	add_child(_icon)

	# Quantity label (bottom-right)
	_qty = Label.new()
	_qty.add_theme_font_size_override("font_size", Global.ui_font_size(12))
	_qty.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_qty.offset_left   = -int(26 * s)
	_qty.offset_top    = -int(16 * s)
	_qty.offset_right  = -int(2 * s)
	_qty.offset_bottom = -int(2 * s)
	_qty.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_qty.mouse_filter  = Control.MOUSE_FILTER_IGNORE
	_qty.visible       = false
	add_child(_qty)

# ── Data ──────────────────────────────────────────────────────────
func set_item(new_item: Dictionary) -> void:
	item = new_item
	var data: ItemData = new_item["data"] as ItemData
	if _icon == null:
		return   # visuals not built yet (called before _ready)
	_icon.texture = data.icon
	_icon.visible = true
	_qty.visible  = new_item["quantity"] > 1
	_qty.text     = str(new_item["quantity"]) if new_item["quantity"] > 1 else ""
	queue_redraw()

func set_empty() -> void:
	item          = null
	if _icon == null:
		return
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
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_on_press()
			slot_clicked.emit(slot_index)
		else:
			_on_release()

func _mouse_enter() -> void:
	_hovered = true
	queue_redraw()

func _mouse_exit() -> void:
	_hovered = false
	queue_redraw()

# ── Drag & Drop ───────────────────────────────────────────────────
# The stack this slot is currently offering as a drag. If the slot still holds
# it when the drag ends unsuccessfully, the drop was never handled and the stack
# belongs in the world; if the slot now holds something ELSE (a swap happened)
# the drop WAS handled and must not also spawn a world item (item duplication).
var _drag_item: Variant = null

func _get_drag_data(_at_position: Vector2) -> Variant:
	var payload: Variant = null
	if is_chest_slot:
		if not _has_chest():
			return null
		payload = chest_link.call("make_drag_data", slot_index, true)
	elif item != null:
		payload = {"from_index": slot_index, "item": item, "source": "inventory"}
	if not (payload is Dictionary):
		return null
	# Build a semi-transparent drag preview
	var item_v: Variant = (payload as Dictionary).get("item")
	if item_v is Dictionary:
		var data: ItemData = (item_v as Dictionary).get("data") as ItemData
		if data != null and data.icon != null:
			var preview := TextureRect.new()
			preview.texture             = data.icon
			var prev_sz: float = Global.ITEM_SLOT_SIZE * Global.ui_scale * 0.75
			preview.custom_minimum_size = Vector2(prev_sz, prev_sz)
			preview.expand_mode         = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
			preview.stretch_mode        = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			preview.modulate            = Color(1, 1, 1, 0.72)
			set_drag_preview(preview)
	_is_drag_source = true
	_drag_item = item_v
	return payload

func _has_chest() -> bool:
	return chest_link != null and is_instance_valid(chest_link)

func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	if not (data is Dictionary and data.has("from_index")):
		return false
	var src: String = str((data as Dictionary).get("source", "inventory"))
	# Chest storage slots apply the chest's own rules (stack limits, merge,
	# swap); player slots need the same route when a chest stack is dragged in.
	if is_chest_slot or src == "chest":
		if not _has_chest():
			return false
		if not bool(chest_link.call("can_accept_drop", slot_index, is_chest_slot, data)):
			return false
		_drag_over = true
		queue_redraw()
		return true
	if src != "inventory" and src != "hotbar":
		return false
	_drag_over = true
	queue_redraw()
	return true

func _drop_data(_at_position: Vector2, data: Variant) -> void:
	_drag_over = false
	queue_redraw()
	var from_idx: int  = data["from_index"]
	var source: String = data.get("source", "inventory")
	var to_idx: int    = slot_index

	# Anything involving the chest is applied by the chest itself, which owns
	# the storage array and the validation/merge rules.
	if is_chest_slot or source == "chest":
		if _has_chest():
			chest_link.call("accept_drop", to_idx, is_chest_slot, data)
		return

	if source == "hotbar":
		var tmp: Variant          = Global.Inventory[to_idx]
		Global.Inventory[to_idx]  = Global.Hotbar[from_idx]
		Global.Hotbar[from_idx]   = tmp
		_update_visual()
		Global.Hotbar_updated.emit()
		Global.Inventory_updated.emit()
	else:
		if from_idx == to_idx:
			return
		var tmp: Variant           = Global.Inventory[to_idx]
		Global.Inventory[to_idx]   = Global.Inventory[from_idx]
		Global.Inventory[from_idx] = tmp
		_update_visual()
		Global.Inventory_updated.emit()

func _update_visual() -> void:
	if is_chest_slot:
		return   # chest views are redrawn from chest.slots by the panel
	var current = Global.Inventory[slot_index]
	if current != null:
		set_item(current as Dictionary)
	else:
		set_empty()

# Clear drag-over highlight if drag exits without drop; if this slot was the
# drag's source and it wasn't accepted by any slot, drop the stack in the world.
func _notification(what: int) -> void:
	if what == NOTIFICATION_DRAG_END:
		Global.item_hold_end()
		_drag_over = false
		queue_redraw()
		if _is_drag_source:
			_is_drag_source = false
			if not get_viewport().gui_is_drag_successful():
				_drop_to_world()
			_drag_item = null

func _drop_to_world() -> void:
	# A chest stack dragged out of the panel is simply cancelled — the chest
	# keeps owning it (the old chest panel behaved the same way).
	if is_chest_slot:
		return
	if slot_index < 0 or slot_index >= Global.Inventory.size():
		return
	var slot: Variant = Global.Inventory[slot_index]
	if slot == null:
		return
	# A swap already put a DIFFERENT stack here — the drag was handled, so
	# dropping this one into the world too would duplicate/lose an item.
	if _drag_item != null and not is_same(slot, _drag_item):
		return
	if not Global.player_node:
		return
	var pos: Vector2 = (Global.player_node as Node2D).global_position
	Global.drop_item({"data": slot["data"], "quantity": slot["quantity"]}, pos)
	Global.Inventory[slot_index] = null
	Global.Inventory_updated.emit()
