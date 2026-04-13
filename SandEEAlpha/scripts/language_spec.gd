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
