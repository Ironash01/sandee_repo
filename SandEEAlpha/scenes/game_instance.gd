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

@onready var pause_menu: Control         = $CanvasLayer/PauseMenu
@onready var pause_btn:  Button          = $CanvasLayer/PauseButton
@onready var _world:     Node2D          = $World  # the overworld — kept alive off-tree while in a cave, never freed
@onready var _player:    CharacterBody2D = $Player

var _loading_screen: CanvasLayer = null
var _loading_label:  Label       = null
var _death_overlay:  ColorRect   = null
var _cave_world:      CaveWorld  = null
var _pixie_cave_world: PixieCaveWorld = null
var _dungeon_world:   DungeonWorld = null
# Full-screen fade used when swapping the world for a cave/pixie cave/dungeon
# (and back), so those transitions read as a deliberate scene change.
var _transition_overlay: CanvasLayer = null
# Low layer holding the BACKGROUND HUD (minimap, quest list, pause button).
# Every panel's full-screen dim overlay sits on a higher layer, so opening a
# station/furnace/chest dims this along with the world. The hotbar is NOT here —
# it stays on $CanvasLayer (10) so it remains bright and draggable on top.
var _hud_backdrop: CanvasLayer = null

func _ready() -> void:
	# Honour the player's saved window/fullscreen choice instead of forcing
	# fullscreen (see Global.apply_display_mode — a no-op on mobile).
	Global.apply_display_mode()
	# Large is only the DEFAULT: if the player already chose a scale (persisted
	# in the save) we keep it, so Small/Medium/Large survives scene loads.
	if not Global.ui_scale_set:
		Global.ui_scale     = 1.5
		Global.ui_scale_set = true
	Global.ui_scale_changed.emit(Global.ui_scale)
	Global.game_node = self
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
	# Tap tooltips (touch screens have no hover) — owns its own high layer.
	add_child(TOOLTIP_TAP_SCRIPT.new())

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

	var bg := ColorRect.new()
	bg.color = Color(0.05, 0.07, 0.14, 1.0)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_loading_screen.add_child(bg)

	# Center container so content sits in the middle of the screen.
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_loading_screen.add_child(center)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 16)
	center.add_child(vbox)

	var title := Label.new()
	title.text = "SandEE Alpha"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 40)
	title.add_theme_color_override("font_color", C_TITLE)
	vbox.add_child(title)

	_loading_label = Label.new()
	_loading_label.text = "Initializing..."
	_loading_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_loading_label.add_theme_font_size_override("font_size", 16)
	_loading_label.add_theme_color_override("font_color", C_MUTED)
	vbox.add_child(_loading_label)

func _on_generation_status(status: String) -> void:
	if is_instance_valid(_loading_label):
		_loading_label.text = status

func _on_generation_complete() -> void:
	# Re-enable and show the player.
	_player.process_mode = Node.PROCESS_MODE_INHERIT
	_player.visible      = true

	# Tear down the loading screen.
	if is_instance_valid(_loading_screen):
		_loading_screen.queue_free()
		_loading_screen = null
		_loading_label  = null

	# World is fully generated — safe to create the initial save now.
	if Global.active_save_slot > 0 and not Global.has_save(Global.active_save_slot):
		Global.save_game(Global.active_save_slot)

# ── Cave entry/exit ─────────────────────────────────────────────────────
# Swaps $World out for a freshly generated CaveWorld rather than a full
# change_scene_to_file — Player/camera/Hotbar/PauseMenu all live as $World's
# siblings here in Game, so a full scene change would destroy them (this is
# also why the old Dungeon Portal system, which did use change_scene_to_file
# against the legacy dungeon scenes, never worked — the legacy scenes
# are gone now, replaced by code-generated DungeonWorld). The overworld
# $World is only removed from the tree, never freed, so nothing about it
# needs to regenerate on return.
func enter_cave(portal: CavePortal) -> void:
	if _cave_world != null or _pixie_cave_world != null or _dungeon_world != null:
		return
	_run_scene_transition(Callable(self, "_do_enter_cave").bind(portal), "Entering cave...")

