extends Node

# ── Shadow sprites ────────────────────────────────────────────────
# Flat blob-shadow builder shared by every entity that draws one
# (player, mobs, trees, placed blocks) instead of duplicating the same
# Sprite2D setup per script.
func make_shadow_sprite(texture: Texture2D, offset: Vector2, scale_v: Vector2, alpha: float) -> Sprite2D:
	var shadow := Sprite2D.new()
	shadow.texture  = texture
	shadow.position = offset
	shadow.scale    = scale_v
	shadow.modulate = Color(0.0, 0.0, 0.0, alpha)
	shadow.z_index  = -1
	return shadow

# ── Break progress bar ────────────────────────────────────────────
# Shared visual for anything breakable (placed blocks, trees) — one
# consistent bar instead of each script drawing its own copy.
const BREAK_BAR_WIDTH:  float = 32.0
const BREAK_BAR_HEIGHT: float = 5.0
const BREAK_BAR_BG:     Color = Color(0.10, 0.10, 0.10, 0.85)
const BREAK_BAR_FILL:   Color = Color(0.30, 0.90, 0.30, 1.00)

# Must be called from inside the caller's own _draw() — CanvasItem only
# allows draw_* calls while that specific node is in its drawing pass.
func draw_break_bar(ci: CanvasItem, progress: float, y_offset: float = -20.0) -> void:
	var half_w: float = BREAK_BAR_WIDTH * 0.5
	ci.draw_rect(Rect2(-half_w, y_offset, BREAK_BAR_WIDTH, BREAK_BAR_HEIGHT), BREAK_BAR_BG)
	var fill_w: float = BREAK_BAR_WIDTH * clampf(progress, 0.0, 1.0)
	ci.draw_rect(Rect2(-half_w, y_offset, fill_w, BREAK_BAR_HEIGHT), BREAK_BAR_FILL)

# ── Hitbox debug overlay helpers ────────────────────────────────────────
# Moved out of world.gd so cave_world.gd (and any future world-like scene)
# can draw the same hitbox visuals without duplicating this logic — the
# only thing that ever differed between them was WHICH nodes to walk, not
# HOW to draw a shape once found. `overlay` is the CanvasItem whose own
# _draw()/draw signal callback is currently active — same "must be called
# from inside the caller's own drawing pass" rule as draw_break_bar above,
# it just also works transitively through these calls since Godot's rule
# is about which CanvasItem issues the draw_* call, not which script does.
#
# Recursively finds every CollisionShape2D whose immediate parent is a
# StaticBody2D or CharacterBody2D (the solid hitbox) — skips shapes parented
# by Area2D (interact/click trigger ranges, not physical collision), and
# doesn't care how deeply the body is nested (e.g. ObjectItem's collider
# sits under Sprite2D/StaticBody2D, LuaNPC has two separate bodies).
func draw_body_hitboxes(overlay: CanvasItem, root: Node, color: Color) -> void:
	for child in root.get_children():
		if child is CollisionShape2D and (child as CollisionShape2D).shape != null \
				and (child.get_parent() is StaticBody2D or child.get_parent() is CharacterBody2D):
			draw_shape_outline(overlay, child as CollisionShape2D, color)
		draw_body_hitboxes(overlay, child, color)

