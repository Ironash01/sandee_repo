extends CharacterBody2D

@export var movement_speed: int   = 80
const SPRINT_MULTIPLIER:   float = 1.8

const SHADOW_TEXTURE: Texture2D = preload("res://sprites/shadow/shadow_base.png")

@onready var sprite:           AnimatedSprite2D = $PlayerSprite
@onready var interaction_shape: CollisionShape2D = $Area2D/InteractionCol
@onready var inventory_layer:   CanvasLayer      = $InventoryUI

# Rebuilding costs ~72 texture lookups; caching mainly helps on scene reload/respawn.
static var _shared_frames: SpriteFrames = null

var input_direction: Vector2 = Vector2.ZERO
var _last_dir:   String = "south"   # default facing
var _sprinting:          bool  = false
var _stamina_exhausted:  bool  = false
var _move_mission_done:      bool  = false
var _inventory_mission_done: bool  = false
const STAMINA_RECOVER_THRESHOLD: float = 15.0

# Recomputed only on Inventory_updated/Hotbar_updated instead of every
# physics frame — avoids scanning both arrays with string ops at 60Hz.
var _has_boat_cached: bool = false
# Resolved once instead of walking the scene tree every physics frame.
var _world_node_cache: Node = null

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

# ── Lifecycle ─────────────────────────────────────────────────────
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	$mainCam.make_current()
	Global.set_player_reference(self)
	$mainCam.zoom = Vector2(Global.camera_zoom, Global.camera_zoom)
	Global.camera_zoom_changed.connect(_on_camera_zoom_changed)
	if _shared_frames == null:
		_shared_frames = _build_frames()
	sprite.sprite_frames = _shared_frames
	sprite.scale = Vector2(0.980, 0.980)
	# Offset tuned to sit under the feet — PlayerCol's collision box
	# (position.y 6.5, half-height 16.5) bottoms out around y=23.
	add_child(Global.make_shadow_sprite(SHADOW_TEXTURE, Vector2(0.0, 14.0), Vector2(0.8, 0.4), 0.35))
	sprite.play("idle_south")
	Global.request_close_all_ui.connect(_on_close_all_ui)
	if Global.has_pending_pos:
		global_position    = Global.pending_player_pos
		Global.has_pending_pos = false
	for m in Global.missions:
		if m["id"] == "move"           and m["completed"]: _move_mission_done      = true
		if m["id"] == "open_inventory" and m["completed"]: _inventory_mission_done = true
	Global.Inventory_updated.connect(_refresh_has_boat_cache)
	Global.Hotbar_updated.connect(_refresh_has_boat_cache)
	_refresh_has_boat_cache()

func _on_camera_zoom_changed(zoom: float) -> void:
	$mainCam.zoom = Vector2(zoom, zoom)

# ── Build SpriteFrames ────────────────────────────────────────────
func _build_frames() -> SpriteFrames:
	var sf := SpriteFrames.new()
	sf.remove_animation("default")

	for d in DIRS:
		var dir: String = d["name"]

		var idle_anim := "idle_" + dir.replace("-", "_")
		sf.add_animation(idle_anim)
		sf.set_animation_speed(idle_anim, 5.0)
		sf.set_animation_loop(idle_anim, true)
		for f in range(4):
			var path := "res://sprites/char/steve/animations/Breathing_Idle-a7ad4449/%s/frame_%03d.png" % [dir, f]
			sf.add_frame(idle_anim, load(path) as Texture2D)

		var walk_anim := "walk_" + dir.replace("-", "_")
		sf.add_animation(walk_anim)
		sf.set_animation_speed(walk_anim, 10.0)
		sf.set_animation_loop(walk_anim, true)
		for f in range(8):
			var path := "res://sprites/char/steve/animations/Walking-e6fa8864/%s/frame_%03d.png" % [dir, f]
			sf.add_frame(walk_anim, load(path) as Texture2D)

	return sf

# ── Input ─────────────────────────────────────────────────────────
func get_input() -> void:
	input_direction = Input.get_vector(
		"gameplay_left", "gameplay_right", "gameplay_up", "gameplay_down"
	).normalized()
	var want_sprint: bool = Input.is_key_pressed(KEY_SHIFT) and input_direction != Vector2.ZERO
	_sprinting = want_sprint and not _stamina_exhausted
	velocity = input_direction * movement_speed * (SPRINT_MULTIPLIER if _sprinting else 1.0)

func _physics_process(delta: float) -> void:
	if get_tree().paused:
		return
	z_index = int(global_position.y / 32)
	get_input()
	if not _move_mission_done and input_direction != Vector2.ZERO:
		_move_mission_done = true
		Global.complete_mission("move")
	# ── Water barrier — block movement into water tiles ───────────
	if not _has_boat_cached:
		var world_node := _get_world_node()
		if world_node != null:
			var water_layer: TileMapLayer = world_node.get_node_or_null("Water") as TileMapLayer
			if water_layer != null:
				_clamp_velocity_for_water(water_layer, delta)
	move_and_slide()
	_update_animation()
	_tick_stamina(delta)

func _tick_stamina(delta: float) -> void:
	if _sprinting:
		Global.stamina = maxf(0.0, Global.stamina - 10.0 * delta)
		if Global.stamina <= 0.0:
			_stamina_exhausted = true
	else:
		Global.stamina = minf(Global.max_stamina, Global.stamina + 5.0 * delta)
		if _stamina_exhausted and Global.stamina >= STAMINA_RECOVER_THRESHOLD:
			_stamina_exhausted = false
	Global.stamina_changed.emit(Global.stamina, Global.max_stamina)

