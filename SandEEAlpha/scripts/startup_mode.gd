extends Control
## Launch sign-in gate before the title menu. The game always starts in online
## mode: a stored session is restored, otherwise the player must sign in.
## The online gate is only enabled after BOTH checks pass:
##   1. the device has internet access,
##   2. the configured Supabase project answers its health endpoint.
## A failed check can be retried without leaving the screen; nothing here ever
## blocks the main thread (every request is an HTTPRequest coroutine). Offline
## play is available later from the main menu's online controls.

const C_BG      := Color(0.04, 0.06, 0.12, 1.00)
const C_PANEL   := Color(0.08, 0.10, 0.20, 0.97)
const C_BORDER  := Color(0.22, 0.32, 0.58, 1.00)
const C_TITLE   := Color(0.80, 0.90, 1.00, 1.00)
const C_MUTED   := Color(0.55, 0.65, 0.85, 1.00)
const C_OK      := Color(0.55, 0.95, 0.68, 1.00)
const C_WARN    := Color(0.98, 0.72, 0.35, 1.00)
const C_BTN_H   := Color(0.12, 0.18, 0.36, 1.00)

const MENU_SCENE := "res://scenes/ui/main_menu_ver.tscn"

var _ui_root: Control = null
var _mode_panel: PanelContainer = null
var _online_btn: Button = null
var _retry_btn: Button = null
var _status_label: Label = null
var _account_panel: Control = null
var _panorama: Node = null
var _bg_tex: TextureRect = null
var _progress_bar: ProgressBar = null

var _connectivity: Dictionary = {"internet": false, "backend": false, "detail": ""}
## Test seam: when non-empty, `_probe_connectivity()` uses this result instead of
## contacting the network. Empty during normal play.
var connectivity_override: Dictionary = {}
var _checking := false
var _busy := false
var _leaving := false
var _auto_prompted := false


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	Global.reset_pause_state()
	# Nothing online is true until the player actually gets through the flow.
	Global.set_online_mode(false)
	Global.set_cloud_status(Global.CloudStatus.OFFLINE)
	_build_background()
	_build_ui()
	_build_account_panel()
	if not Global.ui_scale_changed.is_connected(_on_ui_scale):
		Global.ui_scale_changed.connect(_on_ui_scale)
	if not CloudSync.sync_progress_changed.is_connected(_on_sync_progress):
		CloudSync.sync_progress_changed.connect(_on_sync_progress)
	_check_connectivity()


# ── Background ───────────────────────────────────────────────────────────

func _build_background() -> void:
	var holder := Control.new()
	holder.set_anchors_preset(Control.PRESET_FULL_RECT)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(holder)

	var base := ColorRect.new()
	base.color = C_BG
	base.set_anchors_preset(Control.PRESET_FULL_RECT)
	base.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(base)

	_bg_tex = TextureRect.new()
	_bg_tex.set_anchors_preset(Control.PRESET_FULL_RECT)
	_bg_tex.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_bg_tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_bg_tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_bg_tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(_bg_tex)

	var scrim := ColorRect.new()
	scrim.color = Color(C_BG.r, C_BG.g, C_BG.b, 0.62)
	scrim.set_anchors_preset(Control.PRESET_FULL_RECT)
	scrim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(scrim)

	# Reuse this launch's generated dungeon panoramas, or start generating them.
	_panorama = load("res://scripts/title_panorama.gd").new()
	_panorama.name = "TitlePanorama"
	add_child(_panorama)
	_panorama.connect("panorama_ready", _on_panorama_ready)
	var cached: Variant = _panorama.call("load_cached")
	if cached is Texture2D:
		_bg_tex.texture = cached
	_panorama.call("ensure_panorama")


func _on_panorama_ready(texture: Texture2D) -> void:
	if _bg_tex != null and is_instance_valid(_bg_tex):
		_bg_tex.texture = texture


# ── Foreground UI ────────────────────────────────────────────────────────

func _on_ui_scale(_scale: float) -> void:
	# The scale cannot change from this screen (there are no settings here), and
	# rebuilding mid-request would orphan the pending flow. Skip in that case.
	if _busy or (_account_panel != null and _account_panel.visible):
		return
	_build_ui()
	_apply_connectivity()


