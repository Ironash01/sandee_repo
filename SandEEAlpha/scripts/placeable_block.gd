extends Node2D

var item_data: ItemData = null

const ITEM_SCENE:         PackedScene = preload("res://scenes/ui/InventoryItem.tscn")
const OBJECT_BURST_SCRIPT: GDScript  = preload("res://scripts/object_burst.gd")
const INTERACT_RADIUS_PX: float       = 64.0
const SHADOW_TEXTURE:     Texture2D   = preload("res://sprites/shadow/shadow_blockbase.png")

# Pickaxes are the wrong tool for wood-tagged blocks (ItemData.wooden_block):
# they take a 75% speed penalty, i.e. the block is 4x harder to a pickaxe.
const PICKAXE_WOOD_PENALTY: float = 0.75

var _player_nearby: bool     = false
var _hovered:       bool     = false
var _world_cell:    Vector2i = Vector2i(-99999, -99999)
var _world_ref:     Node     = null

# ── Breaking state ────────────────────────────────────────────────
# Break progress is damage measured in seconds of break work. It comes
# from two sources: holding accumulates delta per frame, and every fresh
# click adds CLICK_BREAK_SECONDS — so spam clicking works as well as
# holding. Damage persists PROGRESS_PERSIST_SECONDS after the last hit
# (click or hold tick) before it's forgotten, but the wobble animation
# only plays while actively breaking — it stops the instant the player
# lets go of the mouse.
var _breaking:       bool  = false
var _break_duration: float = 1.0
var _break_elapsed:  float = 0.0
var _break_progress: float = 0.0
var _mouse_held:     bool  = false
var _last_hit_ms:    int   = -1   # wall-clock of the last damage added

const CLICK_BREAK_SECONDS:      float = 0.5   # damage one click adds
const PROGRESS_PERSIST_SECONDS: float = 2.5   # damage memory window
const WOBBLE_AMPLITUDE_RAD:     float = 0.045 # ~2.6° snap each side
const WOBBLE_SNAPS_PER_SEC:     float = 3.0   # full left→right→left cycles per second
const WOBBLE_FLIP_FRACTION:     float = 0.25  # fraction of each half spent flipping; the rest dwells

@onready var _sprite:   Sprite2D = $Sprite2D
@onready var _interact: Area2D   = $InteractArea

var _anim_timer: Timer = null  # drives the sheet animation when has_place_animation + place_animation_sheet are set

# ── Torch lighting ───────────────────────────────────────────────────
# Torches don't own a PointLight2D each — that tanked framerate with several
# torches (big overlapping pools + a 0.1s flicker Timer per torch). Instead a
# single TorchLights manager (torch_light_manager.gd) on the owning world
# clusters adjacent torches into ONE light per cluster. This block only
# registers/unregisters with that manager.
const TORCH_MANAGER_SCRIPT: GDScript = preload("res://scripts/torch_light_manager.gd")

func _ready() -> void:
	set_process(false)
	if item_data != null:
		_apply_sprite()
		if item_data.is_torch:
			_register_torch_light()
	add_child(Global.make_shadow_sprite(SHADOW_TEXTURE, Vector2(0.0, 10.0), Vector2(0.8, 0.4), 0.35))
	_interact.body_entered.connect(_on_body_entered)
	_interact.body_exited.connect(_on_body_exited)
	refresh_u_collision()
	refresh_torch_connection()

# Lazy-create (once per world) the TorchLights manager under the world that
# owns this block, then register. _world_ref is set by set_world_cell() BEFORE
# this node enters the tree, so it's available in _ready.
func _register_torch_light() -> void:
	var world: Node = _world_ref if _world_ref != null else Global.world_node
	if world == null:
		return
	var mgr: Node = world.get_node_or_null("TorchLights")
	if mgr == null:
		mgr = TORCH_MANAGER_SCRIPT.new()
		mgr.name = "TorchLights"
		world.add_child(mgr)
	if mgr.has_method("register_torch"):
		mgr.call("register_torch", self)

func _exit_tree() -> void:
	var world: Node = _world_ref \
		if (_world_ref != null and is_instance_valid(_world_ref)) \
		else Global.world_node
	if world == null or not is_instance_valid(world):
		return
	var mgr: Node = world.get_node_or_null("TorchLights")
	if mgr != null and is_instance_valid(mgr) and mgr.has_method("unregister_torch"):
		mgr.call("unregister_torch", self)

func setup(data: ItemData) -> void:
	item_data = data
	if _sprite != null:
		_apply_sprite()

