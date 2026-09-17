extends CanvasModulate

# Full loop = one day phase + one night phase, 12 minutes each.
const DAY_LENGTH:   float = 720.0
const NIGHT_LENGTH: float = 720.0
const CYCLE_LENGTH: float = DAY_LENGTH + NIGHT_LENGTH

# time_of_day cycles 0..1 across the full loop:
# 0.0 = sunrise, 0.25 = noon, 0.5 = sunset, 0.75 = midnight, 1.0 wraps to 0.0.
var time_of_day: float = 0.25

# Fires Global.day_started / Global.night_started exactly once per crossing.
var _was_daytime: bool = true  # matches the initial time_of_day = 0.25 (noon)

# ── Snowstorm whiteout tint ──────────────────────────────────────
# Blended in/out on top of the sky gradient — reuses the CanvasModulate this
# node already updates every frame, so "limited visibility" costs one extra
# Color.lerp() instead of a second overlay node.
const STORM_TINT:       Color = Color(0.75, 0.78, 0.85)
const STORM_MAX_BLEND:  float = 1.0  # 2x the previous 0.55, clamped at 1.0 (fully tinted — Color.lerp isn't clamped past that)
const STORM_EASE_SPEED: float = 0.15  # blend fraction per second toward target
var _storm_blend: float = 0.0

var _sky_gradient: Gradient
var _debug_log_timer: float = 0.0

func _ready() -> void:
	Global.day_night_cycle = self
	_sky_gradient = Gradient.new()
	_sky_gradient.offsets = PackedFloat32Array([0.0, 0.25, 0.5, 0.75, 1.0])
	_sky_gradient.colors  = PackedColorArray([
		Color(0.95, 0.75, 0.60), # sunrise
		Color(1.00, 1.00, 1.00), # noon — full brightness, no tint
		Color(0.95, 0.60, 0.45), # sunset
		Color(0.15, 0.17, 0.32), # midnight
		Color(0.95, 0.75, 0.60), # sunrise (wraps back to offset 0.0)
	])
	# Restore the saved time of day (set by Global.load_game) instead of always
	# starting at noon — mirrors Global's pending_player_pos/pending_world_data
	# pattern. _was_daytime is set to match so the first _update_day_state()
	# doesn't spuriously emit a day/night crossing on the load frame.
	if Global.pending_time_of_day >= 0.0:
		time_of_day = fmod(Global.pending_time_of_day, 1.0)
		Global.pending_time_of_day = -1.0
	_was_daytime = is_daytime()
	Global.time_of_day = time_of_day
	color = _sky_gradient.sample(time_of_day)

func _process(delta: float) -> void:
	time_of_day = fmod(time_of_day + delta / CYCLE_LENGTH, 1.0)
	Global.time_of_day = time_of_day
	_update_color(delta)
	_update_day_state()
	# Diagnostic heartbeat — logs time_of_day + flag every 5 seconds.
	_debug_log_timer += delta
	if _debug_log_timer >= 5.0:
		_debug_log_timer = 0.0
		print("[DayNight] time_of_day=", "%.3f" % time_of_day, " Global.is_daytime=", Global.is_daytime)

func is_daytime() -> bool:
	# The sky gradient becomes visibly dark around 0.55–0.6 (between sunset
	# at 0.5 and midnight at 0.75).  Use 0.58 so the flag flips when the
	# sky actually looks like night, not at the mathematical midpoint.
	return time_of_day < 0.58

# Debug command (/daynight) — instantly snaps to the opposite period's
# midpoint (noon / midnight) instead of just flipping by 0.5, so the jump is
# always to the strongest, most visually obvious point of that period.
func toggle_period() -> void:
	time_of_day = 0.75 if is_daytime() else 0.25
	_update_color(0.0)
	_update_day_state()
	print("[DayNight] toggle_period | time_of_day=", time_of_day, " is_daytime()=", is_daytime(), " Global.is_daytime=", Global.is_daytime)

func _update_color(delta: float) -> void:
	var target_blend: float = STORM_MAX_BLEND if Global.snowstorm_active else 0.0
	_storm_blend = move_toward(_storm_blend, target_blend, STORM_EASE_SPEED * delta)
	var base_color: Color = _sky_gradient.sample(time_of_day)
	color = base_color.lerp(STORM_TINT, _storm_blend) if _storm_blend > 0.0 else base_color

# Emits Global.day_started / Global.night_started exactly once per crossing —
# used to roll the snowstorm chance and to cut a storm short when night falls.
func _update_day_state() -> void:
	var now_day: bool = is_daytime()
	Global.is_daytime = now_day
	if now_day and not _was_daytime:
		Global.day_started.emit()
	elif not now_day and _was_daytime:
		Global.night_started.emit()
	_was_daytime = now_day
