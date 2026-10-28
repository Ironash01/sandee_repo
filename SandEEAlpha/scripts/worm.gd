extends CharacterBody2D

# ── Desert worm mob (Terraria-style segmented enemy) ────────────────
# Head is the active mover. Body/tail follow the head's travel path.
# Each body segment samples a position from the head's path history
# at a fixed distance behind the previous segment.

const COMBAT_DATA: MobCombatData = preload("res://resources/mobs/worm.tres")
const CACTUS_ITEM: ItemData = preload("res://resources/items/cactus.tres")
const DROP_ITEM_SCENE: PackedScene = preload("res://scenes/ui/InventoryItem.tscn")
const CACTUS_DROP_MIN: int = 5
const CACTUS_DROP_MAX: int = 10

const AI_SCRIPTS: Dictionary = {
	"WORM": preload("res://scripts/AI/WORM.gd"),
}

# ── Segment chain ──────────────────────────────────────────────────
const SEGMENT_COUNT:  int   = 6
const SEGMENT_SPACING: float = 14.0
const SEGMENT_SCALE:  float = 0.8

# ── Head path history ──────────────────────────────────────────────
var _path_positions: Array = []
var _path_distances: Array = []
var _path_distance: float = 0.0
var _last_head_pos: Vector2 = Vector2.ZERO

# ── Body segments ──────────────────────────────────────────────────
var _segment_nodes: Array = []
var _segment_positions: Array = []

# ── Combat ─────────────────────────────────────────────────────────
var _mob_health: float  = 0.0
var _death_processed: bool = false
var _knockback:  Vector2 = Vector2.ZERO
const KNOCKBACK_DECAY: float = 900.0

# ── Despawn zone ──────────────────────────────────────────────────
enum DespawnZone { INNER, SAFE, OUTER }
const ZONE_DESPAWN_TIME := {
	DespawnZone.INNER: 1800.0,
	DespawnZone.SAFE:  900.0,
	DespawnZone.OUTER: 300.0,
}
var _despawn_zone: int = -1
var _despawn_remaining: float = 0.0

var _ai: RefCounted = null

# ── Player-death dispersal ────────────────────────────────────────
var _is_dispersing:     bool    = false
var _disperse_timer:    float   = 0.0
var _disperse_direction: Vector2 = Vector2.ZERO
const DISPERSE_DURATION: float = 2.0
const DISPERSE_SPEED:    float = 80.0
const DISPERSE_RANDOMNESS: float = 0.4
# Spawn clearing: when the player (re)spawns, mobs within this radius of the
# spawn point flee for SPAWN_CLEAR_DURATION so the player can react.
const SPAWN_CLEAR_RADIUS:   float = 20.0 * 32.0
const SPAWN_CLEAR_DURATION: float = 5.0

@onready var _head_sprite: Sprite2D = $HeadSprite

const SHADOW_TEXTURE: Texture2D = preload("res://sprites/shadow/shadow_base.png")
const DAMAGE_NUMBER_SCRIPT: GDScript = preload("res://scripts/damage_number.gd")
const MELLOW_BURST_SCRIPT: GDScript = preload("res://scripts/mellow_burst.gd")
const MOB_NAME_LABEL_SCRIPT: GDScript = preload("res://scripts/mob_name_label.gd")

# ── Attack ─────────────────────────────────────────────────────────
const ATTACK_RANGE:    float = 30.0
const ATTACK_COOLDOWN: float = 1.2
var _attack_cooldown:  float  = 0.0

# ── Indicator ──────────────────────────────────────────────────────
var _indicator: Sprite2D = null

# ── Shadow ─────────────────────────────────────────────────────────
var _shadow_sprite: Node2D = null

# ── Mob name label ─────────────────────────────────────────────────
var _name_label: Node2D = null

# ── Underground movement ───────────────────────────────────────────
var _collision_shapes: Array = []          # every CollisionShape2D (body + teeth)
var _teeth_shape: CollisionShape2D = null  # front-of-head hitbox (teeth/mouth)
var _surface_timer: float = 0.0
const SURFACE_TIMER: float = 1.0
const TILE_SIZE: float = 32.0
const WORM_RADIUS: float = 8.0  # approximate body half-width for clearance checks

# Teeth hitbox — the head sprite is 63px wide with the mouth/jaws at the
# front (image x39-60).  Sprite is centred on the worm origin, so the teeth
# sit ~+20px along the head's facing direction.  Rotated with the head each
# frame so the hitbox always covers the mouth.
const TEETH_OFFSET: float = 20.0
const TEETH_RADIUS: float = 9.0

# ── Above-ground obstacle avoidance (pivot around blocks) ──────────
const AVOID_RAY_LEN: float = 96.0   # how far a clearance probe reaches
const AVOID_MIN_CLEAR: float = 26.0 # below this the forward path counts as blocked
const AVOID_COMMIT: float = 0.45    # seconds to commit to a chosen evade direction
const AVOID_ANGLES: Array = [15.0, -15.0, 30.0, -30.0, 45.0, -45.0, 60.0, -60.0,
	75.0, -75.0, 90.0, -90.0, 110.0, -110.0, 135.0, -135.0, 160.0, -160.0]
