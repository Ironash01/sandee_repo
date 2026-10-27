extends RefCounted
class_name HeadlessFishAI

# ── Headless Fish AI ──────────────────────────────────────────────
# A flying night-only enemy that orbits the player ~15 blocks away.
# Uses raycast-based LOS detection and a single-attacker claim system.
# When not attacking, orbits the player with organic wobble.
# When attacking, commits to a dive toward the player with acceleration.

enum State { ORBIT, APPROACH, WINDUP, ATTACK, RETURN }

# ── Orbit ─────────────────────────────────────────────────────────
const ORBIT_RADIUS: float = 480.0       # 15 blocks * 32 px
const ORBIT_RADIUS_WOBBLE: float = 40.0
const ORBIT_SPEED: float = 0.4          # radians/sec around the player
const ORBIT_ARRIVE_DIST: float = 20.0   # close enough to orbit point

# ── Detection ─────────────────────────────────────────────────────
const DETECT_RANGE: float = 512.0       # 16 blocks
const PLAYER_AIM_OFFSET_Y: float = 17.0 # player collision center offset

# ── Attack ────────────────────────────────────────────────────────
# ── Attack: pause → lock on → rocket sweep ────────────────────────
# Fair-play pattern. In range the fish STOPS and locks onto the player
# (WINDUP_TIME) — a visible telegraph — then rockets straight down the line
# it locked, with NO tracking, so a player who reads the tell can step aside.
# One sweep every ATTACK_COOLDOWN (shared across all fish).
const WINDUP_TIME: float = 0.45         # pause + lock-on before the sweep
const ATTACK_ACCEL: float = 1200.0      # px/s² — almost instantly up to speed
const ATTACK_MAX_SPEED: float = 420.0   # rocket sweep speed
const ATTACK_COMMIT_TIME: float = 0.6   # seconds of committed sweep
const ATTACK_RANGE: float = 28.0        # begin the windup within this distance
const ATTACK_COOLDOWN: float = 5.0
const ATTACK_WOBBLE: float = 0.15       # slight random angle offset on sweep
# Chasing the player (APPROACH state) runs at 1.5x the mob's base speed — a
# 50% speed increase over orbiting. (The rocket sweep is separate.)
const CHASE_SPEED_MULT: float = 1.5
# Normal cruising (orbiting / flying back to orbit) is HALF the base speed.
# Only the chase and the rocket sweep are fast.
const CRUISE_SPEED_MULT: float = 0.5

# ── Avoidance ─────────────────────────────────────────────────────
const LOOKAHEAD: float = 24.0
const AVOID_STRENGTH: float = 150.0
# Reroute candidates, ordered by how little they deviate from the goal, so the
# FIRST clear one found is the CLOSEST OPEN PATH TOWARD the player — not just
# the most open direction. Full circle, so a dead end turns the fish around
# instead of stalling it against the wall.
const AVOID_ANGLES_DEG: Array = [
	0.0,
	15.0, -15.0, 30.0, -30.0, 45.0, -45.0, 60.0, -60.0, 75.0, -75.0,
	90.0, -90.0, 105.0, -105.0, 120.0, -120.0, 135.0, -135.0,
	150.0, -150.0, 165.0, -165.0, 180.0,
]

# ── Smooth flight (never snap) ────────────────────────────────────
# Bounded turn rate in rad/s. The fish ARCS toward its chosen path instead of
# instantly pointing at it — an instant direction flip reads as teleporting.
const TURN_RATE: float = 3.0            # ~172°/s
const FLIGHT_SPEED_CAP: float = 1.35    # × mob speed, non-attacking

# ── Separation ────────────────────────────────────────────────────
const SEPARATION_DIST: float = 40.0
const SEPARATION_STRENGTH: float = 60.0

# ── Stuck detection ───────────────────────────────────────────────
const STUCK_CHECK_INTERVAL: float = 0.5
const STUCK_THRESHOLD: float = 8.0      # px minimum movement per check
# Five minutes. A fish boxed in that long is KILLED (removed) — never
# teleported. With _find_clear_dir routing around obstacles this should be
# effectively unreachable; it exists only as a leak guard.
const STUCK_TIMEOUT: float = 300.0

