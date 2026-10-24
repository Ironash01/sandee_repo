extends Control

# ── Gameplay FPS overlay ─────────────────────────────────────────────────────
# Small read-only readout in the top-right strip, left of the Pause button. It
# lives on the background HUD CanvasLayer, scales with Global.ui_scale, and is
# mouse-transparent so it can never steal a world tap or HUD press.

const UPDATE_SEC: float = 0.25
const BASE_FONT_SIZE: float = 13.0
const BASE_WIDTH: float = 108.0
const BASE_HEIGHT: float = 26.0
const TOP_OFFSET: float = 10.0
# Pause button: right margin 8 + width 60 + 8px gap. Kept fixed because the
# scene's PauseButton uses fixed offsets on every resolution.
const PAUSE_STRIP: float = 76.0

var _label: Label = null
var _elapsed: float = 0.0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fit_to_viewport()
	if not get_viewport().size_changed.is_connected(_fit_to_viewport):
		get_viewport().size_changed.connect(_fit_to_viewport)

	_label = Label.new()
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 0.95))
	_label.add_theme_color_override("font_outline_color", Color(0.02, 0.03, 0.07, 0.95))
	add_child(_label)

	Global.show_fps_changed.connect(_on_show_fps_changed)
	Global.ui_scale_changed.connect(_on_ui_scale_changed)
	_apply_scale()
	visible = Global.show_fps
	set_process(Global.show_fps)
	_refresh_fps()

func _fit_to_viewport() -> void:
	# Top-left anchors + an explicit viewport-sized rect: a full-rect preset
	# would make Godot override any manual size after _ready (and warn on every
	# launch). We only need a transparent surface; the label is positioned from
	# the live viewport rect in _apply_scale().
	set_anchors_preset(Control.PRESET_TOP_LEFT)
	position = Vector2.ZERO
	size = get_viewport_rect().size
	_apply_scale()

func _process(delta: float) -> void:
	_elapsed += delta
	if _elapsed < UPDATE_SEC:
		return
	_elapsed = 0.0
	_refresh_fps()

func _refresh_fps() -> void:
	if _label == null:
		return
	_label.text = "FPS %d" % int(Engine.get_frames_per_second())

func _on_show_fps_changed(enabled: bool) -> void:
	visible = enabled
	set_process(enabled)
	_elapsed = UPDATE_SEC
	if enabled:
		_refresh_fps()

func _on_ui_scale_changed(_scale: float) -> void:
	_apply_scale()

# Position from the live viewport rect (not the parent's rect) so Android
# stretch and window resizes keep the readout beside the Pause button. The
# viewport size_changed signal re-runs this, so there is no per-frame layout.
func _apply_scale() -> void:
	if _label == null:
		return
	var s: float = maxf(Global.ui_scale, 0.5)
	var font_size: int = maxi(10, int(BASE_FONT_SIZE * s))
	var width: float = maxf(BASE_WIDTH * s, font_size * 5.0)
	var height: float = maxf(BASE_HEIGHT * s, font_size + 8.0 * s)
	var top: float = TOP_OFFSET * s
	var vp: Vector2 = get_viewport_rect().size
	_label.add_theme_font_size_override("font_size", font_size)
	_label.add_theme_constant_override("outline_size", maxi(2, int(4.0 * s)))
	_label.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_label.position = Vector2(vp.x - PAUSE_STRIP - width, top)
	_label.size = Vector2(width, height)
