extends Resource
class_name DungeonMissionData

# ── Dungeon mission (drives one procedurally generated dungeon) ────
# One file per mission, e.g. dungeon_mission_1.tres. Links a teachable
# knowledge entry to the quizzes that verify it. The dungeon generator
# builds a randomized path/layout from these fields:
#   entry_resource_file  → the KnowledgeEntry placed on the knowledge altar
#                          (first room). Interacting records it + unlocks its
#                          keyword in the player's encyclopedia.
#   quiz_resource_files  → QuizQuestion files presented by the quiz altar in
#                          the final room. All must be answered correctly for
#                          the exit to open and the dungeon to be cleared.

@export var mission_name: String = ""            # shown in the mission list
@export var mission_description: String = ""
@export var entry_resource_file: String = ""     # file name, e.g. "entry_1_lua.tres"
@export var quiz_resource_files: Array[String] = []  # e.g. ["quiz_1_lua.tres", "quiz_2_lua.tres"]
@export var dungeon_index: int = 1               # matches the mission's dungeon_index in Global.missions
@export var reward_item_path: String = "res://resources/items/lua_core.tres"

# Base file name used as the stable id.
func id() -> String:
	return resource_path.get_file().get_basename() if not resource_path.is_empty() else mission_name.to_lower().replace(" ", "_")

# Resolved against the loaded registries in Global (see load_knowledge_data).
func entry() -> KnowledgeEntry:
	return Global.get_knowledge_entry_file(entry_resource_file) if not entry_resource_file.is_empty() else null

func quizzes() -> Array[QuizQuestion]:
	var out: Array[QuizQuestion] = []
	for f in quiz_resource_files:
		var q: QuizQuestion = Global.get_quiz_file(f)
		if q != null:
			out.append(q)
	return out