var _evade_dir: Vector2 = Vector2.ZERO
var _evade_timer: float = 0.0

# ── Underground pathfinding ────────────────────────────────────────
var _avoidance_dir: Vector2 = Vector2.ZERO
var _prev_chosen_dir: Vector2 = Vector2.ZERO
var _dir_change_count: int = 0
var _dir_change_timer: float = 0.0
const DIRECTION_CHANGE_LIMIT: int = 4
const DIRECTION_CHANGE_WINDOW: float = 1.0

# ── Attack grace period ────────────────────────────────────────────
# Prevents collision-based burrow on the first frames after surfacing.
# The worm's collision circle may overlap a block at the surface point.
var _attack_grace_frames: int = 0
const GRACE_FRAMES: int = 10

# ── Stuck detection ────────────────────────────────────────────────
var _stuck_timer: float = 0.0
var _last_move_pos: Vector2 = Vector2.ZERO
const STUCK_TIMEOUT: float = 300.0
const STUCK_THRESHOLD: float = 10.0

# ── Sprite textures ───────────────────────────────────────────────
const HEAD_TEXTURE: Texture2D = preload("res://sprites/mobs/desert_worm/head.png")
const BODY_TEXTURE: Texture2D = preload("res://sprites/mobs/desert_worm/body.png")
const TAIL_TEXTURE: Texture2D = preload("res://sprites/mobs/desert_worm/tail.png")

# ── Sand effects ──────────────────────────────────────────────────
const SAND_PARTICLES_SCENE: PackedScene = preload("res://scenes/effects/DesertSandParticles.tscn")
const SAND_FULL_SCENE: PackedScene = preload("res://scenes/effects/SandFullEffect.tscn")
var _sand_particles: Node = null

# ── State ─────────────────────────────────────────────────────────
# IDLE = above ground, AI controls movement (chase/dash)
# EMERGING = brief pause + sand_full, about to surface
# ATTACKING = above ground, dash active, sand particles off
# BURROWING = brief pause + sand_full, about to hide underground
enum State { IDLE, EMERGING, ATTACKING, BURROWING }
var _state: int = State.IDLE
var _state_timer: float = 0.0
const EMERGE_DELAY: float = 0.2    # brief pause before sand cloud
const BURROW_DELAY: float = 0.15   # brief pause before sand cloud
var _was_burrowing: bool = false

func _ready() -> void:
	add_to_group("Mob")
	add_to_group("Worm")
	_mob_health = COMBAT_DATA.health
	z_index = int(global_position.y / 32)

	_head_sprite.texture = HEAD_TEXTURE
	_head_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST

	_shadow_sprite = Global.make_shadow_sprite(SHADOW_TEXTURE, Vector2(0.0, 4.0), Vector2(0.5, 0.25), 0.3)
	add_child(_shadow_sprite)
	_add_name_label()

	var ai_script: Script = AI_SCRIPTS.get(COMBAT_DATA.ai_type)
	if ai_script != null:
		_ai = ai_script.new()

	# Create body segment sprites
	for i in range(SEGMENT_COUNT):
		var seg := Sprite2D.new()
		seg.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		if i == SEGMENT_COUNT - 1:
			seg.texture = TAIL_TEXTURE
		else:
			seg.texture = BODY_TEXTURE
		seg.scale = Vector2(SEGMENT_SCALE, SEGMENT_SCALE)
		seg.z_index = z_index - 1
		seg.visible = false
		add_child(seg)
		_segment_nodes.append(seg)
		_segment_positions.append(global_position)

	# Seed path history
	for i in range(SEGMENT_COUNT * 2 + 4):
		var pos := global_position + Vector2(-SEGMENT_SPACING * (i + 1), 0.0)
		var dist := SEGMENT_SPACING * (i + 1)
		_path_positions.append(pos)
		_path_distances.append(dist)
	_path_distance = _path_positions.size() * SEGMENT_SPACING
	_last_head_pos = global_position

	_head_sprite.visible = false

	_indicator = Sprite2D.new()
	_indicator.texture = SHADOW_TEXTURE
	_indicator.scale = Vector2(0.4, 0.4)
	_indicator.position = Vector2(0, -28)
	_indicator.z_index = z_index + 1
	_indicator.visible = false
	_indicator.modulate = Color(1.0, 0.8, 0.2, 0.8)
	add_child(_indicator)
	Global.player_died.connect(_on_player_died)
	Global.player_spawned.connect(_on_player_spawned)

	# Sand particle effect
	_sand_particles = SAND_PARTICLES_SCENE.instantiate()
	_sand_particles.worm = self
	add_child(_sand_particles)

	# Collect the body collision shape(s) so they can be disabled underground.
	# The scene ships one circle shape; the teeth shape is added below.
	for child in get_children():
		if child is CollisionShape2D:
			_collision_shapes.append(child)

	# Teeth/mouth hitbox at the front of the head — rotated with the head
	# each frame (see _update_segments) so the mouth stays hittable.
	_teeth_shape = CollisionShape2D.new()
	var teeth_circle := CircleShape2D.new()
	teeth_circle.radius = TEETH_RADIUS
	_teeth_shape.shape = teeth_circle
	_teeth_shape.position = Vector2(TEETH_OFFSET, 0.0)
	add_child(_teeth_shape)
	_collision_shapes.append(_teeth_shape)

