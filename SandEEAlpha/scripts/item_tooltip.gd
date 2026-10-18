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

func _ready() -> void:
	layer = 55
	process_mode = Node.PROCESS_MODE_ALWAYS

	_panel = PanelContainer.new()
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.custom_minimum_size = Vector2(200, 0)
	var sb := StyleBoxFlat.new()
	sb.bg_color = C_PANEL; sb.border_color = C_BORDER
	sb.set_border_width_all(1); sb.set_corner_radius_all(6)
	sb.content_margin_left = 10; sb.content_margin_right = 10
	sb.content_margin_top = 8; sb.content_margin_bottom = 8
	_panel.add_theme_stylebox_override("panel", sb)
	_panel.visible = false
	add_child(_panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 3)
	_panel.add_child(vbox)

	_name = _mk(vbox, 13, C_TITLE)
	_name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_qty = _mk(vbox, 11, C_MUTED)
	_type = _mk(vbox, 11, C_MUTED)
	_effect = _mk(vbox, 11, C_EFFECT)
	_desc = _mk(vbox, 11, C_MUTED)
	_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_desc.custom_minimum_size = Vector2(200, 0)

func _mk(parent: Node, fs: int, col: Color) -> Label:
	var s: float = Global.ui_scale
	var l := Label.new()
	l.add_theme_font_size_override("font_size", int(fs * s))
	l.add_theme_color_override("font_color", col)
	parent.add_child(l)
	return l

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
	if d.sword_level > 0:
		parts.append("Damage %d" % d.sword_damage())
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
	_panel.position = Vector2(
		clampf(m.x + 16.0, 4.0, maxf(4.0, vp_size.x - sz.x - 4.0)),
		clampf(m.y + 16.0, 4.0, maxf(4.0, vp_size.y - sz.y - 4.0)))
