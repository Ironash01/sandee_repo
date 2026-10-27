extends Node

# ── Guided onboarding director ──────────────────────────────────────
# This is the persistent tutorial controller. It lives under Game (not the
# overworld) so the dialogue and lesson state survive the overworld→dungeon
# world swap. Py-San/LUA actors live in the overworld; their portraits live in
# the dialogue UI.
#
# Design rules:
#   * short conversations, one mechanic at a time
#   * practical steps are completed by real game state, not by pressing Next
#   * optional camp lessons can be skipped without blocking progression
#   * the starter camp uses the real station/scene/item systems
#   * tutorial rewards and lesson progress are per-world and idempotent

const NPC_SCRIPT: GDScript = preload("res://scripts/tutorial_npc.gd")
const DIALOGUE_SCRIPT: GDScript = preload("res://scripts/tutorial_dialogue.gd")
const MARKER_SCRIPT: GDScript = preload("res://scripts/tutorial_marker.gd")
const ARROW_SCRIPT: GDScript = preload("res://scripts/tutorial_arrow.gd")

const PY_SAN_TEX := "res://sprites/char/pysan.png"
const LUA_TEX := "res://sprites/char/lua/front.png"

const STEPS: Array = [
	"welcome", "movement", "inventory", "mining", "building",
	"automatica", "stations", "missions", "combat",
	"dungeon_travel", "dungeon_encounter", "finish",
]
const STEP_DUNGEON_ENCOUNTER: int = 10

const ITEM_PICKAXE := "res://resources/items/wooden_pickaxe.tres"
const ITEM_SWORD := "res://resources/items/woodensword.tres"
const ITEM_STONE := "res://resources/items/stone.tres"
const ITEM_WOOD := "res://resources/items/wood.tres"
const ITEM_STICK := "res://resources/items/stick.tres"
const ITEM_CHARCOAL := "res://resources/items/charcoal.tres"
const ITEM_COPPER_ORE := "res://resources/items/copper_ore.tres"
const ITEM_CACTUS := "res://resources/items/cactus.tres"
const ITEM_BREAD := "res://resources/items/bread.tres"
const ITEM_CRAFTING := "res://resources/items/crafting_station.tres"
const ITEM_FURNACE := "res://resources/items/furnace.tres"
const ITEM_COLOR := "res://resources/items/color_crafter.tres"
const ITEM_CHEST := "res://resources/items/chest.tres"
const ITEM_AUTOMATICA := "res://resources/items/lua.tres"

const CAMP_LAYOUT: Array = [
	{"role": "crafting", "offset": Vector2i(3, 1), "item": ITEM_CRAFTING},
	{"role": "furnace", "offset": Vector2i(5, 1), "item": ITEM_FURNACE},
	{"role": "color", "offset": Vector2i(3, 3), "item": ITEM_COLOR},
	{"role": "chest", "offset": Vector2i(5, 3), "item": ITEM_CHEST},
]
const PRACTICE_OFFSET := Vector2i(-3, 2)
const BUILD_OFFSET := Vector2i(-5, 0)
const AUTO_OFFSET := Vector2i(-3, -2)
const DUMMY_OFFSET := Vector2i(5, 5)

const TRAINING_SCENES := {
	"lua": "res://scenes/mobs/RuneSentinel.tscn",
	"python": "res://scenes/mobs/BrassProwler.tscn",
}
const TRAINING_DATA := {
	"lua": "res://resources/mobs/rune_sentinel.tres",
	"python": "res://resources/mobs/brass_prowler.tres",
}

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
var _marker: Node2D = null
var _guide_arrow: Node2D = null

var _current_step: int = 0
var _step_dialogue_done: bool = false
var _step_complete: bool = false
var _dialogue_pending: bool = false
var _finished: bool = false

var _movement_origin: Vector2 = Vector2.ZERO
var _camp_cells: Dictionary = {}      # role -> Vector2i
var _camp_nodes: Dictionary = {}      # role -> Node
var _practice_block: Node = null
var _practice_target_created: bool = false
var _automatica_station: Node = null
var _training_dummy: Node = null
var _training_dummy_spawned: bool = false
var _training_dummy_dead: bool = false
var _dungeon_dummy: Node = null
var _dungeon_dummy_spawned: bool = false
var _dungeon_dummy_dead: bool = false

var _step_check_accum: float = 0.0
var _hint_elapsed: float = 0.0
var _hint_shown: bool = false
var _travel_lang: String = ""
var _travel_started: bool = false
var _dungeon_index: int = 0
var _dungeon_lang: String = ""

var _original_pnc: bool = false
var _pnc_changed_for_tutorial: bool = false
var _saved_camp_cells: Dictionary = {}

func setup(spawn_pos: Vector2, world: Node2D) -> void:
	_spawn = spawn_pos
	_world = world
	Global.tutorial_version = 2
	if Global.tutorial_completed:
		queue_free()
		return
	if Global.tutorial_stage >= STEPS.size():
		_finish_tutorial(true)
		return
	_current_step = maxi(0, Global.tutorial_stage)
	# If a world was closed after entering the guided dungeon, do not replay a
	# dungeon visit. Finish the onboarding safely in the overworld instead.
	if _current_step >= STEP_DUNGEON_ENCOUNTER and not Global.is_in_dungeon:
		_current_step = STEPS.size() - 1
		Global.tutorial_stage = _current_step
	_original_pnc = Global.point_and_click
	_build_ui()
	_spawn_npcs()
	_setup_guide_arrow()
	_connect_signals()
	_ensure_camp()
	_grant_kit()
	_ensure_automatica()
	# Keep point-and-click on only for the duration of onboarding. It is not
	# persisted here, so it never silently changes the player's saved settings.
	if not Global.point_and_click:
		Global.set_point_and_click(true, false)
		_pnc_changed_for_tutorial = true
	call_deferred("_start_step")

