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

var _state:        State   = State.ROAM
var _roam_dir:     Vector2 = Vector2.ZERO
var _roam_timer:   float   = 0.0
var _chase_memory: float   = 0.0

func physics_update(mob: CharacterBody2D, speed: float, _tilemap: TileMapLayer, delta: float) -> Vector2:
	var player: Node2D = Global.player_node as Node2D
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

	# Vision: in range AND a clear line of sight to the player.
	var has_vision: bool = dist < AGGRO_RANGE and _has_los(mob, player.global_position)
	if has_vision:
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
	var space_state := mob.get_world_2d().direct_space_state
	var query := PhysicsRayQueryParameters2D.create(
		mob.global_position, mob.global_position + dir.normalized() * LOOKAHEAD)
	query.collision_mask = 1
	query.exclude = exclude
	return space_state.intersect_ray(query).is_empty()

# True when the pixie has a clear line of sight to `target_pos` (the ray
# reaches it — i.e. no wall/ore between them).
func _has_los(mob: CharacterBody2D, target_pos: Vector2) -> bool:
	var space_state := mob.get_world_2d().direct_space_state
	var query := PhysicsRayQueryParameters2D.create(mob.global_position, target_pos)
	query.collision_mask = 1
	query.exclude = [mob.get_rid()]
	var result := space_state.intersect_ray(query)
	if result.is_empty():
		return false
	return (result as Dictionary).get("collider") == Global.player_node