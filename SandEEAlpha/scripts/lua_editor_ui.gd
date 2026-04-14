extends Control

# ── Theme ─────────────────────────────────────────────────────────
const C_PANEL   := Color(0.08, 0.10, 0.20, 0.97)
const C_BORDER  := Color(0.22, 0.32, 0.58, 1.00)
const C_TITLE   := Color(0.80, 0.90, 1.00, 1.00)
const C_MUTED   := Color(0.55, 0.65, 0.85, 1.00)
const C_DIVIDER := Color(0.20, 0.28, 0.50, 1.00)
const C_EDITOR  := Color(0.05, 0.07, 0.13, 1.00)
const C_OUTPUT  := Color(0.04, 0.06, 0.10, 1.00)
const C_OK      := Color(0.15, 0.45, 0.20, 1.00)
const C_ERR     := Color(0.45, 0.12, 0.12, 1.00)
const C_OVERLAY := Color(0.00, 0.00, 0.00, 0.50)

# ── Refs ──────────────────────────────────────────────────────────
var _code_edit:   TextEdit
var _output:      RichTextLabel
var _run_btn:     Button
var _clear_btn:   Button
var _lua_state:   Node       # LuaState from extension

# ── Lifecycle ─────────────────────────────────────────────────────
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_build()
	call_deferred("_find_lua_state")

# Pause game and block player input whenever this UI opens or closes
func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED and is_inside_tree():
		Global.lua_ui_open = visible
		get_tree().paused  = visible

func _find_lua_state() -> void:
	# LuaState is a sibling of this node's parent (the NPC)
	# Walk up: UI → CanvasLayer → LuaNPC → look for LuaState child
	var npc: Node = get_parent().get_parent()
	_lua_state = npc.get_node_or_null("LuaState")
	if _lua_state == null:
		_print_output("[color=#ff8888]LuaState node not found on NPC. Add a LuaState child to LuaNPC.tscn.[/color]")
		return
	_lua_state.connect("signal_print", _on_lua_print)
	_lua_state.connect("signal_move",  _on_lua_move)
	_lua_state.connect("code_executed", _on_code_executed)
	_lua_state.connect("code_failed",  _on_code_failed)
	_print_output("[color=#88ffaa]Lua interpreter ready.[/color]")
	_print_output("[color=#5588aa]Available functions: print(), move(x,y), vector:new(x,y)[/color]")

