extends Node2D

# One PointLight2D per CLUSTER of adjacent torches instead of one light per
# torch. Torches within MERGE_DISTANCE_PX merge into a single larger light
# centered on the cluster's centroid, so "torch spam" renders as a handful of
# light pools instead of dozens of overlapping ones (the per-torch 0.1s flicker
# Timers are gone too — one _process here drives flicker per cluster).
#
# Created lazily by placeable_block.gd on the world that owns the torch
# (world.gd / cave_world.gd) and named "TorchLights". Torch nodes register
# with register_torch() on _ready and unregister on _exit_tree.

const TEXTURE_SIZE:      int   = 256
const BASE_RADIUS_PX:    float = 217.6   # ~6.8 tiles — matches the old single-torch glow
const MERGE_DISTANCE_PX: float = 128.0   # merge torches within 4 tiles of each other
const GLOW_COLOR:        Color = Color(1.0, 0.65, 0.35)
const ENERGY_BASE:       float = 1.2     # kept low — a big pool at full energy reads as distracting glare
const ENERGY_AMP:        float = 0.15
const FLICKER_SPEED:     float = 9.0     # rad/s — same rhythm as the old 0.1s Timer

var _torch_nodes:    Dictionary = {}  # Node -> true
var _cluster_lights: Array      = []  # each: {"light": PointLight2D, "phase": float}
var _dirty:          bool       = false

func register_torch(node: Node) -> void:
	if node == null or _torch_nodes.has(node):
		return
	_torch_nodes[node] = true
	_dirty = true
	set_process(true)

func unregister_torch(node: Node) -> void:
	if node == null:
		return
	_torch_nodes.erase(node)
	_dirty = true
	set_process(true)

func _process(delta: float) -> void:
	# Rebuild whenever a torch was added/removed OR any registered torch node
	# died without unregistering (covers any path where _exit_tree didn't fire
	# on the block — otherwise the old cluster light would linger forever).
	if _dirty or _has_stale_torch():
		_rebuild_clusters()
		_dirty = false
	if _cluster_lights.is_empty():
		set_process(false)
		return
	for i in range(_cluster_lights.size()):
		var entry: Dictionary = _cluster_lights[i]
		# Untyped first: assigning a freed light to a typed PointLight2D var
		# throws "Trying to assign invalid previously freed instance".
		var light_ref: Variant = entry["light"]
		if light_ref == null or not is_instance_valid(light_ref):
			continue
		var light: PointLight2D = light_ref
		var phase: float = entry["phase"] + delta * FLICKER_SPEED
		entry["phase"] = phase
		var flicker: float = sin(phase + i * 1.3) * 0.5 + sin(phase * 2.3 + i) * 0.5
		light.energy = ENERGY_BASE + flicker * ENERGY_AMP

func _has_stale_torch() -> bool:
	for node in _torch_nodes:
		if not is_instance_valid(node):
			return true
	return false

func _rebuild_clusters() -> void:
	for entry in _cluster_lights:
		var light_ref: Variant = entry["light"]
		if is_instance_valid(light_ref):
			(light_ref as Node).queue_free()
	_cluster_lights.clear()

	var positions: Array = []
	var stale: Array = []
	for node in _torch_nodes:
		if not is_instance_valid(node):
			stale.append(node)
			continue
		positions.append((node as Node2D).global_position)
	for n in stale:
		_torch_nodes.erase(n)
	if positions.is_empty():
		return

	# Greedy flood-fill clustering: every torch within MERGE_DISTANCE_PX of the
	# growing cluster joins it, so a line/wall of torches becomes one light.
	var used: Array = []
	used.resize(positions.size())
	for i in range(positions.size()):
		used[i] = false
	for i in range(positions.size()):
		if used[i]:
			continue
		var cluster: Array = [positions[i]]
		used[i] = true
		var grew := true
		while grew:
			grew = false
			for j in range(positions.size()):
				if used[j]:
					continue
				for p in cluster:
					if (positions[j] as Vector2).distance_to(p as Vector2) <= MERGE_DISTANCE_PX:
						cluster.append(positions[j])
						used[j] = true
						grew = true
						break
		_build_cluster_light(cluster)

func _build_cluster_light(cluster: Array) -> void:
	var center := Vector2.ZERO
	for p in cluster:
		center += p as Vector2
	center /= float(cluster.size())
	var max_dist: float = 0.0
	for p in cluster:
		max_dist = maxf(max_dist, (p as Vector2).distance_to(center))
	var radius: float = max_dist + BASE_RADIUS_PX
	var light := PointLight2D.new()
	light.texture       = Global.get_smooth_light_texture(TEXTURE_SIZE)
	light.texture_scale = (radius * 2.0) / float(TEXTURE_SIZE)
	light.color         = GLOW_COLOR
	light.energy        = ENERGY_BASE
	light.position      = center
	add_child(light)
	_cluster_lights.append({"light": light, "phase": float(cluster.size())})
