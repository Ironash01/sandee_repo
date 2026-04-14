extends Node

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

# ── Settings ──────────────────────────────────────────────────────
var master_volume:      float = 1.0
var music_volume:       float = 1.0
var sfx_volume:         float = 1.0
var camera_zoom:        float = 1.0
var pause_on_inventory: bool  = true
var inventory_open:     bool  = false
var lua_ui_open:        bool  = false
var player_near_station: bool  = false
var ui_scale:            float = 1.0

signal ui_scale_changed(scale: float)

signal camera_zoom_changed(zoom: float)
signal inventory_toggled(is_open: bool)

# ── Player ref ────────────────────────────────────────────────────
var player_node: Node = null

@onready var inventory_slot_scene: PackedScene = preload("res://scenes/ui/InventorySlot.tscn")

func _ready() -> void:
	Hotbar.resize(HOTBAR_SIZE)
	Inventory.resize(INVENTORY_SIZE)

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
			return true
	# 2. Stack in inventory
	for i in range(Inventory.size()):
		if Inventory[i] != null \
				and Inventory[i]["data"] == data \
				and Inventory[i]["quantity"] < MAX_STACK:
			Inventory[i]["quantity"] = min(Inventory[i]["quantity"] + item["quantity"], MAX_STACK)
			Inventory_updated.emit()
			return true
	# 3. Empty hotbar slot
	for i in range(Hotbar.size()):
		if Hotbar[i] == null:
			Hotbar[i] = item
			Hotbar_updated.emit()
			return true
	# 4. Empty inventory slot
	for i in range(Inventory.size()):
		if Inventory[i] == null:
			Inventory[i] = item
			Inventory_updated.emit()
			return true
	return false

# ── Remove one from an item slot by ItemData reference ────────────
func remove_item(data: ItemData) -> void:
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

func drop_item(inv_item: Dictionary, drop_position: Vector2) -> void:
	var item_scene: PackedScene = load("res://scenes/ui/InventoryItem.tscn") as PackedScene
	if item_scene == null:
		return
	var inst: Node = item_scene.instantiate()
	inst.call("set_item_data", inv_item["data"] as ItemData)
	drop_position = adjust_drop_pos(drop_position)
	(inst as Node2D).global_position = drop_position
	get_tree().current_scene.add_child(inst)
