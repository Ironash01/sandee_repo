extends Control

# One settings implementation shared with the pause menu.
const SETTINGS_PANEL_SCRIPT: Script = preload("res://scripts/settings_panel.gd")

const C_BG      := Color(0.04, 0.06, 0.12, 1.00)
const C_PANEL   := Color(0.08, 0.10, 0.20, 0.97)
const C_BORDER  := Color(0.22, 0.32, 0.58, 1.00)
const C_TITLE   := Color(0.80, 0.90, 1.00, 1.00)
const C_MUTED   := Color(0.55, 0.65, 0.85, 1.00)
const C_OVERLAY := Color(0.00, 0.00, 0.00, 0.60)
const C_DIVIDER := Color(0.20, 0.28, 0.50, 1.00)
const C_BTN_H   := Color(0.12, 0.18, 0.36, 1.00)
const C_OK      := Color(0.55, 0.95, 0.68, 1.00)
const C_WARN    := Color(0.98, 0.72, 0.35, 1.00)
const C_ERROR   := Color(1.00, 0.50, 0.50, 1.00)

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
var _rename_overlay:   Control = null
var _rename_input:     LineEdit = null
var _rename_slot:      int = -1
var _worlds_outer:     MarginContainer = null
var _rename_center:    CenterContainer = null
var _rename_scroll:    ScrollContainer = null
var _rename_panel:     Control = null
var _keyboard_inset:   float = 0.0
var _bg_holder:        Control = null
var _panorama:         Node    = null
var _worlds_list:      VBoxContainer = null
var _create_name:      LineEdit = null
var _create_btn:       Button   = null
var _create_error:     Label    = null
var _continue_btn:     Button   = null
var _confirm_label:    Label    = null
var _confirm_cb:       Callable = Callable()

# ── Online UI ─────────────────────────────────────────────────────
var _status_label:        Label          = null
var _menu_center:         CenterContainer = null
var _online_row:          HBoxContainer  = null
var _go_online_btn:       Button         = null
var _go_online_busy:      bool           = false
var _leaderboard_overlay: Control        = null
var _cloud_overlay:       Control        = null
var _account_overlay:     Control        = null
var _account_panel:       Control        = null
var _lb_list:             VBoxContainer  = null
var _lb_status:           Label          = null
var _lb_tabs:             Array[Button]  = []
var _lb_kind:             String         = "total_stars"
var _lb_loading:          bool           = false
var _cloud_status:        Label          = null
var _cloud_message:       Label          = null
var _cloud_remote_list:   VBoxContainer  = null
var _cloud_busy:          bool           = false
var _cloud_remote_meta:   Dictionary     = {}
var _net_timer:           Timer          = null
var _net_checking:        bool           = false

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
	if not Global.cloud_status_changed.is_connected(_on_cloud_status_changed):
		Global.cloud_status_changed.connect(_on_cloud_status_changed)
	if not Global.online_state_changed.is_connected(_on_online_state_changed):
		Global.online_state_changed.connect(_on_online_state_changed)
	if not CloudSync.sync_completed.is_connected(_on_cloud_sync_completed):
		CloudSync.sync_completed.connect(_on_cloud_sync_completed)
	if not CloudSync.sync_progress_changed.is_connected(_on_cloud_sync_progress):
		CloudSync.sync_progress_changed.connect(_on_cloud_sync_progress)
	_refresh_status_label()
	_refresh_online_visibility()
	_start_net_timer()
	# Reuse the cached panorama; only regenerate when it is missing/invalid.
	_panorama.call("ensure_panorama")

func _build_all() -> void:
	_build_background()
	_build_main_ui()
	_build_corner_labels()
	_build_worlds_overlay()
	_build_settings_overlay()
	_build_credits_overlay()
	_build_leaderboard_overlay()
	_build_cloud_overlay()
	_build_account_overlay()
	# Confirmation/rename dialogs are built LAST so they always render above the
	# online overlays they can be opened from.
	_build_confirm_overlay()
	_build_rename_overlay()

# Rebuild the whole menu at the new scale so a responsive scale change applies
# live; open overlays keep their visibility.
func _process(_delta: float) -> void:
	if not Global.is_mobile():
		return
	var inset: float = Global.mobile_keyboard_height()
	if is_equal_approx(inset, _keyboard_inset):
		return
	_keyboard_inset = inset
	if _worlds_outer != null and is_instance_valid(_worlds_outer):
		# Slide the whole panel up instead of shrinking it. The create-world
		# field sits at the bottom of the panel; shrinking collapsed the fixed
		# rows and could leave that field below the keyboard. Translating keeps
		# the panel's height, so the list can still shrink around the field.
		_worlds_outer.offset_top = Global.ui_safe_insets.y - inset
		_worlds_outer.offset_bottom = -(Global.ui_safe_insets.w + inset)
	if _rename_scroll != null and is_instance_valid(_rename_scroll):
		_fit_rename_center()
		if _rename_input != null and _rename_input.has_focus():
			_rename_scroll.call_deferred("ensure_control_visible", _rename_input)

func _on_ui_scale(_s: float) -> void:
	# Force the next _process pass to re-apply the keyboard inset to the rebuilt
	# worlds/rename surfaces.
	_keyboard_inset = -1.0
	if _account_panel != null and _account_panel.visible \
			and bool(_account_panel.call("is_busy")):
		return
	var worlds_vis:  bool = _worlds_overlay != null and _worlds_overlay.visible
	var set_vis:     bool = _settings_overlay != null and _settings_overlay.visible
	var credits_vis: bool = _credits_overlay != null and _credits_overlay.visible
	var conf_vis:    bool = _confirm_overlay != null and _confirm_overlay.visible
	var ren_vis:     bool = _rename_overlay != null and _rename_overlay.visible
	var lb_vis:      bool = _leaderboard_overlay != null and _leaderboard_overlay.visible
	var cloud_vis:   bool = _cloud_overlay != null and _cloud_overlay.visible
	var account_vis: bool = _account_overlay != null and _account_overlay.visible
	for child in get_children():
		child.queue_free()
	_stop_pan()
	_worlds_overlay   = null
	_settings_overlay = null
	_credits_overlay  = null
	_confirm_overlay  = null
	_rename_overlay   = null
	_rename_input     = null
	_rename_center    = null
	_rename_scroll    = null
	_rename_panel     = null
	_bg_holder        = null
	_bg_clip          = null
	_bg_rect          = null
	_panorama         = null
	_status_label     = null
	_continue_btn     = null
	_menu_center      = null
	_online_row       = null
	_go_online_btn    = null
	_leaderboard_overlay = null
	_cloud_overlay    = null
	_account_overlay  = null
	_account_panel    = null
	_lb_list          = null
	_lb_status        = null
	_lb_tabs          = []
	_cloud_status     = null
	_cloud_message    = null
	_cloud_remote_list = null
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
	if _rename_overlay != null:
		_rename_overlay.visible = ren_vis
	if _leaderboard_overlay != null:
		_leaderboard_overlay.visible = lb_vis
	if _cloud_overlay != null:
		_cloud_overlay.visible = cloud_vis
	if _account_overlay != null:
		_account_overlay.visible = account_vis
	_refresh_status_label()
	_refresh_online_visibility()

