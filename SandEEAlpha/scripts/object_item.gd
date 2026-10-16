extends Node2D

# Furnace world object: the only placeable that uses ObjectItem.tscn. Left-
# click opens a standalone SmeltingMenu (own CanvasLayer, like the crafting
# station) — smelting does NOT live in the inventory panel anymore. Shift +
# left-click destroys the block and drops it back as an item.

@export var obj_name = ""
@export var obj_type = ""
@export var item_texture = Texture
@export var smelting_ui: PackedScene  # kept for scene compatibility
@onready var col_interact_shape = $Sprite2D/Area2D/interact_shape
@onready var _sprite: Sprite2D = $Sprite2D

# ── World registration (so Shift-destroy can unregister + drop the item) ──
var item_data:      ItemData = null
var _world_cell:    Vector2i = Vector2i(-99999, -99999)
var _world_ref:     Node     = null

# ── Shift-click breaking (respects the mining mechanic) ───────────
# Shift + left-click doesn't INSTANTLY destroy anymore — it runs the same
# hold-to-break mechanic as placed blocks: duration = block_level -
# pickaxe_level (min 0.1s), gated by min_pickaxe_level. Mirrors
# placeable_block.gd's breaking so the furnace breaks at the same speed/tier
# rules a mined block does. Break progress also accepts fresh shift-clicks
# (each adds CLICK_BREAK_SECONDS of work) and persists
# PROGRESS_PERSIST_SECONDS after the last hit, so spam-clicking works
# alongside holding, just like placed blocks.
var _breaking:       bool  = false
var _break_duration: float = 1.0
var _break_elapsed:  float = 0.0
var _break_progress: float = 0.0
var _last_hit_ms:    int   = -1

const CLICK_BREAK_SECONDS:      float = 0.5   # damage one shift-click adds
const PROGRESS_PERSIST_SECONDS: float = 2.5   # damage memory window
const WOBBLE_SNAPS_PER_SEC:     float = 3.0   # full left→right→left cycles per second
const WOBBLE_AMPLITUDE_RAD:     float = 0.045 # ~2.6° snap each side
const WOBBLE_FLIP_FRACTION:     float = 0.25  # fraction of each half spent flipping; the rest dwells

var _player_nearby: bool = false
var _ui:            Control = null

const ITEM_SCENE: PackedScene = preload("res://scenes/ui/InventoryItem.tscn")
# One-block-near interaction: origin-to-block distance for adjacent tiles is
# 32px (orthogonal) / ~45px (diagonal), two tiles is 64px — 48 admits only
# adjacent standing. Matches the Area2D radii CraftingStation.tscn and
# ChestBlock.tscn use (40px against the player's waist-high box).
const INTERACT_RADIUS_PX: float = 48.0

func _ready() -> void:
	col_interact_shape.disabled = true
	if obj_type == "furnace":
		furnace()
	Global.request_close_all_ui.connect(_on_close_all_ui)

	var menu_scene: PackedScene = load("res://scenes/ui/SmeltingMenu.tscn") as PackedScene
	if menu_scene == null:
		return
	var canvas := CanvasLayer.new()
	# Layer 2 (below the hotbar's 10) so the hotbar stays on top and its items
	# remain draggable into the furnace while this menu is open — same as the
	# inventory panel's layer.
	canvas.layer        = 2
	canvas.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(canvas)
	_ui = menu_scene.instantiate() as Control
	# Give the menu its furnace reference BEFORE it enters the tree so _ready()
	# wires the shared smelting state + programming host without a parent walk.
	_ui.set("furnace", self)
	canvas.add_child(_ui)
	_ui.visible = false

func setup(data: ItemData) -> void:
	item_data = data

func set_world_cell(cell: Vector2i, world: Node) -> void:
	_world_cell = cell
	_world_ref  = world

func furnace():
	col_interact_shape.disabled = false

