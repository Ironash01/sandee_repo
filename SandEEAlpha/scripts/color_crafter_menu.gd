extends Control

# ── Color Crafter menu ─────────────────────────────────────────────
# Opened by clicking a placed Color Crafter. Offers BOTH a hue/saturation
# wheel (+ value slider) AND R/G/B sliders with text boxes — either drives the
# same colour. Craft consumes 1 Cactus and produces a 32x32 colour block (1px
# black outline + the chosen fill) generated at runtime by ColorBlock, so no
# per-colour art is needed. Pure black (0,0,0) and pure white (255,255,255)
# are rejected.
#
# STANDING RULE: every size is multiplied by Global.ui_scale.

const CACTUS_DATA:  ItemData = preload("res://resources/items/cactus.tres")
const WHEEL_SCRIPT: GDScript = preload("res://scripts/color_wheel.gd")

const C_PANEL   := Color(0.08, 0.10, 0.20, 0.97)
const C_BORDER  := Color(0.22, 0.32, 0.58, 1.00)
const C_TITLE   := Color(0.80, 0.90, 1.00, 1.00)
const C_MUTED   := Color(0.55, 0.65, 0.85, 1.00)
const C_OVERLAY := Color(0.00, 0.00, 0.00, 0.55)
const C_OK      := Color(0.20, 0.45, 0.20, 1.00)
const C_WARN    := Color(1.00, 0.65, 0.45, 1.00)

var _r: int = 128
var _g: int = 128
var _b: int = 200
var _h: float = 0.60
var _s: float = 0.50
var _v: float = 0.78

var _updating: bool = false
var _root: Control = null
var _sliders: Array = []      # [R, G, B] HSliders
var _edits:   Array = []      # [R, G, B] LineEdits
var _value_slider: HSlider = null
var _wheel: Control = null
var _swatch: ColorRect = null
var _hint: Label = null
var _cactus_label: Label = null

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_preset(Control.PRESET_FULL_RECT)
	visible = false
	_build()
	_fit()
	_refresh_all()
	if not Global.ui_scale_changed.is_connected(_on_ui_scale):
		Global.ui_scale_changed.connect(_on_ui_scale)

# A Control parented to a CanvasLayer is NOT auto-sized — pin it to the
# viewport so the overlay/panel fill the screen.
func _fit() -> void:
	position = Vector2.ZERO
	size = get_viewport_rect().size

func _on_ui_scale(_s: float) -> void:
	var was: bool = visible
	_rebuild()
	visible = was

func open() -> void:
	visible = true
	_fit()
	Global.open_ui()
	_refresh_all()

func hide_menu() -> void:
	if not visible:
		return
	visible = false
	Global.close_ui()

func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		hide_menu()
		get_viewport().set_input_as_handled()

func _rebuild() -> void:
	if _root != null:
		_root.queue_free()
		_root = null
	_sliders.clear(); _edits.clear()
	_value_slider = null; _wheel = null; _swatch = null; _hint = null; _cactus_label = null
	_build()

func _build() -> void:
	var s: float = Global.ui_scale
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(root)
	_root = root

	var overlay := ColorRect.new()
	overlay.color = C_OVERLAY
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(overlay)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(int(440 * s), int(360 * s))
	var ps := StyleBoxFlat.new()
	ps.bg_color = C_PANEL; ps.border_color = C_BORDER
	ps.set_border_width_all(int(2 * s)); ps.set_corner_radius_all(int(8 * s))
	ps.content_margin_left = int(20 * s); ps.content_margin_right = int(20 * s)
	ps.content_margin_top = int(16 * s); ps.content_margin_bottom = int(16 * s)
	panel.add_theme_stylebox_override("panel", ps)
	center.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", int(10 * s))
	panel.add_child(vbox)

	var title := Label.new()
	title.text = "COLOR CRAFTER"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", int(16 * s))
	title.add_theme_color_override("font_color", C_TITLE)
	vbox.add_child(title)

	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", int(14 * s))
	vbox.add_child(body)

	# ── Left: wheel + value ──
	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", int(6 * s))
	body.add_child(left)
	_wheel = WHEEL_SCRIPT.new() as Control
	_wheel.custom_minimum_size = Vector2(int(150 * s), int(150 * s))
	_wheel.connect("picked", _on_wheel_picked)
	left.add_child(_wheel)
	var vrow := HBoxContainer.new()
	vrow.add_theme_constant_override("separation", int(6 * s))
	left.add_child(vrow)
	var vl := Label.new()
	vl.text = "Value"
	vl.add_theme_font_size_override("font_size", int(11 * s))
	vl.add_theme_color_override("font_color", C_MUTED)
	vrow.add_child(vl)
	_value_slider = HSlider.new()
	_value_slider.min_value = 0; _value_slider.max_value = 255
	_value_slider.custom_minimum_size = Vector2(int(92 * s), 0)
	_value_slider.value_changed.connect(_on_value_changed)
	vrow.add_child(_value_slider)

	# ── Right: RGB sliders + text boxes ──
	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", int(8 * s))
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(right)
	for i in range(3):
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", int(6 * s))
		right.add_child(row)
		var lbl := Label.new()
		lbl.text = ["R", "G", "B"][i]
		lbl.custom_minimum_size = Vector2(int(16 * s), 0)
		lbl.add_theme_font_size_override("font_size", int(12 * s))
		lbl.add_theme_color_override("font_color", C_MUTED)
		row.add_child(lbl)
		var sl := HSlider.new()
		sl.min_value = 0; sl.max_value = 255
		sl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		sl.value_changed.connect(_on_slider_changed.bind(i))
		row.add_child(sl)
		_sliders.append(sl)
		var ed := LineEdit.new()
		ed.custom_minimum_size = Vector2(int(48 * s), 0)
		ed.max_length = 3
		ed.alignment = HORIZONTAL_ALIGNMENT_CENTER
		ed.add_theme_font_size_override("font_size", int(12 * s))
		ed.text_submitted.connect(_on_edit_submitted.bind(i))
		ed.focus_exited.connect(_on_edit_committed.bind(i))
		row.add_child(ed)
		_edits.append(ed)

	var swrow := HBoxContainer.new()
	swrow.add_theme_constant_override("separation", int(10 * s))
	right.add_child(swrow)
	_swatch = ColorRect.new()
	_swatch.custom_minimum_size = Vector2(int(48 * s), int(48 * s))
	swrow.add_child(_swatch)
	_hint = Label.new()
	_hint.add_theme_font_size_override("font_size", int(11 * s))
	_hint.add_theme_color_override("font_color", C_MUTED)
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_hint.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	swrow.add_child(_hint)

	_cactus_label = Label.new()
	_cactus_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_cactus_label.add_theme_font_size_override("font_size", int(11 * s))
	_cactus_label.add_theme_color_override("font_color", C_MUTED)
	vbox.add_child(_cactus_label)

	var btn := Button.new()
	btn.text = "Craft  (uses 1 Cactus)"
	btn.custom_minimum_size = Vector2(0, int(36 * s))
	btn.add_theme_font_size_override("font_size", int(13 * s))
	var bs := StyleBoxFlat.new()
	bs.bg_color = C_OK; bs.border_color = C_BORDER
	bs.set_border_width_all(int(1 * s)); bs.set_corner_radius_all(int(4 * s))
	btn.add_theme_stylebox_override("normal", bs)
	btn.add_theme_stylebox_override("hover", bs)
	btn.pressed.connect(_craft)
	vbox.add_child(btn)

