extends RefCounted
class_name DungeonLearningSummary

# ── Dungeon “What You’ve Learned” content ──────────────────────────
# Builds short, mission-specific bullets from the dungeon's own
# DungeonMissionData: its KnowledgeEntry, description, question types and the
# player's actual hint usage. No scene-name checks are used, so new dungeons
# automatically get a relevant summary from their authored data.

static func points_for(mission: DungeonMissionData, stats: Dictionary) -> Array:
	var points: Array = []
	if mission == null:
		points.append("You completed the dungeon and reviewed its challenge.")
		return points

	var entry: KnowledgeEntry = mission.entry()
	var lang: String = entry.language if entry != null else _question_language(mission)
	var compiler_count: int = 0
	var mcq_count: int = 0
	for question in mission.questions:
		if question == null:
			continue
		if question.is_compiler():
			compiler_count += 1
		else:
			mcq_count += 1

	if mission.is_boss():
		points.append("You defeated the Hitman Miniboss and completed the final main dungeon.")
		if not mission.mission_description.strip_edges().is_empty():
			points.append(_trim(mission.mission_description))
		points.append("You combined combat, movement and dungeon navigation under pressure.")
		return points

	if Global.is_first_main_dungeon(mission.dungeon_index):
		points.append("You explored a tutorial dungeon and learned how its rooms connect.")
	else:
		points.append("You navigated a generated dungeon and reached the Quiz Altar.")

	if entry != null and not entry.entry_name.strip_edges().is_empty():
		points.append("Key idea: %s." % entry.entry_name.strip_edges())

	if not mission.mission_description.strip_edges().is_empty():
		points.append(_trim(mission.mission_description))

	if compiler_count > 0 and mcq_count > 0:
		points.append("You answered questions and wrote real %s code in the compiler." % _language_label(lang))
	elif compiler_count > 0:
		points.append("You wrote and ran real %s code in the compiler." % _language_label(lang))
	elif mcq_count > 0:
		points.append("You checked the idea with multiple-choice questions.")

	var hints: int = int(stats.get("hints_used", 0))
	if hints > 0:
		points.append("You used %d hint%s — review them before the next dungeon."
			% [hints, "" if hints == 1 else "s"])
	else:
		points.append("You solved the quiz without using hints.")

	if entry != null and not entry.keyword.strip_edges().is_empty() \
			and Global.learned_entries.has(entry.id()):
		points.append("You unlocked \"%s\" in the Programming Encyclopedia."
			% entry.keyword.strip_edges())

	if mission.is_extra():
		points.append("You completed an optional extra dungeon.")
	return points

static func _question_language(mission: DungeonMissionData) -> String:
	for question in mission.questions:
		if question != null and not question.language.is_empty():
			return question.language
	return ""

static func _language_label(lang: String) -> String:
	if lang == "python":
		return "Python"
	if lang == "lua":
		return "Lua"
	return "programming"

# Keep bullets one readable line on a phone; trim very long authored
# descriptions at a word boundary rather than letting them dominate the modal.
static func _trim(text: String) -> String:
	var clean: String = text.replace("\n", " ").replace("\r", " ").strip_edges()
	while clean.contains("  "):
		clean = clean.replace("  ", " ")
	if clean.length() <= 180:
		return clean
	clean = clean.substr(0, 180)
	var cut: int = clean.rfind(" ")
	if cut > 80:
		clean = clean.substr(0, cut)
	clean = clean.strip_edges()
	while clean.ends_with(".") or clean.ends_with(",") or clean.ends_with(";") \
			or clean.ends_with(":"):
		clean = clean.substr(0, clean.length() - 1)
	return clean + "..."