# ── Background (deterministic world panorama, else the plain colour) ──
# The panorama is generated ONCE from a persisted seed (see title_panorama.gd)
# and cached under user://, so the menu never regenerates a world per open.
#
# ANIMATION: the image is laid out inside a CLIPPING container at "cover" size
# with extra width to travel over, then a Tween slides it slowly left/right and
# eases in/out at each end — a smooth reversal with no gaps or jumps. Only the
# image moves; every UI element is a sibling of the clip container and stays put.
# The Tween is engine-driven, so there is NO per-frame script cost, and it is
# killed before a new one starts (including when the panorama cycles/rebuilds).
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
	if _menu_center != null and is_instance_valid(_menu_center):
		_menu_center.custom_minimum_size = Vector2(0,
			maxf(Global.ui_content_rect().size.y, 1.0))

# ── Online / cloud status ─────────────────────────────────────────
func _refresh_status_label() -> void:
	if _status_label == null or not is_instance_valid(_status_label):
		return
	var text := "SandEE v%s" % Global.game_version()
	if Global.online_mode:
		text += "  |  " + Global.cloud_status_label()
		_status_label.add_theme_color_override("font_color", Global.cloud_status_color())
	else:
		_status_label.add_theme_color_override("font_color", C_MUTED)
	_status_label.text = text
	_status_label.tooltip_text = Global.cloud_status_detail


func _on_cloud_status_changed(_status: int) -> void:
	_refresh_status_label()
	if _cloud_status != null and is_instance_valid(_cloud_status):
		_cloud_status.text = _cloud_status_text()
		_cloud_status.add_theme_color_override("font_color", Global.cloud_status_color())


func _on_online_state_changed() -> void:
	_refresh_status_label()
	_refresh_online_visibility()


func _refresh_online_visibility() -> void:
	if _online_row != null and is_instance_valid(_online_row):
		_online_row.visible = Global.online_mode
	if _go_online_btn != null and is_instance_valid(_go_online_btn):
		_go_online_btn.visible = not Global.online_mode
		if not Global.online_mode:
			_go_online_btn.disabled = _go_online_busy
			_go_online_btn.text = "Connecting…" if _go_online_busy else "Go Online"


# Network loss after Online Mode: poll while online so the bottom-left status
# turns "Offline" even if the player never opens an online overlay. A recovered
# connection re-validates the session before claiming Cloud Save Active again.
func _start_net_timer() -> void:
	if _net_timer != null and is_instance_valid(_net_timer):
		return
	_net_timer = Timer.new()
	_net_timer.wait_time = 30.0
	_net_timer.one_shot = false
	add_child(_net_timer)
	_net_timer.timeout.connect(_poll_connectivity)
	_net_timer.start()


func _poll_connectivity() -> void:
	if _net_checking or not Global.online_mode or not Supabase.is_signed_in():
		return
	_net_checking = true
	var connectivity := await Supabase.check_connectivity()
	_net_checking = false
	if not is_inside_tree():
		return
	if not bool(connectivity.get("backend", false)):
		if Global.cloud_status != Global.CloudStatus.OFFLINE:
			Global.set_cloud_status(Global.CloudStatus.OFFLINE, "No connection")
	elif Global.cloud_status == Global.CloudStatus.OFFLINE:
		if await Supabase.validate_session():
			Global.set_cloud_status(Global.CloudStatus.ACTIVE)
		else:
			Global.set_cloud_status(Global.CloudStatus.ERROR, "Session expired")


func _cloud_status_text() -> String:
	var text := Global.cloud_status_label()
	if Global.cloud_status_detail != "":
		text += " — " + Global.cloud_status_detail
	return text

func _on_panorama_ready(tex: Texture2D) -> void:
	_set_background_texture(tex)

