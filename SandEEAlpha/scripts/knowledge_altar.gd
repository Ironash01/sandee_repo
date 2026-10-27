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
var _panel_scroll:   ScrollContainer = null
var _content_scroll:  ScrollContainer = null
var _touch_scroll_active: bool = false
var _touch_scroll_accum:  float = 0.0
# True while this popup holds a Global.open_ui() reference. A dedicated flag is
# required because _build_panel() leaves the panel visible by default, so
# `_panel.visible` can't be used to tell whether we already registered.
var _pause_registered: bool = false
var _glow:           PointLight2D = null
var _glow_time:      float = 0.0
# True when the panel was opened for an entry the player hadn't learned yet —
# drives the one-time keyword emphasis animation (see _build_panel).
var _is_first_time:  bool  = false
# The keyword Label inside the popup, kept so the animation can target it.
var _keyword_lbl:    Label = null

# ── Knowledge archive pagination ───────────────────────────────────
# The altar still teaches its own entry, but the popup also acts as a
# pageable archive of every knowledge entry this world has unlocked. The
# registry is Global.all_learned_entries(); no separate page list exists.
const ARCHIVE_PAGE_SIZE: int = 3
var _archive_entries: Array[KnowledgeEntry] = []
var _archive_box: VBoxContainer = null
var _archive_page_label: Label = null
var _archive_prev: Button = null
var _archive_next: Button = null
var _archive_page: int = 0

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
	interact.collision_mask  = 4   # player is on layer 4 (see player.tscn)
	interact.body_entered.connect(_on_body_entered)
	interact.body_exited.connect(_on_body_exited)
	add_child(interact)
	call_deferred("_fix_z_index")
	if not Global.ui_scale_changed.is_connected(_on_ui_scale):
		Global.ui_scale_changed.connect(_on_ui_scale)
	if not Global.knowledge_updated.is_connected(_on_knowledge_updated):
		Global.knowledge_updated.connect(_on_knowledge_updated)

# The popup is built at the current UI scale and cached — rebuild it in place
# (when open) so a responsive scale change applies live.
func _on_ui_scale(_s: float) -> void:
	if _panel == null:
		return
	var was_visible: bool = _panel.visible
	var canvas: Node = _panel.get_parent()
	if canvas != null:
		canvas.queue_free()
	_panel = null
	_panel_scroll = null
	_content_scroll = null
	_keyword_lbl = null
	if was_visible:
		_show()

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

static func _get_glow_texture() -> Texture2D:
	return Global.get_pixelated_light_texture(GLOW_TEXTURE_SIZE)

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
			_release_pause()

# The altar can be freed with the dungeon/world while its panel still holds an
# open_ui() reference (death, exit transition, quit-to-menu). Without this the
# refcount leaks and the next scene starts paused.
func _exit_tree() -> void:
	if _panel != null and is_instance_valid(_panel):
		_panel.visible = false
	_release_pause()

# Releases the open_ui() reference exactly once. Writing get_tree().paused =
# false directly (the old behaviour) resumed the game even when the pause menu
# or another UI still required it to stay paused.
func _release_pause() -> void:
	_touch_scroll_active = false
	_touch_scroll_accum = 0.0
	if _panel != null:
		Global.unregister_ui_back(_panel)
	if _pause_registered:
		_pause_registered = false
		Global.close_ui()

func _dismiss_panel() -> void:
	if _panel != null and _panel.visible:
		# Escape closes the encyclopedia WITHOUT marking the entry learned.
		_panel.visible = false
		_release_pause()

func _input(event: InputEvent) -> void:
	if _panel != null and _panel.visible:
		if _handle_touch_scroll(event):
			return
		if event.is_action_pressed("escape"):
			get_viewport().set_input_as_handled()
			if not Global.request_ui_back(event) and not Global.is_ui_back_event_consumed(event):
				_dismiss_panel()
			return
		if event.is_action_pressed("ui_left"):
			_change_archive_page(-1)
			get_viewport().set_input_as_handled()
			return
		if event.is_action_pressed("ui_right"):
			_change_archive_page(1)
			get_viewport().set_input_as_handled()
			return
		return
	if not _player_nearby or Global.block_mode \
			or Global.any_ui_open() or Global.pause_menu_open:
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_show()

## Native ScrollContainer only reacts to the mouse wheel; on a phone a finger
## drag over the body must scroll it. _input runs before GUI, so this works over
## labels/panels without stealing the initial tap from buttons.
func _handle_touch_scroll(event: InputEvent) -> bool:
	if _content_scroll == null or not is_instance_valid(_content_scroll):
		return false
	if event is InputEventScreenTouch:
		var t := event as InputEventScreenTouch
		if t.pressed:
			_touch_scroll_active = _content_scroll.get_global_rect().has_point(t.position) \
				and not _touch_over_button(t.position)
			_touch_scroll_accum = 0.0
		else:
			_touch_scroll_active = false
		return false
	if event is InputEventScreenDrag and _touch_scroll_active:
		var d := event as InputEventScreenDrag
		_touch_scroll_accum -= d.relative.y
		var step: int = int(_touch_scroll_accum)
		if step != 0:
			_content_scroll.scroll_vertical += step
			_touch_scroll_accum -= float(step)
		get_viewport().set_input_as_handled()
		return true
	return false

