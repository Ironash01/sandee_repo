extends Node2D

const TILE_SIZE = 32
const TREE_SCENE:      PackedScene = preload("res://scenes/objects/Tree.tscn")
const WOLF_SCENE:      PackedScene = preload("res://scenes/mobs/Wolf.tscn")
const NEW_TREE_TEX:    Texture2D   = preload("res://sprites/tree/new_tree.webp")
const SHADOW_TEXTURE:  Texture2D   = preload("res://sprites/shadow/shadow_base.png")
const ITEM_DROP_SCENE: PackedScene = preload("res://scenes/ui/InventoryItem.tscn")

# Extra pixels beyond the geometrically-exact half-tile offset used to plant
# a tree's trunk base on the grid line — tune this if the source art has
# transparent padding under the trunk that the math can't see.
const TREE_BASE_EXTRA_OFFSET_PX: float = 4.0

# The tree's local origin (0,0) IS the trunk's visual base (see _spawn_tree),
# so 0.0 sits the shadow right at the base line. A previous +3.0 left a gap
# under the trunk that read as the tree floating above its own shadow.
const TREE_SHADOW_OFFSET_Y: float = -7.0

# Ghost preview, placement grid, and cursor highlight all need to draw above
# every Y-sorted world sprite (player/trees/grass/placed blocks all use a
# quantized z_index = int(y / TILE_SIZE), which can reach several hundred
# near the map edges) so they never get visually overlapped by whatever the
# guide is standing in front of/behind.
const PLACEMENT_GUIDE_Z_INDEX: int = 2000

enum Terrain { Water, Plain, Desert, Snowy }
@export var player: CharacterBody2D

var spawn_center: Vector2

# For Terrain Gen
const WATER_THRESHOLD:     float = 0.33
const SNOW_THRESHOLD:      float = 0.38
const SAND_THRESHOLD:      float = 0.2
const FORCED_PLAINS_RADIUS: float = 128

# For Foliage Gen
const FOLIAGE_SPACING:    float = 16   # was 8 — wider spacing = ~4x fewer base points
const SPAWN_CLEAR_TILES:  int   = 8
const REJECTION_THRESHOLD: int  = 30

# For Grass Gen — dense per-chunk fill (see _fill_chunk_grass), not a sparse
# scatter: every chunk is filled to a random GRASS_CHUNK_COVERAGE_MIN..MAX
# fraction of its eligible plains tiles at world-gen. World only decides
# WHICH tiles get grass — how a single tuft looks/sizes/anchors/animates
# lives in scripts/grass.gd (GrassTuft), instantiated via GRASS_SCENE.
const GRASS_SCENE: PackedScene = preload("res://scenes/objects/Grass.tscn")
const GRASS_CHUNK_COVERAGE_MIN: float = 0.15
const GRASS_CHUNK_COVERAGE_MAX: float = 0.20
# Per chunk fill, 70% of the time the target tile count is taken as one
# compact cluster (nearest tiles to a random seed point) instead of spread
# uniformly across the whole chunk.
const GRASS_GROUPED_CHANCE: float = 0.70
const GRASS_REGROW_INTERVAL: float = 600.0  # 10 minutes, matches the overworld day spawn cadence
# How many chunks _fill_all_chunks_with_grass() processes before yielding a
# frame — keeps the background fill from hitching gameplay while it catches
# up after load. Higher = finishes filling in sooner but each yielded frame
# does more work; lower = smoother but takes longer to fully fill in.
const GRASS_CHUNKS_PER_FRAME: int = 4

# For Large Forest Gen (plains and snowy only)
const LARGE_FOREST_MIN_SEP:   int   = 100
const LARGE_FOREST_R_MIN:     int   = 10  # was 15
const LARGE_FOREST_R_MAX:     int   = 20  # was 30
const LARGE_FOREST_COUNT_MIN: int   = 3   # was 6
const LARGE_FOREST_COUNT_MAX: int   = 7   # was 12
const LARGE_FOREST_ATTEMPTS:  int   = 400 # was 600
const LARGE_FOREST_D_CENTER:  float = 0.40 # was 0.70
const LARGE_FOREST_D_EDGE:    float = 0.07 # was 0.15

@export var random_seed: int  = 1234
@export var width:       int  = 1024
@export var height:      int  = 1024
@export var use_experimental_ground: bool = true

var _exp_ground_src:  int = -1
var _exp_ground_cols: int = 0
var _exp_ground_rows: int = 0

const NEW_TREE_CHANCE: float = 1.0

const WOLF_SPAWN_CHANCE: float = 0.003  # was 0.08 — 8% of 5000 plains tiles = ~400 wolves
const WOLF_BAND_SIZE:    int   = 50
const WOLF_SCAN_STEP:    int   = 5

# One-shot at world-gen, one attempt per chunk (any land biome) — see
# _spawn_cave_entrances(). CavePortal/CaveWorld/CaveGenerator handle
# everything about what's actually inside.
const CAVE_ENTRANCE_CHANCE:         float = 0.25   # per eligible chunk
const CAVE_ENTRANCE_MIN_SPAWN_DIST: float = 200.0  # no caves closer than this to world spawn
const CAVE_ENTRANCE_MIN_SEPARATION: float = 100.0  # no two caves closer than this to each other

# Chunks a cave entrance claims are excluded from every other one-shot
# generation pass (trees/forests, grass fill, wolves) — see
# _is_chunk_cave_claimed(). Populated by _spawn_cave_entrances(), which must
# therefore run BEFORE _spawn_wolves/_deferred_foliage (see the call order
# where these are all queued via call_deferred()).
var _cave_claimed_chunks: Dictionary = {}   # chunk coord (Vector2i) -> true
var _cave_entrance_tiles: Array      = []   # placed entrance tiles, for the min-separation check

# ── Dungeon entrances (spawned on mission accept) ──────────────────────
# Unlike caves (rolled during world-gen), a dungeon entrance spawns LATER —
# the first time the player accepts a dungeon mission (see
# _on_mission_accepted). Its chunk must satisfy every one of:
#   a. no player-placed blocks in it
#   b. not a cave-claimed chunk
#   c. not the chunk the player is currently standing in
#   d. not within DUNGEON_SPAWN_MIN_DIST_TILES tiles of world spawn
const DUNGEON_PORTAL_SCENE: PackedScene = preload("res://scenes/objects/DungeonPortal.tscn")
const DUNGEON_SPAWN_MIN_DIST_TILES: float = 200.0   # tiles (blocks) from world spawn
const DUNGEON_INVALID_TILE: Vector2i = Vector2i(1 << 20, 1 << 20)  # sentinel, outside any map bounds
var _dungeon_entrance_tiles: Dictionary = {}  # dungeon_index -> Vector2i tile
var _dungeon_portal_nodes:   Dictionary = {}  # dungeon_index -> spawned DungeonPortal (so a cleared dungeon's entrance can be removed)

# Trees beyond this radius have their Area2D monitoring disabled to avoid
# O(n²) physics overhead. Must be larger than InteractArea radius (48px).
# NOTE: grass deliberately does NOT use this per-node Area2D pattern — see
# _try_cut_grass_with_sword below. A grass-scale
# (thousands of tufts) periodic full-group scan was tried and became the
# dominant runtime cost; grass cutting is driven centrally instead, same
# O(1) dictionary-lookup approach _destroy_hovered_block() already uses for
# placed blocks.
const TREE_INTERACT_RADIUS: float = 300.0

# ── Chunk grid ──────────────────────────────────────────────────────
# 25x25-tile chunks, indexed from the top-left of the world (0,0) toward
# the bottom-right. Used to gate the periodic outer-region mob spawner
# so the same area can't repeatedly spawn mobs within a short window.
const CHUNK_SIZE: int = 25

var _chunk_cols: int = 0
var _chunk_rows: int = 0

# ── Mob lifecycle (preservation / despawn / spawn) ──────────────────
# "Preserve" radii: which live mobs get written into the save file, so they
# reappear at their last-known position instead of resetting to their
# deterministic world-gen spawn point.
const MOB_PRESERVE_PLAYER_RADIUS: float = 75.0  * TILE_SIZE  # moves with the player
const MOB_PRESERVE_SPAWN_RADIUS:  float = 100.0 * TILE_SIZE  # fixed at world spawn

# "Despawn" radii: how far a mob currently is from the player or world spawn.
# The actual per-zone despawn durations (30/15/5 min) live on the mob script
# itself (see wolf.gd ZONE_DESPAWN_TIME) — this just classifies the zone.
const DESPAWN_INNER_RADIUS: float = 100.0 * TILE_SIZE
const DESPAWN_SAFE_RADIUS:  float = 200.0 * TILE_SIZE
const DESPAWN_CHECK_INTERVAL: float = 10.0

# Periodic overworld spawner — a single unified check across every eligible
# outer chunk, cadence depending on time of day (see Global.is_daytime).
const OUTER_SPAWN_INTERVAL_DAY:   float = 600.0  # 10 minutes
const OUTER_SPAWN_INTERVAL_NIGHT: float = 180.0  # 3 minutes

# Pool of mobs the overworld spawner can pick from — each entry pairs a scene
# with the MobCombatData resource that drives its spawn rules (biome,
# day/night eligibility, min/max count per chunk). Add new mobs here as
# their .tres + AI script get built.
var MOB_SPAWN_POOL: Array = [
	{"scene": WOLF_SCENE, "data": preload("res://resources/mobs/wolf.tres")},
]

var rng: RandomNumberGenerator = RandomNumberGenerator.new()

var humidity:    FastNoiseLite = FastNoiseLite.new()
var temperature: FastNoiseLite = FastNoiseLite.new()
var altitude:    FastNoiseLite = FastNoiseLite.new()

@onready var water_layer:    TileMapLayer = $Water
@onready var ground_layer:   TileMapLayer = $Ground
@onready var editable_layer: TileMapLayer = $Editable

signal generation_complete
signal generation_status_changed(status: String)

var _removed_trees:    Array = []
var _tree_spawn_count: int   = 0
var _gen_start_ms:     int   = 0

# ── Grass ──────────────────────────────────────────────────────────
# Each tuft's own look/sizing/material lives in scripts/grass.gd
# (GrassTuft) — see GRASS_SCENE above. World only tracks which tiles have
# grass, for spawning/regrow/cutting purposes.
var _grass_occupied_tiles: Dictionary   = {}     # tile -> GrassTuft, prevents stacking grass and gives cutting a direct node reference
var _grass_spawn_count:    int          = 0

# ── Block placement ──────────────────────────────────────────────────
var ghost:           Node2D   = null
var ghost_sprite:    Sprite2D = null
var ghost_last_type: String   = ""
var _grid_overlay:      Node2D = null
var _cursor_highlight:  Node2D = null
var _placed_blocks:     Dictionary = {}

# Tiles blocked from placement because a tree's 3x3 footprint covers them.
# Dictionary value is a reference count so overlapping tree footprints don't
# unblock a tile just because ONE of several nearby trees was chopped down.
var _tree_occupied_tiles: Dictionary = {}
const TREE_PLACE_BLOCK_RADIUS: int = 1  # 1 => 3x3 footprint around the tree's cell

# ── Chunk border debug overlay (Ctrl+Shift+C) ────────────────────────
var _chunk_border_overlay: Node2D = null
var _show_chunk_borders:   bool   = false
const CHUNK_BORDER_COLOR: Color = Color(1.0, 0.55, 0.0, 0.9)  # orange

# ── Hitbox debug overlay (Ctrl+Shift+H) ──────────────────────────────
var _hitbox_overlay: Node2D = null
var _show_hitboxes:  bool   = false
const HITBOX_MOB_COLOR:   Color = Color(1.0, 0.15, 0.15, 0.9)  # red
const HITBOX_BLOCK_COLOR: Color = Color(0.15, 0.55, 1.0, 0.9)  # blue
const HITBOX_GRASS_COLOR: Color = Color(0.25, 0.95, 0.35, 0.9)  # green
const GRASS_MARKER_RADIUS: float = 5.0  # small fixed marker, not a bounding box — see _draw_grass_tile_outline

const PLACEABLE_TYPES:    Array  = ["block", "door"]
const PLACE_RADIUS_TILES: int    = 6
const INTERACT_RADIUS_PX: float  = 64.0

