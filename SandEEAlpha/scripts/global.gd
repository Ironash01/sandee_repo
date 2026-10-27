extends Node

# ── Shadow sprites ────────────────────────────────────────────────
# Flat blob-shadow builder shared by every entity that draws one
# (player, mobs, trees, placed blocks) instead of duplicating the same
# Sprite2D setup per script.
func make_shadow_sprite(texture: Texture2D, offset: Vector2, scale_v: Vector2, alpha: float) -> Sprite2D:
	var shadow := Sprite2D.new()
	shadow.texture  = texture
	shadow.position = offset
	shadow.scale    = scale_v
	shadow.modulate = Color(0.0, 0.0, 0.0, alpha)
	shadow.z_index  = -1
	return shadow

# ?? Break progress ring ?????????????????????????????????????????????????????
# One shared visual for anything breakable. It is deliberately drawn as a small
# ring of hard pixels rather than a smooth arc/line, so it matches the game's
# chunky pixel art. The ring is shown above the target and mirrored next to the
# hotbar while something is being broken.
const BREAK_RING_RADIUS: float = 13.0
const BREAK_RING_PIXEL: float  = 2.4
const BREAK_RING_SEGMENTS: int = 24
const BREAK_RING_BG:     Color = Color(0.04, 0.05, 0.08, 0.92)
const BREAK_RING_EMPTY:  Color = Color(0.24, 0.30, 0.36, 0.95)
const BREAK_RING_FILL:   Color = Color(0.48, 0.95, 0.42, 1.00)
const BREAK_RING_CORE:   Color = Color(0.10, 0.13, 0.17, 0.95)
const BREAK_HUD_TIMEOUT_MS: int = 1000

var break_hud_progress: float = 0.0
var break_world_pos: Vector2 = Vector2.ZERO
var break_world_y_offset: float = -26.0
var _break_hud_source_id: int = 0
var _break_hud_updated_ms: int = 0

# Must be called from inside the caller's own _draw() ? CanvasItem only allows
# draw_* calls while that specific node is in its drawing pass.
func draw_break_bar(ci: CanvasItem, progress: float, y_offset: float = -26.0) -> void:
	draw_break_ring(ci, Vector2(0.0, y_offset * ui_scale), progress, true)

## Draws the pixel ring at a local centre. `report` feeds the hotbar copy; the
## hotbar's own _draw() passes false so redrawing the copy cannot keep itself
## alive.
func draw_break_ring(ci: CanvasItem, center: Vector2, progress: float,
		report: bool = true) -> void:
	if ci == null:
		return
	var p: float = clampf(progress, 0.0, 1.0)
	if report:
		report_break_progress(p)
	var s: float = maxf(ui_scale, 0.5)
	var radius: float = BREAK_RING_RADIUS * s
	var pixel: float = maxf(2.0, BREAK_RING_PIXEL * s)
	var border: float = pixel + maxf(2.0, 2.0 * s)
	var filled: int = int(ceil(p * float(BREAK_RING_SEGMENTS)))
	var origin: Vector2 = center.round()
	for i in range(BREAK_RING_SEGMENTS):
		var angle: float = -PI * 0.5 + TAU * float(i) / float(BREAK_RING_SEGMENTS)
		var point: Vector2 = (origin + Vector2(cos(angle), sin(angle)) * radius).round()
		ci.draw_rect(Rect2(point - Vector2(border, border) * 0.5,
			Vector2(border, border)), BREAK_RING_BG)
		var inner: Color = BREAK_RING_FILL if i < filled else BREAK_RING_EMPTY
		ci.draw_rect(Rect2(point - Vector2(pixel, pixel) * 0.5,
			Vector2(pixel, pixel)), inner)
	# A dark pixel core keeps the ring readable over bright blocks.
	ci.draw_rect(Rect2(origin - Vector2(pixel, pixel) * 0.75,
		Vector2(pixel, pixel) * 1.5), BREAK_RING_CORE)

func report_break_progress(progress: float, world_pos: Vector2 = Vector2.INF,
		y_offset: float = -26.0, source: Object = null) -> void:
	break_hud_progress = clampf(progress, 0.0, 1.0)
	if source != null:
		_break_hud_source_id = source.get_instance_id()
	if world_pos != Vector2.INF:
		break_world_pos = world_pos
		break_world_y_offset = y_offset
	_break_hud_updated_ms = Time.get_ticks_msec() if break_hud_progress > 0.0 else 0

func clear_break_progress(source: Object = null) -> void:
	if source != null and source.get_instance_id() != _break_hud_source_id:
		return
	break_hud_progress = 0.0
	_break_hud_source_id = 0
	_break_hud_updated_ms = 0

func break_hud_visible() -> bool:
	if break_hud_progress <= 0.0:
		return false
	if Time.get_ticks_msec() - _break_hud_updated_ms > BREAK_HUD_TIMEOUT_MS:
		break_hud_progress = 0.0
		return false
	return true

func break_ring_size() -> float:
	return (BREAK_RING_RADIUS * 2.0 + 8.0) * maxf(ui_scale, 0.5)

const WOBBLE_AMPLITUDE_RAD: float = 0.045   # ~2.6° snap each side
const WOBBLE_SNAPS_PER_SEC:  float = 3.0     # full left→right→left cycles per second
const WOBBLE_FLIP_FRACTION:  float = 0.25    # fraction of each half spent flipping; the rest dwells

func block_wobble_rotation() -> float:
	var u: float = fposmod(Time.get_ticks_msec() / 1000.0 * WOBBLE_SNAPS_PER_SEC, 1.0)
	var target: float = 1.0 if u < 0.5 else -1.0   # side this half dwells on
	var source: float = -target                    # side the flip starts from
	var half: float   = fmod(u, 0.5)               # 0..0.5 into this half
	var p: float      = clampf(half / (0.5 * WOBBLE_FLIP_FRACTION), 0.0, 1.0)
	return lerpf(source, target, ease(p, 2.0)) * WOBBLE_AMPLITUDE_RAD

# ── Keyword emphasis (shared by the knowledge altar + encyclopedia) ────
# A short "pop + colour flash" on a keyword Label when a knowledge entry is
# first learned: the text scales up with a back-ease overshoot while flashing
# bright gold, then settles back to its normal size/colour. The colour is
# tweened through the theme override (NOT modulate) so the base colour is used
# exactly — modulate would multiply, tinting blue text green during the flash.
# Caller must give the label a pivot_offset = its size * 0.5 first (so it
# pops from the centre rather than the top-left corner).
const KEYWORD_FLASH: Color = Color(1.00, 0.92, 0.45, 1.0)

func emphasize_keyword(label: Label, base_color: Color, base_scale: Vector2 = Vector2.ONE) -> void:
	if label == null or not is_instance_valid(label):
		return
	# Pivot at the centre of the current size so the pop scales from the middle.
	label.pivot_offset = label.size * 0.5
	label.scale = base_scale
	var tw := label.create_tween()
	# Step 1 — pop out with an overshoot while flashing bright gold.
	tw.tween_property(label, "scale", base_scale * 1.6, 0.18) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_method(_set_label_color.bind(label), base_color, KEYWORD_FLASH, 0.18)
	# Step 2 — settle back to normal with a springy ease, fading the flash.
	tw.tween_property(label, "scale", base_scale, 0.30) \
		.set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_method(_set_label_color.bind(label), KEYWORD_FLASH, base_color, 0.30)
	tw.tween_callback(func() -> void:
		if is_instance_valid(label):
			label.scale = base_scale
			label.add_theme_color_override("font_color", base_color))

func _set_label_color(c: Color, label: Label) -> void:
	if is_instance_valid(label):
		label.add_theme_color_override("font_color", c)


# ── Pixelated light texture ────────────────────────────────────────────
# Minecraft-style 2D light falloff: a circular pool whose brightness drops in
# stepped bands (like Minecraft light levels) with a faint dither between
# bands — so it reads as a cascade of pixels ringing out from the center
# rather than a smooth radial gradient. Every PointLight2D in the game
# (cave/pixie ore glows, pixie/mob glow, torches, altars) uses this so all
# lighting shares the same look. Cached per size; each caller passes the size
# its texture_scale was configured with (512 cave/pixie, 256 mob/torch,
# 128 altars).
static var _pixel_light_cache: Dictionary = {}

static func get_pixelated_light_texture(size: int = 256) -> ImageTexture:
	if _pixel_light_cache.has(size):
		return _pixel_light_cache[size]
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var half:  float = size * 0.5
	var steps: float = 6.0           # brightness bands (Minecraft light levels)
	for y in range(size):
		for x in range(size):
			var dx: float = x - half
			var dy: float = y - half
			var r: float = sqrt(dx * dx + dy * dy)
			# 1 at center -> 0 at the circle edge (linear falloff across the pool).
			var level: float = clampf(1.0 - r / half, 0.0, 1.0)
			var band:  float = floor(level * steps) / steps
			var frac:  float = level * steps - floor(level * steps)
			var smooth: float = band + frac * 0.35  # soften the band edges
			var h: int = x * 374761393 + y * 668265263
			var dither: float = (float(absi(h) % 1000) / 1000.0) * 0.12
			var a: float = clampf(smooth + dither, 0.0, 1.0)
			img.set_pixel(x, y, Color(1, 1, 1, a))
	var tex := ImageTexture.create_from_image(img)
	_pixel_light_cache[size] = tex
	return tex

# ── Smooth light texture ─────────────────────────────────────────────
# Clean circular radial falloff (hot core -> transparent edge) with NO stepped
# bands or dither. Used where the pixelated cascade reads as a jarring "square
# highlight" — currently the placed torch's glow. The gradient falls off very
# fast near the center (full alpha ends ~15% of the pool) so the bright
# "initial" light stays a tight core (~0.7 tiles) while a long faint tail
# carries the outer reach to the full pool edge. Cached per size.
static var _smooth_light_cache: Dictionary = {}

static func get_smooth_light_texture(size: int = 256) -> GradientTexture2D:
	if _smooth_light_cache.has(size):
		return _smooth_light_cache[size]
	var gradient := Gradient.new()
	gradient.colors  = PackedColorArray([
		Color(1, 1, 1, 1),
		Color(1, 1, 1, 0.65),
		Color(1, 1, 1, 0.0),
	])
	gradient.offsets = PackedFloat32Array([0.0, 0.15, 1.0])
	var tex := GradientTexture2D.new()
	tex.gradient  = gradient
	tex.fill      = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to   = Vector2(0.5, 0.0)
	tex.width     = size
	tex.height    = size
	_smooth_light_cache[size] = tex
	return tex

# ── Hitbox debug overlay helpers ────────────────────────────────────────
# Moved out of world.gd so cave_world.gd (and any future world-like scene)
# can draw the same hitbox visuals without duplicating this logic — the
# only thing that ever differed between them was WHICH nodes to walk, not
# HOW to draw a shape once found. `overlay` is the CanvasItem whose own
# _draw()/draw signal callback is currently active — same "must be called
# from inside the caller's own drawing pass" rule as draw_break_bar above,
# it just also works transitively through these calls since Godot's rule
# is about which CanvasItem issues the draw_* call, not which script does.
#
# Recursively finds every CollisionShape2D whose immediate parent is a
# StaticBody2D or CharacterBody2D (the solid hitbox) — skips shapes parented
# by Area2D (interact/click trigger ranges, not physical collision), and
# doesn't care how deeply the body is nested (e.g. ObjectItem's collider
# sits under Sprite2D/StaticBody2D, LuaNPC has two separate bodies).
func draw_body_hitboxes(overlay: CanvasItem, root: Node, color: Color) -> void:
	for child in root.get_children():
		if child is CollisionShape2D and (child as CollisionShape2D).shape != null \
				and (child.get_parent() is StaticBody2D or child.get_parent() is CharacterBody2D):
			draw_shape_outline(overlay, child as CollisionShape2D, color)
		draw_body_hitboxes(overlay, child, color)

# Assumes axis-aligned shapes (none of the game's mob/block colliders are
# rotated today) — draws an outline in the overlay's local space.
func draw_shape_outline(overlay: CanvasItem, col: CollisionShape2D, color: Color) -> void:
	var shape: Shape2D = col.shape
	var center: Vector2 = overlay.to_local(col.global_position)
	if shape is RectangleShape2D:
		var size: Vector2 = (shape as RectangleShape2D).size
		overlay.draw_rect(Rect2(center - size * 0.5, size), color, false, 2.0)
	elif shape is CircleShape2D:
		var r: float = (shape as CircleShape2D).radius
		overlay.draw_arc(center, r, 0.0, TAU, 24, color, 2.0)
	elif shape is CapsuleShape2D:
		var cap: CapsuleShape2D = shape as CapsuleShape2D
		var r: float = cap.radius
		var half_h: float = cap.height * 0.5 - r
		var top:    Vector2 = center + Vector2(0.0, -half_h)
		var bottom: Vector2 = center + Vector2(0.0,  half_h)
		overlay.draw_arc(top,    r, PI, TAU, 16, color, 2.0)
		overlay.draw_arc(bottom, r, 0.0, PI, 16, color, 2.0)
		overlay.draw_line(top + Vector2(-r, 0.0), bottom + Vector2(-r, 0.0), color, 2.0)
		overlay.draw_line(top + Vector2( r, 0.0), bottom + Vector2( r, 0.0), color, 2.0)

# ── Inventory constants ───────────────────────────────────────────
const MAX_STACK:      int = 32
const HOTBAR_SIZE:    int = 9
const INVENTORY_SIZE: int = 20

# Shared item-icon slot size (unscaled) — used by every UI that shows an
# ItemData icon (inventory grid, hand-craft tab, crafting station, trash
# slot) so icons read as the same size across all of them.
const ITEM_SLOT_SIZE: float = 64.0

# ── Storage — each slot is {"quantity": int, "data": ItemData} ────
var Hotbar:    Array = []
var Inventory: Array = []

var hotbar_selected: int = 0

signal Hotbar_updated
signal Inventory_updated
signal hotbar_selection_changed(index: int)

# ── Player stats ──────────────────────────────────────────────────
var health:     float = 100.0
var max_health: float = 100.0
var stamina:    float = 50.0
var max_stamina: float = 50.0

# Knockback strength per point of damage taken (px/s per damage point).
const KNOCKBACK_PER_DAMAGE: float = 22.0

# Central damage entry point for every mob/projectile — reduces health, emits
# the HUD signal, grants 0.3s invincibility frames, and knocks the player back
# OPPOSITE the direction they're facing (falling back to away-from-attacker).
# All mobs should go through this (NOT write Global.health directly) so
# invincibility + knockback stay consistent.
func damage_player(amount: float, from_position: Vector2, attack_dir: Vector2 = Vector2.ZERO,
		knockback_scale: float = 1.0) -> void:
	if amount <= 0.0:
		return
	# Dead (pre-respawn): swallow hits so nothing re-triggers death handling or
	# knocks the frozen player around while the respawn timer runs.
	if player_is_dead:
		return
	# Safe dungeon altar room: the player can't be hurt while reading or taking
	# a quiz, so swallow the hit entirely. Union-based (overlapping zones).
	if is_player_in_safe_zone():
		return
	var p: Node2D = player_node as Node2D
	# Invincibility frames block HP loss (and don't re-grant), but the enemy's
	# hit still LANDS — knockback keeps applying so enemies keep hitting even
	# while the player is invincible.
	var invincible: bool = p != null and p.has_method("is_invincible") and p.call("is_invincible")
	if not invincible:
		health = maxf(0.0, health - amount)
		health_changed.emit(health, max_health)
		CrashLogger.event("PLAYER", "damage=%.1f health=%.1f/%.1f attacker=(%.1f, %.1f)" % [
			amount, health, max_health, from_position.x, from_position.y])
		if health <= 0.0:
			_handle_player_death()
			return
		if p != null and p.has_method("become_invincible"):
			p.call("become_invincible")
	if p == null:
		return
	# The attacker's hit reads as a magic swing (see magic_swing.gd) — spawned
	# at the attacker and aimed at the player. Covers mob contact hits and
	# projectiles, since both route through here.
	if world_node != null and is_instance_valid(world_node):
		MagicSwing.spawn(world_node, from_position, p.global_position - from_position, 0.9, 3)
	var strength: float = amount * KNOCKBACK_PER_DAMAGE * maxf(0.0, knockback_scale)
	if p.has_method("apply_knockback"):
		# Knock the player in the ATTACKER's facing direction (attack_dir) —
		# an enemy striking from the left knocks the player right, like other
		# 2D games. Falls back to straight away from the attacker when the
		# attacker didn't supply a facing.
		var dir: Vector2 = attack_dir if attack_dir.length_squared() > 0.001 \
			else (p.global_position - from_position)
		if dir.length_squared() > 0.001:
			p.call("apply_knockback", dir.normalized(), strength)

# Central heal entry point for food / consumables (the mirror of damage_player).
# Restores up to `amount` HP, NEVER exceeding max_health, and emits the HUD
# signal only when something actually healed. Returns the amount restored
# (0.0 = nothing to heal / dead).
func heal_player(amount: float) -> float:
	if amount <= 0.0 or player_is_dead:
		return 0.0
	var missing: float = max_health - health
	if missing <= 0.0:
		return 0.0
	var restored: float = minf(amount, missing)
	health += restored
	health_changed.emit(health, max_health)
	return restored

# Emitted when the player's health hits zero (the game scene uses this to dim
# the screen). _handle_player_death immediately respawns the player.
signal player_died(death_position: Vector2)

# Emitted after the player (re)spawns at a spawn point. Mobs near the spawn
# disperse for a few seconds so the player isn't instantly swarmed before they
# can react (see the AI scripts' _on_player_spawned). Fires for the world spawn
# / death respawn, and can be emitted by any future item-set spawn point.
signal player_spawned(spawn_position: Vector2)

# Player death: notify on the chat bar, teleport back to the world spawn point,
# and restore full health. Runs synchronously inside damage_player so death is
# only handled once per fatal hit.
var _death_in_progress: bool = false
## True from the moment the player dies until respawn completes. Mobs check
## this (see the AI scripts) so they stop moving toward — and can't damage —
## the frozen player's death position during the death window.
var player_is_dead: bool = false
const DEATH_RESPAWN_TIME: float = 5.0

# Player-set respawn point (a placed Bonfire). When has_spawn_point is true the
# player respawns HERE instead of the world spawn. Session-scoped — re-derived
# from the live Bonfire(s) on load (see scripts/bonfire.gd).
var spawn_point: Vector2 = Vector2.ZERO
var has_spawn_point: bool = false

func set_spawn_point(pos: Vector2) -> void:
	spawn_point = pos
	has_spawn_point = true

func clear_spawn_point() -> void:
	spawn_point = Vector2.ZERO
	has_spawn_point = false

