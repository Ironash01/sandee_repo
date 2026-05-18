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
const C_STOP    := Color(0.50, 0.20, 0.08, 1.00)
const C_ERR     := Color(0.45, 0.12, 0.12, 1.00)
const C_OVERLAY := Color(0.00, 0.00, 0.00, 0.50)

# ── Refs ──────────────────────────────────────────────────────────
var _code_edit: TextEdit
var _output:    RichTextLabel
var _run_btn:   Button
var _stop_btn:  Button
var _body:      Control   # code + output view
var _encycl:    Control   # encyclopedia view
var _lua_state: Node
var _running:   bool = false

# ── Lifecycle ─────────────────────────────────────────────────────
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_build()
	call_deferred("_find_lua_state")

func _find_lua_state() -> void:
	var npc: Node = get_parent().get_parent()
	_lua_state = npc.get_node_or_null("LuaState")
	if _lua_state == null:
		_print_output("[color=#ff8888]LuaState not found on NPC.[/color]")
		return
	_lua_state.connect("signal_print",  _on_lua_print)
	_lua_state.connect("signal_move",   _on_lua_move)
	_lua_state.connect("code_executed", _on_code_executed)
	_lua_state.connect("code_failed",   _on_code_failed)
	_print_output("[color=#88ffaa]Robot ready. See Encyclopedia for available functions.[/color]")

# ── Build ─────────────────────────────────────────────────────────
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
	panel.custom_minimum_size = Vector2(700, 480)
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

	# ── Header ───────────────────────────────────────────────────
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 6)
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

	var enc_btn := Button.new()
	enc_btn.text = "📖  Encyclopedia"
	enc_btn.add_theme_font_size_override("font_size", 12)
	var ebs := StyleBoxFlat.new()
	ebs.bg_color = Color(0.12, 0.18, 0.36, 1.0)
	ebs.border_color = C_BORDER
	ebs.set_border_width_all(1); ebs.set_corner_radius_all(4)
	ebs.content_margin_left = 10; ebs.content_margin_right  = 10
	ebs.content_margin_top  =  4; ebs.content_margin_bottom =  4
	enc_btn.add_theme_stylebox_override("normal",  ebs)
	enc_btn.add_theme_stylebox_override("hover",   ebs)
	enc_btn.add_theme_stylebox_override("pressed", ebs)
	enc_btn.add_theme_color_override("font_color", C_TITLE)
	enc_btn.pressed.connect(_toggle_encyclopedia)
	header.add_child(enc_btn)

	var close_btn := Button.new()
	close_btn.text = "✕"; close_btn.flat = true
	close_btn.add_theme_color_override("font_color", C_MUTED)
	close_btn.pressed.connect(_close)
	header.add_child(close_btn)

	_divider(vbox)

	# ── Main body (code + output) ────────────────────────────────
	_body = _build_body()
	_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(_body)

	# ── Encyclopedia (hidden by default) ─────────────────────────
	_encycl = _build_encyclopedia()
	_encycl.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_encycl.visible = false
	vbox.add_child(_encycl)

