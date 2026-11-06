extends Node2D

# ── Persistent dungeon route guide ────────────────────────────────────
# World-owned companion for DungeonWorld. Unlike the onboarding director,
# which disappears when the tutorial ends, this node stays available in every
# dungeon run. It draws the same dotted-circle floor route to the current
# objective and a labelled target marker.
#
# Target priority comes from DungeonWorld.guide_target():
#   main  -> Knowledge Altar until its entry is learned (and until the tutorial
#            records this run's altar read), then Quiz Altar
#   extra -> nearest Quiz Altar
#   boss  -> Hitman Miniboss, then the opened exit
#
# During the scripted dungeon lesson the director already draws this route with
# its objective card, so this guide stays hidden while that step owns guidance
# (and reappears in any other dungeon, even before the full tutorial finishes).

const ROUTE_SCRIPT: GDScript = preload("res://scripts/tutorial_route_guide.gd")
const MARKER_SCRIPT: GDScript = preload("res://scripts/tutorial_marker.gd")

const SCAN_SEC: float = 0.35
const REBUILD_TILES: int = 3
## Minimum gap between floor-BFS rebuilds. Target changes bypass this so the
## knowledge -> quiz handoff is immediate.
const REBUILD_MIN_MS: int = 700

var _route: TutorialRouteGuide = null
var _marker: TutorialMarker = null
var _scan_accum: float = 999.0
var _last_cell: Vector2i = Vector2i(-999999, -999999)
var _last_target: Vector2 = Vector2.INF
var _last_label: String = ""
var _last_rebuild_ms: int = -100000

func _ready() -> void:
	add_to_group("DungeonGuide")
	_route = ROUTE_SCRIPT.new() as TutorialRouteGuide
	add_child(_route)
	_marker = MARKER_SCRIPT.new() as TutorialMarker
	_marker.visible = false
	add_child(_marker)
	set_process(true)

func _process(delta: float) -> void:
	_scan_accum += delta
	if _scan_accum < SCAN_SEC:
		return
	_scan_accum = 0.0
	_refresh()

func _refresh() -> void:
	var world := get_parent()
	var tutorial := get_tree().get_first_node_in_group("TutorialGuide")
	var tutorial_owns: bool = tutorial != null and is_instance_valid(tutorial) \
		and tutorial.has_method("owns_dungeon_route") \
		and bool(tutorial.call("owns_dungeon_route"))
	if world == null or not is_instance_valid(world) \
			or Global.world_node != world or tutorial_owns \
			or not world.has_method("guide_target") \
			or not world.has_method("world_to_grid"):
		_clear()
		return
	var p := Global.player_node as Node2D
	if p == null or not is_instance_valid(p):
		_clear()
		return
	var target: Dictionary = world.call("guide_target") as Dictionary
	if target.is_empty():
		_clear()
		return
	var pos: Vector2 = target.get("position", Vector2.INF) as Vector2
	var label: String = str(target.get("label", ""))
	if pos == Vector2.INF:
		_clear()
		return
	if _marker != null and is_instance_valid(_marker):
		_marker.visible = true
		_marker.global_position = pos
		_marker.set("label_text", label)
	var cell: Vector2i = world.call("world_to_grid", p.global_position) as Vector2i
	var target_changed: bool = pos.distance_to(_last_target) > 2.0 or label != _last_label
	var moved: int = absi(cell.x - _last_cell.x) + absi(cell.y - _last_cell.y)
	var now: int = Time.get_ticks_msec()
	if not target_changed and (moved < REBUILD_TILES
			or now - _last_rebuild_ms < REBUILD_MIN_MS):
		return
	if _route != null and is_instance_valid(_route):
		_route.set_route(TutorialRouteGuide.build_points(
			world, p.global_position, pos))
	_last_cell = cell
	_last_target = pos
	_last_label = label
	_last_rebuild_ms = now

func _clear() -> void:
	_last_cell = Vector2i(-999999, -999999)
	_last_target = Vector2.INF
	_last_label = ""
	_last_rebuild_ms = -100000
	if _route != null and is_instance_valid(_route):
		_route.clear_route()
	if _marker != null and is_instance_valid(_marker):
		_marker.visible = false
