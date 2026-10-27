extends VBoxContainer
class_name PlayerItemsPanel

# ── Player items panel (inventory + hotbar) ───────────────────────
# A reusable DRAG SOURCE for in-panel slot targets (the crafting station's
# INPUT slot, the Lua robot's BUILD SLOTS). Panels that cover the in-world
# hotbar use this so the player can still drag from their items. The slots are
# the SAME controls the real inventory/hotbar use, so the drag payload
# ("inventory"/"hotbar") is exactly what those targets accept.

const INVENTORY_SLOT_SCENE: PackedScene = preload("res://scenes/ui/InventorySlot.tscn")
const HOTBAR_SLOT_SCRIPT:   GDScript    = preload("res://scripts/hotbar_slot.gd")
const INV_COLUMNS: int = 4

# Set BEFORE adding to the tree to omit the HOTBAR strip (the crafting station
# only wants the inventory column).
var show_hotbar: bool = true

var _inv_slots:    Array = []
var _hotbar_slots: Array = []

func _ready() -> void:
	var s: float = Global.ui_scale
	add_theme_constant_override("separation", int(6 * s))
	custom_minimum_size = Vector2(
		INV_COLUMNS * (int(Global.ITEM_SLOT_SIZE * s) + int(6 * s)) + int(8 * s), 0)

	add_child(_mk_label("INVENTORY", s, C_TITLE))
	add_child(_mk_label("Drag items into the station / build slots.", s, C_MUTED))

	var grid := GridContainer.new()
	grid.columns = INV_COLUMNS
	grid.add_theme_constant_override("h_separation", int(6 * s))
	grid.add_theme_constant_override("v_separation", int(6 * s))
	add_child(grid)
	for idx in range(Global.INVENTORY_SIZE):
		var slot: Control = INVENTORY_SLOT_SCENE.instantiate()
		slot.set("slot_index", idx)
		grid.add_child(slot)
		_inv_slots.append(slot)

	if show_hotbar:
		add_child(_mk_label("HOTBAR", s, C_TITLE))
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", int(4 * s))
		add_child(row)
		for idx in range(Global.HOTBAR_SIZE):
			var t := TextureRect.new()
			t.set_script(HOTBAR_SLOT_SCRIPT)
			t.set("slot_index", idx)
			t.custom_minimum_size = Vector2(int(34 * s), int(34 * s))
			t.expand_mode         = TextureRect.EXPAND_IGNORE_SIZE
			t.stretch_mode        = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			var bg := ColorRect.new()
			bg.color = Color(0.11, 0.15, 0.26, 1.0)
			bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
			bg.set_anchors_preset(Control.PRESET_FULL_RECT)
			t.add_child(bg)
			# The ICON must be a CHILD: a Control's children draw OVER its own
			# texture, so setting the slot's own texture hid the item behind the
			# opaque bg (the hotbar looked empty / out of sync).
			var icon := TextureRect.new()
			icon.name = "ItemIcon"
			icon.expand_mode  = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
			icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			icon.set_anchors_preset(Control.PRESET_FULL_RECT)
			icon.offset_left = int(4 * s); icon.offset_top = int(4 * s)
			icon.offset_right = -int(4 * s); icon.offset_bottom = -int(4 * s)
			icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
			icon.visible = false
			t.add_child(icon)
			var qty := Label.new()
			qty.name = "Quantity"
			qty.add_theme_font_size_override("font_size", Global.ui_font_size(10))
			qty.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
			qty.offset_left = -int(16 * s); qty.offset_top = -int(14 * s)
			qty.offset_right = -int(2 * s); qty.offset_bottom = -int(2 * s)
			qty.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			qty.mouse_filter = Control.MOUSE_FILTER_IGNORE
			qty.visible = false
			t.add_child(qty)
			row.add_child(t)
			_hotbar_slots.append(t)

	if not Global.Inventory_updated.is_connected(_refresh):
		Global.Inventory_updated.connect(_refresh)
	if not Global.Hotbar_updated.is_connected(_refresh):
		Global.Hotbar_updated.connect(_refresh)
	# Deferred: slot visuals are built in their own _ready, which hasn't run yet.
	_refresh.call_deferred()

const C_TITLE := Color(0.80, 0.90, 1.00, 1.00)
const C_MUTED := Color(0.55, 0.65, 0.85, 1.00)

func _mk_label(text: String, s: float, col: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", Global.ui_font_size(10))
	l.add_theme_color_override("font_color", col)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l

func _refresh() -> void:
	for i in range(_inv_slots.size()):
		var slot: Control = _inv_slots[i]
		if not is_instance_valid(slot):
			continue
		var item: Variant = Global.Inventory[i] if i < Global.Inventory.size() else null
		if item == null:
			slot.call("set_empty")
		else:
			slot.call("set_item", item)
	for i in range(_hotbar_slots.size()):
		var slot: TextureRect = _hotbar_slots[i]
		if not is_instance_valid(slot):
			continue
		var icon: TextureRect = slot.get_node_or_null("ItemIcon") as TextureRect
		var qty:  Label       = slot.get_node_or_null("Quantity") as Label
		if icon == null:
			continue
		var item: Variant = Global.Hotbar[i] if i < Global.Hotbar.size() else null
		if item != null:
			icon.texture = ((item as Dictionary)["data"] as ItemData).icon
			icon.visible = true
			var q: int = int((item as Dictionary)["quantity"])
			if qty != null:
				qty.text = str(q)
				qty.visible = q > 1
		else:
			icon.texture = null
			icon.visible = false
			if qty != null:
				qty.visible = false