# ── State ─────────────────────────────────────────────────────────
var _state: State = State.ORBIT
var _orbit_angle: float = 0.0
var _orbit_wobble: float = 0.0
var _approach_target: Vector2 = Vector2.ZERO
var _attack_dir: Vector2 = Vector2.ZERO
var _attack_timer: float = 0.0
var _return_timer: float = 0.0
# Windup / lock-on state for the rocket sweep.
var _windup_timer: float = 0.0
var _locked_target: Vector2 = Vector2.ZERO
# Current flight heading — rotated toward the chosen path at TURN_RATE so the
# fish banks around obstacles. Never set instantly.
var _heading: Vector2 = Vector2.ZERO
var _stuck_timer: float = 0.0
var _stuck_check_timer: float = 0.0
var _last_pos: Vector2 = Vector2.ZERO

# ── Attack claim (shared across all HeadlessFish) ─────────────────
static var _attack_claim_active: bool = false
static var _global_attack_cooldown: float = 0.0

func physics_update(mob: CharacterBody2D, speed: float, _tilemap: TileMapLayer, delta: float) -> Vector2:
	# Player dead (pre-respawn): hold still. Dispersal only lasts 2s, so
	# without this every fish resumes chasing the frozen death position.
	if Global.player_is_dead:
		return Vector2.ZERO
	var player: Node2D = _combat_target(mob)
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
			# Hopelessly stuck — kill this fish instead of leaving it vibrating
			# against a wall. It is NEVER teleported.
			if mob.has_method("_die"):
				mob.call("_die")
			return Vector2.ZERO

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
		State.WINDUP:
			vel = _windup(mob, player, speed, delta)
		State.ATTACK:
			vel = _attack_run(mob, player, speed, delta)
		State.RETURN:
			vel = _return_to_orbit(mob, player, speed, delta)

	# Apply separation from other HeadlessFish
	vel += _separation(mob)

	# Apply obstacle avoidance
	vel += _avoidance(mob, vel, delta)

	# ── Smooth flight ─────────────────────────────────────────────
	# The steering forces are ADDED on top of the state velocity, so cap the
	# magnitude (no lurching) and rotate the current heading toward the chosen
	# path at TURN_RATE. The fish FLIES in an arc toward the open path; it must
	# never instantly snap onto it, which is what looked like teleporting.
	var cap: float
	match _state:
		State.ATTACK:
			cap = ATTACK_MAX_SPEED
		State.APPROACH:
			# Chasing runs at CHASE_SPEED_MULT × base — the cap must allow it.
			cap = speed * CHASE_SPEED_MULT * 1.35
		_:
			cap = speed * FLIGHT_SPEED_CAP
	if vel.length() > cap:
		vel = vel.normalized() * cap
	if vel.length_squared() <= 0.001:
		return Vector2.ZERO
	var target_dir: Vector2 = vel.normalized()
	if _heading.length_squared() <= 0.001:
		_heading = target_dir
	else:
		var turn: float = TURN_RATE * delta
		if _state == State.ATTACK:
			turn *= 2.0
		_heading = _heading.rotated(clampf(_heading.angle_to(target_dir), -turn, turn))
	return _heading * vel.length()

# ── Orbit ─────────────────────────────────────────────────────────

func _orbit(mob: CharacterBody2D, player: Node2D, speed: float, delta: float) -> Vector2:
	speed *= CRUISE_SPEED_MULT   # normal cruising is half speed
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
		# In range: stop, pause and lock on before the rocket sweep.
		_begin_windup(mob, player)
		return Vector2.ZERO

	# Move toward a point slightly ahead of the player for the dive.
	# CHASE_SPEED_MULT scales the pursuit speed.
	var chase_speed: float = speed * CHASE_SPEED_MULT
	_approach_target = player.global_position + Vector2(randf_range(-20.0, 20.0), randf_range(-20.0, 20.0))
	var dir: Vector2 = (_approach_target - mob.global_position).normalized()

	if _path_is_clear(mob, dir):
		return dir * chase_speed * 1.2

	var best := _find_clear_dir(mob, dir)
	if best != Vector2.ZERO:
		return best * chase_speed * 1.2

	return dir * chase_speed * 0.5

# ── Attack (rocket sweep along the locked line) ───────────────────

