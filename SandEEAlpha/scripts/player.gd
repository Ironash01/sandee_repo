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
	$mainCam.zoom = Vector2(Global.camera_zoom, Global.camera_zoom)
	Global.camera_zoom_changed.connect(_on_camera_zoom_changed)
	if _shared_frames == null:
		_shared_frames = _build_frames()
	sprite.sprite_frames = _shared_frames
	sprite.scale = Vector2(0.980, 0.980)
	# Offset tuned to sit under the feet — PlayerCol's collision box
	# (position.y 6.5, half-height 16.5) bottoms out around y=23.
	add_child(Global.make_shadow_sprite(SHADOW_TEXTURE, Vector2(0.0, 14.0), Vector2(0.8, 0.4), 0.35))
	add_child(MissionGuideArrow.new())
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

	_snow_particles = _build_snow_particles()
	_biome_check_timer = Timer.new()
	_biome_check_timer.wait_time = 0.5
	_biome_check_timer.autostart = true
	_biome_check_timer.timeout.connect(_check_biome)
	add_child(_biome_check_timer)
	Global.day_started.connect(_on_day_started)
	Global.night_started.connect(_on_night_started)

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
	# While the chat console's input is focused, don't let WASD walk the player.
	if Global.chat_open:
		input_direction = Vector2.ZERO
		velocity = Vector2.ZERO
		_sprinting = false
		return
	input_direction = Input.get_vector(
		"gameplay_left", "gameplay_right", "gameplay_up", "gameplay_down"
	).normalized()
	var want_sprint: bool = Input.is_key_pressed(KEY_SHIFT) and input_direction != Vector2.ZERO
	_sprinting = want_sprint and not _stamina_exhausted
	var storm_mult: float = SNOWSTORM_SPEED_MULT if Global.snowstorm_active else 1.0
	velocity = input_direction * movement_speed * (SPRINT_MULTIPLIER if _sprinting else 1.0) * storm_mult

# The player's origin sits at chest height — the sprite (48x48 @ 0.98 scale,
# centered on the origin) bottoms out around +23px, same as PlayerCol's box.
# Sorting by the origin meant a tree (anchored at its trunk base, same
# int(y/32) bucket) that the player pressed against from the south tied with
# the player and, being added later, drew OVER the player's head. The sort
# key is therefore the FEET plus a half-tile tiebreak: the player now draws
# in front of anything on its own tile whose base is north of its feet, and
# behind everything south of that line — the correct rule for a
# bottom-anchored sprite.
const YSORT_FEET_OFFSET: float = 23.0   # sprite/collision bottom below the origin
const YSORT_TIEBREAK:    float = 16.0   # half a tile — player wins ties when south of an object's base

# ── Knockback (mob/projectile hits) ───────────────────────────────
# A decaying velocity impulse applied on top of input movement. Set via
# apply_knockback() (called by Global.damage_player); decays linearly.
var _knockback: Vector2 = Vector2.ZERO
const KNOCKBACK_DECAY: float = 800.0  # px/s of knockback velocity lost per second (snappy burst)

func apply_knockback(direction: Vector2, strength: float) -> void:
	_knockback = direction.normalized() * strength

# Normalized Vector2 the player is currently facing (from the last movement
# direction). Knockback pushes the player OPPOSITE this.
func facing_vector() -> Vector2:
	for d in DIRS:
		if d["name"] == _last_dir:
			return (d["vec"] as Vector2).normalized()
	return Vector2.DOWN

# ── Invincibility frames (0.3s after being hit) ─────────────────────
var _invincible_until_ms: int = 0
const INVINCIBILITY_MS: int = 300

func is_invincible() -> bool:
	return Time.get_ticks_msec() < _invincible_until_ms

func become_invincible() -> void:
	_invincible_until_ms = Time.get_ticks_msec() + INVINCIBILITY_MS

func _physics_process(delta: float) -> void:
	if get_tree().paused:
		return
	z_index = int((global_position.y + YSORT_FEET_OFFSET + YSORT_TIEBREAK) / 32)
	get_input()
	# Knockback rides on top of the player's own velocity.
	velocity += _knockback
	_knockback = _knockback.move_toward(Vector2.ZERO, KNOCKBACK_DECAY * delta)
	# Red flash while in the post-hit invincibility frames.
	sprite.modulate = Color(1.0, 0.30, 0.30, 1.0) if is_invincible() else Color.WHITE
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
# needs this to pick which tiles are "in front" — _last_dir itself stays
# private since nothing outside this file should be able to set it).
func get_facing_dir() -> String:
	return _last_dir

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

# Debug (via the chat console's /dungeon command): teleport to the accepted
# dungeon's entrance portal. Reuses the guide arrow's world lookup, so it's a
# no-op with a warning when no dungeon mission is accepted or its entrance
# doesn't exist yet. The 64px offset drops the player just south of the portal
# so it doesn't overlap it.
func _debug_teleport_to_dungeon() -> void:
	var world := _get_world_node()
	if world == null or not world.has_method("get_dungeon_guide_target"):
		push_warning("DebugTeleport: no dungeon entrance (accept a dungeon mission first)")
		return
	var target: Vector2 = world.call("get_dungeon_guide_target") as Vector2
	if target == Vector2.INF:
		push_warning("DebugTeleport: no dungeon entrance (accept a dungeon mission first)")
		return
	global_position = target + Vector2(0.0, 64.0)
	print("DebugTeleport: jumped to dungeon entrance at %s" % str(target))

# Debug (via the chat console's /missions command): reset the tutorial mission
# state the same way the old Shift+R shortcut did.
func reset_debug_missions() -> void:
	Global.reset_missions()
	_move_mission_done      = false
	_inventory_mission_done = false

# ── UI management ─────────────────────────────────────────────────
func _on_close_all_ui() -> void:
	if inventory_layer.visible:
		inventory_layer.visible = false
		Global.close_ui()
		Global.inventory_toggled.emit(false)

func _input(event: InputEvent) -> void:
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
