extends Control

# Reference to each hotbar slot (we'll grab them by index)
var slots: Array = []
var selected_index: int = 0

# Highlight color for selected slot
const SELECTED_COLOR = Color(1.0, 1.0, 0.3, 1.0)   # yellow tint
const NORMAL_COLOR   = Color(1.0, 1.0, 1.0, 1.0)   # no tint

func _ready():
	# Grab all TextureRect slots in order from HBoxContainer
	var hbox = $CanvasLayer/HBoxContainer
	for child in hbox.get_children():
		if child is TextureRect:
			slots.append(child)
			# Add an item icon (Sprite2D) and quantity label inside each slot
			var icon = Sprite2D.new()
			icon.name = "ItemIcon"
			icon.position = Vector2(16, 16)  # center of 32x32 slot
			icon.visible = false
			child.add_child(icon)

			var label = Label.new()
			label.name = "Quantity"
			label.add_theme_font_size_override("font_size", 10)
			label.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
			label.offset_left = -14
			label.offset_top = -14
			label.visible = false
			child.add_child(label)

	# Connect to inventory updates
	Global.Inventory_updated.connect(_refresh_hotbar)
	Global.hotbar_selection_changed.connect(_on_selection_changed)

	_refresh_hotbar()
	_highlight_slot(0)

func _input(event):
	# Number keys 1-9
	for i in range(9):
		if event.is_action_pressed("hotbar_%d" % (i + 1)):
			Global.set_hotbar_selection(i)
			return

	# Scroll wheel
	if event is InputEventMouseButton:
		if event.pressed:
			if event.button_index == MOUSE_BUTTON_WHEEL_UP:
				Global.set_hotbar_selection((selected_index - 1 + 9) % 9)
			elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				Global.set_hotbar_selection((selected_index + 1) % 9)

func _on_selection_changed(index: int):
	_highlight_slot(index)

func _highlight_slot(index: int):
	# Remove highlight from old slot
	if selected_index < slots.size():
		slots[selected_index].modulate = NORMAL_COLOR
	selected_index = index
	# Apply highlight to new slot
	if selected_index < slots.size():
		slots[selected_index].modulate = SELECTED_COLOR

func _refresh_hotbar():
	# Sync first 9 inventory slots into hotbar display
	for i in range(min(slots.size(), 9)):
		var slot = slots[i]
		var icon  = slot.get_node_or_null("ItemIcon")
		var label = slot.get_node_or_null("Quantity")
		if icon == null or label == null:
			continue

		var item = Global.Inventory[i]
		if item != null:
			icon.texture = item["texture"]
			icon.visible = true
			label.text = str(item["quantity"])
			label.visible = item["quantity"] > 1
		else:
			icon.texture = null
			icon.visible = false
			label.visible = false
