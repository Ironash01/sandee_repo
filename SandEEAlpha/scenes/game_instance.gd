extends Node2D

const C_PANEL  := Color(0.08, 0.10, 0.20, 0.97)
const C_BORDER := Color(0.22, 0.32, 0.58, 1.00)
const C_TITLE  := Color(0.80, 0.90, 1.00, 1.00)
const C_MUTED  := Color(0.55, 0.65, 0.85, 1.00)

# preload (not class_name) so the debug chat console can be built even before
# the editor has re-scanned/registered the new script's class.
const CHAT_CONSOLE_SCRIPT: Script = preload("res://scripts/chat_console.gd")
const MINIMAP_SCRIPT: Script = preload("res://scripts/minimap.gd")
# Left-middle LUA status HUD (what each placed LUA is doing; click for all).
const LUA_STATUS_SCRIPT: Script = preload("res://scripts/lua_status_ui.gd")
# Touch tap-tooltip popup (built-in tooltips are hover-only).
const TOOLTIP_TAP_SCRIPT: Script = preload("res://scripts/tooltip_tap.gd")
# Top-centre gameplay notifications (fishing/farming/deaths/…). The debug chat
# keeps command output only.
const NOTIFICATION_HUD_SCRIPT: Script = preload("res://scripts/notification_hud.gd")
# Optional top-right FPS readout (Settings → Display → Show FPS).
const FPS_OVERLAY_SCRIPT: Script = preload("res://scripts/fps_overlay.gd")
# Desktop contextual cursor set (the approved 24x24 cursor draft).
const CURSOR_MANAGER_SCRIPT: Script = preload("res://scripts/cursor_manager.gd")
# High-layer world-space mining progress ring (always above world sprites).
const BREAK_OVERLAY_SCRIPT: Script = preload("res://scripts/break_progress_overlay.gd")
# Android touch HUD (joystick + action buttons + tap-to-interact). Only added
# on mobile; the desktop interface stays exactly as it is.
const MOBILE_UI_SCRIPT: Script = preload("res://scripts/mobile_ui.gd")
const TUTORIAL_GUIDE_SCRIPT: Script = preload("res://scripts/tutorial_guide.gd")

@onready var pause_menu: Control         = $CanvasLayer/PauseMenu
@onready var pause_btn:  Button          = $CanvasLayer/PauseButton
@onready var _world:     Node2D          = $World  # the overworld — kept alive off-tree while in a cave, never freed
@onready var _player:    CharacterBody2D = $Player

var _loading_screen: CanvasLayer = null
var _loading_root:   Control     = null
var _loading_label:  Label       = null
var _loading_bar:    ProgressBar = null
var _loading_progress: float     = 0.0
var _death_overlay:  ColorRect   = null
var _cave_world:      CaveWorld  = null
var _pixie_cave_world: PixieCaveWorld = null
var _dungeon_world:   DungeonWorld = null
# Visited cave worlds are kept alive off-tree (like the overworld) so their
# runtime state survives re-entry; per-cave snapshots handle save/load.
var _cave_instances: Dictionary = {}   # state_key -> CaveWorld/PixieCaveWorld
var _cave_explored: Dictionary = {}    # state_key -> Dictionary[Vector2i,bool]
var _active_cave_key: String = ""
var _transitioning: bool = false
# Full-screen fade used when swapping the world for a cave/pixie cave/dungeon
# (and back), so those transitions read as a deliberate scene change.
var _transition_overlay: CanvasLayer = null
# Low layer holding the BACKGROUND HUD (minimap, quest list, pause button).
# Every panel's full-screen dim overlay sits on a higher layer, so opening a
# station/furnace/chest dims this along with the world. The hotbar is NOT here —
# it stays on $CanvasLayer (10) so it remains bright and draggable on top.
var _hud_backdrop: CanvasLayer = null
var _mobile_ui: CanvasLayer = null
var _notification_hud: CanvasLayer = null
var _break_layer: CanvasLayer = null
var _cursor_manager: Node = null
var _tutorial_guide: Node = null

