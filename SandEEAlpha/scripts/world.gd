extends Node2D

const TILE_SIZE = 32
# Max placed LUA stations (labelled "LUA 0".."LUA 30"); see lua_npc.gd.
const LUA_MAX_STATIONS: int = 31
const TREE_SCENE:      PackedScene = preload("res://scenes/objects/Tree.tscn")
const WOLF_SCENE:      PackedScene = preload("res://scenes/mobs/Wolf.tscn")
const SHEEP_SCENE:     PackedScene = preload("res://scenes/mobs/Sheep.tscn")
const WORM_SCENE:      PackedScene = preload("res://scenes/mobs/Worm.tscn")
const HEADLESS_FISH_SCENE: PackedScene = preload("res://scenes/mobs/HeadlessFish.tscn")
# Bestiary creatures. The ambient director uses the same cap/biome machinery
# as the existing mobs; the resources' spawn_weight prevents overpopulation.
const MOSSBACK_NIB_SCENE:      PackedScene = preload("res://scenes/mobs/MossbackNib.tscn")
const EMBERFOX_KIT_SCENE:      PackedScene = preload("res://scenes/mobs/EmberfoxKit.tscn")
const CINDER_OOZE_SCENE:       PackedScene = preload("res://scenes/mobs/CinderOoze.tscn")
const GRAVEBELL_SHAMBLER_SCENE: PackedScene = preload("res://scenes/mobs/GravebellShambler.tscn")
const PLAIN_TREE_TEX:  Texture2D   = preload("res://sprites/tree/tree.png")
const SNOWY_TREE_TEX:  Texture2D   = preload("res://sprites/tree/snowy_tree.png")
const BIRCH_TREE_TEX:  Texture2D   = preload("res://sprites/tree/birch_tree.png")
const SHADOW_TEXTURE:  Texture2D   = preload("res://sprites/shadow/shadow_base.png")
const SWORD_SWING_SCRIPT: GDScript = preload("res://scripts/sword_swing_effect.gd")
const AMBIENT_BIRDS_SCRIPT: GDScript = preload("res://scripts/ambient_birds.gd")
const GRASS_CUT_BURST_SCRIPT: GDScript = preload("res://scripts/grass_cut_burst.gd")
const WHEAT_CROP_SCENE: PackedScene = preload("res://scenes/objects/WheatCrop.tscn")
const WHEAT_SEEDS_ITEM: ItemData = preload("res://resources/items/wheat_seeds.tres")
const TILLED_PLOT_ITEM: ItemData = preload("res://resources/items/tilled_plot.tres")
# Chance a cut grass tuft also yields Wheat Seeds (farming's seed source).
const GRASS_SEED_DROP_CHANCE: float = 0.25
# Tilled soil must be near water: grass can only be tilled within this many
# blocks (Chebyshev) of a water tile — natural or player-poured.
const TILL_WATER_RADIUS_BLOCKS: int = 20
const CACTUS_SCENE:    PackedScene = preload("res://scenes/objects/PlaceableBlock.tscn")
const CACTUS_DATA:     ItemData    = preload("res://resources/items/cactus.tres")
const OBJECT_BURST_SCRIPT: GDScript = preload("res://scripts/object_burst.gd")
const INTERIOR_SHADE_SCRIPT: GDScript = preload("res://scripts/interior_shade.gd")

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
const GRASS_CHUNK_COVERAGE_MIN: float = 0.08
const GRASS_CHUNK_COVERAGE_MAX: float = 0.12
# Per chunk fill, 70% of the time the target tile count is taken as one
# compact cluster (nearest tiles to a random seed point) instead of spread
# uniformly across the whole chunk.
const GRASS_GROUPED_CHANCE: float = 0.70
const GRASS_REGROW_INTERVAL: float = 600.0  # 10 minutes, matches the overworld day spawn cadence
# A random desert tile grows a Cactus every minute (see _spawn_cactus).
# Original rate was one per 300 s; the smaller interval raises desert cactus
# availability 5x while keeping the same one-per-tick placement rules.
const CACTUS_SPAWN_INTERVAL: float = 60.0
# Never grow a cactus on/next to the world spawn point or entrance footprints.
const CACTUS_SPAWN_SAFE_RADIUS: int = 12
const CACTUS_SPAWN_ENTRANCE_CLEAR: int = 3
# How many chunks _fill_all_chunks_with_grass() processes before yielding a
# frame — keeps the background fill from hitching gameplay while it catches
# up after load. Higher = finishes filling in sooner but each yielded frame
# does more work; lower = smoother but takes longer to fully fill in.
const GRASS_CHUNKS_PER_FRAME: int = 4
# Chunks/frame for the INITIAL fill, which now runs behind the loading screen
# (nothing to keep smooth, so it can afford much bigger bites and fewer
# yielded frames). Only the loading-screen fill passes this; the default
# GRASS_CHUNKS_PER_FRAME stays in place for any gentler future caller.
const GRASS_CHUNKS_PER_FRAME_LOAD: int = 16

# ── Stone / charcoal patches ────────────────────────────────────────
# Random clusters of mineable Stone blocks scattered across the world, but
# PLAINS chunks only (never snowy, desert, water or the world edge). Each
# eligible chunk rolls a chance to host one patch of STONE_PATCH_MIN..MAX
# blocks; 70% of patches also embed CHARCOAL_PATCH_MIN..MAX charcoal blocks
# (charcoal is a placeable/mineable block too — see charcoal.tres).
#
# The blocks are registered in _placed_blocks so mining, occupancy and the
# dungeon-entrance "replace the stone" rule all reuse the existing paths, but
# each entry is tagged "natural": excluded from saves (they regenerate
# deterministically from the seed), from hover scanning and from the
# "developed chunk" checks.
const STONE_DATA:             ItemData = preload("res://resources/items/stone.tres")
const CHARCOAL_DATA:          ItemData = preload("res://resources/items/charcoal.tres")
const STONE_PATCH_CHANCE:     float    = 0.40
const STONE_PATCH_MIN:        int      = 5
const STONE_PATCH_MAX:        int      = 20
const STONE_PATCH_RADIUS:     int      = 3   # cluster grows within this many tiles of the centre
const CHARCOAL_PATCH_CHANCE:  float    = 0.70
const CHARCOAL_PATCH_MIN:     int      = 1
const CHARCOAL_PATCH_MAX:     int      = 15

# ── Birch trees ─────────────────────────────────────────────────────
# Birch trees grow AMONG the plains forest (they never replace it): a
# deterministic per-tile roll promotes that fraction of plains trees to birch.
# The roll is a coordinate hash, NOT a draw from the shared generation rng —
# taking from that stream here would shift every later world-gen roll and change
# existing worlds for a given seed.
const BIRCH_CHANCE:           float    = 0.22

# ── Coarse sand (desert surface variant + mineable blocks) ──────────
# The terrain itself is a darker, rougher desert tile painted in irregular
# clumps (see _paint_coarse_sand_patches); the mineable blocks are a separate
# pass (see _place_coarse_sand_patches) so the player has a source for the
# sandstone recipe. Both are chunk-seeded so a world seed always produces the
# same pattern without touching the shared rng.
const COARSE_SAND_DATA:            ItemData = preload("res://resources/items/coarse_sand.tres")
const COARSE_SAND_CHUNK_CHANCE:    float    = 0.55
const COARSE_SAND_PATCH_MIN:       int      = 8
const COARSE_SAND_PATCH_MAX:       int      = 34
const COARSE_SAND_BLOCK_CHANCE:    float    = 0.35
const COARSE_SAND_BLOCK_MIN:       int      = 2
const COARSE_SAND_BLOCK_MAX:       int      = 7

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
# When true (every real world), _ready adopts Global.pending_world_seed — the
# seed rolled for a new game or restored from a save — before generating.
# The title-screen panorama sets this false because it supplies its own seed.
@export var use_pending_seed: bool = true
@export var width:       int  = 1024
@export var height:      int  = 1024
@export var use_experimental_ground: bool = true

var _exp_ground_src:  int = -1
var _exp_ground_cols: int = 0
# Runtime TileSetAtlasSource for the coarse-sand desert tile (see
# _apply_coarse_sand_source); -1 when the texture is missing.
var _coarse_sand_src: int = -1
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

# Decorative block-built houses/pillars. These run at the end of the same
# structure pass, after the existing sprite structures, and use a dedicated RNG
# so the established world-gen sequence (and therefore existing worlds) is not
# perturbed. Their definitions/removals are persisted in the world save.
const DECOR_STRUCTURE_CHANCE:         float = 0.22
const DECOR_STRUCTURE_MIN_SPAWN_DIST: float = 110.0
const DECOR_STRUCTURE_MIN_SEPARATION: float = 18.0
const DECOR_STRUCTURE_ATTEMPTS:       int   = 28
const DECOR_LAYOUT_VERSION:           int   = 1
const DECOR_PROTECT_MOB_RADIUS:       int   = 2
const DECOR_PROTECT_DUNGEON_RADIUS:   int   = 4   # covers the native large-portal footprint
const DECOR_PROTECT_PLAYER_RADIUS:    int   = 2

var _decor_structures: Array = []          # persisted definitions
var _decor_removed: Dictionary = {}        # Vector2i -> true (mined/gone cells)
var _decor_pending_player_cells: Dictionary = {}  # loaded save's blocks to protect
var _decor_pending_reserved_cells: Dictionary = {} # saved mobs/dungeon/player/cleared trees
var _decor_item_cache: Dictionary = {}     # item path -> ItemData
var _decor_templates: Array = []
var _decor_rng: RandomNumberGenerator = null

var _structure_claimed_chunks: Dictionary = {}   # chunk coord (Vector2i) -> true
var _structure_anchor_tiles:   Array      = []   # top-left tiles, for the min-separation check
var _located_structures:        Array      = []   # [{"name": String, "tile": Vector2i}, ...] — every placed structure/entrance, for internal lookups
var _structure_sources:        Dictionary = {}   # GeneratedStructure -> source id in the Structures TileSet

# ── Dungeon entrances (one per language, always present) ──────────────
# Unlike caves (rolled during world-gen), dungeon entrances are placed once
# the world is built and kept in sync as each track advances (see
# _ensure_current_dungeon_entrances). A dungeon's chunk must satisfy every
# one of:
#   a. no player-placed blocks in it
#   b. not a cave-claimed chunk
#   c. not the chunk the player is currently standing in
#   d. not within DUNGEON_SPAWN_MIN_DIST_TILES tiles of world spawn
const DUNGEON_PORTAL_SCENE: PackedScene = preload("res://scenes/objects/DungeonPortal.tscn")
const DUNGEON_WAYPOINT_SCRIPT: GDScript = preload("res://scripts/dungeon_waypoint.gd")
const WORLD_WAYPOINT_TOWER_SCRIPT: GDScript = preload("res://scripts/world_waypoint_tower.gd")
const WAYPOINT_RECALL_FX_SCRIPT: GDScript = preload("res://scripts/waypoint_recall_fx.gd")
const WAYPOINT_RECALL_BEACON_SEC: float = 0.72
const WAYPOINT_WHITE_FADE_IN_SEC: float = 0.30
const WAYPOINT_WHITE_FADE_OUT_SEC: float = 0.55
const DUNGEON_ENTRANCE_PYTHON_TEX: Texture2D = preload("res://sprites/waypoints/portal_python_stonegate_sheet.png")
const DUNGEON_ENTRANCE_LUA_TEX: Texture2D = preload("res://sprites/waypoints/portal_lua_ancient_sheet.png")
const DUNGEON_ENTRANCE_PYTHON_SIZE: Vector2i = Vector2i(5, 4)
const DUNGEON_ENTRANCE_LUA_SIZE: Vector2i = Vector2i(6, 5)
const DUNGEON_SPAWN_MIN_DIST_TILES: float = 40.0    # keep the immediate spawn area clear
const DUNGEON_NEAR_CHUNK_RADIUS: int = 8            # prefer chunks near the player
const DUNGEON_INVALID_TILE: Vector2i = Vector2i(1 << 20, 1 << 20)  # sentinel, outside any map bounds

# World waypoint network. Towers are the approved animated Ruined Skyglass
# sprite, placed by the same structure pass/validation as other overworld
# landmarks, then persisted by definition so reloads cannot duplicate or move
# them. A target density of eligible chunks spreads them across the map.
const WORLD_WAYPOINT_SIZE: Vector2i = Vector2i(5, 7)
const WORLD_WAYPOINT_DENSITY: float = 0.12
const WORLD_WAYPOINT_MIN_SEPARATION: float = 34.0
const WORLD_WAYPOINT_ATTEMPTS: int = 40

var _world_waypoints: Array = []             # [{id,label,x,y}]
var _world_waypoint_nodes: Dictionary = {}   # id -> WorldWaypointTower
var _world_waypoint_cells: Dictionary = {}   # cell -> id
var _world_waypoint_anchors: Array = []      # top-left anchors for spacing
var _world_waypoint_rng: RandomNumberGenerator = null
var _waypoint_teleporting: bool = false

# Temporary one-way dungeon waypoints live near the player and target the
# CURRENT dungeon for their language. They are deliberately separate from
# permanent world waypoint towers.
var _dungeon_waypoint_nodes: Dictionary = {}  # dungeon_index -> DungeonWaypoint
var _dungeon_waypoint_cells: Dictionary = {}  # cell -> dungeon_index
var _dungeon_entrance_tiles: Dictionary = {}  # dungeon_index -> Vector2i tile
# Entrances may only spawn once world-gen has finished: mission_updated fires
# for gameplay missions too (e.g. the "move" tutorial), which can land while
# chunks/terrain/structure claims are still being built.
var _dungeon_entrances_ready: bool = false
var _dungeon_portal_nodes:   Dictionary = {}  # dungeon_index -> spawned DungeonPortal (so a cleared dungeon's entrance can be removed)
var _dungeon_entrance_structure_cells: Dictionary = {}  # dungeon_index -> Array[Vector2i] cells painted for the entrance
var _dungeon_entrance_nodes:  Dictionary = {}   # dungeon_index -> Node2D root of the painted entrance sprite+collision
var _dungeon_entrance_cells:  Dictionary = {}   # cell (Vector2i) -> true - every footprint cell of every live entrance
# Cells around each dungeon door kept free of grass, so the player never spawns
# inside overlapping tufts when returning from a dungeon.
var _dungeon_grass_clearance: Dictionary = {}   # cell (Vector2i) -> true

# Trees beyond this radius have their Area2D monitoring disabled to avoid
# O(n²) physics overhead. Must be larger than InteractArea radius (48px).
# NOTE: grass deliberately does NOT use this per-node Area2D pattern — see
# _on_swing_performed below. A grass-scale
# (thousands of tufts) periodic full-group scan was tried and became the
# dominant runtime cost; grass cutting is driven centrally instead, same
# O(1) dictionary-lookup approach the _placed_blocks map already uses for
# placed blocks.
const TREE_INTERACT_RADIUS: float = 300.0
# Static collision is only needed near the player. Keeping all ~3k tree/block
# shapes registered made the first physics step after world generation take
# 15+ seconds; enabling a 1k-pixel neighbourhood keeps movement/collision
# identical while avoiding that startup spike.
const TREE_PHYSICS_RADIUS: float = 1024.0
const BLOCK_PHYSICS_RADIUS: float = 1024.0
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

# ── Ambient spawn director tuning ────────────────────────────────────
# Continuous, CAPPED population spawned in a ring just around the player
# (Terraria-style). See _start_ambient_spawn_timer / _run_ambient_spawn.
const AMBIENT_RING_MIN_TILES: int = 18     # just off-screen — no pop-in
const AMBIENT_RING_MAX_TILES: int = 44
const AMBIENT_DESPAWN_TILES:  int = 72     # beyond this for LINGER sec → recycled
const AMBIENT_STRAY_LINGER:   float = 5.0
# Small no-spawn bubble around the world spawn tile only. Must stay well under
# RING_MIN so it never eats the ring when the player is standing at spawn.
const AMBIENT_SPAWN_SAFE_TILES: int = 10
const AMBIENT_DAY_CAP:        int = 10
const AMBIENT_DAY_INTERVAL:   float = 4.0
const AMBIENT_DAY_ATTEMPTS_MIN: int = 1
const AMBIENT_DAY_ATTEMPTS_MAX: int = 2
const AMBIENT_NIGHT_CAP:      int = 14
const AMBIENT_NIGHT_INTERVAL: float = 2.5
const AMBIENT_NIGHT_ATTEMPTS_MIN: int = 1
const AMBIENT_NIGHT_ATTEMPTS_MAX: int = 3

# Pool of mobs the overworld spawner can pick from — each entry pairs a scene
# with the MobCombatData resource that drives its spawn rules (biome,
# day/night eligibility, min/max count per chunk). Add new mobs here as
# their .tres + AI script get built.
var MOB_SPAWN_POOL: Array = [
	{"scene": WOLF_SCENE, "data": preload("res://resources/mobs/wolf.tres")},
	{"scene": SHEEP_SCENE, "data": preload("res://resources/mobs/sheep.tres")},
	{"scene": WORM_SCENE, "data": preload("res://resources/mobs/worm.tres")},
	{"scene": HEADLESS_FISH_SCENE, "data": preload("res://resources/mobs/headless_fish.tres")},
	{"scene": MOSSBACK_NIB_SCENE, "data": preload("res://resources/mobs/mossback_nib.tres")},
	{"scene": EMBERFOX_KIT_SCENE, "data": preload("res://resources/mobs/emberfox_kit.tres")},
	{"scene": CINDER_OOZE_SCENE, "data": preload("res://resources/mobs/cinder_ooze.tres")},
	{"scene": GRAVEBELL_SHAMBLER_SCENE, "data": preload("res://resources/mobs/gravebell_shambler.tres")},
]

# The self-rescheduling ambient spawn timer; re-armed on each period flip so
# the interval follows day/night (see _on_night_started / _on_day_started).
var _ambient_spawn_timer: Timer = null
# Stray-recycle bookkeeping: mob instance id -> seconds spent beyond the ring.
var _ambient_stray: Dictionary = {}

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
var _grass_fx_pool:         Array        = []
var _grass_fx_index:        int          = 0

# ── Block placement ──────────────────────────────────────────────────
var ghost:           Node2D   = null
var ghost_sprite:    Sprite2D = null
var ghost_last_type: String   = ""
var _grid_overlay:      Node2D = null
var _cursor_highlight:  Node2D = null
var _placed_blocks:     Dictionary = {}

# Tiles blocked by a standing tree's actual canopy + trunk footprint.
# Dictionary value is a reference count so overlapping tree footprints don't
# unblock a tile just because ONE of several nearby trees was chopped down.
var _tree_occupied_tiles: Dictionary = {}
# Flat water lookup grid (1 byte per tile). Grass/foliage validation queries the
# water map tens of thousands of times; TileMapLayer.get_cell_source_id() in
# those inner loops dominated world load. Built once after terrain generation.
var _water_grid: PackedByteArray = PackedByteArray()
var _water_grid_ready: bool = false
# Cells within 2 tiles of water. Grass validation runs for every map tile, so
# this removes its 25-neighbour water scan from the hot generation loop.
var _water_margin2: PackedByteArray = PackedByteArray()
var _water_margin2_ready: bool = false
# 0=plain, 1=desert, 2=snowy, 255=water/none. Built during terrain generation,
# so grass/foliage validation does not hit TileMapLayer for every tile.
var _biome_grid: PackedByteArray = PackedByteArray()
var _biome_grid_ready: bool = false
# The tree sprite is 96px = 3x3 tiles, with its origin at the trunk base.
# Reserve the canopy rows above the trunk too; a trunk-centred 3x3 square left
# the leafy half of the tree unprotected, so grass/blocks could spawn on it.
const TREE_OCCUPY_X_RADIUS: int = 1   # 3 tiles wide
const TREE_OCCUPY_NORTH:    int = 3   # canopy rises 3 tiles above the trunk cell
const TREE_OCCUPY_SOUTH:    int = 1   # keep the old one-tile base clearance

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
	# Adopt the seed for THIS world (new game / restored save) before any
	# generation or chunk hash is computed — the scene default would otherwise
	# make every world identical. Consumed once so a later world (e.g. the menu
	# panorama or a re-entry) can't inherit it.
	if use_pending_seed and Global.pending_world_seed != 0:
		random_seed = Global.pending_world_seed
		Global.pending_world_seed = 0
	rng.set_seed(random_seed)
	_set_up_noise(humidity,    0.003)
	_set_up_noise(temperature, 0.002)
	_set_up_noise(altitude,    0.005)
	if use_experimental_ground:
		_apply_experimental_ground()
	_apply_coarse_sand_source()
	_setup_ghost()
	_setup_grid_overlay()
	_setup_cursor_highlight()
	_setup_chunk_border_overlay()
	_setup_hitbox_overlay()
	_setup_glow_environment()
	# Darkens the world around a house while the player is indoors (interior
	# stays bright). Lives in the world canvas so it never dims the UI.
	_interior_shade = INTERIOR_SHADE_SCRIPT.new() as Node2D
	if _interior_shade != null:
		add_child(_interior_shade)
	Global.hotbar_selection_changed.connect(_on_hotbar_changed)
	Global.Hotbar_updated.connect(_on_hotbar_changed)
	Global.mission_updated.connect(_on_mission_updated)
	# Each period flip refills the ambient ring to that period's cap.
	Global.night_started.connect(_on_night_started)
	Global.day_started.connect(_on_day_started)
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
	if Global.is_mouse_event_over_ui(event):
		return
	# Ctrl+Shift+H/C/T and the block-mode Ctrl toggle are now detected once,
	# centrally, in Global._input() (dispatches here via has_method()/call())
	# — see Global's own comment for why. This function only needs to react
	# to Global.block_mode/its own toggle_*() methods now, not detect the
	# keypresses itself.
	if not Global.block_mode:
		return
	if event.is_action_pressed("mouse_left"):
		# SHIFT+click = mine/destroy the block under the cursor instead of
		# placing one (build mode doubles as demolition mode — see
		# placeable_block._input). Stations/furnaces/chests handle shift
		# themselves.
		if Global.is_shift_held():
			return
		# Seeds are BUILD-MODE only: planting is a placement action, not a
		# normal click. They are planted on a Tilled Ground cell and cannot be
		# planted anywhere else (see _try_use_held_item, which ignores seeds).
		var held: Variant = Global.get_hotbar_item()
		if held is Dictionary:
			var seed_data: ItemData = (held as Dictionary)["data"] as ItemData
			if seed_data != null and seed_data.is_seed:
				if plant_crop_at_cursor():
					Global.remove_item(seed_data)
				return
		place_block()

# Fired by the player's swing_performed signal (the swing plays in every
# world backend; this overworld reacts to it): if a sword is held, cut the
# grass row in front of the player.
func _on_swing_performed() -> void:
	# The overworld is kept alive (removed from the tree, not freed) while the
	# player is in a cave or dungeon — and its swing_performed connection
	# survives that swap, so this can fire for a swing that happened in
	# ANOTHER world. Ignore it off-tree: acting on it would cut + queue_free
	# overworld tufts while Global.world_node points at the dungeon, so
	# notify_grass_removed() never reaches THIS world and _grass_occupied_tiles
	# keeps a freed entry that crashes the next lookup (see _cut_grass_row).
	if not is_inside_tree():
		return
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
	_cut_crop_row(p)

