extends CanvasLayer
class_name NotificationHUD

# ── Top-of-screen gameplay notifications ─────────────────────────
# Player-facing feedback (fishing catches, farming, deaths, build-mode
# warnings, item messages) appears here as a short stack of toasts at the top
# centre of the screen instead of being buried in the debug chat. The chat
# console keeps command/debug output only.
#
# Toasts are created on demand from Global.notification_posted; each fades out
# after TOAST_SECONDS. At most MAX_TOASTS are visible (the oldest is dropped),
# so spam can never cover the play area.

const MAX_TOASTS: int     = 3
const TOAST_SECONDS: float = 2.5
const FADE_SECONDS: float  = 0.35
const MAX_WIDTH: float     = 620.0
const TOP_MARGIN: float    = 84.0

var _stack: VBoxContainer = null
var _center: CenterContainer = null
var _toast_width: float   = 560.0

func _ready() -> void:
	layer        = 15          # above gameplay panels, below the pause menu
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()
	Global.notification_posted.connect(_on_notification)
	Global.ui_scale_changed.connect(func(_s: float) -> void: _apply_scale())

func _build() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(root)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_TOP_WIDE)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(center)
	_center = center

	_stack = VBoxContainer.new()
	_stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stack.alignment = BoxContainer.ALIGNMENT_BEGIN
	center.add_child(_stack)
	_apply_scale()

func _apply_scale() -> void:
	var s: float = Global.ui_scale
	if _center != null:
		_center.offset_top = int(Global.ui_safe_insets.y + TOP_MARGIN * s)
	if _stack != null:
		_stack.add_theme_constant_override("separation", int(6 * s))
	var content := Global.ui_content_rect()
	_toast_width = minf(MAX_WIDTH * s, content.size.x * 0.8)
	for toast in _stack.get_children():
		if toast is Control:
			(toast as Control).custom_minimum_size.x = _toast_width
			var lbl := (toast as Control).get_node_or_null("RichTextLabel") as RichTextLabel
			if lbl != null:
				lbl.add_theme_font_size_override("normal_font_size",
					Global.ui_type_size(Global.UI_TYPE_LABEL))

func _on_notification(message: String) -> void:
	if _stack == null or message.strip_edges().is_empty():
		return
	# Drop the oldest first so the newest message is always visible.
	while _stack.get_child_count() >= MAX_TOASTS:
		var oldest: Node = _stack.get_child(0)
		_stack.remove_child(oldest)
		var old_tween: Variant = oldest.get_meta("toast_tween", null)
		if old_tween is Tween and (old_tween as Tween).is_valid():
			(old_tween as Tween).kill()
		oldest.queue_free()

	var s: float = Global.ui_scale
	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.custom_minimum_size = Vector2(0, int(30 * s))
	var sb := StyleBoxFlat.new()
	sb.bg_color     = Color(0.07, 0.09, 0.18, 0.92)
	sb.border_color = Color(0.28, 0.42, 0.72, 0.95)
	sb.set_border_width_all(maxi(1, int(1 * s)))
	sb.set_corner_radius_all(int(5 * s))
	sb.content_margin_left   = int(14 * s)
	sb.content_margin_right  = int(14 * s)
	sb.content_margin_top    = int(6 * s)
	sb.content_margin_bottom = int(6 * s)
	panel.add_theme_stylebox_override("panel", sb)

	var label := RichTextLabel.new()
	label.name = "RichTextLabel"
	label.bbcode_enabled = true
	label.fit_content    = true
	label.scroll_active  = false
	label.mouse_filter   = Control.MOUSE_FILTER_IGNORE
	label.autowrap_mode  = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size = Vector2(0, 0)
	label.add_theme_font_size_override("normal_font_size",
		Global.ui_type_size(Global.UI_TYPE_LABEL))
	label.add_theme_color_override("default_color", Color(0.88, 0.94, 1.0, 1.0))
	label.text = message
	panel.add_child(label)
	# Uniform width keeps the stack tidy and readable without spanning the
	# whole screen; the label wraps inside it.
	panel.custom_minimum_size.x = _toast_width
	panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_stack.add_child(panel)

	panel.modulate.a = 0.0
	var tw := create_tween()
	tw.tween_property(panel, "modulate:a", 1.0, 0.12)
	tw.tween_interval(TOAST_SECONDS)
	tw.tween_property(panel, "modulate:a", 0.0, FADE_SECONDS)
	tw.tween_callback(func() -> void:
		if is_instance_valid(panel):
			panel.queue_free())
	# Stored so dropping an old toast can kill its tween (otherwise the tween
	# fires on a freed capture and Godot logs "Lambda capture was freed").
	panel.set_meta("toast_tween", tw)