func _physics_process(delta: float) -> void:
	if _indicator != null:
		_indicator.visible = _state == State.IDLE
		_indicator.z_index = z_index + 1

	# Shadow exists ONLY while the worm is above ground (ATTACKING). While
	# burrowed/emerging/burrowing the worm is underground, so no shadow.
	if _shadow_sprite != null:
		_shadow_sprite.visible = _state == State.ATTACKING

	# ── State machine ──────────────────────────────────────────────
	if _state != State.IDLE:
		_process_state(delta)
		return

	# IDLE: underground, worm hidden until timer triggers emergence
	_head_sprite.visible = false
	for seg in _segment_nodes:
		seg.visible = false

	# Player-death dispersal overrides AI movement
	if _is_dispersing:
		_disperse_timer -= delta
		if _disperse_timer <= 0.0:
			_is_dispersing = false
		else:
			velocity = _disperse_direction * DISPERSE_SPEED
			velocity += _knockback
			_knockback = _knockback.move_toward(Vector2.ZERO, KNOCKBACK_DECAY * delta)
			if _water_blocks_movement(velocity, delta):
				velocity = Vector2.ZERO
			# Underground: move without collision
			global_position += velocity * delta
			_record_path()
			z_index = int(global_position.y / 32)
			_update_segments()
			return

	# AI controls movement
	var desired_vel: Vector2 = Vector2.ZERO
	if _ai != null:
		desired_vel = _ai.call("physics_update", self, COMBAT_DATA.speed, _get_water_layer(), delta)

	velocity = desired_vel + _knockback
	_knockback = _knockback.move_toward(Vector2.ZERO, KNOCKBACK_DECAY * delta)

	# Detect burrowing state changes BEFORE moving — transition must
	# prevent this frame's movement entirely.
	var burrowing: bool = _ai != null and _ai.call("is_burrowing")
	# State guard: only process transitions while in IDLE.
	if _state == State.IDLE:
		if burrowing and not _was_burrowing:
			print("[Worm] IDLE → EMERGE (AI toggle) | pos=", global_position)
			_begin_emerge()
			velocity = Vector2.ZERO
			_update_segments()
			return
		elif not burrowing and _was_burrowing:
			print("[Worm] IDLE → BURROW (AI toggle) | pos=", global_position)
			_begin_burrow()
			velocity = Vector2.ZERO
			_update_segments()
			return

	# ── Underground movement ────────────────────────────────────────
	# The worm moves through terrain with its collision shape disabled.
	# Smart local pathfinding: detect tight spaces early, steer toward
	# open areas, then gradually return to player-directed movement.
	var underground_vel := velocity  # velocity from AI (toward player)

	# --- Determine the direction to move ---
	var move_dir := underground_vel.normalized()

	if underground_vel.length_squared() > 1.0:
		# Check if the current direction has clearance ahead
		if _has_clearance(move_dir):
			# Path is clear — steer toward player, no avoidance needed
			_avoidance_dir = Vector2.ZERO
			move_dir = _steer_toward_player(underground_vel.normalized())
		else:
			# Path is blocked or too tight — search for open direction
			if _avoidance_dir.is_zero_approx() or not _has_clearance(_avoidance_dir):
				# No active avoidance or current avoidance also blocked
				_avoidance_dir = _find_open_direction(underground_vel.normalized())
				# Oscillation guard: if direction changed, track it
				if not _avoidance_dir.is_zero_approx() and _avoidance_dir != _prev_chosen_dir:
					_dir_change_count += 1
					_prev_chosen_dir = _avoidance_dir
			move_dir = _avoidance_dir

		# If all searches failed (dead end), find nearest open area
		if move_dir.is_zero_approx():
			move_dir = _find_nearest_open_area()

	velocity = move_dir * underground_vel.length() if not move_dir.is_zero_approx() else Vector2.ZERO
	if _water_blocks_movement(velocity, delta):
		velocity = Vector2.ZERO

	# --- Oscillation timer ---
	_dir_change_timer -= delta
	if _dir_change_timer <= 0.0:
		_dir_change_count = 0
		_dir_change_timer = DIRECTION_CHANGE_WINDOW

	# --- Move ---
	global_position += velocity * delta
	_record_path()
	z_index = int(global_position.y / 32)

	# --- Underground stuck detection ---
	# If the worm can't move (all directions blocked), force recovery
	# instead of staying stuck forever.
	if velocity.length_squared() < 1.0 and desired_vel.length_squared() > 1.0:
		# AI wants to move but worm is stuck
		_stuck_timer += delta
		if _stuck_timer > 2.0:
			# Force: find any open area and move there
			var escape_dir := _find_nearest_open_area()
			if not escape_dir.is_zero_approx():
				velocity = escape_dir * COMBAT_DATA.speed
				_stuck_timer = 0.0
			else:
				# Truly trapped — stay put, let surface timer or AI handle it
				_stuck_timer = 0.0
	else:
		_stuck_timer = 0.0

	# --- Surface timer ---
	if velocity.length_squared() > 1.0:
		_surface_timer -= delta
		if _surface_timer <= 0.0:
			# Check clearance for the collision circle, not just center tile.
			# The circle extends ~16px above center.
			var clear := true
			for check_y in [-TILE_SIZE, -TILE_SIZE * 0.5]:
				for check_x in [-TILE_SIZE * 0.5, 0.0, TILE_SIZE * 0.5]:
					if _is_tile_solid(global_position + Vector2(check_x, check_y)):
						clear = false
						break
				if not clear:
					break
			if clear:
				print("[Worm] surface timer → EMERGE | pos=", global_position)
				_begin_emerge()
				velocity = Vector2.ZERO
				_update_segments()
				return

	# Sand trail while the worm moves underground — the disturbance
	# follows the whole body so the player can track it.
	if velocity.length_squared() > 1.0:
		_sand_particles.set_burrowing()
	else:
		_sand_particles.set_buried()

	_update_segments()

