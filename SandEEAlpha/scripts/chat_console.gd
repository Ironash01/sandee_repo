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

# Extra /locate suggestions beyond world.gd's structure names: dungeon
# entrances aren't GeneratedStructure names, they're the two live per-language
# portals (see _locate_dungeon_entrance).
const LOCATE_DUNGEON_FORMS: Array = [
	"dungeon entrance lua",
	"dungeon entrance python",
]

var _log: RichTextLabel = null
var _entry: LineEdit = null
var _history: Array = []
var _completion: VBoxContainer = null
var _structure_names: Array = []
var _panel: PanelContainer = null
var _default_panel_x: int = 0
var _default_panel_y: int = 0
var _default_panel_w: int = 0
var _default_panel_h: int = 0

# ── Item picker (the /items command) ──────────────────────────────
var _item_picker: Control = null        # root of the picker overlay (null when closed)
const C_OVERLAY := Color(0.0, 0.0, 0.0, 0.60)

func _ready() -> void:
	# Full-rect, click-through — the world keeps receiving clicks everywhere
	# except on the input line and the autocomplete popup.
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_build()
	Global.chat_logged.connect(_on_chat_logged)

func _build() -> void:
	var s: float = Global.ui_scale
	var content := Global.ui_content_rect()
	var width:  int = mini(int(440 * s), maxi(240, int(content.size.x - 24 * s)))
	var x: int = int(content.position.x + 12 * s)
	# Middle-left inside the display safe area; the minimap owns the upper-left.
	var y: int = int(content.position.y + content.size.y * 0.30)
	var entry_h: int = int(26 * s)
	var height: int = mini(int(150 * s),
		maxi(72, int(content.end.y - y - 4 * s - entry_h - int(2 * s))))

	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	panel.offset_left   = x
	panel.offset_top    = y
	panel.offset_right  = x + width
	panel.offset_bottom = y + height
	_panel = panel
	_default_panel_x = x
	_default_panel_y = y
	_default_panel_w = width
	_default_panel_h = height
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
	# Auto-hidden by default; _open_input() reveals it. The log still collects
	# every line while hidden, so history is there once summoned.
	panel.visible = false

	_log = RichTextLabel.new()
	_log.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_log.bbcode_enabled = true
	_log.scroll_active = true
	_log.scroll_following = true
	_log.selection_enabled = true
	_log.add_theme_font_size_override("normal_font_size", Global.ui_font_size(13))
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
	# Suggestions stay inside the same safe column as the log.
	_completion.custom_minimum_size.x = width
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
	if _item_picker != null:
		if key == KEY_ESCAPE:
			get_viewport().set_input_as_handled()
			if not Global.request_ui_back(event) and not Global.is_ui_back_event_consumed(event):
				_close_item_picker()
		return
	if _entry.visible:
		if key == KEY_ESCAPE:
			get_viewport().set_input_as_handled()
			if _completion != null and _completion.visible:
				Global.consume_ui_back_event(event)
				_completion.visible = false
				return
			if not Global.request_ui_back(event) and not Global.is_ui_back_event_consumed(event):
				_close_input()
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
	# The whole console is hidden until summoned — "/" (or T) reveals the log
	# panel + input line, Esc/click-away hides it again.
	if _panel != null:
		_panel.visible = true
	_entry.visible = true
	_entry.text = prefill
	_entry.grab_focus()
	_entry.caret_column = prefill.length()
	Global.chat_open = true
	Global.open_ui()
	Global.register_ui_back(_entry, Callable(self, "_close_input"))

func _close_input() -> void:
	if _entry == null:
		return
	Global.unregister_ui_back(_entry)
	_entry.visible = false
	_entry.text = ""
	if _completion != null:
		_completion.visible = false
	if _panel != null:
		_panel.visible = false
	if _entry.has_focus():
		_entry.release_focus()
	Global.chat_open = false
	Global.close_ui()

## Scene-transition safety: close a chat input left open inside a dungeon and
## release its focus. A focused chat LineEdit is one of the ways the Ctrl
## build-mode toggle can silently stop responding after a world swap.
func reset_interaction_state() -> void:
	if Global.chat_open:
		_close_input()
	elif _entry != null and is_instance_valid(_entry) and _entry.has_focus():
		_entry.release_focus()

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
	var shown: int = 0
	for n in _locate_candidates():
		if (n as String).to_lower().begins_with(prefix):
			_completion.add_child(_make_completion_btn(n as String))
			shown += 1
	_completion.visible = shown > 0

