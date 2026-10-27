extends CharacterBody2D
class_name BestiaryMob

# ── Bestiary mob actor ───────────────────────────────────────────────
# Shared runtime for the creatures added with the Bestiary update. A single
# actor script keeps four-direction animation, contact combat, flight/ground
# movement, drops, discovery metadata and death handling consistent across all
# eight resources. The mob-specific values live in MobCombatData + the scene.
#
# Sheet layout produced by build_directional_mob_sheets.py:
#   rows: south, north, east, west
#   cols: idle + four walk frames
# The texture is sliced into AtlasTexture frames at runtime, so the game ships
# one PNG per creature rather than dozens of per-frame files. The loader still
# accepts the older idle + two-walk-frame layout if a stale sheet is imported.

signal died

const AI_SCRIPTS: Dictionary = {
	"WOLF": preload("res://scripts/AI/WOLF.gd"),
	"WANDER": preload("res://scripts/AI/WANDER.gd"),
	"PIXIE": preload("res://scripts/AI/PIXIE.gd"),
}

const DIR_VECTORS: Dictionary = {
	"south": Vector2.DOWN,
	"north": Vector2.UP,
	"east": Vector2.RIGHT,
	"west": Vector2.LEFT,
}
const DIR_ROWS: Array = ["south", "north", "east", "west"]

const SHADOW_TEXTURE: Texture2D = preload("res://sprites/shadow/shadow_base.png")
const DAMAGE_NUMBER_SCRIPT: GDScript = preload("res://scripts/damage_number.gd")
const MELLOW_BURST_SCRIPT: GDScript = preload("res://scripts/mellow_burst.gd")
const MOB_NAME_LABEL_SCRIPT: GDScript = preload("res://scripts/mob_name_label.gd")
const DROP_ITEM_SCENE: PackedScene = preload("res://scenes/ui/InventoryItem.tscn")

const ATTACK_COOLDOWN: float = 1.0
const KNOCKBACK_DECAY: float = 900.0
const HP_BAR_SHOW_MS: float = 3000.0
const HP_BAR_W: float = 30.0
const HP_BAR_H: float = 4.0
const PROVOKE_LEASH_PX: float = 420.0

# ── Inspector contract ───────────────────────────────────────────────
# COMBAT_DATA is intentionally uppercase like the existing mobs: Global's
# is_hostile_mob() and safe-zone code already duck-type that property.
@export var COMBAT_DATA: MobCombatData = null
@export_file("*.png") var sprite_sheet_path: String = ""
@export var sprite_frame_size: Vector2i = Vector2i(32, 32)
@export var visual_scale: float = 1.0
@export var sprite_offset: Vector2 = Vector2.ZERO
@export var collision_size: Vector2 = Vector2(16, 12)
@export var collision_offset: Vector2 = Vector2(0, 5)
@export var shadow_offset: Vector2 = Vector2(0, 5)
@export var shadow_scale: Vector2 = Vector2(0.6, 0.3)
@export var shadow_alpha: float = 0.35
@export var avoid_water: bool = true
@export var is_floating: bool = false
@export var separation_distance: float = 26.0
@export var separation_strength: float = 40.0

@onready var _sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var _collision: CollisionShape2D = $CollisionShape2D

var _max_health: float = 0.0
var _mob_health: float = 0.0
var _knockback: Vector2 = Vector2.ZERO
var _attack_cooldown: float = 0.0
var _last_damage_ms: int = -1
var _dead: bool = false
var _facing: String = "south"
var _name_label: Node2D = null
var _water_layer: TileMapLayer = null
var _ai: RefCounted = null
var _flee: FleeBehavior = FleeBehavior.new()
var _provoked_by: Node2D = null

var _despawn_zone: int = -1
var _despawn_remaining: float = 0.0
enum DespawnZone { INNER, SAFE, OUTER }
const ZONE_DESPAWN_TIME := {
	DespawnZone.INNER: 1800.0,
	DespawnZone.SAFE: 900.0,
	DespawnZone.OUTER: 300.0,
}

