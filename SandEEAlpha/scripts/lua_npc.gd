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
# Every LUA is 25% smaller than the original art/body. A combat LUA kept getting
# wedged in tight spaces — its 20x20 body could not thread the gaps the player
# slips through — so the sprite, the collision box and every distance derived
# from the body's size are scaled down together. LuaNPC.tscn carries the
# matching sprite scale (0.75) and RobotCol size (15x15 at y 7.5); keep the two
# in sync (the shape is a scene sub-resource, not built here).
const LUA_SIZE_SCALE:     float = 0.75
# Interaction reach. The robot acts on anything inside a 3x3 tile area centred
# on ITSELF (1.5 tiles = 48 px) — which is exactly the radius the game already
# gives actors: Tree.tscn's InteractArea is a 48 px circle. The robot must NOT
# have to walk right up to a target. With the old 30 px approach it could not
# always get there (a tree in dense forest is walled in by its neighbours), so
# _walk_to_node timed out, _handle_stuck() recalled the robot to its station and
# the job looked like it "did nothing" — no swing, no chop, walk home.
const INTERACT_RADIUS_TILES: int   = 1     # 3x3 tiles around the robot
const INTERACT_RADIUS_PX:    float = TILE_SIZE * (float(INTERACT_RADIUS_TILES) + 0.5)
const CHOP_DELAY:         float = 0.25
const PICKUP_DELAY:       float = 0.4
const NPC_SPEED:          float = 90.0
const SHADOW_TEXTURE:     Texture2D = preload("res://sprites/shadow/shadow_base.png")
const MELLOW_BURST_SCRIPT: GDScript = preload("res://scripts/mellow_burst.gd")
const ATTACK_RING_SCRIPT:  GDScript = preload("res://scripts/attack_ring.gd")

# ── Y-sort (robot visual) ────────────────────────────────────────
# The robot sprite is CENTERED on the Robot node, so the node origin sits at
# the sprite's middle, not its feet. Sorting on the origin (the old behaviour)
# put the robot half a tile too high, so it drew behind trees/blocks it was
# standing in front of. Offset to the sprite's bottom line, then add the same
# half-tile tiebreak the player uses. The floating-entity art is 52px tall at
# scale 1.0, so the visual bottom sits 26px below the origin — scaled by
# LUA_SIZE_SCALE along with the sprite itself.
const ROBOT_FEET_OFFSET: float = 26.0 * LUA_SIZE_SCALE
const YSORT_TIEBREAK:    float = 16.0   # half a tile — matches player.gd

# ── Floating bob ──────────────────────────────────────────────────
# The robot hovers, so its sprite gently bobs up/down while it moves and
# settles to rest when idle. The ground shadow stays put on the floor (only
# shrinking a touch as the robot rises) so the bob reads as hovering.
const BOB_AMPLITUDE: float = 2.5
const BOB_SPEED:     float = 6.5
const SHADOW_OFFSET_Y: float = 28.0 * LUA_SIZE_SCALE  # shadow sits at the sprite's base
var _bob_t: float = 0.0
var _shadow: Sprite2D = null
var _shadow_scale: Vector2 = Vector2(0.7, 0.32) * LUA_SIZE_SCALE

# ── Floating-entity sprite set ────────────────────────────────────
# The robot is now a FLOATING entity (no walk cycle): one static sprite per
# direction, taken from the 3 layer groups of sprites/lua.aseprite
# (front/back/side). Diagonals reuse the nearest cardinal; west mirrors side.
const TEX_FRONT: Texture2D = preload("res://sprites/char/lua/front.png")
const TEX_BACK:  Texture2D = preload("res://sprites/char/lua/back.png")
const TEX_SIDE:  Texture2D = preload("res://sprites/char/lua/side.png")
# Combat-mode sprites (see sprites/char/lua_combat/).
const TEX_COMBAT_FRONT: Texture2D = preload("res://sprites/char/lua_combat/front.png")
const TEX_COMBAT_BACK:  Texture2D = preload("res://sprites/char/lua_combat/back.png")
const TEX_COMBAT_SIDE:  Texture2D = preload("res://sprites/char/lua_combat/side.png")
const LUA_EYES_SHADER: Shader = preload("res://shaders/lua_eyes.gdshader")
const DIR_TEX: Dictionary = {
	"north": TEX_BACK,  "north-east": TEX_BACK,  "north-west": TEX_BACK,
	"south": TEX_FRONT, "south-east": TEX_FRONT, "south-west": TEX_FRONT,
	"east":  TEX_SIDE,  "west":       TEX_SIDE,
}
const DIR_TEX_COMBAT: Dictionary = {
	"north": TEX_COMBAT_BACK,  "north-east": TEX_COMBAT_BACK,  "north-west": TEX_COMBAT_BACK,
	"south": TEX_COMBAT_FRONT, "south-east": TEX_COMBAT_FRONT, "south-west": TEX_COMBAT_FRONT,
	"east":  TEX_COMBAT_SIDE,  "west":       TEX_COMBAT_SIDE,
}

# ── Obstacle avoidance / stuck detection ─────────────────────────
# Trees, placed blocks, chests, etc. are all StaticBody2D on the default
# physics layer (bit 0) — same layer the player's CharacterBody2D collides
# against — so a raycast on that mask reliably detects anything solid.
const OBSTACLE_MASK:         int   = 1
const OBSTACLE_LOOKAHEAD_PX: float = 28.0 * LUA_SIZE_SCALE  # a bit under one tile (32px)
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
# Work radius used by the TREE search. chop_trees(radius) sends the requested
# radius through move(radius, S_SET_RADIUS); before this existed the value was
# dropped and every job used the fixed 20-block constant, so chop_trees(4)
# actually cleared a 20-block circle and looked like it would never finish.
var _work_radius_px:  float   = CHOP_RADIUS_PX
const WORK_RADIUS_MIN_BLOCKS: float = 1.0
const WORK_RADIUS_MAX_BLOCKS: float = 64.0
var _player_nearby:   bool    = false
var _is_working:      bool    = false
var _stop_requested:  bool    = false
# Trees the robot could not path to during the CURRENT job. Without this a
# walled-in tree aborted the whole job (walk fails -> return), so the robot went
# home having done nothing; now it is remembered and the next tree is tried.
var _unreachable:     Array   = []
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
# Build-helper calls arrive in one Lua frame. They are queued and played out
# one block at a time so a loop cannot race itself or place more blocks than
# the selected slot actually holds.
var _build_queue: Array = []
var _build_queue_running: bool = false
const BUILD_PLACE_SEC: float = 0.06
# Highest auto-assigned LUA index. Placed LUAs are labelled "LUA 0".."LUA 30";
# placing more than MAX_LUA_INDEX+1 in the world is refused (world.gd).
const MAX_LUA_INDEX: int = 30
var _build_palette: Array = []           # [ {data, quantity} | null, x3 ]
# Tool slot: the single item the robot SWINGS for its tasks (and its weapon in
# combat mode). {} when empty, else {data: ItemData, quantity: int}.
var _tool: Dictionary = {}
# The LUA's saved Lua source (persisted with the world so a reload keeps it).
var program_code: String = ""
# rename(name) — custom name shown above the robot.
var _custom_name: String = ""
# The station's presentational component (name label + code-editor panel). See
# lua_ui.gd — this node keeps NO UI state of its own.
var _lua_ui: Node = null
const LUA_UI_SCRIPT: GDScript = preload("res://scripts/lua_ui.gd")
# Auto-assigned index (0..MAX_LUA_INDEX) for the default "LUA N" label.
var _name_index:  int    = -1
# Current action shown in the LUA status HUD ("Mining Stone", "Idle", …).
var _status:      String = "Idle"
var _status_ms:   int    = 0

# ── Combat mode ───────────────────────────────────────────────────
# combat_mode(true) turns the LUA into a COMBAT LUA: it swaps to the combat
# sprite, abandons its station to FOLLOW the player, attacks whatever the player
# attacks using its TOOL slot, has HP (enemies can hurt it), and can be
# terminated (remote, or STOP on its station). A terminated combat LUA is gone
# for good. It cannot run code while in combat.
const COMBAT_MAX_HP:        float = 250.0
const COMBAT_FOLLOW_GAP:    float = 44.0 * LUA_SIZE_SCALE  # keep this far from the player
const COMBAT_CONTACT_PX:    float = 26.0 * LUA_SIZE_SCALE  # a mob this close to the LUA hurts it
const COMBAT_CONTACT_DMG:   float = 8.0
const COMBAT_CONTACT_CD:    float = 1.0
const COMBAT_BASE_MULT:     float = 0.75    # retain 75% of the tool's damage
const COMBAT_STACK_PENALTY: float = 0.02    # -2% per extra active combat LUA
# A combat LUA swings a wide area CENTRED ON ITSELF (not a single mob): every
# mob within this radius takes the hit. 2.5 tiles = a 5x5 tile box (raised from
# the old 1.5-tile / 3x3 box by one tile). This is the LUA's REACH, not its body,
# so it does NOT shrink with LUA_SIZE_SCALE.
const COMBAT_AOE_RADIUS:    float = 80.0
# The station beacon pulses this colour while its LUA is in combat.
const COMBAT_BEACON_TINT:   Color = Color(1.00, 0.25, 0.25, 1.00)
# Teleport the follower to the player when they jump a long way (death respawn,
# a cave/dungeon swap, the stuck-teleport) instead of walking forever.
const COMBAT_TELEPORT_DIST: float = 700.0
const COMBAT_TELEPORT_GAP:  float = 40.0 * LUA_SIZE_SCALE
# Multiple combat LUAs following the player form a single-file LINE: each takes a
# slot this far behind the one ahead, so they trail one after another instead of
# all converging on the player's tile (which made them stack and flicker). The
# rank is capped so a huge swarm doesn't stretch into an absurd queue.
const COMBAT_LINE_SPACING:  float = 30.0 * LUA_SIZE_SCALE
const COMBAT_LINE_MAX_RANK: int   = 6
# Steering commit: hold a chosen reroute direction briefly. Re-picking the angle
# every frame made the robot dither between two equally-open directions at a
# corner and stall (it read as "stuck in tight spaces").
const COMBAT_COMMIT_SEC:    float = 0.35

