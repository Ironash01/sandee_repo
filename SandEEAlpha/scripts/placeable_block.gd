extends Node2D

var item_data: ItemData = null

const ITEM_SCENE:         PackedScene = preload("res://scenes/ui/InventoryItem.tscn")
const OBJECT_BURST_SCRIPT: GDScript  = preload("res://scripts/object_burst.gd")
const INTERACT_RADIUS_PX: float       = 64.0
const SHADOW_TEXTURE:     Texture2D   = preload("res://sprites/shadow/shadow_blockbase.png")

# Pickaxes are the wrong tool for wood-tagged blocks (ItemData.wooden_block):
# they take a 75% speed penalty, i.e. the block is 4x harder to a pickaxe.
const PICKAXE_WOOD_PENALTY: float = 0.75

# Bare-handed mining. A block is ALWAYS breakable — with no pickaxe (or an
# unrelated item) it just takes this much longer and yields NO item (see
# _break). The tier gate on ItemData.min_pickaxe_level decides whether the
# player EARNS the block, not whether they can chip it away.
const BAREHAND_TIME_MULT: float = 2.5

var _player_nearby: bool     = false
var _hovered:       bool     = false
var _world_cell:    Vector2i = Vector2i(-99999, -99999)
var _world_ref:     Node     = null

# ── Floor / door ──────────────────────────────────────────────────
# Floors are walkable decor rendered UNDER everything (like the dungeon trap).
const FLOOR_Z: int = -200
# Door state + the facing it was placed with. The door node rotates to the
# player's facing (like the connected torch orients itself from context).
var _door_open:   bool   = false
var _door_facing: String = "south"

# The door art is front-facing at rotation 0, i.e. its front normal points
# "south" (toward the viewer). "Door front = player facing" therefore rotates
# that normal onto the player's facing vector: south → 0, north → PI,
# east → -PI/2, west → +PI/2.
func _door_rotation_for(dir: String) -> float:
	if dir.contains("east"):  return -PI * 0.5
	if dir.contains("west"):  return  PI * 0.5
	if dir.contains("north"): return PI
	return 0.0   # south / unknown

# ── Breaking state ────────────────────────────────────────────────
# Break progress is damage measured in seconds of break work. It comes
# from two sources: holding accumulates delta per frame, and every fresh
# click adds CLICK_BREAK_SECONDS — so spam clicking works as well as
# holding. Damage persists PROGRESS_PERSIST_SECONDS after the last hit
# (click or hold tick) before it's forgotten, but the wobble animation
# only plays while actively breaking — it stops the instant the player
# lets go of the mouse.
var _breaking:       bool  = false
# True when the current break was started WITHOUT a valid tool (bare hands or an
# unrelated item). Such a break still destroys the block — slower — but grants
# no item and no mining-mission progress (see _break).
var _barehanded:     bool  = false
var _break_duration: float = 1.0
var _break_elapsed:  float = 0.0
var _break_progress: float = 0.0
var _break_tool_id:  String = ""
var _break_tool_known: bool = false
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

# Torches/bonfires register their light with the owning world's TorchLights
# manager. This MUST be _enter_tree, not _ready: the overworld is REMOVED from
# the tree (never freed) while a cave/dungeon is active, which fires _exit_tree
# on every block (unregistering its light). _ready only ever fires ONCE, so a
# _ready-only registration never comes back — the bonfire/torch light vanished
# for good after leaving a cave/dungeon. _enter_tree fires on every re-entry.
func _enter_tree() -> void:
	if item_data != null and item_data.is_torch:
		_register_torch_light()

func _ready() -> void:
	if not Global.gameplay_input_cancelled.is_connected(_on_gameplay_input_cancelled):
		Global.gameplay_input_cancelled.connect(_on_gameplay_input_cancelled)
	set_process(false)
	if item_data != null:
		_apply_sprite()
		if item_data.is_floor:
			_apply_floor()
		elif item_data.is_door:
			_apply_door()
		elif item_data.is_torch:
			_apply_torch()
	add_child(Global.make_shadow_sprite(SHADOW_TEXTURE, Vector2(0.0, 10.0), Vector2(0.8, 0.4), 0.35))
	_interact.body_entered.connect(_on_body_entered)
	_interact.body_exited.connect(_on_body_exited)
	refresh_u_collision()
	refresh_torch_connection()
	# Contextual cursors only need to scan doors/bonfires, not every stone block.
	if has_plain_click():
		add_to_group("PlainClickBlock")