var _is_dispersing: bool = false
var _disperse_timer: float = 0.0
var _disperse_direction: Vector2 = Vector2.ZERO
const DISPERSE_DURATION: float = 2.0
const DISPERSE_SPEED: float = 80.0
const DISPERSE_RANDOMNESS: float = 0.4
const SPAWN_CLEAR_RADIUS: float = 20.0 * 32.0
const SPAWN_CLEAR_DURATION: float = 5.0

static var _frames_cache: Dictionary = {}

func _ready() -> void:
	if COMBAT_DATA == null:
		push_error("BestiaryMob: missing COMBAT_DATA")
		queue_free()
		return
	add_to_group("Mob")
	if COMBAT_DATA.behavior == MobCombatData.Behavior.HOSTILE:
		add_to_group("HostileMob")
	var parent := get_parent()
	if parent != null and parent.has_method("grid_to_world"):
		add_to_group("DungeonHostile")
	if not COMBAT_DATA.bestiary_id.is_empty():
		add_to_group("Bestiary_" + COMBAT_DATA.bestiary_id)
		set_meta("bestiary_id", COMBAT_DATA.bestiary_id)

	_max_health = COMBAT_DATA.health
	_mob_health = _max_health
	motion_mode = CharacterBody2D.MOTION_MODE_FLOATING if is_floating \
		else CharacterBody2D.MOTION_MODE_GROUNDED
	z_index = _sort_index()

	_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_sprite.scale = Vector2.ONE * visual_scale
	_sprite.offset = sprite_offset * visual_scale
	_sprite.sprite_frames = _get_frames()
	_sprite.play("idle_south")
	_configure_collision()

	# The shadow rides under the actor and scales with its visual size. The
	# y-sort uses feet, not the texture centre.
	add_child(Global.make_shadow_sprite(
		SHADOW_TEXTURE, shadow_offset * visual_scale,
		shadow_scale * visual_scale, shadow_alpha))
	_add_name_label()

	_water_layer = get_parent().get_node_or_null("Water") as TileMapLayer
	var ai_script: Script = AI_SCRIPTS.get(COMBAT_DATA.ai_type)
	if ai_script != null:
		_ai = ai_script.new()
	Global.player_died.connect(_on_player_died)
	Global.player_spawned.connect(_on_player_spawned)

func _sort_index() -> int:
	var feet: float = collision_offset.y + collision_size.y * 0.5
	return int((global_position.y + feet * visual_scale + 16.0) / 32.0)

func _configure_collision() -> void:
	if _collision == null:
		return
	var rect: RectangleShape2D = _collision.shape as RectangleShape2D
	if rect == null:
		rect = RectangleShape2D.new()
		_collision.shape = rect
	rect.size = collision_size * visual_scale
	_collision.position = collision_offset * visual_scale

func _physics_process(delta: float) -> void:
	if _dead:
		return
	z_index = _sort_index()

	# PASSIVE creatures run from the attacker. Hostile creatures fight on.
	if COMBAT_DATA.behavior == MobCombatData.Behavior.PASSIVE \
			and _flee.tick(delta, global_position, COMBAT_DATA.flee_safe_dist):
		velocity = _flee.direction(global_position) \
			* COMBAT_DATA.speed * COMBAT_DATA.flee_speed_mult + _knockback
		_knockback = _knockback.move_toward(Vector2.ZERO, KNOCKBACK_DECAY * delta)
		_move_and_animate(delta)
		return

	if _is_dispersing:
		_disperse_timer -= delta
		if _disperse_timer <= 0.0:
			_is_dispersing = false
		else:
			velocity = _disperse_direction * DISPERSE_SPEED + _knockback
			_knockback = _knockback.move_toward(Vector2.ZERO, KNOCKBACK_DECAY * delta)
			_move_and_animate(delta)
			return

	if _ai != null:
		velocity = _ai.call("physics_update", self, COMBAT_DATA.speed, _water_layer, delta)
	velocity += _apply_separation()
	velocity += _knockback
	_knockback = _knockback.move_toward(Vector2.ZERO, KNOCKBACK_DECAY * delta)
	_move_and_animate(delta)
	if _last_damage_ms > 0 and Time.get_ticks_msec() - _last_damage_ms < HP_BAR_SHOW_MS:
		queue_redraw()
	_try_attack_player(delta)