# The tile offset to cut: the nearest table direction to where the player is
# POINTING (the mouse), falling back to the 8-way WASD facing when the cursor
# sits on the player. Keeps the grass cut aligned with the mouse-aimed swing.
func _grass_cut_offset(p: Node2D) -> Vector2i:
	var aim: Vector2 = Global.mouse_world(p) - p.global_position
	if aim.length_squared() < 4.0:
		return GRASS_CUT_DIR_VECTORS.get(p.call("get_facing_dir"), Vector2i(0, 1)) as Vector2i
	var want: Vector2 = aim.normalized()
	var best: Vector2i = Vector2i(0, 1)
	var best_dot: float = -INF
	for v in GRASS_CUT_DIR_VECTORS.values():
		var dv: Vector2i = v as Vector2i
		var dot: float = want.dot(Vector2(dv).normalized())
		if dot > best_dot:
			best_dot = dot
			best    = dv
	return best

# The tuft whose clump covers the tile under `world_pos`, if any. The tuft's
# origin sits on a tile boundary and its art overflows ~1.5 tiles up and ~1.3
# tiles sideways, so the WHOLE clicked tile (and its neighbours) counts as
# grass — not just the tuft's origin pixel. Nearest tuft wins when clumps
# overlap, so a click cuts the one it visually belongs to.
func grass_tuft_at_world(world_pos: Vector2) -> GrassTuft:
	if ground_layer == null:
		return null
	var cell: Vector2i = ground_layer.local_to_map(ground_layer.to_local(world_pos))
	var best: GrassTuft = null
	var best_d: float = INF
	for dx in range(-1, 2):
		for dy in range(-1, 2):
			var tile := cell + Vector2i(dx, dy)
			var raw: Variant = _grass_occupied_tiles.get(tile)
			if raw == null or not is_instance_valid(raw):
				_grass_occupied_tiles.erase(tile)
				continue
			var tuft: GrassTuft = raw as GrassTuft
			if tuft == null:
				continue
			# Only count the tuft where it actually covers the point: its whole
			# tile plus its visible blades. This is what stops the empty ground
			# BELOW a tuft from being detected as grass.
			var covers: bool = false
			if tuft.has_method("grass_rect"):
				covers = (tuft.call("grass_rect") as Rect2).has_point(world_pos)
			else:
				covers = tuft.global_position.distance_to(world_pos) <= float(TILE_SIZE)
			if not covers:
				continue
			var d: float = tuft.global_position.distance_to(world_pos)
			if d < best_d:
				best_d = d
				best = tuft
	return best

# Cuts the tuft covering `world_pos` (sword gate lives in the caller). Used by
# tap-to-control so tapping anywhere on the tile cuts that tuft, regardless of
# which 8-way direction the aim snaps to.
func cut_grass_at_world(world_pos: Vector2) -> bool:
	var tuft: GrassTuft = grass_tuft_at_world(world_pos)
	if tuft == null:
		return false
	var tile: Vector2i = tuft.call("tile_index") as Vector2i
	var at: Vector2 = _cut_grass_tile(tile, true)
	if at == Vector2.INF:
		return false
	if randf() < GRASS_SEED_DROP_CHANCE:
		Global.drop_item({"data": WHEAT_SEEDS_ITEM, "quantity": 1}, at)
	return true

# How many tiles out from the aimed tile one swing cuts. 1 = a 3x3 patch, so a
# swing no longer demands pixel-perfect aim (the old single-tile cut felt far
# too tight, especially with tap-to-move).
const GRASS_CUT_PATCH_RADIUS: int = 1

# Every tile a swing cuts, centred on the aimed tile.
func grass_cut_tiles(aimed: Vector2i) -> Array:
	var out: Array = []
	for dx in range(-GRASS_CUT_PATCH_RADIUS, GRASS_CUT_PATCH_RADIUS + 1):
		for dy in range(-GRASS_CUT_PATCH_RADIUS, GRASS_CUT_PATCH_RADIUS + 1):
			out.append(aimed + Vector2i(dx, dy))
	return out

func _cut_grass_row(p: Node2D) -> void:
	var held: Variant = Global.get_hotbar_item()
	if held == null or not (held as Dictionary).has("data"):
		return
	var d: Vector2i = _grass_cut_offset(p)
	var player_tile: Vector2i = ground_layer.local_to_map(ground_layer.to_local(p.global_position))
	var center:      Vector2i = player_tile + d
	# A 3x3 patch around the aimed tile (was a single tile). The patch makes both
	# mouse swings and tap-to-cut forgiving without changing the sword-only rule.
	var first_cut: Vector2 = Vector2.INF
	var first_color := Color(0.55, 1.0, 0.45, 1.0)
	for tile in grass_cut_tiles(center):
		var at: Vector2 = _cut_grass_tile(tile as Vector2i, false, true)
		if at != Vector2.INF and first_cut == Vector2.INF:
			first_cut = at
			first_color = _last_cut_grass_color
	if first_cut != Vector2.INF:
		_spawn_grass_cut_fx(first_cut, first_color)
	# Farming's seed source: one roll per swing (not per tuft, so a wide cut
	# can't flood the world with seeds).
	if first_cut != Vector2.INF and randf() < GRASS_SEED_DROP_CHANCE:
		Global.drop_item({"data": WHEAT_SEEDS_ITEM, "quantity": 1}, first_cut)

# Cuts the tuft on one tile (if any). Returns its world position, or
# Vector2.INF when the tile had no live tuft.
var _last_cut_grass_color: Color = Color(0.55, 1.0, 0.45, 1.0)

func _cut_grass_tile(tile: Vector2i, spawn_fx: bool = false, capture_color: bool = false) -> Vector2:
	# NOTE: `x as GrassTuft` itself CRASHES on a freed object ("Trying to cast
	# a freed object") before any is_instance_valid() can run - so validate the
	# raw Variant FIRST, and erase the stale key so it can't be hit again.
	var raw: Variant = _grass_occupied_tiles.get(tile)
	if raw == null or not is_instance_valid(raw):
		_grass_occupied_tiles.erase(tile)
		return Vector2.INF
	var tuft: GrassTuft = raw as GrassTuft
	if tuft == null or not is_instance_valid(tuft):
		return Vector2.INF
	var at: Vector2 = tuft.global_position
	var cut_color := Color(0.55, 1.0, 0.45, 1.0)
	var raw_color: Variant = tuft.get("cut_color")
	if raw_color is Color:
		cut_color = raw_color
	if capture_color:
		_last_cut_grass_color = cut_color
	tuft.cut()
	if spawn_fx:
		_spawn_grass_cut_fx(at, cut_color)
	return at

func _ensure_grass_fx_pool() -> void:
	if not _grass_fx_pool.is_empty():
		return
	for i in range(4):
		var fx: Node2D = GRASS_CUT_BURST_SCRIPT.new() as Node2D
		if fx == null:
			break
		add_child(fx)
		_grass_fx_pool.append(fx)

func _spawn_grass_cut_fx(at: Vector2, color: Color) -> void:
	_ensure_grass_fx_pool()
	if _grass_fx_pool.is_empty():
		return
	var fx: Node = _grass_fx_pool[_grass_fx_index]
	_grass_fx_index = (_grass_fx_index + 1) % _grass_fx_pool.size()
	fx.call("emit_at", at, color)

# ── Grass: bounded spatial query (sword swing) ─────────────────────────
# Returns the grass tufts whose ORIGIN lies inside `rect` (WORLD space).
#
# Deliberately does NOT use get_nodes_in_group("Grass"). The overworld holds
# thousands of tufts, so the old per-frame group scan both allocated an Array
# of EVERY tuft and then transformed + tested each one: measured at 7.8 ms per
# frame with 20k tufts, i.e. ~109 ms of CPU across a 14-frame swing (0.24 s) —
# far past the 16.7 ms budget, and the cause of the sword-swing stutter. This
# walks only the handful of tiles the rect covers; both grass stores are
# already keyed by tile, so it is a few dictionary lookups per frame.
func grass_tufts_in_world_rect(rect: Rect2) -> Array:
	var found: Array = []
	if ground_layer == null:
		return found
	# A tuft's origin is anchored to the tile's BOTTOM edge (+3 px), not its
	# centre, so a tuft keyed to a tile can sit a row below the rect's own
	# tiles — expand by one tile on every side before looking up.
	var a: Vector2i = ground_layer.local_to_map(ground_layer.to_local(rect.position)) - Vector2i.ONE
	var b: Vector2i = ground_layer.local_to_map(ground_layer.to_local(rect.end)) + Vector2i.ONE
	for ty in range(a.y, b.y + 1):
		for tx in range(a.x, b.x + 1):
			var tile := Vector2i(tx, ty)
			var tuft: GrassTuft = null
			# Natural world-gen grass. Validate the raw Variant BEFORE casting:
			# `x as GrassTuft` on a freed object throws "Trying to cast a freed
			# object" (same gotcha as _cut_grass_row).
			var raw: Variant = _grass_occupied_tiles.get(tile)
			if raw != null and is_instance_valid(raw):
				tuft = raw as GrassTuft
			# Player-placed grass lives in _placed_blocks, not the natural map.
			if tuft == null:
				var entry: Variant = _placed_blocks.get(tile)
				if entry is Dictionary:
					var node_ref: Variant = (entry as Dictionary).get("node")
					if is_instance_valid(node_ref) and node_ref is GrassTuft:
						tuft = node_ref as GrassTuft
			if tuft == null or not is_instance_valid(tuft):
				continue
			if rect.has_point(tuft.global_position):
				found.append(tuft)
	return found

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
# The player's own swing effect shows the sword arc. A swing that cuts grass
# spawns ONE cheap region-sprite pop at the first cut tile instead of a
# separate effect per tuft, which used to hitch during 3x3-patch cuts.
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

# ── Farming: tilling, planting, harvesting ─────────────────────────
# A crop is a wheat plant growing on a Tilled Plot cell. Kept here (not on the
# plot) so the sword's row-cut can find it by tile exactly like grass.
var _crops: Dictionary = {}   # tile -> WheatCrop

func _mouse_cell() -> Vector2i:
	return editable_layer.local_to_map(editable_layer.to_local(Global.mouse_world(self)))

# Hoe click: turn the grass tuft under the cursor into tilled soil.
func till_grass_at_cursor() -> bool:
	return till_grass_at(_mouse_cell())

func till_grass_at(cell: Vector2i) -> bool:
	# Minecraft-style farmland: hoe the GROUND itself, not a decorative tuft.
	# Any open, dry ground tile can be tilled; a grass tuft standing on it is
	# cut first so the new soil shows through.
	if ground_layer.get_cell_source_id(cell) == -1:
		return false
	if water_layer.get_cell_source_id(cell) != -1:
		return false
	if _placed_blocks.has(cell):
		return false
	if _is_tree_occupied(cell) or _cave_entrance_cells.has(cell) \
			or _dungeon_entrance_cells.has(cell):
		return false
	# Irrigation rule: soil can only be worked near water.
	if nearest_water_distance(cell) > TILL_WATER_RADIUS_BLOCKS:
		Global.notify("[color=#ffaa66]Too far from water — soil can only be tilled within %d blocks of water.[/color]"
			% TILL_WATER_RADIUS_BLOCKS)
		return false
	var raw: Variant = _grass_occupied_tiles.get(cell)
	if raw != null and is_instance_valid(raw):
		# cut() spawns the grass burst, erases the tile and frees the tuft, so
		# the placement below sees an empty, buildable cell.
		(raw as Node).call("cut")
	return place_block_at(cell, TILLED_PLOT_ITEM) != null

# ── Water sources (bucket) ────────────────────────────────────────
# Chebyshev distance to the nearest water tile. Ring scan, so it stops as soon
# as the closest source is found; returns RADIUS + 1 when there is none in range.
func nearest_water_distance(cell: Vector2i) -> int:
	for r in range(0, TILL_WATER_RADIUS_BLOCKS + 1):
		for dx in range(-r, r + 1):
			for dy in range(-r, r + 1):
				if absi(dx) != r and absi(dy) != r:
					continue   # ring only, not the filled square
				if water_layer.get_cell_source_id(cell + Vector2i(dx, dy)) != -1:
					return r
	return TILL_WATER_RADIUS_BLOCKS + 1

func cell_is_water(cell: Vector2i) -> bool:
	return water_layer.get_cell_source_id(cell) != -1

func can_place_water_at(cell: Vector2i) -> bool:
	if water_layer.get_cell_source_id(cell) != -1:
		return false
	if _placed_blocks.has(cell):
		return false
	return ground_layer.get_cell_source_id(cell) != -1

# Pours a water tile at `cell`, creating a new water source for irrigation.
func place_water_at(cell: Vector2i) -> bool:
	if not can_place_water_at(cell):
		return false
	# Same tile the generator paints water with.
	water_layer.set_cell(cell, 0, Vector2i(0, 0))
	_note_water_cell_added(cell)
	return true

# Seeds click: plant wheat on the tilled soil under the cursor.
func plant_crop_at_cursor() -> bool:
	return plant_crop_at(_mouse_cell())

func plant_crop_at(cell: Vector2i) -> bool:
	if _crops.has(cell) and is_instance_valid(_crops[cell]):
		return false
	var entry: Variant = _placed_blocks.get(cell)
	if not (entry is Dictionary):
		return false
	var node: Variant = (entry as Dictionary).get("node")
	if not is_instance_valid(node):
		return false
	var data: Variant = (node as Node).get("item_data")
	if data == null or (data as ItemData).item_name != "Tilled Ground":
		return false
	# Only the TOP node matters: a plot with something built on it isn't soil.
	if not _is_floor_block(cell):
		return false
	_spawn_crop(cell, 0.0)
	return true

func _spawn_crop(cell: Vector2i, elapsed: float) -> void:
	if _crops.has(cell) and is_instance_valid(_crops[cell]):
		return
	var crop: Node2D = WHEAT_CROP_SCENE.instantiate() as Node2D
	if crop == null:
		return
	add_child(crop)
	crop.position = to_local(editable_layer.to_global(editable_layer.map_to_local(cell)))
	crop.set("cell", cell)
	crop.set("elapsed", elapsed)
	# Settle grown/ungrown immediately for a restored age (0.0 advances nothing).
	crop.call("_process", 0.0)
	_crops[cell] = crop

# Sword cut: harvest a MATURE crop on the tile the same facing/aim row uses.
# A sprout is left alone (harvest() returns false).
func _cut_crop_row(p: Node2D) -> void:
	var d: Vector2i = _grass_cut_offset(p)
	var cell: Vector2i = ground_layer.local_to_map(ground_layer.to_local(p.global_position)) + d
	var crop: Variant = _crops.get(cell)
	if crop == null or not is_instance_valid(crop):
		return
	if bool(crop.call("harvest")):
		_crops.erase(cell)


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
			# Validate the raw Variant before the typed cast — casting a freed
			# object crashes outright (see _cut_grass_row).
			var raw: Variant = _grass_occupied_tiles.get(feet_tile + Vector2i(dx, dy))
			if raw == null:
				continue
			if not is_instance_valid(raw):
				_grass_occupied_tiles.erase(feet_tile + Vector2i(dx, dy))
				continue
			var tuft: GrassTuft = raw as GrassTuft
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
var _block_collision_active: Dictionary = {}
var _block_collision_initialized: bool = false

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
			# Floors are walkable decor pinned UNDER the world (FLOOR_Z). Never
			# raise one over the player — otherwise the very tile the player
			# stands on gets z = player_z + 1 and covers their sprite.
			var bdata: Variant = block.get("item_data")
			if bdata != null and bdata.is_floor:
				continue
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
			# A floor must always return to FLOOR_Z, never the tile bucket.
			var bdata: Variant = block.get("item_data")
			var static_z: int = FLOOR_Z if (bdata != null and bdata.is_floor) \
				else int(block.global_position.y / TILE_SIZE)
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
	# Throttled: are we inside a valid house? (drives the day/night indoor dim)
	_indoor_check_accum += delta
	if _indoor_check_accum >= INDOOR_CHECK_SEC:
		_indoor_check_accum = 0.0
		_update_player_indoors()
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
		# Player just entered desert — guarantee a worm encounter right away.
		_spawn_desert_worms_ambient(3)
	_last_player_biome = biome

# Guaranteed worm spawns in the ambient ring (used on desert entry). Reuses the
# director's tile rules so it lands somewhere valid and off-screen.
func _spawn_desert_worms_ambient(count: int) -> void:
	var p := _get_player()
	if p == null:
		return
	var data: MobCombatData = preload("res://resources/mobs/worm.tres")
	var player_tile: Vector2i = ground_layer.local_to_map(ground_layer.to_local(p.global_position))
	for _i in range(count):
		var tile: Variant = _find_ambient_tile(player_tile, data)
		if tile == null:
			continue
		_spawn_mob_at(tile, WORM_SCENE)

# Console/debug spawner. Uses the same dry, biome-valid ambient search as the
# real director instead of dropping a worm at the player's feet (which could be
# water at a desert shoreline). Returns false when no valid tile exists.
func _spawn_desert_worms_near_player(scene: PackedScene,
		data: MobCombatData) -> bool:
	var p := _get_player()
	if p == null:
		return false
	var player_tile: Vector2i = ground_layer.local_to_map(ground_layer.to_local(p.global_position))
	var tile: Variant = _find_ambient_tile(player_tile, data)
	if tile == null:
		return false
	_spawn_mob_at(tile, scene)
	return true

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
	_build_water_tileset()
	_build_ocean_base()
	_generate_terrain()
	_invalidate_water_grid()
	# Mirror every water cell onto the static seabed layer (one pass).
	_sync_ocean_base()
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
	# Stone/charcoal patches run AFTER foliage (so they never fight a tree for
	# a tile) and BEFORE apply_world_save_data (so a restored player block wins
	# the cell if the two ever overlap). Dungeon entrances spawn later and will
	# clear any natural block sitting in their footprint.
	_place_stone_patches()
	# Coarse sand blocks follow the same rule (after foliage, before the save
	# restore) but on DESERT tiles — they are the player's source of coarse sand.
	_place_coarse_sand_patches()
	var loading_existing_world := not Global.pending_world_data.is_empty()
	var had_dungeon_waypoint_field := false
	if loading_existing_world:
		var pending_world: Dictionary = Global.pending_world_data
		had_dungeon_waypoint_field = pending_world.has("dungeon_waypoints")
		apply_world_save_data(pending_world)
		_restore_dungeon_waypoints(pending_world.get("dungeon_waypoints", []))
		Global.pending_world_data.clear()
	# Keep one dungeon entrance alive for each language's current mission.
	# Runs on world ready (including after apply_world_save_data above, which
	# may have restored saved entrance tiles) and on every later mission
	# update, so clearing a dungeon immediately posts the next entrance.
	# The ready flag gates the mission_updated handler so nothing tries to
	# spawn during world-gen (see the flag's declaration).
	_dungeon_entrances_ready = true
	_ensure_current_dungeon_entrances()
	if loading_existing_world and not had_dungeon_waypoint_field:
		# Pre-waypoint saves already have live current-dungeon entrances, so
		# _ensure won't generate new ones. Seed the one-way waypoints for those
		# current instances once; the field is present on every later save, so
		# consumed waypoints can never be recreated.
		for idx in Global.current_dungeon_indices():
			var di := int(idx)
			if _dungeon_entrance_tiles.has(di):
				_create_dungeon_waypoint(di)
	_start_interaction_updater()
	_start_despawn_timer()
	_start_ambient_spawn_timer()
	# Decorative flyers (Sunshard Finch by day, Dusk Kite at night). They live
	# under World, so cave/dungeon swaps pause them with the overworld.
	var birds: Node2D = AMBIENT_BIRDS_SCRIPT.new() as Node2D
	if birds != null:
		birds.name = "AmbientBirds"
		add_child(birds)
	_start_grass_regrow_timer()
	_start_cactus_spawn_timer()
	# Fill EVERY grass tuft BEFORE generation_complete comes down, so the world
	# is fully dressed the instant the loading screen lifts and the player
	# never watches grass pop in. This yields every few chunks (so the loading
	# screen keeps rendering and the progress label ticks), hence the await —
	# it must stay AFTER apply_world_save_data() above (needs _placed_blocks
	# final so grass doesn't overlap restored structures) and after
	# _place_foliage() (needs _tree_occupied_tiles final).
	generation_status_changed.emit("Growing grass...")
	await _fill_all_chunks_with_grass(GRASS_CHUNKS_PER_FRAME_LOAD)
	# Everything (terrain, trees, structures, mobs, grass) now exists — the
	# loading screen can come down.
	print("[WORLD] fully loaded in %dms since scene start" % [Time.get_ticks_msec() - _gen_start_ms])
	# Pre-warm the transient attack effects BEFORE the loading screen lifts so
	# the first swing/cut does not pay first-instantiation cost in gameplay.
	_prewarm_attack_effects()
	generation_complete.emit()

# Builds (and immediately frees) one sword-swing effect and one grass-cut pop
# so the first real swing/cut doesn't pay first-instantiation cost. Spawned far
# off-screen; queue_free runs at the end of the frame.
func _prewarm_attack_effects() -> void:
	var fx: Node2D = SWORD_SWING_SCRIPT.new() as Node2D
	if fx != null:
		fx.set("_mode", "swing")
		fx.set("_is_sword", true)
		fx.set("_damage", 0.0)
		fx.set("_aim", Vector2(1, 0))
		fx.position = Vector2(-100000, -100000)
		add_child(fx)
		fx.queue_free()
	_ensure_grass_fx_pool()

func _start_interaction_updater() -> void:
	# Immediate pass so trees near spawn are active the moment the player
	# appears. Grass has no equivalent — see _on_swing_performed.
	_update_tree_interactions()
	var t := Timer.new()
	t.wait_time  = 0.1
	t.autostart  = true
	t.timeout.connect(_update_tree_interactions)
	add_child(t)

# get_nodes_in_group() allocates a fresh Array every call; the Tree group is
# static after generation (trees are only REMOVED when chopped), so cache the
# array and refresh it once a second instead of rebuilding it every frame —
# _update_tree_fade runs at 60fps and _update_tree_interactions at 10Hz, so the
# old code allocated a ~1200-element array ~70 times a second.
var _tree_cache:    Array = []
var _tree_cache_ms: int   = -100000
const TREE_SPATIAL_BUCKET: float = 512.0
var _tree_spatial: Dictionary = {}
var _tree_collision_active: Dictionary = {}
var _tree_interactions_initialized: bool = false

func _get_trees() -> Array:
	var now: int = Time.get_ticks_msec()
	if now - _tree_cache_ms >= 1000:
		_tree_cache = get_tree().get_nodes_in_group("Tree")
		_tree_cache_ms = now
	return _tree_cache

func _build_tree_spatial() -> void:
	var buckets: Dictionary = {}
	for node in _get_trees():
		if not is_instance_valid(node):
			continue
		var tree := node as Node2D
		if tree == null or not tree.is_inside_tree():
			continue
		var key := Vector2i(
			floori(tree.global_position.x / TREE_SPATIAL_BUCKET),
			floori(tree.global_position.y / TREE_SPATIAL_BUCKET))
		if buckets.has(key):
			(buckets[key] as Array).append(tree)
		else:
			buckets[key] = [tree]
	_tree_spatial = buckets

