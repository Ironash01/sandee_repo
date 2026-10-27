extends Control
class_name TutorialDialogue

# ── RPG-style onboarding dialogue ───────────────────────────────────
# A single reusable full-screen dialogue surface. It owns the pause/modal
# lifecycle, a responsive bottom panel, character portraits, a typewriter line,
# and a complete-then-advance input rule:
#
#   first click / tap / Enter while text is appearing -> reveal the whole line
#   next input                                        -> advance exactly one line
#
# This deliberately intercepts input before the player/world sees it, so a
# joystick drag or gameplay tap cannot advance extra lines. The director opens
# and closes conversations; it never polls dialogue state every frame.

signal finished
signal dismissed
signal line_changed(line_index: int)
signal skip_requested

const PY_SAN_PORTRAIT: String = "res://sprites/char/pysan.png"
const LUA_PORTRAIT: String = "res://sprites/char/lua/front.png"
const C_PANEL := Color(0.055, 0.075, 0.145, 0.985)
const C_BORDER := Color(0.30, 0.43, 0.72, 1.0)
const C_TITLE := Color(0.86, 0.94, 1.0, 1.0)
const C_NAME := Color(1.0, 0.84, 0.47, 1.0)
const C_MUTED := Color(0.58, 0.69, 0.88, 1.0)
const C_HINT := Color(0.55, 0.83, 0.95, 1.0)
const TYPE_SPEED: float = 52.0
const INPUT_GUARD_MS: int = 100

var _dialog_panel: PanelContainer = null
var _portrait_frame: PanelContainer = null
var _portrait: TextureRect = null
var _name_label: Label = null
var _text_label: Label = null
var _continue_label: Label = null
var _text_scroll: ScrollContainer = null
var _skip_button: Button = null

var _lines: Array = []
var _line_index: int = 0
var _active: bool = false
var _typing: bool = false
var _revealed: float = 0.0
var _owns_ui_pause: bool = false
var _owns_hud_hide: bool = false
var _done_callback: Callable = Callable()
var _last_input_ms: int = -1000

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	_build()
	get_viewport().size_changed.connect(_layout)
	if not Global.ui_scale_changed.is_connected(_on_ui_scale_changed):
		Global.ui_scale_changed.connect(_on_ui_scale_changed)
	_layout()

func _exit_tree() -> void:
	if _active:
		_release_modal()

func _build() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0.0, 0.0, 0.0, 0.42)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)

	_dialog_panel = PanelContainer.new()
	_dialog_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_dialog_panel)
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = C_PANEL
	panel_style.border_color = C_BORDER
	panel_style.set_border_width_all(2)
	panel_style.set_corner_radius_all(9)
	_dialog_panel.add_theme_stylebox_override("panel", panel_style)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	_dialog_panel.add_child(row)

	_portrait_frame = PanelContainer.new()
	_portrait_frame.custom_minimum_size = Vector2(132, 132)
	_portrait_frame.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_portrait_frame.add_theme_stylebox_override("panel", _portrait_style())
	row.add_child(_portrait_frame)
	_portrait = TextureRect.new()
	_portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_portrait.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_portrait.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_portrait.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_portrait_frame.add_child(_portrait)

	var content := VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 6)
	row.add_child(content)

	_name_label = Label.new()
	_name_label.add_theme_color_override("font_color", C_NAME)
	content.add_child(_name_label)

	var rule := ColorRect.new()
	rule.color = Color(0.24, 0.42, 0.70, 0.75)
	rule.custom_minimum_size = Vector2(0, 1)
	content.add_child(rule)

	_text_scroll = ScrollContainer.new()
	_text_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_text_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	_text_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_text_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(_text_scroll)
	_text_label = Label.new()
	_text_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	_text_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_text_label.add_theme_color_override("font_color", C_TITLE)
	_text_scroll.add_child(_text_label)

	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", 8)
	content.add_child(footer)
	var hint := Label.new()
	hint.text = "Tap to continue   •   Back closes" if Global.is_mobile() else "Click or Enter to continue   •   Esc closes"
	hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hint.add_theme_color_override("font_color", C_MUTED)
	footer.add_child(hint)
	_continue_label = Label.new()
	_continue_label.text = "▼  CONTINUE"
	_continue_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_continue_label.add_theme_color_override("font_color", C_HINT)
	_continue_label.visible = false
	footer.add_child(_continue_label)

	_skip_button = Button.new()
	_skip_button.name = "SkipLessonButton"
	_skip_button.text = "SKIP LESSON"
	_skip_button.focus_mode = Control.FOCUS_NONE
	_skip_button.mouse_filter = Control.MOUSE_FILTER_STOP
	_skip_button.tooltip_text = "Skip the current onboarding lesson."
	_skip_button.add_theme_color_override("font_color", Color(0.92, 0.97, 1.0, 1.0))
	var skip_style := StyleBoxFlat.new()
	skip_style.bg_color = Color(0.10, 0.16, 0.28, 0.94)
	skip_style.border_color = Color(0.38, 0.63, 0.88, 0.95)
	skip_style.set_border_width_all(1)
	skip_style.set_corner_radius_all(5)
	_skip_button.add_theme_stylebox_override("normal", skip_style)
	var skip_hover := skip_style.duplicate() as StyleBoxFlat
	skip_hover.bg_color = Color(0.18, 0.30, 0.48, 0.98)
	skip_hover.border_color = Color(0.65, 0.88, 1.0, 1.0)
	_skip_button.add_theme_stylebox_override("hover", skip_hover)
	_skip_button.add_theme_stylebox_override("pressed", skip_style)
	_skip_button.pressed.connect(_on_skip_button_pressed)
	_skip_button.visible = false
	add_child(_skip_button)

	var hint_size_cb := func(_s: float) -> void:
		hint.add_theme_font_size_override("font_size", Global.ui_font_size(9))
	hint_size_cb.call(Global.ui_scale)