func _move_and_animate(delta: float) -> void:
	if avoid_water:
		_clamp_velocity_for_water(delta)
	if velocity.length_squared() > 0.01:
		_facing = _direction_from_vec(velocity)
		_play("walk_" + _facing)
		move_and_slide()
	else:
		_play("idle_" + _facing)

func _direction_from_vec(vec: Vector2) -> String:
	if absf(vec.x) >= absf(vec.y):
		return "east" if vec.x >= 0.0 else "west"
	return "south" if vec.y >= 0.0 else "north"

func _play(anim: String) -> void:
	if _sprite == null or _sprite.sprite_frames == null:
		return
	if _sprite.sprite_frames.has_animation(anim) and _sprite.animation != anim:
		_sprite.play(anim)

# ── Contact damage ───────────────────────────────────────────────────
func _try_attack_player(delta: float) -> void:
	if COMBAT_DATA.damage <= 1.0:
		return
	_attack_cooldown = maxf(0.0, _attack_cooldown - delta)
	var p: Node2D = Global.player_node as Node2D
	if p == null or _attack_cooldown > 0.0:
		return
	if combat_target() != p:
		return
	var reach: float = maxf(28.0, collision_size.x * visual_scale + 10.0)
	if global_position.distance_to(p.global_position) > reach:
		return
	_attack_cooldown = ATTACK_COOLDOWN
	Global.damage_player(COMBAT_DATA.damage, global_position, facing_vector())
	_show_name_label()

# ── Sword / LUA / explosion damage ───────────────────────────────────
func take_hit(damage: float, source_pos: Vector2, apply_knockback: bool = true) -> void:
	if _dead or damage <= 0.0:
		return
	damage = COMBAT_DATA.damage_taken(damage)
	_mob_health = maxf(0.0, _mob_health - damage)
	_last_damage_ms = Time.get_ticks_msec()
	var away: Vector2 = global_position - source_pos
	if away.length_squared() > 0.001:
		away = away.normalized()
	if apply_knockback and not COMBAT_DATA.is_boss:
		_knockback += away * (60.0 + damage * 6.0)
	modulate = Color(1.0, 0.4, 0.4, 1.0)
	var tw := create_tween()
	tw.tween_interval(1.0)
	tw.tween_callback(_reset_hit_flash)
	_spawn_damage_number(damage)
	_show_name_label()
	_maybe_flee(source_pos)
	queue_redraw()
	if _mob_health <= 0.0:
		_die()

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
	n.position = global_position + Vector2(0.0, -sprite_frame_size.y * visual_scale * 0.55)
	get_parent().add_child(n)

# ── Provoked combat (LUA) ────────────────────────────────────────────
func provoke(node: Node2D) -> void:
	_provoked_by = node

func combat_target() -> Node2D:
	if _provoked_by != null and is_instance_valid(_provoked_by) and _provoked_by.is_inside_tree():
		if (_provoked_by as Node2D).global_position.distance_to(global_position) <= PROVOKE_LEASH_PX:
			return _provoked_by
	_provoked_by = null
	return Global.player_node as Node2D

func facing_vector() -> Vector2:
	return DIR_VECTORS.get(_facing, Vector2.DOWN) as Vector2

# ── Name + health bar ────────────────────────────────────────────────
func _add_name_label() -> void:
	_name_label = MOB_NAME_LABEL_SCRIPT.new() as Node2D
	if _name_label == null:
		return
	_name_label.set("mob_name", COMBAT_DATA.mob_name)
	_name_label.set("vertical_offset",
		-sprite_frame_size.y * visual_scale * 0.5 - 10.0)
	add_child(_name_label)

func _show_name_label() -> void:
	if _name_label != null:
		_name_label.call("flash")