# ── Pursuit tuning ────────────────────────────────────────────────
# Dynamic speed: MIN when boxed in / near the player, NORMAL for a steady
# chase, SPRINT to run down a sprinting player. Smoothed by ACCEL/DECEL so the
# speed never snaps when the distance wobbles.
const COMBAT_SPEED_MIN:     float = 75.0
const COMBAT_SPEED_NORMAL:  float = 125.0
const COMBAT_SPEED_SPRINT:  float = 260.0   # > the player's sprint (144)
const COMBAT_ACCEL:         float = 650.0   # px/s² toward a higher target
const COMBAT_DECEL:         float = 950.0   # px/s² toward a lower target
const COMBAT_SPRINT_DIST:   float = 200.0   # sprint beyond this distance
# Footprint-aware steering: sweep the robot's OWN collision shape this far
# ahead, and reroute through these angles (deg) when the forward path is
# blocked. Sweeping the shape (not a point ray) is what lets it fit narrow
# corridors and refuse diagonal corner cuts.
const COMBAT_LOOKAHEAD:     float = 26.0 * LUA_SIZE_SCALE
const COMBAT_REROUTE_DEG: Array = [0.0, 25.0, -25.0, 50.0, -50.0, 75.0, -75.0, 90.0, -90.0, 135.0, -135.0, 180.0]
# Stuck recovery (last resort — a rare teleport, never the default pursuit).
const COMBAT_STUCK_SEC:      float = 3.0
const COMBAT_STUCK_PROGRESS: float = 8.0    # px of closing distance that counts
const COMBAT_RECOVER_CD_SEC: float = 6.0
const COMBAT_RECOVER_RADIUS: int   = 5      # tiles searched around the player
# Try this many offset search centres so simultaneous recoveries don't all land
# on the same tile (which made the robots stack and flicker).
const COMBAT_RECOVER_TRIES:  int   = 8
# Keep recovered LUAs at least this far apart.
const COMBAT_MIN_SPACING:    float = 30.0 * LUA_SIZE_SCALE

# ── Hostile-mob hunting ───────────────────────────────────────────
# Opportunistic: a combat LUA hunts a nearby HOSTILE mob, then resumes player
# pursuit. The mob must be near BOTH the LUA and the player, so hunting never
# drags it far from the player it escorts.
const COMBAT_HUNT_RADIUS:   float = 220.0   # sight radius from the LUA
const COMBAT_HUNT_LEASH:    float = 240.0   # ... and this close to the player
const COMBAT_HUNT_DROP:     float = 380.0   # give up a hunt target beyond this
const COMBAT_HUNT_RESCAN:   float = 0.4     # s between hostile scans
const COMBAT_ENGAGE_GAP:    float = 40.0 * LUA_SIZE_SCALE  # stand-off distance for a mob
const COMBAT_ATTACK_RANGE:  float = 56.0 * LUA_SIZE_SCALE  # attack a mob within this
const COMBAT_ATTACK_CD:     float = 1.0     # s between autonomous attacks
var _combat:        bool  = false
var _terminated:    bool  = false
var _combat_hp:     float = 0.0
var _combat_hit_cd: float = 0.0
# Pursuit state.
var _combat_speed:      float = 0.0
var _combat_stuck_ms:   int   = -1
var _combat_last_dist:  float = INF
var _combat_recover_ms: int   = -1000000
var _robot_col:         CollisionShape2D = null
# Steering commit (see COMBAT_COMMIT_SEC): the held reroute direction + its
# expiry timestamp.
var _combat_commit_dir:      Vector2 = Vector2.ZERO
var _combat_commit_until_ms: int     = 0
# The player this robot has been made non-solid against (see
# _exempt_player_collision). Kept so the exception is applied once per player
# body, and re-applied if the player node is ever replaced.
var _exempt_player: Node = null
# Hostile-mob hunting.
var _hunt_target:   Node2D = null
var _hunt_scan_ms:  int    = -1000000
var _combat_atk_cd: float  = 0.0
var _beacon_pulse:  bool  = false
var _pulse_t:       float = 0.0
var _selected_slot: int   = 0            # 0-based; the slot place_item uses

# ── Node refs ─────────────────────────────────────────────────────
var _lua_state:    Node    = null
# The world this station was placed in (normally the overworld). A combat LUA
# hides its station whenever another world is active.
var _home_world:   Node    = null

@onready var _robot:        CharacterBody2D  = $Robot
@onready var _robot_sprite: AnimatedSprite2D = $Robot/RobotSprite
@onready var _click_area:   Area2D           = $ClickArea
@onready var _beacon:       Sprite2D         = $BeaconSprite
@onready var _station_col:  CollisionShape2D = $StationBody/StationCol
# Default robot offset inside the station (see LuaNPC.tscn).
const ROBOT_HOME_OFFSET: Vector2 = Vector2(0.0, 36.0)

# Shared across every Lua station robot — built once instead of per-instance
# when multiple stations are placed.
static var _shared_frames: SpriteFrames = null
static var _shared_combat_frames: SpriteFrames = null

# ─────────────────────────────────────────────────────────────────
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group("LuaNPC")
	_build_palette.resize(BUILD_SLOTS)
	_home_world = get_parent()

	if _shared_frames == null:
		_shared_frames = _build_frames(false)
	if _shared_combat_frames == null:
		_shared_combat_frames = _build_frames(true)
	_robot_sprite.sprite_frames = _shared_frames
	# Glow only the eye pixels already painted into each facing frame. This
	# keeps the robot readable without outlining the whole silhouette.
	var eyes := ShaderMaterial.new()
	eyes.shader = LUA_EYES_SHADER
	_robot_sprite.material = eyes
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
	_lua_state.connect("signal_combat_mode", _on_lua_combat_mode)

	# Presentational component: the name label above the robot + the code-editor
	# panel. All UI state lives there (see lua_ui.gd) — this node only calls it.
	_lua_ui = LUA_UI_SCRIPT.new()
	_lua_ui.name = "LuaUI"
	add_child(_lua_ui)
	_lua_ui.call("setup", self, _robot)

	# Default "LUA N" label (lowest unused index). Done after the label + group
	# exist so the scan sees the other placed LUAs.
	_assign_default_name()

func _on_close_all_ui() -> void:
	if _lua_ui != null and is_instance_valid(_lua_ui):
		_lua_ui.call("close_editor")

# ── Draw radius ring ──────────────────────────────────────────────
func _draw() -> void:
	if not _show_radius:
		return
	# Filled tint
	draw_circle(Vector2.ZERO, _work_radius_px, Color(0.3, 0.8, 1.0, 0.06))
	# Solid border ring
	draw_arc(Vector2.ZERO, _work_radius_px, 0.0, TAU, 96, Color(0.3, 0.8, 1.0, 0.55), 2.5)

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
	_tick_beacon_pulse(delta)
	# A combat LUA follows the player into caves/dungeons; its station belongs to
	# the overworld, so hide it (and its collision) while another world is live.
	if _combat:
		_set_station_visible(_home_world_active())
	# Combat mode drives the robot itself (follow the player + contact damage).
	if _combat:
		_combat_process(delta)
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
		# A click that belongs to an open panel must not open the editor behind
		# it (that would stack two UI pauses and leave the tree in a mixed state).
		if Global.pause_menu_open or Global.any_ui_open():
			return
		if _lua_ui != null and is_instance_valid(_lua_ui):
			_lua_ui.call("open_editor")

# ── Player proximity ──────────────────────────────────────────────
func _on_body_entered(body: Node) -> void:
	if body.is_in_group("Player"):
		_player_nearby = true

func _on_body_exited(body: Node) -> void:
	if body.is_in_group("Player"):
		_player_nearby = false
		# Closing the editor must RELEASE the UI pause too. Just hiding it (the
		# old behaviour) left the tree paused with no visible UI — which reads
		# as the game freezing. It fired when a combat LUA reparented itself and
		# its click area re-detected the player.
		_on_close_all_ui()

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
			# chop_trees(radius) → move(radius, -1). Apply it to the tree search
			# (clamped so a stray value can't clear the whole overworld).
			_work_radius_px = clampf(vec.x, WORK_RADIUS_MIN_BLOCKS, WORK_RADIUS_MAX_BLOCKS) * TILE_SIZE
		_:
			_robot_vel = vec   # normal velocity move

