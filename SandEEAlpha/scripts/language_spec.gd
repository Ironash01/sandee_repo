extends Resource
class_name LanguageSpecification

@export_group("Colors")
@export_color_no_alpha var keyword_color: Color = Color("#cba6f7")
@export_color_no_alpha var constant_color: Color = Color("#fab387")
@export_color_no_alpha var function_color: Color = Color("#89b4fa")
@export_color_no_alpha var builtin_color: Color = Color("#f38ba8")
@export_color_no_alpha var member_variable_color: Color = Color("#89b4fa")
@export_color_no_alpha var operator_color: Color = Color("#89dceb")
@export_color_no_alpha var number_color: Color = Color("#fab387")
@export_color_no_alpha var string_color: Color = Color("#a6e3a1")
@export var comment_color: Color = Color(1, 1, 1, 0.5)

@export_group("Comments")
@export var single_line_comment: String
@export_subgroup("Multiline", "multiline_comment")
@export var multiline_comment_enabled: bool
@export var multiline_comment_start: String
@export var multiline_comment_end: String

@export_group("Keywords")
@export var keywords: PackedStringArray

@export_group("Constants")
@export var constants: PackedStringArray
@export var membered_constants: PackedStringArray

@export_group("Functions")
@export var builtin_functions: PackedStringArray
@export var membered_builtin_functions: PackedStringArray

@export_group("Builtins")
@export var builtins: PackedStringArray

@export_group("Strings")
@export var string_delimiters: PackedStringArray

@export_group("Extra Operators")
@export var operators: PackedStringArray

@export_group("Other")
@export var auto_indents: PackedStringArray
@export var auto_braces: Dictionary[String, String]

# ── Editor styling helpers ────────────────────────────────────────
# `CodeHighlighter`'s DEFAULT number_color / symbol_color / function_color /
# member_variable_color are pure BLACK, which is unreadable on the dark code
# editors — build_highlighter() sets every one from the spec. style_code_edit()
# sets the editor-chrome colours (line numbers, caret, selection, current line)
# that the Godot default theme otherwise leaves dark.
static func build_highlighter(spec: LanguageSpecification) -> CodeHighlighter:
	var hl := CodeHighlighter.new()
	hl.function_color        = spec.function_color
	hl.number_color          = spec.number_color
	hl.symbol_color          = spec.operator_color
	hl.member_variable_color = spec.member_variable_color
	if not spec.single_line_comment.is_empty():
		hl.add_color_region(spec.single_line_comment, "", spec.comment_color)
	if spec.multiline_comment_enabled:
		hl.add_color_region(spec.multiline_comment_start, spec.multiline_comment_end, spec.comment_color)
	for d in spec.string_delimiters:
		hl.add_color_region(d, d, spec.string_color)
	for kw in spec.keywords:
		hl.add_keyword_color(kw, spec.keyword_color)
	for c in spec.constants:
		hl.add_keyword_color(c, spec.constant_color)
	for op in spec.operators:
		hl.add_keyword_color(op, spec.operator_color)
	for b in spec.builtins:
		hl.add_keyword_color(b, spec.builtin_color)
	return hl

static func style_code_edit(ce: CodeEdit, font: Color, muted: Color) -> void:
	ce.add_theme_color_override("font_color", font)
	ce.add_theme_color_override("font_readonly_color", font)
	ce.add_theme_color_override("line_number_color", muted)
	ce.add_theme_color_override("caret_color", font)
	ce.add_theme_color_override("current_line_color", Color(1, 1, 1, 0.05))
	ce.add_theme_color_override("selection_color", Color(0.30, 0.45, 0.75, 0.5))
	ce.add_theme_color_override("word_highlighted_color", Color(0.30, 0.45, 0.75, 0.35))