func _ready() -> void:
	# Honour the player's saved window/fullscreen choice instead of forcing
	# fullscreen (see Global.apply_display_mode — a no-op on mobile).
	Global.apply_display_mode()
	# UI scale is global + responsive. Re-assert it when the gameplay scene
	# loads so every panel rebuilt here uses the current viewport metrics.
	Global.refresh_ui_scale()
	Global.game_node = self
	CrashLogger.event("GAME", "ready version=%s slot=%d mobile=%s" % [
		Global.game_version(), Global.active_save_slot, Global.is_mobile()])
	# A fresh game scene must never inherit a pause/UI state from the previous
	# one (quit-to-menu with a UI open, a leaked open_ui(), etc).
	Global.reset_pause_state()

	# Background HUD layer (map + quest list + pause button). Layer 1 is BELOW
	# every panel (2+), so a panel's dim overlay covers and dims it along with
	# the world — the hotbar stays on $CanvasLayer (10) above the panels.
	_hud_backdrop = CanvasLayer.new()
	_hud_backdrop.name         = "HudBackdrop"
	_hud_backdrop.layer        = 1
	_hud_backdrop.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_hud_backdrop)
	pause_btn.reparent(_hud_backdrop)

	pause_btn.pressed.connect(pause_menu.show_menu)
	# The pause menu + settings are MODALS: move them onto their own CanvasLayer
	# above every panel (crafting/chest/smelting/editor = layer 2-12, altar and
	# portal confirm dialogs = 30) so opening the menu over a station shows the
	# MENU on top instead of the station. Chat stays above at 40.
	var modal_layer := CanvasLayer.new()
	modal_layer.layer        = 35
	modal_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(modal_layer)
	pause_menu.reparent(modal_layer)
	_style_pause_button()
	if not Global.ui_scale_changed.is_connected(_on_hud_ui_scale_changed):
		Global.ui_scale_changed.connect(_on_hud_ui_scale_changed)
	if not Global.inventory_toggled.is_connected(_on_inventory_visibility_changed):
		Global.inventory_toggled.connect(_on_inventory_visibility_changed)
	if not Global.modal_hud_changed.is_connected(_on_modal_hud_changed):
		Global.modal_hud_changed.connect(_on_modal_hud_changed)
	_start_autosave()
	_add_mission_ui()

	# Debug chat console (upper-left log + command input). Built in code and
	# added under the UI CanvasLayer, so it layers above the world like the
	# pause button/hotbar and inherits the layer's PROCESS_MODE_ALWAYS.
	$CanvasLayer.add_child(CHAT_CONSOLE_SCRIPT.new())
	# Bottom-left minimap (click / M opens the full map). Background HUD layer,
	# so panels dim it.
	_hud_backdrop.add_child(MINIMAP_SCRIPT.new())
	# Left-middle LUA status panel (3 most-current LUAs; click to expand to all).
	_hud_backdrop.add_child(LUA_STATUS_SCRIPT.new())
	# Optional top-right FPS counter; starts hidden for every existing install.
	_hud_backdrop.add_child(FPS_OVERLAY_SCRIPT.new())
	# Tap tooltips (touch screens have no hover) — owns its own high layer.
	add_child(TOOLTIP_TAP_SCRIPT.new())
	# Top-centre gameplay notifications (fishing, farming, deaths, warnings).
	_notification_hud = NOTIFICATION_HUD_SCRIPT.new() as CanvasLayer
	add_child(_notification_hud)
	# Mining ring lives above all world sprites/HUD panels; the object scripts
	# only report progress, they no longer draw the world ring themselves.
	_break_layer = CanvasLayer.new()
	_break_layer.name = "BreakProgressLayer"
	_break_layer.layer = 20
	_break_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_break_layer)
	_break_layer.add_child(BREAK_OVERLAY_SCRIPT.new())
	# Contextual desktop cursor set. Lives under Game so it survives dungeon/cave
	# world swaps; it is disabled on Android/headless by the manager itself.
	_cursor_manager = CURSOR_MANAGER_SCRIPT.new()
	_cursor_manager.name = "CursorManager"
	add_child(_cursor_manager)

	# Android-only touch HUD. Global.is_mobile() uses Godot's "mobile" feature
	# tag (Android/iOS), NOT a resolution guess, so a small desktop window still
	# gets the normal keyboard/mouse interface.
	if Global.is_mobile():
		_mobile_ui = MOBILE_UI_SCRIPT.new() as CanvasLayer
		add_child(_mobile_ui)

	_setup_death_overlay()

	# Freeze the player until the world is fully generated.
	_player.process_mode = Node.PROCESS_MODE_DISABLED
	_player.visible      = false

	# Show loading screen before any generation work starts.
	_show_loading_screen()

	# World._ready() already set Global.world_node and deferred generation,
	# so signals are safe to connect here before that deferred work fires.
	_world.generation_status_changed.connect(_on_generation_status)
	_world.generation_complete.connect(_on_generation_complete)

# ── Death dim overlay ──────────────────────────────────────────────
# A full-screen black overlay that fades in when the player dies (Global's
# _handle_player_death emits player_died, teleports to spawn, restores HP),
# then fades back out.
func _setup_death_overlay() -> void:
	_death_overlay = ColorRect.new()
	_death_overlay.color = Color(0, 0, 0, 0)
	_death_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_death_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	$CanvasLayer.add_child(_death_overlay)
	Global.player_died.connect(_on_player_died)