func _process_state(delta: float) -> void:
	z_index = int(global_position.y / 32)
	_update_segments()

	match _state:
		State.EMERGING:
			# Brief pause — worm frozen, hidden
			velocity = Vector2.ZERO
			_set_worm_visible(false)
			if _shadow_sprite != null:
				_shadow_sprite.visible = false
			_state_timer -= delta
			if _state_timer <= 0.0:
				print("[Worm] EMERGING → ATTACKING | pos=", global_position)
				_spawn_sand_full()
				_state = State.ATTACKING
				_attack_grace_frames = GRACE_FRAMES
				_evade_timer = 0.0
				_evade_dir = Vector2.ZERO
				_set_worm_visible(true)
				if _shadow_sprite != null:
					_shadow_sprite.visible = true
				_sand_particles.set_buried()
				# Re-enable collision shapes (body + teeth) above ground
				for shape in _collision_shapes:
					if shape != null:
						shape.set_deferred("disabled", false)
				# Worm is now above ground.  Set _was_burrowing = true
				# so the next IDLE edge (not burrowing && was) can fire
				# when the cycle timer says "go underground".
				_was_burrowing = true

		State.ATTACKING:
			# AI controls dash movement
			_set_worm_visible(true)
			if _shadow_sprite != null:
				_shadow_sprite.visible = true
			var desired_vel: Vector2 = Vector2.ZERO
			if _ai != null:
				desired_vel = _ai.call("physics_update", self, COMBAT_DATA.speed, _get_water_layer(), delta)
			velocity = desired_vel + _knockback
			_knockback = _knockback.move_toward(Vector2.ZERO, KNOCKBACK_DECAY * delta)

			# ── Obstacle avoidance: pivot around blocks ─────────────
			# Probe clearance ahead.  If blocked, pick the most open
			# direction near the desired one and COMMIT to it for a
			# short time so the worm doesn't dither on a corner.
			if velocity.length_squared() > 1.0:
				var forward := velocity.normalized()
				var speed := velocity.length()

				if _evade_timer > 0.0:
					_evade_timer -= delta
					# Keep the committed direction while it still leads
					# somewhere; drop it once it closes up.
					if _ray_clearance(_evade_dir) > AVOID_MIN_CLEAR:
						velocity = _evade_dir * speed
					else:
						_evade_timer = 0.0

				if _evade_timer <= 0.0:
					if _ray_clearance(forward) < AVOID_MIN_CLEAR:
						var evade := _choose_avoid_dir(forward)
						if evade != Vector2.ZERO:
							_evade_dir = evade
							_evade_timer = AVOID_COMMIT
							velocity = evade * speed
						else:
							# Fully boxed in — burrow through terrain.
							print("[Worm] ATTACKING → BURROW (boxed in) | pos=", global_position)
							_begin_burrow()
							return
					else:
						# Path reopened — drop the committed evade.
						_evade_dir = Vector2.ZERO

			if _water_blocks_movement(velocity, delta):
				velocity = Vector2.ZERO
			move_and_slide()
			_record_path()
			# ── Contact damage ──────────────────────────────────────
			# Above ground only, and it has to live HERE: _physics_process
			# returns early for every non-IDLE state, so the old IDLE-only
			# call could never fire while the worm was actually emerged.
			_try_attack_player(delta)
			# Subtle sand kicked up while dashing above ground
			if velocity.length_squared() > 1.0:
				_sand_particles.set_normal()
			else:
				_sand_particles.set_buried()
			# Decrement grace period
			if _attack_grace_frames > 0:
				_attack_grace_frames -= 1
			# Physically blocked after moving — pivot to an open side
			# first; only burrow if there is genuinely nowhere to go.
			if _attack_grace_frames <= 0 and velocity.length_squared() > 1.0 and get_slide_collision_count() > 0:
				var evade := _choose_avoid_dir(velocity.normalized())
				if evade != Vector2.ZERO and evade != _evade_dir:
					_evade_dir = evade
					_evade_timer = AVOID_COMMIT
				else:
					print("[Worm] ATTACKING → BURROW (collision fallback) | pos=", global_position)
					_begin_burrow()
					return
			var burrowing: bool = _ai != null and _ai.call("is_burrowing")
			if not burrowing:
				print("[Worm] ATTACKING → BURROW (AI toggle) | pos=", global_position)
				_begin_burrow()

			# ── Stuck detection ──────────────────────────────────────
			if global_position.distance_to(_last_move_pos) > STUCK_THRESHOLD:
				_last_move_pos = global_position
				_stuck_timer = 0.0
			else:
				_stuck_timer += delta
				if _stuck_timer >= STUCK_TIMEOUT:
					# Watchdog cleanup is not a player defeat: no cactus loot.
					_die(false)
					return

		State.BURROWING:
			# Brief pause — worm frozen, visible (obscured by cloud soon).
			# Shadow is removed as the worm sinks back underground.
			velocity = Vector2.ZERO
			_set_worm_visible(true)
			if _shadow_sprite != null:
				_shadow_sprite.visible = false
			_state_timer -= delta
			if _state_timer <= 0.0:
				print("[Worm] BURROWING → IDLE | pos=", global_position)
				_spawn_sand_full()
				_set_worm_visible(false)
				if _shadow_sprite != null:
					_shadow_sprite.visible = false
				_state = State.IDLE
				_sand_particles.set_burrowing()
				# Worm is now underground.  Set _was_burrowing = false
				# so the next IDLE edge (burrowing && !was) can fire
				# when the cycle timer says "go above ground".
				_was_burrowing = false
				# Disable collision shapes so the worm passes through terrain
				for shape in _collision_shapes:
					if shape != null:
						shape.set_deferred("disabled", true)
				# Reset surface timer
				_surface_timer = SURFACE_TIMER
				_stuck_timer = 0.0
				_last_move_pos = global_position
				_avoidance_dir = Vector2.ZERO
				_prev_chosen_dir = Vector2.ZERO
				_dir_change_count = 0

