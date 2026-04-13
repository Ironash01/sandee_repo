extends CharacterBody2D

@export var movement_speed: int = 80
@onready var sprite:               Sprite2D         = $PlayerSprite
@onready var player_animation_tree: AnimationTree   = $PlayerAnimationTree
@onready var interaction_shape:     CollisionShape2D = $Area2D/InteractionCol
@onready var inventory_layer:       CanvasLayer      = $InventoryUI
var input_direction: Vector2 = Vector2.ZERO

func _ready() -> void:
	player_animation_tree.active = true
	$mainCam.make_current()
	Global.set_player_reference(self)
	# Keep input processing when paused so inventory/escape can close
	process_mode = Node.PROCESS_MODE_ALWAYS
	# Apply saved zoom and listen for settings changes
	$mainCam.zoom = Vector2(Global.camera_zoom, Global.camera_zoom)
	Global.camera_zoom_changed.connect(_on_camera_zoom_changed)

func _on_camera_zoom_changed(zoom: float) -> void:
	$mainCam.zoom = Vector2(zoom, zoom)

func get_input() -> void:
	input_direction = Input.get_vector(
		"gameplay_left", "gameplay_right", "gameplay_up", "gameplay_down"
	).normalized()
	velocity = input_direction * movement_speed

func _physics_process(_delta: float) -> void:
	if get_tree().paused:
		return
	get_input()
	move_and_slide()
	update_animation_tree()
	if velocity.x < 0:
		sprite.flip_h = true
	elif velocity.x > 0:
		sprite.flip_h = false

func update_animation_tree() -> void:
	if velocity == Vector2.ZERO:
		player_animation_tree["parameters/conditions/is_idle"]   = true
		player_animation_tree["parameters/conditions/is_moving"] = false
	else:
		player_animation_tree["parameters/conditions/is_idle"]   = false
		player_animation_tree["parameters/conditions/is_moving"] = true
	if input_direction != Vector2.ZERO:
		player_animation_tree["parameters/idle/blend_position"]    = input_direction
		player_animation_tree["parameters/walking/blend_position"] = input_direction

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("inventory"):
		var opening := not inventory_layer.visible
		inventory_layer.visible = opening
		Global.inventory_open = opening
		if not Global.pause_on_inventory:
			get_tree().paused = false
		else:
			get_tree().paused = opening
		Global.inventory_toggled.emit(opening)

func apply_item_effect(item) -> void:
	match item["effect"]:
		"Sword":
			print("You touched my sword")
		_:
			print("No effect uWu")
