extends Node

# ── Guided onboarding director (v3) ─────────────────────────────────
# Short, verified, one-action-at-a-time onboarding. The director owns the
# tutorial-only overlays and reuses the real item, hotbar, crafting, dungeon,
# altar, editor, cave and waypoint systems. It never advances an action step on
# a timer: each step returns true only after the game state proves the action.

const DIALOGUE_SCRIPT: GDScript = preload("res://scripts/tutorial_dialogue.gd")
const NPC_SCRIPT: GDScript = preload("res://scripts/tutorial_npc.gd")
const MARKER_SCRIPT: GDScript = preload("res://scripts/tutorial_marker.gd")
const ARROW_SCRIPT: GDScript = preload("res://scripts/tutorial_arrow.gd")
const UI_TARGET_SCRIPT: GDScript = preload("res://scripts/tutorial_ui_target.gd")
const SETTINGS_TOUR_SCRIPT: Script = preload("res://scripts/settings_tour.gd")
const ROUTE_SCRIPT: GDScript = preload("res://scripts/tutorial_route_guide.gd")

const PY_SAN_TEX := "res://sprites/char/pysan.png"
const LUA_TEX := "res://sprites/char/lua/front.png"

const STEPS: Array = [
	"welcome",
	"move_one", "move_two",
	"axe_select", "tree_chop", "craft_station",
	"dungeon_travel", "dungeon_knowledge", "dungeon_quiz", "dungeon_exit",
	"automatica", "automatica_combat", "algorithmica",
	"cave_regular", "cave_pixie", "waypoint",
	"finish",
]

const ITEM_AXE := "res://resources/items/woodenaxe.tres"
const ITEM_PICKAXE := "res://resources/items/wooden_pickaxe.tres"
const ITEM_SWORD := "res://resources/items/woodensword.tres"
const ITEM_BREAD := "res://resources/items/bread.tres"
const ITEM_WOOD := "res://resources/items/wood.tres"
const ITEM_CRAFTING := "res://resources/items/crafting_station.tres"
const ITEM_FURNACE := "res://resources/items/furnace.tres"
const ITEM_AUTOMATICA := "res://resources/items/lua.tres"

const CAMP_LAYOUT: Array = [
	{"role": "furnace", "offset": Vector2i(4, 2), "item": ITEM_FURNACE},
]
const AUTO_OFFSET := Vector2i(-4, 2)
const TUTORIAL_WOOD_COUNT := 4
# First Automatica lesson: enough Wood for one 32-block straight line. The line
# runs from -15 to +16 tiles, so both ends stay inside the robot's 20-tile work
# radius and inside the spawn chunk kept clear by world generation.
const AUTOMATICA_LINE_BLOCKS := 32
const AUTOMATICA_LINE_MIN_PLACED := 8
const MOVE_ARRIVE_PX := 40.0
const MAX_TARGET_DISTANCE := 1800.0

var _world: Node2D = null
var _spawn: Vector2 = Vector2.ZERO
var _npc_nodes: Array = []

var _dialogue_layer: CanvasLayer = null
var _dialogue: TutorialDialogue = null
var _objective_layer: CanvasLayer = null
var _objective_panel: PanelContainer = null
var _objective_label: Label = null
var _objective_hint: Label = null
var _objective_skip: Button = null
var _ui_focus_layer: CanvasLayer = null
var _ui_focus: TutorialUiTarget = null
var _marker: Node2D = null
var _guide_arrow: Node2D = null
var _route_guide: TutorialRouteGuide = null

var _current_step: int = 0
var _step_dialogue_done: bool = false
var _step_complete: bool = false
var _dialogue_pending: bool = false
var _finished: bool = false
var _tick_accum: float = 0.0

var _camp_cells: Dictionary = {}
var _camp_nodes: Dictionary = {}
var _automatica_station: Node = null
var _automatica_combat_station: Node = null
var _automatica_build_seen: bool = false
var _automatica_run_seen_ms: int = 0
var _camp_return_tried: bool = false

var _move_targets: Dictionary = {}
var _tree_target: Node2D = null
var _tree_felled: bool = false
var _tree_pos: Vector2 = Vector2.INF
var _wood_start: int = 0

var _travel_lang: String = ""
var _travel_started: bool = false
var _dungeon_index: int = 0
var _dungeon_lang: String = ""

var _cave_ore: Dictionary = {}
var _cave_ore_mined: bool = false
var _cave_ore_start_count: int = 0

var _waypoint_target_id: String = ""
var _waypoint_target_node: Node2D = null
var _waypoint_map_target_id: String = ""
var _waypoint_saw_map: bool = false
var _route_last_cell: Vector2i = Vector2i(-99999, -99999)
var _route_last_ms: int = -100000

# Cached target identity so the 0.2s verifier does not rebuild markers/focus
# every tick (which would restart their pulse animations).
var _marker_target: Vector2 = Vector2.INF
var _marker_text: String = ""
var _ui_target_control: Control = null
var _ui_target_text: String = ""
var _ui_screen_rect: Rect2 = Rect2()
var _obj_text: String = ""
var _obj_hint: String = ""
var _obj_optional: bool = false

func setup(spawn_pos: Vector2, world: Node2D) -> void:
	_spawn = spawn_pos
	_world = world
	process_mode = Node.PROCESS_MODE_ALWAYS
	Global.tutorial_version = 3
	if Global.tutorial_completed:
		queue_free()
		return
	if Global.tutorial_stage >= STEPS.size():
		_finish_tutorial(true)
		return
	_current_step = clampi(Global.tutorial_stage, 0, STEPS.size() - 1)
	_build_ui()
	_spawn_npcs()
	_setup_guide_arrow()
	_connect_signals()
	_ensure_safe_start()
	_ensure_camp()
	_ensure_starter_kit()
	_ensure_automatica()
	_recover_stage_after_load()
	call_deferred("_start_step")

func _connect_signals() -> void:
	if not Global.inventory_toggled.is_connected(_on_inventory_toggled):
		Global.inventory_toggled.connect(_on_inventory_toggled)
	if not Global.modal_hud_changed.is_connected(_on_modal_hud_changed):
		Global.modal_hud_changed.connect(_on_modal_hud_changed)
	if not Global.item_crafted.is_connected(_on_item_crafted):
		Global.item_crafted.connect(_on_item_crafted)
	if not Global.dungeon_entered.is_connected(_on_dungeon_entered):
		Global.dungeon_entered.connect(_on_dungeon_entered)
	if not Global.dungeon_exited.is_connected(_on_dungeon_exited):
		Global.dungeon_exited.connect(_on_dungeon_exited)
	if not Global.cave_entered.is_connected(_on_cave_entered):
		Global.cave_entered.connect(_on_cave_entered)
	if not Global.cave_exited.is_connected(_on_cave_exited):
		Global.cave_exited.connect(_on_cave_exited)
	if not Global.ui_scale_changed.is_connected(_on_ui_scale_changed):
		Global.ui_scale_changed.connect(_on_ui_scale_changed)

# ── UI ──────────────────────────────────────────────────────────────
func _build_ui() -> void:
	_dialogue_layer = CanvasLayer.new()
	_dialogue_layer.name = "TutorialDialogueLayer"
	_dialogue_layer.layer = 90
	_dialogue_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_dialogue_layer)
	_dialogue = DIALOGUE_SCRIPT.new() as TutorialDialogue
	_dialogue_layer.add_child(_dialogue)
	_dialogue.dismissed.connect(_on_dialogue_dismissed)
	_dialogue.skip_requested.connect(_on_dialogue_skip_requested)

	_objective_layer = CanvasLayer.new()
	_objective_layer.name = "TutorialObjectiveLayer"
	_objective_layer.layer = 28
	_objective_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_objective_layer)
	_objective_panel = PanelContainer.new()
	# Text card must never eat the tap/click intended for the highlighted target.
	_objective_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_objective_panel.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	var ps := StyleBoxFlat.new()
	ps.bg_color = Color(0.06, 0.085, 0.16, 0.95)
	ps.border_color = Color(0.27, 0.53, 0.78, 0.95)
	ps.set_border_width_all(1)
	ps.set_corner_radius_all(6)
	ps.content_margin_left = 14
	ps.content_margin_right = 14
	ps.content_margin_top = 8
	ps.content_margin_bottom = 8
	_objective_panel.add_theme_stylebox_override("panel", ps)
	_objective_layer.add_child(_objective_panel)
	var vbox := VBoxContainer.new()
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_theme_constant_override("separation", 3)
	_objective_panel.add_child(vbox)
	var title := Label.new()
	title.text = "GUIDED START"
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title.add_theme_color_override("font_color", Color(0.55, 0.86, 0.98, 1.0))
	vbox.add_child(title)
	_objective_label = Label.new()
	_objective_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_objective_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_objective_label.add_theme_color_override("font_color", Color(0.9, 0.95, 1.0, 1.0))
	vbox.add_child(_objective_label)
	_objective_hint = Label.new()
	_objective_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_objective_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_objective_hint.add_theme_color_override("font_color", Color(0.58, 0.70, 0.88, 1.0))
	_objective_hint.visible = false
	vbox.add_child(_objective_hint)
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.alignment = BoxContainer.ALIGNMENT_END
	vbox.add_child(row)
	_objective_skip = Button.new()
	_objective_skip.text = "Skip lesson"
	_objective_skip.mouse_filter = Control.MOUSE_FILTER_STOP
	_objective_skip.visible = false
	_objective_skip.pressed.connect(_skip_current_step)
	row.add_child(_objective_skip)

	_ui_focus_layer = CanvasLayer.new()
	_ui_focus_layer.name = "TutorialUiFocusLayer"
	# Above the map (120), quiz altar (30) and every station/editor layer.
	_ui_focus_layer.layer = 130
	_ui_focus_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_ui_focus_layer)
	_ui_focus = UI_TARGET_SCRIPT.new() as TutorialUiTarget
	_ui_focus_layer.add_child(_ui_focus)
	_layout_ui()

func _spawn_npcs() -> void:
	if _world == null or not is_instance_valid(_world):
		return
	_add_npc("Py-San", PY_SAN_TEX, _spawn + Vector2(-170.0, 34.0))
	_add_npc("LUA", LUA_TEX, _spawn + Vector2(170.0, 34.0))

func _add_npc(npc_name: String, texture_path: String, at: Vector2) -> void:
	var npc := NPC_SCRIPT.new() as Node2D
	npc.call("setup", npc_name, texture_path, self)
	npc.global_position = at
	_world.add_child(npc)
	_npc_nodes.append(npc)

func _setup_guide_arrow() -> void:
	var player := Global.player_node as Node2D
	if player == null or not is_instance_valid(player):
		return
	_guide_arrow = ARROW_SCRIPT.new() as Node2D
	_guide_arrow.name = "TutorialGuideArrow"
	player.add_child(_guide_arrow)