# Immediate swap (used by _run_scene_transition). A cave is never a dungeon —
# make sure a leaked is_in_dungeon (e.g. from a prior dungeon visit) can't
# block the build-mode toggle in here.
func _do_enter_cave(portal: CavePortal) -> void:
	Global.is_in_dungeon = false
	# Each entrance generates a fresh cave, so cave-map fog starts clean.
	Global.explored_cave_tiles.clear()
	var return_position: Vector2 = _player.global_position
	remove_child(_world)

	# "pixie" entrances generate a PixieCaveWorld (128x64 dungeon-like, crystal
	# ores); everything else is a regular CaveWorld. Both are code-built and
	# swapped in for $World the same way — the overworld stays alive off-tree.
	if portal.cave_type == "pixie":
		_pixie_cave_world = PixieCaveWorld.new()
		_pixie_cave_world.name = "World"
		add_child(_pixie_cave_world)
		move_child(_pixie_cave_world, 0)
		_pixie_cave_world.setup(portal.cave_seed, return_position)
		Global.world_node       = _pixie_cave_world
		_player.global_position = _pixie_cave_world.get_player_spawn_position()
		return

	_cave_world = CaveWorld.new()
	_cave_world.name = "World"
	add_child(_cave_world)
	move_child(_cave_world, 0)
	_cave_world.setup(portal.cave_seed, return_position)

	Global.world_node       = _cave_world
	_player.global_position = _cave_world.get_player_spawn_position()

func exit_cave() -> void:
	if _pixie_cave_world != null or _cave_world != null:
		_run_scene_transition(Callable(self, "_do_exit_cave"), "Leaving cave...")

# Immediate swap (used by _run_scene_transition, and directly by the death /
# menu-cleanup paths where the world must be restored synchronously). A pixie
# cave exits the same way a regular cave does — swap the overworld back in and
# free the cave world. Handle whichever kind is currently live.
func _do_exit_cave() -> void:
	if _pixie_cave_world != null:
		var p_return: Vector2 = _pixie_cave_world.overworld_return_position
		remove_child(_pixie_cave_world)
		_pixie_cave_world.queue_free()
		_pixie_cave_world = null
		add_child(_world)
		move_child(_world, 0)
		Global.world_node       = _world
		_player.global_position = p_return
		return
	if _cave_world == null:
		return
	var return_position: Vector2 = _cave_world.overworld_return_position
	remove_child(_cave_world)
	_cave_world.queue_free()
	_cave_world = null

	add_child(_world)
	move_child(_world, 0)
	Global.world_node       = _world
	_player.global_position = return_position

# ── Dungeon entry (mission-accept portal) ─────────────────────────────────
# dungeon_portal.gd dispatches here with the dungeon's index (matching
# Global.missions dungeon_index). Same swap-out-$World pattern as
# enter_cave — the overworld stays alive off-tree, and the dungeon is its own
# TileMapLayer world (DungeonWorld) built in code from the mission's
# DungeonMissionData. The layout generates from a seed rolled once on the
# first mission accept (Global.get_or_create_dungeon_seed), so re-entering
# always reproduces the same dungeon.
func enter_dungeon(dungeon_index: int) -> void:
	if _cave_world != null or _pixie_cave_world != null or _dungeon_world != null:
		return
	var mission: DungeonMissionData = Global.get_dungeon_mission_for_index(dungeon_index)
	if mission == null:
		push_warning("enter_dungeon: no DungeonMissionData for index %d" % dungeon_index)
		return
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
	if Global.block_mode:
		Global.block_mode = false
		Global.block_mode_changed.emit(false)

func exit_dungeon() -> void:
	if _dungeon_world != null:
		_run_scene_transition(Callable(self, "_do_exit_dungeon"), "Leaving dungeon...")

