extends CharacterBody2D
class_name HeadlessFishMob

# ── Headless Fish mob (flies, orbits player, night-only) ──────────
# Follows the same shape as pixie_mob.gd: a CombatData resource drives
# stats, an AI script decides movement, contact attacks go through
# Global.damage_player.

const COMBAT_DATA: MobCombatData = preload("res://resources/mobs/headless_fish.tres")
# Headless Fish drop one raw fish from the existing fishing pool. Reusing the
# four canonical fish resources keeps loot IDs, icons, stacking and cooking
# recipes identical to a fish caught with the rod.
const FISH_ITEMS: Array = [
	preload("res://resources/items/charlie.tres"),
	preload("res://resources/items/glep_glorp.tres"),
	preload("res://resources/items/allan.tres"),
	preload("res://resources/items/pimpim.tres"),
]
const DROP_ITEM_SCENE: PackedScene = preload("res://scenes/ui/InventoryItem.tscn")

const AI_SCRIPTS: Dictionary = {
	"HEADLESS_FISH": preload("res://scripts/AI/HEADLESS_FISH.gd"),
}

const ATTACK_RANGE:    float = 28.0
# Contact-attack cooldown. Was 5.0 — far longer than every other mob
# (wolf/pixie 1.0, worm 1.2), so the fish hit once and then went ~5s without
# ever landing a second bite. Matches wolf/pixie now.
const ATTACK_COOLDOWN: float = 1.0
const SHADOW_TEXTURE:  Texture2D = preload("res://sprites/shadow/shadow_base.png")
const DAMAGE_NUMBER_SCRIPT: GDScript = preload("res://scripts/damage_number.gd")
const MELLOW_BURST_SCRIPT: GDScript = preload("res://scripts/mellow_burst.gd")
const MOB_NAME_LABEL_SCRIPT: GDScript = preload("res://scripts/mob_name_label.gd")

const FISH_TEX: Texture2D = preload("res://sprites/mobs/headless fih/headless_fih.png")
# Actual sheet is 186 x 49 = 3 horizontal frames of 62 x 49.
const FRAME_COUNT: int = 3
const FRAME_W:     int = 62
const FRAME_H:     int = 49
const SPRITE_SCALE: float = 0.6

# ── Combat ─────────────────────────────────────────────────────────
var _mob_health:   float  = 0.0
var _death_processed: bool = false
var _knockback:    Vector2 = Vector2.ZERO
const KNOCKBACK_DECAY: float = 900.0
var _attack_cooldown: float = 0.0

# ── Night-only despawn ─────────────────────────────────────────────
var _day_connected: bool = false

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

# ── Despawn zone (driven by world.gd's periodic distance check) ──────
# Same contract as wolf.gd/worm.gd: the world ticks this with a zone + elapsed
# and the fish vanishes once its zone's budget runs out. Day-time mobs cull
# fast in the outer ring so the ambient director can recycle their slot.
const ZONE_DESPAWN_TIME := {0: 1800.0, 1: 900.0, 2: 300.0}
var _despawn_zone: int = -1
var _despawn_remaining: float = 0.0

@onready var _sprite: AnimatedSprite2D = $AnimatedSprite2D

var _ai: RefCounted = null
var _tilemap: TileMapLayer = null
var _last_move_dir: Vector2 = Vector2.DOWN
# PASSIVE flee-on-hit (see FleeBehavior); HOSTILE mobs never use it.
var _flee: FleeBehavior = FleeBehavior.new()
var _name_label: Node2D = null

func _ready() -> void:
	add_to_group("HeadlessFish")
	add_to_group("Mob")
	# Flying mob: FLOATING motion mode. The default GROUNDED mode applies
	# floor/wall snapping inside move_and_slide, which can visibly pop the fish
	# around when it brushes geometry (reads as teleporting).
	motion_mode = CharacterBody2D.MOTION_MODE_FLOATING
	_mob_health = COMBAT_DATA.health
	z_index = int(global_position.y / 32)

	# Sprite setup — 3-frame horizontal spritesheet, 62x49 per frame
	_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_sprite.scale = Vector2(SPRITE_SCALE, SPRITE_SCALE)
	var frames := _build_frames()
	_sprite.sprite_frames = frames
	_sprite.visible = true
	_sprite.play("swim")
	add_child(Global.make_shadow_sprite(SHADOW_TEXTURE, Vector2(0.0, 10.0), Vector2(0.9, 0.4), 0.35))
	_add_name_label()

	_tilemap = _find_ground_tilemap()
	var ai_script: Script = AI_SCRIPTS.get(COMBAT_DATA.ai_type)
	if ai_script != null:
		_ai = ai_script.new()

	Global.player_died.connect(_on_player_died)
	Global.player_spawned.connect(_on_player_spawned)

	# Night-only: despawn when day starts
	Global.day_started.connect(_on_day_started)
	_day_connected = true

