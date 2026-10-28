extends Resource
class_name DungeonQuestion

# ── Dungeon question (embedded in a DungeonMissionData) ──────────
# One question the quiz altar presents. The `type` dropdown selects how it is
# asked and graded:
#   MCQ      → multiple choice; answer_a..d + correct_index (0=A, 1=B, 2=C, 3=D).
#   COMPILER → code answer; language / starter_code / answer_output.
# Both field sets are plain @export (grouped under their type) so they always
# display and serialize reliably in the inspector — no custom property list.

enum Type { MCQ = 0, COMPILER = 1 }

@export_enum("MCQ", "COMPILER") var type: int = Type.MCQ
@export_multiline var question: String = ""

@export_group("MCQ Options")
@export var answer_a: String = ""
@export var answer_b: String = ""
@export var answer_c: String = ""
@export var answer_d: String = ""
@export_range(0, 3, 1) var correct_index: int = 0

@export_group("Compiler Options")
@export_enum("lua", "python") var language: String = "lua"
@export_multiline var starter_code: String = ""
@export_multiline var answer_output: String = ""
@export_multiline var hint: String = ""

func is_compiler() -> bool:
	return type == Type.COMPILER

func options() -> Array[String]:
	return [answer_a, answer_b, answer_c, answer_d]

func correct_option_index() -> int:
	return clampi(correct_index, 0, 3)