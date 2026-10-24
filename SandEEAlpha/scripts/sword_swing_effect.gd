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
const MELLOW_PUFF_COUNT: int       = 1

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
# grass-cut test inflates the blade box by this much. Raised from 14 → 26: the
# tight box made grass feel like it had to be hit pixel-perfectly, especially
# with tap-to-cut. This only affects GRASS (the mob hitbox is unchanged).
const GRASS_CUT_PAD:     float     = 26.0
# The arc the item sweeps through — a Terraria-style crescent: it starts
# raised behind and swings down/forward past the front. The art is authored
# facing EAST (right); left is that same arc mirrored, and the vertical
# facings rotate the sweep (see _base_rotation_rad / _arm_origin).
const SWING_START_DEG:   float     = -110.0
const SWING_END_DEG:     float     = 70.0

# The item is (canonically) SUMMONED, not drawn from a sheath, so a cheap
# violet bloom marks the conjured item at the start of the sweep. A per-swing
# GPUParticles2D system was removed because creating it hitched every attack.

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
# World-space aim direction (player -> mouse). When non-zero the swing points
# THIS way instead of using the 8-way _dir — mouse aiming. Vector2.ZERO falls
# back to _dir (mouse centred on the player).
var _aim:        Vector2 = Vector2.ZERO
# Combat damage this swing deals to mobs (0 for a non-weapon swing). Set by
# the player's _trigger_swing from the held item's sword_damage().
var _damage:     float  = 0.0
# True when the swing came from a SWORD. Only swords cut grass: every other
# held item still plays the swing animation, but must never clear tufts.
var _is_sword:   bool   = false
# "swing" = item sweep + tip arc + puff burst (a player swing); "puff" =
# grass-break particle only, spawned at the cut site. Set by the spawner.
var _mode:       String = "swing"

func _ready() -> void:
	# Y-sort with the world instead of a fixed "above everything" layer: a
	# swing made while standing behind a tree/block must be occluded by it
	# just like the player is. This effect is a CHILD of the player, so its
	# z_index is relative by default — turn that off and reuse the player's
	# own quantized row. At an equal z a child draws after its parent, so the
	# swing still sits over the player sprite itself.
	z_as_relative = false
	_update_sort_row()
	var lifespan: float = 0.1

	# Left and right are the SAME swing, mirrored on X (never rotated 180°),
	# so a west-facing player sees an identical-but-flipped crescent.
	var v: Vector2 = _aim_vec()
	scale = Vector2(-1.0 if v.x < 0.0 else 1.0, 1.0)

	if _mode == "swing":
		var pivot := _build_item_swing()
		add_child(pivot)
		lifespan = maxf(lifespan, SWING_DURATION)
		# The player owns one reusable particle burst; reuse it here instead of
		# allocating a new GPUParticles2D for every swing.
		var owner := Global.player_node
		if owner != null and owner.has_method("emit_summon_fx"):
			var tip_pos: Vector2 = pivot.to_global(Vector2(ITEM_TIP + ITEM_TIP_GAP, 0.0))
			owner.call("emit_summon_fx", tip_pos)

		# The sword-swing flourish (crescent arc + burst at the blade tip) is
		# SWORD-ONLY. Mining/chopping still sweeps the held tool sprite, but
		# must not fire a blade effect — only an actual sword swing does.
		if _is_sword:
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
var _pivot:          Node2D = null
var _hitbox_shape:   RectangleShape2D = null
var _hitbox_query:   PhysicsShapeQueryParameters2D = null
var _hit_mobs:       Array = []
var _parried_areas:  Array = []
var _cut_grass:      Array = []

func _spawn_hitbox(pivot: Node2D) -> void:
	# Query the physics space directly instead of adding a fresh Area2D +
	# CollisionShape2D + RectangleShape2D per swing. The old per-swing Area2D
	# registration caused a visible frame spike on every attack; a cached shape
	# query keeps the same blade volume with no physics-node churn.
	_pivot = pivot
	_hit_mobs.clear()
	_parried_areas.clear()
	_cut_grass.clear()
	if _hitbox_shape == null:
		_hitbox_shape = RectangleShape2D.new()
		_hitbox_shape.size = Vector2(BLADE_LEN, BLADE_W)
		_hitbox_query = PhysicsShapeQueryParameters2D.new()
		_hitbox_query.shape = _hitbox_shape
		_hitbox_query.collision_mask = 2   # layer 2 = mobs
		_hitbox_query.collide_with_bodies = true
		_hitbox_query.collide_with_areas = true
	_hitbox_active = true

