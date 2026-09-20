extends CodeEdit

var language_spec: LanguageSpecification
var syntax_highlighting: CodeHighlighter = CodeHighlighter.new()

func _get_last_token() -> String:
	var i: int = 0
	var last_token: String = ""
	while last_token.lstrip("\n ").length() == last_token.length() and i <= text.length():
		last_token = text.right(i)
		i += 1
	return last_token.lstrip("\n ")

func code_completion_request() -> void:
	var last_token: String = _get_last_token()
	if not last_token.is_empty():
		if not last_token.contains('.'):
			for keyword: String in language_spec.keywords:
				add_code_completion_option(KIND_PLAIN_TEXT, keyword, keyword, language_spec.keyword_color)

			for constant: String in language_spec.constants:
				add_code_completion_option(KIND_CONSTANT, constant, constant, language_spec.constant_color)

			for operator: String in language_spec.operators:
				add_code_completion_option(KIND_PLAIN_TEXT, operator, operator, language_spec.operator_color)

			for builtin: String in language_spec.builtins:
				add_code_completion_option(KIND_PLAIN_TEXT, builtin, builtin, language_spec.builtin_color)

			for function: String in language_spec.builtin_functions:
				add_code_completion_option(KIND_FUNCTION, function, function, language_spec.function_color)
		else:
			var parent: String = last_token.get_basename()
			if Array(language_spec.string_delimiters).any(func (x: String): return parent.contains(x)):
				parent = "string"
			for constant: String in language_spec.membered_constants:
				if constant.begins_with(parent):
					add_code_completion_option(KIND_CONSTANT, constant.get_extension(), constant.get_extension(), language_spec.constant_color)

			for function: String in language_spec.membered_builtin_functions:
				if function.begins_with(parent):
					add_code_completion_option(KIND_FUNCTION, function.get_extension(), function.get_extension(), language_spec.function_color)

		update_code_completion_options(false)

func load_language_spec(_language_spec: LanguageSpecification) -> void:
	language_spec = _language_spec
	# setup syntax highlighting
	syntax_highlighting.function_color = language_spec.function_color
	syntax_highlighting.number_color = language_spec.number_color
	syntax_highlighting.symbol_color = language_spec.operator_color
	syntax_highlighting.member_variable_color = language_spec.member_variable_color
	# comments
	if not language_spec.single_line_comment.is_empty():
		add_comment_delimiter(language_spec.single_line_comment, "")
		syntax_highlighting.add_color_region(language_spec.single_line_comment, "", language_spec.comment_color)

	if language_spec.multiline_comment_enabled:
		add_comment_delimiter(language_spec.multiline_comment_start, language_spec.multiline_comment_end)
		syntax_highlighting.add_color_region(language_spec.multiline_comment_start, language_spec.multiline_comment_end, language_spec.comment_color)

	# strings
	for str_delimiter: String in language_spec.string_delimiters:
		# add_string_delimiter() ALREADY registers the matching auto-brace
		# completion pair for the delimiter, so also calling
		# add_auto_brace_completion_pair() here raised a Godot error per
		# delimiter ("auto brace completion open key ... already exists").
		add_string_delimiter(str_delimiter, str_delimiter, true)
		syntax_highlighting.add_color_region(str_delimiter, str_delimiter, language_spec.string_color)

	# keywords
	for keyword: String in language_spec.keywords:
		syntax_highlighting.add_keyword_color(keyword, language_spec.keyword_color)

	for constant: String in language_spec.constants:
		syntax_highlighting.add_keyword_color(constant, language_spec.constant_color)

	for operator: String in language_spec.operators:
		syntax_highlighting.add_keyword_color(operator, language_spec.operator_color)

	for builtin: String in language_spec.builtins:
		syntax_highlighting.add_keyword_color(builtin, language_spec.builtin_color)

	# auto-indents
	indent_automatic_prefixes = language_spec.auto_indents

	# auto-braces
	for start: String in language_spec.auto_braces:
		if not auto_brace_completion_pairs.has(start):
			add_auto_brace_completion_pair(start, language_spec.auto_braces[start])

	# set as syntax highlighter
	syntax_highlighter = syntax_highlighting
