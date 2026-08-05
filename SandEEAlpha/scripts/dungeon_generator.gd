extends RefCounted
class_name DungeonGenerator

# Pure generation logic for one dungeon interior — no scene/node work here,
# see dungeon_world.gd for turning this grid into an actual TileMapLayer.
# Dungeons are puzzle spaces, so this is a room-and-corridor layout (NOT the
# organic cellular-automata caverns CaveGenerator carves):
#   - a guaranteed knowledge room (holds the mission's KnowledgeAltar)
#   - a guaranteed quiz room placed far from it (holds the QuizAltar — the
#     quiz is always the LAST room in the walkable path)
#   - a few bonus rooms for path variety
#   - straight L-shaped corridors connecting knowledge -> bonuses -> quiz
#   - an entrance corridor carved from the knowledge room to the nearest
#     grid edge so the dungeon reads as having a mouth
#
# Deterministic from a single int seed (same seed -> identical grid every
# time), matching the rest of world-gen's seeded-RNG convention — every
# random call in here must go through the local `rng`, never the engine's
# global RNG (Array.shuffle(), etc.). The seed itself is rolled once on the
# first mission accept and stored in Global.dungeon_seeds, so a dungeon's
# layout is fixed from then on.

enum Tile { WALL, FLOOR }

# One dungeon is randomly one of these (width x height, tiles), rolled from the
# dungeon's own seeded rng inside generate() — so the same dungeon always has
# the same size, matching the seeded-layout convention.
const DUNGEON_SIZES: Array = [
	Vector2i(64, 128),
	Vector2i(128, 256),
	Vector2i(256, 256),
]

var width:  int = 64
var height: int = 128

const ROOM_MIN: int = 6
const ROOM_MAX: int = 8

# The quiz room must sit this far (center-to-center) from the knowledge room
# so the dungeon isn't trivially short.
const QUIZ_MIN_SEPARATION: float = 20.0
# Bonus rooms stay at least this far from both fixed rooms.
const BONUS_MIN_DIST:  float = 10.0
const BONUS_ATTEMPTS:  int   = 10
const ROOM_PLACE_ATTEMPTS: int = 200  # quiz-room repositioning tries

var grid:                Array     = []  # grid[x][y] = Tile enum value
var knowledge_room:      Dictionary = {} # {"pos": Vector2i, "size": Vector2i}
var quiz_room:           Dictionary = {}
var knowledge_altar_pos: Vector2i = Vector2i.ZERO
var quiz_altar_pos:      Vector2i = Vector2i.ZERO
var player_spawn_pos:    Vector2i = Vector2i.ZERO