func _on_player_died(_death_position: Vector2 = Vector2.ZERO) -> void:
	if _death_overlay == null:
		return
	var tween := create_tween()
	tween.tween_property(_death_overlay, "color:a", 0.75, 0.4)
	tween.tween_interval(0.9)
	tween.tween_property(_death_overlay, "color:a", 0.0, 1.2)

# ── Loading screen ────────────────────────────────────────────────────
func _show_loading_screen() -> void:
	_loading_screen = CanvasLayer.new()
	_loading_screen.layer = 128  # above HUD and pause menu
	add_child(_loading_screen)

	# One root Control lets the whole loading screen fade out smoothly over the
	# already-generated world instead of disappearing in a single hard frame.
	_loading_root = Control.new()
	_loading_root.name = "LoadingRoot"
	_loading_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_loading_root.mouse_filter = Control.MOUSE_FILTER_STOP
	_loading_root.process_mode = Node.PROCESS_MODE_ALWAYS
	_loading_screen.add_child(_loading_root)

	var bg := ColorRect.new()
	bg.color = Color(0.05, 0.07, 0.14, 1.0)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	_loading_root.add_child(bg)

	# Center container so content sits in the middle of the screen.
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	Global.apply_safe_area(center)
	_loading_root.add_child(center)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", int(16 * Global.ui_scale))
	center.add_child(vbox)

	var title := Label.new()
	title.text = "SandEE Alpha"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size",
		Global.ui_type_size(Global.UI_TYPE_TITLE))
	title.add_theme_color_override("font_color", C_TITLE)
	vbox.add_child(title)

	_loading_label = Label.new()
	_loading_label.text = "Initializing..."
	_loading_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_loading_label.add_theme_font_size_override("font_size",
		Global.ui_type_size(Global.UI_TYPE_BODY))
	_loading_label.add_theme_color_override("font_color", C_MUTED)
	vbox.add_child(_loading_label)

	_loading_bar = ProgressBar.new()
	_loading_bar.min_value = 0.0
	_loading_bar.max_value = 100.0
	_loading_bar.value = 0.0
	_loading_bar.show_percentage = false
	_loading_bar.custom_minimum_size = Vector2(
		int(420 * Global.ui_scale), maxi(10, int(14 * Global.ui_scale)))
	_loading_bar.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var bar_bg := StyleBoxFlat.new()
	bar_bg.bg_color = Color(0.03, 0.05, 0.10, 1.0)
	bar_bg.border_color = C_BORDER
	bar_bg.set_border_width_all(1)
	bar_bg.set_corner_radius_all(int(4 * Global.ui_scale))
	var bar_fill := StyleBoxFlat.new()
	bar_fill.bg_color = C_TITLE
	bar_fill.set_corner_radius_all(int(4 * Global.ui_scale))
	_loading_bar.add_theme_stylebox_override("background", bar_bg)
	_loading_bar.add_theme_stylebox_override("fill", bar_fill)
	vbox.add_child(_loading_bar)

func _on_generation_status(status: String) -> void:
	if is_instance_valid(_loading_label):
		_loading_label.text = status
	var target := _loading_progress_for_status(status)
	_loading_progress = maxf(_loading_progress, target)
	if is_instance_valid(_loading_bar):
		_loading_bar.value = _loading_progress * 100.0


func _loading_progress_for_status(status: String) -> float:
	var lower := status.to_lower()
	if lower.contains("chunking"):
		return 0.04
	if lower.contains("terrain"):
		return 0.14
	if lower.contains("forest") or lower.contains("tree"):
		return 0.40
	if lower.contains("grass"):
		var pct := 0.0
		var marker := status.find("%")
		if marker > 0:
			var head := status.substr(0, marker).strip_edges()
			var i := head.length() - 1
			while i >= 0 and head[i] >= "0" and head[i] <= "9":
				i -= 1
			if i < head.length() - 1:
				pct = clampf(float(head.substr(i + 1).to_int()), 0.0, 100.0)
		return 0.72 + 0.26 * (pct / 100.0)
	return minf(0.68, _loading_progress + 0.03)


func _on_generation_complete() -> void:
	if is_instance_valid(_loading_bar):
		_loading_bar.value = 100.0
	if is_instance_valid(_loading_label):
		_loading_label.text = "Ready"
	# Show the generated world behind the fading loader, but keep the player
	# frozen until the fade completes so input cannot act through the overlay.
	_player.visible = true
	_player.process_mode = Node.PROCESS_MODE_DISABLED

	# World is fully generated - safe to create the initial save now.
	if Global.active_save_slot > 0 and not Global.has_save(Global.active_save_slot):
		Global.save_game(Global.active_save_slot)

	if is_instance_valid(_loading_root):
		var tween := create_tween()
		tween.tween_property(_loading_root, "modulate:a", 0.0, 0.55) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		tween.tween_callback(_finish_loading_fade)
	else:
		_finish_loading_fade()