func _draw() -> void:
	if _last_damage_ms < 0:
		return
	if Time.get_ticks_msec() - _last_damage_ms > HP_BAR_SHOW_MS:
		return
	if _mob_health >= _max_health:
		return
	var frac: float = clampf(_mob_health / maxf(1.0, _max_health), 0.0, 1.0)
	var w: float = HP_BAR_W * visual_scale
	var h: float = HP_BAR_H * visual_scale
	var y: float = -sprite_frame_size.y * visual_scale * 0.5 - 7.0
	draw_rect(Rect2(-w * 0.5, y, w, h), Color(0.05, 0.05, 0.08, 0.85))
	draw_rect(Rect2(-w * 0.5, y, w * frac, h), Color(0.85, 0.25, 0.25, 1.0))

# ── Death, loot and Bestiary ─────────────────────────────────────────
func _die() -> void:
	if _dead:
		return
	_dead = true
	if not COMBAT_DATA.bestiary_id.is_empty():
		Global.bestiary_record_kill(COMBAT_DATA.bestiary_id)
	_drop_loot()
	_spawn_death_burst()
	died.emit()
	queue_free()

func _drop_loot() -> void:
	var parent: Node = get_parent()
	if parent == null or not is_instance_valid(parent):
		return
	for entry_value in COMBAT_DATA.drops:
		if not (entry_value is Dictionary):
			continue
		var entry: Dictionary = entry_value as Dictionary
		var chance: float = clampf(float(entry.get("chance", 1.0)), 0.0, 1.0)
		if chance < 1.0 and randf() > chance:
			continue
		var path: String = str(entry.get("item_path", "")).strip_edges()
		if path.is_empty():
			continue
		var item: ItemData = load(path) as ItemData
		if item == null:
			continue
		var qty: int = randi_range(int(entry.get("min", 1)), int(entry.get("max", 1)))
		if qty <= 0:
			continue
		var drop: Node = DROP_ITEM_SCENE.instantiate()
		if drop == null:
			continue
		drop.set("item_data", item)
		drop.set("quantity", qty)
		parent.add_child(drop)
		if drop is Node2D:
			(drop as Node2D).global_position = global_position + Vector2(
				randf_range(-12.0, 12.0), randf_range(-9.0, 3.0))

func _spawn_death_burst() -> void:
	var b: Node2D = MELLOW_BURST_SCRIPT.new() as Node2D
	if b == null:
		return
	b.position = global_position
	get_parent().add_child(b)

# Safe-zone protection removes a hostile without kill credit, loot or Bestiary.
func safe_zone_disintegrate() -> void:
	_dead = true
	_spawn_death_burst()
	queue_free()

# ── Player death / respawn dispersal ────────────────────────────────
func _on_player_died(death_position: Vector2) -> void:
	if _dead:
		return
	var away: Vector2 = global_position - death_position
	if away.length_squared() < 1.0:
		away = Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0))
	_disperse_direction = away.normalized().rotated(
		randf_range(-DISPERSE_RANDOMNESS, DISPERSE_RANDOMNESS))
	_disperse_timer = DISPERSE_DURATION
	_is_dispersing = true

func _on_player_spawned(spawn_position: Vector2) -> void:
	if _dead:
		return
	if global_position.distance_to(spawn_position) > SPAWN_CLEAR_RADIUS:
		return
	var away: Vector2 = global_position - spawn_position
	if away.length_squared() < 1.0:
		away = Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0))
	_disperse_direction = away.normalized().rotated(
		randf_range(-DISPERSE_RANDOMNESS, DISPERSE_RANDOMNESS))
	_disperse_timer = SPAWN_CLEAR_DURATION
	_is_dispersing = true

