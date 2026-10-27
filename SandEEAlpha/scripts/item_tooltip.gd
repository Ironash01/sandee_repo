extends CanvasLayer

# ── Shared floating item tooltip ──────────────────────────────────
# One popup for every interface: slots (inventory, hotbar, furnace) and recipe
# buttons call Global.show_item_tooltip(item) on hover and
# Global.hide_item_tooltip() on exit. Follows the mouse and clamps to the
# viewport. Owned by Global; lives on a high CanvasLayer above the panels.

const C_PANEL   := Color(0.06, 0.08, 0.16, 0.98)
const C_BORDER  := Color(0.30, 0.42, 0.72, 1.00)
const C_TITLE   := Color(0.85, 0.93, 1.00, 1.00)
const C_MUTED   := Color(0.58, 0.68, 0.88, 1.00)
const C_EFFECT  := Color(0.95, 0.82, 0.45, 1.00)

var _panel:  PanelContainer = null
var _name:   Label = null
var _qty:    Label = null
var _type:   Label = null
var _effect: Label = null
var _desc:   Label = null
var _panel_style: StyleBoxFlat = null

func _ready() -> void:
	layer = 55
	process_mode = Node.PROCESS_MODE_ALWAYS

	_panel = PanelContainer.new()
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel_style = StyleBoxFlat.new()
	_panel_style.bg_color = C_PANEL; _panel_style.border_color = C_BORDER
	_panel.add_theme_stylebox_override("panel", _panel_style)
	_panel.visible = false
	add_child(_panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 3)
	_panel.add_child(vbox)

	_name = _mk(vbox, Global.UI_TYPE_BODY, C_TITLE)
	_name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_qty = _mk(vbox, Global.UI_TYPE_LABEL, C_MUTED)
	_type = _mk(vbox, Global.UI_TYPE_LABEL, C_MUTED)
	_effect = _mk(vbox, Global.UI_TYPE_LABEL, C_EFFECT)
	_desc = _mk(vbox, Global.UI_TYPE_LABEL, C_MUTED)
	_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	Global.ui_scale_changed.connect(func(_s: float) -> void: _apply_scale())
	_apply_scale()

func _mk(parent: Node, role: int, col: Color) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", Global.ui_type_size(role))
	l.add_theme_color_override("font_color", col)
	parent.add_child(l)
	return l

func _apply_scale() -> void:
	var s: float = Global.ui_scale
	var width: float = maxf(230.0 * s, 220.0)
	_panel.custom_minimum_size = Vector2(int(width), 0)
	_panel_style.set_border_width_all(maxi(1, int(2 * s)))
	_panel_style.set_corner_radius_all(int(6 * s))
	_panel_style.content_margin_left = int(12 * s)
	_panel_style.content_margin_right = int(12 * s)
	_panel_style.content_margin_top = int(9 * s)
	_panel_style.content_margin_bottom = int(9 * s)
	if _desc != null:
		_desc.custom_minimum_size = Vector2(int(width), 0)
	for label in [_name, _qty, _type, _effect, _desc]:
		if label != null:
			label.add_theme_font_size_override("font_size",
				Global.ui_type_size(Global.UI_TYPE_BODY if label == _name else Global.UI_TYPE_LABEL))

func show_item(inv_item: Dictionary) -> void:
	if inv_item == null or not inv_item.has("data") or inv_item["data"] == null:
		hide_tip()
		return
	var d: ItemData = inv_item["data"] as ItemData
	_name.text   = d.item_name
	_qty.text    = "×%d" % int(inv_item.get("quantity", 1)) if int(inv_item.get("quantity", 1)) > 1 else ""
	_type.text   = d.item_type.capitalize()
	_effect.text = _effect_text(d)
	_desc.text   = d.description
	_panel.visible = true
	# A Control that is a direct child of a CanvasLayer under the root window
	# gets stretched past its content, leaving a big empty box. Snap it back to
	# the content size so the tooltip hugs its text.
	_panel.reset_size()
	_follow()

func hide_tip() -> void:
	if _panel != null:
		_panel.visible = false

func _effect_text(d: ItemData) -> String:
	var parts: Array = []
	# Read the same authoritative held-item damage as player.gd. This also
	# corrects non-swords: their old sword_level default displayed 4 even
	# though the actual token swing is 1.
	var shown_damage: int = d.held_damage_display()
	if shown_damage > 0:
		parts.append("Damage %d" % shown_damage)
	if d.is_pickaxe:
		parts.append("Pickaxe T%d" % d.pickaxe_level)
	if d.axe_level > 0:
		parts.append("Axe T%d" % d.axe_level)
	if d.is_fuel:
		parts.append("Fuel LV %d" % d.fuel_level)
	if d.block_level > 0:
		parts.append("Hardness %d" % d.block_level)
	if d.min_pickaxe_level > 0:
		parts.append("Needs pickaxe T%d" % d.min_pickaxe_level)
	return "  ·  ".join(PackedStringArray(parts))

func _process(_delta: float) -> void:
	if _panel != null and _panel.visible:
		_follow()

func _follow() -> void:
	var vp := get_viewport()
	if vp == null:
		return
	# A Control that is a direct child of a CanvasLayer under the root window
	# gets stretched past its content (a big empty box). Snap it back to the
	# content size every frame so the tooltip always hugs its text.
	_panel.reset_size()
	var vp_size := vp.get_visible_rect().size
	var sz := _panel.size
	var m: Vector2 = vp.get_mouse_position()
	var safe := Global.ui_safe_insets
	var min_x: float = safe.x + 4.0
	var min_y: float = safe.y + 4.0
	var max_x: float = vp_size.x - safe.z - sz.x - 4.0
	var max_y: float = vp_size.y - safe.w - sz.y - 4.0
	_panel.position = Vector2(
		clampf(m.x + 16.0, min_x, maxf(min_x, max_x)),
		clampf(m.y + 16.0, min_y, maxf(min_y, max_y)))
