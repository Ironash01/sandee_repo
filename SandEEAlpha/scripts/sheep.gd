extends CharacterBody2D

const COMBAT_DATA: MobCombatData = preload("res://resources/mobs/sheep.tres")

# ai_type -> AI script dispatch. Only "WOLF" exists today; add new entries
# here as new AI types get built under scripts/AI/.
const AI_SCRIPTS: Dictionary = {
	"WOLF": preload("res://scripts/AI/WOLF.gd"),
}

# Mobs with damage > 1 hit the player on proximity contact (see _try_attack_player).
const ATTACK_RANGE:    float = 24.0
const ATTACK_COOLDOWN: float = 1.0

# ── Loot ───────────────────────────────────────────────────────────
# Wolves are SandEE's canines, so they are the Dog Meat source: every kill
# yields 1, with independent chance rolls for a 2nd and 3rd.
const SHEEP_MEAT_ITEM: ItemData = preload("res://resources/items/sheep_meat.tres")
const DROP_ITEM_SCENE: PackedScene = preload("res://scenes/ui/InventoryItem.tscn")
const WHITE_FUR_ITEM: ItemData = preload("res://resources/items/white_fur.tres")

# ── Separation ─────────────────────────────────────────────────────
# Wolves don't physically collide with each other (different physics layers),
# so chasing ones would stack on the same pixel. A soft separation force
# spreads wolves apart — but it does NOT repel from the player, so the player
# can't push mobs around (they pass through instead).
const SEPARATION_DIST:     float = 26.0
const SEPARATION_STRENGTH: float = 40.0

var _ai:               RefCounted = null
var _attack_cooldown:  float      = 0.0

# ── Player-death dispersal ────────────────────────────────────────
# When the player dies, active wolves scatter outward from the death
# position for a short duration before resuming normal behavior.
var _is_dispersing:     bool    = false
# PASSIVE flee-on-hit (see FleeBehavior); HOSTILE mobs never use it.
var _flee: FleeBehavior = FleeBehavior.new()
var _disperse_timer:    float   = 0.0
var _disperse_direction: Vector2 = Vector2.ZERO
const DISPERSE_DURATION: float = 2.0     # seconds to keep moving away
const DISPERSE_SPEED:    float = 80.0    # px/s while dispersing
const DISPERSE_RANDOMNESS: float = 0.4   # angle spread (radians)
# Spawn clearing: when the player (re)spawns, mobs within this radius of the
# spawn point flee for SPAWN_CLEAR_DURATION so the player can react.
const SPAWN_CLEAR_RADIUS:   float = 20.0 * 32.0
const SPAWN_CLEAR_DURATION: float = 5.0

# ── Combat (sword hits) ────────────────────────────────────────────
# Tracks remaining HP from COMBAT_DATA.health; a sword hit calls take_hit()
# which reduces HP and knocks the wolf back (unless it's a boss).
var _mob_health:   float  = 0.0
var _knockback:    Vector2 = Vector2.ZERO
const KNOCKBACK_DECAY: float = 900.0   # px/s of knockback velocity lost per second

const DIRS: Array = [
	{"name": "south",      "vec": Vector2( 0,  1)},
	{"name": "north",      "vec": Vector2( 0, -1)},
	{"name": "east",       "vec": Vector2( 1,  0)},
	{"name": "west",       "vec": Vector2(-1,  0)},
	{"name": "south-east", "vec": Vector2( 1,  1)},
	{"name": "south-west", "vec": Vector2(-1,  1)},
	{"name": "north-east", "vec": Vector2( 1, -1)},
	{"name": "north-west", "vec": Vector2(-1, -1)},
]

const SPRITE_BASE: String = "res://sprites/mobs/sheep"
# The sheep art ships 2 walk frames per direction (the wolf ships 8), so the
# loader must not probe frame_002..007 — that only spams "resource not found".
const SHEEP_WALK_FRAMES: int = 4
const SHADOW_TEXTURE: Texture2D = preload("res://sprites/shadow/shadow_base.png")
const DAMAGE_NUMBER_SCRIPT: GDScript = preload("res://scripts/damage_number.gd")
const MELLOW_BURST_SCRIPT: GDScript = preload("res://scripts/mellow_burst.gd")
const MOB_NAME_LABEL_SCRIPT: GDScript = preload("res://scripts/mob_name_label.gd")

# ── Feet-anchored y-sort ────────────────────────────────────────────
# The wolf sprite is centred on its origin with the feet ~11px below it, so
# sorting by raw y put the wolf ~11px too high — it drew BEHIND blocks it was
# actually standing south of (reading as "walking through" them). These mirror
# player.gd's YSORT_FEET_OFFSET/YSORT_TIEBREAK convention so mobs and the
# player sort consistently against blocks/trees/each other.
const YSORT_FEET_OFFSET: float = 11.0
const YSORT_TIEBREAK:    float = 16.0