func _find_ground_tilemap() -> TileMapLayer:
	var world: Node = Global.world_node
	if world != null:
		var ground: TileMapLayer = world.get_node_or_null("Ground") as TileMapLayer
		if ground != null:
			return ground
	return null

func _exit_tree() -> void:
	# Clean up signal connection
	if _day_connected and Global.day_started.is_connected(_on_day_started):
		Global.day_started.disconnect(_on_day_started)
	# Release attack claim if this fish was the attacker
	HeadlessFishAI._force_release_claim()

# Called by world.gd's distance check. A zone change re-arms the budget; while
# in a zone the fish counts down and despawns (never teleports).
func _apply_despawn_zone(zone: int, elapsed: float) -> void:
	if zone != _despawn_zone:
		_despawn_zone = zone
		_despawn_remaining = float(ZONE_DESPAWN_TIME.get(zone, 300.0))
		return
	_despawn_remaining -= elapsed
	if _despawn_remaining <= 0.0:
		queue_free()

func _on_day_started() -> void:
	# Despawn when daytime begins
	if is_instance_valid(self):
		queue_free()

func _physics_process(delta: float) -> void:
	z_index = int(global_position.y / 32)

	# PASSIVE flee: fly away from whoever hit us (never teleports).
	if _flee.tick(delta, global_position, COMBAT_DATA.flee_safe_dist):
		velocity = _flee.direction(global_position) \
			* COMBAT_DATA.speed * COMBAT_DATA.flee_speed_mult + _knockback
		_knockback = _knockback.move_toward(Vector2.ZERO, KNOCKBACK_DECAY * delta)
		move_and_slide()
		if velocity.length_squared() > 0.01:
			_last_move_dir = velocity.normalized()
			_sprite.rotation = lerp_angle(_sprite.rotation, velocity.angle(), 0.35)
		return

	# Player-death dispersal overrides AI movement
	if _is_dispersing:
		_disperse_timer -= delta
		if _disperse_timer <= 0.0:
			_is_dispersing = false
		else:
			velocity = _disperse_direction * DISPERSE_SPEED
			velocity += _knockback
			_knockback = _knockback.move_toward(Vector2.ZERO, KNOCKBACK_DECAY * delta)
			move_and_slide()
			if velocity.length_squared() > 0.01:
				_last_move_dir = velocity.normalized()
				_sprite.rotation = lerp_angle(_sprite.rotation, velocity.angle(), 0.35)
			return

	if _ai != null:
		velocity = _ai.call("physics_update", self, COMBAT_DATA.speed, _tilemap, delta)
	velocity += _knockback
	_knockback = _knockback.move_toward(Vector2.ZERO, KNOCKBACK_DECAY * delta)
	move_and_slide()

	# Rotate sprite toward movement direction
	if velocity.length_squared() > 0.01:
		_last_move_dir = velocity.normalized()
		_sprite.rotation = lerp_angle(_sprite.rotation, velocity.angle(), 0.35)

	if _last_damage_ms > 0 and Time.get_ticks_msec() - _last_damage_ms < HP_BAR_SHOW_MS:
		queue_redraw()

	_try_attack_player(delta)

# ── Contact attack ────────────────────────────────────────────────

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
	var p: Node2D = Global.player_node as Node2D
	if p == null or _attack_cooldown > 0.0:
		return
	# Provoked by a combat LUA → the LUA is the target, not the player.
	if combat_target() != p:
		return
	if global_position.distance_to(p.global_position) > ATTACK_RANGE:
		return
	_attack_cooldown = ATTACK_COOLDOWN
	Global.damage_player(COMBAT_DATA.damage, global_position, _last_move_dir)
	_show_name_label()

# ── Sword hit ─────────────────────────────────────────────────────