# Assumes axis-aligned shapes (none of the game's mob/block colliders are
# rotated today) — draws an outline in the overlay's local space.
func draw_shape_outline(overlay: CanvasItem, col: CollisionShape2D, color: Color) -> void:
	var shape: Shape2D = col.shape
	var center: Vector2 = overlay.to_local(col.global_position)
	if shape is RectangleShape2D:
		var size: Vector2 = (shape as RectangleShape2D).size
		overlay.draw_rect(Rect2(center - size * 0.5, size), color, false, 2.0)
	elif shape is CircleShape2D:
		var r: float = (shape as CircleShape2D).radius
		overlay.draw_arc(center, r, 0.0, TAU, 24, color, 2.0)
	elif shape is CapsuleShape2D:
		var cap: CapsuleShape2D = shape as CapsuleShape2D
		var r: float = cap.radius
		var half_h: float = cap.height * 0.5 - r
		var top:    Vector2 = center + Vector2(0.0, -half_h)
		var bottom: Vector2 = center + Vector2(0.0,  half_h)
		overlay.draw_arc(top,    r, PI, TAU, 16, color, 2.0)
		overlay.draw_arc(bottom, r, 0.0, PI, 16, color, 2.0)
		overlay.draw_line(top + Vector2(-r, 0.0), bottom + Vector2(-r, 0.0), color, 2.0)
		overlay.draw_line(top + Vector2( r, 0.0), bottom + Vector2( r, 0.0), color, 2.0)

# ── Inventory constants ───────────────────────────────────────────
const MAX_STACK:      int = 32
const HOTBAR_SIZE:    int = 9
const INVENTORY_SIZE: int = 20

# Shared item-icon slot size (unscaled) — used by every UI that shows an
# ItemData icon (inventory grid, hand-craft tab, crafting station, trash
# slot) so icons read as the same size across all of them.
const ITEM_SLOT_SIZE: float = 64.0

# ── Storage — each slot is {"quantity": int, "data": ItemData} ────
var Hotbar:    Array = []
var Inventory: Array = []

var hotbar_selected: int = 0

signal Hotbar_updated
signal Inventory_updated
signal hotbar_selection_changed(index: int)

# ── Player stats ──────────────────────────────────────────────────
var health:     float = 100.0
var max_health: float = 100.0
var stamina:    float = 50.0
var max_stamina: float = 50.0

signal health_changed(value: float, max_value: float)
signal stamina_changed(value: float, max_value: float)

# ── Settings ──────────────────────────────────────────────────────
var master_volume:      float = 1.0
var music_volume:       float = 1.0
var sfx_volume:         float = 1.0
var camera_zoom:        float = 1.3
var pause_on_inventory: bool  = true
var pause_menu_open:    bool  = false
# ── Unified UI stack ──────────────────────────────────────────────
# All game interfaces call open_ui() / close_ui() instead of
# managing their own boolean flags and pause state.
var _ui_open_count: int = 0
var player_near_station: bool  = false
var block_mode:          bool  = false   # CTRL toggles — shared across all scripts
var ui_scale:            float = 1.0

signal ui_scale_changed(scale: float)
signal request_close_all_ui

signal camera_zoom_changed(zoom: float)
signal inventory_toggled(is_open: bool)
signal block_mode_changed(enabled: bool)
signal item_picked_up(item_name: String, item_type: String)
signal hover_label_changed(text: String)
signal lua_stuck_notice(message: String)

# ── Day/night + weather ──────────────────────────────────────────
signal day_started
signal night_started
signal snowstorm_changed(active: bool)
var snowstorm_active: bool = false
# Mirrored by day_night_cycle.gd on every crossing — lets code that needs to
# know "is it day right now" (not just react to the transition) query this
# directly instead of tracking the signals itself.
var is_daytime: bool = true

# ── Missions ──────────────────────────────────────────────────────
var missions: Array = []
signal mission_updated
signal mission_completed(mission_id: String)
# Only one mission can be accepted at a time — the id of the currently
# accepted mission, "" when none. Accepting a mission also emits
# mission_accepted(), which world.gd uses to spawn the dungeon entrance.
var accepted_mission_id: String = ""
signal mission_accepted(mission_id: String)

