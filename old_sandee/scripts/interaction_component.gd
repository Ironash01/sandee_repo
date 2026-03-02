extends Area2D

func _physics_process(delta):
	# We call the function directly since we ARE the Area2D
	var bodies = get_overlapping_areas()
	if bodies.size() > 0:
		print("I see: ", bodies)
		
	


func _on_area_entered(area: Area2D) -> void:
	print("col")
	pass # Replace with function body.