# Nearby trees only. Tree iteration used to run over every tree in the world
# (1,300+) at 10 Hz and every render frame. A 512px bucket grid keeps both the
# collision-LOD update and canopy-fade driver proportional to what is nearby.
func _trees_near(pos: Vector2, radius: float) -> Array:
	if _tree_spatial.is_empty():
		_build_tree_spatial()
	var result: Array = []
	var center := Vector2i(
		floori(pos.x / TREE_SPATIAL_BUCKET),
		floori(pos.y / TREE_SPATIAL_BUCKET))
	var reach := int(ceil(radius / TREE_SPATIAL_BUCKET))
	for dy in range(-reach, reach + 1):
		for dx in range(-reach, reach + 1):
			var bucket: Variant = _tree_spatial.get(center + Vector2i(dx, dy))
			if not (bucket is Array):
				continue
			for node in bucket:
				if not is_instance_valid(node):
					continue
				var tree := node as Node2D
				if tree == null or tree.is_queued_for_deletion() \
						or not tree.is_inside_tree():
					continue
				if tree.global_position.distance_to(pos) <= radius:
					result.append(tree)
	return result

func _set_solid_collision(node: Node, active: bool) -> void:
	if node == null or not is_instance_valid(node):
		return
	var col := node.get_node_or_null("StaticBody2D/CollisionShape2D") as CollisionShape2D
	if col == null:
		return
	var disabled := not active
	if col.disabled != disabled:
		col.set_deferred("disabled", disabled)

func _block_needs_solid_collision(node: Node) -> bool:
	var data: Variant = node.get("item_data")
	if data is ItemData:
		var item := data as ItemData
		if item.is_floor or item.is_torch:
			return false
	return node.get_node_or_null("StaticBody2D/CollisionShape2D") != null

func _update_block_collision(node: Node) -> void:
	var p := _get_player()
	if p == null or not is_instance_valid(node) or not (node is Node2D):
		return
	if not _block_needs_solid_collision(node):
		return
	var active := (node as Node2D).global_position.distance_to(p.global_position) <= BLOCK_PHYSICS_RADIUS
	_set_solid_collision(node, active)
	if active:
		_block_collision_active[node] = true
	else:
		_block_collision_active.erase(node)

func _update_block_collisions(player_pos: Vector2) -> void:
	# Blocks are keyed by tile. Scan only tiles in the collision-LOD radius
	# instead of every placed block/natural stone patch in the world (which was
	# ~5-6 ms every 100 ms), and only toggle colliders that change state.
	var player_cell: Vector2i = editable_layer.local_to_map(
		editable_layer.to_local(player_pos))
	var reach: int = int(ceil(BLOCK_PHYSICS_RADIUS / float(TILE_SIZE))) + 1
	var radius_sq: float = BLOCK_PHYSICS_RADIUS * BLOCK_PHYSICS_RADIUS
	var near: Dictionary = {}
	for dx in range(-reach, reach + 1):
		for dy in range(-reach, reach + 1):
			var entry: Variant = _placed_blocks.get(player_cell + Vector2i(dx, dy))
			if not (entry is Dictionary):
				continue
			var node_ref: Variant = (entry as Dictionary).get("node")
			if node_ref == null or not is_instance_valid(node_ref) \
					or not (node_ref is Node2D):
				continue
			var node := node_ref as Node2D
			if node.global_position.distance_squared_to(player_pos) > radius_sq:
				continue
			near[node] = true
			if _block_collision_active.has(node):
				continue
			if not _block_needs_solid_collision(node):
				continue
			_set_solid_collision(node, true)
			_block_collision_active[node] = true
	# Disable colliders that were active last update but are no longer near.
	for node in _block_collision_active.keys():
		if not is_instance_valid(node) or not near.has(node):
			if is_instance_valid(node):
				_set_solid_collision(node, false)
			_block_collision_active.erase(node)
	# On the first pass, make sure distant blocks that have never been tracked
	# are disabled too (saved worlds may have restored their colliders active).
	if not _block_collision_initialized:
		_block_collision_initialized = true
		for entry in _placed_blocks.values():
			if not (entry is Dictionary):
				continue
			var node_ref: Variant = (entry as Dictionary).get("node")
			if node_ref == null or not is_instance_valid(node_ref) \
					or not (node_ref is Node2D):
				continue
			var node := node_ref as Node2D
			if not near.has(node):
				_set_solid_collision(node, false)

func _update_tree_interactions() -> void:
	var p := _get_player()
	if p == null:
		return
	# First pass after world generation disables every tree's interaction and
	# collider; subsequent passes only touch trees near the player. Without the
	# first pass, distant scene colliders would stay enabled forever now that
	# this no longer scans the whole tree group.
	if not _tree_interactions_initialized:
		_tree_interactions_initialized = true
		for tree in _get_trees():
			if not is_instance_valid(tree):
				continue
			var init_node := tree as Node2D
			var init_interact := init_node.get_node_or_null("InteractArea") as Area2D
			if init_interact != null:
				init_interact.monitoring = false
				init_interact.monitorable = false
			_set_solid_collision(init_node, false)
		_tree_collision_active.clear()

	var player_pos := p.global_position
	var near_lookup: Dictionary = {}
	for tree in _trees_near(player_pos, TREE_PHYSICS_RADIUS):
		var t_node := tree as Node2D
		near_lookup[t_node] = true
		var interact := t_node.get_node_or_null("InteractArea") as Area2D
		if interact == null:
			continue
		var dist := t_node.global_position.distance_to(player_pos)
		var should_be_active := dist <= TREE_INTERACT_RADIUS
		if interact.monitoring != should_be_active:
			interact.monitoring  = should_be_active
			interact.monitorable = should_be_active
		# Physics collision is kept active in a wider bubble so the player
		# cannot reach a tree before its collider has been enabled.
		_set_solid_collision(t_node, true)
		_tree_collision_active[t_node] = true
	# Disable trees that were enabled during the previous pass but are now out
	# of the collision bubble.
	for node in _tree_collision_active.keys():
		if not is_instance_valid(node) or not near_lookup.has(node):
			if is_instance_valid(node):
				_set_solid_collision(node, false)
			_tree_collision_active.erase(node)
	_update_block_collisions(player_pos)

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
	for tree in _trees_near(p.global_position, 160.0):
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
# Runs over EVERY mob ("Mob" group), not just wolves — worms already expose
# _apply_despawn_zone() and the fish gained one, so a backstop zone timer now
# covers everything the ambient director misses. The director's ring recycle
# (_despawn_strays) is the primary cull; this cleans up far-away stragglers.
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
	for mob in get_tree().get_nodes_in_group("Mob"):
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

# ── Ambient spawn director ───────────────────────────────────────────
# Terraria-style: a continuous, CAPPED population spawned in a ring just
# around the player. Every tick it tops the live count back up to the period's
# cap, ramping as the night deepens; mobs that stray too far are recycled so
# the budget keeps flowing. Replaces the old "far-away outer chunks every N
# minutes" pass, which stocked chunks the player never actually saw.
func _start_ambient_spawn_timer() -> void:
	var t := Timer.new()
	t.one_shot = true
	t.timeout.connect(_run_ambient_spawn)
	add_child(t)
	_ambient_spawn_timer = t
	t.start(_ambient_interval())

func _ambient_interval() -> float:
	return AMBIENT_DAY_INTERVAL if Global.is_daytime else AMBIENT_NIGHT_INTERVAL

func _ambient_cap() -> int:
	return AMBIENT_DAY_CAP if Global.is_daytime else AMBIENT_NIGHT_CAP

# Mobs eligible right now (per-mob day/night flags; biome is checked per tile).
func _ambient_pool() -> Array:
	var pool: Array = []
	for entry in MOB_SPAWN_POOL:
		var data: MobCombatData = entry["data"] as MobCombatData
		var ok_now: bool = data.spawn_during_day if Global.is_daytime else data.spawn_during_night
		if ok_now and data.spawn_weight > 0.0:
			pool.append(entry)
	return pool

func _run_ambient_spawn() -> void:
	var p := _get_player()
	if p != null and not Global.player_is_dead:
		_despawn_strays(p.global_position)
		_top_up_ambient(p.global_position)
	if _ambient_spawn_timer != null and is_instance_valid(_ambient_spawn_timer):
		_ambient_spawn_timer.start(_ambient_interval())

# Spawn attempts per tick: flat by day, ramping to the max as night deepens.
func _ambient_attempts() -> int:
	if Global.is_daytime:
		return AMBIENT_DAY_ATTEMPTS_MIN
	var t: float = _night_progress()
	return AMBIENT_NIGHT_ATTEMPTS_MIN \
		+ roundi(t * float(AMBIENT_NIGHT_ATTEMPTS_MAX - AMBIENT_NIGHT_ATTEMPTS_MIN))

func _night_progress() -> float:
	var cyc: Node = Global.day_night_cycle
	if cyc != null and cyc.has_method("night_progress"):
		return float(cyc.call("night_progress"))
	return 0.0

func _top_up_ambient(player_pos: Vector2) -> void:
	var pool: Array = _ambient_pool()
	if pool.is_empty():
		return
	var live: int = _count_ambient_mobs(player_pos)
	var cap: int = _ambient_cap()
	if live >= cap:
		return
	var budget: int = mini(_ambient_attempts(), cap - live)
	var player_tile: Vector2i = ground_layer.local_to_map(ground_layer.to_local(player_pos))
	for _i in range(budget):
		var entry: Dictionary = _pick_ambient_entry(pool)
		if entry.is_empty():
			continue
		var tile: Variant = _find_ambient_tile(player_tile, entry["data"] as MobCombatData)
		if tile == null:
			continue
		var data: MobCombatData = entry["data"] as MobCombatData
		var scene: PackedScene = entry["scene"] as PackedScene
		_spawn_mob_at(tile, scene)
		live += 1
		# Herd spawning: mobs flagged group_spawn arrive as a cluster of
		# min_spawn..max_spawn (sheep: 2-5), never exceeding the cap.
		if data.group_spawn:
			var want: int = rng.randi_range(maxi(data.min_spawn, 1), maxi(data.max_spawn, 1))
			for _g in range(1, want):
				if live >= cap:
					break
				var near: Variant = _find_tile_near(tile as Vector2i, data)
				if near == null:
					break
				_spawn_mob_at(near, scene)
				live += 1

# A valid spawn tile within a few tiles of `origin` — used for herd/group
# spawns so the extras land around the first one instead of scattering.
func _find_tile_near(origin: Vector2i, data: MobCombatData, radius: int = 4) -> Variant:
	for _i in range(12):
		var t := origin + Vector2i(rng.randi_range(-radius, radius), rng.randi_range(-radius, radius))
		if _valid_ambient_tile(t, data):
			return t
	return null

func _pick_ambient_entry(pool: Array) -> Dictionary:
	var total: float = 0.0
	for e in pool:
		total += ((e as Dictionary)["data"] as MobCombatData).spawn_weight
	if total <= 0.0:
		return {}
	var roll: float = rng.randf() * total
	for e in pool:
		roll -= ((e as Dictionary)["data"] as MobCombatData).spawn_weight
		if roll <= 0.0:
			return e as Dictionary
	return pool[pool.size() - 1] as Dictionary

# A random tile in the ring around the player the mob is allowed to stand on.
func _find_ambient_tile(player_tile: Vector2i, data: MobCombatData) -> Variant:
	for _i in range(40):
		var angle: float = rng.randf() * TAU
		var dist:  float = rng.randf_range(float(AMBIENT_RING_MIN_TILES), float(AMBIENT_RING_MAX_TILES))
		var tile := Vector2i(
			player_tile.x + roundi(cos(angle) * dist),
			player_tile.y + roundi(sin(angle) * dist))
		if _valid_ambient_tile(tile, data):
			return tile
	return null

# Ground rules: biome the mob allows, dry land for land mobs, not on a player
# placement (keeps bases safe), not on a structure, not right on world spawn.
func _valid_ambient_tile(tile: Vector2i, data: MobCombatData) -> bool:
	var biome: int = _cell_biome_type(tile)
	if not _mob_allows_biome(data, biome):
		return false
	if biome != -1 and _has_water_nearby(tile, 3):
		return false
	if _placed_blocks.has(tile):
		return false
	# No ambient spawns inside a valid house (safe zone).
	if housing_is_valid_room_cell(tile):
		return false
	if structures_layer.get_cell_source_id(tile) != -1:
		return false
	var world_pos: Vector2 = ground_layer.to_global(ground_layer.map_to_local(tile))
	if world_pos.distance_to(_world_spawn_pos()) < float(AMBIENT_SPAWN_SAFE_TILES) * TILE_SIZE:
		return false
	return true

# Live ambient mobs within the ring; the director's cap counts only these, so
# distant/foreign mobs never eat the budget.
func _count_ambient_mobs(player_pos: Vector2) -> int:
	var limit: float = float(AMBIENT_RING_MAX_TILES) * TILE_SIZE
	var n: int = 0
	for mob in get_tree().get_nodes_in_group("Mob"):
		if is_instance_valid(mob) \
				and (mob as Node2D).global_position.distance_to(player_pos) <= limit:
			n += 1
	return n

# Recycle mobs that have wandered well past the ring so their slot is freed
# for a fresh spawn. Never teleports — they despawn and something new arrives.
func _despawn_strays(player_pos: Vector2) -> void:
	var limit: float = float(AMBIENT_DESPAWN_TILES) * TILE_SIZE
	var next: Dictionary = {}
	for mob in get_tree().get_nodes_in_group("Mob"):
		if not is_instance_valid(mob):
			continue
		var m2d: Node2D = mob as Node2D
		if m2d.global_position.distance_to(player_pos) <= limit:
			continue
		var id: int = m2d.get_instance_id()
		var t: float = float(_ambient_stray.get(id, 0.0)) + _ambient_interval()
		if t >= AMBIENT_STRAY_LINGER:
			mob.queue_free()
		else:
			next[id] = t
	_ambient_stray = next

# ── Dusk / dawn kickstart ────────────────────────────────────────────
# The moment the period flips, fill the arena straight to the new cap (the
# Terraria dusk burst), then the director tops it up as mobs die or stray out.
# Night mobs despawn themselves at day_started, so dawn refills with the day
# pool and the world never sits empty.
func _on_night_started() -> void:
	_fill_ambient_to_cap()
	_restart_ambient_timer()

func _on_day_started() -> void:
	_fill_ambient_to_cap()
	_restart_ambient_timer()

func _restart_ambient_timer() -> void:
	if _ambient_spawn_timer != null and is_instance_valid(_ambient_spawn_timer):
		_ambient_spawn_timer.start(_ambient_interval())

func _fill_ambient_to_cap() -> void:
	var p := _get_player()
	if p == null:
		return
	var pool: Array = _ambient_pool()
	if pool.is_empty():
		return
	var live: int = _count_ambient_mobs(p.global_position)
	var cap: int = _ambient_cap()
	var player_tile: Vector2i = ground_layer.local_to_map(ground_layer.to_local(p.global_position))
	var guard: int = 0
	while live < cap and guard < cap * 40:
		guard += 1
		var entry: Dictionary = _pick_ambient_entry(pool)
		if entry.is_empty():
			break
		var tile: Variant = _find_ambient_tile(player_tile, entry["data"] as MobCombatData)
		if tile == null:
			continue
		_spawn_mob_at(tile, entry["scene"] as PackedScene)
		live += 1

# ── Mob preservation (save/load) ─────────────────────────────────────
func _is_in_preserve_zone(pos: Vector2, player_pos: Vector2) -> bool:
	if pos.distance_to(player_pos) <= MOB_PRESERVE_PLAYER_RADIUS:
		return true
	return pos.distance_to(_world_spawn_pos()) <= MOB_PRESERVE_SPAWN_RADIUS

func _collect_preserved_mobs() -> Array:
	var mobs_data: Array = []
	# The world can be off-tree when this runs (saves triggered during cave/
	# dungeon swaps remove World via remove_child) — checking get_tree() itself
	# logs an engine error when data.tree is null, so test is_inside_tree().
	if not is_inside_tree():
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
	# is_inside_tree() avoids the engine error that get_tree() logs off-tree.
	if not is_inside_tree():
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
			# A floor cell is placeable decor — show the grid on it (as valid).
			if (_placed_blocks.has(cell) and not _is_floor_block(cell)) \
					or editable_layer.get_cell_source_id(cell) != -1:
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
	var mouse_local: Vector2  = ground_layer.to_local(Global.mouse_world(self))
	var cell:        Vector2i = ground_layer.local_to_map(mouse_local)
	var snapped:     Vector2  = ground_layer.map_to_local(cell)
	_cursor_highlight.global_position = ground_layer.to_global(snapped)
	_cursor_highlight.queue_redraw()
	_cursor_highlight.visible = true

func _update_hover() -> void:
	if Global.block_mode:
		Global.set_hover("")
		return
	var mouse_pos: Vector2 = Global.mouse_world(self)
	var best_name: String  = ""
	var best_name_dist: float = INTERACT_RADIUS_PX
	# Only blocks within INTERACT_RADIUS_PX of the cursor can match, so scan
	# just that tile neighbourhood instead of every placed block — with the
	# world-gen stone/charcoal patches the dictionary can hold thousands.
	var mouse_cell: Vector2i = editable_layer.local_to_map(editable_layer.to_local(mouse_pos))
	var reach: int = int(ceil(INTERACT_RADIUS_PX / float(TILE_SIZE))) + 1
	for dx in range(-reach, reach + 1):
		for dy in range(-reach, reach + 1):
			var entry: Variant = _placed_blocks.get(mouse_cell + Vector2i(dx, dy))
			if not (entry is Dictionary):
				continue
			var node_ref: Variant = (entry as Dictionary).get("node")
			if not is_instance_valid(node_ref):
				continue
			var node: Node2D = node_ref as Node2D
			if node == null:
				continue
			var name_dist: float = mouse_pos.distance_to(node.global_position)
			if name_dist < best_name_dist:
				best_name_dist = name_dist
				# Blocks may expose a contextual hover prompt (a bonfire says
				# "click to set respawn"); otherwise show the item name.
				if node.has_method("hover_prompt"):
					best_name = str(node.call("hover_prompt"))
				else:
					best_name = str((entry as Dictionary).get("name", ""))
	Global.set_hover(best_name)

func _is_placeable_item(item) -> bool:
	if item == null or not (item is Dictionary) or not item.has("data"):
		return false
	return (item["data"] as ItemData).is_placeable

# True when a block may legally occupy `cell` — the shared validation used by
# BOTH the player's place_block() and the Lua robot's placement. Pure query:
# no side effects, so it can be called to preview/validate a whole build.
func can_place_at(cell: Vector2i) -> bool:
	# A FLOOR block is walkable decor — it does NOT occupy the cell for building
	# (you can place a block over it, and build mode shows the cell as valid).
	if _placed_blocks.has(cell) and not _is_floor_block(cell):
		return false
	if editable_layer.get_cell_source_id(cell) != -1:
		return false
	if _grass_occupied_tiles.has(cell):
		return false
	if _is_tree_occupied(cell):
		return false
	if _cave_entrance_cells.has(cell) or _dungeon_entrance_cells.has(cell):
		return false
	if _world_waypoint_cells.has(cell) or _dungeon_waypoint_cells.has(cell):
		return false
	if water_layer.get_cell_source_id(cell) != -1:
		return false
	return true

# Number of placed LUA stations in the world (the "LuaNPC" group).
func _lua_station_count() -> int:
	var n := 0
	for node in get_tree().get_nodes_in_group("LuaNPC"):
		if is_instance_valid(node):
			n += 1
	return n

# Places `item_data`'s block at `cell` (world/tile coords), skipping the
# player-specific checks (reach radius, player-overlap). Returns the spawned
# node, or null when the cell is invalid or the scene can't load. Does NOT
# touch any inventory — the CALLER decides what to consume. Shared by the
# player's place_block() and the Lua robot so both obey identical rules.
func place_block_at(cell: Vector2i, item_data: ItemData, count_mission: bool = true) -> Node:
	if item_data == null or item_data.place_scene_path == "":
		return null
	if not can_place_at(cell):
		return null
	# Cap the number of placed LUA stations (LUA 0 .. LUA 30).
	if item_data.item_id() == "lua" and _lua_station_count() >= LUA_MAX_STATIONS:
		Global.notify("Automatica limit reached (%d placed)." % LUA_MAX_STATIONS)
		return null
	if not ResourceLoader.exists(item_data.place_scene_path):
		return null
	var obj_scene: PackedScene = load(item_data.place_scene_path)
	if obj_scene == null:
		return null
	var obj: Node = obj_scene.instantiate()
	if obj == null:
		return null
	var solid_block: bool = item_data != null and not item_data.is_floor and not item_data.is_torch
	if solid_block:
		var block_col := obj.get_node_or_null("StaticBody2D/CollisionShape2D") as CollisionShape2D
		if block_col != null:
			block_col.disabled = true
	# ChestBlock caches its @onready sprite, so its item texture must be applied
	# after add_child(). Other placeables keep setup-before-add.
	var chest_like := item_data.place_scene_path.ends_with("ChestBlock.tscn")
	if not chest_like and obj.has_method("setup"):
		obj.call("setup", item_data)
	# Floors are walkable ground: placing a BLOCK on a floor cell KEEPS the floor
	# underneath it, so the ground survives and returns when the block is broken.
	# Placing a FLOOR replaces whatever was there; placing a block on another
	# block replaces that block.
	var kept_floor: Variant = null
	if _placed_blocks.has(cell):
		var old_entry: Dictionary = _placed_blocks[cell]
		var old_node:  Variant = old_entry.get("node")
		var old_floor: Variant = old_entry.get("floor")
		if item_data.is_floor:
			if old_node != null and is_instance_valid(old_node):
				old_node.queue_free()
			if old_floor != null and is_instance_valid(old_floor):
				old_floor.queue_free()
		else:
			if old_floor != null and is_instance_valid(old_floor):
				kept_floor = old_floor
				if old_node != null and is_instance_valid(old_node):
					old_node.queue_free()
			elif _is_floor_node(old_node):
				kept_floor = old_node
			elif old_node != null and is_instance_valid(old_node):
				old_node.queue_free()
	_placed_blocks[cell] = {"node": obj, "name": item_data.item_name}
	if kept_floor != null:
		(_placed_blocks[cell] as Dictionary)["floor"] = kept_floor
	if obj.has_method("set_world_cell"):
		obj.call("set_world_cell", cell, self)
	add_child(obj)
	if not is_instance_valid(obj):
		_placed_blocks.erase(cell)
		return null
	if chest_like and obj.has_method("setup"):
		obj.call("setup", item_data)
	var world_pos: Vector2 = editable_layer.map_to_local(cell)
	obj.position = world_pos
	# Floors render UNDER the world (fixed low z); everything else y-sorts.
	obj.z_index  = FLOOR_Z if (item_data != null and item_data.is_floor) else int(world_pos.y / TILE_SIZE)
	_fix_sprite_offset(obj)
	if solid_block:
		_update_block_collision(obj)
	_refresh_neighbor_u_collision(cell)
	housing_rebuild_around(cell)
	# Debris burst coloured like the block (also the visual feedback the robot's
	# paced placement rides on).
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
	# One confirmed successful placement = one mission event. Counting the
	# live _placed_blocks size also counted world-gen stone/charcoal, torches,
	# and restored blocks, so the objective advanced by the wrong amount.
	# Tutorial camp props pass count_mission=false so onboarding setup cannot
	# silently complete the player's real building missions.
	if count_mission:
		Global.record_block_placed(item_data)
	Global.set_mission_progress("build_shelter", housing_valid_room_count())
	CrashLogger.event("WORLD", "place %s cell=(%d, %d)" % [
		item_data.item_name, cell.x, cell.y])
	return obj

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
	var mouse_local: Vector2  = editable_layer.to_local(Global.mouse_world(self))
	var cell:        Vector2i = editable_layer.local_to_map(mouse_local)
	var world_pos:   Vector2  = editable_layer.map_to_local(cell)
	ghost.global_position = editable_layer.to_global(world_pos)
	if not _is_cell_in_place_radius(cell):
		ghost.visible = false
		return
	ghost.visible = true
	# A floor cell is walkable ground you can place ON (matches can_place_at and
	# the build grid) — only a non-floor block counts as occupied.
	var occupied:    bool = (_placed_blocks.has(cell) and not _is_floor_block(cell)) \
		or editable_layer.get_cell_source_id(cell) != -1 \
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
	# A DEAD player must not place blocks: this runs from the WORLD's _input
	# (not the player's), so the player being frozen/hidden during the respawn
	# window doesn't stop it.
	if Global.player_is_dead:
		return
	var item = Global.get_hotbar_item()
	if not _is_placeable_item(item):
		return
	var mouse_pos := editable_layer.to_local(Global.mouse_world(self))
	var cell      := editable_layer.local_to_map(mouse_pos)
	if not _is_cell_in_place_radius(cell):
		return
	if _cell_blocked_by_player(cell):
		return
	# All the terrain/occupancy rules live in place_block_at() → can_place_at()
	# so the Lua robot places under identical constraints.
	var item_data: ItemData = item["data"] as ItemData
	var obj: Node = place_block_at(cell, item_data)
	if obj == null:
		return
	Global.remove_item(item_data)
	if item_data.item_name == "Torch" or item_data.item_name.to_lower().contains("torch"):
		Global.complete_mission("place_torch")

