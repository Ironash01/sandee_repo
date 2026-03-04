extends CodeEdit

var language_spec: LanguageSpecification
var syntax_highlighting: CodeHighlighter = CodeHighlighter.new()
	
func code_completion_requested() -> void:
	for keyword: String in language_spec.keywords:
		add_code_completion_option(CodeEdit.KIND_PLAIN_TEXT, keyword, keyword, language_spec.keyword_color)
	
	for constant: String in language_spec.constants:
		add_code_completion_option(CodeEdit.KIND_PLAIN_TEXT, constant, constant, language_spec.constant_color)
	
	for operator: String in language_spec.operators:
		add_code_completion_option(CodeEdit.KIND_PLAIN_TEXT, operator, operator, language_spec.operator_color)
	
	update_code_completion_options(true)

func load_language_spec(_language_spec: LanguageSpecification) -> void:
	language_spec = _language_spec
	# setup syntax highlighting
	syntax_highlighting.function_color = language_spec.function_color
	syntax_highlighting.number_color = language_spec.number_color
	syntax_highlighting.symbol_color = language_spec.operator_color
	
	# comments
	if not language_spec.single_line_comment.is_empty():
		add_comment_delimiter(language_spec.single_line_comment, "")
		syntax_highlighting.add_color_region(language_spec.single_line_comment, "", language_spec.comment_color)
	
	if language_spec.multiline_comment_enabled:
		add_comment_delimiter(language_spec.multiline_comment_start, language_spec.multiline_comment_end)
		syntax_highlighting.add_color_region(language_spec.multiline_comment_start, language_spec.multiline_comment_end, language_spec.comment_color)
	
	# strings
	for str_delimiter: String in language_spec.string_delimiters:
		add_string_delimiter(str_delimiter, str_delimiter, true)
		add_auto_brace_completion_pair(str_delimiter, str_delimiter)
		syntax_highlighting.add_color_region(str_delimiter, str_delimiter, language_spec.string_color, true)
	
	# keywords
	for keyword: String in language_spec.keywords:
		syntax_highlighting.add_keyword_color(keyword, language_spec.keyword_color)
		
	for constant: String in language_spec.constants:
		syntax_highlighting.add_keyword_color(constant, language_spec.constant_color)
	
	for operator: String in language_spec.operators:
		syntax_highlighting.add_keyword_color(operator, language_spec.operator_color)
	
	# auto-indents
	indent_automatic_prefixes = language_spec.auto_indents
	
	# auto-braces
	for start: String in language_spec.auto_braces:
		add_auto_brace_completion_pair(start, language_spec.auto_braces[start])
	
	# set as syntax highlighter
	syntax_highlighter = syntax_highlighting