func _portrait_style() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.10, 0.13, 0.23, 1.0)
	sb.border_color = Color(0.33, 0.53, 0.78, 1.0)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(5)
	sb.content_margin_left = 8
	sb.content_margin_right = 8
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	return sb

func _layout() -> void:
	if _dialog_panel == null or not is_inside_tree():
		return
	var s: float = Global.ui_scale
	var content := Global.ui_content_rect()
	var margin: float = maxf(8.0, 16.0 * s)
	var panel_width: float = minf(content.size.x - margin * 2.0, 1040.0 * s)
	panel_width = maxf(320.0, panel_width)
	var panel_height: float = clampf(content.size.y * 0.29, 136.0 * s, 280.0 * s)
	panel_height = minf(panel_height, content.size.y - margin * 2.0)
	_dialog_panel.position = Vector2(
		content.position.x + (content.size.x - panel_width) * 0.5,
		content.end.y - panel_height - margin)
	_dialog_panel.size = Vector2(panel_width, panel_height)

	# Keep the portrait a framed character card rather than letting it stretch
	# to the full dialogue height. The cap also keeps Py-San's 64x64 sprite from
	# swallowing the text column on large desktop windows.
	var portrait_size: float = minf(panel_height - 32.0 * s, 104.0 * s)
	portrait_size = maxf(portrait_size, 72.0 * s)
	_portrait_frame.custom_minimum_size = Vector2(portrait_size, portrait_size)
	_portrait_frame.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_name_label.add_theme_font_size_override("font_size", Global.ui_font_size(17))
	_text_label.add_theme_font_size_override("font_size", Global.ui_font_size(14))
	_text_label.add_theme_constant_override("line_spacing", int(4.0 * s))
	_continue_label.add_theme_font_size_override("font_size", Global.ui_font_size(10))
	# Footer hint has no stored reference; update every Label in the footer.
	var footer := _continue_label.get_parent() as HBoxContainer
	if footer != null:
		for child in footer.get_children():
			if child is Label:
				(child as Label).add_theme_font_size_override("font_size", Global.ui_font_size(9))
	# A vertical scrollbar is fine while a long line is being typed; the dialogue
	# itself stays fixed at the bottom of the safe content area.
	var text_width: float = maxf(120.0, panel_width - portrait_size - 58.0 * s)
	_text_label.custom_minimum_size.x = text_width
	if _skip_button != null:
		var skip_w: float = clampf(174.0 * s, 76.0 * s, content.size.x * 0.34)
		var skip_h: float = maxf(36.0 * s, float(Global.ui_font_size(10)) + 18.0 * s)
		var skip_margin: float = 12.0 * s
		_skip_button.position = Vector2(content.end.x - skip_w - skip_margin,
			content.position.y + skip_margin)
		_skip_button.size = Vector2(skip_w, skip_h)
		_skip_button.text = "SKIP LESSON" if skip_w >= 126.0 * s else "SKIP"
		_skip_button.add_theme_font_size_override("font_size", Global.ui_font_size(10))

func _on_ui_scale_changed(_s: float) -> void:
	_layout()

func show_conversation(lines: Array, done: Callable = Callable()) -> bool:
	if _active or lines.is_empty():
		return false
	# Never stomp another modal (inventory, crafting, editor, pause menu).
	if Global.any_ui_open() or Global.pause_menu_open:
		return false
	_lines = lines.duplicate(true)
	_line_index = 0
	_done_callback = done
	_active = true
	visible = true
	if _skip_button != null:
		_skip_button.visible = true
	# A hold-to-interact PNC order can still be running when a lesson finishes
	# and the next dialogue opens. Cancel it before taking the modal pause.
	var p := Global.player_node
	if is_instance_valid(p) and p.has_method("_pnc_cancel"):
		p.call("_pnc_cancel")
	Global.open_ui()
	_owns_ui_pause = true
	Global.register_ui_back(self, Callable(self, "dismiss"))
	Global.modal_hud_changed.emit(true)
	_owns_hud_hide = true
	_layout()
	_show_line(0)
	return true