func _connect_signals() -> void:
	if not Global.inventory_toggled.is_connected(_on_inventory_toggled):
		Global.inventory_toggled.connect(_on_inventory_toggled)
	if not Global.mission_updated.is_connected(_on_mission_updated):
		Global.mission_updated.connect(_on_mission_updated)
	if not Global.modal_hud_changed.is_connected(_on_modal_hud_changed):
		Global.modal_hud_changed.connect(_on_modal_hud_changed)
	if not Global.dungeon_entered.is_connected(_on_dungeon_entered):
		Global.dungeon_entered.connect(_on_dungeon_entered)
	if not Global.ui_scale_changed.is_connected(_on_ui_scale_changed):
		Global.ui_scale_changed.connect(_on_ui_scale_changed)

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
	# Below the 35 pause-menu modal and the 30 altar/portal confirms, but above
	# the normal HUD and notification stack. This prevents the objective card
	# from painting over the pause menu if it is opened mid-lesson.
	_objective_layer.layer = 28
	_objective_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_objective_layer)
	_objective_panel = PanelContainer.new()
	_objective_panel.mouse_filter = Control.MOUSE_FILTER_STOP
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
	vbox.add_theme_constant_override("separation", 3)
	_objective_panel.add_child(vbox)
	var title := Label.new()
	title.text = "GUIDED START"
	title.add_theme_color_override("font_color", Color(0.55, 0.86, 0.98, 1.0))
	vbox.add_child(title)
	_objective_label = Label.new()
	_objective_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_objective_label.add_theme_color_override("font_color", Color(0.9, 0.95, 1.0, 1.0))
	vbox.add_child(_objective_label)
	_objective_hint = Label.new()
	_objective_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_objective_hint.add_theme_color_override("font_color", Color(0.58, 0.70, 0.88, 1.0))
	_objective_hint.visible = false
	vbox.add_child(_objective_hint)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_END
	vbox.add_child(row)
	_objective_skip = Button.new()
	_objective_skip.text = "Skip lesson"
	_objective_skip.visible = false
	_objective_skip.pressed.connect(_skip_current_step)
	row.add_child(_objective_skip)
	_layout_ui()

func _spawn_npcs() -> void:
	if _world == null or not is_instance_valid(_world):
		return
	# Keep the guides at the edge of the camp clearing. They are deliberately
	# outside the station ring so their world labels do not cover Automatica or
	# the crafting/furnace markers.
	_add_npc("Py-San", PY_SAN_TEX, _spawn + Vector2(-180.0, 40.0))
	_add_npc("LUA", LUA_TEX, _spawn + Vector2(180.0, 40.0))

func _setup_guide_arrow() -> void:
	var player := Global.player_node as Node2D
	if player == null or not is_instance_valid(player):
		return
	_guide_arrow = ARROW_SCRIPT.new() as Node2D
	_guide_arrow.name = "TutorialGuideArrow"
	player.add_child(_guide_arrow)

func _add_npc(npc_name: String, texture_path: String, at: Vector2) -> void:
	var npc := NPC_SCRIPT.new() as Node2D
	npc.call("setup", npc_name, texture_path, self)
	npc.global_position = at
	_world.add_child(npc)
	_npc_nodes.append(npc)

# ── Starter camp ─────────────────────────────────────────────────────
func _ensure_camp() -> void:
	if _world == null or not is_instance_valid(_world):
		return
	var saved_cells: Variant = Global.tutorial_flags.get("camp_cells", {})
	if saved_cells is Dictionary:
		for role in (saved_cells as Dictionary):
			var raw: Variant = (saved_cells as Dictionary)[role]
			if raw is Array and (raw as Array).size() >= 2:
				_camp_cells[str(role)] = Vector2i(int(raw[0]), int(raw[1]))
	var built: bool = bool(Global.tutorial_flags.get("camp_built", false))
	if not built:
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
		var practice := _find_camp_cell(base + PRACTICE_OFFSET, used)
		if practice != Vector2i(-9999, -9999):
			used[practice] = true
			_camp_cells["practice"] = practice
			_practice_block = _place_camp_item("practice", practice, ITEM_STONE)
		var build_cell := _find_camp_cell(base + BUILD_OFFSET, used)
		if build_cell != Vector2i(-9999, -9999):
			used[build_cell] = true
			_camp_cells["build"] = build_cell
		var auto_cell := _find_camp_cell(base + AUTO_OFFSET, used)
		if auto_cell != Vector2i(-9999, -9999):
			used[auto_cell] = true
			_camp_cells["automatica"] = auto_cell
		var dummy_cell := _find_camp_cell(base + DUMMY_OFFSET, used)
		if dummy_cell != Vector2i(-9999, -9999):
			used[dummy_cell] = true
			_camp_cells["dummy"] = dummy_cell
		Global.tutorial_flags["camp_cells"] = _cells_to_flags()
		Global.tutorial_flags["camp_built"] = true
		_save_progress()
	else:
		# Re-find live camp nodes after a reload.
		for value in get_tree().get_nodes_in_group("TutorialCamp"):
			if not is_instance_valid(value):
				continue
			var role := str(value.get_meta("tutorial_role", ""))
			if not role.is_empty():
				_camp_nodes[role] = value
				if role == "practice":
					_practice_block = value
		# The cells are authoritative if a node disappeared.
		_ensure_camp_role_nodes()

func _ensure_camp_role_nodes() -> void:
	for spec_value in CAMP_LAYOUT:
		var spec: Dictionary = spec_value as Dictionary
		var role := str(spec["role"])
		if _camp_nodes.has(role) and is_instance_valid(_camp_nodes[role]):
			continue
		if not _camp_cells.has(role):
			continue
		var node := _place_camp_item(role, _camp_cells[role] as Vector2i, str(spec["item"]))
		if node != null:
			_camp_nodes[role] = node
	if _practice_block == null or not is_instance_valid(_practice_block):
		if _camp_cells.has("practice"):
			_practice_block = _place_camp_item("practice", _camp_cells["practice"] as Vector2i, ITEM_STONE)

func _place_camp_item(role: String, cell: Vector2i, item_path: String) -> Node:
	var item := load(item_path) as ItemData
	if item == null or _world == null:
		return null
	var node: Node = _world.call("place_block_at", cell, item, false) as Node
	if node == null:
		return null
	node.set_meta("tutorial_role", role)
	node.add_to_group("TutorialCamp")
	if role == "practice":
		node.add_to_group("TutorialPracticeBlock")
	return node

