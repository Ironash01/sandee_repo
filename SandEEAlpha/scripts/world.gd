extends Node2D

const TILE_SIZE = 32
const TREE_SCENE:      PackedScene = preload("res://scenes/objects/Tree.tscn")
const WOLF_SCENE:      PackedScene = preload("res://scenes/mobs/Wolf.tscn")
const WORM_SCENE:      PackedScene = preload("res://scenes/mobs/Worm.tscn")
const HEADLESS_FISH_SCENE: PackedScene = preload("res://scenes/mobs/HeadlessFish.tscn")
const PLAIN_TREE_TEX:  Texture2D   = preload("res://sprites/tree/tree.png")
const SNOWY_TREE_TEX:  Texture2D   = preload("res://sprites/tree/snowy_tree.png")
const SHADOW_TEXTURE:  Texture2D   = preload("res://sprites/shadow/shadow_base.png")
const ITEM_DROP_SCENE: PackedScene = preload("res://scenes/ui/InventoryItem.tscn")
const SWORD_SWING_SCRIPT: GDScript = preload("res://scripts/sword_swing_effect.gd")
const CACTUS_SCENE:    PackedScene = preload("res://scenes/objects/PlaceableBlock.tscn")
const CACTUS_DATA:     ItemData    = preload("res://resources/items/cactus.tres")
const OBJECT_BURST_SCRIPT: GDScript = preload("res://scripts/object_burst.gd")

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
# Radius (tiles) around world spawn kept clear of natural stuff (trees, grass,
# forest centers) so the player is never trapped right after spawning. Sized to
# a full spawn CHUNK (CHUNK_SIZE) so the whole spawn chunk stays open.
const SPAWN_CLEAR_TILES:  int   = 25
const REJECTION_THRESHOLD: int  = 30

# For Grass Gen — dense per-chunk fill (see _fill_chunk_grass), not a sparse
# scatter: every chunk is filled to a random GRASS_CHUNK_COVERAGE_MIN..MAX
# fraction of its eligible plains tiles at world-gen. World only decides
# WHICH tiles get grass — how a single tuft looks/sizes/anchors/animates
# lives in scripts/grass.gd (GrassTuft), instantiated via GRASS_SCENE.
const GRASS_SCENE: PackedScene = preload("res://scenes/objects/Grass.tscn")
const GRASS_CHUNK_COVERAGE_MIN: float = 0.10
const GRASS_CHUNK_COVERAGE_MAX: float = 0.15
# Per chunk fill, 70% of the time the target tile count is taken as one
# compact cluster (nearest tiles to a random seed point) instead of spread
# uniformly across the whole chunk.
const GRASS_GROUPED_CHANCE: float = 0.70
const GRASS_REGROW_INTERVAL: float = 600.0  # 10 minutes, matches the overworld day spawn cadence
# A random desert tile grows a Cactus every 5 minutes (see _spawn_cactus).
const CACTUS_SPAWN_INTERVAL: float = 300.0
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

const WOLF_SPAWN_CHANCE: float = 0.003  # was 0.08 — 8% of 5000 plains tiles = ~400 wolves
const WOLF_BAND_SIZE:    int   = 50
const WOLF_SCAN_STEP:    int   = 5

# One-shot at world-gen, one attempt per chunk (any land biome) — see
# _spawn_cave_entrances(). CavePortal/CaveWorld/CaveGenerator handle
# everything about what's actually inside.
const CAVE_ENTRANCE_CHANCE:         float = 0.25   # per eligible chunk
const CAVE_ENTRANCE_MIN_SPAWN_DIST: float = 200.0  # no caves closer than this to world spawn
const CAVE_ENTRANCE_MIN_SEPARATION: float = 100.0  # no two caves closer than this to each other

# ── Large cave ground trails (decorative overlay) ──────────────────
# Semi-transparent rubble decals scattered around every large cave
# entrance on the TILE GRID (each decal sits centred on a tile, rotated in
# 90° steps) so they respect the tiling system. They are drawn as plain
# Sprite2D decals parented to the Ground TileMapLayer — NOT painted into
# the ground — so the biome tile underneath stays fully visible and the
# trail keeps its own alpha.
const CAVE_TRAIL_RING_TILES:  int   = 3     # how many tile rings out from the footprint
const CAVE_TRAIL_INNER_CHANCE: float = 0.9  # fill chance for the innermost ring
const CAVE_TRAIL_OUTER_CHANCE: float = 0.55 # fill chance for the outer rings
const CAVE_TRAIL_ITEM_PATHS: Array = [
	"res://resources/items/large_cave_trails01.tres",
	"res://resources/items/large_cave_trails02.tres",
	"res://resources/items/large_cave_trails03.tres",
	"res://resources/items/large_cave_trails04.tres",
]
var _cave_trail_textures: Array = []   # lazily loaded decal textures from the trail items
var _cave_trails_root:    Node2D = null

# Pixie-cave entrances — one-shot per chunk, three rules (see
# _spawn_pixie_cave_entrances): the chunk must NOT already hold a large
# (regular) cave, must be solid land not near the ocean, and the chosen tile
# must be > PIXIE_CAVE_SPAWN_MIN_DIST from world spawn. Rarer than regular
# caves by default; enter a PixieCaveWorld (portal.cave_type = "pixie").
const PIXIE_CAVE_ENTRANCE_CHANCE:          float = 1.0  # TEMP: 100% for testing, reduce to 0.08 for release
const PIXIE_CAVE_SPAWN_MIN_DIST:           float = 100.0  # not within 100 blocks of world spawn
const PIXIE_CAVE_ENTRANCE_MIN_SEPARATION: float = 150.0  # keep pixie entrances apart from each other AND from regular caves

# Chunks a cave entrance claims are excluded from every other one-shot
# generation pass (trees/forests, grass fill, wolves) — see
# _is_chunk_cave_claimed(). Populated by _spawn_cave_entrances(), which must
# therefore run BEFORE _spawn_wolves/_deferred_foliage (see the call order
# where these are all queued via call_deferred()).
var _cave_claimed_chunks: Dictionary = {}   # chunk coord (Vector2i) -> true
var _cave_entrance_tiles: Array      = []   # placed entrance tiles, for the min-separation check
var _pixie_cave_entrance_tiles: Array = []   # placed pixie-entrance tiles, for the min-separation check
var _cave_entrance_pool:  Array      = []   # cached GeneratedStructure resources with type == cave1/cave2/cave3
var _pixie_cave_entrance_pool: Array = []   # cached GeneratedStructure resources with type == "pixie cave"
var _cave_entrance_cells: Dictionary = {}   # cell (Vector2i) -> true — every footprint cell of every live entrance
var _cave_entrance_nodes: Dictionary = {}   # entrance tile -> Node2D root of the painted entrance sprite+collision
var _cave_base_ground_src: int      = -1    # lazily-registered cave_base.png ground tile (see _get_cave_base_ground_src)
var _cave_base_ground_tex: Texture2D = null

# ── Overworld structures (GeneratedStructure resources) ─────────────
# Hand-drawn structure tiles are rolled once per eligible chunk at
# world-gen (see _spawn_overworld_structures), sitting between caves and
# natural stuff in the chunk-priority order: caves claim first, then
# structures, then trees/grass/wolves fill whatever's left. Dungeons spawn
# later (on mission accept) and simply exclude cave- AND structure-claimed
# chunks. All of these skip all-ocean chunks entirely — see
# _is_chunk_all_ocean(). Resources are auto-loaded from STRUCTURES_DIR,
# filtered to spawn_world == "overworld".
const STRUCTURES_DIR: String = "res://resources/structures/"
const STRUCTURE_CHANCE:         float = 0.15   # per eligible chunk
const STRUCTURE_MIN_SPAWN_DIST: float = 100.0  # no structures closer than this to world spawn
const STRUCTURE_MIN_SEPARATION: float = 20.0   # no two structure anchors closer than this

var _structure_claimed_chunks: Dictionary = {}   # chunk coord (Vector2i) -> true
var _structure_anchor_tiles:   Array      = []   # top-left tiles, for the min-separation check
var _located_structures:        Array      = []   # [{"name": String, "tile": Vector2i}, ...] — every placed structure/entrance, for /locate
var _structure_sources:        Dictionary = {}   # GeneratedStructure -> source id in the Structures TileSet

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
var _dungeon_entrance_pool:   Array = []    # cached GeneratedStructure resources with type == "dungeon entrances"
var _dungeon_entrance_structure_cells: Dictionary = {}  # dungeon_index -> Array[Vector2i] cells painted for the entrance
var _dungeon_entrance_nodes:  Dictionary = {}   # dungeon_index -> Node2D root of the painted entrance sprite+collision
var _dungeon_entrance_cells:  Dictionary = {}   # cell (Vector2i) -> true — every footprint cell of every live entrance

# Trees beyond this radius have their Area2D monitoring disabled to avoid
# O(n²) physics overhead. Must be larger than InteractArea radius (48px).
# NOTE: grass deliberately does NOT use this per-node Area2D pattern — see
# _on_swing_performed below. A grass-scale
# (thousands of tufts) periodic full-group scan was tried and became the
# dominant runtime cost; grass cutting is driven centrally instead, same
# O(1) dictionary-lookup approach _destroy_hovered_block() already uses for
# placed blocks.
const TREE_INTERACT_RADIUS: float = 300.0
# ── Tree leaf-fade (player hides behind the canopy) ──────────────────
# When the player's feet are north of a tree's trunk base AND within the
# canopy's horizontal span, the canopy (see tree_canopy_fade.gdshader)
# thins so the player shows through. CANOPY_HEIGHT is the vertical band
# above the base where being behind the tree triggers the fade.
const TREE_FADE_CANOPY_HEIGHT: float = 64.0
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
	{"scene": WORM_SCENE, "data": preload("res://resources/mobs/worm.tres")},
	{"scene": HEADLESS_FISH_SCENE, "data": preload("res://resources/mobs/headless_fish.tres")},
]

var rng: RandomNumberGenerator = RandomNumberGenerator.new()

# Grass has its own RNG stream, seeded deterministically from `random_seed`.
# The grass fill runs in the BACKGROUND (a coroutine that yields every
# GRASS_CHUNKS_PER_FRAME chunks) and can skip tufts based on the player's
# live position (_spawn_grass_at's player-tile guard) — a shared rng stream
# would let those runtime conditions (and the regrow timer, which skips
# chunks with placed blocks) shift it for every tuft, making grass look
# different on every restart. So each chunk's grass uses its OWN rng derived
# from the world seed + chunk coords (see _fill_chunk_grass), making it a
# pure function of (seed, chunk): the pattern is permanent and identical on
# every load, no matter the fill order, interruptions, or game state.
var humidity:    FastNoiseLite = FastNoiseLite.new()
var temperature: FastNoiseLite = FastNoiseLite.new()
var altitude:    FastNoiseLite = FastNoiseLite.new()

@onready var water_layer:    TileMapLayer = $Water
@onready var ground_layer:   TileMapLayer = $Ground
@onready var editable_layer: TileMapLayer = $Editable
@onready var structures_layer: TileMapLayer = $Structures

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

