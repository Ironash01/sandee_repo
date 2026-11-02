extends RefCounted
class_name CodeSafety

# ── Player-program safety checks ───────────────────────────────────
# LuaState/PythonState execute player code synchronously on the main thread.
# A tight loop such as `while true do end` (or `while True:` in Python)
# therefore freezes the whole game before any runtime timeout can fire.
#
# These are deliberately PRE-RUN guards: reject only code we can prove is
# likely non-terminating, with an actionable message. They are conservative
# about safe loops (`break` / `return` exits are accepted) and ignore text
# inside comments and strings.
#
# The checks are not a full parser. They catch the common novice patterns:
#   • while <always true> with no loop-level break/return
#   • repeat ... until false/nil/0 with no loop-level break/return
#   • numeric for loops with a huge literal or math.huge end
#   • Python while True: / for ... in range(<huge>)
const HUGE_LOOP_LIMIT: float = 1_000_000.0


static func lua_issue(code: String) -> String:
	var tokens := _lua_tokens(code)
	var i := 0
	while i < tokens.size():
		var tok: String = str(tokens[i])
		if tok == "while":
			var do_idx := _lua_find_token(tokens, i + 1, "do")
			if do_idx >= 0 and _lua_always_true(_tokens_between(tokens, i + 1, do_idx)):
				var body := _lua_loop_body(tokens, do_idx + 1)
				if not bool(body.get("exits", false)):
					return ("Potential infinite loop detected: this while loop has "
						+ "no break or return. Add a break or a bounded condition.")
			i += 1
			continue
		if tok == "for":
			var do_idx := _lua_find_token(tokens, i + 1, "do")
			if do_idx >= 0:
				var header := _tokens_between(tokens, i + 1, do_idx)
				if _lua_huge_for(header):
					var body := _lua_loop_body(tokens, do_idx + 1)
					if not bool(body.get("exits", false)):
						return ("Potential very long loop detected: this for loop "
							+ "has a huge range and no break or return. Reduce the "
							+ "range or add a break.")
			i += 1
			continue
		if tok == "repeat":
			var info := _lua_repeat_body(tokens, i + 1)
			if not bool(info.get("exits", false)) \
					and _lua_repeat_always_true(tokens, int(info.get("until", -1))):
				return ("Potential infinite loop detected: this repeat loop ends "
					+ "with a false condition and has no break or return.")
			i += 1
			continue
		i += 1
	return ""


static func python_issue(code: String) -> String:
	var lines := _python_clean_lines(code)
	for idx in range(lines.size()):
		var line: String = str(lines[idx])
		var stripped := line.strip_edges()
		if stripped.is_empty():
			continue
		var base_indent := _indent_width(line)
		var while_match := _python_while_condition(stripped)
		if not while_match.is_empty() and _python_always_true(while_match):
			if not _python_body_has_exit(lines, idx, base_indent):
				return ("Potential infinite loop detected: this while loop has "
					+ "no break or return. Add a break or a bounded condition.")
			continue
		var range_end := _python_huge_range(stripped)
		if range_end > HUGE_LOOP_LIMIT:
			if not _python_body_has_exit(lines, idx, base_indent):
				return ("Potential very long loop detected: this for range is "
					+ "huge and has no break or return. Reduce the range or add a break.")
	return ""


# ── Lua tokenizer ──────────────────────────────────────────────────
static func _lua_tokens(code: String) -> Array:
	var cleaned := _lua_strip_literals(code)
	var re := RegEx.new()
	re.compile("[A-Za-z_][A-Za-z0-9_]*|[0-9]+(?:\\.[0-9]+)?")
	var out: Array = []
	for m in re.search_all(cleaned):
		out.append(m.get_string())
	return out


# Remove comments and quoted/long strings so keywords inside them cannot
# trigger a false positive. Keeps whitespace for token separation.
static func _lua_strip_literals(code: String) -> String:
	var out := ""
	var i := 0
	var n := code.length()
	while i < n:
		var c := code.substr(i, 1)
		if c == "-" and i + 1 < n and code.substr(i + 1, 1) == "-":
			# --[[ block comment ]] or -- line comment.
			if i + 3 < n and code.substr(i + 2, 2) == "[[":
				var close := code.find("]]", i + 4)
				i = close + 2 if close >= 0 else n
			else:
				var nl := code.find("\n", i + 2)
				i = nl if nl >= 0 else n
			out += " "
			continue
		if c == "\"" or c == "'":
			var quote := c
			i += 1
			while i < n:
				if code.substr(i, 1) == "\\":
					i += 2
					continue
				if code.substr(i, 1) == quote:
					i += 1
					break
				i += 1
			out += " "
			continue
		if c == "[" and i + 1 < n and code.substr(i + 1, 1) == "[":
			var close := code.find("]]", i + 2)
			i = close + 2 if close >= 0 else n
			out += " "
			continue
		out += c
		i += 1
	return out


