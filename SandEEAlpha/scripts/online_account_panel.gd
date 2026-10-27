extends Control
## Reusable online account panel: sign in, register with a username/password and
## the signed-in account view. Supabase's internal email identifier is derived
## from the username (see supabase_client.register) and never shown.
##
## Used by the startup mode screen and by the main menu's Account overlay, so
## there is exactly one implementation of the credential forms. Passwords are
## only kept in the LineEdit nodes while the screen is open: they are cleared on
## success, on cancel and when the panel is hidden. Nothing is logged.

signal authenticated
signal cancelled
signal logged_out

enum Mode { LOGIN, REGISTER, ACCOUNT }

const C_PANEL   := Color(0.08, 0.10, 0.20, 0.98)
const C_BORDER  := Color(0.22, 0.32, 0.58, 1.00)
const C_TITLE   := Color(0.80, 0.90, 1.00, 1.00)
const C_MUTED   := Color(0.55, 0.65, 0.85, 1.00)
const C_ERROR   := Color(1.00, 0.48, 0.48, 1.00)
const C_OK      := Color(0.55, 0.95, 0.68, 1.00)

const USERNAME_MIN := 3
const USERNAME_MAX := 24
const PASSWORD_MIN := 6
const PASSWORD_MAX := 72

var _mode: Mode = Mode.LOGIN
var _busy := false
var _dim_enabled := true
var _notice_text := ""
var _error_text := ""
var _fields: Dictionary = {}
var _buttons: Array[Button] = []
var _busy_label: Label = null
var _busy_bar: ProgressBar = null
var _error_label: Label = null
var _notice_label: Label = null
var _content: VBoxContainer = null
var _panel: PanelContainer = null
var _center: CenterContainer = null
var _scroll: ScrollContainer = null
var _keyboard_inset: float = 0.0


func _ready() -> void:
	# MUST set anchors AND offsets: `set_anchors_preset()` alone keeps the
	# control's current (zero) rect, producing negative offsets and a 0×0 panel
	# once the node is already inside the tree.
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	_build()
	_fit_center()
	if not Global.ui_scale_changed.is_connected(_on_scale_changed):
		Global.ui_scale_changed.connect(_on_scale_changed)
	if not get_viewport().size_changed.is_connected(_fit_center):
		get_viewport().size_changed.connect(_fit_center)


func _fit_center() -> void:
	var available_h: float = maxf(1.0,
		Global.ui_content_rect().size.y - _keyboard_inset)
	if _center != null and is_instance_valid(_center):
		# The centre must be at least as tall as the panel. Otherwise a tall
		# form (especially with the keyboard up) is centred around a negative
		# offset and its top fields land above the screen with no way to scroll
		# back to them.
		var pad: float = 16.0 * Global.ui_scale
		var panel_h: float = 0.0
		if _panel != null and is_instance_valid(_panel):
			panel_h = _panel.get_combined_minimum_size().y
		_center.custom_minimum_size = Vector2(0,
			maxf(available_h, panel_h + pad))
	if _scroll != null and is_instance_valid(_scroll):
		_scroll.offset_left = Global.ui_safe_insets.x
		_scroll.offset_top = Global.ui_safe_insets.y
		_scroll.offset_right = -Global.ui_safe_insets.z
		_scroll.offset_bottom = -(Global.ui_safe_insets.w + _keyboard_inset)


func _ensure_field_visible(field: Control) -> void:
	if not visible or _scroll == null or field == null:
		return
	if not is_instance_valid(field) or not field.is_inside_tree():
		return
	_scroll.call_deferred("ensure_control_visible", field)


func _ensure_focused_field_visible() -> void:
	var focused := get_viewport().gui_get_focus_owner()
	if focused is LineEdit and _content != null and _content.is_ancestor_of(focused):
		_ensure_field_visible(focused as Control)


func _process(_delta: float) -> void:
	if not visible:
		return
	var inset: float = Global.mobile_keyboard_height()
	if not is_equal_approx(inset, _keyboard_inset):
		_keyboard_inset = inset
		_fit_center()
		_ensure_focused_field_visible()