func _layout_ui() -> void:
	if _objective_panel == null or not is_inside_tree():
		return
	var s := Global.ui_scale
	var content := Global.ui_content_rect()
	var width := minf(content.size.x - 24.0 * s, 500.0 * s)
	width = maxf(260.0, width)
	_objective_panel.position = Vector2(
		content.position.x + (content.size.x - width) * 0.5,
		content.position.y + 118.0 * s)
	var inner_w: float = maxf(140.0, width - 32.0 * s)
	_objective_label.custom_minimum_size.x = inner_w
	_objective_hint.custom_minimum_size.x = inner_w
	_objective_panel.size = Vector2(width, 0.0)
	_objective_panel.reset_size()
	var card_h: float = maxf(48.0 * s, _objective_panel.get_combined_minimum_size().y)
	_objective_panel.size = Vector2(width, card_h)
	_objective_label.add_theme_font_size_override("font_size", Global.ui_font_size(12))
	_objective_hint.add_theme_font_size_override("font_size", Global.ui_font_size(10))
	_objective_skip.add_theme_font_size_override("font_size", Global.ui_font_size(9))
	var title := _objective_panel.get_child(0).get_child(0) as Label
	if title != null:
		title.add_theme_font_size_override("font_size", Global.ui_font_size(9))

func _on_ui_scale_changed(_s: float) -> void:
	_layout_ui()

func _set_objective(text: String, optional: bool = false, hint: String = "") -> void:
	if _objective_label == null:
		return
	if _obj_text == text and _obj_hint == hint and _obj_optional == optional \
			and _objective_panel.visible:
		return
	_obj_text = text
	_obj_hint = hint
	_obj_optional = optional
	_objective_label.text = text
	_objective_hint.text = hint
	_objective_hint.visible = not hint.is_empty()
	_objective_panel.visible = true
	_objective_skip.visible = optional
	_layout_ui()

func _set_objective_visible(on: bool) -> void:
	if _objective_panel != null:
		_objective_panel.visible = on
		if on:
			_layout_ui()

func _on_inventory_toggled(open: bool) -> void:
	if _objective_panel != null and not _finished:
		_objective_panel.visible = not open

func _on_modal_hud_changed(open: bool) -> void:
	if _objective_panel != null and not _finished:
		_objective_panel.visible = not open and not (_dialogue != null and _dialogue.is_active())

func _on_item_crafted(item_name: String, _quantity: int) -> void:
	if _finished:
		return
	if item_name == "Crafting Station":
		Global.tutorial_flags["crafted_station_v3"] = true
		_save_progress()

# ── Target helpers ──────────────────────────────────────────────────
func _clear_world_target() -> void:
	_marker_target = Vector2.INF
	_marker_text = ""
	if _marker != null and is_instance_valid(_marker):
		_marker.queue_free()
	_marker = null
	if _guide_arrow != null and is_instance_valid(_guide_arrow):
		_guide_arrow.call("clear_target")

func _focus_world(pos: Vector2, text: String) -> void:
	if pos == Vector2.INF:
		_clear_world_target()
		return
	if is_finite(_marker_target.x) and _marker_target.distance_to(pos) < 1.5 \
			and _marker_text == text and _marker != null and is_instance_valid(_marker):
		return
	_clear_world_target()
	if _guide_arrow != null and is_instance_valid(_guide_arrow):
		_guide_arrow.call("set_target", pos, text)
	var host := Global.world_node
	if host == null or not is_instance_valid(host):
		return
	var marker := MARKER_SCRIPT.new() as Node2D
	marker.set("label_text", text)
	host.add_child(marker)
	marker.global_position = pos
	_marker = marker
	_marker_target = pos
	_marker_text = text

func _clear_ui_target() -> void:
	_ui_target_control = null
	_ui_target_text = ""
	_ui_screen_rect = Rect2()
	if _ui_focus != null:
		_ui_focus.call("clear_target")

func _focus_ui(control: Control, text: String) -> void:
	if control == null or not is_instance_valid(control) or not control.is_visible_in_tree():
		_clear_ui_target()
		return
	if _ui_target_control == control and _ui_target_text == text \
			and _ui_focus != null and is_instance_valid(_ui_focus) and _ui_focus.visible:
		return
	_ui_target_control = control
	_ui_target_text = text
	_ui_screen_rect = Rect2()
	if _ui_focus != null:
		_ui_focus.call("set_target", control, text)

func _focus_rect(rect: Rect2, text: String) -> void:
	if _ui_target_control == null and _ui_screen_rect == rect and _ui_target_text == text \
			and _ui_focus != null and is_instance_valid(_ui_focus) and _ui_focus.visible:
		return
	_ui_target_control = null
	_ui_screen_rect = rect
	_ui_target_text = text
	if _ui_focus != null:
		_ui_focus.call("set_screen_target", rect, text)

func _clear_targets() -> void:
	_clear_world_target()
	_clear_ui_target()
	_clear_route()

# ── Save / step engine ──────────────────────────────────────────────
func _step_id() -> String:
	return str(STEPS[clampi(_current_step, 0, STEPS.size() - 1)])

func _step_index(id: String) -> int:
	return STEPS.find(id)

func _save_progress() -> void:
	Global.tutorial_stage = _current_step
	if Global.active_save_slot > 0 and Global.game_node != null:
		Global.save_game(Global.active_save_slot)

func _start_step() -> void:
	if _finished:
		return
	if Global.tutorial_completed or _current_step >= STEPS.size():
		_finish_tutorial(true)
		return
	Global.tutorial_stage = _current_step
	_step_complete = false
	_step_dialogue_done = false
	_dialogue_pending = false
	_tick_accum = 0.0
	_clear_targets()
	_prepare_step()
	var lines := _step_lines()
	if lines.is_empty():
		_step_dialogue_done = true
		_activate_step()
		return
	_set_objective_visible(false)
	if _dialogue != null and not _dialogue.is_active() \
			and not Global.any_ui_open() and not Global.pause_menu_open:
		if not _dialogue.show_conversation(lines, Callable(self, "_on_step_dialogue_done")):
			_dialogue_pending = true
	else:
		_dialogue_pending = true

func _activate_step() -> void:
	if _finished or _step_complete:
		return
	_set_objective_visible(true)
	if _tick_current():
		_complete_step()

func _on_step_dialogue_done() -> void:
	_step_dialogue_done = true
	_dialogue_pending = false
	_activate_step()

func _on_dialogue_dismissed() -> void:
	_dialogue_pending = false
	if _step_complete or _finished:
		return
	if _step_dialogue_done:
		_set_objective_visible(true)
		_activate_step()

func _on_dialogue_skip_requested() -> void:
	if _finished or _step_complete:
		return
	var active: bool = _dialogue != null and _dialogue.is_active()
	_skip_current_step()
	if active and _dialogue != null and _dialogue.is_active():
		_dialogue.dismiss()

func request_dialogue() -> void:
	if _finished or _dialogue == null or _dialogue.is_active():
		return
	var lines := _step_lines()
	if not lines.is_empty():
		_dialogue.show_conversation(lines, Callable(self, "_on_step_dialogue_done"))

func _process(delta: float) -> void:
	if _finished:
		return
	if _dialogue_pending and not Global.any_ui_open() and not Global.pause_menu_open \
			and _dialogue != null and not _dialogue.is_active():
		_start_step()
		return
	if not _step_dialogue_done or _step_complete:
		return
	if _dialogue != null and _dialogue.is_active():
		return
	_tick_accum += delta
	if _tick_accum < 0.20:
		return
	_tick_accum = 0.0
	if _tick_current():
		_complete_step()

func _complete_step() -> void:
	if _step_complete or _finished:
		return
	_step_complete = true
	_clear_targets()
	_current_step += 1
	Global.tutorial_stage = _current_step
	_save_progress()
	if _current_step >= STEPS.size():
		_finish_tutorial()
		return
	call_deferred("_start_step")

func _skip_current_step() -> void:
	if _finished or _step_complete:
		return
	var id := _step_id()
	Global.notify("Skipped onboarding lesson.")
	if id.begins_with("dungeon_"):
		if Global.is_in_dungeon and Global.game_node != null \
				and Global.game_node.has_method("exit_dungeon"):
			Global.game_node.call("exit_dungeon")
		# A skipped dungeon cannot satisfy its lesson; continue at the next
		# persistent camp lesson instead of looping back to travel.
		_current_step = _step_index("automatica")
		Global.tutorial_stage = _current_step
		_step_complete = true
		_save_progress()
		call_deferred("_start_step")
		return
	if id == "cave_regular" or id == "cave_pixie":
		if _current_cave_kind() != "" and Global.game_node != null \
				and Global.game_node.has_method("exit_cave"):
			Global.game_node.call("exit_cave")
	if id == "algorithmica":
		Global.tutorial_flags.erase("algorithmica_template_ready")
	_complete_step()

func _prepare_step() -> void:
	var id := _step_id()
	Global.tutorial_flags["v3_started"] = true
	match id:
		"move_one", "move_two":
			_move_targets[id] = _choose_move_cell(id == "move_two")
		"tree_chop":
			_tree_target = null
			_tree_felled = false
			_tree_pos = Vector2.INF
			_wood_start = Global.count_item(load(ITEM_WOOD) as ItemData)
		"craft_station":
			_ensure_tree_station_materials()
		"dungeon_travel":
			_close_inventory_for_transition()
			_travel_lang = _nearest_dungeon_language()
			_travel_started = false
		"dungeon_knowledge", "dungeon_quiz", "dungeon_exit":
			_dungeon_index = int(Global.tutorial_flags.get("dungeon_index", 0))
			_dungeon_lang = Global.dungeon_language(_dungeon_index) if _dungeon_index > 0 else ""
		"automatica":
			_camp_return_tried = false
			_automatica_run_seen_ms = 0
			_give_automatica_line_blocks()
		"automatica_combat":
			_camp_return_tried = false
			_automatica_combat_station = null
			_ensure_automatica()
			_grant_automatica_combat_kit()
		"algorithmica":
			# The furnace editor opens with ready-to-run tutorial code instead
			# of the normal commented example.
			Global.tutorial_flags["algorithmica_template_ready"] = true
		"cave_regular", "cave_pixie":
			_cave_ore = {}
			_cave_ore_mined = false
			_begin_cave_travel(id == "cave_pixie")
		"waypoint":
			_waypoint_target_id = ""
			_waypoint_target_node = null
			_waypoint_map_target_id = ""
			_waypoint_saw_map = false

func _step_lines() -> Array:
	match _step_id():
		"welcome":
			return [
				_line("Py-San", "Welcome to SandEE. Let's learn by doing."),
				_line("LUA", "Follow the arrow. Short steps, one action at a time."),
			]
		"finish":
			return [_line("Py-San", "Onboarding complete. The world and mission tracker are yours.")]
		"automatica":
			return [
				_line("LUA", "Automatica can do tasks for you: mine, chop, craft, build and more."),
				_line("Py-San", "I put 32 Wood in its BUILD SLOT 1. Open its editor and run the build-line example."),
			]
		"automatica_combat":
			return [
				_line("LUA", "Automatica can do more than build. It can fight beside you."),
				_line("Py-San", "Take this second Automatica and Wooden Sword. Place it, equip the sword in its TOOL slot, then run combat_mode(true)."),
			]
	return []

func _line(speaker: String, text: String) -> Dictionary:
	return {
		"speaker": speaker,
		"portrait": PY_SAN_TEX if speaker == "Py-San" else LUA_TEX,
		"text": text,
	}

