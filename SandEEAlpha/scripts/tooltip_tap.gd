extends Node

# ── Tap tooltips ──────────────────────────────────────────────────
# Godot's built-in tooltips only appear on MOUSE HOVER. On a touch screen a tap
# has no hover step, so this node shows the tapped control's tooltip_text as a
# small popup for a moment. On desktop (no touch) it stays out of the way — the
# built-in hover tooltip already covers it.
#
# Added by game_instance; owns its own high CanvasLayer (60).

const SHOW_SEC: float = 2.2

var _popup: PanelContainer = null
var _label: Label = null
var _style: StyleBoxFlat = null
var _timer: float = 0.0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var layer := CanvasLayer.new()
	layer.layer = 60
	layer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(layer)

	_popup = PanelContainer.new()
	_popup.visible = false
	_popup.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_style = StyleBoxFlat.new()
	_style.bg_color = Color(0.08, 0.10, 0.20, 0.98)
	_style.border_color = Color(0.22, 0.32, 0.58, 1.0)
	_popup.add_theme_stylebox_override("panel", _style)
	layer.add_child(_popup)

	_label = Label.new()
	_label.add_theme_color_override("font_color", Color(0.80, 0.90, 1.0))
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_popup.add_child(_label)
	Global.ui_scale_changed.connect(func(_s: float) -> void: _apply_scale())
	_apply_scale()

func _input(event: InputEvent) -> void:
	var pos := Vector2.INF
	if event is InputEventScreenTouch and event.pressed:
		pos = event.position
	elif event is InputEventMouseButton and event.pressed \
			and event.button_index == MOUSE_BUTTON_LEFT \
			and DisplayServer.is_touchscreen_available():
		pos = event.position
	if pos == Vector2.INF:
		return
	_show_at(pos)

func _apply_scale() -> void:
	var s: float = Global.ui_scale
	_style.set_border_width_all(maxi(1, int(2 * s)))
	_style.set_corner_radius_all(int(4 * s))
	_style.content_margin_left = int(10 * s)
	_style.content_margin_right = int(10 * s)
	_style.content_margin_top = int(7 * s)
	_style.content_margin_bottom = int(7 * s)
	_label.add_theme_font_size_override("font_size",
		Global.ui_type_size(Global.UI_TYPE_LABEL))
	_label.custom_minimum_size = Vector2(int(190 * s), 0)

func _show_at(pos: Vector2) -> void:
	var ctrl: Control = get_viewport().gui_get_hovered_control()
	if ctrl == null:
		return
	var text: String = ctrl.tooltip_text
	# Walk up: a Label inside a row often carries the tooltip on the row.
	var p := ctrl.get_parent()
	while p is Control and text.is_empty():
		text = (p as Control).tooltip_text
		p = p.get_parent()
	if text.is_empty():
		return
	_label.text = text
	_popup.visible = true
	_popup.reset_size()
	var vp := get_viewport().get_visible_rect().size
	var sz := _popup.get_combined_minimum_size()
	var safe := Global.ui_safe_insets
	_popup.position = Vector2(
		clampf(pos.x, safe.x + 4.0, maxf(safe.x + 4.0, vp.x - safe.z - sz.x - 4.0)),
		clampf(pos.y - sz.y - 10.0, safe.y + 4.0,
			maxf(safe.y + 4.0, vp.y - safe.w - sz.y - 4.0)))
	_timer = SHOW_SEC

func _process(delta: float) -> void:
	if not _popup.visible:
		return
	_timer -= delta
	if _timer <= 0.0:
		_popup.visible = false