# Walkable-grass y-sort (see _update_grass_sort): tufts within this many
# tiles of the player's feet tile are considered each frame.
const GRASS_SORT_RANGE: int = 2
# The player sprite extends ~48px above the feet, so a tuft's blade band
# can only overlap the player while the feet sit within this window above
# its root line (grass.gd root_y()). Farther tufts keep their static
# bucket so their order vs trees/blocks is never disturbed.
const GRASS_COVER_WINDOW_PX: float = 48.0
# Horizontal half-span of a tuft's blades: the sprite renders 2.7 tiles wide
# (SIZE_TILES in grass.gd), so blades overflow ~0.85 of a tile into each side
# neighbor. A player within this span of a tuft is standing beside/under the
# overhanging blades.
const GRASS_BLADE_HALF_W: float = 44.0
# How far south of the root line a BESIDE-blades player's feet may sit and
# still be covered. The root hugs the tile's bottom edge, so a same-row
# side-neighbor's feet land just south of it — this small tolerance covers
# that brushing case without covering the player a full row south.
const GRASS_BESIDE_SOUTH_PX: float = 10.0
# Block origin (tile center) → visual base (tile bottom): blocks are
# bottom-anchored by _fix_sprite_offset, so their base line sits half a
# tile below the node origin. See _update_block_sort.
const BLOCK_COVER_BASE_OFFSET_PX: float = 16.0
var _grass_sort_touched: Array = []   # tufts whose z was raised last frame
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
	# The swing is owned by the player (it fires in every world backend); this
	# overworld listens for it to run the sword grass-cut on the same trigger.
	# Deferred: World's _ready runs before the Player's _ready (sibling order
	# in game_instance), so Global.player_node may be null yet — defer until
	# the tree is fully built before grabbing the player.
	call_deferred("_connect_swing_signal")
	# Set world reference immediately so game_instance can connect signals.
	Global.world_node = self
	# Two-step deferred chain: step 1 runs this frame's MessageQueue flush,
	# step 2 runs the NEXT frame's flush — after this frame's render step.
	# This guarantees the loading screen draws at least once before any freeze.
	_queue_generation.call_deferred()

func _connect_swing_signal() -> void:
	var pl: Node = _get_player()
	if pl != null and pl.has_signal("swing_performed"):
		pl.connect("swing_performed", _on_swing_performed)

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
		return
	if event.is_action_pressed("mouse_left"):
		place_block()

# Fired by the player's swing_performed signal (the swing plays in every
# world backend; this overworld reacts to it): if a sword is held, cut the
# grass row in front of the player.
func _on_swing_performed() -> void:
	var p: Node2D = _get_player()
	if p == null or not p.has_method("get_facing_dir"):
		return
	var held: Variant = Global.get_hotbar_item()
	if held == null or not (held as Dictionary).has("data"):
		return
	var data: ItemData = (held as Dictionary)["data"] as ItemData
	if not data.is_sword:
		return
	_cut_grass_row(p)

func _cut_grass_row(p: Node2D) -> void:
	var held: Variant = Global.get_hotbar_item()
	if held == null or not (held as Dictionary).has("data"):
		return
	var d: Vector2i = GRASS_CUT_DIR_VECTORS.get(p.call("get_facing_dir"), Vector2i(0, 1)) as Vector2i
	var player_tile: Vector2i = ground_layer.local_to_map(ground_layer.to_local(p.global_position))
	var center:      Vector2i = player_tile + d
	# One tile per swing: the tile directly in front of the player. (The old
	# behaviour cleared a vertical column that grew with sword level; this
	# clears a single patch so a swing is a deliberate single-tile cut.)
	var tile: Vector2i = center
	
	# trying to cast freed object.
	var tuft: GrassTuft = _grass_occupied_tiles.get(tile) as GrassTuft
	if tuft != null and is_instance_valid(tuft):
		tuft.cut()
		_spawn_sword_effect(tuft.global_position, "puff")

func _destroy_hovered_block() -> void:
	var mouse_pos: Vector2 = get_global_mouse_position()
	var best_cell: Variant = null
	var best_dist: float   = INTERACT_RADIUS_PX
	for cell in _placed_blocks:
		var entry: Dictionary = _placed_blocks[cell] as Dictionary
		var node_ref: Variant = entry["node"]
		if not is_instance_valid(node_ref):
			continue
		var node: Node2D = node_ref as Node2D
		if node == null:
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
	var node_ref2: Variant = entry["node"]
	if is_instance_valid(node_ref2):
		var node: Node = node_ref2 as Node
		if node != null:
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
#
# Every swing swallows the click and shows the sword-swing arc sheet
# (_spawn_sword_effect mode "swing"); every tuft broken sprays the mellow
# puff sheet (mode "puff") — so a whiff still reads as a deliberate attack
# and each cut grass visibly pops.
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

# Spawns a transient sword-swing / mellow-puff effect at a world position,
# oriented to the player's facing direction. mode is "swing" (arc + puff) or
# "puff" (grass break, puff only).
func _spawn_sword_effect(world_pos: Vector2, mode: String) -> void:
	var fx: Node2D = SWORD_SWING_SCRIPT.new() as Node2D
	if fx == null:
		return
	fx.set("_mode", mode)
	# Child of this world, so place in world-local space from the world pos.
	fx.position = to_local(world_pos)
	add_child(fx)

# ── Walkable grass y-sort (dynamic, per-frame, O(25) dict lookups) ─────
# Grass has no collision (Grass.tscn) — the player wades THROUGH it, and
# whichever of the two is "south" must draw in front. Static tile-bucket
# z_index can't express that: the player's feet sweep continuously through
# the tuft's tile, and an equal-z tie falls back to tree order, which is
# not stable between the player and World's children. So the world drives
# it: each frame, any tuft whose blade band overlaps the player's sprite
# AND whose root line is south of the player's feet gets z = player_z + 1
# (blades cover the player); every other tuft keeps its static bucket.
# The feet crossing a root line is the exact swap point, so:
#   • entering from the north → blades are already in front, coverage
#     grows smoothly as the sprite bands start overlapping (no pop)
#   • entering from the south → player in front until the feet cross the
#     root line, then the blades take over (the standard y-sort swap)
#   • east/west → the tuft's 2.7-tile-wide blades overflow into the side
#     tiles, so a player beside it (same row) gets a small south tolerance on
#     the band (GRASS_BESIDE_SOUTH_PX) and is covered; a player clearly a row
#     south (in front of the grass) stays in front, as the standard rule does.
# Touched tufts are restored to static_z the next frame (or on the first
# frame after leaving a cave, since this node stops processing off-tree).
func _update_grass_sort() -> void:
	var p: Node2D = _get_player()
	if p == null or not p.has_method("sort_feet_y"):
		return
	var feet_y: float = p.call("sort_feet_y")
	var px: float = p.global_position.x
	var feet_tile: Vector2i = ground_layer.local_to_map(ground_layer.to_local(p.global_position))
	var covered: Array = []
	for dx in range(-GRASS_SORT_RANGE, GRASS_SORT_RANGE + 1):
		for dy in range(-GRASS_SORT_RANGE, GRASS_SORT_RANGE + 1):
			var tuft: GrassTuft = _grass_occupied_tiles.get(feet_tile + Vector2i(dx, dy)) as GrassTuft
			if tuft == null or not is_instance_valid(tuft):
				continue
			var root: float = tuft.root_y()
			# Standard top-down sort: the grass base line is its root; the
			# player's base is their feet. Grass covers the player whenever the
			# feet are NORTH of the root (player behind); the player draws in
			# front once clearly SOUTH of it (the normal y-sort swap).
			#
			# East/west approach: the tuft's blades overflow ~0.85 tile into the
			# side tiles, so a player BESIDE the tuft at the same row has their
			# feet sitting just south of the root (the root hugs the tile's
			# bottom edge). Allow a small south tolerance there so brushing past
			# on the left/right still gets the blades-over-player cover — but
			# NOT so far that a player standing a full row south (in front of
			# the grass) is wrongly covered.
			var beside_blades: bool = absf(px - tuft.global_position.x) <= GRASS_BLADE_HALF_W
			var band_bottom: float = root + (GRASS_BESIDE_SOUTH_PX if beside_blades else 0.0)
			if feet_y < band_bottom and feet_y > root - GRASS_COVER_WINDOW_PX:
				covered.append(tuft)
				# Idempotent write: touching z_index every frame re-registers
				# the tuft's canvas item in the renderer, which double-allocates
				# its instance shader uniforms (grass_sway's root_pos) and
				# spams global_shader_parameters_instance_allocate errors.
				var target: int = p.z_index + 1
				if tuft.z_index != target:
					tuft.z_index = target
	# Tufts that were covered last frame but aren't anymore fall back to
	# their static bucket — again written only on an actual change.
	for t in _grass_sort_touched:
		if is_instance_valid(t) and not covered.has(t):
			var tuft: GrassTuft = t as GrassTuft
			if tuft.z_index != tuft.static_z:
				tuft.z_index = tuft.static_z
	_grass_sort_touched = covered

# ── Walkable-block cover y-sort (same trick as the grass, for blocks) ──
# A block's collision box only covers the tile's LOWER half (see
# PlaceableBlock.tscn) — its visual base. Walking into a block from the
# north therefore puts the player's feet INSIDE the block's upper sprite
# area, where the block must draw OVER them ("player behind the block"),
# while a player south of the base draws in front. Static tile buckets
# can't flip like that (equal z falls back to unstable tree order), so
# each frame any placed block whose tile contains the player's feet gets
# z = player_z + 1, restored to its placement bucket
# (int(position.y / TILE_SIZE) — the exact value place_block assigns)
# once the feet leave its tile. Outside the tile there is no pixel
# overlap between the two sprites, so the static bucket is correct and
# tie-free in every other position.
var _block_sort_touched: Array = []   # blocks whose z was raised last frame

func _update_block_sort() -> void:
	var p: Node2D = _get_player()
	if p == null or not p.has_method("sort_feet_y"):
		return
	var feet_y: float = p.call("sort_feet_y")
	var feet_tile: Vector2i = ground_layer.local_to_map(ground_layer.to_local(p.global_position))
	var covered: Array = []
	for dx in range(-GRASS_SORT_RANGE, GRASS_SORT_RANGE + 1):
		for dy in range(-GRASS_SORT_RANGE, GRASS_SORT_RANGE + 1):
			var entry: Variant = _placed_blocks.get(feet_tile + Vector2i(dx, dy))
			if entry == null or not (entry is Dictionary):
				continue
			var node_ref: Variant = (entry as Dictionary).get("node")
			if node_ref == null or not is_instance_valid(node_ref) or not (node_ref is Node2D):
				continue
			if node_ref is GrassTuft:
				continue   # tufts are driven by _update_grass_sort
			var block: Node2D = node_ref as Node2D
			var base: float = block.global_position.y + BLOCK_COVER_BASE_OFFSET_PX
			# Cover while the feet are inside the block's tile (north of its
			# visual base at the tile bottom).
			if feet_y < base and feet_y > base - TILE_SIZE:
				covered.append(block)
				# Same idempotent-write rule as the grass driver above.
				var target: int = p.z_index + 1
				if block.z_index != target:
					block.z_index = target
	for t in _block_sort_touched:
		if is_instance_valid(t) and not covered.has(t):
			var block: Node2D = t as Node2D
			var static_z: int = int(block.global_position.y / TILE_SIZE)
			if block.z_index != static_z:
				block.z_index = static_z
	_block_sort_touched = covered

func _process(delta: float) -> void:
	_update_ghost()
	_update_hover()
	_update_cursor_highlight()
	_update_grass_ruffle()
	_update_grass_sort()
	_update_block_sort()
	_update_tree_fade(delta)
	_check_desert_worm_spawn(delta)
	if Global.block_mode and _grid_overlay != null:
		_grid_overlay.queue_redraw()
	if _show_hitboxes and _hitbox_overlay != null:
		_hitbox_overlay.queue_redraw()

# ── Desert worm spawn check — guaranteed spawn when player enters desert ──
var _last_player_biome: int = -2  # sentinel: unknown

