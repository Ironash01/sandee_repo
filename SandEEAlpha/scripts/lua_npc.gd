extends Node2D
# ─────────────────────────────────────────────────────────────────
# LUA STATION — the placed beacon block.
# This node's global_position is the permanent spawn point.
# The robot is a child Node2D that moves relative to the station.
# ─────────────────────────────────────────────────────────────────

# Fired when the robot's build palette contents change (player drag, chest
# withdraw, or a placement consuming a block) so the editor UI can refresh.
signal build_palette_changed

# The ItemData this station was placed from (the "LUA" item). world.gd's save
# routine reads node.item_data to persist placed blocks, and place_block_at()
# calls setup() — without both, the station (and its Robot child) was never
# saved and vanished on reload.
var item_data: ItemData = null

func setup(data: ItemData) -> void:
	item_data = data

const TILE_SIZE:          float = 32.0
const CHOP_RADIUS_BLOCKS: int   = 20
const CHOP_RADIUS_PX:     float = CHOP_RADIUS_BLOCKS * TILE_SIZE  # 640 px
const APPROACH_PX:        float = 40.0
const CHOP_DELAY:         float = 0.25
const PICKUP_DELAY:       float = 0.4
const NPC_SPEED:          float = 90.0
const SHADOW_TEXTURE:     Texture2D = preload("res://sprites/shadow/shadow_base.png")

# ── Y-sort (robot visual) ────────────────────────────────────────
# The robot sprite is CENTERED on the Robot node, so the node origin sits at
# the sprite's middle, not its feet. Sorting on the origin (the old behaviour)
# put the robot half a tile too high, so it drew behind trees/blocks it was
# standing in front of. Offset to the sprite's bottom line, then add the same
# half-tile tiebreak the player uses. The floating-entity art is 52px tall at
# scale 1.0, so the visual bottom sits 26px below the origin.
const ROBOT_FEET_OFFSET: float = 26.0
const YSORT_TIEBREAK:    float = 16.0   # half a tile — matches player.gd

# ── Floating bob ──────────────────────────────────────────────────
# The robot hovers, so its sprite gently bobs up/down while it moves and
# settles to rest when idle. The ground shadow stays put on the floor (only
# shrinking a touch as the robot rises) so the bob reads as hovering.
const BOB_AMPLITUDE: float = 2.5
const BOB_SPEED:     float = 6.5
const SHADOW_OFFSET_Y: float = 28.0     # shadow sits at the sprite's base
var _bob_t: float = 0.0
var _shadow: Sprite2D = null
var _shadow_scale: Vector2 = Vector2(0.7, 0.32)

# ── Floating-entity sprite set ────────────────────────────────────
# The robot is now a FLOATING entity (no walk cycle): one static sprite per
# direction, taken from the 3 layer groups of sprites/lua.aseprite
# (front/back/side). Diagonals reuse the nearest cardinal; west mirrors side.
const TEX_FRONT: Texture2D = preload("res://sprites/char/lua/front.png")
const TEX_BACK:  Texture2D = preload("res://sprites/char/lua/back.png")
const TEX_SIDE:  Texture2D = preload("res://sprites/char/lua/side.png")
const LUA_OUTLINE_SHADER: Shader = preload("res://shaders/lua_outline.gdshader")
const DIR_TEX: Dictionary = {
	"north": TEX_BACK,  "north-east": TEX_BACK,  "north-west": TEX_BACK,
	"south": TEX_FRONT, "south-east": TEX_FRONT, "south-west": TEX_FRONT,
	"east":  TEX_SIDE,  "west":       TEX_SIDE,
}

# ── Obstacle avoidance / stuck detection ─────────────────────────
# Trees, placed blocks, chests, etc. are all StaticBody2D on the default
# physics layer (bit 0) — same layer the player's CharacterBody2D collides
# against — so a raycast on that mask reliably detects anything solid.
const OBSTACLE_MASK:         int   = 1
const OBSTACLE_LOOKAHEAD_PX: float = 28.0  # a bit under one tile (32px)
# Angles tried, in order, either side of the direct line to the target when
# that line is blocked — sweeps out to a full about-face for dead ends.
const REROUTE_ANGLES_DEG: Array = [45.0, -45.0, 90.0, -90.0, 135.0, -135.0, 180.0]
const STUCK_TIMEOUT_MS:   int   = 4000  # no net progress for this long → give up
const STUCK_PROGRESS_EPS: float = 4.0   # px of closing distance that counts as progress

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

# ── Build palette (robot's 3-slot block supply) ───────────────────
# A small hotbar the robot places FROM. Three STACK slots; select_block(i)
# chooses which one place_item() uses. Filled by the player dragging a block
# into a slot (LuaEditorUI) or by the robot itself — chop/collect adds wood,
# withdraw(name, n) pulls from the nearest chest.
const BUILD_SLOTS: int = 3
var _build_palette: Array = []           # [ {data, quantity} | null, x3 ]
# rename(name) — custom name shown above the robot.
var _custom_name: String = ""
var _name_label:  Label  = null
var _selected_slot: int   = 0            # 0-based; the slot place_item uses