# Called by world.gd's place_block/restore right after setup: remembers the
# tile this block occupies and the owning world, so _break() can unregister
# the exact cell. Without this the block can never free its tile from
# _placed_blocks (the cell stays occupied, so blocks can't be re-placed on
# it after breaking, and the freed node's collision is gone).
func set_world_cell(cell: Vector2i, world: Node) -> void:
	_world_cell = cell
	_world_ref  = world

# ── U-collider toggle ─────────────────────────────────────────────
# The full-height SIDE walls (SideColL/SideColR) only help when another block
# sits directly above or below this one — a vertical column, where nothing can
# step into the block's upper half anyway. On an isolated block they would stop
# the player entering that upper half, which world.gd's "player behind the
# block" cover y-sort depends on, so they stay disabled.
# Called on _ready, on placement, and whenever an orthogonal neighbour changes.
func refresh_u_collision() -> void:
	var side_l: CollisionShape2D = get_node_or_null("StaticBody2D/SideColL") as CollisionShape2D
	var side_r: CollisionShape2D = get_node_or_null("StaticBody2D/SideColR") as CollisionShape2D
	if side_l == null or side_r == null:
		return
	var stacked: bool = false
	var world: Node = _world_ref if _world_ref != null else Global.world_node
	if world != null and world.has_method("has_placed_block") and _world_cell.x != -99999:
		stacked = bool(world.call("has_placed_block", _world_cell + Vector2i(0, -1))) \
			or bool(world.call("has_placed_block", _world_cell + Vector2i(0, 1)))
	# set_deferred: collision state can't be flipped mid physics flush.
	side_l.set_deferred("disabled", not stacked)
	side_r.set_deferred("disabled", not stacked)

func _apply_sprite() -> void:
	if item_data == null:
		return
	# Sprite-sheet animation: set the sheet as the texture and let hframes slice
	# it into 32x32 frames, then advance `frame` on a timer. (hframes is also
	# what _update_hover uses for the block's click bounds, so hover stays
	# correct per frame.)
	var sheet: Texture2D = _active_sheet()
	if item_data.has_place_animation and sheet != null \
			and item_data.place_animation_frame_count > 1:
		_sprite.texture = sheet
		_sprite.hframes = item_data.place_animation_frame_count
		_sprite.vframes = 1
		_sprite.frame   = 0
		_start_sheet_animation()
		return
	_sprite.texture = item_data.placeable_sprite \
		if item_data.placeable_sprite != null \
		else item_data.icon
	_sprite.hframes = 1
	_sprite.vframes = 1
	_stop_sheet_animation()

# ── Connected torch ───────────────────────────────────────────────
# A torch placed directly beside a solid block uses the "connected" sheet,
# which is authored hugging the LEFT edge of its tile (for a block on the
# left) — so a block on the RIGHT flips it. Recomputed whenever an orthogonal
# neighbour changes (world.gd calls this alongside refresh_u_collision).
var _torch_connected: bool = false

func refresh_torch_connection() -> void:
	if item_data == null or not item_data.is_torch:
		return
	if item_data.torch_connected_sheet == null:
		return
	var world: Node = _world_ref if _world_ref != null else Global.world_node
	if world == null or not world.has_method("has_placed_block") or _world_cell.x == -99999:
		return
	var left:  bool = bool(world.call("has_placed_block", _world_cell + Vector2i(-1, 0)))
	var right: bool = bool(world.call("has_placed_block", _world_cell + Vector2i( 1, 0)))
	var connected: bool = left or right
	_sprite.flip_h = right and not left
	if connected == _torch_connected:
		return
	_torch_connected = connected
	_apply_sprite()

# The animation sheet to draw: the connected sheet while wall-mounted, else the
# normal centred sheet.
func _active_sheet() -> Texture2D:
	if _torch_connected and item_data.torch_connected_sheet != null:
		return item_data.torch_connected_sheet
	return item_data.place_animation_sheet

func _start_sheet_animation() -> void:
	if _anim_timer != null and _anim_timer.is_inside_tree():
		return
	_anim_timer = Timer.new()
	_anim_timer.wait_time = 1.0 / maxf(item_data.place_animation_fps, 1.0)
	_anim_timer.autostart = true
	_anim_timer.timeout.connect(_advance_sheet_frame)
	add_child(_anim_timer)

func _stop_sheet_animation() -> void:
	if _anim_timer != null and _anim_timer.is_inside_tree():
		_anim_timer.queue_free()
	_anim_timer = null

