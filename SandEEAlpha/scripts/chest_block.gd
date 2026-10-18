extends Node2D
# ── Chest Block ───────────────────────────────────────────────────
# Placed in the world. Left-click (when build mode OFF + player nearby)
# opens an 8-slot inventory UI. Items can be transferred to/from the
# player's inventory by clicking slots.
# Shift + left-click mines the chest off the wall (hold-to-break, same
# pickaxe-tier/block_level rules as placed blocks) instead of opening it.
# NPC can call has_space() and deposit_item() autonomously.

const MAX_SLOTS: int = 8
const SHADOW_TEXTURE: Texture2D = preload("res://sprites/shadow/shadow_blockbase.png")

# ── Theme (matches LuaEditorUI) ───────────────────────────────────
const C_PANEL   := Color(0.08, 0.10, 0.20, 0.97)
const C_BORDER  := Color(0.22, 0.32, 0.58, 1.00)
const C_TITLE   := Color(0.80, 0.90, 1.00, 1.00)
const C_MUTED   := Color(0.55, 0.65, 0.85, 1.00)
const C_DIVIDER := Color(0.20, 0.28, 0.50, 1.00)
const C_SLOT    := Color(0.05, 0.07, 0.16, 1.00)
const C_SLOT_H  := Color(0.12, 0.18, 0.36, 1.00)
const C_OVERLAY := Color(0.00, 0.00, 0.00, 0.50)

# Each slot: null or {data: ItemData, quantity: int}
var slots: Array = []

var _player_nearby: bool    = false
var _world_cell:    Vector2i = Vector2i(-99999, -99999)
var _world_ref:     Node    = null
var _ui:            Control = null
var _slot_buttons:  Array   = []
var item_data:      ItemData = null

@onready var _sprite:   Sprite2D = $Sprite2D
@onready var _interact: Area2D   = $InteractArea

func _ready() -> void:
	slots.resize(MAX_SLOTS)
	add_to_group("Chest")
	add_child(Global.make_shadow_sprite(SHADOW_TEXTURE, Vector2(0.0, 10.0), Vector2(0.8, 0.4), 0.35))
	_interact.body_entered.connect(_on_body_entered)
	_interact.body_exited.connect(_on_body_exited)
	_build_ui()
	Global.request_close_all_ui.connect(_close_ui)
	if not Global.ui_scale_changed.is_connected(_on_ui_scale):
		Global.ui_scale_changed.connect(_on_ui_scale)

# Rebuild the chest panel at the new scale, preserving whether it was open and
# its slot contents — so Small/Medium/Large applies live, not only on reopen.
func _on_ui_scale(_s: float) -> void:
	var was_visible: bool = _ui != null and _ui.visible
	if _ui != null:
		var canvas: Node = _ui.get_parent()
		if canvas != null:
			canvas.queue_free()
	_ui = null
	_slot_buttons.clear()
	_build_ui()
	if _ui != null:
		_refresh_ui()
		_ui.visible = was_visible

func setup(data: ItemData) -> void:
	item_data = data
	if _sprite != null:
		var tex: Texture2D = data.placeable_sprite if data.placeable_sprite != null else data.icon
		_sprite.texture = tex

func set_world_cell(cell: Vector2i, world: Node) -> void:
	_world_cell = cell
	_world_ref  = world

# ── NPC interface ─────────────────────────────────────────────────
func has_space() -> bool:
	for slot in slots:
		if slot == null: return true
		var data: ItemData = (slot as Dictionary)["data"] as ItemData
		var limit: int = data.max_stack_size if data != null and data.max_stack_size > 0 else Global.MAX_STACK
		if (slot as Dictionary)["quantity"] < limit: return true
	return false

func deposit_item(item: Dictionary) -> bool:
	var data: ItemData = item["data"] as ItemData
	var qty:  int      = item["quantity"]
	var limit: int = data.max_stack_size if data != null and data.max_stack_size > 0 else Global.MAX_STACK
	# Stack onto existing slot
	for i in range(MAX_SLOTS):
		if slots[i] == null: continue
		if (slots[i] as Dictionary)["data"] == data:
			var space: int = limit - (slots[i] as Dictionary)["quantity"]
			var add:   int = min(qty, space)
			(slots[i] as Dictionary)["quantity"] += add
			qty -= add
			if qty <= 0:
				_refresh_ui()
				return true
	# Empty slot
	for i in range(MAX_SLOTS):
		if slots[i] == null:
			slots[i] = {"data": data, "quantity": qty}
			_refresh_ui()
			return true
	return false  # full

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
	return quantity - remaining