func _poll_hitbox() -> void:
	if not _hitbox_active or _pivot == null or not is_instance_valid(_pivot):
		return
	var space := get_world_2d().direct_space_state
	if space == null or _hitbox_query == null:
		return
	_hitbox_query.transform = _pivot.global_transform \
		* Transform2D(0.0, Vector2(BLADE_BASE + BLADE_LEN * 0.5, 0.0))
	for hit in space.intersect_shape(_hitbox_query, 32):
		var collider: Variant = hit.get("collider")
		if collider is Node and (collider as Node).has_method("take_hit"):
			if not _hit_mobs.has(collider):
				_hit_mobs.append(collider)
				(collider as Node).call("take_hit", _damage, global_position)
		elif collider is Area2D:
			_try_parry(collider as Area2D)

# Runs every frame for the WHOLE swing: mobs caught anywhere along the sweep
# are hit immediately, parryable projectiles are deflected, and any grass tuft
# the blade passes over is cut.
func _process(_delta: float) -> void:
	# The player can walk a sort row during the brief swing - keep the effect
	# on the row it should be occluded at for the whole animation.
	_update_sort_row()
	_poll_hitbox()
	_cut_overlapping_grass()

# Same sort row as whatever this effect rides on:
#   • "swing" (child of the player) → the player's own quantized row, so a
#     tree/block in front of the player occludes the swing too.
#   • "puff" (child of the World, spawned at a grass tile) → the row of its
#     own world position, so it lands at the tuft's level.
func _update_sort_row() -> void:
	var parent_ci: CanvasItem = get_parent() as CanvasItem
	if _mode == "swing" and parent_ci != null:
		z_index = parent_ci.z_index
	else:
		z_index = int(global_position.y / 32.0)

# Deflects a parryable area (anything exposing parry()). Debounced per swing so
# it can only be parried once.
func _try_parry(other: Node) -> void:
	if other == null or not is_instance_valid(other):
		return
	if _parried_areas.has(other) or not other.has_method("parry"):
		return
	_parried_areas.append(other)
	other.call("parry", global_position)

# Cuts every GrassTuft whose ground anchor falls inside the blade rectangle
# (BLADE_BASE..BLADE_BASE+BLADE_LEN along the pivot's +x, |y| <= BLADE_W/2),
# padded a little so grass at the player's feet is caught by a waist-high
# sweep. Uses the hitbox's global transform so it tracks the sweep in any
# direction.
#
# COST: this used to iterate get_tree().get_nodes_in_group("Grass") every frame
# of the swing — an Array of EVERY tuft in the 1024x1024 world plus a transform
# and two range checks per tuft. Measured 7.8 ms/frame at 20k tufts (~109 ms
# per swing), which is the stutter. The world now answers with only the tufts
# inside the blade's world AABB (a few tile-dictionary lookups), and the exact
# blade-local test below is unchanged — same hits, same reach.
func _cut_overlapping_grass() -> void:
	# Grass is sword-only: a normal held item plays the swing but never cuts.
	if not _is_sword:
		return
	if _pivot == null or not is_instance_valid(_pivot):
		return
	var world: Node = Global.world_node
	var xf: Transform2D = _pivot.global_transform
	var inv: Transform2D = xf.affine_inverse()
	# The padded blade box in pivot-local space, then its world-space AABB
	# (four transformed corners, so a rotated/diagonal sweep is covered too).
	var lrect := Rect2(
		Vector2(BLADE_BASE - GRASS_CUT_PAD, -BLADE_W * 0.5 - GRASS_CUT_PAD),
		Vector2(BLADE_LEN + GRASS_CUT_PAD * 2.0, BLADE_W + GRASS_CUT_PAD * 2.0))
	var c0: Vector2 = xf * lrect.position
	var c1: Vector2 = xf * Vector2(lrect.end.x, lrect.position.y)
	var c2: Vector2 = xf * lrect.end
	var c3: Vector2 = xf * Vector2(lrect.position.x, lrect.end.y)
	var lo := Vector2(minf(minf(c0.x, c1.x), minf(c2.x, c3.x)),
		minf(minf(c0.y, c1.y), minf(c2.y, c3.y)))
	var hi := Vector2(maxf(maxf(c0.x, c1.x), maxf(c2.x, c3.x)),
		maxf(maxf(c0.y, c1.y), maxf(c2.y, c3.y)))
	var candidates: Array = []
	if world != null and is_instance_valid(world) \
			and world.has_method("grass_tufts_in_world_rect"):
		candidates = world.call("grass_tufts_in_world_rect", Rect2(lo, hi - lo))
	else:
		# Cave/dungeon worlds have no grass index (and no world-gen grass):
		# they only ever hold a handful of player-placed tufts, so the group
		# walk is cheap there and keeps cave grass cutting working.
		candidates = get_tree().get_nodes_in_group("Grass")
	var blade_box := Rect2(lo, hi - lo)
	for node in candidates:
		if not is_instance_valid(node) or _cut_grass.has(node):
			continue
		var tuft := node as Node2D
		if tuft == null:
			continue
		# Whole-tile hit: the tuft's cuttable area (its tile + visible blades)
		# counts as grass, so any part of it inside the padded blade box cuts.
		var in_tile: bool = false
		if tuft.has_method("grass_rect"):
			in_tile = (tuft.call("grass_rect") as Rect2).intersects(blade_box)
		if not in_tile:
			# Fallback for tufts without a tile rect (legacy/placed variants).
			var local: Vector2 = inv * tuft.global_position
			in_tile = local.x >= BLADE_BASE - GRASS_CUT_PAD \
				and local.x <= BLADE_BASE + BLADE_LEN + GRASS_CUT_PAD \
				and absf(local.y) <= BLADE_W * 0.5 + GRASS_CUT_PAD
		if not in_tile:
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

	# Cheap violet bloom at the item; no per-swing GPU particle system.
	_spawn_summon_magic(item)

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

	sprite.sprite_frames = _effect_frames(tex, frame, count, fps)
	sprite.animation_finished.connect(sprite.stop)
	sprite.play("effect")
	return sprite

