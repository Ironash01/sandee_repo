extends Control

const C_BG      := Color(0.04, 0.06, 0.12, 1.00)
const C_PANEL   := Color(0.08, 0.10, 0.20, 0.97)
const C_BORDER  := Color(0.22, 0.32, 0.58, 1.00)
const C_TITLE   := Color(0.80, 0.90, 1.00, 1.00)
const C_MUTED   := Color(0.55, 0.65, 0.85, 1.00)
const C_OVERLAY := Color(0.00, 0.00, 0.00, 0.60)
const C_DIVIDER := Color(0.20, 0.28, 0.50, 1.00)
const C_BTN_H   := Color(0.12, 0.18, 0.36, 1.00)

# ── Flavor text ───────────────────────────────────────────────────
# Loaded from a dedicated .tres so adding a line never touches this script.
const FLAVOR_TEXT_PATH: String = "res://resources/ui/flavor_text.tres"
const FLAVOR_FALLBACK:  String = "Also try mining!"

# ── Credits (Settings -> Credits) ─────────────────────────────────
# [name, role] pairs, kept in the exact wording/order they must be shown in.
const CREDITS: Array = [
	["Glenn Marco B. Accad",      "Project Manager and Developer, Sub Artist"],
	["Jose Mari Christian Tayag", "Lead Developer, Lead Artist"],
	["Jefferson G. Mamamuag",     "System Analyst"],
	["Adrian V. Gallano",         "Quality Assurance"],
	["Norvin Shaq F. Lintag",     "Special thanks and Thesis Adviser"],
]

# The exact bottom-right project label (wording/capitalisation preserved).
const PROJECT_LABEL: String = "SandEE Developers of BSCS701"

var _worlds_overlay:   Control = null
var _settings_overlay: Control = null
var _credits_overlay:  Control = null
var _confirm_overlay:  Control = null
var _bg_holder:        Control = null
var _panorama:         Node    = null
var _worlds_list:      VBoxContainer = null
var _create_name:      LineEdit = null
var _create_btn:       Button   = null
var _create_error:     Label    = null
var _confirm_label:    Label    = null
var _confirm_cb:       Callable = Callable()

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	# Returning to the title must not inherit the gameplay scene's pause/UI state
	# (e.g. quitting to menu while a UI was open), or the menu would be frozen.
	Global.reset_pause_state()
	# Panorama helper: its own node so generating the preview world can run on a
	# LATER frame and never delay the menu appearing.
	_panorama = load("res://scripts/title_panorama.gd").new()
	_panorama.name = "TitlePanorama"
	add_child(_panorama)
	_panorama.connect("panorama_ready", _on_panorama_ready)
	_build_all()
	if not Global.ui_scale_changed.is_connected(_on_ui_scale):
		Global.ui_scale_changed.connect(_on_ui_scale)
	# Reuse the cached panorama; only regenerate when it is missing/invalid.
	_panorama.call("ensure_panorama")

func _build_all() -> void:
	_build_background()
	_build_main_ui()
	_build_corner_labels()
	_build_worlds_overlay()
	_build_settings_overlay()
	_build_credits_overlay()
	_build_confirm_overlay()

# Rebuild the whole menu at the new scale so a Small/Medium/Large change applies
# live; open overlays keep their visibility.
func _on_ui_scale(_s: float) -> void:
	var worlds_vis:  bool = _worlds_overlay != null and _worlds_overlay.visible
	var set_vis:     bool = _settings_overlay != null and _settings_overlay.visible
	var credits_vis: bool = _credits_overlay != null and _credits_overlay.visible
	var conf_vis:    bool = _confirm_overlay != null and _confirm_overlay.visible
	for child in get_children():
		child.queue_free()
	_stop_pan()
	_worlds_overlay   = null
	_settings_overlay = null
	_credits_overlay  = null
	_confirm_overlay  = null
	_bg_holder        = null
	_bg_clip          = null
	_bg_rect          = null
	_panorama         = null
	if not is_inside_tree():
		return
	await get_tree().process_frame
	_build_all()
	if _worlds_overlay != null:
		_worlds_overlay.visible = worlds_vis
	if _settings_overlay != null:
		_settings_overlay.visible = set_vis
	if _credits_overlay != null:
		_credits_overlay.visible = credits_vis
	if _confirm_overlay != null:
		_confirm_overlay.visible = conf_vis

