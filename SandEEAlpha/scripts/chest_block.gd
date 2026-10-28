extends Node2D
# ── Chest Block ───────────────────────────────────────────────────
# Placed in the world. Left-click (when build mode OFF + player nearby) docks
# this chest's storage into the player's EXISTING inventory panel, shown
# directly beneath the player inventory — one combined screen, not a second
# inventory implementation. Items move only by dragging between the two grids;
# a plain click/tap selects or inspects a stack and never transfers it.
# Shift + left-click mines the chest off the wall (hold-to-break, same
# pickaxe-tier/block_level rules as placed blocks) instead of opening it.
# NPC can call has_space() and deposit_item() autonomously.

const MAX_SLOTS: int = 8
const SHADOW_TEXTURE: Texture2D = preload("res://sprites/shadow/shadow_blockbase.png")

# Each slot: null or {data: ItemData, quantity: int}
var slots: Array = []
# Emitted whenever the authoritative slot array changes. DungeonWorld uses it
# to persist rare-chest contents immediately; ordinary chests ignore it.
signal contents_changed

var _player_nearby: bool    = false
var _world_cell:    Vector2i = Vector2i(-99999, -99999)
var _world_ref:     Node    = null
# The player's inventory panel while it hosts this chest (null when closed).
var _open_ui:       Node    = null
var _side_open_counted: bool = false
var item_data:      ItemData = null

@onready var _sprite:   Sprite2D = $Sprite2D
@onready var _interact: Area2D   = $InteractArea

func _ready() -> void:
	if not Global.gameplay_input_cancelled.is_connected(_on_gameplay_input_cancelled):
		Global.gameplay_input_cancelled.connect(_on_gameplay_input_cancelled)
	slots.resize(MAX_SLOTS)
	add_to_group("Chest")
	add_to_group("TouchInteractable")
	add_child(Global.make_shadow_sprite(SHADOW_TEXTURE, Vector2(0.0, 10.0), Vector2(0.8, 0.4), 0.35))
	_interact.body_entered.connect(_on_body_entered)
	_interact.body_exited.connect(_on_body_exited)
	Global.request_close_all_ui.connect(_close_ui)

func setup(data: ItemData) -> void:
	item_data = data
	if _sprite != null:
		var tex: Texture2D = data.placeable_sprite if data.placeable_sprite != null else data.icon
		_sprite.texture = tex

func set_world_cell(cell: Vector2i, world: Node) -> void:
	_world_cell = cell
	_world_ref  = world

# ── NPC interface ─────────────────────────────────────────────────
func _stack_limit_for(data: ItemData) -> int:
	return data.stack_limit() if data != null else 1

func _deposit_capacity(data: ItemData) -> int:
	if data == null:
		return 0
	var limit: int = _stack_limit_for(data)
	var can_stack: bool = data.can_stack()
	var total: int = 0
	for slot in slots:
		if slot == null:
			total += limit
		elif can_stack and (slot as Dictionary)["data"] == data:
			total += maxi(0, limit - int((slot as Dictionary)["quantity"]))
	return total

func has_space() -> bool:
	for slot in slots:
		if slot == null:
			return true
		var data: ItemData = (slot as Dictionary)["data"] as ItemData
		if data != null and int((slot as Dictionary)["quantity"]) < data.stack_limit():
			return true
	return false

func deposit_item(item: Dictionary) -> bool:
	var data: ItemData = item["data"] as ItemData
	if data == null:
		return false
	var qty: int = int(item["quantity"])
	if qty <= 0:
		return true
	if _deposit_capacity(data) < qty:
		return false
	var limit: int = _stack_limit_for(data)
	var can_stack: bool = data.can_stack()
	# Stack onto existing slots (never for tools).
	if can_stack:
		for i in range(MAX_SLOTS):
			if qty <= 0:
				break
			if slots[i] == null:
				continue
			if (slots[i] as Dictionary)["data"] == data:
				var space: int = limit - int((slots[i] as Dictionary)["quantity"])
				var add: int = mini(qty, space)
				(slots[i] as Dictionary)["quantity"] = int((slots[i] as Dictionary)["quantity"]) + add
				qty -= add
	# Empty slots, one tool per slot or up to the real stack limit.
	for i in range(MAX_SLOTS):
		if qty <= 0:
			break
		if slots[i] != null:
			continue
		var take: int = mini(qty, limit)
		slots[i] = {"data": data, "quantity": take}
		qty -= take
	_refresh_ui()
	notify_contents_changed()
	return qty <= 0

