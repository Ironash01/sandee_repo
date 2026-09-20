extends Resource
class_name MobCombatData

# ── Identity ──────────────────────────────────────────────────────
@export var mob_name: String = ""

# ── AI ────────────────────────────────────────────────────────────
## Selects which script under scripts/AI/ drives this mob's movement/behavior.
@export_enum("WOLF", "PIXIE", "HEADLESS_FISH") var ai_type: String = "WOLF"

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
