extends RefCounted
class_name PixieAI

# ── Pixie AI (MobCombatData.ai_type == "PIXIE") ────────────────────
# A flying pixie that roams the pixie cave. Movement only flies toward CLEAR
# space (a short physics raycast ahead — walls/ores block it, and it steers
# perpendicular to slip around obstacles).
#
# Chasing is VISION-based, so the pixie doesn't home in through walls:
#   - it only commits to chasing while it can see the player (line-of-sight
#     raycast), refreshing a 5-second memory window;
#   - once it loses sight, it keeps chasing only while that memory lasts
#     ("has the vision of a player in the last 5 seconds");
#   - when the memory expires it drops back to idle roaming.
# Contact damage is dealt by the mob body script (Global.damage_player).

enum State { ROAM, CHASE, ATTACK }

const AGGRO_RANGE:       float = 160.0
const ATTACK_RANGE:      float = 30.0
const LOOKAHEAD:         float = 22.0   # px scanned ahead of the move direction
const ROAM_SPEED_FACTOR: float = 0.5
const CHASE_MEMORY_TIME: float = 5.0    # seconds of "lost sight" before giving up
# The player's collision box (PlayerCol: 20x12 at y +17) sits BELOW the chest
# origin, so rays aimed at the origin itself end short of the shape and never
# register a hit — LOS/chase checks must aim at the box's center instead.
const PLAYER_AIM_OFFSET_Y: float = 17.0
# Close-range sense radius: within this the pixie aggros even without LOS
# (it can hear/sense the player through the gap it's standing in).
const SENSE_RANGE:       float = 60.0

var _state:        State   = State.ROAM
var _roam_dir:     Vector2 = Vector2.ZERO
var _roam_timer:   float   = 0.0
var _chase_memory: float   = 0.0

func physics_update(mob: CharacterBody2D, speed: float, _tilemap: TileMapLayer, delta: float) -> Vector2:
	# Player dead (pre-respawn): hold still. Dispersal only lasts 2s, so
	# without this every mob resumes chasing the frozen death position.
	if Global.player_is_dead:
		return Vector2.ZERO
	var player: Node2D = _combat_target(mob)
	if player == null or not is_instance_valid(player):
		return _roam(mob, speed, delta)

	var to_player: Vector2 = player.global_position - mob.global_position
	var dist: float = to_player.length()
	# Attack unconditionally when physically close enough — no vision/memory
	# requirement to bite. Without this, an overlapping pixie (player stopped
	# moving) gets a degenerate LOS ray, its chase-memory drains, and it wanders
	# off just far enough to stop attacking forever.
	if dist <= ATTACK_RANGE:
		_state = State.ATTACK
		return Vector2.ZERO

	# Aggro on vision OR close range: either the pixie has a clear line of
	# sight within aggro range, or the player is close enough to sense without
	# one. Either refreshes the chase-memory window.
	var has_vision: bool = dist < AGGRO_RANGE and _has_los(mob, player.global_position)
	var in_sense_range: bool = dist <= SENSE_RANGE
	if has_vision or in_sense_range:
		_chase_memory = CHASE_MEMORY_TIME
	else:
		_chase_memory = maxf(0.0, _chase_memory - delta)

	if _chase_memory > 0.0:
		_state = State.CHASE
		var dir: Vector2 = to_player / dist
		if _path_is_clear(mob, dir):
			return dir * speed
		return _steer_around(mob, dir, speed)

	# Lost recent vision — idle again (back to roaming).
	return _roam(mob, speed, delta)

func _roam(mob: CharacterBody2D, speed: float, delta: float) -> Vector2:
	_state = State.ROAM
	_roam_timer -= delta
	if _roam_timer <= 0.0:
		_roam_dir   = _pick_clear_dir(mob)
		_roam_timer = randf_range(1.0, 3.0)
	if _roam_dir == Vector2.ZERO:
		return Vector2.ZERO
	return _roam_dir * speed * ROAM_SPEED_FACTOR

func _pick_clear_dir(mob: CharacterBody2D) -> Vector2:
	for _i in range(8):
		var dir: Vector2 = Vector2.from_angle(randf() * TAU)
		if _path_is_clear(mob, dir):
			return dir
	return Vector2.ZERO

# When the direct chase line is blocked, try sliding perpendicular (either
# side) so the pixie can fly around a wall instead of stalling against it.
func _steer_around(mob: CharacterBody2D, desired: Vector2, speed: float) -> Vector2:
	var perp: Vector2 = Vector2(-desired.y, desired.x)
	for sign in [1.0, -1.0]:
		var dir: Vector2 = perp * sign
		if _path_is_clear(mob, dir):
			return dir * speed
	return Vector2.ZERO

# True when a short ray in `dir` from the pixie hits nothing solid. Excludes
# the pixie's own body AND the player — otherwise the player reads as an
# obstacle and the pixie orbits around them instead of flying in to bite.
func _path_is_clear(mob: CharacterBody2D, dir: Vector2) -> bool:
	if dir == Vector2.ZERO:
		return true
	var exclude: Array = [mob.get_rid()]
	var player: Node2D = Global.player_node as Node2D
	if player != null and is_instance_valid(player):
		exclude.append(player.get_rid())
	# Also never treat the provoked LUA (the chase target) as an obstacle.
	if mob.has_method("combat_target"):
		var t: Node2D = mob.call("combat_target") as Node2D
		if t != null and is_instance_valid(t) and t != player:
			exclude.append(t.get_rid())
	var space_state := mob.get_world_2d().direct_space_state
	var query := PhysicsRayQueryParameters2D.create(
		mob.global_position, mob.global_position + dir.normalized() * LOOKAHEAD)
	query.collision_mask = 1
	query.exclude = exclude
	return space_state.intersect_ray(query).is_empty()

# True when the pixie has a clear line of sight to the player (the ray
# reaches them — i.e. no wall/ore between them). The ray aims at the player's
# collision-shape CENTER (waist box, ~17px below the chest origin) — aiming at
# the origin would end short of the shape and never register a hit. The mask
# sees BOTH walls (layer 1) and the player (layer 4): a wall hit blocks LOS, a
# player hit confirms LOS.
func _has_los(mob: CharacterBody2D, target_pos: Vector2) -> bool:
	var space_state := mob.get_world_2d().direct_space_state
	var aim: Vector2 = target_pos + Vector2(0.0, PLAYER_AIM_OFFSET_Y)
	var query := PhysicsRayQueryParameters2D.create(mob.global_position, aim)
	query.collision_mask = 1 | 4
	query.exclude = [mob.get_rid()]
	var result := space_state.intersect_ray(query)
	if result.is_empty():
		return false
	var expected: Node = Global.player_node
	if mob.has_method("combat_target"):
		expected = mob.call("combat_target") as Node
	return (result as Dictionary).get("collider") == expected

# The node this pixie chases: the provoked combat LUA when a LUA has hit it,
# else the player.
func _combat_target(mob: CharacterBody2D) -> Node2D:
	if mob.has_method("combat_target"):
		return mob.call("combat_target") as Node2D
	return Global.player_node as Node2D