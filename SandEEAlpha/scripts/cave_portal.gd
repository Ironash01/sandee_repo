extends Node2D
class_name CavePortal

# Cave entrance/exit marker — ENTER entrances (the overworld large-cave
# structures) follow the DungeonPortal pattern now: when the player is near
# the whole entrance, it gets a yellow outline and a left-click on it pops the
# same confirm dialog (Enter/Cancel) that dispatches to
# Global.game_node.enter_cave(self). The instant walk-in trigger only remains
# for the EXIT marker back inside the cave (cave_exit.png sprite + the same
# yellow highlight).
#
# The ENTER portal is invisible — it only supplies the proximity Area2D (sized
# to the whole entrance structure via set_interact_rect), the highlight and
# the confirm dialog. world.gd paints the actual cave structure sprite.
# Built entirely in code (Area2D + CollisionShape2D added in _ready()) rather
# than a .tscn, same convention dungeon_portal.gd uses for its confirm dialog.

enum Mode { ENTER, EXIT }

const TILE_SIZE:    int   = 32
const COLOR_ENTER:  Color = Color(0.16, 0.55, 0.25, 1.0)
const RETRIGGER_COOLDOWN: float = 1.0  # guards against re-firing the instant the player spawns back on top of it

# The EXIT marker's sprite (replaces the old orange square + "EXIT" text).
const CAVE_EXIT_TEX: Texture2D = preload("res://sprites/cave/cave_exit.png")

# ── Whole-entrance highlight ─────────────────────────────────────────
# Same yellow the dungeon portal uses for its door outline, but drawn around
# the ENTIRE entrance structure (interact_rect) whenever the player is close
# enough to click it. z_index = bottom row bucket + 1 keeps it above every
# structure row and above the player standing on the door row (the same
# convention dungeon_portal.gd's own door outline uses).
const C_DOOR_HIGHLIGHT: Color = Color(1.0, 0.9, 0.2, 1.0)
# The door arch in the cave sprites pokes a few px above the door tile, so the
# highlight is grown upward by this much — otherwise its top edge cuts straight
# through the arch and reads as misaligned.
const DOOR_HIGHLIGHT_GROW_UP: float = 4.0

# ── Confirm dialog theme (matches dungeon_portal.gd — "the same prompt") ─
const C_PANEL   := Color(0.08, 0.10, 0.20, 0.97)
const C_BORDER  := Color(0.40, 0.25, 0.70, 1.00)
const C_TITLE   := Color(0.85, 0.70, 1.00, 1.00)
const C_MUTED   := Color(0.60, 0.55, 0.80, 1.00)
const C_ENTER   := Color(0.20, 0.45, 0.20, 1.00)
const C_CANCEL  := Color(0.40, 0.20, 0.20, 1.00)
const C_OVERLAY := Color(0.00, 0.00, 0.00, 0.55)

var mode:      int = Mode.ENTER
var cave_seed: int = 0  # ENTER only — the seed this entrance's interior generates from
# "cave" (default) -> CaveWorld, "pixie" -> PixieCaveWorld. Set by world.gd
# when it spawns a pixie-cave entrance (the regular cave path leaves default).
var cave_type: String = "cave"

# World-space rect of the whole entrance structure (set by world.gd via
# set_interact_rect). Zero size means no structure was placed — the portal
# falls back to the old single-tile colored marker so the cave stays findable.
var interact_rect: Rect2 = Rect2()

# World-space rect of the cave's actual opening — the dark mouth cells
# (door_rect on the structure grid). This is what gets highlighted when the
# player is near, rather than the whole rock. Set by world.gd via
# set_door_rect; zero size falls back to highlighting the whole interact_rect.
var door_rect: Rect2 = Rect2()

# Optional hand-painted highlight: one world-space rect per cell marked on the
# structure's highlight_mask (see GeneratedStructure). When non-empty this
# takes priority over door_rect so the highlight can be any painted shape, not
# just a rectangle. Set by world.gd via set_highlight_cells.
var highlight_cells: Array[Rect2] = []

var _label_text: String  = "CAVE"
var _triggered:  bool    = false
var _player_nearby: bool = false
var _confirm_ui: Control = null
# Beckoning animation played on approach; the Enter prompt waits until it ends.
var _beaconing:  bool = false
const BEACON_DURATION: float = 0.6

var _area:  Area2D            = null
var _shape: CollisionShape2D  = null

