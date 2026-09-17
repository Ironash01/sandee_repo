extends Area2D
class_name DungeonProjectile

# ── Dungeon flare projectile ─────────────────────────────────────────
# Fired by DungeonFlare in a STRAIGHT line. An 8-frame animated sprite
# (sprites/dungeon/dungeon_projectile.png, 32x32 cells) travels forward
# and deals DAMAGE to the player on contact, then despawns. It expires on
# its own after LIFETIME so a stray shot never lingers forever.

const PROJ_TEX:   Texture2D = preload("res://sprites/dungeon/dungeon_projectile.png")
const FLAME_TEX:  Texture2D = preload("res://sprites/items/bonfire_anim.png")
const FRAME_COUNT: int  = 8
const FRAME_SIZE:  int  = 32
const FLAME_COUNT: int  = 4
const FLAME_SIZE:  int  = 32
const FPS:        float = 12.0
const FLAME_FPS:  float = 14.0
const SPEED:      float = 150.0
const DAMAGE:     float = 40.0
const LIFETIME:   float = 3.0
const HIT_RADIUS: float = 7.0

var direction: Vector2 = Vector2.RIGHT
var _life: float = 0.0
var _flame: AnimatedSprite2D = null

func _ready() -> void:
	collision_layer = 0
	collision_mask  = 4   # player is on layer 4 (see player.tscn)
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = HIT_RADIUS
	shape.shape = circle
	add_child(shape)
	body_entered.connect(_on_body_entered)
	_add_sprite()
	_add_flame()
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

# A looping bonfire sprite over a small warm light — the "fire effect" is just
# a PointLight2D with the sprite on top. Counter-rotated every frame so the
# flame stays upright while the bolt points along its travel direction.
func _add_flame() -> void:
	_flame = AnimatedSprite2D.new()
	_flame.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var ff := SpriteFrames.new()
	ff.remove_animation("default")
	ff.add_animation("burn")
	ff.set_animation_speed("burn", FLAME_FPS)
	ff.set_animation_loop("burn", true)
	for i in range(FLAME_COUNT):
		var atlas := AtlasTexture.new()
		atlas.atlas  = FLAME_TEX
		atlas.region = Rect2(i * FLAME_SIZE, 0, FLAME_SIZE, FLAME_SIZE)
		ff.add_frame("burn", atlas)
	_flame.sprite_frames = ff
	_flame.play("burn")
	_flame.scale = Vector2(0.9, 0.9)
	_flame.modulate = Color(1.0, 0.85, 0.5, 0.95)
	_flame.z_index = 1
	add_child(_flame)

	# Small warm light under the sprite.
	var light := PointLight2D.new()
	light.texture       = Global.get_smooth_light_texture(64)
	light.texture_scale = 0.4
	light.color         = Color(1.0, 0.6, 0.25)
	light.energy        = 1.2
	light.blend_mode    = Light2D.BLEND_MODE_ADD
	_flame.add_child(light)

func _physics_process(delta: float) -> void:
	global_position += direction * SPEED * delta
	z_index = int(global_position.y / 32)   # y-sort against the player/walls
	if _flame != null:
		_flame.rotation = -rotation          # keep the flame upright
	_life += delta
	if _life >= LIFETIME:
		queue_free()

func _on_body_entered(body: Node) -> void:
	if not body.is_in_group("Player"):
		return
	Global.damage_player(DAMAGE, global_position, direction)
	queue_free()
