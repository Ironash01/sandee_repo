extends Control
enum Language { Lua, Python }

@export var language: Language

const LUA_LANGUAGE_SPEC = preload("uid://df7rqt8d0p5if")
const PYTHON_LANGUAGE_SPEC = preload("uid://dwisajvglb4eu")
@onready var code_edit: CodeEdit = $CodeEdit

signal update_language_spec(language_spec: LanguageSpecification)

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	match language:
		Language.Lua:
			update_language_spec.emit(LUA_LANGUAGE_SPEC)
		Language.Python:
			update_language_spec.emit(PYTHON_LANGUAGE_SPEC)

func get_code() -> String:
	return code_edit.text
