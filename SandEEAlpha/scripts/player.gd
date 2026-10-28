extends CharacterBody2D

@export var movement_speed: int   = 80
const SPRINT_MULTIPLIER:   float = 1.8

const SHADOW_TEXTURE: Texture2D = preload("res://sprites/shadow/shadow_base.png")
const SWING_SCRIPT: GDScript = preload("res://scripts/sword_swing_effect.gd")
const BUCKET_ITEM: ItemData = preload("res://resources/items/bucket.tres")
const WATER_BUCKET_ITEM: ItemData = preload("res://resources/items/water_bucket.tres")
const FISHING_SCRIPT: GDScript = preload("res://scripts/fishing_controller.gd")

@onready var sprite:           AnimatedSprite2D = $PlayerSprite
@onready var interaction_shape: CollisionShape2D = $Area2D/InteractionCol
@onready var inventory_layer:   CanvasLayer      = $InventoryUI
@onready var inventory_panel:   Control          = $InventoryUI/InventoryUi

# Rebuilding costs ~72 texture lookups; caching mainly helps on scene reload/respawn.
static var _shared_frames: SpriteFrames = null

var input_direction: Vector2 = Vector2.ZERO
var _last_dir:   String = "south"   # default facing
# The VISIBLE facing. Follows the mouse (so the body matches the mouse-aimed
# swing), falling back to the movement direction when the cursor is on the
# player. `_last_dir` stays the movement facing.
var _face_dir:   String = "south"

# Fired whenever a swing animation actually plays. World backends (overworld
# grass cutting, etc.) connect to this so their swing-coupled gameplay runs
# on the same trigger regardless of which world scene is active.
signal swing_performed
var _fishing: Node2D = null   # FishingController child (created in _ready)
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

# ── Stuck / anti-corner detection ──────────────────────────────────
# If the player holds movement input but stops making real progress for
# STUCK_TELEPORT_TIME, something is wedging them (a block/tree/grass corner).
# First a small perpendicular repulsion tries to slide them out of the nook;
# if that doesn't free them within the window, they're teleported to the
# nearest open tile (see world.gd find_open_spot_near).
const STUCK_MOVE_THRESHOLD: float = 1.0   # px of real movement that clears "stuck"
const STUCK_TELEPORT_TIME:  float = 5.0   # sec held without moving → teleport
const STUCK_REPEL_TIME:     float = 2.0   # sec held without moving → first nudge
const STUCK_REPEL_INTERVAL: float = 1.0   # sec between repeated nudges while still stuck
const STUCK_REPEL_DIST:     float = 3.0   # px per nudge
const STUCK_TELEPORT_SEARCH: int = 6      # tile radius to spiral-search for an open spot

var _stuck_time: float = 0.0
var _last_pos:   Vector2 = Vector2.ZERO
var _last_repel: float = -INF

# ── Snowfall weather effect ───────────────────────────────────────
# Single GPUParticles2D under the camera — follows it for free via normal
# transform inheritance, so there's no per-frame script cost while active.
# Biome is only polled twice a second (see _biome_check_timer), not per-frame.
var _snow_particles:     GPUParticles2D = null
var _in_snow_biome:      bool = false
var _biome_check_timer:  Timer = null
var _snow_fade_tween:    Tween = null
const SNOW_FADE_TIME: float = 1.5

# ── Snowstorm ─────────────────────────────────────────────────────
# Rolled once per day-start (Global.day_started, fired by day_night_cycle.gd)
# while standing in snow — no per-frame cost. Ends on leaving snow biome
# (checked in the same 0.5s poll as the base snowfall) or when night falls.
const SNOWSTORM_CHANCE:      float = 0.2   # 1 in 5
const SNOWSTORM_SPEED_MULT:  float = 0.55
const STORM_SPREAD:          float = 45.0
const STORM_VEL_MIN:         float = 70.0
const STORM_VEL_MAX:         float = 120.0
const CALM_SPREAD:           float = 15.0
const CALM_VEL_MIN:          float = 35.0
const CALM_VEL_MAX:          float = 60.0
# Storm coverage/density — still a single GPU-simulated particle system (one
# draw call), just a bigger emission volume and more of them in it. Sized to
# stay full-screen even at the lowest camera zoom (0.5x, see pause_menu.gd).
const CALM_AMOUNT:           int   = 80
const STORM_AMOUNT:          int   = 4000  # 10x — still one GPU-instanced draw call
const CALM_BOX_EXTENTS:      Vector3 = Vector3(900.0, 350.0, 1.0)
const STORM_BOX_EXTENTS:     Vector3 = Vector3(1800.0, 1000.0, 1.0)

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
	# Point-and-click feedback (ring + sword marker). Top-level so it draws over
	# the world's y-sorted sprites and is freed with the player.
	_pnc_marker = PNC_INDICATOR_SCRIPT.new() as Node2D
	_pnc_marker.top_level = true
	add_child(_pnc_marker)
	_fishing = FISHING_SCRIPT.new()
	_fishing.name = "FishingController"
	add_child(_fishing)
	$mainCam.zoom = Vector2(Global.camera_zoom, Global.camera_zoom)
	Global.camera_zoom_changed.connect(_on_camera_zoom_changed)
	_update_camera_limits(true)
	if _shared_frames == null:
		_shared_frames = _build_frames()
	sprite.sprite_frames = _shared_frames
	# Scaled-up 32x64 art. The art's bottom is the frame's last row (pixel 63 =
	# +31.5 from the centered origin), so offset it back onto the +23 y-sort
	# line after scaling.
	sprite.scale  = Vector2(SPRITE_SCALE, SPRITE_SCALE)
	sprite.offset = Vector2(0.0, FEET_LINE_Y / SPRITE_SCALE - (FRAME_H / 2.0 - 0.5))
	# Shadow at the sprite's actual feet (FEET_LINE_Y = +23), matching
	# PlayerCol's waist-high box bottom — was +14, which sat at the old sprite's
	# base and left the shadow floating above the new taller art's feet.
	add_child(Global.make_shadow_sprite(SHADOW_TEXTURE, Vector2(0.0, FEET_LINE_Y), Vector2(0.8, 0.4), 0.35))
	sprite.play("idle_south")
	_setup_summon_fx()
	Global.request_close_all_ui.connect(_on_close_all_ui)
	# Turning the optional scheme OFF mid-order must stop the character cleanly.
	Global.point_and_click_changed.connect(func(_on: bool) -> void: _pnc_cancel())
	# Losing window focus must not leave a tap order, held key/joystick or sprint
	# running while the player is not actually driving the game.
	var win := get_window()
	if win != null and not win.focus_exited.is_connected(_on_window_focus_exited):
		win.focus_exited.connect(_on_window_focus_exited)
	if Global.has_pending_pos:
		global_position    = Global.pending_player_pos
		Global.has_pending_pos = false
	for m in Global.missions:
		if m["id"] == "move"           and m["completed"]: _move_mission_done      = true
		if m["id"] == "open_inventory" and m["completed"]: _inventory_mission_done = true
	Global.Inventory_updated.connect(_refresh_has_boat_cache)
	Global.Hotbar_updated.connect(_refresh_has_boat_cache)
	_refresh_has_boat_cache()

	_snow_particles = _build_snow_particles()
	_biome_check_timer = Timer.new()
	_biome_check_timer.wait_time = 0.5
	_biome_check_timer.autostart = true
	_biome_check_timer.timeout.connect(_check_biome)
	add_child(_biome_check_timer)
	Global.day_started.connect(_on_day_started)
	Global.night_started.connect(_on_night_started)

func _exit_tree() -> void:
	# A scene/world swap can free the player mid-order. Release synthetic holds
	# and the shared touch cursor so the next player does not inherit a stale
	# world-space click position.
	_pnc_cancel()
	Global.clear_touch_mouse()
	Global.mobile_move  = Vector2.ZERO
	Global.mobile_shift = false

func _on_camera_zoom_changed(zoom: float) -> void:
	$mainCam.zoom = Vector2(zoom, zoom)
	# The visible world size changed, so an area that was wider than the viewport
	# may no longer be — re-derive the limits immediately.
	_update_camera_limits(true)

# ── Camera bounds (per-area clamping) ───────────────────────────────
# The camera must never scroll past the ACTIVE area's playable rect — the
# overworld, the cave/pixie cave, or the dungeon it is currently in. The bounds
# come from the LIVE world (camera_bounds() on world.gd / cave_world.gd /
# pixie_cave_world.gd / dungeon_world.gd) rather than a constant, so entering,
# regenerating or leaving an area re-clamps automatically, and there is no
# cached rect that could go stale when the map changes.
#
# Godot's Camera2D limits clamp the VISIBLE RECT, so viewport size and zoom are
# handled for free. The one case they don't cover is an area SMALLER than the
# viewport: there the limits are widened to exactly one viewport, centred on the
# area, which pins the camera to the area's centre on that axis.
var _cam_bounds: Rect2 = Rect2()
var _cam_view:   Vector2 = Vector2.ZERO
var _cam_set:    bool = false

func _update_camera_limits(force: bool = false) -> void:
	var cam: Camera2D = $mainCam
	if cam == null:
		return
	var world: Node = Global.world_node
	var bounds: Rect2 = Rect2()
	if world != null and is_instance_valid(world) and world.has_method("camera_bounds"):
		bounds = world.call("camera_bounds") as Rect2

	if bounds.size.x <= 0.0 or bounds.size.y <= 0.0:
		# No active area (or one that can't report bounds yet): leave the camera
		# unclamped rather than pinning it to the previous map's rect.
		if _cam_set:
			cam.limit_left   = -10000000
			cam.limit_top    = -10000000
			cam.limit_right  =  10000000
			cam.limit_bottom =  10000000
			_cam_set = false
		return

	var view: Vector2 = get_viewport().get_visible_rect().size / cam.zoom
	if not force and _cam_set and _cam_bounds == bounds and _cam_view.is_equal_approx(view):
		return   # nothing changed — don't touch the camera every frame

	_cam_bounds = bounds
	_cam_view   = view
	_cam_set    = true

	var l: float = bounds.position.x
	var r: float = bounds.end.x
	var t: float = bounds.position.y
	var b: float = bounds.end.y
	if bounds.size.x < view.x:
		var cx: float = bounds.position.x + bounds.size.x * 0.5
		l = cx - view.x * 0.5
		r = cx + view.x * 0.5
	if bounds.size.y < view.y:
		var cy: float = bounds.position.y + bounds.size.y * 0.5
		t = cy - view.y * 0.5
		b = cy + view.y * 0.5
	cam.limit_left   = int(floor(l))
	cam.limit_top    = int(floor(t))
	cam.limit_right  = int(ceil(r))
	cam.limit_bottom = int(ceil(b))

# ── Build SpriteFrames ────────────────────────────────────────────
# New player sheet: 128x576 = 4 frames (cols) x 9 rows of 32x64. Rows are
# three animations — idle (rows 0-2), walk (3-5), sprint (6-8) — each with a
# front / side / back variant. The 8 movement directions map onto those three
# variants (diagonals reuse their cardinal), and west mirrors the side art.
const PLAYER_SHEET: Texture2D = preload("res://sprites/player.png")
const FRAME_W: int = 32
const FRAME_H: int = 64
const SHEET_COLS: int = 4
const ROW_IDLE:   int = 0
const ROW_WALK:   int = 3
const ROW_SPRINT: int = 6
# Draw scale + the y-sort line the feet sit on (matches YSORT_FEET_OFFSET).
const SPRITE_SCALE: float = 0.6
const FEET_LINE_Y:  float = 23.0
# No diagonal art exists, so the 8 directions choose the nearest FACING among
# front / side / back (no image rotation): pure up/down use front/back, and
# everything else (east/west + the 4 diagonals) uses the side art.
const DIR_VARIANT: Dictionary = {
	"south": 0, "north": 2, "east": 1, "west": 1,
	"south-east": 1, "south-west": 1, "north-east": 1, "north-west": 1,
}
# Directions whose art is mirrored (the side art faces east).
const DIR_FLIP_H: Array = ["west", "south-west", "north-west"]

func _build_frames() -> SpriteFrames:
	var sf := SpriteFrames.new()
	sf.remove_animation("default")
	for d in DIRS:
		var dir: String = d["name"]
		var variant: int = DIR_VARIANT.get(dir, 0)
		var key: String = dir.replace("-", "_")
		_add_sheet_anim(sf, "idle_"   + key, ROW_IDLE   + variant, 5.0)
		_add_sheet_anim(sf, "walk_"   + key, ROW_WALK   + variant, 10.0)
		_add_sheet_anim(sf, "sprint_" + key, ROW_SPRINT + variant, 14.0)
	return sf

