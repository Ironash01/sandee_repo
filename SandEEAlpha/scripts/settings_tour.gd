extends CanvasLayer

## Post-onboarding settings tour.
##
## Opens Settings and walks through each category and its important controls.
## The highlight is a pulsing outline only (no pointing arrow); the explanation
## appears beside the highlighted control. NEXT advances, SKIP closes the tour.
## The tour is display-only apart from its own NEXT/SKIP bar: the highlighted
## settings remain usable.

const TOUR_LAYER: int = 131
const FOCUS_SCRIPT: Script = preload("res://scripts/tutorial_ui_target.gd")

const STEPS: Array = [
	{"cat": "Audio", "target": "__category__",
		"text": "Audio settings - control the overall mix."},
	{"cat": "Audio", "target": "Master Volume",
		"text": "Master Volume - overall game volume (music + effects)."},
	{"cat": "Audio", "target": "Music Volume",
		"text": "Music Volume - background music level."},
	{"cat": "Audio", "target": "SFX Volume",
		"text": "SFX Volume - mining, footsteps, mobs and other effects."},
	{"cat": "Display", "target": "__category__",
		"text": "Display settings - camera and screen behaviour."},
	{"cat": "Display", "target": "Camera Zoom",
		"text": "Camera Zoom - see more or less of the world."},
	{"cat": "Display", "target": "Fullscreen",
		"text": "Fullscreen - play fullscreen; remembered for the next launch."},
	{"cat": "Display", "target": "VSync",
		"text": "VSync - sync to the monitor; off can reduce input latency."},
	{"cat": "Gameplay", "target": "__category__",
		"text": "Gameplay settings - pauses and quest tracker style."},
	{"cat": "Gameplay", "target": "Pause on Inventory",
		"text": "Pause on Inventory - freeze the world while the inventory is open."},
	{"cat": "Gameplay", "target": "Opaque Quest Background",
		"text": "Opaque Quest Background - draw missions on a solid panel."},
	{"cat": "Controls", "target": "__category__",
		"text": "Controls - movement mode, sprint and key bindings."},
	{"cat": "Controls", "target": "Point-and-Click Movement",
		"text": "Point-and-Click Movement - click the world to walk, interact or chase."},
	{"cat": "Controls", "target": "Automatic Sprint",
		"text": "Automatic Sprint - sprint automatically during click movement."},
	{"cat": "Controls", "target": "Move Up",
		"text": "Key bindings - click a binding, then press a key. This works for movement, inventory and every hotbar slot."},
	{"cat": "Controls", "target": "__back__",
		"text": "Back - return to the pause menu when you are done."},
]

var _focus: Control = null
var _bar: PanelContainer = null
var _progress: Label = null
var _next_btn: Button = null
var _pause: Control = null
var _settings: Control = null
var _game: Node = null
var _index: int = 0
var _current_cat: String = ""
var _active: bool = false
var _started: bool = false
var _opened_pause: bool = false
var _loading_step: bool = false
var _finished: bool = false


func _ready() -> void:
	layer = TOUR_LAYER
	process_mode = Node.PROCESS_MODE_ALWAYS
	_focus = FOCUS_SCRIPT.new() as Control
	_focus.name = "SettingsTourHighlight"
	add_child(_focus)
	_build_bar()
	if not Global.ui_scale_changed.is_connected(_on_ui_scale):
		Global.ui_scale_changed.connect(_on_ui_scale)
	set_process(true)


func start() -> void:
	if _active or _finished:
		return
	_active = true
	_game = Global.game_node
	if _game == null:
		_finish(false)
		return
	_pause = _game.get("pause_menu") as Control
	if _pause == null:
		_pause = _game.get_node_or_null("CanvasLayer/PauseMenu") as Control
	if _pause == null:
		_finish(false)
		return
	if not _pause.visible:
		_pause.call("show_menu")
		_opened_pause = true
	if not _pause.visible:
		_finish(false)
		return
	_pause.call("_on_open_settings")
	await get_tree().process_frame
	await get_tree().process_frame
	if _finished or not is_inside_tree():
		return
	_settings = _pause.find_child("SettingsPanel", true, false) as Control
	if _settings == null or not _settings.is_visible_in_tree():
		_finish(false)
		return
	_bar.visible = true
	_started = true
	_show_step(0)


