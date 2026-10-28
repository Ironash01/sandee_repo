extends RefCounted
class_name CaveGenerator

# Pure generation logic for one cave's interior — no scene/node work here,
# see cave_world.gd for turning this grid into an actual TileMapLayer.
# Cellular-automata cave carving (organic caverns, not a strict corridor
# maze — see project discussion): random-fill -> smooth -> wall the border
# -> keep only the largest connected floor region (see _connect_main_region)
# -> scatter ore clusters into the remaining wall tiles.
#
# Deterministic from a single int seed (same seed -> identical grid every
# time), matching the rest of world-gen's seeded-RNG convention — every
# random call in here must go through the local `rng`, never the engine's
# global RNG (Array.shuffle(), etc.), or re-entering the same cave would
# produce a different layout each time.

enum Tile { FLOOR, STONE, COPPER, SILICON, IRON, DIAMOND, DIORITE, GRANITE }

const ORE_TYPES: Array = [
	{"name": "COPPER",  "tile": Tile.COPPER,  "chance": 0.50, "min": 5, "max": 10},
	{"name": "SILICON", "tile": Tile.SILICON, "chance": 0.20, "min": 2, "max": 5},
	{"name": "IRON",    "tile": Tile.IRON,    "chance": 0.20, "min": 2, "max": 5},
	{"name": "DIAMOND", "tile": Tile.DIAMOND, "chance": 0.10, "min": 1, "max": 3},
]

# Stone VARIANTS (diorite / granite): small veins grown inside the remaining
# plain STONE so ordinary stone stays the dominant material. Rolled per chunk,
# exactly like ore, but with a lower chance and smaller veins — the brief is
# "small clusters or veins, occasional larger formations, never dominant".
const STONE_VARIANTS: Array = [
	{"name": "DIORITE", "tile": Tile.DIORITE, "chance": 0.5, "min": 4, "max": 14},
	{"name": "GRANITE", "tile": Tile.GRANITE, "chance": 0.5, "min": 4, "max": 14},
]
const VARIANT_CHUNK_CHANCE: float = 0.45

const FILL_PROB:         float = 0.58  # starting fraction of floor (vs. stone) — raised from 0.45 -> 0.50 -> 0.58, still too much stone at 0.50
const SMOOTH_ITERATIONS: int   = 5
# Solid stone layers kept around the generated grid. The camera now pads into
# the surrounding band, so a thick inner wall keeps every edge reading as rock
# instead of exposing a one-tile border.
const BORDER_WALL_TILES: int = 4

# Same chunk-grid idea world.gd uses for the overworld (spawn density,
# debug chunk-border overlay), just a smaller chunk size and driving ore
# placement instead of trees/grass — see _place_ore().
const CHUNK_SIZE: int = 20

var size:          int   = 128
var grid:          Array = []  # grid[x][y] = Tile enum value
var entrance_tile: Vector2i = Vector2i.ZERO
var ore_clusters:  Array = []  # [{"tile": Vector2i, "name": String}, ...]
var chunk_cols:    int   = 0
var chunk_rows:    int   = 0

