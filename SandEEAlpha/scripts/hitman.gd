extends CharacterBody2D

# Emitted whenever this hitman is removed (sword kill OR stuck self-destruct).
# DungeonWorld's spawner uses it to start its respawn cooldown.
signal died
# Emitted only on a real combat death, never on the stuck-watchdog explosion.
# The boss dungeon uses this to complete the finale mission.
signal defeated

# ── Hitman ───────────────────────────────────────────────────────────
# A dungeon enemy that PATROLS the corridors and has two attacks:
#   1. Ranged  — fires a DungeonProjectile flare (20 dmg) at the player.
#   2. Ram     — when the player is IN SIGHT and on a STRAIGHT, clear corridor
#                the hitman's animation FREEZES (windup), then RESUMES and it
#                charges straight at them for a chunk of damage.
#
# It walks the dungeon generator's FLOOR grid cell-to-cell (never teleports,
# never steps into a wall), so it can't normally get stuck. If it DOES get
# stuck — a ram into a dead end, a corridor blocked mid-charge — it
# self-destructs: an explosion that deals 50% of the max HP of everything
# (the player AND other mobs) caught in the blast.
#
# Directional sprites (no north art needed):
#   east  → side sheet (hitman_leftandright.png, gun faces right)
#   west  → side sheet flipped horizontally
#   south → front sheet (hitman_bottom.png)
#   north → front sheet flipped vertically

const COMBAT_DATA: MobCombatData = preload("res://resources/mobs/hitman.tres")

# Sprite sheets — the side sheet is 248x52 (4 frames), the front sheet 256x64
# (4 frames). Both are sliced into per-frame AtlasTextures (see _add_sheet).
const SIDE_TEX:  Texture2D = preload("res://sprites/mobs/hitman/hitman_leftandright.png")
const FRONT_TEX: Texture2D = preload("res://sprites/mobs/hitman/hitman_bottom.png")
const SIDE_W:   int = 62
const SIDE_H:   int = 52
const FRONT_W:  int = 64
const FRONT_H:  int = 64
const SIDE_FRAMES:  int = 4
const FRONT_FRAMES: int = 4
const ANIM_FPS: float = 6.0
# Visual/collision scale for ordinary Hitmen. The boss dungeon overrides this
# per instance; the sprite, shadow, collider and ranges all scale together.
const SIZE_SCALE: float = 0.7

# Miniboss configuration. Ordinary spawner instances keep the defaults.
@export var is_miniboss: bool = false
@export var miniboss_scale: float = 2.2
@export var max_health_override: float = 0.0
@export var projectile_damage_override: float = 0.0
@export var ram_damage_override: float = 0.0
@export var display_name_override: String = ""
@export var fire_interval_override: float = 0.0
@export var patrol_speed_override: float = 0.0

const PROJECTILE_SCRIPT: GDScript = preload("res://scripts/dungeon_projectile.gd")
const EXPLOSION_SCRIPT:  GDScript = preload("res://scripts/dungeon_explosion.gd")
# The Hitman's flare deals exactly this much (reduced from the obstacle's 40).
const PROJECTILE_DAMAGE: float = 10.0

# ── States ─────────────────────────────────────────────────────────
# No RECOVER state: after a ram the hitman immediately resumes patrolling and
# re-locks the player (see _end_charge) instead of pausing.
enum State { PATROL, WINDUP, CHARGE }

# ── Patrol (grid movement through corridors) ───────────────────────
const PATROL_SPEED: float = 40.0
const ARRIVE_EPS:   float = 2.5

# ── Ranged attack ──────────────────────────────────────────────────
## Only fires while the player is within this many px.
@export var fire_range:    float = 320.0
## Seconds between shots (attack cooldown).
@export var fire_interval: float = 2.5
## Random extra delay added to the first shot so a room of hitmen doesn't
## volley in perfect sync.
@export var first_shot_stagger: float = 0.5

