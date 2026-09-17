extends CharacterBody2D
class_name PixieMob

# ── Pixie mob (roams pixie caves, flies, attacks the player) ──────
# Follows the same shape as wolf.gd: a CombatData resource drives stats, an
# AI script (scripts/AI/PIXIE.gd) decides movement, and contact attacks go
# through Global.damage_player (which applies knockback to the player).
#
# The pixie is a flying bobbing sprite (sprites/mobs/pixie/pixie.png — a
# single 7-frame row of 64x64 cells), so unlike the wolf it has ONE looping
# "fly" animation instead of 8-directional walk/idle sets.

const COMBAT_DATA: MobCombatData = preload("res://resources/mobs/pixie.tres")

const AI_SCRIPTS: Dictionary = {
	"PIXIE": preload("res://scripts/AI/PIXIE.gd"),
}

const ATTACK_RANGE:    float = 30.0
const ATTACK_COOLDOWN: float = 1.0
const SHADOW_TEXTURE:  Texture2D = preload("res://sprites/shadow/shadow_base.png")
const DAMAGE_NUMBER_SCRIPT: GDScript = preload("res://scripts/damage_number.gd")
const MELLOW_BURST_SCRIPT: GDScript = preload("res://scripts/mellow_burst.gd")
const MOB_NAME_LABEL_SCRIPT: GDScript = preload("res://scripts/mob_name_label.gd")

const PIXIE_TEX:    Texture2D = preload("res://sprites/mobs/pixie/pixie.png")
const FRAME_COUNT:  int = 7
const FRAME_SIZE:   int = 64
const SPRITE_SCALE: float = 0.5  # 64px frames -> ~32px on screen

# ── Pulsating glow ─────────────────────────────────────────────────
# A soft PointLight2D hugging the pixie (blooms through the cave's glow
# environment). Energy pulses with a sine so the pixie visibly "breathes".
const GLOW_COLOR:         Color = Color(1.0, 0.65, 0.9)  # mystical pink-violet
const GLOW_ENERGY_BASE:   float = 1.2
const GLOW_ENERGY_AMP:    float = 0.5
const GLOW_BLINK_SPEED:   float = 2.5
const GLOW_TEXTURE_SCALE: float = 0.35  # ~90px light pool around a 32px pixie

var _glow:      PointLight2D = null
var _glow_time: float        = 0.0

# ── Combat (sword hits) ────────────────────────────────────────────
var _mob_health:   float  = 0.0
var _knockback:    Vector2 = Vector2.ZERO
const KNOCKBACK_DECAY: float = 900.0   # px/s of knockback velocity lost per second

# ── Separation ─────────────────────────────────────────────────────
# Mobs don't physically collide with each other (different physics layers), so
# chasing ones would pile up on the same pixel. A soft separation force spreads
# pixies apart — but it does NOT repel from the player, so the player can't
# push mobs around (they pass through instead).
const SEPARATION_DIST:     float = 22.0
const SEPARATION_STRENGTH: float = 45.0

var _ai:              RefCounted = null
var _attack_cooldown: float      = 0.0
var _tilemap:         TileMapLayer = null
var _name_label:      Node2D = null

# ── Player-death dispersal ────────────────────────────────────────
var _is_dispersing:     bool    = false
var _disperse_timer:    float   = 0.0
var _disperse_direction: Vector2 = Vector2.ZERO
const DISPERSE_DURATION: float = 2.0
const DISPERSE_SPEED:    float = 80.0
const DISPERSE_RANDOMNESS: float = 0.4

@onready var _sprite: AnimatedSprite2D = $AnimatedSprite2D

func _ready() -> void:
	add_to_group("Pixie")
	add_to_group("Mob")
	_mob_health = COMBAT_DATA.health
	# Same quantized y-sort convention as every world-facing node.
	z_index = int(global_position.y / 32)
	_sprite.scale = Vector2(SPRITE_SCALE, SPRITE_SCALE)
	# NEAREST (pixel-art) filtering stops adjacent frames of the 64x64 sheet
	# from bleeding through when the sprite rotates — the source of the
	# "double sprite" look on direction changes.
	_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_sprite.sprite_frames = _build_frames()
	_sprite.play("fly")
	add_child(Global.make_shadow_sprite(SHADOW_TEXTURE, Vector2(0.0, 5.0), Vector2(0.6, 0.3), 0.35))
	_add_name_label()
	_add_glow()
	_tilemap = get_parent().get_node_or_null("PixieCaveTiles") as TileMapLayer
	var ai_script: Script = AI_SCRIPTS.get(COMBAT_DATA.ai_type)
	if ai_script != null:
		_ai = ai_script.new()
	Global.player_died.connect(_on_player_died)