func _find_camp_cell(preferred: Vector2i, used: Dictionary) -> Vector2i:
	var player := Global.player_node as Node2D
	var player_cell := _world_cell(player.global_position) if player != null else Vector2i(-9999, -9999)
	var base := _base_tile()
	for radius in range(0, 8):
		for dx in range(-radius, radius + 1):
			for dy in range(-radius, radius + 1):
				if maxi(absi(dx), absi(dy)) != radius:
					continue
				var cell := preferred + Vector2i(dx, dy)
				if cell == player_cell or used.has(cell):
					continue
				if cell.distance_to(base) < 2:
					continue
				if not _world.call("can_place_at", cell):
					continue
				return cell
	return Vector2i(-9999, -9999)

func _base_tile() -> Vector2i:
	var ground := _world.get("ground_layer") as TileMapLayer
	if ground != null:
		return ground.local_to_map(ground.to_local(_spawn))
	var p := Global.player_node as Node2D
	return _world_cell(p.global_position) if p != null else Vector2i.ZERO

func _world_cell(world_pos: Vector2) -> Vector2i:
	var ground := _world.get("ground_layer") as TileMapLayer
	if ground != null:
		return ground.local_to_map(ground.to_local(world_pos))
	return Vector2i(floori(world_pos.x / 32.0), floori(world_pos.y / 32.0))

func _cell_world(cell: Vector2i) -> Vector2:
	var ground := _world.get("ground_layer") as TileMapLayer
	if ground != null:
		return ground.to_global(ground.map_to_local(cell))
	return Vector2(cell.x * 32.0, cell.y * 32.0)

func _cells_to_flags() -> Dictionary:
	var out: Dictionary = {}
	for role in _camp_cells:
		var cell: Vector2i = _camp_cells[role] as Vector2i
		out[str(role)] = [cell.x, cell.y]
	return out

func _grant_kit() -> void:
	var kit := [
		{"path": ITEM_PICKAXE, "qty": 1},
		{"path": ITEM_SWORD, "qty": 1},
		{"path": ITEM_STONE, "qty": 8},
		{"path": ITEM_WOOD, "qty": 3},
		{"path": ITEM_STICK, "qty": 2},
		{"path": ITEM_CHARCOAL, "qty": 2},
		{"path": ITEM_COPPER_ORE, "qty": 2},
		{"path": ITEM_CACTUS, "qty": 1},
		{"path": ITEM_BREAD, "qty": 2},
	]
	var first: bool = not bool(Global.tutorial_flags.get("starter_kit", false))
	for entry_value in kit:
		var entry: Dictionary = entry_value as Dictionary
		var data := load(str(entry["path"])) as ItemData
		if data == null:
			continue
		var want: int = int(entry["qty"])
		var have: int = Global.count_item(data)
		# On the first pass grant the full kit. On a resumed/partial tutorial,
		# replace only an actually missing essential stack, never duplicate one.
		if have < want and (first or have == 0):
			Global.grant_item(str(entry["path"]), want - have)
	Global.tutorial_flags["starter_kit"] = true

func _ensure_automatica() -> void:
	if _automatica_station != null and is_instance_valid(_automatica_station):
		Global.tutorial_flags["automatica_awarded"] = true
		return
	for node in get_tree().get_nodes_in_group("LuaNPC"):
		if is_instance_valid(node):
			_automatica_station = node
			Global.tutorial_flags["automatica_awarded"] = true
			return
	if not _camp_cells.has("automatica"):
		return
	var lua_item := load(ITEM_AUTOMATICA) as ItemData
	if lua_item == null:
		return
	var have_item: bool = Global.count_item(lua_item) > 0
	var awarded: bool = bool(Global.tutorial_flags.get("automatica_awarded", false))
	if not have_item and not awarded:
		# Use the real acquisition path once, then consume the item into the
		# actual LuaNPC station scene. This keeps the companion a normal game
		# object and avoids an inventory copy plus a station copy.
		Global.grant_item(ITEM_AUTOMATICA, 1)
		have_item = Global.count_item(lua_item) > 0
	if not have_item:
		return
	var node: Node = _world.call("place_block_at", _camp_cells["automatica"] as Vector2i, lua_item, false) as Node
	if node == null:
		return
	Global.remove_item(lua_item)
	node.set_meta("tutorial_role", "automatica")
	node.add_to_group("TutorialCamp")
	_automatica_station = node
	Global.tutorial_flags["automatica_awarded"] = true
	Global.notify("[color=#b9a4ff]Automatica[/color] joined your camp.")

# ── Step engine ──────────────────────────────────────────────────────
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
	_hint_elapsed = 0.0
	_hint_shown = false
	_clear_marker()
	_prepare_step()
	_show_step_dialogue()

func _show_step_dialogue() -> void:
	if _finished or _dialogue == null:
		return
	if _dialogue.is_active():
		_dialogue_pending = true
		return
	if Global.any_ui_open() or Global.pause_menu_open:
		_dialogue_pending = true
		return
	_dialogue_pending = false
	var lines := _step_lines()
	if lines.is_empty():
		_on_step_dialogue_done()
		return
	_set_objective_visible(false)
	var opened: bool = _dialogue.show_conversation(lines, Callable(self, "_on_step_dialogue_done"))
	if not opened:
		_dialogue_pending = true

func _step_id() -> String:
	return str(STEPS[clampi(_current_step, 0, STEPS.size() - 1)])

func _step_index(id: String) -> int:
	for i in range(STEPS.size()):
		if str(STEPS[i]) == id:
			return i
	return -1