# ── Background (deterministic world panorama, else the plain colour) ──
# The panorama is generated ONCE from a persisted seed (see title_panorama.gd)
# and cached under user://, so the menu never regenerates a world per open.
#
# ANIMATION: the image is laid out inside a CLIPPING container at "cover" size
# with extra width to travel over, then a Tween slides it slowly left/right and
# eases in/out at each end — a smooth reversal with no gaps or jumps. Only the
# image moves; every UI element is a sibling of the clip container and stays put.
# The Tween is engine-driven, so there is NO per-frame script cost, and it is
# killed before a new one starts (no duplicate loops on rebuild).
const PAN_SECONDS:  float = 46.0    # one traversal, left -> right
const PAN_OVERSCAN: float = 1.30    # extra width available to pan across

var _bg_clip:  Control     = null
var _bg_rect:  TextureRect = null
var _pan_tween: Tween      = null

func _build_background() -> void:
	_bg_holder = Control.new()
	_bg_holder.set_anchors_preset(Control.PRESET_FULL_RECT)
	_bg_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_bg_holder)
	# Clipping container: the image slides inside it and can never spill out.
	_bg_clip = Control.new()
	_bg_clip.set_anchors_preset(Control.PRESET_FULL_RECT)
	_bg_clip.mouse_filter   = Control.MOUSE_FILTER_IGNORE
	_bg_clip.clip_contents  = true
	_bg_holder.add_child(_bg_clip)
	_set_background_texture(_panorama_texture())
	# Re-lay the pan out whenever the window/viewport changes size.
	if not resized.is_connected(_on_resized):
		resized.connect(_on_resized)

func _panorama_texture() -> Texture2D:
	if _panorama == null or not is_instance_valid(_panorama):
		return null
	return _panorama.call("load_cached") as Texture2D

func _set_background_texture(tex: Texture2D) -> void:
	if _bg_holder == null or not is_instance_valid(_bg_holder):
		return
	_stop_pan()
	_bg_rect = null
	for c in _bg_holder.get_children():
		_bg_holder.remove_child(c)
		c.queue_free()
	_bg_clip = null

	# Clipping container (rebuilt with the rest).
	_bg_clip = Control.new()
	_bg_clip.set_anchors_preset(Control.PRESET_FULL_RECT)
	_bg_clip.mouse_filter   = Control.MOUSE_FILTER_IGNORE
	_bg_clip.clip_contents  = true
	_bg_holder.add_child(_bg_clip)

	if tex != null:
		var tr := TextureRect.new()
		tr.texture = tex
		tr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST   # keep pixel art crisp
		tr.expand_mode    = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode   = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		tr.mouse_filter   = Control.MOUSE_FILTER_IGNORE
		_bg_clip.add_child(tr)
		_bg_rect = tr
	else:
		var bg := ColorRect.new()
		bg.color = C_BG
		bg.set_anchors_preset(Control.PRESET_FULL_RECT)
		bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_bg_clip.add_child(bg)

	# Scrim LAST so it always sits over the image/colour.
	var scrim := ColorRect.new()
	scrim.color = Color(C_BG.r, C_BG.g, C_BG.b, 0.55)
	scrim.set_anchors_preset(Control.PRESET_FULL_RECT)
	scrim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bg_holder.add_child(scrim)

	_layout_background()

# Sizes the image to COVER the viewport with at least PAN_OVERSCAN extra width
# (so the pan can never expose an empty edge) and (re)starts the pan.
func _layout_background() -> void:
	if _bg_clip == null or not is_instance_valid(_bg_clip):
		return
	var vp: Vector2 = _bg_clip.size
	if vp.x <= 1.0 or vp.y <= 1.0:
		vp = get_viewport_rect().size
	if vp.x <= 1.0 or vp.y <= 1.0:
		return
	if _bg_rect == null or not is_instance_valid(_bg_rect) or _bg_rect.texture == null:
		_stop_pan()
		return
	var tw: float = float(_bg_rect.texture.get_width())
	var th: float = float(_bg_rect.texture.get_height())
	if tw <= 0.0 or th <= 0.0:
		_stop_pan()
		return

	# Cover the viewport, then widen by the overscan so there is travel room.
	var scale: float = maxf(vp.y / th, vp.x / tw)
	var w: float = tw * scale
	var h: float = th * scale
	if w < vp.x * PAN_OVERSCAN:
		var grow: float = (vp.x * PAN_OVERSCAN) / w
		w *= grow
		h *= grow
	_bg_rect.size = Vector2(ceilf(w), ceilf(h))
	_bg_rect.position = Vector2(0.0, floorf((vp.y - h) * 0.5))   # vertically centred

	_start_pan(vp.x)