func _advance_sheet_frame() -> void:
	if _sprite == null or item_data == null:
		return
	var count: int = maxi(item_data.place_animation_frame_count, 1)
	_sprite.frame = (_sprite.frame + 1) % count

# ── Process: hover tracking + breaking timer ─────────────────────
# InteractArea's radius (64px) covers a 4-tile-wide circle, so several
# adjacent placed blocks can ALL have _player_nearby true at once. Without
# an actual mouse-hover check, one click used to start breaking on every
# nearby block simultaneously. _hovered (checked against this block's own
# sprite bounds, same approach as tree.gd) scopes the click to only the
# block actually under the cursor.
func _process(delta: float) -> void:
	if not _player_nearby:
		return
	_update_hover()
	_tick_progress_expiry()
	_tick_wobble()
	if not _mouse_held or not _hovered or not _player_within_radius():
		_cancel_breaking()
		return
	_add_break_progress(delta)

# Adds damage (in seconds of break work) from one source — a held frame's
# delta or a click's flat CLICK_BREAK_SECONDS — then breaks when full.
func _add_break_progress(seconds: float) -> void:
	_break_elapsed  = minf(_break_elapsed + seconds, _break_duration)
	_break_progress = _break_elapsed / _break_duration if _break_duration > 0.0 else 1.0
	_last_hit_ms    = Time.get_ticks_msec()
	queue_redraw()
	if _break_elapsed >= _break_duration:
		_break()

# Damage fades from memory PROGRESS_PERSIST_SECONDS after the last hit —
# until then a returning player (or spam clicker) resumes where they left.
func _tick_progress_expiry() -> void:
	if _break_progress <= 0.0:
		return
	if Time.get_ticks_msec() - _last_hit_ms < int(PROGRESS_PERSIST_SECONDS * 1000.0):
		return
	_break_elapsed  = 0.0
	_break_progress = 0.0
	_last_hit_ms    = -1
	_sprite.rotation = 0.0
	queue_redraw()

# Snappy left↔right shake, played ONLY while actively breaking (mouse
# held on the block) — releasing stops it immediately via
# _cancel_breaking's rotation reset, even mid-flip. The flip is eased-in
# so it lands hard on the target side, and the shape is continuous across
# half-cycle boundaries (a half always starts from the side the previous
# one ended on).
func _tick_wobble() -> void:
	if not _breaking:
		return
	var u: float = fposmod(Time.get_ticks_msec() / 1000.0 * WOBBLE_SNAPS_PER_SEC, 1.0)
	var target: float = 1.0 if u < 0.5 else -1.0   # side this half dwells on
	var source: float = -target                    # side the flip starts from
	var half: float   = fmod(u, 0.5)               # 0..0.5 into this half
	var p: float      = clampf(half / (0.5 * WOBBLE_FLIP_FRACTION), 0.0, 1.0)
	_sprite.rotation = lerpf(source, target, ease(p, 2.0)) * WOBBLE_AMPLITUDE_RAD

func _update_hover() -> void:
	if _sprite.texture == null:
		_hovered = false
		return
	var mouse_local: Vector2 = to_local(get_global_mouse_position())
	var half_w: float = (_sprite.texture.get_width()  / float(maxi(_sprite.hframes, 1))) * 0.5
	var half_h: float = (_sprite.texture.get_height() / float(maxi(_sprite.vframes, 1))) * 0.5
	_hovered = abs(mouse_local.x - _sprite.position.x) <= half_w \
		   and abs(mouse_local.y - _sprite.position.y) <= half_h \
		   and not Global.block_mode

func _draw() -> void:
	if _break_progress <= 0.0:
		return
	Global.draw_break_bar(self, _break_progress)

# ── Input ─────────────────────────────────────────────────────────
func _input(event: InputEvent) -> void:
	if not _player_nearby or Global.block_mode or Global.any_ui_open() or Global.pause_menu_open:
		return
	if not _hovered or not _player_within_radius():
		if _breaking:
			_cancel_breaking()
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			# Extra safety alongside _hovered: if two blocks' sprites ever
			# overlap (large placeable art), only the first one in node
			# order consumes the click instead of both reacting to it.
			if get_viewport().is_input_handled():
				return
			get_viewport().set_input_as_handled()
			_mouse_held = true
			_try_start_breaking()
			if _breaking:
				# Every fresh click is worth CLICK_BREAK_SECONDS of break
				# work, so spam clicking chips away just like holding does.
				_add_break_progress(CLICK_BREAK_SECONDS)
		else:
			_mouse_held = false
			if _breaking:
				_cancel_breaking()

