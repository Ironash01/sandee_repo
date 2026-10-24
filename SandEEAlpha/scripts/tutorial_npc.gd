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
	if tex != null:
		_sprite = Sprite2D.new()
		_sprite.texture = tex
		_sprite.position = Vector2(0.0, -tex.get_height() * 0.5)
		add_child(_sprite)
		var shadow := Sprite2D.new()
		shadow.texture = load("res://sprites/shadow/shadow_base.png") as Texture2D
		shadow.position = Vector2(0.0, -2.0)
		shadow.modulate = Color(0.0, 0.0, 0.0, 0.35)
		add_child(shadow)
	_label = Label.new()
	_label.text = display_name
	_label.position = Vector2(-42.0, -tex.get_height() - 18.0 if tex != null else -66.0)
	_label.size = Vector2(84.0, 16.0)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.add_theme_font_size_override("font_size", 11)
	_label.add_theme_color_override("font_color", Color(0.92, 0.97, 1.0, 1.0))
	_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	_label.add_theme_constant_override("shadow_offset_x", 1)
	_label.add_theme_constant_override("shadow_offset_y", 1)
	add_child(_label)

func _input(event: InputEvent) -> void:
	if guide == null or not (event is InputEventMouseButton):
		return
	var mb := event as InputEventMouseButton
	if mb.button_index != MOUSE_BUTTON_LEFT or not mb.pressed:
		return
	if Global.any_ui_open() or Global.pause_menu_open:
		return
	var p := Global.player_node as Node2D
	if p == null or p.global_position.distance_to(global_position) > 72.0:
		return
	var local := to_local(Global.mouse_world(self))
	if absf(local.x) > 34.0 or local.y > 18.0 or local.y < -76.0:
		return
	guide.call("request_dialogue")
	get_viewport().set_input_as_handled()