# ── Water veto ─────────────────────────────────────────────────────
# A wolf must never end up in (or cross) water. WolfAI's own wander check only
# samples ONE point ~2px ahead of the wolf's centre and only guards the AI's
# walk direction — so the soft separation force and the sword KNOCKBACK were
# free to shove wolves into a lake and straight across it. This veto clamps the
# FINAL velocity per axis (mirroring player.gd's _clamp_velocity_for_water), so
# the wolf slides along the shoreline instead of sticking, and NO movement
# source can bypass it.
# Sample points mirror Wolf.tscn's body: a 16x12 rect at y +5.
const WATER_HALF_W: float = 8.0
const WATER_HALF_H: float = 6.0
const WATER_OY:     float = 5.0

var _last_dir: String = "south"
var _name_label: Node2D = null

@onready var _sprite: AnimatedSprite2D = $AnimatedSprite2D
var _water_layer: TileMapLayer = null

# Shared across every Wolf instance — built once on first spawn instead of
# per-instance, since world-gen can spawn dozens of wolves with identical frames.
static var _shared_frames: SpriteFrames = null

# ── Despawn zone (driven by world.gd's periodic distance check) ──────
enum DespawnZone { INNER, SAFE, OUTER }
const ZONE_DESPAWN_TIME := {
	DespawnZone.INNER: 1800.0,  # 30 min — within 100 blocks of player or world spawn
	DespawnZone.SAFE:  900.0,   # 15 min — within 200 blocks of player or world spawn
	DespawnZone.OUTER: 300.0,   # 5 min  — beyond 200 blocks of both
}
var _despawn_zone: int = -1
var _despawn_remaining: float = 0.0

# Called by world.gd on a periodic tick with the current zone and how much
# time elapsed since the last check. Crossing into a different zone resets
# the countdown to that zone's full duration — no carry-over between zones.
func _apply_despawn_zone(zone: int, elapsed: float) -> void:
	if zone != _despawn_zone:
		_despawn_zone      = zone
		_despawn_remaining = ZONE_DESPAWN_TIME[zone]
		return
	_despawn_remaining -= elapsed
	if _despawn_remaining <= 0.0:
		queue_free()

func _ready() -> void:
	add_to_group("Wolf")
	add_to_group("Mob")
	_mob_health = COMBAT_DATA.health
	# Same quantized y-sort convention as trees/grass/placed blocks (all use
	# z_index = int(y / 32)); without this a mob is stuck at z_index 0 and
	# never sorts against the world — a wolf south of a tree or the player
	# would wrongly render underneath it. The player's own z boost keeps the
	# player on top regardless.
	z_index = int((global_position.y + YSORT_FEET_OFFSET + YSORT_TIEBREAK) / 32.0)
	if _shared_frames == null:
		_shared_frames = _build_frames()
	_sprite.sprite_frames = _shared_frames
	_sprite.play("idle_south")
	add_child(Global.make_shadow_sprite(SHADOW_TEXTURE, Vector2(0.0, 5.0), Vector2(0.6, 0.3), 0.35))
	_add_name_label()
	_water_layer = get_parent().get_node_or_null("Water") as TileMapLayer
	var ai_script: Script = AI_SCRIPTS.get(COMBAT_DATA.ai_type)
	if ai_script != null:
		_ai = ai_script.new()
	Global.player_died.connect(_on_player_died)
	Global.player_spawned.connect(_on_player_spawned)

func _physics_process(delta: float) -> void:
	z_index = int((global_position.y + YSORT_FEET_OFFSET + YSORT_TIEBREAK) / 32.0)

	# PASSIVE flee: run away from whoever hit us. Never teleports — it just
	# out-runs them, then resumes normal AI.
	if _flee.tick(delta, global_position, COMBAT_DATA.flee_safe_dist):
		velocity = _flee.direction(global_position) \
			* COMBAT_DATA.speed * COMBAT_DATA.flee_speed_mult + _knockback
		_knockback = _knockback.move_toward(Vector2.ZERO, KNOCKBACK_DECAY * delta)
		_move_with_water_veto(delta)
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
			_move_with_water_veto(delta)
			return

	if _ai != null:
		velocity = _ai.call("physics_update", self, COMBAT_DATA.speed, _water_layer, delta)
	velocity += _apply_separation()
	velocity += _knockback
	_knockback = _knockback.move_toward(Vector2.ZERO, KNOCKBACK_DECAY * delta)
	_move_with_water_veto(delta)
	if _last_damage_ms > 0 and Time.get_ticks_msec() - _last_damage_ms < HP_BAR_SHOW_MS:
		queue_redraw()
	_try_attack_player(delta)