func _refresh_structure_names() -> void:
	var world: Node = Global.world_node
	if world != null and world.has_method("get_available_structure_names"):
		_structure_names = world.call("get_available_structure_names") as Array

# Everything /locate can jump to: the placed-structure names plus the
# dungeon-entrance special forms.
func _locate_candidates() -> Array:
	return _structure_names + LOCATE_DUNGEON_FORMS

func _make_completion_btn(name: String) -> Button:
	var s: float = Global.ui_scale
	var b := Button.new()
	b.text = name
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.focus_mode = Control.FOCUS_NONE  # never steal focus from the input (would close it)
	b.custom_minimum_size = Vector2(int(280 * s), int(22 * s))
	b.add_theme_font_size_override("font_size", Global.ui_font_size(12))
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
	for n in _locate_candidates():
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
		"inv":          _cmd_give_item(" ".join(args))
		"missions":     _cmd_missions()
		"dungeon":      _cmd_dungeon()
		"tcm":          _cmd_teleport_current_mission()
		"daynight":     _cmd_daynight()
		"shaq":         _cmd_dispatch_world("toggle_shaq_dark", "SHAQ mode toggled")
		"locate":       _cmd_locate(" ".join(args))
		"spawn":        _cmd_spawn(" ".join(args))
		_:
			add_line("[color=#ff7777]Unknown command: %s[/color] — type /help" % cmd)

func _cmd_dispatch_world(method: String, ok_msg: String) -> void:
	Global.dispatch_to_world(method)
	add_line(ok_msg)

func _cmd_blockmode() -> void:
	if Global.is_in_dungeon:
		add_line("[color=#ff7777]Build mode is disabled inside dungeons.[/color]")
		return
	Global.block_mode = not Global.block_mode
	Global.block_mode_changed.emit(Global.block_mode)
	add_line("Block mode: %s" % ("ON" if Global.block_mode else "OFF"))

func _cmd_items() -> void:
	_open_item_picker()

# Opens the /items picker: a full-screen overlay listing every ItemData resource
# in resources/items/. Clicking a row grants one copy (dev items included) and
# closes the picker; Esc or the Close button dismisses it without granting.
func _open_item_picker() -> void:
	if _item_picker != null:
		return
	var s: float = Global.ui_scale
	var canvas := CanvasLayer.new()
	canvas.layer        = 40
	canvas.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(canvas)

	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.process_mode = Node.PROCESS_MODE_ALWAYS
	canvas.add_child(root)
	_item_picker = root
	Global.register_ui_back(_item_picker, Callable(self, "_close_item_picker"))

	var overlay := ColorRect.new()
	overlay.color        = C_OVERLAY
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(overlay)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	Global.apply_safe_area(center)
	root.add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Global.ui_fit_min_size(Vector2(560, 520))
	var ps := StyleBoxFlat.new()
	ps.bg_color = Color(0.06, 0.08, 0.16, 0.98); ps.border_color = Color(0.35, 0.45, 0.75, 1.0)
	ps.set_border_width_all(2); ps.set_corner_radius_all(8)
	ps.content_margin_left = 18; ps.content_margin_right  = 18
	ps.content_margin_top  = 14; ps.content_margin_bottom = 14
	panel.add_theme_stylebox_override("panel", ps)
	center.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	panel.add_child(vbox)

	var hdr := HBoxContainer.new()
	hdr.add_theme_constant_override("separation", 8)
	vbox.add_child(hdr)
	var title := Label.new()
	title.text = "Item Picker"
	title.add_theme_font_size_override("font_size", Global.ui_font_size(17))
	title.add_theme_color_override("font_color", Color(0.85, 0.92, 1.0, 1.0))
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hdr.add_child(title)
	var close_btn := Button.new()
	close_btn.text = "Close"
	close_btn.pressed.connect(_close_item_picker)
	hdr.add_child(close_btn)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, int(430 * s))
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(scroll)

	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 2)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)

	for item in Global.list_all_items():
		var data: ItemData = item as ItemData
		var btn := Button.new()
		btn.text = "  %s" % data.item_name
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.custom_minimum_size = Vector2(0, int(30 * s))
		btn.add_theme_font_size_override("font_size", Global.ui_font_size(13))
		btn.pressed.connect(_grant_and_close.bind(data))
		list.add_child(btn)

	# open_ui is deferred so it runs AFTER the chat input's own close_ui() (the
	# chat closes when a command is submitted) — otherwise the chat's close
	# would undo the picker's pause and the game would run underneath the modal.
	call_deferred("_item_picker_pause")

func _item_picker_pause() -> void:
	if _item_picker != null:
		Global.open_ui()

