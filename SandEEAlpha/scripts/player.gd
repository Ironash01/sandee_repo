extends CharacterBody2D

@export var movement_speed: int = 80

@onready var sprite:           AnimatedSprite2D = $PlayerSprite
@onready var interaction_shape: CollisionShape2D = $Area2D/InteractionCol
@onready var inventory_layer:   CanvasLayer      = $InventoryUI

var input_direction: Vector2 = Vector2.ZERO
var _last_dir: String = "south"   # default facing

# ── Direction map ─────────────────────────────────────────────────
# Maps 8-way input to sprite folder name
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

	sprite.sprite_frames = _build_frames()
	sprite.play("idle_south")

func _on_camera_zoom_changed(zoom: float) -> void:
	$mainCam.zoom = Vector2(zoom, zoom)

# ── Build SpriteFrames ────────────────────────────────────────────
func _build_frames() -> SpriteFrames:
	var sf := SpriteFrames.new()
	sf.remove_animation("default")

	for d in DIRS:
		var dir: String = d["name"]

		# Steve idle (4 frames)
		var idle_anim := "idle_" + dir.replace("-", "_")
		sf.add_animation(idle_anim)
		sf.set_animation_speed(idle_anim, 5.0)
		sf.set_animation_loop(idle_anim, true)
		for f in range(4):
			var path := "res://sprites/char/steve/animations/Breathing_Idle-a7ad4449/%s/frame_%03d.png" % [dir, f]
			sf.add_frame(idle_anim, load(path) as Texture2D)

		# Steve walk (8 frames)
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
	velocity = input_direction * movement_speed

func _physics_process(_delta: float) -> void:
	if get_tree().paused:
		return
	get_input()
	move_and_slide()
	_update_animation()

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
		# Idle — keep last direction
		var anim := "idle_" + _last_dir.replace("-", "_")
		if sprite.animation != anim:
			sprite.play(anim)
	else:
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

func _input(event: InputEvent) -> void:
	# Block all gameplay input while the Lua UI is open
	if Global.lua_ui_open or Global.station_ui_open:
		return
	# Debug: Shift+E gives all items
	if event is InputEventKey and event.pressed 			and event.keycode == KEY_E 			and event.shift_pressed:
		_give_debug_items()
		return
	if event.is_action_pressed("inventory"):
		var opening := not inventory_layer.visible
		inventory_layer.visible = opening
		Global.inventory_open   = opening
		if not Global.pause_on_inventory:
			get_tree().paused = false
		else:
			get_tree().paused = opening
		Global.inventory_toggled.emit(opening)

func apply_item_effect(item) -> void:
	match item["effect"]:
		"Sword": print("You touched my sword")
		_: print("No effect uWu")