func _on_lua_interact() -> void:
	if _is_working:
		# The action was not accepted; drop its sentinel so it can't fire on a
		# later unrelated interact().
		_pending_action = "chop"
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
# the way it last faced (see magic_swing.gd). Tool-gated: attack() swings the
# EQUIPPED tool, so it aborts with "No tool equipped" when the slot is empty.
func _on_lua_attack() -> void:
	if not _tool_gate("attack"):
		return
	_swing_at(Vector2.INF, 1.0, 6)

# _last_dir (a DIRS name) -> a unit vector.
func _facing_vec() -> Vector2:
	for d in DIRS:
		if d["name"] == _last_dir:
			return d["vec"] as Vector2
	return Vector2(0.0, 1.0)

# ── Interaction FX ────────────────────────────────────────────────
# Every world interaction plays the same "LUA is really doing something" beat:
# a violet arcane swing + mote burst AROUND THE ROBOT (aimed at the target when
# one is given), then a short pause so the action reads as a real interaction
# instead of an instant, silent state change. `_swing_at` is the fx-only form
# (used when no pause is wanted); `_interact` awaits the swing window.
const INTERACT_SWING_SEC: float = 0.22
# Overworld actions (chop / mine / place / drop / deposit) are paced at this
# interval; ITEM interactions (crafting station, furnace, …) at the longer one.
const MODIFY_COOLDOWN_SEC: float = 1.5
const ITEM_COOLDOWN_SEC: float = 3.0
var _last_modify_ms: int = -1000000

func _swing_at(target_pos: Vector2 = Vector2.INF, size: float = 1.0, motes: int = 6) -> void:
	var world: Node = Global.world_node
	if world == null or not is_instance_valid(world):
		return
	var dir: Vector2 = _facing_vec()
	if target_pos != Vector2.INF:
		var d: Vector2 = target_pos - _robot.global_position
		if d.length_squared() > 0.0001:
			dir = d.normalized()
	MagicSwing.spawn(world, _robot.global_position + Vector2(0.0, -10.0), dir, size, motes, _tool_icon())

func _interact(target_pos: Vector2 = Vector2.INF, size: float = 1.0, motes: int = 6,
		item_interaction: bool = false) -> void:
	await _wait_modify_cooldown(item_interaction)
	_swing_at(target_pos, size, motes)
	if is_inside_tree():
		await get_tree().create_timer(INTERACT_SWING_SEC).timeout

# Rate-limit: block until the cooldown has passed since the last world
# modification — 3s for ITEM interactions (station etc.), 1.5s for overworld
# actions.
func _wait_modify_cooldown(item_interaction: bool = false) -> void:
	var cd: float = ITEM_COOLDOWN_SEC if item_interaction else MODIFY_COOLDOWN_SEC
	var elapsed: float = float(Time.get_ticks_msec() - _last_modify_ms) / 1000.0
	if elapsed < cd:
		if not is_inside_tree():
			return
		await get_tree().create_timer(cd - elapsed).timeout
	_last_modify_ms = Time.get_ticks_msec()

# The icon of the equipped tool (shown sweeping during a swing), or null.
func _tool_icon() -> Texture2D:
	if _tool.is_empty():
		return null
	var d = _tool.get("data")
	if d is ItemData:
		return (d as ItemData).icon
	return null

# Every job ends here: walk back to the station FIRST, then go idle, so a LUA is
# never left idling away from its station.
func _return_and_idle() -> void:
	if is_inside_tree() and not _stop_requested and _robot.position.length() > 8.0:
		_set_status("Returning to station")
		await _walk_to_spawn()
	_stop_requested = false
	_is_working     = false
	_set_status("Idle")
	# A finished job may have queued station work behind it — kick that now.
	if not _station_queue.is_empty():
		_run_station_jobs.call_deferred()

func _on_lua_print(t: String) -> void:
	CrashLogger.code("lua", "OUT", t)

# ── Building (place_item / place_at / select_block / withdraw) ─────
# The robot places from its 3-slot build palette. Every placement reuses the
# world's own validity rules (World.can_place_at), so the robot obeys exactly
# the same water/tree/grass/occupancy constraints the player does. Lua delivers
# a whole loop's calls in one frame, so they are queued and played out one
# block at a time with a short swing beat: a 40-block build is visible and can
# never out-run the blocks actually held in the selected slot.

func _on_lua_select_block(index: int) -> void:
	_selected_slot = clampi(index, 0, BUILD_SLOTS - 1)

# Relative: place at (robot_tile + dx, robot_tile + dy).
func _on_lua_place_item(dx: int, dy: int) -> void:
	var world: Node = Global.world_node
	if world == null or not world.has_method("world_to_cell"):
		return
	var robot_cell: Vector2i = world.call("world_to_cell", _robot.global_position)
	_enqueue_build(world, robot_cell + Vector2i(dx, dy), _selected_slot)

# Absolute: place at tile (x, y).
func _on_lua_place_at(x: int, y: int) -> void:
	var world: Node = Global.world_node
	if world == null or not world.has_method("can_place_at"):
		return
	_enqueue_build(world, Vector2i(x, y), _selected_slot)

# Build-helper calls all arrive in one Lua frame. Queue them and play them out
# sequentially so a loop cannot start dozens of concurrent placement
# coroutines (which previously all read the same slot quantity and could place
# more blocks than the robot actually carried). The slot index is captured at
# call time so a later select_block() cannot retarget already-queued blocks.
func _enqueue_build(world: Node, cell: Vector2i, slot_index: int) -> void:
	if world == null or not is_instance_valid(world):
		return
	_build_queue.append({"world": world, "cell": cell, "slot": slot_index})
	if not _build_queue_running:
		_run_build_queue.call_deferred()

func _run_build_queue() -> void:
	if _build_queue_running:
		return
	_build_queue_running = true
	_is_working = true
	_set_status("Building")
	while not _build_queue.is_empty():
		if _stop_requested or not is_inside_tree():
			break
		var job: Dictionary = _build_queue.pop_front()
		var world: Variant = job.get("world")
		if world == null or not is_instance_valid(world):
			continue
		var cell: Vector2i = job["cell"]
		await _place_from_palette(world as Node, cell,
			int(job.get("slot", _selected_slot)))
	_build_queue.clear()
	_build_queue_running = false
	_is_working = false
	if _stop_requested or not is_inside_tree():
		_abort_work()
		return
	await _return_and_idle()

# Shared: consume one from the captured slot and place it, if legal + in range.
func _place_from_palette(world: Node, cell: Vector2i, slot_index: int) -> bool:
	if _stop_requested or not is_inside_tree():
		return false
	var idx: int = clampi(slot_index, 0, BUILD_SLOTS - 1)
	var slot: Variant = _build_palette[idx] if idx < _build_palette.size() else null
	if slot == null:
		_build_warn("Build slot %d is empty — give the robot blocks first (drag them in, or withdraw(\"Wood\", n))." % [idx + 1])
		return false
	var data: ItemData = (slot as Dictionary)["data"] as ItemData
	if data == null or not data.is_placeable:
		_build_warn("The selected build slot does not hold a placeable block.")
		return false
	# Reach: same radius the robot works within, measured from the STATION.
	if cell_to_world_dist(world, cell, global_position) > _work_radius_px:
		_build_warn("Placement out of range (further than the work radius).")
		return false
	if world.has_method("can_place_at") and not world.call("can_place_at", cell):
		_build_warn("Cannot place there — the tile is blocked.")
		return false
	# A short swing beat keeps a build loop visible without the 1.5s world-
	# modification cooldown (which made a 40-block helper take a minute).
	var cell_pos: Vector2 = Vector2.ZERO
	if world.has_method("cell_to_world"):
		cell_pos = world.call("cell_to_world", cell)
	_swing_at(cell_pos, 1.0, 3)
	if is_inside_tree():
		await get_tree().create_timer(BUILD_PLACE_SEC).timeout
	if _stop_requested or not is_inside_tree() or not is_instance_valid(world):
		return false
	# Re-check: an earlier queued block may have occupied this cell.
	if world.has_method("can_place_at") and not world.call("can_place_at", cell):
		_build_warn("Cannot place there — the tile is blocked.")
		return false
	var current: Variant = _build_palette[idx] if idx < _build_palette.size() else null
	if current == null or (current as Dictionary)["data"] != data:
		_build_warn("Build slot %d changed while building." % [idx + 1])
		return false
	var obj: Node = null
	if world.has_method("place_block_at"):
		obj = world.call("place_block_at", cell, data)
	if obj == null:
		return false
	# Consume from the SAME captured slot; no other placement can race it now.
	var qty: int = int((current as Dictionary)["quantity"]) - 1
	if qty <= 0:
		_build_palette[idx] = null
	else:
		(current as Dictionary)["quantity"] = qty
	_last_modify_ms = Time.get_ticks_msec()
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
	await _return_and_idle()

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
	var stack_limit: int = data.stack_limit() if data != null else 1
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

# ── Tool slot ─────────────────────────────────────────────────────
# The single item the robot swings for its tasks (and its combat weapon).
func set_tool(data: ItemData, quantity: int = 1) -> void:
	_tool = {} if data == null else {"data": data, "quantity": maxi(quantity, 1)}
	build_palette_changed.emit()

func get_tool() -> Dictionary:
	return _tool

func has_tool() -> bool:
	return not _tool.is_empty()