# Immediate swap (used by _run_scene_transition, and directly by the death /
# menu-cleanup paths where the world must be restored synchronously).
func _do_exit_dungeon() -> void:
	if _dungeon_world == null:
		return
	var return_position: Vector2 = _dungeon_world.overworld_return_position
	remove_child(_dungeon_world)
	_dungeon_world.queue_free()
	_dungeon_world = null
	Global.is_in_dungeon = false

	# Restore the notification log to its default top-left position.
	_reset_chat_position()

	add_child(_world)
	move_child(_world, 0)
	Global.world_node       = _world
	_player.global_position = return_position

	# Persist the clear right away — entrance removal + reward + stars all
	# need to survive a quit that never reaches the 5-minute autosave. The
	# overworld is back in the tree now, so the save captures real world data.
	if Global.active_save_slot > 0:
		Global.save_game(Global.active_save_slot)

func _reset_chat_position() -> void:
	for c in $CanvasLayer.get_children():
		if c is ChatConsole:
			if c.has_method("reset_position"):
				c.call("reset_position")
			break

# Cleanly leave any active cave/pixie cave/dungeon before quitting to the main
# menu. Tearing the complex cave node tree down through the normal exit path —
# instead of letting change_scene free it abruptly mid-pause (while the
# overworld sits orphaned off-tree) — avoids the "quit to menu inside caves
# freezes" hang. Also restores the player to the entrance before the save.
func cleanup_for_menu() -> void:
	if _pixie_cave_world != null or _cave_world != null:
		exit_cave()
	elif _dungeon_world != null:
		exit_dungeon()

# Death respawn: leave any active cave/pixie cave/dungeon (so the overworld is
# restored and the player isn't stuck inside the structure), then return the
# OVERWORLD's world-spawn point. Dying anywhere — cave, dungeon, or overworld —
# always puts the player back at the true world spawn.
func get_world_spawn_position() -> Vector2:
	if _pixie_cave_world != null or _cave_world != null:
		exit_cave()
	elif _dungeon_world != null:
		exit_dungeon()
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

func _start_autosave() -> void:
	var timer := Timer.new()
	timer.wait_time = 300.0
	timer.autostart = true
	timer.timeout.connect(_on_autosave)
	add_child(timer)

func _on_autosave() -> void:
	if Global.active_save_slot > 0:
		Global.save_game(Global.active_save_slot)

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
	if _transition_overlay != null:
		callback.call()
		return
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
	layer.add_child(center)
	var label := Label.new()
	label.text = label_text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 18)
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
		layer.queue_free()
		_transition_overlay = null
	)

# ── Pause button styling ──────────────────────────────────────────────
func _style_pause_button() -> void:
	var normal := StyleBoxFlat.new()
	normal.bg_color     = C_PANEL
	normal.border_color = C_BORDER
	normal.set_border_width_all(1)
	normal.set_corner_radius_all(4)
	normal.content_margin_left   = 10
	normal.content_margin_right  = 10
	normal.content_margin_top    = 4
	normal.content_margin_bottom = 4

	var hover := StyleBoxFlat.new()
	hover.bg_color     = Color(0.13, 0.17, 0.32, 0.97)
	hover.border_color = C_TITLE
	hover.set_border_width_all(1)
	hover.set_corner_radius_all(4)
	hover.content_margin_left   = 10
	hover.content_margin_right  = 10
	hover.content_margin_top    = 4
	hover.content_margin_bottom = 4

	var pressed := StyleBoxFlat.new()
	pressed.bg_color     = Color(0.06, 0.08, 0.16, 0.97)
	pressed.border_color = C_MUTED
	pressed.set_border_width_all(1)
	pressed.set_corner_radius_all(4)
	pressed.content_margin_left   = 10
	pressed.content_margin_right  = 10
	pressed.content_margin_top    = 4
	pressed.content_margin_bottom = 4

	pause_btn.add_theme_stylebox_override("normal",  normal)
	pause_btn.add_theme_stylebox_override("hover",   hover)
	pause_btn.add_theme_stylebox_override("pressed", pressed)
	pause_btn.add_theme_color_override("font_color",         C_TITLE)
	pause_btn.add_theme_color_override("font_hover_color",   C_TITLE)
	pause_btn.add_theme_color_override("font_pressed_color", C_MUTED)
	pause_btn.add_theme_font_size_override("font_size", 12)