func _add_sheet_anim(sf: SpriteFrames, anim: String, row: int, fps: float) -> void:
	sf.add_animation(anim)
	sf.set_animation_speed(anim, fps)
	sf.set_animation_loop(anim, true)
	for col in range(SHEET_COLS):
		var at := AtlasTexture.new()
		at.atlas  = PLAYER_SHEET
		at.region = Rect2(col * FRAME_W, row * FRAME_H, FRAME_W, FRAME_H)
		sf.add_frame(anim, at)

# ── Input ─────────────────────────────────────────────────────────
# Desktop focus loss and Android app pause both route through the same reset.
# Window.focus_exited covers the desktop path; these notifications cover the
# app-level focus/pause events a mobile window may not emit as focus_exited.
func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT \
			or what == NOTIFICATION_APPLICATION_PAUSED \
			or what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		_on_window_focus_exited()

func _on_window_focus_exited() -> void:
	cancel_pending_input()
	for action in ["gameplay_left", "gameplay_right", "gameplay_up", "gameplay_down"]:
		if InputMap.has_action(action):
			Input.action_release(action)

# Called by Global when any interface/menu/pause takes over the screen. Cancels
# world gestures without releasing the player's still-held keyboard keys; after
# the panel closes a held key can resume normally, while a lost touch cannot
# leave a stale tap order or attack latched.
func cancel_pending_input() -> void:
	_pnc_cancel()
	Global.mobile_move  = Vector2.ZERO
	Global.mobile_shift = false
	_attack_held = false
	_apply_movement_direction(Vector2.ZERO, false)

func get_input(delta: float = 0.0) -> void:
	# Keyboard and touch joystick feed the SAME direction: the joystick's analog
	# value is added to the keyboard vector and clamped to unit length, so speed,
	# collision, sprint and terrain rules below stay identical on both platforms.
	var keyboard_dir: Vector2 = Input.get_vector(
		"gameplay_left", "gameplay_right", "gameplay_up", "gameplay_down"
	)
	var manual: Vector2 = (keyboard_dir + Global.mobile_move).limit_length(1.0)
	# Direct control always wins: any WASD/joystick input cancels a move order.
	if manual != Vector2.ZERO:
		_pnc_cancel()
	var direction: Vector2 = manual
	var pnc_driving: bool = false
	# Tap-to-control supplies the SAME direction vector a held WASD key would:
	# it never drives velocity/physics directly. _pnc_steer only chooses where to
	# point the shared movement handler below.
	if direction == Vector2.ZERO and Global.point_and_click:
		input_direction = Vector2.ZERO
		_pnc_steer(delta)
		direction = input_direction
		pnc_driving = direction != Vector2.ZERO
	# Optional point-and-click auto-sprint. It only applies while the order is
	# actually driving movement; direct keyboard/joystick input still needs Shift,
	# and _apply_movement_direction enforces stamina/exhaustion for both paths.
	var sprint_held: bool = Global.is_shift_held() \
		or (pnc_driving and Global.point_and_click_auto_sprint)
	_apply_movement_direction(direction, sprint_held)

## The single movement engine for every control scheme. WASD/joystick and
## tap-to-control all arrive here with a direction vector, so speed, diagonal
## normalization, sprinting, stamina gating, snowstorm slowdown and physics
## remain identical no matter how the direction was produced.
func _apply_movement_direction(direction: Vector2, sprint_held: bool) -> void:
	input_direction = direction
	var want_sprint: bool = sprint_held and input_direction != Vector2.ZERO
	_sprinting = want_sprint and not _stamina_exhausted
	var storm_mult: float = SNOWSTORM_SPEED_MULT if Global.snowstorm_active else 1.0
	velocity = input_direction * movement_speed \
		* (SPRINT_MULTIPLIER if _sprinting else 1.0) * storm_mult

# ── Optional point-and-click movement (Global.point_and_click) ──────
# OFF by default. When ON, a world click/tap issues one move order:
#   • empty ground            → pathfind there; stop when arrived or
#   • interactive target      → walk into one-block range, then open/interact directly
#                               (no synthetic swing replay);
#   • hostile/any mob         → chase it and auto-attack until it dies, the
#                               player clicks elsewhere, or moves manually;
#   • valid held-item target  → the item acts (rod on water, hoe on grass, …),
#                               otherwise the click is a move;
#   • build mode / UI / right-click → never intercepted.
const PNC_ARRIVE_EPS: float         = 8.0
const PNC_ACTION_STOP: float        = 30.0
const PNC_ATTACK_STOP: float        = 40.0
const PNC_ATTACK_INTERVAL_MS: int   = 550
const PNC_STUCK_MS: int             = 1200
# Mob taps use the animated sprite's world bounds, not a large origin radius.
const PNC_MOB_FALLBACK_RADIUS: float = 18.0
const PNC_SELF_TAP_RADIUS: float    = 44.0
const PNC_CHOP_STOP: float          = 46.0
const PNC_CHOP_INTERVAL_MS: int     = 420
const PNC_CHOP_AMOUNT: float        = 0.45
const PNC_INTERACT_STOP: float      = 36.0
# Clickable objects are resolved directly; a plain block is not in this list
# and keeps its walk-then-hold-to-mine behaviour.
const PNC_INTERACT_GROUPS: Array[String] = [
	"Chest", "CraftingStation", "ColorCrafter", "TouchInteractable",
	"PlainClickBlock", "WorldWaypoint", "DungeonPortal", "CavePortal",
	"KnowledgeAltar", "QuizAltar", "LuaNPC", "TutorialNPC",
]
const PNC_PATH_CELL: float          = 32.0
const PNC_TREE_BUCKET: float        = 128.0
const PNC_PATH_RECALC_MS: int       = 800
const PNC_PATH_TARGET_EPS: float    = 24.0
const PNC_PATH_RADIUS: int          = 18
const PNC_PATH_MAX_VISITS: int      = 900
const PNC_INTERACT_HOLD_MS: int     = 12000
const PNC_INDICATOR_SCRIPT: GDScript = preload("res://scripts/pnc_indicator.gd")

var _pnc_active:           bool    = false
var _pnc_dest:             Vector2 = Vector2.ZERO
var _pnc_chase:            Node2D  = null
var _pnc_chase_id:         int     = 0  # survives as a validity token after free()
var _pnc_pending:          String  = ""   # "", "click", "interact", "swing", "chop", "fish"
var _pnc_pending_tree:     Node2D  = null
var _pnc_interact_target:  Node    = null
var _pnc_interact_point:   Vector2 = Vector2.INF
var _pnc_fish_point:       Vector2 = Vector2.ZERO
var _pnc_chop:             Node2D  = null
var _pnc_chop_at_ms:       int     = 0
var _pnc_dispatching:      bool    = false
var _pnc_attack_at_ms:     int     = 0
var _pnc_last_progress_ms: int     = 0
var _pnc_last_pos:         Vector2 = Vector2.ZERO
var _pnc_marker:           Node2D  = null
var _pnc_path:             PackedVector2Array = PackedVector2Array()
var _pnc_path_index:       int     = 0
var _pnc_path_target:      Vector2 = Vector2.ZERO
var _pnc_path_ms:          int     = 0
var _pnc_path_dynamic:     bool    = false
var _pnc_path_retries:     int     = 0
var _pnc_path_attempted:   bool    = false
# Spatial buckets keep PNC tree tap tests from scanning every tree in the
# overworld (1,300+ on a normal save). Rebuilt when the active world changes;
# chopped trees are skipped via their queued/freed state.
var _pnc_tree_bucket_map:  Dictionary = {}
var _pnc_tree_bucket_world: int = -1
# Reused line-of-sight query: PNC steering checks it every frame in open space,
# so avoid allocating a fresh PhysicsRayQueryParameters2D each tick.
var _pnc_los_query:        PhysicsRayQueryParameters2D = null
var _pnc_walk_query:       PhysicsPointQueryParameters2D = null
var _pnc_los_target:       Vector2 = Vector2.ZERO
var _pnc_los_result:       bool = true
var _pnc_los_at_ms:        int = -1000
var _pnc_hold_click:       bool    = false
var _pnc_hold_pos:         Vector2 = Vector2.ZERO
var _pnc_hold_started_ms:  int     = 0
var _pnc_hold_next_check:  int     = 0
var _pnc_hold_prev_active: bool    = false
var _pnc_hold_prev_pos:    Vector2 = Vector2.ZERO
var _pnc_hold_needs_press: bool    = false
var _pnc_hold_seq:         int     = 0

func _pnc_node_text(node) -> String:
	# Keep the parameter untyped: a target can be freed between a chase order
	# and its cleanup. Typing it as Node makes GDScript throw before the
	# is_instance_valid() guard can run.
	if node == null or not is_instance_valid(node):
		return "<none/freed>"
	return str(node)

func _pnc_cancel() -> void:
	if _pnc_active:
		CrashLogger.event("PNC", "cancel pending=%s chase=%s hold=%s" % [
			_pnc_pending, _pnc_node_text(_pnc_chase), _pnc_hold_click])
	if _pnc_chop != null and is_instance_valid(_pnc_chop) \
			and _pnc_chop.has_method("set_pnc_auto_chop"):
		_pnc_chop.call("set_pnc_auto_chop", false)
	_pnc_release_hold()
	_pnc_active       = false
	_pnc_chase        = null
	_pnc_chase_id     = 0
	_pnc_pending      = ""
	_pnc_pending_tree = null
	_pnc_interact_target = null
	_pnc_interact_point  = Vector2.INF
	_pnc_chop         = null
	_pnc_path         = PackedVector2Array()
	_pnc_path_index   = 0
	_pnc_path_dynamic = false
	_pnc_path_retries = 0
	_pnc_path_attempted = false
	# Stopping a tap order stops movement on the very next physics tick; do not
	# leave the last steering vector behind when the scheme is toggled off.
	input_direction = Vector2.ZERO
	if _pnc_marker != null:
		_pnc_marker.call("hide_marker")

func _pnc_stop_for_pending(pending: String) -> float:
	match pending:
		"click", "interact":
			return PNC_INTERACT_STOP
		"swing":
			return PNC_ACTION_STOP
		"chop":
			return PNC_CHOP_STOP
		_:
			return PNC_ARRIVE_EPS

func _pnc_begin(dest: Vector2, chase: Node2D, pending: String, mode: String) -> void:
	_pnc_release_hold()
	_pnc_dest     = dest
	_pnc_chase    = chase
	_pnc_chase_id = chase.get_instance_id() if chase != null else 0
	_pnc_pending  = pending
	_pnc_interact_target = null
	_pnc_interact_point  = Vector2.INF
	_pnc_active   = true
	_pnc_last_pos = global_position
	_pnc_last_progress_ms = Time.get_ticks_msec()
	_pnc_path_dynamic = chase != null
	_pnc_path_retries = 0
	# Do NOT build a grid path here. Most taps have a clear line of sight; the
	# old eager pathfind cost 2-65 ms per click and was the main PNC frame spike.
	# _pnc_next_waypoint builds one lazily only when the direct line is blocked.
	_pnc_path = PackedVector2Array()
	_pnc_path_index = 0
	_pnc_path_target = dest
	_pnc_path_ms = Time.get_ticks_msec()
	_pnc_path_attempted = false
	CrashLogger.event("PNC", "order mode=%s pending=%s chase=%s dest=(%.1f, %.1f) path=%d" % [
		mode, pending, _pnc_node_text(chase), dest.x, dest.y, _pnc_path.size()])
	if _pnc_marker != null:
		if chase != null:
			_pnc_marker.call("follow", chase)
		else:
			_pnc_marker.call("show_at", dest, mode)

func _pnc_marker_pulse(at: Vector2, mode: String) -> void:
	if _pnc_marker != null:
		_pnc_marker.call("pulse", at, mode)

# Returns true when the click was consumed by a move/chase order. False lets the
# normal left-click path (swing / use / hold-to-mine) handle it.
func _pnc_cell(pos: Vector2) -> Vector2i:
	return Vector2i(floori(pos.x / PNC_PATH_CELL), floori(pos.y / PNC_PATH_CELL))

func _pnc_cell_center(cell: Vector2i) -> Vector2:
	return Vector2((cell.x + 0.5) * PNC_PATH_CELL, (cell.y + 0.5) * PNC_PATH_CELL)

func _pnc_cell_walkable(cell: Vector2i, cache: Dictionary,
		space: PhysicsDirectSpaceState2D = null) -> bool:
	if cache.has(cell):
		return bool(cache[cell])
	if space == null:
		space = get_world_2d().direct_space_state
	var clear := true
	if space != null:
		if _pnc_walk_query == null:
			_pnc_walk_query = PhysicsPointQueryParameters2D.new()
			_pnc_walk_query.collide_with_bodies = true
			_pnc_walk_query.collide_with_areas = false
			_pnc_walk_query.collision_mask = 1
		_pnc_walk_query.position = _pnc_cell_center(cell)
		for hit in space.intersect_point(_pnc_walk_query, 8):
			var c = hit.get("collider")
			if c != null and c != self:
				clear = false
				break
	cache[cell] = clear
	return clear