func _click_verb() -> String:
	return "Tap" if Global.is_mobile() else "Click"

func _click_verb_lower() -> String:
	return "tap" if Global.is_mobile() else "click"

# ── Step verifiers ──────────────────────────────────────────────────
func _tick_current() -> bool:
	match _step_id():
		"welcome": return _step_dialogue_done
		"move_one", "move_two": return _tick_movement()
		"axe_select": return _tick_axe_select()
		"tree_chop": return _tick_tree()
		"craft_station": return _tick_craft_station()
		"dungeon_travel": return _tick_dungeon_travel()
		"dungeon_knowledge": return _tick_dungeon_knowledge()
		"dungeon_quiz": return _tick_dungeon_quiz()
		"dungeon_exit": return _tick_dungeon_exit()
		"automatica": return _tick_automatica()
		"automatica_combat": return _tick_automatica_combat()
		"algorithmica": return _tick_algorithmica()
		"cave_regular", "cave_pixie": return _tick_cave()
		"waypoint": return _tick_waypoint()
		"finish": return _step_dialogue_done
	return false

func _tick_movement() -> bool:
	var id := _step_id()
	var target: Vector2 = _move_targets.get(id, Vector2.INF) as Vector2
	var player := Global.player_node as Node2D
	if player == null:
		return false
	if target == Vector2.INF:
		_set_objective("Find open ground to walk on.", true)
		return false
	_focus_world(target, "Move here")
	if Global.point_and_click:
		_set_objective("%s here to move." % _click_verb(), false,
			"The marker is the destination. Walk onto it.")
	else:
		var how := ("Use the joystick" if Global.is_mobile() else "Use WASD or the arrow keys")
		_set_objective("%s to walk to the marker." % how, false,
			"The marker is the destination.")
	return player.global_position.distance_to(target) <= MOVE_ARRIVE_PX

func _tick_axe_select() -> bool:
	var axe := load(ITEM_AXE) as ItemData
	var idx := _find_hotbar_item(ITEM_AXE)
	if idx < 0:
		# Recovery only: the starter axe is missing (dropped/destroyed).
		Global.grant_item(ITEM_AXE, 1)
		idx = _find_hotbar_item(ITEM_AXE)
	if idx < 0:
		_set_objective("Get the Wooden Axe into your hotbar.", true)
		return false
	if Global.held_tool_id() == ITEM_AXE:
		return true
	var slot := _hotbar_slot_control(idx)
	_focus_ui(slot, "Tap here to select your axe.")
	_set_objective("Select the Wooden Axe.", false, "The highlighted hotbar slot holds it.")
	return false

func _tick_tree() -> bool:
	if Global.held_tool_id() != ITEM_AXE:
		var idx := _find_hotbar_item(ITEM_AXE)
		if idx >= 0:
			_focus_ui(_hotbar_slot_control(idx), "Tap here to select your axe.")
			_set_objective("Select the Wooden Axe first.", false)
			return false
	var wood := load(ITEM_WOOD) as ItemData
	if _tree_felled or Global.count_item(wood) >= _wood_start + TUTORIAL_WOOD_COUNT:
		return _tick_wood_pickup()
	if _tree_target == null or not is_instance_valid(_tree_target):
		if _tree_pos != Vector2.INF:
			_tree_felled = true
			return _tick_wood_pickup()
		_tree_target = _find_nearest_tree()
		if _tree_target == null:
			_set_objective("Find a tree to chop.", true)
			return false
	var tree_pos := _tree_target.global_position
	_tree_pos = tree_pos
	var p := Global.player_node as Node2D
	if Global.point_and_click:
		# PNC walks to the tree and auto-chops; one tap is enough.
		_focus_world(tree_pos, "Chop this tree")
		_set_objective("%s the tree to chop it." % _click_verb(), false,
			"You will walk there automatically.")
		return false
	if p != null and not bool(_tree_target.get("_player_nearby")):
		var blocks: int = maxi(1, int(round(p.global_position.distance_to(tree_pos) / 32.0)))
		_focus_world(tree_pos, "Walk to this tree")
		_set_objective("Walk to the tree.", false,
			"It is %d blocks away. The arrow points to the nearest tree." % blocks)
		return false
	_focus_world(tree_pos, "Chop this tree")
	_set_objective("%s the tree to chop it." % _click_verb(), false,
		"Keep the Wooden Axe selected. Pick up the dropped wood.")
	return false

func _tick_wood_pickup() -> bool:
	var wood := load(ITEM_WOOD) as ItemData
	if Global.count_item(wood) >= _wood_start + TUTORIAL_WOOD_COUNT:
		return true
	var drop_pos := _nearest_wood_item_pos()
	if drop_pos == Vector2.INF:
		# The dropped stack is gone and the requirement is not met. Point at
		# another EXISTING tree rather than spawning a tutorial-only tree (a
		# runtime-spawned tree may not be in the world's tree spatial cache and
		# can therefore be unclickable).
		_tree_felled = false
		_tree_pos = Vector2.INF
		_tree_target = _find_nearest_tree()
		if _tree_target == null:
			_set_objective("Find a tree to chop.", true)
		return false
	_focus_world(drop_pos, "Pick up wood")
	_set_objective("Pick up the wood.", false, "Walk over the dropped wood.")
	return false

func _tick_craft_station() -> bool:
	var station := load(ITEM_CRAFTING) as ItemData
	var crafted := bool(Global.tutorial_flags.get("crafted_station_v3", false))
	if crafted and Global.count_item(station) > 0:
		_clear_targets()
		return true
	if crafted or Global.count_item(station) > 0:
		# The station was crafted but is no longer carried (placed/lost), or a
		# found station must not stand in for the required craft action.
		_ensure_tree_station_materials()
	var inv := _inventory_ui()
	if inv == null:
		_set_objective("Open your inventory.", true)
		return false
	if not _inventory_open():
		var inv_btn := _mobile_inventory_button()
		if inv_btn != null:
			_focus_ui(inv_btn, "Tap here to open your inventory.")
		else:
			_clear_ui_target()
		_set_objective("Open your inventory (%s)." % ("INV" if Global.is_mobile() else "E"),
			false, "You need 4 Wood to craft the Crafting Station.")
		return false
	if not bool(inv.call("tutorial_craft_open")):
		_focus_ui(inv.call("tutorial_craft_tab") as Control, "Tap here to craft.")
		_set_objective("Open the CRAFT tab.", false)
		return false
	if str(inv.call("tutorial_craft_active_category")) != "Blocks":
		_focus_ui(inv.call("tutorial_craft_category", "Blocks") as Control, "Tap here for Blocks.")
		_set_objective("Choose the Blocks category.", false)
		return false
	if not bool(inv.call("tutorial_recipe_selected", "Crafting Station")):
		inv.call("tutorial_ensure_recipe_visible", "Crafting Station")
		var recipe := inv.call("tutorial_recipe_button", "Crafting Station") as Control
		_focus_ui(recipe, "Tap here to choose the Crafting Station.")
		_set_objective("Choose the Crafting Station recipe.", false,
			"It costs 4 Wood. Your tree supplied it.")
		return false
	_focus_ui(inv.call("tutorial_craft_button") as Control, "Tap here to craft.")
	_set_objective("Tap CRAFT.", false)
	return false

func _tick_dungeon_travel() -> bool:
	if Global.is_in_dungeon:
		return true
	if not _travel_started:
		_begin_dungeon_travel()
		return false
	if _travel_lang.is_empty():
		_set_objective("No dungeon entrance is available. Explore, or skip this lesson.", true)
		return false
	var target: Vector2 = _world.call("get_dungeon_entrance_target", _travel_lang) as Vector2
	if target == Vector2.INF:
		_set_objective("The dungeon entrance is not available yet.", true)
		return false
	_focus_world(target, "Dungeon entrance")
	_set_objective("%s the %s dungeon portal." % [_click_verb(), _travel_lang.capitalize()], false,
		"Confirm the portal prompt. The next lesson starts inside.")
	return false

func _tick_dungeon_knowledge() -> bool:
	if not Global.is_in_dungeon:
		if _dungeon_cleared():
			_set_current_step("automatica")
			return false
		_set_current_step("dungeon_travel")
		return false
	var mission := Global.get_dungeon_mission_for_index(_dungeon_index)
	var entry: KnowledgeEntry = mission.entry() if mission != null else null
	if entry != null and Global.has_learned_entry(entry.id()):
		return true
	var altar := _nearest_group_node("KnowledgeAltar")
	if altar == null:
		# Extra/boss dungeons intentionally have no Knowledge Altar.
		return true
	_focus_world((altar as Node2D).global_position, "Knowledge Altar")
	_set_objective("%s here to learn." % _click_verb(), false,
		"Read the lesson, then close it. Your Encyclopedia records it.")
	return false

func _tick_dungeon_quiz() -> bool:
	if _dungeon_cleared():
		return true
	if not Global.is_in_dungeon:
		_set_current_step("dungeon_travel")
		return false
	var altar := _nearest_group_node("QuizAltar")
	if altar == null:
		_set_objective("Find the Quiz Altar to finish the dungeon.", true)
		return false
	if not bool(altar.call("tutorial_is_open")):
		_focus_world((altar as Node2D).global_position, "Quiz Altar")
		_set_objective("%s here to open quiz." % _click_verb(), false)
		_ensure_dungeon_route()
		return false
	_clear_world_target()
	if bool(altar.call("tutorial_reward_visible")):
		_set_current_step("dungeon_exit")
		return false
	_ensure_dungeon_route()
	var hint_btn := altar.call("tutorial_hint_button") as Control
	var hint_open := bool(altar.call("tutorial_hint_open"))
	var hint_failed := bool(altar.call("tutorial_hint_run_failed"))
	var hints_used := int(altar.get("_hints_used"))
	var run_btn := altar.call("tutorial_run_button") as Control
	if hint_open:
		if hint_failed:
			# The hinted run was attempted and failed. Now NEXT dismisses the
			# hint panel; the filled code is kept for the retry.
			_focus_ui(hint_btn, "Tap Next to close the hint.")
			_set_objective("Tap NEXT to hide the hint.", false,
				"Then fix the answer and try again.")
			return false
		if run_btn != null and run_btn.visible:
			if str(altar.call("tutorial_code_text")).is_empty():
				_focus_ui(hint_btn, "Tap here for hint.")
				_set_objective("Tap HINT to prepare the code.", false)
			else:
				_focus_ui(run_btn, "Tap here to run.")
				_set_objective("Tap RUN to check the hinted code.", false,
					"You still press RUN yourself.")
			return false
		var answers_hint := altar.call("tutorial_answers_control") as Control
		_focus_ui(answers_hint, "")
		_set_objective("Tap the highlighted answer.", false,
			"Then try another answer, or press NEXT to hide the hint.")
		return false
	var demo_done := bool(Global.tutorial_flags.get("quiz_hint_demo", false))
	if not demo_done:
		if hints_used > 0:
			Global.tutorial_flags["quiz_hint_demo"] = true
			_save_progress()
		else:
			_focus_ui(hint_btn, "Tap here for hint.")
			var free_note := "Hints are free in the first dungeon." if _is_first_dungeon() \
				else "Using a hint costs one blue star."
			_set_objective("Tap HINT to see a hint.", false, free_note)
			return false
	if run_btn != null and run_btn.visible:
		if str(altar.call("tutorial_code_text")).is_empty():
			# Never tell the player to RUN an empty editor. HINT prepares the
			# code; they still press RUN themselves afterwards.
			_focus_ui(hint_btn, "Tap here for hint.")
			_set_objective("Tap HINT to prepare the code.", false,
				"Then press RUN yourself.")
			return false
		_focus_ui(run_btn, "Tap here to run.")
		_set_objective("Tap RUN to submit your code.", false,
			"A wrong result costs one blue star.")
	else:
		var answers := altar.call("tutorial_answers_control") as Control
		# Highlight the answer area only; the objective card already explains
		# the choice. A label above the answers used to cover the question/code.
		_focus_ui(answers, "")
		_set_objective("Choose the answer that matches the lesson.", false)
	return false

