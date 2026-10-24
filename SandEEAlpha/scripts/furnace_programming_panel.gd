extends Control

# ── Furnace Programming panel ─────────────────────────────────────
# A Python editor that drives a furnace through its FurnacePythonHost
# (load / smelt / take_output / input_* / fuel_* / output_*). Modelled on the
# Crafting Station's Programming tab, but self-contained.
#
# STANDING RULE: every size is multiplied by Global.ui_scale.

const C_PANEL   := Color(0.08, 0.10, 0.20, 0.97)
const C_BORDER  := Color(0.22, 0.32, 0.58, 1.00)
const C_TITLE   := Color(0.80, 0.90, 1.00, 1.00)
const C_MUTED   := Color(0.55, 0.65, 0.85, 1.00)
const C_OVERLAY := Color(0.00, 0.00, 0.00, 0.72)
const C_EDITOR  := Color(0.05, 0.07, 0.14, 1.00)
const C_OUTPUT  := Color(0.04, 0.05, 0.10, 1.00)
const C_OK      := Color(0.20, 0.45, 0.20, 1.00)
const C_ERR     := Color(0.45, 0.20, 0.20, 1.00)
# preload (not class_name) so name-argument completion works before the class
# global is registered by the editor.
const NameComplete: GDScript = preload("res://scripts/lua_name_complete.gd")
const PYTHON_SPEC: LanguageSpecification = preload("res://resources/python_language_spec.tres")

var furnace: Node = null

var _root:   Control = null
var _panel_center: CenterContainer = null   # keyboard-aware centring area
var _code:   CodeEdit = null
var _output: RichTextLabel = null
var _hint:   Label = null
var _name_popup: PopupPanel = null
var _name_list:  ItemList = null

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_preset(Control.PRESET_FULL_RECT)
	visible = false
	_build()
	_fit()
	if not Global.ui_scale_changed.is_connected(_on_ui_scale):
		Global.ui_scale_changed.connect(_on_ui_scale)

func _fit() -> void:
	position = Vector2.ZERO
	size     = get_viewport_rect().size

func _on_ui_scale(_s: float) -> void:
	var was: bool = visible
	if _root != null:
		_root.queue_free()
		_root = null
	_build()
	_fit()
	visible = was

func open(furnace_node: Node) -> void:
	furnace = furnace_node
	_fit()
	visible = true
	if _code != null and furnace != null:
		var saved: String = str(furnace.get("program_code"))
		if saved.strip_edges().is_empty():
			_code.text = "# item ids: iron_ore, charcoal\n# feed(\"iron_ore\", 5)\n# fuel(\"charcoal\", 3)\n# smelt(5)\n# take_output()\n"
		else:
			_code.text = saved
	_connect_host()
	Global.open_ui()
	Global.register_ui_back(self, Callable(self, "_back"))
	if _code != null:
		_code.grab_focus()

func _back() -> void:
	if _name_popup != null and _name_popup.visible:
		_name_popup.hide()
		if visible:
			Global.register_ui_back(self, Callable(self, "_back"))
		return
	close()

func close() -> void:
	if not visible:
		return
	# Closing the editor must never discard user-written code: persist the
	# current draft on the furnace, exactly like the crafting station does.
	if furnace != null and _code != null:
		furnace.set("program_code", _code.text)
	visible = false
	Global.unregister_ui_back(self)
	Global.close_ui()

func _input(event: InputEvent) -> void:
	if not visible:
		return
	# The item-name suggestion popup is a layer above the editor.
	if _name_popup != null and _name_popup.visible and event.is_action_pressed("escape"):
		Global.consume_ui_back_event(event)
		_name_popup.hide()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("escape"):
		# Escape is a command, not typed text: it must still work while the
		# CodeEdit owns keyboard focus.
		get_viewport().set_input_as_handled()
		if not Global.request_ui_back(event) and not Global.is_ui_back_event_consumed(event):
			close()

# Android: keep the furnace Algorithmica panel above the software keyboard.
func _process(_delta: float) -> void:
	if not visible or _panel_center == null:
		return
	var inset: float = Global.mobile_keyboard_height()
	if not is_equal_approx(_panel_center.offset_bottom, -inset):
		_panel_center.offset_bottom = -inset

func _connect_host() -> void:
	if furnace == null:
		return
	var host: Node = furnace.call("get_program_host")
	if host == null:
		return
	if not host.is_connected("signal_print", _on_print):
		host.connect("signal_print", _on_print)
	if not host.is_connected("code_failed", _on_failed):
		host.connect("code_failed", _on_failed)
	if not host.is_connected("code_executed", _on_executed):
		host.connect("code_executed", _on_executed)

