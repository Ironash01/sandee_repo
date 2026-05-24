extends CharacterBody2D

const SPEED: float = 38.0

const DIRS: Array = [
	{"name": "south",      "vec": Vector2( 0,  1)},
	{"name": "north",      "vec": Vector2( 0, -1)},
	{"name": "east",       "vec": Vector2( 1,  0)},
	{"name": "west",       "vec": Vector2(-1,  0)},
	{"name": "south-east", "vec": Vector2( 1,  1)},
	{"name": "south-west", "vec": Vector2(-1,  1)},
	{"name": "north-east", "vec": Vector2( 1, -1)},
	{"name": "north-west", "vec": Vector2(-1, -1)},
]

const SPRITE_BASE: String = "res://sprites/mobs/wolf/32x32_Simple_white_wolf_with_pixelated_art_style_a"

enum State { IDLE, WALK }

var _state: State = State.IDLE
var _timer: float = 0.0
var _walk_dir: Vector2 = Vector2.ZERO
var _last_dir: String = "south"

@onready var _sprite: AnimatedSprite2D = $AnimatedSprite2D
var _water_layer: TileMapLayer = null

func _ready() -> void:
	add_to_group("Wolf")
	_sprite.sprite_frames = _build_frames()
	_sprite.play("idle_south")
	_timer = randf_range(0.5, 2.0)
	_water_layer = get_parent().get_node_or_null("Water") as TileMapLayer

func _physics_process(delta: float) -> void:
	_timer -= delta
	if _timer <= 0.0:
		_pick_new_action()

	if _state == State.WALK:
		var next_pos: Vector2 = global_position + _walk_dir * SPEED * delta
		if _is_on_water(next_pos):
			_state = State.IDLE
			_walk_dir = Vector2.ZERO
			_timer = 0.0
		else:
			velocity = _walk_dir * SPEED
			_update_walk_anim(_walk_dir)
			move_and_slide()
	else:
		velocity = Vector2.ZERO
		_play_idle(_last_dir)

func _is_on_water(world_pos: Vector2) -> bool:
	if _water_layer == null:
		return false
	var tile: Vector2i = _water_layer.local_to_map(_water_layer.to_local(world_pos))
	return _water_layer.get_cell_source_id(tile) != -1

func _pick_new_action() -> void:
	if _state == State.IDLE:
		_state = State.WALK
		_walk_dir = Vector2.from_angle(randf() * TAU)
		_timer = randf_range(1.5, 4.0)
	else:
		_state = State.IDLE
		_walk_dir = Vector2.ZERO
		_timer = randf_range(1.0, 3.0)

func _play_idle(dir: String) -> void:
	var anim := "idle_" + dir.replace("-", "_")
	if _sprite.sprite_frames != null and _sprite.sprite_frames.has_animation(anim) \
			and _sprite.animation != anim:
		_sprite.play(anim)

func _update_walk_anim(vec: Vector2) -> void:
	var best_dir: String = _last_dir
	var best_dot: float  = -INF
	var norm := vec.normalized()
	for d in DIRS:
		var dot: float = norm.dot((d["vec"] as Vector2).normalized())
		if dot > best_dot:
			best_dot = dot
			best_dir = d["name"]
	var anim := "walk_" + best_dir.replace("-", "_")
	if _sprite.sprite_frames != null and _sprite.sprite_frames.has_animation(anim) \
			and _sprite.animation != anim:
		_sprite.play(anim)
	_last_dir = best_dir

func _build_frames() -> SpriteFrames:
	var sf := SpriteFrames.new()
	sf.remove_animation("default")

	for d in DIRS:
		var dir: String = d["name"]

		var walk_anim: String = "walk_" + dir.replace("-", "_")
		sf.add_animation(walk_anim)
		sf.set_animation_speed(walk_anim, 10.0)
		sf.set_animation_loop(walk_anim, true)
		for f in range(8):
			var path: String = "%s/animations/animation-121acbd1/%s/frame_%03d.png" % [SPRITE_BASE, dir, f]
			var tex: Texture2D = load(path) as Texture2D
			if tex != null:
				sf.add_frame(walk_anim, tex)

		var idle_anim: String = "idle_" + dir.replace("-", "_")
		sf.add_animation(idle_anim)
		sf.set_animation_speed(idle_anim, 1.0)
		sf.set_animation_loop(idle_anim, false)
		var idle_path: String = "%s/rotations/%s.png" % [SPRITE_BASE, dir]
		var idle_tex: Texture2D = load(idle_path) as Texture2D
		if idle_tex != null:
			sf.add_frame(idle_anim, idle_tex)

	return sf