func _touch_over_button(pos: Vector2) -> bool:
	for b in _content_scroll.find_children("*", "Button", true, false):
		if (b as Control).get_global_rect().has_point(pos):
			return true
	return false

func _on_knowledge_updated() -> void:
	if _panel != null and _panel.visible:
		_refresh_archive()


func _show() -> void:
	if _entry == null:
		_entry = Global.get_knowledge_entry_file(entry_file)
	# Emphasis fires only the FIRST time this entry is offered — i.e. it isn't
	# recorded yet. Recomputed on every open, so closing the popup without
	# pressing Continue and reopening will animate again (nothing was learned).
	_is_first_time = _entry != null and not Global.has_learned_entry(_entry.id())
	if _panel == null:
		_panel = _build_panel()
	if not _pause_registered:
		_pause_registered = true
		# Register with the shared pause model so any_ui_open() is true while
		# this popup is up — that is what stops the player swinging / using
		# items and world nodes (blocks, trees, chests) reacting to clicks
		# THROUGH the popup, and it keeps the pause refcounted.
		Global.open_ui()
	_panel.visible = true
	Global.register_ui_back(_panel, Callable(self, "_dismiss_panel"))
	_refresh_archive()
	if _content_scroll != null:
		_content_scroll.scroll_vertical = 0
	if _panel_scroll != null:
		_panel_scroll.scroll_vertical = 0
	if _is_first_time and _keyword_lbl != null:
		# Defer one frame so the Label has its final laid-out size before the
		# pop sets its centre pivot (otherwise the pivot is (0,0)).
		_play_keyword_emphasis.call_deferred()

func _make_page_button(text: String, s: float) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.custom_minimum_size = Vector2(int(76 * s), int(28 * s))
	btn.add_theme_font_size_override("font_size", Global.ui_font_size(10))
	var sb := StyleBoxFlat.new()
	sb.bg_color = C_OK; sb.border_color = C_BORDER
	sb.set_border_width_all(int(1 * s)); sb.set_corner_radius_all(int(4 * s))
	btn.add_theme_stylebox_override("normal", sb)
	btn.add_theme_stylebox_override("hover", sb)
	btn.add_theme_color_override("font_color", C_TITLE)
	return btn


func _archive_page_count() -> int:
	if _archive_entries.is_empty():
		return 0
	return ceili(float(_archive_entries.size()) / float(ARCHIVE_PAGE_SIZE))


func _refresh_archive() -> void:
	if _archive_box == null or not is_instance_valid(_archive_box):
		return
	var s: float = Global.ui_scale
	for child in _archive_box.get_children():
		_archive_box.remove_child(child)
		child.queue_free()
	_archive_entries = Global.all_learned_entries()
	_archive_entries.sort_custom(func(a: KnowledgeEntry, b: KnowledgeEntry) -> bool:
		return a.entry_name.naturalnocasecmp_to(b.entry_name) < 0)
	var pages: int = _archive_page_count()
	_archive_page = clampi(_archive_page, 0, maxi(pages - 1, 0))
	if _archive_entries.is_empty():
		var none := Label.new()
		none.text = "No knowledge recorded yet."
		none.add_theme_font_size_override("font_size", Global.ui_font_size(10))
		none.add_theme_color_override("font_color", C_MUTED)
		none.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_archive_box.add_child(none)
		_archive_prev.visible = false
		_archive_page_label.visible = false
		_archive_next.visible = false
		return
	_archive_prev.visible = true
	_archive_page_label.visible = true
	_archive_next.visible = true
	var start: int = _archive_page * ARCHIVE_PAGE_SIZE
	var finish: int = mini(start + ARCHIVE_PAGE_SIZE, _archive_entries.size())
	for i in range(start, finish):
		var entry: KnowledgeEntry = _archive_entries[i]
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", int(6 * s))
		row.mouse_filter = Control.MOUSE_FILTER_PASS
		var name_lbl := Label.new()
		name_lbl.text = entry.entry_name
		name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_lbl.add_theme_font_size_override("font_size", Global.ui_font_size(11))
		name_lbl.add_theme_color_override("font_color", C_TITLE)
		name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(name_lbl)
		var lang_lbl := Label.new()
		lang_lbl.text = entry.language.to_upper()
		lang_lbl.add_theme_font_size_override("font_size", Global.ui_font_size(9))
		lang_lbl.add_theme_color_override("font_color", C_MUTED)
		lang_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(lang_lbl)
		_archive_box.add_child(row)
	_archive_page_label.text = "Page %d / %d" % [_archive_page + 1, pages]
	_archive_prev.disabled = _archive_page <= 0
	_archive_next.disabled = _archive_page >= pages - 1


