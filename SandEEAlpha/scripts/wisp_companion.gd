extends CharacterBody2D
class_name WispCompanion

# ── Friendly Wisp companion ──────────────────────────────────────────
# One Wisp belongs to the Game root, not to a world. The overworld, caves,
# pixie caves and dungeons all replace/remove their world node during travel,
# so a Game-owned companion is the only placement that survives every
# transition without reparenting or duplicate spawns. It is deliberately NOT
# in the "Mob" group and never uses collision layer 2, so ambient spawning,
# despawn culling, bestiary scans, sword hits, PNC targeting and dungeon
# explosions all ignore it.
#
# Movement is a smooth follow/orbit around the player. Body movement is always
# continuous during normal play; only explicit world transitions, death
# respawns and a stuck-recovery fallback snap it to a validated nearby spot.

const GROUP: String = "WispCompanion"
const BODY_TEXTURE: Texture2D = preload("res://sprites/mobs/wisp/wisp_frames_4f.png")
const HALO_TEXTURE: Texture2D = preload("res://sprites/particles_effects/glowing_orbs_sample.png")
const LIGHT_TEXTURE_SIZE: int = 256

const FRAME_COUNT: int = 4
const FRAME_FPS: float = 7.0
const HOVER_RADIUS: float = 44.0
const HOVER_SIDE: float = 13.0
const HOVER_HEIGHT: float = -8.0
const LEASH_DIST: float = 245.0
const STUCK_RECOVER_SEC: float = 2.4
const LAG_RECOVER_SEC: float = 3.0
const LAG_MIN_DIST: float = HOVER_RADIUS + 30.0
const FAR_RECOVER_SEC: float = 5.0
const RECOVERY_COOLDOWN_SEC: float = 4.0

const SPEED_MIN: float = 62.0
const SPEED_MAX: float = 150.0
const ACCEL: float = 260.0
const DECEL: float = 380.0
const LOOKAHEAD: float = 32.0
const REROUTE_COMMIT_SEC: float = 0.35
const REROUTE_ANGLES: Array[float] = [
	24.0, -24.0, 48.0, -48.0, 72.0, -72.0,
	104.0, -104.0, 140.0, -140.0, 180.0,
]
const BODY_RADIUS: float = 7.0

# Light profiles. The dim cave and pixie-cave CanvasModulate needs a much
# stronger pool than daylight; dungeons intentionally keep the Wisp dark.
const LIGHT_OVERWORLD_ENERGY: float = 1.08
const LIGHT_OVERWORLD_SCALE: float = 0.42
const LIGHT_CAVE_ENERGY: float = 1.85
const LIGHT_CAVE_SCALE: float = 0.72
const LIGHT_PIXIE_ENERGY: float = 1.62
const LIGHT_PIXIE_SCALE: float = 0.64
const LIGHT_CAVE_COLOR := Color(0.62, 0.95, 1.0, 1.0)
const LIGHT_PIXIE_COLOR := Color(0.68, 0.90, 1.0, 1.0)

var _sprite: Sprite2D = null
var _halo: Sprite2D = null
var _light: PointLight2D = null
var _collision: CollisionShape2D = null
var _recovery_shape: CircleShape2D = null
var _fade_tween: Tween = null
var _light_base_energy: float = LIGHT_OVERWORLD_ENERGY
var _light_base_scale: float = LIGHT_OVERWORLD_SCALE
var _light_context: String = "overworld"

var _anim_time: float = 0.0
var _heading: Vector2 = Vector2.DOWN
var _stuck_time: float = 0.0
var _recovery_cooldown: float = 0.0
var _last_position: Vector2 = Vector2.ZERO
var _has_last_position: bool = false
var _last_player_dist: float = 0.0
var _progress_accum: float = 0.0
var _progress_time: float = 0.0
var _far_time: float = 0.0
var _reroute_dir: Vector2 = Vector2.ZERO
var _reroute_timer: float = 0.0
var _hidden_for_death: bool = false