func get_items() -> Array:
	return slots.duplicate()

# Removes up to `quantity` of `data` and returns how many were actually
# removed. Used by the Lua robot's withdraw(name, n).
func take_item(data: ItemData, quantity: int) -> int:
	if data == null or quantity <= 0:
		return 0
	var remaining: int = quantity
	for i in range(MAX_SLOTS):
		if remaining <= 0:
			break
		if slots[i] == null:
			continue
		if (slots[i] as Dictionary)["data"] != data:
			continue
		var take: int = mini(remaining, int((slots[i] as Dictionary)["quantity"]))
		(slots[i] as Dictionary)["quantity"] = int((slots[i] as Dictionary)["quantity"]) - take
		remaining -= take
		if int((slots[i] as Dictionary)["quantity"]) <= 0:
			slots[i] = null
	if remaining != quantity:
		_refresh_ui()
		notify_contents_changed()
	return quantity - remaining

func notify_contents_changed() -> void:
	contents_changed.emit()

# ── Input ─────────────────────────────────────────────────────────
func _input(event: InputEvent) -> void:
	if Global.is_mouse_event_over_ui(event):
		return
	if Global.block_mode: return
	if not _player_nearby: return
	if Global.pause_menu_open: return
	# While this chest's storage is open, closing is the ✕ / Esc / inventory
	# key — a world click must not toggle it from underneath.
	if is_open(): return
	# Another panel is open: don't react to a click that belongs to it.
	if Global.any_ui_open(): return
	# Only the object actually under the cursor may react. Without this every
	# chest/station within the interact radius consumed the same click, so
	# clicking a crafting station could open a chest instead — and two panels
	# opening together left the tree paused with nothing on screen.
	if not _cursor_over(Global.mouse_event_world(self, event)): return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		# Shift + left-click: mine the chest off the wall (respects pickaxe
		# tier + block_level break time) instead of toggling its UI.
		if Global.is_shift_held():
			if event.pressed:
				_try_start_breaking()
				if _breaking:
					_add_break_progress(CLICK_BREAK_SECONDS)
			else:
				_cancel_breaking()
			get_viewport().set_input_as_handled()
			return
		if event.pressed:
			_open_chest_ui()
			get_viewport().set_input_as_handled()

# True when the cursor is over THIS chest's sprite (same guard the furnace and
# crafting station use — see crafting_station_object.gd:_cursor_over).
func _cursor_over(at: Vector2 = Vector2.INF) -> bool:
	if _sprite == null or _sprite.texture == null:
		return true
	var r: Rect2 = _sprite.get_rect()
	var gt: Transform2D = _sprite.global_transform
	var a: Vector2 = gt * r.position
	var b: Vector2 = gt * (r.position + r.size)
	var lo := Vector2(minf(a.x, b.x), minf(a.y, b.y))
	var hi := Vector2(maxf(a.x, b.x), maxf(a.y, b.y))
	var m: Vector2 = Global.mouse_world(self) if at == Vector2.INF else at
	return m.x >= lo.x and m.x <= hi.x and m.y >= lo.y and m.y <= hi.y

# ── Docking into the player's inventory panel ─────────────────────
# The chest deliberately builds NO UI of its own: it docks its storage under
# the player's existing inventory, which already owns the slot scene, sizing,
# tooltips and drag/drop. This keeps one inventory implementation in the game.

# The player's inventory panel (single instance, owned by the player).
func _inventory_ui() -> Node:
	if Global.player_node == null:
		return null
	var layer: Node = Global.player_node.get_node_or_null("InventoryUI")
	if layer == null:
		return null
	for c in layer.get_children():
		if c.has_method("attach_chest"):
			return c
	return null

# True while the combined panel is showing THIS chest's storage.
func is_open() -> bool:
	return _open_ui != null and is_instance_valid(_open_ui) \
		and _open_ui.call("opened_chest") == self