func _handle_player_death() -> void:
	if _death_in_progress:
		return
	_death_in_progress = true
	player_is_dead = true
	# Leave build mode so the ghost/grid doesn't linger over a dead player (and
	# so a stray click can't place a block during the respawn window).
	if block_mode:
		block_mode = false
		block_mode_changed.emit(false)
	notify("[color=#ff7777]You died! Respawning in %d seconds...[/color]" % int(DEATH_RESPAWN_TIME))
	var p: Node2D = player_node as Node2D
	var death_pos: Vector2 = p.global_position if p != null else Vector2.ZERO
	CrashLogger.event("PLAYER", "died at=(%.1f, %.1f)" % [death_pos.x, death_pos.y])
	player_died.emit(death_pos)
	if p != null:
		# Freeze + hide the player while dead — the sprite disappears until the
		# respawn timer finishes.
		p.process_mode = Node.PROCESS_MODE_DISABLED
		var sprite: Node = p.get_node_or_null("PlayerSprite")
		if sprite != null:
			sprite.visible = false
	await get_tree().create_timer(DEATH_RESPAWN_TIME).timeout
	if p == null or not is_instance_valid(p):
		_death_in_progress = false
		player_is_dead = false
		return
	# Prefer the Game scene: it exits any active cave/pixie cave/dungeon first
	# so the player ALWAYS respawns at the OVERWORLD world spawn — not inside
	# the cave they died in.
	var spawn: Vector2 = _get_respawn_position()
	p.global_position = spawn
	p.process_mode = Node.PROCESS_MODE_ALWAYS
	var sprite: Node = p.get_node_or_null("PlayerSprite")
	if sprite != null:
		sprite.visible = true
	# Clear any knockback and grant brief i-frames so they can't instantly
	# re-die on whatever might be near the spawn.
	if p.has_method("apply_knockback"):
		p.call("apply_knockback", Vector2.ZERO, 0.0)
	if p.has_method("become_invincible"):
		p.call("become_invincible")
	# Clear nearby mobs out of the spawn area for a few seconds so the player
	# gets a chance to react after respawning.
	player_spawned.emit(spawn)
	health = max_health
	health_changed.emit(health, max_health)
	CrashLogger.event("PLAYER", "respawned at=(%.1f, %.1f)" % [spawn.x, spawn.y])
	_death_in_progress = false
	player_is_dead = false

func _get_respawn_position() -> Vector2:
	# Call the Game scene FIRST: get_world_spawn_position() also exits any
	# active cave/pixie cave/dungeon, so the player always respawns in the
	# OVERWORLD. (Returning early on a bonfire would leave the player stranded
	# inside a structure at overworld coordinates.)
	var world_spawn: Vector2 = Vector2.ZERO
	var have_world := false
	if game_node != null and game_node.has_method("get_world_spawn_position"):
		world_spawn = game_node.call("get_world_spawn_position") as Vector2
		have_world = true
	# A placed Bonfire overrides the world spawn (its coords are overworld-only —
	# see bonfire.gd, which refuses to register inside caves/dungeons).
	if has_spawn_point:
		return spawn_point
	if have_world:
		return world_spawn
	var world: Node = world_node
	if world != null:
		if world.has_method("_world_spawn_pos"):
			return world.call("_world_spawn_pos") as Vector2
		elif world.has_method("get_player_spawn_position"):
			return world.call("get_player_spawn_position") as Vector2
	return Vector2.ZERO

signal health_changed(value: float, max_value: float)
signal stamina_changed(value: float, max_value: float)

# ── Settings ──────────────────────────────────────────────────────
var master_volume:      float = 1.0
var music_volume:       float = 1.0
var sfx_volume:         float = 1.0
var camera_zoom:        float = 1.9
var pause_on_inventory: bool  = true
# Quest tracker: draw an opaque panel background instead of floating text.
var quest_opaque_bg:    bool  = true
signal quest_bg_changed(opaque: bool)
var pause_menu_open:    bool  = false
# ── Unified UI stack ──────────────────────────────────────────────
# All game interfaces call open_ui() / close_ui() instead of
# managing their own boolean flags and pause state.
var _ui_open_count: int = 0
var player_near_station: bool  = false
var block_mode:          bool  = false   # Ctrl toggles (gameplay build mode) - shared across all scripts; /blockmode command also works
var is_in_dungeon:       bool  = false   # true while inside a dungeon - blocks build mode toggle
# ── Responsive UI metrics ───────────────────────────────────────────
# ui_scale is the ONE multiplier every interface uses. It is derived from the
# live usable viewport (never a per-save preference) and refreshed on resize /
# orientation / safe-area changes. Base sizes stay in each UI script; this
# scalar translates them to the current screen size.
const UI_REFERENCE_SHORT_EDGE: float = 1080.0
const UI_MIN_SCALE: float = 1.25
const UI_MAX_SCALE: float = 1.65
const UI_MOBILE_MIN_SCALE: float = 1.35
const UI_SCALE_STEP: float = 0.05
const UI_FALLBACK_FONT_BASE: int = 16
## Every explicit UI font size goes through ui_font_size(), which applies this
## readability factor on top of the live ui_scale. The old fixed 9-13px bases
## looked undersized next to panels/buttons already scaled 1.25-1.65x.
const UI_FONT_SCALE: float = 1.20
const UI_TYPE_CAPTION: int = 12
const UI_TYPE_LABEL: int = 14
const UI_TYPE_BODY: int = 15
const UI_TYPE_HEADING: int = 20
const UI_TYPE_TITLE: int = 26
var ui_scale:            float = 1.5
var ui_viewport_size:    Vector2 = Vector2.ZERO
# left, top, right, bottom in viewport/logical coordinates. Zero on desktop.
var ui_safe_insets:      Vector4 = Vector4.ZERO
var ui_pause_strip:      float = 0.0
## Bottom edge (viewport units) of the top-right pause button. The mission
## tracker uses this so it always starts BELOW the button instead of guessing a
## fixed offset that overlaps once the responsive UI scale grows the button.
var ui_pause_bottom:     float = 0.0
var _ui_last_viewport:   Vector2 = Vector2.ZERO
var _ui_last_insets:     Vector4 = Vector4(-1, -1, -1, -1)
var _ui_scale_timer:     Timer = null
var _ui_safe_timer:      Timer = null
## Test/tooling seam: a non-negative value overrides the platform keyboard
## height (already in viewport units). -1 uses DisplayServer.
var keyboard_height_override: float = -1.0

# ── Mobile / touch state ──────────────────────────────────────────
# Written by scripts/mobile_ui.gd (Android only). player.gd blends mobile_move
# with the keyboard vector and reads is_shift_held() instead of the raw key, so
# the touch HUD drives the SAME controller, speeds and collision rules. On
# desktop these stay at their defaults and nothing changes.
var mobile_move:  Vector2 = Vector2.ZERO
## True while tap-to-control is holding the left action for continuous mining.
var pnc_hold_active: bool = false
var mobile_shift: bool    = false
var _touch_mouse_active: bool    = false
var _touch_mouse_pos:    Vector2 = Vector2.ZERO

# Shift equivalent for sprint + shift-click actions.
func is_shift_held() -> bool:
	return mobile_shift or Input.is_key_pressed(KEY_SHIFT)

# Single build-mode toggle (Ctrl key, mobile BUILD button, /blockmode command).
func toggle_build_mode() -> void:
	if is_in_dungeon:
		notify("[color=#ff7777]Build mode is disabled inside dungeons.[/color]")
		CrashLogger.event("BUILD", "toggle refused (in dungeon)")
		return
	block_mode = not block_mode
	CrashLogger.event("BUILD", "mode=%s" % ("on" if block_mode else "off"))
	block_mode_changed.emit(block_mode)

# World-space "cursor" used by all mouse-position reads. Desktop returns the
# real mouse; touch devices return the last tap mapped through the canvas
# transform (see mobile_ui.gd), because Android has no cursor.
func set_touch_mouse(world_pos: Vector2) -> void:
	_touch_mouse_active = true
	_touch_mouse_pos    = world_pos

func clear_touch_mouse() -> void:
	_touch_mouse_active = false

# Snapshot/restore around a synthetic click: the player temporarily points the
# shared cursor at a click-to-move destination, then restores whatever the
# platform had (real mouse on desktop, last tap on Android).
func mouse_override_active() -> bool:
	return _touch_mouse_active

func mouse_override_pos() -> Vector2:
	return _touch_mouse_pos

func restore_mouse_override(active: bool, pos: Vector2) -> void:
	_touch_mouse_active = active
	_touch_mouse_pos    = pos

func mouse_world(node: Node2D) -> Vector2:
	if _touch_mouse_active:
		return _touch_mouse_pos
	if node != null:
		return node.get_global_mouse_position()
	var p: Node2D = player_node as Node2D
	return p.global_position if p != null else Vector2.ZERO

## Pure responsive scale calculation so tests and tooling can verify it without
## a live window. Short edge (not total area) prevents ultrawide screens from
## inflating the UI, while mobile gets a comfortable minimum.
func compute_ui_scale(viewport_size: Vector2, mobile: bool = false) -> float:
	var short_edge: float = minf(maxf(viewport_size.x, 1.0), maxf(viewport_size.y, 1.0))
	var raw: float = 1.5 * pow(short_edge / UI_REFERENCE_SHORT_EDGE, 0.35)
	if mobile:
		raw = maxf(raw, UI_MOBILE_MIN_SCALE)
	raw = clampf(raw, UI_MIN_SCALE, UI_MAX_SCALE)
	return snappedf(raw, UI_SCALE_STEP)

func ui_type_size(role: int) -> int:
	var base: int = UI_TYPE_BODY
	match role:
		UI_TYPE_CAPTION: base = UI_TYPE_CAPTION
		UI_TYPE_LABEL:   base = UI_TYPE_LABEL
		UI_TYPE_HEADING: base = UI_TYPE_HEADING
		UI_TYPE_TITLE:   base = UI_TYPE_TITLE
		_:               base = UI_TYPE_BODY
	return ui_font_size(float(base))

## One font-size funnel for UI text. `base` is the old unscaled size; the
## result tracks the live viewport scale plus a readability factor. World-space
## drawn labels use this too, so they stay in proportion with the panels.
func ui_font_size(base: float) -> int:
	return maxi(11, int(round(base * ui_scale * UI_FONT_SCALE)))

func ui_content_rect() -> Rect2:
	var size: Vector2 = ui_viewport_size
	if size.x <= 0.0 or size.y <= 0.0:
		var vp := get_viewport()
		size = vp.get_visible_rect().size if vp != null else Vector2(1280, 720)
	return Rect2(
		Vector2(ui_safe_insets.x, ui_safe_insets.y),
		Vector2(
			maxf(1.0, size.x - ui_safe_insets.x - ui_safe_insets.z),
			maxf(1.0, size.y - ui_safe_insets.y - ui_safe_insets.w)))

## Constrain a full-rect Control (centres, scroll roots, HUD layers) to the
## live display safe area. This is a no-op on desktop, so the established
## desktop layout is unchanged. Call after set_anchors_preset(FULL_RECT).
func apply_safe_area(control: Control, extra_margin: float = 0.0) -> void:
	if control == null:
		return
	control.offset_left   = ui_safe_insets.x + extra_margin
	control.offset_top    = ui_safe_insets.y + extra_margin
	control.offset_right  = -(ui_safe_insets.z + extra_margin)
	control.offset_bottom = -(ui_safe_insets.w + extra_margin)

## Scaled minimum size for a panel, clamped inside the usable viewport so modal
## dialogs and their Apply/Cancel buttons can never land off-screen.
func ui_fit_min_size(base_size: Vector2, margin: float = 12.0) -> Vector2:
	var content := ui_content_rect().size
	var pad: float = maxf(2.0, margin * ui_scale)
	return Vector2(
		minf(base_size.x * ui_scale, maxf(240.0, content.x - pad * 2.0)),
		minf(base_size.y * ui_scale, maxf(180.0, content.y - pad * 2.0)))

func _compute_safe_insets(viewport_size: Vector2) -> Vector4:
	if not is_mobile() or DisplayServer.get_name() == "headless":
		return Vector4.ZERO
	var safe: Rect2i = DisplayServer.get_display_safe_area()
	if safe.size.x <= 0 or safe.size.y <= 0:
		return Vector4.ZERO
	var vp := get_viewport()
	if vp == null:
		return Vector4.ZERO
	var xf: Transform2D = vp.get_screen_transform()
	var start: Vector2 = xf.affine_inverse() * Vector2(safe.position)
	var end: Vector2 = xf.affine_inverse() * Vector2(safe.position + safe.size)
	if end.x <= start.x or end.y <= start.y:
		return Vector4.ZERO
	if end.x > viewport_size.x + 2.0 or end.y > viewport_size.y + 2.0:
		return Vector4.ZERO
	return Vector4(
		clampf(start.x, 0.0, viewport_size.x),
		clampf(start.y, 0.0, viewport_size.y),
		clampf(viewport_size.x - end.x, 0.0, viewport_size.x),
		clampf(viewport_size.y - end.y, 0.0, viewport_size.y))

func refresh_ui_scale(force_emit: bool = false) -> void:
	var vp := get_viewport()
	if vp == null:
		return
	var size: Vector2 = vp.get_visible_rect().size
	var insets: Vector4 = _compute_safe_insets(size)
	var usable := Vector2(
		maxf(1.0, size.x - insets.x - insets.z),
		maxf(1.0, size.y - insets.y - insets.w))
	var next_scale: float = compute_ui_scale(usable, is_mobile())
	var scale_changed: bool = absf(next_scale - ui_scale) > 0.001
	var layout_changed: bool = size != _ui_last_viewport or insets != _ui_last_insets
	ui_scale = next_scale
	ui_viewport_size = size
	ui_safe_insets = insets
	ThemeDB.fallback_font_size = ui_font_size(float(UI_FALLBACK_FONT_BASE))
	_ui_last_viewport = size
	_ui_last_insets = insets
	if scale_changed or layout_changed or force_emit:
		ui_scale_changed.emit(ui_scale)

func _on_viewport_size_changed() -> void:
	if _ui_scale_timer != null:
		_ui_scale_timer.start(0.10)
	else:
		refresh_ui_scale()

func _on_ui_scale_timer_timeout() -> void:
	refresh_ui_scale()

func _deferred_ui_scale_refresh() -> void:
	refresh_ui_scale()

func _setup_ui_scaling() -> void:
	var vp := get_viewport()
	if vp != null and not vp.size_changed.is_connected(_on_viewport_size_changed):
		vp.size_changed.connect(_on_viewport_size_changed)
	if _ui_scale_timer == null:
		_ui_scale_timer = Timer.new()
		_ui_scale_timer.one_shot = true
		_ui_scale_timer.process_mode = Node.PROCESS_MODE_ALWAYS
		_ui_scale_timer.timeout.connect(_on_ui_scale_timer_timeout)
		add_child(_ui_scale_timer)
	# Edge-to-edge Android can show/hide system bars or rotate 180 degrees without
	# a viewport-size change. Poll the safe area cheaply so panels never keep a
	# stale notch offset. refresh_ui_scale only emits when something changed.
	if is_mobile() and _ui_safe_timer == null:
		_ui_safe_timer = Timer.new()
		_ui_safe_timer.wait_time = 0.75
		_ui_safe_timer.one_shot = false
		_ui_safe_timer.process_mode = Node.PROCESS_MODE_ALWAYS
		_ui_safe_timer.timeout.connect(func() -> void: refresh_ui_scale())
		add_child(_ui_safe_timer)
		_ui_safe_timer.start()
	refresh_ui_scale(true)
	call_deferred("_deferred_ui_scale_refresh")

## True when a mouse event (including Android's emulated first-touch mouse)
## lands on any visible Control. Gameplay _input() handlers run before GUI
## consumption, so they must skip these events themselves.
var _ui_hit_event_id: int = 0
var _ui_hit_result: bool = false

# ── UI root cache for hit-testing ────────────────────────────────────
# _control_at_point() used to recurse from the Viewport through EVERY node in
# the tree. In the overworld that is ~40,000 nodes (grass/trees/blocks), so one
# is_point_over_ui() call cost ~35 ms. The desktop cursor director calls it ten
# times a second and the Android touch bridge calls it on every touch event,
# which made the overworld feel permanently choppy while caves/dungeons (far
# fewer nodes) were fine. UI is rooted at CanvasLayers (plus the odd top-level
# Control), so only those roots need to be walked. Roots are registered as they
# enter the tree; world Node2D subtrees are never visited.
var _ui_roots: Array[Node] = []

func _register_ui_root(node: Node) -> void:
	if node == null:
		return
	if node is CanvasLayer:
		if not _ui_roots.has(node):
			_ui_roots.append(node)
		return
	if node is Control:
		var parent := node.get_parent()
		if parent == null or not (parent is Control or parent is CanvasLayer):
			if not _ui_roots.has(node):
				_ui_roots.append(node)

func _collect_ui_roots(node: Node) -> void:
	if node == null:
		return
	if node is CanvasLayer:
		# The layer itself is the traversal root; its Controls are reached by
		# _control_at_point(). A nested CanvasLayer is handled by the generic
		# child recursion in that function, so no separate registration needed.
		if not _ui_roots.has(node):
			_ui_roots.append(node)
		return
	if node is Control:
		_register_ui_root(node)
		# Keep looking for CanvasLayers nested under Controls (rare but legal).
		for child in node.get_children():
			_collect_ui_roots(child)
		return
	for child in node.get_children():
		_collect_ui_roots(child)

func _on_ui_tree_node_added(node: Node) -> void:
	# Called for every world node too, so keep this branch trivial. Only a
	# CanvasLayer or a top-level Control can become a new UI traversal root.
	if node is CanvasLayer or node is Control:
		_register_ui_root(node)

func is_left_action_held() -> bool:
	# A pointer released while an interface is open is delivered to that
	# interface, not to the paused world. Do not let break/hold loops resume on
	# a stale mouse-down bit after the panel closes.
	if any_ui_open() or pause_menu_open:
		return false
	return pnc_hold_active or Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)

## True when a viewport-space point is over any visible Control. Used by the
## mobile touch bridge to distinguish world taps from UI taps before it
## synthesizes mouse events.
func is_point_over_ui(point: Vector2) -> bool:
	if get_viewport() == null:
		return false
	# Iterate backwards so invalid/freed roots are pruned in place. Order does
	# not matter for a boolean hit test: any visible blocking Control is enough.
	for i in range(_ui_roots.size() - 1, -1, -1):
		var root: Node = _ui_roots[i]
		if not is_instance_valid(root):
			_ui_roots.remove_at(i)
			continue
		if _control_at_point(root, point):
			return true
	return false