func _check_desert_worm_spawn(_delta: float) -> void:
	var p := _get_player()
	if p == null:
		return

	var tile: Vector2i = ground_layer.local_to_map(ground_layer.to_local(p.global_position))
	var biome: int = _cell_biome_type(tile)

	if biome == 1 and _last_player_biome != 1:
		# Player just entered desert — spawn worms immediately (guaranteed)
		_spawn_desert_worms_near_player(WORM_SCENE, preload("res://resources/mobs/worm.tres"))
	_last_player_biome = biome

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
	# Structures sit in the middle of that priority order (cave > structures
	# > natural): they must run AFTER caves (so they skip cave chunks) but
	# BEFORE wolves/trees/grass (so natural stuff skips their chunks).
	_spawn_cave_entrances.call_deferred()
	# Pixie caves claim chunks just like regular caves (natural stuff skips
	# claimed chunks), so this runs right after _spawn_cave_entrances and
	# BEFORE structures/wolves/foliage. Must come after regular caves so the
	# three spawn rules can see which chunks already hold a large cave.
	_spawn_pixie_cave_entrances.call_deferred()
	_spawn_overworld_structures.call_deferred()
	_spawn_wolves.call_deferred()
	_spawn_desert_worms.call_deferred()
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
	_start_cactus_spawn_timer()
	generation_complete.emit()
	# Grass fill runs AFTER the player is already free to move, not before —
	# it's purely decorative and walkable (no collision; the y-sort covering
	# is handled per-frame by _update_grass_sort), so spawning thousands of
	# them synchronously here was the main remaining cause of "world loading
	# feels slow." _fill_all_chunks_with_grass() spreads its own work across
	# many frames internally (see GRASS_CHUNKS_PER_FRAME), so this call is
	# deliberately fire-and-forget, not awaited — tiles fill in progressively
	# in the background while the player is already exploring. Must still run
	# after _place_foliage() (needs _tree_occupied_tiles final) and after
	# apply_world_save_data() (needs _placed_blocks final so grass doesn't
	# overlap restored structures) — both already happened above.
	_fill_all_chunks_with_grass()

func _start_interaction_updater() -> void:
	# Immediate pass so trees near spawn are active the moment the player
	# appears. Grass has no equivalent — see _on_swing_performed.
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

# ── Tree leaf-fade driver (per-frame, ~nearby trees only) ────────────
# Called every frame from _process. A tree's canopy hides the player when
# the player's feet are NORTH of the trunk base (feet_y < base_y) and the
# player's sprite still overlaps the canopy's horizontal span — i.e. the
# player walked behind the tree. The tree's _set_canopy_fade lerps the leaf
# shader's fade uniform. A tree within the scan band but NOT behind (or one
# the player has just walked out from) gets an explicit 0.0 so it thins back
# out on its own; trees outside the band are skipped entirely (the group can
# number in the thousands).
func _update_tree_fade(delta: float) -> void:
	var p := _get_player()
	if p == null or not p.has_method("sort_feet_y"):
		return
	var feet_y: float = p.call("sort_feet_y")
	var px: float = p.global_position.x
	# Rough canopy half-width for an overlap test (48px half of a 96px
	# texture, with a little slack for the 1.15 scale).
	const CANOPY_HALF_W: float = 56.0
	# A tree farther than this from the player can't be occluding them, so
	# skip it entirely — avoids touching every tree's material each frame
	# (the group can count in the thousands).
	const SCAN_RADIUS: float = 96.0
	# Vertical reset window: the active fade band is (0, CANOPY_HEIGHT);
	# keep fading back down for this extra stretch south of it so the tree
	# has time to return to opaque before it's skipped.
	const RESET_WINDOW: float = 32.0
	for tree in get_tree().get_nodes_in_group("Tree"):
		if not is_instance_valid(tree):
			continue
		var t_node := tree as Node2D
		var base_y: float = t_node.global_position.y
		var base_x: float = t_node.global_position.x
		var behind: float = base_y - feet_y
		# Early-out: outside the canopy band AND horizontally well clear.
		if behind < -TREE_FADE_CANOPY_HEIGHT or behind > TREE_FADE_CANOPY_HEIGHT + RESET_WINDOW \
				or absf(px - base_x) > SCAN_RADIUS:
			continue
		# Positive when the player's feet are north of (behind) the base.
		var target: float = 0.0
		if behind > 0.0 and behind < TREE_FADE_CANOPY_HEIGHT \
				and absf(px - base_x) <= CANOPY_HALF_W:
			# Fade in over the first ~10px of overlap so it doesn't pop at
			# the base line; stays full for the rest of the canopy band.
			target = clampf(behind / 10.0, 0.0, 1.0)
		if tree.has_method("_set_canopy_fade"):
			tree.call("_set_canopy_fade", target, delta)

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
		push_warning("[Spawn] Failed to instantiate scene: ", scene.resource_path)
		return
	add_child(mob)
	mob.global_position = world_pos
	print("[Spawn] Spawned ", mob.name, " at tile=", tile, " pos=", world_pos)

# ── Periodic overworld spawner ───────────────────────────────────────
# A single unified check, cadence depending on time of day (Global.is_daytime)
# — every OUTER_SPAWN_INTERVAL_DAY by day, OUTER_SPAWN_INTERVAL_NIGHT by
# night. One-shot + self-rescheduled (rather than a fixed repeating Timer) so
# the interval adapts across a day/night crossing instead of being locked in
# at whatever it was when the Timer started.
func _start_outer_spawn_timer() -> void:
	print("[Spawn] _start_outer_spawn_timer called | is_day=", Global.is_daytime)
	var t := Timer.new()
	t.one_shot = true
	t.timeout.connect(_run_overworld_spawn.bind(t))
	add_child(t)
	t.start(OUTER_SPAWN_INTERVAL_DAY if Global.is_daytime else OUTER_SPAWN_INTERVAL_NIGHT)

# Every eligible outer chunk gets a spawn attempt each time this runs (not
# just one random chunk) — the timer's own day/night interval is what
# throttles frequency now, so there's no separate per-chunk cooldown to track.
func _run_overworld_spawn(t: Timer) -> void:
	print("[Spawn] _run_overworld_spawn called | is_day=", Global.is_daytime, " pool_size=", MOB_SPAWN_POOL.size())
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
		print("[Spawn] Pool: ", data.mob_name, " | day=", data.spawn_during_day, " night=", data.spawn_during_night, " eligible=", eligible_now, " is_day=", Global.is_daytime)
		if not eligible_now:
			continue
		# Desert worms use the special near-player spawner.  Keyed off the
		# AI type, NOT spawn_desert — spawn_desert is a biome-eligibility
		# flag that other mobs (e.g. the night Headless Fish) also use.
		if data.ai_type == "WORM":
			_spawn_desert_worms_near_player(pool_entry["scene"] as PackedScene, data)
			continue
		for chunk in eligible:
			var count: int = rng.randi_range(data.min_spawn, data.max_spawn)
			for _n in range(count):
				var tile = _random_valid_mob_tile_in_chunk(chunk, data)
				if tile == null:
					continue
				_spawn_mob_at(tile, pool_entry["scene"] as PackedScene)

	t.start(OUTER_SPAWN_INTERVAL_DAY if Global.is_daytime else OUTER_SPAWN_INTERVAL_NIGHT)

# ── Desert worm spawner — spawns near the player in desert chunks ──
func _spawn_desert_worms_near_player(scene: PackedScene, data: MobCombatData) -> void:
	var p := _get_player()
	if p == null:
		return

	# Count existing worms to cap at max_spawn
	var worm_count: int = 0
	for mob in get_tree().get_nodes_in_group("Worm"):
		if is_instance_valid(mob):
			worm_count += 1
	var max_to_spawn: int = mini(data.max_spawn - worm_count, 5)
	if max_to_spawn <= 0:
		return

	# Find a desert tile near the player by scanning outward in a spiral
	var player_tile: Vector2i = ground_layer.local_to_map(ground_layer.to_local(p.global_position))
	var spawned := 0
	for radius in range(3, 50):
		for _i in range(radius * 4):
			var angle: float = rng.randf() * TAU
			var dist:  float = float(radius)
			var check := Vector2i(
				player_tile.x + roundi(dist * cos(angle)),
				player_tile.y + roundi(dist * sin(angle)))
			if _cell_biome_type(check) == 1 and not _has_water_nearby(check, 3):
				_spawn_mob_at(check, scene)
				spawned += 1
				if spawned >= max_to_spawn:
					return
			if spawned >= max_to_spawn:
				return

# ── Mob preservation (save/load) ─────────────────────────────────────
func _is_in_preserve_zone(pos: Vector2, player_pos: Vector2) -> bool:
	if pos.distance_to(player_pos) <= MOB_PRESERVE_PLAYER_RADIUS:
		return true
	return pos.distance_to(_world_spawn_pos()) <= MOB_PRESERVE_SPAWN_RADIUS

func _collect_preserved_mobs() -> Array:
	var mobs_data: Array = []
	# The world can be off-tree when this runs (saves triggered during cave/
	# dungeon swaps remove World via remove_child) — get_tree() is null then.
	if get_tree() == null:
		return mobs_data
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
	# Same off-tree guard as _collect_preserved_mobs — restore runs while the
	# world may still be mid swap (apply_world_save_data during cave entry).
	if get_tree() == null:
		return
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
	_chunk_border_overlay.z_index = PLACEMENT_GUIDE_Z_INDEX
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
	# Above PLACEMENT_GUIDE_Z_INDEX (used by the block-placement grid,
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
		var node_ref: Variant = (entry as Dictionary)["node"]
		if not is_instance_valid(node_ref):
			continue
		var node: Node = node_ref as Node
		if node == null:
			continue
		if view_rect.has_point((node as Node2D).global_position):
			Global.draw_body_hitboxes(_hitbox_overlay, node, HITBOX_BLOCK_COLOR)
	# Grass tufts have no collision shape anymore (walkable — see
	# _update_grass_sort); this marker shows tile OCCUPANCY
	# (_grass_occupied_tiles), which is what cutting and placement gate on.
	for tile in _grass_occupied_tiles.keys():
		_draw_grass_tile_outline(tile as Vector2i, view_rect)

# This marker tracks tile OCCUPANCY (_grass_occupied_tiles) — what cutting
# and block placement gate on — rather than any physical collision box
# (grass has none since it became walkable). It stays a discrete "does
# this exact tile have grass" marker rather than trying to match the
# sprite. Two earlier rect-based attempts both misled: a tile-sized
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
	_cursor_highlight.queue_redraw()
	_cursor_highlight.visible = true

func _update_hover() -> void:
	if Global.block_mode:
		Global.set_hover("")
		return
	var mouse_pos: Vector2 = get_global_mouse_position()
	var best_name: String  = ""
	var best_name_dist: float = INTERACT_RADIUS_PX
	for entry in _placed_blocks.values():
		var node_ref: Variant = (entry as Dictionary)["node"]
		if not is_instance_valid(node_ref):
			continue
		var node: Node2D = node_ref as Node2D
		if node == null:
			continue
		var name_dist: float = mouse_pos.distance_to(node.global_position)
		if name_dist < best_name_dist:
			best_name_dist = name_dist
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
		or _is_tree_occupied(cell) or _grass_occupied_tiles.has(cell) \
		or _cave_entrance_cells.has(cell) or _dungeon_entrance_cells.has(cell)
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
	# Natural grass tufts own their tile just like placed blocks do — no
	# stacking blocks on top of uncut grass.
	if _grass_occupied_tiles.has(cell):
		return
	if _is_tree_occupied(cell):
		return
	if _cave_entrance_cells.has(cell) or _dungeon_entrance_cells.has(cell):
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
	# A small debris burst coloured like the block that was just placed.
	var place_tex: Texture2D = item_data.placeable_sprite if item_data.placeable_sprite != null else item_data.icon
	var place_burst: Node2D = OBJECT_BURST_SCRIPT.new() as Node2D
	if place_burst != null:
		place_burst.set("source_texture", place_tex)
		place_burst.set("tint", OBJECT_BURST_SCRIPT.average_color(place_tex))
		place_burst.set("amount", 8)
		add_child(place_burst)
		place_burst.global_position = world_pos + Vector2(0.0, -6.0)
	if item_data.has_place_animation and item_data.place_animation_name != "":
		var ap: AnimationPlayer = obj.get_node_or_null("AnimationPlayer") as AnimationPlayer
		if ap != null:
			ap.play(item_data.place_animation_name)
	Global.remove_item(item_data)
	# Track block placement for mission
	if _placed_blocks.size() >= 5:
		Global.complete_mission("place_blocks")
	if _placed_blocks.size() >= 10:
		Global.complete_mission("build_shelter")
	if item_data.item_name == "Torch" or item_data.item_name.to_lower().contains("torch"):
		Global.complete_mission("place_torch")