func _run() -> void:
	if furnace == null or _code == null:
		return
	# A furnace program may only use furnace functions (the host enforces this
	# too). Check here so the error lands in the visible output panel.
	var foreign := AlgorithmicaAPI.foreign_calls(_code.text, AlgorithmicaAPI.FURNACE)
	if not foreign.is_empty():
		_output.clear()
		_output.append_text("[color=#ff8888]✗ %s[/color]\n"
			% AlgorithmicaAPI.rejection_message(foreign, AlgorithmicaAPI.FURNACE))
		return
	_connect_host()
	_output.clear()
	_output.append_text("[color=#aaddff]Running…[/color]\n")
	furnace.call("run_program", _code.text)

# ── Item-name popup for feed()/fuel() ─────────────────────────────
func _caret_index() -> int:
	var idx: int = 0
	for ln in range(_code.get_caret_line()):
		idx += _code.get_line(ln).length() + 1
	return idx + _code.get_caret_column()

func _on_code_caret_changed() -> void:
	if _name_popup == null:
		return
	if NameComplete.name_arg_open(_code.text, _caret_index()):
		_open_name_popup()
	else:
		_name_popup.hide()

func _open_name_popup() -> void:
	if _name_popup.visible:
		return
	_name_list.clear()
	# Carried items first (inventory + hotbar), then the full catalogue — every
	# entry is the scripting id the program should use.
	var seen: Dictionary = {}
	for data in Global.list_carried_items():
		_name_list.add_item("%s   (%s)" % [data.item_id(), data.item_name])
		_name_list.set_item_metadata(_name_list.item_count - 1, data.item_id())
		seen[data.item_id()] = true
	for id in Global.all_item_ids():
		if seen.has(id):
			continue
		_name_list.add_item(id)
		_name_list.set_item_metadata(_name_list.item_count - 1, id)
	var local: Vector2 = _code.get_caret_draw_pos()
	_name_popup.position = Vector2i(_code.get_screen_position() + local) + Vector2i(0, 22)
	_name_popup.popup()

func _on_name_item_selected(idx: int) -> void:
	var id: String = str(_name_list.get_item_metadata(idx))
	if id.is_empty():
		id = _name_list.get_item_text(idx).split("   (")[0]
	_code.insert_text_at_caret("\"%s\"" % id)
	_name_popup.hide()
	_code.grab_focus()

func _on_print(s: String) -> void:
	if _output != null:
		_output.append_text(s + "\n")

func _on_failed(e: String) -> void:
	if _output != null:
		_output.append_text("[color=#ff8888]Error: %s[/color]\n" % e)

func _on_executed() -> void:
	if _output != null:
		_output.append_text("[color=#88ffaa]✓ Finished running[/color]\n")

# Small target chip, matching the Programming Encyclopedia's Algorithmica
# target badges.
func _target_badge(s: float) -> Control:
	var col := Color(1.00, 0.66, 0.34, 1.00)
	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color     = Color(col.r, col.g, col.b, 0.16)
	sb.border_color = col
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(int(3 * s))
	sb.content_margin_left   = int(7 * s)
	sb.content_margin_right  = int(7 * s)
	sb.content_margin_top    = int(2 * s)
	sb.content_margin_bottom = int(2 * s)
	panel.add_theme_stylebox_override("panel", sb)
	panel.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var lbl := Label.new()
	lbl.text = AlgorithmicaAPI.FURNACE.to_upper()
	lbl.add_theme_font_size_override("font_size", int(9 * s))
	lbl.add_theme_color_override("font_color", col)
	panel.add_child(lbl)
	return panel

