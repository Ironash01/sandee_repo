extends Control
# ── Lua build-palette slot ────────────────────────────────────────
# One of the robot's 3 build slots in the Lua editor. Drop a block from the
# player's inventory/hotbar here to give it to the robot; left-click to take
# the stack back. The robot also fills these itself (chopping wood, or
# withdraw() from a chest). Visuals mirror inventory_slot.gd.

signal slot_changed  # re-emitted as build_palette_changed by the editor UI

const C_SLOT_BG   := Color(0.10, 0.13, 0.24, 1.00)
const C_BORDER    := Color(0.22, 0.32, 0.58, 1.00)
const C_HOVER     := Color(0.50, 0.70, 1.00, 1.00)
const C_DRAG_OVER := Color(1.00, 0.85, 0.25, 1.00)

var slot_index: int = 0
var _npc: Node = null           # LuaNPC (set by the editor UI)
var _hovered:   bool = false
var _drag_over: bool = false

var _bg:   ColorRect
var _icon: TextureRect
var _qty:  Label

func _ready() -> void:
	var sz: float = Global.ITEM_SLOT_SIZE * Global.ui_scale * 0.9
	custom_minimum_size = Vector2(sz, sz)
	mouse_filter        = Control.MOUSE_FILTER_STOP
	_build_visuals()

func _build_visuals() -> void:
	var s: float = Global.ui_scale
	_bg = ColorRect.new()
	_bg.color = C_SLOT_BG
	_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_bg)
	_icon = TextureRect.new()
	_icon.expand_mode  = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_icon.set_anchors_preset(Control.PRESET_FULL_RECT)
	_icon.offset_left   =  int(6 * s)
	_icon.offset_top    =  int(6 * s)
	_icon.offset_right  = -int(6 * s)
	_icon.offset_bottom = -int(6 * s)
	_icon.visible = false
	add_child(_icon)
	_qty = Label.new()
	_qty.add_theme_font_size_override("font_size", Global.ui_font_size(11))
	_qty.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_qty.offset_left   = -int(24 * s)
	_qty.offset_top    = -int(15 * s)
	_qty.offset_right  = -int(2 * s)
	_qty.offset_bottom = -int(2 * s)
	_qty.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_qty.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_qty.visible = false
	add_child(_qty)

# Reads straight from the robot's palette (single source of truth).
func refresh() -> void:
	if _npc == null or not is_instance_valid(_npc):
		return
	var palette: Array = _npc.call("get_build_palette")
	var slot: Variant = palette[slot_index] if slot_index < palette.size() else null
	# This slot is only a VIEW of the NPC's authoritative palette, so a missing
	# or FREED ItemData must clear the icon instead of leaving a stale one (or
	# crashing on a freed instance).
	var data: Variant = null
	if slot is Dictionary:
		data = (slot as Dictionary).get("data")
	if not (data is ItemData) or not is_instance_valid(data) \
			or int((slot as Dictionary).get("quantity", 0)) <= 0:
		_clear_icon()
		return
	_icon.texture = (data as ItemData).icon
	_icon.visible = true
	var qty: int = int((slot as Dictionary).get("quantity", 0))
	_qty.visible = qty > 1
	_qty.text    = str(qty)
	queue_redraw()

func _clear_icon() -> void:
	_icon.texture = null
	_icon.visible = false
	_qty.visible  = false
	queue_redraw()

func _draw() -> void:
	var col := C_BORDER
	if _drag_over:
		col = C_DRAG_OVER
	elif _hovered:
		col = C_HOVER
	draw_rect(Rect2(Vector2.ZERO, size), col, false, 1.5)

func _mouse_enter() -> void:
	_hovered = true
	queue_redraw()

func _mouse_exit() -> void:
	_hovered = false
	queue_redraw()

# Left-click: take the stack back into the player's inventory. Only cleared when
# the inventory can hold the WHOLE stack — otherwise a full inventory would
# silently destroy it.
func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if _npc == null or not is_instance_valid(_npc):
			return
		var palette: Array = _npc.call("get_build_palette")
		var slot: Variant = palette[slot_index] if slot_index < palette.size() else null
		if slot == null:
			return
		var data: ItemData = (slot as Dictionary)["data"] as ItemData
		var qty: int = int((slot as Dictionary)["quantity"])
		if data == null:
			return
		if not Global.has_space_for_item(data, qty):
			Global.notify("[color=#ffaa66]Inventory full — the robot keeps the %s.[/color]" % data.item_name)
			return
		Global.add_item({"data": data, "quantity": qty})
		_npc.call("set_build_slot", slot_index, null, 0)
		slot_changed.emit()

# Accept drops from the player's inventory or hotbar.
func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	if not (data is Dictionary) or not data.has("from_index"):
		return false
	if not data.has("item") or data["item"] == null:
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
	if _npc == null or not is_instance_valid(_npc):
		return
	var item: Dictionary = data["item"]
	var data_obj: ItemData = item["data"] as ItemData
	if data_obj == null:
		return
	# If the slot already holds a DIFFERENT stack, return it to the player first
	# — set_build_slot would otherwise overwrite (destroy) it. Abort the drop if
	# the inventory can't take the old stack back.
	var palette: Array = _npc.call("get_build_palette")
	var existing: Variant = palette[slot_index] if slot_index < palette.size() else null
	if existing != null:
		var ex_data: ItemData = (existing as Dictionary)["data"] as ItemData
		var ex_qty: int = int((existing as Dictionary)["quantity"])
		if ex_data != null and ex_qty > 0:
			if not Global.has_space_for_item(ex_data, ex_qty):
				Global.notify("[color=#ffaa66]Inventory full — can't swap the robot's slot.[/color]")
				return
			Global.add_item({"data": ex_data, "quantity": ex_qty})
	# Give the whole dragged stack to the robot, then clear the player's slot.
	_npc.call("set_build_slot", slot_index, data_obj, int(item["quantity"]))
	_clear_source(data)
	slot_changed.emit()

# Remove the dragged item's source slot (the whole stack moved to the robot).
func _clear_source(data: Dictionary) -> void:
	var from_idx: int = int(data["from_index"])
	var src: String = str(data.get("source", "inventory"))
	if src == "hotbar":
		if from_idx >= 0 and from_idx < Global.Hotbar.size():
			Global.Hotbar[from_idx] = null
		Global.Hotbar_updated.emit()
	elif src == "inventory":
		if from_idx >= 0 and from_idx < Global.Inventory.size():
			Global.Inventory[from_idx] = null
		Global.Inventory_updated.emit()

func _notification(what: int) -> void:
	if what == NOTIFICATION_DRAG_END:
		_drag_over = false
		queue_redraw()
