extends VBoxContainer
class_name EncyclopediaSection

# ── Expandable Programming Encyclopedia section ────────────────────
# One accordion section: a clickable header that shows/hides its entries.
# Headers stay visible while collapsed, sections expand independently (any
# number can be open at once), and the body is indented so entries read as
# children of the header rather than siblings.
#
# Shared by the player inventory's Programming Encyclopedia tab and the LUA
# robot editor's encyclopedia so both present the same four sections with the
# same interaction. Purely presentational: it never executes or unlocks
# anything, and it reads its content from APIReference / EncyclopediaData.

signal expansion_changed(section_id: String, expanded: bool)

# Same palette as inventory_ui.gd / lua_editor_ui.gd.
const C_TITLE    := Color(0.80, 0.90, 1.00, 1.00)
const C_MUTED    := Color(0.55, 0.65, 0.85, 1.00)
const C_BORDER   := Color(0.22, 0.32, 0.58, 1.00)
const C_HEADER   := Color(0.10, 0.14, 0.26, 1.00)
const C_HEADER_H := Color(0.15, 0.21, 0.38, 1.00)
const C_ENTRY    := Color(0.55, 0.90, 1.00, 1.00)
const C_FURNACE  := Color(1.00, 0.66, 0.34, 1.00)
const C_STATION  := Color(0.45, 0.85, 1.00, 1.00)

var section_id: String = ""
var expanded: bool = false

var _header: Button = null
var _body:   VBoxContainer = null
var _indent: MarginContainer = null
var _count:  String = ""
var _title:  String = ""

# Build the header + empty body. Call set_counts() and add_entry() afterwards,
# then set_expanded() (the caller decides the initial state).
func setup(section: Dictionary, s: float) -> void:
	section_id = str(section.get("id", ""))
	_title     = str(section.get("title", "SECTION"))
	add_theme_constant_override("separation", int(4 * s))

	_header = Button.new()
	_header.alignment            = HORIZONTAL_ALIGNMENT_LEFT
	_header.custom_minimum_size  = Vector2(0, int(30 * s))
	_header.add_theme_font_size_override("font_size", int(13 * s))
	_header.focus_mode           = Control.FOCUS_NONE
	_header.tooltip_text         = "Click to expand or collapse this section."
	_header.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_style_header(s)
	_header.pressed.connect(_on_header_pressed)
	add_child(_header)

	# Indentation is what makes an entry read as belonging to its header.
	_indent = MarginContainer.new()
	_indent.add_theme_constant_override("margin_left", int(18 * s))
	_indent.add_theme_constant_override("margin_top",  int(2 * s))
	_indent.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(_indent)

	_body = VBoxContainer.new()
	_body.add_theme_constant_override("separation", int(8 * s))
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_indent.add_child(_body)

	var note := Label.new()
	note.text = str(section.get("note", ""))
	note.add_theme_font_size_override("font_size", int(10 * s))
	note.add_theme_color_override("font_color", C_MUTED)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body.add_child(note)

	set_expanded(false, false)

# "12" for always-available function sections, "3 / 15" for discovered ones.
func set_counts(visible: int, total: int, always_available: bool) -> void:
	_count = str(visible) if always_available else "%d / %d" % [visible, total]
	_update_header_text()

func body() -> VBoxContainer:
	return _body

func _on_header_pressed() -> void:
	set_expanded(not expanded)

func set_expanded(on: bool, notify: bool = true) -> void:
	expanded = on
	if _body != null:
		_body.visible = on
	if _indent != null:
		_indent.visible = on
	_update_header_text()
	if notify:
		expansion_changed.emit(section_id, expanded)

func _update_header_text() -> void:
	if _header == null:
		return
	var mark: String = "[-]" if expanded else "[+]"
	var suffix: String = "" if _count.is_empty() else "   (%s)" % _count
	_header.text = "%s  %s%s" % [mark, _title, suffix]

func _style_header(s: float) -> void:
	var normal := StyleBoxFlat.new()
	normal.bg_color     = C_HEADER
	normal.border_color = C_BORDER
	normal.set_border_width_all(1)
	normal.set_corner_radius_all(int(3 * s))
	normal.content_margin_left  = int(8 * s)
	normal.content_margin_right = int(8 * s)
	normal.content_margin_top   = int(4 * s)
	normal.content_margin_bottom = int(4 * s)
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = C_HEADER_H
	_header.add_theme_stylebox_override("normal",  normal)
	_header.add_theme_stylebox_override("hover",   hover)
	_header.add_theme_stylebox_override("pressed", hover)
	_header.add_theme_color_override("font_color",         C_TITLE)
	_header.add_theme_color_override("font_hover_color",   C_TITLE)
	_header.add_theme_color_override("font_pressed_color", C_TITLE)

# ── Entries ────────────────────────────────────────────────────────
# One function/concept: signature line (plus a target badge when the registry
# defines one) and its description. The badge is what tells an Algorithmica
# function's machine apart from the function name itself.
func add_entry(e: Dictionary, s: float) -> void:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", int(3 * s))

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", int(6 * s))
	box.add_child(row)

	var sig := Label.new()
	sig.text = str(e.get("sig", ""))
	sig.add_theme_font_size_override("font_size", int(13 * s))
	sig.add_theme_color_override("font_color", C_ENTRY)
	sig.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sig.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	row.add_child(sig)

	var target: String = str(e.get("target", ""))
	if not target.is_empty():
		row.add_child(_target_badge(target, s))

	var desc := Label.new()
	desc.text = str(e.get("desc", ""))
	desc.add_theme_font_size_override("font_size", int(11 * s))
	desc.add_theme_color_override("font_color", C_MUTED)
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(desc)

	_body.add_child(box)

func _target_badge(target: String, s: float) -> Control:
	var col: Color = C_FURNACE if target.to_lower().contains("furnace") else C_STATION
	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color     = Color(col.r, col.g, col.b, 0.16)
	sb.border_color = col
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(int(3 * s))
	sb.content_margin_left   = int(6 * s)
	sb.content_margin_right  = int(6 * s)
	sb.content_margin_top    = int(1 * s)
	sb.content_margin_bottom = int(1 * s)
	panel.add_theme_stylebox_override("panel", sb)
	panel.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	panel.tooltip_text = "Target: %s" % target

	var lbl := Label.new()
	lbl.text = target.to_upper()
	lbl.add_theme_font_size_override("font_size", int(9 * s))
	lbl.add_theme_color_override("font_color", col)
	panel.add_child(lbl)
	return panel

# Small helper for callers that want the section's entries without the UI.
static func entries_for(section: Dictionary) -> Array:
	return EncyclopediaData.entries_for_section(section)