func _ready() -> void:
	add_to_group("CavePortal")
	_label_text = "CAVE" if mode == Mode.ENTER else "EXIT"

	_area = Area2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(TILE_SIZE, TILE_SIZE)
	_shape = CollisionShape2D.new()
	_shape.shape = rect
	_area.add_child(_shape)
	_area.collision_layer = 0
	_area.collision_mask  = 4   # player is on layer 4 (see player.tscn)
	_area.body_entered.connect(_on_body_entered)
	_area.body_exited.connect(_on_body_exited)
	add_child(_area)

	if mode == Mode.EXIT:
		_add_exit_sprite()

	_build_confirm_ui()
	queue_redraw()
	if not Global.ui_scale_changed.is_connected(_on_ui_scale):
		Global.ui_scale_changed.connect(_on_ui_scale)

# Rebuild the confirm dialog at the new scale (when open) so a Small/Medium/
# Large change applies live rather than only on the next approach.
func _on_ui_scale(_s: float) -> void:
	if _confirm_ui == null:
		return
	var was_visible: bool = _confirm_ui.visible
	var canvas: Node = _confirm_ui.get_parent()
	if canvas != null:
		canvas.queue_free()
	_confirm_ui = null
	_build_confirm_ui()
	if _confirm_ui != null:
		_confirm_ui.visible = was_visible

# EXIT marker art — a sprite child so it renders on top of the cave floor
# while the node's _draw() supplies the yellow highlight around it.
func _add_exit_sprite() -> void:
	var s := Sprite2D.new()
	s.texture = CAVE_EXIT_TEX
	s.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(s)

# Called by world.gd once the portal is placed on its entrance structure —
# expands the proximity area to the whole structure and records the highlight
# rect. Must be called AFTER global_position is set (the shape offset is
# relative to this node).
func set_interact_rect(rect: Rect2) -> void:
	interact_rect = rect
	if _shape != null and rect.size != Vector2.ZERO:
		(_shape.shape as RectangleShape2D).size = rect.size
		_shape.position = rect.get_center() - global_position
	queue_redraw()

func set_door_rect(rect: Rect2) -> void:
	door_rect = rect
	queue_redraw()

func set_highlight_cells(rects: Array[Rect2]) -> void:
	highlight_cells = rects
	queue_redraw()

func _draw() -> void:
	var s: float = Global.ui_scale
	if mode == Mode.EXIT:
		z_index = int(global_position.y / TILE_SIZE) + 1
		# Yellow highlight around the exit sprite — same colour the cave
		# entrances use, so the two markers read as a matched pair. The exit
		# fires on walk-in, so it is always outlined rather than proximity-lit.
		var half := Vector2(CAVE_EXIT_TEX.get_width(), CAVE_EXIT_TEX.get_height()) * 0.5
		var r := Rect2(-half, half * 2.0)
		draw_rect(r, Color(C_DOOR_HIGHLIGHT.r, C_DOOR_HIGHLIGHT.g, C_DOOR_HIGHLIGHT.b, 0.18), true)
		draw_rect(r, C_DOOR_HIGHLIGHT, false, 2.0 * s)
		return

	# ENTER without a structure — fall back to the old colored marker so the
	# cave is still findable (shouldn't happen; see the resource load in world.gd).
	if interact_rect.size == Vector2.ZERO:
		z_index = int(global_position.y / TILE_SIZE)
		var half: float = TILE_SIZE / 2.0
		draw_rect(Rect2(-half, -half, TILE_SIZE, TILE_SIZE), COLOR_ENTER)
		draw_rect(Rect2(-half, -half, TILE_SIZE, TILE_SIZE), Color(0, 0, 0, 0.6), false, 2.0 * s)
		var font: Font  = ThemeDB.fallback_font
		var fsize: int  = int(8 * s)
		var text_size: Vector2 = font.get_string_size(_label_text, HORIZONTAL_ALIGNMENT_CENTER, -1, fsize)
		draw_string(font, Vector2(-text_size.x / 2.0, fsize / 2.0), _label_text,
			HORIZONTAL_ALIGNMENT_CENTER, -1, fsize, Color.WHITE)
		return

	# Recomputed here rather than _ready() — callers always set
	# global_position AFTER add_child() (which is when _ready() fires), so
	# computing it there would permanently bucket every portal at y=0.
	# Above the whole structure's bottom row (see constant comment).
	z_index = int((interact_rect.position.y + interact_rect.size.y) / TILE_SIZE) + 1
	if not _player_nearby:
		return
	# Highlight ONLY the entrance opening when the player is close enough to
	# click, not the whole rock — a faint fill so it visibly lights up, plus a
	# crisp outline (same yellow the dungeon portal uses for its door). Three
	# shapes, in priority order:
	#   1. highlight_cells — cells hand-painted on the structure's
	#      GeneratedStructure.highlight_mask (arbitrary blob/path shape).
	#   2. door_rect — the dark mouth cells (default, rectangle).
	#   3. the whole interact_rect — fallback when neither was supplied.
	if highlight_cells.size() > 0:
		_draw_cell_highlight(highlight_cells)
		return
	var hl_rect: Rect2 = door_rect if door_rect.size != Vector2.ZERO else interact_rect
	var local_rect := Rect2(
		hl_rect.position - global_position - Vector2(0.0, DOOR_HIGHLIGHT_GROW_UP),
		hl_rect.size + Vector2(0.0, DOOR_HIGHLIGHT_GROW_UP))
	draw_rect(local_rect, Color(C_DOOR_HIGHLIGHT.r, C_DOOR_HIGHLIGHT.g, C_DOOR_HIGHLIGHT.b, 0.18), true)
	draw_rect(local_rect, C_DOOR_HIGHLIGHT, false, 2.0 * s)

