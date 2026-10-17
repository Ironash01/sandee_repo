extends Node2D

# ── Interior shade ───────────────────────────────────────────────────
# While the player is inside a VALID house, darken the world AROUND the house
# while leaving the interior itself completely untouched — a "hole" is cut out
# of the shade over the room (floor cells + a one-tile margin so the wall ring
# stays bright too). Instant on/off, no easing.
#
# The shade is a child of the overworld (default canvas), so it dims the world
# and the player but never the CanvasLayer UI. Four screen-covering rectangles
# are drawn around the hole each frame (the camera moves continuously).
#
# Replaces the old whole-screen CanvasModulate "indoor dim" — that darkened the
# interior too, which is not what we want.

const TILE_SIZE:     int   = 32
const DIM_COLOR:     Color = Color(0.0, 0.0, 0.0, 0.5)  # = a x0.5 multiply on the surroundings
const HOLE_MARGIN:   float = 32.0                        # keep one tile of the wall ring bright

var _active: bool = false
var _hole:   Rect2 = Rect2()

func _ready() -> void:
	z_as_relative = false
	z_index        = 1500   # above world sprites/player, below the placement guides (2000); UI is a separate canvas
	visible        = false
	set_process(false)

# Called by world.gd every indoor check: `cells` are the room's floor cells
# (world tile coords). `active` false clears the shade instantly.
func set_shade(active: bool, cells: Array) -> void:
	if not active or cells.is_empty():
		_active = false
		visible = false
		set_process(false)
		return
	var mn := Vector2i(1 << 20, 1 << 20)
	var mx := Vector2i(-(1 << 20), -(1 << 20))
	for c in cells:
		var v: Vector2i = c
		mn.x = mini(mn.x, v.x); mn.y = mini(mn.y, v.y)
		mx.x = maxi(mx.x, v.x); mx.y = maxi(mx.y, v.y)
	var pos:  Vector2 = Vector2(mn) * float(TILE_SIZE) - Vector2(HOLE_MARGIN, HOLE_MARGIN)
	var size: Vector2 = Vector2(mx - mn + Vector2i.ONE) * float(TILE_SIZE) \
		+ Vector2(HOLE_MARGIN, HOLE_MARGIN) * 2.0
	_hole = Rect2(pos, size)
	_active = true
	visible = true
	set_process(true)
	queue_redraw()

func _process(_delta: float) -> void:
	# The camera follows the player, so the visible region changes every frame.
	queue_redraw()

func _draw() -> void:
	if not _active:
		return
	# Visible region in THIS node's local space (accounts for the camera).
	var screen_rect := Rect2(Vector2.ZERO, get_viewport_rect().size)
	var vis: Rect2 = get_global_transform_with_canvas().affine_inverse() * screen_rect
	# Four rectangles around the hole: top, bottom, left, right.
	_fill(Rect2(vis.position, Vector2(vis.size.x, _hole.position.y - vis.position.y)))
	_fill(Rect2(Vector2(vis.position.x, _hole.end.y), Vector2(vis.size.x, vis.end.y - _hole.end.y)))
	_fill(Rect2(Vector2(vis.position.x, _hole.position.y), Vector2(_hole.position.x - vis.position.x, _hole.size.y)))
	_fill(Rect2(Vector2(_hole.end.x, _hole.position.y), Vector2(vis.end.x - _hole.end.x, _hole.size.y)))

func _fill(r: Rect2) -> void:
	if r.size.x <= 0.0 or r.size.y <= 0.0:
		return
	draw_rect(r, DIM_COLOR, true)
