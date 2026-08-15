extends Control
class_name ChatConsole

# Minecraft-style debug chat: a log panel in the upper-left with a text input
# just below it. Press "/" or "T" to focus the input; Enter submits; Esc
# closes. Lines starting with "/" are commands (gated by DEBUG_COMMANDS_ENABLED
# so they can be compiled out of the final game); anything else is echoed as a
# chat line. This replaces the removed Ctrl+Shift+H/C/T/D, Ctrl, Shift+E/R and
# Ctrl+Shift+L debug shortcuts — every old shortcut has an equivalent /command.

const DEBUG_COMMANDS_ENABLED: bool = true  # flip to false for release builds

const C_BG:     Color = Color(0.0, 0.0, 0.0, 0.50)
const C_BORDER: Color = Color(0.35, 0.35, 0.45, 0.80)

const LOG_MAX_LINES: int = 60

var _log: RichTextLabel = null
var _entry: LineEdit = null
var _history: Array = []
var _completion: VBoxContainer = null
var _structure_names: Array = []

func _ready() -> void:
	# Full-rect, click-through — the world keeps receiving clicks everywhere
	# except on the input line and the autocomplete popup.
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_build()
	Global.chat_logged.connect(_on_chat_logged)

func _build() -> void:
	var s: float = Global.ui_scale
	var width:  int = int(440 * s)
	var height: int = int(150 * s)
	var x: int = int(12 * s)
	var y: int = int(12 * s)

	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	panel.offset_left   = x
	panel.offset_top    = y
	panel.offset_right  = x + width
	panel.offset_bottom = y + height
	var sb := StyleBoxFlat.new()
	sb.bg_color = C_BG
	sb.border_color = C_BORDER
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(4)
	sb.content_margin_left   = int(8 * s)
	sb.content_margin_right  = int(8 * s)
	sb.content_margin_top    = int(6 * s)
	sb.content_margin_bottom = int(6 * s)
	panel.add_theme_stylebox_override("panel", sb)
	add_child(panel)

	_log = RichTextLabel.new()
	_log.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_log.bbcode_enabled = true
	_log.scroll_active = true
	_log.scroll_following = true
	_log.selection_enabled = true
	_log.add_theme_font_size_override("normal_font_size", int(13 * s))
	panel.add_child(_log)

	_entry = LineEdit.new()
	_entry.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_entry.offset_left   = x
	_entry.offset_top    = y + height + int(4 * s)
	_entry.offset_right  = x + width
	_entry.offset_bottom = y + height + int(4 * s) + int(26 * s)
	_entry.placeholder_text = "Type a message or /command"
	_entry.visible = false
	_entry.text_submitted.connect(_submit)
	_entry.text_changed.connect(_on_text_changed)
	_entry.focus_exited.connect(_on_input_focus_exited)
	_entry.gui_input.connect(_on_entry_gui_input)
	add_child(_entry)

	_completion = VBoxContainer.new()
	_completion.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_completion.offset_left = x
	_completion.offset_top  = _entry.offset_bottom + int(2 * s)
	_completion.visible = false
	add_child(_completion)

# Open/close keys: "/" or "T" while the input is closed and no other UI is
# open; Esc closes. The input's own focus handles the actual typing.
func _input(event: InputEvent) -> void:
	if Global.pause_menu_open:
		return
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	var key: int = (event as InputEventKey).keycode
	if _entry.visible:
		if key == KEY_ESCAPE:
			_close_input()
			get_viewport().set_input_as_handled()
		return
	if Global.any_ui_open():
		return
	if key == KEY_SLASH:
		_open_input("/")
		get_viewport().set_input_as_handled()
	elif key == KEY_T:
		_open_input("")
		get_viewport().set_input_as_handled()

func _open_input(prefill: String) -> void:
	_entry.visible = true
	_entry.text = prefill
	_entry.grab_focus()
	_entry.caret_column = prefill.length()
	Global.chat_open = true
	Global.open_ui()

