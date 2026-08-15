extends Node2D

var _player_nearby: bool = false
var _ui:            Control = null
var _world_cell:    Vector2i = Vector2i(-99999, -99999)
var _world_ref:     Node     = null
var item_data:      ItemData = null

const ITEM_SCENE: PackedScene = preload("res://scenes/ui/InventoryItem.tscn")

@onready var _interact: Area2D = $InteractArea

func setup(data: ItemData) -> void:
	item_data = data
	var sprite: Sprite2D = get_node_or_null("Sprite2D") as Sprite2D
	if sprite != null:
		sprite.texture = data.placeable_sprite if data.placeable_sprite != null else data.icon

func set_world_cell(cell: Vector2i, world: Node) -> void:
	_world_cell = cell
	_world_ref  = world

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_interact.body_entered.connect(_on_body_entered)
	_interact.body_exited.connect(_on_body_exited)
	Global.request_close_all_ui.connect(_on_close_all_ui)

	var menu_scene: PackedScene = load("res://scenes/ui/CraftingMenu.tscn") as PackedScene
	var canvas := CanvasLayer.new()
	canvas.layer        = 11
	canvas.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(canvas)
	_ui = menu_scene.instantiate() as Control
	_ui.set_meta("station_mode", true)
	canvas.add_child(_ui)
	_ui.visible = false

func _on_close_all_ui() -> void:
	if _ui != null and _ui.visible:
		_ui.hide_menu()

func _input(event: InputEvent) -> void:
	if not _player_nearby or _ui == null or _ui.visible:
		return
	if Global.block_mode:
		return
	if Global.any_ui_open() or Global.pause_menu_open:
		return
	if event is InputEventMouseButton \
			and event.pressed \
			and event.button_index == MOUSE_BUTTON_LEFT:
		# Hold Shift to destroy this interactable (drops it back as an item)
		# instead of opening the crafting UI.
		if Input.is_key_pressed(KEY_SHIFT):
			_destroy_shift()
			get_viewport().set_input_as_handled()
			return
		_ui.open_as_station()

# Destroy on Shift+click: unregister from the world and drop the block item.
func _destroy_shift() -> void:
	var world: Node = _world_ref if _world_ref != null else Global.world_node
	if world != null and world.has_method("unregister_block"):
		world.call("unregister_block", _world_cell)
	if item_data != null:
		var drop: Node = ITEM_SCENE.instantiate()
		drop.call("set_item_data", item_data)
		var drop_parent: Node = _world_ref if _world_ref != null else Global.world_node
		if drop_parent != null:
			drop_parent.add_child(drop)
			(drop as Node2D).global_position = global_position + Vector2(randf_range(-20, 20), randf_range(-20, 20))
	queue_free()

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
