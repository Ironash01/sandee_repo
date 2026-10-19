extends Node2D
class_name DungeonWorld

# A single dungeon interior — swapped in for the overworld "World" node by
# game_instance.gd's enter_dungeon()/exit_dungeon(), same pattern as
# CaveWorld (see cave_world.gd's header for the shared rationale). Built
# entirely in code at setup() time from DungeonGenerator's output: one
# TileMapLayer rendering real dungeon ItemData sprites — dungeon_floor1-3 as
# the floor (picked deterministically per tile), the eight dungeon_wall_*
# sprites auto-tiled by wall adjacency (see _wall_variant) with native
# per-tile collision — plus the mission's KnowledgeAltar in the first room,
# the QuizAltar in the final room, and bright uniform lighting (no flashlight).
# The dungeon map is the shared Minimap (minimap.gd), which swaps to this
# world's grid content while Global.world_node is a DungeonWorld.
#
# Clearing flow: the QuizAltar emits cleared once every question is right,
# which grants the reward + completes the mission + records the clear star
# (all in quiz_altar.gd / Global). This world then (a) removes the overworld
# entrance ("the dungeon is gone from the map") and (b) activates the EXIT
# marker in the quiz room, which teleports the player out via exit_dungeon().
#
# Scope note for the first pass: dungeons are puzzle spaces, not mining/caving
# maps — deliberately NO block placement, mining, or debug overlays here
# (Global dispatches those with a has_method() guard, so their absence is safe).

const TILE_SIZE: int = 32

# The generated dungeon grid is surrounded by this many tiles of dungeon wall
# on every side, so the map edge doesn't show as black void (see
# _paint_surrounding_walls). 128 tiles matches the cave world's surround.
const SURROUND_BAND_TILES: int = 128

# Wall sprite variant -> the dungeon ItemData that renders it. `mid_mid` has
# no sprite in the tileset, so it reuses top_mid's texture.
const WALL_ITEM_PATHS: Dictionary = {
	"top_left":  "res://resources/items/dungeon_wall_TOPLEFT.tres",
	"top_mid":   "res://resources/items/dungeon_wall_TOPMIDDLE.tres",
	"top_right": "res://resources/items/dungeon_wall_TOPRIGHT.tres",
	"mid_left":  "res://resources/items/dungeon_wall_MIDLEFT.tres",
	"mid_mid":   "res://resources/items/dungeon_wall_TOPMIDDLE.tres",
	"mid_right": "res://resources/items/dungeon_wall_MIDRIGHT.tres",
	"bot_left":  "res://resources/items/dungeon_wall_BOTLEFT.tres",
	"bot_mid":   "res://resources/items/dungeon_wall_BOTMID.tres",
	"bot_right": "res://resources/items/dungeon_wall_BOTRIGHT.tres",
}

const FLOOR_ITEM_PATHS: Array = [
	"res://resources/items/dungeon_floor1.tres",
	"res://resources/items/dungeon_floor2.tres",
	"res://resources/items/dungeon_floor3.tres",
]

# Ranged dungeon enemy (see scripts/hitman.gd). Guards + spawner both use it.
const HITMAN_SCENE: PackedScene = preload("res://scenes/mobs/Hitman.tscn")

# Safe-zone markers use the dev item resources/items/dungeon_safe_zone_marker.tres
# (a 3x 32x32 sheet: idle / active / warning). The zones themselves are built in
# _spawn_safe_zones().

static var _shared_tile_set: TileSet = null
static var _wall_cells: Dictionary = {}  # wall variant -> {"source": id, "coord": Vector2i}
static var _floor_cells: Array = []      # [{"source": id, "coord": Vector2i}, ...]

