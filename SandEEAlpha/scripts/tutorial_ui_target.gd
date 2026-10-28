extends Control
class_name TutorialUiTarget

# Full-screen, input-transparent tutorial highlight for UI targets. It follows
# the target Control every frame (layout/scale/rotation/keyboard changes) and
# draws a pulsing bracket plus a short instruction label beside it. It never
# intercepts mouse/touch input, so taps reach the highlighted button/slot.

const OUTLINE: Color = Color(0.42, 1.0, 0.92, 1.0)
const OUTLINE_SOFT: Color = Color(0.10, 0.45, 0.48, 0.92)
const LABEL_BG: Color = Color(0.04, 0.08, 0.15, 0.97)
const LABEL_BORDER: Color = Color(0.30, 0.72, 0.82, 1.0)
const LABEL_INK: Color = Color(0.88, 1.0, 0.98, 1.0)

var _target: Control = null
var _screen_rect: Rect2 = Rect2()
var _use_screen_rect: bool = false
var _text: String = ""
var _show_arrow: bool = true
var _pulse: float = 0.0
var _panel: PanelContainer = null
var _label: Label = null

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	process_mode = Node.PROCESS_MODE_ALWAYS
	z_index = 500
	visible = false
	_build_label()
	if not Global.ui_scale_changed.is_connected(_on_ui_scale):
		Global.ui_scale_changed.connect(_on_ui_scale)

func _build_label() -> void:
	_panel = PanelContainer.new()
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.visible = false
	var sb := StyleBoxFlat.new()
	sb.bg_color = LABEL_BG
	sb.border_color = LABEL_BORDER
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(5)
	sb.content_margin_left = 9
	sb.content_margin_right = 9
	sb.content_margin_top = 6
	sb.content_margin_bottom = 6
	_panel.add_theme_stylebox_override("panel", sb)
	add_child(_panel)
	_label = Label.new()
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.add_theme_color_override("font_color", LABEL_INK)
	_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	_label.add_theme_constant_override("outline_size", 2)
	_panel.add_child(_label)
	_apply_font()

func _apply_font() -> void:
	if _label != null:
		_label.add_theme_font_size_override("font_size", Global.ui_font_size(11))

func set_target(control: Control, text: String, show_arrow: bool = true) -> void:
	_target = control
	_use_screen_rect = false
	_text = text
	_show_arrow = show_arrow
	_set_active(true)

## For markers drawn inside the map (they are not Controls). `rect` is in
## viewport/screen coordinates.
func set_screen_target(rect: Rect2, text: String, show_arrow: bool = true) -> void:
	_target = null
	_screen_rect = rect
	_use_screen_rect = true
	_text = text
	_show_arrow = show_arrow
	_set_active(true)

func clear_target() -> void:
	_target = null
	_screen_rect = Rect2()
	_use_screen_rect = false
	_text = ""
	_show_arrow = true
	_set_active(false)

func _set_active(on: bool) -> void:
	visible = on
	if _panel != null:
		_panel.visible = on and not _text.is_empty()
		if on and not _text.is_empty():
			_label.text = _text

func _on_ui_scale(_s: float) -> void:
	_apply_font()

func _current_rect() -> Rect2:
	if _use_screen_rect:
		return _screen_rect
	if _target == null or not is_instance_valid(_target):
		return Rect2()
	if not _target.is_visible_in_tree():
		return Rect2()
	var r := _target.get_global_rect()
	if r.size.x <= 1.0 or r.size.y <= 1.0:
		return Rect2()
	return r

func _process(delta: float) -> void:
	if not visible:
		return
	_pulse += delta
	var r := _current_rect()
	if r.size == Vector2.ZERO:
		clear_target()
		return
	_layout_label(r)
	queue_redraw()

func _layout_label(r: Rect2) -> void:
	if _panel == null or _label == null or _text.is_empty():
		return
	var s := Global.ui_scale
	var content := Global.ui_content_rect()
	var width := minf(content.size.x - 20.0 * s, 380.0 * s)
	width = maxf(220.0, width)
	_label.custom_minimum_size.x = width - 20.0 * s
	_panel.size = Vector2(width, 0.0)
	_panel.reset_size()
	var h := maxf(34.0 * s, _panel.get_combined_minimum_size().y)
	var x := clampf(r.position.x + r.size.x * 0.5 - width * 0.5,
		content.position.x + 8.0 * s, content.end.x - width - 8.0 * s)
	var above := r.position.y - h - 12.0 * s
	var y := above
	if above < content.position.y + 8.0 * s:
		y = r.end.y + 10.0 * s
	_panel.position = Vector2(x, y)
	_panel.size = Vector2(width, h)

func _draw() -> void:
	if not visible:
		return
	var r := _current_rect()
	if r.size == Vector2.ZERO:
		return
	var s := Global.ui_scale
	var wave: float = 0.5 + 0.5 * sin(_pulse * 4.0)
	var grow := 3.0 * s + wave * 2.0 * s
	var box := r.grow(grow)
	var fill := Color(OUTLINE.r, OUTLINE.g, OUTLINE.b, 0.04 + 0.04 * wave)
	draw_rect(box, fill, true)
	var col := Color(OUTLINE.r, OUTLINE.g, OUTLINE.b, 0.72 + 0.25 * wave)
	draw_rect(box, col, false, 2.0 * s)
	# Aiming arrow above the target, pointing into it. The settings tour uses
	# highlight-only steps, so the arrow can be disabled per target.
	if _show_arrow:
		var cx: float = box.position.x + box.size.x * 0.5
		var ay: float = box.position.y - 18.0 * s - wave * 3.0 * s
		var pts := PackedVector2Array([
			Vector2(cx, ay + 14.0 * s),
			Vector2(cx - 9.0 * s, ay),
			Vector2(cx + 9.0 * s, ay),
		])
		draw_colored_polygon(pts, col)
		draw_polyline(PackedVector2Array([pts[0], pts[1], pts[2], pts[0]]),
			Color(0.02, 0.12, 0.14, 0.95), 1.2 * s)
	# Corner brackets keep the highlight readable on busy screenshots.
	var c := 12.0 * s
	for sx in [-1.0, 1.0]:
		for sy in [-1.0, 1.0]:
			var px: float = box.position.x + (0.0 if sx < 0.0 else box.size.x)
			var py: float = box.position.y + (0.0 if sy < 0.0 else box.size.y)
			draw_line(Vector2(px, py), Vector2(px + c * sx, py), OUTLINE_SOFT, 3.0 * s)
			draw_line(Vector2(px, py), Vector2(px, py + c * sy), OUTLINE_SOFT, 3.0 * s)
