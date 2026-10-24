extends Node2D
# Reusable grass-cut particle emitter. The world pre-creates a small pool of
# these once, and every cut just moves/re-emits a pooled instance. Previously a
# fresh GPUParticles2D + ParticleProcessMaterial + Gradient was allocated for
# each swing, which caused a visible hitch during sword sweeps.

var _particles: GPUParticles2D = null

func _ready() -> void:
	z_index = 40
	z_as_relative = false
	_particles = GPUParticles2D.new()
	_particles.amount = 10
	_particles.lifetime = 0.45
	_particles.one_shot = true
	_particles.explosiveness = 0.95
	_particles.local_coords = false
	_particles.emitting = false
	_particles.texture = Global.get_smooth_light_texture(16)
	_particles.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_particles.z_index = 40

	var mat := ParticleProcessMaterial.new()
	mat.direction = Vector3(0.0, -1.0, 0.0)
	mat.spread = 180.0
	mat.gravity = Vector3(0.0, 220.0, 0.0)
	mat.initial_velocity_min = 28.0
	mat.initial_velocity_max = 78.0
	mat.angular_velocity_min = -220.0
	mat.angular_velocity_max = 220.0
	mat.scale_min = 0.10
	mat.scale_max = 0.22
	mat.color = Color.WHITE
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	mat.emission_sphere_radius = 6.0

	var grad := Gradient.new()
	grad.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 1), Color(1, 1, 1, 0)])
	grad.offsets = PackedFloat32Array([0.0, 0.5, 1.0])
	var ramp := GradientTexture1D.new()
	ramp.gradient = grad
	mat.color_ramp = ramp
	_particles.process_material = mat
	add_child(_particles)

func emit_at(at: Vector2, color: Color) -> void:
	if _particles == null:
		return
	global_position = at + Vector2(0.0, -12.0)
	modulate = color
	_particles.restart()
	_particles.emitting = true