func unregister_block(cell: Vector2i) -> void:
	# If a floor was kept under the block being removed, restore it as the cell's
	# block so the ground survives (placing on a floor never destroys it).
	var entry: Variant = _placed_blocks.get(cell)
	var kept_floor: Variant = null
	if entry != null:
		kept_floor = (entry as Dictionary).get("floor")
	if is_instance_valid(kept_floor):
		var fd: ItemData = kept_floor.get("item_data") as ItemData
		_placed_blocks[cell] = {"node": kept_floor, "name": (fd.item_name if fd != null else "Floor")}
	else:
		_placed_blocks.erase(cell)
	# A crop only grows on tilled soil — if the plot itself is gone (not merely
	# covered by a block), remove the crop so wheat can't float on bare ground.
	if _crops.has(cell):
		var still_plot: bool = false
		var top: Variant = _placed_blocks.get(cell)
		if top is Dictionary:
			var top_node: Variant = (top as Dictionary).get("node")
			if is_instance_valid(top_node):
				var top_data: Variant = (top_node as Node).get("item_data")
				still_plot = top_data != null and (top_data as ItemData).item_name == "Tilled Ground"
		if not still_plot:
			var crop_ref: Variant = _crops[cell]
			if is_instance_valid(crop_ref):
				(crop_ref as Node).queue_free()
			_crops.erase(cell)
	# A block vanished — any block stacked above/below it may no longer need
	# its full-height side walls.
	_refresh_neighbor_u_collision(cell)
	# The room may have merged/opened up — re-evaluate it.
	housing_rebuild_around(cell)
	Global.set_mission_progress("build_shelter", housing_valid_room_count())

# True when a player-placed block occupies this cell. Used by PlaceableBlock's
# U-collider toggle to detect vertical stacking.
func has_placed_block(cell: Vector2i) -> bool:
	return _placed_blocks.has(cell)

# A torch mounts to a SOLID neighbour. In the overworld that's a wall/door/
# furniture block, including world-gen stone/charcoal. Floors are walkable
# decor and torches/bonfires are non-solid auxiliary lights, so none of those
# may make an adjacent torch look wall-mounted. (Caves override the idea with
# solid wall cells; see cave_world.gd / pixie_cave_world.gd.)
func torch_support(cell: Vector2i) -> bool:
	if not _placed_blocks.has(cell):
		return false
	var d: ItemData = placed_item(cell)
	if d == null:
		return false
	return not d.is_floor and not d.is_torch

# True here (the overworld). Caves/dungeons return false — used by the Bonfire
# to decide whether its position is a valid overworld respawn point.
func is_overworld() -> bool:
	return true

# ── Housing (room detection) ──────────────────────────────────────────
# A "room" is a 4-connected region of FLOOR cells enclosed by player-placed
# boundary blocks (walls + doors). VALID = sealed (no leak) + >=1 door on the
# boundary + interior bounding box >= 3x3. Rebuilt incrementally around a
# placed/broken block (place_block_at / unregister_block). Overworld only.
#
# The flood ALSO traverses INTERIOR blocks (furniture placed on the floor, and
# the enclosed side of thick walls) so a house stays ONE connected room no
# matter how much furniture is placed inside or how large it is — a floor-only
# flood split at every chest/station, which is why interiors flickered to
# "outside" near furniture. A block is interior iff none of its 4 neighbours is
# open ground; a real wall/door always touches open ground.
const ROOM_MAX_CELLS: int = 1600
# Floors render UNDER the world (fixed z; above the -300 ground layer, below all
# y-sorted sprites/player).
const FLOOR_Z: int = -200
# How often to re-check whether the player is inside a valid house.
const INDOOR_CHECK_SEC: float = 0.2
# Downward offset from the player origin (chest) to the feet box centre, used
# for indoor tile detection (see _update_player_indoors).
const INDOOR_FEET_OFFSET: float = 17.0
var _indoor_check_accum: float = 0.0
var _interior_shade: Node2D = null   # darkens the world OUTSIDE the house (see interior_shade.gd)
const ROOM_MIN_SIDE:  int = 3
const ROOM_OFFS: Array = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]

var _room_of:      Dictionary = {}   # floor cell -> room id
var _rooms:        Dictionary = {}   # room id -> {cells, valid, has_door}
var _next_room_id: int        = 1

# The ItemData of a player-placed block at `cell`, or null (natural/empty).
func placed_item(cell: Vector2i) -> ItemData:
	var e = _placed_blocks.get(cell)
	if e == null:
		return null
	var n = (e as Dictionary).get("node")
	if n != null and is_instance_valid(n) and n.get("item_data") != null:
		return n.get("item_data") as ItemData
	return null

# The TOP block node at `cell` (a block, a floor, or null). A block placed on a
# floor becomes the top node; the kept floor underneath is NOT the top. Used by
# PlaceableBlock._is_top_block() so a floor doesn't consume the block's clicks.
func placed_node(cell: Vector2i) -> Node:
	var e: Variant = _placed_blocks.get(cell)
	if e == null:
		return null
	var n: Variant = (e as Dictionary).get("node")
	return n if is_instance_valid(n) else null

func _is_floor_block(cell: Vector2i) -> bool:
	if _is_natural_block(cell):
		return false
	var d := placed_item(cell)
	if d != null and d.is_floor:
		return true
	# A floor kept under a WALKABLE auxiliary block (torch/bonfire — no collision)
	# still counts as interior ground, so standing on one inside a house stays
	# "indoors" and the room's floor region covers it. A wall/door/furniture on
	# top is a solid boundary, not ground.
	if d != null and d.is_torch:
		var e: Variant = _placed_blocks.get(cell)
		if e != null and is_instance_valid((e as Dictionary).get("floor")):
			return true
	return false

# True when a node is a floor block (walkable ground). Used to decide whether a
# block being placed can KEEP the floor underneath it. Takes a Variant (may be a
# freed node) so the caller never binds a freed object to a typed Node param.
func _is_floor_node(node: Variant) -> bool:
	if not is_instance_valid(node):
		return false
	var d = node.get("item_data")
	return d != null and d.is_floor

func _is_door_block(cell: Vector2i) -> bool:
	if _is_natural_block(cell):
		return false
	var d := placed_item(cell)
	return d != null and d.is_door

# Boundary = a player-placed block that is NOT walkable ground (walls, doors,
# furniture). The exact complement of _is_floor_block, so a torch/bonfire on a
# floor is ground, not a boundary.
func _is_boundary_block(cell: Vector2i) -> bool:
	if not _placed_blocks.has(cell) or _is_natural_block(cell):
		return false
	return not _is_floor_block(cell)

# Rebuild the rooms touching `cell` (+ its 4 neighbours). Called after any
# placed-block change. Handles merges (a wall broke) and splits (a wall placed).
func housing_rebuild_around(cell: Vector2i) -> void:
	var dirty: Dictionary = {}
	var probe: Array = [cell]
	for off in ROOM_OFFS:
		probe.append(cell + off)
	for c in probe:
		var rid = _room_of.get(c)
		if rid != null and _rooms.has(rid):
			for rc in (_rooms[rid]["cells"] as Array):
				dirty[rc] = true
		dirty[c] = true
	for c in dirty.keys():
		_room_of.erase(c)
	for rid in _rooms.keys():
		var still := false
		for rc in (_rooms[rid]["cells"] as Array):
			if _room_of.has(rc):
				still = true
				break
		if not still:
			_rooms.erase(rid)
	for c in dirty.keys():
		if _is_floor_block(c) and not _room_of.has(c):
			_rebuild_room_from(c)

# Full rebuild (after a save-restore). Cheap — floors are few.
func housing_rebuild_all() -> void:
	_room_of.clear()
	_rooms.clear()
	_next_room_id = 1
	for cell in _placed_blocks.keys():
		if _is_floor_block(cell) and not _room_of.has(cell):
			_rebuild_room_from(cell)

func _rebuild_room_from(seed: Vector2i) -> void:
	var cells: Array = _flood_floor(seed)
	if cells.is_empty():
		return
	var rid: int = _next_room_id
	_next_room_id += 1
	var sealed := true
	var has_door := false
	for c in cells:
		_room_of[c] = rid
		for off in ROOM_OFFS:
			var n: Vector2i = (c as Vector2i) + (off as Vector2i)
			if _is_floor_block(n):
				continue
			if _is_boundary_block(n):
				if _is_door_block(n):
					has_door = true
			else:
				sealed = false
	var valid: bool = sealed and has_door and _room_min_size(cells)
	_rooms[rid] = {"cells": cells, "valid": valid, "has_door": has_door}

# Collect the floor cells of the room reachable from `seed`, traversing THROUGH
# interior (furniture) blocks so furniture never splits a house. Only floor
# cells are returned; interior blocks are pass-through only.
func _flood_floor(seed: Vector2i) -> Array:
	var out: Array = []
	var seen: Dictionary = {seed: true}
	var queue: Array = [seed]
	while not queue.is_empty():
		var c: Vector2i = queue.pop_front()
		if _is_floor_block(c):
			out.append(c)
			if out.size() >= ROOM_MAX_CELLS:
				break
		for off in ROOM_OFFS:
			var n: Vector2i = c + (off as Vector2i)
			if seen.has(n):
				continue
			if _is_floor_block(n) or _is_interior_block(n):
				seen[n] = true
				queue.append(n)
	return out

# A placed non-floor block that is fully surrounded by blocks (no open-ground
# neighbour) is INTERIOR — furniture placed on the floor, or the inner layer of
# a thick wall. A boundary wall/door always has at least one open neighbour
# (the outside), so it is NOT traversed and houses never merge through a wall.
func _is_interior_block(cell: Vector2i) -> bool:
	if not _is_boundary_block(cell):
		return false
	for off in ROOM_OFFS:
		if not _placed_blocks.has(cell + (off as Vector2i)):
			return false
	return true

func _room_min_size(cells: Array) -> bool:
	var mn := Vector2i(1 << 20, 1 << 20)
	var mx := Vector2i(-(1 << 20), -(1 << 20))
	for c in cells:
		var v: Vector2i = c
		mn.x = mini(mn.x, v.x); mn.y = mini(mn.y, v.y)
		mx.x = maxi(mx.x, v.x); mx.y = maxi(mx.y, v.y)
	return (mx.x - mn.x + 1) >= ROOM_MIN_SIDE and (mx.y - mn.y + 1) >= ROOM_MIN_SIDE

# True when `cell` sits inside a VALID room (used by the no-spawn safe zone).
func housing_is_valid_room_cell(cell: Vector2i) -> bool:
	var rid = _room_of.get(cell)
	if rid == null or not _rooms.has(rid):
		return false
	return bool((_rooms[rid] as Dictionary)["valid"])

func housing_valid_room_count() -> int:
	var n := 0
	for rid in _rooms:
		if bool((_rooms[rid] as Dictionary)["valid"]):
			n += 1
	return n

# Is the player standing inside a VALID house? Sets Global.player_indoors and
# drives the interior shade (dim the world OUTSIDE the house, keep the room
# itself fully bright). Instant.
#
# Detection uses the FEET tile, not the origin (chest): the origin sits ~23px
# above the feet, so near a top wall the chest tile lands on the wall while the
# feet are still on the floor — that made interiors flicker to "outside" at the
# edges. The feet box (collider centre at +17) is always on the standing tile.
func _update_player_indoors() -> void:
	var p := _get_player()
	if p == null:
		Global.player_indoors = false
		_update_interior_shade(false, [])
		return
	var feet: Vector2 = p.global_position + Vector2(0.0, INDOOR_FEET_OFFSET)
	var tile: Vector2i = editable_layer.local_to_map(editable_layer.to_local(feet))
	var indoors: bool = housing_is_valid_room_cell(tile)
	Global.player_indoors = indoors
	var cells: Array = []
	if indoors:
		var rid = _room_of.get(tile)
		if rid != null and _rooms.has(rid):
			cells = (_rooms[rid] as Dictionary)["cells"] as Array
	_update_interior_shade(indoors, cells)

# Hand the current room's floor cells to interior_shade.gd (it cuts a hole in
# the darkening over them). `active` false clears it immediately.
func _update_interior_shade(active: bool, cells: Array) -> void:
	if _interior_shade == null or not is_instance_valid(_interior_shade):
		return
	_interior_shade.call("set_shade", active, cells)

# World position -> tile cell (editable grid). Shared with the Lua robot's
# placement so it targets the same cells the player's mouse would.
func world_to_cell(world_pos: Vector2) -> Vector2i:
	return editable_layer.local_to_map(editable_layer.to_local(world_pos))

# Tile cell -> world (centre) position.
func cell_to_world(cell: Vector2i) -> Vector2:
	return editable_layer.to_global(editable_layer.map_to_local(cell))

