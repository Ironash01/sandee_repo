extends Node2D
class_name KnowledgeAltar
# ── Knowledge Altar (dungeon room object) ─────────────────────────
# Placed by the dungeon generator in the first (learning) room. On
# interaction it shows the KnowledgeEntry it was built with; closing the
# dialog records the entry in the player's encyclopedia and unlocks its
# keyword (Global.learn_entry).
#
# entry_file is the FILE NAME of the entry resource, e.g. "entry_1_lua.tres",
# set by the generator from the DungeonMissionData.entry_resource_file.
#
# Built entirely in code (no .tscn) like CavePortal — the dungeon generator
# instantiates it with .new(), so scene children would be lost anyway.

const TILE_SIZE: int = 32

const C_PANEL   := Color(0.08, 0.10, 0.20, 0.97)
const C_BORDER  := Color(0.35, 0.50, 0.90, 1.00)
const C_TITLE   := Color(0.80, 0.90, 1.00, 1.00)
const C_MUTED   := Color(0.60, 0.70, 0.90, 1.00)
const C_OK      := Color(0.20, 0.45, 0.20, 1.00)
const C_OVERLAY := Color(0.00, 0.00, 0.00, 0.55)
const SPRITE_TEXTURE: Texture2D = preload("res://sprites/dungeon/SandEE_alpha_dungeontilesets.png")

# ── Altar glow ─────────────────────────────────────────────────────
# A small PointLight2D hugging the altar body, slowly pulsing so it reads as a
# "blinking" beacon; the dungeon's WorldEnvironment glow makes it bloom at the
# top of each pulse. Scoped to the altar (tight radius), not a room-wide wash.
const GLOW_COLOR:      Color  = Color(1.0, 0.85, 0.60)
const GLOW_ENERGY_BASE: float = 1.4
const GLOW_ENERGY_AMP:  float = 0.5
const GLOW_BLINK_SPEED: float = 2.0  # sin(2t) → ~3.1s full cycle, slow
const GLOW_TEXTURE_SCALE: float = 0.35
const GLOW_TEXTURE_SIZE:   int   = 128

var entry_file: String = ""   # set by dungeon generator
var _player_nearby:  bool   = false
var _entry:          KnowledgeEntry = null
var _panel:          Control = null
var _glow:           PointLight2D = null
var _glow_time:      float = 0.0

func _ready() -> void:
	add_to_group("KnowledgeAltar")
	var tex := AtlasTexture.new()
	tex.atlas = SPRITE_TEXTURE
	tex.region = Rect2(288, 128, 32, 32)
	var sprite := Sprite2D.new()
	sprite.texture = tex
	add_child(sprite)

	add_child(_build_solid_body())
	_add_glow()

	var interact := Area2D.new()
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(TILE_SIZE, TILE_SIZE)
	shape.shape = rect
	interact.add_child(shape)
	interact.collision_layer = 0
	interact.collision_mask  = 1
	interact.body_entered.connect(_on_body_entered)
	interact.body_exited.connect(_on_body_exited)
	add_child(interact)
	call_deferred("_fix_z_index")

func _process(delta: float) -> void:
	if _glow != null:
		_glow_time += delta
		_glow.energy = GLOW_ENERGY_BASE + sin(_glow_time * GLOW_BLINK_SPEED) * GLOW_ENERGY_AMP

# Solid body so the player can't walk through the altar (it previously only had
# a pass-through proximity Area2D). Layer 1 matches the player's collision mask.
func _build_solid_body() -> StaticBody2D:
	var body := StaticBody2D.new()
	body.collision_layer = 1
	body.collision_mask  = 0
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(24, 24)
	shape.shape = rect
	body.add_child(shape)
	return body

func _add_glow() -> void:
	_glow = PointLight2D.new()
	_glow.texture       = _get_glow_texture()
	_glow.texture_scale = GLOW_TEXTURE_SCALE
	_glow.energy        = GLOW_ENERGY_BASE
	_glow.color         = GLOW_COLOR
	add_child(_glow)

static var _glow_texture: GradientTexture2D = null

static func _get_glow_texture() -> GradientTexture2D:
	if _glow_texture != null:
		return _glow_texture
	var gradient := Gradient.new()
	gradient.colors  = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0.7), Color(1, 1, 1, 0.0)])
	gradient.offsets = PackedFloat32Array([0.0, 0.5, 1.0])
	var tex := GradientTexture2D.new()
	tex.gradient  = gradient
	tex.fill      = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to   = Vector2(1.0, 0.5)
	tex.width     = GLOW_TEXTURE_SIZE
	tex.height    = GLOW_TEXTURE_SIZE
	_glow_texture = tex
	return _glow_texture

