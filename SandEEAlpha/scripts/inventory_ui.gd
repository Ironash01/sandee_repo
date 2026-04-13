extends Control

# ── Colors (dark navy theme, Terraria-inspired) ───────────────────
const C_OVERLAY  := Color(0.00, 0.00, 0.00, 0.50)
const C_PANEL    := Color(0.08, 0.10, 0.20, 0.97)
const C_BORDER   := Color(0.22, 0.32, 0.58, 1.00)
const C_TITLE    := Color(0.80, 0.90, 1.00, 1.00)
const C_DIVIDER  := Color(0.20, 0.28, 0.50, 1.00)
const C_TIP_BG   := Color(0.11, 0.15, 0.28, 1.00)
const C_MUTED    := Color(0.55, 0.65, 0.85, 1.00)
const C_EFFECT   := Color(0.55, 0.90, 0.60, 1.00)

const COLS       := 5
const SLOT_SCENE := preload("res://scenes/ui/InventorySlot.tscn")

# ── Node refs ─────────────────────────────────────────────────────
var _slots:      Array   = []
var _tip_root:   Control = null
var _tip_name:   Label
var _tip_type:   Label
var _tip_effect: Label
var _tip_qty:    Label

var _active_idx:     int     = -1
var _crafting_menu: Control = null

# ── Lifecycle ─────────────────────────────────────────────────────
var _center: CenterContainer

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_build()
	Global.Inventory_updated.connect(_refresh)
	Global.ui_scale_changed.connect(_on_ui_scale)
	_refresh()

func _on_ui_scale(s: float) -> void:
	if _center != null:
		_center.scale = Vector2(s, s)
	# Preload crafting menu into same CanvasLayer
	var cm_scene: PackedScene = load("res://scenes/ui/CraftingMenu.tscn") as PackedScene
	_crafting_menu = cm_scene.instantiate() as Control
	get_parent().add_child(_crafting_menu)

# ── UI construction ───────────────────────────────────────────────
func _build() -> void:
	# Dark screen overlay
	var overlay := ColorRect.new()
	overlay.color        = C_OVERLAY
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(overlay)

	# Center container — centers the panel on screen
	_center = CenterContainer.new()
	_center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_center)
	var center: CenterContainer = _center

	# Main panel
	var panel := PanelContainer.new()
	var ps    := StyleBoxFlat.new()
	ps.bg_color     = C_PANEL
	ps.border_color = C_BORDER
	ps.set_border_width_all(1)
	ps.set_corner_radius_all(6)
	ps.content_margin_left   = 18
	ps.content_margin_right  = 18
	ps.content_margin_top    = 14
	ps.content_margin_bottom = 18
	panel.add_theme_stylebox_override("panel", ps)
	center.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	panel.add_child(vbox)

	# ── Header ────────────────────────────────────────────────────
	var header := HBoxContainer.new()
	vbox.add_child(header)

	var title := Label.new()
	title.text = "INVENTORY"
	title.add_theme_font_size_override("font_size", 16)
	title.add_theme_color_override("font_color", C_TITLE)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)

	var craft_btn := Button.new()
	craft_btn.text = "✦ CRAFT"
	craft_btn.add_theme_font_size_override("font_size", 12)
	var cps := StyleBoxFlat.new()
	cps.bg_color     = Color(0.12, 0.28, 0.48, 1.0)
	cps.border_color = C_BORDER
	cps.set_border_width_all(1)
	cps.set_corner_radius_all(3)
	cps.content_margin_left   = 10
	cps.content_margin_right  = 10
	cps.content_margin_top    = 3
	cps.content_margin_bottom = 3
	craft_btn.add_theme_stylebox_override("normal", cps)
	craft_btn.add_theme_color_override("font_color", C_TITLE)
	craft_btn.pressed.connect(_open_crafting)
	header.add_child(craft_btn)

	var close_btn := Button.new()
	close_btn.text = "✕"
	close_btn.flat = true
	close_btn.add_theme_color_override("font_color", C_MUTED)
	close_btn.pressed.connect(_close)
	header.add_child(close_btn)

	# Divider
	var div := ColorRect.new()
	div.color                = C_DIVIDER
	div.custom_minimum_size  = Vector2(0, 1)
	vbox.add_child(div)

	# ── Body: grid + tooltip side by side ────────────────────────
	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 14)
	vbox.add_child(body)

	# Grid of 20 slots (5 × 4)
	var grid := GridContainer.new()
	grid.columns = COLS
	grid.add_theme_constant_override("h_separation", 5)
	grid.add_theme_constant_override("v_separation", 5)
	body.add_child(grid)

	for i in range(Global.INVENTORY_SIZE):
		var slot = SLOT_SCENE.instantiate()
		slot.slot_index = i
		slot.slot_clicked.connect(_on_slot_clicked)
		grid.add_child(slot)
		_slots.append(slot)

	# Tooltip panel (right column)
	_tip_root = _build_tooltip()
	body.add_child(_tip_root)
	_tip_root.visible = false

