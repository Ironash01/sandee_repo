extends Resource
class_name MobCombatData

# ── Identity ──────────────────────────────────────────────────────
@export var mob_name: String = ""

# ── AI ────────────────────────────────────────────────────────────
## Selects which script under scripts/AI/ drives this mob's movement/behavior.
@export_enum("WOLF", "WANDER", "PIXIE", "HEADLESS_FISH") var ai_type: String = "WOLF"

# ── Combat ────────────────────────────────────────────────────────
## HOSTILE mobs fight the player; PASSIVE mobs run away when hit.
enum Behavior { HOSTILE, PASSIVE }
@export var behavior: Behavior = Behavior.HOSTILE

## Mobs with damage > 1 will hit the player on proximity contact.
@export var damage: float = 0.0
@export var health: float = 10.0
@export var is_boss: bool = false

# ── Movement ──────────────────────────────────────────────────────
@export var speed: float = 38.0

# ── Flee (PASSIVE only) ───────────────────────────────────────────
@export_group("Flee (passive only)")
## Speed multiplier while running away from whoever hit it.
@export var flee_speed_mult: float = 1.6
## Seconds spent fleeing after a hit.
@export var flee_duration: float = 5.0
## Stop fleeing once this far from the attacker.
@export var flee_safe_dist: float = 240.0
## Only flee once HP drops to this fraction of max (0 = flee on any hit).
@export_range(0.0, 1.0, 0.05) var flee_health_pct: float = 0.0

# ── Spawning — time of day ─────────────────────────────────────────
@export var spawn_during_day:   bool = true
@export var spawn_during_night: bool = true

# ── Spawning — biomes ────────────────────────────────────────────────
@export_group("Spawn Biomes")
@export var spawn_plains: bool = false
@export var spawn_desert: bool = false
@export var spawn_snowy:  bool = false
@export var spawn_ocean:  bool = false

# ── Spawning — weighting ─────────────────────────────────────────────
@export_group("Spawn Rate")
## Relative chance of being picked by the ambient spawn director (0 = never).
@export_range(0.0, 10.0, 0.1) var spawn_weight: float = 1.0

# ── Spawning — legacy per-chunk amount (kept for reference/tuning) ────
@export var min_spawn: int = 1
@export var max_spawn: int = 3
## Ambient director: spawn a whole GROUP of min_spawn..max_spawn together
## (herds). Off for existing mobs so their spawn behaviour is unchanged.
@export var group_spawn: bool = false

# ── Bestiary ──────────────────────────────────────────────────────────
# Only resources with a non-empty bestiary_id appear in the Bestiary tab.
# The catalog is data-driven so adding a new creature never requires a second
# registry in the UI.
@export_group("Bestiary")
@export var bestiary_id: String = ""
@export var bestiary_category: String = "Creature"
@export_multiline var bestiary_description: String = ""
@export_file("*.png") var bestiary_icon_path: String = ""

# ── Loot ──────────────────────────────────────────────────────────────
# Each entry is {"item_path": String, "min": int, "max": int, "chance": 0..1}.
# The mob rolls each entry independently on death; the Bestiary reads the same
# table so the displayed loot list can never drift from what can drop.
@export_group("Drops")
@export var drops: Array = []

# ── Daytime damage reduction ──────────────────────────────────────────
## Enemies that spawn during the day (sandworms, wolves, pixies) are daytime
## threats and shrug off part of every hit. Applied in each mob's take_hit()
## through damage_taken().
const DAY_DAMAGE_REDUCTION: float = 0.6

## Damage actually dealt to this mob after the daytime reduction.
func damage_taken(amount: float) -> float:
	if spawn_during_day:
		return amount * (1.0 - DAY_DAMAGE_REDUCTION)
	return amount