# ── Main menu ─────────────────────────────────────────────────────
func _build_main_ui() -> void:
	var s: float = Global.ui_scale
	# Scrollable + centred: the menu is fully reachable on short desktop windows
	# and Android landscape even at the large responsive UI, and never clips.
	var scroll := ScrollContainer.new()
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	Global.apply_safe_area(scroll)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(scroll)

	_menu_center = CenterContainer.new()
	_menu_center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_menu_center.custom_minimum_size = Vector2(0, Global.ui_content_rect().size.y)
	scroll.add_child(_menu_center)

	var vbox := VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", int(10 * s))
	vbox.custom_minimum_size = Vector2(int(320 * s), 0)
	_menu_center.add_child(vbox)

	var title := Label.new()
	title.text = "SandEE"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	# Cap the masthead on short windows so its ascenders never clip and the
	# primary buttons stay on-screen; full desktop still gets the 72*s identity.
	var title_px: int = int(minf(float(Global.ui_font_size(72)),
		maxf(52.0, get_viewport_rect().size.y * 0.105)))
	title.add_theme_font_size_override("font_size", title_px)
	title.add_theme_color_override("font_color", C_TITLE)
	vbox.add_child(title)

	var sub := Label.new()
	sub.text = "Alpha"
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.add_theme_font_size_override("font_size", Global.ui_font_size(16))
	sub.add_theme_color_override("font_color", C_MUTED)
	vbox.add_child(sub)

	# Random flavor text (one line, re-rolled each time the menu opens) — loaded
	# from its own .tres so adding lines never touches this script.
	var flavor := Label.new()
	flavor.text = _random_flavor_line()
	flavor.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	flavor.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	flavor.custom_minimum_size = Vector2(int(300 * s), 0)
	flavor.add_theme_font_size_override("font_size", Global.ui_font_size(12))
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
	continue_btn.disabled = Global.get_last_slot() == -1
	vbox.add_child(continue_btn)
	_continue_btn = continue_btn

	_add_menu_btn(vbox, "Worlds",     _on_worlds,     "Create, load or delete worlds.")

	# After "Play Offline", this is the single explicit entry point for
	# returning to online mode. Cloud controls stay hidden offline.
	var go_online_btn := _make_menu_btn("Go Online", _on_go_online)
	go_online_btn.tooltip_text = "Connect and sign in for cloud saves and leaderboards."
	go_online_btn.visible = not Global.online_mode
	vbox.add_child(go_online_btn)
	_go_online_btn = go_online_btn

	# Online entry points, side by side to keep the menu within a short screen.
	# Hidden entirely in Offline Mode until the player switches Online above.
	var online_row := HBoxContainer.new()
	online_row.alignment = BoxContainer.ALIGNMENT_CENTER
	online_row.add_theme_constant_override("separation", int(6 * s))
	online_row.visible = Global.online_mode
	vbox.add_child(online_row)
	_online_row = online_row
	var lb_btn := _make_menu_btn("Leaderboard", _on_leaderboards)
	lb_btn.tooltip_text = "Blue and yellow star rankings (online)."
	lb_btn.custom_minimum_size = Vector2(0, int(36 * s))
	lb_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lb_btn.add_theme_font_size_override("font_size", Global.ui_font_size(11))
	online_row.add_child(lb_btn)
	var cloud_btn := _make_menu_btn("Cloud Saves", _on_cloud_saves)
	cloud_btn.tooltip_text = "View uploaded cloud worlds and download a copy (online)."
	cloud_btn.custom_minimum_size = Vector2(0, int(36 * s))
	cloud_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cloud_btn.add_theme_font_size_override("font_size", Global.ui_font_size(11))
	online_row.add_child(cloud_btn)
	var account_btn := _make_menu_btn("Account", _on_account)
	account_btn.tooltip_text = "Online account and sign out."
	account_btn.custom_minimum_size = Vector2(0, int(36 * s))
	account_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	account_btn.add_theme_font_size_override("font_size", Global.ui_font_size(11))
	online_row.add_child(account_btn)
	var offline_btn := _make_menu_btn("Play Offline", _on_play_offline)
	offline_btn.tooltip_text = "Stop cloud syncing and play this device's local worlds. Sign-in is required again on the next launch."
	offline_btn.custom_minimum_size = Vector2(0, int(36 * s))
	offline_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	offline_btn.add_theme_font_size_override("font_size", Global.ui_font_size(11))
	online_row.add_child(offline_btn)

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
	# Bottom-left always shows the real build version. Online mode appends the
	# ACTUAL cloud state; offline mode never claims a cloud connection.
	_status_label = ver
	ver.add_theme_font_size_override("font_size", Global.ui_font_size(12))
	ver.add_theme_color_override("font_color", C_MUTED)
	ver.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	ver.add_theme_constant_override("outline_size", int(3 * s))
	ver.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	ver.offset_left   = int(Global.ui_safe_insets.x) + m
	ver.offset_bottom = -int(Global.ui_safe_insets.w) - m
	ver.grow_horizontal = Control.GROW_DIRECTION_END
	ver.grow_vertical   = Control.GROW_DIRECTION_BEGIN
	add_child(ver)
	_refresh_status_label()

	var proj := Label.new()
	proj.text = PROJECT_LABEL
	proj.add_theme_font_size_override("font_size", Global.ui_font_size(12))
	proj.add_theme_color_override("font_color", C_MUTED)
	proj.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	proj.add_theme_constant_override("outline_size", int(3 * s))
	proj.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	proj.offset_right  = -int(Global.ui_safe_insets.z) - m
	proj.offset_bottom = -int(Global.ui_safe_insets.w) - m
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
	Global.apply_safe_area(outer)
	for side in ["left", "right", "top", "bottom"]:
		outer.add_theme_constant_override("margin_" + side, int(20 * s))
	_worlds_outer = outer
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
	title.add_theme_font_size_override("font_size", Global.ui_font_size(20))
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
	create_lbl.add_theme_font_size_override("font_size", Global.ui_font_size(13))
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
	_create_name.add_theme_font_size_override("font_size", Global.ui_font_size(13))
	_create_name.text_changed.connect(func(_t: String) -> void: _update_create_state())
	_create_name.text_submitted.connect(func(_t: String) -> void: _on_create_world())
	row.add_child(_create_name)

	_create_btn = _make_menu_btn("Create", _on_create_world)
	_create_btn.custom_minimum_size = Vector2(int(110 * s), int(34 * s))
	row.add_child(_create_btn)

	_create_error = Label.new()
	_create_error.add_theme_font_size_override("font_size", Global.ui_font_size(11))
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
	Global.apply_safe_area(outer)
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
	title.add_theme_font_size_override("font_size", Global.ui_font_size(20))
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
		name_lbl.add_theme_font_size_override("font_size", Global.ui_font_size(15))
		name_lbl.add_theme_color_override("font_color", C_TITLE)
		list.add_child(name_lbl)

		var role_lbl := Label.new()
		role_lbl.text = str(entry[1])
		role_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		role_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		role_lbl.add_theme_font_size_override("font_size", Global.ui_font_size(12))
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
	Global.apply_safe_area(center)
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
	_confirm_label.add_theme_font_size_override("font_size", Global.ui_font_size(14))
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
		# Always topmost: cloud-save confirmations can be opened from overlays
		# that were built after the dialog itself.
		move_child(_confirm_overlay, get_child_count() - 1)
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

# ── Rename world dialog (pencil button on a world row) ────────────
func _build_rename_overlay() -> void:
	var s: float = Global.ui_scale
	_rename_overlay = _make_overlay()
	add_child(_rename_overlay)

	var scroll := ScrollContainer.new()
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	Global.apply_safe_area(scroll)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_rename_overlay.add_child(scroll)
	_rename_scroll = scroll

	var center := CenterContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	center.custom_minimum_size = Vector2(0, 1)
	scroll.add_child(center)
	_rename_center = center

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(int(380 * s), 0)
	_style_panel(panel)
	center.add_child(panel)
	_rename_panel = panel

	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, int(22 * s))
	panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", int(12 * s))
	margin.add_child(vbox)

	var title := Label.new()
	title.text = "Rename world"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", Global.ui_font_size(15))
	title.add_theme_color_override("font_color", C_TITLE)
	vbox.add_child(title)

	_rename_input = LineEdit.new()
	_rename_input.max_length = 40
	_rename_input.placeholder_text = "World name"
	_rename_input.custom_minimum_size = Vector2(int(300 * s), int(34 * s))
	_rename_input.add_theme_font_size_override("font_size", Global.ui_font_size(13))
	_rename_input.text_submitted.connect(func(_t: String) -> void: _on_rename_save())
	_rename_input.focus_entered.connect(func() -> void:
		if _rename_scroll != null and is_instance_valid(_rename_scroll):
			_rename_scroll.call_deferred("ensure_control_visible", _rename_input))
	vbox.add_child(_rename_input)

	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", int(12 * s))
	vbox.add_child(row)
	var cancel := _make_menu_btn("Cancel", _on_rename_cancel)
	cancel.custom_minimum_size = Vector2(int(140 * s), int(38 * s))
	row.add_child(cancel)
	var save := _make_menu_btn("Save", _on_rename_save)
	save.custom_minimum_size = Vector2(int(140 * s), int(38 * s))
	row.add_child(save)
	_rename_overlay.visible = false