# ── Water veto for ground creatures ─────────────────────────────────
func _clamp_velocity_for_water(delta: float) -> void:
	if _water_layer == null or not is_instance_valid(_water_layer):
		return
	var half_w: float = collision_size.x * visual_scale * 0.5
	var half_h: float = collision_size.y * visual_scale * 0.5
	var oy: float = collision_offset.y * visual_scale
	if _water_at(global_position + Vector2(0.0, oy)):
		return
	if velocity.x != 0.0:
		var lead_x: float = global_position.x + velocity.x * delta + sign(velocity.x) * half_w
		var cy: float = global_position.y + oy
		if _water_at(Vector2(lead_x, cy - half_h)) \
				or _water_at(Vector2(lead_x, cy)) \
				or _water_at(Vector2(lead_x, cy + half_h)):
			velocity.x = 0.0
	if velocity.y != 0.0:
		var lead_y: float = global_position.y + oy + velocity.y * delta + sign(velocity.y) * half_h
		var cx: float = global_position.x
		if _water_at(Vector2(cx - half_w, lead_y)) \
				or _water_at(Vector2(cx, lead_y)) \
				or _water_at(Vector2(cx + half_w, lead_y)):
			velocity.y = 0.0

func _water_at(global_pt: Vector2) -> bool:
	if _water_layer == null or not is_instance_valid(_water_layer):
		return false
	var tc: Vector2i = _water_layer.local_to_map(_water_layer.to_local(global_pt))
	return _water_layer.get_cell_source_id(tc) != -1

# ── Separation ──────────────────────────────────────────────────────
func _apply_separation() -> Vector2:
	if separation_distance <= 0.0 or COMBAT_DATA.bestiary_id.is_empty():
		return Vector2.ZERO
	var group: String = "Bestiary_" + COMBAT_DATA.bestiary_id
	var force: Vector2 = Vector2.ZERO
	for node in get_tree().get_nodes_in_group(group):
		if node == self or not (node is Node2D):
			continue
		var d: Vector2 = global_position - (node as Node2D).global_position
		var dist: float = d.length()
		if dist < separation_distance and dist > 0.001:
			force += d / dist * (1.0 - dist / separation_distance)
	if force.length_squared() > 0.001:
		return force.normalized() * separation_strength
	return Vector2.ZERO

# ── Despawn zone (overworld ambient director) ───────────────────────
func _apply_despawn_zone(zone: int, elapsed: float) -> void:
	if zone != _despawn_zone:
		_despawn_zone = zone
		_despawn_remaining = ZONE_DESPAWN_TIME[zone]
		return
	_despawn_remaining -= elapsed
	if _despawn_remaining <= 0.0:
		queue_free()

# ── Four-direction SpriteFrames ─────────────────────────────────────
func _get_frames() -> SpriteFrames:
	var key: String = "%s|%s" % [sprite_sheet_path, sprite_frame_size]
	if _frames_cache.has(key):
		return _frames_cache[key] as SpriteFrames
	var sheet: Texture2D = load(sprite_sheet_path) as Texture2D
	if sheet == null:
		push_error("BestiaryMob: missing sprite sheet %s" % sprite_sheet_path)
		return SpriteFrames.new()
	var fw: int = maxi(1, sprite_frame_size.x)
	var fh: int = maxi(1, sprite_frame_size.y)
	var sheet_cols: int = maxi(2, int(sheet.get_width() / fw))
	var sf := SpriteFrames.new()
	sf.remove_animation("default")
	for row in range(DIR_ROWS.size()):
		var dir: String = str(DIR_ROWS[row])
		var idle := "idle_" + dir
		var walk := "walk_" + dir
		sf.add_animation(idle)
		sf.set_animation_speed(idle, 1.0)
		sf.set_animation_loop(idle, false)
		sf.add_frame(idle, _atlas(sheet, 0, row, fw, fh))
		sf.add_animation(walk)
		# Five-column sheets carry an idle + four walk frames. Keep reading the
		# old three-column sheets (idle + two frames) so a partially imported
		# build still animates instead of failing.
		sf.set_animation_speed(walk, 9.0 if sheet_cols >= 5 else 7.0)
		sf.set_animation_loop(walk, true)
		for col in range(1, sheet_cols):
			sf.add_frame(walk, _atlas(sheet, col, row, fw, fh))
	_frames_cache[key] = sf
	return sf

func _atlas(sheet: Texture2D, col: int, row: int, fw: int, fh: int) -> AtlasTexture:
	var at := AtlasTexture.new()
	at.atlas = sheet
	at.region = Rect2(col * fw, row * fh, fw, fh)
	return at