func _change_archive_page(delta: int) -> void:
	var pages: int = _archive_page_count()
	if pages <= 0:
		return
	var next: int = clampi(_archive_page + delta, 0, pages - 1)
	if next == _archive_page:
		return
	_archive_page = next
	_refresh_archive()


func _play_keyword_emphasis() -> void:
	# Wait one frame so the freshly built Label has been laid out — the pop
	# needs a non-zero size to centre its pivot.
	if not is_inside_tree():
		return
	await get_tree().process_frame
	if _keyword_lbl != null and is_instance_valid(_keyword_lbl):
		Global.emphasize_keyword(_keyword_lbl, _keyword_lbl.get_theme_color("font_color"))

func _finish() -> void:
	if _panel != null and _panel.visible:
		_panel.visible = false
		_release_pause()
	Global.learn_entry(_entry)

func _build_panel() -> Control:
	var s: float = Global.ui_scale
	var canvas := CanvasLayer.new()
	canvas.layer        = 30
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

	var scroll := ScrollContainer.new()
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	Global.apply_safe_area(scroll)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	root.add_child(scroll)
	_panel_scroll = scroll

	var center := CenterContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	# Leave room for the vertical scrollbar; otherwise the ScrollContainer's
	# minimum width becomes content + scrollbar and pushes the modal a few pixels
	# past the right edge on phones.
	var content_size: Vector2 = Global.ui_content_rect().size
	center.custom_minimum_size = Vector2(
		maxf(1.0, content_size.x - 16.0 * s), content_size.y)
	scroll.add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Global.ui_fit_min_size(Vector2(480, 380))
	# Let touch drags that start on the panel padding reach the scroll roots;
	# the panel itself has no click action.
	panel.mouse_filter = Control.MOUSE_FILTER_PASS
	var ps := StyleBoxFlat.new()
	ps.bg_color = C_PANEL; ps.border_color = C_BORDER
	ps.set_border_width_all(int(2 * s)); ps.set_corner_radius_all(int(8 * s))
	ps.content_margin_left = int(24 * s); ps.content_margin_right  = int(24 * s)
	ps.content_margin_top  = int(20 * s); ps.content_margin_bottom = int(20 * s)
	panel.add_theme_stylebox_override("panel", ps)
	center.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", int(12 * s))
	vbox.mouse_filter = Control.MOUSE_FILTER_PASS
	panel.add_child(vbox)

	var hdr := HBoxContainer.new()
	hdr.add_theme_constant_override("separation", int(8 * s))
	vbox.add_child(hdr)
	var icon := Label.new()
	icon.text = "📖"
	icon.add_theme_font_size_override("font_size", Global.ui_font_size(22))
	hdr.add_child(icon)
	var title := Label.new()
	var name_text: String = _entry.entry_name if _entry != null else "Knowledge"
	title.text = name_text
	title.add_theme_font_size_override("font_size", Global.ui_font_size(18))
	title.add_theme_color_override("font_color", C_TITLE)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hdr.add_child(title)
	var lang := Label.new()
	lang.text = _entry.language.to_upper() if _entry != null else ""
	lang.add_theme_font_size_override("font_size", Global.ui_font_size(11))
	lang.add_theme_color_override("font_color", C_MUTED)
	hdr.add_child(lang)

	var div := ColorRect.new()
	div.color = Color(0.25, 0.35, 0.60, 1.0); div.custom_minimum_size = Vector2(0, int(1 * s))
	vbox.add_child(div)

	# The long encyclopedia body lives in its own scroll. The panel is capped to
	# the usable viewport, so the title and Continue button stay on screen and
	# only the body scrolls (mobile no longer shows a panel running off-screen).
	var content_scroll := ScrollContainer.new()
	content_scroll.name = "BodyScroll"
	content_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	content_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	content_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content_scroll.mouse_filter = Control.MOUSE_FILTER_STOP
	vbox.add_child(content_scroll)
	_content_scroll = content_scroll

	var content_vbox := VBoxContainer.new()
	content_vbox.add_theme_constant_override("separation", int(10 * s))
	content_vbox.mouse_filter = Control.MOUSE_FILTER_PASS
	content_scroll.add_child(content_vbox)

	var body := Label.new()
	body.text = _entry.description if _entry != null else "This knowledge has been recorded."
	body.add_theme_font_size_override("font_size", Global.ui_font_size(13))
	body.add_theme_color_override("font_color", Color(0.85, 0.90, 1.00, 1.0))
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content_vbox.add_child(body)

	# Pageable archive of every knowledge entry already unlocked in this world.
	# The current altar entry stays above; this list is read-only reference.
	var archive_title := Label.new()
	archive_title.text = "KNOWLEDGE ARCHIVE"
	archive_title.add_theme_font_size_override("font_size", Global.ui_font_size(10))
	archive_title.add_theme_color_override("font_color", C_MUTED)
	archive_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content_vbox.add_child(archive_title)
	_archive_box = VBoxContainer.new()
	_archive_box.add_theme_constant_override("separation", int(3 * s))
	_archive_box.mouse_filter = Control.MOUSE_FILTER_PASS
	content_vbox.add_child(_archive_box)
	var page_row := HBoxContainer.new()
	page_row.alignment = BoxContainer.ALIGNMENT_CENTER
	page_row.add_theme_constant_override("separation", int(8 * s))
	page_row.mouse_filter = Control.MOUSE_FILTER_PASS
	content_vbox.add_child(page_row)
	_archive_prev = _make_page_button("‹ Prev", s)
	_archive_prev.pressed.connect(func() -> void: _change_archive_page(-1))
	page_row.add_child(_archive_prev)
	_archive_page_label = Label.new()
	_archive_page_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_archive_page_label.add_theme_font_size_override("font_size", Global.ui_font_size(10))
	_archive_page_label.add_theme_color_override("font_color", C_MUTED)
	_archive_page_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	page_row.add_child(_archive_page_label)
	_archive_next = _make_page_button("Next ›", s)
	_archive_next.pressed.connect(func() -> void: _change_archive_page(1))
	page_row.add_child(_archive_next)
	_refresh_archive()

	# "✔ Recorded in your Encyclopedia — "print" unlocked". The keyword is a
	# SEPARATE Label so it can be animated on its own (first-time emphasis).
	# Laid out as a centred row: [lead] [keyword] [trail], all inline.
	var recorded_row := HBoxContainer.new()
	recorded_row.alignment = BoxContainer.ALIGNMENT_CENTER
	recorded_row.add_theme_constant_override("separation", int(4 * s))
	recorded_row.mouse_filter = Control.MOUSE_FILTER_PASS
	content_vbox.add_child(recorded_row)

	var lead := Label.new()
	lead.text = "✔ Recorded in your Encyclopedia"
	lead.add_theme_font_size_override("font_size", Global.ui_font_size(12))
	lead.add_theme_color_override("font_color", Color(0.45, 0.90, 0.55, 1.0))
	lead.mouse_filter = Control.MOUSE_FILTER_IGNORE
	recorded_row.add_child(lead)

	if _entry != null and not _entry.keyword.is_empty():
		var dash := Label.new()
		dash.text = "—"
		dash.add_theme_font_size_override("font_size", Global.ui_font_size(12))
		dash.add_theme_color_override("font_color", Color(0.45, 0.90, 0.55, 1.0))
		dash.mouse_filter = Control.MOUSE_FILTER_IGNORE
		recorded_row.add_child(dash)

		_keyword_lbl = Label.new()
		_keyword_lbl.text = "“%s”" % _entry.keyword
		_keyword_lbl.add_theme_font_size_override("font_size", Global.ui_font_size(14))
		# Base is a bright white-blue; the first-time emphasis flashes it gold
		# and pops its scale (Global.emphasize_keyword).
		_keyword_lbl.add_theme_color_override("font_color", Color(0.80, 0.95, 1.00, 1.0))
		_keyword_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		recorded_row.add_child(_keyword_lbl)

		var trail := Label.new()
		trail.text = "unlocked"
		trail.add_theme_font_size_override("font_size", Global.ui_font_size(12))
		trail.add_theme_color_override("font_color", Color(0.45, 0.90, 0.55, 1.0))
		trail.mouse_filter = Control.MOUSE_FILTER_IGNORE
		recorded_row.add_child(trail)
	else:
		_keyword_lbl = null

	var btn := Button.new()
	btn.text = "  Continue  "
	btn.custom_minimum_size = Vector2(int(140 * s), int(38 * s))
	btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	btn.add_theme_font_size_override("font_size", Global.ui_font_size(13))
	var es := StyleBoxFlat.new()
	es.bg_color = C_OK; es.border_color = C_BORDER
	es.set_border_width_all(int(1 * s)); es.set_corner_radius_all(int(4 * s))
	btn.add_theme_stylebox_override("normal",  es)
	btn.add_theme_stylebox_override("hover",   es)
	btn.add_theme_color_override("font_color", Color(0.85, 1.0, 0.85, 1.0))
	btn.pressed.connect(_finish)
	vbox.add_child(btn)

	return root