## The parent already dims/blocks input (main-menu overlays); skip the extra dim.
func set_dim_enabled(enabled: bool) -> void:
	_dim_enabled = enabled
	_build()


func open_login(message: String = "") -> void:
	_mode = Mode.LOGIN
	_notice_text = message
	_error_text = ""
	visible = true
	_build()
	_focus_first()


func open_register() -> void:
	_mode = Mode.REGISTER
	_notice_text = ""
	_error_text = ""
	visible = true
	_build()
	_focus_first()


func open_account() -> void:
	_mode = Mode.ACCOUNT
	_notice_text = ""
	_error_text = ""
	visible = true
	_build()
	_focus_first()


func close() -> void:
	_clear_passwords()
	visible = false
	_keyboard_inset = 0.0
	_fit_center()


func is_busy() -> bool:
	return _busy


# ── Layout ───────────────────────────────────────────────────────────────

func _on_scale_changed(_scale: float) -> void:
	if not visible or _busy:
		return
	# Keep whatever the player already typed (never the password), so a scale
	# change while a UI setting is open cannot wipe their username.
	var kept: Dictionary = {}
	for key: String in _fields:
		if key.contains("password") or key == "confirm":
			continue
		kept[key] = (_fields[key] as LineEdit).text
	_build()
	for key: String in kept:
		if _fields.has(key):
			(_fields[key] as LineEdit).text = str(kept[key])


func _build() -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	_fields.clear()
	_buttons.clear()
	_error_label = null
	_notice_label = null
	_busy_label = null
	_busy_bar = null

	var s: float = Global.ui_scale
	if _dim_enabled:
		var dim := ColorRect.new()
		dim.color = Color(0.0, 0.0, 0.0, 0.55)
		dim.mouse_filter = Control.MOUSE_FILTER_STOP
		dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		add_child(dim)

	var scroll := ScrollContainer.new()
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	Global.apply_safe_area(scroll)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	_scroll = scroll

	_center = CenterContainer.new()
	_center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_center.custom_minimum_size = Vector2(0, 1)
	scroll.add_child(_center)

	_panel = PanelContainer.new()
	_panel.custom_minimum_size = Vector2(int(400 * s), 0)
	var style := StyleBoxFlat.new()
	style.bg_color = C_PANEL
	style.border_color = C_BORDER
	style.set_border_width_all(int(1 * s))
	style.set_corner_radius_all(int(6 * s))
	_panel.add_theme_stylebox_override("panel", style)
	_center.add_child(_panel)

	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, int(22 * s))
	_panel.add_child(margin)

	_content = VBoxContainer.new()
	_content.add_theme_constant_override("separation", int(10 * s))
	_content.custom_minimum_size = Vector2(int(340 * s), 0)
	margin.add_child(_content)

	match _mode:
		Mode.LOGIN:
			_build_login()
		Mode.REGISTER:
			_build_register()
		Mode.ACCOUNT:
			_build_account()
	# Scale the centre to the live keyboard inset now that the panel's real
	# minimum height is known.
	_fit_center()


func _make_title(text: String) -> void:
	var s: float = Global.ui_scale
	var title := Label.new()
	title.text = text
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", Global.ui_font_size(20))
	title.add_theme_color_override("font_color", C_TITLE)
	_content.add_child(title)


func _make_note(text: String, color: Color = C_MUTED) -> Label:
	var s: float = Global.ui_scale
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size = Vector2(int(340 * s), 0)
	label.add_theme_font_size_override("font_size", Global.ui_font_size(11))
	label.add_theme_color_override("font_color", color)
	_content.add_child(label)
	return label


func _make_field(key: String, placeholder: String, secret: bool = false) -> LineEdit:
	var s: float = Global.ui_scale
	var edit := LineEdit.new()
	edit.placeholder_text = placeholder
	edit.secret = secret
	edit.custom_minimum_size = Vector2(int(340 * s), int(38 * s))
	edit.add_theme_font_size_override("font_size", Global.ui_font_size(13))
	edit.max_length = PASSWORD_MAX if secret else USERNAME_MAX
	edit.text_submitted.connect(func(_t: String) -> void: _submit_current_mode())
	edit.focus_entered.connect(_ensure_field_visible.bind(edit))
	_fields[key] = edit
	_content.add_child(edit)
	return edit