func _process(delta: float) -> void:
	if _glow == null:
		return
	_glow_time += delta
	_glow.energy = GLOW_ENERGY_BASE + sin(_glow_time * GLOW_BLINK_SPEED) * GLOW_ENERGY_AMP

# Soft pulsing glow — the light is a child, so it rides along with the pixie.
func _add_glow() -> void:
	_glow = PointLight2D.new()
	_glow.texture       = _get_glow_texture()
	_glow.texture_scale = GLOW_TEXTURE_SCALE
	_glow.energy        = GLOW_ENERGY_BASE
	_glow.color         = GLOW_COLOR
	add_child(_glow)

# Soft push away from nearby pixies and (gently) from the player, so a chase
# doesn't turn into a pile-up on one pixel or right on top of the player.
func _apply_separation() -> Vector2:
	var force := Vector2.ZERO
	for node in get_tree().get_nodes_in_group("Pixie"):
		if node == self or not (node is Node2D):
			continue
		var d: Vector2 = global_position - (node as Node2D).global_position
		var dist: float = d.length()
		if dist < SEPARATION_DIST and dist > 0.001:
			force += d / dist * (1.0 - dist / SEPARATION_DIST)
	if force.length_squared() > 0.001:
		return force.normalized() * SEPARATION_STRENGTH
	return Vector2.ZERO

# Circular (radial-gradient) light texture — the pixelated "stepped band" one
# reads as a square around the pixie, so it uses the smooth circular gradient.
static func _get_glow_texture() -> Texture2D:
	return Global.get_smooth_light_texture(256)

var _last_move_dir: Vector2 = Vector2.DOWN  # last non-zero flying direction (knockback facing)

func _physics_process(delta: float) -> void:
	z_index = int(global_position.y / 32)

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
	velocity += _apply_separation()
	velocity += _knockback
	_knockback = _knockback.move_toward(Vector2.ZERO, KNOCKBACK_DECAY * delta)
	move_and_slide()
	if velocity.length_squared() > 0.01:
		_last_move_dir = velocity.normalized()
		_sprite.rotation = lerp_angle(_sprite.rotation, velocity.angle(), 0.35)
	if _last_damage_ms > 0 and Time.get_ticks_msec() - _last_damage_ms < HP_BAR_SHOW_MS:
		queue_redraw()
	_try_attack_player(delta)

# Contact attack: fly close enough and the pixie bites for COMBAT_DATA.damage.
func _try_attack_player(delta: float) -> void:
	if COMBAT_DATA.damage <= 1.0:
		return
	_attack_cooldown = maxf(0.0, _attack_cooldown - delta)
	var p: Node2D = Global.player_node as Node2D
	if p == null or _attack_cooldown > 0.0:
		return
	if global_position.distance_to(p.global_position) > ATTACK_RANGE:
		return
	_attack_cooldown = ATTACK_COOLDOWN
	Global.damage_player(COMBAT_DATA.damage, global_position, _last_move_dir)
	_show_name_label()

# ── Sword hit ────────────────────────────────────────────────────
# Called by the player's swing hitbox (see sword_swing_effect.gd) when the
# blade overlaps this pixie. Reduces HP and knocks it back from the hit
# origin; bosses take the damage but are NOT knocked back. Dies at 0 HP.
func take_hit(damage: float, source_pos: Vector2) -> void:
	if damage <= 0.0:
		return
	_mob_health = maxf(0.0, _mob_health - damage)
	_last_damage_ms = Time.get_ticks_msec()
	var away: Vector2 = global_position - source_pos
	if away.length_squared() > 0.001:
		away = away.normalized()
	if COMBAT_DATA.is_boss:
		pass  # bosses shrug off knockback
	else:
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

# ── Autohide health bar (Terraria-style) ──────────────────────────
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
	_spawn_death_burst()
	queue_free()

# Minecraft-style death poof: a burst of mellow puffs at the body's location,
# spawned as a sibling so it survives this mob's free.
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

func _build_frames() -> SpriteFrames:
	var sf := SpriteFrames.new()
	sf.remove_animation("default")
	sf.add_animation("fly")
	sf.set_animation_speed("fly", 8.0)
	sf.set_animation_loop("fly", true)
	for i in range(FRAME_COUNT):
		var atlas := AtlasTexture.new()
		atlas.atlas  = PIXIE_TEX
		atlas.region = Rect2(i * FRAME_SIZE, 0, FRAME_SIZE, FRAME_SIZE)
		sf.add_frame("fly", atlas)
	return sf