func is_mouse_event_over_ui(event: InputEvent) -> bool:
	if not (event is InputEventMouseButton):
		return false
	var eid := event.get_instance_id()
	if eid == _ui_hit_event_id:
		return _ui_hit_result
	_ui_hit_event_id = eid
	# Hit-test THIS event's position, not the current OS cursor. On Android the
	# emulated first-touch mouse and our secondary-touch bridge can deliver
	# clicks at a position that is not where get_mouse_position() last pointed;
	# using the shared cursor let a tap on a UI button leak into world mining or
	# attacking. Event.position is already in viewport coordinates.
	_ui_hit_result = is_point_over_ui((event as InputEventMouseButton).position)
	return _ui_hit_result

## World-space point for a mouse event. Unlike mouse_world(), this never uses
## the cached touch cursor: a new tap always targets the pixel the player
## actually touched, even after a previous PNC order moved the cursor.
func mouse_event_world(node: Node2D, event: InputEvent) -> Vector2:
	var vp := get_viewport()
	if vp != null and event is InputEventMouse:
		return vp.get_canvas_transform().affine_inverse() \
			* (event as InputEventMouse).position
	return mouse_world(node)

# Windows/Viewports in this Godot build do not expose gui_find_control(), so
# walk the visible Control tree manually. Children are checked first to respect
# draw/input order; IGNORE controls are skipped but their children are not.
func _control_at_point(node: Node, point: Vector2) -> bool:
	if node == null:
		return false
	if node is CanvasLayer and not (node as CanvasLayer).visible:
		return false
	if node is Control:
		var control := node as Control
		if not control.is_visible_in_tree():
			return false
		for i in range(control.get_child_count() - 1, -1, -1):
			if _control_at_point(control.get_child(i), point):
				return true
		return control.mouse_filter != Control.MOUSE_FILTER_IGNORE \
			and control.get_global_rect().has_point(point)
	for i in range(node.get_child_count() - 1, -1, -1):
		if _control_at_point(node.get_child(i), point):
			return true
	return false

## Convert the Android keyboard height (physical screen pixels) into viewport
## units. Subtracting the raw value from a logical viewport made high-DPI
## phones collapse every keyboard-aware panel and push its text fields
## off-screen. Clamp to the viewport so a bogus platform value can never invert
## a panel's rect.
static func keyboard_height_in_viewport(pixels: float, screen_scale_y: float,
		viewport_height: float) -> float:
	if pixels <= 0.0:
		return 0.0
	var scale_y: float = absf(screen_scale_y)
	if scale_y <= 0.0001:
		return 0.0
	var cap: float = maxf(0.0, viewport_height - 1.0)
	return clampf(pixels / scale_y, 0.0, cap)


# Height the Android software keyboard currently covers, in viewport units.
# 0 on desktop or when it is hidden. Editors shrink their layout by this much
# so the focused field and RUN/STOP stay visible (see mobile_ui.gd /
# lua_editor_ui.gd / online_account_panel.gd).
func mobile_keyboard_height() -> float:
	if keyboard_height_override >= 0.0:
		return keyboard_height_override
	if not is_mobile():
		return 0.0
	var pixels: float = float(DisplayServer.virtual_keyboard_get_height())
	if pixels <= 0.0:
		return 0.0
	var vp := get_viewport()
	if vp == null:
		return 0.0
	var vp_height: float = ui_viewport_size.y
	if vp_height <= 0.0:
		vp_height = vp.get_visible_rect().size.y
	# Stretch transform only (viewport -> window pixels). Using the screen
	# transform here would also fold in the active Camera2D's canvas zoom,
	# which has nothing to do with how much of the window the keyboard covers.
	return keyboard_height_in_viewport(
		pixels, vp.get_stretch_transform().get_scale().y, vp_height)
# The old per-save ui_scale preference is intentionally ignored. UI size is now
# derived centrally in refresh_ui_scale() from the live usable viewport.

# Fog of war for the minimap: tiles the player has been near (Vector2i -> true).
# Session-scoped (the minimap marks a radius around the player as it moves).
var explored_tiles:      Dictionary = {}

# Fog of war for DUNGEON maps, keyed by Vector3i(dungeon_index, grid_x, grid_y).
# Kept separate from explored_tiles so dungeon grid coords can't collide with
# overworld world coords (both start near 0). Session-scoped.
var explored_dungeon_tiles: Dictionary = {}

# Fog of war for the ACTIVE cave map (Vector2i grid cell -> true). Swapped
# per entrance by game_instance._do_enter_cave()/_do_exit_cave(); each cave's
# set is stored inside cave_states so re-entry restores its explored map.
var explored_cave_tiles: Dictionary = {}
# Per-cave persistent state, keyed by the entrance's stable state_key:
# { "cave:<seed>:<x>:<y>": {"tiles": [...], "blocks": [...], "explored": [...]} }
var cave_states: Dictionary = {}

# True while the chat console's text input is focused — gates player movement
# (and other input) so typing WASD into a command doesn't also walk the player.
var chat_open: bool = false

# True while ANY text field (TextEdit / CodeEdit / LineEdit) has keyboard focus.
# Every hotkey handler MUST consult this: input handlers use _input(), which
# runs BEFORE a focused Control's _gui_input() and therefore still receives the
# key — so typing "e" in the crafting station or a digit in the Lua editor
# would otherwise close the panel / change the hotbar. Checked via the viewport
# focus owner, so it needs no per-panel bookkeeping.
func is_text_input_focused() -> bool:
	if chat_open:
		return true
	var vp := get_viewport()
	if vp == null:
		return false
	var owner := vp.gui_get_focus_owner()
	return owner is TextEdit or owner is CodeEdit or owner is LineEdit

# Reference to the overworld's DayNightCycle (set in its _ready) so the chat
# console's /daynight command can toggle it from anywhere. Null while inside a
# cave/dungeon (those have no sky tint).
var day_night_cycle: Node = null

# True while the player stands inside a VALID house (a sealed, doored room).
# The overworld's day/night CanvasModulate dims a touch to sell the "indoors"
# feel. Updated by world.gd each frame from the housing system.
var player_indoors: bool = false

# True while the player stands inside a SAFE dungeon altar room (the knowledge
# or quiz room). Kept as a compatibility mirror of the authoritative union check
# below; damage/AI paths call is_player_in_safe_zone() directly.
var player_in_safe_room: bool = false

## Active dungeon safe zones: instance id -> Rect2 (the zone's room footprint).
## Membership is union-based and position-derived, so overlapping zones never
## cancel each other and a zone disappearing cannot unprotect a player still
## inside another one.
var _safe_zone_rects: Dictionary = {}
const SAFE_ZONE_FEET_OFFSET: float = 17.0

func register_safe_zone(owner: Object, rect: Rect2) -> void:
	if owner == null:
		return
	_safe_zone_rects[owner.get_instance_id()] = rect
	refresh_safe_zone_state()

func unregister_safe_zone(owner: Object) -> void:
	if owner == null:
		return
	_safe_zone_rects.erase(owner.get_instance_id())
	refresh_safe_zone_state()

func clear_safe_zones() -> void:
	_safe_zone_rects.clear()
	player_in_safe_room = false

func refresh_safe_zone_state() -> void:
	player_in_safe_room = is_player_in_safe_zone()

func is_point_in_safe_zone(point: Vector2) -> bool:
	for rect in _safe_zone_rects.values():
		if _rect_contains_inclusive(rect, point):
			return true
	return false

## Protection uses the player's FEET point (the origin is the chest) and
## inclusive edges, so every edge/corner tile of a zone counts.
func is_player_in_safe_zone() -> bool:
	var p: Node2D = player_node as Node2D
	if p == null or not is_instance_valid(p):
		return false
	return is_point_in_safe_zone(p.global_position + Vector2(0.0, SAFE_ZONE_FEET_OFFSET))

func _rect_contains_inclusive(rect: Rect2, point: Vector2) -> bool:
	return point.x >= rect.position.x and point.x <= rect.end.x \
		and point.y >= rect.position.y and point.y <= rect.end.y

## True when the segment a->b touches any active safe-zone rect. Used by fast
## projectiles so a one-frame boundary crossing cannot skip protection.
func segment_intersects_safe_zone(a: Vector2, b: Vector2) -> bool:
	for rect in _safe_zone_rects.values():
		if _segment_intersects_rect(a, b, rect):
			return true
	return false

func _segment_intersects_rect(a: Vector2, b: Vector2, rect: Rect2) -> bool:
	var tmin := 0.0
	var tmax := 1.0
	var d := b - a
	for axis in [0, 1]:
		var start := a.x if axis == 0 else a.y
		var delta := d.x if axis == 0 else d.y
		var lo := rect.position.x if axis == 0 else rect.position.y
		var hi := rect.end.x if axis == 0 else rect.end.y
		if absf(delta) < 0.0001:
			if start < lo or start > hi:
				return false
			continue
		var t1 := (lo - start) / delta
		var t2 := (hi - start) / delta
		if t1 > t2:
			var tmp := t1
			t1 = t2
			t2 = tmp
		tmin = maxf(tmin, t1)
		tmax = minf(tmax, t2)
		if tmin > tmax:
			return false
	return true

func is_hostile_mob(node: Node) -> bool:
	if node == null or not is_instance_valid(node):
		return false
	if node.is_in_group("Hitman") or node.is_in_group("DungeonHostile"):
		return true
	var data: Variant = node.get("COMBAT_DATA")
	if data == null:
		return false
	return int(data.get("behavior")) == 0   # MobCombatData.Behavior.HOSTILE

## Remove a hostile enemy without emitting its normal death signal, loot,
## mission progress or kill rewards. Used by safe-zone protection.
func disintegrate_hostile(node: Node) -> void:
	if not is_hostile_mob(node):
		return
	if node.has_method("safe_zone_disintegrate"):
		node.call("safe_zone_disintegrate")
		return
	if node.has_method("_spawn_death_burst"):
		node.call("_spawn_death_burst")
	node.queue_free()

signal ui_scale_changed(scale: float)
## Emitted whenever an interface/ pause takes over the screen. Touch HUDs and
## gesture bridges listen so a held joystick/world touch cannot leak into the
## resumed game.
signal gameplay_input_cancelled
signal request_close_all_ui
signal chat_logged(message: String)

signal camera_zoom_changed(zoom: float)
signal inventory_toggled(is_open: bool)
# Emitted by full-screen station/editor screens that cover the playfield. The
# game HUD is hidden while these are open so the hotbar/FPS/minimap can never
# overlap their panels.
signal modal_hud_changed(open: bool)
signal block_mode_changed(enabled: bool)
signal item_picked_up(item_name: String, item_type: String)
signal hover_label_changed(text: String)
signal lua_stuck_notice(message: String)

# ── Online mode / cloud status ────────────────────────────────────
# Startup requires an online sign-in; the main menu can then switch to local
# offline play via "Play Offline". The menu's bottom-left indicator reads these
# values, so it can only claim "Cloud Save Active" after the client has
# authenticated and initialized the cloud-save service.
enum CloudStatus { OFFLINE, ACTIVE, SYNCING, SYNCED, PENDING, ERROR }
var online_mode: bool = false
var cloud_status: int = CloudStatus.OFFLINE
var cloud_status_detail: String = ""
signal online_state_changed
signal cloud_status_changed(status: int)
## Emitted after a successful atomic save / load, so automatic cloud sync can
## react to autosaves, quit-to-menu saves and world joins exactly once.
signal game_saved(slot: int)
signal world_loaded(slot: int)

func set_online_mode(on: bool) -> void:
	if online_mode == on:
		return
	online_mode = on
	if not on:
		cloud_status = CloudStatus.OFFLINE
		cloud_status_detail = ""
	online_state_changed.emit()
	cloud_status_changed.emit(cloud_status)

func set_cloud_status(status: int, detail: String = "") -> void:
	cloud_status = status
	cloud_status_detail = detail
	cloud_status_changed.emit(status)

func cloud_status_label() -> String:
	match cloud_status:
		CloudStatus.ACTIVE:
			return "Cloud Save Active"
		CloudStatus.SYNCING:
			return "Syncing"
		CloudStatus.SYNCED:
			return "Synced"
		CloudStatus.PENDING:
			return "Pending"
		CloudStatus.ERROR:
			return "Error"
		_:
			return "Offline"

func cloud_status_color() -> Color:
	match cloud_status:
		CloudStatus.ACTIVE:
			return Color(0.55, 0.95, 0.68, 1.0)
		CloudStatus.SYNCING:
			return Color(0.95, 0.85, 0.50, 1.0)
		CloudStatus.SYNCED:
			return Color(0.55, 0.95, 0.68, 1.0)
		CloudStatus.PENDING:
			return Color(0.98, 0.72, 0.35, 1.0)
		CloudStatus.ERROR:
			return Color(1.00, 0.50, 0.50, 1.0)
		_:
			return Color(0.55, 0.65, 0.85, 1.0)

# ── Day/night + weather ──────────────────────────────────────────
signal day_started
signal night_started
signal snowstorm_changed(active: bool)
var snowstorm_active: bool = false
# Mirrored by day_night_cycle.gd on every crossing — lets code that needs to
# know "is it day right now" (not just react to the transition) query this
# directly instead of tracking the signals itself.
var is_daytime: bool = true
# Live mirror of day_night_cycle.gd's time_of_day (0..1), written every frame
# and persisted in save files — so the time of day survives restarts instead
# of always resetting to noon. Lives on Global (not the node) so it stays
# readable even while DayNightCycle is out of the tree during cave visits.
var time_of_day: float = 0.25

# ── Missions ──────────────────────────────────────────────────────
var missions: Array = []
signal mission_updated
signal mission_completed(mission_id: String)
## Emitted once when a mission/clear is completed, carrying the stable reward id
## the cloud uses (see CloudSync / the mission_rewards table).
signal mission_star_earned(reward_id: String)
## Emitted after the cloud star totals were refreshed, so the local UI can redraw.
signal stars_updated

# ── Knowledge / dungeon-mission registries ────────────────────────────
# Data-driven dungeon content lives in two resource folders and is loaded
# once at startup:
#   res://resources/entries/        KnowledgeEntry (encyclopedia + keyword)
#   res://resources/dungeon_missions/  DungeonMissionData (glues entry→questions;
#                               the questions are embedded inline, so no quiz files)
# A dungeon mission references its entry by FILE NAME (e.g. "entry_1_lua.tres")
# so the mission author never needs to build node graphs in the editor — just
# drop a .tres in the right folder and reference it.
const KNOWLEDGE_DIR: String       = "res://resources/entries/"
const DUNGEON_MISSION_DIR: String = "res://resources/dungeon_missions/"

var knowledge_entries: Dictionary = {}  # entry base name -> KnowledgeEntry
var dungeon_missions:  Dictionary = {}  # dungeon_index -> DungeonMissionData

# What the player has actually learned. learned_entries keyed by entry base
# name (drives the encyclopedia view); learned_keywords keyed by the entry's
# keyword string (drives unlocking the concept in the Lua editor later).
var learned_entries:  Dictionary = {}  # entry base name -> true
var learned_keywords: Dictionary = {}  # keyword -> entry base name

# Entries learned but NOT yet viewed in the Encyclopedia — drives the
# "emphasis" animation (pop + flash) the first time each new entry appears
# there. Keyed by entry base name; cleared per-entry when it's been shown.
var unseen_entries:  Dictionary = {}  # entry base name -> true

signal knowledge_updated

# ── Bestiary ─────────────────────────────────────────────────────────
# Per-world observation state. The catalog itself is static data loaded from
# MobCombatData resources (BestiaryCatalog); these dictionaries only remember
# which entries THIS world has seen and studied. A sighting reveals the name;
# the first kill unlocks notes, max health and the full drop table.
var bestiary_seen: Dictionary = {}    # bestiary_id -> true
var bestiary_killed: Dictionary = {}  # bestiary_id -> true
var _bestiary_scan_accum: float = 0.0
const BESTIARY_SCAN_INTERVAL: float = 0.30
signal bestiary_updated

# ── Dungeon runtime state ─────────────────────────────────────────────
# Every dungeon is worth up to THREE blue stars: the mission star plus a
# two-star clear. Perfect clears (no hints) earn all three; one hint earns two;
# two or more hints earn one. `dungeon_stars` stores the final 1..3 award per
# dungeon (legacy cleared dungeons default to 3, matching the new maximum).
# dungeon_seeds: rolled ONCE, the first time the player accepts that
# dungeon's mission, then persisted — re-entering regenerates the exact
# same layout (DungeonGenerator is deterministic from its seed).
var cleared_dungeons: Dictionary = {}  # dungeon_index -> true
var dungeon_stars:    Dictionary = {}  # dungeon_index -> 1..3 blue stars
var dungeon_seeds:    Dictionary = {}  # dungeon_index -> int
# Rare dungeon-chest state keyed by "<dungeon_index>:<x>,<y>". Values contain
# serialized slot contents and/or removed=true so re-entering a dungeon cannot
# regenerate already-taken rewards.
var dungeon_chest_states: Dictionary = {}
signal dungeon_cleared(dungeon_index: int)
# Emitted after the game has actually swapped the overworld for a generated
# DungeonWorld. The onboarding director uses this to begin the in-dungeon lesson
# without polling scene internals.
signal dungeon_entered(dungeon_index: int)

func load_knowledge_data() -> void:
	knowledge_entries.clear()
	dungeon_missions.clear()
	_load_resource_dir(KNOWLEDGE_DIR, knowledge_entries)
	var mission_lookup: Dictionary = {}
	_load_resource_dir(DUNGEON_MISSION_DIR, mission_lookup)
	for key in mission_lookup:
		var m: DungeonMissionData = mission_lookup[key] as DungeonMissionData
		if m != null:
			dungeon_missions[m.dungeon_index] = m

func _load_resource_dir(dir_path: String, into: Dictionary) -> void:
	# ResourceLoader.list_directory (NOT DirAccess) so this also works in an
	# EXPORTED build: text resources are converted to binary on export and the
	# original .tres is replaced by a .tres.remap stub, which DirAccess lists
	# instead of the .tres name — so the scan silently found nothing and the
	# encyclopedia/dungeon lists came up empty. list_directory reports the
	# original editor-side names in both cases (subdirs get a trailing "/").
	for fname in ResourceLoader.list_directory(dir_path):
		if fname.ends_with("/"):
			# Recurse into subdirectories (e.g. python/, lua/)
			_load_resource_dir(dir_path + fname, into)
		elif fname.ends_with(".tres"):
			var res: Resource = load(dir_path + fname)
			if res != null:
				into[fname.get_basename()] = res
			else:
				push_warning("Global: failed to load %s%s" % [dir_path, fname])

func get_knowledge_entry_file(fname: String) -> KnowledgeEntry:
	return knowledge_entries.get(fname.get_basename()) as KnowledgeEntry

func get_dungeon_mission_for_index(idx: int) -> DungeonMissionData:
	return dungeon_missions.get(idx) as DungeonMissionData

