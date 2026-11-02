extends RefCounted
class_name TutorialUiReveal

# ── Opening-tutorial HUD reveal tiers ───────────────────────────────
# This is deliberately scoped to the opening onboarding only. Later tutorial
# lessons (Automatica, Algorithmica, caves, pixie caves, waypoints) map to ALL,
# so this system can never hide unrelated HUD elements again after the opening.
#
# Current guided-v3 steps map to the requested milestones:
#   welcome / move_*                    -> Basic Movement
#   axe_select / tree_chop / craft_station -> placement/tools/tree harvesting
#   dungeon_*                          -> Dungeon 1 (and the opening dungeon end)
#   automatica and everything after    -> ALL (normal gameplay HUD)
#
# The aliases below also accept the design-doc milestone names, so adding a
# literal basic_placement or dungeon_2 step later does not require a rewrite.

enum Tier { MOVEMENT, TOOLS, DUNGEON, ALL }

const COMPLETE_FLAG: String = "opening_ui_complete"
const OPENING_STEP_FLAG: String = "opening_ui_step"

const STEP_ORDER: Array = [
	"welcome",
	"move_one", "move_two",
	"axe_select", "tree_chop", "craft_station",
	"dungeon_travel", "dungeon_knowledge", "dungeon_quiz", "dungeon_exit",
	"automatica",
]

const TIER_BY_STEP: Dictionary = {
	"welcome": Tier.MOVEMENT,
	"move_one": Tier.MOVEMENT,
	"move_two": Tier.MOVEMENT,
	"basic_movement": Tier.MOVEMENT,

	"axe_select": Tier.TOOLS,
	"tree_chop": Tier.TOOLS,
	"craft_station": Tier.TOOLS,
	"basic_placement": Tier.TOOLS,
	"basic_tree_harvesting": Tier.TOOLS,
	"basic_tree": Tier.TOOLS,

	"dungeon_travel": Tier.DUNGEON,
	"dungeon_knowledge": Tier.DUNGEON,
	"dungeon_quiz": Tier.DUNGEON,
	"dungeon_exit": Tier.DUNGEON,
	"dungeon_1": Tier.DUNGEON,
	"dungeon_2": Tier.DUNGEON,

	# Later onboarding is intentionally ALL: never hide UI again.
	"automatica": Tier.ALL,
	"automatica_combat": Tier.ALL,
	"algorithmica": Tier.ALL,
	"cave_regular": Tier.ALL,
	"cave_pixie": Tier.ALL,
	"waypoint": Tier.ALL,
	"finish": Tier.ALL,
}


static func tier_for_step(step_id: String) -> int:
	# Unknown/later steps default to the normal HUD, never to a hidden one.
	return int(TIER_BY_STEP.get(step_id, Tier.ALL))


static func tier_for_progress(stage: int, completed: bool,
		flags: Dictionary, cleared_dungeons: int = 0) -> int:
	# Completed opening tutorial, a completed Dungeon-2-equivalent, or two
	# cleared dungeons permanently graduate the player to the normal HUD.
	if completed or bool(flags.get(COMPLETE_FLAG, false)) or cleared_dungeons >= 2:
		return int(Tier.ALL)

	var tier: int = int(Tier.MOVEMENT)
	# The last saved step is useful when a future step order differs from the
	# index list; take the maximum so a stale lower tier can never re-hide UI.
	var saved_step := str(flags.get(OPENING_STEP_FLAG, "")).strip_edges()
	if not saved_step.is_empty():
		tier = maxi(tier, tier_for_step(saved_step))

	if stage >= STEP_ORDER.size():
		tier = int(Tier.ALL)
	elif stage >= 0:
		tier = maxi(tier, tier_for_step(str(STEP_ORDER[stage])))
	return tier


static func tier_name(tier: int) -> String:
	match tier:
		Tier.MOVEMENT: return "movement"
		Tier.TOOLS: return "tools"
		Tier.DUNGEON: return "dungeon"
		Tier.ALL: return "all"
	return "unknown"