func unregister_block(cell: Vector2i) -> void:
	_placed_blocks.erase(cell)

# Returns a world position on a nearby open tile (no water, tree, placed
# block, painted cell, or dungeon/cave entrance — grass is walkable so
# grass tiles count as open), spiraling outward from `pos` up to
# `max_radius` tiles. Used by the player's stuck-unstuck teleport
# (player.gd) so it never dumps the player onto an obstacle or into a
# transition trigger. Returns Vector2.INF when nothing open is found.
func find_open_spot_near(pos: Vector2, max_radius: int) -> Vector2:
	var center_cell: Vector2i = ground_layer.local_to_map(ground_layer.to_local(pos))
	var half_w: int = width  / 2
	var half_h: int = height / 2
	for r in range(1, max_radius + 1):
		for dx in range(-r, r + 1):
			for dy in range(-r, r + 1):
				if maxi(absi(dx), absi(dy)) != r:
					continue
				var cell := center_cell + Vector2i(dx, dy)
				if not _is_open_for_player(cell, half_w, half_h):
					continue
				if _cave_entrance_cells.has(cell) or _dungeon_entrance_tiles.values().has(cell):
					continue
				return ground_layer.to_global(ground_layer.map_to_local(cell))
	return Vector2.INF

func _is_open_for_player(cell: Vector2i, half_w: int, half_h: int) -> bool:
	if absi(cell.x) >= half_w or absi(cell.y) >= half_h:
		return false
	if water_layer.get_cell_source_id(cell) != -1:
		return false
	if editable_layer.get_cell_source_id(cell) != -1:
		return false
	if structures_layer.get_cell_source_id(cell) != -1:
		return false
	if _cave_entrance_cells.has(cell) or _dungeon_entrance_cells.has(cell):
		return false
	if _is_tree_occupied(cell):
		return false
	# Grass is walkable (no collision — see _update_grass_sort), so grass
	# tiles count as open; the unstuck teleport may land in it.
	if _placed_blocks.has(cell):
		return false
	return true

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
	# restricted build zone matches the player's visual footprint. Mirrors
	# PlayerCol's waist-high box (20x12 at y 17) — keep in sync.
	const S: float = 0.980
	var half_w: float = 10.0 * S + 8.0
	var half_h: float = 6.0 * S + 8.0
	var player_local: Vector2 = editable_layer.to_local(p.global_position) + Vector2(0.0, 17.0 * S)
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
#   Row 1, cols 0-1  → snow (light grey, two variants)
#   Row 1, col 2     → desert (tan / sand)
#   Row 1, col 3     → ocean-coloured tile (not assigned to any biome)
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
			if a.x == 0 or a.x == 1: return 2  # snow (+ variant)
			if a.x == 2: return 1              # desert
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
		# Row 1: cols 0-1 = snow variants, col 2 = desert; col 3 is ocean — skip it.
		snow_cols.append(0)
		desert_cols.append(2 if _exp_ground_cols >= 3 else 1 if _exp_ground_cols >= 2 else 0)

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
	if structures_layer.get_cell_source_id(tile) != -1:
		return false
	if _cave_entrance_cells.has(tile) or _dungeon_entrance_cells.has(tile):
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
	# Appearance derives from the tile itself (see GrassTuft.setup), never the
	# sequential rng — so a tuft skipped here (e.g. under the player) can't
	# shift how every later tuft looks across restarts.
	tuft.setup(ground_anchor, tile)

	# Stores the tuft node itself (not just a bool) — _on_swing_performed
	# needs the actual node to drive the cut, and every other read site
	# (.has()/.erase()/.keys()) doesn't care about the value.
	_grass_occupied_tiles[tile] = tuft
	_grass_spawn_count += 1

# Seeded Fisher-Yates shuffle (Array.shuffle() uses the global RNG, which
# would break world-gen determinism from `random_seed`).
# Takes the rng explicitly so grass is a pure function of the chunk (see
# _fill_chunk_grass) rather than the shared _grass_rng stream, whose position
# drifts if regrow/interruption/gameplay changes call order.
func _shuffle_tiles(arr: Array, rng: RandomNumberGenerator) -> void:
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
func _cluster_tiles(arr: Array, target: int, rng: RandomNumberGenerator) -> void:
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
		_shuffle_tiles(dirs, rng)
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
	if _structure_claimed_chunks.has(chunk):
		return
	var half_w: int = width  / 2
	var half_h: int = height / 2
	var tl := Vector2i(chunk.x * CHUNK_SIZE - half_w, chunk.y * CHUNK_SIZE - half_h)

	# Plains-only — _is_valid_grass_tile rejects Desert/Snowy/Water outright.
	var eligible: Array = []
	for dx in range(CHUNK_SIZE):
		for dy in range(CHUNK_SIZE):
			var tile: Vector2i = tl + Vector2i(dx, dy)
			# Keep the world-spawn chunk clear so grass can't trap the player
			# right after spawning (grass is solid and must be cut).
			if tile.distance_to(Vector2i.ZERO) <= SPAWN_CLEAR_TILES:
				continue
			if _is_valid_grass_tile(tile):
				eligible.append(tile)
	if eligible.is_empty():
		return

	# Determinism: derive this chunk's rng from the world seed + chunk coords
	# so the grass pattern is a pure function of (seed, chunk) — immune to
	# the shared rng's position, which drifts with regrow, interruption, or
	# game state (e.g. which chunks have placed blocks). Same seed → same
	# grass on every load, regardless of call order.
	var chunk_rng := RandomNumberGenerator.new()
	chunk_rng.seed = int(random_seed) ^ (_chunk_hash(chunk))

	var coverage: float = chunk_rng.randf_range(GRASS_CHUNK_COVERAGE_MIN, GRASS_CHUNK_COVERAGE_MAX)
	var target:   int   = mini(ceili(eligible.size() * coverage), eligible.size())

	if chunk_rng.randf() < GRASS_GROUPED_CHANCE:
		_cluster_tiles(eligible, target, chunk_rng)
	else:
		_shuffle_tiles(eligible, chunk_rng)
	for i in range(target):
		_spawn_grass_at(eligible[i] as Vector2i)

# Stable per-(seed, chunk) hash so two chunks never collide to the same rng
# seed even across different seeds. Mixes the chunk coords with a large prime.
func _chunk_hash(chunk: Vector2i) -> int:
	var h: int = chunk.x * 374761393 + chunk.y * 668265263
	return h & 0x7FFFFFFF

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

# ── Cactus — a random desert tile grows one every 5 minutes ─────────────
func _start_cactus_spawn_timer() -> void:
	var t := Timer.new()
	t.wait_time = CACTUS_SPAWN_INTERVAL
	t.autostart = true
	t.timeout.connect(_spawn_cactus)
	add_child(t)

# Places a mineable Cactus (a PlaceableBlock) on a random desert tile. Any
# pickaxe (pickaxe_level >= 1) breaks it instantly — see cactus.tres.
func _spawn_cactus() -> void:
	var cell = _find_random_desert_tile()
	if cell == null:
		return
	var world_pos: Vector2 = editable_layer.map_to_local(cell)
	var obj: Node2D = CACTUS_SCENE.instantiate() as Node2D
	if obj == null:
		return
	if obj.has_method("setup"):
		obj.call("setup", CACTUS_DATA)
	_placed_blocks[cell] = {"node": obj, "name": CACTUS_DATA.item_name}
	if obj.has_method("set_world_cell"):
		obj.call("set_world_cell", cell, self)
	add_child(obj)
	if not is_instance_valid(obj):
		_placed_blocks.erase(cell)
		return
	obj.position = world_pos
	obj.z_index = int(world_pos.y / TILE_SIZE)

# A random desert (biome == 1) land tile that is clear of water, trees,
# grass, structures, caves, dungeons and already-placed blocks. Returns a
# Vector2i cell, or null when no valid tile was found in the attempts.
func _find_random_desert_tile() -> Variant:
	var half_w: int = width  / 2
	var half_h: int = height / 2
	for attempt in range(80):
		var cell := Vector2i(rng.randi_range(-half_w, half_w - 1),
							 rng.randi_range(-half_h, half_h - 1))
		if _cell_biome_type(cell) != 1:          # 1 == desert
			continue
		if _has_water_nearby(cell, 3):
			continue
		if _is_tree_occupied(cell) or _grass_occupied_tiles.has(cell):
			continue
		if _placed_blocks.has(cell) or editable_layer.get_cell_source_id(cell) != -1:
			continue
		if structures_layer != null and structures_layer.get_cell_source_id(cell) != -1:
			continue
		if _cave_entrance_cells.has(cell) or _dungeon_entrance_cells.has(cell):
			continue
		return cell
	return null

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
			tree_type_val = 0  # Plain
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
		if _is_chunk_structure_claimed(tile_coord):
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
	var half_w: int = width  / 2
	var half_h: int = height / 2
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
		if _is_chunk_structure_claimed(tile):
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
			if _is_chunk_structure_claimed(tile):
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
	var tree: Node2D = TREE_SCENE.instantiate() as Node2D
	if tree == null:
		return
	_tree_spawn_count += 1

	# Biome picks the sprite: snowy (type 2) uses the snow tree, everything
	# else uses the normal plains tree.
	var tree_tex: Texture2D = SNOWY_TREE_TEX if tree_type_val == 2 else PLAIN_TREE_TEX
	var sprite := tree.get_node_or_null("Sprite2D") as Sprite2D
	var frame_w: float = 32.0
	var frame_h: float = 32.0
	if sprite != null:
		sprite.texture  = tree_tex
		sprite.modulate = Color(1, 1, 1, 1)
		sprite.hframes  = 1
		sprite.vframes  = 1
		sprite.frame    = 0
		if sprite.texture != null:
			# Y-sort origin is the tree's TRUNK BASE, never the canopy. The
			# canopy texture is drawn upward with Sprite2D.offset — a draw-only
			# shift that does NOT move the sprite node — so the sprite's
			# transform (and therefore its y-sort position) stays anchored at
			# the trunk. Offsetting the node itself (sprite.position.y) would
			# make every tree sort ~half its height too far north.
			sprite.position = Vector2.ZERO
			sprite.offset = Vector2(0.0, -(sprite.texture.get_height() * 0.5))
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
	# world_pos is the tile's center; the sprite's draw-only offset (Sprite2D.offset,
	# which shifts the texture but not the node transform) means the tree's local
	# origin (this anchor point) IS the trunk's visual base regardless of
	# tree.scale, so +half a tile lands it exactly on the tile's bottom grid
	# line. TREE_BASE_EXTRA_OFFSET_PX is an extra empirical nudge on top of that
	# — the source art may have a little transparent padding under the trunk
	# that the exact math can't account for.
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
		if _is_chunk_structure_claimed(tile):
			continue
		var scatter_biome: int = _cell_biome_type(tile)
		if tree_type_val == 0 and scatter_biome != 0:
			continue
		if tree_type_val == 2 and scatter_biome != 2:
			continue
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
			if _is_chunk_structure_claimed(cell):
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

# ── Desert worm spawning during world-gen ──────────────────────────────
func _spawn_desert_worms() -> void:
	var half_w: int = width  / 2
	var half_h: int = height / 2
	var data: MobCombatData = preload("res://resources/mobs/worm.tres")
	var scene: PackedScene = WORM_SCENE

	# Collect all desert tiles near the map edges (far from player)
	var desert_tiles: Array[Vector2i] = []
	for xi in range(-half_w, half_w, 8):
		for yi in range(-half_h, half_h, 8):
			var cell := Vector2i(xi, yi)
			if _cell_biome_type(cell) == 1:
				if _has_water_nearby(cell, 3):
					continue
				if _is_chunk_cave_claimed(cell):
					continue
				desert_tiles.append(cell)

	# Spawn 3-6 worms in desert
	if desert_tiles.is_empty():
		return
	var to_spawn: int = mini(rng.randi_range(3, 6), desert_tiles.size())
	for i in range(to_spawn):
		var tile: Vector2i = desert_tiles[rng.randi_range(0, desert_tiles.size() - 1)]
		_spawn_mob_at(tile, scene)