# ── Body: code editor + output ────────────────────────────────────
func _build_body() -> Control:
	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 10)

	# Code editor
	var ed_wrap := VBoxContainer.new()
	ed_wrap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ed_wrap.add_theme_constant_override("separation", 6)
	body.add_child(ed_wrap)

	var ed_lbl := Label.new()
	ed_lbl.text = "CODE"
	ed_lbl.add_theme_font_size_override("font_size", 11)
	ed_lbl.add_theme_color_override("font_color", C_MUTED)
	ed_wrap.add_child(ed_lbl)

	_code_edit = TextEdit.new()
	_code_edit.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_code_edit.placeholder_text    = "-- write your Lua code here\ninteract()"
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
	ed_wrap.add_child(_code_edit)

	# Buttons: RUN  STOP  CLEAR
	var btn_row := HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 6)
	ed_wrap.add_child(btn_row)

	_run_btn = _make_btn("▶  RUN",  Color(0.8, 1.0, 0.8, 1.0), C_OK,  _run_code)
	_run_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn_row.add_child(_run_btn)

	_stop_btn = _make_btn("■  STOP", Color(1.0, 0.8, 0.6, 1.0), C_STOP, _stop_code)
	_stop_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_stop_btn.disabled = true
	btn_row.add_child(_stop_btn)

	var clear_btn := _make_btn("✕ CLEAR", Color(1.0, 0.8, 0.8, 1.0), C_ERR, _clear_code)
	btn_row.add_child(clear_btn)

	# Output panel
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
	_output.bbcode_enabled        = true
	_output.scroll_following      = true
	_output.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_output.size_flags_vertical   = Control.SIZE_EXPAND_FILL
	_output.add_theme_font_size_override("font_size", 12)
	_output.add_theme_color_override("default_color", C_TITLE)
	scroll.add_child(_output)

	return body

# ── Encyclopedia ──────────────────────────────────────────────────
func _build_encyclopedia() -> Control:
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 10)

	var hdr := Label.new()
	hdr.text = "FUNCTION REFERENCE"
	hdr.add_theme_font_size_override("font_size", 13)
	hdr.add_theme_color_override("font_color", C_TITLE)
	root.add_child(hdr)

	_divider(root)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(scroll)

	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 14)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)

	_enc_section(list, "HIGH-LEVEL HELPERS")
	_enc_entry(list, "auto_work()",
		"Full work cycle: chop all trees in radius → deposit collected items into the nearest chest → return to station.")
	_enc_entry(list, "chop_trees(radius)",
		"Chop every tree within radius blocks of the station (defaults to 20 if omitted). Collects dropped items after each tree, then walks home.")
	_enc_entry(list, "deposit_chest()",
		"Walk to the nearest chest within radius, deposit everything in the robot's inventory, then return to the station.")
	_enc_entry(list, "chest_contents()",
		"Print the contents of the nearest chest to the output panel. Outputs each item and quantity, or a message if the chest is empty or out of range.")
	_enc_entry(list, "return_to_spawn()",
		"Walk the robot directly back to the station and stop. Use this to abort a long task or reset position.")

	_divider(list)

	_enc_section(list, "LOW-LEVEL PRIMITIVES")
	_enc_entry(list, "move(x, y)",
		"Set the robot's movement velocity to (x, y) pixels per second. Positive x = east, positive y = south. Call move(0, 0) to stop. Note: sequences of move() calls all fire instantly — only the last value takes effect.")
	_enc_entry(list, "interact()",
		"Execute the pending action. With no sentinel move() before it, defaults to chopping all trees then returning home. Only one action runs at a time — calls while the robot is busy are ignored.")
	_enc_entry(list, "drop_item(\"name\", qty)",
		"Drop qty copies of the named item at the robot's current position. Example: drop_item(\"Wood\", 5). The item must be in the robot's inventory.")
	_enc_entry(list, "print(val)",
		"Print a value to the output panel. Accepts strings, numbers, and booleans. Output stays visible while the panel is open.")

	return root

func _enc_section(parent: Node, text: String) -> void:
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", 10)
	lbl.add_theme_color_override("font_color", C_MUTED)
	parent.add_child(lbl)

func _enc_entry(parent: Node, sig: String, desc: String) -> void:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	parent.add_child(box)

	var sig_lbl := Label.new()
	sig_lbl.text = sig
	sig_lbl.add_theme_font_size_override("font_size", 13)
	sig_lbl.add_theme_color_override("font_color", Color(0.55, 0.90, 1.00, 1.0))
	box.add_child(sig_lbl)

	var desc_lbl := Label.new()
	desc_lbl.text = desc
	desc_lbl.add_theme_font_size_override("font_size", 11)
	desc_lbl.add_theme_color_override("font_color", C_MUTED)
	desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(desc_lbl)