# ── Build ─────────────────────────────────────────────────────────
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
	_panel_center = center

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(int(560 * s), int(420 * s))
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

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", int(8 * s))
	vbox.add_child(header)
	var title := Label.new()
	title.text = "🐍  ALGORITHMICA — FURNACE"
	title.add_theme_font_size_override("font_size", int(16 * s))
	title.add_theme_color_override("font_color", C_TITLE)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	header.add_child(_target_badge(s))
	var close_btn := Button.new()
	close_btn.text = "✕"; close_btn.flat = true
	close_btn.tooltip_text = "Close the program editor."
	close_btn.add_theme_color_override("font_color", C_MUTED)
	close_btn.add_theme_font_size_override("font_size", int(13 * s))
	close_btn.pressed.connect(close)
	header.add_child(close_btn)

	# Reference line — target first, then the API. The badge wording matches the
	# Programming Encyclopedia's Algorithmica target labels.
	var ref := Label.new()
	ref.text = "TARGET: FURNACE  ·  feed(name, n) · fuel(name, n) · smelt(n) · take_output() · input_*/fuel_*/output_*"
	ref.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	ref.add_theme_font_size_override("font_size", int(11 * s))
	ref.add_theme_color_override("font_color", C_MUTED)
	vbox.add_child(ref)

	_code = CodeEdit.new()
	_code.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_code.custom_minimum_size = Vector2(0, int(150 * s))
	var es := StyleBoxFlat.new()
	es.bg_color = C_EDITOR; es.border_color = C_BORDER
	es.set_border_width_all(1); es.set_corner_radius_all(4)
	es.content_margin_left = int(8 * s); es.content_margin_right = int(8 * s)
	es.content_margin_top = int(8 * s); es.content_margin_bottom = int(8 * s)
	_code.add_theme_stylebox_override("normal", es)
	_code.add_theme_stylebox_override("focus", es)
	_code.add_theme_color_override("font_color", C_TITLE)
	_code.add_theme_font_size_override("font_size", int(13 * s))
	# Python syntax highlighting + light editor chrome. Without this the editor
	# was plain text AND CodeHighlighter's default token colours are pure black.
	_code.syntax_highlighter = LanguageSpecification.build_highlighter(PYTHON_SPEC)
	LanguageSpecification.style_code_edit(_code, C_TITLE, C_MUTED)
	_code.set_code_completion_enabled(true)
	_code.caret_changed.connect(_on_code_caret_changed)
	vbox.add_child(_code)

	# Item-name popup (feed/fuel args) — same helper the station editor uses.
	_name_popup = PopupPanel.new()
	var name_list := ItemList.new()
	name_list.custom_minimum_size = Vector2(int(200 * s), int(180 * s))
	name_list.add_theme_font_size_override("font_size", int(12 * s))
	name_list.item_selected.connect(_on_name_item_selected)
	_name_popup.add_child(name_list)
	_name_list = name_list
	add_child(_name_popup)

	var btn_row := HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", int(6 * s))
	vbox.add_child(btn_row)
	var run_btn := Button.new()
	run_btn.text = "▶  RUN"
	run_btn.tooltip_text = "Run the program now."
	run_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	run_btn.custom_minimum_size = Vector2(0, int(32 * s))
	run_btn.add_theme_font_size_override("font_size", int(13 * s))
	var rs := StyleBoxFlat.new(); rs.bg_color = C_OK; rs.border_color = C_BORDER
	rs.set_border_width_all(int(1 * s)); rs.set_corner_radius_all(int(4 * s))
	run_btn.add_theme_stylebox_override("normal", rs)
	run_btn.add_theme_stylebox_override("hover", rs)
	run_btn.add_theme_color_override("font_color", Color(0.8, 1.0, 0.8))
	run_btn.pressed.connect(_run)
	btn_row.add_child(run_btn)
	var clr_btn := Button.new()
	clr_btn.text = "✕ CLEAR"
	clr_btn.tooltip_text = "Clear the editor and the output."
	clr_btn.custom_minimum_size = Vector2(0, int(32 * s))
	clr_btn.add_theme_font_size_override("font_size", int(13 * s))
	var cs := StyleBoxFlat.new(); cs.bg_color = C_ERR; cs.border_color = C_BORDER
	cs.set_border_width_all(int(1 * s)); cs.set_corner_radius_all(int(4 * s))
	clr_btn.add_theme_stylebox_override("normal", cs)
	clr_btn.add_theme_stylebox_override("hover", cs)
	clr_btn.add_theme_color_override("font_color", Color(1.0, 0.8, 0.8))
	clr_btn.pressed.connect(func() -> void: _code.text = ""; _output.clear())
	btn_row.add_child(clr_btn)

	var out_panel := PanelContainer.new()
	out_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var op := StyleBoxFlat.new()
	op.bg_color = C_OUTPUT; op.border_color = C_BORDER
	op.set_border_width_all(1); op.set_corner_radius_all(4)
	op.content_margin_left = int(8 * s); op.content_margin_right = int(8 * s)
	op.content_margin_top = int(8 * s); op.content_margin_bottom = int(8 * s)
	out_panel.add_theme_stylebox_override("panel", op)
	vbox.add_child(out_panel)
	var scroll := ScrollContainer.new()
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	out_panel.add_child(scroll)
	_output = RichTextLabel.new()
	_output.bbcode_enabled = true
	_output.scroll_following = true
	_output.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_output.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_output.add_theme_font_size_override("font_size", int(12 * s))
	_output.add_theme_color_override("default_color", C_TITLE)
	scroll.add_child(_output)
