extends Node2D

const C_PANEL  := Color(0.08, 0.10, 0.20, 0.97)
const C_BORDER := Color(0.22, 0.32, 0.58, 1.00)
const C_TITLE  := Color(0.80, 0.90, 1.00, 1.00)
const C_MUTED  := Color(0.55, 0.65, 0.85, 1.00)

@onready var pause_menu: Control = $CanvasLayer/PauseMenu
@onready var pause_btn:  Button  = $CanvasLayer/PauseButton

func _ready() -> void:
	pause_btn.pressed.connect(pause_menu.show_menu)
	_style_pause_button()

func _style_pause_button() -> void:
	# Normal state
	var normal := StyleBoxFlat.new()
	normal.bg_color     = C_PANEL
	normal.border_color = C_BORDER
	normal.set_border_width_all(1)
	normal.set_corner_radius_all(4)
	normal.content_margin_left   = 10
	normal.content_margin_right  = 10
	normal.content_margin_top    = 4
	normal.content_margin_bottom = 4
	# Hover state
	var hover := StyleBoxFlat.new()
	hover.bg_color     = Color(0.13, 0.17, 0.32, 0.97)
	hover.border_color = C_TITLE
	hover.set_border_width_all(1)
	hover.set_corner_radius_all(4)
	hover.content_margin_left   = 10
	hover.content_margin_right  = 10
	hover.content_margin_top    = 4
	hover.content_margin_bottom = 4
	# Pressed state
	var pressed := StyleBoxFlat.new()
	pressed.bg_color     = Color(0.06, 0.08, 0.16, 0.97)
	pressed.border_color = C_MUTED
	pressed.set_border_width_all(1)
	pressed.set_corner_radius_all(4)
	pressed.content_margin_left   = 10
	pressed.content_margin_right  = 10
	pressed.content_margin_top    = 4
	pressed.content_margin_bottom = 4
	pause_btn.add_theme_stylebox_override("normal",   normal)
	pause_btn.add_theme_stylebox_override("hover",    hover)
	pause_btn.add_theme_stylebox_override("pressed",  pressed)
	pause_btn.add_theme_color_override("font_color",          C_TITLE)
	pause_btn.add_theme_color_override("font_hover_color",    C_TITLE)
	pause_btn.add_theme_color_override("font_pressed_color",  C_MUTED)
	pause_btn.add_theme_font_size_override("font_size", 12)
