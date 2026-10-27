extends Node2D
class_name WorldWaypointTower

# Persistent overworld waypoint. The tower art is the approved Ruined Skyglass
# animated sheet; this node owns its collision, proximity/click interaction,
# and stable waypoint identity. Placement and persistence live in world.gd.

const TOWER_SHEET: Texture2D = preload("res://sprites/waypoints/world_waypoint_tower_sheet.png")
const SHADOW_TEXTURE: Texture2D = preload("res://sprites/shadow/shadow_base.png")
const FRAME_SIZE := Vector2i(160, 224)
# Include the full tower facade, its base and the soft floor shadow. The old
# rectangle stopped exactly at the sprite edge, so clicks on the foot/base were
# easy to miss.
const CLICK_RECT := Rect2(-96.0, -FRAME_SIZE.y - 8.0,
	FRAME_SIZE.x + 32.0, FRAME_SIZE.y + 42.0)
const TILE_SIZE := 32.0

var waypoint_id: String = ""
var display_name: String = "Skyglass Waypoint"
var anchor_cell: Vector2i = Vector2i.ZERO
var foot_cell: Vector2i = Vector2i.ZERO

var _sprite: AnimatedSprite2D = null
var _interact: Area2D = null
var _label: Label = null
var _player_nearby := false
var _opening := false
var _last_touch_ms := -10000


func setup(id: String, label: String, anchor: Vector2i) -> void:
	waypoint_id = id
	display_name = label
	anchor_cell = anchor
	foot_cell = anchor + Vector2i(FRAME_SIZE.x / 64, FRAME_SIZE.y / 32 - 1)


func _ready() -> void:
	add_to_group("WorldWaypoint")
	z_as_relative = true
	_build_visual()
	_build_interaction()
	queue_redraw()


func _build_visual() -> void:
	var shadow := Global.make_shadow_sprite(
		SHADOW_TEXTURE, Vector2(0.0, 5.0), Vector2(4.8, 1.55), 0.45)
	shadow.name = "TowerShadow"
	shadow.z_index = -2
	add_child(shadow)

	# A squat dark plinth/shade anchors the tower visually to the ground and
	# makes the widened click area read as part of the landmark.
	var base_shade := Polygon2D.new()
	base_shade.name = "TowerBaseShade"
	base_shade.polygon = PackedVector2Array([
		Vector2(-72.0, 8.0), Vector2(72.0, 8.0),
		Vector2(52.0, -10.0), Vector2(-52.0, -10.0),
	])
	base_shade.color = Color(0.02, 0.035, 0.05, 0.42)
	base_shade.z_index = -1
	add_child(base_shade)

	_sprite = AnimatedSprite2D.new()
	_sprite.name = "TowerSprite"
	_sprite.sprite_frames = WaypointAnim.build(TOWER_SHEET, FRAME_SIZE)
	_sprite.animation = "idle"
	_sprite.centered = true
	_sprite.position = Vector2(0.0, -FRAME_SIZE.y * 0.5)
	_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_sprite.play("idle")
	add_child(_sprite)

	# The tower is a solid landmark. world.gd reserves the full 5x7 footprint
	# for building/landing checks; the collider covers the visual facade too so
	# the player cannot walk through the ruin.
	var body := StaticBody2D.new()
	body.name = "TowerBody"
	body.collision_layer = 1
	body.collision_mask = 0
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(150.0, 210.0)
	shape.shape = rect
	shape.position = Vector2(0.0, -105.0)
	body.add_child(shape)
	add_child(body)

	_label = Label.new()
	_label.name = "WaypointLabel"
	_label.text = display_name + "\nclick to open waypoint map"
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label.position = Vector2(-150.0, -FRAME_SIZE.y - 54.0)
	_label.size = Vector2(300.0, 44.0)
	_label.add_theme_font_size_override("font_size", Global.ui_font_size(11))
	_label.add_theme_color_override("font_color", Color(0.89, 0.98, 1.0, 1.0))
	_label.add_theme_color_override("font_outline_color", Color(0.04, 0.08, 0.10, 1.0))
	_label.add_theme_constant_override("outline_size", 4)
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.z_index = 200
	_label.visible = false
	add_child(_label)


func _build_interaction() -> void:
	_interact = Area2D.new()
	_interact.name = "InteractArea"
	_interact.collision_layer = 0
	_interact.collision_mask = 4  # player layer
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	# Reach below the base too: the validated teleport landing is on the open
	# ring around the footprint, usually just south of the tower.
	rect.size = Vector2(240.0, 330.0)
	shape.shape = rect
	shape.position = Vector2(0.0, -95.0)
	_interact.add_child(shape)
	_interact.body_entered.connect(_on_body_entered)
	_interact.body_exited.connect(_on_body_exited)
	add_child(_interact)


func _on_body_entered(body: Node) -> void:
	if body.is_in_group("Player"):
		_player_nearby = true
		if _label != null:
			_label.visible = true
		queue_redraw()


func _on_body_exited(body: Node) -> void:
	if body.is_in_group("Player"):
		_player_nearby = false
		if _label != null:
			_label.visible = false
		queue_redraw()


func _draw() -> void:
	if _player_nearby:
		draw_rect(Rect2(-72.0, -28.0, 144.0, 28.0),
			Color(1.0, 0.88, 0.25, 0.95), false, 2.0)


func _input(event: InputEvent) -> void:
	if _opening or not _player_nearby:
		return
	if Global.block_mode or Global.any_ui_open() or Global.pause_menu_open:
		return
	if event is InputEventMouseButton:
		if Time.get_ticks_msec() - _last_touch_ms < 120:
			return
		if event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			if CLICK_RECT.has_point(to_local(Global.mouse_world(self))):
				get_viewport().set_input_as_handled()
				_open_map()
	elif event is InputEventScreenTouch:
		if event.pressed:
			_last_touch_ms = Time.get_ticks_msec()
			var local: Vector2 = get_global_transform_with_canvas().affine_inverse() * event.position
			if CLICK_RECT.has_point(local):
				get_viewport().set_input_as_handled()
				_open_map()


func _open_map() -> bool:
	if _opening:
		return false
	var maps := get_tree().get_nodes_in_group("Minimap")
	if maps.is_empty():
		return false
	_opening = true
	var ok := bool(maps[0].call("open_world_waypoint_map", waypoint_id))
	# The map owns the UI stack until it closes; this tower may be used again
	# afterwards, so release the one-frame re-entry guard immediately.
	_opening = false
	return ok