# Fills each painted cell and outlines ONLY the outer boundary of the painted
# blob (shared edges between two selected cells are skipped), so a hand-painted
# mask reads as one solid highlighted shape instead of a grid of boxes.
func _draw_cell_highlight(rects: Array[Rect2]) -> void:
	var line_w: float = 2.0 * Global.ui_scale
	var selected: Dictionary = {}  # Vector2i grid cell -> true
	var local_rects: Array[Rect2] = []
	for r in rects:
		var local := Rect2(r.position - global_position, r.size)
		local_rects.append(local)
		draw_rect(local, Color(C_DOOR_HIGHLIGHT.r, C_DOOR_HIGHLIGHT.g, C_DOOR_HIGHLIGHT.b, 0.18), true)
		selected[Vector2i(roundi(local.position.x / TILE_SIZE), roundi(local.position.y / TILE_SIZE))] = true
	# Walk each cell's four edges; draw only edges that border an unselected
	# cell (or the outside) so the outline hugs the blob's silhouette.
	for r in local_rects:
		var key := Vector2i(roundi(r.position.x / TILE_SIZE), roundi(r.position.y / TILE_SIZE))
		var p := r.position
		var s := r.size
		if not selected.has(key + Vector2i.UP):
			draw_line(p, p + Vector2(s.x, 0.0), C_DOOR_HIGHLIGHT, line_w)
		if not selected.has(key + Vector2i.DOWN):
			draw_line(p + Vector2(0.0, s.y), p + s, C_DOOR_HIGHLIGHT, line_w)
		if not selected.has(key + Vector2i.LEFT):
			draw_line(p, p + Vector2(0.0, s.y), C_DOOR_HIGHLIGHT, line_w)
		if not selected.has(key + Vector2i.RIGHT):
			draw_line(p + Vector2(s.x, 0.0), p + s, C_DOOR_HIGHLIGHT, line_w)

func _input(event: InputEvent) -> void:
	if mode != Mode.ENTER or not _player_nearby:
		return
	if Global.block_mode or Global.any_ui_open() or Global.pause_menu_open:
		return
	if _confirm_ui != null and _confirm_ui.visible:
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if _click_is_on_entrance():
			_show_confirm()

# True when the click landed anywhere on the entrance structure.
func _click_is_on_entrance() -> bool:
	if interact_rect.size == Vector2.ZERO:
		return false
	return interact_rect.has_point(get_global_mouse_position())

func _on_body_entered(body: Node) -> void:
	if not body.is_in_group("Player"):
		return
	if mode == Mode.EXIT:
		if _triggered:
			return
		_triggered = true
		_start_cooldown()
		if is_instance_valid(Global.game_node) and Global.game_node.has_method("exit_cave"):
			Global.game_node.call("exit_cave")
		return
	_player_nearby = true
	queue_redraw()
	# Beckoning pulse first; the Enter prompt is deferred to its end.
	if not Global.block_mode and not Global.any_ui_open() and not Global.pause_menu_open:
		_play_beacon()

func _on_body_exited(body: Node) -> void:
	if mode != Mode.ENTER or not body.is_in_group("Player"):
		return
	_player_nearby = false
	queue_redraw()
	if _confirm_ui != null and _confirm_ui.visible:
		_confirm_ui.visible = false
		Global.close_ui()

