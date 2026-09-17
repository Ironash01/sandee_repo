extends RefCounted
class_name HeadlessFishAI

# ── Headless Fish AI ──────────────────────────────────────────────
# A flying night-only enemy that orbits the player ~15 blocks away.
# Uses raycast-based LOS detection and a single-attacker claim system.
# When not attacking, orbits the player with organic wobble.
# When attacking, commits to a dive toward the player with acceleration.

enum State { ORBIT, APPROACH, ATTACK, RETURN }

# ── Orbit ─────────────────────────────────────────────────────────
const ORBIT_RADIUS: float = 480.0       # 15 blocks * 32 px
const ORBIT_RADIUS_WOBBLE: float = 40.0
const ORBIT_SPEED: float = 0.4          # radians/sec around the player
const ORBIT_ARRIVE_DIST: float = 20.0   # close enough to orbit point

# ── Detection ─────────────────────────────────────────────────────
const DETECT_RANGE: float = 512.0       # 16 blocks
const PLAYER_AIM_OFFSET_Y: float = 17.0 # player collision center offset

# ── Attack ────────────────────────────────────────────────────────
const ATTACK_ACCEL: float = 220.0       # px/s² acceleration during dive
const ATTACK_MAX_SPEED: float = 220.0   # cap during dive
const ATTACK_COMMIT_TIME: float = 1.2   # seconds of committed dive
const ATTACK_RANGE: float = 28.0        # damage dealt within this distance
const ATTACK_COOLDOWN: float = 5.0
const ATTACK_WOBBLE: float = 0.15       # slight random angle offset on dive

# ── Avoidance ─────────────────────────────────────────────────────
const LOOKAHEAD: float = 24.0
const AVOID_STRENGTH: float = 150.0

# ── Separation ────────────────────────────────────────────────────
const SEPARATION_DIST: float = 40.0
const SEPARATION_STRENGTH: float = 60.0

# ── Stuck detection ───────────────────────────────────────────────
const STUCK_CHECK_INTERVAL: float = 0.5
const STUCK_THRESHOLD: float = 8.0      # px minimum movement per check
const STUCK_TIMEOUT: float = 3.0        # seconds before giving up

# ── State ─────────────────────────────────────────────────────────
var _state: State = State.ORBIT
var _orbit_angle: float = 0.0
var _orbit_wobble: float = 0.0
var _approach_target: Vector2 = Vector2.ZERO
var _attack_dir: Vector2 = Vector2.ZERO
var _attack_timer: float = 0.0
var _return_timer: float = 0.0
var _stuck_timer: float = 0.0
var _stuck_check_timer: float = 0.0
var _last_pos: Vector2 = Vector2.ZERO

# ── Attack claim (shared across all HeadlessFish) ─────────────────
static var _attack_claim_active: bool = false
static var _global_attack_cooldown: float = 0.0

func physics_update(mob: CharacterBody2D, speed: float, _tilemap: TileMapLayer, delta: float) -> Vector2:
	var player: Node2D = Global.player_node as Node2D
	if player == null or not is_instance_valid(player):
		return Vector2.ZERO

	# Update global attack cooldown
	_global_attack_cooldown = maxf(0.0, _global_attack_cooldown - delta)

	# Stuck detection
	_stuck_check_timer -= delta
	if _stuck_check_timer <= 0.0:
		_stuck_check_timer = STUCK_CHECK_INTERVAL
		var moved: float = mob.global_position.distance_to(_last_pos)
		if moved < STUCK_THRESHOLD:
			_stuck_timer += STUCK_CHECK_INTERVAL
		else:
			_stuck_timer = 0.0
		_last_pos = mob.global_position
		if _stuck_timer >= STUCK_TIMEOUT:
			_force_release_claim()
			_state = State.RETURN
			_return_timer = 2.0
			_stuck_timer = 0.0

	# Check for player detection (ORBIT → APPROACH)
	if _state == State.ORBIT:
		var dist: float = mob.global_position.distance_to(player.global_position)
		if dist < DETECT_RANGE and _has_los(mob, player.global_position):
			_state = State.APPROACH
			_approach_target = player.global_position

	var vel := Vector2.ZERO

	match _state:
		State.ORBIT:
			vel = _orbit(mob, player, speed, delta)
		State.APPROACH:
			vel = _approach(mob, player, speed, delta)
		State.ATTACK:
			vel = _attack_run(mob, player, speed, delta)
		State.RETURN:
			vel = _return_to_orbit(mob, player, speed, delta)

	# Apply separation from other HeadlessFish
	vel += _separation(mob)

	# Apply obstacle avoidance
	vel += _avoidance(mob, vel, delta)

	return vel

