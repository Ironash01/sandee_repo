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

# ── Break progress bar ────────────────────────────────────────────
# Shared visual for anything breakable (placed blocks, trees) — one
# consistent bar instead of each script drawing its own copy.
const BREAK_BAR_WIDTH:  float = 32.0
const BREAK_BAR_HEIGHT: float = 5.0
const BREAK_BAR_BG:     Color = Color(0.10, 0.10, 0.10, 0.85)
const BREAK_BAR_FILL:   Color = Color(0.30, 0.90, 0.30, 1.00)

# Must be called from inside the caller's own _draw() — CanvasItem only
# allows draw_* calls while that specific node is in its drawing pass.
func draw_break_bar(ci: CanvasItem, progress: float, y_offset: float = -20.0) -> void:
	# Break bars are a UI readout even though they are drawn over world objects,
	# so they follow the global UI scale like every other on-screen element.
	var s: float = ui_scale
	var w: float = BREAK_BAR_WIDTH * s
	var h: float = BREAK_BAR_HEIGHT * s
	var half_w: float = w * 0.5
	var y: float = y_offset * s
	ci.draw_rect(Rect2(-half_w, y, w, h), BREAK_BAR_BG)
	var fill_w: float = w * clampf(progress, 0.0, 1.0)
	ci.draw_rect(Rect2(-half_w, y, fill_w, h), BREAK_BAR_FILL)

# ── Shared break wobble ────────────────────────────────────────────
# The snappy left-right shake played while breaking ANY block. One definition
# so a placed block (overworld) and a mined wall tile (caves) shake identically
# instead of each script carrying its own copy. Callers set
# sprite.rotation = Global.block_wobble_rotation() every frame while breaking,
# and 0.0 when not.
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
func damage_player(amount: float, from_position: Vector2, attack_dir: Vector2 = Vector2.ZERO) -> void:
	if amount <= 0.0:
		return
	# Dead (pre-respawn): swallow hits so nothing re-triggers death handling or
	# knocks the frozen player around while the respawn timer runs.
	if player_is_dead:
		return
	# Safe dungeon altar room: the player can't be hurt while reading or taking
	# a quiz, so swallow the hit entirely.
	if player_in_safe_room:
		return
	var p: Node2D = player_node as Node2D
	# Invincibility frames block HP loss (and don't re-grant), but the enemy's
	# hit still LANDS — knockback keeps applying so enemies keep hitting even
	# while the player is invincible.
	var invincible: bool = p != null and p.has_method("is_invincible") and p.call("is_invincible")
	if not invincible:
		health = maxf(0.0, health - amount)
		health_changed.emit(health, max_health)
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
	var strength: float = amount * KNOCKBACK_PER_DAMAGE
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
	log_chat("[color=#ff7777]You died! Respawning in %d seconds...[/color]" % int(DEATH_RESPAWN_TIME))
	var p: Node2D = player_node as Node2D
	var death_pos: Vector2 = p.global_position if p != null else Vector2.ZERO
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
var camera_zoom:        float = 1.3
var pause_on_inventory: bool  = true
# Quest tracker: draw an opaque panel background instead of floating text.
var quest_opaque_bg:    bool  = false
signal quest_bg_changed(opaque: bool)
var pause_menu_open:    bool  = false
# ── Unified UI stack ──────────────────────────────────────────────
# All game interfaces call open_ui() / close_ui() instead of
# managing their own boolean flags and pause state.
var _ui_open_count: int = 0
var player_near_station: bool  = false
var block_mode:          bool  = false   # Ctrl toggles (gameplay build mode) — shared across all scripts; /blockmode command also works
var is_in_dungeon:       bool  = false   # true while inside a dungeon — blocks build mode toggle
var ui_scale:            float = 1.0
# True once the player has explicitly chosen a scale (pause menu / settings) or
# one was restored from a save. game_instance only applies its Large default
# when this is false, so the Small/Medium/Large choice survives scene loads.
var ui_scale_set:        bool  = false

# Fog of war for the minimap: tiles the player has been near (Vector2i -> true).
# Session-scoped (the minimap marks a radius around the player as it moves).
var explored_tiles:      Dictionary = {}