func _tick_dungeon_exit() -> bool:
	if not Global.is_in_dungeon:
		return true
	var altar := _nearest_group_node("QuizAltar")
	if altar != null and bool(altar.call("tutorial_reward_visible")):
		var done := altar.call("tutorial_reward_done") as Control
		_focus_ui(done, "Tap here to return.")
		_set_objective("Review the results, then tap DONE.", false)
		return false
	if _dungeon_cleared():
		_set_objective("Open the quiz results and tap DONE.", false)
		return false
	_set_current_step("dungeon_quiz")
	return false

func _tick_automatica() -> bool:
	if bool(Global.tutorial_flags.get("automatica_lesson_done", false)):
		return true
	if not _ensure_camp_return():
		return false
	_ensure_automatica()
	if _automatica_station == null or not is_instance_valid(_automatica_station):
		_set_objective("Automatica is unavailable. I will restore the camp station.", false)
		_ensure_automatica()
		return false

	# The build itself is asynchronous: the Lua run finishes immediately, then
	# the robot plays out one placement at a time. This state check does not
	# need the editor, so the player may close it to watch the line being built.
	var wood_left := _automatica_wood_left()
	var run_code := str(_automatica_station.get("program_code"))
	var busy := _automatica_busy(_automatica_station)
	if busy or wood_left < AUTOMATICA_LINE_BLOCKS:
		_automatica_build_seen = true
	if _automatica_build_seen and not busy \
			and AUTOMATICA_LINE_BLOCKS - wood_left >= AUTOMATICA_LINE_MIN_PLACED \
			and run_code.contains("build_line"):
		Global.tutorial_flags["automatica_lesson_done"] = true
		_save_progress()
		return true
	if busy:
		_clear_targets()
		_set_objective("Watch Automatica build your line.", false,
			"Close the editor if it covers the camp.")
		return false

	var editor := _station_editor(_automatica_station)
	if editor == null or not editor.visible:
		if Global.any_ui_open():
			_set_objective("Close the open panel to continue.", false)
			_clear_targets()
			return false
		_focus_world((_automatica_station as Node2D).global_position, "Automatica")
		_set_objective("%s Automatica to open its editor." % _click_verb(), false,
			"Automatica can do tasks for you. BUILD SLOT 1 has 32 Wood waiting.")
		return false
	_clear_world_target()
	var code := str(editor.call("tutorial_code_text"))
	var ran := bool(editor.call("tutorial_run_succeeded"))
	if not ran:
		_automatica_run_seen_ms = 0
	elif _automatica_run_seen_ms == 0:
		_automatica_run_seen_ms = Time.get_ticks_msec()
	if not code.contains("build_line"):
		# Recovery only: a save/load or an emptied slot must not strand the
		# lesson. Never top up once the line has started building.
		if wood_left < AUTOMATICA_LINE_BLOCKS and not _automatica_build_seen:
			_give_automatica_line_blocks()
		editor.call("tutorial_show_code_tab")
		var snippet := editor.call("tutorial_snippet_button", "1. Build a line") as Control
		if snippet != null:
			_focus_ui(snippet, "Tap the build-line example.")
		_set_objective("Tap the build-line example.", false,
			"It tells Automatica to build a line with the 32 Wood.")
		return false
	if ran:
		# Give the deferred build queue a moment to start before declaring the
		# run empty. After that, a still-full slot means nothing was placed.
		if not _automatica_build_seen:
			if Time.get_ticks_msec() - _automatica_run_seen_ms < 1200:
				_clear_targets()
				_set_objective("Watch Automatica start building.", false)
				return false
			_give_automatica_line_blocks()
			_set_objective("The line did not build. Run it again.", false,
				"Make sure BUILD SLOT 1 holds the 32 Wood.")
		elif wood_left >= AUTOMATICA_LINE_BLOCKS:
			_set_objective("The robot could not place the blocks.", false,
				"Stand back and make sure the ground in front of it is clear.")
		else:
			_set_objective("Run the build-line example again.", false)
		editor.call("tutorial_show_code_tab")
		_focus_ui(editor.call("tutorial_run_button") as Control, "Tap here to run.")
		return false
	editor.call("tutorial_show_code_tab")
	_focus_ui(editor.call("tutorial_run_button") as Control, "Tap here to run.")
	_set_objective("Tap RUN and watch Automatica build.", false,
		"Automatica can do tasks for you. It places all 32 Wood one block at a time.")
	return false

func _tick_automatica_combat() -> bool:
	if bool(Global.tutorial_flags.get("automatica_combat_done", false)):
		return true
	if not _ensure_camp_return():
		return false
	if not _grant_automatica_combat_kit():
		_set_objective("Make room in your inventory for the Automatica and Wooden Sword.", true)
		return false
	var station := _find_second_automatica()
	if station != null and _station_has_sword(station) \
			and bool(station.call("is_combat")):
		Global.tutorial_flags["automatica_combat_done"] = true
		_save_progress()
		return true
	if station == null:
		var idx := _find_hotbar_item(ITEM_AUTOMATICA)
		if idx >= 0:
			_focus_ui(_hotbar_slot_control(idx), "Select the Automatica.")
			var place_hint := "After selecting it, tap BUILD and tap the ground."
			if not Global.is_mobile():
				place_hint = "After selecting it, press Ctrl for build mode and click the ground."
			_set_objective("Select the second Automatica.", false, place_hint)
		else:
			_clear_targets()
			_set_objective("Place the second Automatica near camp.", false,
				"Move it into your hotbar, select it, then use build mode to place it.")
		return false
	var editor := _station_editor(station)
	if Global.any_ui_open() and (editor == null or not editor.visible):
		_set_objective("Close the open panel to continue.", false)
		_clear_targets()
		return false
	if editor == null or not editor.visible:
		_focus_world((station as Node2D).global_position, "Second Automatica")
		_set_objective("%s the second Automatica to open its editor." % _click_verb(), false)
		return false
	_clear_world_target()

	# The lesson equips the supplied Wooden Sword, not just any item.
	if not _station_has_sword(station):
		_ensure_combat_sword()
		editor.call("tutorial_show_inventory_tab")
		var tool_slot := editor.call("tutorial_tool_slot") as Control
		if tool_slot != null:
			_focus_ui(tool_slot, "Drop the Wooden Sword here.")
		_set_objective("Drag the Wooden Sword into the robot's TOOL slot.", false,
			"Drag the sword from your items into TOOL on the Inventory tab.")
		return false
	if bool(station.call("is_combat")):
		Global.tutorial_flags["automatica_combat_done"] = true
		_save_progress()
		return true
	var code := str(editor.call("tutorial_code_text"))
	if not code.contains("combat_mode(true)"):
		editor.call("tutorial_show_code_tab")
		var snippet := editor.call("tutorial_snippet_button", "2. Combat mode") as Control
		if snippet != null:
			_focus_ui(snippet, "Tap the combat-mode example.")
		_set_objective("Tap the combat-mode example.", false,
			"combat_mode(true) turns this Automatica into a fighter.")
		return false
	editor.call("tutorial_show_code_tab")
	_focus_ui(editor.call("tutorial_run_button") as Control, "Tap here to run.")
	_set_objective("Tap RUN to enter combat mode.", false,
		"This is permanent. The robot will follow and fight beside you.")
	return false

func _tick_algorithmica() -> bool:
	if bool(Global.tutorial_flags.get("algorithmica_lesson_done", false)):
		return true
	if not _ensure_camp_return():
		return false
	_ensure_camp()
	var furnace := _camp_nodes.get("furnace") as Node
	if furnace == null or not is_instance_valid(furnace):
		# Re-adopt a restored furnace (no TutorialCamp tag after save/load) or
		# rebuild it at a nearby free camp cell before showing an error.
		_ensure_camp_role_nodes()
		furnace = _camp_nodes.get("furnace") as Node
	if furnace == null or not is_instance_valid(furnace):
		_set_objective("The camp furnace is unavailable. Making room to rebuild it.", false)
		return false
	var menu := furnace.get("_ui") as Control
	if menu != null and not menu.visible and Global.any_ui_open():
		_set_objective("Close Automatica to continue.", false)
		_clear_targets()
		return false
	if menu == null or not menu.visible:
		_focus_world((furnace as Node2D).global_position, "Furnace")
		_set_objective("%s the furnace to open Algorithmica." % _click_verb(), false)
		return false
	_clear_world_target()
	var panel := menu.call("tutorial_program_panel") as Control
	if panel == null or not panel.visible:
		_focus_ui(menu.call("tutorial_program_button") as Control, "Tap ALGORITHMICA.")
		_set_objective("Tap ALGORITHMICA.", false)
		return false
	if bool(panel.call("tutorial_run_succeeded")):
		var output := str(panel.call("tutorial_output_text"))
		if output.contains("Algorithmica ready"):
			Global.tutorial_flags["algorithmica_lesson_done"] = true
			Global.tutorial_flags.erase("algorithmica_template_ready")
			_save_progress()
			return true
		_set_objective("Print the exact text \"Algorithmica ready\".", false,
			"The program ran, but the expected text was not shown.")
		_focus_ui(panel.call("tutorial_code_editor") as Control, "Fix the printed text.")
		return false
	var code := str(panel.call("tutorial_code_text"))
	if not code.contains("print("):
		_focus_ui(panel.call("tutorial_code_editor") as Control, "Type the Python example.")
		_set_objective("Type print(\"Algorithmica ready\") in the editor.", false,
			"Keep the quotes and parentheses exactly as shown.")
		return false
	_focus_ui(panel.call("tutorial_run_button") as Control, "Tap here to run.")
	_set_objective("Tap RUN.", false, "A successful run completes this lesson.")
	return false