# ── Knowledge / quiz / dungeon-mission registries ───────────────────────
# Data-driven dungeon content lives in three resource folders and is loaded
# once at startup:
#   res://resources/entries/        KnowledgeEntry (encyclopedia + keyword)
#   res://resources/quizzes/        QuizQuestion   (quiz altar questions)
#   res://resources/dungeon_missions/  DungeonMissionData (glues entry→quizzes)
# A dungeon mission references the others by FILE NAME (e.g.
# "entry_1_lua.tres") so the mission author never needs to build node graphs
# in the editor — just drop a .tres in the right folder and reference it.
const KNOWLEDGE_DIR: String       = "res://resources/entries/"
const QUIZ_DIR:      String       = "res://resources/quizzes/"
const DUNGEON_MISSION_DIR: String = "res://resources/dungeon_missions/"

var knowledge_entries: Dictionary = {}  # entry base name -> KnowledgeEntry
var quiz_questions:    Dictionary = {}  # quiz base name -> QuizQuestion
var dungeon_missions:  Dictionary = {}  # dungeon_index -> DungeonMissionData

# What the player has actually learned. learned_entries keyed by entry base
# name (drives the encyclopedia view); learned_keywords keyed by the entry's
# keyword string (drives unlocking the concept in the Lua editor later).
var learned_entries:  Dictionary = {}  # entry base name -> true
var learned_keywords: Dictionary = {}  # keyword -> entry base name

signal knowledge_updated

# ── Dungeon runtime state ─────────────────────────────────────────────
# cleared_dungeons: a dungeon is worth TWO stars — one for clearing the
# dungeon (quiz altar all-correct, recorded here) and one for completing
# its mission (Global.complete_mission, which fires right after). Both are
# counted by the mission UI's star totals.
# dungeon_seeds: rolled ONCE, the first time the player accepts that
# dungeon's mission, then persisted — re-entering regenerates the exact
# same layout (DungeonGenerator is deterministic from its seed).
var cleared_dungeons: Dictionary = {}  # dungeon_index -> true
var dungeon_seeds:    Dictionary = {}  # dungeon_index -> int
signal dungeon_cleared(dungeon_index: int)

func load_knowledge_data() -> void:
	knowledge_entries.clear()
	quiz_questions.clear()
	dungeon_missions.clear()
	_load_resource_dir(KNOWLEDGE_DIR, knowledge_entries)
	_load_resource_dir(QUIZ_DIR,      quiz_questions)
	var mission_lookup: Dictionary = {}
	_load_resource_dir(DUNGEON_MISSION_DIR, mission_lookup)
	for key in mission_lookup:
		var m: DungeonMissionData = mission_lookup[key] as DungeonMissionData
		if m != null:
			dungeon_missions[m.dungeon_index] = m

func _load_resource_dir(dir_path: String, into: Dictionary) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		push_warning("Global: cannot open resource folder %s" % dir_path)
		return
	dir.list_dir_begin()
	var fname := dir.get_next()
	while fname != "":
		if not dir.current_is_dir() and fname.ends_with(".tres"):
			var res: Resource = load(dir_path + fname)
			if res != null:
				into[fname.get_basename()] = res
			else:
				push_warning("Global: failed to load %s%s" % [dir_path, fname])
		fname = dir.get_next()
	dir.list_dir_end()

func get_knowledge_entry_file(fname: String) -> KnowledgeEntry:
	return knowledge_entries.get(fname.get_basename()) as KnowledgeEntry

func get_quiz_file(fname: String) -> QuizQuestion:
	return quiz_questions.get(fname.get_basename()) as QuizQuestion

func get_dungeon_mission_for_index(idx: int) -> DungeonMissionData:
	return dungeon_missions.get(idx) as DungeonMissionData

func get_dungeon_mission_by_file(fname: String) -> DungeonMissionData:
	for idx in dungeon_missions:
		var m: DungeonMissionData = dungeon_missions[idx] as DungeonMissionData
		if m != null and m.id() == fname.get_basename():
			return m
	return null