# ── Build UI ──────────────────────────────────────────────────────
func _build() -> void:
	var overlay := ColorRect.new()
	overlay.color        = C_OVERLAY
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(overlay)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(680, 460)
	var ps := StyleBoxFlat.new()
	ps.bg_color = C_PANEL; ps.border_color = C_BORDER
	ps.set_border_width_all(1); ps.set_corner_radius_all(6)
	ps.content_margin_left = 16; ps.content_margin_right  = 16
	ps.content_margin_top  = 14; ps.content_margin_bottom = 16
	panel.add_theme_stylebox_override("panel", ps)
	center.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	panel.add_child(vbox)

	# Header
	var header := HBoxContainer.new()
	vbox.add_child(header)

	var icon := Label.new()
	icon.text = "🤖"
	icon.add_theme_font_size_override("font_size", 18)
	header.add_child(icon)

	var title := Label.new()
	title.text = "  LUA — Code Editor"
	title.add_theme_font_size_override("font_size", 15)
	title.add_theme_color_override("font_color", C_TITLE)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)

	var close := Button.new()
	close.text = "✕"; close.flat = true
	close.add_theme_color_override("font_color", C_MUTED)
	close.pressed.connect(_close)
	header.add_child(close)

	_divider(vbox)

	# Body — editor left, output right
	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 10)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(body)

	# ── Code editor ────────────────────────────────────────────────
	var editor_wrap := VBoxContainer.new()
	editor_wrap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	editor_wrap.add_theme_constant_override("separation", 6)
	body.add_child(editor_wrap)

	var ed_lbl := Label.new()
	ed_lbl.text = "CODE"
	ed_lbl.add_theme_font_size_override("font_size", 11)
	ed_lbl.add_theme_color_override("font_color", C_MUTED)
	editor_wrap.add_child(ed_lbl)

	_code_edit = TextEdit.new()
	_code_edit.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_code_edit.placeholder_text    = "-- Write Lua here\nprint(\"hello\")\nmove(1, 0)"
	_code_edit.syntax_highlighter  = null
	var es := StyleBoxFlat.new()
	es.bg_color = C_EDITOR; es.border_color = C_BORDER
	es.set_border_width_all(1); es.set_corner_radius_all(4)
	es.content_margin_left = 8; es.content_margin_right  = 8
	es.content_margin_top  = 8; es.content_margin_bottom = 8
	_code_edit.add_theme_stylebox_override("normal", es)
	_code_edit.add_theme_stylebox_override("focus",  es)
	_code_edit.add_theme_color_override("font_color", C_TITLE)
	_code_edit.add_theme_font_size_override("font_size", 13)
	editor_wrap.add_child(_code_edit)

	# Buttons
	var btn_row := HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 6)
	editor_wrap.add_child(btn_row)

	_run_btn = Button.new()
	_run_btn.text = "▶  RUN"
	_run_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_run_btn.custom_minimum_size   = Vector2(0, 34)
	var rs := StyleBoxFlat.new()
	rs.bg_color = C_OK; rs.border_color = C_BORDER
	rs.set_border_width_all(1); rs.set_corner_radius_all(4)
	rs.content_margin_top = 6; rs.content_margin_bottom = 6
	_run_btn.add_theme_stylebox_override("normal", rs)
	_run_btn.add_theme_color_override("font_color", Color(0.8, 1.0, 0.8, 1.0))
	_run_btn.pressed.connect(_run_code)
	btn_row.add_child(_run_btn)

	_clear_btn = Button.new()
	_clear_btn.text = "✕ CLEAR"
	_clear_btn.custom_minimum_size = Vector2(0, 34)
	var cs := StyleBoxFlat.new()
	cs.bg_color = C_ERR; cs.border_color = C_BORDER
	cs.set_border_width_all(1); cs.set_corner_radius_all(4)
	cs.content_margin_top = 6; cs.content_margin_bottom = 6
	_clear_btn.add_theme_stylebox_override("normal", cs)
	_clear_btn.add_theme_color_override("font_color", Color(1.0, 0.8, 0.8, 1.0))
	_clear_btn.pressed.connect(_clear_code)
	btn_row.add_child(_clear_btn)

	# ── Output panel ───────────────────────────────────────────────
	var out_wrap := VBoxContainer.new()
	out_wrap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	out_wrap.add_theme_constant_override("separation", 6)
	body.add_child(out_wrap)

	var out_lbl := Label.new()
	out_lbl.text = "OUTPUT"
	out_lbl.add_theme_font_size_override("font_size", 11)
	out_lbl.add_theme_color_override("font_color", C_MUTED)
	out_wrap.add_child(out_lbl)

	var out_panel := PanelContainer.new()
	out_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var op := StyleBoxFlat.new()
	op.bg_color = C_OUTPUT; op.border_color = C_BORDER
	op.set_border_width_all(1); op.set_corner_radius_all(4)
	op.content_margin_left = 8; op.content_margin_right  = 8
	op.content_margin_top  = 8; op.content_margin_bottom = 8
	out_panel.add_theme_stylebox_override("panel", op)
	out_wrap.add_child(out_panel)

	var scroll := ScrollContainer.new()
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	out_panel.add_child(scroll)

	_output = RichTextLabel.new()
	_output.bbcode_enabled       = true
	_output.scroll_following     = true
	_output.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_output.size_flags_vertical   = Control.SIZE_EXPAND_FILL
	_output.add_theme_font_size_override("font_size", 12)
	_output.add_theme_color_override("default_color", C_TITLE)
	scroll.add_child(_output)

	# Hint at bottom
	_divider(vbox)
	var hint := Label.new()
	hint.text = "Hint: move(x, y)  •  print(val)  •  vector:new(x,y)  •  Escape to close"
	hint.add_theme_font_size_override("font_size", 10)
	hint.add_theme_color_override("font_color", C_MUTED)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(hint)

# ── Actions ───────────────────────────────────────────────────────
func _run_code() -> void:
	if _lua_state == null:
		_print_output("[color=#ff8888]No LuaState connected.[/color]")
		return
	var code: String = _code_edit.text.strip_edges()
	if code.is_empty():
		return
	_lua_state.set("code", code)
	_lua_state.call("run_code")

func _clear_code() -> void:
	_code_edit.text = ""

func _close() -> void:
	visible = false  # _notification sets Global.lua_ui_open and unpauses

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("escape") and visible:
		_close()

# ── Lua signal handlers ───────────────────────────────────────────
func _on_lua_print(text: String) -> void:
	_print_output("[color=#aaddff]» %s[/color]" % text)

func _on_lua_move(vec: Vector2) -> void:
	_print_output("[color=#88ffaa]move → (%.2f, %.2f)[/color]" % [vec.x, vec.y])

func _on_code_executed() -> void:
	_print_output("[color=#88ffaa]✓ OK[/color]")

func _on_code_failed(error: String) -> void:
	_print_output("[color=#ff8888]✗ Error: %s[/color]" % error)

func _print_output(line: String) -> void:
	if _output == null: return
	_output.append_text(line + "\n")

# ── Helpers ───────────────────────────────────────────────────────
func _divider(parent: Node) -> void:
	var d := ColorRect.new()
	d.color = C_DIVIDER; d.custom_minimum_size = Vector2(0, 1)
	parent.add_child(d)
