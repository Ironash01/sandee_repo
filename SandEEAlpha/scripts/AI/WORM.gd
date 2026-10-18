extends RefCounted
class_name WormAI

# ── Desert worm AI ──────────────────────────────────────────────────
# The worm waits underground, then surfaces after a 5-7 second timer.
# Once above ground it commits to the chase and does NOT burrow while
# the player stays within CHASE_RADIUS — it only returns underground
# once they escape.
# While underground it drifts toward the player so it surfaces nearby,
# but stops entirely if the player is beyond CHASE_RADIUS.
# OUT OF THE DESERT it stops chasing: it wanders for a random beat and an
# above-ground worm then burrows itself (see _wander_step).

var _target: Node2D = null
var _burrowing: bool = false  # false = underground, true = above ground
var _world: Node = null

# ── Cycle timer ────────────────────────────────────────────────────
var _cycle_timer: float = 0.0
const CYCLE_MIN: float = 5.0
const CYCLE_MAX: float = 7.0
const CHASE_RADIUS: float = 640.0  # 20 blocks * 32 px/block

# ── Out-of-desert wander ───────────────────────────────────────────
# Replaces the old "freeze in place" behaviour when the player leaves the
# biome: the worm roams on the spot and, once above ground, burrows again
# after a random WANDER_BURROW_* second delay.
var _wandering:          bool    = false
var _wander_dir:         Vector2 = Vector2.ZERO
var _wander_retarget:    float   = 0.0
var _wander_burrow_wait: float   = 0.0
const WANDER_SPEED_MULT:   float = 0.55  # roam slower than the chase
const WANDER_RETARGET_MIN: float = 0.8   # seconds between random turns
const WANDER_RETARGET_MAX: float = 1.8
const WANDER_BURROW_MIN:   float = 2.0   # seconds above ground before diving
const WANDER_BURROW_MAX:   float = 5.0

func _init() -> void:
	_cycle_timer = randf_range(CYCLE_MIN, CYCLE_MAX)
	_burrowing = false  # start underground

func physics_update(mob: CharacterBody2D, speed: float, water_layer: TileMapLayer, delta: float) -> Vector2:
	# Player dead (pre-respawn): hold still. Dispersal only lasts 2s, so
	# without this the worm resumes chasing the frozen death position.
	if Global.player_is_dead:
		return Vector2.ZERO
	_target = _combat_target(mob)
	_world = Global.world_node

	if _target == null or not is_instance_valid(_target) or _world == null:
		return Vector2.ZERO

	# ── Only active inside desert biome ─────────────────────────────
	# Chasing is desert-only, but freezing in place when the player steps out
	# just looked broken — so out of the biome the worm wanders for a random
	# beat and an above-ground one burrows itself shortly after.
	if not _is_in_desert(_target.global_position):
		return _wander_step(mob, speed, delta)
	# Player is back in the desert — drop the roam bookkeeping so the normal
	# chase / emerge logic resumes cleanly.
	_wandering = false

	var to_player: Vector2 = _target.global_position - mob.global_position
	var dist: float = to_player.length()

	if _burrowing:
		# ── Above ground: chase the player. Do NOT burrow while they are
		#    still within chase range — the worm commits to the chase and
		#    only returns underground once the player escapes.
		if dist > CHASE_RADIUS:
			_burrowing = false
			_cycle_timer = randf_range(CYCLE_MIN, CYCLE_MAX)
			return Vector2.ZERO
		return to_player.normalized() * speed

	# ── Underground: wait out the emergence timer, then surface. ────
	# Once the timer elapses the worm stays above ground (no toggle back).
	_cycle_timer -= delta
	if _cycle_timer <= 0.0:
		_burrowing = true
		_cycle_timer = randf_range(CYCLE_MIN, CYCLE_MAX)

	# Still drift toward the player while hidden so it surfaces nearby,
	# but stop chasing if they are too far away.
	if dist > CHASE_RADIUS:
		return Vector2.ZERO
	return to_player.normalized() * speed

func _is_in_desert(world_pos: Vector2) -> bool:
	if _world == null or not _world.has_method("_cell_biome_type"):
		return false
	var tilemap: TileMapLayer = _world.get_node_or_null("Ground") as TileMapLayer
	if tilemap == null:
		return false
	var tile: Vector2i = tilemap.local_to_map(tilemap.to_local(world_pos))
	# _cell_biome_type returns 1 for desert
	return _world.call("_cell_biome_type", tile) == 1

# ── Out-of-desert roaming ──────────────────────────────────────────
func _begin_wander() -> void:
	_wandering          = true
	_wander_dir         = Vector2.RIGHT.rotated(randf_range(0.0, TAU))
	_wander_retarget    = randf_range(WANDER_RETARGET_MIN, WANDER_RETARGET_MAX)
	_wander_burrow_wait = randf_range(WANDER_BURROW_MIN, WANDER_BURROW_MAX)

# Roam instead of chasing. An above-ground worm counts down and then flips
# _burrowing off — that toggle is exactly what worm.gd's ATTACKING branch
# reads as "go underground", so it burrows with the normal sand cloud. An
# underground worm just keeps roaming; it never surfaces on its own here.
# The physical state (is_above_ground) is the source of truth, so an emerge
# that came from worm.gd's own surface timer can't dodge the countdown.
func _wander_step(mob: CharacterBody2D, speed: float, delta: float) -> Vector2:
	if not _wandering:
		_begin_wander()
	_wander_retarget -= delta
	if _wander_retarget <= 0.0:
		_wander_dir      = Vector2.RIGHT.rotated(randf_range(0.0, TAU))
		_wander_retarget = randf_range(WANDER_RETARGET_MIN, WANDER_RETARGET_MAX)

	var above_ground: bool = mob.has_method("is_above_ground") and mob.call("is_above_ground")
	if above_ground:
		_burrowing = true   # keep the AI toggle in step with reality
		_wander_burrow_wait -= delta
		if _wander_burrow_wait <= 0.0:
			_wandering = false
			_burrowing = false   # → worm.gd ATTACKING runs _begin_burrow()
			_cycle_timer = randf_range(CYCLE_MIN, CYCLE_MAX)
			return Vector2.ZERO
	else:
		_burrowing = false
		# Fresh countdown every frame underground, so the worm always gets a
		# full wander window the next time it happens to break the surface.
		_wander_burrow_wait = randf_range(WANDER_BURROW_MIN, WANDER_BURROW_MAX)

	return _wander_dir * speed * WANDER_SPEED_MULT

func is_walking() -> bool:
	return true

func walk_dir() -> Vector2:
	if _target != null and is_instance_valid(_target):
		return (_target.global_position - Vector2.ZERO).normalized()
	return Vector2.RIGHT

func is_burrowing() -> bool:
	return _burrowing

# The node this worm chases: the provoked combat LUA when a LUA has hit it, else
# the player.
func _combat_target(mob: CharacterBody2D) -> Node2D:
	if mob.has_method("combat_target"):
		return mob.call("combat_target") as Node2D
	return Global.player_node as Node2D