func _begin_emerge() -> void:
	# Guard: only allow from IDLE. Prevents restart during EMERGING/ATTACKING/BURROWING.
	if _state != State.IDLE:
		return
	print("[Worm] _begin_emerge | state=", State.keys()[_state], " pos=", global_position)
	_state = State.EMERGING
	_state_timer = EMERGE_DELAY
	velocity = Vector2.ZERO
	_stuck_timer = 0.0
	_sand_particles.set_buried()

func _begin_burrow() -> void:
	# Guard: only allow from IDLE or ATTACKING. Prevents restart during BURROWING.
	if _state != State.IDLE and _state != State.ATTACKING:
		return
	print("[Worm] _begin_burrow | state=", State.keys()[_state], " pos=", global_position)
	_state = State.BURROWING
	_state_timer = BURROW_DELAY
	velocity = Vector2.ZERO
	_stuck_timer = 0.0
	_sand_particles.set_buried()
	# Shadow disappears the instant the worm starts sinking underground.
	if _shadow_sprite != null:
		_shadow_sprite.visible = false

func _set_worm_visible(vis: bool) -> void:
	_head_sprite.visible = vis
	for seg in _segment_nodes:
		seg.visible = vis

# Physical truth for the AI: ATTACKING is the only state where the worm is
# actually out of the ground. The AI polls this so its own _burrowing toggle
# can't drift out of sync when emergence came from the surface timer rather
# than from the AI (which used to cause an emerge → instant re-burrow).
func is_above_ground() -> bool:
	return _state == State.ATTACKING

func _spawn_sand_full() -> void:
	var cloud: Node2D = SAND_FULL_SCENE.instantiate() as Node2D
	if cloud == null:
		return
	# Cover the ENTIRE worm body with the cloud
	var min_pos := global_position
	var max_pos := global_position
	for seg in _segment_nodes:
		if seg != null:
			min_pos = Vector2(min(min_pos.x, seg.global_position.x),
							  min(min_pos.y, seg.global_position.y))
			max_pos = Vector2(max(max_pos.x, seg.global_position.x),
							  max(max_pos.y, seg.global_position.y))
	var center := (min_pos + max_pos) * 0.5
	var body_radius := center.distance_to(max_pos) + 8.0
	cloud.global_position = center
	cloud.z_index = z_index + 2
	var base_scale := clampf(body_radius / 16.0, 1.0, 3.0)
	cloud.scale = Vector2(base_scale, base_scale)
	get_parent().add_child(cloud)
	cloud.burst()

func _on_player_died(death_position: Vector2) -> void:
	if _mob_health <= 0.0:
		return
	var away: Vector2 = global_position - death_position
	if away.length_squared() < 1.0:
		away = Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0))
	away = away.normalized()
	away = away.rotated(randf_range(-DISPERSE_RANDOMNESS, DISPERSE_RANDOMNESS))
	_disperse_direction = away
	_disperse_timer = DISPERSE_DURATION
	_is_dispersing = true

