extends Node2D

# Furnace world object: the only placeable that uses ObjectItem.tscn. Left-
# click opens a standalone SmeltingMenu (own CanvasLayer, like the crafting
# station) — smelting does NOT live in the inventory panel anymore. Shift +
# left-click destroys the block and drops it back as an item.

@export var obj_name = ""
@export var obj_type = ""
@export var item_texture = Texture
@export var smelting_ui: PackedScene  # kept for scene compatibility
@onready var col_interact_shape = $Sprite2D/Area2D/interact_shape

# ── World registration (so Shift-destroy can unregister + drop the item) ──
var item_data:      ItemData = null
var _world_cell:    Vector2i = Vector2i(-99999, -99999)
var _world_ref:     Node     = null

var _player_nearby: bool = false
var _ui:            Control = null

const ITEM_SCENE: PackedScene = preload("res://scenes/ui/InventoryItem.tscn")
const INTERACT_RADIUS_PX: float = 64.0

func _ready() -> void:
	col_interact_shape.disabled = true
	if obj_type == "furnace":
		furnace()
	Global.request_close_all_ui.connect(_on_close_all_ui)

	var menu_scene: PackedScene = load("res://scenes/ui/SmeltingMenu.tscn") as PackedScene
	if menu_scene == null:
		return
	var canvas := CanvasLayer.new()
	canvas.layer        = 11
	canvas.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(canvas)
	_ui = menu_scene.instantiate() as Control
	canvas.add_child(_ui)
	_ui.visible = false

func setup(data: ItemData) -> void:
	item_data = data

func set_world_cell(cell: Vector2i, world: Node) -> void:
	_world_cell = cell
	_world_ref  = world

func furnace():
	col_interact_shape.disabled = false

func _on_close_all_ui() -> void:
	if _ui != null and _ui.visible:
		_ui.hide_menu()

func _on_area_2d_body_entered(body: CharacterBody2D) -> void:
	if body.is_in_group("Player"):
		_player_nearby = true

func _on_area_2d_body_exited(body: CharacterBody2D) -> void:
	if body.is_in_group("Player"):
		_player_nearby = false
		if _ui != null and _ui.visible:
			_ui.hide_menu()

# Left-click (nearby) opens the standalone smelting menu; Shift + left-click
# destroys this interactable (drops it back as an item).
func _input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT):
		return
	if Global.block_mode or Global.any_ui_open() or Global.pause_menu_open:
		return
	var p: Node2D = Global.player_node as Node2D
	if p == null or p.global_position.distance_to(global_position) > INTERACT_RADIUS_PX:
		return
	if Input.is_key_pressed(KEY_SHIFT):
		_destroy_shift()
		get_viewport().set_input_as_handled()
		return
	if _ui != null:
		_ui.open_as_station()
		get_viewport().set_input_as_handled()

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