# Dungeon seeds are rolled the first time the player accepts the mission
# (world.gd calls this from _spawn_dungeon_entrance); kept here so the
# layout survives re-entry and save/load.
func get_or_create_dungeon_seed(dungeon_index: int) -> int:
	if dungeon_seeds.has(dungeon_index):
		return int(dungeon_seeds[dungeon_index])
	var seed := randi()
	dungeon_seeds[dungeon_index] = seed
	return seed

# Star #1 of a dungeon's two: the quiz altar was cleared (called right before
# complete_mission fires for star #2). Idempotent so re-clears never double
# count, and it drives the mission UI popup via dungeon_cleared.
func record_dungeon_clear(dungeon_index: int) -> void:
	if cleared_dungeons.has(dungeon_index):
		return
	cleared_dungeons[dungeon_index] = true
	dungeon_cleared.emit(dungeon_index)
	mission_updated.emit()  # star totals change — refresh the mission UI

func is_dungeon_cleared(dungeon_index: int) -> bool:
	return cleared_dungeons.has(dungeon_index)

# Every dungeon is worth one clear-star in addition to its mission star, so
# the mission UI's star total = mission count + dungeon count.
func clearable_dungeon_count() -> int:
	return dungeon_missions.size()

# Reconstruct keyword → entry mapping from the learned entries each load,
# so it always matches whatever entry resources currently exist.
func _rebuild_learned_keywords() -> void:
	learned_keywords.clear()
	for id in learned_entries:
		var e: KnowledgeEntry = knowledge_entries.get(id) as KnowledgeEntry
		if e != null and not e.keyword.is_empty():
			learned_keywords[e.keyword] = id

# Called by the knowledge altar. Records the concept in the encyclopedia and
# unlocks its keyword (the Lua-editor enforcement itself is a later polish).
func learn_entry(entry: KnowledgeEntry) -> void:
	if entry == null:
		return
	if learned_entries.has(entry.id()):
		return
	learned_entries[entry.id()] = true
	if not entry.keyword.is_empty():
		learned_keywords[entry.keyword] = entry.id()
	knowledge_updated.emit()

func has_learned_entry(fname: String) -> bool:
	return learned_entries.has(fname.get_basename())

func has_keyword_unlocked(keyword: String) -> bool:
	return learned_keywords.has(keyword)

func learned_entry_count() -> int:
	return learned_entries.size()

# Resolve an unlocked entry back to its resource for the encyclopedia view.
func all_learned_entries() -> Array[KnowledgeEntry]:
	var out: Array[KnowledgeEntry] = []
	for id in learned_entries:
		var e: KnowledgeEntry = knowledge_entries.get(id) as KnowledgeEntry
		if e != null:
			out.append(e)
	return out

# Grant an item by resource path (used for the Lua Core reward). Returns true
# if it landed in the inventory. Rejects dev items like every other path.
func grant_item(item_path: String, quantity: int = 1) -> bool:
	if item_path.is_empty() or not ResourceLoader.exists(item_path):
		push_warning("Global: reward item not found: %s" % item_path)
		return false
	var data: ItemData = load(item_path) as ItemData
	if data == null or data.is_dev_item:
		return false
	return add_item({"data": data, "quantity": maxi(quantity, 1)})

# ── Player / world refs ───────────────────────────────────────────
var player_node: Node = null
var world_node:  Node = null
var game_node:   Node = null  # game_instance.gd — CavePortal calls enter_cave()/exit_cave(), DungeonPortal calls enter_dungeon()

@onready var inventory_slot_scene: PackedScene = preload("res://scenes/ui/InventorySlot.tscn")

func _ready() -> void:
	Hotbar.resize(HOTBAR_SIZE)
	Inventory.resize(INVENTORY_SIZE)
	_init_missions()
	load_knowledge_data()
	_append_dungeon_missions()

