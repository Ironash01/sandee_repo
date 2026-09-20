extends Node2D

enum TreeType { Plain = 0, Snowy = 2 }

@export var tree_type: TreeType = TreeType.Plain

const TILE_SIZE:       int        = 32
const WOOD_DROP_COUNT: int        = 4
const ITEM_SCENE:  PackedScene = preload("res://scenes/ui/InventoryItem.tscn")
const WOOD_DATA:   ItemData    = preload("res://resources/items/wood.tres")
const OBJECT_BURST_SCRIPT: GDScript = preload("res://scripts/object_burst.gd")
# Leaf-fade shader (see world.gd _update_tree_fade): the canopy becomes
# translucent while the player hides behind it; the trunk stays opaque.
const CANOPY_FADE_SHADER: Shader = preload("res://shaders/tree_canopy_fade.gdshader")
# Tree's local origin (0,0) is the trunk's visual base, with the canopy
# sprite extending UPWARD (negative y) from there — anywhere in that negative
# range sits inside/behind the canopy, which is what made the old -24.0
# value look like it was drawing behind the tree. Canopy height also differs
# per tree type (Snowy is a different sprite from the plains tree), so a fixed
# negative offset can't reliably clear it for every tree anyway. Positive y
# (below the trunk base, on the ground) is always clear regardless of tree
# type/size, and matches how the block break bar sits close to the sprite's base.
const BREAK_BAR_Y_OFFSET: float = 10.0

# Choppable region: a vertical band this tall above the tree's visual base
# (i.e. the TRUNK). The canopy/leaves above it can't be chopped — if the
# cursor drifts up onto the leaves mid-chop, the break cancels.
const TRUNK_HOVER_HEIGHT: float = 40.0

var _player_nearby: bool = false
var _hovered:       bool = false

# ── Leaf fade state (player walks behind the canopy) ───────────────
# The world driver sets a fade TARGET each frame (_set_canopy_fade); this
# node lerps its own fade uniform toward it so the transition is smooth
# rather than a hard pop. Needs its own ShaderMaterial (not shared) since
# the fade value is per-tree.
const CANOPY_FADE_LEAF_SPEED: float = 12.0   # lerp rate per second
# Max fade amount — leaves thin to (1 - this) opacity so they stay
# readable instead of vanishing outright.
const CANOPY_FADE_MAX: float = 0.70
var _canopy_fade:      float        = 0.0
var _canopy_material:  ShaderMaterial = null

# ── Breaking state — spam-click, each click adds progress.
# Not tool-gated: chopping works from the start of the game, no axe needed.
# Duration comes straight from WOOD_DATA.block_level (no level to subtract).
# Axes give a 2x speed bonus (half the break time).
const CLICK_BREAK_SECONDS:      float = 0.25  # progress added per click
const PROGRESS_PERSIST_SECONDS: float = 2.5   # damage memory window
var _breaking:       bool  = false
var _break_duration: float = 1.0
var _break_elapsed:  float = 0.0
var _break_progress: float = 0.0
var _mouse_held:     bool  = false
var _last_hit_ms:    int   = -1

@onready var _sprite:   Sprite2D = $Sprite2D
@onready var _interact: Area2D   = $InteractArea

func _ready() -> void:
	set_process(false)
	_interact.body_entered.connect(_on_body_entered)
	_interact.body_exited.connect(_on_body_exited)
	# Per-instance leaf-fade material (each tree fades independently). If the
	# sprite is missing (defensive) just skip the shader setup.
	if _sprite != null and _sprite.texture != null:
		_canopy_material = ShaderMaterial.new()
		_canopy_material.shader = CANOPY_FADE_SHADER
		_sprite.material = _canopy_material

# ── Process: hover tracking + breaking timer ─────────────────────
func _process(delta: float) -> void:
	if not _player_nearby:
		return
	_update_hover()
	_tick_progress_expiry()
	if not _mouse_held or not _hovered:
		_cancel_breaking()
		return
	_add_break_progress(delta)

func _update_hover() -> void:
	if _sprite.texture == null:
		_hovered = false
		return
	var mouse_local: Vector2 = to_local(get_global_mouse_position())
	# Hover box matches the sprite's actual frame bounds, centred on the
	# sprite's VISUAL centre. The canopy is drawn upward via Sprite2D.offset
	# (sprite.position stays at the trunk base so the y-sort anchors there),
	# so the on-screen centre is position + offset.
	var visual_center: Vector2 = _sprite.position + _sprite.offset
	var half_w: float = (_sprite.texture.get_width()  / float(maxi(_sprite.hframes, 1))) * 0.5
	var half_h: float = (_sprite.texture.get_height() / float(maxi(_sprite.vframes, 1))) * 0.5
	# Only the TRUNK (the band just above the visual base) is choppable — the
	# leaves/canopy above it don't count. Moving the cursor up onto the leaves
	# mid-chop makes _hovered false so _process cancels the break.
	var bottom: float = visual_center.y + half_h
	var in_trunk: bool = mouse_local.y >= bottom - TRUNK_HOVER_HEIGHT \
		and mouse_local.y <= bottom
	_hovered = abs(mouse_local.x - visual_center.x) <= half_w \
		   and in_trunk \
		   and not Global.block_mode

func _draw() -> void:
	if not _breaking:
		return
	Global.draw_break_bar(self, _break_progress, BREAK_BAR_Y_OFFSET)

