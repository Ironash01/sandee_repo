extends Resource
class_name DungeonMissionData

# ── Dungeon mission (drives one procedurally generated dungeon) ────
# One file per mission, e.g. dungeon_mission_1.tres. Links a teachable
# knowledge entry to the embedded questions that verify it. The dungeon generator
# builds a randomized path/layout from these fields:
#   entry_resource_file  → the KnowledgeEntry placed on the knowledge altar
#                          (first room). Interacting records it + unlocks its
#                          keyword in the player's encyclopedia.
#   questions            → the quiz altar's questions, embedded INLINE in this
#                          resource as DungeonQuestion sub-resources (no separate
#                          quiz .tres files). Each has a type dropdown (MCQ or
#                          COMPILER). All must be answered correctly for the exit
#                          to open and the dungeon to be cleared.
#   size_modifier        → dropdown dungeon grid tier: 64x64, 128x128 or 256x256.
#   altar_amount         → altar/checkpoint rooms to generate (the entry altar's
#                          room is always the first one; the rest are spawned as
#                          bonus rooms until the quiz room, which is always last).
#   chest_amount         → loot chest rooms to generate.
# The generator derives the ROOM COUNT only from altar_amount + chest_amount;
# the grid SIZE comes only from size_modifier (the dropdown).

@export var mission_name: String = ""            # shown in the mission list
@export_multiline var mission_description: String = ""
@export var entry_resource_file: String = ""     # file name, e.g. "entry_1_lua.tres"
@export var questions: Array[DungeonQuestion] = []  # inline quiz questions (MCQ / COMPILER)
@export var dungeon_index: int = 1               # matches the mission's dungeon_index in Global.missions
@export var reward_item_path: String = "res://resources/items/lua.tres"
@export_enum("64x64", "128x128", "256x256") var size_modifier: int = 1
@export_range(1, 8, 1) var altar_amount: int = 1
@export_range(0, 16, 1) var chest_amount: int = 2
## Progression category. Main missions form the normal Lua and Python language
## tracks (the Lua track includes 11 and 26-39; Python includes 1-10). The boss
## is the shared finale. The optional "extra" category is still supported by
## DungeonWorld as post-boss content, but no shipped mission currently uses it.
@export_enum("main", "extra", "boss") var dungeon_category: String = "main"

# Base file name used as the stable id.
func id() -> String:
	return resource_path.get_file().get_basename() if not resource_path.is_empty() else mission_name.to_lower().replace(" ", "_")

# Resolved against the loaded registries in Global (see load_knowledge_data).
func entry() -> KnowledgeEntry:
	return Global.get_knowledge_entry_file(entry_resource_file) if not entry_resource_file.is_empty() else null

func is_main() -> bool:
	return dungeon_category == "main"

func is_extra() -> bool:
	return dungeon_category == "extra"

func is_boss() -> bool:
	return dungeon_category == "boss"
