extends Node

## Tutorial guide: builds the two NPCs, runs the six-line conversation, persists
## the current line and completion in the world save, and removes both NPCs only
## after the closing line. It intentionally reuses Global.open_ui()/register_ui_back
## so dialogue blocks gameplay input exactly like every other modal.

const NPC_SCRIPT: GDScript = preload("res://scripts/tutorial_npc.gd")
const PY_SAN_TEX := "res://sprites/char/pysan.png"
const LUA_TEX := "res://sprites/char/lua/front.png"

const LINES: Array = [
	{"speaker": "Py-San", "npc": "pysan",
		"text": "Ah, a new adventurer! Welcome to SandEE. Move with WASD or the arrow keys, or use the joystick on touch screens. Explore freely - the world is yours."},
	{"speaker": "LUA", "npc": "lua",
		"text": "Want to make this world your own? Pick a block from your inventory or hotbar, then place it with a left-click or tap. On desktop, press Ctrl to toggle Build Mode; use the BUILD button on mobile."},
	{"speaker": "Py-San", "npc": "pysan",
		"text": "Looking for a purpose? Check your mission list on the right. Follow objectives, watch progress, and claim the rewards available to you."},
	{"speaker": "LUA", "npc": "lua",
		"text": "Ready for a challenge? Dungeons stand at portals across the world. Prepare your gear, watch for traps and guards, and work through each dungeon's objectives."},
	{"speaker": "Py-San", "npc": "pysan",
		"text": "That's the essentials! The rest is yours to discover."},
	{"speaker": "LUA", "npc": "lua",
		"text": "Good luck out there. Your adventure starts now!"},
]

var _npcs: Array = []
var _ui: Control = null
var _name_label: Label = null
var _text_label: Label = null
var _continue: Button = null
var _active := false

func setup(spawn_pos: Vector2) -> void:
	# Offset from spawn but outside the player's collision footprint. No solid
	# bodies are created, so these NPCs never block spawning or building.
	_add_npc("Py-San", PY_SAN_TEX, spawn_pos + Vector2(-58.0, 0.0))
	_add_npc("LUA", LUA_TEX, spawn_pos + Vector2(58.0, 0.0))
	_build_ui()
	# New worlds open the conversation at game start; interrupted conversations
	# resume at the saved line when the world is loaded again.
	if not Global.tutorial_completed and Global.tutorial_stage < LINES.size():
		_open_dialogue.call_deferred()

func _add_npc(npc_name: String, texture_path: String, at: Vector2) -> void:
	var npc := NPC_SCRIPT.new() as Node2D
	npc.call("setup", npc_name, texture_path, self)
	npc.global_position = at
	add_child(npc)
	_npcs.append(npc)

func _build_ui() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 45
	layer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(layer)
	_ui = Control.new()
	_ui.set_anchors_preset(Control.PRESET_FULL_RECT)
	_ui.process_mode = Node.PROCESS_MODE_ALWAYS
	_ui.visible = false
	layer.add_child(_ui)

	var dim := ColorRect.new()
	dim.color = Color(0.0, 0.0, 0.0, 0.22)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_ui.add_child(dim)

	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	panel.offset_left = 40
	panel.offset_right = -40
	panel.offset_top = -150
	panel.offset_bottom = -24
	var s := Global.ui_scale
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.10, 0.20, 0.98)
	style.border_color = Color(0.45, 0.55, 0.85, 1.0)
	style.set_border_width_all(int(2 * s))
	style.set_corner_radius_all(int(8 * s))
	style.content_margin_left = int(20 * s)
	style.content_margin_right = int(20 * s)
	style.content_margin_top = int(14 * s)
	style.content_margin_bottom = int(14 * s)
	panel.add_theme_stylebox_override("panel", style)
	_ui.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", int(6 * s))
	panel.add_child(vbox)
	_name_label = Label.new()
	_name_label.add_theme_font_size_override("font_size", int(16 * s))
	_name_label.add_theme_color_override("font_color", Color(1.0, 0.86, 0.52, 1.0))
	vbox.add_child(_name_label)
	_text_label = Label.new()
	_text_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_text_label.add_theme_font_size_override("font_size", int(13 * s))
	_text_label.add_theme_color_override("font_color", Color(0.88, 0.92, 1.0, 1.0))
	vbox.add_child(_text_label)
	_continue = Button.new()
	_continue.text = "Continue"
	_continue.custom_minimum_size = Vector2(0, int(34 * s))
	_continue.add_theme_font_size_override("font_size", int(13 * s))
	_continue.pressed.connect(_advance)
	vbox.add_child(_continue)

func request_dialogue() -> void:
	if Global.tutorial_completed or _active:
		return
	if Global.tutorial_stage >= LINES.size():
		_finish()
		return
	_open_dialogue()

func _open_dialogue() -> void:
	if _active or _ui == null:
		return
	_active = true
	_ui.visible = true
	Global.open_ui()
	Global.register_ui_back(_ui, Callable(self, "close_dialogue"))
	_refresh_line()
	if _continue != null:
		_continue.grab_focus()

func _refresh_line() -> void:
	var index: int = clampi(Global.tutorial_stage, 0, LINES.size() - 1)
	var line: Dictionary = LINES[index]
	_name_label.text = str(line["speaker"])
	_text_label.text = str(line["text"])
	if _continue != null:
		_continue.text = "Continue" if index < LINES.size() - 1 else "Finish"

func _advance() -> void:
	if not _active:
		return
	var next := Global.tutorial_stage + 1
	if next >= LINES.size():
		_finish()
		return
	Global.tutorial_stage = next
	_save_progress()
	_refresh_line()

func close_dialogue() -> void:
	if not _active:
		return
	_active = false
	if _ui != null:
		Global.unregister_ui_back(_ui)
		_ui.visible = false
	Global.close_ui()
	_save_progress()

func _finish() -> void:
	Global.tutorial_completed = true
	Global.tutorial_stage = LINES.size()
	_save_progress()
	_active = false
	if _ui != null:
		Global.unregister_ui_back(_ui)
		_ui.visible = false
	Global.close_ui()
	for npc in _npcs:
		if is_instance_valid(npc):
			npc.queue_free()
	_npcs.clear()
	queue_free()

func _save_progress() -> void:
	if Global.active_save_slot > 0:
		Global.save_game(Global.active_save_slot)
