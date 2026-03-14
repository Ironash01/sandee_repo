extends Node2D

@export var obj_name = ""
@export var obj_type = ""
@export var item_texture = Texture
@export var smelting_ui: PackedScene
@onready var col_interact_shape = $Sprite2D/Area2D/interact_shape
var sm_instance

func _ready() -> void:
	sm_instance = smelting_ui.instantiate()
	add_child(sm_instance)
	sm_instance.visible = false
	col_interact_shape.disabled = true # disable instance of area2d to save resources.
	if obj_type == "furnace":
		furnace()
	pass

func furnace():
	col_interact_shape.disabled = false # enable back the collision
	
	

func _on_area_2d_body_entered(body: CharacterBody2D) -> void:
	print("col")


func _on_area_2d_body_exited(body: CharacterBody2D) -> void:
	print("col")