# ── Custom-function TOOL VALIDATION ───────────────────────────────
# Which custom LUA API functions need a TOOL equipped in the robot's tool slot
# before they may run. Declared in ONE table (checked by the shared _tool_gate
# below) instead of being duplicated inside every handler, so the rule stays
# maintainable as the API grows.
#
# Everything NOT listed here is tool-INDEPENDENT and keeps working with an empty
# slot: move/interact/print/rename/select_block/withdraw/drop_item/place_item/
# place_at (those need BLOCKS, not tools), the crafting-station calls
# (craft/set_recipe/take_output/put_input/input_slot) and combat_mode.
const TOOL_REQUIRED_FUNCS: Dictionary = {
	"mine":   true,   # mines blocks with the equipped tool
	"attack": true,   # swings the equipped tool
}
# The exact message required when a tool-dependent function runs with no tool.
const NO_TOOL_MSG: String = "No tool equipped"
# Throttle: a program that retries the same call in a tight loop must not flood
# the console with the same line.
const NO_TOOL_REPORT_MS: int = 1500
var _last_no_tool_ms: int = -1000000

# Does this custom function require a tool? Public so the editor / docs can ask.
func tool_required_for(func_name: String) -> bool:
	return bool(TOOL_REQUIRED_FUNCS.get(func_name, false))

# True when the robot has a USABLE tool equipped. The robot's own `_tool` slot IS
# the authoritative equipment state (the editor's slot widget is only a view of
# it), so an empty slot, a missing ItemData, a FREED reference or a zero-quantity
# stack all count as "no tool".
func has_valid_tool() -> bool:
	if _tool.is_empty():
		return false
	var d: Variant = _tool.get("data")
	if not (d is ItemData) or not is_instance_valid(d):
		return false
	return int(_tool.get("quantity", 0)) > 0

# Shared gate every tool-dependent handler calls FIRST. Returns false (after
# reporting) when the function needs a tool and none is equipped, so the caller
# aborts before any tool-dependent action — no item consumed, no terrain
# modified, no damage dealt, no work started.
func _tool_gate(func_name: String) -> bool:
	if not tool_required_for(func_name):
		return true
	if has_valid_tool():
		return true
	_report_no_tool()
	return false

func _report_no_tool() -> void:
	var now: int = Time.get_ticks_msec()
	if now - _last_no_tool_ms < NO_TOOL_REPORT_MS:
		return
	_last_no_tool_ms = now
	# The exact console message the validation contract requires.
	print(NO_TOOL_MSG)


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
	# Tool-gated BEFORE anything else: mine() uses the equipped tool, so with an
	# empty slot it must abort with "No tool equipped" and start no work at all.
	if not _tool_gate("mine"):
		return
	if _is_working:
		_lua_state.emit_signal("signal_print", "[mine] robot is busy — mine() ignored.")
		return
	_is_working = true
	_mine_named.call_deferred(name, maxi(radius, 1))

func _on_lua_rename(new_name: String) -> void:
	_custom_name = new_name.strip_edges()
	_update_name_label()

# Public rename entry point (used by the editor UI's rename field). The new name
# shows above the robot AND in the LUA status HUD.
func rename_to(new_name: String) -> void:
	_on_lua_rename(new_name)

func get_display_name() -> String:
	if not _custom_name.is_empty():
		return _custom_name
	if _name_index >= 0:
		return "Automatica %d" % _name_index
	return "Automatica"

func _update_name_label() -> void:
	if _lua_ui == null or not is_instance_valid(_lua_ui):
		return
	_lua_ui.call("set_name_text", get_display_name())

# Lowest unused index 0..MAX_LUA_INDEX across the placed LUAs, so the default
# "LUA N" labels stay stable and gaps are reused after a Lua is destroyed.
func _assign_default_name() -> void:
	var used: Dictionary = {}
	for n in get_tree().get_nodes_in_group("LuaNPC"):
		if n == self or not is_instance_valid(n):
			continue
		var idx: int = int(n.get("_name_index"))
		if idx >= 0:
			used[idx] = true
	var idx: int = 0
	while used.has(idx) and idx <= MAX_LUA_INDEX:
		idx += 1
	_name_index = mini(idx, MAX_LUA_INDEX)
	_update_name_label()

# ── Status (shown in the LUA status HUD) ──────────────────────────
func _set_status(text: String) -> void:
	_status    = text
	_status_ms = Time.get_ticks_msec()

func get_status() -> String:
	return _status

func get_status_ms() -> int:
	return _status_ms

# ── Combat mode ───────────────────────────────────────────────────
func is_combat() -> bool:
	return _combat

func is_terminated() -> bool:
	return _terminated

func get_combat_hp() -> float:
	return _combat_hp

func get_combat_max_hp() -> float:
	return COMBAT_MAX_HP

# combat_mode(on) from Lua. Combat is PERMANENT: combat_mode(false) is ignored —
# a combat LUA can only be terminated, never reverted to a normal LUA.
func _on_lua_combat_mode(on: bool) -> void:
	if _terminated or not on:
		return
	_enter_combat()

# `silent` skips the mellow poof + chat line (used when restoring a save).
func _enter_combat(silent: bool = false) -> void:
	if _combat:
		return
	# A combat LUA abandons its station: stop any job and follow the player.
	_stop_requested = true
	_combat        = true
	_combat_hp     = COMBAT_MAX_HP
	_combat_hit_cd = 0.0
	_combat_atk_cd = 0.0
	_hunt_target   = null
	_reset_combat_motion()
	_apply_combat_frames(true)
	_connect_player_swing()
	# A combat LUA escorts the player at close range, so it must not be able to
	# body-block them. This removes ONLY the player<->LUA pair: the robot still
	# collides with walls, mobs and other robots (see _exempt_player_collision).
	_exempt_player_collision()
	_set_status("Combat")
	# Station beacon pulses red so this station reads as a combat LUA's home.
	_set_beacon_combat(true)
	# Reparent to Game (which survives world swaps) so the LUA can follow the
	# player into caves/dungeons.
	_attach_to_game()
	if not silent:
		_spawn_mellow(_robot.global_position)
		_spawn_mellow(global_position)
		Global.notify("%s entered combat mode." % get_display_name())

func _apply_combat_frames(combat: bool) -> void:
	if _robot_sprite == null:
		return
	_robot_sprite.sprite_frames = _shared_combat_frames if combat else _shared_frames
	_play_idle(_last_dir)

func _connect_player_swing() -> void:
	var p := Global.player_node
	if p != null and is_instance_valid(p) and p.has_signal("swing_performed") \
			and not p.is_connected("swing_performed", _on_player_swung):
		p.connect("swing_performed", _on_player_swung)

# Make the robot non-solid against the PLAYER only. A combat LUA escorts the
# player at close range and used to shove them around / pin them in doorways;
# a per-pair collision exception fixes that without touching any layer, so the
# robot still collides with walls, mobs and other LUAs. Idempotent, and
# re-applied if the player node is ever replaced (respawn / scene reload).
func _exempt_player_collision() -> void:
	var p := Global.player_node
	if p == null or not is_instance_valid(p) or p == _exempt_player:
		return
	if _robot == null or not is_instance_valid(_robot):
		return
	if p is PhysicsBody2D:
		_robot.add_collision_exception_with(p as PhysicsBody2D)
		_exempt_player = p

func _disconnect_player_swing() -> void:
	var p := Global.player_node
	if p != null and is_instance_valid(p) and p.has_signal("swing_performed") \
			and p.is_connected("swing_performed", _on_player_swung):
		p.disconnect("swing_performed", _on_player_swung)

# The player swung — the combat LUA swings too (see _combat_attack).
func _on_player_swung() -> void:
	if not _combat or _terminated or not is_inside_tree():
		return
	_combat_attack(_robot.global_position)

# The circular AoE indicator (drawn, no art), under the world so it survives.
func _spawn_attack_ring(center: Vector2) -> void:
	var world: Node = Global.world_node
	if world == null or not is_instance_valid(world):
		return
	ATTACK_RING_SCRIPT.spawn(world, center, COMBAT_AOE_RADIUS)

# A mellow puff burst spawned under the world so it outlives this node (used on
# entering combat and on termination).
func _spawn_mellow(pos: Vector2) -> void:
	var parent: Node = get_parent()
	if parent == null or not is_instance_valid(parent):
		return
	var b: Node2D = MELLOW_BURST_SCRIPT.new() as Node2D
	if b == null:
		return
	parent.add_child(b)
	b.global_position = pos

# Station combat indicator: tint + pulse the beacon red while in combat.
func _set_beacon_combat(on: bool) -> void:
	_beacon_pulse = on
	_pulse_t      = 0.0
	if _beacon != null and is_instance_valid(_beacon):
		_beacon.modulate = COMBAT_BEACON_TINT if on else Color.WHITE

func _tick_beacon_pulse(delta: float) -> void:
	if not _beacon_pulse or _beacon == null or not is_instance_valid(_beacon):
		return
	_pulse_t += delta
	var k: float = 0.5 + 0.5 * sin(_pulse_t * 4.0)
	_beacon.modulate = Color(1.0, 0.22 + 0.5 * k, 0.22 + 0.5 * k, 1.0)

# ── World-follow (caves / dungeons) ───────────────────────────────
# A combat LUA reparents itself under Game, which is never swapped out when the
# player enters a cave/dungeon — so the robot keeps processing and can follow
# the player anywhere. On exit it returns to its home world.
func _home_world_active() -> bool:
	return _home_world != null and is_instance_valid(_home_world) and Global.world_node == _home_world