func _attack_run(mob: CharacterBody2D, _player: Node2D, _speed: float, delta: float) -> Vector2:
	_attack_timer -= delta

	# Accelerate along the COMMITTED direction. No tracking — the sweep is a
	# straight rocket, which is what makes it dodgeable (fair).
	var current_speed: float = mob.velocity.length()
	var new_speed: float = minf(current_speed + ATTACK_ACCEL * delta, ATTACK_MAX_SPEED)

	# Only deviate if the committed line would fly into scenery.
	if not _path_is_clear(mob, _attack_dir):
		var alt := _find_clear_dir(mob, _attack_dir)
		if alt != Vector2.ZERO:
			_attack_dir = alt

	# Sweep over → back to normal flight; _force_release_claim starts the 5s
	# cooldown before the next sweep.
	if _attack_timer <= 0.0:
		_force_release_claim()
		_state = State.RETURN
		_return_timer = 1.5

	return _attack_dir * new_speed

# ── Return to orbit ───────────────────────────────────────────────

func _return_to_orbit(mob: CharacterBody2D, player: Node2D, speed: float, delta: float) -> Vector2:
	speed *= CRUISE_SPEED_MULT   # normal cruising is half speed
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
# Step 1 of the attack: claim the (shared) attack slot, then stop and lock on.
func _begin_windup(mob: CharacterBody2D, player: Node2D) -> void:
	if _attack_claim_active or _global_attack_cooldown > 0.0:
		# Another fish is mid-attack, or the 5s cooldown is still running —
		# keep circling instead of attacking.
		_state = State.ORBIT
		return
	_attack_claim_active = true
	_state = State.WINDUP
	_windup_timer = WINDUP_TIME
	_locked_target = player.global_position

# Step 2: hold position and keep the crosshair on the player. The sweep flies
# along the line locked when this pause ends, so a player who reads the tell
# can step out of it.
func _windup(_mob: CharacterBody2D, player: Node2D, _speed: float, delta: float) -> Vector2:
	_windup_timer -= delta
	_locked_target = player.global_position
	if _windup_timer <= 0.0:
		_begin_sweep(_mob)
	return Vector2.ZERO

# Step 3: commit. Point straight at the locked spot and rocket down that line.
func _begin_sweep(mob: CharacterBody2D) -> void:
	_state = State.ATTACK
	_attack_timer = ATTACK_COMMIT_TIME
	var to_lock: Vector2 = _locked_target - mob.global_position
	if to_lock.length_squared() > 0.001:
		_attack_dir = to_lock.normalized().rotated(randf_range(-ATTACK_WOBBLE, ATTACK_WOBBLE))
	else:
		_attack_dir = Vector2.from_angle(randf() * TAU)
	# Face the locked line immediately — the windup already telegraphed it, and
	# only the HEADING snaps here (the fish never jumps position).
	_heading = _attack_dir

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

# The closest OPEN path that still heads toward `desired` (the player): walk
# the candidate angles in order of increasing deviation and take the FIRST that
# is clear. Because the list covers the full circle, a fish with a wall dead
# ahead turns to the nearest open side, and a fish boxed in turns around.
func _find_clear_dir(mob: CharacterBody2D, desired: Vector2) -> Vector2:
	if desired.length_squared() < 0.001:
		return _find_open_field_dir(mob, Vector2.ZERO)
	for angle_deg in AVOID_ANGLES_DEG:
		var dir: Vector2 = desired.rotated(deg_to_rad(angle_deg))
		if _path_is_clear(mob, dir):
			return dir
	# Every direction — even straight back — is blocked within LOOKAHEAD. Fall
	# back to the widest-open heading so it still works its way out.
	return _find_open_field_dir(mob, desired)

# ── Open-field search ─────────────────────────────────────────────
# Casts OPEN_FIELD_RAYS rays evenly around the fish and returns the direction
# with the most free space, with a mild preference for directions that still
# head toward `preferred` (so it escapes AND keeps making progress).
const OPEN_FIELD_PROBE: float = 128.0
const OPEN_FIELD_RAYS:  int   = 16

func _find_open_field_dir(mob: CharacterBody2D, preferred: Vector2) -> Vector2:
	var best_dir := Vector2.ZERO
	var best_score := -1.0
	var has_pref: bool = preferred.length_squared() > 0.001
	var pref: Vector2 = preferred.normalized() if has_pref else Vector2.ZERO
	for i in range(OPEN_FIELD_RAYS):
		var dir := Vector2.from_angle(TAU * float(i) / float(OPEN_FIELD_RAYS))
		var open: float = _free_distance(mob, dir)
		var score: float = open
		if has_pref and dir.dot(pref) > 0.5:
			score += OPEN_FIELD_PROBE * 0.15   # tie-break toward the goal
		if score > best_score:
			best_score = score
			best_dir = dir
	return best_dir