func _tick_cave() -> bool:
	var want_pixie := _step_id() == "cave_pixie"
	if Global.any_ui_open():
		_set_objective("Close the open panel to continue.", false)
		_clear_targets()
		return false
	var in_kind := _current_cave_kind()
	if in_kind != "":
		if (want_pixie and in_kind != "pixie") or (not want_pixie and in_kind != "cave"):
			_set_current_step("cave_regular" if in_kind == "cave" else "cave_pixie")
			return false
		Global.tutorial_flags["cave_%s_entered" % in_kind] = true
		var inspected := bool(Global.tutorial_flags.get("cave_%s_inspected" % in_kind, false))
		if not inspected and Global.held_tool_id() != ITEM_PICKAXE:
			var idx := _find_hotbar_item(ITEM_PICKAXE)
			if idx < 0:
				Global.grant_item(ITEM_PICKAXE, 1)
				idx = _find_hotbar_item(ITEM_PICKAXE)
			if idx >= 0:
				_focus_ui(_hotbar_slot_control(idx), "Select the Wooden Pickaxe.")
				_set_objective("Select the Wooden Pickaxe.", false)
				return false
		if not inspected:
			if _cave_ore.is_empty():
				_cave_ore = _nearest_cave_ore(in_kind)
				_cave_ore_mined = false
				_cave_ore_start_count = 0
				if not _cave_ore.is_empty():
					var ore_data := load(str(_cave_ore["item"])) as ItemData
					_cave_ore_start_count = Global.count_item(ore_data)
				else:
					# No ore is reachable in this layout: entry + a look around is
					# the whole lesson. Record it so the exit verifier can complete.
					Global.tutorial_flags["cave_%s_inspected" % in_kind] = true
					_save_progress()
					_set_objective("Explore, then return to the cave exit.", false,
						"Caves contain stone and ores. The exit marker returns you to the overworld."
						if in_kind == "cave" else
						"Pixie Caves contain regrowing crystal ores guarded by pixies.")
					return false
			if not _cave_ore.is_empty():
				var ore_cell: Vector2i = _cave_ore["cell"] as Vector2i
				var gen = Global.world_node.get("generator")
				var still_ore: bool = gen != null and int(gen.grid[ore_cell.x][ore_cell.y]) != 0
				if not still_ore:
					_cave_ore_mined = true
				if not _cave_ore_mined:
					_focus_world(_cave_ore["pos"] as Vector2, "Mine this ore")
					_set_objective("Mine this %s." % str(_cave_ore["label"]), false,
						"Keep the Wooden Pickaxe selected.")
					return false
				var ore_data := load(str(_cave_ore["item"])) as ItemData
				if Global.count_item(ore_data) < _cave_ore_start_count + 1:
					_focus_world(_cave_ore["pos"] as Vector2, "Pick up the ore")
					_set_objective("Pick up the dropped ore.", false)
					return false
				_cave_ore = {}
				Global.tutorial_flags["cave_%s_inspected" % in_kind] = true
				_save_progress()
		var exit_portal := _find_cave_exit()
		if exit_portal != null:
			_focus_world(exit_portal.global_position, "Cave exit")
			_set_objective("Return to the cave exit.", false,
				"Step onto the exit marker to return to the overworld.")
		else:
			_set_objective("Find the cave exit.", true)
		return false
	if _teleporting():
		_set_objective("Moving to the %s entrance..." % ("Pixie Cave" if want_pixie else "cave"), false)
		return false
	var relocate_key := "cave_pixie_relocated" if want_pixie else "cave_regular_relocated"
	if not bool(Global.tutorial_flags.get(relocate_key, false)):
		_begin_cave_travel(want_pixie)
		if _teleporting():
			_set_objective("Moving to the %s entrance..." % ("Pixie Cave" if want_pixie else "cave"), false)
			return false
	var portal := _nearest_cave_portal(want_pixie)
	if portal == null:
		_set_objective("No %s entrance is available. Explore, or skip this lesson."
			% ("Pixie Cave" if want_pixie else "cave"), true)
		return false
	_focus_world(portal.global_position, "Pixie Cave" if want_pixie else "Cave")
	_set_objective("%s here to explore." % _click_verb(), false,
		"Stand in the gateway and confirm the prompt."
		if not want_pixie else "Pixie Caves hold regrowing crystal ores and pixies.")
	return false

func _tick_waypoint() -> bool:
	if bool(Global.tutorial_flags.get("waypoint_lesson_done", false)):
		return true
	var mini := get_tree().get_first_node_in_group("Minimap")
	if mini != null and bool(mini.get("_expanded")) and bool(mini.get("_waypoint_mode")):
		_waypoint_saw_map = true
		Global.tutorial_flags["waypoint_map_seen"] = true
		var hits: Array = mini.get("_waypoint_hitboxes") as Array
		if hits.is_empty():
			_focus_rect(Rect2(Global.ui_content_rect().position, Vector2(120, 60) * Global.ui_scale),
				"No other waypoint yet. Close the map.")
			return false
		var target: Dictionary = hits[0] as Dictionary
		_waypoint_map_target_id = str(target.get("id", ""))
		var pos: Vector2 = target["pos"] as Vector2
		var s := Global.ui_scale
		_focus_rect(Rect2(pos - Vector2(18, 18) * s, Vector2(36, 36) * s),
			"Tap here to teleport.")
		if _waypoint_target_node == null or not is_instance_valid(_waypoint_target_node):
			_waypoint_target_node = _waypoint_node_by_id(_waypoint_map_target_id)
		return false
	_clear_ui_target()
	if _waypoint_saw_map and _waypoint_map_target_id.is_empty():
		# Only one waypoint exists: opening its map demonstrated the interface.
		Global.tutorial_flags["waypoint_lesson_done"] = true
		_save_progress()
		return true
	var node := _nearest_waypoint()
	if node == null:
		_set_objective("No Skyglass Waypoint is available. Explore, or skip this lesson.", true)
		return false
	_waypoint_target_id = str(node.get("waypoint_id"))
	_waypoint_target_node = node
	if _teleporting():
		_set_objective("Moving near the waypoint...", false)
		return false
	if _waypoint_map_target_id != "" and Global.tutorial_flags.get("waypoint_map_seen", false):
		# The player used the map. If the map closed and the target is nearby,
		# the real waypoint teleport completed.
		var map_target := _waypoint_node_by_id(_waypoint_map_target_id)
		var p := Global.player_node as Node2D
		if map_target != null and p != null and p.global_position.distance_to(map_target.global_position) < 420.0:
			Global.tutorial_flags["waypoint_lesson_done"] = true
			_save_progress()
			return true
	if not bool(Global.tutorial_flags.get("waypoint_relocated", false)) and not _teleporting():
		var p := Global.player_node as Node2D
		if p != null and p.global_position.distance_to(node.global_position) > 420.0:
			if bool(_world.call("teleport_to_world_waypoint", _waypoint_target_id)):
				Global.tutorial_flags["waypoint_relocated"] = true
				_save_progress()
				_set_objective("Moving near the nearest waypoint...", false)
				return false
			Global.tutorial_flags["waypoint_relocated"] = true
			_save_progress()
	_focus_world(node.global_position, "Skyglass Waypoint")
	_set_objective("%s here to view waypoint." % _click_verb(), false,
		"You were moved near the nearest tower for this lesson. Tap the tower, then a teal diamond.")
	return false

# ── Movement / trees / materials ────────────────────────────────────
func _choose_move_cell(second: bool) -> Vector2:
	var base := _base_tile()
	var offsets: Array = [
		Vector2i(3, 0), Vector2i(0, 3), Vector2i(-3, 0), Vector2i(0, -3),
		Vector2i(2, 2), Vector2i(-2, 2), Vector2i(2, -2), Vector2i(-2, -2),
		Vector2i(4, 1), Vector2i(1, 4), Vector2i(-4, 1), Vector2i(1, -4),
	]
	if second:
		offsets.reverse()
	for off_value in offsets:
		var cell := base + (off_value as Vector2i)
		if _cell_walkable(cell):
			return _cell_world(cell)
	# The camp can be hemmed in by a structure or resource on a tight spawn.
	# Search a wider ring before giving up so the lesson never deadlocks.
	for radius in range(5, 9):
		for dx in range(-radius, radius + 1):
			for dy in range(-radius, radius + 1):
				if maxi(absi(dx), absi(dy)) != radius:
					continue
				var cell := base + Vector2i(dx, dy)
				if _cell_walkable(cell):
					return _cell_world(cell)
	return Vector2.INF

func _cell_walkable(cell: Vector2i) -> bool:
	if _world == null:
		return false
	if _world.has_method("_is_open_for_player"):
		var half_w: int = int(_world.get("width")) / 2
		var half_h: int = int(_world.get("height")) / 2
		if not bool(_world.call("_is_open_for_player", cell, half_w, half_h)):
			return false
	if bool(_world.call("cell_is_water", cell)):
		return false
	if bool(_world.call("has_placed_block", cell)):
		return false
	var trees: Dictionary = _world.get("_tree_occupied_tiles") as Dictionary
	if trees.has(cell):
		return false
	return true

func _find_nearest_tree() -> Node2D:
	var p := Global.player_node as Node2D
	if p == null:
		return null
	# Never spawn a tutorial tree. The world deliberately keeps the spawn area
	# clear of trees, so the nearest one may be just outside that clearing
	# (~25 tiles). Point at the nearest EXISTING tree and let the compass guide
	# the player there. Prefer a plain tree because the Crafting Station recipe
	# consumes plain Wood; if this world's biome has none, fall back to the
	# nearest tree of any type and the craft step's material recovery handles
	# the wood conversion.
	var best_plain: Node2D = null
	var best_plain_d := INF
	var best_any: Node2D = null
	var best_any_d := INF
	for node in get_tree().get_nodes_in_group("Tree"):
		if not is_instance_valid(node) or not node is Node2D:
			continue
		var n := node as Node2D
		if n.is_queued_for_deletion():
			continue
		var d := p.global_position.distance_to(n.global_position)
		if d < best_any_d:
			best_any_d = d
			best_any = n
		if int(n.get("tree_type")) == 0 and d < best_plain_d:
			best_plain_d = d
			best_plain = n
	return best_plain if best_plain != null else best_any

func _nearest_wood_item_pos() -> Vector2:
	var p := Global.player_node as Node2D
	if p == null or Global.world_node == null:
		return Vector2.INF
	var wood := load(ITEM_WOOD) as ItemData
	var best := Vector2.INF
	var best_d := INF
	for node in Global.world_node.get_children():
		if not node is Node2D or node.is_queued_for_deletion():
			continue
		var data: Variant = node.get("item_data")
		if data == wood:
			var d := p.global_position.distance_to((node as Node2D).global_position)
			if d < best_d:
				best_d = d
				best = (node as Node2D).global_position
	return best

func _ensure_tree_station_materials() -> void:
	var wood := load(ITEM_WOOD) as ItemData
	var station := load(ITEM_CRAFTING) as ItemData
	var crafted := bool(Global.tutorial_flags.get("crafted_station_v3", false))
	if crafted and Global.count_item(station) > 0:
		return
	if Global.count_item(wood) >= TUTORIAL_WOOD_COUNT:
		return
	# The wood was lost after the harvest (death cleanup, dropped stack despawn),
	# or the crafted station was placed/lost. Recovery only: return the minimum
	# recipe amount, never more.
	Global.grant_item(ITEM_WOOD, TUTORIAL_WOOD_COUNT - Global.count_item(wood))

# ── Hotbar / inventory helpers ──────────────────────────────────────
func _find_hotbar_item(path: String) -> int:
	for i in range(Global.Hotbar.size()):
		var slot: Variant = Global.Hotbar[i]
		if slot is Dictionary:
			var data: ItemData = (slot as Dictionary).get("data") as ItemData
			if data != null and (data.resource_path == path or data.item_name == "Wooden Axe" and path == ITEM_AXE):
				return i
	return -1

