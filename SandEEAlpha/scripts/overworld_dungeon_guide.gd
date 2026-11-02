extends Node2D

# ── Persistent overworld dungeon guide ────────────────────────────────
# Points at the dungeon recommended next by Global.next_guided_dungeon_index().
# The two main tracks alternate from the most recently cleared dungeon:
# Python -> Lua -> Python (and Lua -> Python when the player clears Lua first).
#
# Presentation matches the onboarding dungeon guidance:
#   • dotted-circle trail for the next few tiles,
#   • a labelled marker on the live entrance,
#   • a player-mounted compass arrow for the remaining distance.
#
# The scripted tutorial has its own travel lesson, so this guide stays hidden
# until Global.tutorial_completed to avoid a second marker/arrow.

const ROUTE_SCRIPT: GDScript = preload("res://scripts/tutorial_route_guide.gd")
const MARKER_SCRIPT: GDScript = preload("res://scripts/tutorial_marker.gd")
const ARROW_SCRIPT: GDScript = preload("res://scripts/tutorial_arrow.gd")

const TILE: float = 32.0
const SCAN_SEC: float = 0.4
const REBUILD_TILES: int = 3
const TRAIL_STEP_TILES: float = 4.0
const TRAIL_MAX_POINTS: int = 10

var _route: TutorialRouteGuide = null
var _marker: TutorialMarker = null
var _arrow: TutorialArrow = null
var _scan_accum: float = 999.0
var _last_cell: Vector2i = Vector2i(-999999, -999999)
var _last_target: Vector2 = Vector2.INF
var _last_label: String = ""

func _ready() -> void:
	add_to_group("OverworldDungeonGuide")
	_route = ROUTE_SCRIPT.new() as TutorialRouteGuide
	add_child(_route)
	_marker = MARKER_SCRIPT.new() as TutorialMarker
	_marker.visible = false
	add_child(_marker)
	set_process(true)

func _exit_tree() -> void:
	# The overworld is removed from the tree (not freed) while the player is in
	# a cave/dungeon. Clear the player-mounted compass so it cannot keep pointing
	# at a surface entrance from inside another world.
	if _arrow != null and is_instance_valid(_arrow):
		_arrow.call("clear_target")

func _process(delta: float) -> void:
	_scan_accum += delta
	if _scan_accum < SCAN_SEC:
		return
	_scan_accum = 0.0
	_refresh()

func _refresh() -> void:
	var world := get_parent()
	if world == null or not is_instance_valid(world) \
			or Global.world_node != world or not Global.tutorial_completed \
			or not world.has_method("get_guided_dungeon_target"):
		_clear()
		return
	var p := Global.player_node as Node2D
	if p == null or not is_instance_valid(p):
		_clear()
		return
	var pos: Vector2 = world.call("get_guided_dungeon_target") as Vector2
	if pos == Vector2.INF:
		_clear()
		return
	var label: String = Global.next_guided_dungeon_name()
	if label.is_empty():
		label = "Dungeon"
	if _marker != null and is_instance_valid(_marker):
		_marker.visible = true
		_marker.global_position = pos
		_marker.set("label_text", label)
	_sync_arrow(p, pos, label)
	var cell := Vector2i(floori(p.global_position.x / TILE),
		floori(p.global_position.y / TILE))
	var target_changed: bool = pos.distance_to(_last_target) > 2.0 or label != _last_label
	var moved: int = absi(cell.x - _last_cell.x) + absi(cell.y - _last_cell.y)
	if target_changed or moved >= REBUILD_TILES:
		if _route != null and is_instance_valid(_route):
			_route.set_route(_trail_points(p.global_position, pos))
		_last_cell = cell
		_last_target = pos
		_last_label = label

func _sync_arrow(p: Node2D, pos: Vector2, label: String) -> void:
	if _arrow == null or not is_instance_valid(_arrow) or _arrow.get_parent() != p:
		if _arrow != null and is_instance_valid(_arrow):
			_arrow.queue_free()
		_arrow = ARROW_SCRIPT.new() as TutorialArrow
		p.add_child(_arrow)
	if _arrow != null and is_instance_valid(_arrow):
		_arrow.call("set_target", pos, label)

# A short dotted trail. Unlike a dungeon, the overworld has no single room-sized
# floor BFS available cheaply; the compass arrow carries the long-distance
# direction while these discs lead the next few steps. Water tiles are nudged
# aside so the trail does not visibly run across a lake.
func _trail_points(from_world: Vector2, to_world: Vector2) -> Array:
	var delta := to_world - from_world
	var dist := delta.length()
	if dist <= TILE * 1.5:
		return [to_world]
	var dir := delta / dist
	var steps: int = maxi(1, int(ceil(dist / (TILE * TRAIL_STEP_TILES))))
	var count: int = mini(TRAIL_MAX_POINTS, steps)
	var points: Array = []
	var world := get_parent()
	for i in range(1, count + 1):
		var d: float = minf(dist, float(i) * TILE * TRAIL_STEP_TILES)
		var point: Vector2 = from_world + dir * d
		if d < dist:
			point = _nudge_to_dry(world, point)
		points.append(point)
		if d >= dist:
			break
	var reach: float = float(TRAIL_MAX_POINTS) * TILE * TRAIL_STEP_TILES
	if dist <= reach:
		if points.is_empty():
			points.append(to_world)
		else:
			points[points.size() - 1] = to_world
	return points

func _nudge_to_dry(world: Node, point: Vector2) -> Vector2:
	if world == null or not is_instance_valid(world) \
			or not world.has_method("cell_is_water"):
		return point
	var cell := Vector2i(floori(point.x / TILE), floori(point.y / TILE))
	if not bool(world.call("cell_is_water", cell)):
		return point
	var dirs: Array = [
		Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
		Vector2i(1, 1), Vector2i(-1, 1), Vector2i(1, -1), Vector2i(-1, -1),
	]
	for radius in range(1, 6):
		for d_value in dirs:
			var candidate: Vector2i = cell + (d_value as Vector2i) * radius
			if not bool(world.call("cell_is_water", candidate)):
				return Vector2((candidate.x + 0.5) * TILE,
					(candidate.y + 0.5) * TILE)
	return point

func _clear() -> void:
	_last_cell = Vector2i(-999999, -999999)
	_last_target = Vector2.INF
	_last_label = ""
	if _route != null and is_instance_valid(_route):
		_route.clear_route()
	if _marker != null and is_instance_valid(_marker):
		_marker.visible = false
	if _arrow != null and is_instance_valid(_arrow):
		_arrow.call("clear_target")