# Re-evaluate the U-collider of `cell` plus its 8 neighbours. Called whenever a
# block appears or disappears, so a vertical column (above/below) OR a diagonal
# pair gains/loses its side walls the moment its neighbour is added or broken.
func _refresh_neighbor_u_collision(cell: Vector2i) -> void:
	for off in [Vector2i.ZERO, Vector2i(0, -1), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(1, 0),
			Vector2i(-1, -1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(1, 1)]:
		var c: Vector2i = cell + (off as Vector2i)
		if not _placed_blocks.has(c):
			continue
		# Untyped: a freed neighbour node assigned to a typed `Node` var throws
		# "Trying to assign invalid previously freed instance".
		var n: Variant = (_placed_blocks[c] as Dictionary).get("node")
		if is_instance_valid(n) and n.has_method("refresh_u_collision"):
			n.call("refresh_u_collision")
		if is_instance_valid(n) and n.has_method("refresh_torch_connection"):
			n.call("refresh_torch_connection")

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
	if _world_waypoint_cells.has(cell) or _dungeon_waypoint_cells.has(cell):
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

# ── Camera bounds ───────────────────────────────────────────────────
# The playable rect of THIS area, in world coordinates. The generated grid is
# centred on the origin (see _generate_terrain's cell_offset), so the bounds are
# simply the grid extent — the camera clamps to it (player.gd) and never scrolls
# past the overworld's edge.
func camera_bounds() -> Rect2:
	var half := Vector2i(width, height) / 2
	return Rect2(-Vector2(half) * float(TILE_SIZE),
		Vector2(width, height) * float(TILE_SIZE))

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

# ── Coarse sand tile source ─────────────────────────────────────────
# Coarse sand is a DESERT surface variant. Its 32x32 tile is added as a runtime
# TileSetAtlasSource (the same approach as the experimental ground above) so no
# scene edit is needed, and _cell_biome_type can recognise the source as desert.
func _apply_coarse_sand_source() -> void:
	var tex := load("res://sprites/tilesets/coarse_sand.png") as Texture2D
	if tex == null:
		push_warning("coarse_sand.png not found — coarse sand will not generate")
		return
	var src := TileSetAtlasSource.new()
	src.texture             = tex
	src.texture_region_size = Vector2i(TILE_SIZE, TILE_SIZE)
	src.create_tile(Vector2i(0, 0))
	_coarse_sand_src = ground_layer.tile_set.add_source(src)

# Returns 0=Plain, 1=Desert, 2=Snowy, -1=Water/none
func _cell_biome_type(tile_coord: Vector2i) -> int:
	if _biome_grid_ready:
		var idx: int = _water_grid_index(tile_coord)
		if idx < 0:
			return -1
		var code: int = int(_biome_grid[idx])
		return -1 if code == 255 else code
	var src: int = ground_layer.get_cell_source_id(tile_coord)
	if src == -1:
		return -1
	# Coarse sand is a desert surface VARIANT: it must read as desert so trees
	# never spawn on it and every other desert rule still applies.
	if src == _coarse_sand_src:
		return 1
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
# ── Animated water tiles ───────────────────────────────────────────
# The water surface is the project's own 8-frame water sheet (water_tile.png),
# played as a NATIVE Godot animated tile — not a shader. The ocean floor
# (ocean_base.png) is layered underneath (see _build_ocean_base).
const WATER_SHEET: Texture2D = preload("res://sprites/water/water_tile.png")
# The ocean floor: a single 32x32 seabed tile layered UNDER the animated water.
const OCEAN_BASE_TEX: Texture2D = preload("res://sprites/water/ocean_base.png")
const WATER_FRAME_COUNT: int = 8
const WATER_FRAME_SEC: float = 0.34   # ≥300ms/frame so it stays calm
# The animated water layer is drawn slightly translucent so the seabed shows
# through it (1.0 = the seabed is hidden).
const WATER_LAYER_ALPHA: float = 0.85

# Build the water TileSet (a single animated water tile) and assign it to the
# Water layer, replacing the shared ground TileSet. The water LOGIC only checks
# `get_cell_source_id() != -1`, so gameplay is unaffected by the change.
func _build_water_tileset() -> void:
	if water_layer == null:
		return
	var ts := TileSet.new()
	ts.tile_size = Vector2i(32, 32)
	var src := TileSetAtlasSource.new()
	src.texture             = WATER_SHEET
	src.texture_region_size = Vector2i(32, 32)
	src.create_tile(Vector2i(0, 0))
	ts.add_source(src, 0)
	# An animated tile's frames are the IMPLICIT texture regions at (1,0)..(N-1,0)
	# — no separate tiles are created for them (create_tile would refuse, since
	# the animation covers that atlas space).
	src.set_tile_animation_frames_count(Vector2i(0, 0), WATER_FRAME_COUNT)
	for i in range(WATER_FRAME_COUNT):
		src.set_tile_animation_frame_duration(Vector2i(0, 0), i, WATER_FRAME_SEC)
	water_layer.tile_set = ts

# ── Ocean floor (seabed) ──────────────────────────────────────────
# Godot 4.6 has no per-tile RENDERING layers (TileData only exposes custom-data
# layers), so the seabed is a separate STATIC TileMapLayer under the animated
# Water layer. Every water cell gets the ocean_base tile there, and the water
# layer is drawn slightly translucent so the seabed reads through it.
var _ocean_base_layer: TileMapLayer = null

func _build_ocean_base() -> void:
	if _ocean_base_layer != null and is_instance_valid(_ocean_base_layer):
		return
	var ts := TileSet.new()
	ts.tile_size = Vector2i(32, 32)
	var src := TileSetAtlasSource.new()
	src.texture             = OCEAN_BASE_TEX
	src.texture_region_size = Vector2i(32, 32)
	src.create_tile(Vector2i(0, 0))
	ts.add_source(src, 0)
	var layer := TileMapLayer.new()
	layer.name = "OceanBase"
	layer.tile_set = ts
	layer.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	layer.z_index = (water_layer.z_index - 2) if water_layer != null else -302
	add_child(layer)
	_ocean_base_layer = layer
	# Let the seabed show through the animated water.
	if water_layer != null:
		water_layer.modulate = Color(1, 1, 1, WATER_LAYER_ALPHA)

# Mirror every water cell onto the static seabed layer underneath. Runs once
# after the terrain exists — there is no per-frame tile work.
func _sync_ocean_base() -> void:
	if water_layer == null or _ocean_base_layer == null or not is_instance_valid(_ocean_base_layer):
		return
	for c in water_layer.get_used_cells():
		_ocean_base_layer.set_cell(c, 0, Vector2i(0, 0))
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
	_biome_grid.resize(width * height)
	_biome_grid.fill(255)
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
						water_layer.set_cell(c, 0, Vector2i(0, 0))
			else:
				match t:
					Terrain.Plain:
						ground_layer.set_cell(c, 0, Vector2i(0, 0))
					Terrain.Desert:
						ground_layer.set_cell(c, 0, Vector2i(1, 0))
					Terrain.Snowy:
						ground_layer.set_cell(c, 0, Vector2i(1, 1))
					_:
						water_layer.set_cell(c, 0, Vector2i(0, 0))
			var grid_idx: int = _water_grid_index(c)
			if grid_idx >= 0:
				_biome_grid[grid_idx] = 255 if t == Terrain.Water else int(t) - 1

	# Desert surface variant: paint coarse-sand clumps over the finished terrain.
	_paint_coarse_sand_patches(cell_offset)
	_biome_grid_ready = true

# ── Coarse sand patches (desert surface variant) ────────────────────
# Irregular clumps of darker sand inside deserts. Grown per chunk from a
# chunk-seeded rng (the same pattern the grass fill uses) so the layout is
# stable for a world seed WITHOUT drawing from the shared generation rng, which
# would shift every later world-gen roll and change existing worlds.
#
# Clumps are grown as a random-walk frontier rather than as squares or per-tile
# noise, so they read as natural drifts, and a small fraction of steps also drop
# an ISOLATED tile a couple of tiles out — the "occasional isolated tile near
# cluster edges" the desert should have.
func _paint_coarse_sand_patches(cell_offset: Vector2i) -> void:
	if _coarse_sand_src == -1:
		return
	for cx in range(_chunk_cols):
		for cy in range(_chunk_rows):
			var chunk := Vector2i(cx, cy)
			var crng := RandomNumberGenerator.new()
			crng.seed = int(random_seed) ^ (_chunk_hash(chunk) * 31)
			if crng.randf() >= COARSE_SAND_CHUNK_CHANCE:
				continue
			var tl := Vector2i(chunk.x * CHUNK_SIZE, chunk.y * CHUNK_SIZE) - cell_offset
			var desert: Array[Vector2i] = []
			for dx in range(CHUNK_SIZE):
				for dy in range(CHUNK_SIZE):
					var c: Vector2i = tl + Vector2i(dx, dy)
					if _is_desert_ground(c):
						desert.append(c)
			if desert.size() < COARSE_SAND_PATCH_MIN:
				continue
			for _clump in range(crng.randi_range(1, 2)):
				var target: int = crng.randi_range(COARSE_SAND_PATCH_MIN, COARSE_SAND_PATCH_MAX)
				var origin: Vector2i = desert[crng.randi_range(0, desert.size() - 1)]
				var frontier: Array = [origin]
				var seen: Dictionary = {origin: true}
				var placed := 0
				while placed < target and not frontier.is_empty():
					var idx: int = crng.randi_range(0, frontier.size() - 1)
					var cur: Vector2i = frontier[idx]
					frontier.remove_at(idx)
					if not _is_plain_desert_ground(cur):
						continue
					ground_layer.set_cell(cur, _coarse_sand_src, Vector2i(0, 0))
					placed += 1
					if crng.randf() < 0.10:
						var stray: Vector2i = cur + Vector2i(crng.randi_range(-2, 2), crng.randi_range(-2, 2))
						if _is_plain_desert_ground(stray):
							ground_layer.set_cell(stray, _coarse_sand_src, Vector2i(0, 0))
					var dirs: Array = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
					for k in range(dirs.size() - 1, 0, -1):
						var j: int = crng.randi_range(0, k)
						var tmp = dirs[k]
						dirs[k] = dirs[j]
						dirs[j] = tmp
					for d in dirs:
						var n: Vector2i = cur + d
						if seen.has(n):
							continue
						seen[n] = true
						frontier.append(n)

# A desert ground tile (plain sand OR already-painted coarse sand), dry.
func _is_desert_ground(c: Vector2i) -> bool:
	if ground_layer.get_cell_source_id(c) == -1:
		return false
	if water_layer.get_cell_source_id(c) != -1:
		return false
	return _cell_biome_type(c) == 1

# Desert ground that has NOT already been turned into coarse sand.
func _is_plain_desert_ground(c: Vector2i) -> bool:
	return ground_layer.get_cell_source_id(c) != _coarse_sand_src and _is_desert_ground(c)

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
	for dx in range(-TREE_OCCUPY_X_RADIUS, TREE_OCCUPY_X_RADIUS + 1):
		for dy in range(-TREE_OCCUPY_NORTH, TREE_OCCUPY_SOUTH + 1):
			var t: Vector2i = cell + Vector2i(dx, dy)
			_tree_occupied_tiles[t] = int(_tree_occupied_tiles.get(t, 0)) + 1

func _unmark_tree_occupied(cell: Vector2i) -> void:
	for dx in range(-TREE_OCCUPY_X_RADIUS, TREE_OCCUPY_X_RADIUS + 1):
		for dy in range(-TREE_OCCUPY_NORTH, TREE_OCCUPY_SOUTH + 1):
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

# Dense forests intentionally have overlapping crowns. Scattered trees and
# their 0-3 companions should not: a southern companion's canopy otherwise
# erases the northern tree's trunk. Reject a scatter candidate if its own crown
# would touch anything already occupied by a standing tree.
func _scatter_canopy_blocked(tile: Vector2i) -> bool:
	for dx in range(-TREE_OCCUPY_X_RADIUS, TREE_OCCUPY_X_RADIUS + 1):
		for dy in range(-TREE_OCCUPY_NORTH, 1):
			if _tree_occupied_tiles.has(tile + Vector2i(dx, dy)):
				return true
	return false

# True when a foliage tree must NOT spawn on this tile: it already holds a
# placed block (incl. the world-gen stone/charcoal patches), an editable or
# structure tile, grass, an entrance, or another tree. Every foliage pass uses
# this — previously they only checked a LOCAL tile set + chunk claims, so a
# regenerated world could drop a tree onto a saved player block.
func _foliage_tile_blocked(tile: Vector2i) -> bool:
	if _placed_blocks.has(tile):
		return true
	# Saved player blocks are applied after foliage, so their pending cells
	# must veto trees explicitly or a regenerated world can grow one through a
	# player's build.
	if _decor_pending_player_cells.has(tile):
		return true
	if _is_tree_occupied(tile):
		return true
	if _grass_occupied_tiles.has(tile):
		return true
	if editable_layer.get_cell_source_id(tile) != -1:
		return true
	if structures_layer.get_cell_source_id(tile) != -1:
		return true
	if _cave_entrance_cells.has(tile) or _dungeon_entrance_cells.has(tile):
		return true
	return false

# ── Grass ─────────────────────────────────────────────────────────────
# Per-tuft look/sizing/material now lives in scripts/grass.gd (GrassTuft) —
# world.gd only decides which tiles get grass and instantiates GRASS_SCENE.
# Grass grows in the PLAINS and SNOWY biomes (snowy tufts are the same art
# snow-tinted by the shader — see grass_sway.gdshader), never desert/water.
func _is_valid_grass_tile(tile: Vector2i) -> bool:
	if _grass_occupied_tiles.has(tile):
		return false
	if _dungeon_grass_clearance.has(tile):
		return false
	var biome: int = _cell_biome_type(tile)
	if biome != 0 and biome != 2:  # Plains or Snowy only
		return false
	if _is_tree_occupied(tile):
		return false
	if _placed_blocks.has(tile):
		return false
	if _world_waypoint_cells.has(tile) or _dungeon_waypoint_cells.has(tile):
		return false
	if editable_layer.get_cell_source_id(tile) != -1:
		return false
	if structures_layer.get_cell_source_id(tile) != -1:
		return false
	if _cave_entrance_cells.has(tile) or _dungeon_entrance_cells.has(tile):
		return false
	if _has_water_at(tile):
		return false
	# No grass within 2 tiles of water. A tuft's sprite is ~2.7 tiles wide and
	# overhangs its tile, so one sitting right on a shoreline visually reads as
	# growing IN the water — keep a 2-tile dry margin.
	if _has_water_within_2(tile):
		return false
	return true

# Rebuild the grass-free ring around every live dungeon door. Called whenever an
# entrance is added/removed, and again after returning from a dungeon.
func _refresh_dungeon_grass_clearance() -> void:
	_dungeon_grass_clearance.clear()
	for idx in _dungeon_entrance_tiles:
		var tile: Vector2i = _dungeon_entrance_tiles[idx] as Vector2i
		for dx in range(-2, 3):
			for dy in range(-2, 3):
				_dungeon_grass_clearance[tile + Vector2i(dx, dy)] = true
	_clear_grass_in_cells(_dungeon_grass_clearance.keys())

func _clear_grass_in_cells(cells: Array) -> void:
	for cell_value in cells:
		var cell := cell_value as Vector2i
		var raw: Variant = _grass_occupied_tiles.get(cell)
		if raw != null and is_instance_valid(raw):
			if raw is Node:
				(raw as Node).queue_free()
		_grass_occupied_tiles.erase(cell)

## Clear grass around an actual world position (dungeon/cave return spawn).
func clear_grass_around(world_pos: Vector2, radius_tiles: int = 2) -> void:
	if ground_layer == null:
		return
	var center: Vector2i = ground_layer.local_to_map(ground_layer.to_local(world_pos))
	var cells: Array = []
	for dx in range(-radius_tiles, radius_tiles + 1):
		for dy in range(-radius_tiles, radius_tiles + 1):
			cells.append(center + Vector2i(dx, dy))
	_clear_grass_in_cells(cells)

func _spawn_grass_at(tile: Vector2i) -> void:
	# Dungeon entrance clearance: never regrow grass over the return spawn.
	if _dungeon_grass_clearance.has(tile):
		return
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

	# Plains/Snowy only — _is_valid_grass_tile rejects Desert/Water outright
	# (snowy tufts get their snow tint from the shared shader, not new art).
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

# Stable per-(seed, tile) roll in 0..1 for the birch promotion. Mixes the tile
# coords with the world seed and large primes, so birch placement is
# deterministic for a given seed and NEVER draws from the shared gen rng.
func _birch_roll(cell: Vector2i) -> float:
	var h: int = cell.x * 73856093 ^ cell.y * 19349663 ^ random_seed
	h = (h ^ (h >> 13)) * 1274126177
	h = h ^ (h >> 16)
	return float(absi(h) % 100000) / 100000.0

# Spread across many frames (chunks_per_frame chunks at a time, then yield)
# instead of one long synchronous burst. The INITIAL fill is awaited by
# _deferred_foliage() so the loading screen stays up until every tuft exists
# (the player never sees grass popping in after the transition); the yields
# keep the loading screen rendering and the progress label ticking. Contains
# an await, so GDScript treats it as a coroutine automatically.
func _fill_all_chunks_with_grass(chunks_per_frame: int = GRASS_CHUNKS_PER_FRAME) -> void:
	var t0: int = Time.get_ticks_msec()
	var total: int = _chunk_cols * _chunk_rows
	var processed: int = 0
	for cx in range(_chunk_cols):
		for cy in range(_chunk_rows):
			_fill_chunk_grass(Vector2i(cx, cy))
			processed += 1
			if processed % max(1, chunks_per_frame) == 0:
				generation_status_changed.emit("Growing grass... %d%%" % int(100.0 * processed / max(1, total)))
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
	print("[GRASS] spawned %d tufts in %dms" % [_grass_spawn_count, Time.get_ticks_msec() - t0])

# ── Grass regrowth — every 10 minutes, per chunk ────────────────────────
func _start_grass_regrow_timer() -> void:
	var t := Timer.new()
	t.wait_time = GRASS_REGROW_INTERVAL
	t.autostart = true
	t.timeout.connect(_regrow_grass)
	add_child(t)

# ── Cactus — a random desert tile grows one every minute ────────────────
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
	_refresh_neighbor_u_collision(cell)

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
		if cell.distance_to(Vector2i.ZERO) < CACTUS_SPAWN_SAFE_RADIUS:
			continue
		if Global.has_spawn_point:
			var spawn_cell: Vector2i = editable_layer.local_to_map(
				editable_layer.to_local(Global.spawn_point))
			if cell.distance_to(spawn_cell) < CACTUS_SPAWN_SAFE_RADIUS:
				continue
		if _cell_near_any(cell, _cave_entrance_cells, CACTUS_SPAWN_ENTRANCE_CLEAR) \
				or _cell_near_any(cell, _dungeon_entrance_cells, CACTUS_SPAWN_ENTRANCE_CLEAR):
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

# True when `cell` is within `radius` tiles of any cell key in `cells`.
# Used to keep cactus regrowth off entrance footprints and their approach.
func _cell_near_any(cell: Vector2i, cells: Dictionary, radius: int) -> bool:
	for c in cells:
		if cell.distance_to(c as Vector2i) < radius:
			return true
	return false

func _tile_to_chunk(tile: Vector2i) -> Vector2i:
	var half_w: int = width  / 2
	var half_h: int = height / 2
	return Vector2i(floori(float(tile.x + half_w) / CHUNK_SIZE), floori(float(tile.y + half_h) / CHUNK_SIZE))

# A chunk containing any placed block OR a Lua robot (both live in
# _placed_blocks — a robot is just a placeable item like any other block)
# is skipped entirely: a "developed" chunk shouldn't spontaneously regrow.
# Everything else gets topped back up toward its target coverage — a no-op
# if it's already there, since _fill_chunk_grass only fills what's missing.
#
# Spread across frames (same GRASS_CHUNKS_PER_FRAME batching as the initial
# fill): running all ~1024 chunks in the timer callback froze the game for a
# few hundred ms every 10 minutes. Yielding keeps it hitch-free.
func _regrow_grass() -> void:
	var occupied_chunks: Dictionary = {}
	for cell in _placed_blocks:
		# Natural stone/charcoal patches are terrain, not player development —
		# a "developed" chunk is one the player actually built in.
		if _is_natural_block(cell as Vector2i):
			continue
		occupied_chunks[_tile_to_chunk(cell as Vector2i)] = true

	var processed: int = 0
	for cx in range(_chunk_cols):
		for cy in range(_chunk_rows):
			var chunk := Vector2i(cx, cy)
			if occupied_chunks.has(chunk):
				continue
			_fill_chunk_grass(chunk)
			processed += 1
			if processed % GRASS_CHUNKS_PER_FRAME == 0:
				await get_tree().process_frame
				if not is_inside_tree():
					return

# ── Stone / charcoal patches (world-gen) ────────────────────────────
# One chance per chunk to grow a small cluster of mineable Stone blocks on
# PLAINS tiles only; 70% of patches also embed a few charcoal blocks. See the
# STONE_PATCH_* consts for the tuning. Deterministic: driven by the shared gen
# rng, so the same world seed always yields the same patches.
func _place_stone_patches() -> void:
	var half_w: int = width  / 2
	var half_h: int = height / 2
	var placed_count: int = 0
	for cx in range(_chunk_cols):
		for cy in range(_chunk_rows):
			var chunk := Vector2i(cx, cy)
			# Caves/structures own their chunks outright.
			if _cave_claimed_chunks.has(chunk) or _structure_claimed_chunks.has(chunk):
				continue
			if _is_chunk_all_ocean(chunk):
				continue
			if rng.randf() >= STONE_PATCH_CHANCE:
				continue
			var tl := Vector2i(chunk.x * CHUNK_SIZE - half_w, chunk.y * CHUNK_SIZE - half_h)
			# Collect every free PLAINS tile in the chunk, then pick a random
			# centre and grow the cluster within STONE_PATCH_RADIUS of it.
			var free: Array[Vector2i] = []
			for dx in range(CHUNK_SIZE):
				for dy in range(CHUNK_SIZE):
					var tile: Vector2i = tl + Vector2i(dx, dy)
					if _can_host_natural_block(tile):
						free.append(tile)
			if free.size() < STONE_PATCH_MIN:
				continue
			var center: Vector2i = free[rng.randi_range(0, free.size() - 1)]
			var candidates: Array[Vector2i] = []
			for tile in free:
				if tile.distance_to(center) <= float(STONE_PATCH_RADIUS):
					candidates.append(tile)
			# Guarantee at least STONE_PATCH_MIN blocks even in a tight cluster.
			if candidates.size() < STONE_PATCH_MIN:
				candidates = free.duplicate()
			_shuffle_tiles(candidates, rng)
			var stone_n: int = mini(rng.randi_range(STONE_PATCH_MIN, STONE_PATCH_MAX), candidates.size())
			var used: Dictionary = {}
			for i in range(stone_n):
				var tile: Vector2i = candidates[i]
				_spawn_natural_block(tile, STONE_DATA)
				used[tile] = true
				placed_count += 1
			if rng.randf() < CHARCOAL_PATCH_CHANCE:
				# Charcoal embeds in the SAME patch, on the remaining nearby
				# tiles (never overwriting a stone block).
				var char_free: Array[Vector2i] = []
				for tile in candidates:
					if not used.has(tile) and _can_host_natural_block(tile):
						char_free.append(tile)
				_shuffle_tiles(char_free, rng)
				var char_n: int = mini(rng.randi_range(CHARCOAL_PATCH_MIN, CHARCOAL_PATCH_MAX), char_free.size())
				for i in range(char_n):
					_spawn_natural_block(char_free[i], CHARCOAL_DATA)
					placed_count += 1
	print("[STONE] placed %d natural stone/charcoal blocks" % placed_count)

# A tile a world-gen natural block may occupy: plains, dry, no tree/structure/
# cave/entrance, nothing already placed. (Grass doesn't exist yet at this
# point in generation, so it can't conflict.)
func _can_host_natural_block(tile: Vector2i) -> bool:
	if _cell_biome_type(tile) != 0:      # 0 == Plains only
		return false
	if water_layer.get_cell_source_id(tile) != -1:
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
	return true

# ── Coarse sand patches (world-gen, mineable) ───────────────────────
# The same idea as _place_stone_patches but on DESERT tiles: a chance per chunk
# to grow a small cluster of mineable Coarse Sand blocks sitting on the desert.
# This is how the player obtains coarse sand for the sandstone recipe. Uses a
# chunk-seeded rng, so the shared generation stream (and therefore every other
# world-gen roll) is untouched.
func _place_coarse_sand_patches() -> void:
	var half_w: int = width  / 2
	var half_h: int = height / 2
	var placed_count: int = 0
	for cx in range(_chunk_cols):
		for cy in range(_chunk_rows):
			var chunk := Vector2i(cx, cy)
			if _cave_claimed_chunks.has(chunk) or _structure_claimed_chunks.has(chunk):
				continue
			if _is_chunk_all_ocean(chunk):
				continue
			var crng := RandomNumberGenerator.new()
			crng.seed = int(random_seed) ^ (_chunk_hash(chunk) * 17)
			if crng.randf() >= COARSE_SAND_BLOCK_CHANCE:
				continue
			var tl := Vector2i(chunk.x * CHUNK_SIZE - half_w, chunk.y * CHUNK_SIZE - half_h)
			var free: Array[Vector2i] = []
			for dx in range(CHUNK_SIZE):
				for dy in range(CHUNK_SIZE):
					var tile: Vector2i = tl + Vector2i(dx, dy)
					if _can_host_desert_block(tile):
						free.append(tile)
			if free.size() < COARSE_SAND_BLOCK_MIN:
				continue
			_shuffle_tiles(free, crng)
			var n: int = mini(crng.randi_range(COARSE_SAND_BLOCK_MIN, COARSE_SAND_BLOCK_MAX), free.size())
			for i in range(n):
				_spawn_natural_block(free[i], COARSE_SAND_DATA)
				placed_count += 1
	print("[SAND] placed %d natural coarse sand blocks" % placed_count)

# A tile a world-gen coarse-sand block may occupy: DESERT only, dry, no tree /
# structure / cave / entrance, nothing already placed.
func _can_host_desert_block(tile: Vector2i) -> bool:
	if _cell_biome_type(tile) != 1:
		return false
	if water_layer.get_cell_source_id(tile) != -1:
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
	return true

# Instantiates a PlaceableBlock for a world-gen natural block and registers it
# in _placed_blocks tagged "natural". Mirrors the save-restore path (no debris
# burst, no mission credit — those belong to PLAYER placement only).
func _spawn_natural_block(cell: Vector2i, idata: ItemData) -> void:
	if idata == null or idata.place_scene_path.is_empty():
		return
	if not ResourceLoader.exists(idata.place_scene_path):
		return
	var scene: PackedScene = load(idata.place_scene_path) as PackedScene
	if scene == null:
		return
	var obj: Node = scene.instantiate()
	if obj == null:
		return
	if obj.has_method("setup"):
		obj.call("setup", idata)
	_placed_blocks[cell] = {"node": obj, "name": idata.item_name, "natural": true}
	if obj.has_method("set_world_cell"):
		obj.call("set_world_cell", cell, self)
	add_child(obj)
	if not is_instance_valid(obj):
		_placed_blocks.erase(cell)
		return
	var world_pos: Vector2 = editable_layer.map_to_local(cell)
	obj.position = world_pos
	obj.z_index  = int(world_pos.y / TILE_SIZE)
	_fix_sprite_offset(obj)
	_refresh_neighbor_u_collision(cell)

# True for a world-gen natural block (stone/charcoal patch). Such blocks are
# NOT saved, NOT counted as "developed", and are replaceable by dungeon
# entrances.
func _is_natural_block(cell: Vector2i) -> bool:
	var e: Variant = _placed_blocks.get(cell)
	return e is Dictionary and bool((e as Dictionary).get("natural", false))

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
		if _foliage_tile_blocked(tile_coord):
			continue
		if _scatter_canopy_blocked(tile_coord):
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

func _water_grid_index(tile: Vector2i) -> int:
	var half_w: int = width / 2
	var half_h: int = height / 2
	var x: int = tile.x + half_w
	var y: int = tile.y + half_h
	if x < 0 or y < 0 or x >= width or y >= height:
		return -1
	return y * width + x

func _invalidate_water_grid() -> void:
	_water_grid_ready = false
	_water_grid.clear()
	_water_margin2_ready = false
	_water_margin2.clear()

func _note_water_cell_added(cell: Vector2i) -> void:
	# Player-poured water should not force a full water-grid rebuild (and a
	# short freeze) later. Update the cached cells in place instead.
	if _water_grid_ready:
		var idx: int = _water_grid_index(cell)
		if idx >= 0:
			_water_grid[idx] = 1
	if _water_margin2_ready:
		for dx in range(-2, 3):
			for dy in range(-2, 3):
				if dx * dx + dy * dy > 4:
					continue
				var idx2: int = _water_grid_index(cell + Vector2i(dx, dy))
				if idx2 >= 0:
					_water_margin2[idx2] = 1

func _ensure_water_grid() -> void:
	if _water_grid_ready:
		return
	_water_grid_ready = true
	_water_grid.resize(width * height)
	if water_layer == null:
		return
	for cell in water_layer.get_used_cells():
		var idx: int = _water_grid_index(cell)
		if idx >= 0:
			_water_grid[idx] = 1

func _has_water_at(tile: Vector2i) -> bool:
	_ensure_water_grid()
	var idx: int = _water_grid_index(tile)
	return idx >= 0 and _water_grid[idx] == 1

func _ensure_water_margin2() -> void:
	if _water_margin2_ready:
		return
	_water_margin2_ready = true
	_water_margin2.resize(width * height)
	if water_layer == null:
		return
	var half_w: int = width / 2
	var half_h: int = height / 2
	for cell in water_layer.get_used_cells():
		for dx in range(-2, 3):
			for dy in range(-2, 3):
				if dx * dx + dy * dy > 4:
					continue
				var x: int = cell.x + dx + half_w
				var y: int = cell.y + dy + half_h
				if x >= 0 and y >= 0 and x < width and y < height:
					_water_margin2[y * width + x] = 1

func _has_water_within_2(tile: Vector2i) -> bool:
	_ensure_water_margin2()
	var idx: int = _water_grid_index(tile)
	return idx >= 0 and _water_margin2[idx] == 1

func _has_water_nearby(tile: Vector2i, radius: int) -> bool:
	_ensure_water_grid()
	var r_sq: int = radius * radius
	var half_w: int = width / 2
	var half_h: int = height / 2
	for dx in range(-radius, radius + 1):
		for dy in range(-radius, radius + 1):
			if dx * dx + dy * dy > r_sq:
				continue
			var x: int = tile.x + dx + half_w
			var y: int = tile.y + dy + half_h
			if x < 0 or y < 0 or x >= width or y >= height:
				continue
			if _water_grid[y * width + x] == 1:
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
			if _foliage_tile_blocked(tile):
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
	var tree_col := tree.get_node_or_null("StaticBody2D/CollisionShape2D") as CollisionShape2D
	if tree_col != null:
		tree_col.disabled = true
	_tree_spawn_count += 1

	# Birch grows AMONG the plains trees rather than replacing them: a
	# deterministic per-tile roll promotes some plain trees to birch (see
	# BIRCH_CHANCE / _birch_roll — a hash, so the shared gen rng is untouched
	# and every other world-gen roll keeps producing exactly what it did before).
	if tree_type_val == 0 \
			and _birch_roll(editable_layer.local_to_map(editable_layer.to_local(world_pos))) < BIRCH_CHANCE:
		tree_type_val = 3

	# Biome picks the sprite: snowy (2) uses the snow tree, birch (3) the birch
	# tree, everything else the normal plains tree.
	var tree_tex: Texture2D = PLAIN_TREE_TEX
	match tree_type_val:
		2: tree_tex = SNOWY_TREE_TEX
		3: tree_tex = BIRCH_TREE_TEX
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
	# _placed_blocks), so track the canopy + trunk footprint here. This also
	# keeps grass and world-gen patches off the leaves.
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
		if _foliage_tile_blocked(tile):
			continue
		if _scatter_canopy_blocked(tile):
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

func reset_cave_portals() -> void:
	var tree := get_tree()
	if tree == null:
		return
	for node in tree.get_nodes_in_group("CavePortal"):
		if node is CavePortal and (node as CavePortal).mode == CavePortal.Mode.ENTER \
				and is_ancestor_of(node):
			node.call("reset_after_exit")

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
# World's origin (y=0), so it can never y-sort against the player. Each cell
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

			# The door cell is the GATE. Its bottom stays walkable so the player
			# can step into the doorway, but its TOP half is solid so they can't
			# pass THROUGH the gate (up into the rock above it) and trigger the
			# walk-through bug.
			if s.is_door_cell(x, y):
				var gate := StaticBody2D.new()
				gate.collision_layer = 1
				gate.collision_mask  = 1
				var gshape := CollisionShape2D.new()
				var grect := RectangleShape2D.new()
				grect.size = Vector2(GeneratedStructure.TILE_PX, GeneratedStructure.TILE_PX * 0.5)
				gshape.shape = grect
				gshape.position = Vector2(0.0, -GeneratedStructure.TILE_PX * 0.25)
				gate.add_child(gshape)
				root.add_child(gate)
				gate.global_position = ground_layer.to_global(ground_layer.map_to_local(cell))
				continue
			# Every other cell that has any visible pixels is made FULLY solid
			# (a whole-tile box, not the tight per-pixel bounding box the old
			# code used): the bbox collision left gaps inside and at the edges
			# of each cell, so the player could clip straight into the rock.
			# Fully transparent cells stay open so no invisible wall sits in
			# the sprite's empty corners.
			if not solid_rects.has(Vector2i(x, y)):
				continue
			var body := StaticBody2D.new()
			body.collision_layer = 1
			body.collision_mask  = 1
			var shape := CollisionShape2D.new()
			var rect := RectangleShape2D.new()
			rect.size = Vector2(GeneratedStructure.TILE_PX, GeneratedStructure.TILE_PX)
			shape.shape = rect
			body.add_child(shape)
			root.add_child(body)
			body.global_position = ground_layer.to_global(ground_layer.map_to_local(cell))

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
		_spawn_decorative_structures()
		_spawn_world_waypoints()
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
	_spawn_decorative_structures()
	_spawn_world_waypoints()

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
		if s.spawn_world == "overworld" and s.decor_kind == "sprite" \
				and not _is_entrance_structure_type(s.type) \
				and s.type != "dungeon entrances":
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
	# ResourceLoader.list_directory (not DirAccess) so this survives export —
	# see Global._load_resource_dir for why DirAccess misses .tres there.
	for file_name in ResourceLoader.list_directory(STRUCTURES_DIR):
		if file_name.ends_with(".tres"):
			var res: Resource = load(STRUCTURES_DIR + file_name)
			if res is GeneratedStructure:
				var s := res as GeneratedStructure
				if s.is_valid():
					out.append(s)
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

# --- Decorative block houses and pillars -----------------------------
# These are generated after the existing sprite structures, inside the same
# overworld structure pass, so cave/structure priority and chunk claims remain
# authoritative. A separate RNG intentionally keeps the old shared world-gen
# sequence untouched. Definitions and removed cells are persisted in the world
# save; the individual block nodes are derived from the definitions.
func _spawn_decorative_structures() -> void:
	generation_status_changed.emit("Placing houses and pillars...")
	var started_ms := Time.get_ticks_msec()
	_decor_templates = _load_decorative_templates()
	_decor_pending_player_cells = _pending_player_block_cells()
	_decor_pending_reserved_cells = _pending_structure_reserved_cells()
	_decor_removed.clear()
	var pending: Dictionary = Global.pending_world_data
	var initialized: bool = bool(pending.get("decor_initialized", false)) \
		and pending.get("decor_structures", null) is Array
	if initialized:
		_decor_removed = _pending_decor_removed(pending)
		var definitions: Array = pending.get("decor_structures", []) as Array
		for def_value in definitions:
			if def_value is Dictionary:
				_restore_decor_structure(def_value as Dictionary)
		print("[DECOR] restored %d houses/pillars in %dms" % [
			_decor_structures.size(), Time.get_ticks_msec() - started_ms])
		return
	if _decor_templates.is_empty():
		return
	_decor_rng = RandomNumberGenerator.new()
	_decor_rng.seed = int(random_seed) ^ 0x5EED1E55
	_generate_decorative_structures(started_ms)


func _load_decorative_templates() -> Array:
	var out: Array = []
	for res in _scan_structure_dir():
		var s := res as GeneratedStructure
		if s.spawn_world == "overworld" and s.type == "structures" \
				and s.decor_kind != "sprite" and s.is_valid():
			out.append(s)
	return out


func _generate_decorative_structures(started_ms: int) -> void:
	var half_w: int = width / 2
	var half_h: int = height / 2
	var spawned: int = 0
	for cx in range(_chunk_cols):
		for cy in range(_chunk_rows):
			var chunk := Vector2i(cx, cy)
			if _structure_claimed_chunks.has(chunk) or _cave_claimed_chunks.has(chunk):
				continue
			if not _is_chunk_valid_for_structure(chunk):
				continue
			if _decor_rng.randf() >= DECOR_STRUCTURE_CHANCE:
				continue
			var tl := Vector2i(chunk.x * CHUNK_SIZE - half_w, chunk.y * CHUNK_SIZE - half_h)
			for _attempt in range(DECOR_STRUCTURE_ATTEMPTS):
				var anchor: Vector2i = tl + Vector2i(
					_decor_rng.randi_range(0, CHUNK_SIZE - 1),
					_decor_rng.randi_range(0, CHUNK_SIZE - 1))
				var biome_code: int = _cell_biome_type(anchor)
				if biome_code < 0:
					continue
				var template: GeneratedStructure = _pick_decor_template(biome_code)
				if template == null:
					continue
				var layout_seed: int = _decor_rng.randi()
				var layout: Dictionary = template.build_layout(layout_seed)
				if layout.is_empty():
					continue
				var size: Vector2i = layout.get("size", Vector2i.ZERO) as Vector2i
				if size.x <= 0 or size.y <= 0:
					continue
				if not _decor_footprint_valid(anchor, size, biome_code, false):
					continue
				var path := str(template.resource_path)
				if path.is_empty():
					continue
				var index: int = _decor_structures.size()
				if not _spawn_decor_layout(layout.get("cells", {}) as Dictionary,
						anchor, index, false):
					continue
				_decor_structures.append({
					"template_path": path,
					"anchor_x": anchor.x,
					"anchor_y": anchor.y,
					"seed": layout_seed,
					"biome": _biome_key(biome_code),
					"layout_version": DECOR_LAYOUT_VERSION,
				})
				_claim_decor_chunks(anchor, size)
				_structure_anchor_tiles.append(anchor)
				_located_structures.append({"name": template.name, "tile": anchor})
				spawned += 1
				break
	print("[DECOR] generated %d houses/pillars in %dms" % [
		spawned, Time.get_ticks_msec() - started_ms])


func _restore_decor_structure(def: Dictionary) -> void:
	if int(def.get("layout_version", 0)) != DECOR_LAYOUT_VERSION:
		return
	var path := str(def.get("template_path", ""))
	if path.is_empty():
		return
	var template := load(path) as GeneratedStructure
	if template == null or not template.is_valid() or template.decor_kind == "sprite":
		return
	var anchor := Vector2i(int(def.get("anchor_x", 0)), int(def.get("anchor_y", 0)))
	var biome_code := _decor_biome_code(str(def.get("biome", "")))
	if biome_code < 0:
		return
	var layout: Dictionary = template.build_layout(int(def.get("seed", 0)))
	if layout.is_empty():
		return
	var size: Vector2i = layout.get("size", Vector2i.ZERO) as Vector2i
	if size.x <= 0 or size.y <= 0:
		return
	if not _decor_footprint_valid(anchor, size, biome_code, true):
		return
	var index: int = _decor_structures.size()
	if not _spawn_decor_layout(layout.get("cells", {}) as Dictionary,
			anchor, index, true):
		return
	_decor_structures.append(def.duplicate(true))
	_claim_decor_chunks(anchor, size)
	_structure_anchor_tiles.append(anchor)
	_located_structures.append({"name": template.name, "tile": anchor})


func _pending_player_block_cells() -> Dictionary:
	var out: Dictionary = {}
	var pending: Variant = Global.pending_world_data.get("placed_blocks", [])
	if pending is Array:
		for value in (pending as Array):
			if value is Dictionary:
				var bd: Dictionary = value as Dictionary
				if bd.has("cell_x") and bd.has("cell_y"):
					out[Vector2i(int(bd["cell_x"]), int(bd["cell_y"]))] = true
	return out


# Existing-world features restored later by apply_world_save_data() must veto
# new decorative footprints. In particular: cleared trees, preserved mobs, the
# saved dungeon entrance tile, and the saved player position. Small radii keep
# a new house from boxing a returning player/mob in or crowding the entrance.
func _pending_structure_reserved_cells() -> Dictionary:
	var out: Dictionary = {}
	_reserve_saved_world_positions(out, "removed_trees", 0)
	_reserve_saved_world_positions(out, "mobs", DECOR_PROTECT_MOB_RADIUS)
	_reserve_saved_tiles(out, "dungeon_entrances", DECOR_PROTECT_DUNGEON_RADIUS)
	if Global.has_pending_pos:
		_reserve_world_position(out, Global.pending_player_pos,
			DECOR_PROTECT_PLAYER_RADIUS)
	return out


func _reserve_saved_world_positions(out: Dictionary, key: String, radius: int) -> void:
	var rows: Variant = Global.pending_world_data.get(key, [])
	if not rows is Array:
		return
	for value in (rows as Array):
		if value is Dictionary:
			var row: Dictionary = value as Dictionary
			if row.has("x") and row.has("y"):
				_reserve_world_position(out,
					Vector2(float(row["x"]), float(row["y"])), radius)


func _reserve_saved_tiles(out: Dictionary, key: String, radius: int) -> void:
	var rows: Variant = Global.pending_world_data.get(key, [])
	if not rows is Array:
		return
	for value in (rows as Array):
		if value is Dictionary:
			var row: Dictionary = value as Dictionary
			if row.has("x") and row.has("y"):
				_reserve_tile(out, Vector2i(int(row["x"]), int(row["y"])), radius)


func _reserve_world_position(out: Dictionary, world_pos: Vector2, radius: int) -> void:
	var local_pos: Vector2 = editable_layer.to_local(world_pos)
	_reserve_tile(out, editable_layer.local_to_map(local_pos), radius)


func _reserve_tile(out: Dictionary, center: Vector2i, radius: int) -> void:
	for dx in range(-radius, radius + 1):
		for dy in range(-radius, radius + 1):
			out[center + Vector2i(dx, dy)] = true


func _pending_decor_removed(pending: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	var rows: Variant = pending.get("decor_removed", [])
	if rows is Array:
		for value in (rows as Array):
			if value is Dictionary:
				var row: Dictionary = value as Dictionary
				if row.has("x") and row.has("y"):
					out[Vector2i(int(row["x"]), int(row["y"]))] = true
			elif value is Array and (value as Array).size() >= 2:
				out[Vector2i(int((value as Array)[0]), int((value as Array)[1]))] = true
	return out


func _pick_decor_template(biome_code: int) -> GeneratedStructure:
	var key := _biome_key(biome_code)
	var matching: Array = []
	var total: float = 0.0
	for template_value in _decor_templates:
		var template := template_value as GeneratedStructure
		if template == null:
			continue
		if template.biome != "any" and template.biome != key:
			continue
		var weight := maxf(0.05, template.decor_weight)
		matching.append(template)
		total += weight
	if matching.is_empty():
		return null
	var roll := _decor_rng.randf() * total
	for template_value in matching:
		var template := template_value as GeneratedStructure
		roll -= maxf(0.05, template.decor_weight)
		if roll <= 0.0:
			return template
	return matching[matching.size() - 1] as GeneratedStructure


func _biome_key(code: int) -> String:
	match code:
		0: return "plain"
		1: return "desert"
		2: return "snowy"
	return ""


func _decor_biome_code(key: String) -> int:
	match key:
		"plain": return 0
		"desert": return 1
		"snowy": return 2
	return -1


func _decor_footprint_valid(anchor: Vector2i, size: Vector2i, biome_code: int,
		allow_player_cells: bool) -> bool:
	if size.x <= 0 or size.y <= 0:
		return false
	if Vector2(anchor).distance_to(Vector2.ZERO) < DECOR_STRUCTURE_MIN_SPAWN_DIST:
		return false
	for placed in _structure_anchor_tiles:
		if anchor.distance_to(placed as Vector2i) < DECOR_STRUCTURE_MIN_SEPARATION:
			return false
	var half_w: int = width / 2
	var half_h: int = height / 2
	# The candidate chunk was already ocean-gated by the generation loop. Here
	# the full footprint + one-tile ring provide the local water/shore check.
	for x in range(size.x):
		for y in range(size.y):
			var cell: Vector2i = anchor + Vector2i(x, y)
			if absi(cell.x) >= half_w or absi(cell.y) >= half_h:
				return false
			if _cell_biome_type(cell) != biome_code:
				return false
			# Player-poured water is not reflected in the cached biome grid.
			if not allow_player_cells and cell_is_water(cell):
				return false
			if _is_chunk_cave_claimed(cell) or _is_chunk_structure_claimed(cell):
				return false
			if _is_tree_occupied(cell) or _grass_occupied_tiles.has(cell):
				return false
			if _cave_entrance_cells.has(cell) or _dungeon_entrance_cells.has(cell):
				return false
			if _world_waypoint_cells.has(cell) or _dungeon_waypoint_cells.has(cell):
				return false
			if structures_layer.get_cell_source_id(cell) != -1:
				return false
			if not allow_player_cells and _decor_pending_reserved_cells.has(cell):
				return false
			if _decor_pending_player_cells.has(cell):
				if not allow_player_cells:
					return false
				continue
			if _placed_blocks.has(cell):
				return false
	# Keep a one-tile water/void margin around the full footprint.
	for x in range(-1, size.x + 1):
		for y in range(-1, size.y + 1):
			if x >= 0 and y >= 0 and x < size.x and y < size.y:
				continue
			var fringe: Vector2i = anchor + Vector2i(x, y)
			if absi(fringe.x) >= half_w or absi(fringe.y) >= half_h:
				return false
			if _cell_biome_type(fringe) == -1:
				return false
			if not allow_player_cells and cell_is_water(fringe):
				return false
	return true


func _spawn_decor_layout(cells: Dictionary, anchor: Vector2i, index: int,
		restore: bool) -> bool:
	var plan: Array = []
	for cell_value in cells.keys():
		if not (cell_value is Vector2i):
			continue
		var target: Vector2i = anchor + (cell_value as Vector2i)
		if restore and (_decor_removed.has(target) \
				or _decor_pending_player_cells.has(target) \
				or cell_is_water(target)):
			continue
		var idata := _decor_item_data(str(cells[cell_value]))
		if idata == null:
			return false
		plan.append({"cell": target, "item": idata})
	var spawned: Array = []
	for entry in plan:
		var target: Vector2i = (entry as Dictionary)["cell"] as Vector2i
		var idata: ItemData = (entry as Dictionary)["item"] as ItemData
		if not _spawn_decor_block(target, idata, index):
			for spawned_cell in spawned:
				var old_entry: Variant = _placed_blocks.get(spawned_cell)
				if old_entry is Dictionary:
					var old_node: Variant = (old_entry as Dictionary).get("node")
					if is_instance_valid(old_node):
						(old_node as Node).queue_free()
				_placed_blocks.erase(spawned_cell)
			return false
		spawned.append(target)
	return true


func _decor_item_data(path: String) -> ItemData:
	if path.is_empty():
		return null
	if _decor_item_cache.has(path):
		return _decor_item_cache[path] as ItemData
	if not ResourceLoader.exists(path):
		_decor_item_cache[path] = null
		return null
	var data := load(path) as ItemData
	if data == null or not data.is_placeable or data.place_scene_path.is_empty():
		_decor_item_cache[path] = null
		return null
	_decor_item_cache[path] = data
	return data


func _spawn_decor_block(cell: Vector2i, idata: ItemData, index: int) -> bool:
	if idata == null or not ResourceLoader.exists(idata.place_scene_path):
		return false
	var scene := load(idata.place_scene_path) as PackedScene
	if scene == null:
		return false
	var obj := scene.instantiate()
	if obj == null:
		return false
	if obj.has_method("setup"):
		obj.call("setup", idata)
	_placed_blocks[cell] = {
		"node": obj,
		"name": idata.item_name,
		"decor_generated": true,
		"decor_index": index,
	}
	if obj.has_method("set_world_cell"):
		obj.call("set_world_cell", cell, self)
	add_child(obj)
	if not is_instance_valid(obj):
		_placed_blocks.erase(cell)
		return false
	obj.position = editable_layer.map_to_local(cell)
	obj.z_index = FLOOR_Z if idata.is_floor else int(obj.position.y / TILE_SIZE)
	_fix_sprite_offset(obj)
	_refresh_neighbor_u_collision(cell)
	return true


func _claim_decor_chunks(anchor: Vector2i, size: Vector2i) -> void:
	_claim_structure_rect(anchor, size)


func _claim_structure_rect(anchor: Vector2i, size: Vector2i) -> void:
	var tl_chunk: Vector2i = _tile_to_chunk(anchor)
	var br_chunk: Vector2i = _tile_to_chunk(anchor + size - Vector2i.ONE)
	for cx in range(tl_chunk.x, br_chunk.x + 1):
		for cy in range(tl_chunk.y, br_chunk.y + 1):
			_structure_claimed_chunks[Vector2i(cx, cy)] = true


func _decor_save_removed() -> Array:
	var removed: Dictionary = {}
	for index in range(_decor_structures.size()):
		var def: Dictionary = _decor_structures[index] as Dictionary
		var path := str(def.get("template_path", ""))
		if path.is_empty() or not ResourceLoader.exists(path):
			continue
		var template := load(path) as GeneratedStructure
		if template == null or not template.is_valid():
			continue
		var layout: Dictionary = template.build_layout(int(def.get("seed", 0)))
		if layout.is_empty():
			continue
		var cells: Dictionary = layout.get("cells", {}) as Dictionary
		var anchor := Vector2i(int(def.get("anchor_x", 0)), int(def.get("anchor_y", 0)))
		for cell_value in cells.keys():
			if not (cell_value is Vector2i):
				continue
			var target: Vector2i = anchor + (cell_value as Vector2i)
			var entry: Variant = _placed_blocks.get(target)
			var present: bool = entry is Dictionary \
				and bool((entry as Dictionary).get("decor_generated", false)) \
				and int((entry as Dictionary).get("decor_index", -1)) == index
			if not present:
				removed[target] = true
	var out: Array = []
	for cell_value in removed.keys():
		var cell := cell_value as Vector2i
		out.append({"x": cell.x, "y": cell.y})
	return out


# --- Persistent world waypoint towers ---------------------------------
# The tower is a dedicated animated node (not a block), but it participates in
# the same worldgen priority/validation as other landmarks: chunks are claimed,
# the full 5x7 footprint + one-tile ring must be clear, and the positions are
# persisted as compact definitions so reloads cannot duplicate or move them.
func _spawn_world_waypoints() -> void:
	# The title-screen preview is a SubViewport snapshot, not a playable world;
	# keep its established look and skip gameplay waypoint towers.
	if get_viewport() is SubViewport:
		return
	var started_ms := Time.get_ticks_msec()
	var pending: Dictionary = Global.pending_world_data
	var initialized: bool = bool(pending.get("world_waypoints_initialized", false)) \
		and pending.get("world_waypoints", null) is Array
	if initialized:
		for def_value in (pending.get("world_waypoints", []) as Array):
			if def_value is Dictionary:
				_restore_world_waypoint(def_value as Dictionary)
		print("[WAYPOINTS] restored %d world towers in %dms" % [
			_world_waypoints.size(), Time.get_ticks_msec() - started_ms])
		return
	_generate_world_waypoints(started_ms)


func _generate_world_waypoints(started_ms: int) -> void:
	_world_waypoint_rng = RandomNumberGenerator.new()
	_world_waypoint_rng.seed = int(random_seed) ^ 0x57A7C0DE
	var half_w: int = width / 2
	var half_h: int = height / 2
	var eligible: Array[Vector2i] = []
	for cx in range(_chunk_cols):
		for cy in range(_chunk_rows):
			var chunk := Vector2i(cx, cy)
			if _structure_claimed_chunks.has(chunk) or _cave_claimed_chunks.has(chunk):
				continue
			if not _is_chunk_valid_for_structure(chunk):
				continue
			eligible.append(chunk)
	# Shuffle every eligible chunk, then place toward a target density. Using a
	# target count (instead of an independent chance roll) keeps the network
	# reliably discoverable on every seed while still spreading it over the map.
	for i in range(eligible.size() - 1, 0, -1):
		var j: int = _world_waypoint_rng.randi_range(0, i)
		var tmp: Vector2i = eligible[i]
		eligible[i] = eligible[j]
		eligible[j] = tmp
	var target: int = clampi(roundi(float(eligible.size()) * WORLD_WAYPOINT_DENSITY), 12, 28)
	var spawned := 0
	for chunk in eligible:
		if spawned >= target:
			break
		if _structure_claimed_chunks.has(chunk) or _cave_claimed_chunks.has(chunk):
			continue
		var tl := Vector2i(chunk.x * CHUNK_SIZE - half_w,
			chunk.y * CHUNK_SIZE - half_h)
		for _attempt in range(WORLD_WAYPOINT_ATTEMPTS):
			var anchor: Vector2i = tl + Vector2i(
				_world_waypoint_rng.randi_range(0, CHUNK_SIZE - 1),
				_world_waypoint_rng.randi_range(0, CHUNK_SIZE - 1))
			var biome_code := _cell_biome_type(anchor)
			if biome_code < 0:
				continue
			if not _world_waypoint_spacing_ok(anchor):
				continue
			if not _decor_footprint_valid(anchor, WORLD_WAYPOINT_SIZE, biome_code, false):
				continue
			var label := "Skyglass Waypoint %02d" % (_world_waypoints.size() + 1)
			var id := "ww_%d_%d" % [anchor.x, anchor.y]
			var def := {
				"id": id,
				"label": label,
				"x": anchor.x,
				"y": anchor.y,
			}
			if not _spawn_world_waypoint_node(def):
				continue
			_claim_structure_rect(anchor, WORLD_WAYPOINT_SIZE)
			_structure_anchor_tiles.append(anchor)
			_located_structures.append({"name": label,
				"tile": anchor + Vector2i(WORLD_WAYPOINT_SIZE.x / 2,
					WORLD_WAYPOINT_SIZE.y - 1)})
			spawned += 1
			break
	print("[WAYPOINTS] generated %d/%d world towers from %d eligible chunks in %dms" % [
		spawned, target, eligible.size(), Time.get_ticks_msec() - started_ms])


func _restore_world_waypoint(def: Dictionary) -> void:
	var id := str(def.get("id", "")).strip_edges()
	if id.is_empty() or _world_waypoint_nodes.has(id):
		return
	var anchor := Vector2i(int(def.get("x", 0)), int(def.get("y", 0)))
	var label := str(def.get("label", "Skyglass Waypoint"))
	if not _world_waypoint_anchor_clear(anchor):
		return
	var clean_def := {"id": id, "label": label,
		"x": anchor.x, "y": anchor.y}
	if not _spawn_world_waypoint_node(clean_def):
		return
	_claim_structure_rect(anchor, WORLD_WAYPOINT_SIZE)
	_structure_anchor_tiles.append(anchor)
	_located_structures.append({"name": label,
		"tile": anchor + Vector2i(WORLD_WAYPOINT_SIZE.x / 2,
			WORLD_WAYPOINT_SIZE.y - 1)})


func _spawn_world_waypoint_node(def: Dictionary) -> bool:
	var id := str(def.get("id", ""))
	if id.is_empty():
		return false
	var anchor := Vector2i(int(def.get("x", 0)), int(def.get("y", 0)))
	var tower := WORLD_WAYPOINT_TOWER_SCRIPT.new() as Node2D
	if tower == null:
		return false
	tower.call("setup", id, str(def.get("label", "Skyglass Waypoint")), anchor)
	add_child(tower)
	var foot := anchor + Vector2i(WORLD_WAYPOINT_SIZE.x / 2,
		WORLD_WAYPOINT_SIZE.y - 1)
	tower.global_position = ground_layer.to_global(
		ground_layer.map_to_local(foot)) + Vector2(0.0, TILE_SIZE * 0.5)
	tower.z_index = int(tower.global_position.y / TILE_SIZE)
	_world_waypoint_nodes[id] = tower
	_world_waypoint_anchors.append(anchor)
	for x in range(WORLD_WAYPOINT_SIZE.x):
		for y in range(WORLD_WAYPOINT_SIZE.y):
			_world_waypoint_cells[anchor + Vector2i(x, y)] = id
	_world_waypoints.append(def.duplicate(true))
	return true


func _world_waypoint_spacing_ok(anchor: Vector2i) -> bool:
	for other in _world_waypoint_anchors:
		if anchor.distance_to(other as Vector2i) < WORLD_WAYPOINT_MIN_SEPARATION:
			return false
	return true


func _world_waypoint_anchor_clear(anchor: Vector2i) -> bool:
	var half_w: int = width / 2
	var half_h: int = height / 2
	for x in range(WORLD_WAYPOINT_SIZE.x):
		for y in range(WORLD_WAYPOINT_SIZE.y):
			var cell: Vector2i = anchor + Vector2i(x, y)
			if absi(cell.x) >= half_w or absi(cell.y) >= half_h:
				return false
			if _cell_biome_type(cell) == -1:
				return false
			if water_layer.get_cell_source_id(cell) != -1:
				return false
			if _is_chunk_cave_claimed(cell) or _is_chunk_structure_claimed(cell):
				return false
			if _cave_entrance_cells.has(cell) or _dungeon_entrance_cells.has(cell):
				return false
			if structures_layer.get_cell_source_id(cell) != -1:
				return false
			if _placed_blocks.has(cell) or _decor_pending_player_cells.has(cell):
				return false
			if _world_waypoint_cells.has(cell) or _dungeon_waypoint_cells.has(cell):
				return false
	for x in range(-1, WORLD_WAYPOINT_SIZE.x + 1):
		for y in range(-1, WORLD_WAYPOINT_SIZE.y + 1):
			if x >= 0 and y >= 0 and x < WORLD_WAYPOINT_SIZE.x \
					and y < WORLD_WAYPOINT_SIZE.y:
				continue
			var fringe: Vector2i = anchor + Vector2i(x, y)
			if absi(fringe.x) >= half_w or absi(fringe.y) >= half_h:
				return false
			if _cell_biome_type(fringe) == -1:
				return false
			if water_layer.get_cell_source_id(fringe) != -1:
				return false
	return true


func _world_waypoint_save_data() -> Array:
	return _world_waypoints.duplicate(true)


func build_waypoint_map_image(pixel_size: int = 256) -> ImageTexture:
	var img := Image.create_empty(pixel_size, pixel_size, false, Image.FORMAT_RGBA8)
	var half_w: int = width / 2
	var half_h: int = height / 2
	for py in range(pixel_size):
		for px in range(pixel_size):
			var tx: int = int((float(px) + 0.5) / float(pixel_size) * width) - half_w
			var ty: int = int((float(py) + 0.5) / float(pixel_size) * height) - half_h
			var code := _cell_biome_type(Vector2i(tx, ty))
			var col: Color
			match code:
				0: col = Color(0.35, 0.56, 0.16, 1.0)
				1: col = Color(0.76, 0.59, 0.31, 1.0)
				2: col = Color(0.76, 0.82, 0.84, 1.0)
				_: col = Color(0.10, 0.24, 0.36, 1.0)
			if code != -1 and ((tx * 17 + ty * 31 + int(random_seed)) % 29 == 0):
				col = col.lightened(0.06)
			img.set_pixel(px, py, col)
	return ImageTexture.create_from_image(img)


func waypoint_world_rect() -> Rect2:
	var half := Vector2i(width, height) / 2
	return Rect2(Vector2(-half.x, -half.y) * TILE_SIZE,
		Vector2(width, height) * TILE_SIZE)


# Names of every structure resource in STRUCTURES_DIR (internal lookup source)
# — ALL types, including cave/pixie/dungeon entrances.
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
# exists (or none of that name was placed). Internal debug helper.
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
func _structure_footprint_valid(s: GeneratedStructure, anchor: Vector2i, skip_cell: Vector2i, allow_natural: bool = false) -> bool:
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
			if _is_tree_occupied(cell):
				return false
			# A natural stone/charcoal block may be replaced when the caller
			# opts in (dungeon entrances do — see _clear_natural_in_footprint);
			# a player-placed block always vetoes.
			if _placed_blocks.has(cell) and not (allow_natural and _is_natural_block(cell)):
				return false
			if _world_waypoint_cells.has(cell) or _dungeon_waypoint_cells.has(cell):
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
	_claim_structure_rect(anchor, Vector2i(s.tile_width, s.tile_height))

# ── Dungeon entrance structures ───────────────────────────────────────
# Frees any world-gen natural block (stone/charcoal) sitting in the large
# dungeon entrance footprint so the portal can replace the stone it landed on.
# Player-placed blocks still veto placement and are never cleared here.
func _clear_natural_in_footprint(anchor: Vector2i, size: Vector2i) -> void:
	for x in range(size.x):
		for y in range(size.y):
			var cell: Vector2i = anchor + Vector2i(x, y)
			if not _is_natural_block(cell):
				continue
			var entry: Dictionary = _placed_blocks.get(cell) as Dictionary
			var node: Node = entry.get("node") as Node
			unregister_block(cell)
			if is_instance_valid(node):
				node.queue_free()


# Builds the large animated entrance facade, its cell collision (except the
# bottom-centre door), and returns every occupied cell. The DungeonPortal node
# itself stays separate and keeps the existing walk-in/click confirmation role.
func _spawn_large_dungeon_entrance_nodes(anchor: Vector2i, size: Vector2i,
		dungeon_index: int) -> Array:
	var root := Node2D.new()
	root.name = "DungeonEntrance%d" % dungeon_index
	add_child(root)
	_dungeon_entrance_nodes[dungeon_index] = root
	var center := _dungeon_entrance_center(size)
	var base_cell := anchor + center
	var foot := ground_layer.to_global(ground_layer.map_to_local(base_cell)) \
		+ Vector2(0.0, TILE_SIZE * 0.5)
	root.global_position = foot
	root.z_index = int(foot.y / TILE_SIZE)

	var frame_size := Vector2i(size.x * TILE_SIZE, size.y * TILE_SIZE)
	var anim := AnimatedSprite2D.new()
	anim.sprite_frames = WaypointAnim.build(_dungeon_entrance_sheet(dungeon_index), frame_size)
	anim.animation = "idle"
	anim.centered = true
	anim.position = Vector2(0.0, -float(frame_size.y) * 0.5)
	anim.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	anim.play("idle")
	root.add_child(anim)

	var door := base_cell
	var painted: Array = []
	for x in range(size.x):
		for y in range(size.y):
			var cell: Vector2i = anchor + Vector2i(x, y)
			painted.append(cell)
			if cell == door:
				continue
			var body := StaticBody2D.new()
			body.collision_layer = 1
			body.collision_mask = 1
			var shape := CollisionShape2D.new()
			var rect := RectangleShape2D.new()
			rect.size = Vector2(TILE_SIZE, TILE_SIZE)
			shape.shape = rect
			body.add_child(shape)
			root.add_child(body)
			body.global_position = ground_layer.to_global(ground_layer.map_to_local(cell))
	return painted


func _place_dungeon_entrance_structure(portal_tile: Vector2i, dungeon_index: int) -> Vector2i:
	var size := _dungeon_entrance_size(dungeon_index)
	var center := _dungeon_entrance_center(size)
	var anchor := _find_dungeon_entrance_anchor(portal_tile, dungeon_index)
	if anchor == DUNGEON_INVALID_TILE:
		push_warning("DungeonSpawner: no free footprint for dungeon %d entrance structure ? portal still spawned" % dungeon_index)
		return DUNGEON_INVALID_TILE
	_clear_natural_in_footprint(anchor, size)
	var painted := _spawn_large_dungeon_entrance_nodes(anchor, size, dungeon_index)
	for cell in painted:
		_dungeon_entrance_cells[cell as Vector2i] = true
	_dungeon_entrance_structure_cells[dungeon_index] = painted
	_clear_grass_in_cells(painted)
	_claim_structure_rect(anchor, size)
	var lang := Global.dungeon_language(dungeon_index)
	var label := "%s Dungeon Entrance" % lang.capitalize() if not lang.is_empty() \
		else "Dungeon Entrance"
	_located_structures.append({"name": label, "tile": anchor + center})
	return anchor + center


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

# ── Dungeon entrance spawning (one per language, always present) ───────
# Called on every Global.mission_updated (mission cleared, dungeon cleared,
# reset, load). Ensures the current mission of each language track has a live
# entrance; _spawn_dungeon_entrance is idempotent, so repeated calls never
# duplicate one.
func _on_mission_updated() -> void:
	_ensure_current_dungeon_entrances()

# Public kick used by DungeonWorld immediately after a clear. Same idempotent
# path as the mission_updated handler; keeps the next-dungeon handoff explicit.
func ensure_current_dungeon_entrances() -> void:
	_ensure_current_dungeon_entrances()


# Keeps exactly one live entrance per language: spawns one for the current
# mission of each track, and frees any entrance that is no longer current
# (e.g. after a mission reset). Idempotent, so it is safe to call on every
# mission update.
func _ensure_current_dungeon_entrances() -> void:
	if not _dungeon_entrances_ready:
		return
	# The title-screen panorama reuses this generator inside a SubViewport. It
	# has no player and must never spawn live dungeon entrances / temporary
	# waypoints (the old 200-tile minimum also kept them out of the preview).
	if get_viewport() is SubViewport:
		return
	var wanted: Array = Global.current_dungeon_indices()
	for idx in _dungeon_entrance_tiles.keys():
		if not wanted.has(int(idx)):
			remove_dungeon_entrance(int(idx))
	for idx in wanted:
		var di: int = int(idx)
		if Global.is_dungeon_cleared(di):
			continue
		if _dungeon_entrance_tiles.has(di):
			continue
		_spawn_dungeon_entrance(di)

func _spawn_dungeon_entrance(dungeon_index: int) -> void:
	if _dungeon_entrance_tiles.has(dungeon_index):
		return
	var reference_pos := _dungeon_spawn_reference_position()
	var player_tile: Vector2i = ground_layer.local_to_map(
		ground_layer.to_local(reference_pos))

	# Collect every eligible chunk, then prefer the chunks nearest the player.
	# The old flow picked a random distant chunk; this keeps both language
	# tracks close enough for the temporary one-way waypoint to be useful while
	# preserving the existing terrain/claim/developed-chunk protections.
	var developed_chunks: Dictionary = {}
	for cell in _placed_blocks:
		if _is_natural_block(cell as Vector2i):
			continue
		developed_chunks[_tile_to_chunk(cell as Vector2i)] = true

	var player_chunk: Vector2i = _tile_to_chunk(player_tile)
	var valid: Array[Vector2i] = []
	for cx in range(_chunk_cols):
		for cy in range(_chunk_rows):
			var chunk := Vector2i(cx, cy)
			if _is_valid_dungeon_chunk(chunk, player_tile, developed_chunks):
				valid.append(chunk)
	if valid.is_empty():
		push_warning("DungeonSpawner: no valid chunk found for dungeon %d" % dungeon_index)
		return

	var near: Array[Vector2i] = []
	for chunk in valid:
		if chunk.distance_to(player_chunk) <= DUNGEON_NEAR_CHUNK_RADIUS:
			near.append(chunk)
	near.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return a.distance_squared_to(player_chunk) < b.distance_squared_to(player_chunk))
	var ordered: Array[Vector2i] = []
	if not near.is_empty():
		ordered = near
	else:
		# No candidate inside the preferred radius (cramped/edge map): still
		# choose the nearest available chunk rather than a randomly distant one.
		ordered = valid.duplicate()
		ordered.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
			return a.distance_squared_to(player_chunk) < b.distance_squared_to(player_chunk))

	for chunk in ordered:
		var tile: Vector2i = _random_land_tile_in_chunk(chunk)
		if tile == DUNGEON_INVALID_TILE:
			continue
		# Verify the full native large-portal footprint (and its south door
		# approach) can sit here, not just the random portal tile.
		if _find_dungeon_entrance_anchor(tile, dungeon_index) == DUNGEON_INVALID_TILE:
			continue
		_dungeon_entrance_tiles[dungeon_index] = tile
		# The layout's seed is rolled HERE — the first time the entrance is
		# placed — then persisted in Global, so the dungeon is "generated"
		# once and re-entering always reproduces the same layout.
		Global.get_or_create_dungeon_seed(dungeon_index)
		_spawn_dungeon_portal_at(tile, dungeon_index)
		_create_dungeon_waypoint(dungeon_index)
		return

	push_warning("DungeonSpawner: no usable nearby land tile for dungeon %d" % dungeon_index)


