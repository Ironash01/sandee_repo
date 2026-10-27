extends Node2D

var _player_nearby: bool = false
var _ui:            Control = null
var _world_cell:    Vector2i = Vector2i(-99999, -99999)
var _world_ref:     Node     = null
var item_data:      ItemData = null

# ── Automation / programming state ────────────────────────────────
# The station owns this state; the UI only reads/writes it through the methods
# below (see the "Automation API" section at the bottom). Nothing here crafts
# on its own — craft_request() only runs when a program asks for it.
signal station_state_changed

const STATION_PYTHON_HOST_SCRIPT: GDScript = preload("res://scripts/station_python_host.gd")
const STATION_RECIPE_DIR: String = "res://resources/recipes/"
# Algorithmica craft_color() cost/limits. This is the same 1-Cactus-per-block
# economy as the manual Color Crafter, with the station's single output stack
# (32) as the per-call ceiling.
const CACTUS_DATA: ItemData = preload("res://resources/items/cactus.tres")
const COLOR_CHANNEL_MAX: int = 255
const COLOR_MAX_CRAFT: int = 32

## Recipe selected by Algorithmica's set_recipe() (code-only now).
var automation_recipe: CraftingRecipe = null
## Player's Python program, kept on the station so it survives UI rebuilds.
var program_code: String = ""
## Which language the Programming tab runs: "python" or "lua".
var program_language: String = "python"
## The station's single output slot.
var output_item:     ItemData = null
var output_quantity: int      = 0
## The station's single INPUT slot: items loaded here (by the player or the Lua
## robot) feed automatic crafting. A single stack; craft_request() consumes from
## here FIRST, then falls back to the player's inventory for the rest.
var input_item:      ItemData = null
var input_quantity:  int      = 0

var _program_host: Node = null
var _lua_host:     Node = null
# Recipe set is fixed at runtime, so discovery happens once for all stations.
static var _station_recipe_cache: Array = []

# ── Shift-click breaking (respects the mining mechanic) ───────────
# Shift + left-click doesn't INSTANTLY destroy anymore — it runs the same
# hold-to-break mechanic as placed blocks: duration = block_level -
# pickaxe_level (min 0.1s) and gated by min_pickaxe_level. Mirrors
# placeable_block.gd's breaking so the station breaks off the wall at the
# same speed/tier rules a mined block does. Break progress also accepts
# fresh shift-clicks (each adds CLICK_BREAK_SECONDS of work) and persists
# PROGRESS_PERSIST_SECONDS after the last hit before it's forgotten, so
# spam-clicking works alongside holding, just like placed blocks.
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

const ITEM_SCENE: PackedScene = preload("res://scenes/ui/InventoryItem.tscn")

@onready var _sprite:   Sprite2D = $Sprite2D
@onready var _interact: Area2D = $InteractArea

func setup(data: ItemData) -> void:
	item_data = data
	var sprite: Sprite2D = get_node_or_null("Sprite2D") as Sprite2D
	if sprite != null:
		# Placed world art: the ANIMATED sheet when the item ships one (sliced
		# into place_animation_frame_count frames), otherwise a single static
		# frame. placeable_sprite deliberately stays ONE 32x32 frame so the
		# build ghost and the place burst keep showing a single tile.
		if data.place_animation_sheet != null:
			sprite.texture = data.place_animation_sheet
			sprite.hframes = maxi(data.place_animation_frame_count, 1)
		else:
			sprite.texture = data.placeable_sprite if data.placeable_sprite != null else data.icon
			sprite.hframes = 1

func set_world_cell(cell: Vector2i, world: Node) -> void:
	_world_cell = cell
	_world_ref  = world