# ── Node refs ─────────────────────────────────────────────────────
var _lua_state:    Node    = null
var _ui:           Control = null

@onready var _robot:        CharacterBody2D  = $Robot
@onready var _robot_sprite: AnimatedSprite2D = $Robot/RobotSprite
@onready var _click_area:   Area2D           = $ClickArea
@onready var _beacon:       Sprite2D         = $BeaconSprite

# Shared across every Lua station robot — built once instead of per-instance
# when multiple stations are placed.
static var _shared_frames: SpriteFrames = null

# ─────────────────────────────────────────────────────────────────
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_palette.resize(BUILD_SLOTS)

	if _shared_frames == null:
		_shared_frames = _build_frames()
	_robot_sprite.sprite_frames = _shared_frames
	# Glowing outline (a floating entity reads better lit up). Uses the sprite's
	# own texture, so it tracks whichever direction frame is showing.
	var outline := ShaderMaterial.new()
	outline.shader = LUA_OUTLINE_SHADER
	_robot_sprite.material = outline
	_play_idle(_last_dir)
	# Attached to _robot (not the station) so it moves with the robot as it walks.
	# Ground shadow at the robot's base (same soft blob the player/mobs use).
	_shadow = Global.make_shadow_sprite(SHADOW_TEXTURE, Vector2(0.0, SHADOW_OFFSET_Y), _shadow_scale, 0.4)
	_robot.add_child(_shadow)

	# ── Y-sorting ─────────────────────────────────────────────────
	# place_block() stamps a static z_index on this node from the tile it was
	# placed on, but the robot WALKS away from that spot (and the node is moved
	# into position AFTER _ready). Both visuals get z_as_relative = false and
	# have their z recomputed each frame from their OWN base line, using the
	# same int(y / TILE_SIZE) buckets the player, mobs, trees and grass use.
	# The robot sorts from its FEET (origin + ROBOT_FEET_OFFSET + tiebreak),
	# not its origin, so it overlaps trees/blocks the same way the player does.
	_robot.z_as_relative  = false
	_beacon.z_as_relative = false

	_click_area.body_entered.connect(_on_body_entered)
	_click_area.body_exited.connect(_on_body_exited)
	_click_area.input_event.connect(_on_station_input_event)
	_click_area.input_pickable = true
	# Mouse picking needs BOTH input_pickable AND a non-zero collision_layer:
	# an area on layer 0 is invisible to the viewport's point query, so
	# input_event would never fire. Layer 8 is unused by everything else, so
	# enabling picking here can't be caught by any gameplay collision mask.
	_click_area.collision_layer = 8
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
	_lua_state.connect("signal_place_at",   _on_lua_place_at)
	_lua_state.connect("signal_select_block", _on_lua_select_block)
	_lua_state.connect("signal_withdraw",   _on_lua_withdraw)
	_lua_state.connect("signal_print",      _on_lua_print)
	# Crafting Station API (craft/set_recipe/take_output) — routed to the
	# nearest placed Crafting Station so a Lua program can drive one.
	_lua_state.connect("signal_craft",       _on_lua_craft)
	_lua_state.connect("signal_set_recipe",  _on_lua_set_recipe)
	_lua_state.connect("signal_take_output", _on_lua_take_output)
	_lua_state.connect("signal_put_input",   _on_lua_put_input)
	_lua_state.connect("signal_input_slot",  _on_lua_input_slot)
	# mine(name, radius) + rename(name).
	_lua_state.connect("signal_mine",        _on_lua_mine)
	_lua_state.connect("signal_rename",      _on_lua_rename)

	# Persistent name label above the robot (set by rename()).
	_name_label = Label.new()
	_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name_label.add_theme_font_size_override("font_size", 12)
	_name_label.add_theme_color_override("font_color", Color(0.85, 0.95, 1.0, 1.0))
	_name_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	_name_label.add_theme_constant_override("outline_size", 3)
	_name_label.position = Vector2(-60, -58)
	_name_label.size     = Vector2(120, 16)
	_name_label.visible  = false
	_robot.add_child(_name_label)

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
# Robot is a CharacterBody2D so move_and_slide() gives it real collision
# against trees/blocks/chests as a hard backstop — the raycast steering in
# the walk helpers picks a clear direction, but this is what actually stops
# it from ever tunnelling through an obstacle the steering missed.
func _physics_process(delta: float) -> void:
	# Sort by each visual's own feet line every frame — the robot walks far
	# from the station's fixed bucket, so a static z_index would leave it drawn
	# behind trees/blocks it is standing in front of (and vice versa). The
	# robot sprite is centered on the Robot node, so add ROBOT_FEET_OFFSET to
	# reach the feet, plus the player's half-tile tiebreak. The beacon is
	# recomputed too because the node is positioned after _ready.
	_robot.z_index  = int((_robot.global_position.y + ROBOT_FEET_OFFSET + YSORT_TIEBREAK) / TILE_SIZE)
	_beacon.z_index = int(global_position.y / TILE_SIZE)
	if _robot_vel != Vector2.ZERO:
		_robot.velocity = _robot_vel
		_robot.move_and_slide()
		_update_walk_animation(_robot_vel)
	else:
		_robot.velocity = Vector2.ZERO
		_play_idle(_last_dir)

	# Floating bob — only the SPRITE moves; the ground shadow stays put and
	# shrinks a little as the robot rises so the hover reads correctly.
	if _robot_vel != Vector2.ZERO:
		_bob_t += delta * BOB_SPEED
		_robot_sprite.position.y = sin(_bob_t) * BOB_AMPLITUDE
	else:
		_robot_sprite.position.y = move_toward(_robot_sprite.position.y, 0.0, delta * 40.0)
	if _shadow != null and is_instance_valid(_shadow):
		var lift: float   = _robot_sprite.position.y / BOB_AMPLITUDE if BOB_AMPLITUDE > 0.0 else 0.0
		var shrink: float = clampf(1.0 - lift * 0.18, 0.7, 1.0)
		_shadow.scale = Vector2(_shadow_scale.x * shrink, _shadow_scale.y * shrink)

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
			# open_panel() re-syncs RUN/STOP with the robot's real state —
			# plainly setting visible=true would leave STOP disabled (and a
			# still-running robot unstoppable) after a close/reopen.
			if _ui.has_method("open_panel"):
				_ui.call("open_panel")
			else:
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