# A slow ping-pong slide. TRANS_SINE + EASE_IN_OUT makes each direction change a
# gentle reversal instead of a snap, and the image is always wider than the
# viewport so no gap can appear at either end.
func _start_pan(view_w: float) -> void:
	_stop_pan()
	if _bg_rect == null or not is_instance_valid(_bg_rect):
		return
	var travel: float = _bg_rect.size.x - view_w
	if travel <= 1.0:
		return   # nothing to travel over
	var tw := create_tween()
	tw.set_loops()
	tw.tween_property(_bg_rect, "position:x", -travel, PAN_SECONDS) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(_bg_rect, "position:x", 0.0, PAN_SECONDS) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_pan_tween = tw

func _stop_pan() -> void:
	if _pan_tween != null and _pan_tween.is_valid():
		_pan_tween.kill()
	_pan_tween = null

func _on_resized() -> void:
	_layout_background()

func _on_panorama_ready(tex: Texture2D) -> void:
	_set_background_texture(tex)

# ── Main menu ─────────────────────────────────────────────────────
func _build_main_ui() -> void:
	var s: float = Global.ui_scale
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var vbox := VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", int(10 * s))
	vbox.custom_minimum_size = Vector2(int(320 * s), 0)
	center.add_child(vbox)

	var title := Label.new()
	title.text = "SandEE"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", int(72 * s))
	title.add_theme_color_override("font_color", C_TITLE)
	vbox.add_child(title)

	var sub := Label.new()
	sub.text = "Alpha"
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.add_theme_font_size_override("font_size", int(16 * s))
	sub.add_theme_color_override("font_color", C_MUTED)
	vbox.add_child(sub)

	# Random flavor text (one line, re-rolled each time the menu opens) — loaded
	# from its own .tres so adding lines never touches this script.
	var flavor := Label.new()
	flavor.text = _random_flavor_line()
	flavor.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	flavor.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	flavor.custom_minimum_size = Vector2(int(300 * s), 0)
	flavor.add_theme_font_size_override("font_size", int(12 * s))
	flavor.add_theme_color_override("font_color", Color(0.95, 0.92, 0.55, 1.0))
	flavor.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	flavor.add_theme_constant_override("outline_size", int(3 * s))
	vbox.add_child(flavor)

	_add_spacer(vbox, 16)
	var div := ColorRect.new()
	div.color = C_DIVIDER
	div.custom_minimum_size = Vector2(0, int(1 * s))
	vbox.add_child(div)
	_add_spacer(vbox, 16)

	var continue_btn := _make_menu_btn("Continue", _on_continue)
	if Global.get_last_slot() == -1:
		continue_btn.disabled = true
	vbox.add_child(continue_btn)

	_add_menu_btn(vbox, "Worlds",     _on_worlds,     "Create, load or delete worlds.")
	_add_menu_btn(vbox, "Settings",   _on_settings,   "Graphics, audio and gameplay options.")
	_add_spacer(vbox, 8)

	var quit_btn := _make_menu_btn("Quit", _on_quit)
	var qs := StyleBoxFlat.new()
	qs.bg_color = Color(0.18, 0.08, 0.08, 0.97)
	qs.border_color = Color(0.55, 0.22, 0.22, 1.0)
	qs.set_border_width_all(int(1 * s)); qs.set_corner_radius_all(int(4 * s))
	qs.content_margin_top = int(8 * s); qs.content_margin_bottom = int(8 * s)
	var qsh := StyleBoxFlat.new()
	qsh.bg_color = Color(0.28, 0.12, 0.12, 0.97)
	qsh.border_color = Color(1.0, 0.45, 0.45, 1.0)
	qsh.set_border_width_all(int(1 * s)); qsh.set_corner_radius_all(int(4 * s))
	qsh.content_margin_top = int(8 * s); qsh.content_margin_bottom = int(8 * s)
	quit_btn.add_theme_stylebox_override("normal",  qs)
	quit_btn.add_theme_stylebox_override("hover",   qsh)
	quit_btn.add_theme_stylebox_override("pressed", qs)
	quit_btn.add_theme_color_override("font_color",       Color(1.0, 0.55, 0.55, 1.0))
	quit_btn.add_theme_color_override("font_hover_color", Color(1.0, 0.40, 0.40, 1.0))
	vbox.add_child(quit_btn)