func _ready() -> void:
	if not Global.gameplay_input_cancelled.is_connected(_on_gameplay_input_cancelled):
		Global.gameplay_input_cancelled.connect(_on_gameplay_input_cancelled)
	process_mode = Node.PROCESS_MODE_ALWAYS
	# Lets nearby Lua robots find this station (see lua_npc.gd's
	# nearest_crafting_station), so their craft()/set_recipe() calls land here.
	add_to_group("CraftingStation")
	add_to_group("TouchInteractable")
	_interact.body_entered.connect(_on_body_entered)
	_interact.body_exited.connect(_on_body_exited)
	Global.request_close_all_ui.connect(_on_close_all_ui)

	var menu_scene: PackedScene = load("res://scenes/ui/CraftingMenu.tscn") as PackedScene
	var canvas := CanvasLayer.new()
	# Layer 2 (below the hotbar's 10) so the hotbar stays on top and its items
	# remain draggable into the station while this menu is open — same as the
	# inventory panel's layer.
	canvas.layer        = 2
	canvas.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(canvas)
	_ui = menu_scene.instantiate() as Control
	_ui.set_meta("station_mode", true)
	# Give the menu its station reference BEFORE it enters the tree so _ready()
	# can wire itself up without a fragile parent-depth walk.
	_ui.set("station", self)
	canvas.add_child(_ui)
	_ui.visible = false
	_play_place_animation()

# Play the placed-object animation authored for this item (idle_crafting).
# Done here, not only in world.gd's placement path, so save restores and the
# cave worlds — which insert the node directly — animate too. The
# AnimationPlayer lives at the scene root so the world's
# `obj.get_node_or_null("AnimationPlayer")` lookup finds it.
func _play_place_animation() -> void:
	if item_data == null or not item_data.has_place_animation \
			or item_data.place_animation_name.is_empty():
		return
	var ap: AnimationPlayer = get_node_or_null("AnimationPlayer") as AnimationPlayer
	if ap != null and ap.has_animation(item_data.place_animation_name):
		ap.play(item_data.place_animation_name)

func _on_close_all_ui() -> void:
	if _ui != null and _ui.visible:
		_ui.hide_menu()

func _process(delta: float) -> void:
	_tick_progress_expiry()
	if not _breaking:
		return
	if not _player_nearby \
			or not Global.is_shift_held() \
			or not Global.is_left_action_held():
		_cancel_breaking()
		return
	_break_elapsed  = minf(_break_elapsed + delta, _break_duration)
	_break_progress = _break_elapsed / _break_duration if _break_duration > 0.0 else 1.0
	Global.report_break_progress(_break_progress, global_position, -26.0, self)
	_tick_wobble()
	queue_redraw()
	if _break_elapsed >= _break_duration:
		_do_break()

func _draw() -> void:
	# Ring is drawn by BreakProgressOverlay above the world.
	pass

# Adds damage (in seconds of break work) from a held frame's delta or a
# fresh shift-click's flat CLICK_BREAK_SECONDS, then breaks when full.
func _add_break_progress(seconds: float) -> void:
	_break_elapsed  = minf(_break_elapsed + seconds, _break_duration)
	_break_progress = _break_elapsed / _break_duration if _break_duration > 0.0 else 1.0
	_last_hit_ms    = Time.get_ticks_msec()
	Global.report_break_progress(_break_progress, global_position, -26.0, self)
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
	Global.clear_break_progress(self)
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

# True when the cursor is over THIS station's sprite. Without it, every adjacent
# station in range reacted to the same click and the first in tree order consumed
# it — so clicking a specific station opened a different (previously placed) one.
func _cursor_over(at: Vector2 = Vector2.INF) -> bool:
	if _sprite == null or _sprite.texture == null:
		return true
	var r: Rect2 = _sprite.get_rect()
	var gt: Transform2D = _sprite.global_transform
	var a: Vector2 = gt * r.position
	var b: Vector2 = gt * (r.position + r.size)
	var lo := Vector2(minf(a.x, b.x), minf(a.y, b.y))
	var hi := Vector2(maxf(a.x, b.x), maxf(a.y, b.y))
	var m: Vector2 = Global.mouse_world(self) if at == Vector2.INF else at
	return m.x >= lo.x and m.x <= hi.x and m.y >= lo.y and m.y <= hi.y