# ── Centralized world debug/build-mode shortcuts ───────────────────────
# Ctrl+Shift+H/C/T and the block-mode Ctrl toggle used to be hand-wired
# into each world-like scene's own _input() (world.gd, then cave_world.gd
# duplicating it) — every new scene type needed the same key-detection
# copied in again. Detecting the keys HERE once and delegating to whichever
# world is active (via has_method()/call(), same duck-typing convention
# already used everywhere else in this codebase — e.g. placed blocks'
# setup()/set_world_cell()) means a future scene just needs to implement
# matching method names to get these shortcuts for free. World scripts
# still own the actual toggle/draw logic — this only owns detecting the
# keypress and routing it.
func _input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	var key_event := event as InputEventKey
	if key_event.keycode == KEY_H and key_event.ctrl_pressed and key_event.shift_pressed:
		_dispatch_to_world("toggle_hitboxes")
	elif key_event.keycode == KEY_C and key_event.ctrl_pressed and key_event.shift_pressed:
		_dispatch_to_world("toggle_chunk_borders")
	elif key_event.keycode == KEY_T and key_event.ctrl_pressed and key_event.shift_pressed:
		_dispatch_to_world("teleport_to_nearest_cave")
	elif key_event.keycode == KEY_CTRL and not key_event.shift_pressed:
		# Block mode itself is a plain global flag, not something any one
		# world "owns" — flipping it here and letting each world's own
		# per-frame ghost/grid update pick up the new value is simpler than
		# also duck-typing a reaction method. (World.gd's old inline
		# "ghost.visible = false" on toggle-off was redundant with that
		# same per-frame check anyway, just hid it one frame sooner.)
		block_mode = not block_mode
		block_mode_changed.emit(block_mode)

func _dispatch_to_world(method_name: String) -> void:
	if world_node != null and is_instance_valid(world_node) and world_node.has_method(method_name):
		world_node.call(method_name)

func _init_missions() -> void:
	missions = [
		{"id": "move",             "title": "Input any movement",    "completed": false},
		{"id": "open_inventory",   "title": "Open your inventory",   "completed": false},
		{"id": "cut_tree",         "title": "Cut your first tree",   "completed": false},
		{"id": "craft_item",       "title": "Craft your first item", "completed": false},
	]

# Dungeon missions are NOT hardcoded — one is created per DungeonMissionData
# .tres file actually present in resources/dungeon_missions/, so the mission
# list always matches the shipped dungeon content. Called after
# load_knowledge_data() fills the dungeon_missions registry.
func _append_dungeon_missions() -> void:
	const DUNGEON_ROMAN: Array = ["", "I", "II", "III", "IV", "V", "VI", "VII", "VIII", "IX", "X"]
	var indexes: Array = dungeon_missions.keys()
	indexes.sort()
	for idx in indexes:
		var m: DungeonMissionData = dungeon_missions[idx] as DungeonMissionData
		if m == null:
			continue
		var roman: String = DUNGEON_ROMAN[idx] if idx < DUNGEON_ROMAN.size() else str(idx)
		missions.append({
			"id": "dungeon_%d" % idx,
			"title": "Dungeon %s — %s" % [roman, m.mission_name],
			"completed": false,
			"dungeon_index": idx,
		})

func accept_mission(id: String) -> void:
	if accepted_mission_id == id:
		return
	accepted_mission_id = id
	mission_updated.emit()
	mission_accepted.emit(id)

func get_accepted_mission() -> Dictionary:
	for m in missions:
		if m["id"] == accepted_mission_id:
			return m
	return {}

# dungeon_index of the currently accepted dungeon mission, or 0 when the
# accepted mission isn't a dungeon (drives the mission guide arrow).
func accepted_dungeon_index() -> int:
	for m in missions:
		if m["id"] == accepted_mission_id and m.has("dungeon_index"):
			return int(m["dungeon_index"])
	return 0

func complete_mission(id: String) -> void:
	for m in missions:
		if m["id"] == id and not m["completed"]:
			m["completed"] = true
			if accepted_mission_id == id:
				accepted_mission_id = ""
			mission_updated.emit()
			mission_completed.emit(id)
			return