# ── Corner labels: build version (bottom-left) + project (bottom-right) ──
# Both are anchored to the usable viewport corners with a small margin, so they
# stay put at any window size / aspect ratio and can never collide with the
# centered menu.
func _build_corner_labels() -> void:
	var s: float = Global.ui_scale
	var m: int = int(14 * s)

	var ver := Label.new()
	ver.text = "v%s" % Global.game_version()
	ver.add_theme_font_size_override("font_size", int(12 * s))
	ver.add_theme_color_override("font_color", C_MUTED)
	ver.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	ver.add_theme_constant_override("outline_size", int(3 * s))
	ver.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	ver.offset_left   = m
	ver.offset_bottom = -m
	ver.grow_horizontal = Control.GROW_DIRECTION_END
	ver.grow_vertical   = Control.GROW_DIRECTION_BEGIN
	add_child(ver)

	var proj := Label.new()
	proj.text = PROJECT_LABEL
	proj.add_theme_font_size_override("font_size", int(12 * s))
	proj.add_theme_color_override("font_color", C_MUTED)
	proj.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	proj.add_theme_constant_override("outline_size", int(3 * s))
	proj.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	proj.offset_right  = -m
	proj.offset_bottom = -m
	proj.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	proj.grow_vertical   = Control.GROW_DIRECTION_BEGIN
	add_child(proj)

# One random line from the flavor-text resource (fallback when it is missing or
# empty, so a bad/missing .tres can never leave the title screen blank).
func _random_flavor_line() -> String:
	if not ResourceLoader.exists(FLAVOR_TEXT_PATH):
		return FLAVOR_FALLBACK
	var res: Resource = load(FLAVOR_TEXT_PATH)
	if res == null or not res.has_method("random_line"):
		return FLAVOR_FALLBACK
	var line: String = str(res.call("random_line")).strip_edges()
	return line if not line.is_empty() else FLAVOR_FALLBACK

# ── Worlds overlay (create / load / delete) ───────────────────────
# Replaces the old 3-slot picker: up to Global.MAX_WORLDS independent worlds,
# each showing its name, the SandEE version it was created (or last saved) with,
# and when it was last played. Every action touches ONE slot file, so worlds can
# never overwrite each other.
#
# The panel fills a full-rect MarginContainer, so the LIST scrolls inside it
# instead of the panel ever overflowing a short window.
func _build_worlds_overlay() -> void:
	var s: float = Global.ui_scale
	_worlds_overlay = _make_overlay()
	add_child(_worlds_overlay)

	var outer := MarginContainer.new()
	outer.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		outer.add_theme_constant_override("margin_" + side, int(20 * s))
	_worlds_overlay.add_child(outer)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(int(440 * s), 0)
	_style_panel(panel)
	outer.add_child(panel)

	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, int(18 * s))
	panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", int(10 * s))
	margin.add_child(vbox)

	var title := Label.new()
	title.text = "Worlds"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", int(20 * s))
	title.add_theme_color_override("font_color", C_TITLE)
	vbox.add_child(title)

	var div := ColorRect.new()
	div.color = C_DIVIDER
	div.custom_minimum_size = Vector2(0, int(1 * s))
	vbox.add_child(div)

	# Existing worlds (scrollable — long content scrolls, never overflows).
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vbox.add_child(scroll)
	_worlds_list = VBoxContainer.new()
	_worlds_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_worlds_list.add_theme_constant_override("separation", int(6 * s))
	scroll.add_child(_worlds_list)

	var div2 := ColorRect.new()
	div2.color = C_DIVIDER
	div2.custom_minimum_size = Vector2(0, int(1 * s))
	vbox.add_child(div2)

	# Create a world: a name field + validation feedback.
	var create_lbl := Label.new()
	create_lbl.text = "Create a new world"
	create_lbl.add_theme_font_size_override("font_size", int(13 * s))
	create_lbl.add_theme_color_override("font_color", C_TITLE)
	vbox.add_child(create_lbl)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", int(8 * s))
	vbox.add_child(row)

	_create_name = LineEdit.new()
	_create_name.placeholder_text = "World name"
	_create_name.max_length = 24
	_create_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_create_name.custom_minimum_size = Vector2(0, int(34 * s))
	_create_name.add_theme_font_size_override("font_size", int(13 * s))
	_create_name.text_changed.connect(func(_t: String) -> void: _update_create_state())
	_create_name.text_submitted.connect(func(_t: String) -> void: _on_create_world())
	row.add_child(_create_name)

	_create_btn = _make_menu_btn("Create", _on_create_world)
	_create_btn.custom_minimum_size = Vector2(int(110 * s), int(34 * s))
	row.add_child(_create_btn)

	_create_error = Label.new()
	_create_error.add_theme_font_size_override("font_size", int(11 * s))
	_create_error.add_theme_color_override("font_color", Color(1.0, 0.55, 0.55, 1.0))
	_create_error.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(_create_error)

	_add_menu_btn(vbox, "< Back", func() -> void: _worlds_overlay.visible = false)

	_refresh_worlds()