# ── Ram attack ─────────────────────────────────────────────────────
# The ram is only allowed when the player is within SIGHT_RANGE, roughly on
# our axis (within CHARGE_ALIGN_TOL on the perpendicular), and every grid cell
# between us is FLOOR — i.e. a straight, clear corridor. That's what stops the
# charge from slamming into a wall.
const SIGHT_RANGE:      float = 300.0
const CHARGE_ALIGN_TOL: float = 22.0
const CHARGE_MIN_DIST:  float = 48.0
const CHARGE_MAX_DIST:  float = 340.0
const WINDUP_SEC:       float = 0.55   # animation-freeze before the ram
const CHARGE_SPEED:     float = 260.0
const CHARGE_COOLDOWN:  float = 4.0
const RAM_DAMAGE:       float = 12.5
const RAM_HIT_DIST:     float = 22.0

# ── Stuck / self-destruct ──────────────────────────────────────────
# If we're meant to be moving but aren't, we're stuck: blow up.
const STUCK_TIME:      float = 0.18
const STUCK_MIN_SPEED: float = 8.0
const EXPLOSION_FRACTION: float = 0.25   # 25% of each target's max HP (halved)
const EXPLOSION_RADIUS:   float = 64.0

const SHADOW_TEXTURE: Texture2D = preload("res://sprites/shadow/shadow_base.png")
const DAMAGE_NUMBER_SCRIPT: GDScript = preload("res://scripts/damage_number.gd")
const MELLOW_BURST_SCRIPT: GDScript = preload("res://scripts/mellow_burst.gd")
const MOB_NAME_LABEL_SCRIPT: GDScript = preload("res://scripts/mob_name_label.gd")

# Feet-anchored y-sort (mirrors wolf.gd / player.gd).
const YSORT_FEET_OFFSET: float = 11.0
const YSORT_TIEBREAK:    float = 16.0

const HP_BAR_SHOW_MS: float = 3000.0
const HP_BAR_W: float = 30.0
const HP_BAR_H: float = 4.0
const HP_BAR_Y: float = -28.0

@onready var _sprite: AnimatedSprite2D = $AnimatedSprite2D

# Shared across every hitman instance (built once).
static var _shared_frames: SpriteFrames = null

var _state:       int = State.PATROL
var _mob_health:  float = 0.0
var _max_health:  float = 0.0
var _spatial_scale: float = 1.0
var _projectile_damage: float = PROJECTILE_DAMAGE
var _ram_damage: float = RAM_DAMAGE
var _patrol_speed: float = PATROL_SPEED
var _fire_interval: float = 0.0
var _fire_timer:  float = 0.0
var _charge_cd:   float = 0.0
var _state_timer: float = 0.0
var _charge_dir:  Vector2 = Vector2.ZERO
var _charge_start: Vector2 = Vector2.ZERO
var _ram_hit:     bool = false

var _grid_cell:     Vector2i = Vector2i.ZERO
var _patrol_target: Vector2i = Vector2i.ZERO

var _last_dir:   String = "south"
var _last_damage_ms: int = -1
var _name_label: Node2D = null
var _stuck_timer: float = 0.0
var _prev_pos: Vector2 = Vector2.ZERO