func reset_missions() -> void:
	for m in missions:
		m["completed"] = false
	accepted_mission_id = ""
	cleared_dungeons.clear()
	mission_updated.emit()

# ── Add item ──────────────────────────────────────────────────────
func add_item(item: Dictionary) -> bool:
	var data: ItemData = item["data"] as ItemData
	# Dev items (cave ore placeholders, etc.) are world-gen/game-placed only
	# — this is the single funnel every acquisition path (mining drops,
	# crafting results, chest transfers, starting-item grants) goes through,
	# so rejecting here is enough to make them un-obtainable everywhere.
	if data != null and data.is_dev_item:
		return false
	# 1. Stack in hotbar
	for i in range(Hotbar.size()):
		if Hotbar[i] != null \
				and Hotbar[i]["data"] == data \
				and Hotbar[i]["quantity"] < MAX_STACK:
			Hotbar[i]["quantity"] = min(Hotbar[i]["quantity"] + item["quantity"], MAX_STACK)
			Hotbar_updated.emit()
			item_picked_up.emit(data.item_name, data.item_type)
			return true
	# 2. Stack in inventory
	for i in range(Inventory.size()):
		if Inventory[i] != null \
				and Inventory[i]["data"] == data \
				and Inventory[i]["quantity"] < MAX_STACK:
			Inventory[i]["quantity"] = min(Inventory[i]["quantity"] + item["quantity"], MAX_STACK)
			Inventory_updated.emit()
			item_picked_up.emit(data.item_name, data.item_type)
			return true
	# 3. Empty hotbar slot
	for i in range(Hotbar.size()):
		if Hotbar[i] == null:
			Hotbar[i] = item
			Hotbar_updated.emit()
			item_picked_up.emit(data.item_name, data.item_type)
			return true
	# 4. Empty inventory slot
	for i in range(Inventory.size()):
		if Inventory[i] == null:
			Inventory[i] = item
			Inventory_updated.emit()
			item_picked_up.emit(data.item_name, data.item_type)
			return true
	return false

# ── Remove one from an item slot by ItemData reference ────────────
# Always tries the selected hotbar slot first so the active stack is
# consumed rather than whichever matching stack happens to be at index 0.
func remove_item(data: ItemData) -> void:
	if hotbar_selected < Hotbar.size() \
			and Hotbar[hotbar_selected] != null \
			and Hotbar[hotbar_selected]["data"] == data:
		Hotbar[hotbar_selected]["quantity"] -= 1
		if Hotbar[hotbar_selected]["quantity"] <= 0:
			Hotbar[hotbar_selected] = null
		Hotbar_updated.emit()
		return
	for i in range(Hotbar.size()):
		if Hotbar[i] != null and Hotbar[i]["data"] == data:
			Hotbar[i]["quantity"] -= 1
			if Hotbar[i]["quantity"] <= 0:
				Hotbar[i] = null
			Hotbar_updated.emit()
			return
	for i in range(Inventory.size()):
		if Inventory[i] != null and Inventory[i]["data"] == data:
			Inventory[i]["quantity"] -= 1
			if Inventory[i]["quantity"] <= 0:
				Inventory[i] = null
			Inventory_updated.emit()
			return

# ── Hotbar helpers ────────────────────────────────────────────────
func get_hotbar_item() -> Variant:
	if hotbar_selected < Hotbar.size():
		return Hotbar[hotbar_selected]
	return null

func set_hotbar_selection(index: int) -> void:
	hotbar_selected = clamp(index, 0, HOTBAR_SIZE - 1)
	hotbar_selection_changed.emit(hotbar_selected)

# ── Player ────────────────────────────────────────────────────────
func set_player_reference(player: Node) -> void:
	player_node = player

