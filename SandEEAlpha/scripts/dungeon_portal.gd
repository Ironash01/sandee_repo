extends Node2D
# ── Dungeon Portal ────────────────────────────────────────────────
# Placed in the world by a "Dungeon Spawner" item.
# When the player walks near and left-clicks, it loads the assigned
# dungeon scene.  The dungeon index is set by setup() when placed.
#
# Dungeon mapping (matches the 5 difficulty-themed dungeons):
#   1 → dungeon1.tscn  (Easy   — Print, Variables, Booleans)
#   2 → dungeon2.tscn  (Easy   — Type Casting, Input, Concat)
#   3 → dungeon3.tscn  (Medium — If/Else, Logic Ops, Math, Strings)
#   4 → dungeon4.tscn  (Hard   — Loops, Functions, Random, Exception)
#   5 → dungeon5.tscn  (Hard   — Iterators, Classes, Inheritance, Dates)

const DUNGEON_SCENES: Array = [
	"",                                   # [0] unused — index from 1
	"res://scenes/dungeons/dungeon1.tscn",
	"res://scenes/dungeons/dungeon2.tscn",
	"res://scenes/dungeons/dungeon3.tscn",
	"res://scenes/dungeons/dungeon4.tscn",
	"res://scenes/dungeons/dungeon5.tscn",
]

const DUNGEON_NAMES: Array = [
	"",
	"Dungeon I  — The Print Room",
	"Dungeon II — The Variable Vault",
	"Dungeon III — Logic Labyrinth",
	"Dungeon IV — The Loop Forge",
	"Dungeon V  — The Class Citadel",
]

# ── Theme ─────────────────────────────────────────────────────────
const C_PANEL   := Color(0.08, 0.10, 0.20, 0.97)
const C_BORDER  := Color(0.40, 0.25, 0.70, 1.00)
const C_TITLE   := Color(0.85, 0.70, 1.00, 1.00)
const C_MUTED   := Color(0.60, 0.55, 0.80, 1.00)
const C_ENTER   := Color(0.20, 0.45, 0.20, 1.00)
const C_CANCEL  := Color(0.40, 0.20, 0.20, 1.00)
const C_OVERLAY := Color(0.00, 0.00, 0.00, 0.55)

# ── State ─────────────────────────────────────────────────────────
var dungeon_index:   int     = 1      # set by setup()
var _player_nearby:  bool    = false
var _world_cell:     Vector2i = Vector2i(-99999, -99999)
var _world_ref:      Node    = null
var _confirm_ui:     Control = null

@onready var _sprite:   Sprite2D = $Sprite2D
@onready var _interact: Area2D   = $InteractArea

# ── Called by world.gd when placed ───────────────────────────────
func setup(data: ItemData) -> void:
	if _sprite != null:
		var tex: Texture2D = data.placeable_sprite if data.placeable_sprite != null else data.icon
		_sprite.texture = tex
	# Read which dungeon this portal leads to from the item meta
	if data.has_meta("dungeon_index"):
		dungeon_index = int(data.get_meta("dungeon_index"))

func set_world_cell(cell: Vector2i, world: Node) -> void:
	_world_cell = cell
	_world_ref  = world

# ── Ready ─────────────────────────────────────────────────────────
func _ready() -> void:
	add_to_group("DungeonPortal")
	_interact.body_entered.connect(_on_body_entered)
	_interact.body_exited.connect(_on_body_exited)
	_build_confirm_ui()

# ── Input ─────────────────────────────────────────────────────────
func _input(event: InputEvent) -> void:
	if not _player_nearby or Global.block_mode:
		return
	if _confirm_ui != null and _confirm_ui.visible:
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_show_confirm()

# ── Proximity ─────────────────────────────────────────────────────
func _on_body_entered(body: Node) -> void:
	if body.is_in_group("Player"):
		_player_nearby = true

func _on_body_exited(body: Node) -> void:
	if body.is_in_group("Player"):
		_player_nearby = false
		if _confirm_ui != null:
			_confirm_ui.visible = false
			get_tree().paused   = false

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
		get_tree().paused   = true

func _cancel() -> void:
	if _confirm_ui != null:
		_confirm_ui.visible = false
		get_tree().paused   = false

func _enter_dungeon() -> void:
	if _confirm_ui != null:
		_confirm_ui.visible = false
		get_tree().paused   = false
	var idx: int = clamp(dungeon_index, 1, DUNGEON_SCENES.size() - 1)
	var path: String = DUNGEON_SCENES[idx]
	if ResourceLoader.exists(path):
		get_tree().change_scene_to_file(path)
	else:
		push_error("DungeonPortal: scene not found: " + path)