# ── EXIT marker (inner class) ──────────────────────────────────────────
# Dormant until the dungeon is cleared; walking into it teleports the player
# out. Drawn like CavePortal's placeholder markers — no dedicated art yet.
# Defined before the member that holds it (see _exit_marker's type).
class DungeonExit:
	extends Node2D

	const COLOR: Color = Color(0.85, 0.72, 0.20, 1.0)
	const RETRIGGER_COOLDOWN: float = 1.0

	var _active:    bool = false
	var _triggered: bool = false
	var _area: Area2D = null

	func _init() -> void:
		_area = Area2D.new()
		var shape := CollisionShape2D.new()
		var rect := RectangleShape2D.new()
		rect.size = Vector2(32, 32)
		shape.shape = rect
		_area.add_child(shape)
		_area.collision_layer = 0
		_area.collision_mask  = 4   # player is on layer 4 (see player.tscn)
		_area.monitoring      = false
		_area.body_entered.connect(_on_body_entered)
		add_child(_area)
		visible = false
		queue_redraw()

	func set_active(active: bool) -> void:
		_active = active
		visible = active
		_area.monitoring = active
		queue_redraw()

	func _draw() -> void:
		# Recomputed here rather than _init — callers set global_position
		# AFTER add_child(), so it's only valid once the node is placed.
		z_index = int(global_position.y / 32)
		if not _active:
			return
		var half: float = 16.0
		draw_rect(Rect2(-half, -half, 32, 32), COLOR)
		draw_rect(Rect2(-half, -half, 32, 32), Color(0, 0, 0, 0.6), false, 2.0)
		var font: Font = ThemeDB.fallback_font
		var fsize: int = int(8 * Global.ui_scale)
		var text_size := font.get_string_size("EXIT", HORIZONTAL_ALIGNMENT_CENTER, -1, fsize)
		draw_string(font, Vector2(-text_size.x / 2.0, fsize / 2.0), "EXIT",
			HORIZONTAL_ALIGNMENT_CENTER, -1, fsize, Color.WHITE)

	func _on_body_entered(body: Node) -> void:
		if _triggered or not _active or not body.is_in_group("Player"):
			return
		_triggered = true
		_start_cooldown()
		if is_instance_valid(Global.game_node) and Global.game_node.has_method("exit_dungeon"):
			Global.game_node.call("exit_dungeon")

	func _start_cooldown() -> void:
		var t := Timer.new()
		t.wait_time = RETRIGGER_COOLDOWN
		t.one_shot  = true
		t.timeout.connect(func() -> void:
			_triggered = false
			t.queue_free()
		)
		add_child(t)
		t.start()

# ── Dungeon lighting ──────────────────────────────────────────────────
# Brighter than the cave: the "flashlight" PointLight2D that followed the
# player around (cave-style) was removed on request — the whole dungeon is
# uniformly lit by a fairly bright CanvasModulate instead, and a
# WorldEnvironment glow makes the altars' pulsing PointLight2Ds bloom.
# All children of this world, so they die with it on exit_dungeon().
const DUNGEON_AMBIENT_COLOR: Color = Color(0.50, 0.50, 0.62, 1.0)

var generator: DungeonGenerator = null
var overworld_return_position: Vector2 = Vector2.ZERO
var _overworld: Node2D = null

var _dungeon_index: int = 0
var _mission: DungeonMissionData = null
var _tilemap: TileMapLayer = null
var _exit_marker: DungeonExit = null
var _cleared: bool = false

# ── Hitman spawner ─────────────────────────────────────────────────
# Hitmen are NOT placed at generation time — a timer spawns one near a random
# flare/trap every 5-10s so the dungeon keeps feeling dangerous, capped at
# HITMAN_MAX_ALIVE, and held back for HITMAN_DEATH_COOLDOWN after one dies.
const HITMAN_MAX_ALIVE:       int   = 15
const HITMAN_SPAWN_MIN:       float = 5.0
const HITMAN_SPAWN_MAX:       float = 10.0
const HITMAN_DEATH_COOLDOWN:  float = 20.0
# Never spawn right on top of the player.
const HITMAN_MIN_PLAYER_DIST: float = 6.0 * TILE_SIZE