func _finish_loading_fade() -> void:
	if is_instance_valid(_loading_screen):
		_loading_screen.queue_free()
	_loading_screen = null
	_loading_root = null
	_loading_label = null
	_loading_bar = null
	_loading_progress = 0.0
	if is_instance_valid(_player):
		_player.process_mode = Node.PROCESS_MODE_INHERIT
	_setup_tutorial()


func _setup_tutorial() -> void:
	if Global.tutorial_completed or _tutorial_guide != null:
		return
	if Global.is_in_dungeon or _cave_world != null or _pixie_cave_world != null:
		return
	if _world == null or not is_instance_valid(_world):
		return
	var spawn := Vector2.ZERO
	if _world.has_method("_world_spawn_pos"):
		spawn = _world.call("_world_spawn_pos") as Vector2
	_tutorial_guide = TUTORIAL_GUIDE_SCRIPT.new()
	_tutorial_guide.name = "TutorialGuide"
	# The onboarding director owns the dialogue/HUD and must survive world
	# swaps into the guided dungeon. NPC actors are parented to the overworld
	# by the director itself.
	add_child(_tutorial_guide)
	_tutorial_guide.call("setup", spawn, _world)

# ── Cave entry/exit ─────────────────────────────────────────────────────
# Swaps $World out for a CaveWorld/PixieCaveWorld rather than a full
# change_scene_to_file — Player/camera/Hotbar/PauseMenu all live as $World's
# siblings here in Game, so a full scene change would destroy them (this is
# also why the old Dungeon Portal system, which did use change_scene_to_file
# against the legacy dungeon scenes, never worked — the legacy scenes
# are gone now, replaced by code-generated DungeonWorld). The overworld
# $World is only removed from the tree, never freed, so nothing about it
# needs to regenerate on return. Cave instances follow the same rule: they
# are cached off-tree so re-entry keeps their live runtime state.
func enter_cave(portal: CavePortal) -> void:
	if _transitioning or _cave_world != null or _pixie_cave_world != null or _dungeon_world != null:
		# Refusing the transition must not leave the portal permanently locked.
		if portal != null and portal.has_method("reset_after_exit"):
			portal.call("reset_after_exit")
		return
	_run_scene_transition(Callable(self, "_do_enter_cave").bind(portal), "Entering cave...")

# Previously visited caves are re-added from the cache with their live state;
# new/loaded caves generate from the stable entrance seed, then restore the
# saved per-cave state.
func _do_enter_cave(portal: CavePortal) -> void:
	Global.is_in_dungeon = false
	var key: String = portal.state_key() if portal != null and portal.has_method("state_key") else ""
	var return_position: Vector2 = _player.global_position
	var cached: Variant = _cave_instances.get(key) if key != "" else null
	CrashLogger.event("WORLD", "enter cave key=%s type=%s cached=%s at=(%.1f, %.1f)" % [
		key if key != "" else "<none>",
		str(portal.cave_type) if portal != null else "?",
		cached != null and is_instance_valid(cached), return_position.x, return_position.y])
	remove_child(_world)
	var node: Node = null
	if cached != null and is_instance_valid(cached):
		node = cached as Node
		if node is PixieCaveWorld:
			_pixie_cave_world = node as PixieCaveWorld
			_cave_world = null
		else:
			_cave_world = node as CaveWorld
			_pixie_cave_world = null
		node.set("overworld_return_position", return_position)
		add_child(node)
		move_child(node, 0)
	else:
		if portal.cave_type == "pixie":
			var pixie := PixieCaveWorld.new()
			pixie.name = "World"
			node = pixie
			_pixie_cave_world = pixie
			_cave_world = null
		else:
			var cave := CaveWorld.new()
			cave.name = "World"
			node = cave
			_cave_world = cave
			_pixie_cave_world = null
		add_child(node)
		move_child(node, 0)
		node.call("setup", portal.cave_seed, return_position)
		if key != "":
			_cave_instances[key] = node
			var saved: Variant = Global.cave_states.get(key, {})
			if saved is Dictionary and not (saved as Dictionary).is_empty():
				node.call("apply_state", saved)

	_active_cave_key = key
	_restore_cave_exploration(key)
	for child in node.get_children():
		if child is CavePortal and (child as CavePortal).mode == CavePortal.Mode.EXIT:
			child.call("reset_after_exit")
	Global.world_node       = node
	_player.global_position = node.call("get_player_spawn_position")
	Global.reset_pause_state()

func exit_cave() -> void:
	if _transitioning:
		return
	if _pixie_cave_world != null or _cave_world != null:
		_run_scene_transition(Callable(self, "_do_exit_cave"), "Leaving cave...")