# Fog of war for DUNGEON maps, keyed by Vector3i(dungeon_index, grid_x, grid_y).
# Kept separate from explored_tiles so dungeon grid coords can't collide with
# overworld world coords (both start near 0). Session-scoped.
var explored_dungeon_tiles: Dictionary = {}

# Fog of war for CAVE maps (Vector2i grid cell -> true). Cleared on every cave
# entry (game_instance._do_enter_cave) because each entrance generates a fresh
# cave. Session-scoped.
var explored_cave_tiles: Dictionary = {}

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
# or quiz room). Set by dungeon_world.gd each frame; damage_player() ignores all
# damage while it's set, so reading/taking a quiz can't be interrupted.
var player_in_safe_room: bool = false

signal ui_scale_changed(scale: float)
signal request_close_all_ui
signal chat_logged(message: String)

signal camera_zoom_changed(zoom: float)
signal inventory_toggled(is_open: bool)
signal block_mode_changed(enabled: bool)
signal item_picked_up(item_name: String, item_type: String)
signal hover_label_changed(text: String)
signal lua_stuck_notice(message: String)

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

# ── Dungeon runtime state ─────────────────────────────────────────────
# cleared_dungeons: a dungeon is worth TWO stars — one for clearing the
# dungeon (quiz altar all-correct, recorded here) and one for completing
# its mission (Global.complete_mission, which fires right after). Both are
# counted by the mission UI's star totals.
# dungeon_seeds: rolled ONCE, the first time the player accepts that
# dungeon's mission, then persisted — re-entering regenerates the exact
# same layout (DungeonGenerator is deterministic from its seed).
var cleared_dungeons: Dictionary = {}  # dungeon_index -> true
var dungeon_seeds:    Dictionary = {}  # dungeon_index -> int
signal dungeon_cleared(dungeon_index: int)

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

# Star #1 of a dungeon's two: the quiz altar was cleared (called right before
# complete_mission fires for star #2). Idempotent so re-clears never double
# count, and it drives the mission UI popup via dungeon_cleared.
func record_dungeon_clear(dungeon_index: int) -> void:
	if cleared_dungeons.has(dungeon_index):
		return
	cleared_dungeons[dungeon_index] = true
	dungeon_cleared.emit(dungeon_index)
	mission_updated.emit()  # star totals change — refresh the mission UI

func is_dungeon_cleared(dungeon_index: int) -> bool:
	return cleared_dungeons.has(dungeon_index)

# Every dungeon is worth one clear-star in addition to its mission star, so
# the mission UI's star total = mission count + dungeon count.
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
	for fname in ResourceLoader.list_directory(ITEMS_DIR):
		if fname.ends_with(".tres"):
			var data: ItemData = load(ITEMS_DIR + fname) as ItemData
			if data != null:
				var base: String = fname.get_basename().to_lower()
				var display: String = data.item_name.to_lower()
				if base == q or display == q or base.contains(q) or display.contains(q):
					return data
	return null

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
	Hotbar.resize(HOTBAR_SIZE)
	Inventory.resize(INVENTORY_SIZE)
	_init_missions()
	load_knowledge_data()
	_append_dungeon_missions()

# Build mode toggle (Ctrl) — a core gameplay feature that switches between
# interacting with the world and placing/building blocks. Detected centrally so
# it works in every world (overworld/cave/pixie/dungeon); each world's own
# per-frame ghost/grid code reacts to the flag + block_mode_changed signal.
func _input(event: InputEvent) -> void:
	if Global.chat_open or Global.pause_menu_open:
		return
	# Ctrl is a text-editing modifier (Ctrl+A/C/V/…), so never toggle build mode
	# while a text field is focused.
	if Global.is_text_input_focused():
		return
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	var key_event := event as InputEventKey
	if key_event.keycode == KEY_CTRL and not key_event.shift_pressed:
		if is_in_dungeon:
			log_chat("[color=#ff7777]Build mode is disabled inside dungeons.[/color]")
			return
		block_mode = not block_mode
		block_mode_changed.emit(block_mode)

