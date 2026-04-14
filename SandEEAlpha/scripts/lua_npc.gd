extends Node2D

# ── Direction map (matches sprite folder names) ───────────────────
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

const MOVE_SPEED: float = 80.0  # pixels per second

var _player_nearby: bool    = false
var _ui:            Control = null
var _last_dir:      String  = "south"
var _lua_state:     Node    = null

# Current move target; null when idle
var _move_target: Variant = null

@onready var _sprite:   AnimatedSprite2D = $Sprite2D
@onready var _interact: Area2D           = $InteractArea

func _ready() -> void:
	# Must process even while tree is paused (Lua UI open)
	process_mode = Node.PROCESS_MODE_ALWAYS

	_sprite.sprite_frames = _build_frames()
	_play_idle(_last_dir)
	_interact.body_entered.connect(_on_body_entered)
	_interact.body_exited.connect(_on_body_exited)

	# Create LuaState (GDExtension) as child so lua_editor_ui can find it
	_lua_state = LuaState.new()
	_lua_state.name = "LuaState"
	add_child(_lua_state)
	_lua_state.connect("signal_move", _on_lua_move)

	# Spawn the code editor UI on its own CanvasLayer
	var ui_scene: PackedScene = load("res://scenes/ui/LuaEditorUI.tscn") as PackedScene
	var canvas := CanvasLayer.new()
	canvas.layer        = 12
	canvas.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(canvas)
	_ui = ui_scene.instantiate() as Control
	canvas.add_child(_ui)
	_ui.visible = false

# ── Smooth movement ───────────────────────────────────────────────
func _process(delta: float) -> void:
	if _move_target == null:
		return

	var target: Vector2 = _move_target as Vector2
	var diff: Vector2   = target - global_position
	var dist: float     = diff.length()
	var step: float     = MOVE_SPEED * delta

	if dist <= step:
		# Arrived — snap, go idle, tell LuaState to release next move
		global_position = target
		_move_target    = null
		_play_idle(_last_dir)
		if _lua_state and _lua_state.has_method("notify_move_done"):
			_lua_state.notify_move_done()
	else:
		global_position += (diff / dist) * step
		_update_walk_animation(diff)

# ── Build SpriteFrames from individual PNGs ───────────────────────
func _build_frames() -> SpriteFrames:
	var sf := SpriteFrames.new()
	sf.remove_animation("default")
	for d in DIRS:
		var dir: String = d["name"]
		# Walk animation (8 frames)
		var walk: String = "walk_" + dir.replace("-", "_")
		sf.add_animation(walk)
		sf.set_animation_speed(walk, 10.0)
		sf.set_animation_loop(walk, true)
		for f in range(8):
			var path := "res://sprites/char/lua/animations/Walking-c1c75e91/%s/frame_%03d.png" % [dir, f]
			sf.add_frame(walk, load(path) as Texture2D)
		# Idle: frame 0 of same strip, no loop
		var idle: String = "idle_" + dir.replace("-", "_")
		sf.add_animation(idle)
		sf.set_animation_speed(idle, 1.0)
		sf.set_animation_loop(idle, false)
		sf.add_frame(idle, load("res://sprites/char/lua/animations/Walking-c1c75e91/%s/frame_000.png" % dir) as Texture2D)
	return sf

# ── Animation helpers ─────────────────────────────────────────────
func _play_idle(dir: String) -> void:
	var anim := "idle_" + dir.replace("-", "_")
	if _sprite.animation != anim:
		_sprite.play(anim)

func _update_walk_animation(vec: Vector2) -> void:
	var best_dir: String = _last_dir
	var best_dot: float  = -INF
	var norm := vec.normalized()
	for d in DIRS:
		var dot: float = norm.dot((d["vec"] as Vector2).normalized())
		if dot > best_dot:
			best_dot = dot
			best_dir = d["name"]
	var anim := "walk_" + best_dir.replace("-", "_")
	if _sprite.animation != anim:
		_sprite.play(anim)
	_last_dir = best_dir

# ── Interaction ───────────────────────────────────────────────────
func _input(event: InputEvent) -> void:
	if not _player_nearby or _ui == null:
		return
	# Only OPEN the UI on click — closing is owned by the UI (✕ / Escape)
	if _ui.visible:
		return
	if event is InputEventMouseButton \
			and event.pressed \
			and event.button_index == MOUSE_BUTTON_LEFT:
		_ui.visible = true

func _on_body_entered(body: Node) -> void:
	if body.is_in_group("Player"):
		_player_nearby = true

func _on_body_exited(body: Node) -> void:
	if body.is_in_group("Player"):
		_player_nearby = false
		if _ui != null and _ui.visible:
			_ui.visible = false

# ── Lua movement signal ───────────────────────────────────────────
func _on_lua_move(vec: Vector2) -> void:
	# LuaState gates this: fires only when previous move is done
	_move_target = global_position + vec
