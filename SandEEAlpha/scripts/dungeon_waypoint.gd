extends Node2D
class_name DungeonWaypoint

# Temporary one-way waypoint placed near the player when a Lua/Python dungeon
# entrance is generated. It reuses the existing 3x3 dungeon-portal sprite and
# is armed by stepping onto its base tile (point-to-click compatible). Clicking
# is deliberately not an activation path.

const WAYPOINT_TEX: Texture2D = preload("res://sprites/dungeon/dungeon_portal.png")
const FRAME_SIZE := Vector2i(96, 96)
const STEP_LOCAL_CENTER := Vector2(0.0, -48.0)
const STEP_CHECK_RADIUS := 20.0

var dungeon_index: int = 0
var language: String = "python"
var anchor_cell: Vector2i = Vector2i.ZERO
var _world: Node = null
var _sprite: Sprite2D = null
var _label: Label = null
var _step_area: Area2D = null
var _using := false
var _consumed := false
var _can_trigger := true


func setup(index: int, lang: String, world: Node, anchor: Vector2i) -> void:
	dungeon_index = index
	language = lang if lang in ["python", "lua"] else "python"
	_world = world
	anchor_cell = anchor


func _ready() -> void:
	add_to_group("DungeonWaypoint")
	_build_visual()
	_build_interaction()
	call_deferred("_check_initial_step")


func _build_visual() -> void:
	_sprite = Sprite2D.new()
	_sprite.name = "WaypointSprite"
	_sprite.texture = WAYPOINT_TEX
	_sprite.centered = true
	_sprite.position = Vector2(0.0, -FRAME_SIZE.y * 0.5)
	_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(_sprite)

	_label = Label.new()
	_label.text = "%s WAYPOINT\nstep on it to travel - one-way" % language.to_upper()
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label.position = Vector2(-150.0, -FRAME_SIZE.y - 46.0)
	_label.size = Vector2(300.0, 40.0)
	_label.add_theme_font_size_override("font_size", Global.ui_font_size(10))
	_label.add_theme_color_override("font_color",
		Color(0.75, 0.90, 1.0, 1.0) if language == "python" else Color(0.72, 0.82, 1.0, 1.0))
	_label.add_theme_color_override("font_outline_color", Color(0.03, 0.06, 0.10, 1.0))
	_label.add_theme_constant_override("outline_size", 4)
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.z_index = 250
	add_child(_label)

	var light := PointLight2D.new()
	light.texture = Global.get_smooth_light_texture(128)
	light.texture_scale = 0.9
	light.color = Color(0.48, 0.68, 1.0) if language == "python" else Color(0.55, 0.48, 1.0)
	light.energy = 1.0
	light.blend_mode = Light2D.BLEND_MODE_ADD
	light.position = Vector2(0.0, -FRAME_SIZE.y * 0.45)
	add_child(light)


func _build_interaction() -> void:
	_step_area = Area2D.new()
	_step_area.name = "StepArea"
	_step_area.collision_layer = 0
	_step_area.collision_mask = 4  # player layer
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	# Only the glowing centre tile of the 3x3 portal arms the one-way travel.
	# Walking near it, or clicking it, must not.
	rect.size = Vector2(28.0, 24.0)
	shape.shape = rect
	shape.position = STEP_LOCAL_CENTER
	_step_area.add_child(shape)
	_step_area.body_entered.connect(_on_body_entered)
	_step_area.body_exited.connect(_on_body_exited)
	add_child(_step_area)


func _on_body_entered(body: Node) -> void:
	if body.is_in_group("Player") and _can_trigger:
		_can_trigger = false
		_use()


func _on_body_exited(body: Node) -> void:
	if body.is_in_group("Player"):
		# A failed/blocked teleport needs a fresh step; this prevents a
		# notification loop while the player remains standing on the portal.
		_can_trigger = true


# Covers loading a save with the player already standing on a restored
# temporary waypoint: Area2D body_entered may not fire for an overlap that
# already exists on the first monitored frame.
func _check_initial_step() -> void:
	if _consumed or _using or not is_inside_tree():
		return
	var player := Global.player_node as Node2D
	var step_world := to_global(STEP_LOCAL_CENTER)
	if player != null and player.global_position.distance_to(step_world) <= STEP_CHECK_RADIUS:
		_can_trigger = false
		_use()


func _use() -> void:
	if _using or _consumed:
		return
	var world := _world
	if world == null or not is_instance_valid(world):
		world = Global.world_node
	if world == null or not world.has_method("use_dungeon_waypoint"):
		return
	_using = true
	var ok: bool = bool(world.call("use_dungeon_waypoint", dungeon_index, self))
	if ok:
		_consumed = true
		queue_free()
	else:
		_using = false