var _hitman_timer:    float = 0.0
var _hitman_cooldown: float = 0.0
var _safe_zones:      Array = []   # DungeonSafeZone per safe altar room

func setup(dungeon_index: int, mission: DungeonMissionData, seed_value: int,
		overworld: Node2D, return_position: Vector2) -> void:
	_dungeon_index = dungeon_index
	_mission       = mission
	_overworld     = overworld
	overworld_return_position = return_position

	generator = DungeonGenerator.new()
	if _mission != null:
		generator.generate(seed_value, _mission.size_modifier, _mission.altar_amount, _mission.chest_amount)
	else:
		generator.generate(seed_value)

	_tilemap = TileMapLayer.new()
	_tilemap.name     = "DungeonTiles"
	_tilemap.tile_set = _get_shared_tile_set()
	# Same z_index convention cave_world.gd uses (see its comment): the
	# player/altars Y-sort into small quantized buckets that go NEGATIVE
	# north of the grid's center, so the tilemap must sit well below them.
	_tilemap.z_index = -300
	add_child(_tilemap)

	_paint_tiles()
	_spawn_altars()
	_spawn_flares()
	_spawn_traps()
	_spawn_safe_zones()
	_spawn_quiz_guards()
	_spawn_quiz_traps()
	_init_hitman_spawner()
	_spawn_exit_marker()
	_setup_lighting()

# Wall tiles the generator marked as flare hosts get a DungeonFlare overlay
# (a glowing obstacle that shoots projectiles). The wall itself stays solid.
func _spawn_flares() -> void:
	for grid_pos in generator.flare_positions:
		var flare := DungeonFlare.new()
		add_child(flare)
		flare.global_position = _tilemap.to_global(
			_tilemap.map_to_local(_grid_to_cell(grid_pos as Vector2i)))
		flare.z_index = int(flare.global_position.y / 32)

# Corridor FLOOR tiles the generator marked as trap hosts get a persistent
# DungeonTrap (a pressure-plate hazard that detonates explosions when stepped
# on). It never despawns.
func _spawn_traps() -> void:
	for grid_pos in generator.trap_positions:
		var trap := DungeonTrap.new()
		add_child(trap)
		trap.global_position = _tilemap.to_global(
			_tilemap.map_to_local(_grid_to_cell(grid_pos as Vector2i)))

# The single safe zone: the KNOWLEDGE room, with a marker decal on each of its
# corridor gaps. Walking a marker arms the zone (see dungeon_safe_zone.gd). The
# quiz room is NOT safe — its hitman guards must be defeated.
func _spawn_safe_zones() -> void:
	_safe_zones.clear()
	var zone := DungeonSafeZone.new()
	add_child(zone)
	zone.setup(self, _room_rect_px(generator.knowledge_room))
	_safe_zones.append(zone)
	# A marker on every walkable tile around each gap (deduped so overlapping
	# gap neighbourhoods don't stack markers).
	var cells: Dictionary = {}
	for gap in generator.gap_positions:
		for cell in _marker_cells_around(gap as Vector2i):
			cells[cell] = true
	for cell in cells.keys():
		zone.add_marker(grid_to_world(cell as Vector2i))

# The walkable cells SURROUNDING a gap cell (its 3x3 neighbourhood), so the
# safe-zone marker covers the whole corridor entrance, not just one tile.
func _marker_cells_around(cell: Vector2i) -> Array:
	var out: Array = []
	for dx in range(-1, 2):
		for dy in range(-1, 2):
			var c := cell + Vector2i(dx, dy)
			if grid_cell_is_floor(c):
				out.append(c)
	return out

# The world-space rect covering a room's floor tiles (for the glow + inside check).
func _room_rect_px(room: Dictionary) -> Rect2:
	var p: Vector2i = room["pos"]
	var s: Vector2i = room["size"]
	var half := Vector2(TILE_SIZE, TILE_SIZE) * 0.5
	var tl: Vector2 = grid_to_world(p) - half
	var br: Vector2 = grid_to_world(p + s - Vector2i(1, 1)) + half
	return Rect2(tl, br - tl)

