extends Node2D
# ── Desert sand particle effect ────────────────────────────────────
# Follows the worm's ENTIRE segmented body.
# When burrowing, particles are distributed along the full body length
# so the player can track where the underground worm is moving.

@export var normal_amount:    int   = 8
@export var burrow_amount:    int   = 30
@export var burst_amount:     int   = 30
@export var normal_lifetime:  float = 0.5
@export var burrow_lifetime:  float = 0.8
@export var burst_lifetime:   float = 0.6
@export var spread:           float = 200.0
@export var initial_vel_min:  float = 10.0
@export var initial_vel_max:  float = 35.0
@export var scale_min:        float = 0.7
@export var scale_max:        float = 1.3
@export var gravity_y:        float = -30.0

const SAND_TEX: Texture2D = preload("res://sprites/particles_effects/sand_experimental.png")

var _particles: GPUParticles2D = null
var _mat: ParticleProcessMaterial = null
var worm: Node2D = null

func _ready() -> void:
	_particles = GPUParticles2D.new()
	_particles.texture = SAND_TEX
	_particles.amount = normal_amount
	_particles.lifetime = normal_lifetime
	_particles.emitting = true
	_particles.local_coords = true
	_particles.z_index = z_index + 1

	_mat = ParticleProcessMaterial.new()
	_mat.direction = Vector3(0.0, -1.0, 0.0)
	_mat.spread = spread
	_mat.gravity = Vector3(0.0, gravity_y, 0.0)
	_mat.initial_velocity_min = initial_vel_min
	_mat.initial_velocity_max = initial_vel_max
	_mat.angular_velocity_min = -90.0
	_mat.angular_velocity_max = 90.0
	_mat.scale_min = scale_min
	_mat.scale_max = scale_max
	_mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	_mat.emission_sphere_radius = 8.0

	_particles.process_material = _mat
	add_child(_particles)

func _physics_process(_delta: float) -> void:
	if worm == null or not is_instance_valid(worm):
		return
	# Compute bounding box of the ENTIRE worm body (head + segments + tail)
	var bounds := _worm_body_bounds()
	global_position = bounds.center
	# Stretch emission area to cover the full body length
	_mat.emission_box_extents = Vector3(bounds.half_length, 8.0, 0.0)

func set_normal() -> void:
	if _mat == null or _particles == null:
		return
	_particles.amount = normal_amount
	_particles.lifetime = normal_lifetime
	_particles.emitting = true
	_mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	_mat.emission_sphere_radius = 8.0

func set_burrowing() -> void:
	if _mat == null or _particles == null:
		return
	_particles.amount = burrow_amount
	_particles.lifetime = burrow_lifetime
	_particles.emitting = true
	# Box emission along the worm's body length
	_mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX

func set_buried() -> void:
	if _particles == null:
		return
	_particles.emitting = false

func burst() -> void:
	if _mat == null or _particles == null:
		return
	_particles.amount = burst_amount
	_particles.lifetime = burst_lifetime
	_particles.emitting = true
	get_tree().create_timer(burst_lifetime).timeout.connect(set_normal)

# Bounding box of the worm's entire visible body.
# Returns { center: Vector2, half_length: float }
func _worm_body_bounds() -> Dictionary:
	var segs: Array = worm.get("_segment_nodes") if worm.has_method("get") else []
	if segs.is_empty():
		return {"center": worm.global_position, "half_length": 8.0}
	var min_x := worm.global_position.x
	var max_x := worm.global_position.x
	var min_y := worm.global_position.y
	var max_y := worm.global_position.y
	for seg in segs:
		if seg != null:
			min_x = min(min_x, seg.global_position.x)
			max_x = max(max_x, seg.global_position.x)
			min_y = min(min_y, seg.global_position.y)
			max_y = max(max_y, seg.global_position.y)
	var center := Vector2((min_x + max_x) * 0.5, (min_y + max_y) * 0.5)
	var half_length := maxf(abs(max_x - min_x), abs(max_y - min_y)) * 0.5 + 4.0
	return {"center": center, "half_length": half_length}