# ── Input ─────────────────────────────────────────────────────────
func _input(event: InputEvent) -> void:
	if Global.block_mode: return
	if not _player_nearby: return
	if Global.pause_menu_open: return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		# Shift + left-click: mine the chest off the wall (respects pickaxe
		# tier + block_level break time) instead of toggling its UI.
		if Input.is_key_pressed(KEY_SHIFT):
			if event.pressed:
				_try_start_breaking()
				if _breaking:
					_add_break_progress(CLICK_BREAK_SECONDS)
			else:
				_cancel_breaking()
			get_viewport().set_input_as_handled()
			return
		if event.pressed:
			if _ui != null:
				_ui.visible = not _ui.visible
				if _ui.visible:
					Global.open_ui()
				else:
					Global.close_ui()

# ── Build chest UI ────────────────────────────────────────────────
func _build_ui() -> void:
	var s: float = Global.ui_scale
	var canvas := CanvasLayer.new()
	# Layer 2: below the hotbar (10) so the hotbar stays bright/on top, and above
	# the background HUD backdrop (1) so this panel's dim overlay covers it.
	canvas.layer        = 2
	canvas.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(canvas)

	_ui = Control.new()
	_ui.set_anchors_preset(Control.PRESET_FULL_RECT)
	_ui.process_mode = Node.PROCESS_MODE_ALWAYS
	_ui.visible      = false
	canvas.add_child(_ui)

	# Dim overlay
	var overlay := ColorRect.new()
	overlay.color        = C_OVERLAY
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_ui.add_child(overlay)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_ui.add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(int(420 * s), int(320 * s))
	var ps := StyleBoxFlat.new()
	ps.bg_color = C_PANEL; ps.border_color = C_BORDER
	ps.set_border_width_all(int(1 * s)); ps.set_corner_radius_all(int(6 * s))
	ps.content_margin_left = int(18 * s); ps.content_margin_right  = int(18 * s)
	ps.content_margin_top  = int(14 * s); ps.content_margin_bottom = int(18 * s)
	panel.add_theme_stylebox_override("panel", ps)
	center.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", int(12 * s))
	panel.add_child(vbox)

	# Header
	var header := HBoxContainer.new()
	vbox.add_child(header)

	var icon_lbl := Label.new()
	icon_lbl.text = "📦"
	icon_lbl.add_theme_font_size_override("font_size", int(18 * s))
	header.add_child(icon_lbl)

	var title := Label.new()
	title.text = "  Chest"
	title.add_theme_font_size_override("font_size", int(15 * s))
	title.add_theme_color_override("font_color", C_TITLE)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)

	var close_btn := Button.new()
	close_btn.text = "✕"; close_btn.flat = true
	close_btn.add_theme_color_override("font_color", C_MUTED)
	close_btn.pressed.connect(_close_ui)
	header.add_child(close_btn)

	var div := ColorRect.new()
	div.color = C_DIVIDER; div.custom_minimum_size = Vector2(0, int(1 * s))
	vbox.add_child(div)

	# Slot grid (2 rows × 4 cols)
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", int(8 * s))
	grid.add_theme_constant_override("v_separation", int(8 * s))
	vbox.add_child(grid)

	_slot_buttons.clear()
	for i in range(MAX_SLOTS):
		var slot_panel := PanelContainer.new()
		slot_panel.custom_minimum_size = Vector2(int(80 * s), int(80 * s))
		var ss := StyleBoxFlat.new()
		ss.bg_color = C_SLOT; ss.border_color = C_BORDER
		ss.set_border_width_all(int(1 * s)); ss.set_corner_radius_all(int(4 * s))
		slot_panel.add_theme_stylebox_override("panel", ss)
		grid.add_child(slot_panel)

		var btn := Button.new()
		btn.flat = true
		btn.set_anchors_preset(Control.PRESET_FULL_RECT)
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.size_flags_vertical   = Control.SIZE_EXPAND_FILL
		btn.pressed.connect(_on_slot_pressed.bind(i))
		slot_panel.add_child(btn)

		var vb := VBoxContainer.new()
		vb.set_anchors_preset(Control.PRESET_FULL_RECT)
		vb.alignment = BoxContainer.ALIGNMENT_CENTER
		vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
		slot_panel.add_child(vb)

		var tex_rect := TextureRect.new()
		tex_rect.custom_minimum_size = Vector2(int(40 * s), int(40 * s))
		tex_rect.expand_mode         = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
		tex_rect.stretch_mode        = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tex_rect.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		tex_rect.mouse_filter        = Control.MOUSE_FILTER_IGNORE
		vb.add_child(tex_rect)

		var qty_lbl := Label.new()
		qty_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		qty_lbl.add_theme_font_size_override("font_size", int(11 * s))
		qty_lbl.add_theme_color_override("font_color", C_TITLE)
		qty_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		vb.add_child(qty_lbl)

		_slot_buttons.append({"panel": slot_panel, "tex": tex_rect, "qty": qty_lbl, "btn": btn})

	var div2 := ColorRect.new()
	div2.color = C_DIVIDER; div2.custom_minimum_size = Vector2(0, int(1 * s))
	vbox.add_child(div2)

	var hint := Label.new()
	hint.text = "Left-click slot to transfer • Hotbar item transfers into empty slot"
	hint.add_theme_font_size_override("font_size", int(10 * s))
	hint.add_theme_color_override("font_color", C_MUTED)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(hint)

