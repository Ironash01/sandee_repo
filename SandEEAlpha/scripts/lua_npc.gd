extends Node2D

# ── Direction map ─────────────────────────────────────────────────
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

const TILE_SIZE:     float = 32.0   # 1 block = 32 px
const APPROACH_PX:  float = 40.0   # how close to get before chopping (~1.25 blocks)
const CHOP_DELAY:   float = 0.25   # seconds between each hit() call
const PICKUP_DELAY: float = 0.4    # seconds to wait before collecting drops
const NPC_SPEED:    float = 80.0   # pixels/second

# ── State ─────────────────────────────────────────────────────────
var _player_nearby: bool    = false
var _ui:            Control = null
var _last_dir:      String  = "south"
var _lua_state:     Node    = null

# Movement / behaviour
var _velocity:        Vector2 = Vector2.ZERO
var _chop_radius_px:  float   = 5.0 * TILE_SIZE   # default 5 blocks
var _is_chopping:     bool    = false

@onready var _sprite:   AnimatedSprite2D = $Sprite2D
@onready var _interact: Area2D           = $InteractArea

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

	_sprite.sprite_frames = _build_frames()
	_play_idle(_last_dir)
	_interact.body_entered.connect(_on_body_entered)
	_interact.body_exited.connect(_on_body_exited)

	_lua_state = LuaState.new()
	_lua_state.name = "LuaState"
	add_child(_lua_state)

	_lua_state.connect("signal_move",       _on_lua_move)
	_lua_state.connect("signal_interact",   _on_lua_interact)
	_lua_state.connect("signal_attack",     _on_lua_attack)
	_lua_state.connect("signal_drop_item",  _on_lua_drop_item)
	_lua_state.connect("signal_place_item", _on_lua_place_item)
	_lua_state.connect("signal_print",      _on_lua_print)

	var ui_scene: PackedScene = load("res://scenes/ui/LuaEditorUI.tscn") as PackedScene
	var canvas := CanvasLayer.new()
	canvas.layer        = 12
	canvas.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(canvas)
	_ui = ui_scene.instantiate() as Control
	canvas.add_child(_ui)
	_ui.visible = false

# ── Physics: apply velocity every frame ───────────────────────────
func _physics_process(delta: float) -> void:
	if _velocity != Vector2.ZERO:
		global_position += _velocity * delta
		_update_walk_animation(_velocity)
	else:
		_play_idle(_last_dir)

# ── Lua signal handlers ───────────────────────────────────────────

func _on_lua_move(vec: Vector2) -> void:
	# Sentinel: move(radius_blocks, -1.0) → set chop radius, do NOT move
	if vec.y == -1.0:
		_chop_radius_px = vec.x * TILE_SIZE
		return
	# Normal velocity movement
	_velocity = vec

func _on_lua_interact() -> void:
	# Prevent stacking multiple chop coroutines
	if _is_chopping:
		return
	_is_chopping = true
	_chop_all_trees.call_deferred()

func _on_lua_attack() -> void:
	pass

func _on_lua_drop_item(held_item: String, quantity: int) -> void:
	if held_item == "":
		return
	var item_data: ItemData = _find_item_data_by_name(held_item)
	if item_data == null:
		return
	var item_scene: PackedScene = load("res://scenes/ui/InventoryItem.tscn") as PackedScene
	for i in range(quantity):
		var inst: Node = item_scene.instantiate()
		inst.call("set_item_data", item_data)
		(inst as Node2D).global_position = global_position + Vector2(randf_range(-20, 20), randf_range(-20, 20))
		get_parent().add_child(inst)

func _on_lua_place_item(_held_item: String) -> void:
	pass

func _on_lua_print(_text: String) -> void:
	pass