# ── Credits overlay (Settings -> Credits) ─────────────────────────
# Names + roles exactly as supplied, in a scrollable panel so it always fits.
func _build_credits_overlay() -> void:
	var s: float = Global.ui_scale
	_credits_overlay = _make_overlay()
	add_child(_credits_overlay)

	var outer := MarginContainer.new()
	outer.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		outer.add_theme_constant_override("margin_" + side, int(20 * s))
	_credits_overlay.add_child(outer)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(int(440 * s), 0)
	_style_panel(panel)
	outer.add_child(panel)

	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, int(20 * s))
	panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", int(10 * s))
	margin.add_child(vbox)

	var title := Label.new()
	title.text = "Credits"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", int(20 * s))
	title.add_theme_color_override("font_color", C_TITLE)
	vbox.add_child(title)

	var div := ColorRect.new()
	div.color = C_DIVIDER
	div.custom_minimum_size = Vector2(0, int(1 * s))
	vbox.add_child(div)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vbox.add_child(scroll)

	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", int(14 * s))
	scroll.add_child(list)

	for entry in CREDITS:
		var name_lbl := Label.new()
		name_lbl.text = str(entry[0])
		name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		name_lbl.add_theme_font_size_override("font_size", int(15 * s))
		name_lbl.add_theme_color_override("font_color", C_TITLE)
		list.add_child(name_lbl)

		var role_lbl := Label.new()
		role_lbl.text = str(entry[1])
		role_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		role_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		role_lbl.add_theme_font_size_override("font_size", int(12 * s))
		role_lbl.add_theme_color_override("font_color", C_MUTED)
		list.add_child(role_lbl)

	_add_menu_btn(vbox, "< Back", func() -> void: _credits_overlay.visible = false)

# ── Generic confirmation dialog (destructive actions) ─────────────
# Cancel is the first/default-focused action and the only one that is safe by
# default; the panel is short so it always fits.
func _build_confirm_overlay() -> void:
	var s: float = Global.ui_scale
	_confirm_overlay = _make_overlay()
	add_child(_confirm_overlay)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_confirm_overlay.add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(int(360 * s), 0)
	_style_panel(panel)
	center.add_child(panel)

	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, int(22 * s))
	panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", int(14 * s))
	margin.add_child(vbox)

	_confirm_label = Label.new()
	_confirm_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_confirm_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_confirm_label.custom_minimum_size = Vector2(int(300 * s), 0)
	_confirm_label.add_theme_font_size_override("font_size", int(14 * s))
	_confirm_label.add_theme_color_override("font_color", C_TITLE)
	vbox.add_child(_confirm_label)

	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", int(12 * s))
	vbox.add_child(row)

	var cancel := _make_menu_btn("Cancel", _on_confirm_cancel)
	cancel.custom_minimum_size = Vector2(int(140 * s), int(38 * s))
	row.add_child(cancel)

	var ok := _make_menu_btn("Delete", _on_confirm_ok)
	ok.custom_minimum_size = Vector2(int(140 * s), int(38 * s))
	ok.add_theme_color_override("font_color",       Color(1.0, 0.55, 0.55, 1.0))
	ok.add_theme_color_override("font_hover_color", Color(1.0, 0.35, 0.35, 1.0))
	row.add_child(ok)

# Opens the confirmation dialog. `on_confirm` runs ONLY when the player confirms.
func _ask_confirm(message: String, on_confirm: Callable) -> void:
	_confirm_cb = on_confirm
	if _confirm_label != null:
		_confirm_label.text = message
	if _confirm_overlay != null:
		_confirm_overlay.visible = true

func _on_confirm_cancel() -> void:
	_confirm_cb = Callable()
	if _confirm_overlay != null:
		_confirm_overlay.visible = false

func _on_confirm_ok() -> void:
	var cb: Callable = _confirm_cb
	_confirm_cb = Callable()
	if _confirm_overlay != null:
		_confirm_overlay.visible = false
	if cb.is_valid():
		cb.call()

