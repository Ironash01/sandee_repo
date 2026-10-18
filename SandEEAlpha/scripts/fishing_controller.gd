extends Node2D

# ── Fishing controller ────────────────────────────────────────────
# A child of the player. player.gd starts a cast when the fishing rod is
# selected and the player left-clicks a body of water (validated against the
# active world's water layer). Each cast resolves after cast_seconds; the
# attempt then rolls a per-attempt catch chance (catch_min..catch_max) and, on
# success, REELS the fish in: it flies from the float to the player along an
# upward arc and is then banked (or dropped when the inventory is full). While
# the line is out, a black slack line runs from the player's HANDS to a bobbing
# float, and the held fishing-rod sprite floats at the hands. The attempt is
# cancelled if the player moves away, switches items, or leaves the scene.

const RAW_FISH: Array = [
	preload("res://resources/items/charlie.tres"),
	preload("res://resources/items/glep_glorp.tres"),
	preload("res://resources/items/allan.tres"),
	preload("res://resources/items/pimpim.tres"),
]
const LINE_COLOR: Color = Color(0.0, 0.0, 0.0, 0.95)      # black line
const BOB_COLOR:  Color = Color(0.86, 0.22, 0.18, 0.98)   # float body
const BOB_RIM:    Color = Color(0.96, 0.96, 0.96, 0.85)   # float rim
const RIPPLE_COLOR: Color = Color(1.0, 1.0, 1.0, 0.30)    # water ring

# ── Line / float feel ─────────────────────────────────────────────
const LINE_SEGMENTS: int = 16        # polyline steps for the sagging line
const SAG_RATIO: float = 0.16        # slack as a fraction of cast distance
const SAG_MIN: float = 5.0
const SAG_MAX: float = 30.0
const SAG_WOBBLE: float = 1.6        # slack ripple as the float rides the bob
const BOB_SPEED: float = 3.4         # rad/s
const BOB_AMPLITUDE: float = 2.8     # px of vertical float travel
const BOB_RADIUS: float = 4.0
const RIPPLE_PERIOD: float = 1.1     # s per expanding ripple

# The line leaves the player at the HANDS — roughly the vertical middle of the
# 32x64 player art (which spans about -15..+23 in local space, feet at +23),
# not at the chest-height origin.
const HAND_OFFSET: Vector2 = Vector2(0.0, 4.0)

# ── Held rod + reel-in ────────────────────────────────────────────
const ROD_SCALE: float = 0.9         # held rod icon size
const ROD_FORWARD: float = 8.0       # px the rod is held out toward the float
const ROD_BOB: float = 1.4           # px the held rod floats up/down
const REEL_TIME: float = 0.45        # s for the fish to fly to the player
const REEL_ARC: float = 28.0         # px the reel arc bows upward

@export var cast_seconds: float = 5.0
@export var catch_min:    float = 0.70
@export var catch_max:    float = 0.90
## Cancel the attempt once the player has wandered this far (px) from the cast.
@export var move_cancel_dist: float = 64.0

var _active: bool = false
var _elapsed: float = 0.0
var _bob_time: float = 0.0
var _cast_point: Vector2 = Vector2.ZERO
var _player_start: Vector2 = Vector2.ZERO

# Reel-in state
var _reeling: bool = false
var _reel_t: float = 0.0
var _reel_from: Vector2 = Vector2.ZERO
var _pending_fish: ItemData = null
var _rod_sprite: Sprite2D = null
var _fish_sprite: Sprite2D = null

func _ready() -> void:
	z_index = 1000
	_rod_sprite = Sprite2D.new()
	_rod_sprite.z_index = 1                 # relative → drawn above the line
	_rod_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_rod_sprite.scale = Vector2(ROD_SCALE, ROD_SCALE)
	_rod_sprite.visible = false
	add_child(_rod_sprite)
	set_process(false)

func is_active() -> bool:
	return _active

func start(cast_point: Vector2) -> void:
	var p := get_parent() as Node2D
	if p == null:
		return
	_active = true
	_reeling = false
	_elapsed = 0.0
	_bob_time = 0.0
	_cast_point = cast_point
	_player_start = p.global_position
	_show_rod()
	set_process(true)
	queue_redraw()
	Global.log_chat("[color=#7fd0ff]You cast your line...[/color]")