# ── Colour plumbing ────────────────────────────────────────────────
func _on_slider_changed(_val: float, idx: int) -> void:
	if _updating:
		return
	var vals: Array = [_r, _g, _b]
	vals[idx] = int(round((_sliders[idx] as HSlider).value))
	_set_rgb(vals[0], vals[1], vals[2])

func _on_edit_submitted(text: String, idx: int) -> void:
	_apply_edit(text, idx)
	(_edits[idx] as LineEdit).release_focus()

func _on_edit_committed(idx: int) -> void:
	_apply_edit((_edits[idx] as LineEdit).text, idx)

func _apply_edit(text: String, idx: int) -> void:
	var v: int = 0
	if text.strip_edges().is_valid_int():
		v = clampi(int(text), 0, 255)
	var vals: Array = [_r, _g, _b]
	vals[idx] = v
	_set_rgb(vals[0], vals[1], vals[2])

func _on_value_changed(val: float) -> void:
	if _updating:
		return
	_v = clampf(val / 255.0, 0.0, 1.0)
	var c := Color.from_hsv(_h, _s, _v)
	_set_rgb(int(round(c.r * 255.0)), int(round(c.g * 255.0)), int(round(c.b * 255.0)), true)

func _on_wheel_picked(h: float, s: float) -> void:
	if _updating:
		return
	_h = h
	_s = s
	var c := Color.from_hsv(_h, _s, _v)
	_set_rgb(int(round(c.r * 255.0)), int(round(c.g * 255.0)), int(round(c.b * 255.0)), true)

# Set the current colour from RGB. keep_hsv=true when the colour already came
# from the wheel/value path (don't recompute h/s/v from the 8-bit round-trip).
func _set_rgb(r: int, g: int, b: int, keep_hsv: bool = false) -> void:
	_r = clampi(r, 0, 255)
	_g = clampi(g, 0, 255)
	_b = clampi(b, 0, 255)
	if not keep_hsv:
		var c := Color8(_r, _g, _b)
		_h = c.h
		_s = c.s
		_v = c.v
	_refresh_all()

func _refresh_all() -> void:
	_updating = true
	var vals: Array = [_r, _g, _b]
	for i in range(3):
		if i < _sliders.size():
			(_sliders[i] as HSlider).value = vals[i]
		if i < _edits.size():
			(_edits[i] as LineEdit).text = str(vals[i])
	if _value_slider != null:
		_value_slider.value = _v * 255.0
	if _wheel != null:
		_wheel.call("set_hs", _h, _s)
		_wheel.call("set_value", _v)
	if _swatch != null:
		_swatch.color = Color8(_r, _g, _b)
	_updating = false
	_update_cactus_label()

func _update_cactus_label() -> void:
	if _cactus_label == null:
		return
	_cactus_label.text = "Cactus available: %d" % Global.count_item(CACTUS_DATA)

# ── Craft ──────────────────────────────────────────────────────────
func _craft() -> void:
	if ColorBlock.is_forbidden(_r, _g, _b):
		_set_hint("Pure black and pure white are not allowed.", true)
		return
	if Global.count_item(CACTUS_DATA) < 1:
		_set_hint("You need a cactus to craft.", true)
		return
	Global.remove_item(CACTUS_DATA)
	var blk: ItemData = ColorBlock.get_block(_r, _g, _b)
	Global.add_item({"data": blk, "quantity": 1})
	_set_hint("Crafted a Color Block (#%s)." % ColorBlock.key_for(_r, _g, _b), false)
	_update_cactus_label()

func _set_hint(text: String, warn: bool = false) -> void:
	if _hint != null:
		_hint.text = text
		_hint.add_theme_color_override("font_color", C_WARN if warn else C_MUTED)