func _prepare_step() -> void:
	var id := _step_id()
	if id == "movement":
		var p := Global.player_node as Node2D
		_movement_origin = p.global_position if p != null else _spawn
	elif id == "mining":
		_ensure_camp()
		if _practice_block == null or not is_instance_valid(_practice_block):
			_practice_block = _camp_nodes.get("practice") as Node
		if _practice_block != null:
			_practice_target_created = true
			_set_marker(_marker_world_from_node(_practice_block), "Practice stone")
	elif id == "building":
		_ensure_camp()
		if _camp_cells.has("build"):
			_set_marker(_cell_world(_camp_cells["build"] as Vector2i), "Build here")
	elif id == "automatica":
		_ensure_camp()
		_ensure_automatica()
		if _automatica_station != null and is_instance_valid(_automatica_station):
			_set_marker(_marker_world_from_node(_automatica_station), "Automatica")
		elif _camp_cells.has("automatica"):
			_set_marker(_cell_world(_camp_cells["automatica"] as Vector2i), "Deploy Automatica")
	elif id == "stations":
		if _camp_nodes.has("crafting") and is_instance_valid(_camp_nodes["crafting"]):
			_set_marker(_marker_world_from_node(_camp_nodes["crafting"]), "Try a station")
	elif id == "combat":
		_ensure_camp()
		_ensure_training_dummy()
		if _training_dummy != null and is_instance_valid(_training_dummy):
			_set_marker(_marker_world_from_node(_training_dummy), "Training ooze")
	elif id == "dungeon_travel":
		_travel_lang = _nearest_dungeon_language()
	elif id == "dungeon_encounter":
		pass

func _activate_step() -> void:
	if _step_complete or _finished:
		return
	var id := _step_id()
	match id:
		"welcome":
			# The intro is dialogue-complete only; the Next lesson starts after
			# the player has actually read/advanced the last line.
			if _step_dialogue_done:
				_complete_step()
			else:
				_set_objective("Talk to Py-San or LUA to begin the tour.", false)
		"movement":
			if Global.is_mobile():
				_set_objective("Move a few steps with the left joystick.", false,
					"Tap the ground to use tap-to-control; the joystick cancels it. SPRINT runs.")
			else:
				_set_objective("Move a few steps with WASD or the arrow keys.", false,
					"Click the ground to point-and-click; manual keys cancel it. Shift sprints.")
		"inventory":
			if Global.is_mobile():
				_set_objective("Tap INV on the hotbar to open your inventory.", false,
					"Your tools are in the hotbar; materials and the rest are in the inventory.")
			else:
				_set_objective("Open your inventory with E.", false,
					"Your tools are in the hotbar; materials and the rest are in the inventory.")
		"mining":
			if Global.is_mobile():
				_set_objective("Tap the marked practice stone and mine it.", false,
					"Hold the wooden pickaxe. A different tap cancels the order.")
			else:
				_set_objective("Click the marked practice stone and mine it.", false,
					"Hold the wooden pickaxe. A different click cancels the order.")
		"building":
			if Global.is_mobile():
				_set_objective("Select Stone, tap BUILD, and tap the marked plot.", false,
					"The marker is a real empty tile; placing anywhere valid also works after the lesson.")
			else:
				_set_objective("Select Stone, press Ctrl, and click the marked plot.", false,
					"The marker is a real empty tile; placing anywhere valid also works after the lesson.")
		"automatica":
			_ensure_automatica()
			if _automatica_station != null and is_instance_valid(_automatica_station):
				_set_objective("Walk up to Automatica and %s her console; run the Hello example." % _click_verb_lower(), false,
					"Automatica is the LUA robot. The editor's first example is safe to run.")
				_set_marker(_marker_world_from_node(_automatica_station), "Automatica")
			else:
				_set_objective("Select Automatica in your hotbar and place it on the marked plot.", false,
					"Automatica is a placeable companion. %s toggles building." % ("Tap BUILD" if Global.is_mobile() else "Press Ctrl"))
				if _camp_cells.has("automatica"):
					_set_marker(_cell_world(_camp_cells["automatica"] as Vector2i), "Deploy Automatica")
		"stations":
			_set_objective("Optional: open the crafting station, furnace, color crafter, or Algorithmica panel.", true,
				"These are the real interfaces. Skip this lesson whenever you are ready.")
		"missions":
			if _step_dialogue_done:
				_complete_step()
			else:
				_set_objective("Read the mission tracker on the right.", false)
		"combat":
			_ensure_training_dummy()
			if Global.is_mobile():
				_set_objective("Select your wooden sword and tap the harmless training ooze.", false,
					"Tap the ooze to approach and attack. Its contact damage is disabled for this lesson.")
			else:
				_set_objective("Select your wooden sword and click the harmless training ooze.", false,
					"Click the ooze to approach and attack. Its contact damage is disabled for this lesson.")
		"dungeon_travel":
			_set_objective("Wait while I take you to the nearest dungeon entrance.", false)
			_begin_dungeon_travel()
		"dungeon_encounter":
			_set_objective("Defeat the dungeon training enemy, then continue exploring.", false,
				"Read the dungeon's objective; the quiz altar is your progression goal.")
			_spawn_dungeon_training_enemy()
		"finish":
			if _step_dialogue_done:
				_finish_tutorial()
			else:
				_set_objective("Speak to Py-San or LUA to wrap up.", false)
	_show_objective_after_dialogue()
	if id == "stations" or id == "mining" or id == "automatica":
		_update_skip_visibility()

func _show_objective_after_dialogue() -> void:
	if _step_dialogue_done or _dialogue == null or not _dialogue.is_active():
		_set_objective_visible(true)

func _on_step_dialogue_done() -> void:
	_step_dialogue_done = true
	_dialogue_pending = false
	_hint_elapsed = 0.0
	_activate_step()

func _on_dialogue_dismissed() -> void:
	_dialogue_pending = false
	if _step_complete or _finished:
		return
	# Rebuild the current objective/reminder. For a dialogue-only step this
	# tells the player to click a guide NPC to continue rather than silently
	# marking the step complete.
	_set_objective_visible(true)
	_activate_step()

func _on_dialogue_skip_requested() -> void:
	# Advance the lesson BEFORE dismissing the dialogue. The dismissed signal
	# normally calls _activate_step(), which can start a teleport or spawn a
	# training target. Dismissing first would let those side effects run even
	# though the player skipped the lesson. Once _skip_current_step() sets
	# _step_complete (or _finished), the dismissed handler safely ignores the
	# close and the deferred _start_step() owns the next lesson.
	var dialogue_was_active: bool = _dialogue != null and _dialogue.is_active()
	if not _finished and not _step_complete:
		_skip_current_step()
	if dialogue_was_active and _dialogue != null and _dialogue.is_active():
		_dialogue.dismiss()