func generate(seed_value: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	size = 128 if rng.randf() < 0.5 else 256
	chunk_cols = ceili(float(size) / CHUNK_SIZE)
	chunk_rows = chunk_cols  # cave grid is always square
	_random_fill(rng)
	for i in range(SMOOTH_ITERATIONS):
		_smooth()
	_force_border_walls()
	_connect_main_region()
	_place_ore(rng)
	# Diorite / granite veins LAST: _place_ore has already run, so the ore
	# layout (and therefore every existing cave) is byte-for-byte unchanged —
	# the extra rng draws only affect this new pass.
	_place_stone_variants(rng)

func _random_fill(rng: RandomNumberGenerator) -> void:
	grid = []
	grid.resize(size)
	for x in range(size):
		var col: Array = []
		col.resize(size)
		for y in range(size):
			col[y] = Tile.FLOOR if rng.randf() < FILL_PROB else Tile.STONE
		grid[x] = col

func _count_wall_neighbors(x: int, y: int) -> int:
	var count := 0
	for dx in range(-1, 2):
		for dy in range(-1, 2):
			if dx == 0 and dy == 0:
				continue
			var nx := x + dx
			var ny := y + dy
			if nx < 0 or ny < 0 or nx >= size or ny >= size:
				count += 1  # treat the map edge as solid rock
			elif grid[nx][ny] != Tile.FLOOR:
				count += 1
	return count

func _smooth() -> void:
	var new_grid: Array = []
	new_grid.resize(size)
	for x in range(size):
		var col: Array = []
		col.resize(size)
		new_grid[x] = col
	for x in range(size):
		for y in range(size):
			var walls := _count_wall_neighbors(x, y)
			if walls >= 5:
				new_grid[x][y] = Tile.STONE
			elif walls <= 3:
				new_grid[x][y] = Tile.FLOOR
			else:
				new_grid[x][y] = grid[x][y]
	grid = new_grid

func _force_border_walls() -> void:
	for layer in range(BORDER_WALL_TILES):
		var lo: int = layer
		var hi: int = size - 1 - layer
		for x in range(lo, hi + 1):
			grid[x][lo] = Tile.STONE
			grid[x][hi] = Tile.STONE
		for y in range(lo, hi + 1):
			grid[lo][y] = Tile.STONE
			grid[hi][y] = Tile.STONE

# Keeps the LARGEST connected floor region and stones over every other one
# — CA smoothing normally produces several disconnected pockets scattered
# across the map (completely normal), not one single cavern. An earlier
# version flood-filled from one arbitrary seed near bottom-center and threw
# away every OTHER region regardless of size; if that seed happened to land
# in a small pocket, nearly the whole map got stoned over, leaving only a
# cramped sliver near the entrance — "too much stone, can't walk anywhere
# without digging to the edge" was this bug, not a tuning issue.
func _connect_main_region() -> void:
	var regions: Array = _find_floor_regions()
	if regions.is_empty():
		var start: Vector2i = Vector2i(size / 2, size - 1 - BORDER_WALL_TILES)
		grid[start.x][start.y] = Tile.FLOOR
		entrance_tile = start
		_carve_entrance_vestibule()
		return

	var largest: Dictionary = regions[0]
	for r in regions:
		if (r as Dictionary).size() > largest.size():
			largest = r as Dictionary

	for x in range(size):
		for y in range(size):
			if grid[x][y] == Tile.FLOOR and not largest.has(Vector2i(x, y)):
				grid[x][y] = Tile.STONE

	entrance_tile = _closest_in_set(Vector2i(size / 2, size - 2), largest)
	_carve_entrance_vestibule()

# Every connected floor region on the grid, each as a {tile: true}
# membership set, via a flood-fill starting from every not-yet-visited
# floor tile in turn.
func _find_floor_regions() -> Array:
	var visited: Dictionary = {}
	var regions: Array = []
	var dirs := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
	for x in range(size):
		for y in range(size):
			var t := Vector2i(x, y)
			if grid[x][y] != Tile.FLOOR or visited.has(t):
				continue
			var region: Dictionary = {}
			var queue: Array = [t]
			visited[t] = true
			while not queue.is_empty():
				var cur: Vector2i = queue.pop_back()
				region[cur] = true
				for d in dirs:
					var n: Vector2i = cur + d
					if n.x < 0 or n.y < 0 or n.x >= size or n.y >= size or visited.has(n):
						continue
					if grid[n.x][n.y] == Tile.FLOOR:
						visited[n] = true
						queue.append(n)
			regions.append(region)
	return regions

func _closest_in_set(center: Vector2i, region: Dictionary) -> Vector2i:
	var best: Vector2i    = region.keys()[0]
	var best_dist: float  = INF
	for t in region.keys():
		var dist: float = Vector2(t as Vector2i).distance_to(Vector2(center))
		if dist < best_dist:
			best_dist = dist
			best = t
	return best

# CA smoothing can leave entrance_tile as a cramped 1-tile pocket walled in
# on several sides — the player's collision box is nearly as tall as one
# tile, so standing dead-center on a tile with walls immediately above/
# below is enough to wedge them against both simultaneously (reads as
# "can't move at all"). Force a guaranteed-open, single-column vestibule
# running from the entrance 2 tiles north — CaveWorld spawns the player at
# the far (north) end of this, not on the entrance tile itself, with real
# breathing room between them and any wall.
func _carve_entrance_vestibule() -> void:
	for i in range(3):
		var t: Vector2i = entrance_tile - Vector2i(0, i)
		if t.x >= BORDER_WALL_TILES and t.y >= BORDER_WALL_TILES \
				and t.x < size - BORDER_WALL_TILES and t.y < size - BORDER_WALL_TILES:
			grid[t.x][t.y] = Tile.FLOOR

func _roll_ore_type(rng: RandomNumberGenerator) -> Dictionary:
	var roll := rng.randf()
	var cumulative := 0.0
	for ore in ORE_TYPES:
		cumulative += float(ore["chance"])
		if roll <= cumulative:
			return ore
	return ORE_TYPES[0]

# No diamond within this many tiles of the entrance — checked both at
# cluster-origin selection below AND per-tile during growth in
# _grow_cluster (a cluster started just past the boundary could still
# random-walk a tile or two back inside it otherwise).
const DIAMOND_MIN_ENTRANCE_DIST: float = 50.0

# Per CHUNK_SIZE x CHUNK_SIZE chunk (not per-tile or per-fixed-block): any
# chunk that has at least one stone wall tile gets an 80% chance of one ore
# cluster spawning somewhere inside it. Type/size still follow ORE_TYPES'
# weights/ranges exactly as before — only WHERE clusters roll changed, not
# what a roll produces.
const CHUNK_ORE_CHANCE: float = 0.80

func _place_ore(rng: RandomNumberGenerator) -> void:
	ore_clusters = []
	for cx in range(chunk_cols):
		for cy in range(chunk_rows):
			var stone_tiles: Array = _stone_tiles_in_chunk(Vector2i(cx, cy))
			if stone_tiles.is_empty():
				continue
			if rng.randf() >= CHUNK_ORE_CHANCE:
				continue
			var origin: Vector2i = stone_tiles[rng.randi_range(0, stone_tiles.size() - 1)]
			var ore: Dictionary = _roll_ore_type(rng)
			if ore["tile"] == Tile.DIAMOND and _dist_to_entrance(origin) < DIAMOND_MIN_ENTRANCE_DIST:
				continue  # too close to the entrance — drop this chunk's roll rather than relocate it
			var count: int = rng.randi_range(int(ore["min"]), int(ore["max"]))
			_grow_cluster(origin, ore, count, rng)

# Diorite / granite veins. Per chunk, like ore, but a lower chance and a
# smaller vein; grown with the SAME frontier growth (restricted to plain
# STONE), so the shapes read as organic veins instead of blobs.
func _place_stone_variants(rng: RandomNumberGenerator) -> void:
	for cx in range(chunk_cols):
		for cy in range(chunk_rows):
			var stone_tiles: Array = _stone_tiles_in_chunk(Vector2i(cx, cy))
			if stone_tiles.is_empty():
				continue
			if rng.randf() >= VARIANT_CHUNK_CHANCE:
				continue
			var origin: Vector2i = stone_tiles[rng.randi_range(0, stone_tiles.size() - 1)]
			var variant: Dictionary = STONE_VARIANTS[rng.randi_range(0, STONE_VARIANTS.size() - 1)]
			var count: int = rng.randi_range(int(variant["min"]), int(variant["max"]))
			_grow_cluster(origin, variant, count, rng)

func _stone_tiles_in_chunk(chunk: Vector2i) -> Array:
	var result: Array = []
	var x0: int = maxi(chunk.x * CHUNK_SIZE, 1)
	var y0: int = maxi(chunk.y * CHUNK_SIZE, 1)
	var x1: int = mini(x0 + CHUNK_SIZE, size - 1)
	var y1: int = mini(y0 + CHUNK_SIZE, size - 1)
	for x in range(x0, x1):
		for y in range(y0, y1):
			if grid[x][y] == Tile.STONE:
				result.append(Vector2i(x, y))
	return result

func _dist_to_entrance(tile: Vector2i) -> float:
	return Vector2(tile).distance_to(Vector2(entrance_tile))

# Random-walk growth restricted to existing STONE tiles only (ore replaces
# wall material, never floor) — same "frontier + seeded Fisher-Yates" spirit
# world.gd's own grass patch clustering already uses, so cluster shapes read
# as organic veins rather than perfect blobs.
func _grow_cluster(origin: Vector2i, ore: Dictionary, count: int, rng: RandomNumberGenerator) -> void:
	var placed := 0
	var frontier: Array = [origin]
	var visited := {origin: true}
	while placed < count and not frontier.is_empty():
		var idx: int = rng.randi_range(0, frontier.size() - 1)
		var cur: Vector2i = frontier[idx]
		frontier.remove_at(idx)
		if grid[cur.x][cur.y] != Tile.STONE:
			continue
		if ore["tile"] == Tile.DIAMOND and _dist_to_entrance(cur) < DIAMOND_MIN_ENTRANCE_DIST:
			continue  # backstop: skip this tile even though the origin passed the check
		grid[cur.x][cur.y] = ore["tile"]
		placed += 1
		if placed == 1:
			ore_clusters.append({"tile": cur, "name": ore["name"]})

		var dirs: Array = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
		for i in range(dirs.size() - 1, 0, -1):
			var j: int = rng.randi_range(0, i)
			var tmp = dirs[i]
			dirs[i] = dirs[j]
			dirs[j] = tmp
		for d in dirs:
			var n: Vector2i = cur + d
			if n.x < 1 or n.y < 1 or n.x >= size - 1 or n.y >= size - 1 or visited.has(n):
				continue
			visited[n] = true
			if grid[n.x][n.y] == Tile.STONE:
				frontier.append(n)