func _build_tooltip() -> Control:
	var root := Control.new()
	root.custom_minimum_size   = Vector2(160, 200)
	root.size_flags_horizontal = Control.SIZE_SHRINK_END
	root.size_flags_vertical   = Control.SIZE_SHRINK_BEGIN

	var panel := PanelContainer.new()
	var ps    := StyleBoxFlat.new()
	ps.bg_color     = C_TIP_BG
	ps.border_color = C_BORDER
	ps.set_border_width_all(1)
	ps.set_corner_radius_all(4)
	ps.content_margin_left   = 12
	ps.content_margin_right  = 12
	ps.content_margin_top    = 12
	ps.content_margin_bottom = 12
	panel.add_theme_stylebox_override("panel", ps)
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 5)
	panel.add_child(vbox)

	_tip_name = Label.new()
	_tip_name.add_theme_font_size_override("font_size", 14)
	_tip_name.add_theme_color_override("font_color", C_TITLE)
	_tip_name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(_tip_name)

	_tip_qty = Label.new()
	_tip_qty.add_theme_font_size_override("font_size", 11)
	_tip_qty.add_theme_color_override("font_color", C_MUTED)
	vbox.add_child(_tip_qty)

	_tip_type = Label.new()
	_tip_type.add_theme_font_size_override("font_size", 11)
	_tip_type.add_theme_color_override("font_color", C_MUTED)
	vbox.add_child(_tip_type)

	_tip_effect = Label.new()
	_tip_effect.add_theme_font_size_override("font_size", 11)
	_tip_effect.add_theme_color_override("font_color", C_EFFECT)
	vbox.add_child(_tip_effect)

	# Spacer
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 8)
	vbox.add_child(spacer)

	# Divider
	var div := ColorRect.new()
	div.color               = C_DIVIDER
	div.custom_minimum_size = Vector2(0, 1)
	vbox.add_child(div)

	var sp2 := Control.new()
	sp2.custom_minimum_size = Vector2(0, 6)
	vbox.add_child(sp2)

	# Drop button
	var drop_btn := Button.new()
	drop_btn.text = "DROP"
	var ds := StyleBoxFlat.new()
	ds.bg_color     = Color(0.55, 0.15, 0.15, 1.0)
	ds.border_color = Color(0.80, 0.25, 0.25, 1.0)
	ds.set_border_width_all(1)
	ds.set_corner_radius_all(3)
	ds.content_margin_top    = 6
	ds.content_margin_bottom = 6
	drop_btn.add_theme_stylebox_override("normal", ds)
	drop_btn.add_theme_color_override("font_color", Color(1.0, 0.85, 0.85, 1.0))
	drop_btn.pressed.connect(_on_drop_pressed)
	vbox.add_child(drop_btn)

	return root

# ── Refresh slots from Global.Inventory ──────────────────────────
func _refresh() -> void:
	for i in range(_slots.size()):
		var item = Global.Inventory[i] if i < Global.Inventory.size() else null
		if item != null:
			_slots[i].set_item(item)
		else:
			_slots[i].set_empty()
	# If active slot was cleared, hide tooltip
	if _active_idx >= 0:
		var still_there = _active_idx < Global.Inventory.size() \
				and Global.Inventory[_active_idx] != null
		if not still_there:
			_tip_root.visible = false
			_active_idx = -1

# ── Slot click → show tooltip ─────────────────────────────────────
func _on_slot_clicked(idx: int) -> void:
	var item = Global.Inventory[idx] if idx < Global.Inventory.size() else null
	if item == null:
		_tip_root.visible = false
		_active_idx = -1
		return
	_active_idx = idx
	var data: ItemData = item["data"] as ItemData
	_tip_name.text    = data.item_name
	_tip_qty.text     = "Qty: %d / %d" % [item["quantity"], Global.MAX_STACK]
	_tip_type.text    = data.item_type.capitalize()
	_tip_effect.text  = ("+ " + data.effect) if data.effect != "" else ""
	_tip_root.visible = true

# ── Drop ──────────────────────────────────────────────────────────
func _on_drop_pressed() -> void:
	if _active_idx < 0:
		return
	var item = Global.Inventory[_active_idx]
	if item == null:
		return
	if Global.player_node:
		var pos := (Global.player_node as Node2D).global_position + Vector2(0, 50)
		Global.drop_item(item, pos)
		Global.remove_item(item["data"] as ItemData)
	_tip_root.visible = false
	_active_idx = -1

# ── Open crafting ────────────────────────────────────────────────
func _open_crafting() -> void:
	if _crafting_menu != null:
		_close()
		_crafting_menu.call("show_menu")

# ── Close ─────────────────────────────────────────────────────────
func _close() -> void:
	# Toggle the parent CanvasLayer (same as pressing E)
	get_parent().visible = false
	if Global.pause_on_inventory:
		get_tree().paused = false
