extends RefCounted
class_name PixieCaveGenerator

# Pure generation logic for one pixie-cave interior (no scene/node work —
# see pixie_cave_world.gd for turning this grid into a TileMapLayer).
#
# Unlike CaveGenerator's organic cellular-automata caverns, a pixie cave is
# a DUNGEON-LIKE layout: a grid of small rooms connected by 2-wide corridors,
# walls made of pixie stone, with crystal ores housed inside the rooms.
# Deterministic from a single int seed (same seed -> identical grid every
# time), matching the rest of world-gen's seeded-RNG convention.

enum Tile { FLOOR, WALL, CRYSTAL_COPPER, CRYSTAL_IRON, CRYSTAL_SILICON, CRYSTAL_DIAMOND, DIORITE, GRANITE }

# Pixie caves come in three sizes, randomly chosen per-cave (seeded).
const CAVE_SIZES: Array = [
	Vector2i(32, 24),
	Vector2i(40, 20),
	Vector2i(20, 16),
]

const ROOM_MIN: int = 5
const ROOM_MAX: int = 8
const ROOM_PLACE_ATTEMPTS: int = 200
const ROOM_BORDER_MARGIN: int = 2   # keep rooms off the map edge
const ROOM_GAP: int = 1             # min wall tiles separating two rooms
const CORRIDOR_THICKNESS: int = 2   # 2-wide so the 33px-tall player fits

const ORES_PER_ROOM_MIN: int = 1
const ORES_PER_ROOM_MAX: int = 3
const DIAMOND_CHANCE: float = 0.05  # whole-cave: 5% to spawn exactly 1 diamond

# Copper/iron/silicon are GUARANTEED to appear at least once each; diamond is
# the 5% gamble. Order is the cycle used to hand ores out across rooms so all
# three guaranteed types show up even in a small cave.
const GUARANTEED_ORES: Array = [Tile.CRYSTAL_COPPER, Tile.CRYSTAL_IRON, Tile.CRYSTAL_SILICON]

var width:  int = 32  # default; overwritten by generate()
var height: int = 24  # default; overwritten by generate()
var grid: Array = []                       # grid[x][y] = Tile enum
var entrance_tile: Vector2i = Vector2i.ZERO
var rooms: Array = []                      # [{"pos": Vector2i, "size": Vector2i}, ...]

