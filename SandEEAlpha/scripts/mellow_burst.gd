extends Node2D
# ── Mellow death burst ────────────────────────────────────────────
# A transient cluster of mellow puff sprites that bursts where a mob dies
# (Minecraft-style death poof) and frees itself after the puffs fade. Spawned
# by the mob's _die() as a sibling (under the mob's parent) so it outlives the
# freed mob.
#
# Intensified: many more puffs, spread outward from the centre, each puff
# scaling up and drifting out over its lifetime so deaths read as a proper
# "pop" rather than a small cluster.

const TEX:         Texture2D = preload("res://sprites/particles_effects/mellow_effect.png")
const FRAME:       int       = 16
const COUNT:       int       = 5
const FPS:         float     = 20.0
const PUFF_COUNT:  int       = 14
const LIFETIME:    float     = 0.6
const SPREAD:      float     = 22.0   # max initial offset from centre (px)
const DRIFT_MIN:   float     = 4.0    # outward drift over the lifetime (px)
const DRIFT_MAX:   float     = 12.0
const SCALE_START: float     = 0.6
const SCALE_END:   float     = 1.5

func _ready() -> void:
	z_index = 40  # above the mob sprites
	for i in range(PUFF_COUNT):
		var puff := _build_anim_sprite()
		add_child(puff)
		var ang: float = randf() * TAU
		puff.position = Vector2.from_angle(ang) * randf_range(0.0, SPREAD)
		puff.modulate.a = lerpf(1.0, 0.55, float(i) / float(PUFF_COUNT - 1))
		puff.speed_scale = randf_range(0.9, 1.3)
		puff.scale = Vector2(SCALE_START, SCALE_START)
		# Each puff expands and drifts outward, giving the burst a "pop".
		var drift: Vector2 = Vector2.from_angle(ang) * randf_range(DRIFT_MIN, DRIFT_MAX)
		var tw := create_tween()
		tw.set_parallel(true)
		tw.tween_property(puff, "scale", Vector2(SCALE_END, SCALE_END), LIFETIME) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tw.tween_property(puff, "position", puff.position + drift, LIFETIME) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	get_tree().create_timer(LIFETIME).timeout.connect(queue_free)

func _build_anim_sprite() -> AnimatedSprite2D:
	var sprite := AnimatedSprite2D.new()
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var anim := SpriteFrames.new()
	anim.remove_animation("default")
	anim.add_animation("effect")
	anim.set_animation_speed("effect", FPS)
	anim.set_animation_loop("effect", false)
	for i in range(COUNT):
		var at := AtlasTexture.new()
		at.atlas = TEX
		at.region = Rect2(i * FRAME, 0, FRAME, FRAME)
		anim.add_frame("effect", at)
	sprite.sprite_frames = anim
	sprite.animation_finished.connect(sprite.stop)
	sprite.play("effect")
	return sprite