static func _tokens_between(tokens: Array, start: int, stop: int) -> Array:
	var out: Array = []
	for i in range(maxi(start, 0), mini(stop, tokens.size())):
		out.append(tokens[i])
	return out


static func _lua_find_token(tokens: Array, start: int, wanted: String) -> int:
	for i in range(start, tokens.size()):
		if str(tokens[i]) == wanted:
			return i
	return -1


static func _lua_always_true(parts: Array) -> bool:
	if parts.size() == 1:
		var value := str(parts[0])
		if value == "true":
			return true
		if value.is_valid_float():
			return not is_zero_approx(value.to_float())
	if parts.size() == 2 and str(parts[0]) == "not" and str(parts[1]) == "false":
		return true
	return false


static func _lua_huge_for(header: Array) -> bool:
	for i in range(header.size() - 1):
		if str(header[i]) == "math" and str(header[i + 1]) == "huge":
			return true
	var numbers: Array = []
	for value in header:
		var text := str(value)
		if text.is_valid_float():
			numbers.append(text.to_float())
	if numbers.size() < 2:
		return false
	# Lua numeric for: for i = start, stop[, step]. With three numbers the
	# stop is the middle; with two it is the last.
	var stop: float = float(numbers[1] if numbers.size() >= 3 else numbers[numbers.size() - 1])
	return absf(stop) > HUGE_LOOP_LIMIT


# Scan one loop body for a break/return that actually exits THIS loop or the
# enclosing function. Nested loops' breaks and nested functions' returns do
# not count. Returns { end: int, exits: bool }.
static func _lua_loop_body(tokens: Array, start: int) -> Dictionary:
	var stack: Array = []
	var loop_depth := 0
	var function_depth := 0
	var pending_loop_do := 0
	var exits := false
	var i := start
	while i < tokens.size():
		var tok := str(tokens[i])
		match tok:
			"while", "for":
				stack.append("loop")
				loop_depth += 1
				pending_loop_do += 1
			"do":
				if pending_loop_do > 0:
					pending_loop_do -= 1
				else:
					stack.append("do")
			"if":
				stack.append("if")
			"function":
				stack.append("function")
				function_depth += 1
			"repeat":
				stack.append("repeat")
				loop_depth += 1
			"end":
				if stack.is_empty():
					return {"end": i, "exits": exits}
				var top := str(stack.pop_back())
				if top == "function":
					function_depth -= 1
				elif top == "loop" or top == "repeat":
					loop_depth -= 1
			"until":
				if not stack.is_empty() and str(stack.back()) == "repeat":
					stack.pop_back()
					loop_depth -= 1
			"break":
				if loop_depth == 0 and function_depth == 0:
					exits = true
			"return":
				if function_depth == 0:
					exits = true
		i += 1
	return {"end": tokens.size() - 1, "exits": exits}


# Find the matching `until` of a repeat loop and whether its body has an exit.
static func _lua_repeat_body(tokens: Array, start: int) -> Dictionary:
	var stack: Array = []
	var loop_depth := 0
	var function_depth := 0
	var pending_loop_do := 0
	var exits := false
	var i := start
	while i < tokens.size():
		var tok := str(tokens[i])
		match tok:
			"while", "for":
				stack.append("loop")
				loop_depth += 1
				pending_loop_do += 1
			"do":
				if pending_loop_do > 0:
					pending_loop_do -= 1
				else:
					stack.append("do")
			"if":
				stack.append("if")
			"function":
				stack.append("function")
				function_depth += 1
			"repeat":
				stack.append("repeat")
				loop_depth += 1
			"until":
				if stack.is_empty():
					return {"until": i, "exits": exits}
				var top := str(stack.pop_back())
				if top == "repeat":
					loop_depth -= 1
			"end":
				if not stack.is_empty():
					var top := str(stack.pop_back())
					if top == "function":
						function_depth -= 1
					elif top == "loop" or top == "repeat":
						loop_depth -= 1
			"break":
				if loop_depth == 0 and function_depth == 0:
					exits = true
			"return":
				if function_depth == 0:
					exits = true
		i += 1
	return {"until": -1, "exits": exits}