func _input(event: InputEvent) -> void:
	if Global.is_mouse_event_over_ui(event):
		return
	if not _player_nearby or _ui == null or _ui.visible:
		return
	if Global.block_mode:
		return
	if Global.any_ui_open() or Global.pause_menu_open:
		return
	if not _cursor_over(Global.mouse_event_world(self, event)):
		return
	if event is InputEventMouseButton \
			and event.button_index == MOUSE_BUTTON_LEFT:
		# Shift + left-click: start mining this station off the wall (respects
		# pickaxe tier + break time). Without shift it opens the crafting UI.
		if Global.is_shift_held():
			if event.pressed:
				_try_start_breaking()
				if _breaking:
					_add_break_progress(CLICK_BREAK_SECONDS)
			else:
				_cancel_breaking()
			get_viewport().set_input_as_handled()
			return
		if event.pressed:
			_ui.open_as_station()

# Begin the mining process. No-op when no pickaxe is selected, the held
# pickaxe is below min_pickaxe_level, or it's already breaking.
func _try_start_breaking() -> void:
	if _breaking:
		return
	var held: Variant = Global.get_hotbar_item()
	var held_data: ItemData = null
	if held is Dictionary and (held as Dictionary).has("data"):
		held_data = (held as Dictionary)["data"] as ItemData
	var block_lvl: int = item_data.block_level if item_data != null else 0
	var is_wooden: bool = item_data != null and item_data.wooden_block

	if held_data != null and held_data.axe_level > 0 and is_wooden:
		# The station is wooden (item_data.wooden_block): an AXE chops it, with
		# the same hidden wooden-block bonus wooden blocks get. No pickaxe tier
		# is needed for the right tool.
		_break_duration = maxf(0.1, float(block_lvl)) / (1.0 + held_data.axe_wood_block_bonus())
	else:
		var pick_lvl := _held_pickaxe_level()
		if pick_lvl < 0:
			return  # no axe and no pickaxe in hand
		var min_lvl: int = item_data.min_pickaxe_level if item_data != null else 0
		if pick_lvl < min_lvl:
			return  # pickaxe tier too low
		# A pickaxe is the wrong tool for wood: the same 4x penalty wooden
		# blocks take, applied to the hardness so high tiers can't dodge it.
		var hardness: float = float(block_lvl)
		if is_wooden:
			hardness /= (1.0 - 0.75)
		_break_duration = maxf(0.1, hardness - float(Global.held_mining_level()))
	# The swing animation plays for any item used to break — route through the
	# player so it fires even though this station consumed the click input.
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
	Global.clear_break_progress(self)
	_sprite.rotation = 0.0

# The held PICKAXE's mining tier, or -1 when none is in hand. Delegates to
# Global so every break path shares one definition (see Global.held_pickaxe_level).
func _held_pickaxe_level() -> int:
	return Global.held_pickaxe_level()

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

## Touch HUD entry point: opens this station without requiring a mouse cursor
## or a click on the sprite. The player must still be inside the station's
## InteractArea, so the button cannot reach remote stations.
func open_from_touch() -> bool:
	if not _player_nearby or _ui == null or _ui.visible:
		return false
	if Global.block_mode or Global.any_ui_open() or Global.pause_menu_open:
		return false
	_ui.open_as_station()
	return true

func _on_body_entered(body: Node) -> void:
	if body.is_in_group("Player"):
		_player_nearby = true
		Global.player_near_station = true

func _on_body_exited(body: Node) -> void:
	if body.is_in_group("Player"):
		_player_nearby = false
		Global.player_near_station = false
		if _ui != null and _ui.visible:
			_ui.hide_menu()
		_cancel_breaking()

# ══════════════════════════════════════════════════════════════════
# AUTOMATION API
# The station is the single owner of automation state and the only thing that
# validates/performs program-requested crafting. The UI and player programs
# both go through these methods; neither touches the fields directly.
# ══════════════════════════════════════════════════════════════════

