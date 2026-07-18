extends Node2D
# ── Chest Block ───────────────────────────────────────────────────
# Placed in the world. Left-click (when build mode OFF + player nearby)
# opens an 8-slot inventory UI. Items can be transferred to/from the
# player's inventory by clicking slots.
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

func setup(data: ItemData) -> void:
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
		if (slot as Dictionary)["quantity"] < Global.MAX_STACK: return true
	return false

func deposit_item(item: Dictionary) -> bool:
	var data: ItemData = item["data"] as ItemData
	var qty:  int      = item["quantity"]
	# Stack onto existing slot
	for i in range(MAX_SLOTS):
		if slots[i] == null: continue
		if (slots[i] as Dictionary)["data"] == data:
			var space: int = Global.MAX_STACK - (slots[i] as Dictionary)["quantity"]
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

# ── Input ─────────────────────────────────────────────────────────
func _input(event: InputEvent) -> void:
	if Global.block_mode: return
	if not _player_nearby: return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if _ui != null:
			_ui.visible = not _ui.visible
			if _ui.visible:
				Global.open_ui()
			else:
				Global.close_ui()

# ── Build chest UI ────────────────────────────────────────────────
func _build_ui() -> void:
	var canvas := CanvasLayer.new()
	canvas.layer        = 11
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
	panel.custom_minimum_size = Vector2(420, 320)
	var ps := StyleBoxFlat.new()
	ps.bg_color = C_PANEL; ps.border_color = C_BORDER
	ps.set_border_width_all(1); ps.set_corner_radius_all(6)
	ps.content_margin_left = 18; ps.content_margin_right  = 18
	ps.content_margin_top  = 14; ps.content_margin_bottom = 18
	panel.add_theme_stylebox_override("panel", ps)
	center.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	panel.add_child(vbox)

	# Header
	var header := HBoxContainer.new()
	vbox.add_child(header)

	var icon_lbl := Label.new()
	icon_lbl.text = "📦"
	icon_lbl.add_theme_font_size_override("font_size", 18)
	header.add_child(icon_lbl)

	var title := Label.new()
	title.text = "  Chest"
	title.add_theme_font_size_override("font_size", 15)
	title.add_theme_color_override("font_color", C_TITLE)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)

	var close_btn := Button.new()
	close_btn.text = "✕"; close_btn.flat = true
	close_btn.add_theme_color_override("font_color", C_MUTED)
	close_btn.pressed.connect(_close_ui)
	header.add_child(close_btn)

	var div := ColorRect.new()
	div.color = C_DIVIDER; div.custom_minimum_size = Vector2(0, 1)
	vbox.add_child(div)

	# Slot grid (2 rows × 4 cols)
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	vbox.add_child(grid)

	_slot_buttons.clear()
	for i in range(MAX_SLOTS):
		var slot_panel := PanelContainer.new()
		slot_panel.custom_minimum_size = Vector2(80, 80)
		var ss := StyleBoxFlat.new()
		ss.bg_color = C_SLOT; ss.border_color = C_BORDER
		ss.set_border_width_all(1); ss.set_corner_radius_all(4)
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
		tex_rect.custom_minimum_size = Vector2(40, 40)
		tex_rect.expand_mode         = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
		tex_rect.stretch_mode        = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tex_rect.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		tex_rect.mouse_filter        = Control.MOUSE_FILTER_IGNORE
		vb.add_child(tex_rect)

		var qty_lbl := Label.new()
		qty_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		qty_lbl.add_theme_font_size_override("font_size", 11)
		qty_lbl.add_theme_color_override("font_color", C_TITLE)
		qty_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		vb.add_child(qty_lbl)

		_slot_buttons.append({"panel": slot_panel, "tex": tex_rect, "qty": qty_lbl, "btn": btn})

	var div2 := ColorRect.new()
	div2.color = C_DIVIDER; div2.custom_minimum_size = Vector2(0, 1)
	vbox.add_child(div2)

	var hint := Label.new()
	hint.text = "Left-click slot to transfer • Hotbar item transfers into empty slot"
	hint.add_theme_font_size_override("font_size", 10)
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

# ── Break (pickaxe) ───────────────────────────────────────────────
const HITS_TO_BREAK: int = 3
const ITEM_SCENE: PackedScene = preload("res://scenes/ui/InventoryItem.tscn")
var _hit_count: int = 0

func _try_hit() -> void:
	# Only breakable with pickaxe, only when build mode is off
	if Global.block_mode: return
	if not _player_nearby: return
	if not _player_has_pickaxe(): return
	_hit_count += 1
	if _hit_count >= HITS_TO_BREAK:
		_break()

func _player_has_pickaxe() -> bool:
	var selected = Global.get_hotbar_item()
	if _is_pickaxe(selected): return true
	return false

func _is_pickaxe(slot) -> bool:
	if slot == null: return false
	var data: ItemData = slot["data"] as ItemData
	return data != null and data.item_name.to_lower().contains("pickaxe")

func _break() -> void:
	if _world_ref != null and _world_ref.has_method("unregister_block"):
		_world_ref.call("unregister_block", _world_cell)
	# Drop all chest contents
	for slot in slots:
		if slot == null: continue
		var drop: Node = ITEM_SCENE.instantiate()
		drop.call("set_item_data", (slot as Dictionary)["data"] as ItemData)
		get_parent().add_child(drop)
		(drop as Node2D).global_position = global_position + Vector2(randf_range(-20,20), randf_range(-20,20))
	queue_free()