func _on_close_all_ui() -> void:
	if _ui != null and _ui.visible:
		_ui.hide_menu()

func _process(delta: float) -> void:
	_tick_progress_expiry()
	if not _breaking:
		return
	if not _player_nearby \
			or not Input.is_key_pressed(KEY_SHIFT) \
			or not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		_cancel_breaking()
		return
	_break_elapsed  = minf(_break_elapsed + delta, _break_duration)
	_break_progress = _break_elapsed / _break_duration if _break_duration > 0.0 else 1.0
	_tick_wobble()
	queue_redraw()
	if _break_elapsed >= _break_duration:
		_do_break()

func _draw() -> void:
	if _break_progress <= 0.0:
		return
	Global.draw_break_bar(self, _break_progress)

func _on_area_2d_body_entered(body: CharacterBody2D) -> void:
	if body.is_in_group("Player"):
		_player_nearby = true

func _on_area_2d_body_exited(body: CharacterBody2D) -> void:
	if body.is_in_group("Player"):
		_player_nearby = false
		if _ui != null and _ui.visible:
			_ui.hide_menu()
		_cancel_breaking()

# Adds damage (in seconds of break work) from a held frame's delta or a
# fresh shift-click's flat CLICK_BREAK_SECONDS, then breaks when full.
func _add_break_progress(seconds: float) -> void:
	_break_elapsed  = minf(_break_elapsed + seconds, _break_duration)
	_break_progress = _break_elapsed / _break_duration if _break_duration > 0.0 else 1.0
	_last_hit_ms    = Time.get_ticks_msec()
	queue_redraw()
	if _break_elapsed >= _break_duration:
		_do_break()

# Damage fades from memory PROGRESS_PERSIST_SECONDS after the last hit —
# until then a returning player (or spam clicker) resumes where they left.
func _tick_progress_expiry() -> void:
	if _break_progress <= 0.0:
		return
	if Time.get_ticks_msec() - _last_hit_ms < int(PROGRESS_PERSIST_SECONDS * 1000.0):
		return
	_break_elapsed  = 0.0
	_break_progress = 0.0
	_last_hit_ms    = -1
	_sprite.rotation = 0.0
	queue_redraw()

# Snappy left↔right shake, played ONLY while actively breaking — releasing
# stops it immediately. The flip is eased-in so it lands hard on the target
# side, and the shape is continuous across half-cycle boundaries.
func _tick_wobble() -> void:
	var u: float = fposmod(Time.get_ticks_msec() / 1000.0 * WOBBLE_SNAPS_PER_SEC, 1.0)
	var target: float = 1.0 if u < 0.5 else -1.0   # side this half dwells on
	var source: float = -target                    # side the flip starts from
	var half: float   = fmod(u, 0.5)               # 0..0.5 into this half
	var p: float      = clampf(half / (0.5 * WOBBLE_FLIP_FRACTION), 0.0, 1.0)
	_sprite.rotation = lerpf(source, target, ease(p, 2.0)) * WOBBLE_AMPLITUDE_RAD

# Left-click (nearby) opens the standalone smelting menu; Shift + left-click
# mines this interactable off the wall (respecting pickaxe tier + break time).
func _input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT):
		return
	if Global.block_mode or Global.any_ui_open() or Global.pause_menu_open:
		return
	var p: Node2D = Global.player_node as Node2D
	if p == null or p.global_position.distance_to(global_position) > INTERACT_RADIUS_PX:
		return
	if Input.is_key_pressed(KEY_SHIFT):
		if event.pressed:
			_try_start_breaking()
			if _breaking:
				_add_break_progress(CLICK_BREAK_SECONDS)
		else:
			_cancel_breaking()
		get_viewport().set_input_as_handled()
		return
	if event.pressed and _ui != null:
		_ui.open_as_station()
		get_viewport().set_input_as_handled()