func _fit_rename_center() -> void:
	if _rename_center == null or not is_instance_valid(_rename_center):
		return
	var available_h: float = maxf(1.0,
		Global.ui_content_rect().size.y - _keyboard_inset)
	var panel_h: float = 0.0
	if _rename_panel != null and is_instance_valid(_rename_panel):
		panel_h = _rename_panel.get_combined_minimum_size().y
	var pad: float = 16.0 * Global.ui_scale
	_rename_center.custom_minimum_size = Vector2(0,
		maxf(available_h, panel_h + pad))
	if _rename_scroll != null and is_instance_valid(_rename_scroll):
		_rename_scroll.offset_bottom = -(Global.ui_safe_insets.w + _keyboard_inset)

func _open_rename_world(slot: int) -> void:
	_rename_slot = slot
	if _rename_input != null:
		_rename_input.text = Global.world_name_of(slot)
	if _rename_overlay != null:
		_rename_overlay.visible = true
	_fit_rename_center()
	if _rename_input != null:
		_rename_input.grab_focus()
		_rename_input.select_all()

func _on_rename_cancel() -> void:
	_rename_slot = -1
	if _rename_overlay != null:
		_rename_overlay.visible = false

func _on_rename_save() -> void:
	if _rename_slot < 0 or _rename_input == null:
		return
	if Global.rename_world(_rename_slot, _rename_input.text):
		_rename_slot = -1
		if _rename_overlay != null:
			_rename_overlay.visible = false
		_refresh_worlds()

# ── Settings overlay ──────────────────────────────────────────────
func _build_settings_overlay() -> void:
	_settings_overlay = _make_overlay()
	add_child(_settings_overlay)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	Global.apply_safe_area(center)
	_settings_overlay.add_child(center)
	var panel: Control = SETTINGS_PANEL_SCRIPT.new()
	panel.name = "SettingsPanel"
	panel.call("set_show_credits", true)
	panel.connect("close_requested", func() -> void: _settings_overlay.visible = false)
	panel.connect("credits_requested", _on_credits)
	center.add_child(panel)

func _build_leaderboard_overlay() -> void:
	var s: float = Global.ui_scale
	_leaderboard_overlay = _make_overlay()
	add_child(_leaderboard_overlay)

	var outer := MarginContainer.new()
	outer.set_anchors_preset(Control.PRESET_FULL_RECT)
	Global.apply_safe_area(outer)
	for side in ["left", "right", "top", "bottom"]:
		outer.add_theme_constant_override("margin_" + side, int(20 * s))
	_leaderboard_overlay.add_child(outer)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(int(460 * s), 0)
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
	title.text = "Leaderboards"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", Global.ui_font_size(20))
	title.add_theme_color_override("font_color", C_TITLE)
	vbox.add_child(title)

	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", int(6 * s))
	vbox.add_child(tabs)
	_lb_tabs = []
	for entry in [["Overall", "total_stars"], ["Dungeon", "blue_stars"], ["Quests", "yellow_stars"]]:
		var kind: String = str(entry[1])
		var tab := _make_menu_btn(str(entry[0]), _set_leaderboard_kind.bind(kind))
		tab.custom_minimum_size = Vector2(0, int(34 * s))
		tab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tab.add_theme_font_size_override("font_size", Global.ui_font_size(12))
		tabs.add_child(tab)
		_lb_tabs.append(tab)

	var div := ColorRect.new()
	div.color = C_DIVIDER
	div.custom_minimum_size = Vector2(0, int(1 * s))
	vbox.add_child(div)

	_lb_status = Label.new()
	_lb_status.text = ""
	_lb_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_lb_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_lb_status.add_theme_font_size_override("font_size", Global.ui_font_size(12))
	_lb_status.add_theme_color_override("font_color", C_MUTED)
	vbox.add_child(_lb_status)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vbox.add_child(scroll)
	_lb_list = VBoxContainer.new()
	_lb_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_lb_list.add_theme_constant_override("separation", int(4 * s))
	scroll.add_child(_lb_list)

	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", int(8 * s))
	vbox.add_child(footer)
	var refresh := _make_menu_btn("Refresh", func() -> void: _load_leaderboard())
	refresh.custom_minimum_size = Vector2(0, int(36 * s))
	refresh.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	refresh.add_theme_font_size_override("font_size", Global.ui_font_size(12))
	footer.add_child(refresh)
	var back := _make_menu_btn("< Back", func() -> void: _leaderboard_overlay.visible = false)
	back.custom_minimum_size = Vector2(0, int(36 * s))
	back.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	back.add_theme_font_size_override("font_size", Global.ui_font_size(12))
	footer.add_child(back)
	_update_lb_tabs()


func _update_lb_tabs() -> void:
	for i in range(_lb_tabs.size()):
		var active := (i == 0 and _lb_kind == "total_stars") \
			or (i == 1 and _lb_kind == "blue_stars") \
			or (i == 2 and _lb_kind == "yellow_stars")
		_lb_tabs[i].add_theme_color_override("font_color", C_TITLE if active else C_MUTED)
		_lb_tabs[i].add_theme_color_override("font_hover_color", C_TITLE)


func _set_leaderboard_kind(kind: String) -> void:
	_lb_kind = kind
	_update_lb_tabs()
	_load_leaderboard()


func _on_leaderboards() -> void:
	if not _ensure_online("Leaderboards need an online session. Sign in to see the live rankings."):
		return
	if _leaderboard_overlay != null:
		_leaderboard_overlay.visible = true
	_load_leaderboard()