func _ready() -> void:
	add_to_group("Hitman")
	add_to_group("Mob")
	_spatial_scale = miniboss_scale if is_miniboss else 1.0
	_max_health = max_health_override if max_health_override > 0.0 else COMBAT_DATA.health
	_mob_health = _max_health
	_projectile_damage = projectile_damage_override if projectile_damage_override > 0.0 else PROJECTILE_DAMAGE
	_ram_damage = ram_damage_override if ram_damage_override > 0.0 else RAM_DAMAGE
	_patrol_speed = patrol_speed_override if patrol_speed_override > 0.0 else PATROL_SPEED
	_fire_interval = fire_interval_override if fire_interval_override > 0.0 else fire_interval
	# Scale the existing art/collider together so the boss keeps crisp pixels and
	# has a collision body matching its visible size.
	_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_sprite.scale = Vector2.ONE * SIZE_SCALE * _spatial_scale
	var col := $CollisionShape2D
	if col != null:
		col.scale = Vector2.ONE * _spatial_scale
		col.position = Vector2(0.0, 3.0 * _spatial_scale)
	if _shared_frames == null:
		_shared_frames = _build_frames()
	_sprite.sprite_frames = _shared_frames
	_apply_facing("south")
	add_child(Global.make_shadow_sprite(SHADOW_TEXTURE,
		Vector2(0.0, 6.0 * SIZE_SCALE * _spatial_scale),
		Vector2(0.6, 0.3) * SIZE_SCALE * _spatial_scale, 0.35))
	_add_name_label()
	# Stagger the first shot so a row of hitmen doesn't fire in unison.
	_fire_timer = randf_range(first_shot_stagger, maxf(_fire_interval, first_shot_stagger + 0.1))
	_charge_cd  = randf_range(1.0, CHARGE_COOLDOWN)
	_prev_pos   = global_position
	# Deferred: the world assigns global_position AFTER add_child, so the patrol
	# cell can only be read once the position is final.
	call_deferred("_init_grid_cell")

func _physics_process(delta: float) -> void:
	# Safe-zone protection: an enemy inside an active zone is disintegrated
	# (no death signal / loot / mission credit). Recheck every frame so a
	# high-speed entry cannot skip the boundary.
	if Global.is_point_in_safe_zone(global_position + Vector2(0.0, YSORT_FEET_OFFSET)):
		safe_zone_disintegrate()
		return
	# Never hold a charge or a windup against a protected player.
	if Global.is_player_in_safe_zone() and _state != State.PATROL:
		_end_charge()

	z_index = int((global_position.y + YSORT_FEET_OFFSET + YSORT_TIEBREAK) / 32.0)
	if _last_damage_ms > 0 and Time.get_ticks_msec() - _last_damage_ms < HP_BAR_SHOW_MS:
		queue_redraw()

	_charge_cd = maxf(0.0, _charge_cd - delta)

	match _state:
		State.PATROL:  _tick_patrol(delta)
		State.WINDUP:  _tick_windup(delta)
		State.CHARGE:  _tick_charge(delta)

	# Stuck check runs AFTER the move: _prev_pos holds last frame's post-move
	# position, so the delta here is exactly this frame's movement. (Running it
	# BEFORE the move compared the position to itself → always "stuck".)
	_tick_stuck(delta)
	_prev_pos = global_position

# ── Dungeon grid access ────────────────────────────────────────────
# The world is a DungeonWorld exposing grid helpers (grid_to_world /
# world_to_grid / grid_cell_is_floor). Null anywhere else.
func _world() -> Node:
	var w: Node = Global.world_node
	if w == null or not is_instance_valid(w):
		return null
	if not w.has_method("grid_cell_is_floor"):
		return null
	return w

func _init_grid_cell() -> void:
	var w := _world()
	if w == null:
		return
	_grid_cell = w.call("world_to_grid", global_position)
	_pick_patrol_target()

# ── PATROL ─────────────────────────────────────────────────────────
func _tick_patrol(delta: float) -> void:
	var w := _world()
	if w == null:
		velocity = Vector2.ZERO
		return

	# A ram takes priority when the player is in sight on a straight corridor.
	if _charge_cd <= 0.0 and _can_charge_at_player(w):
		_begin_windup()
		return

	var target: Vector2 = w.call("grid_to_world", _patrol_target)
	var to: Vector2 = target - global_position
	if to.length() <= ARRIVE_EPS:
		_grid_cell = _patrol_target
		_pick_patrol_target()
		velocity = Vector2.ZERO
	else:
		var dir: Vector2 = to.normalized()
		velocity = dir * _patrol_speed
		_update_facing(dir)
		move_and_slide()

	_try_fire(delta)