func _ready() -> void:
	# NOTE: do NOT set y_sort_enabled here. Game (World's parent in
	# game_instance.tscn) already has y_sort_enabled = true, which propagates
	# recursively through the whole subtree — that's almost certainly what's
	# always correctly Y-sorted the player against trees/mobs. Re-enabling it
	# here on World creates a NESTED Y-sort scope: World's own children get
	# sorted correctly among themselves, but that sorted group then gets
	# compared against Player (World's sibling under Game, not a descendant
	# of World) as effectively one block using World's own static position —
	# which is what caused grass to sort fine against other grass but
	# inconsistently against the player depending on approach direction.
	ground_layer.z_index = -300
	water_layer.z_index  = -300
	rng.set_seed(random_seed)
	_set_up_noise(humidity,    0.003)
	_set_up_noise(temperature, 0.002)
	_set_up_noise(altitude,    0.005)
	if use_experimental_ground:
		_apply_experimental_ground()
	_setup_ghost()
	_setup_grid_overlay()
	_setup_cursor_highlight()
	_setup_chunk_border_overlay()
	_setup_hitbox_overlay()
	_setup_glow_environment()
	Global.hotbar_selection_changed.connect(_on_hotbar_changed)
	Global.Hotbar_updated.connect(_on_hotbar_changed)
	Global.mission_accepted.connect(_on_mission_accepted)
	# Set world reference immediately so game_instance can connect signals.
	Global.world_node = self
	# Two-step deferred chain: step 1 runs this frame's MessageQueue flush,
	# step 2 runs the NEXT frame's flush — after this frame's render step.
	# This guarantees the loading screen draws at least once before any freeze.
	_queue_generation.call_deferred()

func _input(event: InputEvent) -> void:
	# Ctrl+Shift+H/C/T and the block-mode Ctrl toggle are now detected once,
	# centrally, in Global._input() (dispatches here via has_method()/call())
	# — see Global's own comment for why. This function only needs to react
	# to Global.block_mode/its own toggle_*() methods now, not detect the
	# keypresses itself.
	if not Global.block_mode:
		# Shift + left-click: instantly destroy the nearest placed block.
		if event.is_action_pressed("mouse_left") and Input.is_key_pressed(KEY_SHIFT):
			_destroy_hovered_block()
			return
		# Plain left-click: sword-swing — cuts the 3-tile row in front of the
		# player. Plain click previously did nothing here (only Shift+click
		# did), so this doesn't collide with the block-destroy shortcut above.
		if event.is_action_pressed("mouse_left") and not Input.is_key_pressed(KEY_SHIFT):
			_try_cut_grass_with_sword()
		return
	if event.is_action_pressed("mouse_left"):
		place_block()

func _destroy_hovered_block() -> void:
	var mouse_pos: Vector2 = get_global_mouse_position()
	var best_cell: Variant = null
	var best_dist: float   = INTERACT_RADIUS_PX
	for cell in _placed_blocks:
		var entry: Dictionary = _placed_blocks[cell] as Dictionary
		var node: Node2D      = entry["node"] as Node2D
		if not is_instance_valid(node):
			continue
		var dist: float = mouse_pos.distance_to(node.global_position)
		if dist < best_dist:
			best_dist = dist
			best_cell = cell
	if best_cell == null:
		return
	# Consume the event so the block's own _input doesn't also fire.
	get_viewport().set_input_as_handled()
	var entry: Dictionary = _placed_blocks[best_cell] as Dictionary
	var node: Node        = entry["node"] as Node
	if is_instance_valid(node):
		var idata: ItemData = node.get("item_data") as ItemData
		if idata != null:
			var drop: Node = ITEM_DROP_SCENE.instantiate()
			drop.call("set_item_data", idata)
			add_child(drop)
			drop.global_position = node.global_position + Vector2(0, -16)
		node.queue_free()
	_placed_blocks.erase(best_cell)

# ── Grass cutting (sword-only, instant, facing-based) ──────────────────
# Grass can only be cut while the selected hotbar item is a sword
# (ItemData.is_sword) — no tool, no cut. A swing is instant (no hold timer,
# unlike tree.gd's chopping) and hits a 3-tile-wide row directly in front of
# the player rather than whatever tile the mouse happens to be over — mouse
# position/INTERACT_RADIUS_PX are no longer involved at all, since "in front
# of the player" is itself the range check.
#
# Row shape: center = player_tile + facing_vec (one tile ahead), with one
# tile on each side along the perpendicular axis. rotate90(d) = (-d.y, d.x)
# gives that perpendicular for any of the 8 facing directions (including
# diagonals) from a single small lookup + two integer ops — no per-direction
# tile-offset table to keep in sync.
const GRASS_CUT_DIR_VECTORS: Dictionary = {
	"south":      Vector2i(0, 1),
	"north":      Vector2i(0, -1),
	"east":       Vector2i(1, 0),
	"west":       Vector2i(-1, 0),
	"south-east": Vector2i(1, 1),
	"south-west": Vector2i(-1, 1),
	"north-east": Vector2i(1, -1),
	"north-west": Vector2i(-1, -1),
}

func _try_cut_grass_with_sword() -> void:
	if Global.any_ui_open() or Global.pause_menu_open:
		return
	var held: Variant = Global.get_hotbar_item()
	if held == null or not (held as Dictionary).get("data"):
		return
	var data: ItemData = (held as Dictionary)["data"] as ItemData
	if not data.is_sword:
		return
	var p: Node2D = _get_player()
	if p == null or not p.has_method("get_facing_dir"):
		return
	var d: Vector2i = GRASS_CUT_DIR_VECTORS.get(p.call("get_facing_dir"), Vector2i(0, 1)) as Vector2i
	var player_tile: Vector2i = ground_layer.local_to_map(ground_layer.to_local(p.global_position))
	var center:      Vector2i = player_tile + d
	var width_axis:  Vector2i = Vector2i(-d.y, d.x)
	var cut_any: bool = false
	for tile in [center - width_axis, center, center + width_axis]:
		var tuft: GrassTuft = _grass_occupied_tiles.get(tile) as GrassTuft
		if tuft != null and is_instance_valid(tuft):
			tuft.cut()
			cut_any = true
	if cut_any:
		# Consume the event so nothing else (e.g. a tree's own _input, if one
		# happens to overlap) also reacts to this click.
		get_viewport().set_input_as_handled()

func _process(delta: float) -> void:
	_update_ghost()
	_update_hover()
	_update_cursor_highlight()
	_update_grass_ruffle()
	if Global.block_mode and _grid_overlay != null:
		_grid_overlay.queue_redraw()
	if _show_hitboxes and _hitbox_overlay != null:
		_hitbox_overlay.queue_redraw()

# One Vector2 write per frame onto the single shared grass ShaderMaterial —
# every tuft reads it on the GPU, so this costs the same whether there are
# ten grass instances or a hundred thousand.
func _update_grass_ruffle() -> void:
	var p: Node2D = _get_player()
	if p == null:
		return
	GrassTuft.get_grass_material().set_shader_parameter("player_pos", p.global_position)

func _queue_generation() -> void:
	_begin_generation.call_deferred()

func _begin_generation() -> void:
	_gen_start_ms = Time.get_ticks_msec()
	print("[WORLD] generation started — map %dx%d tiles" % [width, height])
	generation_status_changed.emit("Chunking the chunks, chuckingly")
	_compute_chunks()
	generation_status_changed.emit("Generating terrain...")
	var t0 := Time.get_ticks_msec()
	_generate_terrain()
	print("[TERRAIN] done in %dms — %d tiles processed" % [Time.get_ticks_msec() - t0, width * height])
	generation_status_changed.emit("Spawning trees and forests...")
	# Cave entrances must claim their chunks BEFORE wolves/trees/grass are
	# placed — those all check _is_chunk_cave_claimed() and skip claimed
	# chunks entirely, which only works if the claims already exist.
	_spawn_cave_entrances.call_deferred()
	_spawn_wolves.call_deferred()
	_deferred_foliage.call_deferred()

func _compute_chunks() -> void:
	_chunk_cols = ceili(float(width)  / CHUNK_SIZE)
	_chunk_rows = ceili(float(height) / CHUNK_SIZE)

func _deferred_foliage() -> void:
	var t0 := Time.get_ticks_msec()
	_place_foliage()
	print("[FOLIAGE] total %d trees in %dms" % [_tree_spawn_count, Time.get_ticks_msec() - t0])
	print("[WORLD] fully loaded in %dms since scene start" % [Time.get_ticks_msec() - _gen_start_ms])
	if not Global.pending_world_data.is_empty():
		apply_world_save_data(Global.pending_world_data)
		Global.pending_world_data.clear()
	# Repair the state where a dungeon mission is accepted but its entrance
	# never got recorded — e.g. an old save from before the spawner's all-ocean
	# chunk fix, or a spawn interrupted by a quit. Re-accepting isn't possible
	# once the mission UI disables that mission's Accept button, so reconcile
	# here instead: if the accepted dungeon has no entrance, spawn one now.
	_ensure_accepted_dungeon_entrance()
	_start_interaction_updater()
	_start_despawn_timer()
	_start_outer_spawn_timer()
	_start_grass_regrow_timer()
	generation_complete.emit()
	# Grass fill runs AFTER the player is already free to move, not before —
	# it's purely decorative and each tuft now carries real collision shapes
	# (see the O(n²) Area2D fix above), so spawning thousands of them
	# synchronously here was the main remaining cause of "world loading feels
	# slow." _fill_all_chunks_with_grass() spreads its own work across many
	# frames internally (see GRASS_CHUNKS_PER_FRAME), so this call is
	# deliberately fire-and-forget, not awaited — tiles fill in progressively
	# in the background while the player is already exploring. Must still run
	# after _place_foliage() (needs _tree_occupied_tiles final) and after
	# apply_world_save_data() (needs _placed_blocks final so grass doesn't
	# overlap restored structures) — both already happened above.
	_fill_all_chunks_with_grass()

func _start_interaction_updater() -> void:
	# Immediate pass so trees near spawn are active the moment the player
	# appears. Grass has no equivalent — see _try_cut_grass_with_sword.
	_update_tree_interactions()
	var t := Timer.new()
	t.wait_time  = 0.1
	t.autostart  = true
	t.timeout.connect(_update_tree_interactions)
	add_child(t)

func _update_tree_interactions() -> void:
	var p := _get_player()
	if p == null:
		return
	var player_pos := p.global_position
	for tree in get_tree().get_nodes_in_group("Tree"):
		if not is_instance_valid(tree):
			continue
		var t_node := tree as Node2D
		var interact := t_node.get_node_or_null("InteractArea") as Area2D
		if interact == null:
			continue
		var should_be_active := t_node.global_position.distance_to(player_pos) <= TREE_INTERACT_RADIUS
		if interact.monitoring != should_be_active:
			interact.monitoring  = should_be_active
			interact.monitorable = should_be_active

# ── Mob world spawn reference ───────────────────────────────────────
func _world_spawn_pos() -> Vector2:
	return to_global(Vector2.ZERO)

# ── Mob despawn timer (inner/safe/outer) ─────────────────────────────
func _start_despawn_timer() -> void:
	var t := Timer.new()
	t.wait_time = DESPAWN_CHECK_INTERVAL
	t.autostart = true
	t.timeout.connect(_update_mob_despawn_timers)
	add_child(t)

func _update_mob_despawn_timers() -> void:
	var p := _get_player()
	var player_pos: Vector2 = p.global_position if p != null else Vector2.ZERO
	var spawn_pos:  Vector2 = _world_spawn_pos()
	for mob in get_tree().get_nodes_in_group("Wolf"):
		if not is_instance_valid(mob):
			continue
		var m2d: Node2D = mob as Node2D
		var dp: float = m2d.global_position.distance_to(player_pos)
		var ds: float = m2d.global_position.distance_to(spawn_pos)
		var zone: int
		if dp <= DESPAWN_INNER_RADIUS or ds <= DESPAWN_INNER_RADIUS:
			zone = 0  # inner — 30 min
		elif dp <= DESPAWN_SAFE_RADIUS or ds <= DESPAWN_SAFE_RADIUS:
			zone = 1  # safe — 15 min
		else:
			zone = 2  # outer — 5 min
		if mob.has_method("_apply_despawn_zone"):
			mob.call("_apply_despawn_zone", zone, DESPAWN_CHECK_INTERVAL)