# One-shot frame sets are identical for every instance, so they are built ONCE
# per process and shared. Each swing used to build a fresh SpriteFrames plus one
# AtlasTexture per frame (arc + three puffs ≈ 20 resources) and every grass cut
# built another — pure per-attack allocation churn.
static var _frames_cache: Dictionary = {}

func _effect_frames(tex: Texture2D, frame: int, count: int, fps: float) -> SpriteFrames:
	var key: String = "%s|%d|%d|%s" % [tex.resource_path, frame, count, fps]
	var cached: Variant = _frames_cache.get(key)
	if cached != null:
		return cached as SpriteFrames
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
	_frames_cache[key] = anim
	return anim

# The unit direction the swing points: the mouse aim when we have one, else the
# spawner's 8-way facing name.
func _aim_vec() -> Vector2:
	if _aim.length_squared() > 0.0001:
		return _aim.normalized()
	return (DIR_VEC.get(_dir, Vector2(1, 0)) as Vector2).normalized()

func _base_rotation_rad() -> float:
	# Only the VERTICAL component rotates: atan2(y, |x|) is 0 for east/west
	# (the node's X mirror handles left/right), ±45° for diagonals and ±90°
	# for north/south — and any angle in between for a mouse aim.
	var v: Vector2 = _aim_vec()
	return atan2(v.y, absf(v.x))

# Arm origin in the un-mirrored frame (+x = right). A west facing returns the
# east origin — the node's X mirror flips it into place, so left/right stay
# the same swing mirrored. Diagonal/analog aims reuse the nearest cardinal.
func _arm_origin() -> Vector2:
	var v: Vector2 = _aim_vec()
	if absf(v.x) >= absf(v.y):
		return ARM_ORIGINS["east"]
	if v.y > 0.0:
		return ARM_ORIGINS["south"]
	return ARM_ORIGINS["north"]

# ── Magical summon flash ──────────────────────────────────────────
# A cheap violet bloom at the held item, so it reads as being conjured rather
# than carried without allocating a particle system for every swing.
func _spawn_summon_magic(item: Sprite2D) -> void:
	if item == null:
		return
	# Keep the cheap bloom flash. The 34-particle GPU system used to be
	# recreated for every swing, causing a large per-attack hitch; the item and
	# arc already carry the motion.
	_spawn_summon_flash(item)

# A bright violet flash that blooms out of the item at the start of the swing,
# so the magic reads at a glance — the motes alone were too subtle.
func _spawn_summon_flash(item: Sprite2D) -> void:
	var flash := Sprite2D.new()
	flash.texture = Global.get_smooth_light_texture(64)
	flash.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	flash.modulate = Color(1.0, 0.85, 1.0, 0.95)
	flash.scale = Vector2(0.5, 0.5)
	flash.z_index = 1
	item.add_child(flash)
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(flash, "scale", Vector2(2.4, 2.4), 0.24) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(flash, "modulate:a", 0.0, 0.24)
	tw.chain().tween_callback(flash.queue_free)