# The player just (re)spawned — if we're near the spawn point, clear out so the
# player isn't instantly swarmed. Same dispersal as the death version, just
# longer and scoped to mobs near the spawn.
func _on_player_spawned(spawn_position: Vector2) -> void:
	if _mob_health <= 0.0:
		return
	if global_position.distance_to(spawn_position) > SPAWN_CLEAR_RADIUS:
		return
	var away: Vector2 = global_position - spawn_position
	if away.length_squared() < 1.0:
		away = Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0))
	away = away.normalized().rotated(randf_range(-DISPERSE_RANDOMNESS, DISPERSE_RANDOMNESS))
	_disperse_direction = away
	_disperse_timer = SPAWN_CLEAR_DURATION
	_is_dispersing = true

func _record_path() -> void:
	var step := global_position.distance_to(_last_head_pos)
	if step > 0.01:
		_path_distance += step
		_path_positions.append(global_position)
		_path_distances.append(_path_distance)
		_last_head_pos = global_position
		var trim: int = 0
		for j in range(_path_positions.size()):
			if _path_distance - _path_distances[j] < SEGMENT_SPACING * (SEGMENT_COUNT + 2):
				break
			trim = j + 1
		if trim > 0:
			_path_positions = _path_positions.slice(trim)
			_path_distances = _path_distances.slice(trim)

func _update_segments() -> void:
	for i in range(_segment_nodes.size()):
		# Untyped + validity: a freed segment in a typed Sprite2D var throws.
		var seg_ref: Variant = _segment_nodes[i]
		if not is_instance_valid(seg_ref):
			continue
		var seg := seg_ref as Sprite2D
		var target_distance: float = _path_distance - SEGMENT_SPACING * (i + 1)
		var result := _sample_path(target_distance)
		seg.global_position = result.pos
		seg.rotation = result.dir
		seg.z_index = int(seg.global_position.y / 32) - 1
		_segment_positions[i] = seg.global_position
	if velocity.length_squared() > 1.0:
		_head_sprite.rotation = velocity.angle()
	# Teeth hitbox rides the front of the head in its facing direction.
	if _teeth_shape != null:
		_teeth_shape.position = Vector2.RIGHT.rotated(_head_sprite.rotation) * TEETH_OFFSET

func _sample_path(target_dist: float) -> Dictionary:
	if _path_positions.size() < 2:
		return {"pos": _path_positions[0] if _path_positions.size() > 0 else global_position, "dir": 0.0}
	target_dist = maxf(target_dist, _path_distance - SEGMENT_SPACING * (SEGMENT_COUNT + 1))
	target_dist = minf(target_dist, _path_distance)
	for idx in range(1, _path_positions.size()):
		if _path_distances[idx] >= target_dist:
			var prev_pos: Vector2 = _path_positions[idx - 1]
			var next_pos: Vector2 = _path_positions[idx]
			var prev_dist: float = _path_distances[idx - 1]
			var next_dist: float = _path_distances[idx]
			var ratio: float = 0.0
			if next_dist > prev_dist:
				ratio = clampf((target_dist - prev_dist) / (next_dist - prev_dist), 0.0, 1.0)
			var pos: Vector2 = prev_pos.lerp(next_pos, ratio)
			var dir: float = (next_pos - prev_pos).angle()
			return {"pos": pos, "dir": dir}
	var last := _path_positions.size() - 1
	return {"pos": _path_positions[last], "dir": _head_sprite.rotation}

# ── Provoked aggro (combat LUA) ───────────────────────────────────
# A hostile mob that a combat LUA damages targets the LUA instead of the player,
# until the LUA dies or gets this far away.
const PROVOKE_LEASH_PX: float = 420.0
var _provoked_by: Node2D = null

func provoke(node: Node2D) -> void:
	_provoked_by = node

func combat_target() -> Node2D:
	if _provoked_by != null and is_instance_valid(_provoked_by) and _provoked_by.is_inside_tree():
		if (_provoked_by as Node2D).global_position.distance_to(global_position) <= PROVOKE_LEASH_PX:
			return _provoked_by
	_provoked_by = null
	return Global.player_node as Node2D

func _try_attack_player(delta: float) -> void:
	if COMBAT_DATA.damage <= 1.0:
		return
	_attack_cooldown = maxf(0.0, _attack_cooldown - delta)
	var p := Global.player_node as Node2D
	if p == null or _attack_cooldown > 0.0:
		return
	# Provoked by a combat LUA → the LUA is the target, not the player.
	if combat_target() != p:
		return
	if global_position.distance_to(p.global_position) > ATTACK_RANGE:
		return
	_attack_cooldown = ATTACK_COOLDOWN
	Global.damage_player(COMBAT_DATA.damage, global_position, Vector2.ZERO)
	_show_name_label()

func _get_water_layer() -> TileMapLayer:
	var parent := get_parent()
	if parent != null:
		return parent.get_node_or_null("Water") as TileMapLayer
	return null

# Final velocity veto for knockback / evasion / dispersal: the AI guard stops
# deliberate target-chasing, but every movement source must also stay dry.
func _water_blocks_movement(vel: Vector2, delta: float) -> bool:
	if vel.length_squared() < 0.0001:
		return false
	var water := _get_water_layer()
	if water == null:
		return false
	var probe: Vector2 = global_position \
		+ vel.normalized() * maxf(8.0, vel.length() * delta * 2.0)
	var wtile: Vector2i = water.local_to_map(water.to_local(probe))
	return water.get_cell_source_id(wtile) != -1