# ── Drop item into world ──────────────────────────────────────────
func adjust_drop_pos(pos: Vector2) -> Vector2:
	var rad := 100.0
	for item in get_tree().get_nodes_in_group("items"):
		if (item as Node2D).global_position.distance_to(pos) < rad:
			pos += Vector2(randf_range(-rad, rad), randf_range(-rad, rad))
			break
	return pos

# ── UI state ─────────────────────────────────────────────────────
func open_ui() -> void:
	_ui_open_count += 1
	get_tree().paused = true

func close_ui() -> void:
	_ui_open_count = max(0, _ui_open_count - 1)
	if _ui_open_count == 0 and not pause_menu_open:
		get_tree().paused = false

func any_ui_open() -> bool:
	return _ui_open_count > 0

# ── Block hover label ─────────────────────────────────────────────
var _current_hover_name: String = ""

func set_hover(name: String) -> void:
	if name != _current_hover_name:
		_current_hover_name = name
		hover_label_changed.emit(name)

func drop_item(inv_item: Dictionary, drop_position: Vector2) -> void:
	var item_scene: PackedScene = load("res://scenes/ui/InventoryItem.tscn") as PackedScene
	if item_scene == null:
		return
	var inst: Node = item_scene.instantiate()
	var qty: int = inv_item.get("quantity", 1)
	inst.call("set_item_data", inv_item["data"] as ItemData, qty)
	drop_position = adjust_drop_pos(drop_position)
	(inst as Node2D).global_position = drop_position
	get_tree().current_scene.add_child(inst)

# ── Save / load ───────────────────────────────────────────────────
var active_save_slot:   int        = -1
var has_pending_pos:    bool       = false
var pending_player_pos: Vector2    = Vector2.ZERO
var pending_world_data: Dictionary = {}

func has_save(slot: int) -> bool:
	return FileAccess.file_exists("user://save_slot_%d.json" % slot)

func get_last_slot() -> int:
	var newest_slot: int   = -1
	var newest_time: float = 0.0
	for s in range(1, 4):
		if not has_save(s):
			continue
		var f := FileAccess.open("user://save_slot_%d.json" % s, FileAccess.READ)
		if f == null:
			continue
		var data = JSON.parse_string(f.get_as_text())
		f.close()
		if data is Dictionary and data.has("timestamp"):
			var t: float = float(data["timestamp"])
			if t > newest_time:
				newest_time = t
				newest_slot = s
	return newest_slot

func get_save_info(slot: int) -> Dictionary:
	if not has_save(slot):
		return {}
	var f := FileAccess.open("user://save_slot_%d.json" % slot, FileAccess.READ)
	if f == null:
		return {}
	var data = JSON.parse_string(f.get_as_text())
	f.close()
	if data is Dictionary:
		return data
	return {}

func save_game(slot: int) -> void:
	active_save_slot = slot
	var save_data: Dictionary = {
		"slot":         slot,
		"timestamp":    Time.get_unix_time_from_system(),
		"player_pos_x": 0.0,
		"player_pos_y": 0.0,
		"hotbar":       [],
		"inventory":    [],
	}
	if player_node != null:
		save_data["player_pos_x"] = (player_node as Node2D).global_position.x
		save_data["player_pos_y"] = (player_node as Node2D).global_position.y
	if world_node != null and world_node.has_method("get_world_save_data"):
		save_data["world"] = world_node.call("get_world_save_data")
	for slot_item in Hotbar:
		if slot_item == null:
			save_data["hotbar"].append(null)
		else:
			var d: ItemData = slot_item["data"] as ItemData
			if d == null or d.resource_path.is_empty():
				save_data["hotbar"].append(null)
			else:
				save_data["hotbar"].append({"path": d.resource_path, "quantity": slot_item["quantity"]})
	for slot_item in Inventory:
		if slot_item == null:
			save_data["inventory"].append(null)
		else:
			var d: ItemData = slot_item["data"] as ItemData
			if d == null or d.resource_path.is_empty():
				save_data["inventory"].append(null)
			else:
				save_data["inventory"].append({"path": d.resource_path, "quantity": slot_item["quantity"]})
	var missions_save: Array = []
	for m in missions:
		missions_save.append({"id": m["id"], "completed": m["completed"]})
	save_data["missions"] = missions_save
	save_data["accepted_mission_id"] = accepted_mission_id
	save_data["learned_entries"]  = learned_entries.keys()
	save_data["learned_keywords"] = learned_keywords.keys()
	var cleared_save: Array = []
	for idx in cleared_dungeons:
		cleared_save.append(int(idx))
	save_data["cleared_dungeons"] = cleared_save
	var seeds_save: Array = []
	for idx in dungeon_seeds:
		seeds_save.append({"index": int(idx), "seed": int(dungeon_seeds[idx])})
	save_data["dungeon_seeds"] = seeds_save
	var f := FileAccess.open("user://save_slot_%d.json" % slot, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(save_data))
		f.close()