# ── Settings overlay ──────────────────────────────────────────────
func _build_settings_overlay() -> void:
	var s: float = Global.ui_scale
	_settings_overlay = _make_overlay()
	add_child(_settings_overlay)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_settings_overlay.add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(int(380 * s), 0)
	_style_panel(panel)
	center.add_child(panel)

	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, int(24 * s))
	panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", int(14 * s))
	margin.add_child(vbox)

	var title := Label.new()
	title.text = "Settings"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", int(20 * s))
	title.add_theme_color_override("font_color", C_TITLE)
	vbox.add_child(title)

	var div := ColorRect.new()
	div.color = C_DIVIDER
	div.custom_minimum_size = Vector2(0, int(1 * s))
	vbox.add_child(div)

	_add_spacer(vbox, 4)

	_add_slider_row(vbox, "Music Volume", Global.music_volume,
		func(v: float) -> void:
			Global.music_volume = v
			var idx := AudioServer.get_bus_index("Music")
			if idx != -1:
				AudioServer.set_bus_volume_db(idx, linear_to_db(maxf(v, 0.0001))))

	_add_slider_row(vbox, "Sound Volume", Global.sfx_volume,
		func(v: float) -> void:
			Global.sfx_volume = v
			var idx := AudioServer.get_bus_index("SFX")
			if idx != -1:
				AudioServer.set_bus_volume_db(idx, linear_to_db(maxf(v, 0.0001))))

	_add_spacer(vbox, 8)
	# Display mode — the same persisted setting the pause menu uses (hidden on
	# mobile, where the platform owns the display).
	if not Global.is_mobile():
		var fs_row := HBoxContainer.new()
		fs_row.add_theme_constant_override("separation", int(10 * s))
		vbox.add_child(fs_row)
		var fs_lbl := Label.new()
		fs_lbl.text = "Fullscreen"
		fs_lbl.custom_minimum_size = Vector2(int(140 * s), 0)
		fs_lbl.add_theme_font_size_override("font_size", int(13 * s))
		fs_lbl.add_theme_color_override("font_color", C_TITLE)
		fs_row.add_child(fs_lbl)
		var fs_btn := CheckButton.new()
		fs_btn.button_pressed = Global.fullscreen
		fs_btn.tooltip_text = "Play in fullscreen mode. Saved for the next launch."
		fs_btn.toggled.connect(func(on: bool) -> void: Global.set_fullscreen(on))
		fs_row.add_child(fs_btn)

	_add_menu_btn(vbox, "Credits", _on_credits, "Who made SandEE.")
	_add_menu_btn(vbox, "< Back", func() -> void: _settings_overlay.visible = false)

# ── Builder helpers ───────────────────────────────────────────────
func _make_overlay() -> Control:
	var ctrl := Control.new()
	ctrl.set_anchors_preset(Control.PRESET_FULL_RECT)
	ctrl.visible = false
	var dim := ColorRect.new()
	dim.color = C_OVERLAY
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	ctrl.add_child(dim)
	return ctrl

func _style_panel(panel: PanelContainer) -> void:
	var s: float = Global.ui_scale
	var ps := StyleBoxFlat.new()
	ps.bg_color     = C_PANEL
	ps.border_color = C_BORDER
	ps.set_border_width_all(int(1 * s))
	ps.set_corner_radius_all(int(6 * s))
	panel.add_theme_stylebox_override("panel", ps)

func _make_menu_btn(label: String, callback: Callable) -> Button:
	var s: float = Global.ui_scale
	var btn := Button.new()
	btn.text = label
	btn.custom_minimum_size = Vector2(int(280 * s), int(44 * s))
	btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	btn.add_theme_font_size_override("font_size", int(15 * s))
	btn.add_theme_color_override("font_color",         C_TITLE)
	btn.add_theme_color_override("font_hover_color",   C_TITLE)
	btn.add_theme_color_override("font_pressed_color", C_MUTED)
	var normal := StyleBoxFlat.new()
	normal.bg_color = C_PANEL; normal.border_color = C_BORDER
	normal.set_border_width_all(int(1 * s)); normal.set_corner_radius_all(int(4 * s))
	normal.content_margin_top = int(8 * s); normal.content_margin_bottom = int(8 * s)
	var hover := StyleBoxFlat.new()
	hover.bg_color = C_BTN_H; hover.border_color = C_TITLE
	hover.set_border_width_all(int(1 * s)); hover.set_corner_radius_all(int(4 * s))
	hover.content_margin_top = int(8 * s); hover.content_margin_bottom = int(8 * s)
	btn.add_theme_stylebox_override("normal",  normal)
	btn.add_theme_stylebox_override("hover",   hover)
	btn.add_theme_stylebox_override("pressed", normal)
	btn.pressed.connect(callback)
	return btn

func _add_menu_btn(parent: Node, label: String, callback: Callable, tooltip: String = "") -> void:
	var btn := _make_menu_btn(label, callback)
	btn.tooltip_text = tooltip
	parent.add_child(btn)