func _make_show_password_toggle() -> void:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_END
	_content.add_child(row)
	var toggle := CheckButton.new()
	toggle.text = "Show password"
	toggle.add_theme_font_size_override("font_size", Global.ui_font_size(11))
	toggle.toggled.connect(func(on: bool) -> void:
		for key: String in ["password", "confirm"]:
			if _fields.has(key):
				(_fields[key] as LineEdit).secret = not on)
	row.add_child(toggle)


func _make_button(label: String, callback: Callable, primary: bool = false) -> Button:
	var s: float = Global.ui_scale
	var btn := Button.new()
	btn.text = label
	btn.custom_minimum_size = Vector2(int(340 * s), int(40 * s))
	btn.add_theme_font_size_override("font_size", Global.ui_font_size(14))
	btn.add_theme_color_override("font_color", C_TITLE if primary else C_MUTED)
	btn.add_theme_color_override("font_hover_color", C_TITLE)
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0.12, 0.18, 0.36, 1.0) if primary else C_PANEL
	normal.border_color = C_BORDER
	normal.set_border_width_all(int(1 * s))
	normal.set_corner_radius_all(int(4 * s))
	normal.content_margin_top = int(7 * s)
	normal.content_margin_bottom = int(7 * s)
	var hover := StyleBoxFlat.new()
	hover.bg_color = Color(0.18, 0.26, 0.48, 1.0)
	hover.border_color = C_TITLE
	hover.set_border_width_all(int(1 * s))
	hover.set_corner_radius_all(int(4 * s))
	hover.content_margin_top = int(7 * s)
	hover.content_margin_bottom = int(7 * s)
	btn.add_theme_stylebox_override("normal", normal)
	btn.add_theme_stylebox_override("hover", hover)
	btn.add_theme_stylebox_override("pressed", normal)
	btn.add_theme_stylebox_override("disabled", normal)
	btn.pressed.connect(callback)
	_content.add_child(btn)
	_buttons.append(btn)
	return btn


func _make_link(label: String, callback: Callable) -> Button:
	var s: float = Global.ui_scale
	var btn := Button.new()
	btn.text = label
	btn.flat = true
	btn.custom_minimum_size = Vector2(int(340 * s), int(28 * s))
	btn.add_theme_font_size_override("font_size", Global.ui_font_size(12))
	btn.add_theme_color_override("font_color", C_MUTED)
	btn.add_theme_color_override("font_hover_color", C_TITLE)
	btn.pressed.connect(callback)
	_content.add_child(btn)
	_buttons.append(btn)
	return btn


func _make_error_and_busy() -> void:
	var s: float = Global.ui_scale
	_error_label = _make_note(_error_text, C_ERROR)
	_error_label.visible = not _error_text.is_empty()
	_busy_label = _make_note("", C_MUTED)
	_busy_label.visible = false
	_busy_bar = ProgressBar.new()
	_busy_bar.min_value = 0.0
	_busy_bar.max_value = 100.0
	_busy_bar.value = 0.0
	_busy_bar.show_percentage = false
	_busy_bar.indeterminate = true
	_busy_bar.custom_minimum_size = Vector2(int(340 * s), maxi(10, int(11 * s)))
	_busy_bar.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_busy_bar.visible = false
	var bar_bg := StyleBoxFlat.new()
	bar_bg.bg_color = Color(0.04, 0.06, 0.12, 1.0)
	bar_bg.border_color = C_BORDER
	bar_bg.set_border_width_all(1)
	bar_bg.set_corner_radius_all(int(4 * s))
	var bar_fill := StyleBoxFlat.new()
	bar_fill.bg_color = C_OK
	bar_fill.set_corner_radius_all(int(4 * s))
	_busy_bar.add_theme_stylebox_override("background", bar_bg)
	_busy_bar.add_theme_stylebox_override("fill", bar_fill)
	_content.add_child(_busy_bar)
	if _notice_text != "":
		_notice_label = _make_note(_notice_text, C_OK)


# ── Modes ────────────────────────────────────────────────────────────────