# ── Floor ─────────────────────────────────────────────────────────
# A floor is walkable (its collider is disabled) and sits under the world (low
# z-index). The z is set DEFERRED because the world assigns z_index AFTER
# add_child() (which fires _ready), so setting it here would be overwritten.
func _apply_floor() -> void:
	var cs := get_node_or_null("StaticBody2D/CollisionShape2D") as CollisionShape2D
	if cs != null:
		cs.disabled = true
	call_deferred("_apply_floor_z")

func _apply_floor_z() -> void:
	z_index = FLOOR_Z

# ── Torch / bonfire (auxiliary) ───────────────────────────────────
# Torches (and bonfires) are auxiliary decor — they must NOT block the player,
# so their solid collider is disabled like a floor. They still light + animate.
func _apply_torch() -> void:
	var cs := get_node_or_null("StaticBody2D/CollisionShape2D") as CollisionShape2D
	if cs != null:
		cs.disabled = true

# ── Door ──────────────────────────────────────────────────────────
func _apply_door() -> void:
	var p = Global.player_node
	_door_facing = str(p.get("_face_dir")) if p != null and p.get("_face_dir") != null else "south"
	rotation = _door_rotation_for(_door_facing)
	_set_door_collision(not _door_open)

func _toggle_door() -> void:
	_door_open = not _door_open
	_apply_sprite()
	_set_door_collision(not _door_open)

# ── Plain-click dispatch ──────────────────────────────────────────
# Blocks that react to a PLAIN left-click instead of mining (a door toggles
# open/closed; a bonfire toggles the respawn point — see bonfire.gd). SHIFT+
# click always falls through to mining.
func has_plain_click() -> bool:
	return item_data != null and item_data.is_door

func on_plain_click() -> void:
	_toggle_door()

# True when this node is the TOP block at its cell. A floor kept under a placed
# block is NOT the top, so it must not consume clicks meant for the block on top.
func _is_top_block() -> bool:
	var world := _world()
	if world == null or not world.has_method("placed_node"):
		return true
	return world.call("placed_node", _world_cell) == self

func _set_door_collision(solid: bool) -> void:
	var cs := get_node_or_null("StaticBody2D/CollisionShape2D") as CollisionShape2D
	if cs != null:
		cs.set_deferred("disabled", not solid)

# Door save/restore: the facing it was placed with + its open/closed state.
# Every PlaceableBlock exposes these (the world calls them on every block), so
# they must no-op for non-doors — otherwise a restored FLOOR would run the door
# path and re-enable its (walkable) collider, and a restored wall would take a
# door rotation.
func get_door_save_data() -> Dictionary:
	if item_data == null or not item_data.is_door:
		return {}
	return {"facing": _door_facing, "open": _door_open}

func set_door_save_data(data: Dictionary) -> void:
	if item_data == null or not item_data.is_door:
		return
	_door_facing = str(data.get("facing", "south"))
	_door_open   = bool(data.get("open", false))
	rotation = _door_rotation_for(_door_facing)
	_apply_sprite()
	_set_door_collision(not _door_open)

# The world that owns this block, or null. Guards against a FREED _world_ref:
# `_world_ref != null` is TRUE for a freed instance, so the old
# `_world_ref if _world_ref != null else Global.world_node` assigned a freed
# object to a typed `Node` var and threw
# "Trying to assign invalid previously freed instance".
func _world() -> Node:
	if is_instance_valid(_world_ref):
		return _world_ref
	if is_instance_valid(Global.world_node):
		return Global.world_node
	return null

# Lazy-create (once per world) the TorchLights manager under the world that
# owns this block, then register. _world_ref is set by set_world_cell() BEFORE
# this node enters the tree, so it's available in _ready.
func _register_torch_light() -> void:
	var world: Node = _world()
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
	var world: Node = _world()
	if world == null:
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

# ── Collision ─────────────────────────────────────────────────────
# A placed block uses a SINGLE solid 32x32 collider. The old conditional
# U-shape (a bottom strip + 4px full-height edge walls, upper-middle left open)
# let the player's feet slip into a block's upper half, which read as clipping
# through the block — so it's gone. Kept as a no-op so the worlds'
# neighbour-refresh calls keep working without changes.
func refresh_u_collision() -> void:
	pass

