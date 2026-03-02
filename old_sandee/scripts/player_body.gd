extends CharacterBody2D


@export var movement_speed: int = 80
@onready var sprite = $PlayerSprite
@onready var player_animation_tree : AnimationTree = $PlayerAnimationTree
@onready var interaction_shape = $InteractionShape

var input_direction : Vector2 = Vector2.ZERO

func _ready() -> void:
	player_animation_tree.active = true
func get_input():
	input_direction = Input.get_vector("gameplay_left", "gameplay_right", "gameplay_up", "gameplay_down").normalized()
	velocity = input_direction * movement_speed

func _physics_process(delta):
	get_input()
	move_and_slide()
	update_animation_tree()
	if velocity.x < 0:
		sprite.flip_h = true
	elif velocity.x > 0:
		sprite.flip_h = false
	pass
	
	var overlapping_areas = interaction_shape.get_overlapping_areas()
	if overlapping_areas.size() > 0:
		for area in overlapping_areas:
				print("Near the Crafting Station!")
				# You can add logic here to enable a "Press E to Craft" prompt
	
	
func update_animation_tree():
	if(velocity == Vector2.ZERO):
		player_animation_tree["parameters/conditions/is_idle"] = true
		player_animation_tree["parameters/conditions/is_moving"] = false
	else:
		player_animation_tree["parameters/conditions/is_idle"] = false
		player_animation_tree["parameters/conditions/is_moving"] = true
	
	if(input_direction != Vector2.ZERO):
		player_animation_tree["parameters/Idle/blend_position"] = input_direction
		player_animation_tree["parameters/Walk/blend_position"] = input_direction
	