func _build_bar() -> void:
	var s: float = Global.ui_scale
	_bar = PanelContainer.new()
	_bar.name = "SettingsTourBar"
	_bar.mouse_filter = Control.MOUSE_FILTER_STOP
	_bar.visible = false
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.06, 0.09, 0.16, 0.98)
	sb.border_color = Color(0.28, 0.55, 0.66, 1.0)
	sb.set_border_width_all(maxi(1, int(2 * s)))
	sb.set_corner_radius_all(int(6 * s))
	sb.content_margin_left = int(12 * s)
	sb.content_margin_right = int(12 * s)
	sb.content_margin_top = int(8 * s)
	sb.content_margin_bottom = int(8 * s)
	_bar.add_theme_stylebox_override("panel", sb)
	_bar.custom_minimum_size.x = int(560 * s)
	add_child(_bar)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", int(10 * s))
	_bar.add_child(row)
	var title := Label.new()
	title.text = "SETTINGS TOUR"
	title.add_theme_font_size_override("font_size", Global.ui_type_size(Global.UI_TYPE_LABEL))
	title.add_theme_color_override("font_color", Color(0.80, 0.94, 1.0, 1.0))
	row.add_child(title)
	_progress = Label.new()
	_progress.text = ""
	_progress.add_theme_font_size_override("font_size", Global.ui_type_size(Global.UI_TYPE_CAPTION))
	_progress.add_theme_color_override("font_color", Color(0.58, 0.72, 0.86, 1.0))
	row.add_child(_progress)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)
	_next_btn = _tour_button("NEXT", func() -> void: _on_next())
	row.add_child(_next_btn)
	var skip := _tour_button("SKIP", func() -> void: _finish(true))
	row.add_child(skip)


func _tour_button(text: String, callback: Callable) -> Button:
	var s: float = Global.ui_scale
	var btn := Button.new()
	btn.text = text
	btn.custom_minimum_size = Vector2(int(96 * s), maxi(36, int(32 * s)))
	btn.add_theme_font_size_override("font_size", Global.ui_type_size(Global.UI_TYPE_BODY))
	btn.pressed.connect(callback)
	return btn


func _on_next() -> void:
	if not _active or _loading_step:
		return
	_show_step(_index + 1)


func _show_step(index: int) -> void:
	if _finished or not _active:
		return
	if index >= STEPS.size():
		_finish(true)
		return
	if _loading_step:
		return
	_loading_step = true
	_next_btn.disabled = true
	_index = index
	var step: Dictionary = STEPS[index]
	var cat: String = str(step.get("cat", "Audio"))
	if cat != _current_cat:
		_settings.call("tutorial_show_category", cat)
		_current_cat = cat
		await get_tree().process_frame
		if _finished or not _active:
			return
	var target: String = str(step.get("target", ""))
	var control: Control = null
	if target == "__category__":
		control = _settings.call("tutorial_category_button", cat) as Control
	elif target == "__back__":
		control = _settings.call("tutorial_back_button") as Control
	else:
		control = _settings.call("tutorial_find_control", target) as Control
	if control == null:
		_loading_step = false
		_next_btn.disabled = false
		_show_step(index + 1)
		return
	var scroll: Node = control.get_parent()
	while scroll != null and not (scroll is ScrollContainer):
		scroll = scroll.get_parent()
	if scroll is ScrollContainer:
		(scroll as ScrollContainer).ensure_control_visible(control)
		await get_tree().process_frame
		if _finished or not _active:
			return
	_focus.call("set_target", control, str(step.get("text", "")), false)
	_progress.text = "%d / %d" % [index + 1, STEPS.size()]
	_next_btn.text = "DONE" if index >= STEPS.size() - 1 else "NEXT"
	_loading_step = false
	_next_btn.disabled = false


func _process(_delta: float) -> void:
	if not _active or _finished or not _started:
		return
	if _pause == null or not is_instance_valid(_pause) or not _pause.visible:
		_finish(false)
		return
	if _settings == null or not is_instance_valid(_settings) \
			or not _settings.is_visible_in_tree():
		_finish(false)
		return
	if _bar != null and is_instance_valid(_bar) and _bar.visible:
		_layout_bar()


func _layout_bar() -> void:
	_bar.reset_size()
	var vp: Vector2 = get_viewport().get_visible_rect().size
	var safe: Vector4 = Global.ui_safe_insets
	var size: Vector2 = _bar.get_combined_minimum_size()
	_bar.position = Vector2(
		(vp.x - size.x) * 0.5,
		vp.y - safe.w - size.y - int(18 * Global.ui_scale))


func _on_ui_scale(_s: float) -> void:
	if _bar != null and is_instance_valid(_bar):
		_layout_bar()


func _finish(close_pause: bool) -> void:
	if _finished:
		return
	_finished = true
	_active = false
	if _focus != null and is_instance_valid(_focus):
		_focus.call("clear_target")
	if _bar != null and is_instance_valid(_bar):
		_bar.visible = false
	if close_pause and _opened_pause and _pause != null \
			and is_instance_valid(_pause) and _pause.visible:
		_pause.call("hide_menu")
	Global.notify("[color=#9be89b]Settings tour complete.[/color]")
	queue_free()
