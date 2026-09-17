extends Node2D
# ── Item swing effect ─────────────────────────────────────────────
# A transient swing owned by the PLAYER (parented under it, so it moves with
# the character) and spawned by _trigger_swing in player.gd. The held item's
# icon sweeps through a vertical top-to-bottom chop, oriented to the facing
# direction so the item comes down on the correct side. The arc sheet and a
# mellow puff burst sit at the blade tip. Single-instance and non-overlapping
# is enforced by the player (it won't spawn a new one until this one has
# finished and freed itself).

const SWING_TEX:         Texture2D = preload("res://sprites/particles_effects/sword_swing.png")
const MELLOW_TEX:        Texture2D = preload("res://sprites/particles_effects/mellow_effect.png")
const SWING_FRAME:       int       = 32
const SWING_COUNT:       int       = 3
const SWING_FPS:         float     = 12.0
const MELLOW_FRAME:      int       = 16
const MELLOW_COUNT:      int       = 5
const MELLOW_FPS:        float     = 20.0
const MELLOW_PUFF_COUNT: int       = 3

const SWING_DURATION:    float     = 0.24
# The item icon is drawn at this scale while it sweeps. Raised from 0.60 so
# the held item reads clearly at swing size next to the enlarged arc.
const ITEM_SCALE:        float     = 0.90
const ITEM_GAP:          float     = 2.0
const ITEM_HALF:         float     = 32.0 * ITEM_SCALE * 0.5
# The blade's far (tip) edge; the arc/puff anchor ~ITEM_TIP_GAP past it so the
# effect sits at the point of the sword, not the player's body.
const ITEM_TIP:          float     = ITEM_GAP + 2.0 * ITEM_HALF
const ITEM_TIP_GAP:      float     = 2.0
# The sword collision hugs the actual blade: it starts at the blade base
# (ITEM_GAP) and ends at the tip (ITEM_TIP), with a perpendicular width equal
# to the item's on-screen height. Because the hitbox is parented to the pivot
# it rotates with the blade as it sweeps, so the collision tracks the drawn
# sword instead of a big box covering the whole reach (which felt like the
# hitbox was offset from the blade).
const BLADE_BASE:        float     = ITEM_GAP
const BLADE_LEN:         float     = ITEM_TIP - ITEM_GAP
const BLADE_W:           float     = ITEM_SCALE * 32.0
# The blade sweeps at waist height while grass is anchored at the feet, so the
# grass-cut test inflates the blade box by this much.
const GRASS_CUT_PAD:     float     = 14.0
# The arc the item sweeps through — a Terraria-style crescent: it starts
# raised behind and swings down/forward past the front. The art is authored
# facing EAST (right); left is that same arc mirrored, and the vertical
# facings rotate the sweep (see _base_rotation_rad / _arm_origin).
const SWING_START_DEG:   float     = -110.0
const SWING_END_DEG:     float     = 70.0

# Arc size relative to the authored sprite (raised again so the swing reads
# clearly at gameplay scale).
const SWING_ARC_SCALE:   float     = 2.5

# Facing name → direction vector (same table the player uses).
const DIR_VEC: Dictionary = {
	"south": Vector2(0, 1), "north": Vector2(0, -1),
	"east": Vector2(1, 0), "west": Vector2(-1, 0),
	"south-east": Vector2(1, 1), "south-west": Vector2(-1, 1),
	"north-east": Vector2(1, -1), "north-west": Vector2(-1, -1),
}

# The pivot's "shoulder" offset — authored for only the 4 directions the game
# actually uses (+x = the un-mirrored frame). Left/right are the same swing
# mirrored, so a west facing uses the east origin and the node's X mirror
# flips it into place. Diagonal facings reuse the nearest cardinal.
const ARM_ORIGINS: Dictionary = {
	"east":  Vector2(12.0, 4.0),
	"west":  Vector2(-12.0, 4.0),   # == east mirrored (see _arm_origin)
	"south": Vector2(0.0, 12.0),
	"north": Vector2(0.0, -8.0),
}

# Item icon texture to swing (set by the spawner); null = nothing.
var _icon:       Texture2D = null
# Facing dir name — set by the spawner so the chop respects the facing side.
var _dir:        String = "south"
# Combat damage this swing deals to mobs (0 for a non-weapon swing). Set by
# the player's _trigger_swing from the held item's sword_damage().
var _damage:     float  = 0.0
# "swing" = item sweep + tip arc + puff burst (a player swing); "puff" =
# grass-break particle only, spawned at the cut site. Set by the spawner.
var _mode:       String = "swing"