# Begin the mining process. No-op when no pickaxe is selected, the held
# pickaxe is below min_pickaxe_level, or it's already breaking.
func _try_start_breaking() -> void:
	if _breaking:
		return
	var pick_lvl := _held_pickaxe_level()
	if pick_lvl < 0:
		return  # no pickaxe in hand
	var min_lvl: int = item_data.min_pickaxe_level if item_data != null else 0
	if pick_lvl < min_lvl:
		return  # pickaxe tier too low
	var block_lvl: int = item_data.block_level if item_data != null else 0
	_break_duration = maxf(0.1, float(block_lvl - pick_lvl))
	# The swing animation plays for any item used to break — route through the
	# player so it fires even though this object consumed the click input.
	if Global.player_node != null and Global.player_node.has_method("swing_held_item"):
		Global.player_node.call("swing_held_item")
	# Keep damage accumulated within the persist window — a spam clicker (or
	# a player who walked away and came back) resumes where they left off.
	if _last_hit_ms < 0 \
			or Time.get_ticks_msec() - _last_hit_ms >= int(PROGRESS_PERSIST_SECONDS * 1000.0):
		_break_elapsed  = 0.0
		_break_progress = 0.0
	_breaking = true

func _cancel_breaking() -> void:
	if not _breaking:
		return
	_breaking        = false
	_sprite.rotation = 0.0

func _held_pickaxe_level() -> int:
	var slot = Global.get_hotbar_item()
	if slot == null:
		return -1
	var data: ItemData = (slot as Dictionary)["data"] as ItemData
	if data == null or data.pickaxe_level <= 0:
		return -1
	return data.pickaxe_level

# Break on completion: unregister from the world and drop the block item.
func _do_break() -> void:
	_cancel_breaking()
	var world: Node = _world_ref if _world_ref != null else Global.world_node
	if world != null and world.has_method("unregister_block"):
		world.call("unregister_block", _world_cell)
	if item_data != null:
		var drop: Node = ITEM_SCENE.instantiate()
		drop.call("set_item_data", item_data)
		var drop_parent: Node = _world_ref if _world_ref != null else Global.world_node
		if drop_parent != null:
			drop_parent.add_child(drop)
			(drop as Node2D).global_position = global_position + Vector2(randf_range(-20, 20), randf_range(-20, 20))
	queue_free()

# ═══════════════════════════════════════════════════════════════════
# ── Furnace automation (mirrors the Crafting Station programming) ───
# ═══════════════════════════════════════════════════════════════════
# All smelting state lives HERE, on the furnace object, not in the menu — so a
# program keeps running with the menu closed and the state persists with the
# world save. The menu is only a view that reads/writes these fields.
signal furnace_state_changed

const FURNACE_PYTHON_HOST_SCRIPT: GDScript = preload("res://scripts/furnace_python_host.gd")
const SMELT_RECIPE_DIR: String = "res://resources/recipes/"

var input_item:      ItemData = null
var input_quantity:  int      = 0
var fuel_item:       ItemData = null
var fuel_quantity:   int      = 0
var output_item:     ItemData = null
var output_quantity: int      = 0

var program_code:     String = ""
var program_language: String = "python"
var _program_host: Node = null

static var _smelt_recipe_cache: Array = []

static func all_smelting_recipes() -> Array:
	if _smelt_recipe_cache.is_empty():
		# ResourceLoader.list_directory (not DirAccess) so this survives export.
		for fname in ResourceLoader.list_directory(SMELT_RECIPE_DIR):
			if fname.ends_with(".tres"):
				var res: Resource = load(SMELT_RECIPE_DIR + fname)
				if res is SmeltingRecipe:
					_smelt_recipe_cache.append(res)
	return _smelt_recipe_cache

func smelting_recipe_for(item: ItemData) -> SmeltingRecipe:
	if item == null:
		return null
	for r in all_smelting_recipes():
		var rec: SmeltingRecipe = r
		if rec.input_item == item \
				or (rec.input_item != null and rec.input_item.resource_path == item.resource_path):
			return rec
	return null

