extends Node2D
# ── Dungeon Portal (world entrance) ─────────────────────────────────
# Spawned by world.gd when the player accepts a dungeon mission (see
# world.gd's _spawn_dungeon_entrance) — NOT placed by the player anymore
# (the old "Dungeon Spawner" placeable-item flow was removed).
# When the player is near the door and left-clicks ON the door sprite, it
# shows a confirm dialog that dispatches to
# Global.game_node.enter_dungeon(dungeon_index) — the same parent-scene
# pattern CavePortal uses, instead of the old change_scene_to_file (which
# destroyed Player/UI — see game_instance.gd). Walking near alone no longer
# opens it; the click has to land on the door itself.
#
# Dungeon mapping (matches the currently-shipped missions, backed by
# DungeonMissionData .tres files):
#   1 → Print, Variables, Booleans
#   2 → Type Casting, Input, Concat
const DUNGEON_NAMES: Array = [
	"",
	"Dungeon I  — The Print Room",
	"Dungeon II — The Variable Vault",
]

# ── Theme ─────────────────────────────────────────────────────────
const C_PANEL   := Color(0.08, 0.10, 0.20, 0.97)
const C_BORDER  := Color(0.40, 0.25, 0.70, 1.00)
const C_TITLE   := Color(0.85, 0.70, 1.00, 1.00)
const C_MUTED   := Color(0.60, 0.55, 0.80, 1.00)
const C_ENTER   := Color(0.20, 0.45, 0.20, 1.00)
const C_CANCEL  := Color(0.40, 0.20, 0.20, 1.00)
const C_OVERLAY := Color(0.00, 0.00, 0.00, 0.55)

# ── Door hitbox ────────────────────────────────────────────────────
# The confirm only pops on a left-click that lands ON the door. This node's
# origin sits on the entrance structure's door tile (see world.gd's
# _place_dungeon_entrance_structure), so the door is a small rect centered
# at the origin — roughly the visible doorway (the middle-bottom tile of the
# sprite) plus a little click slack. A click anywhere else (the surrounding
# wall sprite, the ground nearby) does nothing.
const DOOR_HITBOX := Rect2(-18.0, -20.0, 36.0, 40.0)  # px, centered on the door tile

# ── Door highlight ─────────────────────────────────────────────────
# A yellow outline drawn around the door tile whenever the player is close
# enough to click it (same _player_nearby condition the click handler
# checks), so the clickable block reads as clickable. Drawn here in _draw()
# like cave_portal.gd's entrance marker, at z_index = tile bucket + 1 so the
# outline always sits on top of the entrance sprites and the player.
const TILE_SIZE:         int   = 32
const C_DOOR_HIGHLIGHT:  Color = Color(1.0, 0.9, 0.2, 1.0)

# ── State ─────────────────────────────────────────────────────────
var dungeon_index: int = 1      # set by world.gd at spawn
var _player_nearby:  bool = false
var _confirm_ui:     Control = null

@onready var _interact: Area2D   = $InteractArea

# ── Ready ─────────────────────────────────────────────────────────
func _ready() -> void:
	add_to_group("DungeonPortal")
	_interact.body_entered.connect(_on_body_entered)
	_interact.body_exited.connect(_on_body_exited)
	_build_confirm_ui()
	queue_redraw()

# ── Draw ───────────────────────────────────────────────────────────
# Recomputed here rather than _ready() — callers set global_position AFTER
# add_child() (which is when _ready() fires), so computing it there would
# permanently bucket every portal at y=0 (same caveat cave_portal.gd notes).
func _draw() -> void:
	z_index = int(global_position.y / TILE_SIZE) + 1
	if _player_nearby:
		var half: float = TILE_SIZE * 0.5
		draw_rect(Rect2(-half, -half, TILE_SIZE, TILE_SIZE), C_DOOR_HIGHLIGHT, false, 2.0)

# ── Input ─────────────────────────────────────────────────────────
func _input(event: InputEvent) -> void:
	if not _player_nearby or Global.block_mode or Global.any_ui_open() or Global.pause_menu_open:
		return
	if _confirm_ui != null and _confirm_ui.visible:
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if _click_is_on_door():
			_show_confirm()

# True when the click position is on the door sprite — the portal's origin
# sits on the structure's door tile, so the mouse just has to land inside
# DOOR_HITBOX around it.
func _click_is_on_door() -> bool:
	return DOOR_HITBOX.has_point(to_local(get_global_mouse_position()))

# ── Proximity ─────────────────────────────────────────────────────
func _on_body_entered(body: Node) -> void:
	if body.is_in_group("Player"):
		_player_nearby = true
		queue_redraw()