func _enter_tree() -> void:
	add_to_group(GROUP)
	# Defensive singleton: a duplicate Wisp created by a stale scene or a test
	# must never leave two companions following the player. The newest instance
	# wins; the older one is queued for deletion before it can affect movement.
	var tree := get_tree()
	if tree == null:
		return
	for other in tree.get_nodes_in_group(GROUP):
		if other != self and is_instance_valid(other):
			other.queue_free()

func _ready() -> void:
	collision_layer = 0          # never blocks/pushes the player or mobs
	collision_mask = 1           # collide with world terrain/blocks
	motion_mode = CharacterBody2D.MOTION_MODE_FLOATING
	z_as_relative = false
	_build_visuals()
	_apply_light_profile(_context_for_world())
	_connect_signals()
	_last_position = global_position
	_has_last_position = true
	snap_to_player()

func _build_visuals() -> void:
	_collision = CollisionShape2D.new()
	_collision.name = "BodyShape"
	var circle := CircleShape2D.new()
	circle.radius = BODY_RADIUS
	_collision.shape = circle
	add_child(_collision)

	_sprite = Sprite2D.new()
	_sprite.name = "WispSprite"
	_sprite.texture = BODY_TEXTURE
	_sprite.hframes = FRAME_COUNT
	_sprite.vframes = 1
	_sprite.frame = 0
	_sprite.position = Vector2(0.0, -2.0)
	_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_sprite.z_index = 1
	add_child(_sprite)

	# A small additive halo gives the sprite a soft magical edge without a
	# second light. The world's existing glow environment handles the bloom;
	# this is only one extra draw call and works identically in every world.
	_halo = Sprite2D.new()
	_halo.name = "WispHalo"
	_halo.texture = HALO_TEXTURE
	_halo.hframes = 8
	_halo.frame = 0
	_halo.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_halo.modulate = Color(0.52, 0.90, 1.0, 0.30)
	_halo.position = Vector2(0.0, -2.0)
	_halo.z_index = -1
	var halo_material := CanvasItemMaterial.new()
	halo_material.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_halo.material = halo_material
	add_child(_halo)

	# One light only. The texture is the project's cached smooth radial texture,
	# so Android never generates a light texture per frame or per Wisp.
	_light = PointLight2D.new()
	_light.name = "WispLight"
	_light.texture = Global.get_smooth_light_texture(LIGHT_TEXTURE_SIZE)
	_light.texture_scale = 0.42
	_light.color = Color(0.62, 0.95, 1.0, 1.0)
	_light.energy = 1.08
	_light.position = Vector2(0.0, -2.0)
	add_child(_light)

	_recovery_shape = CircleShape2D.new()
	_recovery_shape.radius = BODY_RADIUS

func _connect_signals() -> void:
	if not Global.cave_entered.is_connected(_on_cave_entered):
		Global.cave_entered.connect(_on_cave_entered)
	if not Global.cave_exited.is_connected(_on_cave_exited):
		Global.cave_exited.connect(_on_cave_exited)
	if not Global.dungeon_entered.is_connected(_on_dungeon_entered):
		Global.dungeon_entered.connect(_on_dungeon_entered)
	if not Global.dungeon_exited.is_connected(_on_dungeon_exited):
		Global.dungeon_exited.connect(_on_dungeon_exited)
	if not Global.player_died.is_connected(_on_player_died):
		Global.player_died.connect(_on_player_died)
	if not Global.player_spawned.is_connected(_on_player_spawned):
		Global.player_spawned.connect(_on_player_spawned)

func _exit_tree() -> void:
	if Global.cave_entered.is_connected(_on_cave_entered):
		Global.cave_entered.disconnect(_on_cave_entered)
	if Global.cave_exited.is_connected(_on_cave_exited):
		Global.cave_exited.disconnect(_on_cave_exited)
	if Global.dungeon_entered.is_connected(_on_dungeon_entered):
		Global.dungeon_entered.disconnect(_on_dungeon_entered)
	if Global.dungeon_exited.is_connected(_on_dungeon_exited):
		Global.dungeon_exited.disconnect(_on_dungeon_exited)
	if Global.player_died.is_connected(_on_player_died):
		Global.player_died.disconnect(_on_player_died)
	if Global.player_spawned.is_connected(_on_player_spawned):
		Global.player_spawned.disconnect(_on_player_spawned)