# Pick the next FLOOR cell to walk to. Prefer continuing straight (patrolling
# down a corridor); otherwise turn to a random open neighbour; a dead end
# reverses. Never picks a WALL, so the mob can't walk into geometry.
func _pick_patrol_target() -> void:
	var w := _world()
	if w == null:
		_patrol_target = _grid_cell
		return
	var fwd: Vector2i = _grid_cell - _patrol_target
	if fwd == Vector2i.ZERO:
		fwd = Vector2i(0, 1)
	var straight: Vector2i = _grid_cell + fwd
	if w.call("grid_cell_is_floor", straight):
		_patrol_target = straight
		return
	var open: Array = []
	for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var n: Vector2i = _grid_cell + d
		if w.call("grid_cell_is_floor", n):
			open.append(n)
	if open.is_empty():
		_patrol_target = _grid_cell   # boxed in — _tick_stuck handles it
		return
	_patrol_target = open[randi() % open.size()]

func _try_fire(delta: float) -> void:
	var p := Global.player_node as Node2D
	if p == null or not is_instance_valid(p) or Global.player_is_dead:
		return
	if Global.is_player_in_safe_zone():
		return
	if global_position.distance_to(p.global_position) > fire_range * _spatial_scale:
		return
	_fire_timer -= delta
	if _fire_timer <= 0.0:
		_fire_timer = _fire_interval
		_fire_at(p.global_position)

func _fire_at(target: Vector2) -> void:
	var proj: Node = PROJECTILE_SCRIPT.new()
	proj.set("direction", (target - global_position).normalized())
	# Per-instance damage + wall collision (the obstacle flare keeps its 40 and
	# passes through walls; the Hitman's is 20 and stops at walls).
	proj.set("damage", _projectile_damage)
	proj.set("collide_walls", true)
	get_parent().add_child(proj)
	proj.global_position = global_position + Vector2(0.0, 4.0 * _spatial_scale)

# ── Ram: eligibility ───────────────────────────────────────────────
func _can_charge_at_player(w: Node) -> bool:
	var p := Global.player_node as Node2D
	if p == null or not is_instance_valid(p) or Global.player_is_dead:
		return false
	# Never attack a player who is safe inside an altar room.
	if Global.is_player_in_safe_zone():
		return false
	var to: Vector2 = p.global_position - global_position
	var dist: float = to.length()
	if dist < CHARGE_MIN_DIST * _spatial_scale or dist > SIGHT_RANGE * _spatial_scale:
		return false
	var axis_x: bool = absf(to.x) >= absf(to.y)
	# Must be roughly on the charge axis so the ram goes straight, not diagonally
	# into a corner.
	if axis_x:
		if absf(to.y) > CHARGE_ALIGN_TOL:
			return false
	else:
		if absf(to.x) > CHARGE_ALIGN_TOL:
			return false
	return _straight_path_clear(w, axis_x, p.global_position)

# Walk the grid one cell at a time from our cell toward the player's cell along
# the charge axis. Any WALL in the way means the corridor bends or ends — no ram.
func _straight_path_clear(w: Node, axis_x: bool, player_pos: Vector2) -> bool:
	var target_cell: Vector2i = w.call("world_to_grid", player_pos)
	var cell: Vector2i = _grid_cell
	if axis_x:
		var step: int = signi(target_cell.x - cell.x)
		if step == 0:
			return false
		while cell.x != target_cell.x:
			cell.x += step
			if not w.call("grid_cell_is_floor", cell):
				return false
	else:
		var step: int = signi(target_cell.y - cell.y)
		if step == 0:
			return false
		while cell.y != target_cell.y:
			cell.y += step
			if not w.call("grid_cell_is_floor", cell):
				return false
	return true

func _begin_windup() -> void:
	_state = State.WINDUP
	_state_timer = WINDUP_SEC
	velocity = Vector2.ZERO
	_ram_hit = false
	# Freeze on the spot — the animation stops dead during the windup.
	_sprite.speed_scale = 0.0
	var p := Global.player_node as Node2D
	if p != null and is_instance_valid(p):
		_charge_dir = _axis_dir_toward(p.global_position)
		_update_facing(_charge_dir)