# The robot has no weapon-swing art, so an attack reads as a magic slash aimed
# the way it last faced (see magic_swing.gd).
func _on_lua_attack() -> void:
	var world: Node = Global.world_node
	if world != null:
		MagicSwing.spawn(world, global_position + Vector2(0.0, -10.0), _facing_vec(), 1.0, 5)

# _last_dir (a DIRS name) -> a unit vector.
func _facing_vec() -> Vector2:
	for d in DIRS:
		if d["name"] == _last_dir:
			return d["vec"] as Vector2
	return Vector2(0.0, 1.0)

func _on_lua_print(_t: String) -> void: pass

# ── Building (place_item / place_at / select_block / withdraw) ─────
# The robot places from its 3-slot build palette. Every placement reuses the
# world's own validity rules (World.can_place_at), so the robot obeys exactly
# the same water/tree/grass/occupancy constraints the player does. Calls drain
# ONE PER PHYSICS FRAME (see LuaState.physics_process), so a Lua loop that
# places 40 blocks visibly builds them over ~40 frames — paced for free.

func _on_lua_select_block(index: int) -> void:
	_selected_slot = clampi(index, 0, BUILD_SLOTS - 1)

# Relative: place at (robot_tile + dx, robot_tile + dy).
func _on_lua_place_item(dx: int, dy: int) -> void:
	var world: Node = Global.world_node
	if world == null or not world.has_method("world_to_cell"):
		return
	var robot_cell: Vector2i = world.call("world_to_cell", _robot.global_position)
	_place_from_palette(world, robot_cell + Vector2i(dx, dy))

# Absolute: place at tile (x, y).
func _on_lua_place_at(x: int, y: int) -> void:
	var world: Node = Global.world_node
	if world == null or not world.has_method("can_place_at"):
		return
	_place_from_palette(world, Vector2i(x, y))

# Shared: consume one from the selected slot and place it, if legal + in range.
func _place_from_palette(world: Node, cell: Vector2i) -> bool:
	var slot: Variant = _build_palette[_selected_slot] if _selected_slot < _build_palette.size() else null
	if slot == null:
		_build_warn("Build slot %d is empty — give the robot blocks first (drag them in, or withdraw(\"Wood\", n))." % [_selected_slot + 1])
		return false
	var data: ItemData = (slot as Dictionary)["data"] as ItemData
	if data == null or not data.is_placeable:
		_build_warn("The selected build slot does not hold a placeable block.")
		return false
	# Reach: same radius the robot works within, measured from the STATION.
	if cell_to_world_dist(world, cell, global_position) > CHOP_RADIUS_PX:
		_build_warn("Placement out of range (further than the work radius).")
		return false
	if world.has_method("can_place_at") and not world.call("can_place_at", cell):
		_build_warn("Cannot place there — the tile is blocked.")
		return false
	var obj: Node = null
	if world.has_method("place_block_at"):
		obj = world.call("place_block_at", cell, data)
	if obj == null:
		return false
	# Consume one from the slot.
	var qty: int = int((slot as Dictionary)["quantity"]) - 1
	if qty <= 0:
		_build_palette[_selected_slot] = null
	else:
		(slot as Dictionary)["quantity"] = qty
	build_palette_changed.emit()
	return true