func _apply_sprite() -> void:
	if item_data == null:
		return
	# Door: swap between the closed/open sprite (no sheet animation).
	if item_data.is_door:
		var door_tex: Texture2D = item_data.door_open_sprite if _door_open else item_data.door_closed_sprite
		if door_tex == null:
			door_tex = item_data.placeable_sprite if item_data.placeable_sprite != null else item_data.icon
		_sprite.texture = door_tex
		_sprite.hframes = 1
		_sprite.vframes = 1
		_sprite.flip_h  = false
		_stop_sheet_animation()
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
	var world: Node = _world()
	if world == null or _world_cell.x == -99999:
		return
	# A torch mounts to a solid neighbour. Worlds expose torch_support() for
	# this (caves count solid wall cells, not just placed blocks); fall back to
	# has_placed_block for any world that doesn't.
	var fn: StringName = &"torch_support" if world.has_method("torch_support") else &"has_placed_block"
	if not world.has_method(fn):
		return
	var left:  bool = bool(world.call(fn, _world_cell + Vector2i(-1, 0)))
	var right: bool = bool(world.call(fn, _world_cell + Vector2i( 1, 0)))
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
	# Same lost-release guard as player.gd _tick_attack_hold: opening a UI pauses
	# the tree, so the release during that pause never reaches _input and
	# _mouse_held would stay latched — resuming the break once the UI closes.
	if _mouse_held and not Global.is_left_action_held():
		_mouse_held = false
	# Once PNC locks a block, its cursor can move away without cancelling the
	# mining order or hiding the ring. Manual mining still requires hover.
	if not Global.pnc_hold_active:
		_update_hover()
	_tick_progress_expiry()
	_tick_wobble()
	if not _mouse_held or (not _hovered and not Global.pnc_hold_active) \
			or not _player_within_radius():
		_cancel_breaking()
		return
	# A hotbar/tool switch restarts the break immediately with the new tool's
	# duration, rather than keeping progress earned by the old tool.
	if _mouse_held and (_hovered or Global.pnc_hold_active):
		var tool_id: String = Global.held_tool_id()
		if _breaking and tool_id != _break_tool_id:
			_cancel_breaking()
			_break_elapsed  = 0.0
			_break_progress = 0.0
			_last_hit_ms    = -1
			_try_start_breaking()
		elif not _breaking:
			_try_start_breaking()
	# `_breaking` is the TOOL GATE — it is only ever set by a successful
	# _try_start_breaking(). WITHOUT this check a rejected click (bare hands, or
	# a non-pickaxe item) still latched _mouse_held, and _process kept feeding
	# delta into _add_break_progress until the stale/default _break_duration
	# (1.0s) elapsed — so a stone block broke with no tool at all. Every other
	# mining path (chest/station/object_item) already guards on _breaking here.
	if not _breaking:
		return
	_add_break_progress(delta)

# Adds damage (in seconds of break work) from one source — a held frame's
# delta or a click's flat CLICK_BREAK_SECONDS — then breaks when full.
func _add_break_progress(seconds: float) -> void:
	# Choke point: never advance a break that a valid tool did not start, no
	# matter which caller got here (this is what let bare hands break blocks).
	if not _breaking:
		return
	# Hold-to-mine and PNC both advance this every frame, so the player keeps
	# swinging the selected item/pickaxe until the block breaks.
	Global.swing_player_item()
	_break_elapsed  = minf(_break_elapsed + seconds, _break_duration)
	_break_progress = _break_elapsed / _break_duration if _break_duration > 0.0 else 1.0
	_last_hit_ms    = Time.get_ticks_msec()
	Global.report_break_progress(_break_progress, global_position, -26.0, self)
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
	Global.clear_break_progress(self)
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
	# Shared with the cave wall mining so both shake identically.
	_sprite.rotation = Global.block_wobble_rotation()

func _update_hover() -> void:
	_update_hover_at(Global.mouse_world(self))