func _grant_and_close(data: ItemData) -> void:
	if data != null:
		Global.add_item({"quantity": 1, "data": data}, true)
		add_line("Granted %s" % data.item_name)
	_close_item_picker()

func _close_item_picker() -> void:
	if _item_picker == null:
		return
	Global.unregister_ui_back(_item_picker)
	_item_picker.queue_free()
	_item_picker = null
	Global.close_ui()

# /inv <item> — grant any item in resources/items/ by name (matches display
# name or file base name, case-insensitive contains). Dev items included.
func _cmd_give_item(name: String) -> void:
	if name.is_empty():
		add_line("[color=#ff7777]Usage: /inv <item>[/color]")
		return
	if Global.give_item_by_name(name):
		add_line("Granted %s" % name)
	else:
		add_line("[color=#ff7777]No item matches '%s'[/color]" % name)

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

# /tcm — teleport to the CURRENT MISSION's location. For a dungeon mission
# that's its entrance (the guide arrow's target); for non-dungeon missions it
# falls back to the same helper's "no entrance" warning.
func _cmd_teleport_current_mission() -> void:
	var p: Node = Global.player_node
	if p != null and p.has_method("_debug_teleport_to_dungeon"):
		p.call("_debug_teleport_to_dungeon")
		add_line("Teleported to current mission")
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
# /locate dungeon entrance <lua|python> — the live entrance of a language's
# current dungeon (both tracks always have one, so this picks which to visit).
func _cmd_locate(name: String) -> void:
	if name.is_empty():
		add_line("[color=#ff7777]Usage: /locate <structure>[/color]")
		add_line("[color=#ff7777]       /locate dungeon entrance <lua|python>[/color]")
		return
	var lower: String = name.to_lower()
	if lower.begins_with("dungeon") or lower == "lua" or lower == "python" or lower == "py":
		_locate_dungeon_entrance(lower)
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

# Teleports to the live overworld entrance of a language's current dungeon.
# The language may be given anywhere in the argument, so all of
# /locate dungeon entrance python, /locate dungeon python and /locate python
# resolve to the same portal.
func _locate_dungeon_entrance(arg: String) -> void:
	var lang: String = ""
	for token in arg.split(" ", false):
		if token == "lua" or token == "python" or token == "py":
			lang = "python" if token == "py" else token
			break
	if lang.is_empty():
		add_line("[color=#ff7777]Usage: /locate dungeon entrance <lua|python>[/color]")
		return
	var world: Node = Global.world_node
	if world == null or not world.has_method("get_dungeon_entrance_target"):
		add_line("[color=#ff7777]Dungeon entrances are only in the overworld[/color]")
		return
	var pos: Vector2 = world.call("get_dungeon_entrance_target", lang) as Vector2
	if pos == Vector2.INF:
		add_line("[color=#ff7777]No live %s dungeon entrance[/color]" % lang)
		return
	var p: Node2D = Global.player_node as Node2D
	if p != null:
		p.global_position = pos + Vector2(0.0, 64.0)
	add_line("Located %s dungeon entrance at (%.0f, %.0f)" % [lang, pos.x, pos.y])