func request_dialogue() -> void:
	if _finished or _dialogue == null or _dialogue.is_active():
		return
	_show_step_dialogue()

func _step_lines() -> Array:
	var id := _step_id()
	if id == "welcome":
		return [
			_line("Py-San", "Welcome to SandEE. This is a world of gathering, building, crafting, and programming your own helpers."),
			_line("LUA", "I'm LUA, the Automatica unit assigned to this camp. Py-San handles the wilderness; I handle machines and code."),
			_line("Py-San", "I've set up a small camp and put a starter kit in your hotbar. Let's learn by doing."),
		]
	if id == "movement":
		return [
			_line("Py-San", _move_hint()),
			_line("LUA", "%s is enabled for this tour. %s sets a destination; %s always cancels an automatic order, so you stay in control." % [_pnc_name(), _click_verb(), "the joystick" if Global.is_mobile() else "manual movement"]),
		]
	if id == "inventory":
		return [
			_line("LUA", "Your hotbar holds the active tools. The inventory holds everything else. Open it with %s." % _inventory_control()),
			_line("Py-San", "Rearrange stacks by dragging them. Close the inventory when you are ready to continue."),
		]
	if id == "mining":
		return [
			_line("Py-San", "See the marked practice stone? %s it. %s will walk there and mine it for you." % [_click_verb(), _pnc_name()]),
			_line("LUA", "Select the wooden pickaxe first. A different %s cancels the order, and the block must be within reach of the normal mining rules." % _click_verb_lower()),
		]
	if id == "building":
		return [
			_line("LUA", "Blocks are how you reshape the world. Select Stone in your hotbar, then %s." % ("tap BUILD" if Global.is_mobile() else "press Ctrl")),
			_line("Py-San", "%s the marked plot. You can break it again later with a pickaxe; nothing here is permanent unless you want it." % _click_verb()),
		]
	if id == "automatica":
		if _automatica_station != null and is_instance_valid(_automatica_station):
			return [
				_line("LUA", "I'm already at camp. Walk up and %s my station to open the Automatica console." % _click_verb_lower()),
				_line("Py-San", "Load the Hello example and press RUN. That is a real program running on the companion, not a tutorial mock-up."),
				_line("LUA", "You can write movement, mining, building, crafting, station actions, and even combat logic with the functions in the Encyclopedia."),
			]
		return [
			_line("LUA", "I'm in your hotbar as Automatica. Select me, %s, and place me on the marked camp plot." % ("tap BUILD" if Global.is_mobile() else "press Ctrl")),
			_line("Py-San", "Once she is placed, %s her station and run the Hello example. The interface is the real Automatica editor." % _click_verb_lower()),
		]
	if id == "stations":
		return [
			_line("Py-San", "Your camp has a crafting station, furnace, color crafter, and chest. Each opens a real game interface, not a tutorial menu."),
			_line("LUA", "For a concrete example: the crafting station turns 2 Sticks + 1 Charcoal into 4 Torches. The furnace smelts Copper Ore with Charcoal fuel. The color crafter uses a Cactus plus RGB/HEX input."),
			_line("LUA", "The furnace also has an Algorithmica panel for Python automation. A valid starter there is print('Algorithmica ready'). Automatica handles Lua; Algorithmica handles station logic."),
		]
	if id == "missions":
		return [
			_line("Py-San", "The mission tracker on the right is your progression guide. Small objectives teach the loop; dungeon missions advance the story."),
			_line("LUA", "Mission progress and dungeon stars are authoritative. You can ignore optional camp lessons and still progress normally."),
		]
	if id == "combat":
		return [
			_line("Py-San", "Hostile creatures have health bars and hit on contact. Keep your distance, watch your health, and swing a sword. Bread heals you if you get hurt."),
			_line("LUA", "I placed a harmless training ooze at camp. Select the wooden sword and %s it. Its attacks are disabled for this lesson." % _click_verb_lower()),
		]
	if id == "dungeon_travel":
		if _travel_lang.is_empty():
			return [
				_line("Py-San", "I can't find a live dungeon entrance right now. You can explore and enter one when it appears."),
				_line("LUA", "Dungeons are the progression spine; the tracker will point to the current Lua and Python tracks."),
			]
		return [
			_line("Py-San", "Dungeons are the progression spine: rooms, enemies, traps, knowledge altars, and a quiz altar that completes the mission."),
			_line("LUA", "I'm taking you to the nearest current %s entrance. %s the real portal after we arrive; read its prompt before entering." % [_travel_lang.capitalize(), _click_verb()]),
		]
	if id == "dungeon_encounter":
		var theme := "Lua" if _dungeon_lang == "lua" else "Python"
		var mission_name := ""
		var mission := Global.get_dungeon_mission_for_index(_dungeon_index)
		if mission != null:
			mission_name = mission.mission_name
		return [
			_line("Py-San", "This is the %s dungeon theme. Read the mission objective and use the real rooms and altars—we are not changing the dungeon rules." % theme),
			_line("LUA", "I placed a harmless training enemy beyond the entrance. Defeat it to see dungeon combat, then explore or complete the quiz when you are ready."),
			_line("Py-San", "Current objective: %s." % (mission_name if not mission_name.is_empty() else "explore the dungeon and find the quiz altar.")),
		]
	if id == "finish":
		return [
			_line("Py-San", "That is the loop: gather, build, craft, program, and clear dungeons. The mission tracker will guide you from here."),
			_line("LUA", "I'll remain at camp. %s my station whenever you want to write automation; Algorithmica lives in the furnace. Your world is yours." % _click_verb()),
		]
	return []

func _line(speaker: String, text: String) -> Dictionary:
	return {
		"speaker": speaker,
		"portrait": PY_SAN_TEX if speaker == "Py-San" else LUA_TEX,
		"text": text,
	}

func _move_hint() -> String:
	if Global.is_mobile():
		return "Move with the left joystick. Hold SPRINT to run."
	return "Move with WASD or the arrow keys. Hold Shift to sprint."

func _click_verb() -> String:
	return "Tap" if Global.is_mobile() else "Click"

