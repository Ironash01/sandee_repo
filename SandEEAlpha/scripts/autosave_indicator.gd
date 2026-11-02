extends CanvasLayer

# ── Global autosave notification ─────────────────────────────────────
# A persistent CanvasLayer above every scene and modal. It listens to the
# Global save pipeline so the same top-centre "Autosaving..." pill appears in
# the overworld, caves, dungeons, editors and menus. Saves are synchronous, so
# the indicator enforces a short minimum visibility instead of flashing for one
# frame; a slow save keeps it on screen until save_finished arrives.

const SPINNER_SCRIPT: GDScript = preload("res://scripts/autosave_spinner.gd")
const MIN_VISIBLE_SEC: float = 1.0

const C_PANEL: Color = Color(0.06, 0.09, 0.17, 0.96)
const C_BORDER: Color = Color(0.28, 0.46, 0.76, 1.0)
const C_TITLE: Color = Color(0.80, 0.90, 1.00, 1.0)
const C_MUTED: Color = Color(0.55, 0.65, 0.85, 1.0)

var _root: Control = null
var _panel: PanelContainer = null
var _spinner: Control = null
var _label: Label = null
var _timer: Timer = null
var _saving: bool = false
var _min_elapsed: bool = false


func _ready() -> void:
	layer = 140  # above loading/transition overlays and every modal
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	_timer = Timer.new()
	_timer.one_shot = true
	_timer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_timer)
	_timer.timeout.connect(_on_min_visible_elapsed)
	_build()
	if not Global.save_started.is_connected(_on_save_started):
		Global.save_started.connect(_on_save_started)
	if not Global.save_finished.is_connected(_on_save_finished):
		Global.save_finished.connect(_on_save_finished)
	if not Global.ui_scale_changed.is_connected(_on_ui_scale):
		Global.ui_scale_changed.connect(_on_ui_scale)


func _build() -> void:
	if _root != null and is_instance_valid(_root):
		remove_child(_root)
		_root.queue_free()
	var s: float = Global.ui_scale
	_root = Control.new()
	_root.name = "AutosaveRoot"
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_root)

	# Full-width top band, so the panel stays horizontally centred while the
	# safe-area top inset keeps it below notches/system bars.
	var band := CenterContainer.new()
	band.set_anchors_preset(Control.PRESET_TOP_WIDE)
	band.offset_left = 0.0
	band.offset_right = 0.0
	band.offset_top = Global.ui_safe_insets.y + 8.0 * s
	band.offset_bottom = band.offset_top + 42.0 * s
	band.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(band)

	_panel = PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = C_PANEL
	style.border_color = C_BORDER
	style.set_border_width_all(maxi(1, int(1.5 * s)))
	style.set_corner_radius_all(int(18 * s))
	style.content_margin_left = int(12 * s)
	style.content_margin_right = int(14 * s)
	style.content_margin_top = int(6 * s)
	style.content_margin_bottom = int(6 * s)
	_panel.add_theme_stylebox_override("panel", style)
	band.add_child(_panel)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", int(8 * s))
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(row)

	_spinner = SPINNER_SCRIPT.new() as Control
	_spinner.custom_minimum_size = Vector2(18, 18) * s
	_spinner.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_spinner)

	_label = Label.new()
	_label.text = "Autosaving..."
	_label.add_theme_font_size_override("font_size", Global.ui_font_size(11))
	_label.add_theme_color_override("font_color", C_TITLE)
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(_label)

	var sub := Label.new()
	sub.text = "saving progress"
	sub.add_theme_font_size_override("font_size", Global.ui_font_size(9))
	sub.add_theme_color_override("font_color", C_MUTED)
	sub.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(sub)


func _on_save_started(_slot: int) -> void:
	_saving = true
	_min_elapsed = false
	visible = true
	if _label != null and is_instance_valid(_label):
		_label.text = "Autosaving..."
	if _timer != null and is_instance_valid(_timer):
		_timer.start(MIN_VISIBLE_SEC)


func _on_save_finished(_slot: int, _success: bool) -> void:
	_saving = false
	if _min_elapsed and is_instance_valid(self):
		visible = false


func _on_min_visible_elapsed() -> void:
	_min_elapsed = true
	if not _saving and is_instance_valid(self):
		visible = false


func _on_ui_scale(_s: float) -> void:
	if _panel != null and is_instance_valid(_panel):
		_build()


func indicator_text() -> String:
	return _label.text if _label != null and is_instance_valid(_label) else ""


func spinner_control() -> Control:
	return _spinner if _spinner != null and is_instance_valid(_spinner) else null