func load_game(slot: int) -> void:
	active_save_slot = slot
	if not has_save(slot):
		return
	var f := FileAccess.open("user://save_slot_%d.json" % slot, FileAccess.READ)
	if f == null:
		return
	var data = JSON.parse_string(f.get_as_text())
	f.close()
	if not (data is Dictionary):
		return
	Hotbar.fill(null)
	Inventory.fill(null)
	if data.has("hotbar"):
		var arr: Array = data["hotbar"] as Array
		for i in range(mini(arr.size(), HOTBAR_SIZE)):
			if arr[i] == null:
				continue
			if not (arr[i] is Dictionary):
				continue
			var entry: Dictionary = arr[i] as Dictionary
			if not entry.has("path"):
				continue
			var res: ItemData = load(entry["path"]) as ItemData
			if res != null:
				Hotbar[i] = {"data": res, "quantity": int(entry["quantity"])}
	if data.has("inventory"):
		var arr: Array = data["inventory"] as Array
		for i in range(mini(arr.size(), INVENTORY_SIZE)):
			if arr[i] == null:
				continue
			if not (arr[i] is Dictionary):
				continue
			var entry: Dictionary = arr[i] as Dictionary
			if not entry.has("path"):
				continue
			var res: ItemData = load(entry["path"]) as ItemData
			if res != null:
				Inventory[i] = {"data": res, "quantity": int(entry["quantity"])}
	if data.has("player_pos_x") and data.has("player_pos_y"):
		pending_player_pos = Vector2(float(data["player_pos_x"]), float(data["player_pos_y"]))
		has_pending_pos    = true
	if data.has("world") and data["world"] is Dictionary:
		pending_world_data = data["world"] as Dictionary
	else:
		pending_world_data = {}
	if data.has("missions"):
		var mdata: Array = data["missions"] as Array
		for entry in mdata:
			if not (entry is Dictionary) or not entry.has("id"):
				continue
			for m in missions:
				if m["id"] == entry["id"]:
					m["completed"] = bool(entry.get("completed", false))
					break
		mission_updated.emit()
	if data.has("accepted_mission_id"):
		accepted_mission_id = str(data["accepted_mission_id"])
	if data.has("learned_entries") and data["learned_entries"] is Array:
		for id in (data["learned_entries"] as Array):
			if not learned_entries.has(id):
				learned_entries[id] = true
	_rebuild_learned_keywords()
	knowledge_updated.emit()
	if data.has("cleared_dungeons") and data["cleared_dungeons"] is Array:
		for idx in (data["cleared_dungeons"] as Array):
			if not cleared_dungeons.has(int(idx)):
				cleared_dungeons[int(idx)] = true
	if data.has("dungeon_seeds") and data["dungeon_seeds"] is Array:
		for entry in (data["dungeon_seeds"] as Array):
			if entry is Dictionary:
				dungeon_seeds[int(entry["index"])] = int(entry["seed"])
	Hotbar_updated.emit()
	Inventory_updated.emit()