func _attach_to_game() -> void:
	var game: Node = Global.game_node
	if game == null or not is_instance_valid(game) or get_parent() == game:
		return
	var gp: Vector2 = global_position
	var par: Node = get_parent()
	if par != null:
		par.remove_child(self)
	game.add_child(self)
	global_position = gp

# Show/hide the STATION (beacon + collision + click area). A combat LUA hides
# its station whenever its home world (the overworld) isn't the live one, so the
# station never appears inside a cave/dungeon.
func _set_station_visible(v: bool) -> void:
	if _beacon != null and is_instance_valid(_beacon):
		_beacon.visible = v
	if _station_col != null and is_instance_valid(_station_col):
		_station_col.disabled = not v
	if _click_area != null and is_instance_valid(_click_area):
		_click_area.visible = v
		_click_area.input_pickable = v

# ── Persistence ───────────────────────────────────────────────────
# Saved with the world's placed blocks (world.gd) so a reload keeps the LUA's
# name, index, combat state, tool, build palette, general inventory and program.
func get_lua_save_data() -> Dictionary:
	var palette: Array = []
	for slot in _build_palette:
		palette.append(Global.serialize_item(slot))
	var inv: Array = []
	for slot in _npc_inventory:
		inv.append(Global.serialize_item(slot))
	return {
		"name":       _custom_name,
		"name_index": _name_index,
		"combat":     _combat,
		"combat_hp":  _combat_hp,
		"tool":       Global.serialize_item(_tool if not _tool.is_empty() else null),
		"palette":    palette,
		"inventory":  inv,
		"code":       program_code,
	}

func set_lua_save_data(data: Dictionary) -> void:
	# Name + index (overrides the auto-assigned "LUA N").
	_custom_name = str(data.get("name", _custom_name))
	var ni: int = int(data.get("name_index", _name_index))
	if ni >= 0:
		_name_index = mini(ni, MAX_LUA_INDEX)
	_update_name_label()
	# Tool.
	var tool_slot: Variant = Global.deserialize_item(data.get("tool", null))
	_tool = tool_slot if tool_slot is Dictionary else {}
	# Build palette (3 slots).
	var palette: Variant = data.get("palette", null)
	if palette is Array:
		for i in range(_build_palette.size()):
			_build_palette[i] = Global.deserialize_item((palette as Array)[i]) \
				if i < (palette as Array).size() else null
	# General inventory.
	var inv: Variant = data.get("inventory", null)
	if inv is Array:
		_npc_inventory.clear()
		for entry in (inv as Array):
			var slot: Variant = Global.deserialize_item(entry)
			if slot != null:
				_npc_inventory.append(slot)
	program_code = str(data.get("code", ""))
	build_palette_changed.emit()
	# Combat is IRREVERSIBLE: a saved combat LUA comes back as a combat LUA.
	if bool(data.get("combat", false)) and not _combat:
		_enter_combat(true)
		_combat_hp = clampf(float(data.get("combat_hp", COMBAT_MAX_HP)), 1.0, COMBAT_MAX_HP)

# Damage this combat LUA deals: 75% of its tool's damage, -2% per extra active
# combat LUA.
func combat_damage() -> float:
	var base: float = 1.0
	if not _tool.is_empty():
		var d = _tool.get("data")
		if d is ItemData:
			var id := d as ItemData
			if id.is_sword:
				base = float(id.sword_damage())
			elif id.axe_level > 0 or id.pickaxe_level > 0:
				base = 2.0
	var n: int = _active_combat_count()
	var mult: float = COMBAT_BASE_MULT * maxf(0.0, 1.0 - COMBAT_STACK_PENALTY * float(maxi(n - 1, 0)))
	return base * mult

func _active_combat_count() -> int:
	var n := 0
	for c in get_tree().get_nodes_in_group("LuaNPC"):
		if is_instance_valid(c) and bool(c.get("_combat")):
			n += 1
	return n

# Terminate this combat LUA (remote, or STOP on its station). Gone for good.
func terminate() -> void:
	if _terminated:
		return
	_terminated = true
	Global.notify("%s has been terminated." % get_display_name())
	# Mellow poof on the LUA and on its station before this node is freed
	# (spawned under the world so the burst outlives it).
	_spawn_mellow(_robot.global_position)
	_spawn_mellow(global_position)
	queue_free()

# Combat follow + hostile-mob hunting + enemy contact damage.
func _combat_process(delta: float) -> void:
	var p := Global.player_node as Node2D
	if p == null or not is_instance_valid(p):
		_reset_combat_motion()
		_hunt_target = null
		return
	# Keep the player<->LUA collision exception current (a no-op once applied).
	_exempt_player_collision()
	var dist_p: float = _robot.global_position.distance_to(p.global_position)

	# The player jumped a long way (death respawn, a cave/dungeon swap, the
	# stuck-teleport) — snap to a SAFE, UNOCCUPIED spot near them instead of
	# walking forever. Never the bare "player + fixed offset" it used to be:
	# that could land inside a wall, and with several LUAs they all picked the
	# SAME tile and stacked.
	if dist_p > COMBAT_TELEPORT_DIST:
		_teleport_combat_near_player(p)
		return

	_combat_atk_cd = maxf(0.0, _combat_atk_cd - delta)

	# House restriction: a combat LUA never follows the player inside a house.
	# While the player is indoors it waits OUTSIDE (no pursuit); the movement
	# veto below is the hard check that actually blocks entry.
	if _player_indoors():
		_robot_vel = Vector2.ZERO
		_combat_speed = move_toward(_combat_speed, 0.0, COMBAT_DECEL * delta)
		_combat_stuck_ms = -1
		_tick_combat_contact(delta)
		return

	# Target selection: a nearby hostile mob, else the player (keeping the
	# current engagement so it doesn't oscillate).
	var target: Node2D = _select_combat_target(p, dist_p)
	var hunting: bool = target != p
	# Hunting keeps a stand-off gap from the mob; the follow case uses the LINE
	# anchor directly (the follow gap is already baked into it), so each LUA
	# stands AT its slot in the column instead of orbiting the player.
	var gap: float = COMBAT_ENGAGE_GAP if hunting else 0.0
	var target_pos: Vector2 = target.global_position if hunting else _follow_anchor(p)
	var to: Vector2 = target_pos - _robot.global_position
	var dist: float = to.length()

	# Desired travel direction (the gap is preserved).
	var desired := Vector2.ZERO
	if dist > gap + 8.0:
		desired = to.normalized()
	elif dist < gap - 8.0:
		desired = -to.normalized()

	# Forward obstacle detection + local steering, using the robot's footprint.
	# Other LUAs are excluded: the line formation already spaces them, and
	# treating an ally as a wall made a queue jam up on itself in a corridor.
	var exclude: Array = _steering_exclude()
	var blocked: bool = desired != Vector2.ZERO and not _combat_clear(_robot.global_position, desired, exclude)
	var travel: Vector2 = _combat_travel_dir(desired, exclude)
	# Hard veto: never step into a house interior (a door would let us through).
	if travel != Vector2.ZERO and _move_would_enter_house(travel):
		travel = Vector2.ZERO

	# Dynamic, smoothed pursuit speed.
	var target_speed: float = _combat_target_speed(dist, gap, blocked)
	var rate: float = COMBAT_ACCEL if target_speed > _combat_speed else COMBAT_DECEL
	_combat_speed = move_toward(_combat_speed, target_speed, rate * delta)
	if travel == Vector2.ZERO or desired == Vector2.ZERO:
		_robot_vel = Vector2.ZERO
	else:
		_robot_vel = travel * _combat_speed

	# Autonomous attack on the hunted mob (LOS-gated, one hit per cooldown).
	if hunting and dist <= COMBAT_ATTACK_RANGE and _combat_atk_cd <= 0.0 and _has_los_to(target):
		_combat_atk_cd = COMBAT_ATTACK_CD
		_combat_attack(_robot.global_position)

	# Progress tracking / last-resort recovery, then contact damage.
	_tick_combat_stuck(target, dist, gap, not hunting)
	_tick_combat_contact(delta)

# ── Target selection (hostile mob vs player) ──────────────────────
# Priority: keep the current hunting target while it stays valid + close to
# both the LUA and the player (no oscillation) → an opportunistically-detected
# nearby hostile mob → player pursuit.
func _select_combat_target(p: Node2D, dist_p: float) -> Node2D:
	var t: Node2D = _hunt_target
	if t != null and (not is_instance_valid(t) or not t.is_inside_tree()):
		_hunt_target = null
		t = null
	if t != null:
		var d_lua: float = _robot.global_position.distance_to(t.global_position)
		var d_pl:  float = p.global_position.distance_to(t.global_position)
		if d_lua > COMBAT_HUNT_DROP or d_pl > COMBAT_HUNT_LEASH * 1.5:
			_hunt_target = null
			t = null
	if t != null:
		return t
	# Throttled scan so we don't sweep the mob list every frame.
	if Time.get_ticks_msec() - _hunt_scan_ms >= int(COMBAT_HUNT_RESCAN * 1000.0):
		_hunt_scan_ms = Time.get_ticks_msec()
		var m: Node2D = _find_hostile_mob(COMBAT_HUNT_RADIUS, p.global_position)
		if m != null:
			_hunt_target = m
			return m
	return p

