extends Node2D

var _player_nearby: bool = false
var _ui:            Control = null

@onready var _interact: Area2D = $InteractArea

func setup(data: ItemData) -> void:
	var sprite: Sprite2D = get_node_or_null("Sprite2D") as Sprite2D
	if sprite != null:
		sprite.texture = data.placeable_sprite if data.placeable_sprite != null else data.icon

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_interact.body_entered.connect(_on_body_entered)
	_interact.body_exited.connect(_on_body_exited)

	var menu_scene: PackedScene = load("res://scenes/ui/CraftingMenu.tscn") as PackedScene
	var canvas := CanvasLayer.new()
	canvas.layer        = 11
	canvas.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(canvas)
	_ui = menu_scene.instantiate() as Control
	_ui.set_meta("station_mode", true)
	canvas.add_child(_ui)
	_ui.visible = false

func _input(event: InputEvent) -> void:
	if not _player_nearby or _ui == null or _ui.visible:
		return
	# Block if any other UI is already open
	if Global.inventory_open or Global.lua_ui_open:
		return
	if event is InputEventMouseButton \
			and event.pressed \
			and event.button_index == MOUSE_BUTTON_LEFT:
		_ui.open_as_station()

func _on_body_entered(body: Node) -> void:
	if body.is_in_group("Player"):
		_player_nearby = true
		Global.player_near_station = true

func _on_body_exited(body: Node) -> void:
	if body.is_in_group("Player"):
		_player_nearby = false
		Global.player_near_station = false
		if _ui != null and _ui.visible:
			_ui.hide_menu()