# A* on the 32px world grid. The old breadth-first search explored a whole
# rectangle around the start/target and ran on EVERY point-and-click order,
# including open-ground taps; that caused 2-65 ms frame spikes. This version
# searches only toward the target, caches walkability, and is called lazily by
# _pnc_next_waypoint only when the direct line is obstructed.
# Eight directions are used so a diagonal tap produces diagonal movement. A
# diagonal step needs BOTH cardinal cells open, preventing corner cutting.
func _pnc_find_path(from_pos: Vector2, target: Vector2, stop: float) -> PackedVector2Array:
	var start := _pnc_cell(from_pos)
	var target_cell := _pnc_cell(target)
	var min_x: int = mini(start.x, target_cell.x) - PNC_PATH_RADIUS
	var max_x: int = maxi(start.x, target_cell.x) + PNC_PATH_RADIUS
	var min_y: int = mini(start.y, target_cell.y) - PNC_PATH_RADIUS
	var max_y: int = maxi(start.y, target_cell.y) + PNC_PATH_RADIUS
	if (max_x - min_x + 1) * (max_y - min_y + 1) > 3200:
		return PackedVector2Array()
	var space := get_world_2d().direct_space_state
	if space == null:
		return PackedVector2Array()
	var cache: Dictionary = {start: true}
	var goal_radius: float = maxf(stop, 40.0)
	var open: Array = [start]
	var g: Dictionary = {start: 0.0}
	var f: Dictionary = {start: _pnc_path_heuristic(start, target_cell)}
	var came: Dictionary = {}
	var closed: Dictionary = {}
	var found := Vector2i(999999, 999999)
	var steps: Array = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
		Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1)]
	while not open.is_empty() and closed.size() < PNC_PATH_MAX_VISITS:
		var best_i := 0
		var best_f := float(f.get(open[0], INF))
		for i in range(1, open.size()):
			var candidate_f := float(f.get(open[i], INF))
			if candidate_f < best_f:
				best_f = candidate_f
				best_i = i
		var cur: Vector2i = open[best_i]
		open.remove_at(best_i)
		if closed.has(cur):
			continue
		closed[cur] = true
		if _pnc_cell_center(cur).distance_to(target) <= goal_radius:
			found = cur
			break
		for step in steps:
			var nxt: Vector2i = cur + step
			if nxt.x < min_x or nxt.x > max_x or nxt.y < min_y or nxt.y > max_y:
				continue
			if closed.has(nxt):
				continue
			if not _pnc_cell_walkable(nxt, cache, space):
				continue
			if step.x != 0 and step.y != 0:
				if not _pnc_cell_walkable(cur + Vector2i(step.x, 0), cache, space) \
						or not _pnc_cell_walkable(cur + Vector2i(0, step.y), cache, space):
					continue
			var step_cost: float = 1.41421356 if step.x != 0 and step.y != 0 else 1.0
			var tentative: float = float(g[cur]) + step_cost
			if tentative >= float(g.get(nxt, INF)):
				continue
			came[nxt] = cur
			g[nxt] = tentative
			f[nxt] = tentative + _pnc_path_heuristic(nxt, target_cell)
			if not open.has(nxt):
				open.append(nxt)
	if found.x == 999999:
		return PackedVector2Array()
	var cells: Array = []
	var c := found
	while c != start:
		cells.push_front(c)
		if not came.has(c):
			return PackedVector2Array()
		c = came[c]
	var path := PackedVector2Array()
	for cell in cells:
		path.append(_pnc_cell_center(cell))
	return path

func _pnc_path_heuristic(cell: Vector2i, target_cell: Vector2i) -> float:
	var dx: int = absi(cell.x - target_cell.x)
	var dy: int = absi(cell.y - target_cell.y)
	return float(maxi(dx, dy)) + (sqrt(2.0) - 1.0) * float(mini(dx, dy))

func _pnc_repath(target: Vector2, stop: float, force: bool = false) -> void:
	var now := Time.get_ticks_msec()
	if not force and not _pnc_path.is_empty() \
			and now - _pnc_path_ms < PNC_PATH_RECALC_MS \
			and target.distance_to(_pnc_path_target) < PNC_PATH_TARGET_EPS:
		return
	_pnc_path_target = target
	_pnc_path_ms = now
	_pnc_path_attempted = true
	_pnc_path = _pnc_find_path(global_position, target, stop)
	_pnc_path_index = 0

func _pnc_next_waypoint(target: Vector2, stop: float) -> Vector2:
	if global_position.distance_to(target) <= stop:
		return target
	# Open ground: move exactly toward the tapped point. The grid path's first
	# waypoint is a cell centre, so following it would convert a straight tap
	# into a slight diagonal and no longer match the equivalent WASD direction.
	# Pathfinding is lazy: open taps never pay for a grid search.
	if _pnc_has_line_of_sight(target):
		return target
	var stale_path := _pnc_path_dynamic \
		and Time.get_ticks_msec() - _pnc_path_ms > PNC_PATH_RECALC_MS
	var target_changed: bool = _pnc_path_target.distance_to(target) > PNC_PATH_TARGET_EPS
	if _pnc_path.is_empty():
		if not _pnc_path_attempted or target_changed or stale_path:
			_pnc_repath(target, stop)
	elif target_changed or stale_path:
		_pnc_repath(target, stop)
	while _pnc_path_index < _pnc_path.size() \
			and global_position.distance_to(_pnc_path[_pnc_path_index]) < 8.0:
		_pnc_path_index += 1
	if _pnc_path_index < _pnc_path.size():
		return _pnc_path[_pnc_path_index]
	return target

func _pnc_release_hold() -> void:
	if not _pnc_hold_click:
		return
	_pnc_hold_click = false
	Global.pnc_hold_active = false
	_pnc_hold_seq += 1
	call_deferred("_pnc_emit_release_if_current", _pnc_hold_seq, _pnc_hold_pos)
	Global.restore_mouse_override(_pnc_hold_prev_active, _pnc_hold_prev_pos)

func _pnc_hold_emit(pressed: bool, at: Vector2 = Vector2.INF) -> void:
	var pos: Vector2 = _pnc_hold_pos if at == Vector2.INF else at
	# This can run from a deferred release while the player is being removed for
	# a world transition (for example entering the guided dungeon). In that gap
	# get_viewport() is null; just drop the stale synthetic event instead of
	# crashing the scene swap.
	var vp := get_viewport()
	if vp == null or not is_inside_tree():
		_pnc_hold_click = false
		Global.pnc_hold_active = false
		return
	var screen: Vector2 = vp.get_canvas_transform() * pos
	_pnc_dispatching = true
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = pressed
	ev.position = screen
	ev.global_position = screen
	ev.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
	ev.set_meta("pnc_synthetic", true)
	# push_input(..., true) means "this position is already in viewport
	# coordinates". Input.parse_input_event() treats positions as WINDOW
	# coordinates instead; on Android (canvas_items stretch) that scaled the
	# synthetic press away from the block, so PNC walked to it but never mined.
	vp.push_input(ev, true)
	_pnc_dispatching = false

func _pnc_emit_release_if_current(seq: int, at: Vector2) -> void:
	if seq != _pnc_hold_seq or _pnc_hold_click:
		return
	_pnc_hold_emit(false, at)

func _pnc_begin_hold(world_pos: Vector2) -> void:
	if _pnc_hold_click:
		return
	_pnc_active = true
	_pnc_dest = world_pos
	_pnc_chase = null
	_pnc_chase_id = 0
	_pnc_pending = ""
	_pnc_pending_tree = null
	_pnc_interact_target = null
	_pnc_interact_point  = Vector2.INF
	_pnc_chop = null
	_pnc_path = PackedVector2Array()
	_pnc_path_index = 0
	_pnc_path_target = world_pos
	_pnc_path_ms = Time.get_ticks_msec()
	_pnc_path_attempted = false
	_pnc_hold_click = true
	Global.pnc_hold_active = true
	_pnc_hold_pos = world_pos
	_pnc_hold_started_ms = Time.get_ticks_msec()
	_pnc_hold_next_check = _pnc_hold_started_ms
	_pnc_hold_prev_active = Global.mouse_override_active()
	_pnc_hold_prev_pos = Global.mouse_override_pos()
	_pnc_hold_seq += 1
	_pnc_hold_needs_press = true
	Global.set_touch_mouse(world_pos)
	CrashLogger.event("PNC", "hold target at=(%.1f, %.1f)" % [world_pos.x, world_pos.y])
	if _pnc_marker != null:
		_pnc_marker.call("show_at", world_pos, "act")

func _pnc_handle_click(world_pos: Vector2) -> bool:
	# A new tap always replaces the previous order cleanly (releasing any held
	# mining click before starting another target).
	_pnc_cancel()
	var mob := _pnc_mob_near(world_pos)
	if mob != null:
		# Wolves are deliberately not click-to-attack targets. Treat a tap on
		# one as an ordinary move so PNC cannot auto-chase or auto-swing at it;
		# manual swings/combat remain unchanged.
		# Sheep share the Wolf/Mob groups for AI dispatch; they are still valid
		# PNC targets. Only true wolves (not in the Sheep group) are excluded.
		if mob.is_in_group("Wolf") and not mob.is_in_group("Sheep"):
			_pnc_begin(world_pos, null, "", "move")
		else:
			_pnc_begin(mob.global_position, mob, "", "attack")
		return true
	# Fishing: tapping water with a rod shows the rod icon and casts; if the
	# spot is beyond the rod's range, walk to the shore first, then cast.
	if _pnc_try_fishing_tap(world_pos):
		return true
	# Trees: walk into chopping reach, then keep chopping until the tree falls.
	var tree := _pnc_tree_at(world_pos)
	if tree != null:
		if global_position.distance_to(tree.global_position) <= PNC_CHOP_STOP:
			_pnc_begin_chop(tree)
		else:
			_pnc_pending_tree = tree
			_pnc_begin(tree.global_position, null, "chop", "act")
		return true
	# Self-food taps keep priority over nearby interactables (for example a
	# non-solid bonfire under the player). Clicking a distant chest with food
	# still resolves to the chest below.
	if _pnc_held_food_self_tap(world_pos) and _pnc_try_item_use(world_pos):
		_pnc_marker_pulse(world_pos, "act")
		_pnc_cancel()
		return true
	# Real interactables (chests, stations, furnaces, doors, altars, portals,
	# guides, waypoints) walk to ONE BLOCK of the object's own origin and then
	# invoke its interaction directly. Replaying a left-click here used to make
	# the player swing forever after arrival, and tapping a tall sprite could
	# stop outside the object's actual interact radius.
	var interact_target := _pnc_interact_target_at(world_pos)
	if interact_target != null:
		_pnc_start_interact(interact_target, world_pos)
		return true
	# Held-item actions that target a tile (rod/hoe/bucket/water) act when valid;
	# food is eaten only when tapping yourself, so it can't block walking.
	if _pnc_try_item_use(world_pos):
		_pnc_marker_pulse(world_pos, "act")
		_pnc_cancel()
		return true
	# Solid non-interactable objects (ordinary placed blocks / torches) keep
	# the old walk-then-hold behaviour so mining and demolition still work.
	if _pnc_point_has_target(world_pos):
		if global_position.distance_to(world_pos) <= PNC_INTERACT_STOP:
			_pnc_begin_hold(world_pos)
			return true
		_pnc_begin(world_pos, null, "interact", "act")
		return true
	# Grass has no collider (walkable), so detect the tuft under the tap and
	# walk into sword range before swinging — the existing sword-only grass cut.
	if _pnc_grass_at(world_pos):
		if global_position.distance_to(world_pos) <= PNC_ACTION_STOP:
			_pnc_swing_at(world_pos)
			_pnc_marker_pulse(world_pos, "act")
			_pnc_cancel()
			return true
		_pnc_begin(world_pos, null, "swing", "act")
		return true
	_pnc_begin(world_pos, null, "", "move")
	return true