# ── Chunk grid helpers ────────────────────────────────────────────────
func _chunk_world_rect(chunk: Vector2i) -> Rect2:
	var half_w: int = width  / 2
	var half_h: int = height / 2
	var tile_tl: Vector2i = Vector2i(chunk.x * CHUNK_SIZE - half_w, chunk.y * CHUNK_SIZE - half_h)
	var world_tl: Vector2 = ground_layer.to_global(ground_layer.map_to_local(tile_tl)) \
		- Vector2(TILE_SIZE, TILE_SIZE) * 0.5
	var size_px: Vector2 = Vector2(CHUNK_SIZE, CHUNK_SIZE) * TILE_SIZE
	return Rect2(world_tl, size_px)

# Nearest-corner distance from a chunk's world-space rect to a point.
func _chunk_min_corner_dist(chunk: Vector2i, point: Vector2) -> float:
	var r: Rect2 = _chunk_world_rect(chunk)
	var corners: Array[Vector2] = [
		r.position,
		r.position + Vector2(r.size.x, 0.0),
		r.position + Vector2(0.0, r.size.y),
		r.position + r.size,
	]
	var best: float = INF
	for c in corners:
		best = minf(best, c.distance_to(point))
	return best

func _is_chunk_outer(chunk: Vector2i, player_pos: Vector2, spawn_pos: Vector2) -> bool:
	return _chunk_min_corner_dist(chunk, player_pos) > DESPAWN_SAFE_RADIUS \
		and _chunk_min_corner_dist(chunk, spawn_pos) > DESPAWN_SAFE_RADIUS

# Maps _cell_biome_type()'s codes (0=Plain,1=Desert,2=Snowy,-1=Water) onto a
# mob resource's biome checkboxes.
func _mob_allows_biome(data: MobCombatData, biome_code: int) -> bool:
	match biome_code:
		0:  return data.spawn_plains
		1:  return data.spawn_desert
		2:  return data.spawn_snowy
		-1: return data.spawn_ocean
	return false

func _random_valid_mob_tile_in_chunk(chunk: Vector2i, data: MobCombatData) -> Variant:
	var half_w: int = width  / 2
	var half_h: int = height / 2
	var tl := Vector2i(chunk.x * CHUNK_SIZE - half_w, chunk.y * CHUNK_SIZE - half_h)
	for _i in range(20):
		var tile: Vector2i = tl + Vector2i(rng.randi_range(0, CHUNK_SIZE - 1), rng.randi_range(0, CHUNK_SIZE - 1))
		var biome: int = _cell_biome_type(tile)
		if not _mob_allows_biome(data, biome):
			continue
		# Land mobs keep a shoreline buffer, same as the old Plains-only rule;
		# an ocean-eligible mob obviously needs to be allowed on water itself.
		if biome != -1 and _has_water_nearby(tile, 3):
			continue
		return tile
	return null

func _spawn_mob_at(tile: Vector2i, scene: PackedScene) -> void:
	var local_pos: Vector2 = ground_layer.map_to_local(tile)
	var world_pos: Vector2 = ground_layer.to_global(local_pos)
	var mob: Node2D = scene.instantiate() as Node2D
	if mob == null:
		return
	add_child(mob)
	mob.global_position = world_pos

# ── Periodic overworld spawner ───────────────────────────────────────
# A single unified check, cadence depending on time of day (Global.is_daytime)
# — every OUTER_SPAWN_INTERVAL_DAY by day, OUTER_SPAWN_INTERVAL_NIGHT by
# night. One-shot + self-rescheduled (rather than a fixed repeating Timer) so
# the interval adapts across a day/night crossing instead of being locked in
# at whatever it was when the Timer started.
func _start_outer_spawn_timer() -> void:
	var t := Timer.new()
	t.one_shot = true
	t.timeout.connect(_run_overworld_spawn.bind(t))
	add_child(t)
	t.start(OUTER_SPAWN_INTERVAL_DAY if Global.is_daytime else OUTER_SPAWN_INTERVAL_NIGHT)

# Every eligible outer chunk gets a spawn attempt each time this runs (not
# just one random chunk) — the timer's own day/night interval is what
# throttles frequency now, so there's no separate per-chunk cooldown to track.
func _run_overworld_spawn(t: Timer) -> void:
	var p := _get_player()
	var player_pos: Vector2 = p.global_position if p != null else Vector2.ZERO
	var spawn_pos:  Vector2 = _world_spawn_pos()

	var eligible: Array[Vector2i] = []
	for cx in range(_chunk_cols):
		for cy in range(_chunk_rows):
			var chunk := Vector2i(cx, cy)
			if _is_chunk_outer(chunk, player_pos, spawn_pos):
				eligible.append(chunk)

	for pool_entry in MOB_SPAWN_POOL:
		var data: MobCombatData = pool_entry["data"] as MobCombatData
		var eligible_now: bool = data.spawn_during_day if Global.is_daytime else data.spawn_during_night
		if not eligible_now:
			continue
		for chunk in eligible:
			var count: int = rng.randi_range(data.min_spawn, data.max_spawn)
			for _n in range(count):
				var tile = _random_valid_mob_tile_in_chunk(chunk, data)
				if tile == null:
					continue
				_spawn_mob_at(tile, pool_entry["scene"] as PackedScene)

	t.start(OUTER_SPAWN_INTERVAL_DAY if Global.is_daytime else OUTER_SPAWN_INTERVAL_NIGHT)

# ── Mob preservation (save/load) ─────────────────────────────────────
func _is_in_preserve_zone(pos: Vector2, player_pos: Vector2) -> bool:
	if pos.distance_to(player_pos) <= MOB_PRESERVE_PLAYER_RADIUS:
		return true
	return pos.distance_to(_world_spawn_pos()) <= MOB_PRESERVE_SPAWN_RADIUS

func _collect_preserved_mobs() -> Array:
	var mobs_data: Array = []
	var p := _get_player()
	var player_pos: Vector2 = p.global_position if p != null else Vector2.ZERO
	for mob in get_tree().get_nodes_in_group("Wolf"):
		if not is_instance_valid(mob):
			continue
		var m2d: Node2D = mob as Node2D
		if _is_in_preserve_zone(m2d.global_position, player_pos):
			mobs_data.append({"type": "wolf", "x": m2d.global_position.x, "y": m2d.global_position.y})
	return mobs_data

func _restore_mobs(mobs_data: Array) -> void:
	var p := _get_player()
	var player_pos: Vector2 = p.global_position if p != null else Vector2.ZERO

	# The save data is authoritative for these zones — remove the
	# deterministically-regenerated mobs that fall inside them first.
	for mob in get_tree().get_nodes_in_group("Wolf"):
		if not is_instance_valid(mob):
			continue
		var m2d: Node2D = mob as Node2D
		if _is_in_preserve_zone(m2d.global_position, player_pos):
			mob.queue_free()

	for entry in mobs_data:
		if not (entry is Dictionary):
			continue
		var e: Dictionary = entry as Dictionary
		if str(e.get("type", "")) != "wolf":
			continue
		var pos := Vector2(float(e.get("x", 0.0)), float(e.get("y", 0.0)))
		var wolf: Node2D = WOLF_SCENE.instantiate() as Node2D
		if wolf == null:
			continue
		add_child(wolf)
		wolf.global_position = pos

# ── Ghost preview ────────────────────────────────────────────────────
func _setup_ghost() -> void:
	ghost = Node2D.new()
	ghost.visible = false
	ghost.z_index = PLACEMENT_GUIDE_Z_INDEX
	add_child(ghost)
	ghost_sprite = Sprite2D.new()
	ghost_sprite.modulate = Color(1, 1, 1, 0.5)
	ghost.add_child(ghost_sprite)

func _setup_grid_overlay() -> void:
	_grid_overlay = Node2D.new()
	_grid_overlay.z_index = PLACEMENT_GUIDE_Z_INDEX
	_grid_overlay.visible = false
	editable_layer.add_child(_grid_overlay)
	_grid_overlay.draw.connect(_on_grid_draw)
	Global.block_mode_changed.connect(func(enabled: bool) -> void:
		_grid_overlay.visible = enabled
		if enabled:
			_grid_overlay.queue_redraw()
	)

func _on_grid_draw() -> void:
	var p: Node2D = _get_player()
	if p == null:
		return
	var player_tile: Vector2i = editable_layer.local_to_map(editable_layer.to_local(p.global_position))
	var half: float = TILE_SIZE * 0.5
	for dx in range(-PLACE_RADIUS_TILES, PLACE_RADIUS_TILES + 1):
		for dy in range(-PLACE_RADIUS_TILES, PLACE_RADIUS_TILES + 1):
			var cell: Vector2i = player_tile + Vector2i(dx, dy)
			if not _is_cell_in_place_radius(cell):
				continue
			if _placed_blocks.has(cell) or editable_layer.get_cell_source_id(cell) != -1:
				continue
			var cp: Vector2 = editable_layer.map_to_local(cell)
			var rect := Rect2(cp.x - half, cp.y - half, TILE_SIZE, TILE_SIZE)
			# Tree-occupied cells still show the grid (tinted red like a
			# player-blocked cell) instead of disappearing — forests are dense
			# enough that skipping the whole footprint blanked out most of the
			# grid near the player.
			var color: Color = Color(1.0, 0.2, 0.2, 0.55) \
				if (_cell_blocked_by_player(cell) or _is_tree_occupied(cell)) \
				else Color(1.0, 1.0, 1.0, 0.45)
			_grid_overlay.draw_rect(rect, color, false, 1.0)

# ── Chunk border debug overlay ────────────────────────────────────────
func _setup_chunk_border_overlay() -> void:
	_chunk_border_overlay = Node2D.new()
	_chunk_border_overlay.z_index = 400
	_chunk_border_overlay.visible = false
	add_child(_chunk_border_overlay)
	_chunk_border_overlay.draw.connect(_on_chunk_border_draw)

func toggle_chunk_borders() -> void:
	_show_chunk_borders = not _show_chunk_borders
	_chunk_border_overlay.visible = _show_chunk_borders
	if _show_chunk_borders:
		_chunk_border_overlay.queue_redraw()

func _on_chunk_border_draw() -> void:
	for cx in range(_chunk_cols):
		for cy in range(_chunk_rows):
			var r: Rect2 = _chunk_world_rect(Vector2i(cx, cy))
			var local_rect := Rect2(_chunk_border_overlay.to_local(r.position), r.size)
			_chunk_border_overlay.draw_rect(local_rect, CHUNK_BORDER_COLOR, false, 2.0)

# ── Hitbox debug overlay ─────────────────────────────────────────────
func _setup_hitbox_overlay() -> void:
	_hitbox_overlay = Node2D.new()
	# Above PLACEMENT_GUIDE_Z_INDEX (2000, used by the block-placement grid,
	# ghost preview, and cursor highlight) so hitboxes always render on top
	# of those instead of being hidden underneath while in block mode.
	_hitbox_overlay.z_index = PLACEMENT_GUIDE_Z_INDEX + 100
	_hitbox_overlay.visible = false
	add_child(_hitbox_overlay)
	_hitbox_overlay.draw.connect(_on_hitbox_draw)

func toggle_hitboxes() -> void:
	_show_hitboxes = not _show_hitboxes
	_hitbox_overlay.visible = _show_hitboxes
	if _show_hitboxes:
		_hitbox_overlay.queue_redraw()

# ── Glow / color grading ─────────────────────────────────────────────
# Same idea as cave_world.gd's WorldEnvironment (added there first — see its
# comment), but tuned very differently: the overworld's day_night_cycle.gd
# CanvasModulate already sits near full white (1,1,1) at noon, so reusing
# the cave's threshold (0.85) would make ordinary daylight bloom across the
# whole screen instead of just genuinely bright highlights. Pushed well
# above normal daylight brightness instead — with no torches/fire/emissive
# effects in the overworld yet, glow itself won't have much to catch until
# those exist, so the saturation/contrast bump is what actually reads as
# less flat right now; glow is future-proofing for when it does.
func _setup_glow_environment() -> void:
	var world_env := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_CANVAS
	env.glow_enabled       = true
	env.glow_intensity     = 0.7
	env.glow_strength      = 1.0
	env.glow_bloom         = 0.1
	env.glow_hdr_threshold = 1.25  # above normal (1,1,1) daylight — only real highlights bloom
	env.glow_blend_mode    = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	env.adjustment_enabled   = true
	env.adjustment_saturation = 1.12
	env.adjustment_contrast   = 1.05
	world_env.environment = env
	add_child(world_env)