# Build failures fire once per placement, which a 40-block loop would spam — so
# throttle notices to one every 1.5s.
var _last_build_warn_ms: int = 0

func _build_warn(msg: String) -> void:
	var now: int = Time.get_ticks_msec()
	if now - _last_build_warn_ms < 1500:
		return
	_last_build_warn_ms = now
	_lua_notice(msg)

# Distance (px) from a tile cell to a world point — the tile's CENTRE.
func cell_to_world_dist(world: Node, cell: Vector2i, from: Vector2) -> float:
	if not world.has_method("cell_to_world"):
		return 0.0
	return (world.call("cell_to_world", cell) as Vector2).distance_to(from)

# withdraw(name, quantity): walk to the nearest chest and pull that item into
# the build palette (then the leftover into the general robot inventory).
func _on_lua_withdraw(name: String, quantity: int) -> void:
	_withdraw_from_chest.call_deferred(name, maxi(quantity, 1))

func _withdraw_from_chest(name: String, quantity: int) -> void:
	if _is_working:
		return
	_is_working = true
	var chest: Node = _nearest_chest_in_radius()
	if chest != null and is_instance_valid(chest):
		if not await _walk_to_node(chest as Node2D):
			_is_working = false
			return
		var data := _find_item_data_by_name(name)
		if data != null:
			var taken: int = _take_from_chest(chest, data, quantity)
			if taken > 0:
				_npc_add_to_palette(data, taken)
	_abort_work()

# Removes up to `quantity` of `data` from a chest and returns how many were
# actually removed, via the chest's own take_item() (no reaching into its slots).
func _take_from_chest(chest: Node, data: ItemData, quantity: int) -> int:
	if not chest.has_method("take_item"):
		return 0
	return int(chest.call("take_item", data, quantity))

# Adds `count` of `data` to the first build-palette slot that already holds it,
# else the first empty slot. Falls back to the general inventory when full.
func _npc_add_to_palette(data: ItemData, count: int) -> void:
	var remaining: int = count
	var stack_limit: int = data.max_stack_size if data != null and data.max_stack_size > 0 else Global.MAX_STACK
	for i in range(_build_palette.size()):
		if remaining <= 0:
			break
		var slot: Variant = _build_palette[i]
		if slot == null:
			continue
		if (slot as Dictionary)["data"] == data and int((slot as Dictionary)["quantity"]) < stack_limit:
			var space: int = stack_limit - int((slot as Dictionary)["quantity"])
			var add: int = mini(remaining, space)
			(slot as Dictionary)["quantity"] = int((slot as Dictionary)["quantity"]) + add
			remaining -= add
	for i in range(_build_palette.size()):
		if remaining <= 0:
			break
		if _build_palette[i] == null:
			var add: int = mini(remaining, stack_limit)
			_build_palette[i] = {"data": data, "quantity": add}
			remaining -= add
	# Overflow (all 3 slots full) goes to the general inventory — RAW add, so
	# it can't route back here and recurse.
	if remaining > 0:
		_inventory_add_raw(data, remaining)
	build_palette_changed.emit()

# Public (used by LuaEditorUI when the player drags a block into a slot).
func set_build_slot(index: int, data: ItemData, quantity: int) -> void:
	if index < 0 or index >= _build_palette.size():
		return
	_build_palette[index] = null if data == null else {"data": data, "quantity": maxi(quantity, 1)}
	build_palette_changed.emit()

func get_build_palette() -> Array:
	return _build_palette


# ── Crafting Station bridge ───────────────────────────────────────
# The nearest placed Crafting Station within range, or null. Stations are
# grouped by crafting_station_object.gd.
func nearest_crafting_station() -> Node:
	if not is_inside_tree():
		return null
	var best: Node = null
	var best_d: float = CHOP_RADIUS_PX
	for n in get_tree().get_nodes_in_group("CraftingStation"):
		if not (n is Node2D):
			continue
		var d: float = (n as Node2D).global_position.distance_to(global_position)
		if d < best_d:
			best_d = d
			best = n
	return best

# ── Station jobs: WALK to the nearest station, then act ────────────
# craft()/set_recipe()/take_output()/put_input() are emitted as separate
# signals (one per frame), but walking is asynchronous — so they're QUEUED and
# run one at a time, each after the robot has walked to the station. That is
# what makes the robot visibly travel to a station to craft, exactly like
# deposit_chest() does for chests. Nothing is silent: with no station in range
# (or an empty build slot) a message goes to the program's output.
var _station_queue: Array = []

func _on_lua_craft(quantity: int) -> void:
	_queue_station_job("craft", int(quantity))

func _on_lua_set_recipe(name: String) -> void:
	_queue_station_job("set_recipe", name)

func _on_lua_take_output() -> void:
	_queue_station_job("take_output", 0)