# ── Autonomous chop-trees coroutine ──────────────────────────────
# Finds every tree within _chop_radius_px, walks to each one and
# chops it fully before moving on to the next.
func _chop_all_trees() -> void:
	while true:
		var target: Node2D = _nearest_tree_in_radius()
		if target == null:
			break   # no more trees in radius — done

		# Walk toward the tree until we're within APPROACH_PX
		await _walk_to(target)

		# Chop until it dies (tree calls queue_free on last hit)
		while is_instance_valid(target):
			target.call("hit")
			await get_tree().create_timer(CHOP_DELAY).timeout

		# Brief pause then collect any wood drops nearby
		await get_tree().create_timer(PICKUP_DELAY).timeout
		_collect_drops_nearby()

	# All done — stop NPC
	_velocity    = Vector2.ZERO
	_is_chopping = false

# Walk toward a target node, yielding each frame until close enough.
func _walk_to(target: Node2D) -> void:
	while is_instance_valid(target):
		var dist: float = global_position.distance_to(target.global_position)
		if dist <= APPROACH_PX:
			_velocity = Vector2.ZERO
			return
		_velocity = global_position.direction_to(target.global_position) * NPC_SPEED
		await get_tree().process_frame
	_velocity = Vector2.ZERO

# Return the nearest tree that is still within _chop_radius_px.
func _nearest_tree_in_radius() -> Node2D:
	var best:      Node2D = null
	var best_dist: float  = _chop_radius_px * _chop_radius_px   # compare squared
	for node in get_tree().get_nodes_in_group("Tree"):
		if not (node is Node2D):
			continue
		var d: float = (node as Node2D).global_position.distance_squared_to(global_position)
		if d < best_dist:
			best_dist = d
			best      = node as Node2D
	return best

func _collect_drops_nearby() -> void:
	for item_node in get_tree().get_nodes_in_group("items"):
		if not (item_node is Node2D):
			continue
		var dist: float = (item_node as Node2D).global_position.distance_to(global_position)
		if dist <= APPROACH_PX * 1.5 and item_node.has_method("npc_pickup"):
			item_node.call("npc_pickup", self)

# ── Item helpers ──────────────────────────────────────────────────
const _ALL_ITEM_PATHS: Array = [
	"res://resources/items/wood.tres",
	"res://resources/items/stick.tres",
	"res://resources/items/crafting_station.tres",
	"res://resources/items/furnace.tres",
	"res://resources/items/lua.tres",
	"res://resources/items/plains_planks.tres",
	"res://resources/items/copper.tres",
	"res://resources/items/ironbar.tres",
	"res://resources/items/ironrod.tres",
	"res://resources/items/silicon.tres",
	"res://resources/items/wire.tres",
	"res://resources/items/wireframe.tres",
	"res://resources/items/cpu.tres",
	"res://resources/items/woodenaxe.tres",
	"res://resources/items/woodensword.tres",
]

func _find_item_data_by_name(item_name: String) -> ItemData:
	for path in _ALL_ITEM_PATHS:
		if not ResourceLoader.exists(path):
			continue
		var data: ItemData = load(path) as ItemData
		if data != null and data.item_name == item_name:
			return data
	return null

# ── Sprite helpers ────────────────────────────────────────────────
func _build_frames() -> SpriteFrames:
	var sf := SpriteFrames.new()
	sf.remove_animation("default")
	for d in DIRS:
		var dir: String = d["name"]
		var walk: String = "walk_" + dir.replace("-", "_")
		sf.add_animation(walk)
		sf.set_animation_speed(walk, 10.0)
		sf.set_animation_loop(walk, true)
		for f in range(8):
			var path := "res://sprites/char/lua/animations/Walking-c1c75e91/%s/frame_%03d.png" % [dir, f]
			sf.add_frame(walk, load(path) as Texture2D)
		var idle: String = "idle_" + dir.replace("-", "_")
		sf.add_animation(idle)
		sf.set_animation_speed(idle, 1.0)
		sf.set_animation_loop(idle, false)
		sf.add_frame(idle, load("res://sprites/char/lua/animations/Walking-c1c75e91/%s/frame_000.png" % dir) as Texture2D)
	return sf

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

# ── Player proximity / UI ─────────────────────────────────────────
func _input(event: InputEvent) -> void:
	if not _player_nearby or _ui == null:
		return
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