# ── Automation recipe ─────────────────────────────────────────────
# Every CraftingRecipe that requires a station — the same set the station's
# crafting tab offers. Discovered once and shared (the recipe set is fixed).
func get_station_recipes() -> Array:
	if _station_recipe_cache.is_empty():
		_station_recipe_cache = _discover_station_recipes()
	return _station_recipe_cache

static func _discover_station_recipes() -> Array:
	var out: Array = []
	# ResourceLoader.list_directory (not DirAccess) so this survives export —
	# see Global._load_resource_dir for why DirAccess misses .tres there.
	for fname in ResourceLoader.list_directory(STATION_RECIPE_DIR):
		if fname.ends_with(".tres"):
			var res: Resource = load(STATION_RECIPE_DIR + fname)
			if res is CraftingRecipe:
				var r: CraftingRecipe = res as CraftingRecipe
				if r.requires_station and r.result_item != null \
						and r.result_item.is_craftable and not r.result_item.is_dev_item:
					out.append(r)
	return out

func get_automation_recipe() -> CraftingRecipe:
	return automation_recipe

func get_automation_recipe_name() -> String:
	if automation_recipe == null or automation_recipe.result_item == null:
		return ""
	return automation_recipe.result_item.item_name

# Selecting a recipe is CONFIGURATION ONLY — it never crafts anything.
func set_automation_recipe(recipe: CraftingRecipe) -> bool:
	if recipe != null and not recipe.requires_station:
		return false
	automation_recipe = recipe
	_notify_state_changed()
	return true

# Select by result item name OR scripting id (case-insensitive) — used by the
# set_recipe() API. Accepts "Planks", "planks" and, for multi-word items,
# "iron_sword" as well as "Iron Sword".
func set_automation_recipe_by_name(name: String) -> bool:
	var want: String = name.strip_edges().to_lower()
	if want.is_empty():
		return false
	for r in get_station_recipes():
		var recipe: CraftingRecipe = r as CraftingRecipe
		if recipe.result_item == null:
			continue
		if recipe.result_item.item_name.to_lower() == want \
				or recipe.result_item.item_id() == want:
			automation_recipe = recipe
			_notify_state_changed()
			return true
	return false

# ── Output slot (single) ──────────────────────────────────────────
func get_output_item() -> ItemData:
	return output_item

func get_output_quantity() -> int:
	return output_quantity

# {"data": ItemData, "quantity": int} or {} when empty — same shape the chest
# and inventory slots use.
func get_output_stack() -> Dictionary:
	if output_item == null or output_quantity <= 0:
		return {}
	return {"data": output_item, "quantity": output_quantity}

# Stack ceiling for one item: the item's own limit (or the global default),
# and 1 for non-stackable items (tools) — the same rule Global.add_item uses.
func _stack_limit(data: ItemData) -> int:
	if data == null:
		return 1
	if not data.stackable:
		return 1
	return data.max_stack_size if data.max_stack_size > 0 else Global.MAX_STACK

# ── Input slot (single) ───────────────────────────────────────────
func get_input_item() -> ItemData:
	return input_item

func get_input_quantity() -> int:
	return input_quantity

func get_input_stack() -> Dictionary:
	if input_item == null or input_quantity <= 0:
		return {}
	return {"data": input_item, "quantity": input_quantity}

# Deposit into the input slot (single stack, one item type at a time). Returns
# how many were ACCEPTED (0 when the slot holds a different item or is full).
func put_input(data: ItemData, quantity: int) -> int:
	if data == null or quantity <= 0:
		return 0
	if input_item != null and input_item != data:
		return 0
	var space: int = _stack_limit(data) - input_quantity
	var add: int = mini(quantity, space)
	if add <= 0:
		return 0
	input_item      = data
	input_quantity += add
	_notify_state_changed()
	return add