# Camera-visible world rect (+ a small margin) — grass alone can be tens of
# thousands of tiles across the whole map, and this overlay redraws every
# frame while active, so drawing off-screen entries was the actual cost.
# Same technique as the (since-removed) grass animation LOD used.
func _debug_visible_world_rect() -> Rect2:
	var cam: Camera2D = get_viewport().get_camera_2d()
	if cam == null:
		return Rect2(Vector2(-1e6, -1e6), Vector2(2e6, 2e6))  # no camera — don't cull
	var margin: float = TILE_SIZE * 4.0
	var visible_size: Vector2 = get_viewport().get_visible_rect().size / cam.zoom
	var half: Vector2 = visible_size * 0.5 + Vector2(margin, margin)
	var center: Vector2 = cam.get_screen_center_position()
	return Rect2(center - half, half * 2.0)

func _on_hitbox_draw() -> void:
	var view_rect: Rect2 = _debug_visible_world_rect()
	for mob in get_tree().get_nodes_in_group("Wolf"):
		if is_instance_valid(mob) and view_rect.has_point((mob as Node2D).global_position):
			Global.draw_body_hitboxes(_hitbox_overlay, mob as Node, HITBOX_MOB_COLOR)
	for entry in _placed_blocks.values():
		var node: Node = (entry as Dictionary)["node"] as Node
		if is_instance_valid(node) and view_rect.has_point((node as Node2D).global_position):
			Global.draw_body_hitboxes(_hitbox_overlay, node, HITBOX_BLOCK_COLOR)
	# Grass tufts do have a real collision shape now (see grass.gd/Grass.tscn),
	# but this marker shows tile OCCUPANCY (_grass_occupied_tiles), which is
	# distinct info from the physical collision box — kept as-is.
	for tile in _grass_occupied_tiles.keys():
		_draw_grass_tile_outline(tile as Vector2i, view_rect)

# This marker tracks tile OCCUPANCY (_grass_occupied_tiles), not the tuft's
# actual physical collision shape (see Grass.tscn's StaticBody2D) — the two
# are deliberately different sizes/purposes, so this stays a discrete "does
# this exact tile have grass" marker rather than trying to match the real
# collision box. Two earlier rect-based attempts both misled: a tile-sized
# box (32x32 at the tile anchor) left its bottom half always
# empty, because the sprite is base-anchored AT that point and only extends
# UPWARD from it (see _spawn_grass_at) — the visible blades actually poke
# into the neighboring tile's box above. A sprite-bounds-sized box fixed
# that but, at 2.7-tile-wide sprites and 15-20% tile coverage, constantly
# overlapped neighbors and included the source art's own transparent frame
# padding. Neither reads as clean at this density. A small fixed marker at
# the tile's true anchor point — exactly where every tuft's roots sit —
# sidesteps all three problems: nothing to resize, nothing to overlap.
func _draw_grass_tile_outline(tile: Vector2i, view_rect: Rect2) -> void:
	var local_pos: Vector2 = ground_layer.map_to_local(tile)
	# Must match _spawn_grass_at's ground_anchor exactly (tile center +
	# TILE_SIZE * 0.5 + GrassTuft.BASE_EXTRA_OFFSET_PX), not the raw tile center
	# — otherwise this marker drifts from wherever the sprite actually anchors.
	var tile_center:   Vector2 = ground_layer.to_global(local_pos)
	var ground_anchor: Vector2 = tile_center + Vector2(0.0, TILE_SIZE * 0.5 + GrassTuft.BASE_EXTRA_OFFSET_PX)
	if not view_rect.has_point(ground_anchor):
		return
	var center: Vector2 = _hitbox_overlay.to_local(ground_anchor)
	var r: float = GRASS_MARKER_RADIUS
	_hitbox_overlay.draw_arc(center, r, 0.0, TAU, 10, HITBOX_GRASS_COLOR, 2.0)
	_hitbox_overlay.draw_line(center + Vector2(-r - 3.0, 0.0), center + Vector2(r + 3.0, 0.0), HITBOX_GRASS_COLOR, 1.5)
	_hitbox_overlay.draw_line(center + Vector2(0.0, -r - 3.0), center + Vector2(0.0, r + 3.0), HITBOX_GRASS_COLOR, 1.5)

func _setup_cursor_highlight() -> void:
	_cursor_highlight = Node2D.new()
	_cursor_highlight.z_index = PLACEMENT_GUIDE_Z_INDEX
	_cursor_highlight.visible = false
	_cursor_highlight.draw.connect(func() -> void:
		var half: float = TILE_SIZE * 0.5
		_cursor_highlight.draw_rect(
			Rect2(-half, -half, TILE_SIZE, TILE_SIZE),
			Color(1.0, 1.0, 1.0, 0.28), true)
	)
	add_child(_cursor_highlight)
	_cursor_highlight.queue_redraw()

func _update_cursor_highlight() -> void:
	if _cursor_highlight == null or Global.block_mode:
		if _cursor_highlight != null:
			_cursor_highlight.visible = false
		return
	var mouse_local: Vector2  = ground_layer.get_local_mouse_position()
	var cell:        Vector2i = ground_layer.local_to_map(mouse_local)
	var snapped:     Vector2  = ground_layer.map_to_local(cell)
	_cursor_highlight.global_position = ground_layer.to_global(snapped)
	_cursor_highlight.visible = true

func _update_hover() -> void:
	if Global.block_mode:
		Global.set_hover("")
		return
	var mouse_pos: Vector2 = get_global_mouse_position()
	var best_name: String  = ""
	var best_dist: float   = INTERACT_RADIUS_PX
	for entry in _placed_blocks.values():
		var node: Node2D = (entry as Dictionary)["node"] as Node2D
		if not is_instance_valid(node):
			continue
		var dist: float = mouse_pos.distance_to(node.global_position)
		if dist < best_dist:
			best_dist = dist
			best_name = (entry as Dictionary)["name"]
	Global.set_hover(best_name)

func _is_placeable_item(item) -> bool:
	if item == null or not (item is Dictionary) or not item.has("data"):
		return false
	return (item["data"] as ItemData).is_placeable

func _update_ghost() -> void:
	if not Global.block_mode:
		ghost.visible = false
		return
	var item = Global.get_hotbar_item()
	if not _is_placeable_item(item):
		ghost.visible = false
		return
	var item_key: String = (item["data"] as ItemData).item_name
	if item_key != ghost_last_type:
		ghost_last_type = item_key
		_rebuild_ghost_sprite(item)
	var mouse_local: Vector2  = editable_layer.get_local_mouse_position()
	var cell:        Vector2i = editable_layer.local_to_map(mouse_local)
	var world_pos:   Vector2  = editable_layer.map_to_local(cell)
	ghost.global_position = editable_layer.to_global(world_pos)
	if not _is_cell_in_place_radius(cell):
		ghost.visible = false
		return
	ghost.visible = true
	var occupied:    bool = _placed_blocks.has(cell) or editable_layer.get_cell_source_id(cell) != -1 \
		or _is_tree_occupied(cell)
	var on_water:    bool = water_layer.get_cell_source_id(cell) != -1
	var player_here: bool = _cell_blocked_by_player(cell)
	ghost_sprite.modulate = Color(1.0, 0.3, 0.3, 0.5) if (occupied or on_water or player_here) \
		else Color(1.0, 1.0, 1.0, 0.5)

func _rebuild_ghost_sprite(item: Dictionary) -> void:
	var data: ItemData = item["data"] as ItemData
	var tex: Texture2D = data.placeable_sprite if data.placeable_sprite != null else data.icon
	ghost_sprite.texture  = tex
	ghost_sprite.hframes  = 1
	ghost_sprite.vframes  = 1
	ghost_sprite.frame    = 0
	ghost_sprite.position = Vector2.ZERO

func _on_hotbar_changed(_idx = 0) -> void:
	_update_ghost()

# ── Block placement ───────────────────────────────────────────────────
func place_block() -> void:
	var item = Global.get_hotbar_item()
	if not _is_placeable_item(item):
		return
	var mouse_pos := editable_layer.get_local_mouse_position()
	var cell      := editable_layer.local_to_map(mouse_pos)
	if not _is_cell_in_place_radius(cell):
		return
	if _cell_blocked_by_player(cell):
		return
	if _placed_blocks.has(cell) or editable_layer.get_cell_source_id(cell) != -1:
		return
	if _is_tree_occupied(cell):
		return
	if water_layer.get_cell_source_id(cell) != -1:
		return
	var world_pos  := editable_layer.map_to_local(cell)
	var item_data: ItemData = item["data"] as ItemData
	if item_data == null or item_data.place_scene_path == "":
		return
	if not ResourceLoader.exists(item_data.place_scene_path):
		return
	var obj_scene: PackedScene = load(item_data.place_scene_path)
	if obj_scene == null:
		return
	var obj: Node = obj_scene.instantiate()
	if obj == null:
		return
	if obj.has_method("setup"):
		obj.call("setup", item_data)
	_placed_blocks[cell] = {"node": obj, "name": item_data.item_name}
	if obj.has_method("set_world_cell"):
		obj.call("set_world_cell", cell, self)
	# Parented to World directly, NOT editable_layer (a TileMapLayer meant
	# for painted tile cells) — mixing dynamic gameplay nodes into a
	# TileMapLayer's children is the likely reason placed blocks sorted
	# incorrectly against the player/grass/trees, which all live directly
	# under World.
	add_child(obj)
	if not is_instance_valid(obj):
		_placed_blocks.erase(cell)
		return
	obj.position = world_pos
	obj.z_index  = int(world_pos.y / TILE_SIZE)
	_fix_sprite_offset(obj)
	if item_data.has_place_animation and item_data.place_animation_name != "":
		var ap: AnimationPlayer = obj.get_node_or_null("AnimationPlayer") as AnimationPlayer
		if ap != null:
			ap.play(item_data.place_animation_name)
	Global.remove_item(item_data)

func unregister_block(cell: Vector2i) -> void:
	_placed_blocks.erase(cell)

func _is_cell_in_place_radius(cell: Vector2i) -> bool:
	var p: Node2D = _get_player()
	if p == null:
		return true
	var cell_local:   Vector2 = editable_layer.map_to_local(cell)
	var player_local: Vector2 = editable_layer.to_local(p.global_position)
	return player_local.distance_to(cell_local) <= PLACE_RADIUS_TILES * TILE_SIZE

func _cell_blocked_by_player(cell: Vector2i) -> bool:
	var p: Node2D = _get_player()
	if p == null:
		return false
	# Base collision dims scaled by the player sprite scale (0.980) so the
	# restricted build zone matches the player's visual footprint.
	const S: float = 0.980
	var half_w: float = 10.0 * S + 8.0
	var half_h: float = 16.5 * S + 8.0
	var player_local: Vector2 = editable_layer.to_local(p.global_position) + Vector2(0.0, 6.5 * S)
	var tl: Vector2i = editable_layer.local_to_map(player_local + Vector2(-half_w, -half_h))
	var br: Vector2i = editable_layer.local_to_map(player_local + Vector2( half_w,  half_h))
	return cell.x >= mini(tl.x, br.x) and cell.x <= maxi(tl.x, br.x) \
		and cell.y >= mini(tl.y, br.y) and cell.y <= maxi(tl.y, br.y)

func _fix_sprite_offset(obj: Node) -> void:
	var sprite: Node = obj.get_node_or_null("Sprite2D")
	if sprite == null:
		sprite = obj.get_node_or_null("AnimatedSprite2D")
	if sprite == null:
		return
	var frame_height := 0.0
	if sprite is Sprite2D and (sprite as Sprite2D).texture != null:
		frame_height = (sprite as Sprite2D).texture.get_height() / max((sprite as Sprite2D).vframes, 1)
	elif sprite is AnimatedSprite2D and (sprite as AnimatedSprite2D).sprite_frames != null:
		var frames: SpriteFrames = (sprite as AnimatedSprite2D).sprite_frames
		var anim: StringName     = (sprite as AnimatedSprite2D).animation
		if frames.has_animation(anim) and frames.get_frame_count(anim) > 0:
			var tex: Texture2D = frames.get_frame_texture(anim, 0)
			if tex != null:
				frame_height = tex.get_height()
	if frame_height > 0.0:
		sprite.position = Vector2(0.0, (TILE_SIZE / 2.0) - (frame_height / 2.0))

func _get_player() -> Node2D:
	if player != null:
		return player as Node2D
	return Global.player_node as Node2D

func spawn_player() -> void:
	player.position = Vector2(spawn_center)

