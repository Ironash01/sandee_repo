extends AnimationPlayer

@export var animation_tree : AnimationTree
@onready var player : Player = get_owner()

func _physics_process(delta: float) -> void:
	animation_tree.set("parameters/blend_position", player.velocity.normalized)