func _stack_limit(data: ItemData) -> int:
	if data == null or not data.stackable:
		return 1
	return data.max_stack_size if data.max_stack_size > 0 else Global.MAX_STACK

# ── Slots ─────────────────────────────────────────────────────────
func get_input_stack() -> Dictionary:
	return {} if (input_item == null or input_quantity <= 0) else {"data": input_item, "quantity": input_quantity}
func get_fuel_stack() -> Dictionary:
	return {} if (fuel_item == null or fuel_quantity <= 0) else {"data": fuel_item, "quantity": fuel_quantity}
func get_output_stack() -> Dictionary:
	return {} if (output_item == null or output_quantity <= 0) else {"data": output_item, "quantity": output_quantity}

func put_input(data: ItemData, quantity: int) -> int:
	if data == null or quantity <= 0:
		return 0
	if input_item != null and input_item != data:
		return 0
	var add: int = mini(quantity, _stack_limit(data) - input_quantity)
	if add <= 0:
		return 0
	input_item = data
	input_quantity += add
	furnace_state_changed.emit()
	return add

func put_fuel(data: ItemData, quantity: int) -> int:
	if data == null or not data.is_fuel or quantity <= 0:
		return 0
	if fuel_item != null and fuel_item != data:
		return 0
	var add: int = mini(quantity, _stack_limit(data) - fuel_quantity)
	if add <= 0:
		return 0
	fuel_item = data
	fuel_quantity += add
	furnace_state_changed.emit()
	return add

func take_input(data: ItemData, quantity: int) -> int:
	if data == null or quantity <= 0 or input_item != data or input_quantity <= 0:
		return 0
	var take: int = mini(quantity, input_quantity)
	input_quantity -= take
	if input_quantity <= 0:
		input_quantity = 0
		input_item = null
	furnace_state_changed.emit()
	return take

func take_fuel(data: ItemData, quantity: int) -> int:
	if data == null or quantity <= 0 or fuel_item != data or fuel_quantity <= 0:
		return 0
	var take: int = mini(quantity, fuel_quantity)
	fuel_quantity -= take
	if fuel_quantity <= 0:
		fuel_quantity = 0
		fuel_item = null
	furnace_state_changed.emit()
	return take

# Move the output into the player's inventory one item at a time (so a full
# inventory can't destroy items). Returns how many were taken.
func take_output() -> int:
	if output_item == null or output_quantity <= 0:
		return 0
	var taken: int = 0
	for _i in range(output_quantity):
		if not Global.add_item({"quantity": 1, "data": output_item}):
			break
		taken += 1
	output_quantity -= taken
	if output_quantity <= 0:
		output_quantity = 0
		output_item = null
	if taken > 0:
		furnace_state_changed.emit()
	return taken

# Remove the whole output stack and return it, WITHOUT touching any inventory.
func take_output_stack() -> Dictionary:
	if output_item == null or output_quantity <= 0:
		return {}
	var stack: Dictionary = {"data": output_item, "quantity": output_quantity}
	output_item = null
	output_quantity = 0
	furnace_state_changed.emit()
	return stack