func _click_verb_lower() -> String:
	return "tap" if Global.is_mobile() else "click"

func _pnc_name() -> String:
	return "Tap-to-control" if Global.is_mobile() else "Point-and-click"

func _inventory_control() -> String:
	return "the INV button on the hotbar" if Global.is_mobile() else "E"

func _build_control() -> String:
	return "the BUILD button" if Global.is_mobile() else "Ctrl"

# ── Step completion / checks ─────────────────────────────────────────
func _process(delta: float) -> void:
	if _finished:
		return
	if _dialogue_pending and not Global.any_ui_open() and not Global.pause_menu_open \
			and _dialogue != null and not _dialogue.is_active():
		_show_step_dialogue()
		return
	if not _step_dialogue_done or _step_complete:
		return
	if _dialogue != null and _dialogue.is_active():
		return
	_hint_elapsed += delta
	if not _hint_shown and _hint_elapsed > 16.0:
		_hint_shown = true
		_show_hint_for_step()
		_update_skip_visibility()
	if _hint_elapsed > 30.0:
		_update_skip_visibility(true)
	_step_check_accum += delta
	if _step_check_accum < 0.25:
		return
	_step_check_accum = 0.0
	_check_step_state()

func _check_step_state() -> void:
	var id := _step_id()
	match id:
		"movement":
			var p := Global.player_node as Node2D
			if p != null and p.global_position.distance_to(_movement_origin) > 72.0:
				_complete_step()
		"inventory":
			pass # completed by Global.inventory_toggled
		"mining":
			if _practice_block == null:
				if _practice_target_created:
					_complete_step()
				else:
					_update_skip_visibility(true)
			elif not is_instance_valid(_practice_block):
				_complete_step()
		"building":
			if not _camp_cells.has("build"):
				_update_skip_visibility(true)
			elif _world != null and _world.has_method("has_placed_block") \
					and bool(_world.call("has_placed_block", _camp_cells["build"] as Vector2i)):
				_complete_step()
		"automatica":
			var mission := Global._find_mission("run_program")
			if not mission.is_empty() and bool(mission.get("completed", false)):
				_complete_step()
			elif _automatica_station == null:
				# If the companion was lost, permit a safe skip rather than
				# trapping the player in a lesson they cannot complete.
				_update_skip_visibility(true)
		"combat":
			if _training_dummy_dead or (_training_dummy != null and not is_instance_valid(_training_dummy)):
				_complete_step()
			elif _training_dummy == null:
				if _training_dummy_spawned:
					_complete_step()
				else:
					_update_skip_visibility(true)
		"dungeon_travel":
			if Global.is_in_dungeon:
				var di := 0
				var dw := Global.world_node
				if dw != null:
					di = int(dw.get("_dungeon_index"))
				_on_dungeon_entered(di)
			elif _travel_started and _nearest_dungeon_language().is_empty():
				_update_skip_visibility(true)
		"dungeon_encounter":
			if _dungeon_dummy_dead or (_dungeon_dummy != null and not is_instance_valid(_dungeon_dummy)):
				_complete_step()
			elif _dungeon_dummy == null:
				if _dungeon_dummy_spawned:
					_complete_step()
				else:
					_update_skip_visibility(true)
			if not Global.is_in_dungeon:
				_finish_tutorial()

func _complete_step() -> void:
	if _step_complete or _finished:
		return
	_step_complete = true
	_clear_marker()
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
	Global.notify("Skipped onboarding lesson.")
	var id := _step_id()
	if id == "dungeon_travel" or id == "dungeon_encounter":
		# Skipping the dungeon should not leave the director on an overworld
		# "encounter" step or strand the player in a half-started visit. Go
		# straight to the wrap-up and finish onboarding normally.
		_step_complete = true
		_clear_marker()
		_current_step = STEPS.size() - 1
		Global.tutorial_stage = _current_step
		_save_progress()
		call_deferred("_start_step")
		return
	_complete_step()

func _update_skip_visibility(force: bool = false) -> void:
	if _objective_skip == null:
		return
	var optional := _step_id() == "stations"
	var want: bool = optional or force or _hint_elapsed > 30.0
	if _objective_skip.visible != want:
		_objective_skip.visible = want
		_layout_ui()

func _show_hint_for_step() -> void:
	if _objective_hint == null:
		return
	var hint := ""
	match _step_id():
		"movement":
			hint = "Tip: tap the ground to move, or use the joystick; one short walk is enough." if Global.is_mobile() else "Tip: click the ground to move, or use the keys; one short walk is enough."
		"inventory":
			hint = "Tip: the INV button sits on the mobile hotbar." if Global.is_mobile() else "Tip: E is the inventory key."
		"mining":
			hint = "Tip: select the wooden pickaxe in the hotbar and tap the marked block." if Global.is_mobile() else "Tip: select the wooden pickaxe in the hotbar and click the marked block."
		"building":
			hint = "Tip: tap BUILD to toggle build mode. Stone is in your kit." if Global.is_mobile() else "Tip: Ctrl toggles build mode. Stone is in your kit."
		"automatica":
			if _automatica_station != null:
				hint = "Tip: walk up, then alternate between the LUA station, the Hello example, and RUN."
			else:
				if Global.is_mobile():
					hint = "Tip: select Automatica, tap BUILD, and tap the marked plot."
				else:
					hint = "Tip: select Automatica, press Ctrl, and click the marked plot."
		"stations":
			hint = "Optional lesson: open any camp station, or press Skip lesson."
		"combat":
			hint = "Tip: selecting the sword lets tap-to-control attack; manual taps/swings work too." if Global.is_mobile() else "Tip: selecting the sword lets point-and-click attack; manual clicks/swings work too."
		"dungeon_travel":
			hint = "Tip: after the recall, tap the large language portal and confirm." if Global.is_mobile() else "Tip: after the recall, click the large language portal and confirm."
		"dungeon_encounter":
			hint = "Tip: the training enemy is harmless; use your sword. The real dungeon objectives remain unchanged."
		_:
			hint = ""
	if not hint.is_empty():
		_objective_hint.text = hint
		_objective_hint.visible = true
		_layout_ui()