func is_active() -> bool:
	return _active

func current_line_index() -> int:
	return _line_index

func _show_line(index: int) -> void:
	if index < 0 or index >= _lines.size():
		_finish()
		return
	_line_index = index
	var line: Dictionary = _lines[index] as Dictionary
	_name_label.text = str(line.get("speaker", "Guide"))
	var portrait_path: String = str(line.get("portrait", PY_SAN_PORTRAIT))
	var tex := load(portrait_path) as Texture2D
	_portrait.texture = tex
	_portrait_frame.visible = tex != null
	_text_label.text = str(line.get("text", ""))
	_text_label.visible_characters = 0
	_revealed = 0.0
	_typing = not _text_label.text.is_empty()
	_continue_label.visible = false
	line_changed.emit(index)
	if not _typing:
		_finish_typing()

func _process(delta: float) -> void:
	if not _active:
		return
	if _typing:
		_revealed += TYPE_SPEED * delta
		var total: int = _text_label.text.length()
		_text_label.visible_characters = mini(total, int(_revealed))
		if _text_label.visible_characters >= total:
			_finish_typing()
	# Gentle continue-indicator blink once the line is fully readable.
	if not _typing:
		_continue_label.modulate.a = 0.55 + 0.45 * (0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.006))

func _finish_typing() -> void:
	_typing = false
	_text_label.visible_characters = -1
	_continue_label.visible = true
	_continue_label.modulate.a = 1.0

func advance_from_input() -> void:
	if not _active:
		return
	var now := Time.get_ticks_msec()
	if now - _last_input_ms < INPUT_GUARD_MS:
		return
	_last_input_ms = now
	if _typing:
		_finish_typing()
		return
	if _line_index + 1 < _lines.size():
		_show_line(_line_index + 1)
	else:
		_finish()

func _input(event: InputEvent) -> void:
	if not _active:
		return
	# PNC synthesizes mouse presses/releases to drive the normal interaction
	# path. They are gameplay, not dialogue input.
	if event.has_meta("pnc_synthetic"):
		return
	# Let the real GUI Button consume clicks/taps on the top-right Skip control.
	# Returning here without marking the event handled would lose the button
	# press; returning with handling would make the Button forever unreachable.
	if _skip_button != null and _skip_button.visible:
		var skip_pos := Vector2.INF
		if event is InputEventMouseButton:
			skip_pos = (event as InputEventMouseButton).position
		elif event is InputEventScreenTouch:
			skip_pos = (event as InputEventScreenTouch).position
		if skip_pos != Vector2.INF \
				and _skip_button.get_global_rect().has_point(skip_pos):
			return
	# Back closes the conversation and releases the pause; it does not jump to
	# the next line. The director may reopen the current lesson later.
	if event.is_action_pressed("ui_cancel"):
		Global.request_ui_back(event)
		get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			advance_from_input()
			get_viewport().set_input_as_handled()
		return
	if event is InputEventScreenTouch:
		if (event as InputEventScreenTouch).pressed:
			advance_from_input()
			get_viewport().set_input_as_handled()
		return
	if event is InputEventScreenDrag:
		# Swallow joystick/touch drags while the dialogue owns the screen.
		get_viewport().set_input_as_handled()
		return
	if event is InputEventKey:
		var key := event as InputEventKey
		if key.pressed and not key.echo and (key.keycode == KEY_ENTER \
				or key.keycode == KEY_KP_ENTER or key.keycode == KEY_SPACE):
			advance_from_input()
			get_viewport().set_input_as_handled()
		return
	if event is InputEventJoypadButton:
		var jb := event as InputEventJoypadButton
		if jb.pressed and jb.button_index == JOY_BUTTON_A:
			advance_from_input()
			get_viewport().set_input_as_handled()

func _on_skip_button_pressed() -> void:
	if _active:
		skip_requested.emit()

func _finish() -> void:
	if not _active:
		return
	var cb := _done_callback
	_done_callback = Callable()
	_active = false
	visible = false
	if _skip_button != null:
		_skip_button.visible = false
	_release_modal()
	finished.emit()
	if cb.is_valid():
		cb.call_deferred()

func dismiss() -> void:
	if not _active:
		return
	_active = false
	visible = false
	if _skip_button != null:
		_skip_button.visible = false
	_done_callback = Callable()
	_release_modal()
	dismissed.emit()

func _release_modal() -> void:
	if _owns_ui_pause:
		_owns_ui_pause = false
		Global.unregister_ui_back(self)
		Global.close_ui()
	if _owns_hud_hide:
		_owns_hud_hide = false
		Global.modal_hud_changed.emit(false)