# 4 hitman guards ringing the quiz altar (spawned at generation, inside the room).
func _spawn_quiz_guards() -> void:
	for cell in generator.quiz_guard_positions:
		_spawn_hitman_at(cell as Vector2i)

# A ring of traps around the quiz altar with 2 walk-through gaps.
func _spawn_quiz_traps() -> void:
	for cell in generator.quiz_trap_positions:
		var trap := DungeonTrap.new()
		add_child(trap)
		trap.global_position = grid_to_world(cell as Vector2i)

# ── Hitman spawner ─────────────────────────────────────────────────
# Seeds the spawn timer. No Hitmen are placed at generation time — the first
# one appears 5-10s after the player enters (see _tick_hitman_spawner).
func _init_hitman_spawner() -> void:
	_hitman_timer    = randf_range(HITMAN_SPAWN_MIN, HITMAN_SPAWN_MAX)
	_hitman_cooldown = 0.0

func _process(delta: float) -> void:
	_tick_hitman_spawner(delta)

# Leaving the dungeon must clear the flag — the zones set it while active, and
# _process stops running once we're out of the tree.
func _exit_tree() -> void:
	Global.player_in_safe_room = false

func _tick_hitman_spawner(delta: float) -> void:
	_hitman_cooldown = maxf(0.0, _hitman_cooldown - delta)
	_hitman_timer -= delta
	if _hitman_timer > 0.0 or _hitman_cooldown > 0.0:
		return
	# Cap the population so the dungeon doesn't fill up with hitmen.
	if get_tree().get_nodes_in_group("Hitman").size() >= HITMAN_MAX_ALIVE:
		_hitman_timer = randf_range(HITMAN_SPAWN_MIN, HITMAN_SPAWN_MAX)
		return
	_spawn_hitman_near_hazard()
	_hitman_timer = randf_range(HITMAN_SPAWN_MIN, HITMAN_SPAWN_MAX)

# Spawn a Hitman on a walkable cell next to a random flare or trap.
func _spawn_hitman_near_hazard() -> void:
	var spots: Array = []
	for gp in generator.flare_positions:
		var s := _floor_near(gp as Vector2i)
		if s.x >= 0:
			spots.append(s)
	for gp in generator.trap_positions:
		var s := _floor_near(gp as Vector2i)
		if s.x >= 0:
			spots.append(s)
	# Prefer spots away from the player so hitmen don't pop in on top of them.
	var p: Node2D = Global.player_node as Node2D
	if p != null and is_instance_valid(p):
		var far: Array = []
		for s in spots:
			if p.global_position.distance_to(grid_to_world(s)) >= HITMAN_MIN_PLAYER_DIST:
				far.append(s)
		if not far.is_empty():
			spots = far
	if spots.is_empty():
		return
	_spawn_hitman_at(spots[randi() % spots.size()])

func _spawn_hitman_at(cell: Vector2i) -> void:
	var hitman: Node2D = HITMAN_SCENE.instantiate() as Node2D
	if hitman == null:
		return
	add_child(hitman)
	hitman.global_position = grid_to_world(cell)
	hitman.died.connect(_on_hitman_died)

# A walkable cell adjacent to `gp` (so a spawn never lands in a wall or on the
# hazard tile itself). Vector2i(-1, -1) if none.
func _floor_near(gp: Vector2i) -> Vector2i:
	var dirs: Array = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
	dirs.shuffle()
	for d in dirs:
		if grid_cell_is_floor(gp + d):
			return gp + d
	return Vector2i(-1, -1)

# A hitman died — hold the next spawn back so the dungeon has a lull.
func _on_hitman_died() -> void:
	_hitman_cooldown = HITMAN_DEATH_COOLDOWN

