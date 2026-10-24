extends RefCounted
class_name DungeonGenerator

# Pure generation logic for one dungeon interior — no scene/node work here,
# see dungeon_world.gd for turning this grid into an actual TileMapLayer.
# Dungeons are puzzle spaces, so this is a room-and-corridor layout (NOT the
# organic cellular-automata caverns CaveGenerator carves):
#   - a guaranteed knowledge room (holds the mission's KnowledgeAltar)
#   - a guaranteed quiz room placed far from it (holds the QuizAltar — the
#     quiz is always the LAST room in the walkable path)
#   - a guaranteed ENTRANCE room at the grid edge nearest the knowledge room:
#     the player always spawns INSIDE a real room, never in the 2-wide entrance
#     corridor (see _make_entrance_room)
#   - one room per extra altar + one room per chest, from the mission's
#     altar_amount / chest_amount fields (nothing else drives room count)
#   - straight L-shaped corridors connecting entrance -> knowledge -> rooms -> quiz
#   - a short "mouth" corridor carved from the entrance room to the nearest
#     grid edge so the dungeon reads as having an entrance
#
# The dungeon grid SIZE comes only from the mission's size_modifier dropdown
# (64x64 / 128x128 / 256x256); with no mission (-1) one is rolled randomly.
#
# Deterministic from a single int seed (same seed -> identical grid every
# time), matching the rest of world-gen's seeded-RNG convention — every
# random call in here must go through the local `rng`, never the engine's
# global RNG (Array.shuffle(), etc.). The seed itself is rolled once on the
# first mission accept and stored in Global.dungeon_seeds, so a dungeon's
# layout is fixed from then on.

enum Tile { WALL, FLOOR }

# Grid dimensions per size_modifier tier (index 0/1/2 in the mission's
# "64x64"/"128x128"/"256x256" dropdown).
const DUNGEON_SIZES: Array = [
	Vector2i(64, 64),
	Vector2i(128, 128),
	Vector2i(256, 256),
]

var width:  int = 64
var height: int = 64

const ROOM_MIN: int = 6
const ROOM_MAX: int = 8
# Rooms keep this many tiles of wall between them and the grid edge. The camera
# also pads into that wall band (see DungeonWorld.CAMERA_WALL_PADDING_TILES),
# so the player can be centred near the entrance instead of the camera locking.
const ROOM_EDGE_MARGIN: int = 6
# Traps stay this far (Chebyshev) outside every room, and this far from the
# player spawn, so corridor thresholds and entrances cannot be blocked.
const TRAP_ROOM_CLEARANCE: int = 2
const TRAP_SPAWN_CLEARANCE: float = 4.0
# Only place traps where the corridor is at least 2 tiles wide / a junction
# (a 1-wide passage has just 2 floor neighbours and is excluded).
const TRAP_MIN_FLOOR_NEIGHBOURS: int = 3

# The quiz room must sit this far (center-to-center) from the knowledge room
# so the dungeon isn't trivially short.
const QUIZ_MIN_SEPARATION: float = 20.0
# Bonus rooms stay at least this far from both fixed rooms.
const BONUS_MIN_DIST:  float = 10.0
const BONUS_ATTEMPTS:  int   = 10
const ROOM_PLACE_ATTEMPTS: int = 200  # quiz-room repositioning tries
# Minimum length (tiles) of a straight corridor run between turns. Corridors
# zig-zag (more corners) but keep runs this long — long straight streaks are
# exactly what the Hitman's ram attack needs (see hitman.gd CHARGE_MAX_DIST).
const CORRIDOR_MIN_RUN: int = 6