## Central, explicit dungeon difficulty map. It is metadata only: combat,
## generation, loot and rewards remain untouched. Assignments follow the
## player's progression order and the encounter density of each track.
const DUNGEON_DIFFICULTIES: Dictionary = {
	1: "Easy", 2: "Easy", 3: "Easy", 4: "Easy",
	5: "Medium", 6: "Medium", 7: "Medium",
	8: "Hard", 9: "Hard", 10: "Hard", 11: "Medium",
	26: "Medium", 27: "Medium", 28: "Medium", 29: "Medium",
	30: "Medium", 31: "Medium",
	32: "Hard", 33: "Hard", 34: "Hard", 35: "Hard",
	36: "Hard", 37: "Hard", 38: "Hard", 39: "Hard",
	40: "Hard",
}

func dungeon_difficulty(idx: int) -> String:
	return str(DUNGEON_DIFFICULTIES.get(idx, "Medium"))

func dungeon_display_name(idx: int) -> String:
	var dm := get_dungeon_mission_for_index(idx)
	var title := dm.mission_name if dm != null else "Dungeon %d" % idx
	return "%s — %s" % [title, dungeon_difficulty(idx)]

func get_dungeon_mission_by_file(fname: String) -> DungeonMissionData:
	for idx in dungeon_missions:
		var m: DungeonMissionData = dungeon_missions[idx] as DungeonMissionData
		if m != null and m.id() == fname.get_basename():
			return m
	return null

# Dungeon seeds are rolled the first time a dungeon's overworld entrance is
# placed (world.gd calls this from _spawn_dungeon_entrance); kept here so the
# layout survives re-entry and save/load.
func get_or_create_dungeon_seed(dungeon_index: int) -> int:
	if dungeon_seeds.has(dungeon_index):
		return int(dungeon_seeds[dungeon_index])
	var seed := randi()
	dungeon_seeds[dungeon_index] = seed
	return seed

# ── Rare dungeon chest persistence ────────────────────────────────────
# The chest layout is deterministic from the dungeon seed; only mutable state
# (remaining slot contents / removed flag) is stored here. This survives death,
# exit/re-entry, and save/load without duplicating rewards.
func _dungeon_chest_key(dungeon_index: int, cell: Vector2i) -> String:
	return "%d:%d,%d" % [dungeon_index, cell.x, cell.y]

func get_dungeon_chest_state(dungeon_index: int, cell: Vector2i) -> Dictionary:
	var value: Variant = dungeon_chest_states.get(
		_dungeon_chest_key(dungeon_index, cell), {})
	if value is Dictionary:
		return (value as Dictionary).duplicate(true)
	return {}

func set_dungeon_chest_state(dungeon_index: int, cell: Vector2i,
		state: Dictionary) -> void:
	var key := _dungeon_chest_key(dungeon_index, cell)
	if state.is_empty():
		dungeon_chest_states.erase(key)
	else:
		dungeon_chest_states[key] = state.duplicate(true)

# Records a dungeon clear and its final 1..3 blue-star award. The mission star
# is emitted separately by complete_mission(); this adds the clear star
# (stars >= 2) and the perfect-clear bonus (stars >= 3). Two or more hints
# therefore leave only the mission star. Idempotent so re-clears never
# double-award, and it drives the mission UI popup via dungeon_cleared.
func record_dungeon_clear(dungeon_index: int, stars: int = 3) -> void:
	if cleared_dungeons.has(dungeon_index):
		return
	var earned: int = clampi(stars, 1, 3)
	cleared_dungeons[dungeon_index] = true
	dungeon_stars[dungeon_index] = earned
	dungeon_cleared.emit(dungeon_index)
	if earned >= 2:
		mission_star_earned.emit("dungeon_clear:%d" % dungeon_index)
	if earned >= 3:
		mission_star_earned.emit("dungeon_clear_bonus:%d" % dungeon_index)
	# The general "Clear a dungeon" quest is separate from the dungeon mission
	# star; complete_mission is idempotent, so re-clears cannot double-award it.
	complete_mission("clear_dungeon")
	mission_updated.emit()  # star totals change — refresh the mission UI

func is_dungeon_cleared(dungeon_index: int) -> bool:
	return cleared_dungeons.has(dungeon_index)

## Final blue-star award for a dungeon (0 = not completed, 1..3 = earned).
## Legacy cleared saves have no stored value and default to the new maximum so
## older perfect clears are not punished retroactively.
func dungeon_stars_for(dungeon_index: int) -> int:
	if dungeon_stars.has(dungeon_index):
		return clampi(int(dungeon_stars[dungeon_index]), 0, 3)
	if cleared_dungeons.has(dungeon_index):
		return 3
	var m := _find_mission("dungeon_%d" % dungeon_index)
	if not m.is_empty() and bool(m.get("completed", false)):
		return 1
	return 0

# Every dungeon can now award up to three blue stars. Kept for callers that
# only need the number of dungeon entries.
func clearable_dungeon_count() -> int:
	return dungeon_missions.size()

# Reconstruct keyword → entry mapping from the learned entries each load,
# so it always matches whatever entry resources currently exist.
func _rebuild_learned_keywords() -> void:
	learned_keywords.clear()
	for id in learned_entries:
		var e: KnowledgeEntry = knowledge_entries.get(id) as KnowledgeEntry
		if e != null and not e.keyword.is_empty():
			learned_keywords[e.keyword] = id

# Called by the knowledge altar. Records the concept in the encyclopedia and
# unlocks its keyword (the Lua-editor enforcement itself is a later polish).
# Returns true only when this call actually LEARNED something new — the altar
# uses that to decide whether to play the first-time emphasis animation.
func learn_entry(entry: KnowledgeEntry) -> bool:
	if entry == null:
		return false
	if learned_entries.has(entry.id()):
		return false
	learned_entries[entry.id()] = true
	unseen_entries[entry.id()] = true
	if not entry.keyword.is_empty():
		learned_keywords[entry.keyword] = entry.id()
	knowledge_updated.emit()
	# The "Learn a knowledge entry" quest completes on the first new entry.
	complete_mission("learn_entry")
	return true

# True the FIRST time an entry is offered in the encyclopedia — the view
# plays the emphasis animation for it, then calls mark_entry_seen().
func is_entry_unseen(entry: KnowledgeEntry) -> bool:
	return entry != null and unseen_entries.has(entry.id())

func mark_entry_seen(entry: KnowledgeEntry) -> void:
	if entry == null:
		return
	unseen_entries.erase(entry.id())

func has_learned_entry(fname: String) -> bool:
	return learned_entries.has(fname.get_basename())

func has_keyword_unlocked(keyword: String) -> bool:
	return learned_keywords.has(keyword)

func learned_entry_count() -> int:
	return learned_entries.size()

# Resolve an unlocked entry back to its resource for the encyclopedia view.
func all_learned_entries() -> Array[KnowledgeEntry]:
	var out: Array[KnowledgeEntry] = []
	for id in learned_entries:
		var e: KnowledgeEntry = knowledge_entries.get(id) as KnowledgeEntry
		if e != null:
			out.append(e)
	return out

# Grant an item by resource path (used for the Lua Core reward). Returns true
# if it landed in the inventory. Rejects dev items like every other path.
func grant_item(item_path: String, quantity: int = 1) -> bool:
	if item_path.is_empty() or not ResourceLoader.exists(item_path):
		push_warning("Global: reward item not found: %s" % item_path)
		return false
	var data: ItemData = load(item_path) as ItemData
	if data == null or data.is_dev_item:
		return false
	return add_item({"data": data, "quantity": maxi(quantity, 1)})

# Find any ItemData resource under resources/items/ by display name or file
# base name (case-insensitive, contains match). Returns null when nothing
# matches. Used by the /inv console command to hand out arbitrary items.
func find_item_by_name(query: String) -> ItemData:
	var q: String = query.strip_edges().to_lower()
	if q.is_empty():
		return null
	const ITEMS_DIR: String = "res://resources/items/"
	# 1. Exact scripting id ("iron_sword") — the form Algorithmica programs use.
	for fname in ResourceLoader.list_directory(ITEMS_DIR):
		if not fname.ends_with(".tres"):
			continue
		var data: ItemData = load(ITEMS_DIR + fname) as ItemData
		if data != null and data.item_id() == q:
			return data
	# 2. Exact resource base name / display name, then the old contains match.
	for fname in ResourceLoader.list_directory(ITEMS_DIR):
		if fname.ends_with(".tres"):
			var data: ItemData = load(ITEMS_DIR + fname) as ItemData
			if data != null:
				var base: String = fname.get_basename().to_lower()
				var display: String = data.item_name.to_lower()
				if base == q or display == q:
					return data
	for fname in ResourceLoader.list_directory(ITEMS_DIR):
		if fname.ends_with(".tres"):
			var data: ItemData = load(ITEMS_DIR + fname) as ItemData
			if data != null:
				var base: String = fname.get_basename().to_lower()
				var display: String = data.item_name.to_lower()
				if base.contains(q) or display.contains(q):
					return data
	return null

# Every scripting item id, sorted. Used by the Algorithmica editors to list the
# full catalogue (the popup puts carried items first).
func all_item_ids() -> PackedStringArray:
	var out := PackedStringArray()
	for data in list_all_items():
		out.append(data.item_id())
	out.sort()
	return out

# Every ItemData resource under resources/items/, sorted by display name. Used
# by the /items console command's picker UI.
func list_all_items() -> Array[ItemData]:
	var out: Array[ItemData] = []
	const ITEMS_DIR: String = "res://resources/items/"
	for fname in ResourceLoader.list_directory(ITEMS_DIR):
		if fname.ends_with(".tres"):
			var data: ItemData = load(ITEMS_DIR + fname) as ItemData
			if data != null:
				out.append(data)
	out.sort_custom(func(a: ItemData, b: ItemData) -> bool: return a.item_name < b.item_name)
	return out

# Grant an item by NAME (see find_item_by_name). allow_dev defaults to true so
# the /inv debug command can hand out dev-only blocks (grass, ores, etc.).
func give_item_by_name(query: String, quantity: int = 1) -> bool:
	var data := find_item_by_name(query)
	if data == null:
		return false
	return add_item({"data": data, "quantity": maxi(quantity, 1)}, true)

# ── Player / world refs ───────────────────────────────────────────
var player_node: Node = null
var world_node:  Node = null
var game_node:   Node = null  # game_instance.gd — CavePortal calls enter_cave()/exit_cave(), DungeonPortal calls enter_dungeon()

@onready var inventory_slot_scene: PackedScene = preload("res://scenes/ui/InventorySlot.tscn")

# ── Key rebinding persistence ─────────────────────────────────────
# The settings panel rebinds InputMap actions live; persist the key overrides
# to user://keybinds.cfg so they survive restarts. Saved/loaded by physical
# keycode (layout-independent). Only keyboard events are stored.
const KEYBIND_PATH: String = "user://keybinds.cfg"

func save_keybinds(actions: Array) -> void:
	var cfg := ConfigFile.new()
	for action in actions:
		var codes: Array = []
		for e in InputMap.action_get_events(action):
			if e is InputEventKey:
				codes.append(int((e as InputEventKey).physical_keycode))
		cfg.set_value("keys", action, codes)
	cfg.save(KEYBIND_PATH)

func load_keybinds() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(KEYBIND_PATH) != OK:
		return
	for action in cfg.get_section_keys("keys"):
		if not InputMap.has_action(action):
			continue
		var codes: Array = cfg.get_value("keys", action, [])
		if codes.is_empty():
			continue
		InputMap.action_erase_events(action)
		for code in codes:
			var ev := InputEventKey.new()
			ev.physical_keycode = int(code)
			InputMap.action_add_event(action, ev)

# ── Display mode persistence ──────────────────────────────────────
# Windowed vs fullscreen, kept in its OWN user:// config so it is GLOBAL (not
# tied to one world's save) and survives restarts. Applied from Global._ready —
# which runs before the main scene's _ready — so the title screen opens in the
# configured mode.
#
# Mobile is deliberately excluded: the platform owns its display, so the desktop
# window-mode controls are hidden there and apply_display_mode() is a no-op.
const DISPLAY_PATH: String = "user://settings.cfg"
const DISPLAY_SECTION: String = "display"
# Default matches project.godot's window mode (2 = maximized), so a fresh install
# behaves exactly as before until the player chooses otherwise.
var fullscreen: bool = false
# Frame pacing is a global display preference, not a per-save setting. 120 is
# the game's target refresh; 0 means unlimited. The same FPS cap is applied on
# desktop and mobile, while VSync remains a desktop-only control (Android's
# display compositor owns its presentation timing).
const FPS_LIMIT_OPTIONS: Array = [30, 60, 90, 120, 144, 165, 240, 0]
const DEFAULT_FPS_LIMIT: int = 120
var fps_limit: int = DEFAULT_FPS_LIMIT
var vsync_enabled: bool = true
# Small read-only FPS counter over gameplay. Off for every existing install whose
# settings.cfg predates this key, and off for fresh installs.
signal show_fps_changed(enabled: bool)
var show_fps: bool = false

func is_mobile() -> bool:
	return OS.has_feature("mobile")

## Point-and-click / tap-to-control is enabled again. The flag remains the one
## gate for loading, setting and the settings UI.
const POINT_AND_CLICK_ENABLED: bool = true

func is_point_and_click_available() -> bool:
	return POINT_AND_CLICK_ENABLED

func load_display_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(DISPLAY_PATH) != OK:
		fullscreen = false
		fps_limit = DEFAULT_FPS_LIMIT
		vsync_enabled = true
		point_and_click = false
		point_and_click_auto_sprint = false
		point_and_click_changed.emit(false)
		show_fps = false
		show_fps_changed.emit(false)
		return
	fullscreen = bool(cfg.get_value(DISPLAY_SECTION, "fullscreen", fullscreen))
	fps_limit = _sanitize_fps_limit(int(cfg.get_value(
		DISPLAY_SECTION, "fps_limit", DEFAULT_FPS_LIMIT)))
	vsync_enabled = bool(cfg.get_value(DISPLAY_SECTION, "vsync_enabled", true))
	show_fps = bool(cfg.get_value(DISPLAY_SECTION, "show_fps", false))
	show_fps_changed.emit(show_fps)
	point_and_click = bool(cfg.get_value("controls", "point_and_click", false))
	point_and_click_auto_sprint = bool(cfg.get_value(
		"controls", "point_and_click_auto_sprint", false))
	point_and_click_changed.emit(point_and_click)

func save_display_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.load(DISPLAY_PATH)          # keep any other keys already in the file
	cfg.set_value(DISPLAY_SECTION, "fullscreen", fullscreen)
	cfg.set_value(DISPLAY_SECTION, "fps_limit", fps_limit)
	cfg.set_value(DISPLAY_SECTION, "vsync_enabled", vsync_enabled)
	cfg.set_value(DISPLAY_SECTION, "show_fps", show_fps)
	cfg.set_value("controls", "point_and_click", point_and_click)
	cfg.set_value("controls", "point_and_click_auto_sprint", point_and_click_auto_sprint)
	cfg.save(DISPLAY_PATH)

func _sanitize_fps_limit(limit: int) -> int:
	if limit <= 0:
		return 0
	if FPS_LIMIT_OPTIONS.has(limit):
		return limit
	var best := 0
	var best_diff := 1 << 30
	for raw in FPS_LIMIT_OPTIONS:
		var option := int(raw)
		if option <= 0:
			continue
		var diff := absi(option - limit)
		if diff < best_diff:
			best_diff = diff
			best = option
	return best

# Applies the frame cap on every platform and VSync only on desktop. Android's
# compositor owns its presentation timing, so mobile never exposes/changes VSync.
func apply_frame_settings() -> void:
	Engine.max_fps = fps_limit
	if is_mobile() or DisplayServer.get_name() == "headless":
		return
	DisplayServer.window_set_vsync_mode(
		DisplayServer.VSYNC_ENABLED if vsync_enabled \
		else DisplayServer.VSYNC_DISABLED)

# Puts the OS window into the configured mode. A no-op on mobile, and it never
# forces a fixed resolution — fullscreen uses the desktop's own dimensions, and
# windowed uses the project's configured window size.
func apply_display_mode() -> void:
	if is_mobile():
		return
	DisplayServer.window_set_mode(
		DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen \
		else DisplayServer.WINDOW_MODE_WINDOWED)
	# Fullscreen/window mode changes can reset VSync state on some drivers.
	apply_frame_settings()

# Player-facing setter: applies immediately AND persists for the next launch.
func set_fullscreen(on: bool) -> void:
	fullscreen = on
	CrashLogger.event("SETTINGS", "fullscreen=%s" % on)
	apply_display_mode()
	save_display_settings()

# Player-facing FPS cap setter. Works on both desktop and mobile.
func set_fps_limit(limit: int) -> void:
	var clean := _sanitize_fps_limit(limit)
	var changed := clean != fps_limit
	fps_limit = clean
	apply_frame_settings()
	if changed:
		CrashLogger.event("SETTINGS", "fps_limit=%s" % (
			"unlimited" if clean == 0 else str(clean)))
		save_display_settings()

# Desktop-only VSync setter. Mobile ignores it (and the setting UI is hidden).
func set_vsync(on: bool) -> void:
	if is_mobile() or vsync_enabled == on:
		return
	vsync_enabled = on
	apply_frame_settings()
	CrashLogger.event("SETTINGS", "vsync=%s" % on)
	save_display_settings()

# Player-facing setter: the overlay listens for the signal and hides instantly;
# the global settings.cfg keeps the choice across restarts.
func set_show_fps(on: bool) -> void:
	if show_fps == on:
		return
	show_fps = on
	CrashLogger.event("SETTINGS", "show_fps=%s" % on)
	show_fps_changed.emit(on)
	save_display_settings()

# ── Optional point-and-click movement ─────────────────────────────
# OFF by default on every platform and for every existing save. When ON,
# left-click / tap on the world issues a move order (see player.gd); right-click,
# build mode, inventory and every existing control keep working unchanged.
signal point_and_click_changed(enabled: bool)
signal point_and_click_auto_sprint_changed(enabled: bool)
var point_and_click: bool = false
## When point-and-click issues a movement order, treat it like a held sprint
## key. Manual WASD/joystick movement still requires Shift, and the shared
## stamina/exhaustion rules apply to both paths.
var point_and_click_auto_sprint: bool = false

func set_point_and_click_auto_sprint(on: bool) -> void:
	if point_and_click_auto_sprint == on:
		return
	point_and_click_auto_sprint = on
	CrashLogger.event("SETTINGS", "point_and_click_auto_sprint=%s" % on)
	point_and_click_auto_sprint_changed.emit(on)
	save_display_settings()

func set_point_and_click(on: bool, persist: bool = true) -> void:
	if not POINT_AND_CLICK_ENABLED:
		on = false
	# PNC world clicks are deliberately ignored while build mode is active, so
	# enabling point-and-click must leave build mode. Otherwise the setting
	# appears to do nothing and every "move" click places a block instead.
	# Run this even when PNC is already on, so re-selecting it recovers a session
	# that was left in build mode.
	if on and block_mode:
		block_mode = false
		block_mode_changed.emit(false)
		CrashLogger.event("BUILD", "mode=off (point-and-click enabled)")
	if point_and_click == on:
		return
	point_and_click = on
	CrashLogger.event("SETTINGS", "point_and_click=%s" % on)
	point_and_click_changed.emit(on)
	if persist:
		save_display_settings()