# ── Cave entrance spawning ────────────────────────────────────────────
# One-shot, same timing as _spawn_wolves — a single roll per chunk, any land
# biome (Water excluded via _cell_biome_type() == -1; all-ocean chunks are
# skipped outright via _is_chunk_all_ocean()). Excluded entirely
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
			var chunk := Vector2i(cx, cy)
			if not _is_chunk_valid_for_structure(chunk):
				continue
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
			_cave_claimed_chunks[chunk] = true
			_cave_entrance_tiles.append(tile)
			_spawn_cave_entrance_at(tile)

func _is_chunk_cave_claimed(tile: Vector2i) -> bool:
	return _cave_claimed_chunks.has(_tile_to_chunk(tile))

func _is_chunk_structure_claimed(tile: Vector2i) -> bool:
	return _structure_claimed_chunks.has(_tile_to_chunk(tile))

# True when EVERY tile in the chunk is water (_cell_biome_type() == -1).
# Ocean chunks are excluded from every one-shot generation pass — dungeons,
# caves, structures and natural stuff all skip them (a single land check on
# one tile isn't enough; a chunk can be water on the sampled tile but mostly
# land, or the reverse).
func _is_chunk_all_ocean(chunk: Vector2i) -> bool:
	var half_w: int = width  / 2
	var half_h: int = height / 2
	var tl := Vector2i(chunk.x * CHUNK_SIZE - half_w, chunk.y * CHUNK_SIZE - half_h)
	for dx in range(CHUNK_SIZE):
		for dy in range(CHUNK_SIZE):
			if _cell_biome_type(tl + Vector2i(dx, dy)) != -1:
				return false
	return true

# True when the chunk has water anywhere inside it OR in a `margin`-tile ring
# around it. Coastline/edge chunks are marked invalid for generated
# structures so an entrance (the cave structure is 11x8 tiles) never straddles
# the shore or leaves a structure hanging over the water — a structure needs a
# chunk with enough solid land around it. Out-of-bounds tiles read as water
# (_cell_biome_type() == -1), so world-edge chunks are excluded too.
func _is_chunk_near_ocean(chunk: Vector2i, margin: int = 1) -> bool:
	var half_w: int = width  / 2
	var half_h: int = height / 2
	var tl := Vector2i(chunk.x * CHUNK_SIZE - half_w, chunk.y * CHUNK_SIZE - half_h)
	for dx in range(-margin, CHUNK_SIZE + margin):
		for dy in range(-margin, CHUNK_SIZE + margin):
			if _cell_biome_type(tl + Vector2i(dx, dy)) == -1:
				return true
	return false

# Combined gate used by every generated-structure spawner (caves, structures,
# dungeons): the chunk must be solid land with room to spare, never touching
# the ocean.
func _is_chunk_valid_for_structure(chunk: Vector2i) -> bool:
	return not _is_chunk_all_ocean(chunk) and not _is_chunk_near_ocean(chunk)

func _spawn_cave_entrance_at(tile: Vector2i) -> void:
	var portal := CavePortal.new()
	portal.mode      = CavePortal.Mode.ENTER
	portal.cave_seed = rng.randi()

	if _cave_entrance_pool.is_empty():
		_cave_entrance_pool = _load_cave_entrance_structures()

	var placed: Dictionary = {}
	if not _cave_entrance_pool.is_empty():
		var s := _cave_entrance_pool[_cave_entrance_tiles.size() % _cave_entrance_pool.size()] as GeneratedStructure
		placed = _place_cave_entrance_structure(s, tile)

	add_child(portal)
	if placed.is_empty():
		# No structure could be placed (missing resource / no free footprint) —
		# fall back to the old single-tile marker so the cave stays reachable.
		portal.global_position = ground_layer.to_global(ground_layer.map_to_local(tile))
		return
	portal.global_position = ground_layer.to_global(ground_layer.map_to_local(placed["door_tile"] as Vector2i))
	portal.set_interact_rect(placed["world_rect"] as Rect2)
	portal.set_door_rect(placed["door_rect"] as Rect2)
	portal.set_highlight_cells(placed["highlight_cells"] as Array[Rect2])
	_cave_entrance_nodes[tile] = placed["root"]

# ── Pixie-cave entrance spawn (one-shot, same timing as regular caves) ──
# One attempt per chunk subject to three rules (per the spec):
#   1. the chunk must NOT already hold a large (regular) cave entrance
#      (checked against _cave_claimed_chunks, which regular caves filled
#      in the pass that runs just before this one);
#   2. the chunk must be solid land not touching the ocean
#      (_is_chunk_valid_for_structure — same gate every structure spawner
#      uses, so a pixie entrance never straddles the shore);
#   3. the chosen tile must be > PIXIE_CAVE_SPAWN_MIN_DIST from world spawn.
# Plus a min-separation from ALL existing entrances (regular AND pixie) so a
# pixie portal never lands on top of a regular cave mouth or another pixie.
# The chunk is then claimed in the SAME _cave_claimed_chunks dict regular
# caves use, so structures/trees/grass/wolves skip it just like a cave chunk.
func _spawn_pixie_cave_entrances() -> void:
	if _pixie_cave_entrance_pool.is_empty():
		_pixie_cave_entrance_pool = _load_pixie_cave_entrance_structures()
	if _pixie_cave_entrance_pool.is_empty():
		return  # no pixie_cave_entrance.tres authored yet — nothing to spawn
	var half_w: int = width  / 2
	var half_h: int = height / 2
	for cx in range(_chunk_cols):
		for cy in range(_chunk_rows):
			var chunk := Vector2i(cx, cy)
			# Rule 2: solid land, not near ocean.
			if not _is_chunk_valid_for_structure(chunk):
				continue
			# Rule 1: chunk must not already hold a large (regular) cave.
			if _cave_claimed_chunks.has(chunk):
				continue
			if rng.randf() >= PIXIE_CAVE_ENTRANCE_CHANCE:
				continue
			var tl: Vector2i = Vector2i(cx * CHUNK_SIZE - half_w, cy * CHUNK_SIZE - half_h)
			var tile: Vector2i = tl + Vector2i(rng.randi_range(0, CHUNK_SIZE - 1), rng.randi_range(0, CHUNK_SIZE - 1))
			# Land tile (the chunk gate already excludes all-ocean chunks, but
			# the sampled tile could still be water — skip those too).
			if _cell_biome_type(tile) == -1:
				continue
			# Rule 3: not within 100 blocks of the world spawn point (tile 0,0).
			if tile.distance_to(Vector2i.ZERO) < PIXIE_CAVE_SPAWN_MIN_DIST:
				continue
			# Min-separation from every existing entrance (regular + pixie).
			var too_close: bool = false
			for placed in _cave_entrance_tiles:
				if tile.distance_to(placed as Vector2i) < PIXIE_CAVE_ENTRANCE_MIN_SEPARATION:
					too_close = true
					break
			if not too_close:
				for placed in _pixie_cave_entrance_tiles:
					if tile.distance_to(placed as Vector2i) < PIXIE_CAVE_ENTRANCE_MIN_SEPARATION:
						too_close = true
						break
			if too_close:
				continue
			# Claim the chunk so the later structure/natural passes skip it.
			_cave_claimed_chunks[chunk] = true
			_pixie_cave_entrance_tiles.append(tile)
			_spawn_pixie_cave_entrance_at(tile)

# Mirrors _spawn_cave_entrance_at, but uses the pixie pool and flags the
# portal as a pixie cave (portal.cave_type = "pixie" — what game_instance.gd's
# enter_cave dispatches on to build a PixieCaveWorld). Shares
# _cave_entrance_cells / _cave_entrance_nodes with regular caves so the
# overlap/nearest-cave logic doesn't need a parallel pixie version.
func _spawn_pixie_cave_entrance_at(tile: Vector2i) -> void:
	var portal := CavePortal.new()
	portal.mode      = CavePortal.Mode.ENTER
	portal.cave_seed = rng.randi()
	portal.cave_type = "pixie"

	var placed: Dictionary = {}
	if not _pixie_cave_entrance_pool.is_empty():
		var s := _pixie_cave_entrance_pool[_pixie_cave_entrance_tiles.size() % _pixie_cave_entrance_pool.size()] as GeneratedStructure
		placed = _place_cave_entrance_structure(s, tile)

	add_child(portal)
	if placed.is_empty():
		portal.global_position = ground_layer.to_global(ground_layer.map_to_local(tile))
		return
	portal.global_position = ground_layer.to_global(ground_layer.map_to_local(placed["door_tile"] as Vector2i))
	portal.set_interact_rect(placed["world_rect"] as Rect2)
	portal.set_door_rect(placed["door_rect"] as Rect2)
	portal.set_highlight_cells(placed["highlight_cells"] as Array[Rect2])
	_cave_entrance_nodes[tile] = placed["root"]