func _close_input() -> void:
	if _entry == null:
		return
	_entry.visible = false
	_entry.text = ""
	if _completion != null:
		_completion.visible = false
	if _entry.has_focus():
		_entry.release_focus()
	Global.chat_open = false
	Global.close_ui()

func _on_input_focus_exited() -> void:
	# Clicking away closes the input; deferring avoids fighting the submit
	# path (which already closed it and hid it).
	call_deferred("_check_input_focus")

func _check_input_focus() -> void:
	if _entry.visible and not _entry.has_focus():
		_close_input()

func _submit(text: String) -> void:
	var t: String = text.strip_edges()
	if t != "":
		if t.begins_with("/"):
			_run_command(t.substr(1).strip_edges())
		else:
			add_line("[color=#9a9a9a]<You>[/color] " + t)
	_close_input()

func _on_chat_logged(message: String) -> void:
	add_line(message)

func add_line(text: String) -> void:
	_history.append(text)
	while _history.size() > LOG_MAX_LINES:
		_history.pop_front()
	if _log != null:
		_log.text = "\n".join(_history)

# ── Autocomplete (structure names for /locate) ──────────────────────
func _on_text_changed(text: String) -> void:
	_update_completion(text)

func _update_completion(text: String) -> void:
	if _completion == null:
		return
	for c in _completion.get_children().duplicate():
		c.queue_free()
	var prefix: String
	if text == "/locate":
		prefix = ""
	elif text.begins_with("/locate "):
		prefix = text.substr("/locate ".length()).to_lower()
	else:
		_completion.visible = false
		return
	if _structure_names.is_empty():
		_refresh_structure_names()
	if _structure_names.is_empty():
		_completion.visible = false
		return
	var shown: int = 0
	for n in _structure_names:
		if (n as String).to_lower().begins_with(prefix):
			_completion.add_child(_make_completion_btn(n as String))
			shown += 1
	_completion.visible = shown > 0

func _refresh_structure_names() -> void:
	var world: Node = Global.world_node
	if world != null and world.has_method("get_available_structure_names"):
		_structure_names = world.call("get_available_structure_names") as Array

func _make_completion_btn(name: String) -> Button:
	var s: float = Global.ui_scale
	var b := Button.new()
	b.text = name
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.focus_mode = Control.FOCUS_NONE  # never steal focus from the input (would close it)
	b.custom_minimum_size = Vector2(int(280 * s), int(22 * s))
	b.add_theme_font_size_override("font_size", int(12 * s))
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.10, 0.12, 0.22, 0.95)
	sb.border_color = C_BORDER
	sb.set_border_width_all(1)
	b.add_theme_stylebox_override("normal",  sb)
	b.add_theme_stylebox_override("hover",   sb)
	b.add_theme_stylebox_override("pressed", sb)
	b.pressed.connect(func() -> void: _complete_name(name))
	return b

func _complete_name(name: String) -> void:
	_entry.text = "/locate " + name + " "
	_entry.caret_column = _entry.text.length()
	_completion.visible = false
	_entry.grab_focus()

# Tab completes the current /locate partial to the first matching structure.
func _on_entry_gui_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo \
			and (event as InputEventKey).keycode == KEY_TAB:
		_tab_complete()
		_entry.accept_event()

func _tab_complete() -> void:
	var text: String = _entry.text
	if not text.begins_with("/locate"):
		return
	var prefix: String = ""
	if text.begins_with("/locate "):
		prefix = text.substr("/locate ".length()).to_lower()
	if _structure_names.is_empty():
		_refresh_structure_names()
	for n in _structure_names:
		if (n as String).to_lower().begins_with(prefix):
			_entry.text = "/locate " + (n as String) + " "
			_entry.caret_column = _entry.text.length()
			_completion.visible = false
			return