# The cave instance is snapshotted and kept alive off-tree, never freed on
# exit. Re-entering the same entrance restores the live runtime state; the
# snapshot feeds save/load across restarts.
func _do_exit_cave() -> void:
	var node: Node = null
	if _pixie_cave_world != null:
		node = _pixie_cave_world
	elif _cave_world != null:
		node = _cave_world
	if node == null:
		return

	var rp: Variant = node.get("overworld_return_position")
	var return_position: Vector2 = rp if rp is Vector2 else _player.global_position
	var key := _active_cave_key
	CrashLogger.event("WORLD", "exit cave key=%s type=%s to=(%.1f, %.1f)" % [
		key if key != "" else "<none>", node.get_class(), return_position.x, return_position.y])
	if key != "":
		_cave_explored[key] = Global.explored_cave_tiles.duplicate()
		if node.has_method("snapshot_state"):
			var snap: Dictionary = node.call("snapshot_state")
			snap["explored"] = _explored_to_array(_cave_explored[key])
			Global.cave_states[key] = snap
		_cave_instances[key] = node
		remove_child(node)
	else:
		remove_child(node)
		node.queue_free()
	_cave_world = null
	_pixie_cave_world = null
	_active_cave_key = ""
	Global.explored_cave_tiles.clear()

	add_child(_world)
	move_child(_world, 0)
	Global.world_node       = _world
	_player.global_position = return_position
	Global.reset_pause_state()
	# Re-arm BOTH cave/pixie entrances after the overworld returns.
	if _world.has_method("reset_cave_portals"):
		_world.call("reset_cave_portals")
	if Global.active_save_slot > 0:
		Global.save_game(Global.active_save_slot)

func get_cave_states() -> Dictionary:
	var out: Dictionary = {}
	# Preserve saved states for caves not instantiated this session.
	for key in Global.cave_states:
		if Global.cave_states[key] is Dictionary:
			out[key] = (Global.cave_states[key] as Dictionary).duplicate(true)
	for key in _cave_instances:
		var node_ref: Variant = _cave_instances[key]
		if not is_instance_valid(node_ref):
			continue
		var node := node_ref as Node
		if not node.is_inside_tree():
			continue   # cached snapshot already lives in Global.cave_states
		if node.has_method("snapshot_state"):
			var snap: Dictionary = node.call("snapshot_state")
			var explored: Dictionary = Global.explored_cave_tiles if key == _active_cave_key \
				else (_cave_explored.get(key, {}) as Dictionary)
			snap["explored"] = _explored_to_array(explored)
			out[key] = snap
	return out

func _restore_cave_exploration(key: String) -> void:
	if key != "" and _cave_explored.has(key):
		Global.explored_cave_tiles = (_cave_explored[key] as Dictionary).duplicate()
	elif key != "" and Global.cave_states.has(key):
		var state: Variant = Global.cave_states[key]
		if state is Dictionary:
			Global.explored_cave_tiles = _explored_from_array(
				(state as Dictionary).get("explored", []))
		else:
			Global.explored_cave_tiles.clear()
	else:
		Global.explored_cave_tiles.clear()

func _explored_to_array(explored: Dictionary) -> Array:
	var out: Array = []
	for cell in explored:
		var c := cell as Vector2i
		out.append([int(c.x), int(c.y)])
	return out

func _explored_from_array(values: Variant) -> Dictionary:
	var out: Dictionary = {}
	if values is Array:
		for entry in values:
			if entry is Array and (entry as Array).size() >= 2:
				out[Vector2i(int(entry[0]), int(entry[1]))] = true
	return out

func _exit_tree() -> void:
	CrashLogger.event("GAME", "scene exit slot=%d" % Global.active_save_slot)
	# Cached cave worlds are orphans by design; free them with the Game scene.
	for key in _cave_instances:
		var node_ref: Variant = _cave_instances[key]
		if is_instance_valid(node_ref):
			var node := node_ref as Node
			if node.get_parent() == null:
				node.free()   # cached cave nodes are orphans; free immediately
	_cave_instances.clear()
	# Abrupt scene changes can happen while a structure holds the overworld
	# off-tree; don't leak it if the Game itself is going away.
	if _world != null and is_instance_valid(_world) and _world.get_parent() == null:
		_world.free()


# ── Dungeon entry (mission-accept portal) ─────────────────────────────────
# dungeon_portal.gd dispatches here with the dungeon's index (matching
# Global.missions dungeon_index). Same swap-out-$World pattern as
# enter_cave — the overworld stays alive off-tree, and the dungeon is its own
# TileMapLayer world (DungeonWorld) built in code from the mission's
# DungeonMissionData. The layout generates from a seed rolled once on the
# first mission accept (Global.get_or_create_dungeon_seed), so re-entering
# always reproduces the same dungeon.
func enter_dungeon(dungeon_index: int) -> void:
	if _transitioning or _cave_world != null or _pixie_cave_world != null or _dungeon_world != null:
		return
	var mission: DungeonMissionData = Global.get_dungeon_mission_for_index(dungeon_index)
	if mission == null:
		push_warning("enter_dungeon: no DungeonMissionData for index %d" % dungeon_index)
		CrashLogger.event("WORLD", "enter dungeon refused index=%d (no mission)" % dungeon_index)
		return
	CrashLogger.event("WORLD", "enter dungeon index=%d name=%s seed=%d" % [
		dungeon_index, mission.mission_name,
		Global.get_or_create_dungeon_seed(dungeon_index)])
	_run_scene_transition(Callable(self, "_do_enter_dungeon").bind(dungeon_index, mission),
		"Entering dungeon...")