func generate(seed_value: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	# Randomly pick one of the three cave sizes (deterministic per seed).
	var size_idx: int = rng.randi_range(0, CAVE_SIZES.size() - 1)
	var chosen_size: Vector2i = CAVE_SIZES[size_idx]
	width  = chosen_size.x
	height = chosen_size.y
	_init_walls()
	_place_rooms(rng)
	_connect_rooms(rng)
	_carve_entrance(rng)
	_place_ores(rng)
	# Diorite / granite veins LAST so the ore layout (and therefore every
	# existing pixie cave) is unchanged.
	_place_stone_variants(rng)

func _init_walls() -> void:
	grid = []
	grid.resize(width)
	for x in range(width):
		var col: Array = []
		col.resize(height)
		for y in range(height):
			col[y] = Tile.WALL
		grid[x] = col

# Keep carving valid, non-overlapping rooms until the attempt budget runs out.
# 200 attempts on a 128x64 grid comfortably yields ~10-16 rooms.
func _place_rooms(rng: RandomNumberGenerator) -> void:
	rooms = []
	for _i in range(ROOM_PLACE_ATTEMPTS):
		var room: Dictionary = _make_room(rng)
		if room.is_empty():
			continue
		if _overlaps_any(room, ROOM_GAP):
			continue
		_carve_room(room)
		rooms.append(room)

func _make_room(rng: RandomNumberGenerator) -> Dictionary:
	var w: int = rng.randi_range(ROOM_MIN, ROOM_MAX)
	var h: int = rng.randi_range(ROOM_MIN, ROOM_MAX)
	var x: int = rng.randi_range(ROOM_BORDER_MARGIN, width - 1 - ROOM_BORDER_MARGIN - w)
	var y: int = rng.randi_range(ROOM_BORDER_MARGIN, height - 1 - ROOM_BORDER_MARGIN - h)
	if x < ROOM_BORDER_MARGIN or y < ROOM_BORDER_MARGIN:
		return {}
	return {"pos": Vector2i(x, y), "size": Vector2i(w, h)}

func _carve_room(room: Dictionary) -> void:
	var p: Vector2i = room["pos"]
	var s: Vector2i = room["size"]
	for x in range(p.x, p.x + s.x):
		for y in range(p.y, p.y + s.y):
			if _in_bounds(Vector2i(x, y)):
				grid[x][y] = Tile.FLOOR

func _room_center(room: Dictionary) -> Vector2i:
	var p: Vector2i = room["pos"]
	var s: Vector2i = room["size"]
	return Vector2i(p.x + s.x / 2, p.y + s.y / 2)

# AABB overlap test with a `gap` border expanded on every side, so two rooms
# never share a wall (always at least `gap` wall tiles between them).
func _overlaps_any(room: Dictionary, gap: int) -> bool:
	var p: Vector2i = room["pos"]
	var s: Vector2i = room["size"]
	for other in rooms:
		var op: Vector2i = (other as Dictionary)["pos"]
		var os: Vector2i = (other as Dictionary)["size"]
		if p.x - gap < op.x + os.x and p.x + s.x + gap > op.x \
				and p.y - gap < op.y + os.y and p.y + s.y + gap > op.y:
			return true
	return false

# Connect rooms in placement order with 2-wide L-shaped corridors (a spanning
# path) — every room reachable from the first, so the cave is one connected
# space, not a scattering of sealed chambers.
func _connect_rooms(rng: RandomNumberGenerator) -> void:
	for i in range(1, rooms.size()):
		var a: Vector2i = _room_center(rooms[i - 1])
		var b: Vector2i = _room_center(rooms[i])
		_carve_corridor(a, b, rng)

func _carve_corridor(a: Vector2i, b: Vector2i, rng: RandomNumberGenerator) -> void:
	# L-shape with a random corner point, like DungeonGenerator.
	var corner: Vector2i = Vector2i(b.x, a.y) if rng.randf() < 0.5 else Vector2i(a.x, b.y)
	_carve_hline(a.x, corner.x, corner.y)
	_carve_vline(corner.y, b.y, corner.x)

func _carve_hline(x0: int, x1: int, y: int) -> void:
	var lo: int = mini(x0, x1)
	var hi: int = maxi(x0, x1)
	for x in range(lo, hi + 1):
		for t in range(CORRIDOR_THICKNESS):
			_carve_floor(Vector2i(x, y + t))

func _carve_vline(y0: int, y1: int, x: int) -> void:
	var lo: int = mini(y0, y1)
	var hi: int = maxi(y0, y1)
	for y in range(lo, hi + 1):
		for t in range(CORRIDOR_THICKNESS):
			_carve_floor(Vector2i(x + t, y))

func _carve_floor(c: Vector2i) -> void:
	if not _in_bounds(c):
		return
	grid[c.x][c.y] = Tile.FLOOR

# The entrance/exit portal sits in the first room; the player spawns 2 tiles
# north of it (see PixieCaveWorld.get_player_spawn_position). Carving a small
# vestibule north of the center guarantees those tiles are open floor even if
# the room is shaped oddly.
func _carve_entrance(rng: RandomNumberGenerator) -> void:
	if rooms.is_empty():
		entrance_tile = Vector2i(width / 2, height / 2)
		_carve_floor(entrance_tile)
		_carve_floor(entrance_tile - Vector2i(0, 1))
		_carve_floor(entrance_tile - Vector2i(0, 2))
		return
	entrance_tile = _room_center(rooms[0])
	for i in range(3):
		_carve_floor(entrance_tile - Vector2i(0, i))

# Crystal ores live INSIDE rooms (each room "houses a crystal ore"). Per room
# 1-3 non-diamond ores; the three guaranteed types are cycled across rooms so
# copper/iron/silicon all appear at least once; diamond is a single 5% roll
# for the whole cave.
func _place_ores(rng: RandomNumberGenerator) -> void:
	if rooms.is_empty():
		return
	var placed_types: Dictionary = {}  # Tile -> true
	var cycle_idx: int = 0
	for room in rooms:
		var count: int = rng.randi_range(ORES_PER_ROOM_MIN, ORES_PER_ROOM_MAX)
		for _i in range(count):
			var ore_type: int = GUARANTEED_ORES[cycle_idx % GUARANTEED_ORES.size()]
			cycle_idx += 1
			if _place_ore_in_room(room, ore_type, rng):
				placed_types[ore_type] = true
	# Backstop: force every guaranteed type to appear at least once.
	for ore_type in GUARANTEED_ORES:
		if not placed_types.has(ore_type):
			var room: Dictionary = rooms[rng.randi_range(0, rooms.size() - 1)]
			_place_ore_in_room(room, ore_type, rng)
	# Diamond: 5% chance, exactly one, anywhere.
	if rng.randf() < DIAMOND_CHANCE:
		var room: Dictionary = rooms[rng.randi_range(0, rooms.size() - 1)]
		_place_ore_in_room(room, Tile.CRYSTAL_DIAMOND, rng)

# ── Diorite / granite veins ─────────────────────────────────────────
# A few small veins of the two stone variants grown inside the pixie cave's
# plain WALL tiles, so ordinary pixie stone stays dominant. Runs AFTER
# _place_ores so the ore layout is untouched.
const STONE_VARIANTS: Array = [
	{"name": "DIORITE", "tile": Tile.DIORITE, "min": 2, "max": 6},
	{"name": "GRANITE", "tile": Tile.GRANITE, "min": 2, "max": 6},
]
const VARIANT_VEINS: int = 3

func _place_stone_variants(rng: RandomNumberGenerator) -> void:
	for _i in range(VARIANT_VEINS):
		var walls: Array = []
		for x in range(1, width - 1):
			for y in range(1, height - 1):
				if grid[x][y] == Tile.WALL:
					walls.append(Vector2i(x, y))
		if walls.is_empty():
			return
		var origin: Vector2i = walls[rng.randi_range(0, walls.size() - 1)]
		var variant: Dictionary = STONE_VARIANTS[rng.randi_range(0, STONE_VARIANTS.size() - 1)]
		var count: int = rng.randi_range(int(variant["min"]), int(variant["max"]))
		var frontier: Array = [origin]
		var seen: Dictionary = {origin: true}
		var placed: int = 0
		while placed < count and not frontier.is_empty():
			var idx: int = rng.randi_range(0, frontier.size() - 1)
			var cur: Vector2i = frontier[idx]
			frontier.remove_at(idx)
			if grid[cur.x][cur.y] != Tile.WALL:
				continue
			grid[cur.x][cur.y] = int(variant["tile"])
			placed += 1
			var dirs: Array = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
			for k in range(dirs.size() - 1, 0, -1):
				var j: int = rng.randi_range(0, k)
				var tmp = dirs[k]
				dirs[k] = dirs[j]
				dirs[j] = tmp
			for d in dirs:
				var n: Vector2i = cur + d
				if n.x < 1 or n.y < 1 or n.x >= width - 1 or n.y >= height - 1 or seen.has(n):
					continue
				seen[n] = true
				frontier.append(n)

# Replace a pixie-stone (WALL) cell adjacent to the room with an ore — ores
# embed in the cave-stone around rooms/corridors and NEVER sit on the walkable
# path. Returns false when no free wall cell is available.
func _place_ore_in_room(room: Dictionary, ore_type: int, rng: RandomNumberGenerator) -> bool:
	var p: Vector2i = room["pos"]
	var s: Vector2i = room["size"]
	var wall_cells: Array = []
	for x in range(p.x - 1, p.x + s.x + 1):
		for y in range(p.y - 1, p.y + s.y + 1):
			var c := Vector2i(x, y)
			if not _in_bounds(c) or grid[x][y] != Tile.WALL:
				continue
			if _adjacent_to_floor(c):
				wall_cells.append(c)
	if wall_cells.is_empty():
		return false
	var c: Vector2i = wall_cells[rng.randi_range(0, wall_cells.size() - 1)]
	grid[c.x][c.y] = ore_type
	return true

# True when the cell borders (4-neighbor) at least one FLOOR tile.
func _adjacent_to_floor(c: Vector2i) -> bool:
	for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var n := c + d
		if n.x < 0 or n.y < 0 or n.x >= width or n.y >= height:
			continue
		if grid[n.x][n.y] == Tile.FLOOR:
			return true
	return false

func _in_bounds(c: Vector2i) -> bool:
	return c.x >= 1 and c.y >= 1 and c.x < width - 1 and c.y < height - 1