# Remove up to `quantity` of `data` from the input slot; returns how many left.
func take_input(data: ItemData, quantity: int) -> int:
	if data == null or quantity <= 0 or input_item != data or input_quantity <= 0:
		return 0
	var take: int = mini(quantity, input_quantity)
	input_quantity -= take
	if input_quantity <= 0:
		input_quantity = 0
		input_item     = null
	_notify_state_changed()
	return take

# ── Craft request (the ONLY crafting entry point for programs) ─────
# Validates recipe + ingredients + output space, consumes the ingredients from
# the player's inventory, and stores the result in the station's output slot.
# All-or-nothing: returns the number of CRAFTS performed (== amount) on
# success, or 0 on any failure with the reason printed to the program console.
func craft_request(amount: int) -> int:
	if automation_recipe == null:
		return _craft_fail("No recipe selected")
	if amount <= 0:
		return _craft_fail("Invalid craft amount")
	var result: ItemData = automation_recipe.result_item
	if result == null or automation_recipe.ingredient_1 == null:
		return _craft_fail("Recipe is incomplete")
	if output_item != null and output_item != result:
		return _craft_fail("Output contains incompatible item")
	var per_craft: int  = maxi(1, automation_recipe.result_quantity)
	var produced:  int  = per_craft * amount
	var space:     int  = _stack_limit(result) - output_quantity
	if produced > space:
		return _craft_fail("Output slot full")
	if not _has_ingredients(automation_recipe, amount):
		return _craft_fail("Insufficient ingredients")
	# Consume ingredients — the input slot FIRST, then the player's inventory —
	# using the same per-item remove_item calls the manual CRAFT button makes,
	# so automation can't bypass the inventory rules.
	_consume_ingredient(automation_recipe.ingredient_1, automation_recipe.ingredient_1_quantity * amount)
	if automation_recipe.ingredient_2 != null:
		_consume_ingredient(automation_recipe.ingredient_2, automation_recipe.ingredient_2_quantity * amount)
	output_item     = result
	output_quantity += produced
	CrashLogger.event("CRAFT", "ok %s x%d" % [result.item_name, produced])
	_notify_state_changed()
	return amount

# Algorithmica craft_color(r, g, b, amount).
# 8-bit RGB, one Cactus per Color Block, output goes to the station's normal
# output slot. All validation happens before anything is consumed, so a failed
# request is atomic. Pure black/white are rejected by the existing ColorBlock
# rules; channel values are rejected rather than silently clamped.
func craft_color_request(r, g, b, amount) -> int:
	if typeof(r) != TYPE_INT or typeof(g) != TYPE_INT or typeof(b) != TYPE_INT:
		return _craft_color_fail("RGB channels must be integers 0-255")
	if typeof(amount) != TYPE_INT:
		return _craft_color_fail("Amount must be an integer")
	if amount <= 0 or amount > COLOR_MAX_CRAFT:
		return _craft_color_fail("Amount must be between 1 and %d" % COLOR_MAX_CRAFT)
	if r < 0 or r > COLOR_CHANNEL_MAX or g < 0 or g > COLOR_CHANNEL_MAX \
			or b < 0 or b > COLOR_CHANNEL_MAX:
		return _craft_color_fail("RGB channels must be between 0 and 255")
	if ColorBlock.is_forbidden(r, g, b):
		return _craft_color_fail("Pure black and pure white are not allowed")
	var block: ItemData = ColorBlock.get_block(r, g, b)
	if block == null:
		return _craft_color_fail("Could not create that color")
	if output_item != null and output_item != block:
		return _craft_color_fail("Output contains a different color")
	var space: int = _stack_limit(block) - output_quantity
	if amount > space:
		return _craft_color_fail("Output slot full")
	if _ingredient_available(CACTUS_DATA) < amount:
		return _craft_color_fail("Insufficient Cactus")
	# All-or-nothing: consume exactly once, after every validation passed.
	_consume_ingredient(CACTUS_DATA, amount)
	output_item = block
	output_quantity += amount
	_notify_state_changed()
	return amount