# Immediate swap (used by _run_scene_transition). Same swap-out-$World pattern
# as _do_enter_cave — the overworld stays alive off-tree, and the dungeon is its
# own TileMapLayer world (DungeonWorld) built in code from the mission's
# DungeonMissionData. The layout generates from a seed rolled once on the first
# mission accept (Global.get_or_create_dungeon_seed), so re-entering always
# reproduces the same dungeon.
func _do_enter_dungeon(dungeon_index: int, mission: DungeonMissionData) -> void:
	var return_position: Vector2 = _player.global_position
	remove_child(_world)

	_dungeon_world = DungeonWorld.new()
	_dungeon_world.name = "World"
	add_child(_dungeon_world)
	move_child(_dungeon_world, 0)
	_dungeon_world.setup(dungeon_index, mission,
		Global.get_or_create_dungeon_seed(dungeon_index), _world, return_position)

	Global.world_node       = _dungeon_world
	_player.global_position = _dungeon_world.get_player_spawn_pos()
	Global.is_in_dungeon = true
	Global.dungeon_entered.emit(dungeon_index)
	if Global.block_mode:
		Global.block_mode = false
		Global.block_mode_changed.emit(false)
	# Quest trigger: entering any dungeon counts once (complete_mission is idempotent).
	Global.complete_mission("enter_dungeon")
	# A portal/dialog from the overworld must not keep the dungeon paused.
	Global.reset_pause_state()

func exit_dungeon() -> void:
	if _transitioning:
		return
	if _dungeon_world != null:
		_run_scene_transition(Callable(self, "_do_exit_dungeon"), "Leaving dungeon...")

# Immediate swap (used by _run_scene_transition, and directly by the death /
# menu-cleanup paths where the world must be restored synchronously).
func _do_exit_dungeon() -> void:
	if _dungeon_world == null:
		return
	var return_position: Vector2 = _dungeon_world.overworld_return_position
	CrashLogger.event("WORLD", "exit dungeon index=%d to=(%.1f, %.1f)" % [
		int(_dungeon_world.get("_dungeon_index")), return_position.x, return_position.y])
	remove_child(_dungeon_world)
	_dungeon_world.queue_free()
	_dungeon_world = null

	# Restore the notification log to its default top-left position.
	_reset_chat_position()

	add_child(_world)
	move_child(_world, 0)
	Global.world_node       = _world
	_player.global_position = return_position
	# Restore is_in_dungeon, build mode (with a HUD resync) and the pause state
	# AFTER the overworld is back in the tree.
	Global.restore_overworld_interaction_state()
	# The player returns to the entrance tile; remove any grass overlapping the
	# sprite/collision area that may have grown since the entrance was placed.
	if _world.has_method("clear_grass_around"):
		_world.call("clear_grass_around", _player.global_position, 2)

	# Persist the clear right away — entrance removal + reward + stars all
	# need to survive a quit that never reaches the 1-minute autosave. The
	# overworld is back in the tree now, so the save captures real world data.
	if Global.active_save_slot > 0:
		Global.save_game(Global.active_save_slot)

func _reset_chat_position() -> void:
	for c in $CanvasLayer.get_children():
		if c is ChatConsole:
			if c.has_method("reset_interaction_state"):
				c.call("reset_interaction_state")
			if c.has_method("reset_position"):
				c.call("reset_position")
			break

# Cleanly leave any active cave/pixie cave/dungeon before quitting to the main
# menu. Tearing the complex cave node tree down through the normal exit path —
# instead of letting change_scene free it abruptly mid-pause (while the
# overworld sits orphaned off-tree) — avoids the "quit to menu inside caves
# freezes" hang. Also restores the player to the entrance before the save.
func cleanup_for_menu() -> void:
	# Must be synchronous: the pause menu changes scenes immediately after
	# this call, so an async fade transition would leave the overworld
	# orphaned off-tree and skip the cave-state snapshot.
	if _pixie_cave_world != null or _cave_world != null:
		_do_exit_cave()
	elif _dungeon_world != null:
		_do_exit_dungeon()

