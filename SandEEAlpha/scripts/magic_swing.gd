extends Node2D
class_name MagicSwing

# ── Magic swing effect ────────────────────────────────────────────
# A one-shot violet arcane slash + mote burst, spawned wherever an entity
# "swings"/attacks without a real weapon animation — the Lua robot's
# attack()/mine(), and mob hits (routed through Global.damage_player). The
# player's own swing keeps its richer sword_swing_effect; this is the shared
# lightweight version so every attacker reads as magic-based.

const SWING_TEX:    Texture2D = preload("res://sprites/particles_effects/sword_swing.png")
const MELLOW_TEX:   Texture2D = preload("res://sprites/particles_effects/mellow_effect.png")
const SWING_FRAME:  int   = 32
const SWING_COUNT:  int   = 3
const SWING_FPS:    float = 16.0
const MELLOW_FRAME: int   = 16
const MELLOW_COUNT: int   = 5
const MELLOW_FPS:   float = 20.0
const GLOW_COLOR:   Color = Color(0.90, 0.70, 1.00, 1.0)   # arcane violet
const ARC_SCALE:    float = 1.6

var _dir:   Vector2 = Vector2.RIGHT
var _size:  float   = 1.0
var _motes: int     = 4

# Build + attach a swing effect under `parent`, aimed along `dir` (world space).
# `size` scales the whole effect; `motes` is the mote count. Returns the node.
static func spawn(parent: Node, pos: Vector2, dir: Vector2,
		size: float = 1.0, motes: int = 4) -> Node2D:
	if parent == null or not is_instance_valid(parent):
		return null
	var fx := MagicSwing.new()
	fx._dir   = dir if dir.length_squared() > 0.0001 else Vector2.RIGHT
	fx._size  = size
	fx._motes = motes
	parent.add_child(fx)
	fx.global_position = pos
	fx.z_index = int(pos.y / 32.0)
	return fx

func _ready() -> void:
	rotation = _dir.angle()

	var arc := _anim_sprite(SWING_TEX, SWING_FRAME, SWING_COUNT, SWING_FPS)
	arc.modulate = GLOW_COLOR
	arc.scale    = Vector2(ARC_SCALE, ARC_SCALE) * _size
	add_child(arc)

	for i in range(_motes):
		var m := _anim_sprite(MELLOW_TEX, MELLOW_FRAME, MELLOW_COUNT, MELLOW_FPS)
		m.modulate = GLOW_COLOR
		m.position = Vector2(randf_range(-7.0, 7.0), randf_range(-7.0, 7.0)) * _size
		m.scale    = Vector2(0.5, 0.5) * _size
		add_child(m)
		var tw := create_tween()
		tw.set_parallel(true)
		tw.tween_property(m, "position",
			m.position + Vector2(randf_range(-14.0, 14.0), randf_range(-18.0, -5.0)) * _size, 0.32)
		tw.tween_property(m, "modulate:a", 0.0, 0.32)

	get_tree().create_timer(SWING_COUNT / SWING_FPS + 0.05).timeout.connect(queue_free)

# One-shot AnimatedSprite2D from a horizontal sheet of FRAME sized frames.
func _anim_sprite(tex: Texture2D, frame: int, count: int, fps: float) -> AnimatedSprite2D:
	var sprite := AnimatedSprite2D.new()
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var anim := SpriteFrames.new()
	anim.remove_animation("default")
	anim.add_animation("effect")
	anim.set_animation_speed("effect", fps)
	anim.set_animation_loop("effect", false)
	for i in range(count):
		var at := AtlasTexture.new()
		at.atlas  = tex
		at.region = Rect2(i * frame, 0, frame, frame)
		anim.add_frame("effect", at)
	sprite.sprite_frames = anim
	sprite.animation_finished.connect(sprite.stop)
	sprite.play("effect")
	return sprite