# Pull `count` of `data` from the input slot first, then the player inventory.
func _consume_ingredient(data: ItemData, count: int) -> void:
	if data == null or count <= 0:
		return
	var from_slot: int = take_input(data, count)
	for _i in range(count - from_slot):
		Global.remove_item(data)

func _has_ingredients(recipe: CraftingRecipe, crafts: int) -> bool:
	if recipe.ingredient_1 != null \
			and _ingredient_available(recipe.ingredient_1) < recipe.ingredient_1_quantity * crafts:
		return false
	if recipe.ingredient_2 != null \
			and _ingredient_available(recipe.ingredient_2) < recipe.ingredient_2_quantity * crafts:
		return false
	return true

# Total of `data` available to the station: its input slot + the player's
# inventory (hotbar included).
func _ingredient_available(data: ItemData) -> int:
	var n: int = Global.count_item(data)
	if input_item == data:
		n += input_quantity
	return n

# Move the output into the player's inventory ONE ITEM AT A TIME so a full
# inventory can never destroy items (Global.add_item returns false when it
# can't place one). Returns how many were taken.
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
		output_item     = null
	if taken > 0:
		_notify_state_changed()
	return taken

# Remove the whole output stack from the station and return it ({"data", "quantity"}
# or {}), WITHOUT touching any inventory. The Lua robot uses this so a craft's
# result lands in its OWN build slots rather than the player's inventory.
func take_output_stack() -> Dictionary:
	if output_item == null or output_quantity <= 0:
		return {}
	var stack: Dictionary = {"data": output_item, "quantity": output_quantity}
	output_item     = null
	output_quantity = 0
	_notify_state_changed()
	return stack

# ── Program execution ─────────────────────────────────────────────
# Lazily creates the Python host. The host is a child of THIS station, not of
# the UI, so program state outlives the menu and the UI never runs anything by
# itself — it just calls run_program().
func get_program_host() -> Node:
	if _program_host == null or not is_instance_valid(_program_host):
		_program_host = STATION_PYTHON_HOST_SCRIPT.new()
		_program_host.set("station", self)
		add_child(_program_host)
	return _program_host

# True while the host has a program mid-execution. Python runs synchronously,
# so this only matters if a program is somehow polled re-entrantly.
func is_program_running() -> bool:
	return false

# Runs the player's program. Stored on the station so it survives UI rebuilds.
func run_program(source: String) -> void:
	program_code = source
	CrashLogger.code("python", "RUN", "station=%s chars=%d\n%s" % [
		item_data.item_name if item_data != null else "Crafting Station",
		source.length(), source])
	var host: Node = get_program_host()
	host.set("code", source)
	host.call("run_code")

# ── Lua host (same LuaState the Lua robot uses — not a second interpreter) ──
func is_lua_available() -> bool:
	return ClassDB.class_exists("LuaState")

func get_lua_host() -> Node:
	if _lua_host == null or not is_instance_valid(_lua_host):
		_lua_host = LuaState.new()
		add_child(_lua_host)
		_lua_host.connect("signal_craft", _on_lua_craft)
		_lua_host.connect("signal_set_recipe", _on_lua_set_recipe)
		_lua_host.connect("signal_take_output", _on_lua_take_output)
		_lua_host.connect("signal_print", _on_station_lua_print)
		_lua_host.connect("code_executed", _on_station_lua_ok)
		_lua_host.connect("code_failed", _on_station_lua_fail)
	return _lua_host

# Publishes the station's automation state as Lua globals and runs the program.
# craft(n) / set_recipe(name) / take_output() arrive as LuaState signals and
# are routed through the same validated methods the Python API uses.
func run_lua_program(source: String) -> void:
	program_code = source
	CrashLogger.code("lua", "RUN", "station=%s chars=%d\n%s" % [
		item_data.item_name if item_data != null else "Crafting Station",
		source.length(), source])
	var host: Node = get_lua_host()
	host.set("station_recipe", get_automation_recipe_name())
	host.set("station_output_item", output_item.item_name if output_item != null else "")
	host.set("station_output_count", output_quantity)
	host.set("code", source)
	host.call("run_code")

