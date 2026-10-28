extends Control
class_name StarSummaryUI

# Single-line overall star total shown immediately left of the PAUSE button.
# Blue = dungeon/clear stars, yellow = overworld quests. The mission tracker no
# longer owns the account/world star header.

const C_PANEL  := Color(0.08, 0.10, 0.20, 0.94)
const C_BORDER := Color(0.22, 0.32, 0.58, 0.90)
const C_TEXT   := Color(0.80, 0.90, 1.00, 1.00)
const C_MUTED  := Color(0.55, 0.65, 0.85, 0.90)
const GAP_PX   := 8.0

var _pause_btn: Control = null
var _panel: PanelContainer = null
var _row: HBoxContainer = null

func setup(pause_button: Control) -> void:
	_pause_btn = pause_button
	_refresh()
	_refit()

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel = PanelContainer.new()
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_panel)
	_row = HBoxContainer.new()
	_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_row.add_theme_constant_override("separation", int(6 * Global.ui_scale))
	_panel.add_child(_row)
	_apply_style()
	Global.stars_updated.connect(_refresh)
	Global.online_state_changed.connect(_on_online_changed)
	Global.ui_scale_changed.connect(_on_ui_scale_changed)
	call_deferred("_refit")

func _apply_style() -> void:
	if _panel == null:
		return
	var s: float = Global.ui_scale
	var sb := StyleBoxFlat.new()
	sb.bg_color = C_PANEL
	sb.border_color = C_BORDER
	sb.set_border_width_all(maxi(1, int(2 * s)))
	sb.set_corner_radius_all(int(20 * s))
	sb.content_margin_left = int(12 * s)
	sb.content_margin_right = int(12 * s)
	sb.content_margin_top = int(6 * s)
	sb.content_margin_bottom = int(6 * s)
	_panel.add_theme_stylebox_override("panel", sb)
	_panel.custom_minimum_size = Vector2(0, int(40 * s))
	if _row != null:
		_row.add_theme_constant_override("separation", int(6 * s))

func _refresh() -> void:
	if _row == null or not is_instance_valid(_row):
		return
	for c in _row.get_children():
		_row.remove_child(c)
		c.queue_free()
	var s: float = Global.ui_scale
	_row.add_child(_chip(StarIcon.BLUE, Global.account_blue_stars(), s))
	_row.add_child(_chip(StarIcon.YELLOW, Global.account_yellow_stars(), s))
	var suffix := Label.new()
	suffix.text = "ACCOUNT" if (Global.online_mode and not Supabase.profile.is_empty()) else "LOCAL"
	if not Global.world_progress_eligible(Global.active_save_slot):
		suffix.text = "LEGACY"
	suffix.add_theme_font_size_override("font_size", Global.ui_type_size(Global.UI_TYPE_CAPTION))
	suffix.add_theme_color_override("font_color", C_MUTED)
	suffix.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_row.add_child(suffix)
	call_deferred("_refit")

func _chip(color: Color, value: int, s: float) -> HBoxContainer:
	var chip := HBoxContainer.new()
	chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chip.add_theme_constant_override("separation", int(3 * s))
	var icon := StarIcon.new()
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chip.add_child(icon)
	icon.setup(color, 14.0 * s)
	var label := Label.new()
	label.text = str(value)
	label.add_theme_font_size_override("font_size", Global.ui_font_size(13))
	label.add_theme_color_override("font_color", C_TEXT)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chip.add_child(label)
	return chip

func _on_online_changed() -> void:
	_refresh()

func _on_ui_scale_changed(_s: float) -> void:
	_apply_style()
	_refresh()
	call_deferred("_refit")

func _refit() -> void:
	if _panel == null or not is_instance_valid(_panel):
		return
	_panel.reset_size()
	var s: float = Global.ui_scale
	var size := _panel.get_combined_minimum_size()
	if _pause_btn != null and is_instance_valid(_pause_btn):
		var pr := _pause_btn.get_global_rect()
		var pos := Vector2(pr.position.x - size.x - GAP_PX * s,
			pr.position.y + (pr.size.y - size.y) * 0.5)
		var safe := Global.ui_safe_insets
		pos.x = maxf(safe.x + 4.0 * s, pos.x)
		pos.y = maxf(safe.y + 4.0 * s, pos.y)
		_panel.position = pos
	else:
		_panel.position = Vector2(get_viewport_rect().size.x - size.x - 20.0 * s, 10.0 * s)
