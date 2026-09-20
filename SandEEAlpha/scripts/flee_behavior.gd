extends RefCounted
class_name FleeBehavior

# ── Reusable "run away from the attacker" state (PASSIVE mobs) ───────
# One instance per mob. A mob's take_hit() calls start() with the attacker's
# position; each frame the mob asks tick() whether it should still be fleeing,
# and direction() for where to run. This mirrors the existing player-death
# dispersal (away from a point, plus a per-mob random spread) so the movement
# feel is consistent, and it is deliberately dumb: no teleporting, no
# repositioning — the mob simply runs.

var active:  bool    = false
var _timer:  float   = 0.0
var _from:   Vector2 = Vector2.ZERO
var _spread: float   = 0.0

func start(from_pos: Vector2, duration: float) -> void:
	active  = true
	_timer  = duration
	_from   = from_pos
	_spread = randf_range(-0.5, 0.5)

func stop() -> void:
	active = false

# True while the mob should keep fleeing. Auto-stops on timeout or once it is
# safely away from the attacker.
func tick(delta: float, mob_pos: Vector2, safe_dist: float) -> bool:
	if not active:
		return false
	_timer -= delta
	if _timer <= 0.0 or mob_pos.distance_to(_from) >= safe_dist:
		active = false
		return false
	return true

# Unit direction away from the attacker (with a per-flee random spread).
func direction(mob_pos: Vector2) -> Vector2:
	var away: Vector2 = mob_pos - _from
	if away.length_squared() < 0.001:
		away = Vector2.RIGHT
	return away.normalized().rotated(_spread)

# Keeps the flee pointed away from the attacker as it (and the mob) move.
func refresh(from_pos: Vector2) -> void:
	_from = from_pos