func _axis_dir_toward(target: Vector2) -> Vector2:
	var to: Vector2 = target - global_position
	if absf(to.x) >= absf(to.y):
		return Vector2(signf(to.x), 0.0)
	return Vector2(0.0, signf(to.y))

func _tick_windup(delta: float) -> void:
	velocity = Vector2.ZERO
	_state_timer -= delta
	if _state_timer <= 0.0:
		_begin_charge()

func _begin_charge() -> void:
	_state = State.CHARGE
	_charge_start = global_position
	_ram_hit = false
	# Resume the animation as the ram begins.
	_sprite.speed_scale = 1.0

func _tick_charge(delta: float) -> void:
	velocity = _charge_dir * CHARGE_SPEED
	_update_facing(_charge_dir)
	move_and_slide()

	# Ram the player on contact (once per charge) — but keep going THROUGH them:
	# the hitman barrels past instead of stopping on top of the player.
	var p := Global.player_node as Node2D
	if not _ram_hit and p != null and is_instance_valid(p) and not Global.player_is_dead \
			and not Global.is_player_in_safe_zone():
		if global_position.distance_to(p.global_position) <= RAM_HIT_DIST * _spatial_scale:
			_ram_hit = true
			Global.damage_player(_ram_damage, global_position, _charge_dir)

	if global_position.distance_to(_charge_start) >= CHARGE_MAX_DIST * _spatial_scale:
		_end_charge()

# No post-ram pause — go straight back to patrolling, which immediately re-locks
# onto the player (another ram if they're still in sight on a straight corridor).
func _end_charge() -> void:
	_state = State.PATROL
	_charge_cd = 0.0
	velocity = Vector2.ZERO
	_ram_hit = false
	# _begin_windup froze the animation; restore it if the attack was cancelled
	# because the player became protected.
	if _sprite != null:
		_sprite.speed_scale = 1.0
	var w := _world()
	if w != null:
		_grid_cell = w.call("world_to_grid", global_position)
	_pick_patrol_target()

# ── Stuck → self-destruct ──────────────────────────────────────────
func _tick_stuck(delta: float) -> void:
	# The finale boss must never self-destruct out of a mission completion.
	if is_miniboss:
		_stuck_timer = 0.0
		return
	if _world() == null or (_state != State.PATROL and _state != State.CHARGE):
		_stuck_timer = 0.0
		return
	if global_position.distance_to(_prev_pos) < STUCK_MIN_SPEED * delta:
		_stuck_timer += delta
		if _stuck_timer >= STUCK_TIME:
			_self_destruct()
	else:
		_stuck_timer = 0.0

# Blow up where we stand: an explosion effect that deals 25% of the max HP of
# everything in range (the player + other mobs), then free the hitman.
func _self_destruct() -> void:
	died.emit()
	var ex: Node2D = EXPLOSION_SCRIPT.new() as Node2D
	if ex != null:
		ex.set("damage_fraction", EXPLOSION_FRACTION)
		ex.set("damage_mobs", true)
		get_parent().add_child(ex)
		ex.global_position = global_position
	_spawn_death_burst()
	queue_free()

# Safe-zone removal: visual disintegrate only. Deliberately does NOT emit
# `died` or call notify_mob_killed, so there is no loot, quest credit or
# mission star for a protected-zone cleanup.
var _safe_zone_gone: bool = false
func safe_zone_disintegrate() -> void:
	if _safe_zone_gone:
		return
	_safe_zone_gone = true
	_spawn_death_burst()
	queue_free()

# ── Directional sprites ───────────────────────────────────────────
# Dominant axis wins (|dx| vs |dy|); ties fall to the vertical so a player
# standing near a diagonal doesn't flip the sprite every frame.
func _update_facing(to: Vector2) -> void:
	if to.length_squared() < 0.0001:
		return
	var dir: String
	if absf(to.x) > absf(to.y):
		dir = "east" if to.x > 0.0 else "west"
	else:
		dir = "south" if to.y > 0.0 else "north"
	if dir == _last_dir:
		return
	_apply_facing(dir)