func _pnc_steer(_delta: float) -> void:
	# Whatever happens below, this frame starts from "no PNC movement"; active
	# branches either set a direction or deliberately leave it at zero.
	input_direction = Vector2.ZERO
	if not _pnc_active:
		return
	if not Global.point_and_click or Global.any_ui_open() or Global.pause_menu_open \
			or Global.block_mode or Global.player_is_dead:
		_pnc_cancel()
		return
	if _pnc_hold_click:
		if _pnc_hold_needs_press:
			_pnc_hold_needs_press = false
			_pnc_hold_emit(true)
		var now := Time.get_ticks_msec()
		if now - _pnc_hold_started_ms > PNC_INTERACT_HOLD_MS:
			Global.notify("That interaction couldn't be completed.")
			_pnc_cancel()
			return
		if now >= _pnc_hold_next_check:
			_pnc_hold_next_check = now + 250
			# A destroyed block/tile no longer has colliders at this point.
			if not _pnc_point_has_target(_pnc_hold_pos):
				_pnc_cancel()
				return
		Global.set_touch_mouse(_pnc_hold_pos)
		input_direction = Vector2.ZERO
		_pnc_face(_pnc_hold_pos)
		return
	if _pnc_chase_id != 0:
		# A dying mob can be freed while it is still the stored chase target.
		# The id token distinguishes "no chase" from "freed chase" because a
		# freed Object compares equal to null in GDScript.
		if not is_instance_valid(_pnc_chase) or _pnc_chase.is_queued_for_deletion() \
				or not _pnc_mob_alive(_pnc_chase):
			_pnc_cancel()
			return
		_pnc_dest = _pnc_chase.global_position
		if global_position.distance_to(_pnc_dest) <= PNC_ATTACK_STOP:
			input_direction = Vector2.ZERO
			_pnc_face(_pnc_dest)
			if _pnc_has_line_of_sight(_pnc_dest):
				_pnc_maybe_attack(_pnc_dest)
			# Standing still to attack is the intended state; do not let the
			# movement-progress watchdog cancel the combat order.
			return
	elif _pnc_chop != null:
		if not is_instance_valid(_pnc_chop) or _pnc_chop.is_queued_for_deletion():
			_pnc_cancel()
			return
		_pnc_dest = _pnc_chop.global_position
		if global_position.distance_to(_pnc_dest) <= PNC_CHOP_STOP:
			input_direction = Vector2.ZERO
			_pnc_face(_pnc_dest)
			_pnc_tick_chop()
			# Chopping is deliberately stationary; the movement watchdog must
			# not cancel a valid tree order after PNC_STUCK_MS.
			return
	elif _pnc_pending == "chop" and _pnc_pending_tree != null:
		if not is_instance_valid(_pnc_pending_tree):
			_pnc_cancel()
			return
		_pnc_dest = _pnc_pending_tree.global_position
		if global_position.distance_to(_pnc_dest) <= PNC_CHOP_STOP:
			_pnc_arrive()
			return
	elif _pnc_pending == "interact":
		if _pnc_interact_target != null:
			if not is_instance_valid(_pnc_interact_target) \
					or (_pnc_interact_target is Node2D and not (_pnc_interact_target as Node2D).is_visible_in_tree()):
				_pnc_cancel()
				return
		elif not _pnc_point_has_target(_pnc_dest):
			_pnc_cancel()
			return
		if global_position.distance_to(_pnc_dest) <= PNC_INTERACT_STOP:
			_pnc_arrive()
			return
	else:
		var arrive_stop := _pnc_stop_for_pending(_pnc_pending)
		if global_position.distance_to(_pnc_dest) <= arrive_stop:
			_pnc_arrive()
			return
	var to: Vector2 = _pnc_next_waypoint(_pnc_dest,
		PNC_ATTACK_STOP if _pnc_chase != null else _pnc_stop_for_pending(_pnc_pending)) - global_position
	if to.length_squared() < 0.0001:
		_pnc_arrive()
		return
	input_direction = to.normalized()
	_pnc_face(_pnc_dest)
	_pnc_check_stuck()

func _pnc_arrive() -> void:
	input_direction  = Vector2.ZERO
	var pending: String = _pnc_pending
	var at: Vector2  = _pnc_dest
	CrashLogger.event("PNC", "arrive pending=%s at=(%.1f, %.1f)" % [
		pending if pending != "" else "move", at.x, at.y])
	_pnc_active  = false
	_pnc_pending = ""
	_pnc_chase   = null
	_pnc_chase_id = 0
	if _pnc_marker != null:
		_pnc_marker.call("hide_marker")
	if pending == "interact":
		var interact_target: Node = _pnc_interact_target
		var interact_point: Vector2 = _pnc_interact_point
		_pnc_interact_target = null
		_pnc_interact_point = Vector2.INF
		if interact_point != Vector2.INF:
			# Direct object order. If it vanished mid-walk, do nothing rather
			# than mining whatever happens to be at its old anchor.
			if interact_target != null and is_instance_valid(interact_target):
				_pnc_interact_with(interact_target, interact_point)
		else:
			# Unknown solid point: retain the old block-mining replay.
			_pnc_begin_hold(at)
	elif pending == "click":
		_pnc_dispatch_click(at)
	elif pending == "swing":
		_pnc_swing_at(at)
	elif pending == "chop":
		var tree: Node2D = _pnc_pending_tree
		_pnc_pending_tree = null
		if tree != null and is_instance_valid(tree):
			_pnc_begin_chop(tree)
	elif pending == "fish":
		if _fishing != null and is_instance_valid(_fishing) \
				and bool(_fishing.call("is_in_cast_range", _pnc_fish_point)):
			_pnc_cast_fish(_pnc_fish_point)
		else:
			Global.notify("[color=#ffaa66]Couldn't get close enough to cast.[/color]")

# Face the tap point, aim the shared cursor there, and swing. This is what lets
# a tap cut grass: world._on_swing_performed() picks the grass row from
# Global.mouse_world(), so the cursor must be the tapped tuft while the sword
# swing (the only thing that cuts grass) is triggered. The sword requirement is
# unchanged.
func _pnc_swing_at(world_pos: Vector2) -> void:
	var prev_active: bool    = Global.mouse_override_active()
	var prev_pos:    Vector2 = Global.mouse_override_pos()
	Global.set_touch_mouse(world_pos)
	_pnc_face(world_pos)
	swing_held_item()
	# Whole-tile cut: the sword's directional patch can miss a tuft that isn't on
	# the 8-way aim axis, so also cut the tuft whose tile was actually tapped.
	var held: Variant = Global.get_hotbar_item()
	var is_sword: bool = held is Dictionary \
		and ((held as Dictionary).get("data") as ItemData) != null \
		and ((held as Dictionary)["data"] as ItemData).is_sword
	if is_sword:
		var world := _get_world_node()
		if world != null and world.has_method("cut_grass_at_world"):
			world.call("cut_grass_at_world", world_pos)
	Global.restore_mouse_override(prev_active, prev_pos)

# Grass tufts are walkable (no collider), so resolve the tuft whose tile covers
# the tap via the world's grass registry. The whole tile counts, not just the
# tuft's origin pixel.
func _pnc_grass_at(world_pos: Vector2) -> bool:
	var world := _get_world_node()
	if world == null:
		return false
	if world.has_method("grass_tuft_at_world"):
		return world.call("grass_tuft_at_world", world_pos) != null
	if not world.has_method("grass_tufts_in_world_rect"):
		return false
	var rect := Rect2(world_pos - Vector2(10.0, 10.0), Vector2(20.0, 20.0))
	return not ((world.call("grass_tufts_in_world_rect", rect) as Array).is_empty())

# Rebuild the bucket index of live trees for the active world.
func _pnc_tree_buckets() -> Dictionary:
	var world := _get_world_node()
	var world_id: int = world.get_instance_id() \
		if world != null and is_instance_valid(world) else 0
	# Trees are only spawned during world generation. Once the cache is built
	# for the active world it stays valid; removals and freed nodes are skipped.
	if world_id == _pnc_tree_bucket_world and not _pnc_tree_bucket_map.is_empty():
		return _pnc_tree_bucket_map
	var buckets: Dictionary = {}
	for node in get_tree().get_nodes_in_group("Tree"):
		if not is_instance_valid(node):
			continue
		var tree := node as Node2D
		if tree == null or not tree.is_inside_tree():
			continue
		var key := Vector2i(
			floori(tree.global_position.x / PNC_TREE_BUCKET),
			floori(tree.global_position.y / PNC_TREE_BUCKET))
		if buckets.has(key):
			(buckets[key] as Array).append(tree)
		else:
			buckets[key] = [tree]
	_pnc_tree_bucket_map = buckets
	_pnc_tree_bucket_world = world_id
	return _pnc_tree_bucket_map

# The tree under the tap, if any (trees expose chop()). The physics collider
# only covers the trunk; point-and-click should also accept the canopy/visible
# sprite so tapping the tree does not silently become a move order.
func _pnc_tree_at(world_pos: Vector2) -> Node2D:
	var best: Node2D = null
	var best_d: float = INF
	var buckets := _pnc_tree_buckets()
	var click_bucket := Vector2i(
		floori(world_pos.x / PNC_TREE_BUCKET),
		floori(world_pos.y / PNC_TREE_BUCKET))
	# A tree origin within 128 px may live in any adjacent bucket. Only test
	# that 3x3 neighborhood instead of walking all 1,300+ trees (~2-5 ms/tap).
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			var bucket: Variant = buckets.get(click_bucket + Vector2i(dx, dy))
			if not (bucket is Array):
				continue
			for node in bucket:
				if not is_instance_valid(node):
					continue
				var tree := node as Node2D
				if tree == null or tree.is_queued_for_deletion() or not tree.is_inside_tree():
					continue
				var d := tree.global_position.distance_squared_to(world_pos)
				if d > 128.0 * 128.0:
					continue
				var sprite := tree.get_node_or_null("Sprite2D") as Sprite2D
				if sprite != null and sprite.texture != null:
					var local := sprite.to_local(world_pos)
					if sprite.get_rect().grow(2.0).has_point(local):
						if d < best_d:
							best = tree
							best_d = d
						continue
				# Fallback for unusual tree scenes whose collider is the only target.
				if tree.has_method("chop") and d <= 24.0 * 24.0:
					if d < best_d:
						best = tree
						best_d = d
	if best != null:
		return best
	var space := get_world_2d().direct_space_state
	if space == null:
		return null
	var q := PhysicsPointQueryParameters2D.new()
	q.position            = world_pos
	q.collide_with_bodies = true
	q.collide_with_areas  = false
	q.collision_mask      = 0xFFFFFFFF
	for hit in space.intersect_point(q, 8):
		var c = hit.get("collider")
		if c is Node2D and (c as Node2D).has_method("chop"):
			return c as Node2D
	return null

func _pnc_begin_chop(tree: Node2D) -> void:
	# Keep the order ACTIVE so _pnc_steer keeps ticking the chop every frame.
	_pnc_active       = true
	_pnc_dest         = tree.global_position
	_pnc_pending      = ""
	_pnc_chase        = null
	_pnc_chase_id     = 0
	_pnc_pending_tree = null
	_pnc_chop         = tree
	if tree.has_method("set_pnc_auto_chop"):
		tree.call("set_pnc_auto_chop", true)
	_pnc_chop_at_ms   = 0
	_pnc_path         = PackedVector2Array()
	_pnc_path_index   = 0
	_pnc_path_target  = _pnc_dest
	_pnc_path_ms      = Time.get_ticks_msec()
	_pnc_path_attempted = false
	_pnc_path_dynamic = false
	_pnc_path_retries = 0
	_pnc_last_pos     = global_position
	_pnc_last_progress_ms = Time.get_ticks_msec()
	CrashLogger.event("PNC", "chop target=%s at=(%.1f, %.1f)" % [
		tree.name, tree.global_position.x, tree.global_position.y])
	if _pnc_marker != null:
		_pnc_marker.call("follow_mode", tree, "act")

# Chop the same way the player's click does: advance the tree's own timer in
# CLICK_BREAK-sized steps and play the swing. The tree frees itself when it
# falls, which ends the order.
func _pnc_tick_chop() -> void:
	if _pnc_chop == null or not is_instance_valid(_pnc_chop):
		_pnc_cancel()
		return
	var now: int = Time.get_ticks_msec()
	if now - _pnc_chop_at_ms < PNC_CHOP_INTERVAL_MS:
		return
	_pnc_chop_at_ms = now
	var tree: Node2D = _pnc_chop
	var prev_active: bool    = Global.mouse_override_active()
	var prev_pos:    Vector2 = Global.mouse_override_pos()
	Global.set_touch_mouse(tree.global_position)
	swing_held_item()
	tree.call("chop", PNC_CHOP_AMOUNT)
	Global.restore_mouse_override(prev_active, prev_pos)
	# A felled tree queue_frees itself inside chop(); is_instance_valid() stays
	# true until the end of the frame, so also treat a queued deletion as done.
	if not is_instance_valid(tree) or tree.is_queued_for_deletion():
		_pnc_cancel()

# ── Fishing tap: rod icon + walk into cast range ──────────────────
# True when the tap was a fishing action (water + rod), so the caller doesn't
# treat it as a move. The existing cast rules (water tile, cast_max_blocks,
# active-cast guard) stay in FishingController.
func _pnc_try_fishing_tap(world_pos: Vector2) -> bool:
	if _fishing == null or not is_instance_valid(_fishing):
		return false
	var held: Variant = Global.get_hotbar_item()
	if held == null:
		return false
	var data: ItemData = (held as Dictionary).get("data") as ItemData
	if data == null or not data.is_fishing_rod:
		return false
	var prev_active: bool    = Global.mouse_override_active()
	var prev_pos:    Vector2 = Global.mouse_override_pos()
	Global.set_touch_mouse(world_pos)
	var on_water: bool = _cursor_on_water()
	Global.restore_mouse_override(prev_active, prev_pos)
	if not on_water:
		return false
	if bool(_fishing.call("is_active")):
		_pnc_cancel()
		_pnc_marker_pulse(world_pos, "fish")
		return true   # already fishing: swallow the tap, never restart the timer
	if bool(_fishing.call("is_in_cast_range", world_pos)):
		_pnc_cast_fish(world_pos)
		return true
	# Out of range: walk toward the water, then cast on arrival.
	_pnc_fish_point = world_pos
	_pnc_begin(world_pos, null, "fish", "fish")
	return true