# ── Input ─────────────────────────────────────────────────────────
func _input(event: InputEvent) -> void:
	if not _player_nearby or Global.block_mode or Global.any_ui_open() or Global.pause_menu_open:
		return
	if not _hovered:
		if _breaking:
			_cancel_breaking()
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			get_viewport().set_input_as_handled()
			_mouse_held = true
			# Spam-click: every press adds break progress (the first also
			# starts the timer), so each click chips the wood away.
			if not _breaking:
				_try_start_breaking()
			_add_break_progress(CLICK_BREAK_SECONDS)
		else:
			_mouse_held = false
			if _breaking:
				_cancel_breaking()

func _try_start_breaking() -> void:
	if _breaking:
		return
	var base_dur := maxf(0.1, float(WOOD_DATA.block_level))
	_break_duration = _get_break_duration(base_dur)
	# Keep accumulated damage within the persist window — a spam clicker (or
	# a player who walked away and came back) resumes where they left off.
	if _last_hit_ms < 0 \
			or Time.get_ticks_msec() - _last_hit_ms >= int(PROGRESS_PERSIST_SECONDS * 1000.0):
		_break_elapsed  = 0.0
		_break_progress = 0.0
	_breaking = true
	if Global.player_node != null and Global.player_node.has_method("swing_held_item"):
		Global.player_node.call("swing_held_item")
	queue_redraw()

func _add_break_progress(amount: float) -> void:
	_break_elapsed  = minf(_break_elapsed + amount, _break_duration)
	_break_progress = _break_elapsed / _break_duration if _break_duration > 0.0 else 1.0
	_last_hit_ms    = Time.get_ticks_msec()
	queue_redraw()
	if _break_elapsed >= _break_duration:
		_destroy()

# Damage fades from memory PROGRESS_PERSIST_SECONDS after the last hit —
# until then a returning player (or spam clicker) resumes where they left.
func _tick_progress_expiry() -> void:
	if _break_progress <= 0.0:
		return
	if Time.get_ticks_msec() - _last_hit_ms < int(PROGRESS_PERSIST_SECONDS * 1000.0):
		return
	_break_elapsed  = 0.0
	_break_progress = 0.0
	queue_redraw()

# ── Public: autonomous chopping (Lua NPC) ─────────────────────────
# Advances the same timer the player's spam-click uses, in fixed
# increments called on a delay loop rather than driven by mouse input.
func chop(amount: float) -> void:
	if not _breaking:
		var base_dur := maxf(0.1, float(WOOD_DATA.block_level))
		_break_duration = _get_break_duration(base_dur)
		_breaking       = true
	_add_break_progress(amount)

func _cancel_breaking() -> void:
	if not _breaking:
		return
	_breaking = false
	# Keep accumulated damage (spam-clicking resumes where it left off);
	# it expires via _tick_progress_expiry.
	queue_redraw()

# Chopping is faster with an axe: base / (axe_level + 1), so LV1 = 2x,
# LV2 = 3x, LV3 = 4x. Reads ItemData.axe_level instead of the item's name.
func _get_break_duration(base: float) -> float:
	var held: Variant = Global.get_hotbar_item()
	if held != null and (held as Dictionary).has("data"):
		var data: ItemData = (held as Dictionary)["data"] as ItemData
		if data != null and data.axe_level > 0:
			return base / float(data.axe_level + 1)
	return base

# ── Leaf fade (called each frame by world.gd's _update_tree_fade) ────
# target is 1.0 when the player is hidden behind the canopy, 0.0 when
# clear. Lerps the shader's fade uniform toward it (capped so the leaves
# thin but stay visible) so the canopy eases in/out rather than blinking.
# No-op if the material isn't set up.
func _set_canopy_fade(target: float, delta: float) -> void:
	if _canopy_material == null:
		return
	var capped: float = clampf(target, 0.0, CANOPY_FADE_MAX)
	_canopy_fade = lerpf(
		_canopy_fade,
		capped,
		minf(1.0, delta * CANOPY_FADE_LEAF_SPEED)
	)
	_canopy_material.set_shader_parameter("fade", _canopy_fade)

# ── Destroy ───────────────────────────────────────────────────────
func _destroy() -> void:
	_breaking = false
	# Use the global reference rather than get_parent() to avoid coupling to scene structure.
	var world: Node = Global.world_node
	# Leaf/wood debris burst coloured like the tree, spawned under the world so
	# it outlives this tree.
	if is_instance_valid(world):
		var burst: Node2D = OBJECT_BURST_SCRIPT.new() as Node2D
		if burst != null:
			var tex: Texture2D = _sprite.texture if _sprite != null else null
			burst.set("source_texture", tex)
			burst.set("tint", OBJECT_BURST_SCRIPT.average_color(tex))
			world.add_child(burst)
			burst.global_position = global_position + Vector2(0.0, -24.0)
	if is_instance_valid(world) and world.has_method("notify_tree_removed"):
		world.call("notify_tree_removed", self)
	Global.complete_mission("cut_tree")
	_drop_wood()
	queue_free()

func _drop_wood() -> void:
	for i in range(WOOD_DROP_COUNT):
		var item: Node      = ITEM_SCENE.instantiate()
		var offset: Vector2 = Vector2(randf_range(-24, 24), randf_range(-24, 24))
		item.call("set_item_data", WOOD_DATA)
		get_parent().add_child(item)
		item.global_position = global_position + offset

# ── Proximity ─────────────────────────────────────────────────────
func _on_body_entered(body: Node) -> void:
	if body.is_in_group("Player"):
		_player_nearby = true
		set_process(true)

func _on_body_exited(body: Node) -> void:
	if body.is_in_group("Player"):
		_player_nearby = false
		_hovered       = false
		_mouse_held    = false
		_cancel_breaking()
		set_process(false)