func _add_spacer(parent: Node, height: int) -> void:
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, int(height * Global.ui_scale))
	parent.add_child(spacer)

# One world row: name + version + last-played, with Load and Delete. Delete goes
# through the confirmation dialog — it never touches the file directly.
func _make_world_row(slot: int) -> Control:
	var s: float = Global.ui_scale
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", int(6 * s))
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var btn := Button.new()
	btn.text = ""
	btn.custom_minimum_size = Vector2(0, int(62 * s))
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var normal := StyleBoxFlat.new()
	normal.bg_color = C_PANEL; normal.border_color = C_BORDER
	normal.set_border_width_all(int(1 * s)); normal.set_corner_radius_all(int(4 * s))
	var hover := StyleBoxFlat.new()
	hover.bg_color = C_BTN_H; hover.border_color = C_TITLE
	hover.set_border_width_all(int(1 * s)); hover.set_corner_radius_all(int(4 * s))
	btn.add_theme_stylebox_override("normal",  normal)
	btn.add_theme_stylebox_override("hover",   hover)
	btn.add_theme_stylebox_override("pressed", normal)
	btn.tooltip_text = "Load this world."
	btn.pressed.connect(func() -> void: _load_world(slot))

	var content := VBoxContainer.new()
	content.set_anchors_preset(Control.PRESET_FULL_RECT)
	content.alignment = BoxContainer.ALIGNMENT_CENTER
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn.add_child(content)

	var name_lbl := Label.new()
	name_lbl.text = Global.world_name_of(slot)
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_lbl.add_theme_font_size_override("font_size", int(15 * s))
	name_lbl.add_theme_color_override("font_color", C_TITLE)
	name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(name_lbl)

	# Version metadata: created-with (else last-saved-with), else "Unknown
	# version" for a save made before this existed.
	var meta := Label.new()
	meta.text = "v%s  ·  %s" % [Global.world_version_of(slot), _last_played_text(slot)]
	meta.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	meta.add_theme_font_size_override("font_size", int(11 * s))
	meta.add_theme_color_override("font_color", C_MUTED)
	meta.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(meta)

	row.add_child(btn)

	var del := Button.new()
	del.text = "Delete"
	del.custom_minimum_size = Vector2(int(78 * s), int(62 * s))
	del.size_flags_horizontal = Control.SIZE_SHRINK_END
	del.add_theme_font_size_override("font_size", int(12 * s))
	var ds := StyleBoxFlat.new()
	ds.bg_color     = Color(0.18, 0.06, 0.06, 0.97)
	ds.border_color = Color(0.55, 0.22, 0.22, 1.0)
	ds.set_border_width_all(int(1 * s)); ds.set_corner_radius_all(int(4 * s))
	var dsh := StyleBoxFlat.new()
	dsh.bg_color     = Color(0.38, 0.10, 0.10, 0.97)
	dsh.border_color = Color(1.0, 0.40, 0.40, 1.0)
	dsh.set_border_width_all(int(1 * s)); dsh.set_corner_radius_all(int(4 * s))
	del.add_theme_stylebox_override("normal",  ds)
	del.add_theme_stylebox_override("hover",   dsh)
	del.add_theme_stylebox_override("pressed", ds)
	del.add_theme_color_override("font_color",       Color(1.0, 0.55, 0.55, 1.0))
	del.add_theme_color_override("font_hover_color", Color(1.0, 0.35, 0.35, 1.0))
	del.tooltip_text = "Delete this world (asks first)."
	del.pressed.connect(func() -> void: _ask_delete_world(slot))
	row.add_child(del)

	return row

func _last_played_text(slot: int) -> String:
	var ts: int = int(float(Global.get_save_info(slot).get("timestamp", 0)))
	if ts <= 0:
		return "never played"
	var dt: Dictionary = Time.get_datetime_dict_from_unix_time(ts)
	return "%04d-%02d-%02d %02d:%02d" % [
		int(dt["year"]), int(dt["month"]), int(dt["day"]),
		int(dt["hour"]), int(dt["minute"])]

# Rebuilds the world list from the live save slots (never a cached copy) and
# re-evaluates the create form. Shows an empty state when there are no worlds.
func _refresh_worlds() -> void:
	if _worlds_list == null:
		return
	for c in _worlds_list.get_children():
		_worlds_list.remove_child(c)
		c.queue_free()

	var slots: Array = Global.list_worlds()
	if slots.is_empty():
		var empty := Label.new()
		empty.text = "No worlds yet — create one below to start playing."
		empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		empty.add_theme_font_size_override("font_size", int(13 * Global.ui_scale))
		empty.add_theme_color_override("font_color", C_MUTED)
		_worlds_list.add_child(empty)
	else:
		for slot in slots:
			_worlds_list.add_child(_make_world_row(slot))
	_update_create_state()