# The player's effective overworld position, even while the overworld is
# off-tree inside a cave/dungeon. New dungeon entrances and temporary waypoints
# should appear near the surface position the player will return to.
func _dungeon_spawn_reference_position() -> Vector2:
	var p: Node2D = _get_player()
	var current: Node = Global.world_node
	if current != null and current != self:
		var return_pos: Variant = current.get("overworld_return_position")
		if return_pos is Vector2:
			return return_pos as Vector2
	if p != null:
		return p.global_position
	return _world_spawn_pos()

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
			# A natural stone/charcoal block is fair game — the entrance clears
			# it. A player-placed block still vetoes the tile.
			if _placed_blocks.has(tile) and not _is_natural_block(tile):
				continue
			if _is_tree_occupied(tile):
				continue
			candidates.append(tile)
	if candidates.is_empty():
		return DUNGEON_INVALID_TILE
	return candidates[rng.randi_range(0, candidates.size() - 1)]

# The persistent dungeon entrance is now the native large language portal.
# Python uses the 5x4 Stonegate; Lua uses the 6x5 Ancient Rune Gate. The bottom
# centre tile is the walk-in door, so the whole structure can be solid while
# still allowing the player to step onto the DungeonPortal trigger.
func _dungeon_entrance_size(dungeon_index: int) -> Vector2i:
	return DUNGEON_ENTRANCE_LUA_SIZE if Global.dungeon_language(dungeon_index) == "lua" \
		else DUNGEON_ENTRANCE_PYTHON_SIZE