# ── Shared floating item tooltip ──────────────────────────────────
# Slots and recipe buttons call these on hover; the popup follows the mouse.
# Lazily created and parented to the scene root so it draws above every UI.
var _item_tooltip: Node = null
const ITEM_TOOLTIP_SCRIPT: GDScript = preload("res://scripts/item_tooltip.gd")

func show_item_tooltip(inv_item: Dictionary) -> void:
	if _item_tooltip == null or not is_instance_valid(_item_tooltip):
		_item_tooltip = ITEM_TOOLTIP_SCRIPT.new()
		get_tree().root.add_child(_item_tooltip)
	_item_tooltip.call("show_item", inv_item)

func hide_item_tooltip() -> void:
	if _item_tooltip != null and is_instance_valid(_item_tooltip):
		_item_tooltip.call("hide_tip")

# Press-and-hold helper (used by slots): call with the button/touch pressed
# state as it changes. Holding for ITEM_HOLD_SEC shows the item tooltip;
# releasing hides it. Implemented via a one-shot timer, so nothing needs to
# run every frame.
const ITEM_HOLD_SEC: float = 0.45
var _hold_timer: Timer = null
var _hold_item:  Dictionary = {}

func item_hold_start(item: Dictionary) -> void:
	_hold_item = item
	if _hold_timer == null:
		_hold_timer = Timer.new()
		_hold_timer.one_shot = true
		_hold_timer.process_mode = Node.PROCESS_MODE_ALWAYS
		add_child(_hold_timer)
		_hold_timer.timeout.connect(_on_hold_timeout)
	_hold_timer.start(ITEM_HOLD_SEC)

func _on_hold_timeout() -> void:
	# _hold_timer is a child of Global (an autoload Node that PAUSES with the
	# tree), so process_mode ALWAYS keeps the hold working inside menus that
	# pause the game — e.g. the crafting station.
	if not _hold_item.is_empty():
		show_item_tooltip(_hold_item)

func item_hold_end() -> void:
	if _hold_timer != null:
		_hold_timer.stop()
	_hold_item = {}
	hide_item_tooltip()

func _ready() -> void:
	# Global input (Ctrl build toggle, pause/chat shortcuts) must work even when
	# the SceneTree is paused — a leaked open_ui() leaves get_tree().paused true
	# while the player (PROCESS_MODE_ALWAYS) still moves, and a pausable Global
	# would silently stop receiving _input. ALWAYS keeps this responsive.
	process_mode = Node.PROCESS_MODE_ALWAYS
	load_keybinds()
	# Apply the saved window/fullscreen mode THIS early so the very first scene
	# (the title screen) is already presented in the right mode.
	load_display_settings()
	apply_display_mode()
	apply_frame_settings()   # mobile needs the FPS cap even though display mode is fixed
	_setup_ui_scaling()
	Hotbar.resize(HOTBAR_SIZE)
	Inventory.resize(INVENTORY_SIZE)
	_init_missions()
	load_knowledge_data()
	_append_dungeon_missions()
	_append_side_missions()
	# UI hit-testing walks only registered UI roots (see is_point_over_ui).
	# Autoloads exist before the first scene, so scan them now, then pick up
	# every later CanvasLayer/top-level Control as it enters the tree.
	var scene_tree := get_tree()
	if scene_tree != null:
		if not scene_tree.node_added.is_connected(_on_ui_tree_node_added):
			scene_tree.node_added.connect(_on_ui_tree_node_added)
		_collect_ui_roots(scene_tree.root)

# Scans only while a world is actually running. A creature counts as "seen"
# when its world sprite is on screen (the same screen the player is looking at),
# not merely when it spawns off in the dark. This is deliberately throttled: it
# is a discovery scan, not a per-frame physics query.
func _process(delta: float) -> void:
	if active_save_slot <= 0 or not is_instance_valid(player_node) or get_tree().paused:
		return
	_bestiary_scan_accum += delta
	if _bestiary_scan_accum < BESTIARY_SCAN_INTERVAL:
		return
	_bestiary_scan_accum = 0.0
	for mob in get_tree().get_nodes_in_group("Mob"):
		if not is_instance_valid(mob) or not (mob is Node2D):
			continue
		var id: String = _bestiary_id_for_mob(mob)
		if id.is_empty() or bestiary_seen.has(id):
			continue
		if _bestiary_mob_on_screen(mob as Node2D):
			bestiary_record_seen(id)

func _bestiary_id_for_mob(mob: Node) -> String:
	var meta_id: Variant = mob.get_meta("bestiary_id", "")
	var id: String = str(meta_id).strip_edges()
	if not id.is_empty():
		return id
	var data: Variant = mob.get("COMBAT_DATA")
	if data is MobCombatData:
		return (data as MobCombatData).bestiary_id.strip_edges()
	return ""

func _bestiary_mob_on_screen(mob: Node2D) -> bool:
	if not mob.is_visible_in_tree():
		return false
	var vp := get_viewport()
	if vp == null:
		return false
	var screen_pos: Vector2 = vp.get_canvas_transform() * mob.global_position
	return vp.get_visible_rect().grow(-8.0).has_point(screen_pos)

## True once this world has sighted the catalog entry.
func bestiary_is_seen(id: String) -> bool:
	return bestiary_seen.has(id)

## True once this world has defeated the catalog entry at least once.
func bestiary_is_killed(id: String) -> bool:
	return bestiary_killed.has(id)

## Record a first sighting and publish a top-centre toast. Returns true only on
## the first observation for this world.
func bestiary_record_seen(id: String) -> bool:
	id = id.strip_edges()
	if id.is_empty() or bestiary_seen.has(id) or BestiaryCatalog.get_entry(id) == null:
		return false
	bestiary_seen[id] = true
	bestiary_updated.emit()
	var entry := BestiaryCatalog.get_entry(id)
	notify("[color=#8fd8ff]Bestiary entry added:[/color] [b]%s[/b]" % entry.mob_name)
	return true

## Record the first kill for this world. Sight and kill are both marked (a
## creature can be killed before the observation scan catches it). Returns true
## only on the first completion.
func bestiary_record_kill(id: String) -> bool:
	id = id.strip_edges()
	if id.is_empty() or BestiaryCatalog.get_entry(id) == null:
		return false
	var was_seen: bool = bestiary_seen.has(id)
	bestiary_seen[id] = true
	if bestiary_killed.has(id):
		return false
	bestiary_killed[id] = true
	bestiary_updated.emit()
	var entry := BestiaryCatalog.get_entry(id)
	if was_seen:
		notify("[color=#ffd77a]Bestiary entry studied:[/color] [b]%s[/b] - notes, health and drops unlocked." % entry.mob_name)
	else:
		notify("[color=#ffd77a]Bestiary entry completed:[/color] [b]%s[/b] - sighted and studied." % entry.mob_name)
	return true

func reset_bestiary_state() -> void:
	bestiary_seen.clear()
	bestiary_killed.clear()
	bestiary_updated.emit()

# Build mode toggle (Ctrl) — a core gameplay feature that switches between
# interacting with the world and placing/building blocks. Detected centrally so
# it works in every world (overworld/cave/pixie/dungeon); each world's own
# per-frame ghost/grid code reacts to the flag + block_mode_changed signal.
func _input(event: InputEvent) -> void:
	if Global.chat_open or Global.pause_menu_open:
		if event is InputEventKey and (event as InputEventKey).keycode == KEY_CTRL:
			CrashLogger.report("build toggle blocked: chat_open=%s pause_menu_open=%s" % [
				Global.chat_open, Global.pause_menu_open])
		return
	# Ctrl is a text-editing modifier (Ctrl+A/C/V/…), so never toggle build mode
	# while a text field is focused.
	if Global.is_text_input_focused():
		if event is InputEventKey and (event as InputEventKey).keycode == KEY_CTRL:
			var focused := get_viewport().gui_get_focus_owner()
			CrashLogger.report("build toggle blocked: text focus=%s" % [
				focused.get_path() if focused != null else "<none>"])
		return
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	var key_event := event as InputEventKey
	if key_event.keycode == KEY_CTRL and not key_event.shift_pressed:
		# One implementation for the Ctrl key, the mobile BUILD button and the
		# /blockmode command. The old duplicated branch skipped the dungeon guard
		# notification and could drift from toggle_build_mode().
		toggle_build_mode()

# ── World-method dispatch (used by the chat console's debug commands) ──
# Duck-typed like the rest of the codebase (has_method()/call()) — whichever
# world is active (overworld/cave/pixie/dungeon) only needs to implement the
# matching method name to support the /hitboxes, /chunkborders and
# /nearestcave commands. World scripts own the toggle/draw logic; this only
# routes the call.
func dispatch_to_world(method_name: String) -> void:
	if world_node != null and is_instance_valid(world_node) and world_node.has_method(method_name):
		world_node.call(method_name)

# Central fallback for UIs that do not consume Escape in their own _input().
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("escape") and request_ui_back(event):
		get_viewport().set_input_as_handled()

# Routes a line into the chat log (the ChatConsole listens for this). Any
# system can print to the on-screen chat this way without knowing where the
# console node is.
func log_chat(message: String) -> void:
	chat_logged.emit(message)

# ── Top-of-screen gameplay notifications ─────────────────────────
# Player-facing feedback (fishing, farming, deaths, build-mode warnings, item
# messages) is shown by NotificationHUD as a top-centre toast instead of being
# buried in the debug chat. Command/debug output keeps using log_chat().
signal notification_posted(message: String)

func notify(message: String) -> void:
	notification_posted.emit(message)

func _init_missions() -> void:
	missions = [
		{"id": "move",             "title": "Input any movement",    "completed": false},
		{"id": "open_inventory",   "title": "Open your inventory",   "completed": false},
		{"id": "cut_tree",         "title": "Cut your first tree",   "completed": false},
		{"id": "craft_item",       "title": "Craft your first item", "completed": false},
		{"id": "collect_wood",     "title": "Collect 20 wood",       "completed": false, "goal": 20},
		{"id": "craft_sword",      "title": "Craft a wooden sword",  "completed": false},
		{"id": "craft_pickaxe",    "title": "Craft a wooden pickaxe","completed": false},
		{"id": "mine_stone",       "title": "Mine 10 stone blocks",  "completed": false, "goal": 10},
		{"id": "place_blocks",     "title": "Place 5 blocks",        "completed": false, "goal": 5},
		{"id": "build_shelter",    "title": "Build a shelter",       "completed": false, "goal": 1},
		{"id": "craft_chest",      "title": "Craft a chest",         "completed": false},
		{"id": "enter_cave",       "title": "Enter a cave",          "completed": false},
		{"id": "mine_iron",        "title": "Mine 5 iron ore",       "completed": false, "goal": 5},
		{"id": "smelt_iron",       "title": "Smelt 3 iron bars",     "completed": false, "goal": 3},
		{"id": "craft_iron_sword", "title": "Craft an iron sword",   "completed": false},
		{"id": "craft_iron_pickaxe","title": "Craft an iron pickaxe","completed": false},
		{"id": "place_torch",      "title": "Place a torch",         "completed": false},
		{"id": "explore_tiles",    "title": "Explore 500 tiles",     "completed": false, "goal": 500},
		{"id": "survive_days",     "title": "Survive 3 in-game days","completed": false, "goal": 3},
		{"id": "defeat_worms",     "title": "Defeat 10 worms",       "completed": false, "goal": 10},
		{"id": "enter_dungeon",    "title": "Enter your first dungeon","completed": false},
		{"id": "clear_dungeon",    "title": "Clear a dungeon",       "completed": false},
		{"id": "learn_entry",      "title": "Learn a knowledge entry","completed": false},
		{"id": "mine_diamond",     "title": "Mine 3 diamond ore",    "completed": false, "goal": 3},
		{"id": "run_program",      "title": "Run your first Lua program", "completed": false},
		{"id": "craft_diamond_sword",   "title": "Craft a diamond sword",   "completed": false},
		{"id": "craft_diamond_pickaxe", "title": "Craft a diamond pickaxe", "completed": false},
		{"id": "craft_diamond_axe",     "title": "Craft a diamond axe",     "completed": false},
	]

# Dungeon missions are NOT hardcoded — one is created per DungeonMissionData
# .tres file actually present in resources/dungeon_missions/, so the mission
# list always matches the shipped dungeon content. Called after
# load_knowledge_data() fills the dungeon_missions registry.
func _append_dungeon_missions() -> void:
	# Player-visible title is the mission NAME only — the numbering (Roman
	# numerals) was dropped so the list reads by name. The index still lives
	# in "id" and "dungeon_index", which are internal keys, not display text.
	var indexes: Array = dungeon_missions.keys()
	indexes.sort()
	for idx in indexes:
		var m: DungeonMissionData = dungeon_missions[idx] as DungeonMissionData
		if m == null:
			continue
		missions.append({
			"id": "dungeon_%d" % idx,
			"title": m.mission_name,
			"completed": false,
			"dungeon_index": idx,
			"dungeon_category": m.dungeon_category,
		})

# ── Side missions (unlocked after the complete dungeon progression) ──
# These use the same mission dictionary/progress/save pipeline as every other
# objective. They are deliberately world/cave/robot activities because all
# dungeon entrances are gone once the extra track is complete. Completion
# awards the normal mission star through the existing tracker.
func _append_side_missions() -> void:
	var side_defs: Array = [
		{"id": "side_worm_slayer", "title": "Worm Slayer II", "goal": 25,
			"description": "Hunt the deep desert.", "objective": "Defeat 25 Desert Worms."},
		{"id": "side_wolf_slayer", "title": "Pack Breaker", "goal": 15,
			"description": "Thin the wolf packs.", "objective": "Defeat 15 wolves."},
		{"id": "side_pixie_slayer", "title": "Pixie Pest Control", "goal": 15,
			"description": "Clear the crystal caves.", "objective": "Defeat 15 pixies."},
		{"id": "side_headless_angler", "title": "Headless Angler", "goal": 10,
			"description": "The night sky has teeth.", "objective": "Defeat 10 Headless Fish."},
		{"id": "side_stone_quarry", "title": "Stone Quarry", "goal": 50,
			"description": "Build a serious reserve.", "objective": "Mine 50 stone blocks."},
		{"id": "side_iron_bars", "title": "Iron Industry", "goal": 20,
			"description": "Feed the furnace.", "objective": "Smelt 20 iron bars."},
		{"id": "side_diamond_prospector", "title": "Diamond Prospector", "goal": 5,
			"description": "Go deeper than comfortable.", "objective": "Mine 5 diamond ore."},
		{"id": "side_master_builder", "title": "Master Builder", "goal": 75,
			"description": "Leave a mark on the world.", "objective": "Place 75 blocks."},
		{"id": "side_torchbearer", "title": "Torchbearer", "goal": 20,
			"description": "Push back the dark.", "objective": "Place 20 torches."},
		{"id": "side_cave_explorer", "title": "Cave Cartographer", "goal": 8,
			"description": "Every entrance hides a new map.", "objective": "Enter 8 caves."},
		{"id": "side_master_angler", "title": "Master Angler", "goal": 20,
			"description": "Patience pays.", "objective": "Catch 20 fish."},
		{"id": "side_chef", "title": "Dungeon Chef", "goal": 10,
			"description": "A full stomach is a buff.", "objective": "Cook 10 meals."},
		{"id": "side_cactus_grower", "title": "Cactus Collector", "goal": 30,
			"description": "Colorful and useful.", "objective": "Harvest 30 Cactus."},
		{"id": "side_rare_chests", "title": "Rare Find", "goal": 3,
			"description": "Not every cache is ordinary.", "objective": "Open 3 Rare Dungeon Chests."},
		{"id": "side_chest_collector", "title": "Chest Collector", "goal": 10,
			"description": "Storage solves everything.", "objective": "Open 10 chests."},
		{"id": "side_lua_automator", "title": "Automatica Engineer", "goal": 10,
			"description": "Teach the robot well.", "objective": "Run 10 Automatica programs successfully."},
		{"id": "side_python_automator", "title": "Algorithmica Engineer", "goal": 10,
			"description": "Automate the machines.", "objective": "Run 10 Algorithmica programs successfully."},
		{"id": "side_world_explorer", "title": "World Explorer", "goal": 1500,
			"description": "There is always another horizon.", "objective": "Explore 1,500 overworld tiles."},
		{"id": "side_survivor", "title": "Long-Term Survivor", "goal": 7,
			"description": "Outlast the cycle.", "objective": "Survive 7 in-game days."},
		{"id": "side_woodcutter", "title": "Master Woodcutter", "goal": 100,
			"description": "The forest is a resource.", "objective": "Collect 100 wood."},
	]
	for d in side_defs:
		var m: Dictionary = (d as Dictionary).duplicate(true)
		m["completed"] = false
		m["progress"] = 0
		m["side"] = true
		m["category"] = "side"
		missions.append(m)

func _is_side_mission(id: String) -> bool:
	for m in missions:
		if m["id"] == id:
			return bool(m.get("side", false))
	return false

func active_side_missions(limit: int = 3) -> Array:
	if not side_missions_unlocked():
		return []
	var started: Array = []
	var unstarted: Array = []
	for m in missions:
		if not bool(m.get("side", false)) or m["completed"]:
			continue
		if int(m.get("progress", 0)) > 0:
			started.append(m)
		else:
			unstarted.append(m)
	var out: Array = []
	for m in started + unstarted:
		out.append(m)
		if out.size() >= limit:
			break
	return out

# ── Dungeon progression (sequential, no acceptance) ───────────────────
# There is no "accept a dungeon mission" step anymore. Each language runs as
# its own strictly sequential track, and the overworld always keeps exactly
# two entrances alive: the current Lua dungeon and the current Python dungeon
# (see world.gd's _ensure_current_dungeon_entrances). Clearing one removes its
# entrance and the next mission in that language's track spawns in its place.
const DUNGEON_LANGUAGES: Array[String] = ["lua", "python"]

# The language a dungeon belongs to, inferred from the file name of its
# linked knowledge entry (e.g. "entry_3_python.tres" -> "python").
func dungeon_language(idx: int) -> String:
	var m := get_dungeon_mission_for_index(idx)
	if m == null:
		return ""
	var fname: String = m.entry_resource_file
	if fname.contains("_lua"):
		return "lua"
	if fname.contains("_python"):
		return "python"
	return ""

