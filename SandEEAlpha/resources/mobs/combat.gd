extends Resource
class_name MobCombatData

# ── Identity ──────────────────────────────────────────────────────
@export var mob_name: String = ""

# ── AI ────────────────────────────────────────────────────────────
## Selects which script under scripts/AI/ drives this mob's movement/behavior.
@export_enum("WOLF", "PIXIE", "HEADLESS_FISH") var ai_type: String = "WOLF"

# ── Combat ────────────────────────────────────────────────────────
## Mobs with damage > 1 will hit the player on proximity contact.
@export var damage: float = 0.0
@export var health: float = 10.0
@export var is_boss: bool = false

# ── Movement ──────────────────────────────────────────────────────
@export var speed: float = 38.0

# ── Spawning — time of day ─────────────────────────────────────────
@export var spawn_during_day:   bool = true
@export var spawn_during_night: bool = true

# ── Spawning — biomes ────────────────────────────────────────────────
@export_group("Spawn Biomes")
@export var spawn_plains: bool = false
@export var spawn_desert: bool = false
@export var spawn_snowy:  bool = false
@export var spawn_ocean:  bool = false

# ── Spawning — amount per eligible chunk ────────────────────────────
@export_group("Spawn Rate")
@export var min_spawn: int = 1
@export var max_spawn: int = 3
