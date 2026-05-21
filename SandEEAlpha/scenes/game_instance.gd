extends Node2D

const C_PANEL  := Color(0.08, 0.10, 0.20, 0.97)
const C_BORDER := Color(0.22, 0.32, 0.58, 1.00)
const C_TITLE  := Color(0.80, 0.90, 1.00, 1.00)
const C_MUTED  := Color(0.55, 0.65, 0.85, 1.00)

@onready var pause_menu: Control         = $CanvasLayer/PauseMenu
@onready var pause_btn:  Button          = $CanvasLayer/PauseButton
@onready var _world:     Node2D          = $World
@onready var _player:    CharacterBody2D = $Player

var _loading_screen: CanvasLayer = null
var _loading_label:  Label       = null

func _ready() -> void:
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	Global.ui_scale = 1.5
	Global.ui_scale_changed.emit(Global.ui_scale)

	pause_btn.pressed.connect(pause_menu.show_menu)
	_style_pause_button()
	_start_autosave()
	_add_mission_ui()

	# Freeze the player until the world is fully generated.
	_player.process_mode = Node.PROCESS_MODE_DISABLED
	_player.visible      = false

	# Show loading screen before any generation work starts.
	_show_loading_screen()

	# World._ready() already set Global.world_node and deferred generation,
	# so signals are safe to connect here before that deferred work fires.
	_world.generation_status_changed.connect(_on_generation_status)
	_world.generation_complete.connect(_on_generation_complete)

# ── Loading screen ────────────────────────────────────────────────────
func _show_loading_screen() -> void:
	_loading_screen = CanvasLayer.new()
	_loading_screen.layer = 128  # above HUD and pause menu
	add_child(_loading_screen)

	var bg := ColorRect.new()
	bg.color = Color(0.05, 0.07, 0.14, 1.0)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_loading_screen.add_child(bg)

	# Center container so content sits in the middle of the screen.
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_loading_screen.add_child(center)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 16)
	center.add_child(vbox)

	var title := Label.new()
	title.text = "SandEE Alpha"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 40)
	title.add_theme_color_override("font_color", C_TITLE)
	vbox.add_child(title)

	_loading_label = Label.new()
	_loading_label.text = "Initializing..."
	_loading_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_loading_label.add_theme_font_size_override("font_size", 16)
	_loading_label.add_theme_color_override("font_color", C_MUTED)
	vbox.add_child(_loading_label)

func _on_generation_status(status: String) -> void:
	if is_instance_valid(_loading_label):
		_loading_label.text = status

func _on_generation_complete() -> void:
	# Re-enable and show the player.
	_player.process_mode = Node.PROCESS_MODE_INHERIT
	_player.visible      = true

	# Tear down the loading screen.
	if is_instance_valid(_loading_screen):
		_loading_screen.queue_free()
		_loading_screen = null
		_loading_label  = null

	# World is fully generated — safe to create the initial save now.
	if Global.active_save_slot > 0 and not Global.has_save(Global.active_save_slot):
		Global.save_game(Global.active_save_slot)

# ── Autosave ──────────────────────────────────────────────────────────
func _add_mission_ui() -> void:
	var ui: Control = load("res://scripts/mission_ui.gd").new() as Control
	$CanvasLayer.add_child(ui)

func _start_autosave() -> void:
	var timer := Timer.new()
	timer.wait_time = 300.0
	timer.autostart = true
	timer.timeout.connect(_on_autosave)
	add_child(timer)

func _on_autosave() -> void:
	if Global.active_save_slot > 0:
		Global.save_game(Global.active_save_slot)

# ── Pause button styling ──────────────────────────────────────────────
func _style_pause_button() -> void:
	var normal := StyleBoxFlat.new()
	normal.bg_color     = C_PANEL
	normal.border_color = C_BORDER
	normal.set_border_width_all(1)
	normal.set_corner_radius_all(4)
	normal.content_margin_left   = 10
	normal.content_margin_right  = 10
	normal.content_margin_top    = 4
	normal.content_margin_bottom = 4

	var hover := StyleBoxFlat.new()
	hover.bg_color     = Color(0.13, 0.17, 0.32, 0.97)
	hover.border_color = C_TITLE
	hover.set_border_width_all(1)
	hover.set_corner_radius_all(4)
	hover.content_margin_left   = 10
	hover.content_margin_right  = 10
	hover.content_margin_top    = 4
	hover.content_margin_bottom = 4

	var pressed := StyleBoxFlat.new()
	pressed.bg_color     = Color(0.06, 0.08, 0.16, 0.97)
	pressed.border_color = C_MUTED
	pressed.set_border_width_all(1)
	pressed.set_corner_radius_all(4)
	pressed.content_margin_left   = 10
	pressed.content_margin_right  = 10
	pressed.content_margin_top    = 4
	pressed.content_margin_bottom = 4

	pause_btn.add_theme_stylebox_override("normal",  normal)
	pause_btn.add_theme_stylebox_override("hover",   hover)
	pause_btn.add_theme_stylebox_override("pressed", pressed)
	pause_btn.add_theme_color_override("font_color",         C_TITLE)
	pause_btn.add_theme_color_override("font_hover_color",   C_TITLE)
	pause_btn.add_theme_color_override("font_pressed_color", C_MUTED)
	pause_btn.add_theme_font_size_override("font_size", 12)