# ── Experimental ground ──────────────────────────────────────────────
# Spritesheet layout (128×64 px, 4 cols × 2 rows of 32×32):
#   Row 0, cols 0-3  → four plains / grass variants
#   Row 1, col 0     → snow (light grey)
#   Row 1, col 1     → desert (tan / sand)
#   Row 1, cols 2-3  → ocean-coloured tiles (not assigned to any biome)
func _apply_experimental_ground() -> void:
	var tex := load("res://sprites/ground/EXPERIMENTALGROUND.webp") as Texture2D
	if tex == null:
		push_warning("EXPERIMENTALGROUND.webp not found — falling back to original tileset")
		return
	var img_w: int    = tex.get_width()
	var img_h: int    = tex.get_height()
	var num_cols: int = img_w / 32
	var num_rows: int = img_h / 32
	if num_cols < 1 or num_rows < 1:
		push_warning("EXPERIMENTALGROUND.webp too small — falling back to original tileset")
		return
	var src := TileSetAtlasSource.new()
	src.texture             = tex
	src.texture_region_size = Vector2i(32, 32)
	for col in range(num_cols):
		src.create_tile(Vector2i(col, 0))
	if num_rows >= 2:
		for col in range(num_cols):
			src.create_tile(Vector2i(col, 1))
	_exp_ground_src  = ground_layer.tile_set.add_source(src)
	_exp_ground_cols = num_cols
	_exp_ground_rows = num_rows

# Returns 0=Plain, 1=Desert, 2=Snowy, -1=Water/none
func _cell_biome_type(tile_coord: Vector2i) -> int:
	var src: int = ground_layer.get_cell_source_id(tile_coord)
	if src == -1:
		return -1
	var a: Vector2i = ground_layer.get_cell_atlas_coords(tile_coord)
	if src == _exp_ground_src:
		if a.y == 0: return 0
		if a.y == 1:
			if a.x == 0: return 2  # snow
			if a.x == 1: return 1  # desert
		return -1
	if a == Vector2i(0, 0): return 0
	if a == Vector2i(1, 0): return 1
	if a == Vector2i(1, 1): return 2
	return -1

# Public: true if the given world position sits on snowy terrain — used by
# weather effects (e.g. the player-attached snowfall particles).
# NOTE: _cell_biome_type()'s return codes (0=Plain,1=Desert,2=Snowy,-1=Water)
# are its own numbering, NOT the Terrain enum above (Water=0,Plain=1,
# Desert=2,Snowy=3) — comparing against Terrain.Snowy here would be wrong.
func is_snow_biome_at(world_pos: Vector2) -> bool:
	var tile: Vector2i = ground_layer.local_to_map(ground_layer.to_local(world_pos))
	return _cell_biome_type(tile) == 2

# ── Terrain Generation ───────────────────────────────────────────────
func _generate_terrain() -> void:
	var cell_offset := Vector2i(width, height) / 2

	# Pre-compute biome column lists once — rebuilding these inside the
	# 262K-iteration loop was allocating a new Array on every desert/snowy tile.
	var desert_cols: Array[int] = []
	var snow_cols:   Array[int] = []
	if use_experimental_ground and _exp_ground_src != -1 and _exp_ground_rows >= 2:
		# Col 0 = snow, col 1 = desert; cols 2-3 are ocean-coloured — skip them.
		snow_cols.append(0)
		desert_cols.append(1 if _exp_ground_cols >= 2 else 0)

	var use_exp: bool = use_experimental_ground and _exp_ground_src != -1
	for x in width:
		for y in height:
			var cell := Vector2i(x, y)
			var dist := cell.distance_to(cell_offset)
			var psc  := clampf(1.0 - dist / FORCED_PLAINS_RADIUS, 0.0, 1.0)
			var wc   := smoothstep(width / 2 - 50, width / 2, dist)
			var humid := humidity.get_noise_2d(x, y)    * 0.5 + 0.5
			var temp  := temperature.get_noise_2d(x, y) * 0.5 + 0.5
			var alt   := altitude.get_noise_2d(x, y)    * 0.5 + 0.5 + psc * WATER_THRESHOLD

			alt   = 0.0 if wc >= 1.0 else alt - wc * WATER_THRESHOLD
			humid += temp * psc
			temp  += SNOW_THRESHOLD * psc
			humid += (SNOW_THRESHOLD - SAND_THRESHOLD) * psc

			var t := _get_tile_type(humid, temp, alt)
			var c := cell - cell_offset
			if use_exp:
				match t:
					Terrain.Plain:
						ground_layer.set_cell(c, _exp_ground_src, Vector2i(rng.randi() % _exp_ground_cols, 0))
					Terrain.Desert:
						if _exp_ground_rows >= 2:
							ground_layer.set_cell(c, _exp_ground_src, Vector2i(desert_cols[rng.randi() % desert_cols.size()], 1))
						else:
							ground_layer.set_cell(c, 0, Vector2i(1, 0))
					Terrain.Snowy:
						if _exp_ground_rows >= 2:
							ground_layer.set_cell(c, _exp_ground_src, Vector2i(snow_cols[rng.randi() % snow_cols.size()], 1))
						else:
							ground_layer.set_cell(c, 0, Vector2i(1, 1))
					_:
						water_layer.set_cell(c, 0, Vector2i(0, 1))
			else:
				match t:
					Terrain.Plain:
						ground_layer.set_cell(c, 0, Vector2i(0, 0))
					Terrain.Desert:
						ground_layer.set_cell(c, 0, Vector2i(1, 0))
					Terrain.Snowy:
						ground_layer.set_cell(c, 0, Vector2i(1, 1))
					_:
						water_layer.set_cell(c, 0, Vector2i(0, 1))

func _set_up_noise(noise: FastNoiseLite, frequency: float, type: FastNoiseLite.FractalType = FastNoiseLite.FractalType.FRACTAL_FBM) -> void:
	noise.fractal_type = type
	noise.seed        = rng.randi()
	noise.frequency   = frequency

func _get_tile_type(hum: float, temp: float, alt: float) -> Terrain:
	if alt < WATER_THRESHOLD:
		return Terrain.Water
	if temp < SNOW_THRESHOLD:
		return Terrain.Snowy
	if temp - hum > SAND_THRESHOLD:
		return Terrain.Desert
	return Terrain.Plain

# ── Foliage ──────────────────────────────────────────────────────────

func _mark_tree_tile(tile: Vector2i, occupied: Dictionary) -> void:
	for dx in range(-1, 2):
		for dy in range(-1, 2):
			occupied[tile + Vector2i(dx, dy)] = true

# ── Live tree occupancy (blocks placement near a standing tree) ─────
func _mark_tree_occupied(cell: Vector2i) -> void:
	for dx in range(-TREE_PLACE_BLOCK_RADIUS, TREE_PLACE_BLOCK_RADIUS + 1):
		for dy in range(-TREE_PLACE_BLOCK_RADIUS, TREE_PLACE_BLOCK_RADIUS + 1):
			var t: Vector2i = cell + Vector2i(dx, dy)
			_tree_occupied_tiles[t] = int(_tree_occupied_tiles.get(t, 0)) + 1

func _unmark_tree_occupied(cell: Vector2i) -> void:
	for dx in range(-TREE_PLACE_BLOCK_RADIUS, TREE_PLACE_BLOCK_RADIUS + 1):
		for dy in range(-TREE_PLACE_BLOCK_RADIUS, TREE_PLACE_BLOCK_RADIUS + 1):
			var t: Vector2i = cell + Vector2i(dx, dy)
			if not _tree_occupied_tiles.has(t):
				continue
			var remaining: int = int(_tree_occupied_tiles[t]) - 1
			if remaining <= 0:
				_tree_occupied_tiles.erase(t)
			else:
				_tree_occupied_tiles[t] = remaining

func _is_tree_occupied(cell: Vector2i) -> bool:
	return _tree_occupied_tiles.has(cell)

# ── Grass ─────────────────────────────────────────────────────────────
# Per-tuft look/sizing/material now lives in scripts/grass.gd (GrassTuft) —
# world.gd only decides which tiles get grass and instantiates GRASS_SCENE.
func _is_valid_grass_tile(tile: Vector2i) -> bool:
	if _grass_occupied_tiles.has(tile):
		return false
	if _cell_biome_type(tile) != 0:  # Plains only
		return false
	if _is_tree_occupied(tile):
		return false
	if _placed_blocks.has(tile):
		return false
	if editable_layer.get_cell_source_id(tile) != -1:
		return false
	if water_layer.get_cell_source_id(tile) != -1:
		return false
	return true

func _spawn_grass_at(tile: Vector2i) -> void:
	# _fill_all_chunks_with_grass()'s background coroutine (await
	# get_tree().process_frame) keeps resuming even after this World node is
	# removed from the tree — enter_cave()/exit_cave() do that with
	# remove_child(), not queue_free(), specifically so the overworld
	# survives the round trip, but an in-flight await doesn't know or care
	# about that. If it resumes while off-tree, add_child(tuft) below no
	# longer puts tuft in the tree either (a node's children aren't in the
	# tree until the node itself is), so tuft's @onready vars (grass.gd's
	# _sprite) never resolve — crashes as a null-instance property set the
	# moment setup() touches _sprite. Bail out here rather than spawn
	# anything while off-tree.
	if not is_inside_tree():
		return
	# Grass now fills in over several frames in the BACKGROUND, after the
	# player is already free to move (see _deferred_foliage) — unlike before,
	# it's possible for a tuft to be about to spawn on the exact tile the
	# player is currently standing on. Since tufts carry solid collision now,
	# that would shove the player the instant it's added. Skip it (don't mark
	# the tile occupied either) rather than spawn on top of them — it'll
	# naturally get filled in by the next _regrow_grass pass instead.
	var p: Node2D = _get_player()
	if p != null:
		var player_tile: Vector2i = ground_layer.local_to_map(ground_layer.to_local(p.global_position))
		if player_tile == tile:
			return
	var local_pos: Vector2 = ground_layer.map_to_local(tile)
	# map_to_local() returns the tile's CENTER, not its bottom edge. _spawn_tree
	# gets this right: it adds TILE_SIZE*0.5 to reach the tile's bottom grid
	# line before anchoring anything to it — mirrored here, plus a small
	# empirical nudge (GrassTuft.BASE_EXTRA_OFFSET_PX).
	var tile_center:   Vector2 = ground_layer.to_global(local_pos)
	var ground_anchor: Vector2 = tile_center + Vector2(0.0, TILE_SIZE * 0.5 + GrassTuft.BASE_EXTRA_OFFSET_PX)

	var tuft: GrassTuft = GRASS_SCENE.instantiate() as GrassTuft
	if tuft == null:
		return
	add_child(tuft)
	tuft.setup(rng, ground_anchor, tile)

	# Stores the tuft node itself (not just a bool) — _try_cut_grass_with_sword
	# needs the actual node to drive the cut, and every other read site
	# (.has()/.erase()/.keys()) doesn't care about the value.
	_grass_occupied_tiles[tile] = tuft
	_grass_spawn_count += 1

# Seeded Fisher-Yates shuffle (Array.shuffle() uses the global RNG, which
# would break world-gen determinism from `random_seed`).
func _shuffle_tiles(arr: Array) -> void:
	for i in range(arr.size() - 1, 0, -1):
		var j: int = rng.randi_range(0, i)
		var tmp: Vector2i = arr[i]
		arr[i] = arr[j]
		arr[j] = tmp

# Grows an irregular patch of `target` tiles outward from a random seed via
# randomized flood-fill — each step picks a random tile off the growth
# frontier (not always the newest one) and a random direction off it, so the
# resulting shape is a ragged, organic blob rather than a smooth disc. A pure
# nearest-neighbor-to-a-point sort (the previous approach) always produces
# the same circular silhouette regardless of seed, just at different sizes/
# positions — every group reading as "the same pattern" was that shape
# repeating, not a variety problem. This grows a genuinely different outline
# each call since growth order itself is randomized.
# Moves the grown tiles to the front of `arr`; if the flood-fill runs out of
# reachable neighbors before hitting `target` (possible near sparse/broken-up
# eligible regions), tops up with whatever other eligible tiles remain so the
# chunk still reaches its coverage target.
func _cluster_tiles(arr: Array, target: int) -> void:
	if arr.is_empty() or target <= 0:
		return
	var seed_tile: Vector2i = arr[rng.randi_range(0, arr.size() - 1)] as Vector2i
	var eligible_set: Dictionary = {}
	for t in arr:
		eligible_set[t] = true

	var cluster:  Array      = [seed_tile]
	var claimed:  Dictionary = {seed_tile: true}
	var frontier: Array      = [seed_tile]
	var dirs: Array = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]

	while cluster.size() < target and not frontier.is_empty():
		var f_idx: int = rng.randi_range(0, frontier.size() - 1)
		var from_tile: Vector2i = frontier[f_idx] as Vector2i
		_shuffle_tiles(dirs)
		var grew: bool = false
		for d in dirs:
			var n: Vector2i = from_tile + (d as Vector2i)
			if eligible_set.has(n) and not claimed.has(n):
				claimed[n] = true
				cluster.append(n)
				frontier.append(n)
				grew = true
				break
		if not grew:
			frontier.remove_at(f_idx)

	if cluster.size() < target:
		for t in arr:
			if cluster.size() >= target:
				break
			if not claimed.has(t):
				claimed[t] = true
				cluster.append(t)

	for i in range(cluster.size()):
		arr[i] = cluster[i]