# ── Cave entrance structures ─────────────────────────────────────────
# The overworld cave entrances are painted as per-cell Sprite2D nodes instead
# of the Structures TileMapLayer — the layer is ONE canvas item pinned at
# World's origin (y=0), so it can never y-sort against the player (same
# reason the dungeon entrance uses _spawn_dungeon_entrance_nodes). Each cell
# sprite anchors at its own tile center and gets the same quantized
# z_index = int(y / TILE_SIZE) the player uses, so each row sorts correctly
# (player walks behind the rock above, in front of the rock below).
#
# Collision is added ONLY on present pixels: every cell's solid area is
# shrunk to the bounding box of its opaque pixels (see _cell_solid_rects /
# _opaque_bbox_in_image), and fully-transparent cells get no body at all — so
# the player slides along the rock's actual shape instead of hitting invisible
# full-tile boxes. The entrance's door cells (door_rect) anchor the structure
# to the requested tile but stay solid like the rest of the rock: entry is a
# click + confirm, not a physical walk-through.
#
# Returns {"door_tile", "world_rect", "door_rect", "highlight_cells", "root"};
# empty when no valid footprint was found within the search radius.
func _place_cave_entrance_structure(s: GeneratedStructure, portal_tile: Vector2i) -> Dictionary:
	var door_cell: Vector2i = s.door_center_cell()
	var ideal_anchor: Vector2i = portal_tile - door_cell
	# Anchor candidates walk a 5x5 search around the ideal anchor (door dead
	# center of the portal tile) so water/trees in the footprint can't veto the
	# whole entrance. Offsets are tried nearest-first.
	var offsets: Array[Vector2i] = []
	for dy in range(-2, 3):
		for dx in range(-2, 3):
			offsets.append(Vector2i(dx, dy))
	offsets.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return a.length_squared() < b.length_squared())
	for offset in offsets:
		var anchor: Vector2i = ideal_anchor + offset
		if not _structure_footprint_valid(s, anchor, Vector2i(-1, -1)):
			continue
		var result := _spawn_cave_entrance_nodes(s, anchor)
		for cell in result["cells"]:
			_cave_entrance_cells[cell as Vector2i] = true
		_claim_structure_chunks(s, anchor)
		# NOTE: the old dark cave_base ground ring (_paint_cave_base_ground)
		# is intentionally NOT painted — it read as a large black band around
		# the new cave sprites. The semi-transparent cave trails now provide
		# the ground transition around every cave entrance (large AND pixie).
		_scatter_cave_trails(anchor, s)
		var world_tl: Vector2 = ground_layer.to_global(ground_layer.map_to_local(anchor)) \
			- Vector2(TILE_SIZE / 2.0, TILE_SIZE / 2.0)
		# The structure's painted footprint, not the full tile grid: a sprite
		# that isn't an exact multiple of TILE_PX (342px cave sprite vs 352px
		# claimed) would leave the highlight/click box sticking past the rock.
		var sprite_w: int = mini(s.sprite.get_width(), s.tile_width * TILE_SIZE)
		var sprite_h: int = mini(s.sprite.get_height(), s.tile_height * TILE_SIZE)
		# World rect of the entrance opening itself (the dark door_rect cells on
		# the structure grid) — the portal highlights just this, not the rock.
		# A structure without a door_rect (-1,-1) gets a zero rect, which makes
		# the portal fall back to highlighting the whole structure.
		var door_rect_world := Rect2()
		if s.door_rect.position.x >= 0:
			var door_world_tl: Vector2 = ground_layer.to_global(
				ground_layer.map_to_local(anchor + s.door_rect.position)) - Vector2(TILE_SIZE / 2.0, TILE_SIZE / 2.0)
			door_rect_world = Rect2(door_world_tl, Vector2(s.door_rect.size) * TILE_SIZE)
		# Optional hand-painted highlight: every cell marked on the structure's
		# highlight_mask (a tile_width x tile_height pixel grid) gets its own
		# world rect. Empty when no mask is set — the portal then uses door_rect.
		var highlight_cells: Array[Rect2] = []
		var mask: Texture2D = s.highlight_mask
		if mask != null:
			var mask_img := mask.get_image()
			if mask_img == null:
				push_warning("World: highlight_mask has no image — falling back to door_rect for %s" % s.name)
			elif mask_img.get_width() != s.tile_width or mask_img.get_height() != s.tile_height:
				push_warning("World: highlight_mask size %dx%d doesn't match %s grid %dx%d — falling back to door_rect" % [
					mask_img.get_width(), mask_img.get_height(), s.name, s.tile_width, s.tile_height])
			else:
				for my in range(mask_img.get_height()):
					for mx in range(mask_img.get_width()):
						if mask_img.get_pixel(mx, my).a <= 0.5:
							continue
						var cell: Vector2i = anchor + Vector2i(mx, my)
						var cell_tl: Vector2 = ground_layer.to_global(ground_layer.map_to_local(cell)) \
							- Vector2(TILE_SIZE / 2.0, TILE_SIZE / 2.0)
						highlight_cells.append(Rect2(cell_tl, Vector2(TILE_SIZE, TILE_SIZE)))
		_located_structures.append({"name": s.name, "tile": portal_tile})
		return {
			"door_tile": anchor + door_cell,
			"world_rect": Rect2(world_tl, Vector2(sprite_w, sprite_h)),
			"door_rect": door_rect_world,
			"highlight_cells": highlight_cells,
			"root": result["root"],
		}
	push_warning("World: no free footprint for cave entrance at %s — portal still spawned" % str(portal_tile))
	return {}

# ── Large cave ground trails ─────────────────────────────────────────
# Lazy-load the trail decal textures from the large_cave_trails0X items so
# the dev items stay the single source of truth for their sheet regions.
func _get_cave_trail_textures() -> Array:
	if not _cave_trail_textures.is_empty():
		return _cave_trail_textures
	for path in CAVE_TRAIL_ITEM_PATHS:
		var item: Resource = load(path)
		if item == null:
			continue
		var icon: Texture2D = item.get("icon") as Texture2D
		if icon != null:
			_cave_trail_textures.append(icon)
	return _cave_trail_textures

# Trails live as Sprite2D children of the Ground TileMapLayer: the layer is
# pinned at World's origin, so its children draw immediately above the biome
# tiles but below every other layer (Editable/Structures), entity and the
# cave rock itself. No collision, no tile writes — the ground underneath is
# untouched and the decal's own alpha is preserved.
func _get_cave_trails_root() -> Node2D:
	if _cave_trails_root != null and is_instance_valid(_cave_trails_root):
		return _cave_trails_root
	if ground_layer == null:
		return null
	_cave_trails_root = Node2D.new()
	_cave_trails_root.name = "CaveTrails"
	ground_layer.add_child(_cave_trails_root)
	return _cave_trails_root

# Scatter semi-transparent trail decals on the tile grid around the cave:
# walk outward ring by ring from the footprint and drop a decal on a ring
# tile (with a per-ring chance). Every decal is centred on a tile and
# rotated in 90° steps, so the trails line up with the tiling system.
func _scatter_cave_trails(anchor: Vector2i, s: GeneratedStructure) -> void:
	var textures := _get_cave_trail_textures()
	if textures.is_empty():
		return
	var root := _get_cave_trails_root()
	if root == null:
		return
	var used: Dictionary = {}
	for ring in range(1, CAVE_TRAIL_RING_TILES + 1):
		var chance: float = CAVE_TRAIL_INNER_CHANCE if ring == 1 else CAVE_TRAIL_OUTER_CHANCE
		for cell in _structure_ring_cells(anchor, s.tile_width, s.tile_height, ring):
			if used.has(cell):
				continue
			used[cell] = true
			# Never paint trails on water (a cave hugging the shore).
			if _cell_biome_type(cell) == -1:
				continue
			if rng.randf() > chance:
				continue
			var pos: Vector2 = ground_layer.to_global(ground_layer.map_to_local(cell))
			_add_cave_trail_decal(root, textures, pos)

# The ring of cells exactly `ring` tiles outside a tile_width x tile_height
# footprint anchored at `anchor` (no duplicates, border-only).
func _structure_ring_cells(anchor: Vector2i, tw: int, th: int, ring: int) -> Array:
	var cells: Array = []
	var x0: int = anchor.x - ring
	var x1: int = anchor.x + tw - 1 + ring
	var y0: int = anchor.y - ring
	var y1: int = anchor.y + th - 1 + ring
	for x in range(x0, x1 + 1):
		cells.append(Vector2i(x, y0))
		cells.append(Vector2i(x, y1))
	for y in range(y0 + 1, y1):
		cells.append(Vector2i(x0, y))
		cells.append(Vector2i(x1, y))
	return cells

func _add_cave_trail_decal(root: Node2D, textures: Array, pos: Vector2) -> void:
	var sprite := Sprite2D.new()
	sprite.texture = textures[rng.randi() % textures.size()]
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sprite.global_position = pos
	# Random 90° rotation + mirror gives 8 pattern variants from one tile.
	sprite.rotation = rng.randi_range(0, 3) * (PI * 0.5)
	sprite.flip_h = rng.randf() < 0.5
	sprite.flip_v = rng.randf() < 0.5
	# Small alpha jitter only — the decal's own semi-transparency stays.
	sprite.modulate = Color(1, 1, 1, rng.randf_range(0.85, 1.0))
	root.add_child(sprite)

func _spawn_cave_entrance_nodes(s: GeneratedStructure, anchor: Vector2i) -> Dictionary:
	var root := Node2D.new()
	root.name = "CaveEntrance"
	add_child(root)

	# The structure sprite may be an AtlasTexture region into a shared sheet;
	# the per-cell AtlasTextures must unwrap it to the BASE texture + the
	# region origin so each cell's region lands on the right pixels (see
	# cave_world.gd's _add_icon_source for the same unwrap pattern).
	var base_tex: Texture2D   = s.sprite
	var base_origin: Vector2i = Vector2i.ZERO
	var sprite_atlas := s.sprite as AtlasTexture
	if sprite_atlas != null:
		base_tex    = sprite_atlas.atlas
		base_origin = Vector2i(sprite_atlas.region.position.round())

	var tex_w: int = base_tex.get_width()
	var tex_h: int = base_tex.get_height()
	var solid_rects: Dictionary = _cell_solid_rects(s)

	var cells: Array = []
	for y in range(s.tile_height):
		for x in range(s.tile_width):
			var cell: Vector2i = anchor + Vector2i(x, y)
			var region_origin: Vector2i = base_origin + Vector2i(x * GeneratedStructure.TILE_PX, y * GeneratedStructure.TILE_PX)
			var region := Rect2i(region_origin, Vector2i(GeneratedStructure.TILE_PX, GeneratedStructure.TILE_PX))
			# The sprite isn't guaranteed to be an exact multiple of TILE_PX —
			# clamp the last column/row to the texture's real bounds.
			region.size.x = mini(region.size.x, tex_w - region_origin.x)
			region.size.y = mini(region.size.y, tex_h - region_origin.y)
			if region.size.x <= 0 or region.size.y <= 0:
				continue

			var cell_tex := AtlasTexture.new()
			cell_tex.atlas  = base_tex
			cell_tex.region = Rect2(region)
			var sprite := Sprite2D.new()
			sprite.texture = cell_tex
			root.add_child(sprite)
			sprite.global_position = ground_layer.to_global(ground_layer.map_to_local(cell))
			# A partial edge cell (the sprite isn't an exact multiple of
			# TILE_PX, e.g. the cave sprite is 342px wide = 10 full columns +
			# a 22px last one) is drawn FLUSH with the tile's top-left instead
			# of centered on the tile. Centered, the clipped column floats
			# mid-tile and leaves a see-through slit between it and the
			# neighbouring cell (and its collision drifts off the rock).
			if region.size.x < GeneratedStructure.TILE_PX:
				sprite.global_position.x -= (GeneratedStructure.TILE_PX - region.size.x) / 2.0
			if region.size.y < GeneratedStructure.TILE_PX:
				sprite.global_position.y -= (GeneratedStructure.TILE_PX - region.size.y) / 2.0
			sprite.z_index         = int(sprite.global_position.y / TILE_SIZE)

			cells.append(cell)

			# The door cell is the walkable opening — the player walks through
			# it (the click/confirm portal still sits on it). Every other cell
			# gets pixel collision from its opaque pixels.
			if s.is_door_cell(x, y):
				continue
			var solid: Rect2i = solid_rects.get(Vector2i(x, y), Rect2i(Vector2i.ZERO, Vector2i.ZERO)) as Rect2i
			if solid.size == Vector2i.ZERO:
				continue
			var body := StaticBody2D.new()
			body.collision_layer = 1
			body.collision_mask  = 1
			var shape := CollisionShape2D.new()
			var rect := RectangleShape2D.new()
			rect.size = Vector2(solid.size)
			shape.shape = rect
			body.add_child(shape)
			root.add_child(body)
			var cell_world: Vector2 = ground_layer.to_global(ground_layer.map_to_local(cell))
			var solid_offset: Vector2 = Vector2(solid.position) - Vector2(GeneratedStructure.TILE_PX / 2.0, GeneratedStructure.TILE_PX / 2.0)
			body.global_position = cell_world + solid_offset

	return {"cells": cells, "root": root}

# ── Cave base ground ring ─────────────────────────────────────────────
# The rock's bottom row meets the ground at a hard grass edge — replace the
# ground tiles immediately around the base (a U-ring: the row below the
# structure plus the single cells flanking its bottom row) with the cave_base
# tile (cave_base.png), so the cave reads as planted in dark soil rather than
# dropped on bright grass. Water cells are skipped so a cave hugging the
# shore doesn't paint over the ocean.
func _paint_cave_base_ground(s: GeneratedStructure, anchor: Vector2i) -> void:
	var src: int = _get_cave_base_ground_src()
	if src == -1:
		return
	var ring: Array[Vector2i] = [
		Vector2i(anchor.x - 1, anchor.y + s.tile_height - 1),
		Vector2i(anchor.x + s.tile_width, anchor.y + s.tile_height - 1),
	]
	for x in range(anchor.x - 1, anchor.x + s.tile_width + 1):
		ring.append(Vector2i(x, anchor.y + s.tile_height))
	for cell in ring:
		if water_layer.get_cell_source_id(cell) != -1:
			continue
		ground_layer.set_cell(cell, src, Vector2i.ZERO)