func cancel(reason: String = "") -> void:
	if not _active:
		return
	_end_cast()
	if reason != "":
		Global.log_chat("[color=#ffaa66]%s[/color]" % reason)

# Show the held fishing-rod icon at the hands for the whole cast.
func _show_rod() -> void:
	if _rod_sprite == null:
		return
	var held: Variant = Global.get_hotbar_item()
	if held != null:
		var d: ItemData = (held as Dictionary).get("data") as ItemData
		if d != null:
			_rod_sprite.texture = d.icon
	_rod_sprite.position = HAND_OFFSET
	_rod_sprite.visible = _rod_sprite.texture != null

func _end_cast() -> void:
	_active = false
	_reeling = false
	set_process(false)
	if _rod_sprite != null and is_instance_valid(_rod_sprite):
		_rod_sprite.visible = false
	queue_redraw()

func _process(delta: float) -> void:
	if not _active:
		return
	_bob_time += delta
	_update_rod()
	queue_redraw()
	if _reeling:
		return   # the reel tween drives the rest
	var p := get_parent() as Node2D
	if p == null or not is_instance_valid(p):
		cancel()
		return
	# Equipment changed → cancel (the rod must stay selected).
	var held: Variant = Global.get_hotbar_item()
	var data: ItemData = (held as Dictionary)["data"] as ItemData if held != null else null
	if data == null or not data.is_fishing_rod:
		cancel("Fishing interrupted (rod unequipped).")
		return
	if p.global_position.distance_to(_player_start) > move_cancel_dist:
		cancel("Fishing interrupted (you moved).")
		return
	_elapsed += delta
	if _elapsed >= cast_seconds:
		_resolve()

# The rod floats at the hands: held slightly out toward the float and bobbing
# in time with the line.
func _update_rod() -> void:
	if _rod_sprite == null or not is_instance_valid(_rod_sprite) or not _rod_sprite.visible:
		return
	var wave: float = sin(_bob_time * BOB_SPEED)
	var to_float: Vector2 = _float_local() - HAND_OFFSET
	var forward: Vector2 = to_float.normalized() * ROD_FORWARD if to_float.length() > 1.0 else Vector2.ZERO
	_rod_sprite.position = HAND_OFFSET + forward + Vector2(0.0, wave * ROD_BOB)

func _resolve() -> void:
	var chance: float = randf_range(catch_min, catch_max)
	if randf() > chance:
		_end_cast()
		Global.log_chat("[color=#ffaa66]The fish got away...[/color]")
		return
	_begin_reel(RAW_FISH[randi() % RAW_FISH.size()])

# Reel in: the fish flies from the float to the player along an upward arc and
# is banked on arrival (so the item appears exactly when the fish reaches you).
func _begin_reel(fish: ItemData) -> void:
	_pending_fish = fish
	_reel_from = _float_local()      # capture the bobbing float BEFORE flipping to reeling
	_reeling = true
	_reel_t = 0.0
	Global.log_chat("[color=#7fd0ff]Something's on the line![/color]")
	if _fish_sprite != null and is_instance_valid(_fish_sprite):
		_fish_sprite.queue_free()
	_fish_sprite = Sprite2D.new()
	_fish_sprite.texture = fish.icon
	_fish_sprite.z_index = 2
	_fish_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_fish_sprite.position = _reel_from
	add_child(_fish_sprite)
	var tw := create_tween()
	tw.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_method(_set_reel_t, 0.0, 1.0, REEL_TIME)
	tw.tween_callback(_finish_reel)

func _set_reel_t(t: float) -> void:
	_reel_t = t
	if _fish_sprite != null and is_instance_valid(_fish_sprite):
		_fish_sprite.position = _float_local()
		_fish_sprite.scale = Vector2.ONE * lerpf(1.0, 0.55, t)
		_fish_sprite.modulate.a = lerpf(1.0, 0.9, t)
	queue_redraw()

