extends Node2D
class_name CavePortal

# Placeholder cave entrance/exit marker — no sprite yet, just a drawn colored
# square + label (per the "no art yet" instruction). Built entirely in code
# (Area2D + CollisionShape2D added in _ready()) rather than a .tscn, same
# convention dungeon_portal.gd already uses for its confirm-dialog UI —
# there's nothing here an editor-authored scene would add.
#
# Walking into it triggers immediately (no click/confirm) — closer to how
# Pokémon cave mouths actually work than the Dungeon Portal's confirm-popup
# pattern, and simpler to get working for a first pass.

enum Mode { ENTER, EXIT }

const TILE_SIZE:    int   = 32
const COLOR_ENTER:  Color = Color(0.16, 0.55, 0.25, 1.0)
const COLOR_EXIT:   Color = Color(0.55, 0.30, 0.15, 1.0)
const RETRIGGER_COOLDOWN: float = 1.0  # guards against re-firing the instant the player spawns back on top of it

var mode:      int = Mode.ENTER
var cave_seed: int = 0  # ENTER only — the seed this entrance's interior generates from

var _label_text: String = "CAVE"
var _triggered:  bool   = false

@onready var _area: Area2D = Area2D.new()

func _ready() -> void:
	add_to_group("CavePortal")
	_label_text = "CAVE" if mode == Mode.ENTER else "EXIT"

	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(TILE_SIZE, TILE_SIZE)
	shape.shape = rect
	_area.add_child(shape)
	_area.collision_layer = 0
	_area.collision_mask  = 1
	_area.body_entered.connect(_on_body_entered)
	add_child(_area)
	queue_redraw()

func _draw() -> void:
	# Recomputed here rather than _ready() — callers always set
	# global_position AFTER add_child() (which is when _ready() fires), so
	# computing it there would permanently bucket every portal at y=0.
	# _draw() runs later, once the real position is in place.
	z_index = int(global_position.y / TILE_SIZE)

	var color: Color = COLOR_ENTER if mode == Mode.ENTER else COLOR_EXIT
	var half: float = TILE_SIZE / 2.0
	draw_rect(Rect2(-half, -half, TILE_SIZE, TILE_SIZE), color)
	draw_rect(Rect2(-half, -half, TILE_SIZE, TILE_SIZE), Color(0, 0, 0, 0.6), false, 2.0)

	var font: Font  = ThemeDB.fallback_font
	var fsize: int  = 8
	var text_size: Vector2 = font.get_string_size(_label_text, HORIZONTAL_ALIGNMENT_CENTER, -1, fsize)
	draw_string(font, Vector2(-text_size.x / 2.0, fsize / 2.0), _label_text,
		HORIZONTAL_ALIGNMENT_CENTER, -1, fsize, Color.WHITE)

func _on_body_entered(body: Node) -> void:
	if _triggered or not body.is_in_group("Player"):
		return
	_triggered = true
	_start_cooldown()
	if not is_instance_valid(Global.game_node):
		return
	if mode == Mode.ENTER and Global.game_node.has_method("enter_cave"):
		Global.game_node.call("enter_cave", self)
	elif mode == Mode.EXIT and Global.game_node.has_method("exit_cave"):
		Global.game_node.call("exit_cave")

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