var grid:                Array     = []  # grid[x][y] = Tile enum value
var knowledge_room:      Dictionary = {} # {"pos": Vector2i, "size": Vector2i}
var quiz_room:           Dictionary = {}
## Two-room Hitman finale: entrance room + boss arena. Only populated by
## generate_boss(); ordinary dungeons leave it empty.
var boss_room:           Dictionary = {}
var boss_spawn_pos:      Vector2i = Vector2i.ZERO
# The player's spawn room, always against the grid edge nearest the knowledge
# room (see _make_entrance_room). player_spawn_pos is its center.
var entrance_room:       Dictionary = {}
var knowledge_altar_pos: Vector2i = Vector2i.ZERO
var quiz_altar_pos:      Vector2i = Vector2i.ZERO
var player_spawn_pos:    Vector2i = Vector2i.ZERO
# Wall cells chosen to host a DungeonFlare obstacle (dungeon_world spawns
# one node per entry). Kept as Tile.WALL in the grid so the wall art and
# collision are unchanged — see _pick_flare_positions().
var flare_positions:     Array     = []
# Corridor FLOOR cells chosen to host a persistent DungeonTrap (dungeon_world
# spawns one node per entry). Unlike flares these are WALKABLE tiles the player
# steps on — see _pick_trap_positions().
var trap_positions:      Array     = []
# Corridor-mouth cells of the KNOWLEDGE room — the only SAFE altar room.
# dungeon_world puts a safe-zone marker on each (see _pick_gap_positions). The
# quiz room is NOT safe: the player must defeat its hitman guards.
var gap_positions:        Array     = []  # [Vector2i, ...]
# 4 walkable cells inside the quiz room where hitman guards spawn.
var quiz_guard_positions: Array     = []
# Up to 8 cells ringing the quiz altar (2 gaps left open to walk through);
# dungeon_world spawns a DungeonTrap on each.
var quiz_trap_positions:  Array     = []

# altar_amount counts the altar/checkpoint rooms INCLUDING the first knowledge
# room; chest_amount is pure extra loot rooms. The quiz room is always the
# final room on top of those. bonus_count therefore = (altar_amount - 1) + chest_amount.
var bonus_count: int = 0
# Bonus rooms are deliberately empty loot rooms. A rare chest may occupy one
# of them; at most one per dungeon, and only on a low deterministic roll.
var bonus_rooms:    Array = []
var rare_chest_positions: Array = []
const RARE_CHEST_CHANCE: float = 0.18
const RARE_CHEST_ROOM_CLEARANCE: int = 2

# Neither the knowledge nor the quiz altar may sit within this many tiles of the
# player's entrance spawn. generate() retries with a bumped seed until both clear.
const ALTAR_SPAWN_MIN_DIST: float = 10.0
const ALTAR_SPAWN_ATTEMPTS: int = 8
# No corridor traps within this many tiles (Chebyshev, measured outside the room
# rect) of the SAFE room — the knowledge altar room. Its entrances must stay a
# genuine breather, so the safe-zone ring is trap-free.
const SAFE_TRAP_CLEARANCE: int = 5

func generate(seed_value: int, size_tier: int = -1, altar_amount: int = 1, chest_amount: int = 0) -> void:
	# Retry with a bumped seed until BOTH altars are far enough from the spawn.
	for attempt in range(ALTAR_SPAWN_ATTEMPTS):
		_generate_once(seed_value + attempt, size_tier, altar_amount, chest_amount)
		var spawn := Vector2(player_spawn_pos)
		var kd: float = Vector2(_room_center(knowledge_room)).distance_to(spawn)
		var qd: float = Vector2(_room_center(quiz_room)).distance_to(spawn)
		if kd >= ALTAR_SPAWN_MIN_DIST and qd >= ALTAR_SPAWN_MIN_DIST:
			return