# put_input(name, qty): walk to the nearest station and move that item from the
# robot's own stores (build palette + inventory) into the station's input slot.
func _on_lua_put_input(name: String, quantity: int) -> void:
	_queue_station_job("put_input", {"name": name, "quantity": maxi(quantity, 1)})

# input_slot(qty): same, but the item is whatever the SELECTED build slot holds,
# so a program doesn't need to name it.
func _on_lua_input_slot(quantity: int) -> void:
	_queue_station_job("input_slot", maxi(quantity, 1))

# ── mine(name, radius) + rename(name) ─────────────────────────────
func _on_lua_mine(name: String, radius: int) -> void:
	if _is_working:
		_lua_state.emit_signal("signal_print", "[mine] robot is busy — mine() ignored.")
		return
	_is_working = true
	_mine_named.call_deferred(name, maxi(radius, 1))

func _on_lua_rename(new_name: String) -> void:
	_custom_name = new_name.strip_edges()
	if _name_label != null:
		_name_label.text    = _custom_name
		_name_label.visible = not _custom_name.is_empty()

# Mines every placed block whose item_name matches `name` within `radius` tiles
# of the station: walk to each, break it (drops the item), store the drop.
# Verbose progress is written to the editor's output panel via signal_print.
func _mine_named(name: String, radius: int) -> void:
	var world: Node = Global.world_node
	if world == null:
		_lua_state.emit_signal("signal_print", "[mine] no world to mine in.")
		_is_working = false
		return
	_lua_state.emit_signal("signal_print", "[mine] searching for \"%s\" within %d blocks..." % [name, radius])
	var mined: int = 0
	while true:
		if _stop_requested:
			break
		var cell: Variant = _nearest_named_block(name, radius)
		if cell == null:
			break
		var block: Node2D = _placed_block_node(cell as Vector2i)
		if block == null:
			_erase_placed_block(cell as Vector2i)   # stale entry — forget it
			continue
		_lua_state.emit_signal("signal_print", "[mine] mining %s..." % name)
		if not await _walk_to_node(block):
			_is_working = false
			return
		if _stop_requested:
			break
		if block.has_method("_break"):
			# Mining reads as magic too — a small slash at the block being broken.
			MagicSwing.spawn(world, block.global_position, _facing_vec(), 0.8, 3)
			block.call("_break")
		await get_tree().create_timer(PICKUP_DELAY).timeout
		_collect_drops_nearby()
		mined += 1
		_lua_state.emit_signal("signal_print", "[mine] storing... (%d x %s)" % [mined, name])
	if not _stop_requested:
		await _walk_to_spawn()
	_lua_state.emit_signal("signal_print", "[mine] done — mined %d x %s." % [mined, name])
	_is_working = false

# Nearest placed block (by item_name) within radius tiles of the station.
func _nearest_named_block(name: String, radius: int) -> Variant:
	var world: Node = Global.world_node
	if world == null:
		return null
	var placed: Variant = world.get("_placed_blocks")
	if not (placed is Dictionary):
		return null
	var center: Vector2 = global_position
	var best: Variant = null
	var best_d: float = float(radius) * TILE_SIZE
	for cell in (placed as Dictionary):
		var entry: Variant = (placed as Dictionary)[cell]
		if not (entry is Dictionary):
			continue
		if str((entry as Dictionary).get("name", "")) != name:
			continue
		var node_ref: Variant = (entry as Dictionary).get("node")
		if not is_instance_valid(node_ref):
			continue
		var d: float = center.distance_to((node_ref as Node2D).global_position)
		if d <= best_d:
			best_d = d
			best   = cell
	return best

func _placed_block_node(cell: Vector2i) -> Node2D:
	var world: Node = Global.world_node
	if world == null:
		return null
	var placed: Variant = world.get("_placed_blocks")
	if not (placed is Dictionary):
		return null
	var entry: Variant = (placed as Dictionary).get(cell)
	if not (entry is Dictionary):
		return null
	var node_ref: Variant = (entry as Dictionary).get("node")
	return node_ref as Node2D if is_instance_valid(node_ref) else null

func _erase_placed_block(cell: Vector2i) -> void:
	var world: Node = Global.world_node
	if world != null and world.has_method("unregister_block"):
		world.call("unregister_block", cell)

func _queue_station_job(action: String, arg: Variant) -> void:
	_station_queue.append({"action": action, "arg": arg})
	if not _is_working:
		_run_station_jobs.call_deferred()

func _run_station_jobs() -> void:
	if _is_working:
		return
	_is_working = true
	while not _station_queue.is_empty():
		if _stop_requested or not is_inside_tree():
			break
		var job: Dictionary = _station_queue.pop_front()
		var station: Node = nearest_crafting_station()
		if station == null or not is_instance_valid(station):
			_lua_notice("No crafting station in range.")
			continue
		if not await _walk_to_node(station as Node2D):
			break
		_apply_station_job(station, job)
	_abort_work()