# Fills a chunk with grass up to a random GRASS_CHUNK_COVERAGE_MIN..MAX
# fraction (per-chunk, so coverage varies chunk to chunk) of its
# currently-eligible plains tiles. Which tiles get picked depends on
# GRASS_GROUPED_CHANCE: usually (70%) one irregular grown patch, otherwise
# spread uniformly across the whole chunk. Idempotent — already-grass tiles
# are excluded by _is_valid_grass_tile, so calling this again only tops up
# whatever's still missing from that chunk's own target.
func _fill_chunk_grass(chunk: Vector2i) -> void:
	if _cave_claimed_chunks.has(chunk):
		return
	var half_w: int = width  / 2
	var half_h: int = height / 2
	var tl := Vector2i(chunk.x * CHUNK_SIZE - half_w, chunk.y * CHUNK_SIZE - half_h)

	# Plains-only — _is_valid_grass_tile rejects Desert/Snowy/Water outright.
	var eligible: Array = []
	for dx in range(CHUNK_SIZE):
		for dy in range(CHUNK_SIZE):
			var tile: Vector2i = tl + Vector2i(dx, dy)
			if _is_valid_grass_tile(tile):
				eligible.append(tile)
	if eligible.is_empty():
		return

	var coverage: float = rng.randf_range(GRASS_CHUNK_COVERAGE_MIN, GRASS_CHUNK_COVERAGE_MAX)
	var target:   int   = mini(ceili(eligible.size() * coverage), eligible.size())

	if rng.randf() < GRASS_GROUPED_CHANCE:
		_cluster_tiles(eligible, target)
	else:
		_shuffle_tiles(eligible)
	for i in range(target):
		_spawn_grass_at(eligible[i] as Vector2i)

# Spread across many frames (GRASS_CHUNKS_PER_FRAME chunks at a time, then
# yield) instead of one long synchronous burst — called fire-and-forget
# after generation_complete has already fired (see _deferred_foliage), so
# this running in the background doesn't block or hitch anything the player
# is doing. Contains an await, so GDScript treats it as a coroutine
# automatically; callers that don't need to wait for full completion (the
# normal case) just call it without awaiting.
func _fill_all_chunks_with_grass() -> void:
	var t0: int = Time.get_ticks_msec()
	var processed: int = 0
	for cx in range(_chunk_cols):
		for cy in range(_chunk_rows):
			_fill_chunk_grass(Vector2i(cx, cy))
			processed += 1
			if processed % GRASS_CHUNKS_PER_FRAME == 0:
				await get_tree().process_frame
				# This await resumes on the SceneTree's own signal, which
				# fires every frame regardless of whether World is still in
				# the tree — a cave visit (enter_cave() removes World via
				# remove_child(), not queue_free()) doesn't pause it the way
				# a Timer would. Stop rather than keep grinding through the
				# rest of the map off-tree (each call would now just no-op
				# via _spawn_grass_at's own guard, but there's no point
				# continuing); _regrow_grass will top the rest up later once
				# World is back in the tree.
				if not is_inside_tree():
					return
	print("[GRASS] spawned %d tufts in %dms (background-filled after load)" % [_grass_spawn_count, Time.get_ticks_msec() - t0])

# ── Grass regrowth — every 10 minutes, per chunk ────────────────────────
func _start_grass_regrow_timer() -> void:
	var t := Timer.new()
	t.wait_time = GRASS_REGROW_INTERVAL
	t.autostart = true
	t.timeout.connect(_regrow_grass)
	add_child(t)

func _tile_to_chunk(tile: Vector2i) -> Vector2i:
	var half_w: int = width  / 2
	var half_h: int = height / 2
	return Vector2i(floori(float(tile.x + half_w) / CHUNK_SIZE), floori(float(tile.y + half_h) / CHUNK_SIZE))

# A chunk containing any placed block OR a Lua robot (both live in
# _placed_blocks — a robot is just a placeable item like any other block)
# is skipped entirely: a "developed" chunk shouldn't spontaneously regrow.
# Everything else gets topped back up toward its target coverage — a no-op
# if it's already there, since _fill_chunk_grass only fills what's missing.
func _regrow_grass() -> void:
	var occupied_chunks: Dictionary = {}
	for cell in _placed_blocks:
		occupied_chunks[_tile_to_chunk(cell as Vector2i)] = true

	for cx in range(_chunk_cols):
		for cy in range(_chunk_rows):
			var chunk := Vector2i(cx, cy)
			if occupied_chunks.has(chunk):
				continue
			_fill_chunk_grass(chunk)

func _place_foliage() -> void:
	var cell_offset: Vector2i = Vector2i(width, height) / 2
	var occupied_tiles: Dictionary = {}

	# ── 1. Large forests (plains and snowy only) ──
	var t0 := Time.get_ticks_msec()
	var forest_centers: Array[Vector2i] = _generate_forest_centers()
	print("[FORESTS] %d centers found in %dms" % [forest_centers.size(), Time.get_ticks_msec() - t0])
	var t1 := Time.get_ticks_msec()
	var forest_tree_start := _tree_spawn_count
	for fc: Vector2i in forest_centers:
		_spawn_dense_forest(fc, occupied_tiles)
	print("[FORESTS] spawned %d trees in %dms" % [_tree_spawn_count - forest_tree_start, Time.get_ticks_msec() - t1])

	# ── 2. Scattered trees via Poisson disk sampling ──
	var t2 := Time.get_ticks_msec()
	var points: PackedVector2Array = _generate_points()
	print("[POISSON] %d sample points in %dms" % [points.size(), Time.get_ticks_msec() - t2])
	var t3 := Time.get_ticks_msec()
	var scatter_tree_start := _tree_spawn_count
	for point in points:
		var int_point:  Vector2i = Vector2i(point)
		var tile_coord: Vector2i = int_point - cell_offset
		var biome: int           = _cell_biome_type(tile_coord)

		var tree_type_val: int
		if biome == 0:
			tree_type_val = 0  # Plain → becomes NewTree inside _spawn_tree
		elif biome == 2:
			tree_type_val = 2  # Snowy
		else:
			continue           # Desert or water — no trees

		if occupied_tiles.has(tile_coord):
			continue
		if tile_coord.distance_to(Vector2i.ZERO) <= SPAWN_CLEAR_TILES:
			continue
		if _has_water_nearby(tile_coord, 3):
			continue
		if _is_chunk_cave_claimed(tile_coord):
			continue
		_mark_tree_tile(tile_coord, occupied_tiles)

		var local_pos: Vector2 = ground_layer.map_to_local(tile_coord)
		var world_pos: Vector2 = ground_layer.to_global(local_pos)
		_spawn_tree(world_pos, tree_type_val)
		# 0–3 extra trees per point (was 0–9 — reduced to cut spawn count)
		_spawn_scattered_group(tile_coord, tree_type_val, rng.randi_range(0, 3), occupied_tiles)
	print("[SCATTER] spawned %d trees in %dms" % [_tree_spawn_count - scatter_tree_start, Time.get_ticks_msec() - t3])

func _has_water_nearby(tile: Vector2i, radius: int) -> bool:
	var r_sq: int = radius * radius
	for dx in range(-radius, radius + 1):
		for dy in range(-radius, radius + 1):
			if dx * dx + dy * dy > r_sq:
				continue
			if water_layer.get_cell_source_id(tile + Vector2i(dx, dy)) != -1:
				return true
	return false

func _generate_forest_centers() -> Array[Vector2i]:
	var centers: Array[Vector2i] = []
	var target:  int = rng.randi_range(LARGE_FOREST_COUNT_MIN, LARGE_FOREST_COUNT_MAX)
	var half_w:  int = width  / 2
	var half_h:  int = height / 2
	var margin:  int = LARGE_FOREST_R_MAX + 20

	for _attempt in range(LARGE_FOREST_ATTEMPTS):
		if centers.size() >= target:
			break
		var tx:   int      = rng.randi_range(-half_w + margin, half_w - margin)
		var ty:   int      = rng.randi_range(-half_h + margin, half_h - margin)
		var tile: Vector2i = Vector2i(tx, ty)

		var biome_fc: int = _cell_biome_type(tile)
		if biome_fc != 0 and biome_fc != 2:
			continue
		if _has_water_nearby(tile, LARGE_FOREST_R_MAX + 10):
			continue
		if tile.distance_to(Vector2i.ZERO) < SPAWN_CLEAR_TILES + LARGE_FOREST_R_MAX:
			continue
		if _is_chunk_cave_claimed(tile):
			continue

		var too_close: bool = false
		for c: Vector2i in centers:
			if tile.distance_to(c) < LARGE_FOREST_MIN_SEP:
				too_close = true
				break
		if too_close:
			continue

		centers.append(tile)
	return centers

func _spawn_dense_forest(center: Vector2i, occupied_tiles: Dictionary) -> void:
	var center_biome: int = _cell_biome_type(center)
	if center_biome == -1:
		return
	var tree_type_val: int = 0 if center_biome == 0 else 2
	var radius: int        = rng.randi_range(LARGE_FOREST_R_MIN, LARGE_FOREST_R_MAX)
	var r_sq: float        = float(radius * radius)

	for dx in range(-radius, radius + 1):
		for dy in range(-radius, radius + 1):
			var dist_sq: float = float(dx * dx + dy * dy)
			if dist_sq > r_sq:
				continue
			var tile: Vector2i = center + Vector2i(dx, dy)
			if occupied_tiles.has(tile):
				continue
			if tile.distance_to(Vector2i.ZERO) <= SPAWN_CLEAR_TILES:
				continue
			if _cell_biome_type(tile) != center_biome:
				continue
			if _has_water_nearby(tile, 10):
				continue
			if _is_chunk_cave_claimed(tile):
				continue
			var prob: float = lerp(LARGE_FOREST_D_CENTER, LARGE_FOREST_D_EDGE,
				sqrt(dist_sq) / float(radius))
			if rng.randf() > prob:
				continue
			_mark_tree_tile(tile, occupied_tiles)
			var local_pos: Vector2 = ground_layer.map_to_local(tile)
			var world_pos: Vector2 = ground_layer.to_global(local_pos)
			_spawn_tree(world_pos, tree_type_val)