func _pnc_cast_fish(point: Vector2) -> void:
	_pnc_cancel()
	var prev_active: bool    = Global.mouse_override_active()
	var prev_pos:    Vector2 = Global.mouse_override_pos()
	Global.set_touch_mouse(point)
	_fishing.call("start", point)
	Global.restore_mouse_override(prev_active, prev_pos)
	_pnc_marker_pulse(point, "fish")

# Re-send the click at the destination through the REAL input pipeline, so
# blocks/stations/chests/trees apply their own range, tool and validation rules.
func _pnc_dispatch_click(world_pos: Vector2) -> void:
	if not is_inside_tree():
		return
	var screen: Vector2 = get_viewport().get_canvas_transform() * world_pos
	var prev_active: bool   = Global.mouse_override_active()
	var prev_pos:    Vector2 = Global.mouse_override_pos()
	Global.set_touch_mouse(world_pos)
	_pnc_dispatching = true
	for pressed in [true, false]:
		var ev := InputEventMouseButton.new()
		ev.button_index    = MOUSE_BUTTON_LEFT
		ev.pressed         = pressed
		ev.position        = screen
		ev.global_position = screen
		ev.button_mask     = MOUSE_BUTTON_MASK_LEFT if pressed else 0
		ev.set_meta("pnc_synthetic", true)
		# Viewport-local coordinates, matching _pnc_hold_emit (see the stretch
		# explanation there). Input.parse_input_event treats these as window
		# coordinates and misplaces every synthetic click on Android.
		get_viewport().push_input(ev, true)
	_pnc_dispatching = false
	Global.restore_mouse_override(prev_active, prev_pos)

func _pnc_face(world_pos: Vector2) -> void:
	var d: Vector2 = world_pos - global_position
	if d.length_squared() > 0.0001:
		_last_dir = _get_closest_dir(d.normalized())

func _pnc_has_line_of_sight(target: Vector2) -> bool:
	var now: int = Time.get_ticks_msec()
	# Direct steering asks every physics tick. A 50 ms cache is well below
	# player/target movement that could make a wall appear, and avoids paying
	# for a physics ray query at 120 Hz during every tap-to-move order.
	if now - _pnc_los_at_ms <= 50 \
			and _pnc_los_target.distance_squared_to(target) <= 64.0:
		return _pnc_los_result
	var space := get_world_2d().direct_space_state
	if space == null:
		return true
	if _pnc_los_query == null:
		_pnc_los_query = PhysicsRayQueryParameters2D.new()
		_pnc_los_query.collision_mask = 1
		_pnc_los_query.exclude = [get_rid()]
	_pnc_los_query.from = global_position
	_pnc_los_query.to = target
	_pnc_los_target = target
	_pnc_los_at_ms = now
	_pnc_los_result = space.intersect_ray(_pnc_los_query).is_empty()
	return _pnc_los_result

func _pnc_maybe_attack(target: Vector2) -> void:
	var now: int = Time.get_ticks_msec()
	if now - _pnc_attack_at_ms < PNC_ATTACK_INTERVAL_MS:
		return
	if _active_swing != null and is_instance_valid(_active_swing):
		return
	_pnc_attack_at_ms = now
	var prev_active := Global.mouse_override_active()
	var prev_pos := Global.mouse_override_pos()
	Global.set_touch_mouse(target)
	swing_held_item()
	Global.restore_mouse_override(prev_active, prev_pos)

func _pnc_check_stuck() -> void:
	var now: int = Time.get_ticks_msec()
	if global_position.distance_to(_pnc_last_pos) >= 2.0:
		_pnc_last_pos = global_position
		_pnc_last_progress_ms = now
	elif now - _pnc_last_progress_ms > PNC_STUCK_MS:
		# Try one fresh route before giving up on a blocked/oscillating path.
		if _pnc_path_retries < 1:
			_pnc_path_retries += 1
			var retry_stop := PNC_ATTACK_STOP if _pnc_chase != null \
				else (PNC_CHOP_STOP if _pnc_chop != null or _pnc_pending == "chop" \
					else _pnc_stop_for_pending(_pnc_pending))
			_pnc_repath(_pnc_dest, retry_stop, true)
			_pnc_last_pos = global_position
			_pnc_last_progress_ms = now
			return
		if _pnc_chase != null or _pnc_chop != null or _pnc_pending == "interact":
			CrashLogger.event("PNC", "stuck/unreachable target at=(%.1f, %.1f)" % [
				_pnc_dest.x, _pnc_dest.y])
			Global.notify("Can't reach that target.")
		_pnc_cancel()

func _pnc_mob_alive(m) -> bool:
	# Untyped for the same reason as _pnc_node_text: a freed target is a normal
	# race after an attack, not an error.
	if m == null or not is_instance_valid(m):
		return false
	for prop in ["health", "hp", "_mob_health"]:
		var v: Variant = m.get(prop)
		if v != null and float(v) <= 0.0:
			return false
	return true

func _pnc_mob_near(world_pos: Vector2) -> Node2D:
	var best: Node2D = null
	var best_d: float = INF
	var seen: Dictionary = {}
	# Sheep are their own group rather than "Mob", but they are legitimate
	# point-and-click targets. Include both groups and de-duplicate.
	for group_name in ["Mob", "Sheep"]:
		for n in get_tree().get_nodes_in_group(group_name):
			if seen.has(n) or not is_instance_valid(n) or not (n is Node2D):
				continue
			seen[n] = true
			var m := n as Node2D
			if not _pnc_mob_alive(m):
				continue
			if not _pnc_mob_click_rect(m).has_point(world_pos):
				continue
			var d: float = m.global_position.distance_squared_to(world_pos)
			if d <= best_d:
				best_d = d
				best = m
	return best

## Precise mob click bounds. The old 30px origin radius made taps on nearby
## walkable ground attack the mob instead. Prefer the animated sprite's actual
## world rectangle (so head/feet clicks still work) and use a small fallback
## only for unusual mob nodes without a sprite.
func _pnc_mob_click_rect(m: Node2D) -> Rect2:
	var sprite := m.get_node_or_null("AnimatedSprite2D") as AnimatedSprite2D
	if sprite != null and sprite.sprite_frames != null:
		var tex: Texture2D = sprite.sprite_frames.get_frame_texture(
			sprite.animation, sprite.frame)
		if tex != null:
			var sprite_scale := Vector2(absf(sprite.scale.x), absf(sprite.scale.y))
			var size := tex.get_size() * sprite_scale
			var center := m.global_position + sprite.position + sprite.offset
			return Rect2(center - size * 0.5, size).grow(5.0)
	return Rect2(
		m.global_position - Vector2(PNC_MOB_FALLBACK_RADIUS, PNC_MOB_FALLBACK_RADIUS),
		Vector2(PNC_MOB_FALLBACK_RADIUS, PNC_MOB_FALLBACK_RADIUS) * 2.0)

# True when something solid/interactive sits under the point (block, tree,
# station, chest, furnace, portal…). Empty walkable ground returns false.
func _pnc_point_has_target(world_pos: Vector2) -> bool:
	var space := get_world_2d().direct_space_state
	if space == null:
		return false
	var q := PhysicsPointQueryParameters2D.new()
	q.position           = world_pos
	q.collide_with_bodies = true
	q.collide_with_areas  = true
	q.collision_mask      = 0xFFFFFFFF
	for hit in space.intersect_point(q, 8):
		var c = hit.get("collider")
		if c == null or c == self:
			continue
		if c is Node and (c as Node).is_in_group("Player"):
			continue
		if c is Area2D:
			# Lua/Automatica stations expose a click Area2D rather than a
			# solid body; other ambient areas are not interaction targets.
			var owner_node := (c as Node).get_parent()
			if owner_node != null and owner_node.is_in_group("LuaNPC"):
				return true
			continue
		return true
	# Sprite edges can overhang a placed block's 32px collider by a few pixels
	# (and diagonal taps can land just outside the point query). Fall back to
	# the overworld's own placed-block registry for the tapped cell so a visible
	# block still becomes a mining order.
	var world := _get_world_node()
	if world != null and world.has_method("placed_node"):
		var cell := Vector2i(floori(world_pos.x / PNC_PATH_CELL), floori(world_pos.y / PNC_PATH_CELL))
		var placed: Variant = world.call("placed_node", cell)
		if placed is Node and is_instance_valid(placed):
			var data: Variant = (placed as Node).get("item_data")
			if data is ItemData and not (data as ItemData).is_floor:
				return true
	return false

# Find an actual clickable object under the tap. Unlike _pnc_point_has_target()
# this returns the owning node, so PNC can walk to its origin and invoke the
# correct interaction instead of replaying a left-click that swings the item.
func _pnc_held_food_self_tap(world_pos: Vector2) -> bool:
	var held: Variant = Global.get_hotbar_item()
	if held == null:
		return false
	var data: ItemData = (held as Dictionary).get("data") as ItemData
	return data != null and data.heal_amount > 0.0 \
			and global_position.distance_to(world_pos) <= PNC_SELF_TAP_RADIUS

func _pnc_interact_target_at(world_pos: Vector2) -> Node2D:
	var tree := get_tree()
	if tree == null:
		return null
	for group_name in PNC_INTERACT_GROUPS:
		for value in tree.get_nodes_in_group(group_name):
			if _pnc_interact_contains(value, world_pos):
				return value as Node2D
	return null

func _pnc_interact_contains(value: Variant, world_pos: Vector2) -> bool:
	if value == null or not is_instance_valid(value) or not (value is Node2D):
		return false
	var node := value as Node2D
	if not node.is_visible_in_tree():
		return false
	# Chests, stations and ObjectItem machines provide their own sprite test.
	if node.has_method("_cursor_over"):
		return bool(node.call("_cursor_over", world_pos))
	if node.is_in_group("WorldWaypoint"):
		return _pnc_local_rect_contains(node, _pnc_script_rect(node, "CLICK_RECT"), world_pos)
	if node.is_in_group("DungeonPortal"):
		return _pnc_local_rect_contains(node, _pnc_script_rect(node, "DOOR_HITBOX"), world_pos)
	if node.is_in_group("CavePortal"):
		var cave_rect: Variant = node.get("interact_rect")
		if cave_rect is Rect2:
			var cr := cave_rect as Rect2
			return cr.size != Vector2.ZERO and cr.has_point(world_pos)
		return false
	if node.is_in_group("KnowledgeAltar") or node.is_in_group("QuizAltar"):
		return node.global_position.distance_to(world_pos) <= 32.0
	if node.is_in_group("LuaNPC"):
		var robot: Variant = node.get("_robot")
		var centre: Vector2 = (robot as Node2D).global_position \
				if robot is Node2D else node.global_position
		# The station's ClickArea is centred on the node, while the robot can
		# stand a tile below it; accept either valid click surface.
		return node.global_position.distance_to(world_pos) <= 32.0 \
				or centre.distance_to(world_pos) <= 48.0
	if node.is_in_group("TutorialNPC"):
		# Match tutorial_npc.gd's own click rectangle (sprite + name area).
		var local := node.to_local(world_pos)
		return absf(local.x) <= 34.0 and local.y <= 18.0 and local.y >= -76.0
	# Doors, bonfires and Color Crafters expose only a sprite.
	return _pnc_sprite_contains(node, world_pos)

func _pnc_script_rect(node: Node, key: String) -> Rect2:
	var node_script: Script = node.get_script() as Script
	if node_script == null:
		return Rect2()
	var constants: Dictionary = node_script.get_script_constant_map()
	var value: Variant = constants.get(key)
	return value as Rect2 if value is Rect2 else Rect2()

func _pnc_local_rect_contains(node: Node2D, rect: Rect2, world_pos: Vector2) -> bool:
	return rect.size != Vector2.ZERO and rect.has_point(node.to_local(world_pos))

func _pnc_sprite_contains(node: Node2D, world_pos: Vector2) -> bool:
	var sprite_value: Variant = node.get("_sprite")
	if not (sprite_value is Sprite2D):
		return false
	var sprite := sprite_value as Sprite2D
	if sprite.texture == null:
		return false
	var local_rect := sprite.get_rect()
	var xf := sprite.global_transform
	var a: Vector2 = xf * local_rect.position
	var b: Vector2 = xf * (local_rect.position + local_rect.size)
	var bounds := Rect2(
		Vector2(minf(a.x, b.x), minf(a.y, b.y)),
		Vector2(absf(b.x - a.x), absf(b.y - a.y))).grow(2.0)
	return bounds.has_point(world_pos)