# ── Slot interaction ──────────────────────────────────────────────
func _on_slot_pressed(index: int) -> void:
	var slot = slots[index]
	if slot != null:
		# Transfer from chest to player inventory
		var moved: bool = Global.add_item(slot as Dictionary)
		if moved:
			slots[index] = null
	else:
		# Transfer from player hotbar into chest
		var held = Global.get_hotbar_item()
		if held != null:
			slots[index] = {"data": held["data"], "quantity": held["quantity"]}
			Global.remove_item(held["data"] as ItemData)
	_refresh_ui()

func _refresh_ui() -> void:
	if _slot_buttons.is_empty(): return
	for i in range(MAX_SLOTS):
		var entry: Dictionary = _slot_buttons[i] as Dictionary
		var tex_rect: TextureRect = entry["tex"] as TextureRect
		var qty_lbl:  Label       = entry["qty"] as Label
		var slot = slots[i]
		if slot == null:
			tex_rect.texture = null
			qty_lbl.text     = ""
		else:
			var data: ItemData = (slot as Dictionary)["data"] as ItemData
			tex_rect.texture   = data.icon
			var qty: int       = (slot as Dictionary)["quantity"]
			qty_lbl.text       = "" if qty <= 1 else str(qty)

func _close_ui() -> void:
	if _ui != null and _ui.visible:
		_ui.visible = false
		Global.close_ui()

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
	_tick_progress_expiry()
	if not _breaking:
		return
	if not _player_nearby \
			or not Input.is_key_pressed(KEY_SHIFT) \
			or not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		_cancel_breaking()
		return
	_break_elapsed  = minf(_break_elapsed + delta, _break_duration)
	_break_progress = _break_elapsed / _break_duration if _break_duration > 0.0 else 1.0
	_tick_wobble()
	queue_redraw()
	if _break_elapsed >= _break_duration:
		_do_break()

func _draw() -> void:
	if _break_progress <= 0.0:
		return
	Global.draw_break_bar(self, _break_progress)

# Adds damage (in seconds of break work) from a held frame's delta or a
# fresh shift-click's flat CLICK_BREAK_SECONDS, then breaks when full.
func _add_break_progress(seconds: float) -> void:
	_break_elapsed  = minf(_break_elapsed + seconds, _break_duration)
	_break_progress = _break_elapsed / _break_duration if _break_duration > 0.0 else 1.0
	_last_hit_ms    = Time.get_ticks_msec()
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
			drop_parent.add_child(drop)
			(drop as Node2D).global_position = global_position + Vector2(randf_range(-20, 20), randf_range(-20, 20))
		if item_data != null:
			var drop: Node = ITEM_SCENE.instantiate()
			drop.call("set_item_data", item_data)
			drop_parent.add_child(drop)
			(drop as Node2D).global_position = global_position + Vector2(0, -16)
	queue_free()