# Nearest HOSTILE mob that is within `radius` of the LUA, within the player
# leash, and has line of sight, or null.
func _find_hostile_mob(radius: float, player_pos: Vector2) -> Node2D:
	if not is_inside_tree():
		return null
	var best: Node2D = null
	var best_d: float = radius
	for m in get_tree().get_nodes_in_group("Mob"):
		if not (m is Node2D) or not is_instance_valid(m):
			continue
		if not _is_hostile_mob(m):
			continue
		var mob := m as Node2D
		var d: float = mob.global_position.distance_to(_robot.global_position)
		if d >= best_d:
			continue
		if mob.global_position.distance_to(player_pos) > COMBAT_HUNT_LEASH:
			continue
		if not _has_los_to(mob):
			continue
		best_d = d
		best = mob
	return best

# True for a HOSTILE mob (MobCombatData.behavior == HOSTILE). Reads the mob's
# own COMBAT_DATA constant, so it needs no new per-mob faction API.
func _is_hostile_mob(m: Node) -> bool:
	var sc: Script = m.get_script()
	if sc == null:
		return false
	var cd: Variant = sc.get_script_constant_map().get("COMBAT_DATA")
	return cd is MobCombatData and (cd as MobCombatData).behavior == MobCombatData.Behavior.HOSTILE

# True when a wall-only ray from the robot reaches `target` (walls, trees and
# placed blocks block it; the mob itself is not in the mask, so it never
# counts as its own obstacle). Fellow LUAs are excluded too — an ally standing
# between this robot and a mob must not hide the mob from it.
func _has_los_to(target: Node2D) -> bool:
	if not is_inside_tree() or target == null or not is_instance_valid(target):
		return false
	var world_2d := get_world_2d()
	if world_2d == null:
		return false
	var query := PhysicsRayQueryParameters2D.create(_robot.global_position, target.global_position)
	query.collision_mask = OBSTACLE_MASK
	query.exclude        = _steering_exclude()
	return world_2d.direct_space_state.intersect_ray(query).is_empty()

# One attack event: the 3x3 AoE centred on the LUA, shared by the player-swing
# trigger and the autonomous mob-hunt attack.
func _combat_attack(center: Vector2) -> void:
	var dmg: float = combat_damage()
	var nearest: Node2D = null
	var nearest_d: float = COMBAT_AOE_RADIUS
	for m in get_tree().get_nodes_in_group("Mob"):
		if not (m is Node2D) or not is_instance_valid(m):
			continue
		var mob := m as Node2D
		var d: float = mob.global_position.distance_to(center)
		if d <= COMBAT_AOE_RADIUS and d < nearest_d:
			nearest_d = d
			nearest = mob
		if d > COMBAT_AOE_RADIUS:
			continue
		if mob.has_method("take_hit"):
			# NO KNOCKBACK from a LUA hit (the trailing `false`). The shove used
			# to fight the mob's own steering — re-applied on every player swing
			# and every autonomous attack — which made provoked enemies look like
			# they were moving and attacking in slow motion.
			mob.call("take_hit", dmg, center, false)
		# Hostile mobs now target this LUA instead of the player.
		if mob.has_method("provoke"):
			mob.call("provoke", _robot)
	_swing_at(nearest.global_position if nearest != null else Vector2.INF, 1.0, 6)
	_spawn_attack_ring(center)

# The target speed for this frame from the distance + the player's own speed.
func _combat_target_speed(dist: float, gap: float, blocked: bool) -> float:
	# Within the gap → hold position (the 3x3 swing covers the target).
	if dist <= gap + 8.0 and dist >= gap - 8.0:
		return 0.0
	var sp: float = COMBAT_SPEED_NORMAL
	if dist > COMBAT_SPRINT_DIST:
		sp = COMBAT_SPEED_SPRINT
	# Run down a sprinting player once there's real ground to close.
	if _player_sprinting() and dist > COMBAT_SPRINT_DIST * 0.5:
		sp = maxf(sp, COMBAT_SPEED_SPRINT)
	# Ease off when boxed in / backing off, so it doesn't slam walls.
	if blocked or dist < gap:
		sp = minf(sp, COMBAT_SPEED_MIN)
	return sp

func _player_sprinting() -> bool:
	var p := Global.player_node
	if p == null or not is_instance_valid(p) or not p.has_method("is_sprinting"):
		return false
	return bool(p.call("is_sprinting"))

# ── Line formation (multiple combat LUAs) ─────────────────────────
# With more than one combat LUA following, they form a single-file LINE behind
# the player instead of all aiming at the player's tile (which made them pile up
# and flicker). Each LUA takes a slot COMBAT_FOLLOW_GAP + rank*COMBAT_LINE_SPACING
# further back along the player's heading, so they trail one after another
# ("successively") — the lead LUA sits right behind the player, the next behind
# that, and so on.
func _follow_anchor(p: Node2D) -> Vector2:
	var dir: Vector2 = _player_heading(p)
	if dir == Vector2.ZERO:
		return p.global_position
	var back: float = COMBAT_FOLLOW_GAP + COMBAT_LINE_SPACING * float(_combat_line_rank())
	return p.global_position - dir * back

# The direction the follow line trails behind: the player's travel direction
# while they move (remembered so a standing player aiming the mouse around
# doesn't make the column orbit them), else their facing.
var _line_dir_cache: Vector2 = Vector2.ZERO

func _player_heading(p: Node2D) -> Vector2:
	if p is CharacterBody2D:
		var v: Vector2 = (p as CharacterBody2D).velocity
		if v.length() > 8.0:
			_line_dir_cache = v.normalized()
			return _line_dir_cache
	if _line_dir_cache != Vector2.ZERO:
		return _line_dir_cache
	if p.has_method("facing_vector"):
		var f: Variant = p.call("facing_vector")
		if f is Vector2 and (f as Vector2).length() > 0.001:
			return (f as Vector2).normalized()
	return Vector2.ZERO

# This LUA's slot in the follow column (0 = the lead, right behind the player).
# The order is stable — LUA name index first, then instance id as a tiebreak —
# so the slots never swap every frame.
func _combat_line_rank() -> int:
	if not is_inside_tree():
		return 0
	var mine: int = _name_index if _name_index >= 0 else 1 << 30
	var my_id: int = get_instance_id()
	var rank: int = 0
	for n in get_tree().get_nodes_in_group("LuaNPC"):
		if n == self or not is_instance_valid(n) or not bool(n.get("_combat")):
			continue
		var other: int = int(n.get("_name_index"))
		if other < 0:
			other = 1 << 30
		if other < mine or (other == mine and n.get_instance_id() < my_id):
			rank += 1
	return mini(rank, COMBAT_LINE_MAX_RANK)

# RIDs the steering should IGNORE: this robot itself, plus every other LUA's
# robot. A LUA is not an obstacle to another LUA — the line formation (combat)
# keeps them apart, and treating an ally as a wall made a queue jam up on itself
# in a corridor. Physics still stops them overlapping.
func _steering_exclude() -> Array:
	var rids: Array = [_robot.get_rid()]
	if not is_inside_tree():
		return rids
	for n in get_tree().get_nodes_in_group("LuaNPC"):
		if n == self or not is_instance_valid(n):
			continue
		var other: Variant = n.get("_robot")
		if other is CharacterBody2D and is_instance_valid(other):
			rids.append((other as CharacterBody2D).get_rid())
	return rids

# Steering: the desired direction if its footprint path is clear, else the
# closest clear reroute angle. ZERO when fully boxed in.
#
# The chosen reroute is COMMITTED for COMBAT_COMMIT_SEC: re-picking every frame
# let two equally-open angles alternate and the robot stalled on the spot (the
# "suffers in tight spaces" symptom). The commit is dropped early if it stops
# being clear or starts pointing away from the goal.
func _combat_travel_dir(desired: Vector2, exclude: Array) -> Vector2:
	if desired == Vector2.ZERO:
		_combat_commit_dir = Vector2.ZERO
		return Vector2.ZERO
	var now: int = Time.get_ticks_msec()
	if _combat_commit_dir != Vector2.ZERO and now < _combat_commit_until_ms \
			and _combat_commit_dir.dot(desired) > 0.0 \
			and _combat_clear(_robot.global_position, _combat_commit_dir, exclude):
		return _combat_commit_dir
	if _combat_clear(_robot.global_position, desired, exclude):
		_combat_commit_dir = Vector2.ZERO
		return desired
	for ang in COMBAT_REROUTE_DEG:
		var cand: Vector2 = desired.rotated(deg_to_rad(ang))
		if _combat_clear(_robot.global_position, cand, exclude):
			_combat_commit_dir      = cand
			_combat_commit_until_ms = now + int(COMBAT_COMMIT_SEC * 1000.0)
			return cand
	_combat_commit_dir = Vector2.ZERO
	return Vector2.ZERO

# Footprint-aware clearance: sweep the robot's OWN collision shape one lookahead
# step along `dir`. A point ray says "clear" while the body's edge clips a
# corner — the diagonal-corner / narrow-corridor stall. Mirrors the headless
# fish's shape-sweep navigation.
func _combat_clear(from: Vector2, dir: Vector2, exclude: Array) -> bool:
	if dir == Vector2.ZERO:
		return true
	if not is_inside_tree():
		return false
	var world_2d := get_world_2d()
	if world_2d == null:
		return false
	var space := world_2d.direct_space_state
	var step: Vector2 = dir.normalized() * COMBAT_LOOKAHEAD
	var col := _robot_collision_shape()
	if col != null:
		var params := PhysicsShapeQueryParameters2D.new()
		params.shape          = col.shape
		params.transform      = col.global_transform
		params.motion         = step
		params.collision_mask = OBSTACLE_MASK
		params.exclude        = exclude
		params.margin         = 0.0
		var res: PackedFloat32Array = space.cast_motion(params)
		if res.size() >= 1:
			return res[0] >= 1.0
	# Fallback (no collision shape): centre ray.
	var query := PhysicsRayQueryParameters2D.create(from, from + step)
	query.collision_mask = OBSTACLE_MASK
	query.exclude        = exclude
	query.hit_from_inside = true
	return space.intersect_ray(query).is_empty()