func open_from_touch() -> bool:
	if not _player_nearby or is_open():
		return false
	if Global.block_mode or Global.any_ui_open() or Global.pause_menu_open:
		return false
	_open_chest_ui()
	return true

func _open_chest_ui() -> void:
	if is_open():
		return   # already showing this chest — never open/pause twice
	if not _side_open_counted:
		_side_open_counted = true
		Global.add_mission_progress("side_chest_collector", 1)
		if item_data != null and item_data.item_name.to_lower().contains("rare"):
			Global.add_mission_progress("side_rare_chests", 1)
	var ui: Node = _inventory_ui()
	if ui == null:
		return
	# Repeated interaction reuses the same panel — attach_chest() rebuilds the
	# storage views, it never creates a second UI.
	_open_ui = ui
	ui.call("attach_chest", self)
	var layer: Node = ui.get_parent()
	if layer != null:
		layer.set("visible", true)
	Global.open_ui()
	Global.inventory_toggled.emit(true)

# The panel closed itself (✕ / Esc / inventory key / close-all). The chest keeps
# its contents; only the view is gone.
func on_inventory_ui_closed() -> void:
	_open_ui = null

# The combined panel redraws the chest from `slots`; this just prompts it.
func _refresh_ui() -> void:
	if _open_ui != null and is_instance_valid(_open_ui) \
			and _open_ui.has_method("refresh_chest_slots"):
		_open_ui.call("refresh_chest_slots")

# Close the combined panel through the inventory UI so the pause refcount and
# the chest binding are released exactly once (idempotent).
func _close_ui() -> void:
	var ui: Node = _open_ui
	_open_ui = null
	if ui != null and is_instance_valid(ui) and ui.has_method("close_chest"):
		ui.call("close_chest", self)

# ── Drag & drop (chest ↔ player inventory, plus slot reordering) ───
# The shared slot component (inventory_slot.gd) makes every slot in the
# combined panel a drag source AND a drop target, so a stack can be deposited,
# taken out, or moved between slots. Payloads use the same
# {"from_index", "item", "source"} shape the inventory/hotbar slots emit; the
# chest's own grid adds "chest" as a source.
func _arr_of(src: String) -> Array:
	if src == "chest":
		return slots
	if src == "hotbar":
		return Global.Hotbar
	return Global.Inventory

# Called by inventory_slot.gd when a drag starts. Returns null for an empty slot.
func make_drag_data(index: int, from_chest: bool) -> Variant:
	var arr: Array = slots if from_chest else Global.Inventory
	if index < 0 or index >= arr.size() or arr[index] == null:
		return null
	return {"from_index": index, "item": arr[index],
		"source": "chest" if from_chest else "inventory"}

func can_accept_drop(index: int, to_chest: bool, data: Variant) -> bool:
	# Out of range / already closed: the chest must not accept anything, even
	# if a stale view managed to start a drag.
	if not _player_nearby or not is_open():
		return false
	if not (data is Dictionary):
		return false
	var info: Dictionary = data as Dictionary
	if not info.has("from_index") or not info.has("item"):
		return false
	var src: String = str(info.get("source", ""))
	if src != "chest" and src != "inventory" and src != "hotbar":
		return false
	var item: Variant = info.get("item")
	if not (item is Dictionary) or (item as Dictionary).get("data") == null:
		return false
	var from_arr: Array = _arr_of(src)
	var from_idx: int = int(info.get("from_index", -1))
	if from_idx < 0 or from_idx >= from_arr.size() or from_arr[from_idx] == null:
		return false
	var to_arr: Array = slots if to_chest else Global.Inventory
	if index < 0 or index >= to_arr.size():
		return false
	# Dropping a stack back onto its own slot is a no-op, not an invalid drop.
	if src == ("chest" if to_chest else "inventory") and from_idx == index:
		return false
	return true