func _build_ui() -> void:
	if _ui_root != null and is_instance_valid(_ui_root):
		remove_child(_ui_root)
		_ui_root.queue_free()
	_ui_root = Control.new()
	_ui_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_ui_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_ui_root)

	var s: float = Global.ui_scale
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	Global.apply_safe_area(center)
	_ui_root.add_child(center)

	var vbox := VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", int(10 * s))
	vbox.custom_minimum_size = Vector2(int(380 * s), 0)
	center.add_child(vbox)

	var title := Label.new()
	title.text = "SandEE"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", int(minf(float(Global.ui_font_size(64)),
		maxf(48.0, get_viewport_rect().size.y * 0.12))))
	title.add_theme_color_override("font_color", C_TITLE)
	vbox.add_child(title)

	var sub := Label.new()
	sub.text = "Alpha  ·  v%s" % Global.game_version()
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.add_theme_font_size_override("font_size", Global.ui_font_size(14))
	sub.add_theme_color_override("font_color", C_MUTED)
	vbox.add_child(sub)

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, int(14 * s))
	vbox.add_child(spacer)

	_mode_panel = PanelContainer.new()
	_mode_panel.custom_minimum_size = Vector2(int(380 * s), 0)
	var style := StyleBoxFlat.new()
	style.bg_color = C_PANEL
	style.border_color = C_BORDER
	style.set_border_width_all(int(1 * s))
	style.set_corner_radius_all(int(6 * s))
	_mode_panel.add_theme_stylebox_override("panel", style)
	vbox.add_child(_mode_panel)

	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, int(20 * s))
	_mode_panel.add_child(margin)

	var inner := VBoxContainer.new()
	inner.add_theme_constant_override("separation", int(10 * s))
	margin.add_child(inner)

	var heading := Label.new()
	heading.text = "Sign in to play SandEE"
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	heading.add_theme_font_size_override("font_size", Global.ui_font_size(16))
	heading.add_theme_color_override("font_color", C_TITLE)
	inner.add_child(heading)

	var online_hint := Label.new()
	online_hint.text = "Sign in to sync your worlds, cloud saves and leaderboards."
	online_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	online_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	online_hint.add_theme_font_size_override("font_size", Global.ui_font_size(11))
	online_hint.add_theme_color_override("font_color", C_MUTED)
	inner.add_child(online_hint)

	_online_btn = _make_btn("Sign In / Play Online", _on_online, true)
	_online_btn.disabled = true
	inner.add_child(_online_btn)

	var status_row := HBoxContainer.new()
	status_row.alignment = BoxContainer.ALIGNMENT_CENTER
	status_row.add_theme_constant_override("separation", int(10 * s))
	inner.add_child(status_row)

	_status_label = Label.new()
	_status_label.text = "Checking connection…"
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status_label.custom_minimum_size = Vector2(int(250 * s), 0)
	_status_label.add_theme_font_size_override("font_size", Global.ui_font_size(11))
	_status_label.add_theme_color_override("font_color", C_MUTED)
	status_row.add_child(_status_label)

	_retry_btn = _make_btn("Retry", _on_retry, false)
	_retry_btn.custom_minimum_size = Vector2(int(90 * s), int(32 * s))
	_retry_btn.visible = false
	status_row.add_child(_retry_btn)

	_progress_bar = ProgressBar.new()
	_progress_bar.min_value = 0.0
	_progress_bar.max_value = 100.0
	_progress_bar.value = 0.0
	_progress_bar.show_percentage = false
	_progress_bar.custom_minimum_size = Vector2(int(340 * s), maxi(10, int(12 * s)))
	_progress_bar.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_progress_bar.visible = false
	var bar_bg := StyleBoxFlat.new()
	bar_bg.bg_color = Color(0.04, 0.06, 0.12, 1.0)
	bar_bg.border_color = C_BORDER
	bar_bg.set_border_width_all(1)
	bar_bg.set_corner_radius_all(int(4 * s))
	var bar_fill := StyleBoxFlat.new()
	bar_fill.bg_color = C_OK
	bar_fill.set_corner_radius_all(int(4 * s))
	_progress_bar.add_theme_stylebox_override("background", bar_bg)
	_progress_bar.add_theme_stylebox_override("fill", bar_fill)
	inner.add_child(_progress_bar)

	var footer := Label.new()
	footer.text = "Sign-in is required. You can switch to offline play from the main menu."
	footer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	footer.add_theme_font_size_override("font_size", Global.ui_font_size(10))
	footer.add_theme_color_override("font_color", Color(C_MUTED.r, C_MUTED.g, C_MUTED.b, 0.8))
	inner.add_child(footer)

	var version := Label.new()
	version.text = "SandEE v%s" % Global.game_version()
	version.add_theme_font_size_override("font_size", Global.ui_font_size(11))
	version.add_theme_color_override("font_color", C_MUTED)
	version.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	version.add_theme_constant_override("outline_size", int(3 * s))
	version.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	version.offset_left = int(Global.ui_safe_insets.x) + int(14 * s)
	version.offset_bottom = -int(Global.ui_safe_insets.w) - int(14 * s)
	version.grow_horizontal = Control.GROW_DIRECTION_END
	version.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_ui_root.add_child(version)