func _load_leaderboard() -> void:
	if _lb_loading or _lb_list == null or not is_instance_valid(_lb_list):
		return
	if not _ensure_online("Sign in to load the live leaderboard."):
		return
	_lb_loading = true
	for c in _lb_list.get_children():
		_lb_list.remove_child(c)
		c.queue_free()
	if _lb_status != null:
		_lb_status.text = "Loading…"
		_lb_status.add_theme_color_override("font_color", C_MUTED)

	var result := await Supabase.get_leaderboard(_lb_kind, 100)
	_lb_loading = false
	if _lb_list == null or not is_instance_valid(_lb_list):
		return
	for c in _lb_list.get_children():
		_lb_list.remove_child(c)
		c.queue_free()

	if not result.ok:
		if result.status == 0:
			Global.set_cloud_status(Global.CloudStatus.OFFLINE, "No connection")
			_set_lb_status("Offline — the leaderboard needs a connection.")
		elif result.status == 401 or result.status == 403:
			Global.set_cloud_status(Global.CloudStatus.ERROR, "Session expired")
			_set_lb_status("Your session expired. Open Account and sign in again.")
		else:
			_set_lb_status("Could not load the leaderboard. Tap Refresh to retry.")
		return

	var rows: Array = result.data if result.data is Array else []
	if rows.is_empty():
		_set_lb_status("No players on this leaderboard yet.")
		return
	_set_lb_status("")
	var rank := 1
	for row_value in rows:
		if typeof(row_value) != TYPE_DICTIONARY:
			continue
		_lb_list.add_child(_make_lb_row(rank, row_value))
		rank += 1


func _set_lb_status(text: String) -> void:
	if _lb_status == null or not is_instance_valid(_lb_status):
		return
	_lb_status.text = text
	_lb_status.add_theme_color_override("font_color", C_WARN if text != "" else C_MUTED)


func _make_lb_row(rank: int, row: Dictionary) -> Control:
	var s: float = Global.ui_scale
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", int(8 * s))

	var rank_lbl := Label.new()
	rank_lbl.text = "#%d" % rank
	rank_lbl.custom_minimum_size = Vector2(int(42 * s), 0)
	rank_lbl.add_theme_font_size_override("font_size", Global.ui_font_size(12))
	rank_lbl.add_theme_color_override("font_color", C_MUTED)
	h.add_child(rank_lbl)

	var name_lbl := Label.new()
	name_lbl.text = str(row.get("username", "?"))
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_lbl.clip_text = true
	name_lbl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name_lbl.add_theme_font_size_override("font_size", Global.ui_font_size(12))
	name_lbl.add_theme_color_override("font_color", C_TITLE)
	h.add_child(name_lbl)

	if _lb_kind == "total_stars" or _lb_kind == "blue_stars":
		h.add_child(_star_stat(StarIcon.BLUE, int(row.get("blue_stars", 0))))
	if _lb_kind == "total_stars" or _lb_kind == "yellow_stars":
		h.add_child(_star_stat(StarIcon.YELLOW, int(row.get("yellow_stars", 0))))
	if _lb_kind == "total_stars":
		var total := Label.new()
		total.text = "(%d)" % int(row.get("total_stars", 0))
		total.add_theme_font_size_override("font_size", Global.ui_font_size(11))
		total.add_theme_color_override("font_color", C_MUTED)
		h.add_child(total)
	return h


func _star_stat(color: Color, value: int) -> Control:
	var s: float = Global.ui_scale
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", int(3 * s))
	var icon := StarIcon.new()
	row.add_child(icon)
	icon.setup(color, 13.0 * s)
	var label := Label.new()
	label.text = str(value)
	label.add_theme_font_size_override("font_size", Global.ui_font_size(12))
	label.add_theme_color_override("font_color", C_TITLE)
	row.add_child(label)
	return row


# ── Cloud saves overlay ───────────────────────────────────────────
func _build_cloud_overlay() -> void:
	var s: float = Global.ui_scale
	_cloud_overlay = _make_overlay()
	add_child(_cloud_overlay)

	var outer := MarginContainer.new()
	outer.set_anchors_preset(Control.PRESET_FULL_RECT)
	Global.apply_safe_area(outer)
	for side in ["left", "right", "top", "bottom"]:
		outer.add_theme_constant_override("margin_" + side, int(20 * s))
	_cloud_overlay.add_child(outer)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(int(480 * s), 0)
	_style_panel(panel)
	outer.add_child(panel)

	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, int(18 * s))
	panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", int(8 * s))
	margin.add_child(vbox)

	var title := Label.new()
	title.text = "Cloud Saves"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", Global.ui_font_size(20))
	title.add_theme_color_override("font_color", C_TITLE)
	vbox.add_child(title)

	_cloud_status = Label.new()
	_cloud_status.text = _cloud_status_text()
	_cloud_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_cloud_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_cloud_status.add_theme_font_size_override("font_size", Global.ui_font_size(11))
	_cloud_status.add_theme_color_override("font_color", Global.cloud_status_color())
	vbox.add_child(_cloud_status)

	_cloud_message = Label.new()
	_cloud_message.text = ""
	_cloud_message.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_cloud_message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_cloud_message.add_theme_font_size_override("font_size", Global.ui_font_size(11))
	_cloud_message.add_theme_color_override("font_color", C_MUTED)
	vbox.add_child(_cloud_message)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vbox.add_child(scroll)

	var body := VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", int(8 * s))
	scroll.add_child(body)

	body.add_child(_section_label("Uploaded cloud saves"))
	var cloud_note := _muted_label("Worlds sync automatically at startup. Download a copy to restore it on this device.")
	body.add_child(cloud_note)
	_cloud_remote_list = VBoxContainer.new()
	_cloud_remote_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_cloud_remote_list.add_theme_constant_override("separation", int(4 * s))
	body.add_child(_cloud_remote_list)

	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", int(8 * s))
	vbox.add_child(footer)
	var refresh := _make_menu_btn("Refresh", func() -> void: _refresh_cloud())
	refresh.custom_minimum_size = Vector2(0, int(36 * s))
	refresh.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	refresh.add_theme_font_size_override("font_size", Global.ui_font_size(12))
	footer.add_child(refresh)
	var back := _make_menu_btn("< Back", func() -> void: _cloud_overlay.visible = false)
	back.custom_minimum_size = Vector2(0, int(36 * s))
	back.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	back.add_theme_font_size_override("font_size", Global.ui_font_size(12))
	footer.add_child(back)


func _section_label(text: String) -> Label:
	var s: float = Global.ui_scale
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", Global.ui_font_size(13))
	label.add_theme_color_override("font_color", C_TITLE)
	return label


func _on_cloud_saves() -> void:
	if not _ensure_online("Cloud saves need an online session. Sign in to manage uploaded worlds."):
		return
	if _cloud_overlay != null:
		_cloud_overlay.visible = true
	_refresh_cloud()


