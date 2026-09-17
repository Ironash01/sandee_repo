extends RefCounted
class_name WormAI

# ── Desert worm AI ──────────────────────────────────────────────────
# The worm waits underground, then surfaces after a 5-7 second timer.
# Once above ground it commits to the chase and does NOT burrow while
# the player stays within CHASE_RADIUS — it only returns underground
# once they escape.
# While underground it drifts toward the player so it surfaces nearby,
# but stops entirely if the player is beyond CHASE_RADIUS.

var _target: Node2D = null
var _burrowing: bool = false  # false = underground, true = above ground
var _world: Node = null

# ── Cycle timer ────────────────────────────────────────────────────
var _cycle_timer: float = 0.0
const CYCLE_MIN: float = 5.0
const CYCLE_MAX: float = 7.0
const CHASE_RADIUS: float = 640.0  # 20 blocks * 32 px/block

func _init() -> void:
	_cycle_timer = randf_range(CYCLE_MIN, CYCLE_MAX)
	_burrowing = false  # start underground

func physics_update(mob: CharacterBody2D, speed: float, water_layer: TileMapLayer, delta: float) -> Vector2:
	_target = Global.player_node as Node2D if Global.player_node != null else null
	_world = Global.world_node

	if _target == null or not is_instance_valid(_target) or _world == null:
		return Vector2.ZERO

	# ── Only active inside desert biome ─────────────────────────────
	if not _is_in_desert(_target.global_position):
		return Vector2.ZERO

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

func is_walking() -> bool:
	return true

func walk_dir() -> Vector2:
	if _target != null and is_instance_valid(_target):
		return (_target.global_position - Vector2.ZERO).normalized()
	return Vector2.RIGHT

func is_burrowing() -> bool:
	return _burrowing
