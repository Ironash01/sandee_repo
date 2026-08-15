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

@onready var _sprite: AnimatedSprite2D = $AnimatedSprite2D

func _ready() -> void:
	add_to_group("Pixie")
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
	_add_glow()
	_tilemap = get_parent().get_node_or_null("PixieCaveTiles") as TileMapLayer
	var ai_script: Script = AI_SCRIPTS.get(COMBAT_DATA.ai_type)
	if ai_script != null:
		_ai = ai_script.new()

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

# Shared Minecraft-style pixelated light texture (rounded box + stepped bands).
static func _get_glow_texture() -> Texture2D:
	return Global.get_pixelated_light_texture(256)

var _last_move_dir: Vector2 = Vector2.DOWN  # last non-zero flying direction (knockback facing)

func _physics_process(delta: float) -> void:
	z_index = int(global_position.y / 32)
	if _ai != null:
		velocity = _ai.call("physics_update", self, COMBAT_DATA.speed, _tilemap, delta)
	velocity += _apply_separation()
	move_and_slide()
	# Face the direction the pixie is currently flying (rotate the art, keep
	# the shadow flat underneath). Rotation is eased toward the target so rapid
	# direction changes turn smoothly instead of snapping (which, combined with
	# linear filtering, caused the "double sprite" artifact).
	if velocity.length_squared() > 0.01:
		_last_move_dir = velocity.normalized()
		_sprite.rotation = lerp_angle(_sprite.rotation, velocity.angle(), 0.35)
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