func _physics_process(delta: float) -> void:
	_anim_time += delta
	_animate()
	_recovery_cooldown = maxf(0.0, _recovery_cooldown - delta)

	var player := _player()
	if player == null:
		velocity = velocity.move_toward(Vector2.ZERO, DECEL * delta)
		move_and_slide()
		return

	if _hidden_for_death or Global.player_is_dead:
		velocity = velocity.move_toward(Vector2.ZERO, DECEL * delta)
		move_and_slide()
		return

	var player_pos: Vector2 = player.global_position
	var player_dist: float = global_position.distance_to(player_pos)
	if player_dist > LEASH_DIST:
		# Waypoint recalls and any other teleport that has no explicit signal.
		# This is a recovery, not ordinary movement; ordinary following never
		# assigns a position.
		snap_to_player()
		return

	var target := _follow_target(player, player_pos, delta)
	var to_target := target - global_position
	var target_dist := to_target.length()

	if target_dist <= 6.0:
		velocity = velocity.move_toward(Vector2.ZERO, DECEL * delta)
	else:
		var desired := to_target / target_dist
		desired = _steer_around(desired, delta)
		var speed := clampf(
			SPEED_MIN + maxf(0.0, player_dist - HOVER_RADIUS) * 1.15,
			SPEED_MIN, SPEED_MAX)
		if target_dist < 26.0:
			speed *= 0.55
		var rate := ACCEL if target_dist > 12.0 else DECEL
		velocity = velocity.move_toward(desired * speed, rate * delta)

	velocity = velocity.limit_length(SPEED_MAX)
	move_and_slide()
	z_index = int(global_position.y / 32.0)
	_tick_stuck(delta, player_dist)

func _follow_target(player: Node2D, player_pos: Vector2, delta: float) -> Vector2:
	var facing := Vector2.ZERO
	# While walking, hover behind the direction of travel; while standing,
	# settle behind the player's actual facing/cursor direction.
	if player is CharacterBody2D:
		var body := player as CharacterBody2D
		if body.velocity.length_squared() > 25.0:
			facing = body.velocity.normalized()
	if facing == Vector2.ZERO and player.has_method("facing_vector"):
		var raw: Variant = player.call("facing_vector")
		if raw is Vector2:
			facing = raw
	if facing.length_squared() < 0.001:
		facing = Vector2.DOWN
	facing = facing.normalized()

	# Ease the follow heading instead of mirroring every mouse/facing change.
	_heading = _heading.lerp(facing, clampf(delta * 2.4, 0.0, 1.0))
	if _heading.length_squared() < 0.001:
		_heading = facing
	else:
		_heading = _heading.normalized()

	var back := -_heading
	var side := Vector2(-_heading.y, _heading.x)
	var sway := sin(_anim_time * 0.85) * 0.32 + cos(_anim_time * 0.37) * 0.12
	var offset := back.rotated(sway) * HOVER_RADIUS
	offset += side * (sin(_anim_time * 0.63) * HOVER_SIDE)
	offset += Vector2(0.0, HOVER_HEIGHT)
	return player_pos + offset

func _steer_around(desired: Vector2, delta: float) -> Vector2:
	if _reroute_timer > 0.0:
		_reroute_timer = maxf(0.0, _reroute_timer - delta)
		if _reroute_dir != Vector2.ZERO and _path_clear(_reroute_dir):
			return _reroute_dir
		_reroute_timer = 0.0

	if _path_clear(desired):
		_reroute_dir = desired
		return desired

	# Try progressively wider directions and commit briefly so the Wisp glides
	# around a corner instead of dithering left/right in front of it.
	for angle in REROUTE_ANGLES:
		var candidate := desired.rotated(deg_to_rad(angle))
		if _path_clear(candidate):
			_reroute_dir = candidate
			_reroute_timer = REROUTE_COMMIT_SEC
			return candidate

	_reroute_dir = desired
	_reroute_timer = 0.15
	return desired

