extends RefCounted
class_name WanderAI

# ── Passive clear-path wander AI (MobCombatData.ai_type == "WANDER") ──
# Friendly Bestiary creatures roam without chasing the player. Unlike the
# legacy WOLF wanderer, this AI probes the physics space before committing to a
# heading, so a tree, placed block or dungeon pillar does not stall it. The
# actor still owns movement, water veto, animation and y-sorting.

const LOOKAHEAD: float = 24.0
const DIRECTION_COUNT: int = 12

var _dir: Vector2 = Vector2.ZERO
var _timer: float = 0.0

func _init() -> void:
	_timer = randf_range(0.4, 1.8)

func physics_update(mob: CharacterBody2D, speed: float, water_layer: TileMapLayer,
		delta: float) -> Vector2:
	if Global.player_is_dead:
		return Vector2.ZERO
	_timer -= delta
	if _dir == Vector2.ZERO or _timer <= 0.0 or not _path_is_clear(mob, _dir):
		_pick_direction(mob, water_layer)
	if _dir == Vector2.ZERO:
		return Vector2.ZERO
	return _dir * speed

func _pick_direction(mob: CharacterBody2D, water_layer: TileMapLayer) -> void:
	var start: float = randf() * TAU
	# Try a fan of headings. A reef/water probe rejects a heading that would
	# immediately put the creature's centre over water; the actor's footprint
	# veto still clamps the final velocity.
	for i in range(DIRECTION_COUNT):
		var angle: float = start + TAU * float(i) / float(DIRECTION_COUNT)
		var candidate := Vector2.from_angle(angle)
		if not _path_is_clear(mob, candidate):
			continue
		if _touches_water(mob, water_layer, mob.global_position + candidate * LOOKAHEAD):
			continue
		_dir = candidate
		_timer = randf_range(1.0, 3.2)
		return
	_dir = Vector2.ZERO
	_timer = randf_range(0.5, 1.0)

func _path_is_clear(mob: CharacterBody2D, dir: Vector2) -> bool:
	if dir == Vector2.ZERO:
		return true
	var exclude: Array = [mob.get_rid()]
	var player: Node2D = Global.player_node as Node2D
	if player != null and is_instance_valid(player):
		exclude.append(player.get_rid())
	var space := mob.get_world_2d().direct_space_state
	if space == null:
		return true
	var query := PhysicsRayQueryParameters2D.create(
		mob.global_position, mob.global_position + dir.normalized() * LOOKAHEAD)
	query.collision_mask = 1
	query.exclude = exclude
	return space.intersect_ray(query).is_empty()

func _touches_water(mob: CharacterBody2D, water_layer: TileMapLayer, world_pos: Vector2) -> bool:
	if water_layer == null or not is_instance_valid(water_layer):
		return false
	var tile: Vector2i = water_layer.local_to_map(water_layer.to_local(world_pos))
	return water_layer.get_cell_source_id(tile) != -1
