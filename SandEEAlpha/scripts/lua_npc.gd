extends Node2D
# ─────────────────────────────────────────────────────────────────
# LUA STATION — the placed beacon block.
# This node's global_position is the permanent spawn point.
# The robot is a child Node2D that moves relative to the station.
# ─────────────────────────────────────────────────────────────────

const TILE_SIZE:          float = 32.0
const CHOP_RADIUS_BLOCKS: int   = 20
const CHOP_RADIUS_PX:     float = CHOP_RADIUS_BLOCKS * TILE_SIZE  # 640 px
const APPROACH_PX:        float = 40.0
const CHOP_DELAY:         float = 0.25
const PICKUP_DELAY:       float = 0.4
const NPC_SPEED:          float = 90.0
const SHADOW_TEXTURE:     Texture2D = preload("res://sprites/shadow/shadow_base.png")

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

# ── Sentinel codes sent via move(x, y) from Lua ──────────────────
const S_SET_RADIUS:    float = -1.0  # move(radius_blocks, -1) → set radius
const S_AUTO_WORK:     float = -2.0  # move(0, -2) + interact() → full work loop
const S_RETURN_SPAWN:  float = -3.0  # move(0, -3) + interact() → return to station
const S_DEPOSIT_CHEST: float = -4.0  # move(0, -4) + interact() → deposit to chest
const S_CHEST_ITEMS:   float = -5.0  # move(0, -5) + interact() → print chest contents

# ── State ─────────────────────────────────────────────────────────
var _show_radius:     bool    = false
var _player_nearby:   bool    = false
var _is_working:      bool    = false
var _stop_requested:  bool    = false
var _pending_action:  String  = "chop"   # action dispatched on next interact()
var _last_dir:        String  = "south"
var _robot_vel:       Vector2 = Vector2.ZERO
var _npc_inventory:   Array   = []       # [{data: ItemData, quantity: int}, ...]

# ── Node refs ─────────────────────────────────────────────────────
var _lua_state:    Node    = null
var _ui:           Control = null

@onready var _robot:        Node2D           = $Robot
@onready var _robot_sprite: AnimatedSprite2D = $Robot/RobotSprite
@onready var _click_area:   Area2D           = $ClickArea

# Shared across every Lua station robot — built once instead of per-instance
# when multiple stations are placed.
static var _shared_frames: SpriteFrames = null

# ─────────────────────────────────────────────────────────────────
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

	if _shared_frames == null:
		_shared_frames = _build_frames()
	_robot_sprite.sprite_frames = _shared_frames
	_play_idle(_last_dir)
	# Attached to _robot (not the station) so it moves with the robot as it walks.
	_robot.add_child(Global.make_shadow_sprite(SHADOW_TEXTURE, Vector2(0.0, 5.0), Vector2(0.6, 0.3), 0.35))

	_click_area.body_entered.connect(_on_body_entered)
	_click_area.body_exited.connect(_on_body_exited)
	_click_area.input_event.connect(_on_station_input_event)
	_click_area.input_pickable = true
	Global.request_close_all_ui.connect(_on_close_all_ui)

	# LuaState GDExtension
	_lua_state = LuaState.new()
	_lua_state.name = "LuaState"
	add_child(_lua_state)
	_lua_state.connect("signal_move",       _on_lua_move)
	_lua_state.connect("signal_interact",   _on_lua_interact)
	_lua_state.connect("signal_attack",     _on_lua_attack)
	_lua_state.connect("signal_drop_item",  _on_lua_drop_item)
	_lua_state.connect("signal_place_item", _on_lua_place_item)
	_lua_state.connect("signal_print",      _on_lua_print)

	# Code editor UI
	var ui_scene: PackedScene = load("res://scenes/ui/LuaEditorUI.tscn") as PackedScene
	var canvas := CanvasLayer.new()
	canvas.layer        = 12
	canvas.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(canvas)
	_ui = ui_scene.instantiate() as Control
	canvas.add_child(_ui)
	_ui.visible = false

func _on_close_all_ui() -> void:
	if _ui != null and _ui.visible:
		Global.close_ui()
		_ui.visible = false

# ── Draw radius ring ──────────────────────────────────────────────
func _draw() -> void:
	if not _show_radius:
		return
	# Filled tint
	draw_circle(Vector2.ZERO, CHOP_RADIUS_PX, Color(0.3, 0.8, 1.0, 0.06))
	# Solid border ring
	draw_arc(Vector2.ZERO, CHOP_RADIUS_PX, 0.0, TAU, 96, Color(0.3, 0.8, 1.0, 0.55), 2.5)

# ── Physics: move robot child each frame ─────────────────────────
func _physics_process(delta: float) -> void:
	if _robot_vel != Vector2.ZERO:
		_robot.position += _robot_vel * delta
		_update_walk_animation(_robot_vel)
	else:
		_play_idle(_last_dir)

