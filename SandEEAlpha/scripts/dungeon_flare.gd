extends StaticBody2D
class_name DungeonFlare

# ── Dungeon flare obstacle ───────────────────────────────────────────
# Sits on a dungeon wall brick (the wall tile still provides the solid
# collision). It periodically fires a straight-line DungeonProjectile at
# the player — 40 damage on hit — and is destroyable with the sword. It never
# despawns on its own; only a sword hit removes it (with the mellow burst).

const MELLOW_BURST_SCRIPT: GDScript = preload("res://scripts/mellow_burst.gd")
# The flare's own sprite (the vent tile) — the dev item the user authored.
const FLARE_DATA: ItemData = preload("res://resources/items/dungeon_flare.tres")

const FIRE_INTERVAL: float = 2.5
const FIRE_RANGE:    float = 320.0   # only fires when the player is this close
const MAX_HP:        float = 30.0
const GLOW_COLOR:    Color = Color(1.0, 0.55, 0.25)

var _hp:         float = MAX_HP
var _fire_timer: float = FIRE_INTERVAL
var _time:       float = 0.0
var _glow:       PointLight2D = null

func _ready() -> void:
	add_to_group("DungeonFlare")
	# Layer 2 = the sword hitbox's mask, so the player can destroy it.
	# Mask 0 = the flare never blocks anything itself (the wall does that).
	collision_layer = 2
	collision_mask  = 0
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = 11.0
	shape.shape = circle
	add_child(shape)
	_add_visual()
	# Stagger the first shot so a row of flares doesn't volley in sync.
	_fire_timer = randf_range(0.6, FIRE_INTERVAL)

func _add_visual() -> void:
	# The flare's own sprite (the vent brick) from the dev item.
	if FLARE_DATA != null and FLARE_DATA.icon != null:
		var flare := Sprite2D.new()
		flare.texture = FLARE_DATA.icon
		flare.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		add_child(flare)

	# A soft flame bloom over the vent.
	var s := Sprite2D.new()
	s.texture = Global.get_smooth_light_texture(64)
	s.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	s.scale = Vector2(0.55, 0.55)
	s.modulate = Color(1.0, 0.6, 0.3, 0.9)
	add_child(s)

	_glow = PointLight2D.new()
	_glow.texture       = Global.get_smooth_light_texture(128)
	_glow.texture_scale = 0.8
	_glow.color         = GLOW_COLOR
	_glow.energy        = 1.4
	_glow.blend_mode    = Light2D.BLEND_MODE_ADD
	add_child(_glow)

func _physics_process(delta: float) -> void:
	_time += delta
	if _glow != null:
		_glow.energy = 1.4 + sin(_time * 4.0) * 0.5

	var p := Global.player_node as Node2D
	if p == null or not is_instance_valid(p):
		return
	if global_position.distance_to(p.global_position) > FIRE_RANGE:
		return
	_fire_timer -= delta
	if _fire_timer <= 0.0:
		_fire_timer = FIRE_INTERVAL
		_fire_at(p.global_position)

func _fire_at(target: Vector2) -> void:
	var proj := DungeonProjectile.new()
	proj.direction = (target - global_position).normalized()
	get_parent().add_child(proj)
	proj.global_position = global_position

# Sword hit — same shape mobs expose (see sword_swing_effect.gd).
func take_hit(damage: float, _source_pos: Vector2, _apply_knockback: bool = true) -> void:
	if damage <= 0.0 or _hp <= 0.0:
		return
	_hp = maxf(0.0, _hp - damage)
	modulate = Color(1.6, 0.7, 0.5, 1.0)
	if _hp <= 0.0:
		_disappear()

func _disappear() -> void:
	var b: Node2D = MELLOW_BURST_SCRIPT.new() as Node2D
	if b != null:
		b.position = global_position
		get_parent().add_child(b)
	queue_free()