# ── Objective HUD ────────────────────────────────────────────────────
func _set_objective(text: String, optional: bool = false, hint: String = "") -> void:
	if _objective_label == null:
		return
	_objective_label.text = text
	_objective_hint.text = hint
	_objective_hint.visible = not hint.is_empty()
	_objective_panel.visible = true
	_objective_skip.visible = optional
	_update_skip_visibility()
	_layout_ui()

func _set_objective_visible(on: bool) -> void:
	if _objective_panel != null:
		_objective_panel.visible = on
		if on:
			_layout_ui()

func _layout_ui() -> void:
	if _objective_panel == null or not is_inside_tree():
		return
	var s := Global.ui_scale
	var content := Global.ui_content_rect()
	var width := minf(content.size.x - 24.0 * s, 480.0 * s)
	width = maxf(260.0, width)
	_objective_panel.position = Vector2(
		content.position.x + (content.size.x - width) * 0.5,
		content.position.y + 132.0 * s)
	# A bare PanelContainer under a CanvasLayer can be stretched by its child
	# labels while their autowrap width is still zero (which makes the minimum
	# height look enormous for one frame). Give the labels their real inner
	# width first, then reset to the content minimum for a compact card.
	var inner_w: float = maxf(140.0, width - 32.0 * s)
	_objective_label.custom_minimum_size.x = inner_w
	_objective_hint.custom_minimum_size.x = inner_w
	_objective_panel.size = Vector2(width, 0.0)
	_objective_panel.reset_size()
	var card_h: float = maxf(54.0 * s, _objective_panel.get_combined_minimum_size().y)
	_objective_panel.size = Vector2(width, card_h)
	_objective_label.add_theme_font_size_override("font_size", Global.ui_font_size(11))
	_objective_hint.add_theme_font_size_override("font_size", Global.ui_font_size(9))
	_objective_skip.add_theme_font_size_override("font_size", Global.ui_font_size(9))
	var title := _objective_panel.get_child(0).get_child(0) as Label
	if title != null:
		title.add_theme_font_size_override("font_size", Global.ui_font_size(9))

func _on_ui_scale_changed(_s: float) -> void:
	_layout_ui()

# ── Signals ──────────────────────────────────────────────────────────
func _on_inventory_toggled(open: bool) -> void:
	if _objective_panel != null and not _finished:
		_objective_panel.visible = not open
	if not open or _step_complete or _finished:
		return
	if _step_id() == "inventory":
		_complete_step()
	elif _step_id() == "stations":
		# Chest interaction uses the inventory surface; treat it as a valid
		# optional station demonstration when the player is at the chest.
		if _camp_cells.has("chest"):
			var p := Global.player_node as Node2D
			if p != null and p.global_position.distance_to(
					_cell_world(_camp_cells["chest"] as Vector2i)) < 90.0:
				_complete_step()
				return
		_update_skip_visibility()

func _on_modal_hud_changed(open: bool) -> void:
	if _objective_panel != null and not _finished:
		_objective_panel.visible = not open and not (_dialogue != null and _dialogue.is_active())
	if not open or _step_complete or _finished:
		return
	if _dialogue != null and _dialogue.is_active():
		return
	if _step_id() == "stations":
		_complete_step()

func _on_mission_updated() -> void:
	if _step_complete or _finished:
		return
	if _step_id() == "automatica":
		var mission := Global._find_mission("run_program")
		if not mission.is_empty() and bool(mission.get("completed", false)):
			_complete_step()

func _on_dungeon_entered(index: int) -> void:
	if _finished or _dungeon_dummy_dead:
		return
	if _step_id() != "dungeon_travel":
		return
	_dungeon_index = index
	_dungeon_lang = Global.dungeon_language(index)
	_current_step = STEP_DUNGEON_ENCOUNTER
	Global.tutorial_stage = _current_step
	_dungeon_dummy_dead = false
	_dungeon_dummy = null
	_clear_marker()
	_save_progress()
	# Let the scene transition finish before presenting the room lesson.
	await get_tree().create_timer(0.55).timeout
	if _finished:
		return
	_start_step()

# ── Dungeon / training helpers ───────────────────────────────────────
func _nearest_dungeon_language() -> String:
	if _world == null or not _world.has_method("get_dungeon_entrance_target"):
		return ""
	var p := Global.player_node as Node2D
	if p == null:
		return ""
	var best := ""
	var best_dist := INF
	for lang in ["lua", "python"]:
		var target: Vector2 = _world.call("get_dungeon_entrance_target", str(lang)) as Vector2
		if target == Vector2.INF:
			continue
		var dist: float = p.global_position.distance_to(target)
		if dist < best_dist:
			best_dist = dist
			best = str(lang)
	return best

func _begin_dungeon_travel() -> void:
	if _travel_started:
		return
	_travel_started = true
	_travel_lang = _nearest_dungeon_language()
	if _travel_lang.is_empty():
		_set_objective("No live dungeon entrance was found. Explore and enter one when it appears.", true,
			"You can skip this lesson; your mission tracker remains available.")
		_update_skip_visibility(true)
		return
	_set_objective("Traveling to the nearest %s dungeon entrance..." % _travel_lang.capitalize(), false)
	var started := bool(_world.call("tutorial_teleport_near_dungeon", _travel_lang))
	if not started:
		# Try the other track once before falling back.
		var other := "python" if _travel_lang == "lua" else "lua"
		if bool(_world.call("tutorial_teleport_near_dungeon", other)):
			_travel_lang = other
			started = true
	if not started:
		_set_objective("I couldn't reach a dungeon entrance safely. Explore, or skip this lesson.", true,
			"The normal dungeon entrances still work; no shortcut dungeon was created.")
		_update_skip_visibility(true)
		return
	await get_tree().create_timer(2.0).timeout
	if _finished or _step_id() != "dungeon_travel":
		return
	var target: Vector2 = _world.call("get_dungeon_entrance_target", _travel_lang) as Vector2
	if target != Vector2.INF:
		_set_marker(target, "Dungeon entrance")
	_set_objective("%s the %s dungeon portal and enter it." % [_click_verb(), _travel_lang.capitalize()], false,
		"Read the portal prompt; the real dungeon and its normal rules will load.")