# ── Station click (left = editor, right = radius toggle) ─────────
func _on_station_input_event(_viewport, event: InputEvent, _shape) -> void:
	if not (event is InputEventMouseButton) or not event.pressed:
		return
	if event.button_index == MOUSE_BUTTON_RIGHT:
		_show_radius = not _show_radius
		queue_redraw()
	elif event.button_index == MOUSE_BUTTON_LEFT and _player_nearby and not Global.block_mode:
		if _ui != null and not _ui.visible and not Global.pause_menu_open:
			Global.open_ui()
			_ui.visible = true

# ── Player proximity ──────────────────────────────────────────────
func _on_body_entered(body: Node) -> void:
	if body.is_in_group("Player"):
		_player_nearby = true

func _on_body_exited(body: Node) -> void:
	if body.is_in_group("Player"):
		_player_nearby = false
		if _ui != null and _ui.visible:
			_ui.visible = false

# ── Lua signal handlers ───────────────────────────────────────────
func _on_lua_move(vec: Vector2) -> void:
	match vec.y:
		S_AUTO_WORK:
			_pending_action = "auto_work"
		S_RETURN_SPAWN:
			_pending_action = "return_spawn"
		S_DEPOSIT_CHEST:
			_pending_action = "deposit_chest"
		S_CHEST_ITEMS:
			_pending_action = "chest_items"
		S_SET_RADIUS:
			pass  # radius is fixed at 20 blocks — ignore custom radius (kept for debug)
		_:
			_robot_vel = vec   # normal velocity move

func _on_lua_interact() -> void:
	if _is_working:
		return
	_is_working = true
	match _pending_action:
		"auto_work":     _auto_work.call_deferred()
		"return_spawn":  _walk_to_spawn_then_stop.call_deferred()
		"deposit_chest": _deposit_then_stop.call_deferred()
		"chest_items":   _print_chest_items.call_deferred()
		_:               _chop_all_trees.call_deferred()   # default / chop_trees()
	_pending_action = "chop"

func _on_lua_attack()                            -> void: pass
func _on_lua_place_item(_n: String)              -> void: pass
func _on_lua_print(_t: String)                   -> void: pass

func _on_lua_drop_item(name: String, qty: int) -> void:
	var data := _find_item_data_by_name(name)
	if data == null: return
	var scene: PackedScene = load("res://scenes/ui/InventoryItem.tscn") as PackedScene
	for _i in range(qty):
		var inst: Node = scene.instantiate()
		inst.call("set_item_data", data)
		(inst as Node2D).global_position = _robot.global_position + Vector2(randf_range(-20,20), randf_range(-20,20))
		get_parent().add_child(inst)

# ── Public: called by the Lua editor Stop button ──────────────────
func stop_work() -> void:
	_stop_requested = true
	_robot_vel      = Vector2.ZERO

# ─────────────────────────────────────────────────────────────────
# ── AUTONOMOUS BEHAVIOURS ─────────────────────────────────────────
# ─────────────────────────────────────────────────────────────────

func _auto_work() -> void:
	while true:
		if _stop_requested: break
		var tree: Node2D = _nearest_tree_in_radius()
		if tree == null: break
		await _walk_to_node(tree)
		if _stop_requested: break
		while is_instance_valid(tree):
			if _stop_requested: break
			tree.call("chop", CHOP_DELAY)
			await get_tree().create_timer(CHOP_DELAY).timeout
		await get_tree().create_timer(PICKUP_DELAY).timeout
		_collect_drops_nearby()

	if not _stop_requested:
		var chest: Node = _nearest_chest_in_radius()
		if chest != null and is_instance_valid(chest):
			await _walk_to_node(chest as Node2D)
			_deposit_to_chest(chest)
		await _walk_to_spawn()

	_stop_requested = false
	_is_working     = false

func _chop_all_trees() -> void:
	while true:
		if _stop_requested: break
		var tree: Node2D = _nearest_tree_in_radius()
		if tree == null: break
		await _walk_to_node(tree)
		if _stop_requested: break
		while is_instance_valid(tree):
			if _stop_requested: break
			tree.call("chop", CHOP_DELAY)
			await get_tree().create_timer(CHOP_DELAY).timeout
		await get_tree().create_timer(PICKUP_DELAY).timeout
		_collect_drops_nearby()

	if not _stop_requested:
		await _walk_to_spawn()
	_stop_requested = false
	_is_working     = false

func _walk_to_spawn_then_stop() -> void:
	await _walk_to_spawn()
	_is_working = false