# Registers (once, lazily) the cave_base.png tile as a ground-tile source.
# Returns the tile source id, or -1 when the texture is missing.
func _get_cave_base_ground_src() -> int:
	if _cave_base_ground_src != -1:
		return _cave_base_ground_src
	var tex := load("res://sprites/cave/cave_base.png") as Texture2D
	if tex == null:
		return -1
	_cave_base_ground_tex = tex
	var src := TileSetAtlasSource.new()
	src.texture             = _cave_base_ground_tex
	src.texture_region_size = Vector2i(TILE_SIZE, TILE_SIZE)
	src.create_tile(Vector2i.ZERO)
	_cave_base_ground_src = ground_layer.tile_set.add_source(src)
	return _cave_base_ground_src

# ── Cave structure pixel collision ────────────────────────────────────
# The sprite's opaque pixels are scanned ONCE per structure (cached — every
# cave entrance shares the same resource instance) and each cell maps to the
# local bounding box of its solid pixels, or is absent when the cell has no
# pixels at all.
static var _cave_structure_bbox_cache: Dictionary = {}  # GeneratedStructure -> {Vector2i cell: Rect2i}

static func _cell_solid_rects(s: GeneratedStructure) -> Dictionary:
	if _cave_structure_bbox_cache.has(s):
		return _cave_structure_bbox_cache[s] as Dictionary
	var solid: Dictionary = {}
	var base_tex: Texture2D   = s.sprite
	var base_origin: Vector2i = Vector2i.ZERO
	var sprite_atlas := s.sprite as AtlasTexture
	if sprite_atlas != null:
		base_tex    = sprite_atlas.atlas
		base_origin = Vector2i(sprite_atlas.region.position.round())
	if base_tex != null:
		var img: Image = base_tex.get_image()
		if img != null:
			img.convert(Image.FORMAT_RGBA8)
			var tex_w: int = img.get_width()
			var tex_h: int = img.get_height()
			var data: PackedByteArray = img.get_data()
			for y in range(s.tile_height):
				for x in range(s.tile_width):
					var region := Rect2i(
						base_origin + Vector2i(x * GeneratedStructure.TILE_PX, y * GeneratedStructure.TILE_PX),
						Vector2i(GeneratedStructure.TILE_PX, GeneratedStructure.TILE_PX))
					region.size.x = mini(region.size.x, tex_w - region.position.x)
					region.size.y = mini(region.size.y, tex_h - region.position.y)
					var bbox := _opaque_bbox_in_image(data, tex_w, region)
					if bbox.size != Vector2i.ZERO:
						solid[Vector2i(x, y)] = bbox
	_cave_structure_bbox_cache[s] = solid
	return solid

# Local bounding box (relative to the cell's region) of pixels with alpha
# > 0.1 in a packed RGBA8 image. Zero size when the cell has no pixels.
static func _opaque_bbox_in_image(data: PackedByteArray, tex_w: int, region: Rect2i) -> Rect2i:
	var minp := Vector2i(region.end.x, region.end.y)
	var maxp := Vector2i(region.position.x - 1, region.position.y - 1)
	for y in range(region.position.y, region.end.y):
		var row_base: int = y * tex_w
		for x in range(region.position.x, region.end.x):
			if data[(row_base + x) * 4 + 3] > 25:
				if x < minp.x: minp.x = x
				if y < minp.y: minp.y = y
				if x > maxp.x: maxp.x = x
				if y > maxp.y: maxp.y = y
	if maxp.x < minp.x:
		return Rect2i(Vector2i.ZERO, Vector2i.ZERO)
	return Rect2i(minp - region.position, maxp - minp + Vector2i.ONE)

# ── Overworld structure spawning ──────────────────────────────────────
# Second in the chunk-priority order (dungeon > cave > structures > natural
# stuff): runs AFTER _spawn_cave_entrances() so cave-claimed chunks are
# already excluded, and BEFORE _spawn_wolves/_deferred_foliage so trees and
# grass skip the chunks a structure claims. All-ocean chunks are skipped.
# Runs on the seeded world rng (iterating chunks in order, no shuffle) so a
# given world seed reproduces the same structures.
func _spawn_overworld_structures() -> void:
	var structures: Array = _load_overworld_structures()
	if structures.is_empty():
		return
	_prepare_structure_tileset(structures)
	var half_w: int = width  / 2
	var half_h: int = height / 2
	var spawned: int = 0
	for cx in range(_chunk_cols):
		for cy in range(_chunk_rows):
			var chunk := Vector2i(cx, cy)
			if _structure_claimed_chunks.has(chunk):
				continue
			if not _is_chunk_valid_for_structure(chunk):
				continue
			if _cave_claimed_chunks.has(chunk):
				continue
			if rng.randf() >= STRUCTURE_CHANCE:
				continue
			var s := structures[rng.randi_range(0, structures.size() - 1)] as GeneratedStructure
			var tl := Vector2i(chunk.x * CHUNK_SIZE - half_w, chunk.y * CHUNK_SIZE - half_h)
			for _attempt in range(60):
				var anchor: Vector2i = tl + Vector2i(rng.randi_range(0, CHUNK_SIZE - 1), rng.randi_range(0, CHUNK_SIZE - 1))
				if not _can_place_structure(s, anchor):
					continue
				_spawn_structure(s, anchor)
				spawned += 1
				break
	print("[STRUCTURES] placed %d overworld structures" % spawned)

# Load every GeneratedStructure .tres in STRUCTURES_DIR flagged to spawn in
# the overworld. Adding a new .tres to that folder is all it takes to put a
# structure into the pool — no per-resource wiring in code.
# NOTE: type == "dungeon entrances" AND the cave entrance types (cave1-3,
# pixie cave) are deliberately excluded from this random pool — those are only
# ever placed as the entrance of a dungeon mission / cave entrance (see
# _place_dungeon_entrance_structure / _spawn_cave_entrance_at), never scattered.
func _load_overworld_structures() -> Array:
	var out: Array = []
	for res in _scan_structure_dir():
		var s := res as GeneratedStructure
		if s.spawn_world == "overworld" and not _is_entrance_structure_type(s.type) \
				and s.type != "dungeon entrances":
			out.append(s)
	return out

# Every GeneratedStructure with type == "dungeon entrances" (and spawn_world
# == "overworld") — the visual entrance used by EVERY dungeon mission. One
# per mission is picked round-robin from this pool by dungeon_index, so
# adding more .tres of this type gives later dungeons their own look.
func _load_dungeon_entrance_structures() -> Array:
	var out: Array = []
	for res in _scan_structure_dir():
		var s := res as GeneratedStructure
		if s.spawn_world == "overworld" and s.type == "dungeon entrances":
			out.append(s)
	return out

# Every GeneratedStructure with a cave entrance type (cave1/cave2/cave3 —
# NOT pixie cave, which has its own pool/loader) — the large-cave structure
# used by the overworld cave entrances (see _spawn_cave_entrance_at). Picked
# round-robin per entrance.
func _load_cave_entrance_structures() -> Array:
	var out: Array = []
	for res in _scan_structure_dir():
		var s := res as GeneratedStructure
		if s.spawn_world == "overworld" and _is_entrance_structure_type(s.type) and s.type != "pixie cave":
			out.append(s)
	return out

# Every GeneratedStructure with type == "pixie cave" — the entrance used by
# the pixie-cave spawn pass (see _spawn_pixie_cave_entrances, added in a later
# task). Kept separate from the regular cave pool so normal cave entrances
# never drop the player into a pixie cave.
func _load_pixie_cave_entrance_structures() -> Array:
	var out: Array = []
	for res in _scan_structure_dir():
		var s := res as GeneratedStructure
		if s.spawn_world == "overworld" and s.type == "pixie cave":
			out.append(s)
	return out

func _is_entrance_structure_type(structure_type: String) -> bool:
	# The CAVE entrance types — used by _load_cave_entrance_structures to pick
	# the cave pool, and by _load_overworld_structures to exclude them. NOTE:
	# "dungeon entrances" is deliberately NOT here — the dungeon pool has its
	# own loader and is excluded from the random overworld pass separately (see
	# _load_overworld_structures), so adding it here would leak it into the
	# cave entrance pool and scatter dungeons at world creation.
	return structure_type in ["cave1", "cave2", "cave3", "pixie cave"]

func _scan_structure_dir() -> Array:
	var out: Array = []
	var dir := DirAccess.open(STRUCTURES_DIR)
	if dir == null:
		return out
	dir.list_dir_begin()
	var file_name: String = dir.get_next()
	while file_name != "":
		if not dir.current_is_dir() and file_name.ends_with(".tres"):
			var res: Resource = load(STRUCTURES_DIR + file_name)
			if res is GeneratedStructure:
				var s := res as GeneratedStructure
				if s.is_valid():
					out.append(s)
		file_name = dir.get_next()
	dir.list_dir_end()
	return out

# Each structure's sprite becomes a TileSetAtlasSource (32x32 cells) in the
# Structures layer's TileSet, with a full-cell collision polygon so a
# structure blocks the player and item repel the same way a placed block
# does. The source id per structure is cached in _structure_sources.
func _prepare_structure_tileset(structures: Array) -> void:
	if structures_layer == null:
		return
	var ts: TileSet = structures_layer.tile_set
	if ts == null:
		ts = TileSet.new()
		structures_layer.tile_set = ts
	if ts.tile_size != Vector2i(TILE_SIZE, TILE_SIZE):
		ts.tile_size = Vector2i(TILE_SIZE, TILE_SIZE)
	if ts.get_physics_layers_count() == 0:
		ts.add_physics_layer()
	ts.set_physics_layer_collision_layer(0, 1)
	ts.set_physics_layer_collision_mask(0, 1)
	for s in structures:
		var struct := s as GeneratedStructure
		if _structure_sources.has(struct):
			continue
		var src := TileSetAtlasSource.new()
		src.texture             = struct.sprite
		src.texture_region_size = Vector2i(TILE_SIZE, TILE_SIZE)
		for col in range(struct.tile_width):
			for row in range(struct.tile_height):
				var atl := Vector2i(col, row)
				src.create_tile(atl)
				var td := src.get_tile_data(atl, 0)
				if td != null:
					td.add_collision_polygon(0)
					td.set_collision_polygon_points(0, 0, PackedVector2Array([
						Vector2(-16, -16), Vector2(16, -16), Vector2(16, 16), Vector2(-16, 16),
					]))
		_structure_sources[struct] = ts.add_source(src)

# A structure can sit here only if every cell of its tile_width x tile_height
# footprint is in-bounds, land (not water), free of trees/placed blocks/other
# structure cells, outside STRUCTURE_MIN_SPAWN_DIST of world spawn, and not
# within STRUCTURE_MIN_SEPARATION of another structure's anchor.
func _can_place_structure(s: GeneratedStructure, anchor: Vector2i) -> bool:
	if anchor.distance_to(Vector2i.ZERO) < STRUCTURE_MIN_SPAWN_DIST:
		return false
	if not _structure_footprint_valid(s, anchor, Vector2i(-1, -1)):
		return false
	for placed in _structure_anchor_tiles:
		if anchor.distance_to(placed as Vector2i) < STRUCTURE_MIN_SEPARATION:
			return false
	return true

func _spawn_structure(s: GeneratedStructure, anchor: Vector2i) -> void:
	_paint_structure(s, anchor, Vector2i(-1, -1))
	_claim_structure_chunks(s, anchor)
	_structure_anchor_tiles.append(anchor)
	_located_structures.append({"name": s.name, "tile": anchor})

# Names of every structure resource in STRUCTURES_DIR (the /locate autocomplete
# source) — ALL types, including cave/pixie/dungeon entrances.
func get_available_structure_names() -> Array:
	var names: Array = []
	for res in _scan_structure_dir():
		var s := res as GeneratedStructure
		var n: String = s.name
		if not n.is_empty() and not names.has(n):
			names.append(n)
	return names