func _spawn_tree(world_pos: Vector2, tree_type_val: int) -> void:
	if tree_type_val == 0 and rng.randf() < NEW_TREE_CHANCE:
		tree_type_val = 3  # NewTree sprite for all plain trees
	var tree: Node2D = TREE_SCENE.instantiate() as Node2D
	if tree == null:
		return
	_tree_spawn_count += 1

	# Every tree — regardless of biome — uses the default overworld tree sprite,
	# so they all render (and cast the same shadow) identically for now.
	var sprite := tree.get_node_or_null("Sprite2D") as Sprite2D
	var frame_w: float = 32.0
	var frame_h: float = 32.0
	if sprite != null:
		sprite.texture  = NEW_TREE_TEX
		sprite.modulate = Color(1, 1, 1, 1)
		sprite.hframes  = 1
		sprite.vframes  = 1
		sprite.frame    = 0
		if sprite.texture != null:
			sprite.position.y = -(sprite.texture.get_height() * 0.5)
			frame_w = sprite.texture.get_width()  / float(maxi(sprite.hframes, 1))
			frame_h = sprite.texture.get_height() / float(maxi(sprite.vframes, 1))

	# Flat blob shadow sprite at the tree's base — replaces the old
	# per-pixel drop_shadow.gdshader silhouette approach. Scaled off the
	# tree's own frame size, which is now the same for every tree.
	var shadow_scale := Vector2(
		(frame_w * 0.55) / SHADOW_TEXTURE.get_width(),
		(frame_h * 0.22) / SHADOW_TEXTURE.get_height()
	)
	tree.add_child(Global.make_shadow_sprite(SHADOW_TEXTURE, Vector2(0.0, TREE_SHADOW_OFFSET_Y), shadow_scale, 0.35))

	# Disable Area2D monitoring before entering the scene tree.
	# Without this, every add_child triggers an O(n) broadphase scan against all
	# existing physics bodies, making bulk spawn O(n²). Monitoring is re-enabled
	# lazily by _update_tree_interactions once the world is loaded.
	var interact := tree.get_node_or_null("InteractArea") as Area2D
	if interact != null:
		interact.monitoring  = false
		interact.monitorable = false

	tree.set("tree_type", tree_type_val)
	add_child(tree)
	tree.scale         = Vector2(1.15, 1.15)
	# world_pos is the tile's center; the sprite's own -(height/2) offset means
	# the tree's local origin (this anchor point) IS the trunk's visual base
	# regardless of tree.scale, so +half a tile lands it exactly on the tile's
	# bottom grid line. TREE_BASE_EXTRA_OFFSET_PX is an extra empirical nudge
	# on top of that — the source art may have a little transparent padding
	# under the trunk that the exact math can't account for.
	tree.global_position = world_pos + Vector2(0.0, TILE_SIZE * 0.5 + TREE_BASE_EXTRA_OFFSET_PX)
	tree.z_index = int(tree.global_position.y / TILE_SIZE)

	# Block placement can't see trees (they're not on editable_layer or in
	# _placed_blocks), so track a 3x3 footprint here to stop blocks being
	# placed on top of / right next to a live tree.
	var tree_cell: Vector2i = editable_layer.local_to_map(editable_layer.to_local(world_pos))
	_mark_tree_occupied(tree_cell)
	tree.set_meta("spawn_cell", tree_cell)

func _spawn_scattered_group(origin: Vector2i, tree_type_val: int, extra: int, occupied_tiles: Dictionary) -> void:
	if extra <= 0:
		return
	const SPREAD: int = 3
	var placed: int   = 0
	var tries:  int   = 0
	while placed < extra and tries < extra * 10:
		tries += 1
		var tile: Vector2i = origin + Vector2i(
			rng.randi_range(-SPREAD, SPREAD),
			rng.randi_range(-SPREAD, SPREAD)
		)
		if tile == origin or occupied_tiles.has(tile):
			continue
		if tile.distance_to(Vector2i.ZERO) <= SPAWN_CLEAR_TILES:
			continue
		if ground_layer.get_cell_source_id(tile) == -1:
			continue
		if _is_chunk_cave_claimed(tile):
			continue
		var scatter_biome: int = _cell_biome_type(tile)
		if tree_type_val == 0 and scatter_biome != 0:
			continue
		if tree_type_val == 2 and scatter_biome != 2:
			continue
		# Water check last — it's 49 tile queries vs the single-query checks above.
		if _has_water_nearby(tile, 3):
			continue
		_mark_tree_tile(tile, occupied_tiles)
		var local_pos: Vector2 = ground_layer.map_to_local(tile)
		var world_pos: Vector2 = ground_layer.to_global(local_pos)
		_spawn_tree(world_pos, tree_type_val)
		placed += 1

func _generate_points() -> PackedVector2Array:
	var cell_size:   float = FOLIAGE_SPACING / sqrt(2)
	var grid_width:  int   = ceili(width  / cell_size)
	var grid_height: int   = ceili(height / cell_size)

	var grid: PackedInt32Array = PackedInt32Array()
	grid.resize(grid_width * grid_height)
	grid.fill(-1)

	var points:       PackedVector2Array = PackedVector2Array()
	var spawn_points: PackedInt32Array   = PackedInt32Array()

	var initial_point := Vector2(width * 0.5, height * 0.5)
	points.append(initial_point)
	spawn_points.append(0)
	grid[_point_to_cell_index(initial_point, cell_size, grid_width, grid_height)] = 0

	while not spawn_points.is_empty():
		var spawn_point_index = rng.randi_range(0, spawn_points.size() - 1)
		spawn_center          = points[spawn_points[spawn_point_index]]
		var point_accepted    = false

		for _i in REJECTION_THRESHOLD:
			var r         = rng.randf_range(FOLIAGE_SPACING, FOLIAGE_SPACING * 2)
			var a         = rng.randf() * TAU
			var new_point = spawn_center + Vector2.from_angle(a) * r
			if _is_valid_point(new_point, cell_size, grid_width, grid_height, points, grid):
				spawn_points.append(points.size())
				grid[_point_to_cell_index(new_point, cell_size, grid_width, grid_height)] = points.size()
				points.append(new_point)
				point_accepted = true
				break

		if not point_accepted:
			spawn_points.remove_at(spawn_point_index)

	return points

func _is_valid_point(point: Vector2, cell_size: float, grid_width: int, grid_height: int, points: PackedVector2Array, grid: PackedInt32Array) -> bool:
	if point.x >= 0 and point.x < width and point.y >= 0 and point.y < height:
		var cell_offset := Vector2i(width, height) / 2
		if ground_layer.get_cell_source_id(Vector2i(point) - cell_offset) == -1:
			return false
		var cell_x := floori(point.x / cell_size)
		var cell_y := floori(point.y / cell_size)
		var search_start_x := maxi(0, cell_x - 2)
		var search_end_x   := mini(cell_x + 2, grid_width - 1)
		var search_start_y := maxi(0, cell_y - 2)
		var search_end_y   := mini(cell_y + 2, grid_height - 1)
		for x in range(search_start_x, search_end_x + 1):
			for y in range(search_start_y, search_end_y + 1):
				var point_index := grid[x + y * grid_width]
				if point_index != -1:
					if point.distance_squared_to(points[point_index]) < FOLIAGE_SPACING * FOLIAGE_SPACING:
						return false
		return true
	return false

func _point_to_cell_index(point: Vector2, cell_size: float, grid_width: int, grid_height: int) -> int:
	var x := floori(point.x / cell_size)
	var y := floori(point.y / cell_size)
	assert(x < grid_width,  "Out of bounds: x")
	assert(y < grid_height, "Out of bounds. y=%.3f grid_y=%f cell_size=%f" % [point.y, point.y / cell_size, cell_size])
	return x + y * grid_width

# ── Wolf spawning ────────────────────────────────────────────────────
func _spawn_wolves() -> void:
	var half_w: int = width  / 2
	var half_h: int = height / 2

	var topmost_y:    int        = half_h + 1
	var plains_by_band: Dictionary = {}
	var all_plains:   Array      = []

	for xi in range(-half_w, half_w, WOLF_SCAN_STEP):
		for yi in range(-half_h, half_h, WOLF_SCAN_STEP):
			var cell := Vector2i(xi, yi)
			if _cell_biome_type(cell) != 0:
				continue
			if cell.distance_to(Vector2i.ZERO) <= SPAWN_CLEAR_TILES + 10:
				continue
			if _has_water_nearby(cell, 3):
				continue
			if _is_chunk_cave_claimed(cell):
				continue
			all_plains.append(cell)
			if yi < topmost_y:
				topmost_y = yi

	if not all_plains.is_empty():
		for cell in all_plains:
			var band_idx: int = (cell.y - topmost_y) / WOLF_BAND_SIZE
			if not plains_by_band.has(band_idx):
				plains_by_band[band_idx] = []
			plains_by_band[band_idx].append(cell)

		for band_idx in plains_by_band.keys():
			var band: Array = plains_by_band[band_idx]
			_spawn_wolf_at(band[rng.randi_range(0, band.size() - 1)])

		for cell in all_plains:
			if rng.randf() < WOLF_SPAWN_CHANCE:
				_spawn_wolf_at(cell)

	var near_count:  int = rng.randi_range(1, 5)
	var near_placed: int = 0
	var near_tries:  int = 0
	while near_placed < near_count and near_tries < 100:
		near_tries += 1
		var angle: float = rng.randf() * TAU
		var dist:  float = rng.randf_range(5.0, 10.0)
		var tile := Vector2i(roundi(dist * cos(angle)), roundi(dist * sin(angle)))
		if _cell_biome_type(tile) == 0 and not _has_water_nearby(tile, 2):
			_spawn_wolf_at(tile)
			near_placed += 1

func _spawn_wolf_at(tile: Vector2i) -> void:
	var local_pos: Vector2  = ground_layer.map_to_local(tile)
	var world_pos: Vector2  = ground_layer.to_global(local_pos)
	var wolf:      Node2D   = WOLF_SCENE.instantiate() as Node2D
	if wolf == null:
		push_warning("Wolf instantiation failed at tile %s" % str(tile))
		return
	add_child(wolf)
	wolf.global_position = world_pos

# ── Cave entrance spawning ────────────────────────────────────────────
# One-shot, same timing as _spawn_wolves — a single roll per chunk, any land
# biome (Water excluded via _cell_biome_type() == -1). Excluded entirely
# within CAVE_ENTRANCE_MIN_SPAWN_DIST of world spawn, and any roll landing
# within CAVE_ENTRANCE_MIN_SEPARATION of an already-placed entrance is
# dropped. Each entrance gets its own fixed seed here (via the world's own
# seeded rng) so its interior is deterministic and identical every time
# it's re-entered, without needing to generate the interior itself until
# the player actually walks in (see CaveWorld). The whole chunk an entrance
# lands in is marked claimed — see _is_chunk_cave_claimed().
func _spawn_cave_entrances() -> void:
	var half_w: int = width  / 2
	var half_h: int = height / 2
	for cx in range(_chunk_cols):
		for cy in range(_chunk_rows):
			if rng.randf() >= CAVE_ENTRANCE_CHANCE:
				continue
			var tl: Vector2i = Vector2i(cx * CHUNK_SIZE - half_w, cy * CHUNK_SIZE - half_h)
			var tile: Vector2i = tl + Vector2i(rng.randi_range(0, CHUNK_SIZE - 1), rng.randi_range(0, CHUNK_SIZE - 1))
			if _cell_biome_type(tile) == -1:
				continue
			if tile.distance_to(Vector2i.ZERO) < CAVE_ENTRANCE_MIN_SPAWN_DIST:
				continue
			var too_close: bool = false
			for placed in _cave_entrance_tiles:
				if tile.distance_to(placed as Vector2i) < CAVE_ENTRANCE_MIN_SEPARATION:
					too_close = true
					break
			if too_close:
				continue
			_cave_claimed_chunks[Vector2i(cx, cy)] = true
			_cave_entrance_tiles.append(tile)
			_spawn_cave_entrance_at(tile)

func _is_chunk_cave_claimed(tile: Vector2i) -> bool:
	return _cave_claimed_chunks.has(_tile_to_chunk(tile))

func _spawn_cave_entrance_at(tile: Vector2i) -> void:
	var local_pos: Vector2 = ground_layer.map_to_local(tile)
	var world_pos: Vector2 = ground_layer.to_global(local_pos)
	var portal := CavePortal.new()
	portal.mode      = CavePortal.Mode.ENTER
	portal.cave_seed = rng.randi()
	add_child(portal)
	portal.global_position = world_pos

# ── Debug: teleport to the nearest cave entrance (Ctrl+Shift+T) ────────
func teleport_to_nearest_cave() -> void:
	var p: Node2D = _get_player()
	if p == null or _cave_entrance_tiles.is_empty():
		return
	var best_tile: Vector2i = _cave_entrance_tiles[0]
	var best_dist: float    = INF
	for t in _cave_entrance_tiles:
		var tile: Vector2i     = t as Vector2i
		var world_pos: Vector2 = ground_layer.to_global(ground_layer.map_to_local(tile))
		var dist: float         = p.global_position.distance_to(world_pos)
		if dist < best_dist:
			best_dist = dist
			best_tile = tile
	# Land one tile south of the entrance, not exactly on it — lets the
	# player see the marker and walk in deliberately rather than the
	# CavePortal's own Area2D triggering entry the instant they land.
	var target: Vector2 = ground_layer.to_global(ground_layer.map_to_local(best_tile + Vector2i(0, 1)))
	p.global_position = target

# ── Dungeon entrance spawning (mission-accept driven) ───────────────────
# Called when Global.mission_accepted fires. Only dungeon missions (those
# with a dungeon_index in Global.missions) spawn an entrance; each dungeon
# spawns at most one, so re-accepting / repeated calls never duplicate it.
func _on_mission_accepted(mission_id: String) -> void:
	for m in Global.missions:
		if m["id"] == mission_id and m.has("dungeon_index"):
			_spawn_dungeon_entrance(int(m["dungeon_index"]))
			return