func _path_clear(direction: Vector2) -> bool:
	if direction.length_squared() < 0.0001:
		return true
	return not test_move(global_transform, direction.normalized() * LOOKAHEAD)

func _tick_stuck(delta: float, player_dist: float) -> void:
	if not _has_last_position:
		_last_position = global_position
		_has_last_position = true
		_last_player_dist = player_dist
		return
	var moved: float = global_position.distance_to(_last_position)
	_last_position = global_position

	if player_dist > LAG_MIN_DIST:
		_far_time += delta
		# "Moved" alone is not enough: sliding along a long wall can keep the
		# body in motion while making no progress toward the player. Accumulate
		# actual closing distance over a window and recover if it never closes.
		# A large outward jump is usually a teleport, so start a fresh window
		# instead of letting that one frame poison the progress total.
		var closing := _last_player_dist - player_dist
		if closing < -48.0:
			_progress_accum = 0.0
			_progress_time = 0.0
		else:
			_progress_accum += closing
			_progress_time += delta
		if moved < 0.25:
			_stuck_time += delta
		else:
			_stuck_time = maxf(0.0, _stuck_time - delta)
		if _stuck_time >= STUCK_RECOVER_SEC and _recovery_cooldown <= 0.0:
			snap_to_player()
			return
		if _far_time >= FAR_RECOVER_SEC and _recovery_cooldown <= 0.0:
			snap_to_player()
			return
		if _progress_time >= LAG_RECOVER_SEC:
			if _progress_accum < 2.0 and _recovery_cooldown <= 0.0:
				snap_to_player()
				return
			_progress_time = 0.0
			_progress_accum = 0.0
	else:
		_stuck_time = 0.0
		_progress_time = 0.0
		_progress_accum = 0.0
		_far_time = 0.0
	_last_player_dist = player_dist

func _animate() -> void:
	if _sprite == null:
		return
	_sprite.frame = int(_anim_time * FRAME_FPS) % FRAME_COUNT
	_sprite.position = Vector2(
		sin(_anim_time * 1.6) * 1.5,
		-2.0 + sin(_anim_time * 2.2) * 3.0)

	if _halo != null:
		_halo.position = _sprite.position
		_halo.rotation = _anim_time * 0.35
		var pulse := 1.0 + sin(_anim_time * 1.8) * 0.06
		_halo.scale = Vector2(pulse, pulse)

	if _light != null:
		_light.position = _sprite.position
		if _light.enabled:
			_light.energy = _light_base_energy + sin(_anim_time * 2.1) * 0.10
			_light.texture_scale = _light_base_scale + sin(_anim_time * 1.4) * 0.015

## Recover to a validated spot near the player. Used only on explicit world
## transitions, death respawns, waypoint-distance recovery and the stuck
## watchdog -- never during ordinary following.
func snap_to_player() -> void:
	var player := _player()
	if player == null:
		return
	var spot := _find_recovery_spot(player.global_position)
	global_position = spot
	velocity = Vector2.ZERO
	_reroute_dir = Vector2.ZERO
	_reroute_timer = 0.0
	_stuck_time = 0.0
	_recovery_cooldown = RECOVERY_COOLDOWN_SEC
	_last_position = global_position
	_has_last_position = true
	_last_player_dist = global_position.distance_to(player.global_position)
	_progress_accum = 0.0
	_progress_time = 0.0
	_far_time = 0.0
	_hidden_for_death = Global.player_is_dead
	visible = not _hidden_for_death
	_fade_in()