func _player_within_radius() -> bool:
	if Global.player_node == null:
		return true
	return (Global.player_node as Node2D).global_position.distance_to(global_position) <= INTERACT_RADIUS_PX

func _try_start_breaking() -> void:
	if _breaking:
		return
	var slot = Global.get_hotbar_item()
	if slot == null:
		return
	var held_data: ItemData = slot["data"] as ItemData
	if held_data == null:
		return
	var held_name: String = held_data.item_name.to_lower()
	var is_axe: bool      = held_data.axe_level > 0
	var is_pickaxe: bool  = held_name.contains("pickaxe")
	var is_wood_block: bool = item_data != null and item_data.wooden_block
	var block_lvl: int = item_data.block_level if item_data != null else 0

	if is_axe and is_wood_block:
		# Axes chop wooden blocks — no pickaxe tier needed. Speed comes from the
		# axe's hidden wooden-block bonus (LV1 +0.3x, LV2 +0.6x, LV3 +1.0x).
		# Spam clicking works normally.
		_break_duration = maxf(0.1, float(block_lvl)) / (1.0 + held_data.axe_wood_block_bonus())
	elif is_pickaxe:
		var min_lvl: int = item_data.min_pickaxe_level if item_data != null else 0
		if held_data.pickaxe_level < min_lvl:
			return  # pickaxe tier too low for this block
		# Wood-tagged blocks penalise a pickaxe by 75% (speed x0.25). The
		# penalty is applied to the block's HARDNESS rather than to the clamped
		# seconds: a high pickaxe tier already floors the time at 0.1s, so
		# multiplying afterwards would leave iron/diamond pickaxes untouched and
		# the penalty would never bite.
		var hardness: float = float(block_lvl)
		if is_wood_block:
			hardness /= (1.0 - PICKAXE_WOOD_PENALTY)
		_break_duration = maxf(0.1, hardness - float(held_data.pickaxe_level))
	else:
		return  # no tool that can break this block
	# The swing animation plays for ANY item used to break — route through the
	# player so it fires even though this block consumed the click input.
	if Global.player_node != null and Global.player_node.has_method("swing_held_item"):
		Global.player_node.call("swing_held_item")
	# Keep damage accumulated within the persist window — a spam clicker (or
	# a player who walked away and came back) resumes where they left off.
	if _last_hit_ms < 0 \
			or Time.get_ticks_msec() - _last_hit_ms >= int(PROGRESS_PERSIST_SECONDS * 1000.0):
		_break_elapsed  = 0.0
		_break_progress = 0.0
	_breaking = true

# Stops active mining only — accumulated damage stays until it expires
# (see _tick_progress_expiry), so releasing the button doesn't reset it.
# Rests the sprite immediately so the wobble halts dead on release,
# hover-loss or walking away, even mid-flip.
func _cancel_breaking() -> void:
	if not _breaking:
		return
	_breaking        = false
	_sprite.rotation = 0.0

func _break() -> void:
	_breaking = false
	var world: Node = _world_ref if _world_ref != null else Global.world_node
	if world != null and world.has_method("unregister_block"):
		world.call("unregister_block", _world_cell)
	# Debris burst coloured like the block, spawned under the world so it
	# outlives this node.
	if world != null:
		var burst: Node2D = OBJECT_BURST_SCRIPT.new() as Node2D
		if burst != null:
			var tex: Texture2D = _sprite.texture if _sprite != null else null
			burst.set("source_texture", tex)
			burst.set("tint", OBJECT_BURST_SCRIPT.average_color(tex))
			world.add_child(burst)
			burst.global_position = global_position + Vector2(0.0, -10.0)
	if item_data != null:
		var drop: Node = ITEM_SCENE.instantiate() as Node
		drop.call("set_item_data", item_data)
		# World itself (via _world_ref, falling back to Global.world_node)
		# rather than get_parent() — see chest_block.gd's _break() for why.
		var drop_parent: Node = _world_ref if _world_ref != null else Global.world_node
		if drop_parent != null:
			drop_parent.add_child(drop)
			drop.global_position = global_position + Vector2(0, -16)
	queue_free()

func _on_body_entered(body: Node) -> void:
	if body.is_in_group("Player"):
		_player_nearby = true
		set_process(true)

func _on_body_exited(body: Node) -> void:
	if body.is_in_group("Player"):
		_player_nearby = false
		_hovered       = false
		_mouse_held    = false
		_cancel_breaking()   # also rests the sprite rotation
		set_process(false)
