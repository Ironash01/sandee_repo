extends Area2D
class_name DungeonProjectile

# ── Dungeon flare projectile ─────────────────────────────────────────
# Fired by DungeonFlare in a STRAIGHT line. An 8-frame animated sprite
# (sprites/dungeon/dungeon_projectile.png, 32x32 cells) travels forward,
# carries a small warm light so it reads as a fiery bolt, and deals DAMAGE
# to the player on contact. Expires on its own after LIFETIME.
# NOTE: no bonfire artwork here — bonfire_anim.png belongs to the bonfire,
# not the dungeon.

const PROJ_TEX:   Texture2D = preload("res://sprites/dungeon/dungeon_projectile.png")
const MELLOW_BURST_SCRIPT: GDScript = preload("res://scripts/mellow_burst.gd")
const FRAME_COUNT: int  = 8
const FRAME_SIZE:  int  = 32
const FPS:        float = 12.0
const SPEED:      float = 150.0
const DAMAGE:     float = 20.0
const LIFETIME:   float = 3.0
const HIT_RADIUS: float = 7.0
const GLOW_COLOR: Color = Color(1.0, 0.55, 0.22)

var direction: Vector2 = Vector2.RIGHT
# Per-instance damage. Defaults to the obstacle flare's 40; the Hitman enemy
# overrides it to 20 (see hitman.gd) so the two never share a value.
var damage: float = DAMAGE
# When true the bolt stops at walls/obstacles (layer 1) via a raycast. Off by
# default so the DungeonFlare obstacle is unchanged; the Hitman turns it on.
var collide_walls: bool = false
# Multiplier on the player knockback this bolt applies. 1.0 = the old full
# knockback (damage × Global.KNOCKBACK_PER_DAMAGE). The obstacle flare sets a
# reduced value (see dungeon_flare.gd); the Hitman keeps 1.0.
var knockback_scale: float = 1.0
var _life: float = 0.0
var _glow: PointLight2D = null
var _parried: bool = false
var _safe_gone: bool = false

func _ready() -> void:
	# Layer 2 is the "sword-hittable" layer (the swing hitbox masks it), so the
	# player can PARRY this projectile out of the air. It still scans layer 4
	# (the player) for the contact hit.
	collision_layer = 2
	collision_mask  = 4   # player is on layer 4 (see player.tscn)
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = HIT_RADIUS
	shape.shape = circle
	add_child(shape)
	body_entered.connect(_on_body_entered)
	_add_sprite()
	_add_glow()
	rotation = direction.angle()

func _add_sprite() -> void:
	var spr := AnimatedSprite2D.new()
	spr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var sf := SpriteFrames.new()
	sf.remove_animation("default")
	sf.add_animation("fly")
	sf.set_animation_speed("fly", FPS)
	sf.set_animation_loop("fly", true)
	for i in range(FRAME_COUNT):
		var atlas := AtlasTexture.new()
		atlas.atlas  = PROJ_TEX
		atlas.region = Rect2(i * FRAME_SIZE, 0, FRAME_SIZE, FRAME_SIZE)
		sf.add_frame("fly", atlas)
	spr.sprite_frames = sf
	spr.play("fly")
	add_child(spr)

# A small warm light so the bolt looks like fire — the "flame" is just a
# point light (plus its soft pool), no bonfire sprite.
func _add_glow() -> void:
	var sprite := Sprite2D.new()
	sprite.texture = Global.get_smooth_light_texture(64)
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sprite.scale = Vector2(0.5, 0.5)
	sprite.modulate = Color(1.0, 0.6, 0.25, 0.85)
	add_child(sprite)

	_glow = PointLight2D.new()
	_glow.texture       = Global.get_smooth_light_texture(64)
	_glow.texture_scale = 0.45
	_glow.color         = GLOW_COLOR
	_glow.energy        = 1.2
	_glow.blend_mode    = Light2D.BLEND_MODE_ADD
	add_child(_glow)

func _physics_process(delta: float) -> void:
	if _parried or _safe_gone:
		return
	var step: Vector2 = direction * SPEED * delta
	# Safe-zone protection: remove the bolt even if it crossed the boundary
	# between frames (segment test) or was spawned inside a zone.
	if Global.is_point_in_safe_zone(global_position) \
			or Global.segment_intersects_safe_zone(global_position, global_position + step):
		_vanish_in_safe_zone()
		return
	# Optional wall/obstacle collision (layer 1). TileMapLayer collision isn't a
	# Node, so an Area2D body test can't see it — a raycast can.
	if collide_walls and is_inside_tree():
		var from: Vector2 = global_position
		var q := PhysicsRayQueryParameters2D.create(from, from + step, 1)
		if not get_world_2d().direct_space_state.intersect_ray(q).is_empty():
			queue_free()
			return
	global_position += step
	z_index = int(global_position.y / 32)   # y-sort against the player/walls
	_life += delta
	if _life >= LIFETIME:
		queue_free()

func _on_body_entered(body: Node) -> void:
	if _parried or _safe_gone or not body.is_in_group("Player"):
		return
	if Global.is_player_in_safe_zone():
		_vanish_in_safe_zone()
		return
	Global.damage_player(damage, global_position, direction, knockback_scale)
	queue_free()

func _vanish_in_safe_zone() -> void:
	if _safe_gone:
		return
	_safe_gone = true
	_parried = true
	set_deferred("monitoring", false)
	var b: Node2D = MELLOW_BURST_SCRIPT.new() as Node2D
	var parent := get_parent()
	if b != null and parent != null and is_instance_valid(parent):
		b.position = global_position
		parent.add_child(b)
	queue_free()

# Called by the sword swing hitbox when the blade sweeps over this bolt.
# Parrying destroys it (with a poof) and stops it dealing damage.
func parry(_source_pos: Vector2) -> void:
	if _parried:
		return
	_parried = true
	monitoring = false
	var b: Node2D = MELLOW_BURST_SCRIPT.new() as Node2D
	if b != null:
		b.position = global_position
		get_parent().add_child(b)
	queue_free()