# ── Smelt (the validated entry point programs call) ───────────────
# Consumes input AND one fuel per item, produces the recipe's output. Fuel is
# SLOT-ONLY — it is never auto-consumed from the player's inventory.
func smelt_request(amount: int) -> int:
	if amount <= 0:
		return _smelt_fail("Invalid smelt amount")
	var rec: SmeltingRecipe = smelting_recipe_for(input_item)
	if input_item == null or rec == null:
		return _smelt_fail("No smeltable input loaded")
	if rec.output_item == null:
		return _smelt_fail("Recipe has no output")
	if output_item != null and output_item != rec.output_item:
		return _smelt_fail("Output slot holds a different item")
	if fuel_item == null or not fuel_item.is_fuel or fuel_item.fuel_level < rec.fuel_level_required:
		return _smelt_fail("No suitable fuel in the fuel slot")
	var n: int = mini(amount, input_quantity)
	n = mini(n, fuel_quantity)
	n = mini(n, _stack_limit(rec.output_item) - output_quantity)
	if n <= 0:
		return _smelt_fail("Nothing to smelt (input, fuel or output space)")
	input_quantity -= n
	if input_quantity <= 0:
		input_quantity = 0
		input_item = null
	fuel_quantity -= n
	if fuel_quantity <= 0:
		fuel_quantity = 0
		fuel_item = null
	output_item = rec.output_item
	output_quantity += n
	if rec.output_item.item_name.to_lower().contains("iron bar"):
		Global.add_mission_progress("smelt_iron", n)
	furnace_state_changed.emit()
	return n

# Load named items from the player's inventory into a specific slot. Returns
# how many were loaded. Input and fuel are SEPARATE (an item can be both a
# smeltable input and a fuel — e.g. Wood — so the slot is never inferred).
func load_input_named(data: ItemData, amount: int) -> int:
	return _load_from_inventory(data, amount, false)

func load_fuel_named(data: ItemData, amount: int) -> int:
	if data == null or not data.is_fuel:
		return 0
	return _load_from_inventory(data, amount, true)

func _load_from_inventory(data: ItemData, amount: int, as_fuel: bool) -> int:
	var accepted: int = 0
	for _i in range(amount):
		if Global.count_item(data) <= 0:
			break
		var put: int = put_fuel(data, 1) if as_fuel else put_input(data, 1)
		if put <= 0:
			break
		Global.remove_item(data)
		accepted += 1
	return accepted

func _smelt_fail(reason: String) -> int:
	var msg: String = "[smelt] " + reason
	if _program_host != null and is_instance_valid(_program_host):
		_program_host.emit_signal("signal_print", msg)
	else:
		print("[Furnace] ", msg)
	return 0

# ── Program execution ─────────────────────────────────────────────
func get_program_host() -> Node:
	if _program_host == null or not is_instance_valid(_program_host):
		_program_host = FURNACE_PYTHON_HOST_SCRIPT.new()
		_program_host.set("furnace", self)
		add_child(_program_host)
	return _program_host

func run_program(source: String) -> void:
	program_code = source
	var host: Node = get_program_host()
	host.set("code", source)
	host.call("run_code")

# ── Persistence ───────────────────────────────────────────────────
func get_furnace_save_data() -> Dictionary:
	return {
		"code":     program_code,
		"language": program_language,
		"input":    Global.serialize_item(get_input_stack()),
		"fuel":     Global.serialize_item(get_fuel_stack()),
		"output":   Global.serialize_item(get_output_stack()),
	}

func set_furnace_save_data(data: Dictionary) -> void:
	program_code = str(data.get("code", ""))
	var lang: String = str(data.get("language", "python"))
	program_language = lang if lang in ["python", "lua"] else "python"
	var in_slot: Variant = Global.deserialize_item(data.get("input", null))
	input_item     = (in_slot as Dictionary)["data"] as ItemData if in_slot != null else null
	input_quantity = int((in_slot as Dictionary)["quantity"]) if in_slot != null else 0
	var fuel_slot: Variant = Global.deserialize_item(data.get("fuel", null))
	fuel_item     = (fuel_slot as Dictionary)["data"] as ItemData if fuel_slot != null else null
	fuel_quantity = int((fuel_slot as Dictionary)["quantity"]) if fuel_slot != null else 0
	var out_slot: Variant = Global.deserialize_item(data.get("output", null))
	output_item     = (out_slot as Dictionary)["data"] as ItemData if out_slot != null else null
	output_quantity = int((out_slot as Dictionary)["quantity"]) if out_slot != null else 0
	furnace_state_changed.emit()