# ── Boat / water helpers ──────────────────────────────────────────

# Clamp velocity per-axis so the player can slide along a shoreline.
func _clamp_velocity_for_water(water_layer: TileMapLayer, delta: float) -> void:
	const HALF_W: float = 10.0
	const HALF_H: float = 16.5
	const OY:     float = 6.5

	if velocity.x != 0.0:
		var sx: float     = sign(velocity.x)
		var lead_x: float = global_position.x + velocity.x * delta + sx * HALF_W
		var cy: float     = global_position.y + OY
		if _water_at(water_layer, Vector2(lead_x, cy - HALF_H)) \
		or _water_at(water_layer, Vector2(lead_x, cy)) \
		or _water_at(water_layer, Vector2(lead_x, cy + HALF_H)):
			velocity.x = 0.0

	if velocity.y != 0.0:
		var sy: float     = sign(velocity.y)
		var lead_y: float = global_position.y + OY + velocity.y * delta + sy * HALF_H
		var cx: float     = global_position.x
		if _water_at(water_layer, Vector2(cx - HALF_W, lead_y)) \
		or _water_at(water_layer, Vector2(cx,          lead_y)) \
		or _water_at(water_layer, Vector2(cx + HALF_W, lead_y)):
			velocity.y = 0.0

func _water_at(water_layer: TileMapLayer, global_pt: Vector2) -> bool:
	var tc: Vector2i = water_layer.local_to_map(water_layer.to_local(global_pt))
	return water_layer.get_cell_source_id(tc) != -1

func _refresh_has_boat_cache() -> void:
	_has_boat_cached = _compute_has_boat()

func _compute_has_boat() -> bool:
	for i in range(Global.Hotbar.size()):
		var slot = Global.Hotbar[i]
		if slot != null:
			var d: ItemData = slot["data"] as ItemData
			if d.item_type == "boat" or d.item_name.to_lower().contains("boat"):
				return true
	for i in range(Global.Inventory.size()):
		var slot = Global.Inventory[i]
		if slot != null:
			var d: ItemData = slot["data"] as ItemData
			if d.item_type == "boat" or d.item_name.to_lower().contains("boat"):
				return true
	return false

func _get_world_node() -> Node:
	if is_instance_valid(_world_node_cache):
		return _world_node_cache
	var scene: Node = get_tree().current_scene
	if scene == null:
		return null
	var world := scene.get_node_or_null("world_gen")
	if world == null:
		world = scene.get_node_or_null("World")
	if world == null and scene.has_node("Water"):
		world = scene
	_world_node_cache = world
	return world

# ── Animation ─────────────────────────────────────────────────────
func _get_closest_dir(vec: Vector2) -> String:
	var best_dir: String = _last_dir
	var best_dot: float  = -2.0
	for d in DIRS:
		var dot: float = vec.dot((d["vec"] as Vector2).normalized())
		if dot > best_dot:
			best_dot = dot
			best_dir = d["name"]
	return best_dir

func _update_animation() -> void:
	if input_direction == Vector2.ZERO:
		sprite.speed_scale = 1.0
		var anim := "idle_" + _last_dir.replace("-", "_")
		if sprite.animation != anim:
			sprite.play(anim)
	else:
		sprite.speed_scale = SPRINT_MULTIPLIER if _sprinting else 1.0
		_last_dir = _get_closest_dir(input_direction)
		var anim := "walk_" + _last_dir.replace("-", "_")
		if sprite.animation != anim:
			sprite.play(anim)

const _DEBUG_ITEM_PATHS: Array = [
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

func _give_debug_items() -> void:
	for path in _DEBUG_ITEM_PATHS:
		if not ResourceLoader.exists(path):
			continue
		var data: ItemData = load(path) as ItemData
		if data != null:
			Global.add_item({"quantity": 10, "data": data})

# ── UI management ─────────────────────────────────────────────────
func _on_close_all_ui() -> void:
	if inventory_layer.visible:
		inventory_layer.visible = false
		Global.close_ui()
		Global.inventory_toggled.emit(false)

func _input(event: InputEvent) -> void:
	# Debug shortcut must come before the inventory action check because
	# Shift+E would otherwise match the "inventory" action (same key, Shift ignored by action system)
	if event is InputEventKey and event.pressed \
			and event.keycode == KEY_E and event.shift_pressed:
		_give_debug_items()
		return

	if event is InputEventKey and event.pressed \
			and event.keycode == KEY_R and event.shift_pressed:
		Global.reset_missions()
		_move_mission_done      = false
		_inventory_mission_done = false
		return

	# Inventory key: can always close; blocked from opening when another UI is active
	if event.is_action_pressed("inventory"):
		if inventory_layer.visible:
			inventory_layer.visible = false
			Global.close_ui()
			Global.inventory_toggled.emit(false)
			get_viewport().set_input_as_handled()
		elif not Global.any_ui_open() and not Global.pause_menu_open:
			inventory_layer.visible = true
			Global.open_ui()
			Global.inventory_toggled.emit(true)
			get_viewport().set_input_as_handled()
			if not _inventory_mission_done:
				_inventory_mission_done = true
				Global.complete_mission("open_inventory")
		return

	if Global.any_ui_open() or Global.pause_menu_open:
		return

func apply_item_effect(item) -> void:
	match item["effect"]:
		"Sword": print("You touched my sword")
		_: print("No effect uWu")