func _is_tile_solid(world_pos: Vector2) -> bool:
	var world: Node = Global.world_node
	if world == null:
		return false
	var tilemap: TileMapLayer = world.get_node_or_null("Ground") as TileMapLayer
	if tilemap == null:
		return false
	var tile: Vector2i = tilemap.local_to_map(tilemap.to_local(world_pos))
	if tilemap.get_cell_tile_data(tile) != null:
		return true
	# Desert Worms treat water as impassable for path planning too. Without
	# this, an underground chase could route straight across a shoreline.
	var water := _get_water_layer()
	if water != null:
		var wtile: Vector2i = water.local_to_map(water.to_local(world_pos))
		if water.get_cell_source_id(wtile) != -1:
			return true
	return false

func _has_clearance(dir: Vector2, dist: float = 24.0) -> bool:
	# Check if the path ahead has enough room for the worm's body.
	# Tests the head position + two side offsets (body width).
	var d := dir * dist
	if _is_tile_solid(global_position + d):
		return false
	if _is_tile_solid(global_position + d + dir.rotated(PI * 0.5) * WORM_RADIUS):
		return false
	if _is_tile_solid(global_position + d + dir.rotated(-PI * 0.5) * WORM_RADIUS):
		return false
	return true

# Distance to the first solid tile along `dir`, up to AVOID_RAY_LEN.
# Longer = more open route.  Terrain only (layer 1), so the player is
# never treated as an obstacle.
func _ray_clearance(dir: Vector2) -> float:
	if dir.length_squared() < 0.0001:
		return 0.0
	var space := get_world_2d().direct_space_state
	if space == null:
		return AVOID_RAY_LEN
	var from := global_position
	var to := from + dir.normalized() * AVOID_RAY_LEN
	var query := PhysicsRayQueryParameters2D.create(from, to)
	query.collision_mask = 1
	query.exclude = [get_rid()]
	var result := space.intersect_ray(query)
	if result.is_empty():
		return AVOID_RAY_LEN
	return from.distance_to(result.get("position", to))

# Pick the best evasive direction: sample angles around `desired` and
# score by (clearance distance) minus (deviation penalty).  Returns
# Vector2.ZERO when every sampled direction is too tight.
func _choose_avoid_dir(desired: Vector2) -> Vector2:
	if desired.length_squared() < 0.0001:
		return Vector2.ZERO
	var forward := desired.normalized()
	var best_dir := Vector2.ZERO
	var best_score := -1.0
	for angle_deg in AVOID_ANGLES:
		var dir := forward.rotated(deg_to_rad(angle_deg))
		var clear := _ray_clearance(dir)
		if clear < AVOID_MIN_CLEAR:
			continue
		var deviation: float = absf(angle_deg) / 180.0
		var score: float = clear / AVOID_RAY_LEN - deviation * 0.35
		if score > best_score:
			best_score = score
			best_dir = dir
	return best_dir

func _check_openness(pos: Vector2) -> int:
	# Count clear cardinal neighbours to estimate how open an area is.
	var count := 0
	for offset in [Vector2(TILE_SIZE, 0), Vector2(-TILE_SIZE, 0),
				   Vector2(0, TILE_SIZE), Vector2(0, -TILE_SIZE)]:
		if not _is_tile_solid(pos + offset):
			count += 1
	return count

func _steer_toward_player(desired: Vector2) -> Vector2:
	# When the forward path is clear, bias slightly toward the player
	# to stay on course.  Small deviation keeps movement smooth.
	var p := Global.player_node as Node2D
	if p == null or not is_instance_valid(p):
		return desired
	var to_player := (p.global_position - global_position).normalized()
	return (desired * 0.8 + to_player * 0.2).normalized()

func _find_open_direction(desired: Vector2) -> Vector2:
	# Search nearby directions for one with clearance.
	# Score: open neighbours (40%) + player alignment (30%) + direction fidelity (30%).
	# Oscillation guard: if too many direction changes, expand search range.
	var max_angle := 90.0
	if _dir_change_count >= DIRECTION_CHANGE_LIMIT:
		max_angle = 150.0  # widen search to break oscillation

	var p := Global.player_node as Node2D
	var to_player := Vector2.ZERO
	if p != null and is_instance_valid(p):
		to_player = (p.global_position - global_position).normalized()

	var best_dir := Vector2.ZERO
	var best_score := -1.0

	for angle_deg in range(-int(max_angle), int(max_angle) + 1, 15):
		var angle := deg_to_rad(float(angle_deg))
		var dir := desired.rotated(angle)
		if not _has_clearance(dir):
			continue

		var test_pos := global_position + dir * TILE_SIZE
		var openness := _check_openness(test_pos)
		var player_dot := dir.dot(to_player) if to_player.length_squared() > 0.0 else 0.0
		var fidelity := dir.dot(desired)

		var score := openness * 0.4 + player_dot * 0.3 + fidelity * 0.3
		if score > best_score:
			best_score = score
			best_dir = dir

	return best_dir