func accept_drop(index: int, to_chest: bool, data: Variant) -> void:
	if not can_accept_drop(index, to_chest, data):
		return
	var info: Dictionary = data as Dictionary
	var src: String = str(info.get("source", ""))
	var from_idx: int = int(info.get("from_index", -1))
	var from_arr: Array = _arr_of(src)
	var to_arr: Array = slots if to_chest else Global.Inventory
	var a: Variant = from_arr[from_idx]
	var b: Variant = to_arr[index]

	if a != null and b != null and (a as Dictionary)["data"] == (b as Dictionary)["data"] \
			and ((a as Dictionary)["data"] as ItemData).can_stack():
		# Same stackable item: merge up to the stack limit, leaving any
		# remainder behind. Tools never take this path; they swap instead.
		var data_i: ItemData = (b as Dictionary)["data"] as ItemData
		var limit: int = data_i.stack_limit()
		var have: int = int((b as Dictionary)["quantity"])
		var space: int = maxi(limit - have, 0)
		if space <= 0:
			return
		var add: int = mini(int((a as Dictionary)["quantity"]), space)
		if add <= 0:
			return
		(b as Dictionary)["quantity"] = have + add
		var left: int = int((a as Dictionary)["quantity"]) - add
		if left <= 0:
			from_arr[from_idx] = null
		else:
			(a as Dictionary)["quantity"] = left
	else:
		# Different items, or an empty target: swap — this is the reorder case,
		# and it also covers taking an item out of / putting one into the chest.
		to_arr[index] = a
		from_arr[from_idx] = b

	# Keep the hotbar/inventory UIs in step with the arrays they render.
	Global.Hotbar_updated.emit()
	Global.Inventory_updated.emit()
	_refresh_ui()
	notify_contents_changed()

func _on_body_entered(body: Node) -> void:
	if body.is_in_group("Player"):
		_player_nearby = true

func _on_body_exited(body: Node) -> void:
	if body.is_in_group("Player"):
		_player_nearby = false
		_close_ui()
		_cancel_breaking()

# ── Shift-click breaking (respects the mining mechanic) ───────────
# Mirrors crafting_station_object.gd / placeable_block.gd exactly: shift +
# left-click runs the hold-to-break mechanic — duration = block_level -
# pickaxe_level (min 0.1s), gated by min_pickaxe_level — instead of
# destroying the chest instantly. Fresh shift-clicks each add
# CLICK_BREAK_SECONDS of work and progress persists
# PROGRESS_PERSIST_SECONDS past the last hit, so holding and spam-clicking
# both work. Completing the break drops the contents and the chest item.
const ITEM_SCENE: PackedScene = preload("res://scenes/ui/InventoryItem.tscn")
const CLICK_BREAK_SECONDS:      float = 0.5   # damage one shift-click adds
const PROGRESS_PERSIST_SECONDS: float = 2.5   # damage memory window
const WOBBLE_SNAPS_PER_SEC:     float = 3.0   # full left→right→left cycles per second
const WOBBLE_AMPLITUDE_RAD:     float = 0.045 # ~2.6° snap each side
const WOBBLE_FLIP_FRACTION:     float = 0.25  # fraction of each half spent flipping; the rest dwells

var _breaking:       bool  = false
var _break_duration: float = 1.0
var _break_elapsed:  float = 0.0
var _break_progress: float = 0.0
var _last_hit_ms:    int   = -1

func _process(delta: float) -> void:
	# The panel may have been closed by its own controls (✕ / Esc / inventory
	# key). Drop the binding so a later interaction opens it again cleanly.
	if _open_ui != null and not is_open():
		_open_ui = null
	_tick_progress_expiry()
	if not _breaking:
		return
	if not _player_nearby \
			or not Global.is_shift_held() \
			or not Global.is_left_action_held():
		_cancel_breaking()
		return
	_break_elapsed  = minf(_break_elapsed + delta, _break_duration)
	_break_progress = _break_elapsed / _break_duration if _break_duration > 0.0 else 1.0
	Global.report_break_progress(_break_progress, global_position, -26.0, self)
	_tick_wobble()
	queue_redraw()
	if _break_elapsed >= _break_duration:
		_do_break()

func _draw() -> void:
	# Ring is drawn by BreakProgressOverlay above the world.
	pass

# Adds damage (in seconds of break work) from a held frame's delta or a
# fresh shift-click's flat CLICK_BREAK_SECONDS, then breaks when full.
func _add_break_progress(seconds: float) -> void:
	_break_elapsed  = minf(_break_elapsed + seconds, _break_duration)
	_break_progress = _break_elapsed / _break_duration if _break_duration > 0.0 else 1.0
	_last_hit_ms    = Time.get_ticks_msec()
	Global.report_break_progress(_break_progress, global_position, -26.0, self)
	queue_redraw()
	if _break_elapsed >= _break_duration:
		_do_break()