# Spawns the entrance for the currently accepted dungeon mission if it's
# missing (see the call in _deferred_foliage for why reconciliation is needed).
func _ensure_accepted_dungeon_entrance() -> void:
	var idx: int = Global.accepted_dungeon_index()
	if idx <= 0 or Global.is_dungeon_cleared(idx):
		return
	if _dungeon_entrance_tiles.has(idx):
		return
	_spawn_dungeon_entrance(idx)

func _spawn_dungeon_entrance(dungeon_index: int) -> void:
	if _dungeon_entrance_tiles.has(dungeon_index):
		return
	var player: Node2D = _get_player()
	var player_tile: Vector2i = ground_layer.local_to_map(ground_layer.to_local(player.global_position)) \
		if player != null else Vector2i.ZERO

	# Collect every eligible chunk, then pick one at random — a fixed number
	# of random attempts could keep missing valid chunks on tighter maps.
	var developed_chunks: Dictionary = {}
	for cell in _placed_blocks:
		developed_chunks[_tile_to_chunk(cell as Vector2i)] = true

	var valid: Array[Vector2i] = []
	for cx in range(_chunk_cols):
		for cy in range(_chunk_rows):
			var chunk := Vector2i(cx, cy)
			if _is_valid_dungeon_chunk(chunk, player_tile, developed_chunks):
				valid.append(chunk)
	if valid.is_empty():
		push_warning("DungeonSpawner: no valid chunk found for dungeon %d" % dungeon_index)
		return

	# A single random pick can land on an all-ocean chunk (the corner chunks
	# routinely are), and _random_land_tile_in_chunk then finds nothing — so
	# walk the list from a random start until one chunk yields a usable tile.
	var start: int = rng.randi_range(0, valid.size() - 1)
	for i in range(valid.size()):
		var chunk: Vector2i = valid[(start + i) % valid.size()]
		var tile:  Vector2i = _random_land_tile_in_chunk(chunk)
		if tile == DUNGEON_INVALID_TILE:
			continue
		_dungeon_entrance_tiles[dungeon_index] = tile
		# The layout's seed is rolled HERE — the first time the player accepts
		# the mission — then persisted in Global, so the dungeon is "generated"
		# once and re-entering always reproduces the same layout.
		Global.get_or_create_dungeon_seed(dungeon_index)
		_spawn_dungeon_portal_at(tile, dungeon_index)
		return

	push_warning("DungeonSpawner: no land tile found in any valid chunk for dungeon %d" % dungeon_index)

# Every constraint of where a dungeon entrance may NOT occupy a chunk:
#   a. no player-placed blocks anywhere in it
#   b. not a cave-claimed chunk
#   c. not the chunk the player is currently standing in
#   d. not within DUNGEON_SPAWN_MIN_DIST_TILES tiles of world spawn
func _is_valid_dungeon_chunk(chunk: Vector2i, player_tile: Vector2i, developed_chunks: Dictionary) -> bool:
	if _cave_claimed_chunks.has(chunk):
		return false
	if _tile_to_chunk(player_tile) == chunk:
		return false
	if developed_chunks.has(chunk):
		return false
	if _chunk_min_corner_dist(chunk, _world_spawn_pos()) < DUNGEON_SPAWN_MIN_DIST_TILES * TILE_SIZE:
		return false
	return true

# Land tile inside a chunk (rejecting water, trees and placed blocks — a
# portal can't sit on any of those; _cell_biome_type() == -1 is water).
# Scans the whole 25x25 chunk once and returns a random usable tile, instead
# of a fixed number of random attempts that can whiff on a partially-land
# chunk. An ENTIRELY water chunk still fails (DUNGEON_INVALID_TILE) — the
# caller then falls through to the next valid chunk.
func _random_land_tile_in_chunk(chunk: Vector2i) -> Vector2i:
	var half_w: int = width  / 2
	var half_h: int = height / 2
	var tl := Vector2i(chunk.x * CHUNK_SIZE - half_w, chunk.y * CHUNK_SIZE - half_h)
	var candidates: Array[Vector2i] = []
	for dx in range(CHUNK_SIZE):
		for dy in range(CHUNK_SIZE):
			var tile: Vector2i = tl + Vector2i(dx, dy)
			if _cell_biome_type(tile) == -1:
				continue
			if _placed_blocks.has(tile) or _is_tree_occupied(tile):
				continue
			candidates.append(tile)
	if candidates.is_empty():
		return DUNGEON_INVALID_TILE
	return candidates[rng.randi_range(0, candidates.size() - 1)]

func _spawn_dungeon_portal_at(tile: Vector2i, dungeon_index: int) -> void:
	var portal: Node2D = DUNGEON_PORTAL_SCENE.instantiate() as Node2D
	if portal == null:
		return
	portal.set("dungeon_index", dungeon_index)
	_dungeon_portal_nodes[dungeon_index] = portal
	add_child(portal)
	portal.global_position = ground_layer.to_global(ground_layer.map_to_local(tile))

# Called by DungeonWorld when its quiz altar is cleared — the dungeon is
# "gone from the map": free the entrance portal and forget its tile. Safe to
# call while the overworld is off-tree (in-dungeon): the portal is a child of
# this node and queue_free() works on off-tree nodes.
func remove_dungeon_entrance(dungeon_index: int) -> void:
	if _dungeon_portal_nodes.has(dungeon_index):
		var portal: Node = _dungeon_portal_nodes[dungeon_index]
		if is_instance_valid(portal):
			portal.queue_free()
		_dungeon_portal_nodes.erase(dungeon_index)
	_dungeon_entrance_tiles.erase(dungeon_index)

# World position the mission guide arrow points at — the accepted dungeon's
# entrance portal. Vector2.INF means "no active target" (the arrow hides):
# no dungeon mission accepted, the entrance was removed (dungeon cleared),
# or this is called while inside a cave/dungeon (those worlds don't have this
# method, and the arrow's has_method() guard handles that).
func get_dungeon_guide_target() -> Vector2:
	var idx: int = Global.accepted_dungeon_index()
	if idx <= 0 or not _dungeon_entrance_tiles.has(idx) or Global.is_dungeon_cleared(idx):
		return Vector2.INF
	var tile: Vector2i = _dungeon_entrance_tiles[idx] as Vector2i
	return ground_layer.to_global(ground_layer.map_to_local(tile))

# ── Tree removal tracking ────────────────────────────────────────────
func notify_tree_removed(tree: Node2D) -> void:
	_removed_trees.append({"x": tree.global_position.x, "y": tree.global_position.y})
	if tree.has_meta("spawn_cell"):
		_unmark_tree_occupied(tree.get_meta("spawn_cell") as Vector2i)

# ── Grass removal tracking ───────────────────────────────────────────
# Called by GrassTuft._destroy() once a tuft is cut. Unlike trees, grass
# isn't save/load persisted (it regenerates deterministically from the world
# seed) — freeing the tile here just makes it eligible again for the next
# _regrow_grass() pass.
func notify_grass_removed(tile: Vector2i) -> void:
	_grass_occupied_tiles.erase(tile)

# ── World save / load ────────────────────────────────────────────────
func get_world_save_data() -> Dictionary:
	var data: Dictionary = {
		"placed_blocks": [],
		"removed_trees": _removed_trees.duplicate(),
		"mobs":          _collect_preserved_mobs(),
		"dungeon_entrances": [],
	}
	for idx in _dungeon_entrance_tiles:
		var t: Vector2i = _dungeon_entrance_tiles[idx] as Vector2i
		data["dungeon_entrances"].append({"index": int(idx), "x": t.x, "y": t.y})
	for cell in _placed_blocks:
		var entry: Dictionary = _placed_blocks[cell] as Dictionary
		var node: Node        = entry["node"] as Node
		if not is_instance_valid(node):
			continue
		var idata: ItemData = node.get("item_data") as ItemData
		if idata == null or idata.resource_path.is_empty():
			continue
		var block_entry: Dictionary = {
			"cell_x":        (cell as Vector2i).x,
			"cell_y":        (cell as Vector2i).y,
			"item_path":     idata.resource_path,
			"chest_slots":   null,
			"dungeon_index": null,
		}
		if node.has_method("get_items"):
			var slots: Array = node.call("get_items") as Array
			var saved: Array = []
			for slot in slots:
				if slot == null:
					saved.append(null)
				else:
					var sd: ItemData = (slot as Dictionary)["data"] as ItemData
					if sd != null and not sd.resource_path.is_empty():
						saved.append({"path": sd.resource_path, "quantity": (slot as Dictionary)["quantity"]})
					else:
						saved.append(null)
			block_entry["chest_slots"] = saved
		var di = node.get("dungeon_index")
		if di != null:
			block_entry["dungeon_index"] = int(di)
		data["placed_blocks"].append(block_entry)
	return data

func apply_world_save_data(data: Dictionary) -> void:
	if data.has("removed_trees"):
		for entry in (data["removed_trees"] as Array):
			if not (entry is Dictionary):
				continue
			var pos := Vector2(float(entry["x"]), float(entry["y"]))
			for node in get_tree().get_nodes_in_group("Tree"):
				if not (node is Node2D):
					continue
				if (node as Node2D).global_position.distance_to(pos) < 8.0:
					if node.has_meta("spawn_cell"):
						_unmark_tree_occupied(node.get_meta("spawn_cell") as Vector2i)
					node.queue_free()
					break
	if data.has("mobs") and data["mobs"] is Array:
		_restore_mobs(data["mobs"] as Array)
	if data.has("dungeon_entrances") and data["dungeon_entrances"] is Array:
		for entry in (data["dungeon_entrances"] as Array):
			if not (entry is Dictionary):
				continue
			var de: Dictionary = entry as Dictionary
			var idx: int  = int(de.get("index", 1))
			var tile := Vector2i(int(de.get("x", 0)), int(de.get("y", 0)))
			if _dungeon_entrance_tiles.has(idx):
				continue
			_dungeon_entrance_tiles[idx] = tile
			_spawn_dungeon_portal_at(tile, idx)
	if not data.has("placed_blocks"):
		return
	for block_data in (data["placed_blocks"] as Array):
		if not (block_data is Dictionary):
			continue
		var bd: Dictionary = block_data as Dictionary
		var cell := Vector2i(int(bd["cell_x"]), int(bd["cell_y"]))
		if _placed_blocks.has(cell):
			continue
		var item_path: String = str(bd.get("item_path", ""))
		if item_path.is_empty() or not ResourceLoader.exists(item_path):
			continue
		var idata: ItemData = load(item_path) as ItemData
		if idata == null:
			continue
		var scene_path: String = idata.place_scene_path
		if scene_path.is_empty() or not ResourceLoader.exists(scene_path):
			continue
		var obj_scene: PackedScene = load(scene_path) as PackedScene
		if obj_scene == null:
			continue
		var obj: Node = obj_scene.instantiate()
		if obj == null:
			continue
		if obj.has_method("setup"):
			obj.call("setup", idata)
		_placed_blocks[cell] = {"node": obj, "name": idata.item_name}
		if obj.has_method("set_world_cell"):
			obj.call("set_world_cell", cell, self)
		add_child(obj)
		if not is_instance_valid(obj):
			_placed_blocks.erase(cell)
			continue
		obj.position = editable_layer.map_to_local(cell)
		obj.z_index  = int(obj.position.y / TILE_SIZE)
		_fix_sprite_offset(obj)
		var chest_slots = bd.get("chest_slots", null)
		if chest_slots is Array:
			var slots_ref = obj.get("slots")
			if slots_ref is Array:
				for i in range(mini((chest_slots as Array).size(), (slots_ref as Array).size())):
					var se = (chest_slots as Array)[i]
					if not (se is Dictionary):
						continue
					var spath: String = str((se as Dictionary).get("path", ""))
					if spath.is_empty() or not ResourceLoader.exists(spath):
						continue
					var res: ItemData = load(spath) as ItemData
					if res != null:
						(slots_ref as Array)[i] = {"data": res, "quantity": int((se as Dictionary).get("quantity", 1))}
			if obj.has_method("_refresh_ui"):
				obj.call("_refresh_ui")
		var di = bd.get("dungeon_index", null)
		if di != null:
			obj.set("dungeon_index", int(di))