# Enables Create only for a valid, unused name and while under the 10-world cap.
func _update_create_state() -> void:
	if _create_btn == null or _create_name == null:
		return
	if not Global.can_create_world():
		_create_name.editable = false
		_create_btn.disabled  = true
		_create_error.text = "World limit reached (%d). Delete a world to make room." % Global.MAX_WORLDS
		return
	_create_name.editable = true
	var name: String = _create_name.text.strip_edges()
	var msg := ""
	var ok := true
	if name.is_empty():
		ok = false
	elif not Global.is_world_name_free(name):
		ok = false
		msg = "That name is already used by another world."
	_create_btn.disabled = not ok
	_create_error.text = msg

func _add_slider_row(parent: Node, label_text: String, init_v: float, callback: Callable) -> void:
	var s: float = Global.ui_scale
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", int(10 * s))
	parent.add_child(row)

	var lbl := Label.new()
	lbl.text = label_text
	lbl.custom_minimum_size = Vector2(int(140 * s), 0)
	lbl.add_theme_font_size_override("font_size", int(13 * s))
	lbl.add_theme_color_override("font_color", C_TITLE)
	row.add_child(lbl)

	var val_lbl := Label.new()
	val_lbl.text = "%d%%" % int(init_v * 100.0)
	val_lbl.custom_minimum_size = Vector2(int(44 * s), 0)
	val_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	val_lbl.add_theme_font_size_override("font_size", int(13 * s))
	val_lbl.add_theme_color_override("font_color", C_MUTED)

	var slider := HSlider.new()
	slider.min_value = 0.0
	slider.max_value = 1.0
	slider.step      = 0.05
	slider.value     = init_v
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.value_changed.connect(func(v: float) -> void:
		val_lbl.text = "%d%%" % int(v * 100.0)
		callback.call(v))
	row.add_child(slider)
	row.add_child(val_lbl)

# ── Actions ───────────────────────────────────────────────────────
func _on_continue() -> void:
	var slot := Global.get_last_slot()
	if slot == -1:
		return
	Global.load_game(slot)
	get_tree().change_scene_to_file("res://scenes/game_instance.tscn")

func _on_worlds() -> void:
	_refresh_worlds()
	if _create_name != null:
		_create_name.text = ""
	_update_create_state()
	if _worlds_overlay != null:
		_worlds_overlay.visible = true

# Loads an existing world. Re-reads the slot first so a stale row can't load the
# wrong world.
func _load_world(slot: int) -> void:
	if not Global.has_save(slot):
		_refresh_worlds()
		return
	Global.load_game(slot)
	get_tree().change_scene_to_file("res://scenes/game_instance.tscn")

# Creates a NEW world in the lowest free slot. Refuses at the 10-world cap, on an
# empty name, or on a duplicate name — and only ever writes its own slot file.
func _on_create_world() -> void:
	if not Global.can_create_world():
		_update_create_state()
		return
	var name: String = _create_name.text.strip_edges()
	if name.is_empty() or not Global.is_world_name_free(name):
		_update_create_state()
		return
	var slot: int = Global.next_free_slot()
	if slot < 0:
		_update_create_state()
		return
	Global.begin_new_world(slot, name)
	get_tree().change_scene_to_file("res://scenes/game_instance.tscn")

# Deleting ALWAYS asks first, and only ever removes the ONE slot file. The slot's
# name is re-checked at confirm time, so a stale row can't delete a world that
# changed underneath it.
func _ask_delete_world(slot: int) -> void:
	if not Global.has_save(slot):
		_refresh_worlds()
		return
	var name: String = Global.world_name_of(slot)
	_ask_confirm("Delete \"%s\" permanently?\n\nThis cannot be undone." % name,
		func() -> void: _do_delete_world(slot, name))

func _do_delete_world(slot: int, expected_name: String) -> void:
	if not Global.has_save(slot) or Global.world_name_of(slot) != expected_name:
		_refresh_worlds()
		return
	Global.delete_world(slot)
	_refresh_worlds()

func _on_settings() -> void:
	_settings_overlay.visible = true

func _on_credits() -> void:
	if _credits_overlay != null:
		_credits_overlay.visible = true

func _on_quit() -> void:
	get_tree().quit()

# Stop the background pan with the scene (the Tween would be auto-killed anyway,
# but this keeps the "no duplicate loops" guarantee explicit).
func _exit_tree() -> void:
	_stop_pan()