func _apply_station_job(station: Node, job: Dictionary) -> void:
	match str(job["action"]):
		"craft":
			var n: int = int(job["arg"])
			var made: int = int(station.call("craft_request", n))
			if made <= 0:
				_lua_notice("Craft failed — check the recipe, ingredients and output space.")
		"set_recipe":
			if not bool(station.call("set_automation_recipe_by_name", str(job["arg"]))):
				_lua_notice("Unknown recipe: %s" % str(job["arg"]))
		"take_output":
			# A robot's craft result goes to the ROBOT's 3 build slots (falling
			# back to its inventory when full) — not the player's inventory.
			var stack: Dictionary = {}
			if station.has_method("take_output_stack"):
				stack = station.call("take_output_stack")
			if stack.is_empty():
				_lua_notice("Nothing to collect.")
				return
			_npc_add_to_palette(stack["data"] as ItemData, int(stack["quantity"]))
		"put_input":
			var d: Dictionary = job["arg"]
			var data := _find_item_data_by_name(str(d["name"]))
			if data == null:
				_lua_notice("Unknown item: %s" % str(d["name"]))
				return
			var give: int = mini(int(d["quantity"]), _count_robot_item(data))
			if give <= 0:
				_lua_notice("The robot is not carrying any %s." % str(d["name"]))
				return
			var accepted: int = int(station.call("put_input", data, give))
			if accepted > 0:
				_remove_robot_item(data, accepted)
		"input_slot":
			# Feed from the SELECTED build slot — no item name needed.
			var slot: Variant = _build_palette[_selected_slot] if _selected_slot < _build_palette.size() else null
			if slot == null:
				_lua_notice("Build slot %d is empty — nothing to load into the station." % [_selected_slot + 1])
				return
			var data2: ItemData = (slot as Dictionary)["data"] as ItemData
			if data2 == null:
				return
			var give2: int = mini(int(job["arg"]), _count_robot_item(data2))
			if give2 <= 0:
				_lua_notice("The robot is not carrying any %s." % data2.item_name)
				return
			var accepted2: int = int(station.call("put_input", data2, give2))
			if accepted2 > 0:
				_remove_robot_item(data2, accepted2)

# Sends a status line to the Lua editor's output panel (the LuaState's
# signal_print is what the editor listens to).
func _lua_notice(msg: String) -> void:
	if _lua_state != null and is_instance_valid(_lua_state):
		_lua_state.emit_signal("signal_print", msg)
	else:
		print("[Lua] ", msg)


# Total of `data` the robot is holding (build palette + general inventory).
func _count_robot_item(data: ItemData) -> int:
	var total: int = 0
	for slot in _build_palette:
		if slot != null and (slot as Dictionary)["data"] == data:
			total += int((slot as Dictionary)["quantity"])
	for slot in _npc_inventory:
		if slot != null and slot["data"] == data:
			total += int(slot["quantity"])
	return total

# Removes up to `count` of `data` from the robot's stores (palette first).
func _remove_robot_item(data: ItemData, count: int) -> void:
	var remaining: int = count
	for i in range(_build_palette.size()):
		if remaining <= 0:
			break
		var slot: Variant = _build_palette[i]
		if slot == null or (slot as Dictionary)["data"] != data:
			continue
		var take: int = mini(remaining, int((slot as Dictionary)["quantity"]))
		(slot as Dictionary)["quantity"] = int((slot as Dictionary)["quantity"]) - take
		remaining -= take
		if int((slot as Dictionary)["quantity"]) <= 0:
			_build_palette[i] = null
	if remaining != count:
		build_palette_changed.emit()
	# Iterate the inventory in REVERSE so removing an emptied slot is safe —
	# _npc_inventory holds only real entries (no nulls), so it must be erased,
	# not set to null.
	for i in range(_npc_inventory.size() - 1, -1, -1):
		if remaining <= 0:
			break
		var slot: Variant = _npc_inventory[i]
		if slot == null or slot["data"] != data:
			continue
		var take: int = mini(remaining, int(slot["quantity"]))
		slot["quantity"] = int(slot["quantity"]) - take
		remaining -= take
		if int(slot["quantity"]) <= 0:
			_npc_inventory.remove_at(i)

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
# True while a dispatched job (auto_work / chop / walk) is still running. The
# editor UI uses this to re-sync its RUN/STOP buttons whenever it reopens,
# since closing the panel deliberately leaves the robot working.
func is_working() -> bool:
	return _is_working

func stop_work() -> void:
	_stop_requested = true
	_robot_vel      = Vector2.ZERO
	# Nothing is running, so no loop will consume the flag — clear it now or
	# the next job would abort the instant it starts.
	if not _is_working:
		_abort_work()

