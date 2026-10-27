extends RefCounted
class_name BestiaryCatalog

# ── Bestiary catalog ─────────────────────────────────────────────────
# Every MobCombatData resource with a non-empty bestiary_id is a Bestiary
# entry. Loading through ResourceLoader.list_directory (rather than DirAccess)
# keeps the catalog working in exported builds, where .tres files may be
# remapped. The catalog is intentionally read-only: discovery state lives in
# Global so it is per-world and survives save/load.

const MOB_DIR: String = "res://resources/mobs/"

static var _loaded: bool = false
static var _entries: Array = []          # Array[MobCombatData]
static var _by_id: Dictionary = {}       # bestiary_id -> MobCombatData

static func _ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	_entries.clear()
	_by_id.clear()
	for fname in ResourceLoader.list_directory(MOB_DIR):
		if not fname.ends_with(".tres"):
			continue
		var res: Resource = load(MOB_DIR + fname) as Resource
		if res == null or not (res is MobCombatData):
			continue
		var data: MobCombatData = res as MobCombatData
		var id: String = data.bestiary_id.strip_edges()
		if id.is_empty():
			continue
		if _by_id.has(id):
			push_warning("BestiaryCatalog: duplicate bestiary_id '%s' in %s" % [id, fname])
			continue
		_by_id[id] = data
		_entries.append(data)
	_entries.sort_custom(func(a: MobCombatData, b: MobCombatData) -> bool:
		var ra: int = category_rank(a.bestiary_category)
		var rb: int = category_rank(b.bestiary_category)
		if ra != rb:
			return ra < rb
		return a.mob_name.naturalnocasecmp_to(b.mob_name) < 0)

static func entries() -> Array:
	_ensure_loaded()
	return _entries.duplicate()

static func get_entry(id: String) -> MobCombatData:
	_ensure_loaded()
	return _by_id.get(id.strip_edges()) as MobCombatData

static func has_entry(id: String) -> bool:
	return get_entry(id) != null

static func category_rank(category: String) -> int:
	match category:
		"Friendly": return 0
		"Overworld": return 1
		"Lua Dungeon": return 2
		"Python Dungeon": return 3
		_: return 9

static func invalidate() -> void:
	_loaded = false
	_entries.clear()
	_by_id.clear()