# How far the fish can travel along `dir` before hitting an obstacle, capped
# at OPEN_FIELD_PROBE. `hit_from_inside` makes a ray starting inside a block
# (the wedged case) read as 0, so that direction is never chosen as "open".
func _free_distance(mob: CharacterBody2D, dir: Vector2) -> float:
	if dir.length_squared() < 0.001:
		return 0.0
	var space_state := mob.get_world_2d().direct_space_state
	var from: Vector2 = mob.global_position
	var query := PhysicsRayQueryParameters2D.create(from, from + dir.normalized() * OPEN_FIELD_PROBE)
	query.collision_mask  = 1
	query.hit_from_inside = true
	query.exclude = [mob.get_rid()]
	var result := space_state.intersect_ray(query)
	if result.is_empty():
		return OPEN_FIELD_PROBE
	return from.distance_to((result as Dictionary).get("position", from))

# ── Raycast helpers ───────────────────────────────────────────────

# ── Collision-aware clearance ─────────────────────────────────────

# The fish's own CollisionShape2D (cached) — used to sweep the ACTUAL body
# rather than a zero-width ray.
var _body_col: CollisionShape2D = null

func _body_collision(mob: CharacterBody2D) -> CollisionShape2D:
	if _body_col != null and is_instance_valid(_body_col):
		return _body_col
	for child in mob.get_children():
		if child is CollisionShape2D and (child as CollisionShape2D).shape != null:
			_body_col = child as CollisionShape2D
			break
	return _body_col

func _path_is_clear(mob: CharacterBody2D, dir: Vector2) -> bool:
	if dir.length_squared() < 0.001:
		return true
	var exclude: Array = [mob.get_rid()]
	var player: Node2D = _valid_player_node()
	if player != null:
		exclude.append(player.get_rid())
	# Also never treat the provoked LUA (the chase target) as an obstacle.
	if mob.has_method("combat_target"):
		var t: Node2D = mob.call("combat_target") as Node2D
		if t != null and is_instance_valid(t) and t != player:
			exclude.append(t.get_rid())
	var space_state := mob.get_world_2d().direct_space_state
	var step: Vector2 = dir.normalized() * LOOKAHEAD

	# Body-aware test: sweep the fish's actual circle along the motion. A single
	# centre ray says "clear" while the body's leading edge clips a corner —
	# exactly the diagonal-wall stall — so use cast_motion when we can.
	var col: CollisionShape2D = _body_collision(mob)
	if col != null:
		var params := PhysicsShapeQueryParameters2D.new()
		params.shape          = col.shape
		params.transform      = col.global_transform
		params.motion         = step
		params.collision_mask = 1
		params.exclude        = exclude
		params.margin         = 0.0
		var res: PackedFloat32Array = space_state.cast_motion(params)
		# res = [safe_fraction, unsafe_fraction]; 1.0 safe means the whole
		# sweep fits. Starting inside a block reports 0.0, which is blocked.
		if res.size() >= 1:
			return res[0] >= 1.0

	# Fallback (no collision shape): centre ray, reporting blocked when it
	# starts inside a block.
	var query := PhysicsRayQueryParameters2D.create(mob.global_position, mob.global_position + step)
	query.collision_mask = 1
	query.exclude = exclude
	query.hit_from_inside = true
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
	var expected: Node = _valid_player_node()
	if mob.has_method("combat_target"):
		expected = mob.call("combat_target") as Node
	return (result as Dictionary).get("collider") == expected

# The node this fish chases: the provoked combat LUA when a LUA has hit it, else
# the player.
func _combat_target(mob: CharacterBody2D) -> Node2D:
	if mob.has_method("combat_target"):
		return mob.call("combat_target") as Node2D
	return _valid_player_node()

func _valid_player_node() -> Node2D:
	# Global.player_node can be a freed reference during scene teardown.
	# Check the raw Variant before casting so a stale node never throws.
	var raw: Variant = Global.player_node
	if not is_instance_valid(raw):
		return null
	if raw is Node2D and (raw as Node2D).is_inside_tree():
		return raw as Node2D
	return null