# Mobs with damage > 1 hit the player on proximity contact, on a cooldown.
func _try_attack_player(delta: float) -> void:
	if COMBAT_DATA.damage <= 1.0:
		return
	_attack_cooldown = maxf(0.0, _attack_cooldown - delta)
	var p := Global.player_node as Node2D
	if p == null or _attack_cooldown > 0.0:
		return
	if global_position.distance_to(p.global_position) > ATTACK_RANGE:
		return
	_attack_cooldown = ATTACK_COOLDOWN
	Global.damage_player(COMBAT_DATA.damage, global_position, facing_vector())
	_show_name_label()

# ── Sword hit ────────────────────────────────────────────────────
# Called by the player's swing hitbox (see sword_swing_effect.gd) when the
# blade overlaps this mob. Reduces HP, knocks the wolf back from the hit
# origin (unless it's a boss), shows the red hit flash + floating damage
# number, and dies at 0 HP.
func take_hit(damage: float, source_pos: Vector2, apply_knockback: bool = true) -> void:
	if damage <= 0.0:
		return
	damage = COMBAT_DATA.damage_taken(damage)
	_mob_health = maxf(0.0, _mob_health - damage)
	_last_damage_ms = Time.get_ticks_msec()
	var away: Vector2 = global_position - source_pos
	if away.length_squared() > 0.001:
		away = away.normalized()
	# Bosses shrug off knockback; a caller may also suppress it entirely (a LUA
	# attacks with apply_knockback = false so its repeated hits never shove a mob
	# out of its own attack range and make it look sluggish).
	if not COMBAT_DATA.is_boss and apply_knockback:
		var strength: float = 60.0 + damage * 6.0
		_knockback += away * strength
	# Hit feedback: red flash for ~1s (Terraria-style), plus the floating
	# damage number above the head.
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

# ── Autohide health bar (Terraria-style) ──────────────────────────
# Shown above the mob while it's recently damaged and below full HP; fades
# out after HP_BAR_SHOW_MS. Drawn in _draw and refreshed via queue_redraw.
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

func _die() -> void:
	var world: Node = Global.world_node
	if is_instance_valid(world) and world.has_method("notify_mob_killed"):
		world.call("notify_mob_killed", self)
	pass  # sheep: no wolf mission
	_drop_sheep_loot()
	_spawn_death_burst()
	queue_free()

# Spawns 1-3 Dog Meat at the corpse. Spawns the drop scene directly rather than
# going through Global.drop_item(), which deliberately snaps drag-out drops to
# the tile in front of the player — wrong for loot.
func _drop_sheep_loot() -> void:
	var count: int = 1
	if randf() < 0.65:
		count += 1
	if randf() < 0.30:
		count += 1
	var parent: Node = get_parent()
	if parent == null or not is_instance_valid(parent):
		return
	var drop: Node = DROP_ITEM_SCENE.instantiate()
	if drop == null:
		return
	drop.set("item_data", SHEEP_MEAT_ITEM)
	drop.set("quantity", count)
	parent.add_child(drop)
	if drop is Node2D:
		(drop as Node2D).global_position = global_position + Vector2(0.0, -6.0)
	# Wool: White Fur doubles as sheep wool (50% per kill). Reused rather than
	# adding a duplicate "wool" material — the item already reads as white fur.
	if randf() < 0.5:
		var fur: Node = DROP_ITEM_SCENE.instantiate()
		if fur != null:
			fur.set("item_data", WHITE_FUR_ITEM)
			fur.set("quantity", 1)
			parent.add_child(fur)
			if fur is Node2D:
				(fur as Node2D).global_position = global_position + Vector2(randf_range(-5.0, 5.0), -2.0)

# Minecraft-style death poof: a burst of mellow puffs at the body's location,
# spawned as a sibling so it survives this mob's free.
func _spawn_death_burst() -> void:
	var b: Node2D = MELLOW_BURST_SCRIPT.new() as Node2D
	if b == null:
		return
	b.position = global_position
	get_parent().add_child(b)

# The direction the wolf is currently facing (its last movement direction),
# so knockback on the player reflects which side the hit came from.
func facing_vector() -> Vector2:
	for d in DIRS:
		if d["name"] == _last_dir:
			return (d["vec"] as Vector2).normalized()
	return Vector2.DOWN