# Read-only list of the account's uploaded cloud saves. Uploads are automatic
# (CloudSync), never a manual action from this screen.
func _refresh_cloud(silent: bool = false) -> void:
	if _cloud_busy:
		return
	_cloud_busy = true
	if not silent:
		_cloud_set_message("Refreshing…", C_MUTED)
	var result := await Supabase.list_saves()
	if _cloud_remote_list == null or not is_instance_valid(_cloud_remote_list):
		_cloud_busy = false
		return
	if result.ok and result.data is Array:
		_build_remote_rows(result.data)
		if not silent:
			_cloud_set_message("Cloud saves are up to date.", C_MUTED)
	else:
		_build_remote_error()
		if result.status == 0:
			Global.set_cloud_status(Global.CloudStatus.OFFLINE, "No connection")
		elif result.status == 401 or result.status == 403:
			Global.set_cloud_status(Global.CloudStatus.ERROR, "Session expired")
		else:
			Global.set_cloud_status(Global.CloudStatus.ERROR, "Cloud saves unavailable.")
		_cloud_set_message("Could not load cloud saves. Tap Refresh to retry.", C_ERROR)
	_cloud_busy = false


func _build_remote_rows(rows: Array) -> void:
	if _cloud_remote_list == null or not is_instance_valid(_cloud_remote_list):
		return
	for c in _cloud_remote_list.get_children():
		_cloud_remote_list.remove_child(c)
		c.queue_free()
	_cloud_remote_meta.clear()
	if rows.is_empty():
		_cloud_remote_list.add_child(_muted_label("No uploaded cloud saves yet. They will appear here after sync."))
		return
	var s: float = Global.ui_scale
	for row_value in rows:
		if typeof(row_value) != TYPE_DICTIONARY:
			continue
		var meta: Dictionary = row_value
		var slot: int = int(meta.get("slot", 0))
		if slot <= 0:
			continue
		_cloud_remote_meta[slot] = meta
		var sync_note := ""
		if Global.has_save(slot):
			var local_checksum := _local_checksum(slot)
			var local_uid := Global.world_uid_of(slot)
			var cloud_uid := str(meta.get("world_uid", "")).strip_edges()
			var local_rev := Global.save_revision_of(slot)
			var cloud_rev := maxi(0, int(meta.get("revision", 0)))
			if local_checksum == str(meta.get("checksum", "")):
				sync_note = "  \u00b7  in sync"
			elif local_uid.is_empty() or cloud_uid.is_empty():
				sync_note = "  \u00b7  legacy/unknown identity"
			elif local_uid != cloud_uid:
				sync_note = "  \u00b7  different world"
			elif cloud_rev > local_rev:
				sync_note = "  \u00b7  cloud newer"
			elif cloud_rev == local_rev:
				sync_note = "  \u00b7  conflict"
			else:
				sync_note = "  \u00b7  local newer"
		else:
			sync_note = "  \u00b7  local missing"

		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", int(6 * s))
		var info := Label.new()
		var cloud_name := str(meta.get("world_name", "")).strip_edges()
		var label_prefix := cloud_name if not cloud_name.is_empty() else "Slot %d" % slot
		info.text = "%s  \u00b7  slot %d  \u00b7  rev %d  \u00b7  %s%s" % [label_prefix, slot,
			int(meta.get("revision", 0)), _format_size(int(meta.get("size_bytes", 0))), sync_note]
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		info.clip_text = true
		info.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		info.tooltip_text = "Updated: %s" % _format_timestamp(str(meta.get("updated_at", "")))
		info.add_theme_font_size_override("font_size", Global.ui_font_size(11))
		info.add_theme_color_override("font_color", C_TITLE)
		row.add_child(info)

		var download := _small_btn("Download", _cloud_download.bind(slot), int(88 * s))
		row.add_child(download)
		var del_btn := _small_btn("Delete", _ask_cloud_delete.bind(slot), int(70 * s))
		del_btn.add_theme_color_override("font_color", C_ERROR)
		row.add_child(del_btn)
		_cloud_remote_list.add_child(row)


func _build_remote_error() -> void:
	if _cloud_remote_list == null or not is_instance_valid(_cloud_remote_list):
		return
	for c in _cloud_remote_list.get_children():
		_cloud_remote_list.remove_child(c)
		c.queue_free()
	_cloud_remote_list.add_child(_muted_label("Cloud saves could not be loaded."))


func _cloud_download(slot: int) -> void:
	if _cloud_busy or not _cloud_remote_meta.has(slot):
		return
	var remote: Dictionary = _cloud_remote_meta[slot]
	if Global.has_save(slot):
		if _local_checksum(slot) == str(remote.get("checksum", "")):
			_cloud_set_message("That world is already in sync.", C_MUTED)
			return
		_ask_confirm("Download cloud slot %d and replace the local world \"%s\"?\n\nThe current local save is kept as a .bak backup." % [slot, Global.world_name_of(slot)],
			_do_cloud_download.bind(slot))
		return
	_do_cloud_download(slot)


func _do_cloud_download(slot: int) -> void:
	if _cloud_busy:
		return
	_cloud_busy = true
	_cloud_set_message("Downloading cloud slot %d?" % slot, C_MUTED)
	Global.set_cloud_status(Global.CloudStatus.SYNCING, "Downloading world?")
	var remote_meta: Dictionary = _cloud_remote_meta.get(slot, {})
	var expected_checksum := str(remote_meta.get("checksum", ""))
	var result: Dictionary = await CloudSync.download_to_local(slot, expected_checksum)
	if not result.get("ok", false):
		_cloud_busy = false
		var err := str(result.get("error", ""))
		if err.contains("corrupt") or err.contains("invalid"):
			Global.set_cloud_status(Global.CloudStatus.ERROR, "Corrupt cloud save.")
		elif int(result.get("status", 0)) == 0:
			Global.set_cloud_status(Global.CloudStatus.OFFLINE, "No connection")
		else:
			Global.set_cloud_status(Global.CloudStatus.PENDING, "Download failed")
		_cloud_set_message("Download failed ? the local world is unchanged.", C_ERROR)
		return
	Global.set_cloud_status(Global.CloudStatus.SYNCED)
	_cloud_set_message("Downloaded cloud slot %d." % slot, C_OK)
	_cloud_busy = false
	await _refresh_cloud(true)
	_refresh_worlds()


func _ask_cloud_delete(slot: int) -> void:
	_ask_confirm("Delete cloud slot %d?\n\nLocal worlds are not affected.", _do_cloud_delete.bind(slot))