func _finish_reel() -> void:
	var fish: ItemData = _pending_fish
	_pending_fish = null
	if _fish_sprite != null and is_instance_valid(_fish_sprite):
		_fish_sprite.queue_free()
	_fish_sprite = null
	_end_cast()
	if fish != null:
		_award(fish)

func _award(fish: ItemData) -> void:
	if Global.add_item(fish.to_dict(1)):
		Global.log_chat("[color=#9be89b]Caught a %s![/color]" % fish.item_name)
		return
	# Inventory full → drop it in the world via the shared drop path (one tile in
	# FRONT OF THE PLAYER, on land). Dropping at the water cast point would put it
	# somewhere the player can't walk to pick it up, silently losing the catch.
	var p := get_parent() as Node2D
	var at: Vector2 = p.global_position if p != null and is_instance_valid(p) else _cast_point
	Global.drop_item({"data": fish, "quantity": 1}, at)
	Global.log_chat("[color=#9be89b]Caught a %s! (inventory full - dropped)[/color]" % fish.item_name)

func _exit_tree() -> void:
	_active = false
	# Safety net: if the scene is torn down mid-reel, still bank the catch.
	if _pending_fish != null:
		var fish: ItemData = _pending_fish
		_pending_fish = null
		Global.add_item(fish.to_dict(1))

# The float's local position: the bobbing cast point while waiting, or the
# retracting arc while reeling in.
func _float_local() -> Vector2:
	if _reeling:
		var mid: Vector2 = (_reel_from + HAND_OFFSET) * 0.5 + Vector2(0.0, -REEL_ARC)
		return _quad_bezier(_reel_from, mid, HAND_OFFSET, _reel_t)
	var bob: Vector2 = to_local(_cast_point)
	bob.y += sin(_bob_time * BOB_SPEED) * BOB_AMPLITUDE
	return bob

func _draw() -> void:
	if not _active:
		return
	var s: float = Global.ui_scale
	var end: Vector2 = _float_local()
	var wave: float = 0.0 if _reeling else sin(_bob_time * BOB_SPEED)

	# Slack string from the hands to the float.
	var pts: PackedVector2Array = _string_points(HAND_OFFSET, end, wave)
	draw_polyline(pts, LINE_COLOR, maxf(1.0, 2.0 * s), true)

	if _reeling:
		return   # the flying fish sprite replaces the float during the reel

	# Expanding water ripple synced to the bob.
	var rp: float = fmod(_bob_time, RIPPLE_PERIOD) / RIPPLE_PERIOD
	var ripple: Color = RIPPLE_COLOR
	ripple.a *= 1.0 - rp
	draw_arc(end, (BOB_RADIUS + rp * 10.0) * s, 0.0, TAU, 24, ripple, maxf(1.0, 1.5 * s), true)

	# The float: red body with a light rim.
	var r: float = BOB_RADIUS * s
	draw_circle(end, r, BOB_COLOR)
	draw_arc(end, r, 0.0, TAU, 20, BOB_RIM, maxf(1.0, 1.2 * s), true)

func _quad_bezier(p0: Vector2, c: Vector2, p1: Vector2, t: float) -> Vector2:
	var u: float = 1.0 - t
	return u * u * p0 + 2.0 * u * t * c + t * t * p1

# Slack string from `start` to `end`: a quadratic Bezier bowed downward. The sag
# grows with cast distance (longer line droops more) and wobbles with `wave`
# (the float's bob) so it reads as real cord. Split out so the geometry can be
# unit-tested without a renderer.
func _string_points(start: Vector2, end: Vector2, wave: float) -> PackedVector2Array:
	var span: Vector2 = end - start
	var dist: float = span.length()
	var sag: float = clampf(dist * SAG_RATIO, SAG_MIN, SAG_MAX) + wave * SAG_WOBBLE
	var ctrl: Vector2 = start + span * 0.5 + Vector2(0.0, sag)
	var pts := PackedVector2Array()
	for i in range(LINE_SEGMENTS + 1):
		pts.append(_quad_bezier(start, ctrl, end, float(i) / float(LINE_SEGMENTS)))
	return pts
