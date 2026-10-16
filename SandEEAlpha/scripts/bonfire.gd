extends "res://scripts/placeable_block.gd"

# ── Bonfire ──────────────────────────────────────────────────────────
# A placeable block that ALSO sets the player's respawn point. It joins the
# "Bonfire" group so the minimap draws it as a green marker (minimap.gd), and it
# lights up + animates through the base PlaceableBlock (the item sets is_torch
# and a place_animation_sheet). Breaking it clears the respawn point if it was
# the active one.

func _ready() -> void:
	super()
	add_to_group("Bonfire")
	# The world assigns our position AFTER add_child() (which fires _ready), so
	# register on the next idle frame when global_position is valid.
	call_deferred("_register_bonfire")

func _register_bonfire() -> void:
	if not is_inside_tree():
		return
	# Only the OVERWORLD sets a respawn point — a cave/dungeon bonfire's
	# coordinates are structure-local and invalid for the overworld respawn, so
	# there it acts as a plain light/block.
	var world: Node = _world_ref if _world_ref != null else Global.world_node
	if world != null and world.has_method("is_overworld") and not bool(world.call("is_overworld")):
		return
	Global.set_spawn_point(global_position)

func _break() -> void:
	# Only clear the respawn point if THIS bonfire is the active one.
	if Global.has_spawn_point and Global.spawn_point.distance_to(global_position) < 1.0:
		Global.clear_spawn_point()
	super()