# ── Orbit ─────────────────────────────────────────────────────────

func _orbit(mob: CharacterBody2D, player: Node2D, speed: float, delta: float) -> Vector2:
	_orbit_angle += ORBIT_SPEED * delta
	_orbit_wobble = sin(_orbit_angle * 0.7) * ORBIT_RADIUS_WOBBLE

	var orbit_dist: float = ORBIT_RADIUS + _orbit_wobble
	var target_pos: Vector2 = player.global_position + Vector2.from_angle(_orbit_angle) * orbit_dist

	var to_target: Vector2 = target_pos - mob.global_position
	var dist: float = to_target.length()

	if dist < ORBIT_ARRIVE_DIST:
		return Vector2.ZERO

	var dir: Vector2 = to_target / dist
	var desired_speed: float = clampf(dist * 2.0, speed * 0.3, speed)

	# Check for obstacles and player LOS
	if _has_los(mob, player.global_position) and _path_is_clear(mob, dir):
		return dir * desired_speed

	# Can't see player or path blocked — search for clear direction
	var best := _find_clear_dir(mob, dir)
	if best != Vector2.ZERO:
		return best * desired_speed

	return dir * desired_speed * 0.3

# ── Approach (transition to attack) ───────────────────────────────

func _approach(mob: CharacterBody2D, player: Node2D, speed: float, _delta: float) -> Vector2:
	var to_player: Vector2 = player.global_position - mob.global_position
	var dist: float = to_player.length()

	if dist <= ATTACK_RANGE:
		_start_attack(mob, player)
		return Vector2.ZERO

	# Move toward a point slightly ahead of the player for the dive
	_approach_target = player.global_position + Vector2(randf_range(-20.0, 20.0), randf_range(-20.0, 20.0))
	var dir: Vector2 = (_approach_target - mob.global_position).normalized()

	if _path_is_clear(mob, dir):
		return dir * speed * 1.2

	var best := _find_clear_dir(mob, dir)
	if best != Vector2.ZERO:
		return best * speed * 1.2

	return dir * speed * 0.5

# ── Attack (committed dive) ───────────────────────────────────────

func _attack_run(mob: CharacterBody2D, player: Node2D, _speed: float, delta: float) -> Vector2:
	_attack_timer -= delta

	# Accelerate in committed direction
	var current_speed: float = mob.velocity.length()
	var new_speed: float = minf(current_speed + ATTACK_ACCEL * delta, ATTACK_MAX_SPEED)

	# Slight course correction during dive (not full re-targeting)
	var to_player: Vector2 = player.global_position - mob.global_position
	if to_player.length_squared() > 0.001:
		var desired_dir: Vector2 = to_player.normalized()
		_attack_dir = _attack_dir.lerp(desired_dir, 0.3 * delta).normalized()

	# Check for obstacles during attack — steer around
	if not _path_is_clear(mob, _attack_dir):
		var alt := _find_clear_dir(mob, _attack_dir)
		if alt != Vector2.ZERO:
			_attack_dir = alt

	# End attack after commit time
	if _attack_timer <= 0.0:
		_force_release_claim()
		_state = State.RETURN
		_return_timer = 1.5

	return _attack_dir * new_speed

# ── Return to orbit ───────────────────────────────────────────────

