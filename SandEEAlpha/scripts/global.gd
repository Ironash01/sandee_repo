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

# ── Inventory constants ───────────────────────────────────────────
const MAX_STACK:      int = 32
const HOTBAR_SIZE:    int = 9
const INVENTORY_SIZE: int = 20

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

# ── Missions ──────────────────────────────────────────────────────
var missions: Array = []
signal mission_updated
signal mission_completed(mission_id: String)

# ── Player / world refs ───────────────────────────────────────────
var player_node: Node = null
var world_node:  Node = null

@onready var inventory_slot_scene: PackedScene = preload("res://scenes/ui/InventorySlot.tscn")

func _ready() -> void:
	Hotbar.resize(HOTBAR_SIZE)
	Inventory.resize(INVENTORY_SIZE)
	_init_missions()

func _init_missions() -> void:
	missions = [
		{"id": "move",             "title": "Input any movement",    "completed": false},
		{"id": "open_inventory",   "title": "Open your inventory",   "completed": false},
		{"id": "cut_tree",         "title": "Cut your first tree",   "completed": false},
		{"id": "craft_item",       "title": "Craft your first item", "completed": false},
	]

func complete_mission(id: String) -> void:
	for m in missions:
		if m["id"] == id and not m["completed"]:
			m["completed"] = true
			mission_updated.emit()
			mission_completed.emit(id)
			return

func reset_missions() -> void:
	for m in missions:
		m["completed"] = false
	mission_updated.emit()

# ── Add item ──────────────────────────────────────────────────────
func add_item(item: Dictionary) -> bool:
	var data: ItemData = item["data"] as ItemData
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
	inst.call("set_item_data", inv_item["data"] as ItemData)
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
	Hotbar_updated.emit()
	Inventory_updated.emit()