func _build_login() -> void:
	_make_title("Sign in")
	if _notice_text.is_empty() and _error_text.is_empty():
		_make_note("Use your SandEE online account.")
	var username := _make_field("username", "Username")
	username.max_length = USERNAME_MAX
	var password := _make_field("password", "Password", true)
	_make_show_password_toggle()
	_make_error_and_busy()
	_make_button("Sign In", _submit_login, true)
	_make_link("Create an account", func() -> void: open_register())
	_make_link("< Back", _on_back)


func _build_register() -> void:
	_make_title("Create account")
	_make_note("No email needed — your username is your login.")
	var username := _make_field("username", "Username (3-24 letters, numbers, _)")
	username.max_length = USERNAME_MAX
	var password := _make_field("password", "Password (at least 6 characters)", true)
	var confirm := _make_field("confirm", "Confirm password", true)
	_make_show_password_toggle()
	_make_error_and_busy()
	_make_button("Create Account", _submit_register, true)
	_make_link("< Back to sign in", func() -> void: open_login())


func _build_account() -> void:
	var s: float = Global.ui_scale
	_make_title("Account")
	var name_label := Label.new()
	name_label.text = Supabase.display_username()
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.add_theme_font_size_override("font_size", Global.ui_font_size(18))
	name_label.add_theme_color_override("font_color", C_TITLE)
	_content.add_child(name_label)

	var stars := HBoxContainer.new()
	stars.alignment = BoxContainer.ALIGNMENT_CENTER
	stars.add_theme_constant_override("separation", int(8 * s))
	_content.add_child(stars)
	_add_star_stat(stars, StarIcon.BLUE, int(Supabase.profile.get("blue_stars", 0)))
	_add_star_stat(stars, StarIcon.YELLOW, int(Supabase.profile.get("yellow_stars", 0)))

	_make_note("Signing out keeps every local world. Unsaved cloud changes stay pending until you sign in again.")
	_make_error_and_busy()
	_make_button("Log Out", _submit_logout, true)
	_make_link("< Back", _on_back)


func _add_star_stat(parent: HBoxContainer, color: Color, value: int) -> void:
	var s: float = Global.ui_scale
	var icon := StarIcon.new()
	parent.add_child(icon)
	icon.setup(color, 16.0 * s)
	var label := Label.new()
	label.text = str(value)
	label.add_theme_font_size_override("font_size", Global.ui_font_size(13))
	label.add_theme_color_override("font_color", C_TITLE)
	parent.add_child(label)


# ── Actions ──────────────────────────────────────────────────────────────

func _submit_current_mode() -> void:
	match _mode:
		Mode.LOGIN:
			_submit_login()
		Mode.REGISTER:
			_submit_register()


func _submit_login() -> void:
	if _busy:
		return
	var user_value: String = (_fields["username"] as LineEdit).text.strip_edges()
	var password: String = (_fields["password"] as LineEdit).text
	if user_value.is_empty() or password.is_empty():
		_show_error("Enter your username and password.")
		return
	_set_busy(true, "Signing in…")
	var result: Dictionary = await Supabase.sign_in(user_value, password)
	if not result.ok:
		_set_busy(false)
		_show_error(_auth_error_text(result))
		return
	await Supabase.refresh_profile()
	_clear_fields()
	_set_busy(false)
	authenticated.emit()


func _submit_register() -> void:
	if _busy:
		return
	var user_value: String = (_fields["username"] as LineEdit).text.strip_edges()
	var password: String = (_fields["password"] as LineEdit).text
	var confirm: String = (_fields["confirm"] as LineEdit).text
	if not _valid_username(user_value):
		_show_error("Usernames must be 3-24 characters: letters, numbers or underscore.")
		return
	if password.length() < PASSWORD_MIN:
		_show_error("Passwords must be at least %d characters." % PASSWORD_MIN)
		return
	if password.length() > PASSWORD_MAX:
		_show_error("Passwords can be at most %d characters." % PASSWORD_MAX)
		return
	if password != confirm:
		_show_error("The passwords do not match.")
		return

	_set_busy(true, "Checking username…")
	var available := await Supabase.username_available(user_value)
	if Supabase.last_username_check_error != "":
		_set_busy(false)
		_show_error(_network_error_text())
		return
	if not available:
		_set_busy(false)
		_show_error("That username is already taken.")
		return

	_set_busy(true, "Creating account…")
	var result: Dictionary = await Supabase.register(user_value, password)
	if not result.ok:
		_set_busy(false)
		_show_error(_register_error_text(result))
		return
	_clear_fields()
	if not Supabase.is_signed_in():
		# The project can require email confirmation; no session was issued.
		_set_busy(false)
		open_login("Account created, but sign-in was not completed. Try signing in again.")
		return
	await Supabase.refresh_profile()
	_set_busy(false)
	authenticated.emit()


