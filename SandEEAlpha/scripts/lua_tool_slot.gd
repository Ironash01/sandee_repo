extends Control
# ── Lua TOOL slot ─────────────────────────────────────────────────
# The single tool slot in the Lua editor: drop a tool/weapon here and the robot
# swings it for its tasks (and uses its damage in combat mode). Left-click to
# take the stack back. Mirrors lua_build_slot.gd.

signal slot_changed

const C_SLOT_BG   := Color(0.10, 0.13, 0.24, 1.00)
const C_BORDER    := Color(0.22, 0.32, 0.58, 1.00)
const C_HOVER     := Color(0.50, 0.70, 1.00, 1.00)
const C_DRAG_OVER := Color(1.00, 0.85, 0.25, 1.00)

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
	_qty.add_theme_font_size_override("font_size", int(11 * s))
	_qty.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_qty.offset_left   = -int(24 * s)
	_qty.offset_top    = -int(15 * s)
	_qty.offset_right  = -int(2 * s)
	_qty.offset_bottom = -int(2 * s)
	_qty.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_qty.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_qty.visible = false
	add_child(_qty)

func refresh() -> void:
	if _npc == null or not is_instance_valid(_npc):
		return
	var tool: Dictionary = _npc.call("get_tool")
	if tool.is_empty():
		_clear_icon()
		return
	# The tool is only a VIEW of the NPC's authoritative slot, so a missing or
	# FREED ItemData must clear the icon rather than leave a stale one (or crash
	# on a freed instance).
	var data: Variant = tool.get("data")
	if not (data is ItemData) or not is_instance_valid(data):
		_clear_icon()
		return
	var idata := data as ItemData
	_icon.texture = idata.icon
	_icon.visible = true
	var qty: int = int(tool.get("quantity", 0))
	if qty <= 0:
		_clear_icon()
		return
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

# Left-click: take the tool back into the player's inventory. Only cleared when
# the inventory can hold it — otherwise a full inventory would destroy it.
func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if _npc == null or not is_instance_valid(_npc):
			return
		var tool: Dictionary = _npc.call("get_tool")
		if tool.is_empty():
			return
		var data: ItemData = tool["data"] as ItemData
		var qty: int = int(tool["quantity"])
		if data == null:
			return
		if not Global.has_space_for_item(data, qty):
			Global.log_chat("[color=#ffaa66]Inventory full — the robot keeps the %s.[/color]" % data.item_name)
			return
		Global.add_item({"data": data, "quantity": qty})
		_npc.call("set_tool", null, 0)
		slot_changed.emit()

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
	# Return the tool already in the slot to the player first — set_tool would
	# otherwise overwrite (destroy) it. Abort if the inventory can't take it.
	var existing: Dictionary = _npc.call("get_tool")
	if not existing.is_empty():
		var ex_data: ItemData = existing["data"] as ItemData
		var ex_qty: int = int(existing["quantity"])
		if ex_data != null and ex_qty > 0:
			if not Global.has_space_for_item(ex_data, ex_qty):
				Global.log_chat("[color=#ffaa66]Inventory full — can't swap the robot's tool.[/color]")
				return
			Global.add_item({"data": ex_data, "quantity": ex_qty})
	_npc.call("set_tool", data_obj, int(item["quantity"]))
	var from_idx: int = int(data["from_index"])
	var src: String = String(data.get("source", "inventory"))
	if src == "hotbar":
		if from_idx >= 0 and from_idx < Global.Hotbar.size():
			Global.Hotbar[from_idx] = null
		Global.Hotbar_updated.emit()
	elif src == "inventory":
		if from_idx >= 0 and from_idx < Global.Inventory.size():
			Global.Inventory[from_idx] = null
		Global.Inventory_updated.emit()
	slot_changed.emit()

func _notification(what: int) -> void:
	if what == NOTIFICATION_DRAG_END:
		_drag_over = false
		queue_redraw()
