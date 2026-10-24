extends Node2D
class_name DungeonExplosion

# ── Dungeon trap explosion ───────────────────────────────────────────
# A one-shot fireball: the 6-frame flame_ass_explosions sheet plays once with
# a warm light flash. Damages the player over a 3x3-tile area centred on the
# blast (see AOE_HALF). Spawned by DungeonTrap at its own tile. Self-frees
# when the animation ends.

const EXPL_TEX:     Texture2D = preload("res://sprites/particles_effects/flame_ass_explosions.png")
const FRAME_SIZE:   int   = 64
const FRAME_COUNT:  int   = 6
const FPS:          float = 14.0
const DAMAGE:       float = 10.0
# 3x3 tiles centred on the blast = a half-extent of 1.5 tiles (48px).
const AOE_HALF:     float = 48.0
const GLOW_COLOR:   Color = Color(1.0, 0.6, 0.25)

# Per-instance overrides. The defaults keep DungeonTrap's blast exactly as it
# was; the Hitman's self-destruct sets damage_fraction + damage_mobs (hitman.gd).
var damage: float = DAMAGE
# If > 0, each target takes this fraction of ITS OWN max HP instead of `damage`.
var damage_fraction: float = 0.0
# Also hit "Mob"-group nodes, not just the player.
var damage_mobs: bool = false

func _ready() -> void:
	z_index = 45
	_add_sprite()
	_add_glow()
	# DEFERRED: add_child() runs _ready() BEFORE the spawner assigns
	# global_position, so testing the blast distance here would use (0,0) and
	# never hit. The deferred call runs after the position is set.
	call_deferred("_apply_damage")
	get_tree().create_timer(FRAME_COUNT / FPS + 0.05).timeout.connect(queue_free)

func _add_sprite() -> void:
	var spr := AnimatedSprite2D.new()
	spr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	# 64px art scaled to 96px so the blast visually fills its 3x3 area.
	spr.scale = Vector2(1.5, 1.5)
	var sf := SpriteFrames.new()
	sf.remove_animation("default")
	sf.add_animation("boom")
	sf.set_animation_speed("boom", FPS)
	sf.set_animation_loop("boom", false)
	for i in range(FRAME_COUNT):
		var at := AtlasTexture.new()
		at.atlas  = EXPL_TEX
		at.region = Rect2(i * FRAME_SIZE, 0, FRAME_SIZE, FRAME_SIZE)
		sf.add_frame("boom", at)
	spr.sprite_frames = sf
	spr.animation_finished.connect(spr.stop)
	spr.play("boom")
	add_child(spr)

# A soft warm pool + a light so the blast blooms through the dungeon's glow.
func _add_glow() -> void:
	var pool := Sprite2D.new()
	pool.texture = Global.get_smooth_light_texture(128)
	pool.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	pool.scale = Vector2(1.4, 1.4)
	pool.modulate = Color(1.0, 0.65, 0.3, 0.85)
	add_child(pool)

	var glow := PointLight2D.new()
	glow.texture       = Global.get_smooth_light_texture(128)
	glow.texture_scale = 1.2
	glow.color         = GLOW_COLOR
	glow.energy        = 2.0
	glow.blend_mode    = Light2D.BLEND_MODE_ADD
	add_child(glow)

# 3x3-tile AoE: damages the player if their centre is within one-and-a-half
# tiles of the blast on BOTH axes.
func _apply_damage() -> void:
	if Global.is_point_in_safe_zone(global_position):
		return   # a blast inside a protected room harms nothing
	var p := Global.player_node as Node2D
	if p != null and is_instance_valid(p) and not Global.is_player_in_safe_zone():
		var d: Vector2 = p.global_position - global_position
		if absf(d.x) <= AOE_HALF and absf(d.y) <= AOE_HALF:
			var amt: float = Global.max_health * damage_fraction if damage_fraction > 0.0 else damage
			Global.damage_player(amt, global_position, d)
	if damage_mobs:
		_damage_mobs()

# Blast also hits every mob in range, each for damage_fraction of its max HP.
func _damage_mobs() -> void:
	for m in get_tree().get_nodes_in_group("Mob"):
		# Untyped + validity: a node freed between the group query and here would
		# throw if assigned to a typed `Node` var.
		var node_ref: Variant = m
		if not (node_ref is Node2D) or not is_instance_valid(node_ref):
			continue
		var node := node_ref as Node2D
		var md: Vector2 = node.global_position - global_position
		if absf(md.x) > AOE_HALF or absf(md.y) > AOE_HALF:
			continue
		var data = node.get("COMBAT_DATA")
		if data == null:
			continue
		var amt: float = float(data.get("health")) * damage_fraction
		if amt <= 0.0:
			continue
		if node.has_method("take_hit"):
			node.call("take_hit", amt, global_position)
