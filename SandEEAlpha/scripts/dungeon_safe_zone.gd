extends Node2D
class_name DungeonSafeZone

# ── Dungeon safe zone ─────────────────────────────────────────────
# One per SAFE altar room (knowledge + quiz). Marker decals (a 3-frame sheet:
# idle / active / warning) SURROUND the room's corridor gap(s); walking over any
# of them ACTIVATES the zone: the room is surrounded by a green glow, the player
# is invulnerable + heals HEAL_PER_SEC, and enemies inside despawn for good.
# Safety lasts SAFE_SECONDS per entry; as it runs out the glow pulses faster.
# When it ends (or the player leaves the room) the glow drops, the player becomes
# vulnerable again, and the zone needs COOLDOWN_SECONDS before it can re-arm.
#
# Owned by DungeonWorld (dungeon_world.gd), which places the markers + hands the
# zone its room rect.

const MARKER_TEX: Texture2D = preload("res://sprites/dungeon/dungeon_safe_zone_marker.png")
const IDLE_FRAME:   int = 0
const ACTIVE_FRAME: int = 1
const WARN_FRAME:   int = 2
const MARKER_Z:     int = -200   # floor decal: same layer as placed floor blocks

const SAFE_SECONDS:     float = 30.0
const COOLDOWN_SECONDS: float = 20.0
const WARN_SECONDS:     float = 5.0
const HEAL_PER_SEC:     float = 1.0
const GLOW_COLOR: Color = Color(0.30, 1.00, 0.45)
const GLOW_Z: int = 1500   # above the world sprites, below the UI canvas
# Soft green halo SURROUNDING the room: this many expanding outline layers.
const HALO_LAYERS: int = 6
const HALO_STEP:   float = 8.0

enum State { IDLE, ACTIVE, COOLDOWN }

var _world: Node = null
var _room_rect_px: Rect2 = Rect2()
var _markers: Array = []
var _state: int = State.IDLE
var _timer: float = 0.0
var _pulse: float = 0.0
var _light: PointLight2D = null

func setup(world: Node, room_rect_px: Rect2) -> void:
	_world = world
	_room_rect_px = room_rect_px
	z_index = GLOW_Z
	set_process(false)
	# A soft green light so the glow also reads through the dungeon's dark ambient.
	_light = PointLight2D.new()
	_light.texture = Global.get_smooth_light_texture(256)
	_light.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_light.color = GLOW_COLOR
	_light.blend_mode = Light2D.BLEND_MODE_ADD
	_light.energy = 0.0
	_light.texture_scale = maxf(_room_rect_px.size.x, _room_rect_px.size.y) / 200.0
	_light.position = _room_rect_px.get_center()
	add_child(_light)

# A 32x32 marker decal + a trigger area on one of the room's corridor-gap tiles.
func add_marker(pos: Vector2) -> void:
	var spr := Sprite2D.new()
	spr.texture = MARKER_TEX
	spr.hframes = 3
	spr.frame = IDLE_FRAME
	spr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	# Treat the marker like a floor block: an absolute low z, NOT relative to the
	# zone's own z (1500) — otherwise it would draw over the player.
	spr.z_as_relative = false
	spr.z_index = MARKER_Z
	spr.global_position = pos
	add_child(spr)
	_markers.append(spr)

	var area := Area2D.new()
	area.collision_layer = 0
	area.collision_mask  = 4   # player is on layer 4 (see player.tscn)
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(32, 32)
	shape.shape = rect
	area.add_child(shape)
	spr.add_child(area)
	area.body_entered.connect(_on_marker_body)

func _on_marker_body(body: Node) -> void:
	if body.is_in_group("Player"):
		activate()

# ── Activation ─────────────────────────────────────────────────────
func activate() -> void:
	if _state != State.IDLE:
		return
	_state = State.ACTIVE
	_timer = SAFE_SECONDS
	_pulse = 0.0
	Global.register_safe_zone(self, _room_rect_px)
	_clear_enemies()
	set_process(true)
	_update_marker_frames()
	queue_redraw()