# Nearest placed structure/entrance whose .name matches `structure_name`
# (case-insensitive), measured from the player. Returns Vector2.INF when none
# exists (or none of that name was placed). Used by the /locate chat command.
func locate_nearest_structure(structure_name: String) -> Vector2:
	if _located_structures.is_empty():
		return Vector2.INF
	var query: String = structure_name.strip_edges().to_lower()
	var player_tile := Vector2i.ZERO
	var player: Node2D = Global.player_node as Node2D
	if player != null:
		player_tile = ground_layer.local_to_map(ground_layer.to_local(player.global_position))
	var best: Vector2i = Vector2i.ZERO
	var best_dist: float = INF
	var found: bool = false
	for entry in _located_structures:
		var nm: String = str((entry as Dictionary)["name"]).to_lower()
		if query != "" and nm != query:
			continue
		var tile: Vector2i = (entry as Dictionary)["tile"] as Vector2i
		var d: float = Vector2(tile).distance_to(Vector2(player_tile))
		if d < best_dist:
			best_dist = d
			best = tile
			found = true
	if not found:
		return Vector2.INF
	return ground_layer.to_global(ground_layer.map_to_local(best))

# Every cell of the structure's footprint (except skip_cell — a
# Vector2i(-1, -1) sentinel means "skip nothing") must be in-bounds, land,
# and free of trees, placed blocks and already-painted structure cells.
func _structure_footprint_valid(s: GeneratedStructure, anchor: Vector2i, skip_cell: Vector2i) -> bool:
	var half_w: int = width  / 2
	var half_h: int = height / 2
	for x in range(s.tile_width):
		for y in range(s.tile_height):
			if Vector2i(x, y) == skip_cell:
				continue
			var cell: Vector2i = anchor + Vector2i(x, y)
			if absi(cell.x) >= half_w or absi(cell.y) >= half_h:
				return false
			if _cell_biome_type(cell) == -1:
				return false
			if _placed_blocks.has(cell) or _is_tree_occupied(cell):
				return false
			if structures_layer.get_cell_source_id(cell) != -1:
				return false
	return true

# Paints every footprint cell except skip_cell (Vector2i(-1, -1) paints all)
# onto the Structures layer. Returns the painted world cells.
func _paint_structure(s: GeneratedStructure, anchor: Vector2i, skip_cell: Vector2i) -> Array:
	var src_id: int = int(_structure_sources[s])
	var painted: Array = []
	for x in range(s.tile_width):
		for y in range(s.tile_height):
			if Vector2i(x, y) == skip_cell:
				continue
			var cell: Vector2i = anchor + Vector2i(x, y)
			structures_layer.set_cell(cell, src_id, Vector2i(x, y))
			painted.append(cell)
	return painted

# Claim every chunk a structure touches so no other pass spawns under it.
func _claim_structure_chunks(s: GeneratedStructure, anchor: Vector2i) -> void:
	var tl_chunk: Vector2i = _tile_to_chunk(anchor)
	var br_chunk: Vector2i = _tile_to_chunk(anchor + Vector2i(s.tile_width - 1, s.tile_height - 1))
	for cx in range(tl_chunk.x, br_chunk.x + 1):
		for cy in range(tl_chunk.y, br_chunk.y + 1):
			_structure_claimed_chunks[Vector2i(cx, cy)] = true

# ── Dungeon entrance structures ───────────────────────────────────────
# Paints a dungeon entrance as per-cell Sprite2D nodes instead of the
# Structures TileMapLayer. The layer is ONE canvas item pinned at World's
# origin (y=0), so it can never y-sort against the player — the whole
# sprite stayed stuck behind the player no matter which side they approach
# from. Individual cell sprites anchor at their own tile center and get the
# same quantized z_index = int(y / TILE_SIZE) that trees/grass/placed
# blocks/player all use, so each cell sorts correctly against the player
# (player walks behind the upper wall when north of it, in front of the
# bottom wall when south of it). Every cell also gets a full-tile
# StaticBody2D so the entrance is solid — previously the sprite had no
# collision the player could actually hit.
#
# Returns the painted world cells (anchor + local cell offset).
func _spawn_dungeon_entrance_nodes(s: GeneratedStructure, anchor: Vector2i, dungeon_index: int) -> Array:
	var root := Node2D.new()
	root.name = "DungeonEntrance%d" % dungeon_index
	add_child(root)

	# The structure sprite is an AtlasTexture region into a shared sheet; the
	# per-cell AtlasTextures must unwrap it to the BASE texture + the region
	# origin so each cell's region lands on the right pixels (see
	# cave_world.gd's _add_icon_source for the same unwrap pattern).
	var base_tex: Texture2D     = s.sprite
	var base_origin: Vector2i   = Vector2i.ZERO
	var sprite_atlas := s.sprite as AtlasTexture
	if sprite_atlas != null:
		base_tex    = sprite_atlas.atlas
		base_origin = Vector2i(sprite_atlas.region.position.round())

	var painted: Array = []
	for x in range(s.tile_width):
		for y in range(s.tile_height):
			var cell: Vector2i = anchor + Vector2i(x, y)
			var cell_tex := AtlasTexture.new()
			cell_tex.atlas  = base_tex
			cell_tex.region = Rect2(base_origin + Vector2i(x * TILE_SIZE, y * TILE_SIZE), Vector2(TILE_SIZE, TILE_SIZE))

			var sprite := Sprite2D.new()
			sprite.texture = cell_tex
			root.add_child(sprite)
			sprite.global_position = ground_layer.to_global(ground_layer.map_to_local(cell))
			sprite.z_index         = int(sprite.global_position.y / TILE_SIZE)

			# Door cells (the walkable opening — the portal's middle tile)
			# get NO collision so the player can step into the entrance.
			if not s.is_door_cell(x, y):
				var body := StaticBody2D.new()
				body.collision_layer = 1
				body.collision_mask  = 1
				var shape := CollisionShape2D.new()
				var rect := RectangleShape2D.new()
				rect.size = Vector2(TILE_SIZE, TILE_SIZE)
				shape.shape = rect
				body.add_child(shape)
				root.add_child(body)
				body.global_position = ground_layer.to_global(ground_layer.map_to_local(cell))

			painted.append(cell)
	return painted

# Every dungeon mission's entrance uses a GeneratedStructure of type
# "dungeon entrances" (see _load_dungeon_entrance_structures): the structure
# is painted around the portal tile, one per dungeon picked round-robin by
# dungeon_index. The FULL footprint is painted — there is no empty center
# cell; the DungeonPortal node at the center is invisible (Sprite2D removed)
# and only supplies the walk-in Area2D + confirm dialog.
#
# Returns the DOOR tile (anchor + center) — the cell the structure's doorway
# actually landed on. The caller must put the portal there so the visible
# entrance and the real entry trigger are always the same position: the 5x5
# search below can shift the whole picture off the requested portal tile when
# a tree/block occupies the ideal footprint.
func _place_dungeon_entrance_structure(portal_tile: Vector2i, dungeon_index: int) -> Vector2i:
	if _dungeon_entrance_pool.is_empty():
		_dungeon_entrance_pool = _load_dungeon_entrance_structures()
	if _dungeon_entrance_pool.is_empty():
		return DUNGEON_INVALID_TILE
	var s := _dungeon_entrance_pool[(dungeon_index - 1) % _dungeon_entrance_pool.size()] as GeneratedStructure
	# Paint EVERY footprint cell (the portal node is invisible, so there is
	# no reason to keep a walkable hole in the middle of the sprite).
	# The door cell (walkable opening) sits at the structure's door center —
	# for the dungeon portal that's the glowing middle tile.
	var center := s.door_center_cell()
	# Anchor candidates walk a 5x5 search around the ideal anchor (portal dead
	# center of the footprint) so a tree/block in the chunk can't veto the
	# whole entrance. Offsets are tried nearest-first so the door lands as
	# close to the requested portal tile as possible.
	var offsets: Array[Vector2i] = []
	for dy in range(-2, 3):
		for dx in range(-2, 3):
			offsets.append(Vector2i(dx, dy))
	offsets.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return a.length_squared() < b.length_squared())
	for offset in offsets:
		var anchor: Vector2i = portal_tile - center + offset
		if not _structure_footprint_valid(s, anchor, Vector2i(-1, -1)):
			continue
		var painted := _spawn_dungeon_entrance_nodes(s, anchor, dungeon_index)
		for cell in painted:
			_dungeon_entrance_cells[cell as Vector2i] = true
		_dungeon_entrance_structure_cells[dungeon_index] = painted
		_claim_structure_chunks(s, anchor)
		_located_structures.append({"name": s.name, "tile": anchor + center})
		return anchor + center
	push_warning("DungeonSpawner: no free footprint for dungeon %d entrance structure — portal still spawned" % dungeon_index)
	return DUNGEON_INVALID_TILE

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
#   c. not a structure-claimed chunk
#   d. not a chunk without enough solid land (all-ocean OR touches the ocean)
#   e. not the chunk the player is currently standing in
#   f. not within DUNGEON_SPAWN_MIN_DIST_TILES tiles of world spawn
func _is_valid_dungeon_chunk(chunk: Vector2i, player_tile: Vector2i, developed_chunks: Dictionary) -> bool:
	if _cave_claimed_chunks.has(chunk):
		return false
	if _structure_claimed_chunks.has(chunk):
		return false
	if not _is_chunk_valid_for_structure(chunk):
		return false
	if _tile_to_chunk(player_tile) == chunk:
		return false
	if developed_chunks.has(chunk):
		return false
	if _chunk_min_corner_dist(chunk, _world_spawn_pos()) < DUNGEON_SPAWN_MIN_DIST_TILES * TILE_SIZE:
		return false
	return true

# Land tile inside a chunk (rejecting water, trees, placed blocks and
# structure cells — a portal can't sit on any of those;
# _cell_biome_type() == -1 is water). Scans the whole 25x25 chunk once and
# returns a random usable tile, instead of a fixed number of random attempts
# that can whiff on a partially-land chunk. An ENTIRELY water chunk still
# fails (DUNGEON_INVALID_TILE) — the caller then falls through to the next
# valid chunk.
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
			if structures_layer.get_cell_source_id(tile) != -1:
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
	# Paint the entrance structure around the tile, then move the portal onto
	# the structure's actual door — the anchor search may shift the picture,
	# and the trigger must sit exactly on the sprite's doorway so the guide
	# arrow and walk-in entry line up with what the player sees.
	var door_tile := _place_dungeon_entrance_structure(tile, dungeon_index)
	if door_tile != DUNGEON_INVALID_TILE:
		_dungeon_entrance_tiles[dungeon_index] = door_tile
		tile = door_tile
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
	# Scrub the painted entrance so a cleared dungeon leaves no orphaned
	# sprite or collision (the portal's chunk was validated structure-free
	# when the entrance spawned, so un-claiming is safe).
	if _dungeon_entrance_nodes.has(dungeon_index):
		var entrance: Node = _dungeon_entrance_nodes[dungeon_index]
		if is_instance_valid(entrance):
			entrance.queue_free()
		_dungeon_entrance_nodes.erase(dungeon_index)
	if _dungeon_entrance_structure_cells.has(dungeon_index):
		for cell in (_dungeon_entrance_structure_cells[dungeon_index] as Array):
			var c := cell as Vector2i
			_dungeon_entrance_cells.erase(c)
			_structure_claimed_chunks.erase(_tile_to_chunk(c))
		_dungeon_entrance_structure_cells.erase(dungeon_index)

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
		var node_ref: Variant = entry["node"]
		if not is_instance_valid(node_ref):
			continue
		var node: Node = node_ref as Node
		if node == null:
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
	# The world may be mid-swap (off-tree) while save data is applied — a null
	# get_tree() would crash the group scans below.
	if get_tree() == null:
		return
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
			# Entrances only belong to the world while their dungeon mission is
			# ACCEPTED — restoring them unconditionally respawned entrances for
			# missions the player had already completed or never accepted.
			if Global.accepted_dungeon_index() != idx:
				continue
			if Global.is_dungeon_cleared(idx):
				continue
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