# ── Commands ─────────────────────────────────────────────────────────
func _run_command(line: String) -> void:
	add_line("[color=#ffe27a]/%s[/color]" % line)
	if not DEBUG_COMMANDS_ENABLED:
		add_line("[color=#ff7777]Commands are disabled.[/color]")
		return
	var parts := line.split(" ", false)
	var cmd: String = parts[0].to_lower()
	var args: Array = parts.slice(1)
	match cmd:
		"help":         _cmd_help()
		"hitboxes":     _cmd_dispatch_world("toggle_hitboxes", "Toggled hitbox overlay")
		"chunkborders": _cmd_dispatch_world("toggle_chunk_borders", "Toggled chunk borders")
		"nearestcave":  _cmd_dispatch_world("teleport_to_nearest_cave", "Teleported to nearest cave")
		"blockmode":    _cmd_blockmode()
		"items":        _cmd_items()
		"missions":     _cmd_missions()
		"dungeon":      _cmd_dungeon()
		"daynight":     _cmd_daynight()
		"locate":       _cmd_locate(" ".join(args))
		_:
			add_line("[color=#ff7777]Unknown command: %s[/color] — type /help" % cmd)

func _cmd_dispatch_world(method: String, ok_msg: String) -> void:
	Global.dispatch_to_world(method)
	add_line(ok_msg)

func _cmd_blockmode() -> void:
	Global.block_mode = not Global.block_mode
	Global.block_mode_changed.emit(Global.block_mode)
	add_line("Block mode: %s" % ("ON" if Global.block_mode else "OFF"))

func _cmd_items() -> void:
	var p: Node = Global.player_node
	if p != null and p.has_method("_give_debug_items"):
		p.call("_give_debug_items")
		add_line("Granted debug items")
	else:
		add_line("[color=#ff7777]No player node available[/color]")

func _cmd_missions() -> void:
	var p: Node = Global.player_node
	if p != null and p.has_method("reset_debug_missions"):
		p.call("reset_debug_missions")
	else:
		Global.reset_missions()
	add_line("Missions reset")

func _cmd_dungeon() -> void:
	var p: Node = Global.player_node
	if p != null and p.has_method("_debug_teleport_to_dungeon"):
		p.call("_debug_teleport_to_dungeon")
		add_line("Teleported to dungeon entrance")
	else:
		add_line("[color=#ff7777]No player node available[/color]")

func _cmd_daynight() -> void:
	if Global.day_night_cycle != null and Global.day_night_cycle.has_method("toggle_period"):
		Global.day_night_cycle.call("toggle_period")
		add_line("Toggled day/night")
	else:
		add_line("[color=#ff7777]Day/night cycle not available here[/color]")

# /locate <structure> — teleport to (and report) the nearest placed structure
# matching the name. Autocompleted from world.gd's structure pool.
func _cmd_locate(name: String) -> void:
	if name.is_empty():
		add_line("[color=#ff7777]Usage: /locate <structure>[/color]")
		return
	var world: Node = Global.world_node
	if world == null or not world.has_method("locate_nearest_structure"):
		add_line("[color=#ff7777]Structure locator not available here[/color]")
		return
	var pos: Vector2 = world.call("locate_nearest_structure", name) as Vector2
	if pos == Vector2.INF:
		add_line("[color=#ff7777]No placed structure named '%s'[/color]" % name)
		return
	var p: Node2D = Global.player_node as Node2D
	if p != null:
		p.global_position = pos + Vector2(0.0, 32.0)
	add_line("Located %s at (%.0f, %.0f)" % [name, pos.x, pos.y])

func _cmd_help() -> void:
	for line in [
		"[color=#ffe27a]Commands:[/color]",
		"  /help — show this list",
		"  /hitboxes — toggle hitbox overlay",
		"  /chunkborders — toggle chunk borders",
		"  /nearestcave — teleport to nearest cave",
		"  /locate <structure> — teleport to nearest structure",
		"  /blockmode — toggle build mode",
		"  /items — grant debug items",
		"  /missions — reset tutorial missions",
		"  /dungeon — teleport to dungeon entrance",
		"  /daynight — toggle day/night",
	]:
		add_line(line)