func _update_hover_at(world_pos: Vector2) -> void:
	if _sprite.texture == null:
		_hovered = false
		return
	var mouse_local: Vector2 = to_local(world_pos)
	var half_w: float = (_sprite.texture.get_width()  / float(maxi(_sprite.hframes, 1))) * 0.5
	var half_h: float = (_sprite.texture.get_height() / float(maxi(_sprite.vframes, 1))) * 0.5
	_hovered = abs(mouse_local.x - _sprite.position.x) <= half_w \
		   and abs(mouse_local.y - _sprite.position.y) <= half_h \
		   and not Global.block_mode

func _draw() -> void:
	# The progress ring is drawn by BreakProgressOverlay, above every world
	# sprite, so this node does not draw it behind its own Sprite2D.
	pass

# ── Input ─────────────────────────────────────────────────────────
func _input(event: InputEvent) -> void:
	# A PNC synthetic press targets a world point that was already accepted by
	# the player's tap filter. Do not re-classify it as UI: on Android the
	# screen-position mapping can differ under canvas stretch, which made the
	# block reject the very press that should start its mining.
	if not event.has_meta("pnc_synthetic") and Global.is_mouse_event_over_ui(event):
		return
	if not _player_nearby or Global.any_ui_open() or Global.pause_menu_open:
		return
	# In build mode a plain click PLACES a block (world._input). SHIFT+click
	# still mines the block under the cursor — the world skips placement when
	# shift is held, so construction and demolition share one mode.
	if Global.block_mode and not Global.is_shift_held():
		return
	# PNC's synthetic press fires after the player has walked to the tapped
	# point. By then the real mouse/camera may have moved, leaving the cached
	# hover stale; the PNC touch cursor is still pinned to the ordered block, so
	# rebuild hover from that before deciding whether this click is ours.
	# Use this click's own screen position for the hover test. Android secondary
	# touches are bridged to mouse events and the shared touch cursor may point
	# at a previous order; event position is authoritative.
	if event is InputEventMouseButton \
			and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		# PNC already knows the ordered world point. Trust that over the
		# synthetic event's screen position, which can be stretched differently
		# on Android and used to make the block ignore its own mining press.
		if event.has_meta("pnc_synthetic") and Global.pnc_hold_active \
				and Global.mouse_override_active():
			_update_hover_at(Global.mouse_override_pos())
		else:
			_update_hover_at(Global.mouse_event_world(self, event))
	elif Global.pnc_hold_active:
		_update_hover()
	if not _hovered or not _player_within_radius():
		if _breaking:
			_cancel_breaking()
		return
	# A floor kept under a placed block is NOT the top block — it must not
	# consume clicks meant for the block on top (e.g. a door placed over a floor).
	if item_data != null and item_data.is_floor and not _is_top_block():
		return
	# A block that reacts to a PLAIN left-click (doors toggle open/closed;
	# bonfires toggle the respawn point) consumes it. SHIFT+click mines instead
	# (falls through to the mining path below, which supports click-spam/hold).
	if has_plain_click():
		var shift_held: bool = event is InputEventMouseButton \
			and (event as InputEventMouseButton).shift_pressed
		if not shift_held:
			if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
				if not get_viewport().is_input_handled():
					get_viewport().set_input_as_handled()
					on_plain_click()
			return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			# Extra safety alongside _hovered: if two blocks' sprites ever
			# overlap (large placeable art), only the first one in node
			# order consumes the click instead of both reacting to it.
			if get_viewport().is_input_handled():
				return
			get_viewport().set_input_as_handled()
			_try_start_breaking()
			# Only latch the hold when a valid tool actually started the break:
			# a rejected click must not leave _mouse_held on (see _process).
			_mouse_held = _breaking
			if _breaking:
				# Every fresh click is worth CLICK_BREAK_SECONDS of break
				# work, so spam clicking chips away just like holding does.
				_add_break_progress(CLICK_BREAK_SECONDS)
		else:
			# Tap-to-control keeps its synthetic hold through the finger-up
			# event so continuous mining is not cancelled immediately.
			if Global.pnc_hold_active:
				return
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
	var slot: Variant = Global.get_hotbar_item()
	# An empty hand is fine now: bare-handed mining is allowed (slow, no drop).
	var held_data: ItemData = null
	if slot != null and (slot as Dictionary).has("data"):
		held_data = (slot as Dictionary)["data"] as ItemData
	var is_axe: bool      = held_data != null and held_data.axe_level > 0
	var is_pickaxe: bool  = held_data != null and held_data.is_pickaxe
	var is_wood_block: bool = item_data != null and item_data.wooden_block
	# Torches are wooden auxiliary decor but historically were not tagged
	# wooden_block; allow an axe to chop them without imposing the pickaxe
	# wood penalty on an otherwise ordinary cheap torch.
	var axe_can_chop: bool = is_wood_block or (item_data != null and item_data.is_torch)
	var block_lvl: int = item_data.block_level if item_data != null else 0

	_barehanded = false
	if is_axe and axe_can_chop:
		# Axes chop wooden blocks and torches — no pickaxe tier needed. Speed
		# comes from the axe's hidden wooden-block bonus (LV1 +0.3x, LV2 +0.6x,
		# LV3 +1.0x). Spam clicking works normally.
		_break_duration = maxf(0.1, float(block_lvl)) / (1.0 + held_data.axe_wood_block_bonus())
	elif is_pickaxe:
		var min_lvl: int = item_data.min_pickaxe_level if item_data != null else 0
		# Mining tier comes from the PICKAXE only (Global.held_pickaxe_level
		# reads ItemData.is_pickaxe) — reading held_data.pickaxe_level directly
		# let axes/swords, which carry stray pickaxe_level values, mine here.
		if Global.held_pickaxe_level() < min_lvl:
			return  # pickaxe tier too low for this block
		# Wood-tagged blocks penalise a pickaxe by 75% (speed x0.25). The
		# penalty is applied to the block's HARDNESS rather than to the clamped
		# seconds: a high pickaxe tier already floors the time at 0.1s, so
		# multiplying afterwards would leave iron/diamond pickaxes untouched and
		# the penalty would never bite.
		var hardness: float = float(block_lvl)
		if is_wood_block:
			hardness /= (1.0 - PICKAXE_WOOD_PENALTY)
		_break_duration = maxf(0.1, hardness - float(Global.held_mining_level()))
	else:
		# BARE HANDS (or an unrelated item). The block can still be broken, but
		# it takes BAREHAND_TIME_MULT as long and yields nothing — the pickaxe
		# tier is what EARNS the block, not what allows chipping it.
		_barehanded     = true
		_break_duration = maxf(0.1, float(block_lvl) * BAREHAND_TIME_MULT)
	# The swing animation plays for ANY item used to break — route through the
	# player so it fires even though this block consumed the click input.
	if Global.player_node != null and Global.player_node.has_method("swing_held_item"):
		Global.player_node.call("swing_held_item")
	# Keep damage accumulated within the persist window ? a spam clicker (or
	# a player who walked away and came back) resumes where they left ? but a
	# changed hotbar tool always restarts the bar.
	var tool_id: String = Global.held_tool_id()
	if _break_tool_known and tool_id != _break_tool_id:
		_break_elapsed  = 0.0
		_break_progress = 0.0
		_last_hit_ms    = -1
	_break_tool_id = tool_id
	_break_tool_known = true
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
	Global.clear_break_progress(self)
	_sprite.rotation = 0.0