func _find_recovery_spot(center: Vector2) -> Vector2:
	var radii: Array[float] = [HOVER_RADIUS, HOVER_RADIUS + 18.0, HOVER_RADIUS + 36.0]
	for radius in radii:
		for i in range(8):
			var angle: float = TAU * float(i) / 8.0 + 0.35
			var candidate: Vector2 = center + Vector2(cos(angle), sin(angle)) * radius
			candidate.y += HOVER_HEIGHT
			if _spot_free(candidate):
				return candidate
	# The player's own tile is always clear. If every surrounding candidate is
	# blocked (tight corridor), overlapping the player is safer than embedding
	# the Wisp inside a wall.
	return center + Vector2(0.0, HOVER_HEIGHT)

func _spot_free(point: Vector2) -> bool:
	if not is_inside_tree() or _recovery_shape == null:
		return true
	var world := get_world_2d()
	if world == null:
		return true
	var space := world.direct_space_state
	if space == null:
		return true
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = _recovery_shape
	query.transform = Transform2D(0.0, point)
	query.collision_mask = 1
	query.exclude = [get_rid()]
	return space.intersect_shape(query, 1).is_empty()

func _fade_in() -> void:
	if _sprite == null or _halo == null:
		return
	if _fade_tween != null and _fade_tween.is_valid():
		_fade_tween.kill()
	_sprite.modulate.a = 0.0
	_halo.modulate.a = 0.0
	_fade_tween = create_tween().set_parallel(true)
	_fade_tween.tween_property(_sprite, "modulate:a", 1.0, 0.22)
	_fade_tween.tween_property(_halo, "modulate:a", 0.30, 0.22)

func _player() -> Node2D:
	var node: Node = Global.player_node
	if node == null or not is_instance_valid(node):
		return null
	return node as Node2D

func _on_cave_entered(kind: String) -> void:
	_apply_light_profile("pixie" if kind == "pixie" else "cave")
	snap_to_player()

func _on_cave_exited(_kind: String) -> void:
	_apply_light_profile("overworld")
	snap_to_player()

func _on_dungeon_entered(_index: int) -> void:
	_apply_light_profile("dungeon")
	snap_to_player()

func _on_dungeon_exited(_index: int) -> void:
	_apply_light_profile("overworld")
	snap_to_player()

func _on_player_died(_death_position: Vector2) -> void:
	_hidden_for_death = true
	velocity = Vector2.ZERO
	visible = false

func _context_for_world() -> String:
	if Global.is_in_dungeon:
		return "dungeon"
	var world: Node = Global.world_node
	# The global can outlive a world during a transition or a test teardown;
	# `is` on a freed instance raises a script error.
	if world == null or not is_instance_valid(world):
		return "overworld"
	if world is DungeonWorld:
		return "dungeon"
	if world is PixieCaveWorld:
		return "pixie"
	if world is CaveWorld:
		return "cave"
	return "overworld"

# The cave and Pixie-cave CanvasModulates are much darker than daylight, so the
# same tiny overworld light barely registers. Boost it in caves, use a slightly
# softer Pixie profile, and switch it off entirely in dungeons.
func _apply_light_profile(kind: String) -> void:
	_light_context = kind
	if _light == null:
		return
	match kind:
		"dungeon":
			_light.enabled = false
			_light.energy = 0.0
			return
		"cave":
			_light_base_energy = LIGHT_CAVE_ENERGY
			_light_base_scale = LIGHT_CAVE_SCALE
			_light.color = LIGHT_CAVE_COLOR
		"pixie":
			_light_base_energy = LIGHT_PIXIE_ENERGY
			_light_base_scale = LIGHT_PIXIE_SCALE
			_light.color = LIGHT_PIXIE_COLOR
		_:
			_light_base_energy = LIGHT_OVERWORLD_ENERGY
			_light_base_scale = LIGHT_OVERWORLD_SCALE
			_light.color = Color(0.62, 0.95, 1.0, 1.0)
	_light.enabled = true
	_light.energy = _light_base_energy
	_light.texture_scale = _light_base_scale

func _on_player_spawned(_spawn_position: Vector2) -> void:
	_apply_light_profile(_context_for_world())
	snap_to_player()
