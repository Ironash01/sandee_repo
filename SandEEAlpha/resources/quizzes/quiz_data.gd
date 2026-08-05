extends Resource
class_name QuizQuestion

# ── Quiz question (used by the dungeon quiz altar) ────────────────
# One file per question, e.g. quiz_1_lua.tres, quiz_2_python.tres.
# A dungeon mission references several of these; the quiz altar presents
# them in order and only opens the exit when every one is answered
# correctly.
#
# A single `shape` enum picks the question type:
#   Shape.SHORT → multiple choice over answer_short_a..d; correct_short_index
#                 picks which one is right. (A true/false question is just a
#                 short question with a="True", b="False".)
#   Shape.LONG  → typed answer, compared against answer_long.
#
# Multi-line / indented content is fully supported for LONG questions:
#   - `question` renders as-is in the altar's Label — include `\n` escapes
#     (or literal newlines) and leading spaces for code-style layout.
#   - `answer_long` is graded by content, not formatting: case-insensitive,
#     trimmed, and whitespace runs (spaces/tabs/newlines) collapsed — so the
#     player can type the answer with any indentation/line breaks and still
#     pass (e.g. an if/end block typed without exact indentation).

enum Shape { SHORT = 0, LONG = 1 }

@export var shape: Shape = Shape.LONG

@export var question_name: String = ""       # short id, e.g. "print basics"
@export var question: String = ""            # the actual question text
@export var question_field: String = ""      # reference to the KnowledgeEntry FILE NAME this
                                             # question verifies, e.g. "entry_1_lua.tres"
@export var answer_long: String = ""         # the typed/enumeration answer
@export var answer_short_a: String = ""
@export var answer_short_b: String = ""
@export var answer_short_c: String = ""
@export var answer_short_d: String = ""
@export var correct_short_index: int = 0     # 0..3 = which of a..d is correct (Shape.SHORT)

static var _ws_re: RegEx = null

# Base file name used as the stable id ("quiz_1_lua").
func id() -> String:
	return resource_path.get_file().get_basename() if not resource_path.is_empty() else question_name.to_lower().replace(" ", "_")

func is_short() -> bool:
	return shape == Shape.SHORT

func short_answers() -> Array[String]:
	return [answer_short_a, answer_short_b, answer_short_c, answer_short_d]

# The canonical correct answer as text (used by every question shape).
func correct_text() -> String:
	if is_short():
		return short_answers()[clampi(correct_short_index, 0, 3)].strip_edges()
	return _normalize_answer_text(answer_long)

# Long answers are graded on their content, not their formatting: case,
# indentation, extra blank lines, and trailing whitespace are all tolerated,
# so a player can type/retype a multi-line answer with different spacing and
# still pass. (Short answers don't use this — they're graded by index.)
func _normalize_answer_text(text: String) -> String:
	if _ws_re == null:
		_ws_re = RegEx.new()
		_ws_re.compile("\\s+")
	return _ws_re.sub(text.strip_edges(), " ", true).to_lower()

func is_answer_correct(input_text: String) -> bool:
	var given := input_text.strip_edges()
	if is_short():
		var choice := given.to_int() - 1   # UI labels options 1..4
		return choice == clampi(correct_short_index, 0, 3)
	return _normalize_answer_text(given) == _normalize_answer_text(answer_long)