func _ensure_training_dummy() -> void:
	if _training_dummy != null and is_instance_valid(_training_dummy):
		return
	if not _camp_cells.has("dummy"):
		return
	var pos := _cell_world(_camp_cells["dummy"] as Vector2i)
	_training_dummy_spawned = true
	_training_dummy = _spawn_training_mob(
		"res://scenes/mobs/CinderOoze.tscn",
		"res://resources/mobs/cinder_ooze.tres",
		pos, "Training Ooze")
	if _training_dummy != null and _training_dummy.has_signal("died"):
		_training_dummy.died.connect(_on_training_dummy_died)

func _spawn_dungeon_training_enemy() -> void:
	if _dungeon_dummy != null and is_instance_valid(_dungeon_dummy):
		_set_marker(_marker_world_from_node(_dungeon_dummy), "Training enemy")
		return
	var dw := Global.world_node
	if dw == null or not dw.has_method("world_to_grid") or not dw.has_method("grid_cell_is_floor"):
		return
	var p := Global.player_node as Node2D
	if p == null:
		return
	var pc: Vector2i = dw.call("world_to_grid", p.global_position) as Vector2i
	var chosen := Vector2i(-9999, -9999)
	for radius in range(2, 8):
		for dx in range(-radius, radius + 1):
			for dy in range(-radius, radius + 1):
				if maxi(absi(dx), absi(dy)) != radius:
					continue
				var cell := pc + Vector2i(dx, dy)
				if cell == pc:
					continue
				if not bool(dw.call("grid_cell_is_floor", cell)):
					continue
				var pos: Vector2 = dw.call("grid_to_world", cell) as Vector2
				if Global.is_point_in_safe_zone(pos):
					continue
				chosen = cell
				break
			if chosen.x != -9999:
				break
		if chosen.x != -9999:
			break
	if chosen.x == -9999:
		_set_objective("The training enemy could not be placed safely. You can still explore the dungeon.", true,
			"Skip this optional encounter; the real dungeon and quiz altar are unchanged.")
		_update_skip_visibility(true)
		return
	var scene_path := str(TRAINING_SCENES.get(_dungeon_lang, "res://scenes/mobs/CinderOoze.tscn"))
	var data_path := str(TRAINING_DATA.get(_dungeon_lang, "res://resources/mobs/cinder_ooze.tres"))
	var pos: Vector2 = dw.call("grid_to_world", chosen) as Vector2
	_dungeon_dummy_spawned = true
	_dungeon_dummy = _spawn_training_mob(scene_path, data_path, pos, "Training Enemy")
	if _dungeon_dummy != null:
		if _dungeon_dummy.has_signal("died"):
			_dungeon_dummy.died.connect(_on_dungeon_dummy_died)
		_set_marker(_marker_world_from_node(_dungeon_dummy), "Training enemy")
		_set_objective("Defeat the training enemy. Real dungeon objectives remain unchanged.", false,
			"It is harmless. Use your sword; then explore or complete the quiz altar at your own pace.")

func _spawn_training_mob(scene_path: String, data_path: String, pos: Vector2, display_name: String) -> Node:
	var scene := load(scene_path) as PackedScene
	var base := load(data_path) as MobCombatData
	if scene == null or base == null:
		return null
	var data := base.duplicate(true) as MobCombatData
	if data == null:
		return null
	data.mob_name = display_name
	data.health = 40.0
	data.damage = 0.0
	data.speed = 20.0
	data.spawn_during_day = false
	data.spawn_during_night = true
	data.behavior = MobCombatData.Behavior.PASSIVE
	data.bestiary_id = ""
	data.drops = []
	data.flee_duration = 0.0
	data.flee_speed_mult = 0.0
	var mob := scene.instantiate() as Node2D
	if mob == null:
		return null
	mob.set("COMBAT_DATA", data)
	mob.set_meta("tutorial_training", true)
	mob.add_to_group("TutorialTraining")
	Global.world_node.add_child(mob)
	mob.global_position = pos
	return mob

func _on_training_dummy_died() -> void:
	_training_dummy_dead = true
	if _step_id() == "combat":
		_complete_step()

func _on_dungeon_dummy_died() -> void:
	_dungeon_dummy_dead = true
	if _step_id() == "dungeon_encounter":
		_complete_step()

# ── Markers / progress / finish ──────────────────────────────────────
func _marker_world_from_node(node: Node) -> Vector2:
	if node is Node2D:
		return (node as Node2D).global_position
	return _spawn

func _set_marker(world_pos: Vector2, label: String = "") -> void:
	_clear_marker()
	if _guide_arrow != null and is_instance_valid(_guide_arrow):
		_guide_arrow.call("set_target", world_pos, label)
	var host := Global.world_node
	if host == null or not is_instance_valid(host):
		return
	var marker := MARKER_SCRIPT.new() as Node2D
	marker.set("label_text", label)
	host.add_child(marker)
	marker.global_position = world_pos
	_marker = marker

func _clear_marker() -> void:
	if _marker != null and is_instance_valid(_marker):
		_marker.queue_free()
	_marker = null
	if _guide_arrow != null and is_instance_valid(_guide_arrow):
		_guide_arrow.call("clear_target")

func _save_progress() -> void:
	Global.tutorial_stage = _current_step
	if Global.active_save_slot > 0 and Global.game_node != null:
		Global.save_game(Global.active_save_slot)

func _exit_tree() -> void:
	if _pnc_changed_for_tutorial:
		_pnc_changed_for_tutorial = false
		Global.set_point_and_click(_original_pnc, false)
	if _marker != null and is_instance_valid(_marker):
		_marker.queue_free()
		_marker = null


func _finish_tutorial(silent: bool = false) -> void:
	if _finished:
		return
	_finished = true
	Global.tutorial_completed = true
	_current_step = STEPS.size()
	Global.tutorial_stage = _current_step
	Global.tutorial_version = 2
	_save_progress()
	_clear_marker()
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
	if _pnc_changed_for_tutorial:
		Global.set_point_and_click(_original_pnc, false)
	if not silent:
		Global.notify("[color=#9be89b]Guided start complete.[/color] Your mission tracker leads onward.")
	queue_free()