func _pnc_start_interact(target: Node2D, world_pos: Vector2) -> void:
	var anchor: Vector2 = _pnc_interact_anchor(target)
	_pnc_interact_target = target
	_pnc_interact_point = world_pos
	if global_position.distance_to(anchor) <= PNC_INTERACT_STOP:
		_pnc_interact_target = null
		_pnc_interact_point = Vector2.INF
		_pnc_face(anchor)
		_pnc_marker_pulse(world_pos, "act")
		_pnc_interact_with(target, world_pos)
		return
	_pnc_begin(anchor, null, "interact", "act")
	# _pnc_begin clears any previous target; restore this order's target.
	_pnc_interact_target = target
	_pnc_interact_point = world_pos

func _pnc_interact_anchor(target: Node2D) -> Vector2:
	# Large facades need a walkable approach point, not the collider centre.
	if target.is_in_group("WorldWaypoint"):
		return target.global_position + Vector2(0.0, 48.0)
	if target.is_in_group("CavePortal"):
		var door: Variant = target.get("door_rect")
		if door is Rect2:
			var door_rect := door as Rect2
			if door_rect.size != Vector2.ZERO:
				return door_rect.get_center()
	return target.global_position

func _pnc_interact_with(target: Node, at: Vector2) -> bool:
	if target == null or not is_instance_valid(target):
		return false
	if target is Node2D:
		_pnc_face((target as Node2D).global_position)
	# Machines/chests: their own autoplay API also respects proximity/UI state.
	if target.has_method("open_from_touch") and bool(target.call("open_from_touch")):
		return true
	# Plain-click blocks (doors and bonfires).
	if target.has_method("has_plain_click") \
			and bool(target.call("has_plain_click")) \
			and target.has_method("on_plain_click"):
		target.call("on_plain_click")
		return true
	if target.is_in_group("ColorCrafter") and target.has_method("_open_menu"):
		target.call("_open_menu")
		return true
	if target.is_in_group("WorldWaypoint") and target.has_method("_open_map"):
		target.call("_open_map")
		return true
	if target.has_method("_show_confirm"):
		target.call("_show_confirm")
		return true
	if target.is_in_group("KnowledgeAltar") and target.has_method("_show"):
		target.call("_show")
		return true
	if target.is_in_group("QuizAltar") and target.has_method("_start_quiz"):
		target.call("_start_quiz")
		return true
	if target.is_in_group("LuaNPC"):
		var lua_ui: Variant = target.get("_lua_ui")
		if lua_ui != null and is_instance_valid(lua_ui) and (lua_ui as Node).has_method("open_editor"):
			lua_ui.call("open_editor")
			return true
	if target.is_in_group("TutorialNPC"):
		var guide: Variant = target.get("guide")
		if guide != null and is_instance_valid(guide) and (guide as Node).has_method("request_dialogue"):
			guide.call("request_dialogue")
			return true
	# Direct fallbacks for older panels or a stale proximity area after walking.
	if target.is_in_group("Chest") and target.has_method("_open_chest_ui"):
		target.call("_open_chest_ui")
		return true
	var ui: Variant = target.get("_ui")
	if ui != null and is_instance_valid(ui) and (ui as Node).has_method("open_as_station"):
		ui.call("open_as_station")
		return true
	# Last resort only: replay a click for an unexpected custom interactable.
	# Player._input ignores pnc_synthetic, so this cannot trigger a swing.
	_pnc_dispatch_click(at)
	return true

# Held-item actions. Food only counts when tapping near yourself; rod/hoe/
# bucket calls fall through to the existing validators, which return false on
# non-target tiles so the click becomes a move instead.
func _pnc_try_item_use(world_pos: Vector2) -> bool:
	var held: Variant = Global.get_hotbar_item()
	if held == null:
		return false
	var data: ItemData = (held as Dictionary).get("data") as ItemData
	if data == null:
		return false
	if data.heal_amount > 0.0 and global_position.distance_to(world_pos) > PNC_SELF_TAP_RADIUS:
		return false
	var prev_active: bool    = Global.mouse_override_active()
	var prev_pos:    Vector2 = Global.mouse_override_pos()
	Global.set_touch_mouse(world_pos)
	var used: bool = _try_use_held_item()
	Global.restore_mouse_override(prev_active, prev_pos)
	return used

# The player's origin sits at chest height — the sprite (48x48 @ 0.98 scale,
# centered on the origin) bottoms out around +23px, where PlayerCol's
# waist-high collision band also ends (the head/shoulders above it no longer
# collide, the classic top-down overlap behavior).
# Sorting by the origin meant a tree (anchored at its trunk base, same
# int(y/32) bucket) that the player pressed against from the south tied with
# the player and, being added later, drew OVER the player's head. The sort
# key is therefore the FEET plus a half-tile tiebreak: the player now draws
# in front of anything on its own tile whose base is north of its feet, and
# behind everything south of that line — the correct rule for a
# bottom-anchored sprite.
const YSORT_FEET_OFFSET: float = 23.0   # sprite/collision bottom below the origin
const YSORT_TIEBREAK:    float = 16.0   # half a tile — player wins ties when south of an object's base

# World-space Y of the feet — the reference world.gd's _update_grass_sort
# compares against each walkable grass tuft's root line (see grass.gd's
# root_y()). Kept here so the feet offset has a single source of truth.
func sort_feet_y() -> float:
	return global_position.y + YSORT_FEET_OFFSET

# ── Knockback (mob/projectile hits) ───────────────────────────────
# A decaying velocity impulse applied on top of input movement. Set via
# apply_knockback() (called by Global.damage_player); decays linearly.
var _knockback: Vector2 = Vector2.ZERO
const KNOCKBACK_DECAY: float = 800.0  # px/s of knockback velocity lost per second (snappy burst)

func apply_knockback(direction: Vector2, strength: float) -> void:
	_knockback = direction.normalized() * strength

# Normalized Vector2 the player is currently facing (the visible facing, which
# follows the mouse). Knockback pushes the player OPPOSITE this.
func facing_vector() -> Vector2:
	for d in DIRS:
		if d["name"] == _face_dir:
			return (d["vec"] as Vector2).normalized()
	return Vector2.DOWN

# ── Invincibility frames (0.3s after being hit) ─────────────────────
var _invincible_until_ms: int = 0
const INVINCIBILITY_MS: int = 300
# Visual-only red flash duration — longer than invincibility so a hit reads
# clearly (Terraria-style), without extending the i-frame gameplay window.
var _hit_flash_until_ms: int = 0
const HIT_FLASH_MS: int = 1000

func is_invincible() -> bool:
	return Time.get_ticks_msec() < _invincible_until_ms

func become_invincible() -> void:
	_invincible_until_ms = Time.get_ticks_msec() + INVINCIBILITY_MS
	_hit_flash_until_ms  = Time.get_ticks_msec() + HIT_FLASH_MS

func _physics_process(delta: float) -> void:
	if get_tree().paused:
		return
	# Re-derive the camera's clamp from the LIVE area every frame, so a cave /
	# dungeon transition (or a regenerated map) can never leave the camera
	# using a previously visited map's limits.
	_update_camera_limits()
	z_index = int((global_position.y + YSORT_FEET_OFFSET + YSORT_TIEBREAK) / 32)
	get_input(delta)
	# Knockback rides on top of the player's own velocity.
	velocity += _knockback
	_knockback = _knockback.move_toward(Vector2.ZERO, KNOCKBACK_DECAY * delta)
	# Red flash for ~1s on hit (longer than the invincibility window) so a
	# landed hit reads clearly; settles back to white after.
	sprite.modulate = Color(1.0, 0.30, 0.30, 1.0) \
		if (is_invincible() or Time.get_ticks_msec() < _hit_flash_until_ms) \
		else Color.WHITE
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
	_tick_attack_hold()
	_tick_stamina(delta)
	_tick_stuck(delta)

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

# ── Stuck / anti-corner handling ───────────────────────────────────
func _tick_stuck(delta: float) -> void:
	if input_direction == Vector2.ZERO:
		_stuck_time = 0.0
		_last_pos = global_position
		return
	var moved: float = global_position.distance_to(_last_pos)
	if moved >= STUCK_MOVE_THRESHOLD:
		_stuck_time = 0.0
		_last_pos = global_position
		return
	_stuck_time += delta
	if _stuck_time >= STUCK_TELEPORT_TIME:
		_stuck_time = 0.0
		_last_pos = global_position
		_teleport_to_open_spot()
		return
	# Corner nudge: after holding into a wall for a bit, apply a small
	# perpendicular repulsion so a mere nook resolves on its own. Repeats on
	# STUCK_REPEL_INTERVAL until movement actually resumes.
	if _stuck_time >= STUCK_REPEL_TIME and _stuck_time - _last_repel >= STUCK_REPEL_INTERVAL:
		_last_repel = _stuck_time
		global_position += Vector2(-input_direction.y, input_direction.x).normalized() * STUCK_REPEL_DIST

# Last resort: drop the player onto the nearest open tile so they can't be
# permanently wedged. Uses world.gd's spiral search so the landing spot is
# guaranteed free of water/trees/grass/blocks/entrances.
func _teleport_to_open_spot() -> void:
	var world_node := _get_world_node()
	if world_node == null or not world_node.has_method("find_open_spot_near"):
		return
	var spot: Vector2 = world_node.call("find_open_spot_near", global_position, STUCK_TELEPORT_SEARCH) as Vector2
	if spot == Vector2.INF:
		return
	global_position = spot
	_last_pos = spot
	velocity = Vector2.ZERO
	print("[STUCK] teleported to open spot at %s" % str(spot))

# ── Boat / water helpers ──────────────────────────────────────────

# Clamp velocity per-axis so the player can slide along a shoreline.
# Mirrors PlayerCol's waist-high box: 20x12 at (0, 17) — keep in sync with
# player.tscn (and _cell_blocked_by_player in world.gd / cave_world.gd).
func _clamp_velocity_for_water(water_layer: TileMapLayer, delta: float) -> void:
	const HALF_W: float = 10.0
	const HALF_H: float = 6.0
	const OY:     float = 17.0

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

# ── Snowfall weather effect ────────────────────────────────────────
func _build_snow_particles() -> GPUParticles2D:
	var p := GPUParticles2D.new()
	p.name         = "SnowParticles"
	p.z_index      = 900
	p.amount       = CALM_AMOUNT   # kept low — GPU-simulated, but no need to overdo it
	p.lifetime     = 4.0
	p.preprocess   = 2.0    # already mid-fall the moment it's switched on
	p.local_coords = true   # simulated relative to the camera — free follow, no script cost
	p.emitting     = false
	p.visible      = false
	p.modulate.a   = 0.0
	p.texture      = SHADOW_TEXTURE   # reuse the existing soft blob texture, tinted white below
	p.position     = Vector2(0.0, -100.0)

	var mat := ParticleProcessMaterial.new()
	mat.direction             = Vector3(0.1, 1.0, 0.0)
	mat.spread                = CALM_SPREAD
	mat.gravity               = Vector3(0.0, 40.0, 0.0)
	mat.initial_velocity_min  = CALM_VEL_MIN
	mat.initial_velocity_max  = CALM_VEL_MAX
	mat.angular_velocity_min  = -30.0
	mat.angular_velocity_max  = 30.0
	mat.scale_min             = 0.10
	mat.scale_max             = 0.22
	mat.color                 = Color(1.0, 1.0, 1.0, 0.9)
	mat.emission_shape        = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	mat.emission_box_extents  = CALM_BOX_EXTENTS   # comfortably wider/taller than any viewport at typical zoom
	p.process_material = mat

	$mainCam.add_child(p)
	return p

# Polled on a 0.5s timer instead of every physics frame — a single tile
# lookup twice a second is negligible next to the cost of getting this wrong.
func _check_biome() -> void:
	var world_node := _get_world_node()
	if world_node == null or not world_node.has_method("is_snow_biome_at"):
		return
	var is_snow: bool = bool(world_node.call("is_snow_biome_at", global_position))
	if Global.snowstorm_active and not is_snow:
		_end_snowstorm()
	if is_snow == _in_snow_biome:
		return
	_in_snow_biome = is_snow
	_set_snow_effect(is_snow)

# ── Snowstorm ─────────────────────────────────────────────────────
func _on_day_started() -> void:
	if not Global.snowstorm_active and _in_snow_biome and randf() < SNOWSTORM_CHANCE:
		_start_snowstorm()

func _on_night_started() -> void:
	if Global.snowstorm_active:
		_end_snowstorm()