func _hotbar_slot_control(index: int) -> Control:
	for node in get_tree().get_nodes_in_group("hotbar_slot"):
		if node is Control and int(node.get("slot_index")) == index:
			return node as Control
	return null

func _mobile_inventory_button() -> Control:
	for node in get_tree().get_nodes_in_group("hotbar_slot"):
		if node is Control:
			var b := (node as Control).get_node_or_null("InventoryButton") as Control
			if b != null and b.visible:
				return b
	return null

func _inventory_ui() -> Control:
	var p := Global.player_node
	if p == null:
		return null
	return p.get_node_or_null("InventoryUI/InventoryUi") as Control

func _inventory_open() -> bool:
	var p := Global.player_node
	if p == null:
		return false
	var layer := p.get_node_or_null("InventoryUI") as CanvasLayer
	return layer != null and layer.visible

func _close_inventory_for_transition() -> void:
	if not _inventory_open():
		return
	var inv := _inventory_ui()
	if inv != null and inv.has_method("_close"):
		inv.call("_close")
	elif Global.player_node != null and Global.player_node.has_method("toggle_inventory"):
		Global.player_node.call("toggle_inventory")

# ── Camp / kit / stations ───────────────────────────────────────────
func _ensure_safe_start() -> void:
	if bool(Global.tutorial_flags.get("safe_start_v3", false)):
		return
	var p := Global.player_node as Node2D
	if p != null and _world != null:
		var cell := _world.call("world_to_cell", p.global_position) as Vector2i
		var bad: bool = bool(_world.call("cell_is_water", cell)) \
			or bool(_world.call("_is_hazardous_landing", p.global_position))
		if bad:
			var dest: Vector2 = _world.call("_safe_landing_near_tile", cell, 12) as Vector2
			if dest != Vector2.INF:
				p.global_position = dest
				_spawn = dest
	Global.tutorial_flags["safe_start_v3"] = true
	_save_progress()

func _ensure_starter_kit() -> void:
	if bool(Global.tutorial_flags.get("starter_kit_v3", false)):
		return
	for path in [ITEM_AXE, ITEM_PICKAXE, ITEM_SWORD]:
		var data := load(path) as ItemData
		if data != null and Global.count_item(data) <= 0:
			Global.grant_item(path, 1)
	var bread := load(ITEM_BREAD) as ItemData
	if bread != null and Global.count_item(bread) < 10:
		Global.grant_item(ITEM_BREAD, 10 - Global.count_item(bread))
	# Leave the axe unselected so the axe lesson is a real action rather than an
	# automatic pass. Only applies while creating the starter kit.
	var axe_idx := _find_hotbar_item(ITEM_AXE)
	if axe_idx >= 0 and Global.hotbar_selected == axe_idx:
		for i in range(Global.Hotbar.size()):
			if i != axe_idx and Global.Hotbar[i] != null:
				Global.set_hotbar_selection(i)
				break
	Global.tutorial_flags["starter_kit_v3"] = true
	_save_progress()

func _ensure_camp() -> void:
	if _world == null or not is_instance_valid(_world):
		return
	var saved_cells: Variant = Global.tutorial_flags.get("camp_cells_v3", {})
	if saved_cells is Dictionary:
		for role in (saved_cells as Dictionary):
			var raw: Variant = (saved_cells as Dictionary)[role]
			if raw is Array and (raw as Array).size() >= 2:
				_camp_cells[str(role)] = Vector2i(int(raw[0]), int(raw[1]))
	if not bool(Global.tutorial_flags.get("camp_v3_built", false)):
		var used: Dictionary = {}
		var base := _base_tile()
		for spec_value in CAMP_LAYOUT:
			var spec: Dictionary = spec_value as Dictionary
			var role := str(spec["role"])
			var cell := _find_camp_cell(base + (spec["offset"] as Vector2i), used)
			if cell == Vector2i(-9999, -9999):
				continue
			used[cell] = true
			_camp_cells[role] = cell
			var node := _place_camp_item(role, cell, str(spec["item"]))
			if node != null:
				_camp_nodes[role] = node
		var auto_cell := _find_camp_cell(base + AUTO_OFFSET, used)
		if auto_cell != Vector2i(-9999, -9999):
			used[auto_cell] = true
			_camp_cells["automatica"] = auto_cell
		Global.tutorial_flags["camp_cells_v3"] = _cells_to_flags()
		Global.tutorial_flags["camp_v3_built"] = true
		_save_progress()
	else:
		_ensure_camp_role_nodes()
		for value in get_tree().get_nodes_in_group("TutorialCamp"):
			if is_instance_valid(value):
				var role := str(value.get_meta("tutorial_role", ""))
				if not role.is_empty():
					_camp_nodes[role] = value

func _ensure_camp_role_nodes() -> void:
	if _world == null or not is_instance_valid(_world):
		return
	for spec_value in CAMP_LAYOUT:
		var spec: Dictionary = spec_value as Dictionary
		var role := str(spec["role"])
		if _camp_nodes.has(role) and is_instance_valid(_camp_nodes[role]):
			continue
		var item_path := str(spec["item"])
		var item := load(item_path) as ItemData
		if item == null:
			continue
		var preferred: Vector2i = _camp_cells.get(role, _base_tile() + (spec["offset"] as Vector2i)) as Vector2i
		# A save/load restores the placed camp block but does NOT persist the
		# TutorialCamp group/meta. Re-adopt the real station at the saved cell
		# instead of trying to place a duplicate on top of it (which fails and
		# leaves the Algorithmica lesson saying the furnace is unavailable).
		var existing: Node = null
		if _world.has_method("placed_node"):
			existing = _world.call("placed_node", preferred) as Node
		if existing != null:
			var existing_item: Variant = existing.get("item_data")
			if existing_item is ItemData \
					and (existing_item as ItemData).resource_path == item_path:
				existing.set_meta("tutorial_role", role)
				existing.add_to_group("TutorialCamp")
				_camp_nodes[role] = existing
				continue
		# The saved cell is empty/occupied: find a nearby valid camp cell, update
		# the persisted cell and rebuild the station there.
		var used: Dictionary = {}
		for other_role in _camp_cells:
			if str(other_role) == role:
				continue
			used[_camp_cells[other_role] as Vector2i] = true
		var cell := _find_camp_cell(preferred, used)
		if cell == Vector2i(-9999, -9999):
			continue
		_camp_cells[role] = cell
		var node := _place_camp_item(role, cell, item_path)
		if node != null:
			_camp_nodes[role] = node
			Global.tutorial_flags["camp_cells_v3"] = _cells_to_flags()
			_save_progress()

func _place_camp_item(role: String, cell: Vector2i, item_path: String) -> Node:
	var item := load(item_path) as ItemData
	if item == null or _world == null:
		return null
	var node: Node = _world.call("place_block_at", cell, item, false) as Node
	if node == null:
		return null
	node.set_meta("tutorial_role", role)
	node.add_to_group("TutorialCamp")
	return node

func _find_camp_cell(preferred: Vector2i, used: Dictionary) -> Vector2i:
	var player := Global.player_node as Node2D
	var player_cell := _base_tile()
	if player != null and _world != null:
		player_cell = _world.call("world_to_cell", player.global_position) as Vector2i
	var base := _base_tile()
	for radius in range(0, 8):
		for dx in range(-radius, radius + 1):
			for dy in range(-radius, radius + 1):
				if maxi(absi(dx), absi(dy)) != radius:
					continue
				var cell := preferred + Vector2i(dx, dy)
				if cell == player_cell or used.has(cell) or cell.distance_to(base) < 2:
					continue
				if not bool(_world.call("can_place_at", cell)):
					continue
				return cell
	return Vector2i(-9999, -9999)

func _base_tile() -> Vector2i:
	if _world != null:
		return _world.call("world_to_cell", _spawn) as Vector2i
	return Vector2i.ZERO

func _world_cell(world_pos: Vector2) -> Vector2i:
	return _world.call("world_to_cell", world_pos) as Vector2i

func _cell_world(cell: Vector2i) -> Vector2:
	return _world.call("cell_to_world", cell) as Vector2

func _cells_to_flags() -> Dictionary:
	var out: Dictionary = {}
	for role in _camp_cells:
		var cell: Vector2i = _camp_cells[role] as Vector2i
		out[str(role)] = [cell.x, cell.y]
	return out

func _ensure_automatica() -> void:
	if _automatica_station != null and is_instance_valid(_automatica_station):
		return
	# Prefer the robot at the saved camp cell (or one already tagged as the
	# camp station). After the combat lesson a SECOND LuaNPC exists, and a
	# save/load must not mistake the fighter for the tutorial station.
	var camp_cell: Vector2i = _camp_cells.get("automatica", Vector2i(-9999, -9999)) as Vector2i
	for node in get_tree().get_nodes_in_group("LuaNPC"):
		if not is_instance_valid(node):
			continue
		var at_camp: bool = _station_cell(node) == camp_cell
		var tagged := str(node.get_meta("tutorial_role", "")) == "automatica"
		if at_camp or tagged:
			_automatica_station = node
			node.add_to_group("TutorialCamp")
			node.set_meta("tutorial_role", "automatica")
			return
	for node in get_tree().get_nodes_in_group("LuaNPC"):
		if is_instance_valid(node):
			_automatica_station = node
			node.add_to_group("TutorialCamp")
			node.set_meta("tutorial_role", "automatica")
			return
	if not _camp_cells.has("automatica"):
		return
	var lua_item := load(ITEM_AUTOMATICA) as ItemData
	if lua_item == null:
		return
	if Global.count_item(lua_item) <= 0:
		# The previous station was destroyed or the item was lost. Recovery is
		# safe because there is no live LuaNPC to duplicate.
		Global.grant_item(ITEM_AUTOMATICA, 1)
	if Global.count_item(lua_item) <= 0:
		return
	var node: Node = _world.call("place_block_at", _camp_cells["automatica"] as Vector2i, lua_item, false) as Node
	if node == null:
		return
	Global.remove_item(lua_item)
	node.set_meta("tutorial_role", "automatica")
	node.add_to_group("TutorialCamp")
	_camp_nodes["automatica"] = node
	_automatica_station = node

func _automatica_editor_open() -> bool:
	var editor := _station_editor(_automatica_station)
	return editor != null and editor.visible

func _station_editor(station: Node) -> Control:
	if station == null or not is_instance_valid(station):
		return null
	var ui := station.get_node_or_null("LuaUI")
	if ui == null:
		return null
	return ui.get("_editor") as Control

func _station_cell(station: Node) -> Vector2i:
	if station is Node2D and _world != null and is_instance_valid(_world):
		return _world.call("world_to_cell", (station as Node2D).global_position) as Vector2i
	return Vector2i(-9999, -9999)

