extends AnimationPlayer

@export var animation_tree : AnimationTree
@export var player: CharacterBody2D

func _physics_process(delta: float) -> void:
	animation_tree.set("parameters/blend_position", player.velocity.normalized())