func _start_snowstorm() -> void:
	Global.snowstorm_active = true
	Global.snowstorm_changed.emit(true)
	_apply_storm_intensity(true)

func _end_snowstorm() -> void:
	Global.snowstorm_active = false
	Global.snowstorm_changed.emit(false)
	_apply_storm_intensity(false)

# Reuses the single snowfall particle system — no extra nodes. "Heavier"
# snow is just faster/wider-spread existing particles, all cheap runtime
# property writes with no reallocation.
func _apply_storm_intensity(active: bool) -> void:
	if _snow_particles == null:
		return
	_snow_particles.speed_scale = 2.0 if active else 1.0
	_snow_particles.amount      = STORM_AMOUNT if active else CALM_AMOUNT
	var mat: ParticleProcessMaterial = _snow_particles.process_material as ParticleProcessMaterial
	if mat != null:
		mat.spread               = STORM_SPREAD if active else CALM_SPREAD
		mat.initial_velocity_min = STORM_VEL_MIN if active else CALM_VEL_MIN
		mat.initial_velocity_max = STORM_VEL_MAX if active else CALM_VEL_MAX
		mat.emission_box_extents = STORM_BOX_EXTENTS if active else CALM_BOX_EXTENTS
	# amount changes need a restart to actually resize the particle buffer —
	# without it the extra particles never spawn until the next full cycle.
	if _snow_particles.emitting:
		_snow_particles.restart()

func _set_snow_effect(active: bool) -> void:
	if _snow_particles == null:
		return
	if _snow_fade_tween != null and _snow_fade_tween.is_valid():
		_snow_fade_tween.kill()

	if active:
		_snow_particles.emitting = true
		_snow_particles.visible  = true
		_snow_fade_tween = create_tween()
		_snow_fade_tween.tween_property(_snow_particles, "modulate:a", 1.0, SNOW_FADE_TIME)
	else:
		_snow_fade_tween = create_tween()
		_snow_fade_tween.tween_property(_snow_particles, "modulate:a", 0.0, SNOW_FADE_TIME)
		_snow_fade_tween.tween_callback(func() -> void:
			_snow_particles.emitting = false
			_snow_particles.visible  = false
		)

func _get_world_node() -> Node:
	# is_inside_tree(), not just is_instance_valid() — entering/exiting a
	# cave (game_instance.gd's enter_cave/exit_cave) swaps $World's child
	# via remove_child(), never queue_free(), specifically so the overworld
	# survives for the return trip. That means the old node stays "valid"
	# forever, and without this check this cache would keep pointing at the
	# stale (now off-tree) world — e.g. the water-avoidance code below would
	# keep querying the OVERWORLD's Water layer using the player's new
	# cave-space coordinates, and if that coincidentally lands on water,
	# velocity gets clamped to zero every frame: looks exactly like the
	# player being unable to move at all.
	if is_instance_valid(_world_node_cache) and _world_node_cache.is_inside_tree():
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
# Public read of the player's current facing (world.gd's sword grass-cutting
# needs this to pick which tiles are "in front" — _face_dir/_last_dir stay
# private since nothing outside this file should be able to set them).
func get_facing_dir() -> String:
	return _face_dir

# Public read of the sprint state — a combat LUA uses it to decide whether to
# accelerate into a sprint to run the player down.
func is_sprinting() -> bool:
	return _sprinting

# The 8-way facing name for the cursor direction, or "" when the cursor sits on
# the player. Only used when point-and-click is OFF; with PNC on the cursor is a
# command pointer, not a facing/aim input.
func _mouse_facing_dir() -> String:
	var aim: Vector2 = Global.mouse_world(self) - global_position
	if aim.length_squared() < 4.0:
		return ""
	return _get_closest_dir(aim)

func _get_closest_dir(vec: Vector2) -> String:
	var best_dir: String = _last_dir
	var best_dot: float  = -2.0
	for d in DIRS:
		var dot: float = vec.dot((d["vec"] as Vector2).normalized())
		if dot > best_dot:
			best_dot = dot
			best_dir = d["name"]
	return best_dir

# ── Swing facing-lock ─────────────────────────────────────────────
# While a swing is playing the player is locked to the facing direction they
# started the swing from — turning the character mid-swing would break the
# arc's alignment. world.gd calls _trigger_swing() when the player swings.
var _swing_lock_until_ms: int = 0
var _active_swing:        Node = null   # the live swing effect (single instance)
# One reusable summon burst owned by the player; every swing re-emits it instead
# of allocating a GPUParticles2D + material + gradients per attack.
var _summon_fx:           GPUParticles2D = null
const SWING_LOCK_MS:     int = 240   # a touch longer than the swing effect
# True while the left mouse is held — drives auto-repeat swings (see
# _tick_attack_hold): holding keeps swinging, restarting the instant each
# swing finishes instead of only firing on the initial press.
var _attack_held:        bool = false

func _setup_summon_fx() -> void:
	if not ClassDB.class_exists("GPUParticles2D"):
		return
	_summon_fx = GPUParticles2D.new()
	_summon_fx.name = "SummonMagic"
	_summon_fx.texture = Global.get_smooth_light_texture(32)
	_summon_fx.amount = 34
	_summon_fx.lifetime = 0.7
	_summon_fx.one_shot = true
	_summon_fx.explosiveness = 0.65
	_summon_fx.local_coords = false
	_summon_fx.emitting = false
	_summon_fx.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_summon_fx.z_as_relative = false
	var mat := ParticleProcessMaterial.new()
	mat.direction = Vector3(0.0, -1.0, 0.0)
	mat.spread = 360.0
	mat.gravity = Vector3(0.0, -50.0, 0.0)
	mat.initial_velocity_min = 24.0
	mat.initial_velocity_max = 70.0
	mat.scale_min = 0.28
	mat.scale_max = 0.62
	mat.color = Color(1.0, 0.82, 1.0, 1.0)
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	mat.emission_sphere_radius = 16.0
	var grad := Gradient.new()
	grad.colors = PackedColorArray([
		Color(1.0, 0.85, 1.0, 0.0),
		Color(1.0, 0.9, 1.0, 1.0),
		Color(0.9, 0.7, 1.0, 0.0)])
	grad.offsets = PackedFloat32Array([0.0, 0.4, 1.0])
	var ramp := GradientTexture1D.new()
	ramp.gradient = grad
	mat.color_ramp = ramp
	_summon_fx.process_material = mat
	add_child(_summon_fx)

## Re-emits the single cached summon effect at a world position. The node and
## all particle resources are created once in _ready, never per swing.
func emit_summon_fx(world_pos: Vector2) -> void:
	if _summon_fx == null:
		return
	_summon_fx.global_position = world_pos
	_summon_fx.z_index = z_index + 1
	_summon_fx.restart()
	_summon_fx.emitting = true

# Public: perform a swing with whatever item is currently held. Callable from
# any interaction (plain click, block/tool breaking, tree chopping) so the
# swing effect plays regardless of how the input event is consumed — this is
# the single entry point the whole game routes swings through. The effect is
# spawned as a CHILD of the player so it anchors to the character and travels
# with them, oriented to the current facing. Only one swing is live at a time
# (a new one is ignored until the current has finished and freed itself).
func swing_held_item() -> bool:
	var icon: Texture2D = null
	var damage: float  = 0.0
	var is_sword: bool = false
	var held: Variant = Global.get_hotbar_item()
	if held != null and (held as Dictionary).get("data") != null:
		var data: ItemData = (held as Dictionary)["data"] as ItemData
		if data != null:
			icon = data.icon
			is_sword = data.is_sword
			# Shared with item_tooltip.gd: sword tier, or the existing 1.0 token
			# damage for every other held item. Bare hands (no item) stay at 0.
			damage = data.held_damage()
	return _trigger_swing(icon, damage, is_sword)

# Spawns the swing effect as a child of the player. Returns false if it was
# ignored — a swing already live, or no icon to swing with.
func _trigger_swing(icon: Texture2D, damage: float = 0.0, is_sword: bool = false) -> bool:
	# Ignore while a swing is still playing — no overlapping swings.
	if _active_swing != null and is_instance_valid(_active_swing):
		return false
	if icon == null:
		return false
	var fx: Node2D = SWING_SCRIPT.new() as Node2D
	if fx == null:
		return false
	fx.set("_icon", icon)
	fx.set("_dir", _last_dir)
	fx.set("_damage", damage)
	fx.set("_is_sword", is_sword)
	# Aim the swing at the MOUSE (world space) — swinging where you point is far
	# more intuitive than the 8-way WASD facing. Falls back to _dir when the
	# cursor is on the player, so the swing always has a direction.
	var aim: Vector2 = Global.mouse_world(self) - global_position
	fx.set("_aim", aim if aim.length_squared() > 4.0 else Vector2.ZERO)
	_active_swing = fx
	add_child(fx)
	_swing_lock_until_ms = Time.get_ticks_msec() + SWING_LOCK_MS
	swing_performed.emit()
	return true

func _update_animation() -> void:
	var locked := Time.get_ticks_msec() < _swing_lock_until_ms
	# Movement facing is the default for a walking body — keeps the feet and
	# the sprite pointing the same way (no moonwalking) and keeps
	# facing_vector()/item drops in sync. Frozen during a swing.
	if input_direction != Vector2.ZERO and not locked:
		_last_dir = _get_closest_dir(input_direction)

	# Facing rules (top-down):
	#   • swinging      → lock onto the cursor so the body matches the mouse
	#                     arc for the duration of the swing
	#   • walking       → face the MOVEMENT direction (body follows the feet)
	#   • standing still→ face the cursor, so the character watches your aim
	# Point-and-click deliberately does NOT make the body stare at the mouse:
	# the cursor is a command pointer there, not an aiming device. Movement and
	# PNC targets set _last_dir, so an idle PNC player keeps facing the last
	# action/movement direction. With PNC OFF, the original cursor-facing
	# behaviour is preserved exactly.
	var mouse_dir: String = "" if Global.point_and_click else _mouse_facing_dir()
	if locked:
		if not mouse_dir.is_empty():
			_face_dir = mouse_dir
		elif Global.point_and_click:
			_face_dir = _last_dir
	elif input_direction == Vector2.ZERO:
		if Global.point_and_click:
			_face_dir = _last_dir
		else:
			_face_dir = mouse_dir if not mouse_dir.is_empty() else _last_dir
	else:
		_face_dir = _last_dir

	sprite.speed_scale = 1.0
	if input_direction == Vector2.ZERO:
		var anim := "idle_" + _face_dir.replace("-", "_")
		if sprite.animation != anim:
			sprite.play(anim)
	else:
		var anim := ("sprint_" if _sprinting else "walk_") + _face_dir.replace("-", "_")
		if sprite.animation != anim:
			sprite.play(anim)
	# Mirror the (east-facing) side art for west-ish directions. The 8 directions
	# pick a facing via DIR_VARIANT; no image rotation.
	sprite.flip_h = _face_dir in DIR_FLIP_H
	sprite.rotation = 0.0

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
	"res://resources/items/grass.tres",
]

func _give_debug_items() -> void:
	for path in _DEBUG_ITEM_PATHS:
		if not ResourceLoader.exists(path):
			continue
		var data: ItemData = load(path) as ItemData
		if data != null:
			# allow_dev=true so dev-only items (e.g. the grass tuft) can be
			# handed out here for block-mode testing — see Global.add_item.
			Global.add_item({"quantity": 10, "data": data}, true)

# Debug helper: teleport to the NEAREST dungeon entrance from the current
# dungeon entrance. Reuses the guide arrow's world lookup, so it's a no-op with
# a warning when neither language has a live entrance. The 64px offset drops
# the player just south of the portal so it doesn't overlap it.
func _debug_teleport_to_dungeon() -> void:
	var world := _get_world_node()
	if world == null or not world.has_method("get_dungeon_guide_target"):
		push_warning("DebugTeleport: no dungeon entrance available")
		return
	var target: Vector2 = world.call("get_dungeon_guide_target") as Vector2
	if target == Vector2.INF:
		push_warning("DebugTeleport: no dungeon entrance available")
		return
	global_position = target + Vector2(0.0, 64.0)
	print("DebugTeleport: jumped to dungeon entrance at %s" % str(target))

# Debug helper: reset the tutorial mission state.
# state the same way the old Shift+R shortcut did.
func reset_debug_missions() -> void:
	Global.reset_missions()
	_move_mission_done      = false
	_inventory_mission_done = false

# One inventory toggle used by the keyboard hotkey AND the mobile hotbar's
# inventory button, so both share the pause refcount, mission and UI state.
func toggle_inventory() -> void:
	if inventory_layer.visible:
		if is_instance_valid(inventory_panel):
			inventory_panel.call("dismiss_back")
		else:
			inventory_layer.visible = false
			Global.close_ui()
			Global.inventory_toggled.emit(false)
		return
	if Global.any_ui_open() or Global.pause_menu_open:
		return
	inventory_layer.visible = true
	Global.open_ui()
	# The panel owns the close path so a docked chest is released first and
	# its pause/back registration is always removed together.
	Global.register_ui_back(inventory_panel, Callable(inventory_panel, "dismiss_back"))
	Global.inventory_toggled.emit(true)
	if not _inventory_mission_done:
		_inventory_mission_done = true
		Global.complete_mission("open_inventory")