# Damage fades from memory PROGRESS_PERSIST_SECONDS after the last hit —
# until then a returning player (or spam clicker) resumes where they left.
func _tick_progress_expiry() -> void:
	if _break_progress <= 0.0:
		return
	if Time.get_ticks_msec() - _last_hit_ms < int(PROGRESS_PERSIST_SECONDS * 1000.0):
		return
	_break_elapsed  = 0.0
	_break_progress = 0.0
	_last_hit_ms    = -1
	_sprite.rotation = 0.0
	Global.clear_break_progress(self)
	queue_redraw()

# Snappy left↔right shake, played ONLY while actively breaking.
func _tick_wobble() -> void:
	var u: float = fposmod(Time.get_ticks_msec() / 1000.0 * WOBBLE_SNAPS_PER_SEC, 1.0)
	var target: float = 1.0 if u < 0.5 else -1.0   # side this half dwells on
	var source: float = -target                    # side the flip starts from
	var half: float   = fmod(u, 0.5)               # 0..0.5 into this half
	var p: float      = clampf(half / (0.5 * WOBBLE_FLIP_FRACTION), 0.0, 1.0)
	_sprite.rotation = lerpf(source, target, ease(p, 2.0)) * WOBBLE_AMPLITUDE_RAD

# Begin the mining process. No-op when no pickaxe is selected, the held
# pickaxe is below min_pickaxe_level, or it's already breaking.
func _try_start_breaking() -> void:
	if _breaking:
		return
	var pick_lvl := _held_pickaxe_level()
	if pick_lvl < 0:
		return  # no pickaxe in hand
	var min_lvl: int = item_data.min_pickaxe_level if item_data != null else 0
	if pick_lvl < min_lvl:
		return  # pickaxe tier too low
	var block_lvl: int = item_data.block_level if item_data != null else 0
	_break_duration = maxf(0.1, float(block_lvl - pick_lvl))
	# The swing animation plays for any item used to break — route through the
	# player so it fires even though the chest consumed the click input.
	if Global.player_node != null and Global.player_node.has_method("swing_held_item"):
		Global.player_node.call("swing_held_item")
	# Keep damage accumulated within the persist window — a spam clicker (or
	# a player who walked away and came back) resumes where they left off.
	if _last_hit_ms < 0 \
			or Time.get_ticks_msec() - _last_hit_ms >= int(PROGRESS_PERSIST_SECONDS * 1000.0):
		_break_elapsed  = 0.0
		_break_progress = 0.0
	_breaking = true

func _cancel_breaking() -> void:
	if not _breaking:
		return
	_breaking        = false
	Global.clear_break_progress(self)
	_sprite.rotation = 0.0

# The held PICKAXE's mining tier, or -1 when none is in hand. Delegates to
# Global so every break path shares one definition (see Global.held_pickaxe_level).
func _held_pickaxe_level() -> int:
	return Global.held_pickaxe_level()

# Break on completion: unregister from the world, drop the contents, then
# drop the chest item itself.
func _do_break() -> void:
	_cancel_breaking()
	var world: Node = _world_ref if _world_ref != null else Global.world_node
	if world != null and world.has_method("unregister_block"):
		world.call("unregister_block", _world_cell)
	var drop_parent: Node = _world_ref if _world_ref != null else Global.world_node
	if drop_parent != null:
		for slot in slots:
			if slot == null: continue
			var drop: Node = ITEM_SCENE.instantiate()
			drop.call("set_item_data", (slot as Dictionary)["data"] as ItemData)
			drop.set("quantity", int((slot as Dictionary).get("quantity", 1)))
			drop_parent.add_child(drop)
			(drop as Node2D).global_position = global_position + Vector2(randf_range(-20, 20), randf_range(-20, 20))
		if item_data != null:
			var drop: Node = ITEM_SCENE.instantiate()
			drop.call("set_item_data", item_data)
			drop_parent.add_child(drop)
			(drop as Node2D).global_position = global_position + Vector2(0, -16)
	notify_contents_changed()
	queue_free()

func _on_gameplay_input_cancelled() -> void:
	if _breaking:
		_cancel_breaking()