func _ready() -> void:
	z_index = 40  # above the player sprite (child of the player)
	var lifespan: float = 0.1

	# Left and right are the SAME swing, mirrored on X (never rotated 180°),
	# so a west-facing player sees an identical-but-flipped crescent.
	var v: Vector2 = DIR_VEC.get(_dir, Vector2(1, 0))
	scale = Vector2(-1.0 if v.x < 0.0 else 1.0, 1.0)

	if _mode == "swing":
		var pivot := _build_item_swing()
		add_child(pivot)
		lifespan = maxf(lifespan, SWING_DURATION)

		# Arc + puff burst at the blade tip, parented under the pivot so they
		# travel with the blade as it sweeps.
		var tip := Vector2(ITEM_TIP + ITEM_TIP_GAP, 0.0)
		var arc := _build_anim_sprite(SWING_TEX, SWING_FRAME, SWING_COUNT, SWING_FPS)
		arc.position = tip
		arc.scale = Vector2(SWING_ARC_SCALE, SWING_ARC_SCALE)
		pivot.add_child(arc)
		lifespan = maxf(lifespan, SWING_COUNT / SWING_FPS)
		_spawn_mellow_burst(pivot, tip)
		# The hitbox is spawned for EVERY swing (not just damaging ones) so it
		# is active the whole animation and cuts grass as well as mobs.
		_spawn_hitbox(pivot)
	else:
		# Grass break: a single puff at the cut site (this node sits there).
		_spawn_mellow_burst(self, Vector2.ZERO, 1.0)

	# Despawn just after the longest animation finishes; freeing also clears
	# the player's active-swing flag (see player.gd _trigger_swing).
	get_tree().create_timer(lifespan + 0.05).timeout.connect(queue_free)

# Spawns a puff burst as a child of `parent` at `at_pos`, staying near the
# swing tip. Grass breaks (count 1) drop a single puff at the cut site.
func _spawn_mellow_burst(parent: Node2D, at_pos: Vector2, count: int = MELLOW_PUFF_COUNT) -> void:
	for i in range(count):
		var puff := _build_anim_sprite(MELLOW_TEX, MELLOW_FRAME, MELLOW_COUNT, MELLOW_FPS)
		parent.add_child(puff)
		puff.position = at_pos + Vector2(
			randf_range(-10.0, 10.0),
			randf_range(-10.0, 10.0)
		)
		puff.modulate.a = lerpf(1.0, 0.75, float(i) / maxf(count - 1, 1))
		if count > 1:
			puff.speed_scale = randf_range(0.9, 1.1)

# One-shot swing hitbox (the "sword collision"): an Area2D parented to the
# item pivot that detects overlapping mobs while the blade sweeps. Uses the
# body_entered signal (reliable, no per-frame polling) and is debounced via a
# hit-set so a mob isn't struck twice by the same swing. The shape hugs the
# blade reach, sized to the full tip arc.
# A _process check runs every frame during the swing so the hitbox is active
# throughout the ENTIRE animation — mobs caught mid-sweep are hit immediately
# rather than waiting for a single mid-swing timer.
var _hitbox_active: bool = false
var _hitbox_area:  Area2D = null
var _hit_mobs:     Array  = []
var _cut_grass:    Array  = []

func _spawn_hitbox(pivot: Node2D) -> void:
	_hit_mobs.clear()
	_cut_grass.clear()
	var area := Area2D.new()
	area.collision_layer = 0
	area.collision_mask  = 2   # layer 2 = mobs (see Wolf.tscn / Pixie.tscn)
	area.monitoring      = true
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	# Cover the blade reach: a box hugging the drawn blade (base->tip), thin
	# enough to match the sword but wide enough to catch a mob at the point.
	rect.size = Vector2(BLADE_LEN, BLADE_W)
	shape.shape = rect
	shape.position = Vector2(BLADE_BASE + BLADE_LEN * 0.5, 0.0)
	area.add_child(shape)
	pivot.add_child(area)
	_hitbox_area = area

	# Signal-based hits for mobs that enter the area for the first time.
	area.body_entered.connect(func(body: Node) -> void:
		if body != null and body.has_method("take_hit") and not _hit_mobs.has(body):
			_hit_mobs.append(body)
			body.call("take_hit", _damage, global_position)
	)

	# Also check every frame so mobs already overlapping (or caught mid-sweep)
	# are hit immediately — the hitbox is active throughout the ENTIRE animation.
	_hitbox_active = true

