extends PanelContainer

@onready var icon_rect = $TextureRect 

# Adding '= null' makes this parameter "Nullable"
func display_item(item: ItemData = null):
	# Check if the node actually exists to prevent crashes
	if not icon_rect: 
		return

	if item != null:
		icon_rect.texture = item.icon
		icon_rect.visible = true
	else:
		# If no item, clear the texture and hide the rect
		icon_rect.texture = null
		icon_rect.visible = false