func _process(delta: float) -> void:
	_pulse += delta
	match _state:
		State.ACTIVE:
			_timer -= delta
			_heal(delta)
			if not _player_inside():
				# Left the room → glow off, vulnerable again (per entry).
				_end(State.IDLE)
				return
			if _timer <= 0.0:
				_end(State.COOLDOWN)
				return
			Global.refresh_safe_zone_state()
			_update_marker_frames()
			_update_light()
			queue_redraw()
		State.COOLDOWN:
			_timer -= delta
			if _timer <= 0.0:
				_end(State.IDLE)
		State.IDLE:
			set_process(false)

func _end(next_state: int) -> void:
	Global.unregister_safe_zone(self)
	_state = next_state
	if _light != null:
		_light.energy = 0.0
	for spr in _markers:
		if is_instance_valid(spr):
			spr.frame = IDLE_FRAME
	if next_state == State.COOLDOWN:
		_timer = COOLDOWN_SECONDS
	else:
		set_process(false)
	queue_redraw()

# ── Effects ────────────────────────────────────────────────────────
func _heal(delta: float) -> void:
	if Global.health >= Global.max_health:
		return
	Global.health = minf(Global.max_health, Global.health + HEAL_PER_SEC * delta)
	Global.health_changed.emit(Global.health, Global.max_health)

# The altar/world can be freed while a zone is active (death, dungeon exit).
# Unregistering here lets the union recompute from any remaining zones.
func _exit_tree() -> void:
	Global.unregister_safe_zone(self)

# Enemies inside the room are removed for good (the user's "enemies go away").
# Only HOSTILE mobs; passive animals are left alone.
func _clear_enemies() -> void:
	for m in get_tree().get_nodes_in_group("Mob"):
		var node_ref: Variant = m
		if not (node_ref is Node2D) or not is_instance_valid(node_ref):
			continue
		var node := node_ref as Node2D
		if not Global.is_hostile_mob(node):
			continue
		if _room_rect_px.has_point(node.global_position):
			Global.disintegrate_hostile(node)

func _player_inside() -> bool:
	var p: Node2D = Global.player_node as Node2D
	if p == null or not is_instance_valid(p):
		return false
	return Global._rect_contains_inclusive(
		_room_rect_px, p.global_position + Vector2(0.0, Global.SAFE_ZONE_FEET_OFFSET))

func _update_light() -> void:
	if _light == null:
		return
	var e: float = 1.25
	if _timer <= WARN_SECONDS:
		e = lerpf(0.9, 1.9, (sin(_pulse * 12.0) + 1.0) * 0.5)
	_light.energy = e

# Marker tile: active while safe; near the end it blinks to the warning tile
# faster and faster, then settles on warning.
func _update_marker_frames() -> void:
	var frame: int = ACTIVE_FRAME
	if _timer <= WARN_SECONDS:
		frame = WARN_FRAME if fmod(_pulse, 0.25) < 0.125 else ACTIVE_FRAME
	for spr in _markers:
		if is_instance_valid(spr):
			spr.frame = frame

# A green halo SURROUNDING the room (expanding outline layers) + a faint fill.
func _draw() -> void:
	if _state != State.ACTIVE:
		return
	var base_a: float = 0.85
	if _timer <= WARN_SECONDS:
		base_a = lerpf(0.5, 1.0, (sin(_pulse * 12.0) + 1.0) * 0.5)
	draw_rect(_room_rect_px, Color(GLOW_COLOR.r, GLOW_COLOR.g, GLOW_COLOR.b, base_a * 0.16), true)
	for i in range(HALO_LAYERS):
		var grow: float = float(i + 1) * HALO_STEP
		var a: float = base_a * (1.0 - float(i) / float(HALO_LAYERS)) * 0.55
		draw_rect(_room_rect_px.grow(grow), Color(GLOW_COLOR.r, GLOW_COLOR.g, GLOW_COLOR.b, a), false, 5.0)