func generate(seed_value: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value

	var sz: Vector2i = DUNGEON_SIZES[rng.randi_range(0, DUNGEON_SIZES.size() - 1)]
	width  = sz.x
	height = sz.y

	grid = []
	grid.resize(width)
	for x in range(width):
		var col: Array = []
		col.resize(height)
		for y in range(height):
			col[y] = Tile.WALL
		grid[x] = col

	knowledge_room = _make_room(rng)
	_carve_room(knowledge_room)

	quiz_room = _make_room(rng)
	var attempts := 0
	while _center_dist(quiz_room, knowledge_room) < QUIZ_MIN_SEPARATION and attempts < ROOM_PLACE_ATTEMPTS:
		quiz_room = _make_room(rng)
		attempts += 1
	_carve_room(quiz_room)

	# Bonus rooms: skip ones that collide with an existing room or crowd the
	# two fixed rooms.
	var all_rooms: Array = [knowledge_room, quiz_room]
	var bonus: Array = []
	for i in range(BONUS_ATTEMPTS):
		var room := _make_room(rng)
		if _overlaps_any(room, all_rooms):
			continue
		if _center_dist(room, knowledge_room) < BONUS_MIN_DIST \
				or _center_dist(room, quiz_room) < BONUS_MIN_DIST:
			continue
		_carve_room(room)
		all_rooms.append(room)
		bonus.append(room)

	# The quiz is always LAST — connect knowledge -> bonuses -> quiz so the
	# player's path flows toward the quiz and never beyond it.
	var path_rooms: Array = [knowledge_room]
	path_rooms.append_array(bonus)
	path_rooms.append(quiz_room)
	for i in range(path_rooms.size() - 1):
		_carve_corridor(path_rooms[i], path_rooms[i + 1], rng)

	knowledge_altar_pos = _room_center(knowledge_room)
	quiz_altar_pos      = _room_center(quiz_room)
	player_spawn_pos    = knowledge_altar_pos + Vector2i(0, 2)
	_carve_entrance()

func _make_room(rng: RandomNumberGenerator) -> Dictionary:
	var w := rng.randi_range(ROOM_MIN, ROOM_MAX)
	var h := rng.randi_range(ROOM_MIN, ROOM_MAX)
	# Margins keep rooms off the border walls (index 0 / width-1 / height-1)
	# with room to spare for an entrance corridor.
	var x := rng.randi_range(2, width - w - 3)
	var y := rng.randi_range(2, height - h - 3)
	return {"pos": Vector2i(x, y), "size": Vector2i(w, h)}

func _carve_room(room: Dictionary) -> void:
	var p: Vector2i = room["pos"]
	var s: Vector2i = room["size"]
	for x in range(p.x, p.x + s.x):
		for y in range(p.y, p.y + s.y):
			grid[x][y] = Tile.FLOOR

func _room_center(room: Dictionary) -> Vector2i:
	var p: Vector2i = room["pos"]
	var s: Vector2i = room["size"]
	return p + Vector2i(s.x / 2, s.y / 2)

func _center_dist(a: Dictionary, b: Dictionary) -> float:
	return Vector2(_room_center(a)).distance_to(Vector2(_room_center(b)))

# True if `room` overlaps (with a 1-tile wall gap) any room in `rooms`.
func _overlaps_any(room: Dictionary, rooms: Array) -> bool:
	var pa: Vector2i = room["pos"]
	var sa: Vector2i = room["size"]
	for other in rooms:
		var pb: Vector2i = other["pos"]
		var sb: Vector2i = other["size"]
		if pa.x - 1 < pb.x + sb.x and pa.x + sa.x + 1 > pb.x \
				and pa.y - 1 < pb.y + sb.y and pa.y + sa.y + 1 > pb.y:
			return true
	return false

# L-shaped corridor (horizontal then vertical, with a random corner point)
# between two room centers — axis-aligned segments only, so it never leaves
# the rooms' bounding box or overshoots. Every pass is carved 2 tiles thick
# (_carve_thick_line): the player's collision box is 20x33 on a 32px grid —
# TALLER than one tile — so 1-wide corridors between walls were impassable
# (the "can't walk through some floors between walls" playtest report). 2-wide
# passages give the 33px box comfortable clearance in every direction.
func _carve_corridor(a: Dictionary, b: Dictionary, rng: RandomNumberGenerator) -> void:
	var pa := _room_center(a)
	var pb := _room_center(b)
	var corner := Vector2i(
		rng.randi_range(mini(pa.x, pb.x), maxi(pa.x, pb.x)),
		rng.randi_range(mini(pa.y, pb.y), maxi(pa.y, pb.y)))
	_carve_thick_line(pa, Vector2i(corner.x, pa.y))
	_carve_thick_line(Vector2i(corner.x, pa.y), pb)

func _carve_thick_line(from: Vector2i, to: Vector2i) -> void:
	var t := from
	_carve_floor_block(t)
	while t.x != to.x:
		t.x += signi(to.x - t.x)
		_carve_floor_block(t)
	while t.y != to.y:
		t.y += signi(to.y - t.y)
		_carve_floor_block(t)

# Marks a 2x2 block of tiles (anchored at c, expanding toward +x/+y) as floor,
# so every carved passage is at least 2 tiles wide everywhere the player walks.
func _carve_floor_block(c: Vector2i) -> void:
	for dx in [0, 1]:
		for dy in [0, 1]:
			var p := c + Vector2i(dx, dy)
			if p.x >= 0 and p.y >= 0 and p.x < width and p.y < height:
				grid[p.x][p.y] = Tile.FLOOR

# Carve a straight corridor from the knowledge room to the nearest grid edge
# — a visual "mouth" so the dungeon reads as having an entrance. The border
# wall itself is left intact.
func _carve_entrance() -> void:
	var center: Vector2i = _room_center(knowledge_room)
	var best_edge := ""
	var best_dist := maxi(width, height)
	for edge in ["left", "right", "up", "down"]:
		var d := _edge_dist(center, edge)
		if d < best_dist:
			best_dist = d
			best_edge = edge
	var step := _edge_step(best_edge)
	# range stops one short of the wall cap: each _carve_floor_block expands
	# +x/+y, so the final block would otherwise eat into the border wall.
	for i in range(1, best_dist - 1):
		_carve_floor_block(center + step * i)

func _edge_dist(center: Vector2i, edge: String) -> int:
	match edge:
		"left":  return center.x
		"right": return width - 1 - center.x
		"up":    return center.y
		_:       return height - 1 - center.y

func _edge_step(edge: String) -> Vector2i:
	match edge:
		"left":  return Vector2i(-1, 0)
		"right": return Vector2i(1, 0)
		"up":    return Vector2i(0, -1)
		_:       return Vector2i(0, 1)