func _do_cloud_delete(slot: int) -> void:
	if _cloud_busy:
		return
	_cloud_busy = true
	Global.set_cloud_status(Global.CloudStatus.SYNCING, "Deleting cloud save…")
	var result := await Supabase.delete_save(slot)
	_cloud_busy = false
	if not result.ok:
		if result.status == 0:
			Global.set_cloud_status(Global.CloudStatus.OFFLINE, "No connection")
		else:
			Global.set_cloud_status(Global.CloudStatus.ERROR, "Delete failed")
		_cloud_set_message("Could not delete the cloud save.", C_ERROR)
		return
	Global.set_cloud_status(Global.CloudStatus.SYNCED)
	_cloud_set_message("Deleted cloud slot %d." % slot, C_OK)
	await _refresh_cloud(true)


func _cloud_set_message(text: String, color: Color) -> void:
	if _cloud_message == null or not is_instance_valid(_cloud_message):
		return
	_cloud_message.text = text
	_cloud_message.add_theme_color_override("font_color", color)


func _small_btn(label: String, callback: Callable, width: int) -> Button:
	var s: float = Global.ui_scale
	var btn := Button.new()
	btn.text = label
	btn.custom_minimum_size = Vector2(width, int(32 * s))
	btn.add_theme_font_size_override("font_size", Global.ui_font_size(11))
	btn.add_theme_color_override("font_color", C_TITLE)
	var normal := StyleBoxFlat.new()
	normal.bg_color = C_PANEL
	normal.border_color = C_BORDER
	normal.set_border_width_all(int(1 * s))
	normal.set_corner_radius_all(int(4 * s))
	var hover := StyleBoxFlat.new()
	hover.bg_color = C_BTN_H
	hover.border_color = C_TITLE
	hover.set_border_width_all(int(1 * s))
	hover.set_corner_radius_all(int(4 * s))
	btn.add_theme_stylebox_override("normal", normal)
	btn.add_theme_stylebox_override("hover", hover)
	btn.add_theme_stylebox_override("pressed", normal)
	btn.pressed.connect(callback)
	return btn


func _muted_label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", Global.ui_font_size(11))
	label.add_theme_color_override("font_color", C_MUTED)
	return label


func _local_checksum(slot: int) -> String:
	var path := "user://save_slot_%d.json" % slot
	if not FileAccess.file_exists(path):
		return ""
	return FileAccess.get_sha256(path)


func _format_size(bytes: int) -> String:
	if bytes >= 1024 * 1024:
		return "%.1f MB" % (float(bytes) / (1024.0 * 1024.0))
	if bytes >= 1024:
		return "%.1f KB" % (float(bytes) / 1024.0)
	return "%d B" % bytes


func _format_timestamp(iso: String) -> String:
	if iso.is_empty():
		return "unknown"
	return iso.replace("T", " ").substr(0, 16)


# ── Account overlay ───────────────────────────────────────────────
func _build_account_overlay() -> void:
	_account_overlay = _make_overlay()
	add_child(_account_overlay)
	_account_panel = load("res://scripts/online_account_panel.gd").new()
	_account_panel.name = "AccountPanel"
	_account_overlay.add_child(_account_panel)
	_account_panel.set_dim_enabled(false)
	_account_panel.authenticated.connect(_on_account_authenticated)
	_account_panel.cancelled.connect(_on_account_cancelled)
	_account_panel.logged_out.connect(_on_account_logged_out)
	_account_overlay.visible = false


func _dim_ignore() -> Control:
	var node := Control.new()
	node.set_anchors_preset(Control.PRESET_FULL_RECT)
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return node




# Offline-mode entry point. It uses the same account panel as the startup
# screen: check connectivity, reuse a valid cached session when possible, or
# show the username/password form. Offline play remains available throughout.
func _on_go_online() -> void:
	if Global.online_mode or _go_online_busy:
		return
	_go_online_busy = true
	if _go_online_btn != null and is_instance_valid(_go_online_btn):
		_go_online_btn.disabled = true
		_go_online_btn.text = "Connecting…"

	var connectivity := await Supabase.check_connectivity()
	if not is_inside_tree():
		return
	if not bool(connectivity.get("backend", false)):
		_finish_go_online()
		_open_account_overlay(
			"Sandee online is unavailable right now. Offline play and local worlds stay available.")
		return

	if Supabase.has_stored_session():
		if await Supabase.validate_session():
			_finish_go_online()
			await _on_account_authenticated()
			return
		# Expired/invalid cached token: clear it before showing the form.
		await Supabase.sign_out()
		if not is_inside_tree():
			return

	_finish_go_online()
	_open_account_overlay(
		"Sign in to switch to Online. Offline play and local worlds stay available.")


func _finish_go_online() -> void:
	_go_online_busy = false
	if _go_online_btn != null and is_instance_valid(_go_online_btn):
		_go_online_btn.disabled = false
		_go_online_btn.text = "Go Online"


func _on_play_offline() -> void:
	if not Global.online_mode:
		return
	Global.set_online_mode(false)
	Global.set_cloud_status(Global.CloudStatus.OFFLINE)
	CrashLogger.event("ONLINE", "Play Offline selected")
	if _cloud_overlay != null:
		_cloud_overlay.visible = false
	if _account_overlay != null:
		_account_overlay.visible = false
	_refresh_status_label()
	_refresh_online_visibility()
	_refresh_worlds()

func _on_account() -> void:
	if Global.online_mode and Supabase.is_signed_in():
		_open_account_overlay("")
	else:
		_open_account_overlay("Sign in to use online features. Local worlds stay available offline.")


func _open_account_overlay(message: String) -> void:
	if _account_overlay == null or _account_panel == null:
		return
	_account_overlay.visible = true
	if Global.online_mode and Supabase.is_signed_in():
		# Show the cached profile immediately, then refresh in the background so
		# the overlay never sits blank while a request is in flight.
		_account_panel.open_account()
		await Supabase.refresh_profile()
		if is_instance_valid(_account_panel) and _account_panel.visible:
			_account_panel.open_account()
	else:
		_account_panel.open_login(message)


func _on_account_cancelled() -> void:
	if _account_overlay != null:
		_account_overlay.visible = false


