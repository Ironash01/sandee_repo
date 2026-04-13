extends Node2D

var _player_nearby: bool   = false
var _menu:          Control = null

@onready var _interact: Area2D = $InteractArea

func setup(data: ItemData) -> void:
	var sprite: Sprite2D = get_node_or_null("Sprite2D") as Sprite2D
	if sprite != null:
		sprite.texture = data.placeable_sprite if data.placeable_sprite != null else data.icon

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_interact.body_entered.connect(_on_body_entered)
	_interact.body_exited.connect(_on_body_exited)
	# Instantiate crafting menu into a CanvasLayer so it renders above world
	var canvas := CanvasLayer.new()
	canvas.layer = 10
	canvas.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(canvas)
	var menu_scene: PackedScene = load("res://scenes/ui/CraftingMenu.tscn") as PackedScene
	_menu = menu_scene.instantiate() as Control
	canvas.add_child(_menu)

func _input(event: InputEvent) -> void:
	if not _player_nearby:
		return
	if event is InputEventMouseButton \
			and event.pressed \
			and event.button_index == MOUSE_BUTTON_LEFT:
		if _menu != null and not _menu.visible:
			_menu.call("show_menu")

func _on_body_entered(body: Node) -> void:
	if body.is_in_group("Player"):
		_player_nearby = true
		Global.player_near_station = true

func _on_body_exited(body: Node) -> void:
	if body.is_in_group("Player"):
		_player_nearby = false
		Global.player_near_station = false
		if _menu != null and _menu.visible:
			_menu.call("hide_menu")