# ── Paint the generated grid into the TileMapLayer ─────────────────────
func _paint_tiles() -> void:
	for x in range(generator.width):
		for y in range(generator.height):
			var grid_pos := Vector2i(x, y)
			if generator.grid[x][y] == DungeonGenerator.Tile.FLOOR:
				if _floor_cells.is_empty():
					continue
				var cell: Dictionary = _floor_cells[_floor_variant_index(grid_pos)]
				_tilemap.set_cell(_grid_to_cell(grid_pos), cell["source"], cell["coord"])
			else:
				var cell: Dictionary = _wall_cells.get(_wall_variant(x, y), {})
				if not cell.is_empty():
					_tilemap.set_cell(_grid_to_cell(grid_pos), cell["source"], cell["coord"])
	_paint_surrounding_walls()

# Fills the void around the generated dungeon with a solid band of dungeon
# walls — the grid itself is fully populated, but the TileMapLayer beyond its
# border was empty, so the map edge showed through as black void. A
# SURROUND_BAND_TILES-thick wall band on all four sides closes that off,
# mirroring cave_world.gd's stone-wall surround.
func _paint_surrounding_walls() -> void:
	var cell: Dictionary = _wall_cells.get("mid_mid", {})
	if cell.is_empty():
		return
	var half_w: int = generator.width / 2
	var half_h: int = generator.height / 2
	var x0 := -(half_w + SURROUND_BAND_TILES)
	var x1 := half_w + SURROUND_BAND_TILES
	var y0 := -(half_h + SURROUND_BAND_TILES)
	var y1 := half_h + SURROUND_BAND_TILES
	for cx in range(x0, x1):
		for cy in range(y0, y1):
			if cx >= -half_w and cx < half_w and cy >= -half_h and cy < half_h:
				continue  # inside the generated grid — already painted
			_tilemap.set_cell(Vector2i(cx, cy), cell["source"], cell["coord"])

# Deterministic pick (pure function of tile position, no RNG needed) so a
# dungeon's visuals stay identical across repeat visits, same as its layout.
func _floor_variant_index(grid_pos: Vector2i) -> int:
	var h: int = (grid_pos.x * 92821) ^ (grid_pos.y * 68917)
	return absi(h) % _floor_cells.size()

# Picks which of the eight wall sprites a wall cell shows from its orthogonal
# neighbors. The tileset is a 3x3 face set (TOP row = top face, MID = middle
# band, BOT = bottom face; LEFT/CENTER/RIGHT = sides): a wall whose cell
# above is open shows its top face, one whose cell below is open shows its
# bottom face, and a buried wall shows its middle band (sides exposed).
func _wall_variant(x: int, y: int) -> String:
	var up    := _cell_is_wall(x, y - 1)
	var down  := _cell_is_wall(x, y + 1)
	var left  := _cell_is_wall(x - 1, y)
	var right := _cell_is_wall(x + 1, y)
	if not up:
		if not left: return "top_left"
		if not right: return "top_right"
		return "top_mid"
	if not down:
		if not left: return "bot_left"
		if not right: return "bot_right"
		return "bot_mid"
	if not left: return "mid_left"
	if not right: return "mid_right"
	return "mid_mid"

func _cell_is_wall(x: int, y: int) -> bool:
	if x < 0 or y < 0 or x >= generator.width or y >= generator.height:
		return true  # off the generated map — solid surround walls
	return generator.grid[x][y] != DungeonGenerator.Tile.FLOOR

# ── Objects ────────────────────────────────────────────────────────────
func _spawn_altars() -> void:
	var knowledge := KnowledgeAltar.new()
	knowledge.setup(_mission)
	add_child(knowledge)
	knowledge.global_position = _tilemap.to_global(_tilemap.map_to_local(_grid_to_cell(generator.knowledge_altar_pos)))

	var quiz := QuizAltar.new()
	quiz.setup(_mission)
	quiz.cleared.connect(_on_dungeon_cleared)
	add_child(quiz)
	quiz.global_position = _tilemap.to_global(_tilemap.map_to_local(_grid_to_cell(generator.quiz_altar_pos)))