func _set_progress(show: bool, value: float = -1.0, text: String = "") -> void:
	if _progress_bar != null and is_instance_valid(_progress_bar):
		_progress_bar.visible = show
		if value >= 0.0:
			_progress_bar.value = clampf(value, 0.0, 100.0)
	if not text.is_empty():
		_set_status(text, C_MUTED)


func _on_sync_progress(info: Dictionary) -> void:
	if _progress_bar == null or not is_instance_valid(_progress_bar) or _leaving:
		return
	var stage := str(info.get("stage", ""))
	var done := maxi(0, int(info.get("done", 0)))
	var total := maxi(0, int(info.get("total", 0)))
	var message := str(info.get("message", ""))
	var value := 20.0
	if stage == "listing":
		value = 10.0
	elif stage == "syncing":
		value = 20.0 + 65.0 * (float(done) / float(maxi(1, total)))
	elif stage == "progress" or stage == "done":
		value = 90.0
	elif stage == "error" or stage == "offline":
		value = 100.0
	_progress_bar.visible = true
	_progress_bar.value = value
	if not message.is_empty():
		_set_status(message, C_MUTED)


func _build_account_panel() -> void:
	_account_panel = load("res://scripts/online_account_panel.gd").new()
	_account_panel.name = "AccountPanel"
	_account_panel.z_index = 20
	_account_panel.set_dim_enabled(true)
	add_child(_account_panel)
	_account_panel.authenticated.connect(_on_authenticated)
	_account_panel.cancelled.connect(_on_login_cancelled)
	_account_panel.logged_out.connect(_on_login_cancelled)


func _make_btn(label: String, callback: Callable, primary: bool) -> Button:
	var s: float = Global.ui_scale
	var btn := Button.new()
	btn.text = label
	btn.custom_minimum_size = Vector2(int(340 * s), int(42 * s))
	btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	btn.add_theme_font_size_override("font_size", Global.ui_font_size(15))
	btn.add_theme_color_override("font_color", C_TITLE)
	btn.add_theme_color_override("font_hover_color", C_TITLE)
	btn.add_theme_color_override("font_disabled_color", Color(C_MUTED.r, C_MUTED.g, C_MUTED.b, 0.45))
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0.12, 0.18, 0.36, 1.0) if primary else C_PANEL
	normal.border_color = C_BORDER
	normal.set_border_width_all(int(1 * s))
	normal.set_corner_radius_all(int(4 * s))
	normal.content_margin_top = int(8 * s)
	normal.content_margin_bottom = int(8 * s)
	var hover := StyleBoxFlat.new()
	hover.bg_color = C_BTN_H
	hover.border_color = C_TITLE
	hover.set_border_width_all(int(1 * s))
	hover.set_corner_radius_all(int(4 * s))
	hover.content_margin_top = int(8 * s)
	hover.content_margin_bottom = int(8 * s)
	btn.add_theme_stylebox_override("normal", normal)
	btn.add_theme_stylebox_override("hover", hover)
	btn.add_theme_stylebox_override("pressed", normal)
	btn.add_theme_stylebox_override("disabled", normal)
	btn.pressed.connect(callback)
	return btn


# ── Connectivity ─────────────────────────────────────────────────────────

func _check_connectivity() -> void:
	if _checking or _leaving:
		return
	_checking = true
	_set_status("Checking connection…", C_MUTED)
	if _online_btn != null:
		_online_btn.disabled = true
	if _retry_btn != null:
		_retry_btn.visible = false
	_connectivity = await _probe_connectivity()
	if not is_inside_tree():
		return
	_checking = false
	_apply_connectivity()


func _probe_connectivity() -> Dictionary:
	if not connectivity_override.is_empty():
		return connectivity_override
	return await Supabase.check_connectivity()


func _apply_connectivity() -> void:
	if _online_btn == null or _status_label == null:
		return
	if _busy or _leaving:
		return
	if _connectivity.get("backend", false):
		_online_btn.disabled = false
		_retry_btn.visible = false
		_set_status("Online services available.", C_OK)
		if not _auto_prompted:
			_auto_prompted = true
			call_deferred("_auto_prompt_login")
	elif _connectivity.get("internet", false):
		_online_btn.disabled = true
		_retry_btn.visible = true
		_set_status("Sandee online is unavailable right now. Try again later.", C_WARN)
	else:
		_online_btn.disabled = true
		_retry_btn.visible = true
		_set_status("Internet connection required.", C_MUTED)


func _set_status(text: String, color: Color) -> void:
	if _status_label == null or not is_instance_valid(_status_label):
		return
	_status_label.text = text
	_status_label.add_theme_color_override("font_color", color)


func _set_mode_buttons_enabled(enabled: bool) -> void:
	if _online_btn != null:
		_online_btn.disabled = not enabled or not bool(_connectivity.get("backend", false))
	if _retry_btn != null:
		_retry_btn.disabled = not enabled