func _find_nearest_open_area() -> Vector2:
	# Dead-end fallback: search outward for the most open nearby position
	# and steer toward it.
	var best_pos := global_position
	var best_openness := -1
	for ring in range(1, 6):
		var ring_dist := float(ring) * TILE_SIZE
		for angle_deg in range(0, 360, 30):
			var angle := deg_to_rad(float(angle_deg))
			var offset := Vector2(cos(angle), sin(angle)) * ring_dist
			var test_pos := global_position + offset
			if _is_tile_solid(test_pos):
				continue
			var openness := _check_openness(test_pos)
			if openness > best_openness:
				best_openness = openness
				best_pos = test_pos
	if best_pos != global_position:
		return (best_pos - global_position).normalized()
	return Vector2.ZERO

# ── Combat ─────────────────────────────────────────────────────────
func take_hit(damage: float, source_pos: Vector2, apply_knockback: bool = true) -> void:
	if damage <= 0.0:
		return
	damage = COMBAT_DATA.damage_taken(damage)
	_mob_health = maxf(0.0, _mob_health - damage)
	var away: Vector2 = global_position - source_pos
	if away.length_squared() > 0.001:
		away = away.normalized()
	if not COMBAT_DATA.is_boss and apply_knockback:
		_knockback += away * (60.0 + damage * 6.0)
	modulate = Color(1.0, 0.4, 0.4, 1.0)
	if _head_sprite != null:
		var tw := create_tween()
		tw.tween_interval(1.0)
		tw.tween_callback(_reset_hit_flash)
	_spawn_damage_number(damage)
	_show_name_label()
	queue_redraw()
	if _mob_health <= 0.0:
		_die()

func _reset_hit_flash() -> void:
	if is_instance_valid(self):
		modulate = Color.WHITE

func _spawn_damage_number(damage: float) -> void:
	var n: Node2D = DAMAGE_NUMBER_SCRIPT.new() as Node2D
	if n == null:
		return
	n.set("_text", str(int(round(damage))))
	n.position = global_position + Vector2(0.0, -24.0)
	get_parent().add_child(n)

# ── Mob name label (Terraria-style) ───────────────────────────────
func _add_name_label() -> void:
	_name_label = MOB_NAME_LABEL_SCRIPT.new() as Node2D
	if _name_label == null:
		return
	_name_label.set("mob_name", COMBAT_DATA.mob_name)
	add_child(_name_label)

func _show_name_label() -> void:
	if _name_label != null:
		_name_label.call("flash")

# allow_loot is false for cleanup deaths (e.g. the stuck watchdog). A normal
# combat defeat passes true. The guard makes repeated damage calls / callbacks
# produce exactly one death and one loot bundle.
func _die(allow_loot: bool = true) -> void:
	if _death_processed:
		return
	_death_processed = true
	if _sand_particles != null and _sand_particles.has_method("set_buried"):
		_sand_particles.set_buried()
	var world: Node = Global.world_node
	if is_instance_valid(world) and world.has_method("notify_mob_killed"):
		world.call("notify_mob_killed", self)
	Global.add_mission_progress("defeat_worms")
	if allow_loot:
		if not COMBAT_DATA.bestiary_id.is_empty():
			Global.bestiary_record_kill(COMBAT_DATA.bestiary_id)
		Global.add_mission_progress("side_worm_slayer", 1)
		_drop_cactus_loot()
		Global.spawn_mob_crystal_drop(get_parent(), global_position)
	_spawn_death_burst()
	queue_free()

# One cactus bundle per successful defeat, quantity 5-10 inclusive. Normal
# InventoryItem pickup/overflow rules apply after it lands on the ground.
func _drop_cactus_loot() -> void:
	var parent: Node = get_parent()
	if parent == null or not is_instance_valid(parent):
		return
	var drop: Node = DROP_ITEM_SCENE.instantiate()
	if drop == null:
		return
	drop.set("item_data", CACTUS_ITEM)
	drop.set("quantity", randi_range(CACTUS_DROP_MIN, CACTUS_DROP_MAX))
	parent.add_child(drop)
	if drop is Node2D:
		(drop as Node2D).global_position = global_position + Vector2(0.0, -6.0)

func _spawn_death_burst() -> void:
	var b: Node2D = MELLOW_BURST_SCRIPT.new() as Node2D
	if b == null:
		return
	b.position = global_position
	get_parent().add_child(b)

func _draw() -> void:
	if _mob_health < COMBAT_DATA.health:
		var w := 24.0
		var h := 3.0
		var y := -20.0
		var frac: float = _mob_health / COMBAT_DATA.health
		draw_rect(Rect2(-w * 0.5, y, w, h), Color(0.05, 0.05, 0.08, 0.85))
		draw_rect(Rect2(-w * 0.5, y, w * frac, h), Color(0.85, 0.25, 0.25, 1.0))

# ── Despawn ────────────────────────────────────────────────────────
func _apply_despawn_zone(zone: int, elapsed: float) -> void:
	if zone != _despawn_zone:
		_despawn_zone = zone
		_despawn_remaining = ZONE_DESPAWN_TIME[zone]
		return
	_despawn_remaining -= elapsed
	if _despawn_remaining <= 0.0:
		queue_free()