func _on_lua_craft(quantity: int) -> void:
	craft_request(int(quantity))

func _on_lua_set_recipe(name: String) -> void:
	set_automation_recipe_by_name(name)

func _on_lua_take_output() -> void:
	take_output()

func _on_station_lua_print(text: String) -> void:
	CrashLogger.code("lua", "OUT", "station: " + text)

func _on_station_lua_ok() -> void:
	CrashLogger.code("lua", "OK", "station code finished")

func _on_station_lua_fail(error: String) -> void:
	CrashLogger.code("lua", "FAIL", "station: " + error)

# ── Persistence ───────────────────────────────────────────────────
func get_station_save_data() -> Dictionary:
	return {
		"recipe_path":      automation_recipe.resource_path if automation_recipe != null else "",
		"code":             program_code,
		"language":         program_language,
		"output":           Global.serialize_item({"data": output_item, "quantity": output_quantity} if output_item != null else null),
		"input":            Global.serialize_item({"data": input_item, "quantity": input_quantity} if input_item != null else null),
	}

func set_station_save_data(data: Dictionary) -> void:
	var recipe_path: String = str(data.get("recipe_path", ""))
	if not recipe_path.is_empty() and ResourceLoader.exists(recipe_path):
		set_automation_recipe(load(recipe_path) as CraftingRecipe)
	program_code = str(data.get("code", ""))
	var lang: String = str(data.get("language", "python"))
	program_language = lang if lang in ["python", "lua"] else "python"
	var out_slot: Variant = Global.deserialize_item(data.get("output", null))
	if out_slot != null:
		output_item     = (out_slot as Dictionary)["data"] as ItemData
		output_quantity = int((out_slot as Dictionary)["quantity"])
	else:
		output_item     = null
		output_quantity = 0
	var in_slot: Variant = Global.deserialize_item(data.get("input", null))
	if in_slot != null:
		input_item     = (in_slot as Dictionary)["data"] as ItemData
		input_quantity = int((in_slot as Dictionary)["quantity"])
	else:
		input_item     = null
		input_quantity = 0
	_notify_state_changed()

# ── Internals ─────────────────────────────────────────────────────
func _notify_state_changed() -> void:
	station_state_changed.emit()

# Reports a rejected request both to the program console (when a host exists)
# and the Godot log, so failures are never silent.
func _craft_fail(reason: String) -> int:
	CrashLogger.event("CRAFT", "fail: " + reason)
	var msg: String = "[craft] " + reason
	if _program_host != null and is_instance_valid(_program_host):
		_program_host.emit_signal("signal_print", msg)
	else:
		print("[CraftingStation] ", msg)
	return 0

func _craft_color_fail(reason: String) -> int:
	var msg: String = "[craft_color] " + reason
	if _program_host != null and is_instance_valid(_program_host):
		_program_host.emit_signal("signal_print", msg)
	else:
		print("[CraftingStation] ", msg)
	return 0

# UI-only recolor of an already-crafted color output block. Quantity, material
# accounting and the Python API are untouched; the player can inspect the block
# as RGB or HEX and edit that representation before taking it.
func recolor_output(r, g, b) -> bool:
	if output_item == null or not output_item.is_color_block or output_quantity <= 0:
		return false
	if typeof(r) != TYPE_INT or typeof(g) != TYPE_INT or typeof(b) != TYPE_INT:
		return false
	if r < 0 or r > COLOR_CHANNEL_MAX or g < 0 or g > COLOR_CHANNEL_MAX \
			or b < 0 or b > COLOR_CHANNEL_MAX:
		return false
	if ColorBlock.is_forbidden(r, g, b):
		return false
	var block: ItemData = ColorBlock.get_block(r, g, b)
	if block == null:
		return false
	output_item = block
	_notify_state_changed()
	return true

func _on_gameplay_input_cancelled() -> void:
	if _breaking:
		_cancel_breaking()