# ── Mode actions ─────────────────────────────────────────────────────────

func _on_retry() -> void:
	if _checking or _busy or _leaving:
		return
	_check_connectivity()


func _auto_prompt_login() -> void:
	if not is_inside_tree() or _leaving or _busy \
			or (_account_panel != null and _account_panel.visible):
		return
	if Supabase.has_stored_session() or bool(_connectivity.get("backend", false)):
		_on_online()

func _on_online() -> void:
	if _busy or _leaving or (_online_btn != null and _online_btn.disabled):
		return
	_busy = true
	_set_mode_buttons_enabled(false)
	_set_progress(true, 5.0)
	_set_status("Checking online services…", C_MUTED)

	var connectivity := await _probe_connectivity()
	if not is_inside_tree():
		return
	if not connectivity.get("backend", false):
		_connectivity = connectivity
		_busy = false
		_set_progress(false)
		_set_mode_buttons_enabled(true)
		_apply_connectivity()
		return

	if Supabase.has_stored_session():
		_set_status("Restoring session…", C_MUTED)
		var restored := await Supabase.validate_session()
		if not is_inside_tree():
			return
		if restored:
			_busy = false
			await _enter_online()
			return
		# The stored token is expired/invalid: clear it before showing the form.
		await Supabase.sign_out()
		if not is_inside_tree():
			return

	_busy = false
	_show_login("Sign in to play SandEE. An online account is required.")


func _show_login(message: String) -> void:
	_busy = false
	_set_progress(false)
	_set_mode_buttons_enabled(true)
	# Without this the screen kept saying "Restoring session…" behind the panel,
	# which looked like an endless restore when there was simply no session.
	_set_status("Sign in to play SandEE.", C_MUTED)
	if _account_panel != null:
		_account_panel.open_login(message)


func _on_login_cancelled() -> void:
	if _account_panel != null and _account_panel.visible:
		_account_panel.close()
	_busy = false
	_set_progress(false)
	_set_mode_buttons_enabled(true)
	_apply_connectivity()


func _on_authenticated() -> void:
	if _account_panel != null:
		_account_panel.close()
	_busy = false
	await _enter_online()


func _enter_online() -> void:
	if _leaving:
		return
	_busy = true
	_set_mode_buttons_enabled(false)
	Global.set_online_mode(true)
	_set_progress(true, 10.0)
	Global.set_cloud_status(Global.CloudStatus.SYNCING, "Initializing cloud saves…")
	_set_status("Setting up your online account…", C_MUTED)

	var profile_result := await Supabase.refresh_profile()
	if not is_inside_tree():
		return
	if not profile_result.ok:
		var auth_failed: bool = profile_result.status == 401 or profile_result.status == 403
		if auth_failed:
			await Supabase.sign_out()
			Global.set_online_mode(false)
			Global.set_cloud_status(Global.CloudStatus.OFFLINE)
			_busy = false
			_show_login("Your session expired. Sign in again.")
			return
		# Signed in, but the profile could not be fetched (service/network).
		Global.set_cloud_status(Global.CloudStatus.ERROR, "Could not load your profile.")
		_set_progress(true, 100.0, "Continuing without cloud saves...")
		await _go_to_menu()
		return

	# Initialize cloud-save metadata. A failure must not claim cloud saving works.
	var saves_result := await Supabase.list_saves()
	if not is_inside_tree():
		return
	var cloud_ok: bool = saves_result.ok and saves_result.data is Array
	if cloud_ok:
		Global.set_cloud_status(Global.CloudStatus.ACTIVE)
		# Startup is a sync barrier: every local world is uploaded and every
		# automatically-resolvable cloud world is downloaded before the menu.
		_set_progress(true, 10.0, "Syncing your worlds...")
		await CloudSync.sync_all()
		if not is_inside_tree():
			return
		_set_progress(true, 90.0, "Finishing cloud sync...")
	else:
		Global.set_cloud_status(Global.CloudStatus.ERROR, "Cloud saves could not be initialized.")
		_set_progress(true, 90.0, "Continuing without cloud sync...")

	# Warm the leaderboard cache before the menu (the overlay reloads live data).
	_set_progress(true, 95.0, "Preparing the main menu...")
	await Supabase.get_leaderboard("total_stars", 25)

	_busy = false
	_set_progress(true, 100.0, "Ready.")
	await _go_to_menu()


func _go_to_menu() -> void:
	if _leaving:
		return
	_leaving = true
	_set_mode_buttons_enabled(false)
	var err := get_tree().change_scene_to_file(MENU_SCENE)
	if err != OK:
		_leaving = false
		_busy = false
		_set_mode_buttons_enabled(true)
		_set_status("Could not open the main menu. Please try again.", C_WARN)