func _return_to_orbit(mob: CharacterBody2D, player: Node2D, speed: float, delta: float) -> Vector2:
	_return_timer -= delta

	# Calculate orbit position
	_orbit_angle += ORBIT_SPEED * delta * 0.5
	var orbit_dist: float = ORBIT_RADIUS + sin(_orbit_angle * 0.7) * ORBIT_RADIUS_WOBBLE
	var orbit_pos: Vector2 = player.global_position + Vector2.from_angle(_orbit_angle) * orbit_dist

	var to_orbit: Vector2 = orbit_pos - mob.global_position
	var dist: float = to_orbit.length()

	# Transition back to orbit when close enough or timer expired
	if dist < ORBIT_ARRIVE_DIST * 2.0 or _return_timer <= 0.0:
		_state = State.ORBIT
		return Vector2.ZERO

	var dir: Vector2 = to_orbit / dist
	var desired_speed: float = clampf(dist * 1.5, speed * 0.5, speed * 1.2)

	if _path_is_clear(mob, dir):
		return dir * desired_speed

	var best := _find_clear_dir(mob, dir)
	if best != Vector2.ZERO:
		return best * desired_speed

	return dir * desired_speed * 0.5

# ── Attack management ─────────────────────────────────────────────

func _start_attack(mob: CharacterBody2D, player: Node2D) -> void:
	if _attack_claim_active or _global_attack_cooldown > 0.0:
		# Another fish is attacking or cooldown active — stay in orbit
		_state = State.ORBIT
		return

	_attack_claim_active = true
	_state = State.ATTACK
	_attack_timer = ATTACK_COMMIT_TIME

	var to_player: Vector2 = player.global_position - mob.global_position
	if to_player.length_squared() > 0.001:
		_attack_dir = to_player.normalized()
		# Add slight random wobble to the dive
		_attack_dir = _attack_dir.rotated(randf_range(-ATTACK_WOBBLE, ATTACK_WOBBLE))
	else:
		_attack_dir = Vector2.from_angle(randf() * TAU)

static func _force_release_claim() -> void:
	_attack_claim_active = false
	_global_attack_cooldown = ATTACK_COOLDOWN

# ── Separation ────────────────────────────────────────────────────

func _separation(mob: CharacterBody2D) -> Vector2:
	var force := Vector2.ZERO
	var tree: SceneTree = mob.get_tree()
	if tree == null:
		return Vector2.ZERO
	for node in tree.get_nodes_in_group("HeadlessFish"):
		if node == mob or not (node is Node2D):
			continue
		var d: Vector2 = mob.global_position - (node as Node2D).global_position
		var dist: float = d.length()
		if dist < SEPARATION_DIST and dist > 0.001:
			force += d / dist * (1.0 - dist / SEPARATION_DIST)
	if force.length_squared() > 0.001:
		return force.normalized() * SEPARATION_STRENGTH
	return Vector2.ZERO

# ── Obstacle avoidance ────────────────────────────────────────────

func _avoidance(mob: CharacterBody2D, desired: Vector2, _delta: float) -> Vector2:
	if desired.length_squared() < 0.001:
		return Vector2.ZERO
	if _path_is_clear(mob, desired.normalized()):
		return Vector2.ZERO
	# Path blocked — steer perpendicular
	var perp := Vector2(-desired.y, desired.x)
	for sign in [1.0, -1.0]:
		var dir: Vector2 = perp * sign
		if _path_is_clear(mob, dir):
			return dir * AVOID_STRENGTH
	return -desired.normalized() * AVOID_STRENGTH * 0.5

func _find_clear_dir(mob: CharacterBody2D, desired: Vector2) -> Vector2:
	for angle_deg in [15.0, -15.0, 30.0, -30.0, 45.0, -45.0, 60.0, -60.0, 90.0, -90.0]:
		var dir: Vector2 = desired.rotated(deg_to_rad(angle_deg))
		if _path_is_clear(mob, dir):
			return dir
	return Vector2.ZERO

# ── Raycast helpers ───────────────────────────────────────────────

func _path_is_clear(mob: CharacterBody2D, dir: Vector2) -> bool:
	if dir.length_squared() < 0.001:
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

func _has_los(mob: CharacterBody2D, target_pos: Vector2) -> bool:
	var space_state := mob.get_world_2d().direct_space_state
	var aim: Vector2 = target_pos + Vector2(0.0, PLAYER_AIM_OFFSET_Y)
	var query := PhysicsRayQueryParameters2D.create(mob.global_position, aim)
	query.collision_mask = 1 | 4
	query.exclude = [mob.get_rid()]
	var result := space_state.intersect_ray(query)
	if result.is_empty():
		return false
	return (result as Dictionary).get("collider") == Global.player_node
