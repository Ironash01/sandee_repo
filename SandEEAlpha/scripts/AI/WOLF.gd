extends RefCounted
class_name WolfAI

# ── Wandering AI (MobCombatData.ai_type == "WOLF") ───────────────────
# Idle/walk state machine with simple water avoidance. Migrated out of
# wolf.gd so any mob whose resource selects AI Type "WOLF" can reuse this
# exact behavior instead of it being hardwired into the Wolf scene script.

enum State { IDLE, WALK }

var _state:    State   = State.IDLE
var _timer:    float   = 0.0
var _walk_dir: Vector2 = Vector2.ZERO

func _init() -> void:
	_timer = randf_range(0.5, 2.0)

# Returns this frame's desired velocity. The caller owns actually moving the
# body (mob.velocity = ...; mob.move_and_slide()) and driving animation off
# is_walking()/walk_dir() — this object only decides direction/timing.
func physics_update(mob: CharacterBody2D, speed: float, water_layer: TileMapLayer, delta: float) -> Vector2:
	# Player dead (pre-respawn): hold still. Dispersal only lasts 2s, so
	# without this every mob resumes chasing the frozen death position.
	if Global.player_is_dead:
		return Vector2.ZERO
	_timer -= delta
	if _timer <= 0.0:
		_pick_new_action()

	if _state != State.WALK:
		return Vector2.ZERO

	var next_pos: Vector2 = mob.global_position + _walk_dir * speed * delta
	if _is_on_water(water_layer, next_pos):
		_state    = State.IDLE
		_walk_dir = Vector2.ZERO
		_timer    = 0.0
		return Vector2.ZERO

	return _walk_dir * speed

func is_walking() -> bool:
	return _state == State.WALK

func walk_dir() -> Vector2:
	return _walk_dir

func _is_on_water(water_layer: TileMapLayer, world_pos: Vector2) -> bool:
	if water_layer == null:
		return false
	var tile: Vector2i = water_layer.local_to_map(water_layer.to_local(world_pos))
	return water_layer.get_cell_source_id(tile) != -1

func _pick_new_action() -> void:
	if _state == State.IDLE:
		_state    = State.WALK
		_walk_dir = Vector2.from_angle(randf() * TAU)
		_timer    = randf_range(1.5, 4.0)
	else:
		_state    = State.IDLE
		_walk_dir = Vector2.ZERO
		_timer    = randf_range(1.0, 3.0)