func _deposit_then_stop() -> void:
	var chest: Node = _nearest_chest_in_radius()
	if chest != null and is_instance_valid(chest):
		await _walk_to_node(chest as Node2D)
		_deposit_to_chest(chest)
	await _walk_to_spawn()
	_is_working = false

func _print_chest_items() -> void:
	var chest: Node = _nearest_chest_in_radius()
	if chest == null or not is_instance_valid(chest):
		_lua_state.emit_signal("signal_print", "No chest in radius.")
		_is_working = false
		return
	var items: Array = chest.call("get_items")
	var found: bool = false
	for slot in items:
		if slot == null: continue
		var data: ItemData = (slot as Dictionary)["data"] as ItemData
		var qty:  int      = (slot as Dictionary)["quantity"]
		_lua_state.emit_signal("signal_print", "%s x%d" % [data.item_name, qty])
		found = true
	if not found:
		_lua_state.emit_signal("signal_print", "Chest is empty.")
	_is_working = false

# ── Walk helpers ──────────────────────────────────────────────────

# Walk robot toward a world node.
func _walk_to_node(target: Node2D) -> void:
	while is_instance_valid(target):
		var dist: float = _robot.global_position.distance_to(target.global_position)
		if dist <= APPROACH_PX:
			_robot_vel = Vector2.ZERO
			return
		_robot_vel = _robot.global_position.direction_to(target.global_position) * NPC_SPEED
		await get_tree().process_frame
	_robot_vel = Vector2.ZERO

# Walk robot back to station origin (position 0,0 relative to station).
func _walk_to_spawn() -> void:
	while _robot.position.length() > 8.0:
		_robot_vel = (_robot.position * -1.0).normalized() * NPC_SPEED
		await get_tree().process_frame
	_robot_vel    = Vector2.ZERO
	_robot.position = Vector2.ZERO

# ── Search helpers ────────────────────────────────────────────────

# Nearest tree within CHOP_RADIUS_PX of the STATION (not the robot).
func _nearest_tree_in_radius() -> Node2D:
	var best:  Node2D = null
	var best2: float  = CHOP_RADIUS_PX * CHOP_RADIUS_PX
	for node in get_tree().get_nodes_in_group("Tree"):
		if not (node is Node2D): continue
		var d: float = (node as Node2D).global_position.distance_squared_to(global_position)
		if d < best2:
			best2 = d
			best  = node as Node2D
	return best

# Nearest chest with space within station radius.
func _nearest_chest_in_radius() -> Node:
	var best:  Node  = null
	var best2: float = CHOP_RADIUS_PX * CHOP_RADIUS_PX
	for node in get_tree().get_nodes_in_group("Chest"):
		if not (node is Node2D): continue
		var d: float = (node as Node2D).global_position.distance_squared_to(global_position)
		if d < best2:
			if node.has_method("has_space") and node.call("has_space"):
				best2 = d
				best  = node
	return best

func _collect_drops_nearby() -> void:
	for item_node in get_tree().get_nodes_in_group("items"):
		if not (item_node is Node2D): continue
		var dist: float = (item_node as Node2D).global_position.distance_to(_robot.global_position)
		if dist > APPROACH_PX * 2.0: continue
		var data = item_node.get("item_data")
		if data == null and item_node.has_method("get_item_data"):
			data = item_node.call("get_item_data")
		if data != null:
			_npc_add_to_inventory(data as ItemData)
			item_node.queue_free()

func _npc_add_to_inventory(data: ItemData) -> void:
	for slot in _npc_inventory:
		if slot["data"] == data and slot["quantity"] < 32:
			slot["quantity"] += 1
			return
	_npc_inventory.append({"data": data, "quantity": 1})

func _deposit_to_chest(chest: Node) -> void:
	var to_remove: Array = []
	for slot in _npc_inventory:
		if chest.call("deposit_item", slot):
			to_remove.append(slot)
	for slot in to_remove:
		_npc_inventory.erase(slot)

# ─────────────────────────────────────────────────────────────────
# ── ITEM / SPRITE HELPERS ─────────────────────────────────────────
# ─────────────────────────────────────────────────────────────────
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
	"res://resources/items/chest.tres",
]

func _find_item_data_by_name(item_name: String) -> ItemData:
	for path in _ALL_ITEM_PATHS:
		if not ResourceLoader.exists(path): continue
		var data: ItemData = load(path) as ItemData
		if data != null and data.item_name == item_name:
			return data
	return null

func _build_frames() -> SpriteFrames:
	var sf := SpriteFrames.new()
	sf.remove_animation("default")
	for d in DIRS:
		var dir: String  = d["name"]
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
	if _robot_sprite.animation != anim:
		_robot_sprite.play(anim)

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
	if _robot_sprite.animation != anim:
		_robot_sprite.play(anim)
	_last_dir = best_dir