# Death respawn: leave any active cave/pixie cave/dungeon (so the overworld is
# restored and the player isn't stuck inside the structure), then return the
# OVERWORLD's world-spawn point. Dying anywhere — cave, dungeon, or overworld —
# always puts the player back at the true world spawn.
func get_world_spawn_position() -> Vector2:
	# Respawn must have the overworld back synchronously before the caller
	# places the player; an async transition would later overwrite the
	# respawn position with the structure's return position.
	if _pixie_cave_world != null or _cave_world != null:
		_do_exit_cave()
	elif _dungeon_world != null:
		_do_exit_dungeon()
	if _world != null and _world.has_method("_world_spawn_pos"):
		return _world.call("_world_spawn_pos") as Vector2
	return Vector2.ZERO

# ── Autosave ──────────────────────────────────────────────────────────
func _add_mission_ui() -> void:
	var ui: Control = load("res://scripts/mission_ui.gd").new() as Control
	# Quest list lives on the background HUD layer so panels dim it.
	if _hud_backdrop != null:
		_hud_backdrop.add_child(ui)
	else:
		$CanvasLayer.add_child(ui)

# Automatic crash protection: write the active world to its save slot once a
# minute while playing. Saves are skipped until a slot exists and while the
# loading screen is up (an empty world snapshot must never overwrite a good
# save). Global.save_game() writes atomically, so a crash mid-save can only
# leave a .tmp/.bak file, never a truncated save.
const AUTOSAVE_INTERVAL_SEC: float = 60.0

func _start_autosave() -> void:
	var timer := Timer.new()
	timer.name = "AutosaveTimer"
	timer.wait_time = AUTOSAVE_INTERVAL_SEC
	timer.autostart = true
	# Keep ticking while a menu/panel pauses the tree — a crash while the player
	# is in a menu should still have a recent save.
	timer.process_mode = Node.PROCESS_MODE_ALWAYS
	timer.timeout.connect(_on_autosave)
	add_child(timer)

func _on_autosave() -> void:
	_save_if_safe()

# Shared save guard for the timer and Android lifecycle interruptions. Never
# snapshot a half-built world (initial generation / scene transition), and
# never save while the player is dead (Global handles respawn separately).
func _save_if_safe() -> void:
	if Global.active_save_slot <= 0:
		return
	if _loading_screen != null and is_instance_valid(_loading_screen) and _loading_screen.visible:
		return
	if Global.world_node == null or not is_instance_valid(Global.world_node):
		return
	if Global.player_is_dead:
		return
	Global.save_game(Global.active_save_slot)

func _notification(what: int) -> void:
	if not Global.is_mobile():
		return
	# Android can kill a paused app without warning. Persist the active world on
	# pause/focus loss; the atomic save path makes this safe to do at any time.
	if what == NOTIFICATION_APPLICATION_PAUSED or what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		_save_if_safe()

# What a save should persist: the player's spawn position + the OVERWORLD's
# world data. When the player saves while inside a cave/pixie cave/dungeon,
# their live position is in structure coordinates that don't exist on the
# overworld — so instead we save the overworld's data and the structure's
# overworld_return_position (where the player stood when they entered, i.e.
# right outside the entrance). On "Continue" the game loads the overworld and
# spawns them just outside the structure's entrance.
func get_overworld_save_context() -> Dictionary:
	var active_structure: Node2D = null
	if _cave_world != null:
		active_structure = _cave_world
	elif _pixie_cave_world != null:
		active_structure = _pixie_cave_world
	elif _dungeon_world != null:
		active_structure = _dungeon_world
	var world_data: Dictionary = {}
	if _world != null and _world.has_method("get_world_save_data"):
		world_data = _world.call("get_world_save_data")
	if active_structure != null:
		return {
			"player_pos": active_structure.overworld_return_position,
			"world_data": world_data,
		}
	return {
		"player_pos": _player.global_position,
		"world_data": world_data,
	}

# ── Scene transition fade ────────────────────────────────────────────────
# A full-screen fade-to-black loading transition used when swapping the world
# for a cave/pixie cave/dungeon (and back). Fades in a black overlay with a
# status label, runs the callback (which swaps $World) while fully black, then
# fades back out. The swap is synchronous but the fade makes it read as a
# deliberate scene change rather than a hard cut.
func _run_scene_transition(callback: Callable, label_text: String) -> void:
	if _transitioning:
		return
	_transitioning = true
	var layer := CanvasLayer.new()
	layer.layer = 130  # above the loading screen and HUD
	add_child(layer)
	_transition_overlay = layer

	var bg := ColorRect.new()
	bg.color = Color(0.0, 0.0, 0.0, 0.0)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(bg)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	Global.apply_safe_area(center)
	layer.add_child(center)
	var label := Label.new()
	label.text = label_text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", Global.ui_font_size(18))
	label.add_theme_color_override("font_color", C_TITLE)
	center.add_child(label)

	var tween := create_tween()
	tween.tween_property(bg, "color:a", 1.0, 0.28)
	tween.tween_callback(func() -> void:
		callback.call()
	)
	tween.tween_interval(0.15)
	tween.tween_property(bg, "color:a", 0.0, 0.35)
	tween.tween_callback(func() -> void:
		_transitioning = false
		layer.queue_free()
		_transition_overlay = null
	)