# Clears the "a job is running" state. Called when a job is interrupted by
# STOP (or by the station leaving the tree), so _on_lua_interact's
# _is_working guard can't latch and a stale _stop_requested can't make every
# future job bail out immediately.
func _abort_work() -> void:
	_robot_vel      = Vector2.ZERO
	_stop_requested = false
	_is_working     = false
	# A finished job may have queued station work behind it (e.g. chop_trees()
	# then input_slot()/craft()) — kick that queue now that we're free.
	if not _station_queue.is_empty():
		_run_station_jobs.call_deferred()

# ─────────────────────────────────────────────────────────────────
# ── AUTONOMOUS BEHAVIOURS ─────────────────────────────────────────
# ─────────────────────────────────────────────────────────────────

func _auto_work() -> void:
	while true:
		if _stop_requested: break
		var tree: Node2D = _nearest_tree_in_radius()
		if tree == null: break
		if not await _walk_to_node(tree):
			_is_working = false
			return
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
			if not await _walk_to_node(chest as Node2D):
				_is_working = false
				return
			_deposit_to_chest(chest)
		if not await _walk_to_spawn():
			_is_working = false
			return

	_stop_requested = false
	_is_working     = false

func _chop_all_trees() -> void:
	while true:
		if _stop_requested: break
		var tree: Node2D = _nearest_tree_in_radius()
		if tree == null: break
		if not await _walk_to_node(tree):
			_is_working = false
			return
		if _stop_requested: break
		while is_instance_valid(tree):
			if _stop_requested: break
			tree.call("chop", CHOP_DELAY)
			await get_tree().create_timer(CHOP_DELAY).timeout
		await get_tree().create_timer(PICKUP_DELAY).timeout
		_collect_drops_nearby()

	if not _stop_requested:
		if not await _walk_to_spawn():
			_is_working = false
			return
	_stop_requested = false
	_is_working     = false

func _walk_to_spawn_then_stop() -> void:
	await _walk_to_spawn()
	_is_working = false

func _deposit_then_stop() -> void:
	var chest: Node = _nearest_chest_in_radius()
	if chest != null and is_instance_valid(chest):
		if not await _walk_to_node(chest as Node2D):
			_is_working = false
			return
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

# Walk robot toward a world node, rerouting around solid obstacles (trees,
# placed blocks, chests). Returns false if it got stuck and had to be
# recalled to the station instead of arriving normally.
func _walk_to_node(target: Node2D) -> bool:
	var exclude_rids:  Array = _collision_rids_of(target)
	var last_dist:     float = INF
	var stuck_since_ms: int  = -1
	while is_instance_valid(target):
		# STOP pressed mid-walk, or the station left the tree (the overworld is
		# swapped out when the player enters a cave/dungeon) — abandon the walk
		# instead of marching on or touching a null physics world.
		if _stop_requested or not is_inside_tree():
			_abort_work()
			return false
		var dist: float = _robot.global_position.distance_to(target.global_position)
		if dist <= APPROACH_PX:
			_robot_vel = Vector2.ZERO
			return true

		var desired: Vector2 = _robot.global_position.direction_to(target.global_position)
		var travel:  Vector2 = _pick_travel_dir(_robot.global_position, desired, exclude_rids)
		_robot_vel = travel * NPC_SPEED

		if dist < last_dist - STUCK_PROGRESS_EPS:
			last_dist      = dist
			stuck_since_ms = -1
		elif stuck_since_ms == -1:
			stuck_since_ms = Time.get_ticks_msec()
		elif Time.get_ticks_msec() - stuck_since_ms > STUCK_TIMEOUT_MS:
			_handle_stuck()
			return false

		await get_tree().process_frame
	_robot_vel = Vector2.ZERO
	return true

# Walk robot back to station origin (position 0,0 relative to station),
# rerouting around solid obstacles. Returns false if it got stuck (already
# teleported home by _handle_stuck in that case).
func _walk_to_spawn() -> bool:
	var last_dist:     float = INF
	var stuck_since_ms: int  = -1
	while _robot.position.length() > 8.0:
		if _stop_requested or not is_inside_tree():
			_abort_work()
			return false
		var dist: float = _robot.position.length()

		var desired: Vector2 = (_robot.position * -1.0).normalized()
		var travel:  Vector2 = _pick_travel_dir(_robot.global_position, desired, [])
		_robot_vel = travel * NPC_SPEED

		if dist < last_dist - STUCK_PROGRESS_EPS:
			last_dist      = dist
			stuck_since_ms = -1
		elif stuck_since_ms == -1:
			stuck_since_ms = Time.get_ticks_msec()
		elif Time.get_ticks_msec() - stuck_since_ms > STUCK_TIMEOUT_MS:
			_handle_stuck()
			return false

		await get_tree().process_frame
	_robot_vel      = Vector2.ZERO
	_robot.position = Vector2.ZERO
	return true

# ── Obstacle avoidance ──────────────────────────────────────────────