func _apply_facing(dir: String) -> void:
	_last_dir = dir
	if dir == "north" or dir == "south":
		if _sprite.animation != "front":
			_sprite.play("front")
		_sprite.flip_h = false
		_sprite.flip_v = (dir == "north")   # north reuses the front sheet, flipped
	else:
		if _sprite.animation != "side":
			_sprite.play("side")
		_sprite.flip_v = false
		_sprite.flip_h = (dir == "west")    # the side art faces east

func _build_frames() -> SpriteFrames:
	var sf := SpriteFrames.new()
	sf.remove_animation("default")
	_add_sheet(sf, "side",  SIDE_TEX,  SIDE_W,  SIDE_H,  SIDE_FRAMES)
	_add_sheet(sf, "front", FRONT_TEX, FRONT_W, FRONT_H, FRONT_FRAMES)
	return sf

func _add_sheet(sf: SpriteFrames, anim_name: String, tex: Texture2D,
		w: int, h: int, count: int) -> void:
	sf.add_animation(anim_name)
	sf.set_animation_speed(anim_name, ANIM_FPS)
	sf.set_animation_loop(anim_name, true)
	for i in range(count):
		var at := AtlasTexture.new()
		at.atlas  = tex
		at.region = Rect2(i * w, 0, w, h)
		sf.add_frame(anim_name, at)

# ── Sword hit / death (mirrors wolf.gd) ───────────────────────────
func take_hit(damage: float, _source_pos: Vector2, _apply_knockback: bool = true) -> void:
	if damage <= 0.0 or _mob_health <= 0.0:
		return
	damage = COMBAT_DATA.damage_taken(damage)
	_mob_health = maxf(0.0, _mob_health - damage)
	_last_damage_ms = Time.get_ticks_msec()
	modulate = Color(1.0, 0.4, 0.4, 1.0)
	var tw := create_tween()
	tw.tween_interval(1.0)
	tw.tween_callback(_reset_hit_flash)
	_spawn_damage_number(damage)
	if _name_label != null:
		_name_label.call("flash")
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

func _add_name_label() -> void:
	_name_label = MOB_NAME_LABEL_SCRIPT.new() as Node2D
	if _name_label == null:
		return
	_name_label.set("mob_name",
		display_name_override if not display_name_override.is_empty() else COMBAT_DATA.mob_name)
	add_child(_name_label)

# Killed by the sword — a normal death (no self-destruct blast).
func _die() -> void:
	died.emit()
	defeated.emit()
	var world: Node = Global.world_node
	if is_instance_valid(world) and world.has_method("notify_mob_killed"):
		world.call("notify_mob_killed", self)
	_spawn_death_burst()
	queue_free()

func _spawn_death_burst() -> void:
	var b: Node2D = MELLOW_BURST_SCRIPT.new() as Node2D
	if b == null:
		return
	b.position = global_position
	get_parent().add_child(b)

func _draw() -> void:
	if _last_damage_ms < 0:
		return
	if Time.get_ticks_msec() - _last_damage_ms > HP_BAR_SHOW_MS:
		return
	if _mob_health >= _max_health:
		return
	var frac: float = clampf(_mob_health / _max_health, 0.0, 1.0)
	var bar_w: float = HP_BAR_W * _spatial_scale
	var bar_h: float = HP_BAR_H * _spatial_scale
	var bar_y: float = HP_BAR_Y * _spatial_scale
	draw_rect(Rect2(-bar_w * 0.5, bar_y, bar_w, bar_h), Color(0.05, 0.05, 0.08, 0.85))
	draw_rect(Rect2(-bar_w * 0.5, bar_y, bar_w * frac, bar_h), Color(0.85, 0.25, 0.25, 1.0))