# The exit stays dormant until the quiz is cleared ("the exit opens"); it
# then teleports the player back out of the dungeon.
func _spawn_exit_marker() -> void:
	_exit_marker = DungeonExit.new()
	add_child(_exit_marker)
	_exit_marker.global_position = _tilemap.to_global(
		_tilemap.map_to_local(_grid_to_cell(generator.quiz_altar_pos + Vector2i(0, 2))))
	_exit_marker.set_active(false)

func _on_dungeon_cleared(_index: int) -> void:
	if _cleared:
		return
	_cleared = true
	if _exit_marker != null:
		_exit_marker.set_active(true)
	# The dungeon is gone from the map: free the overworld's portal + forget
	# its tile so it never reappears (persisted on the next overworld save).
	if _overworld != null and _overworld.has_method("remove_dungeon_entrance"):
		_overworld.call("remove_dungeon_entrance", _dungeon_index)

# Not the overworld — a Bonfire here must not set the respawn point.
func is_overworld() -> bool:
	return false

func get_player_spawn_pos() -> Vector2:
	return _tilemap.to_global(_tilemap.map_to_local(_grid_to_cell(generator.player_spawn_pos)))

# Generator grid indices run 0..width-1 / 0..height-1; centering the map on
# the origin (matching the overworld/cave convention) means every grid->cell
# conversion needs this same per-axis offset.
# ── Camera bounds ───────────────────────────────────────────────────
# The playable rect of THIS dungeon, in world coordinates — the generated grid
# (rooms + corridors) is centred on the origin (see _grid_to_cell). The band of
# dungeon wall painted around the grid (SURROUND_BAND_TILES) is deliberately
# EXCLUDED so the camera stops at the real playable area instead of drifting out
# into the surround.
func camera_bounds() -> Rect2:
	if generator == null:
		return Rect2()
	var half := Vector2i(generator.width / 2, generator.height / 2)
	return Rect2(-Vector2(half) * float(TILE_SIZE),
		Vector2(generator.width, generator.height) * float(TILE_SIZE))

func _grid_to_cell(tile: Vector2i) -> Vector2i:
	return tile - Vector2i(generator.width / 2, generator.height / 2)

# ── Grid helpers for dungeon AIs (see hitman.gd) ───────────────────────
# The Hitman walks the generator's FLOOR grid, so it needs to convert between
# grid indices and world positions and ask whether a cell is walkable. These
# wrap the same _grid_to_cell / map_to_local math the spawners use, so the two
# can never drift apart.
func grid_to_world(grid_pos: Vector2i) -> Vector2:
	return _tilemap.to_global(_tilemap.map_to_local(_grid_to_cell(grid_pos)))

func world_to_grid(world_pos: Vector2) -> Vector2i:
	var cell: Vector2i = _tilemap.local_to_map(_tilemap.to_local(world_pos))
	return cell + Vector2i(generator.width / 2, generator.height / 2)

func grid_cell_is_floor(grid_pos: Vector2i) -> bool:
	if grid_pos.x < 0 or grid_pos.y < 0 \
			or grid_pos.x >= generator.width or grid_pos.y >= generator.height:
		return false
	return generator.grid[grid_pos.x][grid_pos.y] == DungeonGenerator.Tile.FLOOR