# ── Pause button styling ──────────────────────────────────────────────
func _on_inventory_visibility_changed(is_open: bool) -> void:
	# Inventory is a full modal. Hide every gameplay HUD layer so its tabs,
	# minimap, quest tracker, FPS/pause controls and hotbar cannot show through
	# or overlap the inventory panel. The inventory itself lives on the player's
	# InventoryUI CanvasLayer (layer 12).
	_set_gameplay_hud_visible(not is_open)

func _on_modal_hud_changed(open: bool) -> void:
	# Station/editor screens cover the full playfield and have their own item
	# sources; hiding the HUD prevents the hotbar and overlays from covering
	# their content.
	_set_gameplay_hud_visible(not open)

func _set_gameplay_hud_visible(show_hud: bool) -> void:
	if _hud_backdrop != null:
		_hud_backdrop.visible = show_hud
	$CanvasLayer.visible = show_hud
	if _mobile_ui != null:
		_mobile_ui.visible = show_hud
	if _notification_hud != null:
		_notification_hud.visible = show_hud
	if _break_layer != null:
		_break_layer.visible = show_hud
	if not show_hud:
		Global.hide_item_tooltip()

func _on_hud_ui_scale_changed(_scale: float) -> void:
	_style_pause_button()

func _style_pause_button() -> void:
	var s: float = Global.ui_scale
	var font_size: int = Global.ui_type_size(Global.UI_TYPE_LABEL)
	var btn_h: float = maxf(44.0 * s, float(font_size + 20))
	var btn_w: float = maxf(96.0 * s, float(font_size * 4 + 36))
	var margin: float = 8.0 * s
	var safe_top: float = Global.ui_safe_insets.y
	var safe_right: float = Global.ui_safe_insets.z
	pause_btn.anchor_left = 1.0
	pause_btn.anchor_right = 1.0
	pause_btn.anchor_top = 0.0
	pause_btn.anchor_bottom = 0.0
	pause_btn.offset_left = -safe_right - margin - btn_w
	pause_btn.offset_top = safe_top + margin
	pause_btn.offset_right = -safe_right - margin
	pause_btn.offset_bottom = safe_top + margin + btn_h
	pause_btn.custom_minimum_size = Vector2(btn_w, btn_h)
	# The FPS overlay sits immediately left of this button.
	Global.ui_pause_strip = safe_right + margin + btn_w + margin
	Global.ui_pause_bottom = safe_top + margin + btn_h
	var normal := StyleBoxFlat.new()
	normal.bg_color     = C_PANEL
	normal.border_color = C_BORDER
	normal.set_border_width_all(maxi(1, int(s)))
	normal.set_corner_radius_all(int(6 * s))
	normal.content_margin_left   = int(10 * s)
	normal.content_margin_right  = int(10 * s)
	normal.content_margin_top    = int(4 * s)
	normal.content_margin_bottom = int(4 * s)

	var hover := StyleBoxFlat.new()
	hover.bg_color     = Color(0.13, 0.17, 0.32, 0.97)
	hover.border_color = C_TITLE
	hover.set_border_width_all(maxi(1, int(s)))
	hover.set_corner_radius_all(int(6 * s))
	hover.content_margin_left   = int(10 * s)
	hover.content_margin_right  = int(10 * s)
	hover.content_margin_top    = int(4 * s)
	hover.content_margin_bottom = int(4 * s)

	var pressed := StyleBoxFlat.new()
	pressed.bg_color     = Color(0.06, 0.08, 0.16, 0.97)
	pressed.border_color = C_MUTED
	pressed.set_border_width_all(maxi(1, int(s)))
	pressed.set_corner_radius_all(int(6 * s))
	pressed.content_margin_left   = int(10 * s)
	pressed.content_margin_right  = int(10 * s)
	pressed.content_margin_top    = int(4 * s)
	pressed.content_margin_bottom = int(4 * s)

	pause_btn.add_theme_stylebox_override("normal",  normal)
	pause_btn.add_theme_stylebox_override("hover",   hover)
	pause_btn.add_theme_stylebox_override("pressed", pressed)
	pause_btn.add_theme_color_override("font_color",         C_TITLE)
	pause_btn.add_theme_color_override("font_hover_color",   C_TITLE)
	pause_btn.add_theme_color_override("font_pressed_color", C_MUTED)
	pause_btn.add_theme_font_size_override("font_size", font_size)