func _dungeon_entrance_sheet(dungeon_index: int) -> Texture2D:
	return DUNGEON_ENTRANCE_LUA_TEX if Global.dungeon_language(dungeon_index) == "lua" \
		else DUNGEON_ENTRANCE_PYTHON_TEX


func _dungeon_entrance_center(size: Vector2i) -> Vector2i:
	return Vector2i(size.x / 2, size.y - 1)


func _find_dungeon_entrance_anchor(portal_tile: Vector2i, dungeon_index: int) -> Vector2i:
	var size := _dungeon_entrance_size(dungeon_index)
	var center := _dungeon_entrance_center(size)
	var offsets: Array[Vector2i] = []
	for dy in range(-2, 3):
		for dx in range(-2, 3):
			offsets.append(Vector2i(dx, dy))
	offsets.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return a.length_squared() < b.length_squared())
	for offset in offsets:
		var anchor: Vector2i = portal_tile - center + offset
		if _dungeon_entrance_footprint_valid(anchor, size):
			return anchor
	return DUNGEON_INVALID_TILE


func _dungeon_entrance_footprint_valid(anchor: Vector2i, size: Vector2i) -> bool:
	var half_w: int = width / 2
	var half_h: int = height / 2
	for x in range(size.x):
		for y in range(size.y):
			var cell: Vector2i = anchor + Vector2i(x, y)
			if absi(cell.x) >= half_w or absi(cell.y) >= half_h:
				return false
			if _cell_biome_type(cell) == -1:
				return false
			if water_layer.get_cell_source_id(cell) != -1:
				return false
			if _is_tree_occupied(cell):
				return false
			if _placed_blocks.has(cell) and not _is_natural_block(cell):
				return false
			if _world_waypoint_cells.has(cell) or _dungeon_waypoint_cells.has(cell):
				return false
			if structures_layer.get_cell_source_id(cell) != -1:
				return false
			if _cave_entrance_cells.has(cell) or _dungeon_entrance_cells.has(cell):
				return false
			if _decor_pending_player_cells.has(cell):
				return false
	# The player enters from the south into the free bottom-centre door.
	var door: Vector2i = anchor + _dungeon_entrance_center(size)
	var approach: Vector2i = door + Vector2i(0, 1)
	if absi(approach.x) >= half_w or absi(approach.y) >= half_h:
		return false
	if _cell_biome_type(approach) == -1:
		return false
	if water_layer.get_cell_source_id(approach) != -1:
		return false
	if _is_tree_occupied(approach):
		return false
	if _placed_blocks.has(approach):
		return false
	if structures_layer.get_cell_source_id(approach) != -1:
		return false
	if _cave_entrance_cells.has(approach) or _dungeon_entrance_cells.has(approach):
		return false
	if _world_waypoint_cells.has(approach) or _dungeon_waypoint_cells.has(approach):
		return false
	return true


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
	_refresh_dungeon_grass_clearance()

# Called by DungeonWorld when its quiz altar is cleared — the dungeon is
# "gone from the map": free the entrance portal and forget its tile. Safe to
# call while the overworld is off-tree (in-dungeon): the portal is a child of
# this node and queue_free() works on off-tree nodes.
# --- Temporary dungeon waypoints (one-way) -----------------------------
# Created after a new current-dungeon entrance is placed. The node is purely a
# marker/interaction (no collision) and uses the approved language portal art.
func _create_dungeon_waypoint(dungeon_index: int) -> void:
	if _dungeon_waypoint_nodes.has(dungeon_index):
		return
	if Global.is_dungeon_cleared(dungeon_index):
		return
	if not Global.current_dungeon_indices().has(dungeon_index):
		return
	var lang := Global.dungeon_language(dungeon_index)
	if lang != "lua" and lang != "python":
		return
	var reference_pos := _dungeon_spawn_reference_position()
	var anchor := _find_dungeon_waypoint_anchor(reference_pos, lang)
	if anchor == DUNGEON_INVALID_TILE:
		Global.notify("No clear space near you for the %s dungeon waypoint." % lang.capitalize())
		return
	_spawn_dungeon_waypoint_at(dungeon_index, lang, anchor)


func _dungeon_waypoint_size(_lang: String) -> Vector2i:
	# Temporary waypoints now use the existing 3x3 dungeon-portal art. The real
	# persistent entrance uses the larger language-specific portal instead.
	return Vector2i(3, 3)


func _find_dungeon_waypoint_anchor(reference_pos: Vector2, lang: String) -> Vector2i:
	var size := _dungeon_waypoint_size(lang)
	var base_center := _tile_at_world(reference_pos)
	var center_offset := Vector2i(size.x / 2, size.y - 1)
	# Put Lua on the left and Python on the right when space allows. The two
	# tracks can generate entrances back-to-back, so this keeps their large
	# portals and floating labels from stacking on top of each other.
	var prefer_left := lang == "lua"
	for side_pass in range(2):
		# Keep the temporary dungeon waypoint out of the player's spawn/camp
		# clearing. The old 3-tile minimum put two large portal pads and their
		# labels directly around a new player, making the starting area cramped.
		for radius in range(10, 22):
			for dx in range(-radius, radius + 1):
				for dy in range(-radius, radius + 1):
					if maxi(absi(dx), absi(dy)) != radius:
						continue
					if side_pass == 0:
						if prefer_left and dx > -2:
							continue
						if not prefer_left and dx < 2:
							continue
					var base_cell := base_center + Vector2i(dx, dy)
					var anchor := base_cell - center_offset
					if not _temp_waypoint_anchor_clear(anchor, size, base_center):
						continue
					if not _temp_waypoint_spacing_ok(anchor):
						continue
					return anchor
	return DUNGEON_INVALID_TILE


func _temp_waypoint_spacing_ok(anchor: Vector2i) -> bool:
	for di in _dungeon_waypoint_nodes:
		var other: Variant = _dungeon_waypoint_nodes[di]
		if not is_instance_valid(other):
			continue
		var other_anchor: Variant = other.get("anchor_cell")
		if other_anchor is Vector2i and anchor.distance_to(other_anchor as Vector2i) < 9.0:
			return false
	return true


func _temp_waypoint_anchor_clear(anchor: Vector2i, size: Vector2i,
		player_tile: Vector2i, allow_player_cell: bool = false) -> bool:
	var half_w: int = width / 2
	var half_h: int = height / 2
	for x in range(size.x):
		for y in range(size.y):
			var cell: Vector2i = anchor + Vector2i(x, y)
			if cell == player_tile and not allow_player_cell:
				return false
			if absi(cell.x) >= half_w or absi(cell.y) >= half_h:
				return false
			if _cell_biome_type(cell) == -1:
				return false
			if water_layer.get_cell_source_id(cell) != -1:
				return false
			if structures_layer.get_cell_source_id(cell) != -1:
				return false
			if _cave_entrance_cells.has(cell) or _dungeon_entrance_cells.has(cell):
				return false
			if _placed_blocks.has(cell) or _decor_pending_player_cells.has(cell):
				return false
			if _world_waypoint_cells.has(cell) or _dungeon_waypoint_cells.has(cell):
				return false
			if _is_tree_occupied(cell):
				return false
	for x in range(-1, size.x + 1):
		for y in range(-1, size.y + 1):
			if x >= 0 and y >= 0 and x < size.x and y < size.y:
				continue
			var fringe: Vector2i = anchor + Vector2i(x, y)
			if absi(fringe.x) >= half_w or absi(fringe.y) >= half_h:
				return false
			if _cell_biome_type(fringe) == -1:
				return false
			if water_layer.get_cell_source_id(fringe) != -1:
				return false
	return true


func _spawn_dungeon_waypoint_at(dungeon_index: int, lang: String,
		anchor: Vector2i) -> void:
	if _dungeon_waypoint_nodes.has(dungeon_index):
		return
	var node := DUNGEON_WAYPOINT_SCRIPT.new() as Node2D
	if node == null:
		return
	node.call("setup", dungeon_index, lang, self, anchor)
	add_child(node)
	var size := _dungeon_waypoint_size(lang)
	var base := anchor + Vector2i(size.x / 2, size.y - 1)
	node.global_position = ground_layer.to_global(ground_layer.map_to_local(base)) \
		+ Vector2(0.0, TILE_SIZE * 0.5)
	node.z_index = int(node.global_position.y / TILE_SIZE)
	_dungeon_waypoint_nodes[dungeon_index] = node
	var cells: Array = []
	for x in range(size.x):
		for y in range(size.y):
			var cell := anchor + Vector2i(x, y)
			_dungeon_waypoint_cells[cell] = dungeon_index
			cells.append(cell)
	_clear_grass_in_cells(cells)


