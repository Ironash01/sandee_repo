extends VBoxContainer
class_name AlgorithmicaTemplateList

# ── Algorithmica template chooser ──────────────────────────────────
# Mirrors Automatica's TEMPLATES column: one named button per example, with the
# full program in its tooltip. Clicking a button hands the template entry back
# to the owning editor, which loads its code into the code box.
#
# Shared by the Crafting Station and Furnace Algorithmica editors so both use
# the same layout, styling and template registry.

const C_TITLE  := Color(0.80, 0.90, 1.00, 1.00)
const C_MUTED  := Color(0.55, 0.65, 0.85, 1.00)
const C_BORDER := Color(0.22, 0.32, 0.58, 1.00)

static func build(target: String, s: float, on_pick: Callable) -> VBoxContainer:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", int(6 * s))
	col.custom_minimum_size = Vector2(int(160 * s), 0)

	var lbl := Label.new()
	lbl.text = "TEMPLATES"
	lbl.add_theme_font_size_override("font_size", Global.ui_font_size(11))
	lbl.add_theme_color_override("font_color", C_MUTED)
	col.add_child(lbl)

	var hint := Label.new()
	hint.text = "Click to load an example into the editor."
	hint.add_theme_font_size_override("font_size", Global.ui_font_size(9))
	hint.add_theme_color_override("font_color", C_MUTED)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(hint)

	for entry in APIReference.templates_for(target):
		var btn := Button.new()
		btn.text = str((entry as Dictionary)["name"])
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.add_theme_font_size_override("font_size", Global.ui_font_size(11))
		btn.custom_minimum_size = Vector2(0, int(30 * s))
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.12, 0.16, 0.32, 1.0)
		sb.border_color = C_BORDER
		sb.set_border_width_all(1)
		sb.set_corner_radius_all(int(4 * s))
		sb.content_margin_left  = int(8 * s)
		sb.content_margin_right = int(8 * s)
		btn.add_theme_stylebox_override("normal",  sb)
		btn.add_theme_stylebox_override("hover",   sb)
		btn.add_theme_stylebox_override("pressed", sb)
		btn.add_theme_color_override("font_color", C_TITLE)
		btn.tooltip_text = str((entry as Dictionary)["code"])
		btn.pressed.connect(on_pick.bind(entry))
		col.add_child(btn)
	return col