func _break() -> void:
	_breaking = false
	Global.clear_break_progress(self)
	var world: Node = _world()
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
	# Bare-handed breaks still destroy the block (see _try_start_breaking) but
	# yield NO item and don't advance mining missions — the tool tier is what
	# EARNS the block, not what allows chipping it away.
	CrashLogger.event("WORLD", "break %s cell=(%d, %d) barehanded=%s" % [
		item_data.item_name if item_data != null else "?",
		_world_cell.x, _world_cell.y, _barehanded])
	if item_data != null and not _barehanded:
		# Connected-torch variants are visual ItemData resources; they must
		# return the normal torch item, not their own dev/variant identity.
		var drop_data: ItemData = item_data
		if item_data.is_torch and item_data.torch_drop_item != null:
			drop_data = item_data.torch_drop_item
		# Mining-progress missions keyed off the block that was broken.
		Global.track_mining(drop_data)
		var drop: Node = ITEM_SCENE.instantiate() as Node
		drop.call("set_item_data", drop_data)
		# World itself (via _world_ref, falling back to Global.world_node)
		# rather than get_parent() — see chest_block.gd's _break() for why.
		var drop_parent: Node = _world()
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

func _on_gameplay_input_cancelled() -> void:
	_mouse_held = false
	if _breaking:
		_cancel_breaking()