# Runs every frame for the WHOLE swing: mobs caught anywhere along the sweep
# are hit immediately, and any grass tuft the blade passes over is cut.
func _process(_delta: float) -> void:
	if not _hitbox_active or _hitbox_area == null or not is_instance_valid(_hitbox_area):
		return
	for body in _hitbox_area.get_overlapping_bodies():
		if body.has_method("take_hit") and not _hit_mobs.has(body):
			_hit_mobs.append(body)
			body.call("take_hit", _damage, global_position)
	_cut_overlapping_grass()

# Cuts every GrassTuft whose ground anchor falls inside the blade rectangle
# (BLADE_BASE..BLADE_BASE+BLADE_LEN along the pivot's +x, |y| <= BLADE_W/2),
# padded a little so grass at the player's feet is caught by a waist-high
# sweep. Uses the hitbox's global transform so it tracks the sweep in any
# direction.
func _cut_overlapping_grass() -> void:
	var xf: Transform2D = _hitbox_area.global_transform
	for node in get_tree().get_nodes_in_group("Grass"):
		var tuft := node as Node2D
		if tuft == null or not is_instance_valid(tuft) or _cut_grass.has(tuft):
			continue
		var local: Vector2 = xf.affine_inverse() * tuft.global_position
		if local.x < BLADE_BASE - GRASS_CUT_PAD or local.x > BLADE_BASE + BLADE_LEN + GRASS_CUT_PAD:
			continue
		if absf(local.y) > BLADE_W * 0.5 + GRASS_CUT_PAD:
			continue
		_cut_grass.append(tuft)
		if tuft.has_method("cut"):
			tuft.call("cut")

# Terraria-style sweep: a child pivot offset to the player's side (the arm)
# that holds the item drawn along +x. It starts raised behind and sweeps
# down/forward past the front, easing in toward the end like a real blade's
# momentum — a snappy crescent rather than a mechanical rotation. The whole
# sweep is rotated by the facing angle so it works in all 8 directions.
func _build_item_swing() -> Node2D:
	# Only the vertical part rotates; the left/right flip is the node's X
	# scale (set in _ready), so the two horizontally-opposite swings are the
	# same art mirrored instead of a 180° rotation.
	var base: float = _base_rotation_rad()

	var pivot := Node2D.new()
	pivot.position = _arm_origin()

	var item := Sprite2D.new()
	item.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	item.texture = _icon
	item.scale = Vector2(ITEM_SCALE, ITEM_SCALE)
	item.position = Vector2(ITEM_GAP + ITEM_HALF, 0.0)
	pivot.add_child(item)

	var tw := create_tween()
	tw.tween_property(pivot, "rotation", base + deg_to_rad(SWING_START_DEG), 0.0)
	tw.tween_property(pivot, "rotation", base + deg_to_rad(SWING_END_DEG), SWING_DURATION) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	return pivot

# Builds a one-shot AnimatedSprite2D from a horizontal sheet of FRAME sized
# frames, sliced into per-frame AtlasTextures.
func _build_anim_sprite(tex: Texture2D, frame: int, count: int, fps: float) -> AnimatedSprite2D:
	var sprite := AnimatedSprite2D.new()
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sprite.position       = Vector2.ZERO

	var anim := SpriteFrames.new()
	anim.remove_animation("default")
	anim.add_animation("effect")
	anim.set_animation_speed("effect", fps)
	anim.set_animation_loop("effect", false)
	for i in range(count):
		var at := AtlasTexture.new()
		at.atlas = tex
		at.region = Rect2(i * frame, 0, frame, frame)
		anim.add_frame("effect", at)
	sprite.sprite_frames = anim
	sprite.animation_finished.connect(sprite.stop)
	sprite.play("effect")
	return sprite

func _base_rotation_rad() -> float:
	# Only the VERTICAL component rotates: atan2(y, |x|) is 0 for east/west
	# (the node's X mirror handles left/right), ±45° for diagonals and ±90°
	# for north/south.
	var v: Vector2 = DIR_VEC.get(_dir, Vector2(1, 0))
	return atan2(v.y, absf(v.x))

# Arm origin in the un-mirrored frame (+x = right). A west facing returns the
# east origin — the node's X mirror flips it into place, so left/right stay
# the same swing mirrored. Diagonal facings reuse the nearest cardinal.
func _arm_origin() -> Vector2:
	var v: Vector2 = DIR_VEC.get(_dir, Vector2(1, 0))
	if absf(v.x) >= absf(v.y):
		return ARM_ORIGINS["east"]
	if v.y > 0.0:
		return ARM_ORIGINS["south"]
	return ARM_ORIGINS["north"]
