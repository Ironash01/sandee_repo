extends "res://scripts/placeable_block.gd"

# ── Color Crafter (placed block) ────────────────────────────────────
# Left-click (without shift) opens the Color Crafter UI. Everything else —
# collision, the shift+click hold-to-break mining (pickaxe tier + break time),
# and the drop on break — is inherited from placeable_block.gd, so it mines
# and persists like any other block.

const MENU_SCRIPT: GDScript = preload("res://scripts/color_crafter_menu.gd")

var _menu: Control = null

func _ready() -> void:
	super._ready()
	add_to_group("ColorCrafter")
	var canvas := CanvasLayer.new()
	canvas.layer        = 2
	canvas.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(canvas)
	_menu = MENU_SCRIPT.new() as Control
	canvas.add_child(_menu)

func _input(event: InputEvent) -> void:
	if Global.is_mouse_event_over_ui(event):
		return
	# A plain left-click opens the colour UI; shift+click (and anything else)
	# falls through to the inherited mining behaviour.
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT \
			and not Global.is_shift_held():
		if _player_nearby and _hovered and not Global.block_mode \
				and not Global.any_ui_open() and not Global.pause_menu_open:
			if event.pressed and not get_viewport().is_input_handled():
				get_viewport().set_input_as_handled()
				_open_menu()
		return
	super._input(event)

func _open_menu() -> void:
	if _menu != null and _menu.has_method("open"):
		_menu.call("open")