func _fix_z_index() -> void:
	z_index = int(global_position.y / TILE_SIZE)

func setup(mission: DungeonMissionData) -> void:
	if mission != null:
		entry_file = mission.entry_resource_file
		_entry = mission.entry()

func _on_body_entered(body: Node) -> void:
	if body.is_in_group("Player"):
		_player_nearby = true

func _on_body_exited(body: Node) -> void:
	if body.is_in_group("Player"):
		_player_nearby = false
		if _panel != null and _panel.visible:
			_panel.visible = false
			get_tree().paused = false

func _input(event: InputEvent) -> void:
	if not _player_nearby or Global.block_mode or Global.any_ui_open():
		return
	if _panel != null and _panel.visible:
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_show()

func _show() -> void:
	if _entry == null:
		_entry = Global.get_knowledge_entry_file(entry_file)
	if _panel == null:
		_panel = _build_panel()
	_panel.visible = true
	get_tree().paused = true

func _finish() -> void:
	if _panel != null:
		_panel.visible = false
	get_tree().paused = false
	Global.learn_entry(_entry)

func _build_panel() -> Control:
	var canvas := CanvasLayer.new()
	canvas.layer        = 15
	canvas.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(canvas)

	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.process_mode = Node.PROCESS_MODE_ALWAYS
	canvas.add_child(root)

	var overlay := ColorRect.new()
	overlay.color        = C_OVERLAY
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(overlay)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(480, 0)
	var ps := StyleBoxFlat.new()
	ps.bg_color = C_PANEL; ps.border_color = C_BORDER
	ps.set_border_width_all(2); ps.set_corner_radius_all(8)
	ps.content_margin_left = 24; ps.content_margin_right  = 24
	ps.content_margin_top  = 20; ps.content_margin_bottom = 20
	panel.add_theme_stylebox_override("panel", ps)
	center.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	panel.add_child(vbox)

	var hdr := HBoxContainer.new()
	hdr.add_theme_constant_override("separation", 8)
	vbox.add_child(hdr)
	var icon := Label.new()
	icon.text = "📖"
	icon.add_theme_font_size_override("font_size", 22)
	hdr.add_child(icon)
	var title := Label.new()
	var name_text: String = _entry.entry_name if _entry != null else "Knowledge"
	title.text = name_text
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_color_override("font_color", C_TITLE)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hdr.add_child(title)
	var lang := Label.new()
	lang.text = _entry.language.to_upper() if _entry != null else ""
	lang.add_theme_font_size_override("font_size", 11)
	lang.add_theme_color_override("font_color", C_MUTED)
	hdr.add_child(lang)

	var div := ColorRect.new()
	div.color = Color(0.25, 0.35, 0.60, 1.0); div.custom_minimum_size = Vector2(0, 1)
	vbox.add_child(div)

	var body := Label.new()
	body.text = _entry.description if _entry != null else "This knowledge has been recorded."
	body.add_theme_font_size_override("font_size", 13)
	body.add_theme_color_override("font_color", Color(0.85, 0.90, 1.00, 1.0))
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(body)

	var recorded := Label.new()
	recorded.text = "✔ Recorded in your Encyclopedia" + ((" — “%s” unlocked" % _entry.keyword) if _entry != null and not _entry.keyword.is_empty() else "")
	recorded.add_theme_font_size_override("font_size", 12)
	recorded.add_theme_color_override("font_color", Color(0.45, 0.90, 0.55, 1.0))
	recorded.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(recorded)

	var btn := Button.new()
	btn.text = "  Continue  "
	btn.custom_minimum_size = Vector2(140, 38)
	btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	btn.add_theme_font_size_override("font_size", 13)
	var es := StyleBoxFlat.new()
	es.bg_color = C_OK; es.border_color = C_BORDER
	es.set_border_width_all(1); es.set_corner_radius_all(4)
	btn.add_theme_stylebox_override("normal",  es)
	btn.add_theme_stylebox_override("hover",   es)
	btn.add_theme_color_override("font_color", Color(0.85, 1.0, 0.85, 1.0))
	btn.pressed.connect(_finish)
	vbox.add_child(btn)

	return root