# /spawn [mob_id] — spawn a mob near the player for debugging
# Available IDs: wolf, worm, pixie, headless_fish
func _cmd_spawn(arg: String = "") -> void:
	var world: Node = Global.world_node
	if world == null:
		add_line("[color=#ff7777]No world available[/color]")
		return
	var p: Node2D = Global.player_node as Node2D
	if p == null:
		add_line("[color=#ff7777]No player node available[/color]")
		return

	# Mob lookup table: id → {scene, data}
	var mobs: Dictionary = {
		"wolf": {
			"scene": preload("res://scenes/mobs/Wolf.tscn"),
			"data": preload("res://resources/mobs/wolf.tres"),
		},
		"worm": {
			"scene": preload("res://scenes/mobs/Worm.tscn"),
			"data": preload("res://resources/mobs/worm.tres"),
		},
		"pixie": {
			"scene": preload("res://scenes/mobs/Pixie.tscn"),
			"data": preload("res://resources/mobs/pixie.tres"),
		},
		"headless_fish": {
			"scene": preload("res://scenes/mobs/HeadlessFish.tscn"),
			"data": preload("res://resources/mobs/headless_fish.tres"),
		},
		"mossback_nib": {
			"scene": preload("res://scenes/mobs/MossbackNib.tscn"),
			"data": preload("res://resources/mobs/mossback_nib.tres"),
		},
		"emberfox_kit": {
			"scene": preload("res://scenes/mobs/EmberfoxKit.tscn"),
			"data": preload("res://resources/mobs/emberfox_kit.tres"),
		},
		"cinder_ooze": {
			"scene": preload("res://scenes/mobs/CinderOoze.tscn"),
			"data": preload("res://resources/mobs/cinder_ooze.tres"),
		},
		"gravebell_shambler": {
			"scene": preload("res://scenes/mobs/GravebellShambler.tscn"),
			"data": preload("res://resources/mobs/gravebell_shambler.tres"),
		},
		"rune_sentinel": {
			"scene": preload("res://scenes/mobs/RuneSentinel.tscn"),
			"data": preload("res://resources/mobs/rune_sentinel.tres"),
		},
		"vesper_acolyte": {
			"scene": preload("res://scenes/mobs/VesperAcolyte.tscn"),
			"data": preload("res://resources/mobs/vesper_acolyte.tres"),
		},
		"brass_prowler": {
			"scene": preload("res://scenes/mobs/BrassProwler.tscn"),
			"data": preload("res://resources/mobs/brass_prowler.tres"),
		},
		"cipher_warden": {
			"scene": preload("res://scenes/mobs/CipherWarden.tscn"),
			"data": preload("res://resources/mobs/cipher_warden.tres"),
		},
	}

	var id: String = arg.strip_edges().to_lower()
	if id.is_empty():
		# Default to worm for backward compatibility
		id = "worm"

	if not mobs.has(id):
		var available: String = ", ".join(mobs.keys())
		add_line("[color=#ff7777]Unknown mob: %s[/color] — available: %s" % [id, available])
		return

	var entry: Dictionary = mobs[id]
	var scene: PackedScene = entry["scene"]
	var data: MobCombatData = entry["data"]

	# Only actual worms use the special near-player desert spawner.
	# spawn_desert is a biome flag (the Headless Fish also sets it), so
	# key off the AI type instead.
	if data.ai_type == "WORM" and world.has_method("_spawn_desert_worms_near_player"):
		var spawned: bool = bool(world.call("_spawn_desert_worms_near_player", scene, data))
		if spawned:
			add_line("Spawned %s near player" % id)
		else:
			add_line("[color=#ffaa66]No valid dry desert spawn near the player.[/color]")
	else:
		# Spawn directly at the player
		var mob = scene.instantiate() as Node2D
		if mob != null:
			world.add_child(mob)
			mob.global_position = p.global_position + Vector2(48.0, 0.0)
			add_line("Spawned %s at player" % id)
			print("[Spawn] /spawn ", id, " at ", mob.global_position)
		else:
			add_line("[color=#ff7777]Failed to spawn %s[/color]" % id)

func _cmd_help() -> void:
	for line in [
		"[color=#ffe27a]Commands:[/color]",
		"  /help — show this list",
		"  /hitboxes — toggle hitbox overlay",
		"  /chunkborders — toggle chunk borders",
		"  /nearestcave — teleport to nearest cave",
		"  /locate <structure> — teleport to nearest structure",
		"  /locate dungeon entrance <lua|python> — teleport to a dungeon entrance",
		"  /blockmode — toggle build mode",
		"  /items — open item picker",
		"  /inv <item> — grant any item by name",
		"  /missions — reset tutorial missions",
		"  /dungeon — teleport to dungeon entrance",
		"  /tcm — teleport to current mission",
		"  /daynight — toggle day/night",
		"  /spawn <mob> — spawn mob (wolf, worm, pixie, headless_fish, cinder_ooze, gravebell_shambler, mossback_nib, emberfox_kit, rune_sentinel, vesper_acolyte, brass_prowler, cipher_warden)",
		"  /shaq — toggle dark mode",
		"  /shaq — make the cave pitch black (torches only), toggle back",
	]:
		add_line(line)

func reset_position() -> void:
	if _panel == null:
		return
	var s: float = Global.ui_scale
	var width:  int = int(440 * s)
	var height: int = int(150 * s)
	var x: int = int(12 * s)
	_panel.offset_left   = x
	_panel.offset_top    = _default_panel_y
	_panel.offset_right  = x + width
	_panel.offset_bottom = _default_panel_y + height
	_entry.offset_left   = x
	_entry.offset_top    = _default_panel_y + height + int(4 * s)
	_entry.offset_right  = x + width
	_entry.offset_bottom = _default_panel_y + height + int(4 * s) + int(26 * s)
	_completion.offset_left = x
	_completion.offset_top  = _entry.offset_bottom + int(2 * s)