# Give the camp Automatica EXACTLY the 32 Wood the first lesson builds with.
# This is tutorial-only state placed directly in BUILD SLOT 1; the player does
# not spend inventory wood for it.
func _give_automatica_line_blocks() -> void:
	_automatica_build_seen = false
	_ensure_automatica()
	if _automatica_station == null or not is_instance_valid(_automatica_station):
		return
	var wood := load(ITEM_WOOD) as ItemData
	if wood == null:
		return
	var palette: Array = _automatica_station.call("get_build_palette") as Array
	var current: int = 0
	if not palette.is_empty() and palette[0] is Dictionary:
		var slot: Dictionary = palette[0] as Dictionary
		if slot.get("data") == wood:
			current = int(slot.get("quantity", 0))
	if current != AUTOMATICA_LINE_BLOCKS:
		_automatica_station.call("set_build_slot", 0, wood, AUTOMATICA_LINE_BLOCKS)

func _automatica_wood_left() -> int:
	if _automatica_station == null or not is_instance_valid(_automatica_station):
		return 0
	var wood := load(ITEM_WOOD) as ItemData
	if wood == null:
		return 0
	var palette: Array = _automatica_station.call("get_build_palette") as Array
	if palette.is_empty() or not (palette[0] is Dictionary):
		return 0
	var slot: Dictionary = palette[0] as Dictionary
	if slot.get("data") != wood:
		return 0
	return int(slot.get("quantity", 0))

func _automatica_busy(station: Node) -> bool:
	if station == null or not is_instance_valid(station):
		return false
	var queue: Variant = station.get("_build_queue")
	return bool(station.get("_build_queue_running")) \
		or bool(station.get("_is_working")) \
		or (queue is Array and not (queue as Array).is_empty())

# One-time combat kit: a SECOND Automatica and a SECOND Wooden Sword. The
# starter kit already includes a sword, so grant the tutorial sword explicitly
# instead of checking whether the player owns one.
func _grant_automatica_combat_kit() -> bool:
	if bool(Global.tutorial_flags.get("automatica_combat_kit", false)):
		return true
	var lua_item := load(ITEM_AUTOMATICA) as ItemData
	var sword := load(ITEM_SWORD) as ItemData
	if lua_item == null or sword == null:
		return false
	if not bool(Global.tutorial_flags.get("automatica_combat_robot_granted", false)):
		if Global.grant_item(ITEM_AUTOMATICA, 1):
			Global.tutorial_flags["automatica_combat_robot_granted"] = true
	if not bool(Global.tutorial_flags.get("automatica_combat_sword_granted", false)):
		if Global.grant_item(ITEM_SWORD, 1):
			Global.tutorial_flags["automatica_combat_sword_granted"] = true
	if not bool(Global.tutorial_flags.get("automatica_combat_robot_granted", false)) \
			or not bool(Global.tutorial_flags.get("automatica_combat_sword_granted", false)):
		return false
	Global.tutorial_flags["automatica_combat_kit"] = true
	_save_progress()
	return true

# Recovery only: the kit sword was dropped/lost before it reached the robot.
func _ensure_combat_sword() -> void:
	var sword := load(ITEM_SWORD) as ItemData
	if sword == null:
		return
	if Global.count_item(sword) <= 0:
		Global.grant_item(ITEM_SWORD, 1)

func _station_has_sword(station: Node) -> bool:
	if station == null or not is_instance_valid(station):
		return false
	var tool: Variant = station.call("get_tool") if station.has_method("get_tool") else {}
	if not (tool is Dictionary) or (tool as Dictionary).is_empty():
		return false
	var data: Variant = (tool as Dictionary).get("data")
	return data is ItemData and (data as ItemData).resource_path == ITEM_SWORD

func _find_second_automatica() -> Node:
	if _automatica_combat_station != null and is_instance_valid(_automatica_combat_station) \
			and not bool(_automatica_combat_station.get("_terminated")):
		return _automatica_combat_station
	var camp_cell: Vector2i = _camp_cells.get("automatica", Vector2i(-9999, -9999)) as Vector2i
	var best: Node = null
	var best_d: float = INF
	var best_combat: Node = null
	var best_combat_d: float = INF
	var player := Global.player_node as Node2D
	var camp_valid: bool = _automatica_station != null \
		and is_instance_valid(_automatica_station)
	for node in get_tree().get_nodes_in_group("LuaNPC"):
		if not is_instance_valid(node):
			continue
		if camp_valid and node == _automatica_station:
			continue
		if bool(node.get("_terminated")):
			continue
		if _station_cell(node) == camp_cell:
			continue
		var d: float = INF
		if player != null and node is Node2D:
			d = player.global_position.distance_to((node as Node2D).global_position)
		# Prefer a normal robot for the lesson. A combat robot only serves as a
		# fallback when loading a save made after combat_mode(true) ran.
		if bool(node.get("_combat")):
			if d < best_combat_d:
				best_combat_d = d
				best_combat = node
		elif d < best_d:
			best_d = d
			best = node
	_automatica_combat_station = best if best != null else best_combat
	return _automatica_combat_station

func _ensure_camp_return() -> bool:
	if bool(Global.tutorial_flags.get("programming_camp_return", false)):
		return true
	var p := Global.player_node as Node2D
	if p == null or _world == null:
		return false
	if p.global_position.distance_to(_spawn) < 360.0:
		Global.tutorial_flags["programming_camp_return"] = true
		_save_progress()
		return true
	if _teleporting():
		_set_objective("Returning to camp...", false)
		return false
	if not _camp_return_tried:
		_camp_return_tried = true
		if _world.has_method("tutorial_return_to_camp") \
				and bool(_world.call("tutorial_return_to_camp", _spawn)):
			_set_objective("Returning to camp...", false)
			return false
		Global.tutorial_flags["programming_camp_return"] = true
		_save_progress()
	_focus_world(_spawn, "Starter camp")
	_set_objective("Walk back to the starter camp.", false)
	return false

# ── Dungeon helpers ─────────────────────────────────────────────────
func _nearest_dungeon_language() -> String:
	var p := Global.player_node as Node2D
	if p == null or _world == null or not _world.has_method("get_dungeon_entrance_target"):
		return ""
	var best := ""
	var best_d := MAX_TARGET_DISTANCE * 4.0
	for lang in ["lua", "python"]:
		var target: Vector2 = _world.call("get_dungeon_entrance_target", str(lang)) as Vector2
		if target == Vector2.INF:
			continue
		var d := p.global_position.distance_to(target)
		if d < best_d:
			best_d = d
			best = str(lang)
	return best

func _begin_dungeon_travel() -> void:
	if _travel_started:
		return
	_travel_started = true
	_travel_lang = _nearest_dungeon_language()
	if _travel_lang.is_empty():
		_set_objective("No dungeon entrance is available. Explore, or skip this lesson.", true)
		return
	if bool(_world.call("tutorial_teleport_near_dungeon", _travel_lang)):
		_set_objective("Next lesson: dungeon. Traveling to the entrance...", false)
	else:
		_set_objective("Could not reach a dungeon entrance safely.", true)

func _on_dungeon_entered(index: int) -> void:
	if _finished or _step_complete:
		return
	var id := _step_id()
	if id != "dungeon_travel" and id != "dungeon_knowledge":
		return
	_dungeon_index = index
	_dungeon_lang = Global.dungeon_language(index)
	Global.tutorial_flags["dungeon_index"] = index
	Global.tutorial_flags["quiz_hint_demo"] = false
	_clear_targets()
	_set_current_step("dungeon_knowledge")
	_save_progress()

func _on_dungeon_exited(index: int) -> void:
	if _finished:
		return
	if Global.is_dungeon_cleared(index):
		_set_current_step("automatica")
	else:
		_set_current_step("dungeon_travel")
	_save_progress()

func _dungeon_cleared() -> bool:
	return _dungeon_index > 0 and Global.is_dungeon_cleared(_dungeon_index)

func _is_first_dungeon() -> bool:
	return _dungeon_index > 0 and Global.is_first_dungeon_hint_free(_dungeon_index)

func _ensure_dungeon_route() -> void:
	if not Global.is_in_dungeon:
		_clear_route()
		return
	if _route_guide == null or not is_instance_valid(_route_guide) \
			or _route_guide.get_parent() != Global.world_node:
		_clear_route()
		_route_guide = ROUTE_SCRIPT.new() as TutorialRouteGuide
		Global.world_node.add_child(_route_guide)
	var altar := _nearest_group_node("QuizAltar") as Node2D
	if altar == null:
		_clear_route()
		return
	var dw := Global.world_node
	var p := Global.player_node as Node2D
	if dw == null or p == null or not dw.has_method("world_to_grid"):
		return
	var cell: Vector2i = dw.call("world_to_grid", p.global_position) as Vector2i
	if cell == _route_last_cell and _route_guide.visible:
		return
	var now := Time.get_ticks_msec()
	if _route_guide.visible and now - _route_last_ms < 1500:
		return
	_route_last_cell = cell
	_route_last_ms = now
	_route_guide.call("set_route", _build_route_points(altar.global_position))

func _build_route_points(goal_world: Vector2) -> Array:
	var dw := Global.world_node
	var p := Global.player_node as Node2D
	if dw == null or p == null or not dw.has_method("world_to_grid") or not dw.has_method("grid_to_world"):
		return [goal_world]
	var start: Vector2i = dw.call("world_to_grid", p.global_position) as Vector2i
	var goal: Vector2i = dw.call("world_to_grid", goal_world) as Vector2i
	var gen = dw.get("generator")
	if gen == null or start.x < 0 or start.y < 0 or goal.x < 0 or goal.y < 0:
		return [goal_world]
	var blocked: Dictionary = {}
	for cell_value in (gen.trap_positions as Array):
		blocked[cell_value as Vector2i] = true
	for cell_value in (gen.quiz_trap_positions as Array):
		blocked[cell_value as Vector2i] = true
	var queue: Array = [start]
	var came: Dictionary = {start: start}
	var dirs: Array = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
	var found := false
	while not queue.is_empty():
		var cur: Vector2i = queue.pop_front() as Vector2i
		if cur == goal:
			found = true
			break
		for d_value in dirs:
			var n := cur + (d_value as Vector2i)
			if came.has(n) or blocked.has(n):
				continue
			if not bool(dw.call("grid_cell_is_floor", n)):
				continue
			came[n] = cur
			queue.append(n)
	if not found:
		return [goal_world]
	var path: Array = []
	var c := goal
	while c != start:
		path.push_front(c)
		c = came[c] as Vector2i
	# Keep turns plus every fourth tile; cap the number of discs so they never
	# obscure the room. Always end at the actual Quiz Altar.
	var out_cells: Array = []
	var prev_dir := Vector2i.ZERO
	for i in range(path.size()):
		var cell: Vector2i = path[i] as Vector2i
		var dir := Vector2i.ZERO
		if i > 0:
			dir = cell - (path[i - 1] as Vector2i)
		var turn := dir != prev_dir
		if turn or i % 4 == 0 or i == path.size() - 1:
			out_cells.append(cell)
		prev_dir = dir
	if out_cells.size() > 16:
		var reduced: Array = []
		var step := maxi(1, int(ceil(float(out_cells.size()) / 16.0)))
		for i in range(0, out_cells.size(), step):
			reduced.append(out_cells[i])
		if reduced.is_empty() or reduced[reduced.size() - 1] != goal:
			reduced.append(goal)
		out_cells = reduced
	var out: Array = []
	for cell_value in out_cells:
		out.append(dw.call("grid_to_world", cell_value as Vector2i) as Vector2)
	if out.is_empty():
		out.append(goal_world)
	return out

