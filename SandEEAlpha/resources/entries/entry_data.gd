extends Resource
class_name KnowledgeEntry

# ── Knowledge entry (dungeon-teachable concept) ────────────────────
# One file per teachable concept, e.g. entry_1_lua.tres, entry_2_python.tres.
# Placed on the knowledge altar of a dungeon mission; when the player
# interacts with that altar the entry is recorded in the player's
# encyclopedia (Global.learn_entry) and its keyword becomes unlocked.

@export var entry_name: String = ""          # human label, e.g. "print()"
@export var description: String = ""         # the Desc / teaching text
@export var keyword: String = ""             # unlocks use of this concept in the Lua editor
@export_enum("lua", "python") var language: String = "lua"
@export var category: String = ""            # optional grouping shown in the encyclopedia

# Base file name of this entry resource, e.g. "entry_1_lua" — used as the
# stable id when storing learned knowledge (survives renames of other fields).
func id() -> String:
	return resource_path.get_file().get_basename() if not resource_path.is_empty() else entry_name.to_lower().replace(" ", "_")