# Deterministic two-room finale: one safe entrance room and one large boss
# arena joined by a clear 2-wide corridor. No bonus rooms, altars, traps,
# flares, guards, or rare-chest rolls are generated.
func generate_boss(seed_value: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	width = 64
	height = 64
	bonus_count = 0
	bonus_rooms = []
	rare_chest_positions = []
	flare_positions = []
	trap_positions = []
	gap_positions = []
	quiz_guard_positions = []
	quiz_trap_positions = []

	grid = []
	grid.resize(width)
	for x in range(width):
		var col: Array = []
		col.resize(height)
		for y in range(height):
			col[y] = Tile.WALL
		grid[x] = col

	entrance_room = {"pos": Vector2i(8, 27), "size": Vector2i(10, 10)}
	boss_room = {"pos": Vector2i(38, 23), "size": Vector2i(18, 18)}
	_carve_room(entrance_room)
	_carve_room(boss_room)
	_carve_thick_line(_room_center(entrance_room), _room_center(boss_room))
	player_spawn_pos = _room_center(entrance_room)
	boss_spawn_pos = _room_center(boss_room)
	knowledge_room = {}
	quiz_room = boss_room
	knowledge_altar_pos = Vector2i.ZERO
	quiz_altar_pos = boss_spawn_pos
	_carve_mouth()


func _generate_once(seed_value: int, size_tier: int, altar_amount: int, chest_amount: int) -> void:
	boss_room = {}
	boss_spawn_pos = Vector2i.ZERO
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value

	var sz: Vector2i
	if size_tier >= 0 and size_tier < DUNGEON_SIZES.size():
		sz = DUNGEON_SIZES[size_tier]
	else:
		sz = DUNGEON_SIZES[rng.randi_range(0, DUNGEON_SIZES.size() - 1)]
	width  = sz.x
	height = sz.y

	bonus_count = maxi(0, altar_amount - 1) + chest_amount

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

	# The ENTRANCE room — where the player spawns. Always carved so the spawn is
	# inside a real room, not in the 2-wide entrance corridor.
	entrance_room = _make_entrance_room(rng)
	_carve_room(entrance_room)

	# Rooms beyond the two fixed ones: their COUNT depends only on the mission's
	# altar_amount + chest_amount (see bonus_count). Keep placing until we hit
	# that target, skipping ones that collide with an existing room or crowd the
	# two fixed rooms. Attempts scale with the target so dense layouts (many
	# chests on a 64x64 grid) still get a fair chance to fill up.
	var all_rooms: Array = [knowledge_room, quiz_room, entrance_room]
	var bonus: Array = []
	var placed := 0
	var attempts_total: int = maxi(BONUS_ATTEMPTS, bonus_count * 30)
	for i in range(attempts_total):
		if placed >= bonus_count:
			break
		var room := _make_room(rng)
		if _overlaps_any(room, all_rooms):
			continue
		if _center_dist(room, knowledge_room) < BONUS_MIN_DIST \
				or _center_dist(room, quiz_room) < BONUS_MIN_DIST:
			continue
		_carve_room(room)
		all_rooms.append(room)
		bonus.append(room)
		placed += 1
	bonus_rooms = bonus.duplicate()
	if placed < bonus_count:
		push_warning("DungeonGenerator: placed %d/%d rooms (altar_amount=%d chest_amount=%d on %dx%d grid)" \
			% [placed, bonus_count, altar_amount, chest_amount, width, height])

	# The quiz is always LAST — connect knowledge -> bonuses -> quiz so the
	# player's path flows toward the quiz and never beyond it. The entrance room
	# links to the knowledge room (the first room the player reaches).
	var path_rooms: Array = [knowledge_room]
	path_rooms.append_array(bonus)
	path_rooms.append(quiz_room)
	for i in range(path_rooms.size() - 1):
		_carve_corridor(path_rooms[i], path_rooms[i + 1], rng)
	_carve_corridor(entrance_room, knowledge_room, rng)

	knowledge_altar_pos = _room_center(knowledge_room)
	quiz_altar_pos      = _room_center(quiz_room)
	# The player spawns in the MIDDLE of the entrance room — never in a corridor.
	player_spawn_pos    = _room_center(entrance_room)
	_carve_mouth()
	_pick_flare_positions(rng)
	_pick_trap_positions(rng, all_rooms)
	_pick_gap_positions()
	_pick_quiz_guards(rng)
	_pick_quiz_traps()
	# Runs last so the optional rare-chest roll cannot change the dungeon
	# layout/room/corridor placement above.
	_pick_rare_chest_position(rng)

# Wall tiles that face a walkable FLOOR cell become flare host cells. They
# stay WALL in the grid (collision + wall-variant art untouched); the world
# just spawns a DungeonFlare node on top of them.
func _pick_flare_positions(rng: RandomNumberGenerator) -> void:
	flare_positions = []
	var wanted: int = clampi((width * height) / 900, 3, 12)
	var candidates: Array = []
	for x in range(1, width - 1):
		for y in range(1, height - 1):
			if grid[x][y] != Tile.WALL:
				continue
			if grid[x - 1][y] == Tile.FLOOR or grid[x + 1][y] == Tile.FLOOR \
					or grid[x][y - 1] == Tile.FLOOR or grid[x][y + 1] == Tile.FLOOR:
				candidates.append(Vector2i(x, y))
	for i in range(wanted):
		if candidates.is_empty():
			break
		var idx: int = rng.randi_range(0, candidates.size() - 1)
		flare_positions.append(candidates[idx])
		candidates.remove_at(idx)

# Corridor FLOOR cells (walkable tiles NOT inside any room) chosen to host a
# persistent DungeonTrap. Spaced apart so traps don't cluster into a wall of
# explosions, and kept clear of the safe (knowledge) room so the trap-free
# breather around the safe zone is preserved. `rooms` is every room rect
# (knowledge + quiz + bonus).
func _pick_trap_positions(rng: RandomNumberGenerator, rooms: Array) -> void:
	trap_positions = []
	var wanted: int = clampi((width * height) / 1000, 6, 14)
	var candidates: Array = []
	for x in range(1, width - 1):
		for y in range(1, height - 1):
			if grid[x][y] != Tile.FLOOR:
				continue
			if _cell_in_any_room(Vector2i(x, y), rooms):
				continue
			# Safe-zone clearance: no traps around the knowledge altar room.
			if _dist_to_room(Vector2i(x, y), knowledge_room) <= SAFE_TRAP_CLEARANCE:
				continue
			var cell := Vector2i(x, y)
			# No traps near ANY room mouth/threshold.
			var near_room := false
			for room in rooms:
				if _dist_to_room(cell, room) <= TRAP_ROOM_CLEARANCE:
					near_room = true
					break
			if near_room:
				continue
			# Keep the entrance spawn corridor clear.
			if Vector2(cell).distance_to(Vector2(player_spawn_pos)) < TRAP_SPAWN_CLEARANCE:
				continue
			# 1-wide passages are too easy to soft-lock with knockback.
			if _floor_neighbours(cell) < TRAP_MIN_FLOOR_NEIGHBOURS:
				continue
			candidates.append(cell)
	var min_sep: float = 4.0
	for i in range(wanted):
		if candidates.is_empty():
			break
		var chosen: int = -1
		for _try in range(30):
			var idx: int = rng.randi_range(0, candidates.size() - 1)
			var c: Vector2i = candidates[idx]
			var ok := true
			for t in trap_positions:
				if Vector2(c).distance_to(Vector2(t as Vector2i)) < min_sep:
					ok = false
					break
			if ok:
				chosen = idx
				break
		if chosen < 0:
			chosen = rng.randi_range(0, candidates.size() - 1)
		trap_positions.append(candidates[chosen])
		candidates.remove_at(chosen)

# Safe-zone gaps: every walkable ring cell of the KNOWLEDGE room that opens into
# it (a corridor mouth). Rooms can have several corridors, so all such cells are
# collected. The quiz room is deliberately NOT a safe zone.
func _pick_gap_positions() -> void:
	gap_positions = []
	var room: Dictionary = knowledge_room
	var p: Vector2i = room["pos"]
	var s: Vector2i = room["size"]
	var dirs: Array = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
	for x in range(p.x - 1, p.x + s.x + 1):
		for y in range(p.y - 1, p.y + s.y + 1):
			var c := Vector2i(x, y)
			if _cell_in_room(c, room):
				continue
			if not _in_bounds(c) or grid[c.x][c.y] != Tile.FLOOR:
				continue
			# Must orthogonally touch the room: a walkable cell inside the rect
			# right next to it. (Diagonal corners can't match, so a corner cell
			# never gets picked.)
			for d in dirs:
				var n: Vector2i = c + d
				if not _in_bounds(n) or grid[n.x][n.y] != Tile.FLOOR:
					continue
				if not _cell_in_room(n, room):
					continue
				gap_positions.append(c)
				break

# Exactly two walkable cells ringing the quiz altar for hitman guards.
func _pick_quiz_guards(rng: RandomNumberGenerator) -> void:
	quiz_guard_positions = []
	var c := quiz_altar_pos
	var r := 2
	var count: int = 2
	for i in range(8):
		if quiz_guard_positions.size() >= count:
			break
		var ang := TAU * float(i) / 8.0
		var cell := c + Vector2i(roundi(cos(ang) * r), roundi(sin(ang) * r))
		if not _in_bounds(cell) or grid[cell.x][cell.y] != Tile.FLOOR:
			continue
		if cell in quiz_guard_positions:
			continue
		quiz_guard_positions.append(cell)

# Up to 8 traps ringing the quiz altar, with 2 opposite gaps left open so the
# player can walk through.
func _floor_neighbours(cell: Vector2i) -> int:
	var count := 0
	for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var n: Vector2i = cell + d
		if _in_bounds(n) and grid[n.x][n.y] == Tile.FLOOR:
			count += 1
	return count

# True when `cell` is a floor cell just inside `room` that touches a floor cell
# outside the room (a corridor opening). Never place a quiz trap there.
func _touches_room_opening(cell: Vector2i, room: Dictionary) -> bool:
	for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var n: Vector2i = cell + d
		if _cell_in_room(n, room):
			continue
		if _in_bounds(n) and grid[n.x][n.y] == Tile.FLOOR:
			return true
	return false

func _pick_quiz_traps() -> void:
	quiz_trap_positions = []
	var c := quiz_altar_pos
	var r := 3
	var samples := 10
	var gap_a := 0
	var gap_b := samples / 2
	var seen: Dictionary = {}
	for i in range(samples):
		var ang := TAU * float(i) / float(samples)
		var cell := c + Vector2i(roundi(cos(ang) * r), roundi(sin(ang) * r))
		if seen.has(cell):
			continue
		seen[cell] = true
		if not _in_bounds(cell) or grid[cell.x][cell.y] != Tile.FLOOR:
			continue
		if i == gap_a or i == gap_b:
			continue   # walk-through gap
		if _touches_room_opening(cell, quiz_room):
			continue   # corridor threshold: never trap it
		quiz_trap_positions.append(cell)

# Safe altar room: the KNOWLEDGE room only. The quiz room is NOT safe — its
# hitman guards must be defeated.
func is_safe_room_cell(cell: Vector2i) -> bool:
	return _cell_in_room(cell, knowledge_room)

func _cell_in_room(cell: Vector2i, room: Dictionary) -> bool:
	var p: Vector2i = room["pos"]
	var s: Vector2i = room["size"]
	return cell.x >= p.x and cell.x < p.x + s.x and cell.y >= p.y and cell.y < p.y + s.y

func _in_bounds(c: Vector2i) -> bool:
	return c.x >= 0 and c.y >= 0 and c.x < width and c.y < height

# Optional rare chest in one of the otherwise-empty bonus rooms. The roll is a
# single low-probability check per dungeon; candidates need a clear 3x3 floor
# patch two tiles inside the room and cannot share a tile with any generated
# feature (altars, guards, traps, spawn, corridor gaps).
func _pick_rare_chest_position(rng: RandomNumberGenerator) -> void:
	rare_chest_positions = []
	if bonus_rooms.is_empty() or rng.randf() >= RARE_CHEST_CHANCE:
		return
	var reserved: Dictionary = {}
	for cell in [player_spawn_pos, knowledge_altar_pos, quiz_altar_pos]:
		reserved[cell] = true
	for arr in [gap_positions, quiz_guard_positions, quiz_trap_positions,
			trap_positions, flare_positions]:
		for cell in (arr as Array):
			reserved[cell as Vector2i] = true
	var rooms: Array = bonus_rooms.duplicate()
	for i in range(rooms.size() - 1, 0, -1):
		var j: int = rng.randi_range(0, i)
		var tmp: Variant = rooms[i]
		rooms[i] = rooms[j]
		rooms[j] = tmp
	for room_value in rooms:
		var room: Dictionary = room_value as Dictionary
		var p: Vector2i = room["pos"]
		var sz: Vector2i = room["size"]
		var candidates: Array = []
		for x in range(p.x + RARE_CHEST_ROOM_CLEARANCE, p.x + sz.x - RARE_CHEST_ROOM_CLEARANCE):
			for y in range(p.y + RARE_CHEST_ROOM_CLEARANCE, p.y + sz.y - RARE_CHEST_ROOM_CLEARANCE):
				var cell := Vector2i(x, y)
				if reserved.has(cell) or grid[x][y] != Tile.FLOOR:
					continue
				if not _floor_patch_clear(cell, 1):
					continue
				candidates.append(cell)
		if candidates.is_empty():
			continue
		rare_chest_positions = [candidates[rng.randi_range(0, candidates.size() - 1)]]
		return

func _floor_patch_clear(center: Vector2i, radius: int) -> bool:
	for x in range(center.x - radius, center.x + radius + 1):
		for y in range(center.y - radius, center.y + radius + 1):
			if x < 1 or y < 1 or x >= width - 1 or y >= height - 1:
				return false
			if grid[x][y] != Tile.FLOOR:
				return false
	return true

func _cell_in_any_room(cell: Vector2i, rooms: Array) -> bool:
	for room in rooms:
		var p: Vector2i = room["pos"]
		var s: Vector2i = room["size"]
		if cell.x >= p.x and cell.x < p.x + s.x and cell.y >= p.y and cell.y < p.y + s.y:
			return true
	return false

# Chebyshev distance in tiles from `cell` to the outside of `room`'s rect
# (0 when the cell is inside the room). Used to keep hazards clear of the safe
# (knowledge) room.
func _dist_to_room(cell: Vector2i, room: Dictionary) -> int:
	if room.is_empty():
		return 9999
	var p: Vector2i = room["pos"]
	var s: Vector2i = room["size"]
	var dx: int = maxi(maxi(p.x - cell.x, cell.x - (p.x + s.x - 1)), 0)
	var dy: int = maxi(maxi(p.y - cell.y, cell.y - (p.y + s.y - 1)), 0)
	return maxi(dx, dy)

func _make_room(rng: RandomNumberGenerator) -> Dictionary:
	var w := rng.randi_range(ROOM_MIN, ROOM_MAX)
	var h := rng.randi_range(ROOM_MIN, ROOM_MAX)
	# Margins keep rooms off the border walls (index 0 / width-1 / height-1)
	# with room to spare for an entrance corridor.
	var x := rng.randi_range(ROOM_EDGE_MARGIN, width - w - ROOM_EDGE_MARGIN)
	var y := rng.randi_range(ROOM_EDGE_MARGIN, height - h - ROOM_EDGE_MARGIN)
	return {"pos": Vector2i(x, y), "size": Vector2i(w, h)}

# ── Entrance room (the player's spawn room) ────────────────────────
# The dungeon ALWAYS opens into a real room: the player spawns in its center
# instead of the 2-tile entrance corridor. It sits flush against the grid edge
# nearest the knowledge room, so the walk from the entrance to the first altar
# stays short, and is slid along that edge (and shrunk toward ROOM_MIN) until it
# clears the knowledge room — the knowledge room can hug the same edge, and the
# two must never overlap (a 1-tile wall gap is required by _overlaps_any).
func _make_entrance_room(rng: RandomNumberGenerator) -> Dictionary:
	var kc: Vector2i = _room_center(knowledge_room)
	var edge: String = _nearest_edge(kc)
	var w := rng.randi_range(ROOM_MIN, ROOM_MAX)
	var h := rng.randi_range(ROOM_MIN, ROOM_MAX)
	# Slide along the edge either way; shrink toward ROOM_MIN if a long edge is
	# somehow still crowded.
	for shrink in range(0, ROOM_MAX - ROOM_MIN + 1):
		var sw: int = maxi(ROOM_MIN, w - shrink)
		var sh: int = maxi(ROOM_MIN, h - shrink)
		for slide in range(0, maxi(width, height)):
			for dir_i in [1, -1]:
				var room: Dictionary = _entrance_rect(edge, sw, sh, kc, slide * dir_i)
				if not _overlaps_any(room, [knowledge_room]):
					return room
	return _entrance_rect(edge, ROOM_MIN, ROOM_MIN, kc, 0)

# A room rect of `w`x`h` flush against `edge`, centered on the knowledge room's
# cross-axis coordinate and nudged `offset` tiles along the edge, clamped to the
# grid's 2-tile margin (so the border walls at index 0 / width-1 stay intact).
func _entrance_rect(edge: String, w: int, h: int, kc: Vector2i, offset: int) -> Dictionary:
	var pos := Vector2i.ZERO
	match edge:
		"left":  pos = Vector2i(ROOM_EDGE_MARGIN, kc.y - h / 2 + offset)
		"right": pos = Vector2i(width - w - ROOM_EDGE_MARGIN, kc.y - h / 2 + offset)
		"up":    pos = Vector2i(kc.x - w / 2 + offset, ROOM_EDGE_MARGIN)
		_:       pos = Vector2i(kc.x - w / 2 + offset, height - h - ROOM_EDGE_MARGIN)
	pos.x = clampi(pos.x, ROOM_EDGE_MARGIN, width  - w - ROOM_EDGE_MARGIN)
	pos.y = clampi(pos.y, ROOM_EDGE_MARGIN, height - h - ROOM_EDGE_MARGIN)
	return {"pos": pos, "size": Vector2i(w, h)}

# The grid edge closest to `center` — "left" / "right" / "up" / "down".
func _nearest_edge(center: Vector2i) -> String:
	var best := "left"
	var best_dist := maxi(width, height)
	for edge in ["left", "right", "up", "down"]:
		var d := _edge_dist(center, edge)
		if d < best_dist:
			best_dist = d
			best = edge
	return best

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

# A multi-turn zig-zag corridor between two room centers. Every straight run is
# at least CORRIDOR_MIN_RUN tiles long — the long straight streaks are exactly
# what the Hitman's ram attack needs (see hitman.gd). The route never leaves the
# rooms' bounding box, so it can't overshoot into other rooms.
func _carve_corridor(a: Dictionary, b: Dictionary, rng: RandomNumberGenerator) -> void:
	var pts: Array = _zigzag_points(_room_center(a), _room_center(b), rng)
	for i in range(pts.size() - 1):
		_carve_thick_line(pts[i], pts[i + 1])

# Builds a staircase of waypoints from `a` to `b`: alternate horizontal/vertical
# runs, each a random length clamped to what's left on that axis. Because every
# step moves toward b and never overshoots, the whole path stays inside a/b's
# bounding box. The final point is always exactly b.
func _zigzag_points(a: Vector2i, b: Vector2i, rng: RandomNumberGenerator) -> Array:
	var pts: Array = [a]
	var cur: Vector2i = a
	var horiz_next: bool = rng.randi() % 2 == 0
	for _i in range(64):
		if cur == b:
			break
		var rx: int = absi(b.x - cur.x)
		var ry: int = absi(b.y - cur.y)
		# Both axes nearly done — finish with one axis-aligned L to b instead of
		# a string of 1-tile jogs.
		if rx < CORRIDOR_MIN_RUN and ry < CORRIDOR_MIN_RUN:
			if rx > 0:
				cur = Vector2i(b.x, cur.y)
				pts.append(cur)
			if ry > 0:
				pts.append(b)
			break
		# Prefer the current axis, but only start a run on it if it can be a
		# full-length straight streak; otherwise switch to the other axis if IT
		# can. This keeps the long rammable runs even when one axis is nearly
		# exhausted.
		var do_x: bool = horiz_next
		if do_x and rx < CORRIDOR_MIN_RUN and ry >= CORRIDOR_MIN_RUN:
			do_x = false
		elif not do_x and ry < CORRIDOR_MIN_RUN and rx >= CORRIDOR_MIN_RUN:
			do_x = true
		if do_x and rx == 0:
			do_x = false
		elif not do_x and ry == 0:
			do_x = true
		var remaining: int = rx if do_x else ry
		var run: int = mini(rng.randi_range(CORRIDOR_MIN_RUN, CORRIDOR_MIN_RUN * 2), remaining)
		if do_x:
			cur.x += signi(b.x - cur.x) * run
		else:
			cur.y += signi(b.y - cur.y) * run
		pts.append(cur)
		horiz_next = not horiz_next
	if pts[pts.size() - 1] != b:
		pts.append(b)
	return pts

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

# Carve a short straight "mouth" corridor from the entrance room out toward the
# nearest grid edge so the dungeon still reads as having an entrance. The border
# wall itself is left intact. The player appears in the ENTRANCE ROOM (see
# player_spawn_pos), just inside this mouth.
func _carve_mouth() -> void:
	var center: Vector2i = _room_center(entrance_room)
	var best_edge: String = _nearest_edge(center)
	var best_dist: int = _edge_dist(center, best_edge)
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