func _clear_route() -> void:
	_route_last_cell = Vector2i(-99999, -99999)
	_route_last_ms = -100000
	if _route_guide != null and is_instance_valid(_route_guide):
		_route_guide.queue_free()
	_route_guide = null

func _nearest_group_node(group: String) -> Node2D:
	var p := Global.player_node as Node2D
	if p == null:
		return null
	var best: Node2D = null
	var best_d := INF
	for node in get_tree().get_nodes_in_group(group):
		if not is_instance_valid(node) or not node is Node2D:
			continue
		var n := node as Node2D
		var d := p.global_position.distance_to(n.global_position)
		if d < best_d:
			best_d = d
			best = n
	return best

# ── Cave helpers ────────────────────────────────────────────────────
func _current_cave_kind() -> String:
	var w := Global.world_node
	if w == null:
		return ""
	if w is PixieCaveWorld:
		return "pixie"
	if w is CaveWorld:
		return "cave"
	return ""

func _begin_cave_travel(pixie: bool) -> void:
	var key := "cave_pixie_relocated" if pixie else "cave_regular_relocated"
	if bool(Global.tutorial_flags.get(key, false)):
		return
	# Already inside a cave: the player proceeded naturally, so never yank them
	# out with a recall. Mark it so a later resume does not relocate either.
	if _current_cave_kind() != "":
		Global.tutorial_flags[key] = true
		_save_progress()
		return
	if _teleporting():
		return
	if _world == null or not is_instance_valid(_world) \
			or not _world.has_method("tutorial_teleport_near_cave"):
		return
	if bool(_world.call("tutorial_teleport_near_cave", pixie)):
		Global.tutorial_flags[key] = true
		_save_progress()

func _nearest_cave_portal(pixie: bool) -> Node2D:
	var p := Global.player_node as Node2D
	if p == null:
		return null
	var best: Node2D = null
	var best_d := MAX_TARGET_DISTANCE * 4.0
	var want := "pixie" if pixie else "cave"
	for node in get_tree().get_nodes_in_group("CavePortal"):
		if not is_instance_valid(node) or not node is Node2D:
			continue
		if int(node.get("mode")) != CavePortal.Mode.ENTER:
			continue
		if str(node.get("cave_type")) != want:
			continue
		var n := node as Node2D
		var d := p.global_position.distance_to(n.global_position)
		if d < best_d:
			best_d = d
			best = n
	return best

func _find_cave_exit() -> Node2D:
	for node in get_tree().get_nodes_in_group("CavePortal"):
		if is_instance_valid(node) and node is Node2D \
				and int(node.get("mode")) == CavePortal.Mode.EXIT:
			return node as Node2D
	return null

func _nearest_cave_ore(kind: String) -> Dictionary:
	var w := Global.world_node
	var p := Global.player_node as Node2D
	if w == null or p == null:
		return {}
	var gen = w.get("generator")
	var tm := w.get("_tilemap") as TileMapLayer
	if gen == null or tm == null:
		return {}
	var width := int(gen.get("width")) if kind == "pixie" else int(gen.get("size"))
	var height := int(gen.get("height")) if kind == "pixie" else int(gen.get("size"))
	var half := Vector2i(width / 2, height / 2)
	var choices: Array = []
	if kind == "pixie":
		choices = [
			{"tile": PixieCaveGenerator.Tile.CRYSTAL_COPPER, "item": "res://resources/items/crystal_copper_ore.tres", "label": "crystal copper ore"},
			{"tile": PixieCaveGenerator.Tile.CRYSTAL_IRON, "item": "res://resources/items/crystal_iron_ore.tres", "label": "crystal iron ore"},
			{"tile": PixieCaveGenerator.Tile.CRYSTAL_SILICON, "item": "res://resources/items/crystal_silicon_ore.tres", "label": "crystal silicon ore"},
			{"tile": PixieCaveGenerator.Tile.CRYSTAL_DIAMOND, "item": "res://resources/items/crystal_diamond_ore.tres", "label": "crystal diamond ore"},
		]
	else:
		choices = [
			{"tile": CaveGenerator.Tile.COPPER, "item": "res://resources/items/copper_ore.tres", "label": "copper ore"},
			{"tile": CaveGenerator.Tile.IRON, "item": "res://resources/items/iron_ore.tres", "label": "iron ore"},
			{"tile": CaveGenerator.Tile.SILICON, "item": "res://resources/items/silicon_ore.tres", "label": "silicon ore"},
			{"tile": CaveGenerator.Tile.DIAMOND, "item": "res://resources/items/diamond_ore.tres", "label": "diamond ore"},
		]
	var tile_to_info: Dictionary = {}
	for c_value in choices:
		tile_to_info[int((c_value as Dictionary)["tile"])] = c_value
	var exit_portal := _find_cave_exit()
	var exit_pos: Vector2 = exit_portal.global_position if exit_portal != null else Vector2.INF
	var best: Dictionary = {}
	var best_d := INF
	for x in range(width):
		for y in range(height):
			var info: Variant = tile_to_info.get(int(gen.grid[x][y]))
			if not (info is Dictionary):
				continue
			var cell := Vector2i(x, y) - half
			var pos := tm.to_global(tm.map_to_local(cell))
			# Never teach on an ore overlapping the exit marker: walking onto it
			# could leave the cave before the pickup is registered.
			if exit_pos != Vector2.INF and pos.distance_to(exit_pos) < 120.0:
				continue
			var d := p.global_position.distance_to(pos)
			if d < best_d:
				best_d = d
				best = (info as Dictionary).duplicate()
				best["cell"] = Vector2i(x, y)
				best["pos"] = pos
	return best

# ── Waypoint helpers ────────────────────────────────────────────────
func _nearest_waypoint() -> Node2D:
	var p := Global.player_node as Node2D
	if p == null:
		return null
	var best: Node2D = null
	var best_d := INF
	for node in get_tree().get_nodes_in_group("WorldWaypoint"):
		if not is_instance_valid(node) or not node is Node2D:
			continue
		var n := node as Node2D
		var d := p.global_position.distance_to(n.global_position)
		if d < best_d:
			best_d = d
			best = n
	return best

func _waypoint_node_by_id(id: String) -> Node2D:
	if id.is_empty():
		return null
	for node in get_tree().get_nodes_in_group("WorldWaypoint"):
		if is_instance_valid(node) and node is Node2D and str(node.get("waypoint_id")) == id:
			return node as Node2D
	return null

func _teleporting() -> bool:
	var w := Global.world_node
	return w != null and w.has_method("is_waypoint_teleporting") and bool(w.call("is_waypoint_teleporting"))

# ── Cave/dungeon signals ────────────────────────────────────────────
func _on_cave_entered(kind: String) -> void:
	var id := _step_id()
	if (id == "cave_regular" and kind == "cave") or (id == "cave_pixie" and kind == "pixie"):
		Global.tutorial_flags["cave_%s_entered" % kind] = true
		_clear_targets()
		_save_progress()

func _on_cave_exited(kind: String) -> void:
	var id := _step_id()
	if (id == "cave_regular" and kind == "cave") or (id == "cave_pixie" and kind == "pixie"):
		if not bool(Global.tutorial_flags.get("cave_%s_inspected" % kind, false)):
			# Leaving early must not silently complete the lesson. Keep the step
			# active; _tick_cave points at the nearest valid entrance again.
			Global.notify("Finish the cave lesson before leaving.")
			_save_progress()
			return
		Global.tutorial_flags["cave_%s_done" % kind] = true
		_save_progress()
		_complete_step()

func _recover_stage_after_load() -> void:
	_dungeon_index = int(Global.tutorial_flags.get("dungeon_index", 0))
	var id := _step_id()
	if id.begins_with("dungeon_"):
		if not Global.is_in_dungeon:
			if _dungeon_index > 0 and Global.is_dungeon_cleared(_dungeon_index):
				_current_step = _step_index("automatica")
			else:
				_current_step = _step_index("dungeon_travel")
			Global.tutorial_stage = _current_step
	elif id == "automatica" and bool(Global.tutorial_flags.get("automatica_lesson_done", false)):
		_current_step = _step_index("automatica_combat"
			if not bool(Global.tutorial_flags.get("automatica_combat_done", false))
			else "algorithmica")
		Global.tutorial_stage = _current_step
	elif id == "automatica_combat" and bool(Global.tutorial_flags.get("automatica_combat_done", false)):
		_current_step = _step_index("algorithmica")
		Global.tutorial_stage = _current_step
	elif id == "algorithmica" and bool(Global.tutorial_flags.get("algorithmica_lesson_done", false)):
		_current_step = _step_index("cave_regular")
		Global.tutorial_stage = _current_step
	elif id == "cave_regular" and bool(Global.tutorial_flags.get("cave_cave_done", false)):
		_current_step = _step_index("cave_pixie")
		Global.tutorial_stage = _current_step
	elif id == "cave_pixie" and bool(Global.tutorial_flags.get("cave_pixie_done", false)):
		_current_step = _step_index("waypoint")
		Global.tutorial_stage = _current_step
	elif id == "waypoint" and bool(Global.tutorial_flags.get("waypoint_lesson_done", false)):
		_finish_tutorial(true)

func _set_current_step(id: String) -> void:
	var idx := _step_index(id)
	if idx < 0:
		return
	_current_step = idx
	Global.tutorial_stage = idx
	_step_complete = false
	_step_dialogue_done = false
	_clear_targets()
	_prepare_step()
	call_deferred("_start_step")

# ── Finish ──────────────────────────────────────────────────────────
func _finish_tutorial(silent: bool = false) -> void:
	if _finished:
		return
	_finished = true
	Global.tutorial_completed = true
	Global.tutorial_flags.erase("algorithmica_template_ready")
	_current_step = STEPS.size()
	Global.tutorial_stage = _current_step
	Global.tutorial_version = 3
	_save_progress()
	_clear_targets()
	if _guide_arrow != null and is_instance_valid(_guide_arrow):
		_guide_arrow.queue_free()
		_guide_arrow = null
	if _objective_panel != null:
		_objective_panel.visible = false
	if _dialogue != null and _dialogue.is_active():
		_dialogue.dismiss()
	for npc in _npc_nodes:
		if is_instance_valid(npc):
			npc.queue_free()
	_npc_nodes.clear()
	if not silent:
		Global.notify("[color=#9be89b]Guided start complete.[/color] The world and mission tracker are yours.")
	# First natural finish: tour Settings so the player knows what each control
	# does. Previously completed tutorials (silent) never replay this.
	var show_settings_tour: bool = not silent \
		and not bool(Global.tutorial_flags.get("settings_tour_done", false))
	if show_settings_tour:
		Global.tutorial_flags["settings_tour_done"] = true
		_save_progress()
		var game := Global.game_node
		if game != null and is_instance_valid(game):
			var tour: Node = SETTINGS_TOUR_SCRIPT.new()
			tour.name = "SettingsTour"
			game.add_child(tour)
			tour.call_deferred("start")
	queue_free()

func _exit_tree() -> void:
	_clear_targets()
