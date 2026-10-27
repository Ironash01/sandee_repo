extends Node2D

## A small, non-blocking tutorial NPC. It has no solid collision: the player can
## walk through it, build on/around it, and it disappears after the tutorial.

var display_name: String = "Guide"
var sprite_path: String = ""
var guide: Node = null

var _sprite: Sprite2D = null
var _label: Label = null

func setup(npc_name: String, texture_path: String, owner_guide: Node) -> void:
	display_name = npc_name
	sprite_path = texture_path
	guide = owner_guide

func _ready() -> void:
	add_to_group("TutorialNPC")
	z_as_relative = false
	z_index = int(global_position.y / 32.0)
	var tex: Texture2D = load(sprite_path) as Texture2D
	# Py-San's concept art is 64x64, much wider than the player sprite. In the
	# world it reads as a giant head next to the player, so keep the NPC version
	# compact while the dialogue portrait still uses the full-resolution art.
	var art_scale: float = 0.65 if display_name == "Py-San" else 1.0
	var drawn_h: float = tex.get_height() * art_scale if tex != null else 0.0
	if tex != null:
		_sprite = Sprite2D.new()
		_sprite.texture = tex
		_sprite.scale = Vector2(art_scale, art_scale)
		_sprite.position = Vector2(0.0, -drawn_h * 0.5)
		add_child(_sprite)
		var shadow := Sprite2D.new()
		shadow.texture = load("res://sprites/shadow/shadow_base.png") as Texture2D
		shadow.position = Vector2(0.0, -2.0)
		shadow.scale = Vector2(art_scale, art_scale)
		shadow.modulate = Color(0.0, 0.0, 0.0, 0.35)
		add_child(shadow)
	_label = Label.new()
	_label.text = display_name
	_label.position = Vector2(-42.0, -drawn_h - 18.0 if tex != null else -66.0)
	_label.size = Vector2(84.0, 16.0)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.add_theme_font_size_override("font_size", Global.ui_font_size(11))
	_label.add_theme_color_override("font_color", Color(0.92, 0.97, 1.0, 1.0))
	_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	_label.add_theme_constant_override("shadow_offset_x", 1)
	_label.add_theme_constant_override("shadow_offset_y", 1)
	add_child(_label)

func _input(event: InputEvent) -> void:
	if guide == null:
		return
	if Global.any_ui_open() or Global.pause_menu_open:
		return
	var world_pos := Vector2.INF
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index != MOUSE_BUTTON_LEFT or not mb.pressed:
			return
		world_pos = Global.mouse_world(self)
	elif event is InputEventScreenTouch:
		if not (event as InputEventScreenTouch).pressed:
			return
		var vp := get_viewport()
		if vp == null:
			return
		world_pos = vp.get_canvas_transform().affine_inverse() \
			* (event as InputEventScreenTouch).position
	else:
		return
	var p := Global.player_node as Node2D
	if p == null or p.global_position.distance_to(global_position) > 72.0:
		return
	var local := to_local(world_pos)
	if absf(local.x) > 34.0 or local.y > 18.0 or local.y < -76.0:
		return
	guide.call("request_dialogue")
	get_viewport().set_input_as_handled()