func take_hit(damage: float, source_pos: Vector2, apply_knockback: bool = true) -> void:
	if damage <= 0.0:
		return
	damage = COMBAT_DATA.damage_taken(damage)
	_mob_health = maxf(0.0, _mob_health - damage)
	_last_damage_ms = Time.get_ticks_msec()
	var away: Vector2 = global_position - source_pos
	if away.length_squared() > 0.001:
		away = away.normalized()
	if not COMBAT_DATA.is_boss and apply_knockback:
		_knockback += away * (60.0 + damage * 6.0)
	modulate = Color(1.0, 0.4, 0.4, 1.0)
	if _sprite != null:
		var tw := create_tween()
		tw.tween_interval(1.0)
		tw.tween_callback(_reset_hit_flash)
	_spawn_damage_number(damage)
	_show_name_label()
	_maybe_flee(source_pos)
	queue_redraw()
	if _mob_health <= 0.0:
		_die()

# PASSIVE mobs run from the attacker (see FleeBehavior); HOSTILE mobs fight on.
func _maybe_flee(source_pos: Vector2) -> void:
	if COMBAT_DATA.behavior != MobCombatData.Behavior.PASSIVE:
		return
	if COMBAT_DATA.flee_health_pct > 0.0 \
			and _mob_health > COMBAT_DATA.health * COMBAT_DATA.flee_health_pct:
		return
	_flee.start(source_pos, COMBAT_DATA.flee_duration)

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

# ── Health bar ────────────────────────────────────────────────────

var _last_damage_ms: int = -1
const HP_BAR_SHOW_MS: float = 3000.0
const HP_BAR_W: float = 30.0
const HP_BAR_H: float = 4.0
const HP_BAR_Y: float = -24.0

func _draw() -> void:
	if _last_damage_ms < 0:
		return
	if Time.get_ticks_msec() - _last_damage_ms > HP_BAR_SHOW_MS:
		return
	if _mob_health >= COMBAT_DATA.health:
		return
	var frac: float = clampf(_mob_health / COMBAT_DATA.health, 0.0, 1.0)
	var w := HP_BAR_W
	var h := HP_BAR_H
	draw_rect(Rect2(-w * 0.5, HP_BAR_Y, w, h), Color(0.05, 0.05, 0.08, 0.85))
	draw_rect(Rect2(-w * 0.5, HP_BAR_Y, w * frac, h), Color(0.85, 0.25, 0.25, 1.0))

# ── Death ─────────────────────────────────────────────────────────

func _die() -> void:
	if _death_processed:
		return
	_death_processed = true
	var world: Node = Global.world_node
	if is_instance_valid(world) and world.has_method("notify_mob_killed"):
		world.call("notify_mob_killed", self)
	HeadlessFishAI._force_release_claim()
	Global.add_mission_progress("side_headless_angler", 1)
	_drop_fish()
	_spawn_death_burst()
	queue_free()

# One raw fish per successful defeat, chosen from the existing fishing pool.
# Despawn/day cleanup paths call queue_free() directly, so they never reach
# this function (and never award loot).
func _drop_fish() -> void:
	var parent: Node = get_parent()
	if parent == null or not is_instance_valid(parent):
		return
	var fish: ItemData = FISH_ITEMS[randi() % FISH_ITEMS.size()] as ItemData
	var drop: Node = DROP_ITEM_SCENE.instantiate()
	if drop == null or fish == null:
		return
	drop.set("item_data", fish)
	drop.set("quantity", 1)
	parent.add_child(drop)
	if drop is Node2D:
		(drop as Node2D).global_position = global_position + Vector2(0.0, -6.0)

func _spawn_death_burst() -> void:
	var b: Node2D = MELLOW_BURST_SCRIPT.new() as Node2D
	if b == null:
		return
	b.position = global_position
	get_parent().add_child(b)

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

func _build_frames() -> SpriteFrames:
	var sf := SpriteFrames.new()
	sf.remove_animation("default")
	sf.add_animation("swim")
	sf.set_animation_speed("swim", 6.0)
	sf.set_animation_loop("swim", true)
	for i in range(FRAME_COUNT):
		var atlas := AtlasTexture.new()
		atlas.atlas  = FISH_TEX
		atlas.region = Rect2(i * FRAME_W, 0, FRAME_W, FRAME_H)
		sf.add_frame("swim", atlas)
	return sf