# True if a straight line from `from` along `dir`, one lookahead step long,
# is clear of solid bodies other than those in `exclude_rids`.
func _path_is_clear(from: Vector2, dir: Vector2, exclude_rids: Array) -> bool:
	if dir == Vector2.ZERO:
		return true
	# get_world_2d() is null whenever this station is outside the tree (e.g. a
	# walk was in flight when the overworld was swapped for a cave/dungeon).
	# Report "blocked" so callers stop steering instead of dereferencing null.
	if not is_inside_tree():
		return false
	var world_2d := get_world_2d()
	if world_2d == null:
		return false
	var space_state := world_2d.direct_space_state
	var query := PhysicsRayQueryParameters2D.create(from, from + dir.normalized() * OBSTACLE_LOOKAHEAD_PX)
	query.collision_mask = OBSTACLE_MASK
	query.exclude        = exclude_rids
	return space_state.intersect_ray(query).is_empty()

# Picks the clear direction closest to desired_dir, sweeping wider angles
# either side when the direct line is blocked. Vector2.ZERO means every
# candidate direction is blocked (fully boxed in).
func _pick_travel_dir(from: Vector2, desired_dir: Vector2, exclude_rids: Array) -> Vector2:
	if _path_is_clear(from, desired_dir, exclude_rids):
		return desired_dir
	for angle in REROUTE_ANGLES_DEG:
		var candidate: Vector2 = desired_dir.rotated(deg_to_rad(angle))
		if _path_is_clear(from, candidate, exclude_rids):
			return candidate
	return Vector2.ZERO

# Collision body RIDs belonging to a target node, so walking TOWARD a
# tree/chest doesn't treat that same destination as an obstacle to dodge.
func _collision_rids_of(node: Node) -> Array:
	var rids: Array = []
	if node == null:
		return rids
	for body in node.find_children("*", "StaticBody2D", true, false):
		rids.append((body as StaticBody2D).get_rid())
	return rids

# Shows the stuck dialogue and instantly recalls the robot to its station.
func _handle_stuck() -> void:
	Global.lua_stuck_notice.emit("A LUA got stuck!")
	_robot_vel      = Vector2.ZERO
	_robot.position = Vector2.ZERO

# ── Search helpers ────────────────────────────────────────────────

# Nearest tree within CHOP_RADIUS_PX of the STATION (not the robot).
func _nearest_tree_in_radius() -> Node2D:
	if not is_inside_tree():
		return null
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
	if not is_inside_tree():
		return null
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
	if not is_inside_tree():
		return
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
	# Placeable items (wood, planks, stone, …) go to the BUILD palette first,
	# so a robot that chops trees can immediately build with the wood. The
	# palette falls back to the raw inventory when all 3 slots are full.
	if data != null and data.is_placeable:
		_npc_add_to_palette(data, 1)
		return
	_inventory_add_raw(data, 1)

# The original stacking rule, with no palette routing — the palette's own
# overflow fallback calls THIS (routing would recurse forever).
func _inventory_add_raw(data: ItemData, count: int) -> void:
	if data == null:
		return
	var stack_limit: int = data.max_stack_size if data.max_stack_size > 0 else Global.MAX_STACK
	var remaining: int = count
	for slot in _npc_inventory:
		if remaining <= 0:
			break
		if slot["data"] == data and slot["quantity"] < stack_limit:
			var add: int = mini(remaining, stack_limit - int(slot["quantity"]))
			slot["quantity"] += add
			remaining -= add
	while remaining > 0:
		var add: int = mini(remaining, stack_limit)
		_npc_inventory.append({"data": data, "quantity": add})
		remaining -= add

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
	# Floating entity: one STATIC frame per direction (front/back/side), no
	# walk cycle. Both the idle_ and walk_ animation names are kept so the rest
	# of the code (which asks for walk_<dir>/idle_<dir>) is unchanged.
	for d in DIRS:
		var dir: String = d["name"]
		var tex: Texture2D = DIR_TEX.get(dir, TEX_FRONT)
		var walk: String = "walk_" + dir.replace("-", "_")
		sf.add_animation(walk)
		sf.set_animation_speed(walk, 1.0)
		sf.set_animation_loop(walk, false)
		sf.add_frame(walk, tex)
		var idle: String = "idle_" + dir.replace("-", "_")
		sf.add_animation(idle)
		sf.set_animation_speed(idle, 1.0)
		sf.set_animation_loop(idle, false)
		sf.add_frame(idle, tex)
	return sf

# West mirrors the side sprite; everything else uses its own texture.
func _apply_facing(dir: String) -> void:
	_robot_sprite.flip_h = dir == "west"

func _play_idle(dir: String) -> void:
	_apply_facing(dir)
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
	_apply_facing(best_dir)
	var anim := "walk_" + best_dir.replace("-", "_")
	if _robot_sprite.animation != anim:
		_robot_sprite.play(anim)
	_last_dir = best_dir