# ── Shared tileset (built once, reused by every dungeon) ───────────────
# Same approach as cave_world.gd's: every ItemData icon is its own AtlasTexture
# region that does NOT all land on one common 32px grid, so each gets a
# dedicated TileSetAtlasSource sized/margined to its exact region (see
# _add_icon_source). Collision lives on the TileSet itself, not per-tile nodes.
static func _get_shared_tile_set() -> TileSet:
	if _shared_tile_set != null:
		return _shared_tile_set

	var ts := TileSet.new()
	ts.tile_size = Vector2i(TILE_SIZE, TILE_SIZE)
	ts.add_physics_layer()
	ts.set_physics_layer_collision_layer(0, 1)
	ts.set_physics_layer_collision_mask(0, 1)

	var poly := PackedVector2Array([
		Vector2(-TILE_SIZE / 2.0, -TILE_SIZE / 2.0),
		Vector2(TILE_SIZE / 2.0, -TILE_SIZE / 2.0),
		Vector2(TILE_SIZE / 2.0, TILE_SIZE / 2.0),
		Vector2(-TILE_SIZE / 2.0, TILE_SIZE / 2.0),
	])

	for variant in WALL_ITEM_PATHS:
		var item: ItemData = load(WALL_ITEM_PATHS[variant]) as ItemData
		if item == null:
			push_warning("DungeonWorld: missing wall item resource %s" % WALL_ITEM_PATHS[variant])
			continue
		var cell: Dictionary = _add_icon_source(ts, item.icon)
		if cell.is_empty():
			push_warning("DungeonWorld: '%s' has no icon set — wall tile will be invisible" % item.item_name)
			continue
		var src: TileSetAtlasSource = ts.get_source(cell["source"]) as TileSetAtlasSource
		var td: TileData = src.get_tile_data(cell["coord"], 0)
		td.add_collision_polygon(0)
		td.set_collision_polygon_points(0, 0, poly)
		_wall_cells[variant] = cell

	for path in FLOOR_ITEM_PATHS:
		var item: ItemData = load(path) as ItemData
		if item == null or item.icon == null:
			continue
		var cell: Dictionary = _add_icon_source(ts, item.icon)
		if not cell.is_empty():
			_floor_cells.append(cell)
	if _floor_cells.is_empty():
		push_warning("DungeonWorld: no dungeon_floor item has an icon set — floor will be invisible")

	_shared_tile_set = ts
	return ts

# Adds a dedicated 1-tile TileSetAtlasSource for a single ItemData icon —
# each icon is its own AtlasTexture region, so it gets a source sized and
# margined to its EXACT region, with its one tile always at (0,0).
static func _add_icon_source(ts: TileSet, icon: Texture2D) -> Dictionary:
	if icon == null:
		return {}
	var tex: Texture2D
	var region: Rect2
	var atlas_tex := icon as AtlasTexture
	if atlas_tex != null:
		tex    = atlas_tex.atlas
		region = atlas_tex.region
	else:
		tex    = icon
		region = Rect2(Vector2.ZERO, icon.get_size())
	if tex == null:
		return {}
	var src := TileSetAtlasSource.new()
	src.texture             = tex
	src.margins             = Vector2i(region.position.round())
	src.texture_region_size = Vector2i(region.size.round())
	src.create_tile(Vector2i.ZERO)
	var source_id: int = ts.add_source(src)
	return {"source": source_id, "coord": Vector2i.ZERO}

# ── Dungeon lighting ────────────────────────────────────────────────────
func _setup_lighting() -> void:
	var ambient := CanvasModulate.new()
	ambient.color = DUNGEON_AMBIENT_COLOR
	add_child(ambient)

	add_child(_build_glow_environment())

# Glow makes the altars' pulsing PointLight2Ds bloom (their energy clears the
# HDR threshold at the top of each pulse) — scoped to the dungeon world, so a
# future light source in a dungeon blooms for free, no extra wiring needed.
func _build_glow_environment() -> WorldEnvironment:
	var world_env := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode   = Environment.BG_CANVAS  # keep normal 2D rendering, no 3D sky/clear color
	env.glow_enabled       = true
	env.glow_intensity     = 0.9
	env.glow_strength      = 1.1
	env.glow_bloom         = 0.15
	env.glow_hdr_threshold = 0.85
	env.glow_blend_mode    = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	world_env.environment = env
	return world_env