func _robot_collision_shape() -> CollisionShape2D:
	if _robot_col != null and is_instance_valid(_robot_col):
		return _robot_col
	for c in _robot.get_children():
		if c is CollisionShape2D and (c as CollisionShape2D).shape != null:
			_robot_col = c as CollisionShape2D
			break
	return _robot_col

# ── Stuck detection + teleport recovery ───────────────────────────
# Tracks the CLOSING distance to the player: brief pauses (waiting in the
# follow gap, steering around a corner) don't count, only a sustained failure
# to make progress. On timeout it tries ONE valid spot near the player, on a
# cooldown, and otherwise keeps trying through normal movement.
func _tick_combat_stuck(target: Node2D, dist: float, gap: float, is_player: bool) -> void:
	if dist <= gap + 8.0:
		_combat_stuck_ms = -1
		_combat_last_dist = dist
		return
	if dist < _combat_last_dist - COMBAT_STUCK_PROGRESS:
		_combat_last_dist = dist
		_combat_stuck_ms = -1
		return
	if _combat_stuck_ms < 0:
		_combat_stuck_ms = Time.get_ticks_msec()
		return
	if Time.get_ticks_msec() - _combat_stuck_ms < int(COMBAT_STUCK_SEC * 1000.0):
		return
	_combat_stuck_ms  = -1
	_combat_last_dist = dist
	# Hunting a mob we can't reach → drop it and resume normal behaviour (no
	# teleport). Player pursuit is the only case that teleport-recovers.
	if not is_player:
		_hunt_target = null
		return
	if Time.get_ticks_msec() - _combat_recover_ms < int(COMBAT_RECOVER_CD_SEC * 1000.0):
		return
	_combat_recover_ms = Time.get_ticks_msec()
	_teleport_combat_near_player(target)

# Find a valid recovery/teleport spot near the player and teleport there. The
# spot is never on the player, inside a house, on another LUA, or overlapping a
# wall. If nothing valid exists it does nothing (normal recovery keeps running)
# rather than teleporting to an arbitrary spot — EXCEPT for the long-distance
# case, which must land somewhere (walking across the world would never arrive).
func _teleport_combat_near_player(p: Node2D) -> void:
	if _robot == null or not is_instance_valid(_robot):
		return
	var spot: Vector2 = _find_recovery_spot(p)
	if spot == Vector2.INF:
		# Nothing open within the search radius: fall back to the plain offset so
		# a long-distance catch-up still happens. Only reached when the spiral
		# search found no free tile at all.
		spot = p.global_position + Vector2(0.0, COMBAT_TELEPORT_GAP)
	_robot.global_position = spot
	_reset_combat_motion()

# A safe landing spot near `p`: tries several offset search centres (so
# simultaneous recoveries never pick the same tile) and validates each one
# against the player's tile, houses, other LUAs, and the physics world.
func _find_recovery_spot(p: Node2D) -> Vector2:
	var world: Node = Global.world_node
	var use_world: bool = world != null and is_instance_valid(world) \
		and world.has_method("find_open_spot_near")
	for attempt in range(COMBAT_RECOVER_TRIES):
		var center: Vector2 = p.global_position
		if attempt > 0:
			center += Vector2.from_angle(TAU * float(attempt) / float(COMBAT_RECOVER_TRIES)) * TILE_SIZE
		# Prefer the world's own open-tile search — it also rejects water, trees,
		# placed blocks and cave/dungeon entrances. It exists only on the
		# overworld, so caves/dungeons fall through to the footprint sweep below
		# (which is why a stuck combat LUA used to have NO recovery in a cave).
		var spot: Vector2 = Vector2.INF
		if use_world:
			spot = world.call("find_open_spot_near", center, COMBAT_RECOVER_RADIUS) as Vector2
		if spot == Vector2.INF:
			spot = _find_free_spot(center, float(COMBAT_RECOVER_RADIUS) * TILE_SIZE)
		if spot == Vector2.INF:
			continue
		if spot.distance_to(p.global_position) < 16.0:
			continue   # never on top of the player
		if _cell_blocks_house_entry(world, spot):
			continue   # never teleport into a house
		if _recovery_spot_taken(spot):
			continue   # keep LUAs off each other's tile
		return spot
	return Vector2.INF

# Generic footprint-based open-spot search that works in EVERY world: spiral
# outward from `center` and return the first position where the robot's own
# collision shape overlaps nothing solid. The overworld's find_open_spot_near is
# overworld-only, so this is the only recovery available inside caves/dungeons.
func _find_free_spot(center: Vector2, max_radius_px: float) -> Vector2:
	if not is_inside_tree():
		return Vector2.INF
	var world_2d := get_world_2d()
	if world_2d == null:
		return Vector2.INF
	var col := _robot_collision_shape()
	if col == null or col.shape == null:
		return center
	var space := world_2d.direct_space_state
	var exclude: Array = _steering_exclude()
	# Ring by ring at half-tile steps, with 8+ sample directions per ring.
	var steps: int = maxi(1, int(ceil(max_radius_px / (TILE_SIZE * 0.5))))
	for r in range(1, steps + 1):
		var radius: float = float(r) * TILE_SIZE * 0.5
		var count: int = maxi(8, r * 8)
		for i in range(count):
			var cand: Vector2 = center + Vector2.from_angle(TAU * float(i) / float(count)) * radius
			if _spot_is_free(space, col, cand, exclude):
				return cand
	return Vector2.INF

# True when the robot's collision shape, placed at `robot_pos`, overlaps no
# solid body on the obstacle layer.
func _spot_is_free(space: PhysicsDirectSpaceState2D, col: CollisionShape2D,
		robot_pos: Vector2, exclude: Array) -> bool:
	if space == null or col == null or col.shape == null:
		return false
	var params := PhysicsShapeQueryParameters2D.new()
	params.shape          = col.shape
	# The shape sits at col.position inside the Robot node (no rotation), so the
	# candidate transform is that offset applied to the candidate robot position.
	params.transform      = Transform2D(0.0, robot_pos + col.position)
	params.collision_mask = OBSTACLE_MASK
	params.exclude        = exclude
	params.margin         = 0.0
	return space.intersect_shape(params, 1).is_empty()

# True when another LuaNPC's robot already sits within COMBAT_MIN_SPACING of
# `spot`, so two recoveries never stack on one tile.
func _recovery_spot_taken(spot: Vector2) -> bool:
	if not is_inside_tree():
		return false
	for n in get_tree().get_nodes_in_group("LuaNPC"):
		if n == self or not is_instance_valid(n):
			continue
		var other: Variant = n.get("_robot")
		if other is Node2D and is_instance_valid(other) \
				and (other as Node2D).global_position.distance_to(spot) < COMBAT_MIN_SPACING:
			return true
	return false

func _reset_combat_motion() -> void:
	_robot_vel        = Vector2.ZERO
	_robot.velocity   = Vector2.ZERO
	_combat_speed     = 0.0
	_combat_stuck_ms  = -1
	_combat_last_dist = INF
	# Drop any steering commit: after a teleport the old direction is meaningless
	# and would carry the robot away from its new spot for up to COMBAT_COMMIT_SEC.
	_combat_commit_dir      = Vector2.ZERO
	_combat_commit_until_ms = 0

# Enemies hurt the LUA on contact (cooldown per hit).
func _tick_combat_contact(delta: float) -> void:
	_combat_hit_cd = maxf(0.0, _combat_hit_cd - delta)
	if _combat_hit_cd > 0.0:
		return
	for m in get_tree().get_nodes_in_group("Mob"):
		if not (m is Node2D) or not is_instance_valid(m):
			continue
		if (m as Node2D).global_position.distance_to(_robot.global_position) <= COMBAT_CONTACT_PX:
			_combat_hit_cd = COMBAT_CONTACT_CD
			_combat_hp = maxf(0.0, _combat_hp - COMBAT_CONTACT_DMG)
			if _combat_hp <= 0.0:
				terminate()
			break

# ── House-entry restriction ───────────────────────────────────────
# True when the player is inside a VALID house (overworld only). The combat LUA
# waits outside instead of following in.
func _player_indoors() -> bool:
	var world: Node = Global.world_node
	if world == null or not world.has_method("housing_is_valid_room_cell"):
		return false
	return Global.player_indoors

# True when `world_pos` sits on (or is boxed in by) a house interior — a hard
# veto used by BOTH movement and teleport recovery so no code path can bypass
# it. Checks the cell plus its 4 neighbours, so the doorway (a boundary tile)
# and the tile just outside also read as "house" and the LUA stops short.
func _cell_blocks_house_entry(world: Node, world_pos: Vector2) -> bool:
	if world == null or not is_instance_valid(world):
		return false
	if not world.has_method("housing_is_valid_room_cell") or not world.has_method("world_to_cell"):
		return false
	var cell: Vector2i = world.call("world_to_cell", world_pos)
	if bool(world.call("housing_is_valid_room_cell", cell)):
		return true
	for off in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		if bool(world.call("housing_is_valid_room_cell", cell + off)):
			return true
	return false