# A beckoning pulse expanding out of the entrance. The prompt only appears
# once this animation finishes, so walking up never instantly opens a dialog.
func _play_beacon() -> void:
	if _beaconing:
		return
	_beaconing = true
	var pulse := Sprite2D.new()
	pulse.texture = Global.get_smooth_light_texture(128)
	pulse.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	pulse.modulate = Color(0.75, 0.90, 0.70, 0.85)
	pulse.scale = Vector2(0.35, 0.35)
	pulse.z_index = 3
	add_child(pulse)
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(pulse, "scale", Vector2(1.7, 1.7), BEACON_DURATION) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(pulse, "modulate:a", 0.0, BEACON_DURATION)
	get_tree().create_timer(BEACON_DURATION).timeout.connect(_on_beacon_done.bind(pulse))

func _on_beacon_done(pulse: Node) -> void:
	if is_instance_valid(pulse):
		pulse.queue_free()
	_beaconing = false
	if _player_nearby \
			and not Global.block_mode and not Global.any_ui_open() and not Global.pause_menu_open:
		_show_confirm()

func _start_cooldown() -> void:
	var t := Timer.new()
	t.wait_time = RETRIGGER_COOLDOWN
	t.one_shot  = true
	t.timeout.connect(func() -> void:
		_triggered = false
		t.queue_free()
	)
	add_child(t)
	t.start()

# ── Confirm UI — same dialog as dungeon_portal.gd ─────────────────────
func _build_confirm_ui() -> void:
	var s: float = Global.ui_scale
	var canvas := CanvasLayer.new()
	canvas.layer        = 30
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
	panel.custom_minimum_size = Vector2(int(360 * s), int(180 * s))
	var ps := StyleBoxFlat.new()
	ps.bg_color = C_PANEL; ps.border_color = C_BORDER
	ps.set_border_width_all(int(2 * s)); ps.set_corner_radius_all(int(8 * s))
	ps.content_margin_left = int(20 * s); ps.content_margin_right  = int(20 * s)
	ps.content_margin_top  = int(16 * s); ps.content_margin_bottom = int(16 * s)
	panel.add_theme_stylebox_override("panel", ps)
	center.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", int(12 * s))
	panel.add_child(vbox)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", int(8 * s))
	vbox.add_child(header)
	var icon_lbl := Label.new()
	icon_lbl.text = "⛰"
	icon_lbl.add_theme_font_size_override("font_size", int(20 * s))
	header.add_child(icon_lbl)
	var title := Label.new()
	title.text = "Large Cave Entrance"
	title.add_theme_font_size_override("font_size", int(14 * s))
	title.add_theme_color_override("font_color", C_TITLE)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)

	var div := ColorRect.new()
	div.color = Color(0.30, 0.20, 0.55, 1.0); div.custom_minimum_size = Vector2(0, int(1 * s))
	vbox.add_child(div)

	var hint := Label.new()
	hint.text = "Enter the cave?"
	hint.add_theme_font_size_override("font_size", int(12 * s))
	hint.add_theme_color_override("font_color", C_MUTED)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(hint)

	var btn_row := HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", int(10 * s))
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(btn_row)

	var enter_btn := Button.new()
	enter_btn.text = "  Enter  "
	enter_btn.custom_minimum_size = Vector2(int(120 * s), int(36 * s))
	enter_btn.add_theme_font_size_override("font_size", int(13 * s))
	var es := StyleBoxFlat.new()
	es.bg_color = C_ENTER; es.border_color = C_BORDER
	es.set_border_width_all(int(1 * s)); es.set_corner_radius_all(int(4 * s))
	es.content_margin_top = int(6 * s); es.content_margin_bottom = int(6 * s)
	enter_btn.add_theme_stylebox_override("normal",  es)
	enter_btn.add_theme_stylebox_override("hover",   es)
	enter_btn.add_theme_color_override("font_color", Color(0.8, 1.0, 0.8, 1.0))
	enter_btn.pressed.connect(_enter_cave)
	btn_row.add_child(enter_btn)

	var cancel_btn := Button.new()
	cancel_btn.text = "  Cancel  "
	cancel_btn.custom_minimum_size = Vector2(int(100 * s), int(36 * s))
	cancel_btn.add_theme_font_size_override("font_size", int(13 * s))
	var cs := StyleBoxFlat.new()
	cs.bg_color = C_CANCEL; cs.border_color = C_BORDER
	cs.set_border_width_all(int(1 * s)); cs.set_corner_radius_all(int(4 * s))
	cs.content_margin_top = int(6 * s); cs.content_margin_bottom = int(6 * s)
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

func _enter_cave() -> void:
	if _confirm_ui != null:
		_confirm_ui.visible = false
		Global.close_ui()
	Global.complete_mission("enter_cave")
	if is_instance_valid(Global.game_node) and Global.game_node.has_method("enter_cave"):
		Global.game_node.call("enter_cave", self)