# Soft push away from nearby wolves and (gently) from the player, so a chase
# doesn't turn into a pile-up on one pixel or right on top of the player.
func _apply_separation() -> Vector2:
	var force := Vector2.ZERO
	for node in get_tree().get_nodes_in_group("Wolf"):
		if node == self or not (node is Node2D):
			continue
		var d: Vector2 = global_position - (node as Node2D).global_position
		var dist: float = d.length()
		if dist < SEPARATION_DIST and dist > 0.001:
			force += d / dist * (1.0 - dist / SEPARATION_DIST)
	if force.length_squared() > 0.001:
		return force.normalized() * SEPARATION_STRENGTH
	return Vector2.ZERO

# Apply the water veto, then move. EVERY branch (flee / dispersal / AI) goes
# through this, so no code path can skip the check.
func _move_with_water_veto(delta: float) -> void:
	_clamp_velocity_for_water(delta)
	if velocity != Vector2.ZERO:
		_update_walk_anim(velocity)
		move_and_slide()
	else:
		_play_idle(_last_dir)

# Clamp velocity per axis so the wolf slides along a shoreline instead of
# sticking to it. The leading EDGE of the wolf's body is sampled (3 points per
# axis), so a diagonal can't clip a corner into the water either.
func _clamp_velocity_for_water(delta: float) -> void:
	if _water_layer == null or not is_instance_valid(_water_layer):
		return
	# Already in the water (spawned or pushed there by an older build): let it
	# walk OUT instead of freezing it against the shoreline forever.
	if _water_at(global_position + Vector2(0.0, WATER_OY)):
		return

	if velocity.x != 0.0:
		var sx: float = sign(velocity.x)
		var lead_x: float = global_position.x + velocity.x * delta + sx * WATER_HALF_W
		var cy: float = global_position.y + WATER_OY
		if _water_at(Vector2(lead_x, cy - WATER_HALF_H)) \
		or _water_at(Vector2(lead_x, cy)) \
		or _water_at(Vector2(lead_x, cy + WATER_HALF_H)):
			velocity.x = 0.0

	if velocity.y != 0.0:
		var sy: float = sign(velocity.y)
		var lead_y: float = global_position.y + WATER_OY + velocity.y * delta + sy * WATER_HALF_H
		var cx: float = global_position.x
		if _water_at(Vector2(cx - WATER_HALF_W, lead_y)) \
		or _water_at(Vector2(cx, lead_y)) \
		or _water_at(Vector2(cx + WATER_HALF_W, lead_y)):
			velocity.y = 0.0

func _water_at(global_pt: Vector2) -> bool:
	if _water_layer == null or not is_instance_valid(_water_layer):
		return false
	var tc: Vector2i = _water_layer.local_to_map(_water_layer.to_local(global_pt))
	return _water_layer.get_cell_source_id(tc) != -1

func _play_idle(dir: String) -> void:
	var anim := "idle_" + dir.replace("-", "_")
	if _sprite.sprite_frames != null and _sprite.sprite_frames.has_animation(anim) \
			and _sprite.animation != anim:
		_sprite.play(anim)

func _update_walk_anim(vec: Vector2) -> void:
	var best_dir: String = _last_dir
	var best_dot: float  = -INF
	var norm := vec.normalized()
	for d in DIRS:
		var dot: float = norm.dot((d["vec"] as Vector2).normalized())
		if dot > best_dot:
			best_dot = dot
			best_dir = d["name"]
	var anim := "walk_" + best_dir.replace("-", "_")
	if _sprite.sprite_frames != null and _sprite.sprite_frames.has_animation(anim) \
			and _sprite.animation != anim:
		_sprite.play(anim)
	_last_dir = best_dir

func _on_player_died(death_position: Vector2) -> void:
	if _mob_health <= 0.0:
		return
	var away: Vector2 = global_position - death_position
	if away.length_squared() < 1.0:
		away = Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0))
	away = away.normalized()
	# Add controlled random spread so wolves don't all flee in the same line
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

	for d in DIRS:
		var dir: String = d["name"]

		var walk_anim: String = "walk_" + dir.replace("-", "_")
		sf.add_animation(walk_anim)
		sf.set_animation_speed(walk_anim, 10.0)
		sf.set_animation_loop(walk_anim, true)
		for f in range(SHEEP_WALK_FRAMES):
			var path: String = "%s/animations/animation-1/%s/frame_%03d.png" % [SPRITE_BASE, dir, f]
			var tex: Texture2D = load(path) as Texture2D
			if tex != null:
				sf.add_frame(walk_anim, tex)

		var idle_anim: String = "idle_" + dir.replace("-", "_")
		sf.add_animation(idle_anim)
		sf.set_animation_speed(idle_anim, 1.0)
		sf.set_animation_loop(idle_anim, false)
		var idle_path: String = "%s/rotations/%s.png" % [SPRITE_BASE, dir]
		var idle_tex: Texture2D = load(idle_path) as Texture2D
		if idle_tex != null:
			sf.add_frame(idle_anim, idle_tex)

	return sf

