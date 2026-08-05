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
# the QuizAltar in the final room, bright uniform lighting (no flashlight),
# and a whole-layout minimap (see _setup_minimap) that only exists in dungeons.
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
		_area.collision_mask  = 1
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
		var fsize: int = 8
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

func setup(dungeon_index: int, mission: DungeonMissionData, seed_value: int,
		overworld: Node2D, return_position: Vector2) -> void:
	_dungeon_index = dungeon_index
	_mission       = mission
	_overworld     = overworld
	overworld_return_position = return_position

	generator = DungeonGenerator.new()
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
	_spawn_exit_marker()
	_setup_lighting()
	_setup_minimap()

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

func get_player_spawn_pos() -> Vector2:
	return _tilemap.to_global(_tilemap.map_to_local(_grid_to_cell(generator.player_spawn_pos)))

# Generator grid indices run 0..width-1 / 0..height-1; centering the map on
# the origin (matching the overworld/cave convention) means every grid->cell
# conversion needs this same per-axis offset.
func _grid_to_cell(tile: Vector2i) -> Vector2i:
	return tile - Vector2i(generator.width / 2, generator.height / 2)

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

# ── Dungeon minimap (whole-layout map, left side, dungeons only) ────────
# A small always-on panel rendering the ENTIRE dungeon grid: walls as filled
# cells, walkable floor dim, knowledge (cyan) / quiz (purple) altars and the
# EXIT (gold, once active) as dots, and the player as a bright dot. Owned by
# this world — a child of DungeonWorld — so it appears ONLY while inside a
# dungeon and is freed automatically on exit_dungeon().
class DungeonMinimap:
	extends Control

	const PAD:          float = 10.0
	const MAX_MAP_PX:   float = 448.0  # cap for the widest 256-cell dimension
	const C_BG:        Color = Color(0.04, 0.05, 0.09, 0.78)
	const C_BORDER:    Color = Color(0.40, 0.30, 0.70, 0.9)
	const C_WALL:      Color = Color(0.38, 0.33, 0.48, 1.0)
	const C_FLOOR:     Color = Color(0.13, 0.14, 0.18, 1.0)
	const C_KNOWLEDGE: Color = Color(0.30, 0.80, 0.95, 1.0)
	const C_QUIZ:      Color = Color(0.80, 0.45, 0.95, 1.0)
	const C_EXIT:      Color = Color(0.90, 0.75, 0.25, 1.0)
	const C_PLAYER:    Color = Color(0.96, 0.96, 1.00, 1.0)

	var world: DungeonWorld = null
	var _px: float = 4.0  # pixels per grid cell, shrinks for big dungeons

	func _init(w: DungeonWorld) -> void:
		world = w
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		var g: DungeonGenerator = world.generator
		if g != null:
			_px = minf(4.0, MAX_MAP_PX / maxi(g.width, g.height))
		var map_px := Vector2(world.generator.width, world.generator.height) * _px
		position = Vector2(16, 26)
		size     = map_px + Vector2(PAD, PAD) * 2.0

	func _process(_delta: float) -> void:
		queue_redraw()

	func _draw() -> void:
		if world == null or world.generator == null:
			return
		var g: DungeonGenerator = world.generator
		draw_rect(Rect2(Vector2.ZERO, size), C_BG)
		draw_rect(Rect2(Vector2.ZERO, size), C_BORDER, false, 2.0)

		for x in range(g.width):
			for y in range(g.height):
				var wall: bool = g.grid[x][y] == DungeonGenerator.Tile.WALL
				var cell_rect := Rect2(PAD + x * _px, PAD + y * _px, _px, _px)
				draw_rect(cell_rect, C_WALL if wall else C_FLOOR)

		var dot_r := _px * 0.5 + 0.5
		_draw_marker(g.knowledge_altar_pos, C_KNOWLEDGE, dot_r)
		_draw_marker(g.quiz_altar_pos, C_QUIZ, dot_r)
		if world._exit_marker != null and world._exit_marker._active:
			_draw_marker(g.quiz_altar_pos + Vector2i(0, 2), C_EXIT, dot_r)

		var player: Node2D = Global.player_node as Node2D
		if player != null:
			_draw_marker(_grid_from_world(player.global_position), C_PLAYER, dot_r + 1.0)

	func _draw_marker(grid_pos: Vector2i, color: Color, r: float) -> void:
		var center := Vector2(PAD, PAD) + Vector2(grid_pos) * _px + Vector2(_px, _px) * 0.5
		draw_circle(center, r, color)

	# World position -> generator grid coords (inverse of _grid_to_cell).
	func _grid_from_world(world_pos: Vector2) -> Vector2i:
		if world == null or world._tilemap == null:
			return Vector2i.ZERO
		var cell: Vector2i = world._tilemap.local_to_map(world._tilemap.to_local(world_pos))
		return cell + Vector2i(world.generator.width / 2, world.generator.height / 2)

func _setup_minimap() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 4
	layer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(layer)

	var title := Label.new()
	title.text = "Dungeon Map"
	title.position = Vector2(18, 8)
	title.add_theme_font_size_override("font_size", 12)
	title.add_theme_color_override("font_color", Color(0.80, 0.70, 1.00, 0.9))
	layer.add_child(title)

	var map := DungeonMinimap.new(self)
	map.process_mode = Node.PROCESS_MODE_ALWAYS
	layer.add_child(map)
