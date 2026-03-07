extends Area2D
class_name InteractionComponent

@export var interaction_radius: float = 100.0
var current_target: Node2D = null

func _ready():
	# 1. Clear existing shapes to avoid duplicates
	for child in get_children():
		if child is CollisionShape2D:
			child.queue_free()
			
	# 2. Create the sensor area
	var circle = CircleShape2D.new()
	circle.radius = interaction_radius
	var collision_shape = CollisionShape2D.new()
	collision_shape.shape = circle
	add_child(collision_shape)
	
	print("Radar is online and searching...")

func _process(_delta: float) -> void:
	var new_nearest = _find_nearest()
	
	if new_nearest != current_target:
		_switch_target(new_nearest)

func _find_nearest() -> Node2D:
	var list = get_overlapping_areas()
	var nearest: Node2D = null
	var shortest_dist = INF
	
	for area in list:
		var dist = global_position.distance_squared_to(area.global_position)
		if dist < shortest_dist:
			shortest_dist = dist
			nearest = area
	return nearest

func _switch_target(new_target: Node2D):
	if current_target and current_target.has_method("unhighlight"):
		current_target.unhighlight()
		
	current_target = new_target
	
	if current_target:
		print("Targeting: ", current_target.name)
		if current_target.has_method("highlight"):
			current_target.highlight()
