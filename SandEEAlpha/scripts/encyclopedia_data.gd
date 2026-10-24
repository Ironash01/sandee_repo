extends RefCounted
class_name EncyclopediaData

# ── Programming Encyclopedia availability ──────────────────────────
# Two different rules, deliberately kept apart:
#
#   • LANGUAGE sections (LUA Programming Language / Python Programming
#     Language) are discovered through dungeon progression. Each concept is
#     revealed by the KnowledgeEntry its dungeon teaches; that knowledge is
#     already persisted per world by Global (learned_entries), so saves keep
#     working and replaying a dungeon can never duplicate an entry.
#
#   • FUNCTION sections (Automatica / Algorithmica) are ALWAYS fully listed.
#     They document the custom LUA robot API and the custom Python automation
#     API, which exist from the start of a new world — nothing here gates,
#     grants or bypasses execution rights.
#
# Entry ids are stable (see APIReference) and never saved themselves: the
# saved state is only the learned KnowledgeEntry ids, as before.

# ── Language concept gates ─────────────────────────────────────────
# Entry id -> KnowledgeEntry base name (resources/entries/). Each entry is
# taught by exactly one dungeon (dungeon_mission_*.tres), so this doubles as
# the dungeon mapping.

# Lua Programming Language — Lua dungeons (11, 26-39).
const LUA_LANGUAGE_GATES := {
	"lua.print":          "entry_11_lua",   # Lua print()
	"lua.type":           "entry_26_lua",   # Lua Variables
	"lua.tostring":       "entry_26_lua",
	"lua.vector":         "entry_28_lua",   # Lua Tables
	"lua.pairs":          "entry_28_lua",
	"lua.table_insert":   "entry_28_lua",
	"lua.table_sort":     "entry_28_lua",
	"lua.string_format":  "entry_27_lua",   # Lua Strings
	"lua.string_len":     "entry_27_lua",
	"lua.math_floor":     "entry_32_lua",   # Lua Arithmetic
	"lua.math_abs":       "entry_32_lua",
	"lua.math_min":       "entry_32_lua",
	"lua.math_random":    "entry_32_lua",
	"lua.metatable":      "entry_35_lua",   # Lua OOP
	"lua.error_handling": "entry_38_lua",   # Lua Error Handling
}

# Python Programming Language — Python dungeons (1-10).
const PYTHON_LANGUAGE_GATES := {
	"python.print": "entry_1_python",
	"python.int":   "entry_2_python",
	"python.abs":   "entry_5_python",   # Arithmetic Expressions
	"python.min":   "entry_5_python",
	"python.len":   "entry_6_python",   # Strings
	"python.bool":  "entry_4_python",   # What is boolean?
	"python.range": "entry_9_python",   # Looping
}

# ── Lookup ─────────────────────────────────────────────────────────
static func gates() -> Dictionary:
	var all: Dictionary = {}
	all.merge(LUA_LANGUAGE_GATES)
	all.merge(PYTHON_LANGUAGE_GATES)
	return all

static func gate_for(entry_id: String) -> String:
	return str(gates().get(entry_id, ""))

# Function sections are never gated.
static func section_is_always_available(section: Dictionary) -> bool:
	return str(section.get("kind", "language")) == "functions"

# True when this entry may be shown. Function entries are always available;
# language entries need the dungeon that teaches them.
static func is_entry_available(entry: Dictionary) -> bool:
	var id: String = str(entry.get("id", ""))
	if id.begins_with("automatica.") or id.begins_with("algorithmica."):
		return true
	var gate: String = gate_for(id)
	if gate.is_empty():
		return false
	return Global.learned_entries.has(gate)

# Backwards-compatible name used by the language sections / tests.
static func is_discovered(entry_id: String) -> bool:
	return is_entry_available({"id": entry_id})

# Every entry the section should list right now, in registry order.
#  • functions → all entries (available immediately)
#  • language  → only entries whose dungeon has been cleared
static func entries_for_section(section: Dictionary) -> Array:
	if section_is_always_available(section):
		return (section["entries"] as Array).duplicate()
	var out: Array = []
	for e in (section["entries"] as Array):
		if is_entry_available(e as Dictionary):
			out.append(e)
	return out

# Alias kept for callers written against the previous API.
static func discovered_entries(section: Dictionary) -> Array:
	return entries_for_section(section)

static func section_total(section: Dictionary) -> int:
	return (section["entries"] as Array).size()

static func visible_count(section: Dictionary) -> int:
	return entries_for_section(section).size()

static func discovered_count(section: Dictionary) -> int:
	return visible_count(section)

# Language entries with no gate at all — a content bug, not a gameplay state.
# Function entries are expected to be ungated and are not reported here.
static func ungated_ids() -> PackedStringArray:
	var out := PackedStringArray()
	var all: Dictionary = gates()
	for section in APIReference.encyclopedia_sections():
		if section_is_always_available(section as Dictionary):
			continue
		for e in (section["entries"] as Array):
			var id: String = str((e as Dictionary).get("id", ""))
			if not all.has(id):
				out.append(id)
	return out