# ── UI management ─────────────────────────────────────────────────
func _on_close_all_ui() -> void:
	if inventory_layer.visible:
		if is_instance_valid(inventory_panel):
			inventory_panel.call("dismiss_back")
		else:
			inventory_layer.visible = false
			Global.close_ui()
			Global.inventory_toggled.emit(false)

# Convert a real mouse/touch event to world space from its OWN position. Do not
# read the shared touch-cursor override here: that override can still point at
# an old tap while a new tap arrives, which made PNC act on the wrong tile.
func _mouse_event_world(event: InputEventMouse) -> Vector2:
	var vp := get_viewport()
	if vp == null:
		return Global.mouse_world(self)
	return vp.get_canvas_transform().affine_inverse() * event.position

func _input(event: InputEvent) -> void:
	# PNC replays target interactions through the normal event pipeline, but the
	# player must NOT also swing/use/eat from that synthetic press. The target
	# node receives the same event and performs its own action.
	if event.has_meta("pnc_synthetic"):
		return
	# Any real tap/click outside the hotbar releases an active PNC mining lock.
	# A hotbar tap is an item switch instead: the lock stays alive and the block
	# or tree restarts its break bar with the newly selected tool. Synthetic
	# hold events are tagged and must not cancel the lock they belong to.
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT \
			and event.pressed and not event.has_meta("pnc_synthetic") and _pnc_active:
		var mb := event as InputEventMouseButton
		if not Global.is_point_over_hotbar(mb.position):
			_pnc_cancel()
	if Global.is_mouse_event_over_ui(event):
		return
	# Track the left mouse for auto-repeat swings. The release is handled BEFORE
	# the UI guard below so a menu opening mid-hold still clears it (otherwise
	# the player would keep swinging once the menu closes).
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT \
			and not event.pressed:
		_attack_held = false

	# Escape cancels an automated tap order without opening the pause menu.
	if event.is_action_pressed("escape") and _pnc_active:
		_pnc_cancel()
		get_viewport().set_input_as_handled()
		return

	# Inventory key: can always close; blocked from opening when another UI is
	# active. Ignored entirely while a text field is focused — "e" is a typed
	# character then, not the inventory hotkey.
	if event.is_action_pressed("inventory") and not Global.is_text_input_focused():
		toggle_inventory()
		get_viewport().set_input_as_handled()
		return

	if Global.any_ui_open() or Global.pause_menu_open or Global.block_mode:
		return
	# Optional point-and-click: a left click/tap first tries a move/chase order.
	# Build mode, open panels and right-click are never intercepted; clicks that
	# are already in interaction range fall through to the normal action below.
	if Global.point_and_click and not Global.is_mobile() and not _pnc_dispatching \
			and not event.has_meta("pnc_synthetic") \
			and event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT \
			and event.pressed:
		var click_world: Vector2 = _mouse_event_world(event as InputEventMouse)
		# A usable held item wins over the PnC order: click to use/eat/drink/
		# consume it instead of walking or interacting. One use per press; a
		# held button does not repeat because this branch only runs on press.
		if _held_item_is_usable():
			_attack_held = false
			_pnc_cancel()
			_pnc_use_held_item(click_world)
			get_viewport().set_input_as_handled()
			return
		if _pnc_handle_click(click_world):
			get_viewport().set_input_as_handled()
			return
	# Plain left-click swings the held item. This runs from the PLAYER, which
	# exists in every world backend (overworld, cave, pixie cave, dungeon), so
	# the swing animation plays no matter which scene is active. Shift does NOT
	# block it: Shift is the sprint key, so the player must still be able to
	# swing / use items while sprinting (a shift-click on a block simply also
	# starts its hold-to-break, handled by the block's own _input).
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT \
			and event.pressed:
		_attack_held = true
		if _try_use_held_item():
			return
		swing_held_item()

# Auto-repeat: while the left mouse is held, start the next swing the moment the
# current one finishes. swing_held_item()/swing_effect already refuse while a
# swing is live, so this paces itself to the swing duration instead of spamming.
func _tick_attack_hold() -> void:
	if not _attack_held:
		return
	# A UI/menu (or the cave/portal confirm dialog) PAUSES the tree, and a
	# paused player never runs _input — so a mouse RELEASE during that pause is
	# never seen and _attack_held stays latched, resuming the swing loop forever
	# once the UI closes. Reconcile with the real button state every tick so a
	# lost release can't leave it stuck.
	if not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		_attack_held = false
		return
	if Global.any_ui_open() or Global.pause_menu_open or Global.block_mode:
		return
	if _active_swing != null and is_instance_valid(_active_swing):
		return
	swing_held_item()

# ── Held-item "use" (runs before the swing fallback) ───────────────
# A plain left-click normally swings whatever is held. Two item kinds instead
# USE on the click: the fishing rod (cast at a water tile) and cooked food (eat
# to heal). Returns true when the click was consumed by a use, so _input skips
# the swing — the swing is the fallback, not a parallel action.
func _try_use_held_item() -> bool:
	var held: Variant = Global.get_hotbar_item()
	if held == null:
		return false
	var data: ItemData = (held as Dictionary).get("data") as ItemData
	if data == null:
		return false
	if data.is_fishing_rod:
		return _try_cast_fishing_rod()
	if data.is_hoe:
		return _try_till_ground()
	# Seeds are BUILD-MODE only (see world.gd:_input) — outside build mode a
	# click with seeds in hand just swings, it never plants.
	if data.is_bucket:
		return _try_fill_bucket()
	if data.is_water_bucket:
		return _try_place_water()
	if data.max_health_bonus > 0.0 or data.max_stamina_bonus > 0.0:
		return _try_use_stat_crystal(data)
	if data.heal_amount > 0.0:
		return _try_eat_food(data)
	return false


## True when the held item has a click-use path (food, crystals, rod, hoe or
## bucket). Point-and-click uses this to let the item win over a move order.
func _held_item_is_usable() -> bool:
	var held: Variant = Global.get_hotbar_item()
	if held == null:
		return false
	var data: ItemData = (held as Dictionary).get("data") as ItemData
	if data == null:
		return false
	return data.is_fishing_rod or data.is_hoe or data.is_bucket \
		or data.is_water_bucket or data.max_health_bonus > 0.0 \
		or data.max_stamina_bonus > 0.0 or data.heal_amount > 0.0


## Use the held item against the PnC click point. The mouse override lets
## cursor-targeted uses (rod/hoe/bucket) resolve the tapped cell instead of a
## stale cursor position, then restores the previous shared cursor.
func _pnc_use_held_item(world_pos: Vector2) -> bool:
	var prev_active: bool = Global.mouse_override_active()
	var prev_pos: Vector2 = Global.mouse_override_pos()
	Global.set_touch_mouse(world_pos)
	var used: bool = _try_use_held_item()
	Global.restore_mouse_override(prev_active, prev_pos)
	return used

# Hoe: click a grass tuft to till it into plantable soil.
func _try_till_ground() -> bool:
	var world := _get_world_node()
	if world == null or not world.has_method("till_grass_at_cursor"):
		return false
	if not bool(world.call("till_grass_at_cursor")):
		return false
	Global.notify("[color=#9be89b]Tilled the ground. Plant seeds on it.[/color]")
	return true

# Seeds: click tilled soil to plant one seed.
func _try_plant_seeds() -> bool:
	var world := _get_world_node()
	if world == null or not world.has_method("plant_crop_at_cursor"):
		return false
	if not bool(world.call("plant_crop_at_cursor")):
		return false
	var held: Variant = Global.get_hotbar_item()
	if held is Dictionary:
		Global.remove_item((held as Dictionary)["data"] as ItemData)
	Global.notify("[color=#9be89b]Planted wheat. It ripens in 3 minutes.[/color]")
	return true

# Bucket + water tile -> a filled Water Bucket (the empty one is consumed).
func _try_fill_bucket() -> bool:
	var world := _get_world_node()
	if world == null or not world.has_method("cell_is_water"):
		return false
	if not bool(world.call("cell_is_water", world.call("_mouse_cell"))):
		return false
	Global.remove_item(BUCKET_ITEM)
	Global.add_item({"data": WATER_BUCKET_ITEM, "quantity": 1})
	Global.notify("[color=#9bd8f5]Filled the bucket with water.[/color]")
	return true

# Water Bucket + ground -> pours a NEW water source, returning the empty bucket.
func _try_place_water() -> bool:
	var world := _get_world_node()
	if world == null or not world.has_method("place_water_at"):
		return false
	if not bool(world.call("place_water_at", world.call("_mouse_cell"))):
		return false
	Global.remove_item(WATER_BUCKET_ITEM)
	Global.add_item({"data": BUCKET_ITEM, "quantity": 1})
	Global.notify("[color=#9bd8f5]Poured a water source.[/color]")
	return true

# Fishing rod: only a click on a WATER tile casts, so clicking a mob / ground
# still swings the rod normally. Reuses the player's existing water lookup and
# never starts a second cast while one is live.
func _try_cast_fishing_rod() -> bool:
	if _fishing == null or not is_instance_valid(_fishing):
		return false
	if bool(_fishing.call("is_active")):
		return true   # already fishing — swallow the click, don't restart the timer
	if not _cursor_on_water():
		return false
	# RANGE GATE (the rod's configurable cast distance lives in the controller —
	# see fishing_controller.cast_max_blocks). A rejected cast never starts the
	# 5-second attempt, never consumes an item and never rolls the catch chance.
	var target: Vector2 = Global.mouse_world(self)
	if not bool(_fishing.call("is_in_cast_range", target)):
		var max_b: float = float(_fishing.call("max_cast_blocks"))
		Global.notify("[color=#ffaa66]Too far to cast — the rod reaches %d blocks.[/color]"
			% int(round(max_b)))
		return true   # swallow the click so the rod doesn't swing instead
	_fishing.call("start", target)
	return true

# Cooked food: eat one only when it would actually heal (never at full health),
# and never when the cursor is over a solid world object (a wall / placed block /
# furnace) the click should interact with instead. Raw fish have heal_amount 0,
# so they fall through to a normal swing and never heal.
func _try_eat_food(data: ItemData) -> bool:
	if _cursor_over_world_object():
		return false
	if Global.health >= Global.max_health:
		Global.notify("[color=#ffaa66]You're already at full health.[/color]")
		return true
	var healed: float = Global.heal_player(data.heal_amount)
	if healed <= 0.0:
		return true
	Global.remove_item(data)
	Global.notify("[color=#9be89b]Ate a %s (+%d health).[/color]" % [data.item_name, int(healed)])
	return true

# Permanent Life/Stamina Crystals. Only consume the item when at least one
# stat actually grew; at the cap the click is swallowed with a message.
func _try_use_stat_crystal(data: ItemData) -> bool:
	var hp_gain: float = Global.increase_max_health(data.max_health_bonus)
	var sp_gain: float = Global.increase_max_stamina(data.max_stamina_bonus)
	if hp_gain <= 0.0 and sp_gain <= 0.0:
		Global.notify("[color=#ffaa66]%s is already at its maximum.[/color]" % data.item_name)
		return true
	Global.remove_item(data)
	var parts: PackedStringArray = []
	if hp_gain > 0.0:
		parts.append("+%d max HP" % int(round(hp_gain)))
	if sp_gain > 0.0:
		parts.append("+%d max stamina" % int(round(sp_gain)))
	Global.notify("[color=#9be89b]Used %s: %s.[/color]" % [data.item_name, ", ".join(parts)])
	return true

# True when the mouse is over a water cell of the active world.
func _cursor_on_water() -> bool:
	var world := _get_world_node()
	if world == null:
		return false
	var water_layer: TileMapLayer = world.get_node_or_null("Water") as TileMapLayer
	if water_layer == null:
		return false
	return _water_at(water_layer, Global.mouse_world(self))

# True when the cursor is over a solid body on the world layer (walls, placed
# blocks, furnace/crafting station). Eating is skipped then so clicking an
# object interacts with it instead of being swallowed by a bite.
func _cursor_over_world_object() -> bool:
	var space := get_world_2d().direct_space_state
	if space == null:
		return false
	var params := PhysicsPointQueryParameters2D.new()
	params.position = Global.mouse_world(self)
	params.collision_mask = 1          # world / walls / placed blocks
	params.collide_with_bodies = true
	params.collide_with_areas = false
	return not space.intersect_point(params, 1).is_empty()

func apply_item_effect(item) -> void:
	match item["effect"]:
		"Sword": print("You touched my sword")
		_: print("No effect uWu")
