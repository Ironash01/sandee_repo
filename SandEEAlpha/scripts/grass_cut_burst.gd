extends Node2D
# ── Grass-cut burst ────────────────────────────────────────────────
# A short-lived burst of small green blades/specks spawned where a grass
# tuft is cut (Terraria-style). Uses one frame of the grass sheet as the
# particle texture, tinted green. Added as a sibling of the tuft (under the
# world) so it outlives the freed tuft, then frees itself.

const GRASS_TEX: Texture2D = preload("res://sprites/ground/grass.png")
const FRAME_SIZE: int   = 96
const AMOUNT:     int   = 12
const LIFETIME:   float = 0.55

func _ready() -> void:
	z_index = 40   # above grass/player, like the other burst effects

	var p := GPUParticles2D.new()
	p.amount        = AMOUNT
	p.lifetime      = 0.45
	p.one_shot      = true
	p.explosiveness = 0.95
	p.emitting      = true
	p.local_coords  = false
	p.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST

	# One frame of the grass sheet as the particle art.
	var at := AtlasTexture.new()
	at.atlas  = GRASS_TEX
	at.region = Rect2(0, 0, FRAME_SIZE, FRAME_SIZE)
	p.texture = at

	var m := ParticleProcessMaterial.new()
	m.direction            = Vector3(0.0, -1.0, 0.0)
	m.spread               = 180.0
	m.gravity              = Vector3(0.0, 220.0, 0.0)   # arc back down
	m.initial_velocity_min = 28.0
	m.initial_velocity_max = 78.0
	m.angular_velocity_min = -220.0
	m.angular_velocity_max = 220.0
	m.scale_min            = 0.10
	m.scale_max            = 0.20
	m.color                = Color(0.55, 1.0, 0.45, 1.0)
	m.emission_shape       = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
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