func _on_account_authenticated() -> void:
	Global.set_online_mode(true)
	Global.set_cloud_status(Global.CloudStatus.SYNCING, "Initializing cloud saves…")
	var panel_open: bool = _account_panel != null and _account_panel.visible
	if _account_panel != null:
		_account_panel.call("set_operation_progress", "Preparing cloud saves…", 5.0)
	var saves := await Supabase.list_saves()
	if not is_inside_tree():
		return
	if saves.ok:
		Global.set_cloud_status(Global.CloudStatus.ACTIVE)
		if _account_panel != null:
			_account_panel.call("set_operation_progress", "Syncing your worlds…", 5.0)
		# Startup/online sign-in is a sync barrier. Do not let the world list
		# become actionable until every local/cloud slot has been reconciled.
		await CloudSync.sync_all()
		if not is_inside_tree():
			return
	else:
		Global.set_cloud_status(Global.CloudStatus.ERROR, "Cloud saves unavailable.")
	if _account_panel != null:
		_account_panel.call("set_operation_progress", "", 100.0, false)
	_refresh_status_label()
	_refresh_worlds()
	if panel_open and _account_panel != null and _account_panel.visible:
		_account_panel.open_account()


func _on_cloud_sync_progress(info: Dictionary) -> void:
	if _account_panel == null or not is_instance_valid(_account_panel):
		return
	if not _account_panel.visible or not bool(_account_panel.call("is_busy")):
		return
	var stage := str(info.get("stage", ""))
	var done := maxi(0, int(info.get("done", 0)))
	var total := maxi(0, int(info.get("total", 0)))
	var value := 10.0
	if stage == "listing":
		value = 8.0
	elif stage == "syncing":
		value = 10.0 + 80.0 * (float(done) / float(maxi(1, total)))
	elif stage == "progress" or stage == "done":
		value = 92.0
	elif stage == "error" or stage == "offline":
		value = 100.0
	_account_panel.call("set_operation_progress", str(info.get("message", "")), value)


func _on_account_logged_out() -> void:
	Global.set_online_mode(false)
	Global.set_cloud_status(Global.CloudStatus.OFFLINE)
	_refresh_status_label()
	if _account_panel != null:
		_account_panel.open_login("Signed out. Your local worlds were kept.")


func _on_cloud_sync_completed(_summary: Dictionary) -> void:
	_refresh_worlds()
	if _cloud_overlay != null and _cloud_overlay.visible and not _cloud_busy:
		_refresh_cloud(true)

func _ensure_online(message: String) -> bool:
	if Global.online_mode and Supabase.is_signed_in():
		return true
	_open_account_overlay(message)
	return false


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
	btn.add_theme_font_size_override("font_size", Global.ui_type_size(Global.UI_TYPE_BODY))
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
	name_lbl.add_theme_font_size_override("font_size", Global.ui_font_size(15))
	name_lbl.add_theme_color_override("font_color", C_TITLE)
	name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(name_lbl)

	# Version metadata: created-with (else last-saved-with), else "Unknown
	# version" for a save made before this existed.
	var meta := Label.new()
	meta.text = "v%s  ·  %s" % [Global.world_version_of(slot), _last_played_text(slot)]
	meta.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	meta.add_theme_font_size_override("font_size", Global.ui_font_size(11))
	meta.add_theme_color_override("font_color", C_MUTED)
	meta.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(meta)

	row.add_child(btn)

	# Pencil: rename this world (opens a small dialog; persists to the slot).
	var ren := Button.new()
	ren.text = "✏"
	ren.tooltip_text = "Rename this world."
	ren.custom_minimum_size = Vector2(int(46 * s), int(62 * s))
	ren.size_flags_horizontal = Control.SIZE_SHRINK_END
	ren.add_theme_font_size_override("font_size", Global.ui_font_size(16))
	var rs := StyleBoxFlat.new()
	rs.bg_color     = C_PANEL
	rs.border_color = C_BORDER
	rs.set_border_width_all(int(1 * s)); rs.set_corner_radius_all(int(4 * s))
	var rsh := StyleBoxFlat.new()
	rsh.bg_color     = C_BTN_H
	rsh.border_color = C_TITLE
	rsh.set_border_width_all(int(1 * s)); rsh.set_corner_radius_all(int(4 * s))
	ren.add_theme_stylebox_override("normal",  rs)
	ren.add_theme_stylebox_override("hover",   rsh)
	ren.add_theme_stylebox_override("pressed", rs)
	ren.add_theme_color_override("font_color", C_TITLE)
	ren.pressed.connect(func() -> void: _open_rename_world(slot))
	row.add_child(ren)

	var del := Button.new()
	del.text = "Delete"
	del.custom_minimum_size = Vector2(int(78 * s), int(62 * s))
	del.size_flags_horizontal = Control.SIZE_SHRINK_END
	del.add_theme_font_size_override("font_size", Global.ui_font_size(12))
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
		empty.add_theme_font_size_override("font_size", Global.ui_font_size(13))
		empty.add_theme_color_override("font_color", C_MUTED)
		_worlds_list.add_child(empty)
	else:
		for slot in slots:
			_worlds_list.add_child(_make_world_row(slot))
	_update_create_state()
	if _continue_btn != null and is_instance_valid(_continue_btn):
		_continue_btn.disabled = Global.get_last_slot() == -1

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

# Android Back uses the same overlay order as Escape in the title menu.
func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		_close_top_overlay()

# Escape closes the topmost dismissible menu overlay, returning to its parent.
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("escape"):
		if _close_top_overlay():
			get_viewport().set_input_as_handled()

func _close_top_overlay() -> bool:
	if _confirm_overlay != null and _confirm_overlay.visible:
		_on_confirm_cancel()
		return true
	if _rename_overlay != null and _rename_overlay.visible:
		_on_rename_cancel()
		return true
	if _account_overlay != null and _account_overlay.visible:
		if _account_panel != null and _account_panel.visible \
				and bool(_account_panel.call("is_busy")):
			return true
		if _account_panel != null and _account_panel.visible:
			_account_panel.call("close")
		_account_overlay.visible = false
		return true
	if _cloud_overlay != null and _cloud_overlay.visible:
		_cloud_overlay.visible = false
		return true
	if _leaderboard_overlay != null and _leaderboard_overlay.visible:
		_leaderboard_overlay.visible = false
		return true
	if _credits_overlay != null and _credits_overlay.visible:
		_credits_overlay.visible = false
		return true
	if _settings_overlay != null and _settings_overlay.visible:
		_settings_overlay.visible = false
		return true
	if _worlds_overlay != null and _worlds_overlay.visible:
		_worlds_overlay.visible = false
		return true
	return false

# Stop the background pan with the scene (the Tween would be auto-killed anyway,
# but this keeps the "no duplicate loops" guarantee explicit).
func _exit_tree() -> void:
	_stop_pan()
