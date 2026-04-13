extends TextureRect

var slot_index: int = -1

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP

# ── Drag out of hotbar (only when inventory is open) ──────────────
func _get_drag_data(_at_position: Vector2) -> Variant:
	if not Global.inventory_open:
		return null
	var item: Variant = Global.Hotbar[slot_index]
	if item == null:
		return null
	var preview := TextureRect.new()
	preview.texture             = ((item as Dictionary)["data"] as ItemData).icon
	preview.custom_minimum_size = Vector2(40, 40)
	preview.expand_mode         = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	preview.stretch_mode        = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	preview.modulate            = Color(1, 1, 1, 0.72)
	set_drag_preview(preview)
	return {"from_index": slot_index, "item": item, "source": "hotbar"}

# ── Accept drops from inventory OR other hotbar slots ─────────────
func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	if not (data is Dictionary) or not data.has("from_index"):
		return false
	var src: String = data.get("source", "")
	return src == "inventory" or src == "hotbar"

func _drop_data(_at_position: Vector2, data: Variant) -> void:
	var from_idx: int  = data["from_index"]
	var src: String    = data.get("source", "")

	if src == "inventory":
		if from_idx < 0 or from_idx >= Global.Inventory.size():
			return
		var dragged: Variant  = Global.Inventory[from_idx]
		if dragged == null:
			return
		var existing: Variant = Global.Hotbar[slot_index]
		Global.Hotbar[slot_index]  = dragged
		Global.Inventory[from_idx] = existing
		Global.Hotbar_updated.emit()
		Global.Inventory_updated.emit()

	elif src == "hotbar":
		if from_idx == slot_index:
			return
		if from_idx < 0 or from_idx >= Global.Hotbar.size():
			return
		# Swap within hotbar
		var tmp: Variant           = Global.Hotbar[slot_index]
		Global.Hotbar[slot_index]  = Global.Hotbar[from_idx]
		Global.Hotbar[from_idx]    = tmp
		Global.Hotbar_updated.emit()
