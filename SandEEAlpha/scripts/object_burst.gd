extends Node2D
class_name ObjectBurst

# ── Colored object burst ───────────────────────────────────────────
# One-shot debris burst used when a block is placed / broken or a tree is
# felled. Uses the object's own sprite as the particle art and tints the
# particles to that sprite's average colour, so the effect always matches
# whatever object it came from (the same idea as the green grass-cut burst).
# Configure source_texture / tint / amount BEFORE add_child(); frees itself.

const SHADOW_TEX: Texture2D = preload("res://sprites/shadow/shadow_base.png")
const LIFETIME:   float     = 0.5

var source_texture: Texture2D = null
var tint:           Color     = Color.WHITE
var amount:         int       = 12
var scale_min:      float     = 0.12
var scale_max:      float     = 0.26

static var _avg_cache: Dictionary = {}

# Average colour of a texture's visible pixels (cached per texture so a burst
# is cheap after the first use). Samples on a stride, ignores transparent
# pixels, and falls back to white when the image can't be read.
static func average_color(tex: Texture2D) -> Color:
	if tex == null:
		return Color.WHITE
	if _avg_cache.has(tex):
		return _avg_cache[tex]
	var col: Color = Color.WHITE
	var img: Image = null
	# An AtlasTexture (block/tree sprites) must sample only its region, not the
	# whole shared sheet.
	var atlas := tex as AtlasTexture
	if atlas != null and atlas.atlas != null:
		var src: Image = atlas.atlas.get_image()
		if src != null:
			img = src.get_region(Rect2i(atlas.region.position, atlas.region.size))
	else:
		img = tex.get_image()
	if img != null:
		img.convert(Image.FORMAT_RGBA8)
		var acc := Vector3.ZERO
		var n: int = 0
		var step: int = maxi(1, int(max(img.get_width(), img.get_height()) / 32))
		for y in range(0, img.get_height(), step):
			for x in range(0, img.get_width(), step):
				var c: Color = img.get_pixel(x, y)
				if c.a <= 0.05:
					continue
				acc += Vector3(c.r, c.g, c.b)
				n += 1
		if n > 0:
			col = Color(acc.x / n, acc.y / n, acc.z / n, 1.0)
	_avg_cache[tex] = col
	return col

func _ready() -> void:
	z_index = 40   # above world sprites, like the other burst effects

	var p := GPUParticles2D.new()
	p.amount         = amount
	p.lifetime       = LIFETIME - 0.05
	p.one_shot       = true
	p.explosiveness  = 0.95
	p.emitting       = true
	p.local_coords   = false
	p.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	p.texture        = source_texture if source_texture != null else SHADOW_TEX

	# Scale the fragments so they read at a similar on-screen size whatever
	# the source sprite is (a 32px block vs a 96px tree).
	var sc_min: float = scale_min
	var sc_max: float = scale_max
	if source_texture != null:
		var base: float = 12.0 / float(maxi(source_texture.get_width(), 1))
		sc_min = base * 0.6
		sc_max = base * 1.2

	var m := ParticleProcessMaterial.new()
	m.direction              = Vector3(0.0, -1.0, 0.0)
	m.spread                 = 180.0
	m.gravity                = Vector3(0.0, 220.0, 0.0)   # arc back down
	m.initial_velocity_min   = 28.0
	m.initial_velocity_max   = 78.0
	m.angular_velocity_min   = -220.0
	m.angular_velocity_max   = 220.0
	m.scale_min              = sc_min
	m.scale_max              = sc_max
	m.color                  = tint
	m.emission_shape         = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	m.emission_sphere_radius = 6.0

	# Fade out over the tail of the lifetime.
	var grad := Gradient.new()
	grad.colors  = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 1), Color(1, 1, 1, 0)])
	grad.offsets = PackedFloat32Array([0.0, 0.5, 1.0])
	var ramp := GradientTexture1D.new()
	ramp.gradient = grad
	m.color_ramp = ramp

	p.process_material = m
	add_child(p)

	get_tree().create_timer(LIFETIME).timeout.connect(queue_free)