func _on_body_exited(body: Node) -> void:
	if body.is_in_group("Player"):
		_player_nearby = false
		queue_redraw()
		if _confirm_ui != null and _confirm_ui.visible:
			_confirm_ui.visible = false
			Global.close_ui()

# ── Confirm UI ────────────────────────────────────────────────────
func _build_confirm_ui() -> void:
	var canvas := CanvasLayer.new()
	canvas.layer        = 15
	canvas.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(canvas)

	_confirm_ui = Control.new()
	_confirm_ui.set_anchors_preset(Control.PRESET_FULL_RECT)
	_confirm_ui.process_mode = Node.PROCESS_MODE_ALWAYS
	_confirm_ui.visible      = false
	canvas.add_child(_confirm_ui)

	var overlay := ColorRect.new()
	overlay.color        = C_OVERLAY
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_confirm_ui.add_child(overlay)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_confirm_ui.add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(360, 180)
	var ps := StyleBoxFlat.new()
	ps.bg_color = C_PANEL; ps.border_color = C_BORDER
	ps.set_border_width_all(2); ps.set_corner_radius_all(8)
	ps.content_margin_left = 20; ps.content_margin_right  = 20
	ps.content_margin_top  = 16; ps.content_margin_bottom = 16
	panel.add_theme_stylebox_override("panel", ps)
	center.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	panel.add_child(vbox)

	# Icon + title row
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 8)
	vbox.add_child(header)
	var icon_lbl := Label.new()
	icon_lbl.text = "🌀"
	icon_lbl.add_theme_font_size_override("font_size", 20)
	header.add_child(icon_lbl)
	var title := Label.new()
	var dname: String = DUNGEON_NAMES[dungeon_index] if dungeon_index < DUNGEON_NAMES.size() else "Unknown Dungeon"
	title.text = dname
	title.add_theme_font_size_override("font_size", 14)
	title.add_theme_color_override("font_color", C_TITLE)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)

	var div := ColorRect.new()
	div.color = Color(0.30, 0.20, 0.55, 1.0); div.custom_minimum_size = Vector2(0, 1)
	vbox.add_child(div)

	var hint := Label.new()
	hint.text = "Enter the dungeon?"
	hint.add_theme_font_size_override("font_size", 12)
	hint.add_theme_color_override("font_color", C_MUTED)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(hint)

	var btn_row := HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 10)
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(btn_row)

	var enter_btn := Button.new()
	enter_btn.text = "  Enter  "
	enter_btn.custom_minimum_size = Vector2(120, 36)
	enter_btn.add_theme_font_size_override("font_size", 13)
	var es := StyleBoxFlat.new()
	es.bg_color = C_ENTER; es.border_color = C_BORDER
	es.set_border_width_all(1); es.set_corner_radius_all(4)
	es.content_margin_top = 6; es.content_margin_bottom = 6
	enter_btn.add_theme_stylebox_override("normal",  es)
	enter_btn.add_theme_stylebox_override("hover",   es)
	enter_btn.add_theme_color_override("font_color", Color(0.8, 1.0, 0.8, 1.0))
	enter_btn.pressed.connect(_enter_dungeon)
	btn_row.add_child(enter_btn)

	var cancel_btn := Button.new()
	cancel_btn.text = "  Cancel  "
	cancel_btn.custom_minimum_size = Vector2(100, 36)
	cancel_btn.add_theme_font_size_override("font_size", 13)
	var cs := StyleBoxFlat.new()
	cs.bg_color = C_CANCEL; cs.border_color = C_BORDER
	cs.set_border_width_all(1); cs.set_corner_radius_all(4)
	cs.content_margin_top = 6; cs.content_margin_bottom = 6
	cancel_btn.add_theme_stylebox_override("normal",  cs)
	cancel_btn.add_theme_stylebox_override("hover",   cs)
	cancel_btn.add_theme_color_override("font_color", Color(1.0, 0.8, 0.8, 1.0))
	cancel_btn.pressed.connect(_cancel)
	btn_row.add_child(cancel_btn)

func _show_confirm() -> void:
	if _confirm_ui != null:
		_confirm_ui.visible = true
		Global.open_ui()

func _cancel() -> void:
	if _confirm_ui != null:
		_confirm_ui.visible = false
		Global.close_ui()

func _enter_dungeon() -> void:
	if _confirm_ui != null:
		_confirm_ui.visible = false
		Global.close_ui()
	if is_instance_valid(Global.game_node) and Global.game_node.has_method("enter_dungeon"):
		Global.game_node.call("enter_dungeon", dungeon_index)
	else:
		push_error("DungeonPortal: game node has no enter_dungeon(%d)" % dungeon_index)
