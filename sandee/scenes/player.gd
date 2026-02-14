extends CharacterBody2D

@export var speed: float = 200.0
@onready var sprite: AnimatedSprite2D = $PlayerAnimation

# Interaction
var interactable_in_range: Node = null  # current interactable
var interact_popup: Control = null       # instance of InteractPopUp

var last_direction: Vector2 = Vector2.DOWN

# preload the popup scene
var InteractPopUpScene = preload("res://scenes/InteractPopUp.tscn")


func _ready():
	if has_node("InteractDetector"):
		$InteractDetector.body_entered.connect(_on_body_entered)
		$InteractDetector.body_exited.connect(_on_body_exited)


func _physics_process(delta):
	var direction = Vector2.ZERO

	# Movement input
	direction.x = Input.get_action_strength("ui_right") - Input.get_action_strength("ui_left")
	direction.y = Input.get_action_strength("ui_down") - Input.get_action_strength("ui_up")

	if direction != Vector2.ZERO:
		direction = direction.normalized()
		velocity = direction * speed
		last_direction = direction
		play_walk_animation(direction)
	else:
		velocity = Vector2.ZERO
		play_idle_animation()

	move_and_slide()

	# Interaction input
	if Input.is_action_just_pressed("ui_accept") and interactable_in_range:
		interactable_in_range.call("interact", self)  # call object's interact function
		
	


func play_walk_animation(direction: Vector2):
	if abs(direction.x) > abs(direction.y):
		sprite.flip_h = direction.x < 0
		sprite.play("walk_right")
	else:
		sprite.flip_h = false
		if direction.y > 0:
			sprite.play("walk_down")
		else:
			sprite.play("walk_up")


func play_idle_animation():
	if abs(last_direction.x) > abs(last_direction.y):
		sprite.flip_h = last_direction.x < 0
		sprite.play("idle_facingright")
	else:
		sprite.flip_h = false
		if last_direction.y > 0:
			sprite.play("idle")
		else:
			sprite.play("idle_facingup")


# ---------------- Interaction Signals ----------------

func _on_body_entered(body: Node2D) -> void:
	# Only react to Layer 3 (interact range)
<<<<<<< Updated upstream
<<<<<<< Updated upstream
	if body.collision_layer & (1 << 4):  # Layer 3 = index 2
		interactable_in_range = body.get_parent()
		print("In range of:", interactable_in_range.name)
		show_interact_popup()
=======
	if body.get_collision_layer_value_(3):
		print("Player entered")
>>>>>>> Stashed changes
=======
	if body.get_collision_layer_value_(3):
		print("Player entered")
>>>>>>> Stashed changes


func _on_body_exited(body):
	if interactable_in_range and body == interactable_in_range.get_node("Interact"):
		interactable_in_range = null
		print("Left interactable range")
		hide_interact_popup()


# Interact Test

func show_interact_popup():
	if interact_popup == null:
		interact_popup = InteractPopUpScene.instantiate()
		get_tree().current_scene.add_child(interact_popup)  # add to root of current scene
	interact_popup.visible = true


func hide_interact_popup():
	if interact_popup:
		interact_popup.visible = false


func _on_interact_body_entered(body: Node2D) -> void:
	pass # Replace with function body.
