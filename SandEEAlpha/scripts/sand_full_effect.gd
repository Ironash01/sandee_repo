extends Node2D
# ── Sand-full transition cloud ─────────────────────────────────────
# A one-shot dense sand cloud used to obscure the worm during
# appear/disappear transitions.  Instance it, set its position,
# call burst(), and it auto-frees after the cloud dissipates.

const SAND_FULL_TEX: Texture2D = preload("res://sprites/particles_effects/sand_full.png")

@export var burst_amount:  int   = 20
@export var burst_lifetime: float = 0.6
@export var spread:        float = 360.0
@export var vel_min:       float = 5.0
@export var vel_max:       float = 30.0
@export var scale_min:     float = 1.0
@export var scale_max:     float = 2.0

var _particles: GPUParticles2D = null

func _ready() -> void:
	_particles = GPUParticles2D.new()
	_particles.texture = SAND_FULL_TEX
	_particles.amount = burst_amount
	_particles.lifetime = burst_lifetime
	_particles.emitting = false
	_particles.local_coords = true
	_particles.z_index = z_index + 1

	var mat := ParticleProcessMaterial.new()
	mat.direction = Vector3(0.0, 0.0, 0.0)
	mat.spread = spread
	mat.gravity = Vector3.ZERO
	mat.initial_velocity_min = vel_min
	mat.initial_velocity_max = vel_max
	mat.angular_velocity_min = -60.0
	mat.angular_velocity_max = 60.0
	mat.scale_min = scale_min
	mat.scale_max = scale_max
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	mat.emission_sphere_radius = 16.0

	_particles.process_material = mat
	add_child(_particles)

func burst() -> void:
	if _particles == null:
		return
	_particles.emitting = true
	get_tree().create_timer(burst_lifetime + 0.1).timeout.connect(queue_free)