# A repeat loop is infinite when its `until` condition is a constant false
# value. Only inspect the mouthful of tokens immediately after `until`; a
# larger expression may terminate at runtime and is left alone.
static func _lua_repeat_always_true(tokens: Array, until_idx: int) -> bool:
	if until_idx < 0 or until_idx + 1 >= tokens.size():
		return false
	var value := str(tokens[until_idx + 1])
	if value == "false" or value == "nil":
		return true
	if value.is_valid_float() and is_zero_approx(value.to_float()):
		return true
	return false


# ── Python line helpers ────────────────────────────────────────────
# Strip comments and strings while preserving indentation and line count.
static func _python_clean_lines(code: String) -> Array:
	var out: Array = []
	var triple := ""
	for raw in code.split("\n"):
		var clean := ""
		var i := 0
		var n := raw.length()
		while i < n:
			if not triple.is_empty():
				var end := raw.find(triple, i)
				if end < 0:
					i = n
					break
				i = end + triple.length()
				triple = ""
				continue
			var c := raw.substr(i, 1)
			if c == "#":
				break
			if c == "\"" or c == "'":
				var quote := c
				if i + 2 < n and raw.substr(i + 1, 1) == quote \
						and raw.substr(i + 2, 1) == quote:
					triple = quote + quote + quote
					i += 3
					continue
				i += 1
				while i < n:
					if raw.substr(i, 1) == "\\":
						i += 2
						continue
					if raw.substr(i, 1) == quote:
						i += 1
						break
					i += 1
				clean += " "
				continue
			clean += c
			i += 1
		out.append(clean)
	return out


static func _python_while_condition(stripped: String) -> String:
	var re := RegEx.new()
	re.compile("^while\\s+(.+?)\\s*:\\s*$")
	var m := re.search(stripped)
	return m.get_string(1).strip_edges() if m != null else ""


static func _python_always_true(condition: String) -> bool:
	if condition == "True":
		return true
	if condition == "not False":
		return true
	if condition.is_valid_float():
		return not is_zero_approx(condition.to_float())
	return false


static func _python_huge_range(stripped: String) -> float:
	var re := RegEx.new()
	re.compile("^for\\s+.+?\\s+in\\s+range\\s*\\((.+)\\)\\s*:\\s*$")
	var m := re.search(stripped)
	if m == null:
		return 0.0
	var parts := m.get_string(1).split(",")
	var stop_index := 0 if parts.size() == 1 else 1
	if stop_index >= parts.size():
		return 0.0
	var stop := str(parts[stop_index]).strip_edges()
	return stop.to_float() if stop.is_valid_float() else 0.0


static func _indent_width(line: String) -> int:
	var width := 0
	for i in range(line.length()):
		var c := line.substr(i, 1)
		if c == " ":
			width += 1
		elif c == "\t":
			width += 4
		else:
			break
	return width


# Find whether a Python loop body has a break/return that actually exits this
# loop/function. Tracks nested loops and defs by indentation so a break inside
# an inner loop does not count as an exit for the outer loop.
static func _python_body_has_exit(lines: Array, loop_line: int, base_indent: int) -> bool:
	var blocks: Array = []  # {type: "loop"/"def", indent: int}
	var i := loop_line + 1
	while i < lines.size():
		var line: String = str(lines[i])
		var stripped := line.strip_edges()
		if stripped.is_empty():
			i += 1
			continue
		var indent := _indent_width(line)
		if indent <= base_indent:
			break
		while not blocks.is_empty() and indent <= int(blocks.back()["indent"]):
			blocks.pop_back()
		var has_loop := false
		var has_def := false
		for block in blocks:
			if str(block["type"]) == "loop":
				has_loop = true
			elif str(block["type"]) == "def":
				has_def = true
		if stripped.begins_with("break") and not has_loop:
			return true
		if stripped.begins_with("return") and not has_def:
			return true
		if stripped.begins_with("while ") or stripped.begins_with("for ") \
				or stripped == "while" or stripped == "for":
			blocks.append({"type": "loop", "indent": indent})
		elif stripped.begins_with("def ") or stripped == "def":
			blocks.append({"type": "def", "indent": indent})
		i += 1
	return false