# Would stepping `travel` from here put the robot inside a house?
func _move_would_enter_house(travel: Vector2) -> bool:
	var world: Node = Global.world_node
	if world == null:
		return false
	var ahead: Vector2 = _robot.global_position + travel.normalized() * COMBAT_LOOKAHEAD
	return _cell_blocks_house_entry(world, ahead)

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
	_set_status("Searching for %s" % name)
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
		_set_status("Mining %s" % name)
		if not await _walk_to_node(block):
			_is_working = false
			return
		if _stop_requested:
			break
		if block.has_method("_break"):
			# Mining plays the swing beat at the block, then breaks it.
			await _interact(block.global_position, 0.8, 4)
			if _stop_requested:
				break
			block.call("_break")
		await get_tree().create_timer(PICKUP_DELAY).timeout
		_collect_drops_nearby()
		mined += 1
		_lua_state.emit_signal("signal_print", "[mine] storing... (%d x %s)" % [mined, name])
	await _return_and_idle()
	_lua_state.emit_signal("signal_print", "[mine] done — mined %d x %s." % [mined, name])

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
	_set_status("Using crafting station")
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
		await _apply_station_job(station, job)
	await _return_and_idle()

func _apply_station_job(station: Node, job: Dictionary) -> void:
	# Interaction beat before the station acts (not instant). Item interaction →
	# the longer 3s cooldown.
	await _interact(station.global_position, 1.0, 5, true)
	if not is_instance_valid(station):
		return
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
	await _interact(Vector2.INF, 1.0, 5)
	if not is_inside_tree(): return
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

# True while there is anything for STOP to stop: a dispatched job, a velocity
# left behind by move(), or station work still queued behind a job. The editor
# keeps STOP enabled only while this is true, so a script that has already
# finished (and left nothing running) cannot offer a button that does nothing.
func has_active_work() -> bool:
	return _is_working or _robot_vel != Vector2.ZERO \
		or not _station_queue.is_empty() or not _build_queue.is_empty()

func stop_work() -> void:
	# NOTE: STOP no longer terminates a combat LUA. Termination is a MENU action
	# now (pause menu -> LUA Management), so the player always has to pick the
	# specific LUA from the active list. STOP on a combat LUA just halts whatever
	# work it was doing; the internal terminate() path (death to enemies) is
	# unaffected.
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
	_build_queue.clear()
	_set_status("Idle")
	# A finished job may have queued station work behind it (e.g. chop_trees()
	# then input_slot()/craft()) — kick that queue now that we're free.
	if not _station_queue.is_empty():
		_run_station_jobs.call_deferred()

# ─────────────────────────────────────────────────────────────────
# ── AUTONOMOUS BEHAVIOURS ─────────────────────────────────────────
# ─────────────────────────────────────────────────────────────────

func _auto_work() -> void:
	_set_status("Working")
	_unreachable.clear()
	while true:
		if _stop_requested: break
		var tree: Node2D = _nearest_tree_in_radius()
		if tree == null: break
		_set_status("Chopping trees")
		if not await _walk_to_node(tree, false):
			if _stop_requested or not is_inside_tree():
				_is_working = false
				return
			# Could not path to this tree (walled in, or the walk timed out and
			# recalled us home). Remember it and try the NEXT tree — bailing out
			# here is what made a LUA walk home having done nothing at all.
			_unreachable.append(tree)
			continue
		if _stop_requested: break
		# ONE interaction beat as we START on this tree, then chop at CHOP_DELAY
		# so the tree falls in its real break time. Routing EVERY chop through
		# _interact() put the 1.5s modify cooldown INSIDE the loop, so a single
		# 4-second tree took ~27s and the robot looked permanently stuck.
		await _interact(tree.global_position, 0.9, 5)
		while is_instance_valid(tree):
			if _stop_requested: break
			_swing_at(tree.global_position, 0.9, 5)   # FX only — no cooldown
			tree.call("chop", CHOP_DELAY)
			await get_tree().create_timer(CHOP_DELAY).timeout
		await get_tree().create_timer(PICKUP_DELAY).timeout
		_collect_drops_nearby()

	if not _stop_requested:
		var chest: Node = _nearest_chest_in_radius()
		if chest != null and is_instance_valid(chest):
			_set_status("Depositing to chest")
			if not await _walk_to_node(chest as Node2D):
				_is_working = false
				return
			await _deposit_to_chest(chest)
	await _return_and_idle()

func _chop_all_trees() -> void:
	_set_status("Chopping trees")
	_unreachable.clear()
	while true:
		if _stop_requested: break
		var tree: Node2D = _nearest_tree_in_radius()
		if tree == null: break
		if not await _walk_to_node(tree, false):
			if _stop_requested or not is_inside_tree():
				_is_working = false
				return
			# Could not path to this tree (walled in, or the walk timed out and
			# recalled us home). Remember it and try the NEXT tree — bailing out
			# here is what made a LUA walk home having done nothing at all.
			_unreachable.append(tree)
			continue
		if _stop_requested: break
		# ONE interaction beat as we START on this tree, then chop at CHOP_DELAY
		# so the tree falls in its real break time. Routing EVERY chop through
		# _interact() put the 1.5s modify cooldown INSIDE the loop, so a single
		# 4-second tree took ~27s and the robot looked permanently stuck.
		await _interact(tree.global_position, 0.9, 5)
		while is_instance_valid(tree):
			if _stop_requested: break
			_swing_at(tree.global_position, 0.9, 5)   # FX only — no cooldown
			tree.call("chop", CHOP_DELAY)
			await get_tree().create_timer(CHOP_DELAY).timeout
		await get_tree().create_timer(PICKUP_DELAY).timeout
		_collect_drops_nearby()

	await _return_and_idle()

func _walk_to_spawn_then_stop() -> void:
	await _return_and_idle()

func _deposit_then_stop() -> void:
	_set_status("Depositing to chest")
	var chest: Node = _nearest_chest_in_radius()
	if chest != null and is_instance_valid(chest):
		if not await _walk_to_node(chest as Node2D):
			_is_working = false
			return
		await _deposit_to_chest(chest)
	await _return_and_idle()

func _print_chest_items() -> void:
	_set_status("Reading chest")
	var chest: Node = _nearest_chest_in_radius()
	if chest == null or not is_instance_valid(chest):
		_lua_state.emit_signal("signal_print", "No chest in radius.")
		await _return_and_idle()
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
	await _return_and_idle()

# ── Walk helpers ──────────────────────────────────────────────────

# Walk robot toward a world node, rerouting around solid obstacles (trees,
# placed blocks, chests). Returns false if it got stuck and had to be
# recalled to the station instead of arriving normally.
func _walk_to_node(target: Node2D, recall_on_stuck: bool = true) -> bool:
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
		if dist <= INTERACT_RADIUS_PX:
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
			_handle_stuck(recall_on_stuck)
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
# candidate direction is blocked (fully boxed in). Fellow LUAs are merged into
# the exclusion list so a robot never routes around an ally as if it were a wall.
func _pick_travel_dir(from: Vector2, desired_dir: Vector2, exclude_rids: Array) -> Vector2:
	var ex: Array = exclude_rids.duplicate()
	ex.append_array(_steering_exclude())
	if _path_is_clear(from, desired_dir, ex):
		return desired_dir
	for angle in REROUTE_ANGLES_DEG:
		var candidate: Vector2 = desired_dir.rotated(deg_to_rad(angle))
		if _path_is_clear(from, candidate, ex):
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

# Shows the stuck dialogue and (optionally) instantly recalls the robot to its
# station. A chop job passes recall = false: it just skips the unreachable tree
# and carries on from where it stands, instead of being yanked home.
func _handle_stuck(recall: bool = true) -> void:
	Global.lua_stuck_notice.emit("An Automatica got stuck!")
	_robot_vel      = Vector2.ZERO
	if recall:
		_robot.position = Vector2.ZERO

# ── Search helpers ────────────────────────────────────────────────

# Nearest tree within the work radius of the STATION (not the robot).
func _nearest_tree_in_radius() -> Node2D:
	if not is_inside_tree():
		return null
	var best:  Node2D = null
	var best2: float  = _work_radius_px * _work_radius_px
	for node in get_tree().get_nodes_in_group("Tree"):
		if not (node is Node2D): continue
		if _unreachable.has(node): continue
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
		if dist > INTERACT_RADIUS_PX * 2.0: continue
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
	var stack_limit: int = data.stack_limit()
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
	await _interact(chest.global_position, 1.0, 5)
	if not is_instance_valid(chest):
		return
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

func _build_frames(combat: bool = false) -> SpriteFrames:
	var sf := SpriteFrames.new()
	sf.remove_animation("default")
	# Floating entity: one STATIC frame per direction (front/back/side), no
	# walk cycle. Both the idle_ and walk_ animation names are kept so the rest
	# of the code (which asks for walk_<dir>/idle_<dir>) is unchanged.
	var table: Dictionary = DIR_TEX_COMBAT if combat else DIR_TEX
	var fallback: Texture2D = TEX_COMBAT_FRONT if combat else TEX_FRONT
	for d in DIRS:
		var dir: String = d["name"]
		var tex: Texture2D = table.get(dir, fallback)
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
