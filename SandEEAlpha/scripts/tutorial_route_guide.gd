extends Node2D
class_name TutorialRouteGuide

# Dotted route markers for the guided dungeon walk. The tutorial director
# computes a floor-only BFS path and hands it the turn/waypoint cells. Dots only
# — no numbers or text — so the trail reads as a clear path to follow.

const C_RING: Color = Color(0.35, 0.96, 0.88, 1.0)
const C_LINE: Color = Color(0.35, 0.96, 0.88, 0.35)

## Hard cap for the dungeon BFS. A fully connected large dungeon is well under
## this; the cap only exists so a pathological/isolated objective cannot stall a
## frame. When it is reached the guide falls back to the direct target disc.
const MAX_ROUTE_VISITS: int = 20000

var _points: Array = []
var _pulse: float = 0.0

## Floor-only BFS route through a generated dungeon. Shared by the tutorial
## director and the persistent DungeonGuide so both always draw the same dots.
static func build_points(world: Node, from_world: Vector2,
		goal_world: Vector2) -> Array:
	if world == null or not world.has_method("world_to_grid") \
			or not world.has_method("grid_to_world") \
			or not world.has_method("grid_cell_is_floor"):
		return [goal_world]
	var start: Vector2i = world.call("world_to_grid", from_world) as Vector2i
	var goal: Vector2i = world.call("world_to_grid", goal_world) as Vector2i
	var gen: Variant = world.get("generator")
	if gen == null or start.x < 0 or start.y < 0 or goal.x < 0 or goal.y < 0:
		return [goal_world]
	var blocked: Dictionary = {}
	var trap_list: Variant = gen.get("trap_positions")
	if trap_list is Array:
		for cell_value in (trap_list as Array):
			blocked[cell_value as Vector2i] = true
	var quiz_trap_list: Variant = gen.get("quiz_trap_positions")
	if quiz_trap_list is Array:
		for cell_value in (quiz_trap_list as Array):
			blocked[cell_value as Vector2i] = true
	var queue: Array = [start]
	var came: Dictionary = {start: start}
	var dirs: Array = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
	var found := false
	while not queue.is_empty() and came.size() < MAX_ROUTE_VISITS:
		var cur: Vector2i = queue.pop_front() as Vector2i
		if cur == goal:
			found = true
			break
		for d_value in dirs:
			var n := cur + (d_value as Vector2i)
			if came.has(n) or blocked.has(n):
				continue
			if not bool(world.call("grid_cell_is_floor", n)):
				continue
			came[n] = cur
			queue.append(n)
	if not found:
		return [goal_world]
	var path: Array = []
	var c := goal
	while c != start:
		path.push_front(c)
		c = came[c] as Vector2i
	# Keep turns plus every fourth tile; cap the number of discs so they never
	# obscure the room. Always end at the actual objective.
	var out_cells: Array = []
	var prev_dir := Vector2i.ZERO
	for i in range(path.size()):
		var cell: Vector2i = path[i] as Vector2i
		var dir := Vector2i.ZERO
		if i > 0:
			dir = cell - (path[i - 1] as Vector2i)
		var turn := dir != prev_dir
		if turn or i % 4 == 0 or i == path.size() - 1:
			out_cells.append(cell)
		prev_dir = dir
	if out_cells.size() > 16:
		var reduced: Array = []
		var step := maxi(1, int(ceil(float(out_cells.size()) / 16.0)))
		for i in range(0, out_cells.size(), step):
			reduced.append(out_cells[i])
		if reduced.is_empty() or reduced[reduced.size() - 1] != goal:
			reduced.append(goal)
		out_cells = reduced
	var out: Array = []
	for cell_value in out_cells:
		out.append(world.call("grid_to_world", cell_value as Vector2i) as Vector2)
	if out.is_empty():
		out.append(goal_world)
	return out

func _ready() -> void:
	z_as_relative = false
	z_index = 4010
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_process(true)
	visible = false

func set_route(points: Array) -> void:
	_points = points.duplicate()
	visible = not _points.is_empty()
	queue_redraw()

func clear_route() -> void:
	_points.clear()
	visible = false
	queue_redraw()

func _process(delta: float) -> void:
	if not visible:
		return
	_pulse += delta
	queue_redraw()

func _draw() -> void:
	if _points.is_empty():
		return
	if Global.any_ui_open() or Global.pause_menu_open:
		return
	var s: float = Global.ui_scale
	var wave: float = 0.5 + 0.5 * sin(_pulse * 3.4)
	# Small dotted trail only: connector dots plus a slightly brighter dot at
	# each computed waypoint. There are no large target discs; the labelled
	# target marker already identifies the destination.
	var dot_r: float = maxf(1.2, 1.8 * s)
	var point_r: float = maxf(1.6, 2.2 * s)
	for i in range(1, _points.size()):
		var a: Vector2 = _points[i - 1] as Vector2
		var b: Vector2 = _points[i] as Vector2
		var seg := a.distance_to(b)
		var steps := maxi(1, int(ceil(seg / (18.0 * s))))
		for k in range(steps):
			var t := float(k) / float(steps)
			draw_circle(a.lerp(b, t), dot_r, C_LINE)
	for i in range(_points.size()):
		var p: Vector2 = _points[i] as Vector2
		draw_circle(p, point_r + wave * 0.25 * s, C_RING)