func _remove_dungeon_waypoint(dungeon_index: int) -> void:
	var node: Variant = _dungeon_waypoint_nodes.get(dungeon_index)
	_dungeon_waypoint_nodes.erase(dungeon_index)
	for cell in _dungeon_waypoint_cells.keys():
		if int(_dungeon_waypoint_cells[cell]) == dungeon_index:
			_dungeon_waypoint_cells.erase(cell)
	if is_instance_valid(node):
		(node as Node).queue_free()


func _restore_dungeon_waypoints(rows: Variant) -> void:
	if not (rows is Array):
		return
	var current: Array = Global.current_dungeon_indices()
	for value in (rows as Array):
		if not (value is Dictionary):
			continue
		var row: Dictionary = value as Dictionary
		var di := int(row.get("index", 0))
		var lang := str(row.get("language", ""))
		if di <= 0 or not current.has(di) or Global.is_dungeon_cleared(di):
			continue
		if Global.dungeon_language(di) != lang or not _dungeon_entrance_tiles.has(di):
			continue
		var anchor := Vector2i(int(row.get("x", 0)), int(row.get("y", 0)))
		var size := _dungeon_waypoint_size(lang)
		var player_tile := _tile_at_world(_dungeon_spawn_reference_position())
		# Older saves may contain a temporary waypoint inside the spawn clearing.
		# Relocate those on load so the starting grounds become roomy without
		# discarding the player's existing dungeon access.
		var spawn_tile := _tile_at_world(_world_spawn_pos())
		if anchor.distance_to(spawn_tile) < 10.0:
			var relocated := _find_dungeon_waypoint_anchor(_dungeon_spawn_reference_position(), lang)
			if relocated != DUNGEON_INVALID_TILE and relocated.distance_to(spawn_tile) >= 10.0:
				anchor = relocated
		if not _temp_waypoint_anchor_clear(anchor, size, player_tile, true):
			continue
		_spawn_dungeon_waypoint_at(di, lang, anchor)


func _dungeon_waypoint_save_data() -> Array:
	var out: Array = []
	for di in _dungeon_waypoint_nodes:
		var node: Variant = _dungeon_waypoint_nodes[di]
		if not is_instance_valid(node):
			continue
		var anchor: Variant = node.get("anchor_cell")
		if not (anchor is Vector2i):
			continue
		out.append({
			"index": int(di),
			"language": str(node.get("language")),
			"x": (anchor as Vector2i).x,
			"y": (anchor as Vector2i).y,
		})
	return out


# Called by DungeonWaypoint after the player steps onto it. Return true ONLY after the player
# has actually been moved; the caller then consumes/frees the waypoint.
func use_dungeon_waypoint(dungeon_index: int, node: Node) -> bool:
	if _dungeon_waypoint_nodes.get(dungeon_index) != node:
		return false
	if Global.is_dungeon_cleared(dungeon_index) \
			or not Global.current_dungeon_indices().has(dungeon_index) \
			or not _dungeon_entrance_tiles.has(dungeon_index):
		_remove_dungeon_waypoint(dungeon_index)
		Global.notify("That dungeon waypoint is no longer valid.")
		return false
	var dest := _safe_landing_near_tile(
		_dungeon_entrance_tiles[dungeon_index] as Vector2i, 14)
	if dest == Vector2.INF:
		Global.notify("No safe landing spot near the dungeon entrance.")
		return false
	if not _teleport_player_to(dest):
		Global.notify("Could not reach the dungeon entrance.")
		return false
	_remove_dungeon_waypoint(dungeon_index)
	Global.notify("%s dungeon waypoint used ? this entrance is now one-way." %
		Global.dungeon_language(dungeon_index).capitalize())
	# Persist consumption immediately so a quit/crash before the next autosave
	# cannot resurrect a one-way waypoint.
	if Global.active_save_slot > 0 and Global.game_node != null:
		Global.save_game(Global.active_save_slot)
	return true


func _tile_at_world(world_pos: Vector2) -> Vector2i:
	return ground_layer.local_to_map(ground_layer.to_local(world_pos))


func _safe_landing_near_tile(target_tile: Vector2i, max_radius: int) -> Vector2:
	var half_w: int = width / 2
	var half_h: int = height / 2
	for radius in range(1, max_radius + 1):
		for dx in range(-radius, radius + 1):
			for dy in range(-radius, radius + 1):
				if maxi(absi(dx), absi(dy)) != radius:
					continue
				var cell := target_tile + Vector2i(dx, dy)
				if not _is_open_for_player(cell, half_w, half_h):
					continue
				var pos := ground_layer.to_global(ground_layer.map_to_local(cell))
				if _is_hazardous_landing(pos):
					continue
				return pos
	return Vector2.INF


func _is_hazardous_landing(pos: Vector2) -> bool:
	if not is_inside_tree():
		return false
	for mob in get_tree().get_nodes_in_group("Mob"):
		if is_instance_valid(mob) and mob is Node2D:
			if (mob as Node2D).global_position.distance_to(pos) < 64.0:
				return true
	for group in ["DungeonTrap", "DungeonFlare"]:
		for hazard in get_tree().get_nodes_in_group(group):
			if is_instance_valid(hazard) and hazard is Node2D:
				if (hazard as Node2D).global_position.distance_to(pos) < 64.0:
					return true
	return false


func _teleport_player_to(pos: Vector2) -> bool:
	var p: Node2D = _get_player()
	if p == null:
		return false
	if p.has_method("_pnc_cancel"):
		p.call("_pnc_cancel")
	if p is CharacterBody2D:
		(p as CharacterBody2D).velocity = Vector2.ZERO
	p.global_position = pos
	return true


# Called by the minimap's waypoint map. Validation and landing search happen
# before the recall starts so a failed destination never plays the effect.
func teleport_to_world_waypoint(waypoint_id: String) -> bool:
	if _waypoint_teleporting:
		return false
	var node: Variant = _world_waypoint_nodes.get(waypoint_id)
	if not is_instance_valid(node):
		Global.notify("That world waypoint is no longer available.")
		return false
	var anchor: Variant = node.get("anchor_cell")
	if not (anchor is Vector2i):
		return false
	var foot := (anchor as Vector2i) + Vector2i(
		WORLD_WAYPOINT_SIZE.x / 2, WORLD_WAYPOINT_SIZE.y - 1)
	var dest := _safe_landing_near_tile(foot, 14)
	if dest == Vector2.INF:
		Global.notify("No safe landing spot near that world waypoint.")
		return false
	_waypoint_teleporting = true
	call_deferred("_run_waypoint_recall", dest)
	return true


func is_waypoint_teleporting() -> bool:
	return _waypoint_teleporting


func _run_waypoint_recall(dest: Vector2) -> void:
	var p: Node2D = _get_player()
	if p == null or not is_instance_valid(p):
		_waypoint_teleporting = false
		return
	if p.has_method("_pnc_cancel"):
		p.call("_pnc_cancel")
	if p is CharacterBody2D:
		(p as CharacterBody2D).velocity = Vector2.ZERO
	var was_physics: bool = p.is_physics_processing()
	var was_input: bool = p.is_processing_input()
	p.set_physics_process(false)
	p.set_process_input(false)

	# The beacon is anchored at the player's feet, not the sprite origin.
	var fx := WAYPOINT_RECALL_FX_SCRIPT.new() as Node2D
	if fx != null:
		fx.global_position = p.global_position + Vector2(0.0, 17.0)
		add_child(fx)

	await get_tree().create_timer(WAYPOINT_RECALL_BEACON_SEC).timeout
	var host: Node = Global.game_node
	if host == null or not is_instance_valid(host):
		host = get_tree().current_scene
	if host == null:
		host = get_parent()
	var overlay_layer := CanvasLayer.new()
	overlay_layer.layer = 125
	overlay_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	if host != null:
		host.add_child(overlay_layer)
	else:
		add_child(overlay_layer)
	var white := ColorRect.new()
	white.color = Color(1.0, 1.0, 1.0, 0.0)
	white.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay_layer.add_child(white)
	# Anchor after entering the CanvasLayer so the fill resolves against the
	# viewport; a ColorRect sized before parenting can stay at 0x0 on some
	# renderers, making the white recall flash invisible.
	white.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	white.position = Vector2.ZERO
	white.size = get_viewport().get_visible_rect().size

	var fade_in := create_tween()
	fade_in.tween_property(white, "color:a", 1.0, WAYPOINT_WHITE_FADE_IN_SEC) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	await fade_in.finished
	_teleport_player_to(dest)
	await get_tree().create_timer(0.08).timeout
	var fade_out := create_tween()
	fade_out.tween_property(white, "color:a", 0.0, WAYPOINT_WHITE_FADE_OUT_SEC) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	await fade_out.finished

	if is_instance_valid(overlay_layer):
		overlay_layer.queue_free()
	if is_instance_valid(p):
		p.set_physics_process(was_physics)
		p.set_process_input(was_input)
	_waypoint_teleporting = false


func remove_dungeon_entrance(dungeon_index: int) -> void:
	# A temporary one-way waypoint only exists for this exact dungeon instance.
	_remove_dungeon_waypoint(dungeon_index)
	# Untyped: a freed portal/entrance assigned to a typed `Node` var throws
	# "Trying to assign invalid previously freed instance".
	var portal: Variant   = _dungeon_portal_nodes.get(dungeon_index)
	var entrance: Variant = _dungeon_entrance_nodes.get(dungeon_index)
	_dungeon_portal_nodes.erase(dungeon_index)
	_dungeon_entrance_nodes.erase(dungeon_index)
	_dungeon_entrance_tiles.erase(dungeon_index)
	_refresh_dungeon_grass_clearance()
	# Scrub the painted entrance bookkeeping so a cleared dungeon leaves no
	# orphaned collision cells / chunk claims (persisted on the next save).
	if _dungeon_entrance_structure_cells.has(dungeon_index):
		for cell in (_dungeon_entrance_structure_cells[dungeon_index] as Array):
			var c := cell as Vector2i
			_dungeon_entrance_cells.erase(c)
			_structure_claimed_chunks.erase(_tile_to_chunk(c))
		_dungeon_entrance_structure_cells.erase(dungeon_index)
	# Dramatic send-off: the portal dissolves itself (taking the painted
	# entrance with it). This runs while the player is INSIDE the dungeon and
	# the overworld is off-tree, so the portal defers the animation until it is
	# back on screen — i.e. the moment the player returns to the surface.
	if is_instance_valid(portal) and portal.has_method("begin_dissolve"):
		portal.call("begin_dissolve", entrance)
	else:
		if is_instance_valid(entrance):
			entrance.queue_free()
		if is_instance_valid(portal):
			portal.queue_free()

# World position of the live entrance for a language's current dungeon
# ("lua"/"python"), or Vector2.INF when that track is finished or its
# entrance hasn't been placed. Internal debug helper.
func get_dungeon_entrance_target(lang: String) -> Vector2:
	var idx: int = Global.current_dungeon_index(lang)
	if idx <= 0 or not _dungeon_entrance_tiles.has(idx) or Global.is_dungeon_cleared(idx):
		return Vector2.INF
	var tile: Vector2i = _dungeon_entrance_tiles[idx] as Vector2i
	return ground_layer.to_global(ground_layer.map_to_local(tile))

# Guided onboarding travel: validates the live entrance and uses the same
# safe-landing + recall/white-fade path as the permanent waypoint network. The
# player still has to click the real dungeon portal after arriving.
func tutorial_teleport_near_dungeon(lang: String) -> bool:
	if _waypoint_teleporting:
		return false
	var idx: int = Global.current_dungeon_index(lang)
	if idx <= 0 or not _dungeon_entrance_tiles.has(idx) or Global.is_dungeon_cleared(idx):
		return false
	var tile: Vector2i = _dungeon_entrance_tiles[idx] as Vector2i
	var dest := _safe_landing_near_tile(tile, 14)
	if dest == Vector2.INF:
		return false
	_waypoint_teleporting = true
	call_deferred("_run_waypoint_recall", dest)
	return true

# World position the mission guide arrow points at: the NEAREST of the live
# dungeon entrances (one per language). Vector2.INF means "no target" (the
# arrow hides): no entrance currently exists, or this is called while inside a
# cave/dungeon (those worlds don't have this method, and the arrow's
# has_method() guard handles that).
func get_dungeon_guide_target() -> Vector2:
	var player: Node2D = _get_player()
	if player == null:
		return Vector2.INF
	var best: Vector2 = Vector2.INF
	var best_dist: float = INF
	for idx in Global.current_dungeon_indices():
		var di: int = int(idx)
		if not _dungeon_entrance_tiles.has(di) or Global.is_dungeon_cleared(di):
			continue
		var tile: Vector2i = _dungeon_entrance_tiles[di] as Vector2i
		var pos: Vector2 = ground_layer.to_global(ground_layer.map_to_local(tile))
		var dist: float = player.global_position.distance_to(pos)
		if dist < best_dist:
			best_dist = dist
			best = pos
	return best

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
		# The map is regenerated from this seed on load, so it must be saved or
		# the world would come back as a different map.
		"seed":          random_seed,
		"placed_blocks": [],
		"removed_trees": _removed_trees.duplicate(),
		"mobs":          _collect_preserved_mobs(),
		"dungeon_entrances": [],
		# Planted crops (tile + age). The tilled plot itself is a placed block;
		# this records what is growing on it so a reload restores the crop at
		# the age it had reached — including fully grown wheat.
		"crops":         [],
	}
	# Procedural houses/pillars persist as small deterministic definitions plus
	# a list of cells the player has removed. Individual generated blocks are
	# excluded from placed_blocks below, so the save stays compact.
	data["decor_structures"] = _decor_structures.duplicate(true)
	data["decor_removed"] = _decor_save_removed()
	# Empty is authoritative only when the save already told us this world was
	# initialised (or we actually placed structures). This prevents a save made
	# before world-gen finishes from permanently locking a legacy world out of
	# the decorative pass.
	data["decor_initialized"] = \
		bool(Global.pending_world_data.get("decor_initialized", false)) \
		or not _decor_structures.is_empty()
	data["world_waypoints"] = _world_waypoint_save_data()
	data["world_waypoints_initialized"] = \
		bool(Global.pending_world_data.get("world_waypoints_initialized", false)) \
		or not _world_waypoints.is_empty()
	data["dungeon_waypoints"] = _dungeon_waypoint_save_data()
	for ccell in _crops:
		var crop_ref: Variant = _crops[ccell]
		if not is_instance_valid(crop_ref):
			continue
		var cc: Vector2i = ccell as Vector2i
		data["crops"].append({"x": int(cc.x), "y": int(cc.y),
			"elapsed": float((crop_ref as Node).get("elapsed"))})
	for idx in _dungeon_entrance_tiles:
		var t: Vector2i = _dungeon_entrance_tiles[idx] as Vector2i
		data["dungeon_entrances"].append({"index": int(idx), "x": t.x, "y": t.y})
	for cell in _placed_blocks:
		var entry: Dictionary = _placed_blocks[cell] as Dictionary
		# Natural world-gen patches (stone/charcoal) are NOT saved — they
		# regenerate deterministically from the seed, and persisting thousands
		# of them would bloat the save and slow loading. Procedural structure
		# blocks are likewise rebuilt from decor_structures/decor_removed.
		if bool(entry.get("natural", false)) or bool(entry.get("decor_generated", false)):
			continue
		var node_ref: Variant = entry["node"]
		if not is_instance_valid(node_ref):
			continue
		var node: Node = node_ref as Node
		if node == null:
			continue
		var idata: ItemData = node.get("item_data") as ItemData
		if idata == null:
			continue
		var block_entry: Dictionary = {
			"cell_x":        (cell as Vector2i).x,
			"cell_y":        (cell as Vector2i).y,
			"item_path":     "" if idata.is_color_block else idata.resource_path,
			"color":         ColorBlock.key_of(idata.block_color) if idata.is_color_block else "",
			"chest_slots":   null,
			"dungeon_index": null,
		}
		# Runtime-generated color blocks have no resource_path — they persist by
		# their RGB key instead. Anything else with no path can't be saved.
		if not idata.is_color_block and idata.resource_path.is_empty():
			continue
		if node.has_method("get_items"):
			var slots: Array = node.call("get_items") as Array
			var saved: Array = []
			for slot in slots:
				saved.append(Global.serialize_item(slot))
			block_entry["chest_slots"] = saved
		var di = node.get("dungeon_index")
		if di != null:
			block_entry["dungeon_index"] = int(di)
		# Crafting Station automation state (selected recipe / program / output).
		if node.has_method("get_station_save_data"):
			block_entry["station"] = node.call("get_station_save_data")
		# Furnace automation state (program / input / fuel / output).
		if node.has_method("get_furnace_save_data"):
			block_entry["furnace"] = node.call("get_furnace_save_data")
		# LUA station state (name, combat, tool, build palette, inventory, code).
		if node.has_method("get_lua_save_data"):
			block_entry["lua"] = node.call("get_lua_save_data")
		# Door state (facing + open/closed) — doors only.
		if idata.is_door and node.has_method("get_door_save_data"):
			block_entry["door"] = node.call("get_door_save_data")
		# A floor kept underneath this block persists so it survives a reload.
		var floor_ref: Variant = entry.get("floor")
		if floor_ref != null and is_instance_valid(floor_ref):
			var fdata: ItemData = (floor_ref as Node).get("item_data") as ItemData
			if fdata != null and not fdata.is_color_block and not fdata.resource_path.is_empty():
				block_entry["floor_path"] = fdata.resource_path
		data["placed_blocks"].append(block_entry)
	return data

func apply_world_save_data(data: Dictionary) -> void:
	# The world may be mid-swap (off-tree) while save data is applied — a null
	# get_tree() would crash the group scans below. is_inside_tree() avoids the
	# engine error get_tree() itself logs while off-tree.
	if not is_inside_tree():
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
			# Only restore entrances that are still playable (their dungeon
			# hasn't been cleared and its mission content still resolves);
			# _ensure_current_dungeon_entrances then fills in any the saved
			# data predates.
			if Global.is_dungeon_cleared(idx):
				continue
			if not Global.is_dungeon_mission_ready(idx):
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
		var color_key:  String = str(bd.get("color", ""))
		var idata: ItemData = null
		if not color_key.is_empty():
			idata = ColorBlock.from_key(color_key)
		elif not item_path.is_empty() and ResourceLoader.exists(item_path):
			idata = load(item_path) as ItemData
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
		var chest_like := scene_path.ends_with("ChestBlock.tscn")
		if not chest_like and obj.has_method("setup"):
			obj.call("setup", idata)
		_placed_blocks[cell] = {"node": obj, "name": idata.item_name}
		if obj.has_method("set_world_cell"):
			obj.call("set_world_cell", cell, self)
		add_child(obj)
		if not is_instance_valid(obj):
			_placed_blocks.erase(cell)
			continue
		if chest_like and obj.has_method("setup"):
			obj.call("setup", idata)
		obj.position = editable_layer.map_to_local(cell)
		obj.z_index  = FLOOR_Z if idata.is_floor else int(obj.position.y / TILE_SIZE)
		_fix_sprite_offset(obj)
		# Restore a floor kept underneath this block (placing on a floor keeps it).
		var floor_path: String = str(bd.get("floor_path", ""))
		if not floor_path.is_empty() and ResourceLoader.exists(floor_path):
			var fdata: ItemData = load(floor_path) as ItemData
			if fdata != null and fdata.is_floor and not fdata.place_scene_path.is_empty() \
					and ResourceLoader.exists(fdata.place_scene_path):
				var fscene: PackedScene = load(fdata.place_scene_path) as PackedScene
				if fscene != null:
					var fobj: Node = fscene.instantiate()
					if fobj != null:
						if fobj.has_method("setup"):
							fobj.call("setup", fdata)
						if fobj.has_method("set_world_cell"):
							fobj.call("set_world_cell", cell, self)
						add_child(fobj)
						if is_instance_valid(fobj):
							fobj.position = editable_layer.map_to_local(cell)
							fobj.z_index = FLOOR_Z
							_fix_sprite_offset(fobj)
							(_placed_blocks[cell] as Dictionary)["floor"] = fobj
		var chest_slots = bd.get("chest_slots", null)
		if chest_slots is Array:
			var slots_ref = obj.get("slots")
			if slots_ref is Array:
				for i in range(mini((chest_slots as Array).size(), (slots_ref as Array).size())):
					var slot: Variant = Global.deserialize_item((chest_slots as Array)[i])
					if slot != null:
						(slots_ref as Array)[i] = slot
			if obj.has_method("_refresh_ui"):
				obj.call("_refresh_ui")
		var di = bd.get("dungeon_index", null)
		if di != null:
			obj.set("dungeon_index", int(di))
		# Restore Crafting Station automation state, if this block had any.
		var station_data = bd.get("station", null)
		if station_data is Dictionary and obj.has_method("set_station_save_data"):
			obj.call("set_station_save_data", station_data)
		# Restore Furnace automation state, if this block had any.
		var furnace_data = bd.get("furnace", null)
		if furnace_data is Dictionary and obj.has_method("set_furnace_save_data"):
			obj.call("set_furnace_save_data", furnace_data)
		# Restore LUA station state, if this block had any.
		var lua_data = bd.get("lua", null)
		if lua_data is Dictionary and obj.has_method("set_lua_save_data"):
			obj.call("set_lua_save_data", lua_data)
		# Door state (facing + open/closed) — doors only.
		var door_data = bd.get("door", null)
		if idata.is_door and door_data is Dictionary and obj.has_method("set_door_save_data"):
			obj.call("set_door_save_data", door_data)

	# Restored columns need their U-colliders re-evaluated now that every
	# neighbour exists (each block's _ready ran before the rest of its column
	# was restored, so it saw no vertical neighbour yet).
	for cell in _placed_blocks.keys():
		_refresh_neighbor_u_collision(cell as Vector2i)
	# Rebuild the housing rooms now that every restored block exists.
	housing_rebuild_all()
	# Restore planted crops now that their tilled plots exist. The age is
	# preserved, so a crop that was already ripe stays ripe (and cuttable).
	for crop_entry in (data.get("crops", []) as Array):
		if not (crop_entry is Dictionary):
			continue
		var ce: Dictionary = crop_entry as Dictionary
		_spawn_crop(Vector2i(int(ce.get("x", 0)), int(ce.get("y", 0))),
			float(ce.get("elapsed", 0.0)))
	Global.set_mission_progress("build_shelter", housing_valid_room_count())
	# A (re)generated tree must never share a tile with a restored block. If the
	# world regenerated even slightly differently (or a block was saved under a
	# tree), free any tree now sitting in a block-occupied cell so it can't
	# overlap the player's build.
	for tree in get_tree().get_nodes_in_group("Tree"):
		if not is_instance_valid(tree):
			continue
		var spawn_cell: Variant = tree.get_meta("spawn_cell", null)
		if spawn_cell == null:
			continue
		if _placed_blocks.has(spawn_cell as Vector2i):
			_unmark_tree_occupied(spawn_cell as Vector2i)
			(tree as Node).queue_free()