# A dungeon mission is playable only when its linked content fully resolves:
# at least one inline question, and a teachable entry. Incomplete placeholder
# missions are listed but never made current (otherwise the quiz altar
# auto-clears an empty question list and the dungeon "completes" doing nothing).
func is_dungeon_mission_ready(idx: int) -> bool:
	var m := get_dungeon_mission_for_index(idx)
	if m == null:
		return false
	if m.is_boss():
		return true   # boss missions have no knowledge/quiz content
	if m.questions.is_empty():
		return false
	if m.is_extra():
		return true   # extra dungeons use Quiz Altars, not Knowledge Altars
	return m.entry() != null

func _dungeon_mission_completed(idx: int) -> bool:
	for m in missions:
		if m.has("dungeon_index") and int(m["dungeon_index"]) == idx:
			return bool(m.get("completed", false))
	return false

func _dungeon_index_by_category(category: String) -> Array:
	var out: Array = []
	for idx in dungeon_missions:
		var m: DungeonMissionData = dungeon_missions[idx] as DungeonMissionData
		if m != null and m.dungeon_category == category and is_dungeon_mission_ready(int(idx)):
			out.append(int(idx))
	out.sort()
	return out

func main_dungeon_indices() -> Array:
	return _dungeon_index_by_category("main")


# Lowest main-dungeon index in a language track. The tutorial layout is applied
# only to this one (Python 1 and Lua 11 in the current registry).
func first_main_dungeon_index(lang: String) -> int:
	for idx in main_dungeon_indices():
		if dungeon_language(int(idx)) == lang:
			return int(idx)
	return 0


func is_first_main_dungeon(idx: int) -> bool:
	var mission: DungeonMissionData = get_dungeon_mission_for_index(idx)
	if mission == null or not mission.is_main():
		return false
	var lang: String = dungeon_language(idx)
	if lang.is_empty():
		return false
	return first_main_dungeon_index(lang) == idx

func extra_dungeon_indices() -> Array:
	return _dungeon_index_by_category("extra")

func boss_dungeon_index() -> int:
	var all := _dungeon_index_by_category("boss")
	return int(all[0]) if not all.is_empty() else 0

func main_dungeons_complete() -> bool:
	var all := main_dungeon_indices()
	if all.is_empty():
		return false
	for idx in all:
		if not _dungeon_mission_completed(int(idx)):
			return false
	return true

func boss_dungeon_complete() -> bool:
	var idx := boss_dungeon_index()
	return idx > 0 and _dungeon_mission_completed(idx)

func extra_dungeons_complete() -> bool:
	var all := extra_dungeon_indices()
	if all.is_empty():
		return true
	for idx in all:
		if not _dungeon_mission_completed(int(idx)):
			return false
	return true

# All main dungeons and the Hitman finale must be cleared, and every extra
# dungeon must be finished, before the 20 side missions become visible.
func side_missions_unlocked() -> bool:
	return main_dungeons_complete() and boss_dungeon_complete() and extra_dungeons_complete()

# The current dungeon of a language during the main phase. Once the main tracks
# finish, the shared boss and then the extra track take over.
func current_main_dungeon_index(lang: String) -> int:
	var best: int = 0
	for idx in main_dungeon_indices():
		var di: int = int(idx)
		if _dungeon_mission_completed(di):
			continue
		if dungeon_language(di) != lang:
			continue
		if not is_dungeon_mission_ready(di):
			continue
		if best == 0 or di < best:
			best = di
	return best

func current_dungeon_index(lang: String) -> int:
	if not main_dungeons_complete():
		return current_main_dungeon_index(lang)
	if not boss_dungeon_complete():
		return 0   # the shared finale is exposed through current_dungeon_rows
	if not extra_dungeons_complete():
		var extras := extra_dungeon_indices()
		for idx in extras:
			if not _dungeon_mission_completed(int(idx)):
				return int(idx) if lang == "lua" else 0
	return 0

func current_dungeon_mission(lang: String) -> Dictionary:
	var idx: int = current_dungeon_index(lang)
	if idx <= 0:
		return {}
	for m in missions:
		if m.has("dungeon_index") and int(m["dungeon_index"]) == idx:
			return m
	return {}

## Rows for the mission tracker: main language tracks, then the boss finale,
## then the current extra dungeon. The UI adds the section heading.
func current_dungeon_rows() -> Array:
	var rows: Array = []
	if not main_dungeons_complete():
		for lang in DUNGEON_LANGUAGES:
			var idx: int = current_main_dungeon_index(lang)
			if idx <= 0:
				continue
			var m := _find_mission("dungeon_%d" % idx)
			if not m.is_empty():
				rows.append({"section": String(lang).to_upper(), "mission": m})
		return rows
	if not boss_dungeon_complete():
		var boss_idx := boss_dungeon_index()
		var bm := _find_mission("dungeon_%d" % boss_idx)
		if not bm.is_empty():
			rows.append({"section": "FINAL BOSS", "mission": bm})
		return rows
	if not extra_dungeons_complete():
		for idx in extra_dungeon_indices():
			if _dungeon_mission_completed(int(idx)):
				continue
			var em := _find_mission("dungeon_%d" % int(idx))
			if not em.is_empty():
				rows.append({"section": "EXTRA DUNGEON", "mission": em})
			break
	return rows

# Every dungeon the overworld must currently keep an entrance for.
func current_dungeon_indices() -> Array:
	var out: Array = []
	if not main_dungeons_complete():
		for lang in DUNGEON_LANGUAGES:
			var idx: int = current_main_dungeon_index(lang)
			if idx > 0:
				out.append(idx)
		return out
	if not boss_dungeon_complete():
		var boss_idx := boss_dungeon_index()
		if boss_idx > 0:
			out.append(boss_idx)
		return out
	if not extra_dungeons_complete():
		for idx in extra_dungeon_indices():
			if not _dungeon_mission_completed(int(idx)):
				out.append(int(idx))
				break
	return out

func _find_mission(id: String) -> Dictionary:
	for m in missions:
		if m["id"] == id:
			return m
	return {}

func complete_mission(id: String) -> void:
	for m in missions:
		if m["id"] == id and not m["completed"]:
			m["completed"] = true
			m["progress"] = int(m.get("goal", m.get("progress", 0)))
			# mission_completed FIRST so the tracker can animate the row while
			# it still exists; mission_updated then rebuilds the list.
			mission_completed.emit(id)
			# Dungeon missions are blue; overworld quests are yellow.
			if m.has("dungeon_index"):
				mission_star_earned.emit("dungeon_mission:" + id)
			else:
				mission_star_earned.emit("mission:" + id)
			mission_updated.emit()
			return


# ── Local star totals (per world) ─────────────────────────────────
# The local UI counts THIS world's blue/yellow stars. Blue = dungeon missions +
# dungeon clear stars; yellow = overworld quests. The account totals below are
# the cloud profile values when online, with the local totals as a fallback.
func local_blue_stars() -> int:
	var total: int = 0
	var counted: Dictionary = {}
	for m in missions:
		if bool(m.get("completed", false)) and m.has("dungeon_index"):
			var idx: int = int(m["dungeon_index"])
			counted[idx] = true
			total += dungeon_stars_for(idx) if cleared_dungeons.has(idx) else 1
	# Defensive: a cleared save whose mission row is missing still contributes
	# its stored award.
	for idx_value in cleared_dungeons:
		var idx: int = int(idx_value)
		if not counted.has(idx):
			total += dungeon_stars_for(idx)
	return total

func local_yellow_stars() -> int:
	var total: int = 0
	for m in missions:
		if bool(m.get("completed", false)) and not m.has("dungeon_index"):
			total += 1
	return total

func account_blue_stars() -> int:
	if online_mode:
		var cloud: Dictionary = Supabase.profile
		if not cloud.is_empty():
			return int(cloud.get("blue_stars", 0))
	return local_blue_stars()

func account_yellow_stars() -> int:
	if online_mode:
		var cloud: Dictionary = Supabase.profile
		if not cloud.is_empty():
			return int(cloud.get("yellow_stars", 0))
	return local_yellow_stars()

# ── Mission progress ──────────────────────────────────────────────
# Count missions (m["goal"] > 1) show "x/goal" in the tracker.
# add_mission_progress increments and auto-completes at the goal;
# set_mission_progress sets the exact count (used where a live total already
# exists, e.g. wood currently in the inventory).
func set_mission_progress(id: String, value: int) -> void:
	if _is_side_mission(id) and not side_missions_unlocked():
		return
	for m in missions:
		if m["id"] == id:
			if m["completed"]:
				return
			var goal: int = int(m.get("goal", 0))
			var v: int = maxi(0, value)
			if goal > 0:
				v = mini(v, goal)
			# Completion must win over the "unchanged" early-out: a loaded save
			# can already be at goal while `completed` is false (e.g. after a
			# goal change), and returning here would leave it stuck at goal/goal.
			if goal > 0 and v >= goal:
				m["progress"] = goal
				complete_mission(id)
				return
			if int(m.get("progress", -1)) == v:
				return
			m["progress"] = v
			mission_updated.emit()
			return

func add_mission_progress(id: String, amount: int = 1) -> void:
	for m in missions:
		if m["id"] == id and not m["completed"]:
			set_mission_progress(id, int(m.get("progress", 0)) + amount)
			return

# Authoritative "one block was successfully placed" event. All world backends
# call this only after placement is confirmed.
func record_block_placed(data: ItemData = null) -> void:
	add_mission_progress("place_blocks", 1)
	add_mission_progress("side_master_builder", 1)
	if data != null and data.is_torch:
		add_mission_progress("side_torchbearer", 1)

# Credit the mining missions for a mined block/ore. Centralised so EVERY world
# backend tracks the same quests — the overworld's placed blocks AND the cave /
# pixie-cave wall tiles (which are mined via the worlds' own _break_tile, not
# placeable_block.gd). Without this, mining stone/iron/diamond inside a cave
# dropped the item but never advanced "Mine 10 stone blocks" etc.
func track_mining(item: ItemData) -> void:
	if item == null:
		return
	var lower: String = item.item_name.to_lower()
	if lower == "stone":
		add_mission_progress("mine_stone")
		add_mission_progress("side_stone_quarry")
	elif lower.contains("iron ore"):
		add_mission_progress("mine_iron")
	elif lower.contains("diamond"):
		add_mission_progress("mine_diamond")
		add_mission_progress("side_diamond_prospector")
	elif lower == "cactus":
		add_mission_progress("side_cactus_grower")

func reset_missions() -> void:
	for m in missions:
		m["completed"] = false
		m["progress"] = 0
	cleared_dungeons.clear()
	dungeon_stars.clear()
	mission_updated.emit()

# ── Add item ──────────────────────────────────────────────────────
func add_item(item: Dictionary, allow_dev: bool = false) -> bool:
	var data: ItemData = item["data"] as ItemData
	if data != null and data.is_dev_item and not allow_dev:
		return false
	# Non-stackable items (tools) go straight to an empty slot — never
	# merge onto an existing stack.
	var stackable: bool = data.stackable if data != null else true
	var stack_limit: int = data.max_stack_size if data != null and data.max_stack_size > 0 else MAX_STACK
	var remaining: int = item["quantity"]
	# 1. Stack in hotbar (only if stackable)
	if stackable:
		for i in range(hotbar_item_slots()):
			if remaining <= 0:
				break
			if Hotbar[i] != null \
					and Hotbar[i]["data"] == data \
					and Hotbar[i]["quantity"] < stack_limit:
				var space: int = stack_limit - Hotbar[i]["quantity"]
				var add: int = mini(remaining, space)
				Hotbar[i]["quantity"] += add
				remaining -= add
		if remaining <= 0:
			Hotbar_updated.emit()
			item_picked_up.emit(data.item_name, data.item_type)
			CrashLogger.event("ITEM", "add %s x%d -> hotbar" % [data.item_name, int(item["quantity"])])
			_track_craft_missions(data, item["quantity"])
			return true
	# 2. Stack in inventory (only if stackable)
	if stackable:
		for i in range(Inventory.size()):
			if remaining <= 0:
				break
			if Inventory[i] != null \
					and Inventory[i]["data"] == data \
					and Inventory[i]["quantity"] < stack_limit:
				var space: int = stack_limit - Inventory[i]["quantity"]
				var add: int = mini(remaining, space)
				Inventory[i]["quantity"] += add
				remaining -= add
		if remaining <= 0:
			Inventory_updated.emit()
			item_picked_up.emit(data.item_name, data.item_type)
			CrashLogger.event("ITEM", "add %s x%d -> inventory" % [data.item_name, int(item["quantity"])])
			_track_craft_missions(data, item["quantity"])
			return true
	# 3. Empty hotbar slot
	for i in range(hotbar_item_slots()):
		if Hotbar[i] == null:
			Hotbar[i] = item.duplicate()
			Hotbar[i]["quantity"] = remaining
			Hotbar_updated.emit()
			item_picked_up.emit(data.item_name, data.item_type)
			CrashLogger.event("ITEM", "add %s x%d -> empty hotbar slot" % [data.item_name, remaining])
			_track_craft_missions(data, item["quantity"])
			remaining = 0
			break
	if remaining <= 0:
		return true
	# 4. Empty inventory slot
	for i in range(Inventory.size()):
		if Inventory[i] == null:
			Inventory[i] = item.duplicate()
			Inventory[i]["quantity"] = remaining
			Inventory_updated.emit()
			item_picked_up.emit(data.item_name, data.item_type)
			CrashLogger.event("ITEM", "add %s x%d -> empty inventory slot" % [data.item_name, remaining])
			_track_craft_missions(data, item["quantity"])
			remaining = 0
			break
	return remaining <= 0

# Free space (in items) for `data` across the hotbar + inventory, respecting
# stack limits. Non-stackable items need a whole empty slot. Used to avoid
# partial adds (which would lose the remainder) when returning items from a
# robot slot to the player.
func space_for_item(data: ItemData) -> int:
	if data == null:
		return 0
	var limit: int = data.max_stack_size if data.max_stack_size > 0 else MAX_STACK
	var space: int = 0
	if data.stackable:
		for arr in [Hotbar, Inventory]:
			for slot in arr:
				if slot == null:
					space += limit
				elif (slot as Dictionary)["data"] == data:
					space += maxi(0, limit - int((slot as Dictionary)["quantity"]))
	else:
		for arr in [Hotbar, Inventory]:
			for slot in arr:
				if slot == null:
					space += 1
	return space

func has_space_for_item(data: ItemData, quantity: int) -> bool:
	return quantity <= 0 or space_for_item(data) >= quantity

# ── Track wood collection for mission ─────────────────────────────
func _track_craft_missions(data: ItemData, qty: int) -> void:
	if data == null:
		return
	var name_lower: String = data.item_name.to_lower()
	if name_lower == "wood":
		var total := 0
		for slot in Hotbar:
			if slot != null and (slot["data"] as ItemData).item_name == "Wood":
				total += slot["quantity"]
		for slot in Inventory:
			if slot != null and (slot["data"] as ItemData).item_name == "Wood":
				total += slot["quantity"]
		set_mission_progress("collect_wood", total)
		add_mission_progress("side_woodcutter", qty)
	if name_lower.begins_with("cooked "):
		add_mission_progress("side_chef", qty)

# ── Remove one from an item slot by ItemData reference ────────────
# Always tries the selected hotbar slot first so the active stack is
# consumed rather than whichever matching stack happens to be at index 0.
func remove_item(data: ItemData) -> void:
	if hotbar_selected < Hotbar.size() \
			and Hotbar[hotbar_selected] != null \
			and Hotbar[hotbar_selected]["data"] == data:
		Hotbar[hotbar_selected]["quantity"] -= 1
		if Hotbar[hotbar_selected]["quantity"] <= 0:
			Hotbar[hotbar_selected] = null
		Hotbar_updated.emit()
		return
	for i in range(hotbar_item_slots()):
		if Hotbar[i] != null and Hotbar[i]["data"] == data:
			Hotbar[i]["quantity"] -= 1
			if Hotbar[i]["quantity"] <= 0:
				Hotbar[i] = null
			Hotbar_updated.emit()
			return
	for i in range(Inventory.size()):
		if Inventory[i] != null and Inventory[i]["data"] == data:
			Inventory[i]["quantity"] -= 1
			if Inventory[i]["quantity"] <= 0:
				Inventory[i] = null
			Inventory_updated.emit()
			return

# ── Hotbar helpers ────────────────────────────────────────────────
## Stable identifier for the currently selected hotbar item. Used by mining
## timers to detect a real tool switch without relying on UI signals.
func held_tool_id() -> String:
	var slot: Variant = get_hotbar_item()
	if slot == null or not (slot is Dictionary):
		return ""
	var data: ItemData = (slot as Dictionary).get("data") as ItemData
	if data == null:
		return ""
	return data.resource_path if not data.resource_path.is_empty() else data.item_name

func get_hotbar_item() -> Variant:
	if hotbar_selected < Hotbar.size():
		return Hotbar[hotbar_selected]
	return null

# ── Mining level ──────────────────────────────────────────────────
# The ONE place the player's mining tier is read. Returns the held PICKAXE's
# tier, or -1 when no pickaxe is in hand, so callers can tell "no pickaxe at
# all" (cannot mine) from "a tier-0 pickaxe". Bare hands / any non-tool item is
# a mining level of 0, which never satisfies a min_pickaxe_level of 1+.
#
# The gate is ItemData.is_pickaxe, NOT pickaxe_level: axes, swords and the
# Color Crafter all carry stray pickaxe_level values (1..10), and reading those
# as a mining tier is what let a sword — or a block — mine stone/ore.
func held_pickaxe_level() -> int:
	var data: ItemData = _held_item_data()
	if data == null or not data.is_pickaxe:
		return -1
	return maxi(0, data.pickaxe_level)

# The player's MINING level: 0 when bare-handed or holding a non-tool.
func held_mining_level() -> int:
	return maxi(0, held_pickaxe_level())

# The ItemData of the currently selected hotbar slot, or null (empty slot).
func _held_item_data() -> ItemData:
	var slot: Variant = get_hotbar_item()
	if slot == null or not (slot is Dictionary):
		return null
	return (slot as Dictionary).get("data") as ItemData

# Total quantity of `data` the player is carrying (hotbar + inventory). Single
# source of truth shared by the crafting menu and the crafting station's
# automation validation.
func count_item(data: ItemData) -> int:
	if data == null:
		return 0
	var total: int = 0
	for slot in Hotbar:
		if slot != null and (slot as Dictionary)["data"] == data:
			total += (slot as Dictionary)["quantity"]
	for slot in Inventory:
		if slot != null and (slot as Dictionary)["data"] == data:
			total += (slot as Dictionary)["quantity"]
	return total

# Every distinct ItemData the player carries (hotbar + inventory), sorted by
# display name. Backs the Algorithmica editors' item popup, which lists carried
# items first so a program can reference what is actually at hand.
func list_carried_items() -> Array[ItemData]:
	var seen: Dictionary = {}
	var out: Array[ItemData] = []
	for arr in [Hotbar, Inventory]:
		for slot in (arr as Array):
			if slot == null:
				continue
			var d: ItemData = (slot as Dictionary).get("data") as ItemData
			if d != null and not seen.has(d):
				seen[d] = true
				out.append(d)
	out.sort_custom(func(a: ItemData, b: ItemData) -> bool: return a.item_name < b.item_name)
	return out