# ── World-method dispatch (used by the chat console's debug commands) ──
# Duck-typed like the rest of the codebase (has_method()/call()) — whichever
# world is active (overworld/cave/pixie/dungeon) only needs to implement the
# matching method name to support the /hitboxes, /chunkborders and
# /nearestcave commands. World scripts own the toggle/draw logic; this only
# routes the call.
func dispatch_to_world(method_name: String) -> void:
	if world_node != null and is_instance_valid(world_node) and world_node.has_method(method_name):
		world_node.call(method_name)

# Routes a line into the chat log (the ChatConsole listens for this). Any
# system can print to the on-screen chat this way without knowing where the
# console node is.
func log_chat(message: String) -> void:
	chat_logged.emit(message)

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
		{"id": "defeat_wolves",    "title": "Defeat 5 wolves",       "completed": false, "goal": 5},
		{"id": "build_shelter",    "title": "Place 10 blocks",       "completed": false, "goal": 10},
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
		})

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
	if m.questions.is_empty():
		return false
	return m.entry() != null

# The current dungeon of a language: its lowest-index incomplete, playable
# mission. Dungeons are strictly sequential, so at most one is current per
# language. 0 = that language's track is finished.
func current_dungeon_index(lang: String) -> int:
	var best: int = 0
	for m in missions:
		if m["completed"] or not m.has("dungeon_index"):
			continue
		var idx: int = int(m["dungeon_index"])
		if dungeon_language(idx) != lang:
			continue
		if not is_dungeon_mission_ready(idx):
			continue
		if best == 0 or idx < best:
			best = idx
	return best

func current_dungeon_mission(lang: String) -> Dictionary:
	var idx: int = current_dungeon_index(lang)
	if idx <= 0:
		return {}
	for m in missions:
		if m.has("dungeon_index") and int(m["dungeon_index"]) == idx:
			return m
	return {}

# Every dungeon the overworld must currently keep an entrance for (the
# current mission of each language, skipping finished tracks).
func current_dungeon_indices() -> Array:
	var out: Array = []
	for lang in DUNGEON_LANGUAGES:
		var idx: int = current_dungeon_index(lang)
		if idx > 0:
			out.append(idx)
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
			mission_updated.emit()
			return

# ── Mission progress ──────────────────────────────────────────────
# Count missions (m["goal"] > 1) show "x/goal" in the tracker.
# add_mission_progress increments and auto-completes at the goal;
# set_mission_progress sets the exact count (used where a live total already
# exists, e.g. wood currently in the inventory).
func set_mission_progress(id: String, value: int) -> void:
	for m in missions:
		if m["id"] == id:
			if m["completed"]:
				return
			var goal: int = int(m.get("goal", 0))
			var v: int = maxi(0, value)
			if goal > 0:
				v = mini(v, goal)
			if int(m.get("progress", -1)) == v:
				return
			m["progress"] = v
			mission_updated.emit()
			if goal > 0 and v >= goal:
				complete_mission(id)
			return

func add_mission_progress(id: String, amount: int = 1) -> void:
	for m in missions:
		if m["id"] == id and not m["completed"]:
			set_mission_progress(id, int(m.get("progress", 0)) + amount)
			return

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
	elif lower.contains("iron ore"):
		add_mission_progress("mine_iron")
	elif lower.contains("diamond"):
		add_mission_progress("mine_diamond")

func reset_missions() -> void:
	for m in missions:
		m["completed"] = false
	cleared_dungeons.clear()
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
		for i in range(Hotbar.size()):
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
			_track_craft_missions(data, item["quantity"])
			return true
	# 3. Empty hotbar slot
	for i in range(Hotbar.size()):
		if Hotbar[i] == null:
			Hotbar[i] = item.duplicate()
			Hotbar[i]["quantity"] = remaining
			Hotbar_updated.emit()
			item_picked_up.emit(data.item_name, data.item_type)
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
	for i in range(Hotbar.size()):
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

func set_hotbar_selection(index: int) -> void:
	hotbar_selected = clamp(index, 0, HOTBAR_SIZE - 1)
	hotbar_selection_changed.emit(hotbar_selected)

# ── Player ────────────────────────────────────────────────────────
func set_player_reference(player: Node) -> void:
	player_node = player

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
func open_ui() -> void:
	_ui_open_count += 1
	get_tree().paused = true