func _submit_logout() -> void:
	if _busy:
		return
	_set_busy(true, "Signing out…")
	await Supabase.sign_out()
	_set_busy(false)
	logged_out.emit()


func _on_back() -> void:
	close()
	cancelled.emit()


func _input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("escape"):
		get_viewport().set_input_as_handled()
		# Authentication and the initial sync are a barrier: don't let Escape
		# dismiss the panel while a request/world sync is still in flight.
		if _busy:
			return
		_on_back()


# ── Helpers ──────────────────────────────────────────────────────────────

func _set_busy(on: bool, text: String = "") -> void:
	_busy = on
	for btn in _buttons:
		btn.disabled = on
	if _busy_label != null:
		_busy_label.text = text
		_busy_label.visible = on
	if _busy_bar != null:
		_busy_bar.visible = on
		_busy_bar.indeterminate = on
		if not on:
			_busy_bar.value = 0.0
	# The busy bar changes the panel height; keep the scroll range correct.
	_fit_center()


## Public determinate progress hook used by the main menu while it finishes the
## initial cloud upload/download batch. A negative value keeps the bar
## indeterminate for ordinary auth requests.
func set_operation_progress(text: String, value: float = -1.0, active: bool = true) -> void:
	_set_busy(active, text)
	if _busy_bar == null:
		return
	if value >= 0.0:
		_busy_bar.indeterminate = false
		_busy_bar.value = clampf(value, 0.0, 100.0)


func _show_error(text: String) -> void:
	_error_text = text
	if _error_label != null:
		_error_label.text = text
		_error_label.visible = true
	if _notice_label != null:
		_notice_label.visible = false
	_fit_center()
	_ensure_focused_field_visible()


func _clear_passwords() -> void:
	for key: String in _fields:
		if key.contains("password") or key == "confirm":
			(_fields[key] as LineEdit).text = ""


func _clear_fields() -> void:
	for key: String in _fields:
		(_fields[key] as LineEdit).text = ""


func _focus_first() -> void:
	if not is_inside_tree():
		return
	var tree := get_tree()
	if tree == null:
		return
	await tree.process_frame
	if not is_inside_tree() or not visible:
		return
	if _fields.has("username"):
		var username := _fields["username"] as LineEdit
		username.grab_focus()
		_ensure_field_visible(username)


func _valid_username(value: String) -> bool:
	if value.length() < USERNAME_MIN or value.length() > USERNAME_MAX:
		return false
	for i in range(value.length()):
		var c := value[i]
		var ok := (c >= "a" and c <= "z") or (c >= "A" and c <= "Z") \
			or (c >= "0" and c <= "9") or c == "_"
		if not ok:
			return false
	return true


func _network_error_text() -> String:
	return "Could not reach SandEE online. Check your connection and try again."


func _auth_error_text(result: Dictionary) -> String:
	if result.status == 429:
		return "Too many attempts. Wait a moment and try again."
	if result.status == 0 or str(result.error).begins_with("offline"):
		return _network_error_text()
	if result.status >= 500:
		return "The online service is temporarily unavailable."
	# Deliberately generic: never reveal whether a username exists.
	return "Incorrect username or password."


func _register_error_text(result: Dictionary) -> String:
	var message := str(result.error).to_lower()
	if message.contains("already registered") or message.contains("already exists") \
			or message.contains("duplicate"):
		return "That username is already taken."
	if message.contains("password"):
		return "Supabase rejected that password. Use at least 6 characters."
	if result.status == 0 or message.begins_with("offline"):
		return _network_error_text()
	return "Could not create the account. Check your details and try again."