# Number of hotbar slots that may hold items. Android reserves the LAST visible
# slot for the inventory button (see hotbar.gd), so acquired items must never
# land there — otherwise they would be unreachable behind the button.
func hotbar_item_slots() -> int:
	return HOTBAR_SIZE - 1 if is_mobile() else HOTBAR_SIZE

func set_hotbar_selection(index: int) -> void:
	hotbar_selected = clamp(index, 0, hotbar_item_slots() - 1)
	hotbar_selection_changed.emit(hotbar_selected)

## True when a viewport-space point is on a visible hotbar slot. A hotbar tap
## is an item switch, not a "do something else" action: it keeps a PNC mining
## lock alive so the break timer can restart with the newly selected tool.
func is_point_over_hotbar(point: Vector2) -> bool:
	for node in get_tree().get_nodes_in_group("hotbar_slot"):
		var slot := node as Control
		if slot != null and slot.is_visible_in_tree() \
				and slot.get_global_rect().has_point(point):
			return true
	return false

# ── Player ────────────────────────────────────────────────────────
func set_player_reference(player: Node) -> void:
	player_node = player

## Plays one swing animation with the currently held item. Mining loops call
## this every frame while a target is being broken; the player ignores the
## request while a previous swing is still alive, so this naturally paces the
## animation at one repeat per swing instead of spawning overlapping effects.
func swing_player_item() -> void:
	if player_node != null and is_instance_valid(player_node) \
			and player_node.has_method("swing_held_item"):
		player_node.call("swing_held_item")

# ── Drop item into world ──────────────────────────────────────────
# Drag-out drops always land ONE TILE in front of the player, in the
# direction they're facing. The old behavior scattered items up to ~5
# tiles away (fixed +50px below the player plus a random ±100px nudge);
# now the anti-overlap jitter is kept small and the final spot is clamped
# to a single tile from the player.
const DROP_FACING_VECTORS: Dictionary = {
	"south":      Vector2(0, 1),
	"north":      Vector2(0, -1),
	"east":       Vector2(1, 0),
	"west":       Vector2(-1, 0),
	"south-east": Vector2(1, 1),
	"south-west": Vector2(-1, 1),
	"north-east": Vector2(1, -1),
	"north-west": Vector2(-1, -1),
}

func adjust_drop_pos(_pos: Vector2) -> Vector2:
	var player := Global.player_node as Node2D
	if player == null or not player.has_method("get_facing_dir"):
		return _pos
	var facing: Vector2 = DROP_FACING_VECTORS.get(player.call("get_facing_dir"), Vector2(0, 1)) as Vector2
	var result: Vector2 = player.global_position + facing * 32.0
	# Small jitter so consecutive drops don't stack on the same pixel, but
	# never enough to leave the 1-tile zone in front of the player.
	var rad := 16.0
	for item in get_tree().get_nodes_in_group("items"):
		if (item as Node2D).global_position.distance_to(result) < rad:
			result += Vector2(randf_range(-rad, rad), randf_range(-rad, rad))
			break
	var to_player: Vector2 = result - player.global_position
	if to_player.length() > 32.0:
		result = player.global_position + to_player.normalized() * 32.0
	return result

# ── UI state ─────────────────────────────────────────────────────
# `_ui_open_count` is the number of open UI panels. `_ui_pause_suspended` holds
# the instance ids of panels that TEMPORARILY let the world run while they stay
# open — the LUA editor does this so its robot can work. Keeping the two apart
# means the refcount stays balanced (closing still releases exactly once) and a
# second UI (pause menu) can still pause the game while a run is in flight.
var _ui_pause_suspended: Dictionary = {}
# Topmost-first dismissible UI stack. Each open modal registers its own back
# action; Escape/Android Back consumes only the newest valid entry.
var _ui_back_stack: Array = []
var _last_back_event_id: int = 0
var _last_back_event_frame: int = -1

func register_ui_back(owner: Object, action: Callable) -> void:
	if owner == null or not action.is_valid():
		return
	unregister_ui_back(owner)
	_ui_back_stack.append({"owner": owner, "action": action})

func unregister_ui_back(owner: Object) -> void:
	if owner == null:
		return
	for i in range(_ui_back_stack.size() - 1, -1, -1):
		var entry: Dictionary = _ui_back_stack[i]
		if entry.get("owner") == owner:
			_ui_back_stack.remove_at(i)

## Mark one Escape event as consumed by an inner sub-layer (a suggestion popup,
## for example) so a parent panel's _input() cannot also act on the same press.
func _mark_ui_back_event(event: InputEvent) -> void:
	_last_back_event_frame = Engine.get_process_frames()
	_last_back_event_id = event.get_instance_id()

func is_ui_back_event_consumed(event: InputEvent) -> bool:
	if event == null:
		return false
	return Engine.get_process_frames() == _last_back_event_frame \
		and event.get_instance_id() == _last_back_event_id

func consume_ui_back_event(event: InputEvent) -> void:
	if event != null:
		_mark_ui_back_event(event)

## Dismiss the topmost valid registered UI. Returns true when an action ran.
## `event` is optional; when passed, repeated UI handlers receiving the same
## key event cannot dismiss two stacked windows in one press.
func request_ui_back(event: InputEvent = null) -> bool:
	if event != null and is_ui_back_event_consumed(event):
		return false
	for i in range(_ui_back_stack.size() - 1, -1, -1):
		var entry: Dictionary = _ui_back_stack[i]
		var owner_ref: Variant = entry.get("owner")
		var action_ref: Variant = entry.get("action")
		var valid_owner: bool = owner_ref is Object and is_instance_valid(owner_ref)
		var visible: bool = true
		if valid_owner:
			var vis: Variant = owner_ref.get("visible")
			visible = true if vis == null else bool(vis)
		if not valid_owner or not visible or not (action_ref is Callable) \
				or not (action_ref as Callable).is_valid():
			_ui_back_stack.remove_at(i)
			continue
		if event != null:
			_mark_ui_back_event(event)
		_ui_back_stack.remove_at(i)
		(action_ref as Callable).call()
		return true
	return false

func cancel_gameplay_input() -> void:
	mobile_move = Vector2.ZERO
	mobile_shift = false
	pnc_hold_active = false
	var p: Node = player_node
	if is_instance_valid(p) and p.has_method("cancel_pending_input"):
		p.call("cancel_pending_input")
	gameplay_input_cancelled.emit()

func open_ui() -> void:
	# Opening any interface ends the current world gesture. Without this, a
	# tap-to-control move or held touch could resume behind the panel when the
	# paused tree comes back.
	cancel_gameplay_input()
	_ui_open_count += 1
	_apply_pause_state()

func close_ui() -> void:
	_ui_open_count = max(0, _ui_open_count - 1)
	# No panel left open means no suspension can still be legitimate: drop any
	# stale entry so a freed UI can never keep later panels from pausing.
	if _ui_open_count == 0:
		_ui_pause_suspended.clear()
	_apply_pause_state()

func any_ui_open() -> bool:
	return _ui_open_count > 0

# Let the world simulate while `owner` keeps its panel open. Idempotent: the
# owner is tracked by instance id, so calling it every frame is harmless.
func suspend_ui_pause(owner: Object) -> void:
	_ui_pause_suspended[_pause_owner_id(owner)] = true
	_apply_pause_state()

# Take the pause back once the owner no longer needs the world to run.
func resume_ui_pause(owner: Object) -> void:
	_ui_pause_suspended.erase(_pause_owner_id(owner))
	_apply_pause_state()

func is_ui_pause_suspended(owner: Object) -> bool:
	return _ui_pause_suspended.has(_pause_owner_id(owner))

func _pause_owner_id(owner: Object) -> int:
	return owner.get_instance_id() if owner != null else 0

# Single source of truth for `SceneTree.paused`. Re-derived (never toggled
# blindly) so a window switch, a scene change or a stray direct write can't
# leave the game running behind an open panel.
func _apply_pause_state() -> void:
	if get_tree() == null:
		return
	# Each suspended owner releases exactly one UI's pause, so a second panel
	# that is still open keeps the game paused.
	var effective_open: int = maxi(0, _ui_open_count - _ui_pause_suspended.size())
	var want: bool = pause_menu_open or effective_open > 0
	if get_tree().paused != want:
		get_tree().paused = want

# Re-assert the pause when the window regains focus: the game must never come
# back with control inside the world while a UI panel is still open.
func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_IN \
			or what == NOTIFICATION_APPLICATION_RESUMED \
			or what == NOTIFICATION_WM_WINDOW_FOCUS_IN:
		# System bars/cutouts can change while the app is in the background
		# without a viewport resize. Recompute safe insets and layouts.
		call_deferred("refresh_ui_scale", false)
		_apply_pause_state()
	elif what == NOTIFICATION_APPLICATION_FOCUS_OUT \
			or what == NOTIFICATION_APPLICATION_PAUSED \
			or what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		cancel_gameplay_input()
	elif what == NOTIFICATION_WM_GO_BACK_REQUEST:
		# Android Back uses the same topmost-first stack as Escape. With no
		# dismissible UI, open the pause menu instead of letting the platform
		# quit and potentially discard progress. The title menu is unaffected
		# because game_node is not a live Game instance there.
		if request_ui_back():
			return
		if game_node != null and is_instance_valid(game_node):
			var pause_menu: Node = game_node.get("pause_menu")
			if pause_menu != null and pause_menu.has_method("show_menu"):
				pause_menu.call("show_menu")

# ── Scene-change safety net ───────────────────────────────────────
# Global is an autoload, so the pause model outlives every scene. If a UI node
# is ever freed without releasing its open_ui() — or the tree is left paused by
# a transition — the NEXT scene would inherit that: a new game / Continue that
# starts paused, or a game where every world click is silently ignored because
# any_ui_open() is stuck true. Every scene (re)load calls this so a fresh scene
# always begins from a clean, unpaused state.
func reset_pause_state() -> void:
	var leaked: int = _ui_open_count
	_ui_open_count  = 0
	pause_menu_open = false
	_ui_pause_suspended.clear()
	_ui_back_stack.clear()
	pnc_hold_active = false
	mobile_move = Vector2.ZERO
	mobile_shift = false
	clear_touch_mouse()
	break_hud_progress = 0.0
	_break_hud_source_id = 0
	_break_hud_updated_ms = 0
	if get_tree() != null:
		get_tree().paused = false
	# Diagnostic: a scene/world transition had to clean up a UI that never
	# released open_ui(). Keep this in release builds — it is silent in normal
	# play and makes a future pause leak visible in the log.
	if leaked > 0:
		push_warning("Global: reset_pause_state cleared %d unreleased UI pause(s)" % leaked)


# Restore the overworld-only interaction state after a dungeon. Dungeons
# deliberately disable build mode; this re-asserts the real state to every
# listener and clears any pause leaked by dungeon UI. Kept as one function so
# the transition path is testable and cannot drift from the HUD.
func restore_overworld_interaction_state() -> void:
	is_in_dungeon = false
	block_mode = false
	block_mode_changed.emit(false)
	# A quiz/chat text field that was focused when the dungeon ended can block
	# the Ctrl build toggle even after the world is restored. Release it here;
	# no legitimate overworld text input should keep focus across a transition.
	var viewport := get_viewport()
	if viewport != null:
		var focused := viewport.gui_get_focus_owner()
		if focused != null and is_instance_valid(focused):
			focused.release_focus()
	reset_pause_state()

# ── Block hover label ─────────────────────────────────────────────
var _current_hover_name: String = ""

func set_hover(name: String) -> void:
	if name != _current_hover_name:
		_current_hover_name = name
		hover_label_changed.emit(name)

func drop_item(inv_item: Dictionary, drop_position: Vector2) -> void:
	var item_scene: PackedScene = load("res://scenes/ui/InventoryItem.tscn") as PackedScene
	if item_scene == null:
		return
	var inst: Node = item_scene.instantiate()
	var qty: int = inv_item.get("quantity", 1)
	inst.call("set_item_data", inv_item["data"] as ItemData, qty)
	drop_position = adjust_drop_pos(drop_position)
	(inst as Node2D).global_position = drop_position
	get_tree().current_scene.add_child(inst)
	var item_data: ItemData = inv_item.get("data") as ItemData
	CrashLogger.event("ITEM", "drop %s x%d at=(%.1f, %.1f)" % [
		item_data.item_name if item_data != null else "?",
		qty, drop_position.x, drop_position.y])

# ── Save / load ───────────────────────────────────────────────────
var active_save_slot:   int        = -1
var has_pending_pos:    bool       = false
var pending_player_pos: Vector2    = Vector2.ZERO
var pending_world_data: Dictionary = {}
# Seed the NEXT World node should generate from. 0 = none (the scene's own
# default, i.e. a legacy save made before seeds were persisted). Set by
# begin_new_world() (fresh random roll) and by load_world_slot() (the seed saved
# with that world), consumed once by world.gd:_ready before terrain generation.
var pending_world_seed:  int = 0
var pending_time_of_day: float = -1.0  # -1 = no saved time, keep the noon default

# ── Build version ─────────────────────────────────────────────────
# The ONE authoritative version string for the RUNNING build, read from the
# Godot project setting `application/config/version` (project.godot) so there is
# a single place to bump it. Keep the export presets' application/file_version
# in step with it. Never confuse this with a SAVED WORLD's version — a world
# records the build it was last saved with (see world_version_of()).
const VERSION_FALLBACK: String = "Unknown version"
## Worlds created before this build are not eligible for account/leaderboard
## progress. Their local missions still work, but CloudSync leaves them out.
const LEADERBOARD_MIN_WORLD_VERSION: String = "0.9.3.0"
## Bump when mission definitions change materially. Stored in saves so future
## migrations can distinguish old layouts; v2 = wolf mission retired + diamond
## equipment missions added.
const MISSIONS_VERSION: int = 2

func version_at_least(version: String, minimum: String) -> bool:
	var value := version.strip_edges()
	if value.is_empty():
		return false
	var a := value.split(".")
	var b := minimum.split(".")
	for i in range(maxi(a.size(), b.size())):
		var ai := 0
		var bi := 0
		if i < a.size() and a[i].is_valid_int():
			ai = int(a[i])
		if i < b.size() and b[i].is_valid_int():
			bi = int(b[i])
		if ai > bi:
			return true
		if ai < bi:
			return false
	return true

## A world earns account/leaderboard stars only if it was CREATED at or after
## the leaderboard-era version. Legacy saves (or saves with no created_version)
## are deliberately excluded from cloud progress.
func world_progress_eligible(slot: int) -> bool:
	if slot < 1:
		return false
	var created := str(get_save_info(slot).get("created_version", "")).strip_edges()
	return version_at_least(created, LEADERBOARD_MIN_WORLD_VERSION)

func game_version() -> String:
	var v: String = str(ProjectSettings.get_setting("application/config/version", "")).strip_edges()
	return v if not v.is_empty() else VERSION_FALLBACK

func has_save(slot: int) -> bool:
	return FileAccess.file_exists("user://save_slot_%d.json" % slot)

func get_last_slot() -> int:
	var newest_slot: int   = -1
	var newest_time: float = 0.0
	for s in range(1, MAX_WORLDS + 1):
		if not has_save(s):
			continue
		var f := FileAccess.open("user://save_slot_%d.json" % s, FileAccess.READ)
		if f == null:
			continue
		var data = JSON.parse_string(f.get_as_text())
		f.close()
		if data is Dictionary and data.has("timestamp"):
			var t: float = float(data["timestamp"])
			if t > newest_time:
				newest_time = t
				newest_slot = s
	return newest_slot

func get_save_info(slot: int) -> Dictionary:
	if not has_save(slot):
		return {}
	var f := FileAccess.open("user://save_slot_%d.json" % slot, FileAccess.READ)
	if f == null:
		return {}
	var data = JSON.parse_string(f.get_as_text())
	f.close()
	if data is Dictionary:
		return data
	return {}

# ── Worlds (save slots) ───────────────────────────────────────────
# A "world" is one save slot file (user://save_slot_N.json). Slots are fully
# independent, so creating / loading / renaming / deleting one can never touch
# another. 10 worlds max; slots 1..3 predate this and keep working unchanged.
const MAX_WORLDS: int = 10
# The player-facing name of the world currently loaded (saved with it).
var world_name: String = ""
# Tutorial progress is per-world. Existing pre-tutorial saves are treated as
# completed on load so returning players are not ambushed by the intro.
# tutorial_version 2 is the guided onboarding (dialogue + practical lessons).
var tutorial_version: int = 2
var tutorial_stage: int = 0
var tutorial_completed: bool = false
# Per-lesson completion/reward flags: starter kit, Automatica deployment,
# dialogue-seen markers, etc. Kept separate from mission progress so tutorial
# retries never duplicate rewards.
var tutorial_flags: Dictionary = {}

# The version this world was CREATED with, else the one it was last SAVED with,
# else a fallback. Never invents a version for an old save that has neither.
func world_version_of(slot: int) -> String:
	var info: Dictionary = get_save_info(slot)
	for key in ["created_version", "world_version"]:
		var v: String = str(info.get(key, "")).strip_edges()
		if not v.is_empty():
			return v
	return VERSION_FALLBACK

func world_name_of(slot: int) -> String:
	var n: String = str(get_save_info(slot).get("world_name", "")).strip_edges()
	return n if not n.is_empty() else "World %d" % slot

# Rename a saved world without touching anything else in the slot. Used by the
# pencil button in the Worlds list. Writes atomically (same tmp/.bak scheme as
# save_game) so a failed rename can never corrupt the save.
func rename_world(slot: int, new_name: String) -> bool:
	var name: String = new_name.strip_edges()
	if name.is_empty():
		return false
	if name.length() > 40:
		name = name.substr(0, 40)
	var path: String = "user://save_slot_%d.json" % slot
	if not FileAccess.file_exists(path):
		return false
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return false
	var data: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if not (data is Dictionary):
		return false
	(data as Dictionary)["world_name"] = name

	var tmp: String = path + ".tmp"
	var out := FileAccess.open(tmp, FileAccess.WRITE)
	if out == null:
		return false
	out.store_string(JSON.stringify(data))
	out.close()

	var abs_path: String = ProjectSettings.globalize_path(path)
	var abs_tmp:  String = ProjectSettings.globalize_path(tmp)
	DirAccess.remove_absolute(abs_path + ".bak")
	if FileAccess.file_exists(path):
		DirAccess.rename_absolute(abs_path, abs_path + ".bak")
	if DirAccess.rename_absolute(abs_tmp, abs_path) != OK:
		return false
	if active_save_slot == slot:
		world_name = name
	return true