# ── Actions ───────────────────────────────────────────────────────
func _toggle_encyclopedia() -> void:
	_encycl.visible = not _encycl.visible
	_body.visible   = not _encycl.visible

func _run_code() -> void:
	if _lua_state == null:
		_print_output("[color=#ff8888]No LuaState connected.[/color]")
		return
	var code: String = _code_edit.text.strip_edges()
	if code.is_empty():
		return

	var preamble: String = """
-- Built-in helpers
function chop_trees(radius)
    move(radius or 20, -1)
    interact()
end
function auto_work()
    move(0, -2)
    interact()
end
function deposit_chest()
    move(0, -4)
    interact()
end
function return_to_spawn()
    move(0, -3)
    interact()
end
function chest_contents()
    move(0, -5)
    interact()
end
"""
	_lua_state.set("code", preamble + code)
	_lua_state.call("run_code")

	# Unpause so the robot can move, but keep the panel open
	_running = true
	get_tree().paused  = false
	_run_btn.disabled  = true
	_stop_btn.disabled = false
	_code_edit.editable = false
	_print_output("[color=#88ffaa]▶ Running...[/color]")

func _stop_code() -> void:
	var npc: Node = get_parent().get_parent()
	if npc.has_method("stop_work"):
		npc.call("stop_work")

	_running = false
	get_tree().paused   = true   # re-pause for editing
	_run_btn.disabled   = false
	_stop_btn.disabled  = true
	_code_edit.editable = true
	_print_output("[color=#ffaa44]■ Stopped.[/color]")

func _clear_code() -> void:
	_code_edit.text = ""

func _close() -> void:
	# Reset UI state but do NOT stop the robot — it keeps running after the panel closes
	_running            = false
	_run_btn.disabled   = false
	_stop_btn.disabled  = true
	_code_edit.editable = true
	Global.close_ui()
	visible = false

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("escape") and visible:
		get_viewport().set_input_as_handled()
		_close()

# ── Lua signal handlers ───────────────────────────────────────────
func _on_lua_print(text: String) -> void:
	_print_output("[color=#aaddff]» %s[/color]" % text)

func _on_lua_move(vec: Vector2) -> void:
	_print_output("[color=#88ffaa]move → (%.1f, %.1f)[/color]" % [vec.x, vec.y])

func _on_code_executed() -> void:
	_print_output("[color=#88ffaa]✓ Code executed[/color]")

func _on_code_failed(error: String) -> void:
	_print_output("[color=#ff8888]✗ %s[/color]" % error)
	# Re-enable editing on error
	if _running:
		_running = false
		get_tree().paused   = true
		_run_btn.disabled   = false
		_stop_btn.disabled  = true
		_code_edit.editable = true

func _print_output(line: String) -> void:
	if _output == null: return
	_output.append_text(line + "\n")

# ── Helpers ───────────────────────────────────────────────────────
func _make_btn(label: String, font_col: Color, bg: Color, cb: Callable) -> Button:
	var btn := Button.new()
	btn.text = label
	btn.custom_minimum_size = Vector2(0, 34)
	var s := StyleBoxFlat.new()
	s.bg_color = bg; s.border_color = C_BORDER
	s.set_border_width_all(1); s.set_corner_radius_all(4)
	s.content_margin_top = 6; s.content_margin_bottom = 6
	btn.add_theme_stylebox_override("normal",  s)
	btn.add_theme_stylebox_override("hover",   s)
	btn.add_theme_stylebox_override("pressed", s)
	btn.add_theme_color_override("font_color", font_col)
	btn.pressed.connect(cb)
	return btn

func _divider(parent: Node) -> void:
	var d := ColorRect.new()
	d.color = C_DIVIDER; d.custom_minimum_size = Vector2(0, 1)
	parent.add_child(d)