func close_ui() -> void:
	_ui_open_count = max(0, _ui_open_count - 1)
	if _ui_open_count == 0 and not pause_menu_open:
		get_tree().paused = false

func any_ui_open() -> bool:
	return _ui_open_count > 0

# ── Scene-change safety net ───────────────────────────────────────
# Global is an autoload, so the pause model outlives every scene. If a UI node
# is ever freed without releasing its open_ui() — or the tree is left paused by
# a transition — the NEXT scene would inherit that: a new game / Continue that
# starts paused, or a game where every world click is silently ignored because
# any_ui_open() is stuck true. Every scene (re)load calls this so a fresh scene
# always begins from a clean, unpaused state.
func reset_pause_state() -> void:
	_ui_open_count  = 0
	pause_menu_open = false
	if get_tree() != null:
		get_tree().paused = false

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

# ── Save / load ───────────────────────────────────────────────────
var active_save_slot:   int        = -1
var has_pending_pos:    bool       = false
var pending_player_pos: Vector2    = Vector2.ZERO
var pending_world_data: Dictionary = {}
var pending_time_of_day: float = -1.0  # -1 = no saved time, keep the noon default

func has_save(slot: int) -> bool:
	return FileAccess.file_exists("user://save_slot_%d.json" % slot)

func get_last_slot() -> int:
	var newest_slot: int   = -1
	var newest_time: float = 0.0
	for s in range(1, 4):
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

func save_game(slot: int) -> void:
	active_save_slot = slot
	var save_data: Dictionary = {
		"slot":         slot,
		"timestamp":    Time.get_unix_time_from_system(),
		"player_pos_x": 0.0,
		"player_pos_y": 0.0,
		"hotbar":       [],
		"inventory":    [],
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
		missions_save.append({"id": m["id"], "completed": m["completed"]})
	save_data["missions"] = missions_save
	save_data["time_of_day"] = time_of_day
	save_data["ui_scale"]    = ui_scale
	save_data["learned_entries"]  = learned_entries.keys()
	save_data["learned_keywords"] = learned_keywords.keys()
	save_data["unseen_entries"]   = unseen_entries.keys()
	var cleared_save: Array = []
	for idx in cleared_dungeons:
		cleared_save.append(int(idx))
	save_data["cleared_dungeons"] = cleared_save
	var seeds_save: Array = []
	for idx in dungeon_seeds:
		seeds_save.append({"index": int(idx), "seed": int(dungeon_seeds[idx])})
	save_data["dungeon_seeds"] = seeds_save
	var f := FileAccess.open("user://save_slot_%d.json" % slot, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(save_data))
		f.close()

func load_game(slot: int) -> void:
	active_save_slot = slot
	if not has_save(slot):
		return
	var f := FileAccess.open("user://save_slot_%d.json" % slot, FileAccess.READ)
	if f == null:
		return
	var data = JSON.parse_string(f.get_as_text())
	f.close()
	if not (data is Dictionary):
		return
	Hotbar.fill(null)
	Inventory.fill(null)
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
	else:
		pending_world_data = {}
	if data.has("missions"):
		var mdata: Array = data["missions"] as Array
		for entry in mdata:
			if not (entry is Dictionary) or not entry.has("id"):
				continue
			for m in missions:
				if m["id"] == entry["id"]:
					m["completed"] = bool(entry.get("completed", false))
					break
		mission_updated.emit()
	pending_time_of_day = float(data["time_of_day"]) if data.has("time_of_day") else -1.0
	if data.has("ui_scale"):
		ui_scale     = float(data["ui_scale"])
		ui_scale_set = true
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
	_rebuild_learned_keywords()
	knowledge_updated.emit()
	if data.has("cleared_dungeons") and data["cleared_dungeons"] is Array:
		for idx in (data["cleared_dungeons"] as Array):
			if not cleared_dungeons.has(int(idx)):
				cleared_dungeons[int(idx)] = true
	if data.has("dungeon_seeds") and data["dungeon_seeds"] is Array:
		for entry in (data["dungeon_seeds"] as Array):
			if entry is Dictionary:
				dungeon_seeds[int(entry["index"])] = int(entry["seed"])
	Hotbar_updated.emit()
	Inventory_updated.emit()