# Every existing world slot, oldest-first by slot number.
func list_worlds() -> Array:
	var out: Array = []
	for s in range(1, MAX_WORLDS + 1):
		if has_save(s):
			out.append(s)
	return out

func world_count() -> int:
	return list_worlds().size()

func can_create_world() -> bool:
	return world_count() < MAX_WORLDS

# True when `name` is free (case-insensitive) across every existing world.
func is_world_name_free(name: String) -> bool:
	var want: String = name.strip_edges().to_lower()
	if want.is_empty():
		return false
	for s in list_worlds():
		if world_name_of(s).to_lower() == want:
			return false
	return true

# The lowest free slot, or -1 when the 10-world limit is reached.
func next_free_slot() -> int:
	for s in range(1, MAX_WORLDS + 1):
		if not has_save(s):
			return s
	return -1

# Deletes a world. Callers MUST have confirmed with the player first — this
# only ever removes the one slot file.
func delete_world(slot: int) -> bool:
	if not has_save(slot):
		return false
	var dir := DirAccess.open("user://")
	if dir == null:
		return false
	var err := dir.remove("save_slot_%d.json" % slot)
	if err != OK:
		return false
	if active_save_slot == slot:
		active_save_slot = -1
	return true

# Starts a brand-new world in `slot` (name + empty inventory + reset missions),
# leaving every other slot untouched.
func begin_new_world(slot: int, name: String) -> void:
	active_save_slot    = slot
	world_name          = name.strip_edges()
	tutorial_version    = 2
	tutorial_stage      = 0
	tutorial_completed  = false
	tutorial_flags.clear()
	Hotbar.fill(null)
	Inventory.fill(null)
	has_pending_pos     = false
	pending_world_data.clear()
	# Every new world gets its OWN map. Non-zero so it can't be mistaken for
	# the "no pending seed" sentinel (see pending_world_seed).
	pending_world_seed = randi()
	while pending_world_seed == 0:
		pending_world_seed = randi()
	pending_time_of_day = -1.0
	cave_states.clear()
	explored_cave_tiles.clear()
	dungeon_chest_states.clear()
	reset_missions()
	reset_bestiary_state()

# ── Item (de)serialization ─────────────────────────────────────────
# Items are normally saved by resource_path. Runtime-generated color blocks
# have no .tres on disk, so they're saved by their RGB key instead and rebuilt
# via ColorBlock on load. These two helpers are the single funnel every item
# slot (hotbar, inventory, chests, station input/output, placed blocks) uses.
func serialize_item(slot_item: Variant) -> Variant:
	if slot_item == null or not (slot_item is Dictionary):
		return null
	var d: ItemData = (slot_item as Dictionary).get("data") as ItemData
	if d == null:
		return null
	var qty: int = int((slot_item as Dictionary).get("quantity", 1))
	if d.is_color_block:
		return {"color": ColorBlock.key_of(d.block_color), "quantity": qty}
	if d.resource_path.is_empty():
		return null
	return {"path": d.resource_path, "quantity": qty}

# Rebuild a {"data": ItemData, "quantity": int} slot from a saved entry, or
# null when the entry can't be resolved.
func deserialize_item(entry: Variant) -> Variant:
	if entry == null or not (entry is Dictionary):
		return null
	var e: Dictionary = entry as Dictionary
	var qty: int = int(e.get("quantity", 1))
	if e.has("color"):
		var d: ItemData = ColorBlock.from_key(str(e["color"]))
		return {"data": d, "quantity": qty} if d != null else null
	if not e.has("path"):
		return null
	var res: ItemData = load(str(e["path"])) as ItemData
	return {"data": res, "quantity": qty} if res != null else null

## Portable identity for a world, independent of its save slot. The same UID is
## preserved by every save and survives a Windows <-> Android cloud round-trip,
## so automatic sync can distinguish an updated copy from a different world
## that happens to occupy the same slot on another device.
const SAVE_FORMAT_VERSION: int = 2

func new_world_uid() -> String:
	var bytes: PackedByteArray = Crypto.new().generate_random_bytes(16)
	if bytes.is_empty():
		return "%d-%d-%d" % [Time.get_unix_time_from_system(),
			randi(), randi()]
	return bytes.hex_encode()

func world_uid_of(slot: int) -> String:
	return str(get_save_info(slot).get("world_uid", "")).strip_edges()

func save_revision_of(slot: int) -> int:
	return maxi(0, int(get_save_info(slot).get("save_revision", 0)))

## Migrate a pre-identity save in place. Old worlds keep all content; only the
## portable identity/format metadata is added, using the same atomic tmp/.bak
## swap as a normal save. Returns the refreshed info dictionary.
func ensure_save_identity(slot: int) -> Dictionary:
	var info: Dictionary = get_save_info(slot)
	if info.is_empty():
		return info
	var changed := false
	if str(info.get("world_uid", "")).strip_edges().is_empty():
		info["world_uid"] = new_world_uid()
		changed = true
	if int(info.get("save_revision", 0)) <= 0:
		info["save_revision"] = 1
		changed = true
	if not info.has("save_format"):
		info["save_format"] = SAVE_FORMAT_VERSION
		changed = true
	if not changed:
		return info
	var path := "user://save_slot_%d.json" % slot
	var tmp := path + ".tmp"
	var bak := path + ".bak"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		return info
	f.store_string(JSON.stringify(info))
	f.close()
	var abs_path := ProjectSettings.globalize_path(path)
	var abs_tmp := ProjectSettings.globalize_path(tmp)
	var abs_bak := ProjectSettings.globalize_path(bak)
	DirAccess.remove_absolute(abs_bak)
	if FileAccess.file_exists(path):
		if DirAccess.rename_absolute(abs_path, abs_bak) != OK:
			DirAccess.remove_absolute(abs_tmp)
			return info
	if DirAccess.rename_absolute(abs_tmp, abs_path) != OK:
		if FileAccess.file_exists(bak):
			DirAccess.rename_absolute(abs_bak, abs_path)
		DirAccess.remove_absolute(abs_tmp)
		return info
	return get_save_info(slot)

func save_game(slot: int) -> void:
	active_save_slot = slot
	CrashLogger.event("SAVE", "begin slot=%d world=%s" % [
		slot, world_name if not world_name.is_empty() else "<unnamed>"])
	# World metadata. `world_version` is the build that last SAVED this world;
	# `created_version` is preserved from the first save so the world list can
	# show where it came from. A save made before this existed simply has neither
	# and is reported as the fallback version — nothing is migrated or invented.
	var existing: Dictionary = get_save_info(slot)
	var uid: String = str(existing.get("world_uid", "")).strip_edges()
	if uid.is_empty():
		uid = new_world_uid()
	var save_data: Dictionary = {
		"slot":         slot,
		"timestamp":    Time.get_unix_time_from_system(),
		"save_format":  SAVE_FORMAT_VERSION,
		"world_uid":    uid,
		"save_revision": int(existing.get("save_revision", 0)) + 1,
		"player_pos_x": 0.0,
		"player_pos_y": 0.0,
		"hotbar":       [],
		"inventory":    [],
		"world_name":       world_name,
		"world_version":    game_version(),
		"created_version":  str(existing.get("created_version", game_version())),
		"tutorial_version":  tutorial_version,
		"tutorial_stage":    tutorial_stage,
		"tutorial_completed": tutorial_completed,
		"tutorial_flags":    tutorial_flags.duplicate(true),
	}
	if player_node != null:
		save_data["player_pos_x"] = (player_node as Node2D).global_position.x
		save_data["player_pos_y"] = (player_node as Node2D).global_position.y
	if world_node != null and world_node.has_method("get_world_save_data"):
		save_data["world"] = world_node.call("get_world_save_data")
	# If the Game scene can report a save context (overworld data + a spawn
	# point), prefer it — this is what makes "saved inside a structure" spawn
	# the player outside the entrance on Continue instead of at invalid
	# structure coordinates.
	if game_node != null and game_node.has_method("get_overworld_save_context"):
		var ctx: Dictionary = game_node.call("get_overworld_save_context")
		if ctx.has("player_pos") and ctx.has("world_data"):
			save_data["player_pos_x"] = (ctx["player_pos"] as Vector2).x
			save_data["player_pos_y"] = (ctx["player_pos"] as Vector2).y
			save_data["world"] = ctx["world_data"]
	for slot_item in Hotbar:
		save_data["hotbar"].append(serialize_item(slot_item))
	for slot_item in Inventory:
		save_data["inventory"].append(serialize_item(slot_item))
	var missions_save: Array = []
	for m in missions:
		missions_save.append({
			"id": m["id"],
			"completed": m["completed"],
			"progress": int(m.get("progress", 0)),
		})
	save_data["missions"] = missions_save
	save_data["missions_version"] = MISSIONS_VERSION
	if game_node != null and game_node.has_method("get_cave_states"):
		save_data["cave_states"] = game_node.call("get_cave_states")
	else:
		save_data["cave_states"] = cave_states.duplicate(true)
	save_data["time_of_day"] = time_of_day
	save_data["learned_entries"]  = learned_entries.keys()
	save_data["learned_keywords"] = learned_keywords.keys()
	save_data["unseen_entries"]   = unseen_entries.keys()
	# Bestiary state is per-world; existing saves simply load these as empty.
	save_data["bestiary_seen"]   = bestiary_seen.keys()
	save_data["bestiary_killed"] = bestiary_killed.keys()
	var cleared_save: Array = []
	for idx in cleared_dungeons:
		cleared_save.append(int(idx))
	save_data["cleared_dungeons"] = cleared_save
	var dungeon_stars_save: Array = []
	for idx in dungeon_stars:
		dungeon_stars_save.append({"index": int(idx), "stars": int(dungeon_stars[idx])})
	save_data["dungeon_stars"] = dungeon_stars_save
	var seeds_save: Array = []
	for idx in dungeon_seeds:
		seeds_save.append({"index": int(idx), "seed": int(dungeon_seeds[idx])})
	save_data["dungeon_seeds"] = seeds_save
	var chest_save: Array = []
	for key in dungeon_chest_states:
		var state_value: Variant = dungeon_chest_states[key]
		if state_value is Dictionary:
			chest_save.append({"key": str(key), "state": state_value})
	save_data["dungeon_chests"] = chest_save
	# ── Crash-safe write ─────────────────────────────────────────
	# Write to a temp file, then atomically replace the real save and keep the
	# previous one as .bak. A crash or power loss mid-write can therefore never
	# truncate a good save — the worst case is a stale .tmp (ignored by
	# has_save/load_game) plus the intact .bak.
	var path: String = "user://save_slot_%d.json" % slot
	var tmp: String = path + ".tmp"
	var bak: String = path + ".bak"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		push_warning("Global: could not open %s for writing" % tmp)
		return
	f.store_string(JSON.stringify(save_data))
	f.close()

	var abs_path: String = ProjectSettings.globalize_path(path)
	var abs_tmp:  String = ProjectSettings.globalize_path(tmp)
	var abs_bak:  String = ProjectSettings.globalize_path(bak)
	DirAccess.remove_absolute(abs_bak)
	if FileAccess.file_exists(path):
		var backup_err: Error = DirAccess.rename_absolute(abs_path, abs_bak)
		if backup_err != OK:
			push_warning("Global: could not rotate the previous save (%s)" % error_string(backup_err))
			DirAccess.remove_absolute(abs_tmp)
			return
	var replace_err: Error = DirAccess.rename_absolute(abs_tmp, abs_path)
	if replace_err != OK:
		push_warning("Global: could not replace the save file (%s)" % error_string(replace_err))
		# Restore the previous good save if the swap failed.
		if FileAccess.file_exists(bak):
			DirAccess.rename_absolute(abs_bak, abs_path)
		DirAccess.remove_absolute(abs_tmp)
		return
	CrashLogger.event("SAVE", "ok slot=%d revision=%d" % [
		slot, int(save_data.get("save_revision", 0))])
	game_saved.emit(slot)

func load_game(slot: int) -> void:
	active_save_slot = slot
	CrashLogger.event("LOAD", "begin slot=%d" % slot)
	if not has_save(slot):
		CrashLogger.event("LOAD", "missing slot=%d" % slot)
		return
	var f := FileAccess.open("user://save_slot_%d.json" % slot, FileAccess.READ)
	if f == null:
		CrashLogger.event("LOAD", "cannot open slot=%d" % slot)
		return
	var data = JSON.parse_string(f.get_as_text())
	f.close()
	if not (data is Dictionary):
		CrashLogger.event("LOAD", "invalid JSON slot=%d" % slot)
		return
	Hotbar.fill(null)
	Inventory.fill(null)
	if data.has("cave_states") and data["cave_states"] is Dictionary:
		cave_states = (data["cave_states"] as Dictionary).duplicate(true)
	else:
		cave_states.clear()
	# Cave exploration is per-entrance; the active set is restored when a cave
	# is entered (see game_instance._do_enter_cave).
	explored_cave_tiles.clear()
	# Restore the world's player-facing name (older saves have none).
	world_name = str((data as Dictionary).get("world_name", "")).strip_edges()
	var saved_tutorial_version: int = int(data.get("tutorial_version", 0))
	if saved_tutorial_version >= 2:
		tutorial_version = saved_tutorial_version
		tutorial_completed = bool(data.get("tutorial_completed", false))
		tutorial_stage = maxi(0, int(data.get("tutorial_stage", 0)))
		tutorial_flags.clear()
		if data.get("tutorial_flags") is Dictionary:
			tutorial_flags = (data["tutorial_flags"] as Dictionary).duplicate(true)
	else:
		# Legacy world (including old unfinished six-line intros): never
		# retroactively insert the new multi-stage onboarding. Keep the player's
		# existing world exactly where it was.
		tutorial_version = 2
		tutorial_completed = true
		tutorial_stage = 0
		tutorial_flags.clear()
	if data.has("hotbar"):
		var arr: Array = data["hotbar"] as Array
		for i in range(mini(arr.size(), HOTBAR_SIZE)):
			var saved_slot: Variant = deserialize_item(arr[i])
			if saved_slot != null:
				Hotbar[i] = saved_slot
	if data.has("inventory"):
		var arr: Array = data["inventory"] as Array
		for i in range(mini(arr.size(), INVENTORY_SIZE)):
			var saved_slot: Variant = deserialize_item(arr[i])
			if saved_slot != null:
				Inventory[i] = saved_slot
	if data.has("player_pos_x") and data.has("player_pos_y"):
		pending_player_pos = Vector2(float(data["player_pos_x"]), float(data["player_pos_y"]))
		has_pending_pos    = true
	if data.has("world") and data["world"] is Dictionary:
		pending_world_data = data["world"] as Dictionary
		# Reuse the seed this world was generated with so loading reproduces the
		# SAME map. Legacy saves predate the field → 0 → scene default.
		pending_world_seed = int(pending_world_data.get("seed", 0))
	else:
		pending_world_data = {}
		pending_world_seed = 0
	# Always start from a clean mission state: loading world B must not inherit
	# partial counters from world A, and old saves without a missions array must
	# not keep the previous world's quests.
	var saved_missions_version: int = int(data.get("missions_version", 0))
	reset_missions()
	bestiary_seen.clear()
	bestiary_killed.clear()
	dungeon_chest_states.clear()
	if data.has("missions"):
		# v0 = pre-versioning. Unknown/retired ids (e.g. the old wolf mission)
		# are simply ignored; progress without a value falls back below.
		var mdata: Array = data["missions"] as Array
		for entry in mdata:
			if not (entry is Dictionary) or not entry.has("id"):
				continue
			for m in missions:
				if m["id"] == entry["id"]:
					m["completed"] = bool(entry.get("completed", false))
					var goal: int = int(m.get("goal", 0))
					if entry.has("progress"):
						var progress: int = maxi(0, int(entry["progress"]))
						m["progress"] = mini(progress, goal) if goal > 0 else progress
						# A save can be at/above the goal while `completed` was
						# false (legacy goal changes); never leave a stuck full bar.
						if goal > 0 and int(m["progress"]) >= goal:
							m["completed"] = true
					elif m["completed"]:
						# Old saves only stored `completed`; restore a full bar.
						m["progress"] = goal
					break
		mission_updated.emit()
	pending_time_of_day = float(data["time_of_day"]) if data.has("time_of_day") else -1.0
	# `ui_scale` from older saves is deliberately ignored: UI size is now a
	# live responsive metric and never a per-world preference.
	if data.has("learned_entries") and data["learned_entries"] is Array:
		for id in (data["learned_entries"] as Array):
			if not learned_entries.has(id):
				learned_entries[id] = true
	# Older saves predate unseen_entries: with nothing stored, treat every
	# learned entry as already seen (no replay of the intro animation).
	if data.has("unseen_entries") and data["unseen_entries"] is Array:
		for id in (data["unseen_entries"] as Array):
			if learned_entries.has(id):
				unseen_entries[id] = true
	# Bestiary fields are optional: pre-Bestiary saves are valid and simply
	# start with an empty catalog of observations.
	if data.has("bestiary_seen") and data["bestiary_seen"] is Array:
		for id in (data["bestiary_seen"] as Array):
			var sid: String = str(id).strip_edges()
			if not sid.is_empty() and BestiaryCatalog.has_entry(sid):
				bestiary_seen[sid] = true
	if data.has("bestiary_killed") and data["bestiary_killed"] is Array:
		for id in (data["bestiary_killed"] as Array):
			var kid: String = str(id).strip_edges()
			if not kid.is_empty() and BestiaryCatalog.has_entry(kid):
				bestiary_killed[kid] = true
				bestiary_seen[kid] = true
	_rebuild_learned_keywords()
	knowledge_updated.emit()
	bestiary_updated.emit()
	if data.has("cleared_dungeons") and data["cleared_dungeons"] is Array:
		for idx in (data["cleared_dungeons"] as Array):
			if not cleared_dungeons.has(int(idx)):
				cleared_dungeons[int(idx)] = true
	if data.has("dungeon_stars") and data["dungeon_stars"] is Array:
		for entry in (data["dungeon_stars"] as Array):
			if entry is Dictionary:
				dungeon_stars[int(entry.get("index", 0))] = clampi(
					int(entry.get("stars", 3)), 1, 3)
	if data.has("dungeon_seeds") and data["dungeon_seeds"] is Array:
		for entry in (data["dungeon_seeds"] as Array):
			if entry is Dictionary:
				dungeon_seeds[int(entry["index"])] = int(entry["seed"])
	if data.has("dungeon_chests") and data["dungeon_chests"] is Array:
		for entry in (data["dungeon_chests"] as Array):
			if entry is Dictionary and entry.get("state") is Dictionary:
				dungeon_chest_states[str(entry.get("key", ""))] = \
					(entry["state"] as Dictionary).duplicate(true)
	Hotbar_updated.emit()
	Inventory_updated.emit()
	CrashLogger.event("LOAD", "ok slot=%d world=%s uid=%s" % [
		slot, str(data.get("world_name", "")), str(data.get("world_uid", ""))])
	world_loaded.emit(slot)
