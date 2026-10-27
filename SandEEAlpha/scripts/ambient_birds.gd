extends Node2D

# ── Ambient birds ─────────────────────────────────────────────────
# Purely decorative overworld flyers: no collision, no combat, no loot and no
# Bestiary entry. Two approved sprite concepts:
#   • Sunshard Finch (24x24) — daytime flocks.
#   • Dusk Kite (32x32)     — night-time raptors.
# Both ship as 4-frame horizontal wing strips. This manager slices them once,
# spawns a small flock crossing near the player, and despawns birds that fly
# out of range. It lives under World, so caves/dungeons (which take World out
# of the tree) pause it automatically.

const FINCH_TEX: Texture2D = preload("res://sprites/birds/sunshard_finch_wing_4f.png")
const KITE_TEX:  Texture2D = preload("res://sprites/birds/dusk_kite_wing_4f.png")
const FINCH_FRAME: Vector2i = Vector2i(24, 24)
const KITE_FRAME:  Vector2i = Vector2i(32, 32)

const MAX_BIRDS: int = 8
const SPAWN_MIN_SEC: float = 2.5
const SPAWN_MAX_SEC: float = 6.0
const DESPAWN_DIST: float = 1200.0
const MAX_AGE_SEC: float = 30.0
const FLAP_FPS: float = 8.0

var _birds: Array = []
var _spawn_clock: float = 2.0
static var _finch_frames: SpriteFrames = null
static var _kite_frames:  SpriteFrames = null


func _ready() -> void:
	# Birds are above the canopy and the player. z_as_relative = false keeps
	# that absolute layer even though World is y-sorted.
	z_index = 2000
	z_as_relative = false
	_ensure_frames()
	_spawn_clock = randf_range(0.8, 2.5)


func _process(delta: float) -> void:
	_spawn_clock -= delta
	if _spawn_clock <= 0.0:
		_spawn_clock = randf_range(SPAWN_MIN_SEC, SPAWN_MAX_SEC)
		_try_spawn()
	_update_birds(delta)


func bird_count() -> int:
	return _birds.size()


func _ensure_frames() -> void:
	if _finch_frames == null:
		_finch_frames = _make_frames(FINCH_TEX, FINCH_FRAME)
	if _kite_frames == null:
		_kite_frames = _make_frames(KITE_TEX, KITE_FRAME)


static func _make_frames(texture: Texture2D, frame_size: Vector2i) -> SpriteFrames:
	var frames := SpriteFrames.new()
	frames.add_animation("fly")
	frames.set_animation_loop("fly", true)
	frames.set_animation_speed("fly", FLAP_FPS)
	var count: int = maxi(1, int(texture.get_width() / frame_size.x))
	for i in range(count):
		var atlas := AtlasTexture.new()
		atlas.atlas = texture
		atlas.region = Rect2(i * frame_size.x, 0, frame_size.x, frame_size.y)
		frames.add_frame("fly", atlas)
	return frames


func _visible_world_size() -> Vector2:
	var vp := get_viewport()
	if vp == null:
		return Vector2(1152.0, 648.0)
	var size: Vector2 = vp.get_visible_rect().size
	var cam := vp.get_camera_2d()
	if cam != null:
		size /= cam.zoom
	return size


func _try_spawn() -> void:
	if _birds.size() >= MAX_BIRDS:
		return
	var player := Global.player_node as Node2D
	if player == null or not is_instance_valid(player):
		return
	var night: bool = not Global.is_daytime
	var kind: String = "kite" if night else "finch"
	var flock: int = randi_range(1, 2) if night else randi_range(2, 4)
	var view: Vector2 = _visible_world_size()
	var side: float = 1.0 if randf() < 0.5 else -1.0
	for i in range(flock):
		if _birds.size() >= MAX_BIRDS:
			break
		_spawn_bird(kind, player.global_position, view, side, i)


func _spawn_bird(kind: String, center: Vector2, view: Vector2,
		side: float, index: int) -> void:
	var sprite := AnimatedSprite2D.new()
	sprite.sprite_frames = _finch_frames if kind == "finch" else _kite_frames
	sprite.animation = "fly"
	sprite.speed_scale = randf_range(0.9, 1.25)
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sprite.z_as_relative = false
	sprite.z_index = 2000
	sprite.play()
	add_child(sprite)

	var start := center + Vector2(
		side * (view.x * 0.62 + randf_range(50.0, 150.0) + index * 24.0),
		randf_range(-view.y * 0.40, view.y * 0.08) + randf_range(-16.0, 16.0))
	var speed: float = randf_range(70.0, 115.0) if kind == "finch" \
		else randf_range(95.0, 150.0)
	var drift: float = randf_range(-0.08, 0.08)
	var vel := Vector2(-side, drift).normalized() * speed
	sprite.global_position = start
	sprite.flip_h = vel.x < 0.0

	_birds.append({
		"node": sprite,
		"vel": vel,
		"base_y": start.y,
		"bob_phase": randf() * TAU,
		"bob_speed": randf_range(2.0, 4.0),
		"bob_amp": randf_range(1.5, 4.0),
		"age": 0.0,
		"kind": kind,
	})


func _update_birds(delta: float) -> void:
	var player := Global.player_node as Node2D
	var player_valid: bool = player != null and is_instance_valid(player)
	for i in range(_birds.size() - 1, -1, -1):
		var bird: Dictionary = _birds[i]
		var node: Node2D = bird["node"] as Node2D
		if node == null or not is_instance_valid(node):
			_birds.remove_at(i)
			continue
		bird["age"] = float(bird["age"]) + delta
		bird["base_y"] = float(bird["base_y"]) + (bird["vel"] as Vector2).y * delta
		bird["bob_phase"] = float(bird["bob_phase"]) + float(bird["bob_speed"]) * delta
		var vel: Vector2 = bird["vel"]
		node.global_position = Vector2(
			node.global_position.x + vel.x * delta,
			float(bird["base_y"]) + sin(float(bird["bob_phase"])) * float(bird["bob_amp"]))
		node.flip_h = vel.x < 0.0
		var expired: bool = float(bird["age"]) >= MAX_AGE_SEC
		if not expired and player_valid:
			expired = node.global_position.distance_squared_to(player.global_position) \
				> DESPAWN_DIST * DESPAWN_DIST
		if expired:
			node.queue_free()
			_birds.remove_at(i)
