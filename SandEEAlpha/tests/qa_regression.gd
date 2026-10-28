extends Node
## Permanent headless regression suite.
##
## Run from the repository root:
##   tools/run_qa.ps1
## or directly:
##   <godot> --headless --path SandEEAlpha res://tests/qa_regression.tscn
##
## Offline-only by design: no Supabase/network calls. It uses a free save slot
## and deletes everything it creates.

var fails := 0
var checks := 0

const TEST_ACCOUNT_A := "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"
const TEST_ACCOUNT_B := "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb"


class SwingProbe:
	extends CharacterBody2D
	var swing_count: int = 0

	func swing_held_item() -> void:
		swing_count += 1


class CancelProbe:
	extends Node
	var cancelled: int = 0

	func cancel_pending_input() -> void:
		cancelled += 1


class FurnaceTemplateProbe:
	extends Node
	var program_code: String = ""

	func get_program_host() -> Node:
		return null

	func run_program(_code: String) -> void:
		pass


class SettingsTourGameProbe:
	extends Node
	var pause_menu: Control = null


class CursorProbe:
	extends Node2D
	var item_data: ItemData = null
	var _player_nearby: bool = true

	func _cursor_over(_at: Vector2 = Vector2.INF) -> bool:
		return true


class CursorPortalProbe:
	extends Node2D
	var _player_nearby: bool = true

	func _click_is_on_entrance() -> bool:
		return true

	func _click_is_on_door() -> bool:
		return true


class PncInteractProbe:
	extends Node2D
	var opened: int = 0
	var _player_nearby: bool = true

	func _cursor_over(_at: Vector2 = Vector2.INF) -> bool:
		return true

	func open_from_touch() -> bool:
		opened += 1
		return true


class PNCInputProbe:
	extends Node
	var press_count: int = 0
	var last_position: Vector2 = Vector2(-1, -1)

	func _input(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
			press_count += 1
			last_position = (event as InputEventMouseButton).position


class FakeWaypointNode:
	extends Node2D
	var anchor_cell := Vector2i.ZERO
	var language := "lua"


class FakeWorldNode:
	extends Node
	var teleported_id := ""

	func teleport_to_world_waypoint(id: String) -> bool:
		teleported_id = id
		return true


class ExitGameProbe:
	extends Node
	var exit_calls: int = 0

	func exit_dungeon() -> void:
		exit_calls += 1


class BuildWorldProbe:
	extends Node
	var placed: Array = []

	func cell_to_world(cell: Vector2i) -> Vector2:
		return Vector2(cell) * 32.0

	func can_place_at(_cell: Vector2i) -> bool:
		return true

	func place_block_at(cell: Vector2i, data: ItemData) -> Node:
		placed.append({"cell": cell, "data": data})
		return self


class AutoNextOverworld:
	extends Node2D
	var ensure_calls := 0
	var removed_indices: Array = []

	func remove_dungeon_entrance(index: int) -> void:
		removed_indices.append(index)

	func ensure_current_dungeon_entrances() -> void:
		ensure_calls += 1


func _ready() -> void:
	await _run()
	print("QA_RESULT: %d/%d passed, %d failed" % [checks - fails, checks, fails])
	get_tree().quit(0 if fails == 0 else 1)


func check(ok: bool, label: String) -> void:
	checks += 1
	if ok:
		print("PASS: " + label)
	else:
		fails += 1
		print("FAIL: " + label)


func _run() -> void:
	Global.account_test_mode = true
	_cleanup_test_account_dir(TEST_ACCOUNT_A)
	_cleanup_test_account_dir(TEST_ACCOUNT_B)
	Global.account_transitioning = false
	Global.online_mode = true
	Global.begin_account_session(TEST_ACCOUNT_A)
	Global.mark_account_cloud_ready()
	Global.set_online_mode(true)
	Global.reset_pause_state()
	_test_registry()
	_test_friendly_mobs()
	await _test_bestiary()
	await _test_save_and_progress()
	_test_account_isolation()
	await _test_tutorial_state_and_dialogue()
	await _test_guided_tutorial_v3()
	await _test_triggers()
	await _test_pause_and_build()
	await _test_pause_menu_short_layout()
	await _test_tutorial_help_and_cursors()
	_test_world_eligibility()
	_test_dungeon_generation()
	await _test_dungeon_altar_coverage()
	await _test_first_dungeon_tutorial()
	await _test_dungeon_progression_and_sides()
	_test_damage_and_spawn_constants()
	await _test_damage_application()
	await _test_safe_zones()
	await _test_grass_clearance()
	await _test_cave_persistence()
	await _test_cave_cache_lifecycle()
	await _test_cave_generation_edges()
	await _test_wisp_companion()
	await _test_torches()
	await _test_algorithmica_color()
	await _test_cactus_and_worm()
	await _test_fish_and_automatica()
	await _test_headless_fish_loot()
	await _test_rare_chest_generation()
	_test_minimap_lua_legend()
	await _test_knowledge_altar_pages()
	await _test_mission_events()
	_test_tool_stacking_and_wood_mission()
	await _test_stat_hud_layout()
	_test_stat_crystals()
	await _test_smelting_recipes()
	await _test_held_damage_display()
	await _test_mining_tool_switch()
	await _test_pickaxe_blockers()
	await _test_cave_pickup()
	await _test_pixie_loot()
	await _test_worm_water_guard()
	await _test_escape()
	await _test_ui_back_stack()
	await _test_ui_back_actual()
	await _test_inventory_hotbar()
	await _test_chest_inventory_panel()
	_test_cloud_save_identity()
	await _test_sync_loading()
	_test_android_config()
	_test_display_frame_cap()
	_test_removed_debug_surfaces()
	_test_ui_scaling()
	await _test_android_input_and_safe_area()
	await _test_pc_controls_overlay()
	await _test_settings_tour()
	await _test_android_tooltip_suppression()
	await _test_android_keyboard_layout()
	await _test_ambient_birds()
	await _test_automatica_api()
	await _test_automatica_build_queue()
	await _test_algorithmica_templates()
	await _test_quiz_reward_ui()
	await _test_quiz_compiler_layout()
	await _test_altar_mobile_layout()
	await _test_title_panorama()
	await _test_interpreters()
	await _test_crash_logger()
	await _test_control_scheme_parity()
	_test_tree_canopy_occupancy()
	_test_decorative_structures()
	_test_waypoints()
	_cleanup_test_account_dir(TEST_ACCOUNT_A)
	_cleanup_test_account_dir(TEST_ACCOUNT_B)
	Global.clear_active_account("qa_done")
	Global.account_test_mode = false


func _cleanup_test_account_dir(account_id: String) -> void:
	var dir_path := "user://accounts/" + account_id
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	for f in dir.get_files():
		dir.remove(f)
	var root := DirAccess.open("user://accounts")
	if root != null:
		root.remove(account_id)


func _test_registry() -> void:
	var ids: Array = []
	var gameplay_ids: Array = []
	var side_ids: Array = []
	for m in Global.missions:
		ids.append(str(m.get("id", "")))
		if not m.has("dungeon_index") and not bool(m.get("side", false)):
			gameplay_ids.append(str(m.get("id", "")))
		if bool(m.get("side", false)):
			side_ids.append(str(m.get("id", "")))
	check(not ids.has("defeat_wolves"), "retired Kill Wolves mission is absent")
	check(gameplay_ids.size() == 28, "28 overworld missions (25 + 3 diamond equipment)")
	check(gameplay_ids.size() >= 3
		and gameplay_ids[gameplay_ids.size() - 3] == "craft_diamond_sword"
		and gameplay_ids[gameplay_ids.size() - 2] == "craft_diamond_pickaxe"
		and gameplay_ids[gameplay_ids.size() - 1] == "craft_diamond_axe",
		"diamond equipment missions are the final three core overworld missions")
	check(side_ids.size() == 20 and _unique_count(side_ids) == side_ids.size()
		and _unique_count(ids) == ids.size(),
		"20 unique side missions are registered without duplicate ids")
	var shelter := Global._find_mission("build_shelter")
	check(not shelter.is_empty() and int(shelter.get("goal", 0)) == 1,
		"build_shelter goal matches its room tracker")


func _test_friendly_mobs() -> void:
	var sheep: Node = load("res://scenes/mobs/Sheep.tscn").instantiate()
	var data: MobCombatData = sheep.get("COMBAT_DATA") as MobCombatData
	check(data != null and data.behavior == MobCombatData.Behavior.PASSIVE,
		"sheep is classified as a passive/friendly mob")
	check(not Global.is_hostile_mob(sheep),
		"sheep is not treated as a hostile mob")
	var minimap := Minimap.new()
	check(not bool(minimap.call("_mob_is_hostile", sheep)),
		"sheep uses the friendly minimap color")
	minimap.free()
	sheep.free()


func _test_bestiary() -> void:
	var old_slot: int = Global.active_save_slot
	Global.active_save_slot = -1
	Global.reset_bestiary_state()

	var entries: Array = BestiaryCatalog.entries()
	var ids: Array = []
	for value in entries:
		var data: MobCombatData = value as MobCombatData
		ids.append(data.bestiary_id)
	check(entries.size() == 14 and ids.has("cinder_ooze")
		and ids.has("gravebell_shambler") and ids.has("rune_sentinel")
		and ids.has("vesper_acolyte") and ids.has("brass_prowler")
		and ids.has("cipher_warden") and ids.has("mossback_nib")
		and ids.has("emberfox_kit") and ids.has("wolf") and ids.has("sheep")
		and ids.has("worm") and ids.has("pixie") and ids.has("headless_fish")
		and ids.has("hitman"),
		"all new and legacy Bestiary creatures are present in the data catalog")
	var drop_paths_ok := true
	var icons_ok := true
	for value in entries:
		var data: MobCombatData = value as MobCombatData
		if not ResourceLoader.exists(data.bestiary_icon_path):
			icons_ok = false
		for drop_value in data.drops:
			if not (drop_value is Dictionary):
				drop_paths_ok = false
				continue
			var path := str((drop_value as Dictionary).get("item_path", ""))
			if path.is_empty() or not ResourceLoader.exists(path):
				drop_paths_ok = false
	check(icons_ok, "every Bestiary entry has an existing portrait icon")
	check(drop_paths_ok, "every Bestiary drop points at an existing ItemData resource")

	# Exercise the first-sighting and first-kill transitions, including the
	# toast contract used by NotificationHUD.
	var toasts: Array = []
	var on_notification := func(msg: String) -> void: toasts.append(msg)
	Global.notification_posted.connect(on_notification)
	var first_seen := Global.bestiary_record_seen("cinder_ooze")
	var duplicate_seen := Global.bestiary_record_seen("cinder_ooze")
	check(first_seen and not duplicate_seen and Global.bestiary_is_seen("cinder_ooze")
		and toasts.size() == 1 and str(toasts[0]).contains("Cinder Ooze"),
		"first sighting records the name and posts one notification")
	var first_kill := Global.bestiary_record_kill("cinder_ooze")
	var duplicate_kill := Global.bestiary_record_kill("cinder_ooze")
	check(first_kill and not duplicate_kill and Global.bestiary_is_killed("cinder_ooze")
		and toasts.size() == 2,
		"first kill unlocks the entry and notifications are not repeated")
	var unseen_kill := Global.bestiary_record_kill("rune_sentinel")
	check(unseen_kill and Global.bestiary_is_seen("rune_sentinel")
		and Global.bestiary_is_killed("rune_sentinel"),
		"a kill before the sighting scan still marks both discovery states")
	Global.notification_posted.disconnect(on_notification)

	var scenes: Dictionary = {
		"res://scenes/mobs/MossbackNib.tscn": false,
		"res://scenes/mobs/EmberfoxKit.tscn": false,
		"res://scenes/mobs/CinderOoze.tscn": true,
		"res://scenes/mobs/GravebellShambler.tscn": true,
		"res://scenes/mobs/RuneSentinel.tscn": true,
		"res://scenes/mobs/VesperAcolyte.tscn": true,
		"res://scenes/mobs/BrassProwler.tscn": true,
		"res://scenes/mobs/CipherWarden.tscn": true,
	}
	var anims_ok := true
	var walk_frames_ok := true
	var hostility_ok := true
	for path in scenes:
		var scene: PackedScene = load(path) as PackedScene
		if scene == null:
			anims_ok = false
			continue
		var mob: Node2D = scene.instantiate() as Node2D
		add_child(mob)
		await get_tree().process_frame
		var sprite := mob.get_node_or_null("AnimatedSprite2D") as AnimatedSprite2D
		if sprite == null or sprite.sprite_frames == null:
			anims_ok = false
		else:
			var names: Array = sprite.sprite_frames.get_animation_names()
			for dir in ["south", "north", "east", "west"]:
				if not names.has("idle_" + dir) or not names.has("walk_" + dir):
					anims_ok = false
				elif sprite.sprite_frames.get_frame_count("walk_" + dir) < 4:
					walk_frames_ok = false
		var expected_hostile: bool = bool(scenes[path])
		if Global.is_hostile_mob(mob) != expected_hostile:
			hostility_ok = false
		mob.queue_free()
		await get_tree().process_frame
	check(anims_ok, "each Bestiary creature has four-direction idle/walk animations")
	check(walk_frames_ok, "each walk cycle uses four gait frames")
	check(hostility_ok, "new hostile creatures report hostile and friendlies do not")

	# A real death must reach both halves of the feature: the Bestiary study
	# state and the actual loot spawner.
	Global.reset_bestiary_state()
	var kill_scene: PackedScene = load("res://scenes/mobs/CinderOoze.tscn") as PackedScene
	var kill_mob: Node2D = kill_scene.instantiate() as Node2D
	add_child(kill_mob)
	await get_tree().process_frame
	kill_mob.call("take_hit", 9999.0, kill_mob.global_position + Vector2(0, -1))
	await get_tree().process_frame
	var dropped_item := false
	for child in get_children():
		if child.get("item_data") is ItemData:
			dropped_item = true
			child.queue_free()
	check(Global.bestiary_is_killed("cinder_ooze") and dropped_item,
		"a real kill unlocks the Bestiary entry and spawns its loot")

	# Legacy mobs must participate in the same sighting/kill pipeline. The
	# sheep is the reported case; the source check covers the other old death
	# paths so they cannot silently regress to no Bestiary credit.
	Global.reset_bestiary_state()
	var legacy_ids: Array = ["wolf", "sheep", "worm", "pixie", "headless_fish", "hitman"]
	var legacy_ids_ok := true
	for legacy_id in legacy_ids:
		if BestiaryCatalog.get_entry(legacy_id) == null:
			legacy_ids_ok = false
	check(legacy_ids_ok, "legacy mobs have Bestiary catalog entries")
	var old_world: Node = Global.world_node
	Global.world_node = null
	var sheep_scene: PackedScene = load("res://scenes/mobs/Sheep.tscn") as PackedScene
	var sheep_mob: Node2D = sheep_scene.instantiate() as Node2D
	add_child(sheep_mob)
	await get_tree().process_frame
	check(str(Global.call("_bestiary_id_for_mob", sheep_mob)) == "sheep",
		"the Bestiary sighting scan reads the sheep's id")
	sheep_mob.call("_die")
	await get_tree().process_frame
	check(Global.bestiary_is_killed("sheep"),
		"a real sheep death records Bestiary kill credit")
	for child in get_children():
		if child.get("item_data") is ItemData:
			child.queue_free()
	Global.world_node = old_world
	var legacy_scripts: Array = [
		"res://scripts/wolf.gd", "res://scripts/sheep.gd", "res://scripts/worm.gd",
		"res://scripts/pixie_mob.gd", "res://scripts/headless_fish_mob.gd",
		"res://scripts/hitman.gd",
	]
	var legacy_credit_ok := true
	for script_path in legacy_scripts:
		if not FileAccess.get_file_as_string(script_path).contains(
				"bestiary_record_kill(COMBAT_DATA.bestiary_id)"):
			legacy_credit_ok = false
	check(legacy_credit_ok, "every legacy mob death path records Bestiary kills")
	Global.reset_bestiary_state()

	# Restore the deterministic UI fixture.
	Global.reset_bestiary_state()
	Global.bestiary_record_seen("cinder_ooze")
	Global.bestiary_record_kill("cinder_ooze")
	Global.bestiary_record_kill("rune_sentinel")

	# The inventory page exposes the Bestiary as a sibling of CRAFT and the
	# Encyclopedia. The studied entry must show its health and guaranteed drop.
	var layer := CanvasLayer.new()
	add_child(layer)
	var ui: Control = load("res://scenes/ui/inventory_ui.tscn").instantiate() as Control
	layer.add_child(ui)
	await get_tree().process_frame
	await get_tree().process_frame
	ui.call("_switch_tab", "bestiary")
	await get_tree().process_frame
	var has_tab := false
	var has_entry := false
	var has_health := false
	var has_drop := false
	for n in ui.find_children("*", "Button", true, false):
		var button := n as Button
		if button == null:
			continue
		if button.text == "BESTIARY":
			has_tab = true
		if button.text.begins_with("Cinder Ooze") and button.text.contains("STUDIED"):
			has_entry = true
	for n in ui.find_children("*", "Label", true, false):
		var label := n as Label
		if label == null:
			continue
		if label.text.begins_with("MAX HEALTH   85"):
			has_health = true
		if label.text == "Always":
			has_drop = true
	check(has_tab and has_entry and has_health and has_drop,
		"Bestiary tab shows a studied creature, its health and its drops")
	layer.queue_free()
	await get_tree().process_frame

	var world_src := FileAccess.get_file_as_string("res://scripts/world.gd")
	var dungeon_src := FileAccess.get_file_as_string("res://scripts/dungeon_world.gd")
	check(world_src.contains("CinderOoze.tscn") and world_src.contains("GravebellShambler.tscn")
		and world_src.contains("MossbackNib.tscn") and world_src.contains("EmberfoxKit.tscn"),
		"overworld ambient pool contains both enemies and both friendly creatures")
	check(dungeon_src.contains("THEME_DUNGEON_ENEMIES") and dungeon_src.contains("RuneSentinel.tscn")
		and dungeon_src.contains("VesperAcolyte.tscn") and dungeon_src.contains("BrassProwler.tscn")
		and dungeon_src.contains("CipherWarden.tscn"),
		"Lua/Python dungeon pools contain their theme-specific enemies")

	Global.reset_bestiary_state()
	Global.active_save_slot = old_slot


func _test_save_and_progress() -> void:
	Global.reset_missions()
	Global.reset_bestiary_state()
	Global.bestiary_record_seen("cinder_ooze")
	Global.bestiary_record_kill("rune_sentinel")
	var wood := Global._find_mission("collect_wood")
	wood["progress"] = 7
	Global.reset_missions()
	check(int(wood.get("progress", -1)) == 0, "reset clears partial progress")

	var slot: int = Global.next_free_slot()
	if slot <= 0:
		print("NOTE: no free save slot; save/load progress test skipped")
		return
	var path := Global.save_file_path(slot)

	var moved := Global._find_mission("move")
	moved["completed"] = true
	moved["progress"] = 1
	wood["progress"] = 7
	Global.cleared_dungeons[77] = true
	Global.dungeon_stars[77] = 2
	Global.dungeon_quiz_hints[77] = 4
	Global.dungeon_quiz_penalties[77] = 2
	Global.save_game(slot)
	Global.reset_missions()
	Global.load_game(slot)
	check(int(wood.get("progress", -1)) == 7, "partial progress survives save/load")
	check(bool(moved.get("completed", false)), "completion survives save/load")
	check(Global.dungeon_stars_for(77) == 2,
		"per-dungeon blue-star awards survive save/load")
	check(Global.dungeon_quiz_hints_for(77) == 4
		and Global.dungeon_quiz_penalties_for(77) == 2,
		"quiz hint and penalty counts survive save/load")
	check(Global.bestiary_is_seen("cinder_ooze")
		and Global.bestiary_is_killed("rune_sentinel")
		and Global.bestiary_is_seen("rune_sentinel"),
		"Bestiary sighting/study state survives save/load")
	check(FileAccess.get_file_as_string(path).contains("\"bestiary_seen\"")
		and FileAccess.get_file_as_string(path).contains("\"bestiary_killed\""),
		"Bestiary state is persisted in the world save")
	check(_saved_missions_version(path) >= 2, "save stores the mission-content version")
	var first_uid := Global.world_uid_of(slot)
	var first_rev := Global.save_revision_of(slot)
	Global.save_game(slot)
	check(first_uid.length() >= 16 and Global.world_uid_of(slot) == first_uid,
		"world identity is stable across saves")
	check(Global.save_revision_of(slot) == first_rev + 1,
		"save revision increments exactly once per save")
	# Simulate a pre-identity save: loading must still work, and the in-place
	# migration must add a stable UID/revision without touching gameplay data.
	var legacy: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if legacy is Dictionary:
		(legacy as Dictionary).erase("world_uid")
		(legacy as Dictionary).erase("save_revision")
		(legacy as Dictionary).erase("save_format")
		(legacy as Dictionary).erase("max_health")
		(legacy as Dictionary).erase("health")
		(legacy as Dictionary).erase("max_stamina")
		(legacy as Dictionary).erase("stamina")
		var lf := FileAccess.open(path, FileAccess.WRITE)
		lf.store_string(JSON.stringify(legacy))
		lf.close()
		Global.load_game(slot)
		var migrated: Dictionary = Global.ensure_save_identity(slot)
		check(str(migrated.get("world_uid", "")).length() >= 16
			and int(migrated.get("save_revision", 0)) >= 1,
			"legacy saves migrate to portable identity/revision metadata")
		check(int(Global._find_mission("collect_wood").get("progress", 0)) >= 0,
			"legacy-save identity migration preserves gameplay data")
		check(is_equal_approx(Global.max_health, Global.BASE_MAX_HEALTH)
			and is_equal_approx(Global.health, Global.BASE_MAX_HEALTH)
			and is_equal_approx(Global.max_stamina, Global.BASE_MAX_STAMINA)
			and is_equal_approx(Global.stamina, Global.BASE_MAX_STAMINA),
			"legacy saves without crystal fields start at base stats")

	# Old save containing the retired wolf mission must load safely.
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if data is Dictionary:
		(data["missions"] as Array).append({"id": "defeat_wolves", "completed": true, "progress": 5})
		var f := FileAccess.open(path, FileAccess.WRITE)
		f.store_string(JSON.stringify(data))
		f.close()
		Global.load_game(slot)
		check(Global._find_mission("defeat_wolves").is_empty(),
			"old save with the retired mission loads safely")

	# Permanent crystal growth is per-world: both the raised maximum and the
	# current value must survive a save/load round trip.
	Global.max_health = 240.0
	Global.health = 205.0
	Global.max_stamina = 340.0
	Global.stamina = 315.0
	Global.save_game(slot)
	var stat_save: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	check(stat_save is Dictionary
		and is_equal_approx(float((stat_save as Dictionary).get("max_health", 0.0)), 240.0)
		and is_equal_approx(float((stat_save as Dictionary).get("max_stamina", 0.0)), 340.0),
		"crystal-raised maximums are stored in the world save")
	Global.reset_player_stats()
	check(is_equal_approx(Global.max_health, Global.BASE_MAX_HEALTH),
		"reset_player_stats restores the base maximums")
	Global.load_game(slot)
	check(is_equal_approx(Global.max_health, 240.0)
		and is_equal_approx(Global.health, 205.0)
		and is_equal_approx(Global.max_stamina, 340.0)
		and is_equal_approx(Global.stamina, 315.0),
		"save/load preserves crystal-raised maximums and current stats")
	Global.reset_player_stats()

	# At-goal progress completes even if `completed` was false.
	Global.reset_missions()
	var shelter := Global._find_mission("build_shelter")
	shelter["completed"] = false
	shelter["progress"] = 1
	Global.set_mission_progress("build_shelter", 1)
	check(bool(shelter.get("completed", false)), "at-goal progress completes immediately")

	Global.cleared_dungeons.erase(77)
	Global.dungeon_stars.erase(77)
	Global.dungeon_quiz_hints.erase(77)
	Global.dungeon_quiz_penalties.erase(77)
	Global.delete_world(slot)
	Global.reset_bestiary_state()


func _test_account_isolation() -> void:
	var old_slot: int = Global.active_save_slot
	var old_name: String = Global.world_name
	# No account context: no file access at all.
	Global.clear_active_account("qa_fresh")
	check(not Global.can_access_worlds() and Global.list_worlds().is_empty()
		and not Global.has_save(1),
		"fresh/unauthenticated state exposes no local worlds")

	# Account A creates and owns a world.
	Global.set_online_mode(true)
	check(Global.begin_account_session(TEST_ACCOUNT_A), "account A session starts")
	# Cloud sync must be allowed to verify a newly authenticated account even
	# though world access stays closed until the verification finishes.
	var old_token := Supabase.access_token
	var old_user: Dictionary = Supabase.user.duplicate(true)
	Supabase.access_token = "qa-test-token"
	Supabase.user = {"id": TEST_ACCOUNT_A}
	check(CloudSync.is_enabled() and not Global.can_access_worlds(),
		"cloud sync can verify a new account before its world list is published")
	Supabase.access_token = old_token
	Supabase.user = old_user
	Global.mark_account_cloud_ready()
	var slot: int = Global.next_free_slot()
	Global.world_name = "A-only world"
	Global.save_game(slot)
	var a_path := Global.save_file_path(slot)
	check(Global.has_save(slot) and Global.list_worlds().has(slot)
		and a_path.contains(TEST_ACCOUNT_A),
		"account A sees its own account-scoped world")

	# Switch to B: A's file remains on disk but is outside B's boundary.
	Global.begin_account_transition("qa_switch")
	check(not Global.can_access_worlds() and Global.list_worlds().is_empty(),
		"an account transition immediately hides all worlds")
	check(Global.begin_account_session(TEST_ACCOUNT_B), "account B session starts")
	Global.set_online_mode(true)
	Global.mark_account_cloud_ready()
	Global.active_save_slot = -1
	Global.load_game(slot)
	check(not Global.has_save(slot) and not Global.list_worlds().has(slot)
		and Global.active_save_slot == -1 and FileAccess.file_exists(a_path),
		"account B cannot list, load, or overwrite account A's world")

	# Copying A's file into B's boundary without an owner sidecar does not grant
	# access; B's session must not adopt it automatically.
	var b_path := Global.save_file_path(slot)
	if FileAccess.file_exists(a_path) and not b_path.is_empty():
		DirAccess.copy_absolute(ProjectSettings.globalize_path(a_path),
			ProjectSettings.globalize_path(b_path))
		DirAccess.copy_absolute(ProjectSettings.globalize_path(a_path.get_basename() + ".account"),
			ProjectSettings.globalize_path(b_path.get_basename() + ".account"))
		check(not Global.has_save(slot),
			"a copied world with another account's owner metadata is rejected")
		DirAccess.remove_absolute(ProjectSettings.globalize_path(b_path))
		DirAccess.remove_absolute(ProjectSettings.globalize_path(b_path.get_basename() + ".account"))

	# A can still play offline from a previously verified binding. Offline mode
	# cannot create a new world, but can save the existing account-owned copy.
	Global.begin_account_transition("qa_offline")
	Global.begin_account_session(TEST_ACCOUNT_A)
	Global.mark_account_cloud_ready()
	Global.last_verified_account_id = TEST_ACCOUNT_A
	check(Global.enter_offline_mode() and Global.can_access_worlds(),
		"verified account A can enter offline mode")
	check(not Global.can_create_world(), "offline mode cannot create new worlds")
	Global.world_name = "A-only world"
	Global.save_game(slot)
	check(Global.has_save(slot), "offline play can save its own existing world")

	# A new account cannot reuse A's offline authorization.
	Global.begin_account_transition("qa_offline_switch")
	Global.begin_account_session(TEST_ACCOUNT_B)
	Global.set_online_mode(true)
	Global.mark_account_cloud_ready()
	check(not Global.list_worlds().has(slot) and not Global.has_save(slot),
		"offline authorization never carries across an account switch")

	# Interrupted transition fails closed until a new verified session clears it.
	Global.begin_account_transition("qa_interrupted")
	check(Global.account_transitioning and not Global.can_access_worlds()
		and Global.list_worlds().is_empty(),
		"interrupted account transition blocks world access")
	Global.begin_account_session(TEST_ACCOUNT_A)
	Global.set_online_mode(true)
	Global.mark_account_cloud_ready()
	check(not Global.account_transitioning and Global.can_access_worlds(),
		"a verified account clears an interrupted transition safely")

	Global.active_save_slot = old_slot
	Global.world_name = old_name


func _test_tutorial_state_and_dialogue() -> void:
	var old_version: int = Global.tutorial_version
	var old_stage: int = Global.tutorial_stage
	var old_completed: bool = Global.tutorial_completed
	var old_flags: Dictionary = Global.tutorial_flags.duplicate(true)
	var old_slot: int = Global.active_save_slot
	Global.reset_pause_state()

	var slot: int = Global.next_free_slot()
	if slot > 0:
		Global.tutorial_version = 3
		Global.tutorial_stage = 8
		Global.tutorial_completed = false
		Global.tutorial_flags = {
			"starter_kit_v3": true,
			"automatica_awarded": true,
			"camp_cells_v3": {"furnace": [3, 4]},
		}
		Global.save_game(slot)
		Global.tutorial_stage = 0
		Global.tutorial_completed = true
		Global.tutorial_flags.clear()
		Global.load_game(slot)
		check(Global.tutorial_version == 3 and Global.tutorial_stage == 8
			and not Global.tutorial_completed
			and bool(Global.tutorial_flags.get("starter_kit_v3", false))
			and bool(Global.tutorial_flags.get("automatica_awarded", false)),
			"guided tutorial version, step and one-time reward flags survive save/load")
		check(FileAccess.get_file_as_string(Global.save_file_path(slot)).contains("tutorial_flags"),
			"tutorial reward flags are persisted in the world save")

		# A previous guided-tutorial generation must not be replayed inside the
		# v3 flow. Existing items, missions and dungeon progress stay untouched.
		Global.tutorial_version = 2
		Global.tutorial_stage = 5
		Global.tutorial_completed = false
		Global.tutorial_flags = {"starter_kit": true}
		Global.save_game(slot)
		Global.load_game(slot)
		check(Global.tutorial_version == 3 and Global.tutorial_completed
			and Global.tutorial_stage == 0,
			"unfinished v2 tutorials migrate to completed v3 onboarding")

		# A pre-v2 save must not be ambushed by the new onboarding, even if the
		# old six-line tutorial was left unfinished.
		var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string(Global.save_file_path(slot)))
		if raw is Dictionary:
			(raw as Dictionary).erase("tutorial_version")
			(raw as Dictionary).erase("tutorial_flags")
			(raw as Dictionary)["tutorial_completed"] = false
			(raw as Dictionary)["tutorial_stage"] = 4
			var f := FileAccess.open(Global.save_file_path(slot), FileAccess.WRITE)
			f.store_string(JSON.stringify(raw))
			f.close()
			Global.load_game(slot)
			check(Global.tutorial_completed and Global.tutorial_stage == 0,
				"legacy unfinished tutorials are treated as complete, not replayed")
		Global.delete_world(slot)

	Global.tutorial_version = old_version
	Global.tutorial_stage = old_stage
	Global.tutorial_completed = old_completed
	Global.tutorial_flags = old_flags
	Global.active_save_slot = old_slot
	Global.reset_pause_state()

	# Exercise the real overlay input contract: first input reveals the line,
	# a same-tick second input is swallowed, the next input advances one line,
	# and the final input closes and releases the pause/modal ownership.
	var layer := CanvasLayer.new()
	add_child(layer)
	var dlg: Control = load("res://scripts/tutorial_dialogue.gd").new() as Control
	layer.add_child(dlg)
	await get_tree().process_frame
	var callback_hits := [0]
	var opened: bool = bool(dlg.call("show_conversation", [
		{"speaker": "Py-San", "portrait": "res://sprites/char/pysan.png", "text": "First line."},
		{"speaker": "LUA", "portrait": "res://sprites/char/lua/front.png", "text": "Second line."},
	], func() -> void: callback_hits[0] += 1))
	check(opened and bool(dlg.call("is_active")) and Global.any_ui_open(),
		"RPG dialogue opens as a real modal with a portrait-capable line list")
	dlg.call("advance_from_input")
	check(bool(dlg.get("_continue_label").visible) and int(dlg.call("current_line_index")) == 0,
		"first dialogue input reveals the current line without advancing it")
	dlg.call("advance_from_input")
	check(int(dlg.call("current_line_index")) == 0,
		"duplicate same-tick dialogue input cannot skip a line")
	await get_tree().create_timer(0.35).timeout
	dlg.call("advance_from_input")
	check(int(dlg.call("current_line_index")) == 1,
		"the next dialogue input advances exactly one line")
	dlg.call("advance_from_input")
	await get_tree().create_timer(0.35).timeout
	dlg.call("advance_from_input")
	await get_tree().create_timer(0.35).timeout
	dlg.call("advance_from_input")
	await get_tree().create_timer(0.35).timeout
	dlg.call("advance_from_input")
	await get_tree().process_frame
	await get_tree().process_frame
	check(int(callback_hits[0]) == 1 and not bool(dlg.call("is_active")) and not Global.any_ui_open(),
		"dialogue completion runs one callback and releases pause/modal state")
	layer.queue_free()
	await get_tree().process_frame
	Global.reset_pause_state()


func _test_guided_tutorial_v3() -> void:
	# The lesson order is intentional: onboarding -> first dungeon -> both
	# programming systems -> exploration (caves, Pixie Caves, waypoints).
	var guide_script: Script = load("res://scripts/tutorial_guide.gd")
	var steps: Array = guide_script.get_script_constant_map().get("STEPS", []) as Array
	var order_ok := steps.find("dungeon_quiz") < steps.find("automatica") \
		and steps.find("automatica") < steps.find("automatica_combat") \
		and steps.find("automatica_combat") < steps.find("algorithmica") \
		and steps.find("algorithmica") < steps.find("cave_regular") \
		and steps.find("cave_regular") < steps.find("cave_pixie") \
		and steps.find("cave_pixie") < steps.find("waypoint") \
		and steps.has("move_one") and steps.has("move_two") and steps.has("tree_chop") \
		and steps.has("craft_station") and steps.has("dungeon_knowledge")
	check(order_ok, "guided tutorial v3 orders dungeon, Automatica build/combat, programming and exploration")

	# Starting kit: all three wooden tools and exactly 10 bread, granted once.
	var old_hotbar: Array = Global.Hotbar.duplicate(true)
	var old_inventory: Array = Global.Inventory.duplicate(true)
	var old_flags: Dictionary = Global.tutorial_flags.duplicate(true)
	var old_selected: int = Global.hotbar_selected
	var old_slot: int = Global.active_save_slot
	Global.active_save_slot = -1
	Global.tutorial_flags.clear()
	Global.Hotbar.fill(null)
	Global.Inventory.fill(null)
	var guide: Node = guide_script.new()
	add_child(guide)
	guide.set("_finished", true)
	guide.call("_ensure_starter_kit")
	var axe := load("res://resources/items/woodenaxe.tres") as ItemData
	var pick := load("res://resources/items/wooden_pickaxe.tres") as ItemData
	var sword := load("res://resources/items/woodensword.tres") as ItemData
	var bread := load("res://resources/items/bread.tres") as ItemData
	check(Global.count_item(axe) == 1 and Global.count_item(pick) == 1
		and Global.count_item(sword) == 1 and Global.count_item(bread) == 10,
		"new-world starter kit grants three wooden tools and exactly 10 bread")
	var held_before: String = Global.held_tool_id()
	guide.call("_ensure_starter_kit")
	check(Global.count_item(axe) == 1 and Global.count_item(pick) == 1
		and Global.count_item(sword) == 1 and Global.count_item(bread) == 10
		and Global.held_tool_id() == held_before,
		"starter kit is idempotent and does not reset the selected slot")
	check(held_before != "res://resources/items/woodenaxe.tres",
		"starter kit leaves the axe unselected so the axe lesson requires an action")
	guide.queue_free()
	await get_tree().process_frame
	Global.Hotbar = old_hotbar
	Global.Inventory = old_inventory
	Global.tutorial_flags = old_flags
	Global.set_hotbar_selection(old_selected)
	Global.active_save_slot = old_slot

	# The first Automatica lesson gives the robot an exact 32-Wood stack in
	# BUILD SLOT 1 instead of asking the player to spend inventory wood.
	var old_auto_stage: int = Global.tutorial_stage
	var auto_guide: Node = guide_script.new()
	add_child(auto_guide)
	auto_guide.set("_finished", true)
	var auto_npc: Node = load("res://scenes/objects/LuaNPC.tscn").instantiate()
	add_child(auto_npc)
	await get_tree().process_frame
	auto_guide.set("_automatica_station", auto_npc)
	auto_guide.call("_give_automatica_line_blocks")
	var wood_item := load("res://resources/items/wood.tres") as ItemData
	var auto_palette: Array = auto_npc.call("get_build_palette") as Array
	var auto_slot: Variant = auto_palette[0] if auto_palette.size() > 0 else null
	check(auto_slot is Dictionary
		and (auto_slot as Dictionary).get("data") == wood_item
		and int((auto_slot as Dictionary).get("quantity", 0)) == 32,
		"the first Automatica lesson loads exactly 32 Wood into BUILD SLOT 1")
	auto_npc.call("set_tool", wood_item, 1)
	var wrong_tool := bool(auto_guide.call("_station_has_sword", auto_npc))
	auto_npc.call("set_tool", sword, 1)
	var right_tool := bool(auto_guide.call("_station_has_sword", auto_npc))
	check(not wrong_tool and right_tool,
		"the combat lesson only accepts the Wooden Sword in the robot's TOOL slot")
	auto_guide.queue_free()
	auto_npc.queue_free()
	await get_tree().process_frame

	# The combat lesson grants a SECOND Automatica and a SECOND Wooden Sword
	# even though the starter kit already contains a sword, and only once.
	var lua_item := load("res://resources/items/lua.tres") as ItemData
	var kit_guide: Node = guide_script.new()
	add_child(kit_guide)
	kit_guide.set("_finished", true)
	Global.active_save_slot = -1
	Global.tutorial_flags.clear()
	Global.Hotbar.fill(null)
	Global.Inventory.fill(null)
	Global.tutorial_stage = 0
	Global.add_item({"data": sword, "quantity": 1})
	var kit_granted: bool = bool(kit_guide.call("_grant_automatica_combat_kit"))
	var kit_lua: int = Global.count_item(lua_item)
	var kit_swords: int = Global.count_item(sword)
	kit_guide.call("_grant_automatica_combat_kit")
	check(kit_granted and kit_lua == 1 and kit_swords == 2
		and Global.count_item(lua_item) == 1 and Global.count_item(sword) == 2,
		"combat lesson grants one more Automatica and Wooden Sword exactly once")
	kit_guide.queue_free()
	await get_tree().process_frame
	Global.Hotbar = old_hotbar
	Global.Inventory = old_inventory
	Global.tutorial_flags = old_flags
	Global.set_hotbar_selection(old_selected)
	Global.active_save_slot = old_slot
	Global.tutorial_stage = old_auto_stage

	# The Crafting Station lesson must be satisfied by the real inventory craft
	# action, not by a station found in a chest.
	var craft_guide: Node = guide_script.new()
	add_child(craft_guide)
	craft_guide.set("_finished", false)
	craft_guide.set("_current_step", steps.find("craft_station"))
	var old_craft_flags: Dictionary = Global.tutorial_flags.duplicate(true)
	var old_craft_hotbar: Array = Global.Hotbar.duplicate(true)
	var old_craft_inventory: Array = Global.Inventory.duplicate(true)
	Global.active_save_slot = -1
	Global.tutorial_flags.clear()
	Global.Hotbar.fill(null)
	Global.Inventory.fill(null)
	var station_item := load("res://resources/items/crafting_station.tres") as ItemData
	Global.add_item({"quantity": 1, "data": station_item})
	check(not bool(craft_guide.call("_tick_craft_station")),
		"a found Crafting Station does not satisfy the craft lesson")
	craft_guide.call("_on_item_crafted", "Crafting Station", 1)
	check(bool(Global.tutorial_flags.get("crafted_station_v3", false))
		and bool(craft_guide.call("_tick_craft_station")),
		"the real craft action verifies and completes the station lesson")
	var inv_src := FileAccess.get_file_as_string("res://scripts/inventory_ui.gd")
	var craft_guide_src := FileAccess.get_file_as_string("res://scripts/tutorial_guide.gd")
	check(inv_src.contains("Global.item_crafted.emit") 
		and craft_guide_src.contains("Global.item_crafted"),
		"craft verification is wired through the real inventory craft path")
	craft_guide.set("_finished", true)
	craft_guide.queue_free()
	Global.tutorial_flags = old_craft_flags
	Global.Hotbar = old_craft_hotbar
	Global.Inventory = old_craft_inventory
	Global.set_hotbar_selection(old_selected)
	await get_tree().process_frame

	# UI focus follows a real target, never captures input, and hides with it.
	var target_root := Control.new()
	add_child(target_root)
	var btn := Button.new()
	btn.text = "CRAFT"
	btn.position = Vector2(80, 90)
	btn.size = Vector2(120, 40)
	target_root.add_child(btn)
	var ui_focus: Control = load("res://scripts/tutorial_ui_target.gd").new() as Control
	target_root.add_child(ui_focus)
	ui_focus.call("set_target", btn, "Tap here to craft.")
	await get_tree().process_frame
	var target_rect: Rect2 = ui_focus.call("_current_rect") as Rect2
	check(ui_focus.visible and ui_focus.mouse_filter == Control.MOUSE_FILTER_IGNORE
		and target_rect == btn.get_global_rect(),
		"tutorial UI highlight follows its target without intercepting input")
	btn.position = Vector2(210, 140)
	await get_tree().process_frame
	check((ui_focus.call("_current_rect") as Rect2) == btn.get_global_rect(),
		"tutorial UI highlight follows a target that moves or reflows")
	btn.visible = false
	await get_tree().process_frame
	check(not ui_focus.visible,
		"tutorial UI highlight hides when its target is no longer visible")
	# A temporarily hidden target must light up again when it returns, even
	# though the guide caches the target across 0.2s verifier ticks.
	var focus_guide: Node = guide_script.new()
	add_child(focus_guide)
	focus_guide.set("_finished", false)
	focus_guide.set("_ui_focus", ui_focus)
	btn.visible = true
	focus_guide.call("_focus_ui", btn, "Tap here to craft.")
	await get_tree().process_frame
	check(ui_focus.visible,
		"tutorial UI highlight returns after a hidden target becomes visible again")
	focus_guide.set("_finished", true)
	focus_guide.queue_free()
	target_root.queue_free()
	await get_tree().process_frame

	# Dungeon route discs must end at the real Quiz Altar and stay on floor.
	var mission: DungeonMissionData = Global.get_dungeon_mission_for_index(
		Global.first_main_dungeon_index("python"))
	if mission != null:
		var overworld := AutoNextOverworld.new()
		add_child(overworld)
		var dun := DungeonWorld.new()
		add_child(dun)
		dun.setup(mission.dungeon_index, mission, 24680 + mission.dungeon_index,
			overworld, Vector2.ZERO)
		await get_tree().process_frame
		var old_player: Node = Global.player_node
		var old_world: Node = Global.world_node
		var p := CharacterBody2D.new()
		p.add_to_group("Player")
		add_child(p)
		p.global_position = dun.call("get_player_spawn_pos") as Vector2
		Global.player_node = p
		Global.world_node = dun
		var route_guide: Node = guide_script.new()
		add_child(route_guide)
		route_guide.set("_finished", true)
		route_guide.set("_world", dun)
		var quiz_world: Vector2 = dun.call("grid_to_world", dun.generator.quiz_altar_pos) as Vector2
		var points: Array = route_guide.call("_build_route_points", quiz_world) as Array
		var endpoint_ok := not points.is_empty() \
			and (points[points.size() - 1] as Vector2).distance_to(quiz_world) < 1.0
		var floor_ok := true
		for point in points:
			var cell: Vector2i = dun.call("world_to_grid", point as Vector2) as Vector2i
			if not bool(dun.call("grid_cell_is_floor", cell)):
				floor_ok = false
		check(endpoint_ok and floor_ok and points.size() > 1,
			"dungeon route markers stay on floor and end at the actual Quiz Altar")
		var route_src := FileAccess.get_file_as_string("res://scripts/tutorial_route_guide.gd")
		check(not route_src.contains("draw_string")
			and not route_src.contains("str(i + 1)"),
			"dungeon route guide uses plain dots without numbers or text")
		route_guide.queue_free()
		p.queue_free()
		Global.player_node = old_player
		Global.world_node = old_world
		dun.queue_free()
		overworld.queue_free()
		await get_tree().process_frame

	# Cave entry/exit and waypoint relocation are driven by verified signals /
	# persisted one-time flags, not timers.
	var game_src := FileAccess.get_file_as_string("res://scenes/game_instance.gd")
	var guide_src := FileAccess.get_file_as_string("res://scripts/tutorial_guide.gd")
	check(game_src.contains("Global.cave_entered.emit") 
		and game_src.contains("Global.cave_exited.emit")
		and game_src.contains("Global.dungeon_exited.emit"),
		"cave and dungeon transitions emit verified tutorial signals")
	check(guide_src.contains("waypoint_relocated") and guide_src.contains("teleport_to_world_waypoint")
		and guide_src.contains("waypoint_lesson_done") and guide_src.contains("cave_%s_entered"),
		"cave and waypoint lessons persist one-time progress and use the real systems")
	check(guide_src.contains("var inspected := bool(Global.tutorial_flags.get(\"cave_%s_inspected\"")
		and guide_src.contains("if not inspected:"),
		"cave lessons run exactly one verified ore interaction before the exit objective")
	var tree_world_src := FileAccess.get_file_as_string("res://scripts/world.gd")
	check(guide_src.contains("_begin_cave_travel")
		and guide_src.contains("cave_regular_relocated")
		and guide_src.contains("cave_pixie_relocated")
		and tree_world_src.contains("tutorial_teleport_near_cave"),
		"cave and Pixie lessons relocate safely to their entrance once")
	check(not guide_src.contains("_spawn_tutorial_tree")
		and not guide_src.contains("_world.call(\"_spawn_tree\"")
		and guide_src.contains("var best_plain")
		and guide_src.contains("Walk to the tree.")
		and tree_world_src.contains("(_tree_spatial[spatial_key] as Array).append(tree)"),
		"tree lesson points at existing trees and runtime trees join the interaction cache")
	check(tree_world_src.contains("var scene_tree := get_tree()")
		and tree_world_src.contains("if scene_tree == null or not is_inside_tree()")
		and tree_world_src.contains("_abort_waypoint_recall"),
		"waypoint recall aborts safely while the overworld is off-tree")
	check(guide_src.contains("_world.call(\"placed_node\"")
		and guide_src.contains("Making room to rebuild it"),
		"camp furnace recovery re-adopts restored stations before reporting failure")

	# Calling the deferred recall on an off-tree overworld must not reach
	# get_tree().create_timer() (the null-tree crash reported in world.gd).
	var off_world: Node2D = load("res://scripts/world.gd").new() as Node2D
	var old_off_player: Node = Global.player_node
	var dummy_player := CharacterBody2D.new()
	add_child(dummy_player)
	Global.player_node = dummy_player
	off_world.set("_waypoint_teleporting", true)
	off_world.call("_run_waypoint_recall", Vector2.ZERO)
	await get_tree().process_frame
	check(not bool(off_world.get("_waypoint_teleporting")),
		"off-tree waypoint recall exits before using a null SceneTree")
	off_world.free()
	dummy_player.queue_free()
	Global.player_node = old_off_player
	await get_tree().process_frame

	# An open hint must keep the quiz tutorial on NEXT; only after the hint is
	# dismissed may it advance to RUN / answer selection.
	var hint_branch := guide_src.find("if hint_open:")
	var demo_branch := guide_src.find(
		"var demo_done := bool(Global.tutorial_flags.get(\"quiz_hint_demo\"")
	check(hint_branch >= 0 and demo_branch > hint_branch
		and guide_src.contains("Tap NEXT to hide the hint.")
		and guide_src.contains("Tap RUN to check the hinted code.")
		and guide_src.contains("tutorial_hint_run_failed")
		and guide_src.contains("tutorial_code_text")
		and guide_src.contains("Tap HINT to prepare the code."),
		"dungeon quiz tutorial hints then runs; NEXT follows a failed hinted run")

	# Leaving a cave before the interaction must not complete the lesson, and
	# the verified interaction unlocks the normal exit completion.
	var cave_req: Node = guide_script.new()
	add_child(cave_req)
	cave_req.set("_finished", false)
	cave_req.set("_step_complete", false)
	cave_req.set("_current_step", steps.find("cave_regular"))
	var old_cave_flags: Dictionary = Global.tutorial_flags.duplicate(true)
	var old_cave_stage: int = Global.tutorial_stage
	var old_cave_slot: int = Global.active_save_slot
	Global.active_save_slot = -1
	Global.tutorial_flags.clear()
	Global.tutorial_stage = steps.find("cave_regular")
	cave_req.call("_on_cave_exited", "cave")
	check(int(cave_req.get("_current_step")) == steps.find("cave_regular")
		and not bool(Global.tutorial_flags.get("cave_cave_done", false)),
		"leaving a cave before its interaction does not falsely complete the lesson")
	Global.tutorial_flags["cave_cave_inspected"] = true
	cave_req.call("_on_cave_exited", "cave")
	check(int(cave_req.get("_current_step")) == steps.find("cave_pixie")
		and bool(Global.tutorial_flags.get("cave_cave_done", false))
		and int(Global.tutorial_stage) == steps.find("cave_pixie"),
		"a verified cave interaction lets the real exit complete the lesson")
	cave_req.set("_finished", true)
	cave_req.queue_free()
	Global.tutorial_flags = old_cave_flags
	Global.tutorial_stage = old_cave_stage
	Global.active_save_slot = old_cave_slot
	await get_tree().process_frame

	# Programming lessons require the real run result, not just opening a
	# panel. RichTextLabel output is read with get_parsed_text() because
	# append_text() does not populate the .text getter.
	var lua_editor_src := FileAccess.get_file_as_string("res://scripts/lua_editor_ui.gd")
	var furnace_panel_src := FileAccess.get_file_as_string(
		"res://scripts/furnace_programming_panel.gd")
	check(lua_editor_src.contains("get_parsed_text")
		and furnace_panel_src.contains("get_parsed_text")
		and guide_src.contains("build_line")
		and guide_src.contains("combat_mode(true)")
		and guide_src.contains("output.contains(\"Algorithmica ready\")"),
		"Automatica lessons verify the real build, combat and Algorithmica run results")
	check(lua_editor_src.contains("build_line(-15, -8, 16, -8)")
		and guide_src.contains("Automatica can do tasks for you")
		and guide_src.contains("automatica_combat_kit"),
		"the tutorial demonstrates a 32-block Automatica task and explains what it can do")
	check(guide_src.contains("_tick_automatica_combat")
		and guide_src.contains("_grant_automatica_combat_kit")
		and guide_src.contains("tutorial_tool_slot")
		and guide_src.contains("is_combat")
		and guide_src.contains("_find_second_automatica"),
		"the combat lesson guides the player through tool assignment and combat_mode(true)")


func _test_stat_hud_layout() -> void:
	var old_scale: float = Global.ui_scale
	var old_viewport: Vector2 = Global.ui_viewport_size
	var old_insets: Vector4 = Global.ui_safe_insets
	Global.ui_scale = 1.0
	Global.ui_viewport_size = Vector2(1152, 648)
	Global.ui_safe_insets = Vector4.ZERO

	var pause := Button.new()
	pause.position = Vector2(300, 20)
	pause.size = Vector2(96, 40)
	add_child(pause)
	await get_tree().process_frame
	var summary: Control = load("res://scripts/star_summary_ui.gd").new()
	add_child(summary)
	summary.call("setup", pause)
	await get_tree().process_frame
	var panel: PanelContainer = summary.get("_panel") as PanelContainer
	var row: HBoxContainer = summary.get("_row") as HBoxContainer
	var one_line := row != null and row.get_child_count() == 3
	if one_line:
		for i in range(2):
			var chip := row.get_child(i)
			one_line = chip is HBoxContainer \
				and (chip as HBoxContainer).get_child_count() == 2
	check(one_line,
		"star totals sit on one line as blue + yellow chips plus a suffix")
	# Put PAUSE far enough right that the summary has room, then verify it is
	# directly to its left and vertically centred rather than stacked below.
	var panel_size := panel.get_combined_minimum_size()
	pause.position = Vector2(panel_size.x + 40.0, 20.0)
	summary.call("_refit")
	var pause_rect: Rect2 = pause.get_global_rect()
	var summary_rect: Rect2 = panel.get_global_rect()
	check(summary_rect.end.x <= pause_rect.position.x
		and absf(summary_rect.get_center().y - pause_rect.get_center().y) < 2.0,
		"star summary sits directly left of PAUSE and vertically centred")
	summary.queue_free()
	pause.queue_free()
	await get_tree().process_frame

	var mission_src := FileAccess.get_file_as_string("res://scripts/mission_ui.gd")
	check(not mission_src.contains("_refresh_star_header")
		and not mission_src.contains("_stars_row")
		and mission_src.contains("const TOP_OFFSET    := 30.0"),
		"the mission tracker is raised and no longer duplicates the star header")

	var hotbar_consts: Dictionary = load("res://scripts/hotbar.gd").get_script_constant_map()
	var hotbar_src := FileAccess.get_file_as_string("res://scripts/hotbar.gd")
	check(float(hotbar_consts.get("HP_BAR_H", 0.0)) >= 20.0
		and float(hotbar_consts.get("SP_BAR_H", 0.0)) >= 16.0
		and hotbar_src.contains("HP  %d / %d")
		and hotbar_src.contains("STAMINA  %d / %d"),
		"HP/stamina bars are thicker and show current / max values")

	Global.ui_scale = old_scale
	Global.ui_viewport_size = old_viewport
	Global.ui_safe_insets = old_insets


func _test_stat_crystals() -> void:
	var life := load("res://resources/items/life_crystal.tres") as ItemData
	var stamina := load("res://resources/items/stamina_crystal.tres") as ItemData
	check(life != null and stamina != null
		and life.item_type == "consumable" and stamina.item_type == "consumable"
		and is_equal_approx(life.max_health_bonus, 10.0)
		and is_equal_approx(stamina.max_stamina_bonus, 10.0)
		and is_zero_approx(life.heal_amount) and is_zero_approx(stamina.heal_amount)
		and life.icon != null and stamina.icon != null,
		"Life/Stamina Crystals are hotbar consumables worth +10 permanent stats")

	var old_hotbar: Array = Global.Hotbar.duplicate(true)
	var old_inventory: Array = Global.Inventory.duplicate(true)
	var old_selected: int = Global.hotbar_selected
	var old_health: float = Global.health
	var old_max_health: float = Global.max_health
	var old_stamina: float = Global.stamina
	var old_max_stamina: float = Global.max_stamina
	var old_missions: Array = Global.missions.duplicate(true)
	var old_cleared: Dictionary = Global.cleared_dungeons.duplicate(true)
	var old_stars: Dictionary = Global.dungeon_stars.duplicate(true)
	Global.Hotbar.fill(null)
	Global.Inventory.fill(null)
	Global.hotbar_selected = 0

	# Base values, then the +10/+10 rule (maximum and current rise together).
	Global.reset_player_stats()
	check(is_equal_approx(Global.max_health, Global.BASE_MAX_HEALTH)
		and is_equal_approx(Global.health, Global.BASE_MAX_HEALTH)
		and is_equal_approx(Global.max_stamina, Global.BASE_MAX_STAMINA)
		and is_equal_approx(Global.stamina, Global.BASE_MAX_STAMINA),
		"new worlds start at 100 HP / 50 stamina")
	Global.health = 90.0
	check(is_equal_approx(Global.increase_max_health(10.0), 10.0)
		and is_equal_approx(Global.max_health, 110.0)
		and is_equal_approx(Global.health, 100.0),
		"a Life Crystal raises max and current health by 10")
	Global.stamina = 40.0
	check(is_equal_approx(Global.increase_max_stamina(10.0), 10.0)
		and is_equal_approx(Global.max_stamina, 60.0)
		and is_equal_approx(Global.stamina, 50.0),
		"a Stamina Crystal raises max and current stamina by 10")

	# Caps: partial gain at the boundary, none beyond it.
	Global.max_health = 495.0
	Global.health = 495.0
	check(is_equal_approx(Global.increase_max_health(10.0), 5.0)
		and is_equal_approx(Global.max_health, Global.MAX_HEALTH_CAP)
		and is_equal_approx(Global.health, Global.MAX_HEALTH_CAP)
		and is_zero_approx(Global.increase_max_health(10.0))
		and is_equal_approx(Global.max_health, 500.0),
		"health growth clamps at the 500 maximum")
	Global.max_stamina = 995.0
	Global.stamina = 995.0
	check(is_equal_approx(Global.increase_max_stamina(10.0), 5.0)
		and is_equal_approx(Global.max_stamina, Global.MAX_STAMINA_CAP)
		and is_equal_approx(Global.stamina, Global.MAX_STAMINA_CAP)
		and is_zero_approx(Global.increase_max_stamina(10.0))
		and is_equal_approx(Global.max_stamina, 1000.0),
		"stamina growth clamps at the 1000 maximum")

	# Using the crystal from the hotbar consumes exactly one item. At the cap
	# the click is swallowed and the crystal stays in the slot.
	Global.reset_player_stats()
	var player: Node = load("res://scripts/player.gd").new()
	Global.Hotbar[0] = {"data": life, "quantity": 1}
	player.call("_try_use_stat_crystal", life)
	check(Global.count_item(life) == 0
		and is_equal_approx(Global.max_health, 110.0)
		and is_equal_approx(Global.health, 110.0),
		"using a hotbar Life Crystal consumes it and applies +10")
	Global.Hotbar[0] = {"data": stamina, "quantity": 1}
	player.call("_try_use_stat_crystal", stamina)
	check(Global.count_item(stamina) == 0
		and is_equal_approx(Global.max_stamina, 60.0)
		and is_equal_approx(Global.stamina, 60.0),
		"using a hotbar Stamina Crystal consumes it and applies +10")
	Global.max_health = Global.MAX_HEALTH_CAP
	Global.health = Global.MAX_HEALTH_CAP
	Global.Hotbar[0] = {"data": life, "quantity": 1}
	player.call("_try_use_stat_crystal", life)
	check(Global.count_item(life) == 1
		and is_equal_approx(Global.max_health, Global.MAX_HEALTH_CAP),
		"a crystal at the stat cap is not consumed")

	# Point-and-click click routing: a usable held item is consumed/used
	# instead of starting a move or interaction order.
	Global.reset_player_stats()
	Global.Hotbar[0] = {"data": life, "quantity": 1}
	Global.hotbar_selected = 0
	check(bool(player.call("_held_item_is_usable")),
		"a Life Crystal reports as a usable PnC click item")
	player.call("_pnc_use_held_item", Vector2.ZERO)
	check(Global.count_item(life) == 0
		and is_equal_approx(Global.max_health, 110.0),
		"PnC use path consumes the held crystal instead of issuing an order")
	var wood_data: ItemData = load("res://resources/items/wood.tres")
	Global.Hotbar[0] = {"data": wood_data, "quantity": 1}
	check(not bool(player.call("_held_item_is_usable")),
		"non-usable held items keep the normal PnC movement order")
	var player_src := FileAccess.get_file_as_string("res://scripts/player.gd")
	check(player_src.contains("if _held_item_is_usable():")
		and player_src.contains("_pnc_use_held_item"),
		"the PnC input branch tries usable items before move/interact")
	player.free()

	# One 10% total roll per mob, then a 50/50 Life/Stamina pick. Forced values
	# make both branches deterministic without relying on RNG.
	var drop_parent := Node2D.new()
	add_child(drop_parent)
	check(Global.spawn_mob_crystal_drop(drop_parent, Vector2.ZERO, 0.11, 0.0) == null,
		"a mob crystal roll above 10% drops nothing")
	var life_drop: Node = Global.spawn_mob_crystal_drop(
		drop_parent, Vector2.ZERO, 0.10, 0.25)
	var stamina_drop: Node = Global.spawn_mob_crystal_drop(
		drop_parent, Vector2.ZERO, 0.10, 0.75)
	check(life_drop != null and life_drop.get("item_data") == life
		and stamina_drop != null and stamina_drop.get("item_data") == stamina,
		"the 10% mob roll picks one crystal with a 50/50 Life/Stamina choice")
	drop_parent.queue_free()

	# First dungeon completion grants one of each; a repeat clear grants none.
	Global.reset_player_stats()
	Global.Hotbar.fill(null)
	Global.Inventory.fill(null)
	var dungeon_index: int = 987
	Global.cleared_dungeons.erase(dungeon_index)
	Global.dungeon_stars.erase(dungeon_index)
	Global.record_dungeon_clear(dungeon_index, 3)
	check(Global.count_item(life) == 1 and Global.count_item(stamina) == 1,
		"the first dungeon clear rewards one Life and one Stamina Crystal")
	Global.record_dungeon_clear(dungeon_index, 3)
	check(Global.count_item(life) == 1 and Global.count_item(stamina) == 1,
		"re-clearing a dungeon does not duplicate crystal rewards")
	Global.cleared_dungeons.erase(dungeon_index)
	Global.dungeon_stars.erase(dungeon_index)

	# Restore every piece of shared state this test touched.
	Global.reset_player_stats()
	Global.health = old_health
	Global.max_health = old_max_health
	Global.stamina = old_stamina
	Global.max_stamina = old_max_stamina
	Global.missions = old_missions
	Global.cleared_dungeons = old_cleared
	Global.dungeon_stars = old_stars
	Global.hotbar_selected = old_selected
	Global.Hotbar.fill(null)
	for i in range(mini(old_hotbar.size(), Global.Hotbar.size())):
		Global.Hotbar[i] = old_hotbar[i]
	Global.Inventory.fill(null)
	for i in range(mini(old_inventory.size(), Global.Inventory.size())):
		Global.Inventory[i] = old_inventory[i]
	Global.Hotbar_updated.emit()
	Global.Inventory_updated.emit()


func _test_triggers() -> void:
	Global.reset_missions()
	var star_ids: Array = []
	var on_star := func(id: String) -> void: star_ids.append(id)
	Global.mission_star_earned.connect(on_star)
	Global.record_dungeon_clear(50, 3)
	check(bool(Global._find_mission("clear_dungeon").get("completed", false)),
		"dungeon clear completes Clear a Dungeon")
	check(Global.dungeon_stars_for(50) == 3
		and Global.local_blue_stars() == 3
		and star_ids.has("dungeon_clear:50")
		and star_ids.has("dungeon_clear_bonus:50"),
		"perfect dungeon clears award three blue stars")
	Global.mission_star_earned.disconnect(on_star)
	# 1 hint = 2 stars; 2+ hints = 1 star.
	Global.cleared_dungeons[51] = true
	Global.dungeon_stars[51] = 2
	Global.cleared_dungeons[52] = true
	Global.dungeon_stars[52] = 1
	Global.cleared_dungeons[53] = true
	Global.dungeon_stars[53] = 0
	check(Global.dungeon_stars_for(51) == 2
		and Global.dungeon_stars_for(52) == 1
		and Global.dungeon_stars_for(53) == 0
		and Global.local_blue_stars() == 6,
		"penalties award 2 / 1 / 0 blue stars while zero-star clears still complete")
	Global.cleared_dungeons.erase(53)
	Global.dungeon_stars.erase(53)
	# First-dungeon hints are free; later hints and wrong runs each charge once.
	var first_idx: int = Global.first_main_dungeon_index("python")
	var other_idx: int = Global.first_main_dungeon_index("lua")
	var old_hints := Global.dungeon_quiz_hints.duplicate(true)
	var old_penalties := Global.dungeon_quiz_penalties.duplicate(true)
	var old_cleared := Global.cleared_dungeons.duplicate(true)
	var old_stars := Global.dungeon_stars.duplicate(true)
	Global.dungeon_quiz_hints.clear()
	Global.dungeon_quiz_penalties.clear()
	Global.cleared_dungeons.clear()
	Global.dungeon_stars.clear()
	check(Global.record_quiz_hint(first_idx) == 0
		and Global.dungeon_quiz_hints_for(first_idx) == 1
		and Global.dungeon_quiz_penalties_for(first_idx) == 0,
		"first-dungeon hints are free")
	Global.cleared_dungeons[first_idx] = true
	Global.dungeon_stars[first_idx] = 3
	check(Global.record_quiz_hint(other_idx) == 1
		and Global.dungeon_quiz_penalties_for(other_idx) == 1,
		"later-dungeon hints charge one blue star")
	check(Global.record_quiz_mistake(other_idx) == 1
		and Global.dungeon_quiz_penalties_for(other_idx) == 2,
		"wrong code submissions charge one blue star")
	Global.dungeon_quiz_hints = old_hints
	Global.dungeon_quiz_penalties = old_penalties
	Global.cleared_dungeons = old_cleared
	Global.dungeon_stars = old_stars
	Global.cleared_dungeons.erase(51)
	Global.dungeon_stars.erase(51)
	Global.cleared_dungeons.erase(52)
	Global.dungeon_stars.erase(52)
	# Legacy cleared saves without a stored award count as perfect clears.
	Global.cleared_dungeons[53] = true
	check(Global.dungeon_stars_for(53) == 3,
		"legacy dungeon clears default to three blue stars")
	Global.cleared_dungeons.erase(53)
	Global.reset_missions()

	Global.reset_missions()
	var entry: KnowledgeEntry = null
	for e in Global.knowledge_entries.values():
		entry = e as KnowledgeEntry
		if entry != null:
			break
	if entry != null:
		Global.learn_entry(entry)
		check(bool(Global._find_mission("learn_entry").get("completed", false)),
			"learning an entry completes Learn a Knowledge Entry")
	else:
		check(false, "knowledge entries loaded for the learn_entry trigger")

	# A clean Lua run in the dungeon quiz must complete "Run your first Lua
	# program" (not just a run from the robot editor).
	Global.reset_missions()
	var lua_mission: DungeonMissionData = null
	var lua_question: DungeonQuestion = null
	for m in Global.dungeon_missions.values():
		var dm := m as DungeonMissionData
		if dm == null:
			continue
		for q in dm.questions:
			var dq := q as DungeonQuestion
			if dq != null and dq.language == "lua":
				lua_mission = dm
				lua_question = dq
				break
		if lua_question != null:
			break
	if lua_mission != null and lua_question != null:
		var quiz := QuizAltar.new()
		add_child(quiz)
		quiz.setup(lua_mission)
		quiz.set("_compiler_q", lua_question)
		quiz.set("_accept_results", true)
		quiz.call("_start_quiz")
		quiz.call("_on_quiz_executed")
		await get_tree().create_timer(0.6).timeout
		check(bool(Global._find_mission("run_program").get("completed", false)),
			"dungeon quiz run completes Run your first Lua program")
		quiz.free()
	else:
		check(false, "Lua dungeon question available for the quiz trigger test")


func _test_pause_and_build() -> void:
	Global.open_ui()
	check(Global.any_ui_open() and get_tree().paused, "open_ui pauses the tree")
	Global.reset_pause_state()
	check(not Global.any_ui_open() and not get_tree().paused,
		"reset_pause_state releases a leaked UI")

	# An altar freed with the dungeon must release its UI pause.
	var mission: DungeonMissionData = null
	for m in Global.dungeon_missions.values():
		var dm := m as DungeonMissionData
		if dm != null and not dm.questions.is_empty():
			mission = dm
			break
	if mission != null:
		var altar := QuizAltar.new()
		add_child(altar)
		altar.setup(mission)
		altar.call("_start_quiz")
		await get_tree().process_frame
		var opened: bool = Global.any_ui_open()
		var paused_while_open: bool = get_tree().paused
		altar.free()
		await get_tree().process_frame
		check(opened and paused_while_open, "quiz panel registers a UI pause and pauses the tree")
		check(not Global.any_ui_open() and not get_tree().paused,
			"freeing a dungeon altar releases the pause")
	else:
		check(false, "quiz mission available for altar teardown test")

	# Dungeon exit restores interaction state, releases focus and unpauses.
	var field := LineEdit.new()
	add_child(field)
	field.grab_focus()
	var focus := get_viewport().gui_get_focus_owner()
	Global.is_in_dungeon = true
	Global.block_mode = true
	Global.open_ui()
	Global.restore_overworld_interaction_state()
	check(not Global.is_in_dungeon and not Global.block_mode
		and not Global.any_ui_open() and not get_tree().paused,
		"dungeon-exit restore clears pause and build mode")
	check(focus == null or not is_instance_valid(focus) or not focus.has_focus(),
		"dungeon-exit restore releases stale text focus")
	field.queue_free()

	Global.is_in_dungeon = true
	Global.toggle_build_mode()
	check(not Global.block_mode, "build mode stays disabled inside dungeons")
	Global.restore_overworld_interaction_state()
	Global.toggle_build_mode()
	check(Global.block_mode, "build mode enables after leaving a dungeon")
	Global.toggle_build_mode()
	check(not Global.block_mode, "build mode disables again in the overworld")


func _test_world_eligibility() -> void:
	check(Global.version_at_least("0.9.3.1", "0.9.3.0"), "version compare accepts 0.9.3.1")
	check(not Global.version_at_least("0.9.2.9", "0.9.3.0"), "version compare rejects 0.9.2.9")
	check(not Global.version_at_least("", "0.9.3.0"), "missing version is ineligible")

	var old_slot: int = Global.next_free_slot()
	if old_slot <= 0:
		print("NOTE: no free save slot; eligibility file test skipped")
		return
	_write_world(old_slot, "Legacy World", "0.9.2.0")
	check(not Global.world_progress_eligible(old_slot),
		"world created before 0.9.3.0 is not leaderboard-eligible")
	Global.delete_world(old_slot)

	var new_slot: int = Global.next_free_slot()
	if new_slot <= 0:
		return
	_write_world(new_slot, "New World", "0.9.3.1")
	check(Global.world_progress_eligible(new_slot),
		"world created at/after 0.9.3.0 is leaderboard-eligible")
	Global.delete_world(new_slot)


func _test_dungeon_generation() -> void:
	var gen := DungeonGenerator.new()
	var margins_ok := true
	var traps_ok := true
	var guards_ok := true
	var quiz_traps_ok := true
	var traps_total := 0
	for seed_value in range(0, 12):
		gen.generate(seed_value, 0, 1, 0)
		for room in [gen.knowledge_room, gen.quiz_room, gen.entrance_room]:
			var pos: Vector2i = room["pos"]
			var size: Vector2i = room["size"]
			if pos.x < DungeonGenerator.ROOM_EDGE_MARGIN \
					or pos.y < DungeonGenerator.ROOM_EDGE_MARGIN \
					or pos.x + size.x > gen.width - DungeonGenerator.ROOM_EDGE_MARGIN \
					or pos.y + size.y > gen.height - DungeonGenerator.ROOM_EDGE_MARGIN:
				margins_ok = false
		if gen.quiz_guard_positions.size() > 2:
			guards_ok = false
		for t in gen.quiz_trap_positions:
			if gen._touches_room_opening(t as Vector2i, gen.quiz_room):
				quiz_traps_ok = false
		for t in gen.trap_positions:
			traps_total += 1
			var cell := t as Vector2i
			if gen._floor_neighbours(cell) < DungeonGenerator.TRAP_MIN_FLOOR_NEIGHBOURS:
				traps_ok = false
			if Vector2(cell).distance_to(Vector2(gen.player_spawn_pos)) < DungeonGenerator.TRAP_SPAWN_CLEARANCE:
				traps_ok = false
			for room in [gen.knowledge_room, gen.quiz_room, gen.entrance_room]:
				if gen._dist_to_room(cell, room) <= DungeonGenerator.TRAP_ROOM_CLEARANCE:
					traps_ok = false
	check(margins_ok, "dungeon rooms keep the enlarged edge margin")
	check(traps_ok, "dungeon traps stay clear of rooms, spawn and narrow passages")
	check(traps_total > 0, "valid traps still spawn elsewhere")
	check(guards_ok, "quiz rooms generate at most two hitman guards")
	check(quiz_traps_ok, "quiz traps avoid corridor openings")

	var cam := DungeonWorld.camera_rect_for(64, 64)
	var expected := (64.0 + 2.0 * DungeonWorld.CAMERA_WALL_PADDING_TILES) * 32.0
	check(is_equal_approx(cam.size.x, expected) and is_equal_approx(cam.size.y, expected),
		"dungeon camera bounds include the wall padding")


func _test_dungeon_altar_coverage() -> void:
	# Base pair: every seed must produce distinct, walkable Knowledge/Quiz cells.
	var pair_ok := true
	var extra_ok := true
	for seed_value in range(0, 40):
		var pair_gen := DungeonGenerator.new()
		pair_gen.generate(seed_value, 0, 1, 2)
		var k: Vector2i = pair_gen.knowledge_altar_pos
		var q: Vector2i = pair_gen.quiz_altar_pos
		if k == q or pair_gen.grid[k.x][k.y] != DungeonGenerator.Tile.FLOOR \
				or pair_gen.grid[q.x][q.y] != DungeonGenerator.Tile.FLOOR:
			pair_ok = false

		var extra_gen := DungeonGenerator.new()
		extra_gen.generate(seed_value, 0, 2, 2)
		if extra_gen.extra_altar_positions.size() != 1:
			extra_ok = false
		for pos_value in extra_gen.extra_altar_positions:
			var pos: Vector2i = pos_value as Vector2i
			if extra_gen.grid[pos.x][pos.y] != DungeonGenerator.Tile.FLOOR \
					or pos == extra_gen.knowledge_altar_pos \
					or pos == extra_gen.quiz_altar_pos:
				extra_ok = false
	check(pair_ok, "every dungeon seed reserves a distinct walkable Knowledge/Quiz altar pair")
	check(extra_ok, "altar_amount=2 reserves a distinct walkable extra Knowledge altar cell")

	# Real world: Python 5 declares altar_amount=2, so it must contain a second
	# Knowledge Altar instead of an empty checkpoint room.
	var idx: int = 5
	var mission: DungeonMissionData = Global.get_dungeon_mission_for_index(idx)
	if mission == null:
		check(false, "dungeon altar coverage mission available")
		return
	var dun := DungeonWorld.new()
	add_child(dun)
	dun.setup(idx, mission, 24680, null, Vector2.ZERO)
	await get_tree().process_frame
	var knowledge := 0
	var quizzes := 0
	var altar_positions: Array = []
	for child in dun.get_children():
		if child.is_in_group("KnowledgeAltar"):
			knowledge += 1
			altar_positions.append((child as Node2D).global_position)
		elif child.is_in_group("QuizAltar"):
			quizzes += 1
			altar_positions.append((child as Node2D).global_position)
	check(knowledge == 2 and quizzes == 1,
		"a dungeon with altar_amount=2 spawns two Knowledge altars and one Quiz altar")
	var unique_positions: Dictionary = {}
	for pos_value in altar_positions:
		unique_positions[(pos_value as Vector2).snapped(Vector2(1, 1))] = true
	check(unique_positions.size() == altar_positions.size(),
		"spawned dungeon altars occupy distinct interaction cells")
	var knowledge_region := Rect2()
	var quiz_region := Rect2()
	for child in dun.get_children():
		var is_knowledge: bool = child.is_in_group("KnowledgeAltar")
		var is_quiz: bool = child.is_in_group("QuizAltar")
		if not is_knowledge and not is_quiz:
			continue
		for sub in child.get_children():
			if sub is Sprite2D and (sub as Sprite2D).texture is AtlasTexture:
				var region: Rect2 = ((sub as Sprite2D).texture as AtlasTexture).region
				if is_knowledge and knowledge_region == Rect2():
					knowledge_region = region
				elif is_quiz and quiz_region == Rect2():
					quiz_region = region
	check(knowledge_region == Rect2(288, 96, 32, 32)
		and quiz_region == Rect2(352, 96, 32, 32),
		"dungeon altar sprites use the visible altar art instead of floor-tile regions")
	var altars_before := knowledge + quizzes
	dun.call("_spawn_altars")
	var altars_after := 0
	for child in dun.get_children():
		if child.is_in_group("KnowledgeAltar") or child.is_in_group("QuizAltar"):
			altars_after += 1
	check(altars_after == altars_before,
		"re-running altar spawn does not duplicate dungeon altars")
	dun.queue_free()
	await get_tree().process_frame


func _test_first_dungeon_tutorial() -> void:
	var py_first: int = Global.first_main_dungeon_index("python")
	var lua_first: int = Global.first_main_dungeon_index("lua")
	check(py_first == 1 and lua_first == 11,
		"the first main dungeon is identified per language")
	var py_first_mission: DungeonMissionData = Global.get_dungeon_mission_for_index(py_first)
	var py_all_compiler := py_first_mission != null and py_first_mission.questions.size() == 2
	if py_first_mission != null:
		for q in py_first_mission.questions:
			if q == null or q.type != DungeonQuestion.Type.COMPILER:
				py_all_compiler = false
	check(py_all_compiler,
		"the first Python dungeon has two compiler questions and no multiple-choice question")
	var quiz_guide_src := FileAccess.get_file_as_string("res://scripts/tutorial_guide.gd")
	check(quiz_guide_src.contains("_focus_ui(answers, \"\")")
		and quiz_guide_src.contains("_focus_ui(answers_hint, \"\")")
		and not quiz_guide_src.contains("Choose the correct answer."),
		"quiz tutorial highlights the answers without a label over the question")
	var py_rewards_ok := true
	for idx in range(1, 11):
		var pm := Global.get_dungeon_mission_for_index(idx)
		if pm == null or pm.reward_item_path != "res://resources/items/cpu.tres":
			py_rewards_ok = false
	check(py_rewards_ok,
		"Python dungeon rewards use the Algorithmica CPU instead of the Lua station item")
	var lua_station_entry := Global.get_knowledge_entry_file("entry_37_lua.tres")
	var lua_items_entry := Global.get_knowledge_entry_file("entry_39_lua.tres")
	var python_join_entry := Global.get_knowledge_entry_file("entry_7_python.tres")
	check(lua_station_entry != null and lua_station_entry.keyword == "set_recipe"
		and lua_items_entry != null and lua_items_entry.keyword == "list_items"
		and python_join_entry != null and python_join_entry.keyword == "join",
		"lesson entries teach supported Lua station/item APIs and Python string joining")
	check(Global.is_first_main_dungeon(py_first)
		and Global.is_first_main_dungeon(lua_first)
		and not Global.is_first_main_dungeon(py_first + 1),
		"only the first main dungeon of each language is marked tutorial")

	for theme in ["lua", "python"]:
		var themed: Dictionary = DungeonWorld._get_theme_tile_data(theme)
		check(themed.get("tileset") != null
			and (themed.get("wall_cells", {}) as Dictionary).size() == 11
			and (themed.get("floor_cells", []) as Array).size() == 5,
			"%s dungeon theme loads 11 walls and 5 floors" % theme)
		var sconce_tex := load("res://sprites/dungeon/%s/sconce_sheet.png" % theme) as Texture2D
		var medallion_tex := load("res://sprites/dungeon/%s/medallion_sheet.png" % theme) as Texture2D
		var sconce_frames := WaypointAnim.build(sconce_tex, Vector2i(16, 32))
		var medallion_frames := WaypointAnim.build(medallion_tex, Vector2i(64, 64))
		check(sconce_tex != null and medallion_tex != null
			and sconce_frames.get_frame_count("idle") == 8
			and medallion_frames.get_frame_count("idle") == 8
			and is_equal_approx(sconce_frames.get_animation_speed("idle"), 10.0)
			and is_equal_approx(medallion_frames.get_animation_speed("idle"), 10.0),
			"%s sconces and floor medallions are 8-frame 10 fps animations" % theme)
		var arch_paths: Dictionary = DungeonWorld.THEME_ARCH_PATHS.get(theme, {}) as Dictionary
		var missing_arch := false
		for arch_path in arch_paths.values():
			if not ResourceLoader.exists(str(arch_path)):
				missing_arch = true
		check(arch_paths.size() == 7 and not missing_arch,
			"%s themed architecture and animation assets are present" % theme)

	var gen := DungeonGenerator.new()
	gen.generate_tutorial(24680)
	var knowledge_center: Vector2i = gen._room_center(gen.knowledge_room)
	var quiz_center: Vector2i = gen._room_center(gen.quiz_room)
	check(gen.entrance_room["pos"] == gen.knowledge_room["pos"]
		and gen.entrance_room["size"] == gen.knowledge_room["size"],
		"tutorial room one is both the entrance and Knowledge room")
	check(knowledge_center != quiz_center and gen.bonus_rooms.is_empty()
		and gen.flare_positions.is_empty() and gen.trap_positions.is_empty()
		and gen.quiz_guard_positions.is_empty()
		and gen.quiz_trap_positions.is_empty()
		and gen.rare_chest_positions.is_empty(),
		"tutorial generation has exactly two rooms and no hazards, guards, or bonus rooms")
	check(gen.grid[gen.knowledge_altar_pos.x][gen.knowledge_altar_pos.y]
			== DungeonGenerator.Tile.FLOOR
		and gen.grid[gen.quiz_altar_pos.x][gen.quiz_altar_pos.y]
			== DungeonGenerator.Tile.FLOOR
		and gen.grid[gen.player_spawn_pos.x][gen.player_spawn_pos.y]
			== DungeonGenerator.Tile.FLOOR,
		"tutorial spawn and both altars sit on walkable floor")

	for lang in ["python", "lua"]:
		var idx: int = int(py_first if lang == "python" else lua_first)
		var mission: DungeonMissionData = Global.get_dungeon_mission_for_index(idx)
		var overworld := AutoNextOverworld.new()
		add_child(overworld)
		var dun := DungeonWorld.new()
		add_child(dun)
		dun.setup(idx, mission, 13579 + idx, overworld, Vector2.ZERO)
		await get_tree().process_frame
		var sconce_anims := _count_dungeon_anims(dun, Vector2(16, 32))
		var medallion_anims := _count_dungeon_anims(dun, Vector2(64, 64))
		check(str(dun.get("_theme")) == lang
			and (dun.get("_theme_wall_cells") as Dictionary).size() == 11
			and (dun.get("_theme_floor_cells") as Array).size() == 5,
			"%s dungeon uses its themed runtime tileset" % lang)
		check(sconce_anims >= 1 and medallion_anims >= 1
			and (dun.get("_theme_lights") as Array).size() >= sconce_anims,
			"%s dungeon spawns animated sconces, medallions and local lights" % lang)
		# Medallions are floor decals. Actors y-sort into negative buckets above
		# world origin, so a medallion left at z=-2 could draw over the player.
		var medallion_layers := 0
		var medallion_z_ok := true
		for child in dun.get_children():
			var root2d := child as Node2D
			if root2d == null:
				continue
			for sub in child.get_children():
				var anim := sub as AnimatedSprite2D
				if anim == null or anim.sprite_frames == null \
						or not anim.sprite_frames.has_animation("idle") \
						or anim.sprite_frames.get_frame_count("idle") != 8:
					continue
				var frame := anim.sprite_frames.get_frame_texture("idle", 0) as AtlasTexture
				if frame == null or frame.region.size != Vector2(64, 64):
					continue
				medallion_layers += 1
				if root2d.z_index > -200 or root2d.z_index <= -300:
					medallion_z_ok = false
		check(medallion_layers >= 1 and medallion_z_ok,
			"%s floor medallions sort above the tilemap but below actors" % lang)
		check((dun.get("_architecture_blocked") as Dictionary).size() > 0,
			"%s dungeon registers solid pillar bases for navigation" % lang)
		var knowledge := 0
		var quizzes := 0
		var hitmen := 0
		var traps := 0
		var flares := 0
		for child in dun.get_children():
			if child.is_in_group("KnowledgeAltar"):
				knowledge += 1
			if child.is_in_group("QuizAltar"):
				quizzes += 1
			if child.is_in_group("Hitman"):
				hitmen += 1
			if child.is_in_group("DungeonTrap"):
				traps += 1
			if child.is_in_group("DungeonFlare"):
				flares += 1
		check(bool(dun.get("_tutorial_layout")) and knowledge == 1 and quizzes == 1,
			"%s first dungeon spawns Knowledge + Quiz altars only" % lang)
		check(hitmen == 0 and traps == 0 and flares == 0,
			"%s first dungeon is enemy- and hazard-free" % lang)
		dun.call("_on_dungeon_cleared", idx)
		check(overworld.ensure_calls >= 1 and overworld.removed_indices.has(idx),
			"%s dungeon completion asks the overworld to post the next entrance" % lang)
		dun.queue_free()
		overworld.queue_free()
		await get_tree().process_frame


func _count_dungeon_anims(node: Node, frame_size: Vector2) -> int:
	var count := 0
	for child in node.get_children():
		if child is AnimatedSprite2D:
			var spr := child as AnimatedSprite2D
			if spr.sprite_frames != null \
					and spr.sprite_frames.has_animation("idle") \
					and spr.sprite_frames.get_frame_count("idle") == 8:
				var at := spr.sprite_frames.get_frame_texture("idle", 0) as AtlasTexture
				if at != null and at.region.size == frame_size:
					count += 1
		count += _count_dungeon_anims(child, frame_size)
	return count


func _test_dungeon_progression_and_sides() -> void:
	var mains: Array = Global.main_dungeon_indices()
	var extras: Array = Global.extra_dungeon_indices()
	var boss_idx: int = Global.boss_dungeon_index()
	var lua_main_count := 0
	var py_main_count := 0
	for idx in mains:
		if Global.dungeon_language(int(idx)) == "lua":
			lua_main_count += 1
		elif Global.dungeon_language(int(idx)) == "python":
			py_main_count += 1
	check(mains.size() == 25 and lua_main_count == 15 and py_main_count == 10
		and boss_idx > 0,
		"Lua (15) and Python (10) main tracks plus the Hitman boss are registered")
	check(extras.is_empty(),
		"all shipped Lua lessons are part of the main progression, not post-boss extras")
	check(Global.get_dungeon_mission_for_index(boss_idx) != null
		and Global.get_dungeon_mission_for_index(boss_idx).is_boss(),
		"the final main mission is the Hitman boss dungeon")

	# Regression: clearing Lua 11 must advance to Lua 26 instead of leaving the
	# Lua track with no current dungeon until the Python track/ boss finishes.
	var saved_dungeon_states: Dictionary = {}
	for m in Global.missions:
		if m.has("dungeon_index"):
			saved_dungeon_states[str(m["id"])] = {
				"completed": bool(m["completed"]),
				"progress": int(m.get("progress", 0)),
			}
			m["completed"] = false
	Global._find_mission("dungeon_11")["completed"] = true
	var lua_next: int = Global.current_main_dungeon_index("lua")
	check(lua_next == 26 and Global.current_dungeon_indices().has(26),
		"clearing Lua 11 exposes Lua 26 as the next Lua dungeon")
	for m in Global.missions:
		var id := str(m.get("id", ""))
		if saved_dungeon_states.has(id):
			m["completed"] = bool(saved_dungeon_states[id]["completed"])
			m["progress"] = int(saved_dungeon_states[id]["progress"])

	var blank_starters := true
	for dm_value in Global.dungeon_missions.values():
		var dm := dm_value as DungeonMissionData
		if dm == null:
			continue
		for qv in dm.questions:
			var q := qv as DungeonQuestion
			if q != null and q.is_compiler() and not q.starter_code.is_empty():
				blank_starters = false
	check(blank_starters, "no Lua/Python dungeon question starts with solution code")

	var gen := DungeonGenerator.new()
	gen.generate_boss(12345)
	check(not gen.entrance_room.is_empty() and not gen.boss_room.is_empty()
		and gen.knowledge_room.is_empty() and gen.bonus_rooms.is_empty()
		and gen.flare_positions.is_empty() and gen.trap_positions.is_empty(),
		"Hitman dungeon generator creates exactly the entrance and boss rooms")

	var boss_mission: DungeonMissionData = Global.get_dungeon_mission_for_index(boss_idx)
	var old_hotbar: Array = Global.Hotbar.duplicate(true)
	var old_inventory: Array = Global.Inventory.duplicate(true)
	var old_player := Global.player_node
	var old_mission: Dictionary = Global._find_mission("dungeon_%d" % boss_idx).duplicate(true)
	var old_cleared := Global.cleared_dungeons.has(boss_idx)
	var old_dungeon_stars: Dictionary = Global.dungeon_stars.duplicate(true)
	var dun := DungeonWorld.new()
	add_child(dun)
	dun.setup(boss_idx, boss_mission, 12345, null, Vector2.ZERO)
	await get_tree().process_frame
	var boss_player := CharacterBody2D.new()
	add_child(boss_player)
	Global.player_node = boss_player
	boss_player.global_position = dun.grid_to_world(dun.generator.quiz_altar_pos)
	var boss: Node = dun.get("_boss")
	var boss_count := 0
	for child in dun.get_children():
		if child.is_in_group("Hitman"):
			boss_count += 1
	check(boss != null and boss_count == 1,
		"the Hitman dungeon spawns exactly one miniboss")
	var boss_altars := 0
	for child in dun.get_children():
		if child.is_in_group("KnowledgeAltar") or child.is_in_group("QuizAltar"):
			boss_altars += 1
	check(boss_altars == 0, "the boss arena intentionally spawns no altars")
	if boss != null:
		var sprite := boss.get_node("AnimatedSprite2D") as AnimatedSprite2D
		check(sprite != null and sprite.scale.x > 0.7,
			"the Hitman miniboss uses the existing sprite at a larger scale")
		check(float(boss.get("_max_health")) > 150.0,
			"the Hitman miniboss has final-encounter health")
		boss.call("take_hit", 10000.0, Vector2.ZERO, false)
		await get_tree().process_frame
		var exit_ref: Variant = dun.get("_exit_marker")
		check(Global.is_dungeon_cleared(boss_idx)
			and bool(Global._find_mission("dungeon_%d" % boss_idx).get("completed", false))
			and exit_ref != null and bool(exit_ref._active) and bool(exit_ref.visible),
			"defeating the miniboss completes the finale and shows the exit")
		if exit_ref != null:
			check(boss_player.global_position.distance_to((exit_ref as Node2D).global_position) <= 3.0 * 32.0,
				"the dungeon exit appears beside the player who completed the challenge")
	dun.queue_free()
	await get_tree().process_frame
	boss_player.queue_free()
	await get_tree().process_frame
	Global.player_node = old_player if is_instance_valid(old_player) else null
	Global.Hotbar = old_hotbar
	Global.Inventory = old_inventory
	if old_cleared:
		Global.cleared_dungeons[boss_idx] = true
	else:
		Global.cleared_dungeons.erase(boss_idx)
	Global.dungeon_stars = old_dungeon_stars
	var bm := Global._find_mission("dungeon_%d" % boss_idx)
	bm["completed"] = bool(old_mission.get("completed", false))
	bm["progress"] = int(old_mission.get("progress", 0))
	Global.mission_updated.emit()

	# The optional extra-dungeon code path remains supported for future
	# post-boss content. Exercise it with a duplicate of Lua 26 rather than
	# requiring a shipped extra mission.
	var extra_source: DungeonMissionData = Global.get_dungeon_mission_for_index(26)
	var extra_mission: DungeonMissionData = extra_source.duplicate(true) as DungeonMissionData
	extra_mission.dungeon_category = "extra"
	var edun := DungeonWorld.new()
	add_child(edun)
	edun.setup(26, extra_mission, 54321, null, Vector2.ZERO)
	await get_tree().process_frame
	var knowledge_count := 0
	var quiz_count := 0
	for child in edun.get_children():
		if child.is_in_group("KnowledgeAltar"):
			knowledge_count += 1
		if child.is_in_group("QuizAltar"):
			quiz_count += 1
	check(knowledge_count == 0 and quiz_count >= 2,
		"the supported extra-dungeon path has no Knowledge Altar and two Quiz Altars")
	edun.queue_free()
	await get_tree().process_frame

	var side_ids: Array = []
	var side_titles: Dictionary = {}
	var side_ok := true
	for m in Global.missions:
		if not bool(m.get("side", false)):
			continue
		var id := str(m.get("id", ""))
		side_ids.append(id)
		side_titles[str(m.get("title", ""))] = true
		if id.is_empty() or str(m.get("objective", "")).is_empty() or int(m.get("goal", 0)) <= 0:
			side_ok = false
	check(side_ids.size() == 20 and side_ids.size() == _unique_count(side_ids)
		and side_titles.size() == 20 and side_ok,
		"all 20 new side missions have unique ids, titles, objectives and goals")

	# Unlock gate and post-unlock progress. Preserve all original mission state.
	var old_dungeon_state: Dictionary = {}
	for m in Global.missions:
		if m.has("dungeon_index"):
			old_dungeon_state[str(m["id"])] = {"completed": bool(m["completed"]),
				"progress": int(m.get("progress", 0))}
			m["completed"] = false
	for m in Global.missions:
		if bool(m.get("side", false)):
			m["progress"] = 0
	check(not Global.side_missions_unlocked(),
		"side missions are locked before the dungeon progression finishes")
	Global.add_mission_progress("side_chest_collector", 1)
	check(int(Global._find_mission("side_chest_collector").get("progress", 0)) == 0,
		"side objectives do not advance while locked")
	for m in Global.missions:
		if m.has("dungeon_index"):
			m["completed"] = true
	check(Global.side_missions_unlocked() and Global.active_side_missions().size() == 3,
		"completing all main and boss dungeons unlocks the side mission pool")
	Global.add_mission_progress("side_chest_collector", 1)
	check(int(Global._find_mission("side_chest_collector").get("progress", 0)) == 1,
		"side missions track progress after unlock")
	for m in Global.missions:
		if bool(m.get("side", false)):
			m["progress"] = 0
	for m in Global.missions:
		var id := str(m.get("id", ""))
		if old_dungeon_state.has(id):
			m["completed"] = bool(old_dungeon_state[id]["completed"])
			m["progress"] = int(old_dungeon_state[id]["progress"])
	Global.mission_updated.emit()

func _unique_count(values: Array) -> int:
	var seen: Dictionary = {}
	for v in values:
		seen[v] = true
	return seen.size()


func _test_damage_and_spawn_constants() -> void:
	check(DungeonExplosion.DAMAGE == 10.0, "trap explosion halved to 10")
	check(DungeonProjectile.DAMAGE == 20.0, "flare projectile halved to 20")
	var hitman_script: GDScript = preload("res://scripts/hitman.gd")
	check(hitman_script.PROJECTILE_DAMAGE == 10.0, "hitman projectile halved to 10")
	check(hitman_script.RAM_DAMAGE == 12.5, "hitman ram halved to 12.5")
	check(hitman_script.EXPLOSION_FRACTION == 0.25, "hitman self-destruct halved to 25% max HP")
	var world_script: GDScript = preload("res://scripts/dungeon_world.gd")
	check(world_script.QUIZ_GUARD_MAX == 2, "quiz altar guard cap is two")
	check(world_script.HITMAN_MAX_ALIVE <= 6 and world_script.EARLY_HITMAN_MAX_ALIVE <= 2,
		"hitman population caps are reduced")


func _test_damage_application() -> void:
	Global.clear_safe_zones()
	var stub := Node2D.new()
	stub.add_to_group("Player")
	add_child(stub)
	Global.set_player_reference(stub)
	Global.player_is_dead = false
	Global.health = Global.max_health

	var blast := DungeonExplosion.new()
	add_child(blast)
	blast.global_position = Vector2.ZERO
	await get_tree().process_frame
	await get_tree().process_frame
	check(is_equal_approx(Global.health, Global.max_health - 10.0),
		"trap blast applies its halved 10 damage once")
	blast.queue_free()

	Global.health = Global.max_health
	var flare_bolt := DungeonProjectile.new()
	add_child(flare_bolt)
	flare_bolt.call("_on_body_entered", stub)
	await get_tree().process_frame
	check(is_equal_approx(Global.health, Global.max_health - 20.0),
		"dungeon flare bolt applies its halved 20 damage")

	Global.health = Global.max_health
	var hitman_bolt := DungeonProjectile.new()
	add_child(hitman_bolt)
	hitman_bolt.set("damage", 10.0)
	hitman_bolt.call("_on_body_entered", stub)
	await get_tree().process_frame
	check(is_equal_approx(Global.health, Global.max_health - 10.0),
		"hitman bolt applies its halved 10 damage")

	Global.health = Global.max_health
	Global.register_safe_zone(stub, Rect2(-32, -32, 64, 64))
	var protected_bolt := DungeonProjectile.new()
	add_child(protected_bolt)
	protected_bolt.call("_on_body_entered", stub)
	check(is_equal_approx(Global.health, Global.max_health),
		"protected player takes no bolt damage")
	Global.clear_safe_zones()

	Global.health = Global.max_health
	Global.set_player_reference(null)
	if is_instance_valid(flare_bolt):
		flare_bolt.queue_free()
	if is_instance_valid(hitman_bolt):
		hitman_bolt.queue_free()
	if is_instance_valid(protected_bolt):
		protected_bolt.queue_free()
	stub.queue_free()
	await get_tree().process_frame


func _test_safe_zones() -> void:
	Global.clear_safe_zones()
	var stub := Node2D.new()
	add_child(stub)
	Global.set_player_reference(stub)

	var zone_a := Node.new()
	var zone_b := Node.new()
	Global.register_safe_zone(zone_a, Rect2(0, 0, 64, 64))
	stub.global_position = Vector2(40, 40)   # feet at y=57
	check(Global.is_player_in_safe_zone(), "player inside one safe zone is protected")
	Global.register_safe_zone(zone_b, Rect2(32, 0, 64, 64))
	Global.unregister_safe_zone(zone_a)
	check(Global.is_player_in_safe_zone(), "overlapping zone keeps protection when A is removed")
	Global.unregister_safe_zone(zone_b)
	check(not Global.is_player_in_safe_zone(), "protection ends only after leaving all zones")

	Global.register_safe_zone(zone_a, Rect2(0, 0, 64, 64))
	stub.global_position = Vector2(64, 47)   # feet exactly on the right/bottom edge
	check(Global.is_player_in_safe_zone(), "edge tiles are protected inclusively")
	stub.global_position = Vector2(64.5, 47)
	check(not Global.is_player_in_safe_zone(), "just outside the edge is unprotected")
	check(Global.segment_intersects_safe_zone(Vector2(-100, 32), Vector2(200, 32)),
		"fast projectile segment detects a safe-zone crossing")

	# Projectile spawned inside a zone is removed before it can damage.
	Global.clear_safe_zones()
	Global.register_safe_zone(zone_a, Rect2(90, 90, 40, 40))
	var proj := DungeonProjectile.new()
	add_child(proj)
	proj.global_position = Vector2(100, 100)
	await get_tree().physics_frame
	await get_tree().process_frame
	check(not is_instance_valid(proj), "hostile projectile inside a safe zone is removed")

	# Hitman entering/spawned inside a zone disintegrates without a death signal.
	var hitman: Node2D = load("res://scenes/mobs/Hitman.tscn").instantiate() as Node2D
	var died := [false]
	hitman.connect("died", func() -> void: died[0] = true)
	add_child(hitman)
	hitman.global_position = Vector2(100, 100)
	await get_tree().physics_frame
	await get_tree().process_frame
	check(not is_instance_valid(hitman) or hitman.is_queued_for_deletion(),
		"hostile enemy inside a safe zone is disintegrated")
	check(not died[0], "safe-zone cleanup grants no death/loot signal")

	Global.clear_safe_zones()
	Global.set_player_reference(null)
	zone_a.free()
	zone_b.free()
	stub.queue_free()


func _test_grass_clearance() -> void:
	var world_script: GDScript = preload("res://scripts/world.gd")
	var probe: Node2D = world_script.new() as Node2D
	var center := Vector2i(10, 10)
	probe.set("_dungeon_entrance_tiles", {1: center})
	var tuft := Node2D.new()
	add_child(tuft)
	probe.set("_grass_occupied_tiles", {center + Vector2i(1, -1): tuft})
	probe.call("_refresh_dungeon_grass_clearance")
	var clearance: Dictionary = probe.get("_dungeon_grass_clearance")
	check(clearance.has(center) and clearance.has(center + Vector2i(2, 2)),
		"dungeon entrance grass clearance covers the spawn ring")
	check(not (probe.get("_grass_occupied_tiles") as Dictionary).has(center + Vector2i(1, -1)),
		"existing grass inside the entrance clearance is removed")
	probe.free()
	await get_tree().process_frame


func _test_cave_persistence() -> void:
	var old_first_pixie: bool = Global.first_pixie_cave_entered
	# ── Portal re-arm + stable per-type identity ──
	var portal := CavePortal.new()
	portal.mode = CavePortal.Mode.ENTER
	add_child(portal)
	await get_tree().process_frame
	portal.set("_prompt_shown", true)
	portal.set("_in_gate", true)
	portal.set("_gate_dwell", 0.5)
	(portal.get("_gate_area") as Area2D).monitoring = false
	portal.call("reset_after_exit")
	check(not bool(portal.get("_prompt_shown")) and not bool(portal.get("_in_gate"))
		and is_zero_approx(float(portal.get("_gate_dwell"))),
		"cave portal re-arms its prompt/dwell after exit")
	await get_tree().physics_frame
	check((portal.get("_gate_area") as Area2D).monitoring,
		"cave portal re-enables gate monitoring after exit")
	# Returning to the overworld standing inside the gate must re-arm the dwell
	# even though Area2D does not re-emit body_entered for an existing overlap.
	var player_probe := CharacterBody2D.new()
	player_probe.add_to_group("Player")
	player_probe.collision_layer = 4
	var pshape := CollisionShape2D.new()
	var prect := RectangleShape2D.new()
	prect.size = Vector2(16, 16)
	pshape.shape = prect
	player_probe.add_child(pshape)
	add_child(player_probe)
	player_probe.global_position = portal.global_position
	await get_tree().physics_frame
	(portal.get("_gate_area") as Area2D).monitoring = false
	portal.set("_in_gate", false)
	portal.set("_prompt_shown", true)
	portal.call("reset_after_exit")
	await get_tree().physics_frame
	await get_tree().process_frame
	check(bool(portal.get("_in_gate")),
		"cave portal re-arms its dwell when the player returns inside the gate")
	player_probe.queue_free()
	await get_tree().physics_frame
	portal.queue_free()

	var cave_probe := CavePortal.new()
	cave_probe.cave_type = "cave"
	cave_probe.cave_seed = 12345
	cave_probe.global_position = Vector2(10, 20)
	var pixie_probe := CavePortal.new()
	pixie_probe.cave_type = "pixie"
	pixie_probe.cave_seed = 12345
	pixie_probe.global_position = Vector2(10, 20)
	check(cave_probe.state_key() != pixie_probe.state_key(),
		"cave and pixie entrances never share a state key")
	cave_probe.free()
	pixie_probe.free()

	# ── Regular cave tile state round-trip ──
	var cave := CaveWorld.new()
	add_child(cave)
	cave.setup(424242, Vector2.ZERO)
	var changed := Vector2i(-1, -1)
	for x in range(cave.generator.size):
		for y in range(cave.generator.size):
			if cave.generator.grid[x][y] != CaveGenerator.Tile.FLOOR:
				changed = Vector2i(x, y)
				break
		if changed.x >= 0:
			break
	if changed.x >= 0:
		cave.generator.grid[changed.x][changed.y] = CaveGenerator.Tile.FLOOR
		cave.call("_paint_cell", cave.call("_grid_to_cell", changed),
			CaveGenerator.Tile.FLOOR, changed)
		var saved: Dictionary = cave.snapshot_state()
		check((saved.get("tiles", []) as Array).size() >= 1,
			"cave snapshot records mined tile changes")
		cave.queue_free()
		await get_tree().process_frame

		var restored := CaveWorld.new()
		add_child(restored)
		restored.setup(424242, Vector2.ZERO)
		restored.apply_state(saved)
		check(restored.generator.grid[changed.x][changed.y] == CaveGenerator.Tile.FLOOR,
			"cave mined wall is restored on re-entry")
		restored.queue_free()
		await get_tree().process_frame
	else:
		check(false, "cave generated a wall for the persistence probe")
		cave.queue_free()

	# ── Pixie ore + defeated-pixie state round-trip ──
	var pixie := PixieCaveWorld.new()
	add_child(pixie)
	pixie.setup(828282, Vector2.ZERO)
	var ore_cell := Vector2i(-1, -1)
	var ore_grid := Vector2i(-1, -1)
	var found_ore := false
	for x in range(pixie.generator.width):
		for y in range(pixie.generator.height):
			var tile := int(pixie.generator.grid[x][y])
			if tile >= PixieCaveGenerator.Tile.CRYSTAL_COPPER \
					and tile <= PixieCaveGenerator.Tile.CRYSTAL_DIAMOND:
				ore_grid = Vector2i(x, y)
				ore_cell = pixie.call("_grid_to_cell", ore_grid)
				found_ore = true
				break
		if found_ore:
			break
	if found_ore:
		pixie.call("_break_tile", ore_cell)
		var pixie_before := 0
		var removed := false
		for child in pixie.get_children():
			if child.is_in_group("Pixie"):
				pixie_before += 1
				if not removed:
					child.queue_free()
					removed = true
		await get_tree().process_frame
		var pixie_saved: Dictionary = pixie.snapshot_state()
		check((pixie_saved.get("mined_ores", []) as Array).size() >= 1,
			"pixie snapshot records mined crystal ores")
		check((pixie_saved.get("pixies_alive", []) as Array).size() == pixie_before - 1,
			"pixie snapshot records defeated enemies")
		pixie.queue_free()
		await get_tree().process_frame

		var pixie_restored := PixieCaveWorld.new()
		add_child(pixie_restored)
		pixie_restored.setup(828282, Vector2.ZERO)
		pixie_restored.apply_state(pixie_saved)
		await get_tree().process_frame
		check(pixie_restored.generator.grid[ore_grid.x][ore_grid.y]
			== PixieCaveGenerator.Tile.FLOOR,
			"pixie mined ore restores as floor")
		check((pixie_restored.get("_mined_ores") as Dictionary).has(ore_cell),
			"pixie mined-ore regeneration data is restored")
		var alive_after := 0
		for child in pixie_restored.get_children():
			if child.is_in_group("Pixie"):
				alive_after += 1
		check(alive_after == pixie_before - 1,
			"defeated pixies stay defeated after re-entry")
		pixie_restored.queue_free()
		await get_tree().process_frame
	else:
		check(false, "pixie generated a crystal ore for the persistence probe")
		pixie.queue_free()

	# ── Cave state survives world save/load ──
	var slot: int = Global.next_free_slot()
	if slot > 0:
		Global.cave_states = {
			"cave:424242:0:0": {"version": 1, "tiles": [[1, 2, 0]], "blocks": [],
				"explored": [[10, 20]]},
		}
		Global.first_pixie_cave_entered = true
		Global.save_game(slot)
		Global.cave_states.clear()
		Global.first_pixie_cave_entered = false
		Global.load_game(slot)
		check(Global.cave_states.has("cave:424242:0:0"),
			"cave/pixie states survive world save/load")
		check(Global.first_pixie_cave_entered,
			"the first-Pixie-Cave safety flag survives world save/load")
		Global.delete_world(slot)
		Global.cave_states.clear()
		Global.first_pixie_cave_entered = false
	else:
		print("NOTE: no free save slot; cave-state save/load test skipped")
	Global.first_pixie_cave_entered = old_first_pixie


func _test_cave_generation_edges() -> void:
	# Both generators keep several solid border layers, and a Pixie Cave must
	# never collapse to a single room. The border keeps the padded camera view
	# reading as rock instead of exposing the generated-grid edge.
	var pixie_rooms_ok := true
	var pixie_border_ok := true
	var pixie_border: int = PixieCaveGenerator.BORDER_WALL_TILES
	for seed_value in range(0, 200):
		var gen := PixieCaveGenerator.new()
		gen.generate(seed_value)
		if gen.rooms.size() < PixieCaveGenerator.MIN_ROOMS:
			pixie_rooms_ok = false
		for x in range(gen.width):
			for layer in range(pixie_border):
				if int(gen.grid[x][layer]) == PixieCaveGenerator.Tile.FLOOR \
						or int(gen.grid[x][gen.height - 1 - layer]) == PixieCaveGenerator.Tile.FLOOR:
					pixie_border_ok = false
		for y in range(gen.height):
			for layer in range(pixie_border):
				if int(gen.grid[layer][y]) == PixieCaveGenerator.Tile.FLOOR \
						or int(gen.grid[gen.width - 1 - layer][y]) == PixieCaveGenerator.Tile.FLOOR:
					pixie_border_ok = false
	check(pixie_rooms_ok,
		"every Pixie Cave generates at least two rooms")
	check(pixie_border_ok,
		"Pixie Caves keep four solid border layers")

	var cave_border_ok := true
	var cave_border: int = CaveGenerator.BORDER_WALL_TILES
	for seed_value in range(0, 24):
		var gen := CaveGenerator.new()
		gen.generate(seed_value)
		for x in range(gen.size):
			for layer in range(cave_border):
				if int(gen.grid[x][layer]) == CaveGenerator.Tile.FLOOR \
						or int(gen.grid[x][gen.size - 1 - layer]) == CaveGenerator.Tile.FLOOR:
					cave_border_ok = false
		for y in range(gen.size):
			for layer in range(cave_border):
				if int(gen.grid[layer][y]) == CaveGenerator.Tile.FLOOR \
						or int(gen.grid[gen.size - 1 - layer][y]) == CaveGenerator.Tile.FLOOR:
					cave_border_ok = false
	check(cave_border_ok,
		"regular caves keep four solid border layers")

	# Camera bounds extend into the surrounding wall band, like dungeons, so the
	# camera can centre the player near the generated edge.
	var cave_world := CaveWorld.new()
	add_child(cave_world)
	cave_world.setup(424242, Vector2.ZERO)
	var cave_bounds: Rect2 = cave_world.call("camera_bounds")
	var cave_span: float = float(cave_world.generator.size * CaveWorld.TILE_SIZE)
	var cave_pad: float = float(CaveWorld.CAMERA_WALL_PADDING_TILES * CaveWorld.TILE_SIZE)
	check(is_equal_approx(cave_bounds.size.x, cave_span + 2.0 * cave_pad)
		and is_equal_approx(cave_bounds.size.y, cave_span + 2.0 * cave_pad),
		"cave camera bounds include the wall padding")
	cave_world.queue_free()
	await get_tree().process_frame

	var pixie_safe := PixieCaveWorld.new()
	add_child(pixie_safe)
	pixie_safe.setup(828282, Vector2.ZERO, false)
	var pixie_bounds: Rect2 = pixie_safe.call("camera_bounds")
	var pixie_span_x: float = float(pixie_safe.generator.width * PixieCaveWorld.TILE_SIZE)
	var pixie_span_y: float = float(pixie_safe.generator.height * PixieCaveWorld.TILE_SIZE)
	var pixie_pad: float = float(PixieCaveWorld.CAMERA_WALL_PADDING_TILES * PixieCaveWorld.TILE_SIZE)
	var safe_pixies := 0
	for child in pixie_safe.get_children():
		if child.is_in_group("Pixie"):
			safe_pixies += 1
	check(safe_pixies == 0,
		"a Pixie Cave can generate without pixies for the safe first visit")
	check(is_equal_approx(pixie_bounds.size.x, pixie_span_x + 2.0 * pixie_pad)
		and is_equal_approx(pixie_bounds.size.y, pixie_span_y + 2.0 * pixie_pad),
		"Pixie Cave camera bounds include the wall padding")
	pixie_safe.queue_free()
	await get_tree().process_frame

	var pixie_populated := PixieCaveWorld.new()
	add_child(pixie_populated)
	pixie_populated.setup(828282, Vector2.ZERO, true)
	var populated_pixies := 0
	for child in pixie_populated.get_children():
		if child.is_in_group("Pixie"):
			populated_pixies += 1
	check(populated_pixies > 0,
		"later Pixie Caves still spawn their pixie population")
	pixie_populated.queue_free()
	await get_tree().process_frame

	var game_src := FileAccess.get_file_as_string("res://scenes/game_instance.gd")
	check(game_src.contains("first_pixie_entry")
		and game_src.contains("not first_pixie_entry")
		and game_src.contains("Global.first_pixie_cave_entered = true"),
		"the game suppresses pixies on the first Pixie Cave entry only")

func _test_cave_cache_lifecycle() -> void:
	# Drive the real Game enter/exit functions off-tree: the cave instance must
	# be cached (not freed) and re-entry must return the SAME node with its
	# runtime changes intact. Also cover the pixie branch.
	var old_slot := Global.active_save_slot
	var old_game := Global.game_node
	var old_player := Global.player_node
	var old_first_pixie := Global.first_pixie_cave_entered
	Global.active_save_slot = -1

	var game: Node = load("res://scenes/game_instance.gd").new()
	var world := Node2D.new()
	var player := CharacterBody2D.new()
	game.add_child(world)
	game.add_child(player)
	game.set("_world", world)
	game.set("_player", player)
	Global.game_node = game
	Global.player_node = player

	var portal := CavePortal.new()
	portal.mode = CavePortal.Mode.ENTER
	portal.cave_type = "cave"
	portal.cave_seed = 515151
	portal.global_position = Vector2(100, 100)
	game.call("_do_enter_cave", portal)
	var first: Variant = game.get("_cave_world")
	var grid_pos := Vector2i(-1, -1)
	check(first is CaveWorld, "cave entry creates a cave world")
	var active_key := portal.state_key()
	var live_states: Dictionary = game.call("get_cave_states") as Dictionary
	check(live_states.has(active_key)
		and (Global.cave_states as Dictionary).has(active_key),
		"saving inside a cave syncs the active snapshot into the live cave cache")
	if first is CaveWorld:
		var cave := first as CaveWorld
		var cell := Vector2i(-1, -1)
		for x in range(cave.generator.size):
			for y in range(cave.generator.size):
				if cave.generator.grid[x][y] != CaveGenerator.Tile.FLOOR:
					grid_pos = Vector2i(x, y)
					cell = cave.call("_grid_to_cell", grid_pos)
					break
			if grid_pos.x >= 0:
				break
		if grid_pos.x >= 0:
			cave.generator.grid[grid_pos.x][grid_pos.y] = CaveGenerator.Tile.FLOOR
			cave.call("_paint_cell", cell, CaveGenerator.Tile.FLOOR, grid_pos)
		var key := portal.state_key()
		game.call("_do_exit_cave")
		check(game.get("_cave_world") == null and game.get("_world") == world,
			"cave exit restores the overworld")
		var cache: Dictionary = game.get("_cave_instances") as Dictionary
		check(cache.has(key) and is_instance_valid(cache[key]),
			"cave exit caches the visited instance instead of freeing it")
		game.call("_do_enter_cave", portal)
		check(game.get("_cave_world") == cave,
			"cave re-entry reuses the cached instance")
		if grid_pos.x >= 0:
			check(cave.generator.grid[grid_pos.x][grid_pos.y] == CaveGenerator.Tile.FLOOR,
				"cave re-entry keeps mined tiles")
		game.call("_do_exit_cave")

	# A second regular cave must cache independently from the first.
	var portal_b := CavePortal.new()
	portal_b.mode = CavePortal.Mode.ENTER
	portal_b.cave_type = "cave"
	portal_b.cave_seed = 525252
	portal_b.global_position = Vector2(300, 300)
	game.call("_do_enter_cave", portal_b)
	var cave_b: Variant = game.get("_cave_world")
	check(cave_b is CaveWorld and cave_b != first,
		"a different cave entrance gets its own cave instance")
	var key_b := portal_b.state_key()
	check(key_b != portal.state_key(), "different cave entrances use different state keys")
	game.call("_do_exit_cave")
	game.call("_do_enter_cave", portal)
	check(game.get("_cave_world") == first,
		"re-entering cave A after cave B still reuses cave A")
	if grid_pos.x >= 0:
		check((first as CaveWorld).generator.grid[grid_pos.x][grid_pos.y]
			== CaveGenerator.Tile.FLOOR,
			"cave A state is independent from cave B")
	game.call("_do_exit_cave")

	# Pixie branch: same cache contract, separate state key/type. The first
	# Pixie Cave in a world must be the safe, pixie-free introduction.
	Global.first_pixie_cave_entered = false
	var pixie_portal := CavePortal.new()
	pixie_portal.mode = CavePortal.Mode.ENTER
	pixie_portal.cave_type = "pixie"
	pixie_portal.cave_seed = 626262
	pixie_portal.global_position = Vector2(200, 200)
	game.call("_do_enter_cave", pixie_portal)
	var pixie_first: Variant = game.get("_pixie_cave_world")
	var first_pixie_count := 0
	if pixie_first is Node:
		for child in (pixie_first as Node).get_children():
			if child.is_in_group("Pixie"):
				first_pixie_count += 1
	check(pixie_first is PixieCaveWorld, "pixie entry creates a pixie cave world")
	check(Global.first_pixie_cave_entered and first_pixie_count == 0,
		"the first Pixie Cave entered through the game is pixie-free")
	game.call("_do_exit_cave")
	var pixie_key := pixie_portal.state_key()
	var pixie_cache: Dictionary = game.get("_cave_instances") as Dictionary
	check(pixie_cache.has(pixie_key), "pixie exit caches its own instance")
	game.call("_do_enter_cave", pixie_portal)
	check(game.get("_pixie_cave_world") == pixie_first,
		"pixie re-entry reuses its cached instance")
	game.call("_do_exit_cave")

	# A later Pixie Cave still gets its normal pixie population.
	var pixie_portal_b := CavePortal.new()
	pixie_portal_b.mode = CavePortal.Mode.ENTER
	pixie_portal_b.cave_type = "pixie"
	pixie_portal_b.cave_seed = 636363
	pixie_portal_b.global_position = Vector2(400, 400)
	game.call("_do_enter_cave", pixie_portal_b)
	var pixie_later: Variant = game.get("_pixie_cave_world")
	var later_pixie_count := 0
	if pixie_later is Node:
		for child in (pixie_later as Node).get_children():
			if child.is_in_group("Pixie"):
				later_pixie_count += 1
	check(pixie_later is PixieCaveWorld and later_pixie_count > 0,
		"later Pixie Caves entered through the game still spawn pixies")
	game.call("_do_exit_cave")

	for key in (game.get("_cave_instances") as Dictionary).keys():
		var cached_node: Variant = (game.get("_cave_instances") as Dictionary)[key]
		if is_instance_valid(cached_node):
			(cached_node as Node).free()
	game.free()
	portal.free()
	portal_b.free()
	pixie_portal.free()
	pixie_portal_b.free()
	Global.game_node = old_game
	Global.player_node = old_player
	Global.active_save_slot = old_slot
	Global.first_pixie_cave_entered = old_first_pixie
	Global.explored_cave_tiles.clear()


const TORCH_PATH := "res://resources/items/Torch.tres"
const TORCH_CONNECTED_PATH := "res://resources/items/Torch_connected.tres"
const STONE_PATH := "res://resources/items/stone.tres"
const BONFIRE_PATH := "res://resources/items/bonfire.tres"
const WOODEN_PICK_PATH := "res://resources/items/wooden_pickaxe.tres"
const WOODEN_AXE_PATH := "res://resources/items/woodenaxe.tres"

func _tile_matches(tile: int, mode: String, pixie: bool) -> bool:
	if mode == "any":
		return true
	if mode == "floor":
		return tile == 0
	if mode == "wall":
		return tile != 0
	if mode == "ore" and pixie:
		return tile >= PixieCaveGenerator.Tile.CRYSTAL_COPPER \
			and tile <= PixieCaveGenerator.Tile.CRYSTAL_DIAMOND
	return false

func _find_floor_cell(world: Node, pixie: bool, left_mode: String, right_mode: String) -> Vector2i:
	var gen = world.get("generator")
	var w: int = int(gen.get("width")) if pixie else int(gen.get("size"))
	var h: int = int(gen.get("height")) if pixie else int(gen.get("size"))
	for x in range(1, w - 1):
		for y in range(1, h - 1):
			if not _tile_matches(int(gen.get("grid")[x][y]), "floor", pixie):
				continue
			if _tile_matches(int(gen.get("grid")[x - 1][y]), left_mode, pixie) \
					and _tile_matches(int(gen.get("grid")[x + 1][y]), right_mode, pixie):
				var cell: Vector2i = world.call("_grid_to_cell", Vector2i(x, y)) as Vector2i
				if not (world.get("_placed_blocks") as Dictionary).has(cell):
					return cell
	return Vector2i(-99999, -99999)

# Three adjacent, clear floor tiles in a row. Used by torch tests that need a
# deterministic horizontal wall/ore neighbour instead of relying on where the
# seeded ore pass happened to embed an ore.
func _find_horizontal_floor_run(world: Node, pixie: bool) -> Dictionary:
	var gen = world.get("generator")
	var w: int = int(gen.get("width")) if pixie else int(gen.get("size"))
	var h: int = int(gen.get("height")) if pixie else int(gen.get("size"))
	var blocks: Dictionary = world.get("_placed_blocks") as Dictionary
	var entrance: Vector2i = gen.get("entrance_tile") as Vector2i
	for x in range(2, w - 1):
		for y in range(1, h - 1):
			var run: Array = [Vector2i(x - 1, y), Vector2i(x, y), Vector2i(x + 1, y)]
			var ok := true
			for gp in run:
				if gp == entrance or not _tile_matches(
						int(gen.get("grid")[gp.x][gp.y]), "floor", pixie):
					ok = false
					break
				var cell: Vector2i = world.call("_grid_to_cell", gp) as Vector2i
				if blocks.has(cell):
					ok = false
					break
			if ok:
				return {"left": run[0], "mid": run[1], "right": run[2]}
	return {}

func _find_clear_floor_cell(world: Node, pixie: bool) -> Vector2i:
	var gen = world.get("generator")
	var w: int = int(gen.get("width")) if pixie else int(gen.get("size"))
	var h: int = int(gen.get("height")) if pixie else int(gen.get("size"))
	var blocks: Dictionary = world.get("_placed_blocks") as Dictionary
	for x in range(1, w - 1):
		for y in range(1, h - 1):
			if not _tile_matches(int(gen.get("grid")[x][y]), "floor", pixie):
				continue
			var clear := true
			for dx in range(-1, 2):
				for dy in range(-1, 2):
					if dx == 0 and dy == 0:
						continue
					if not _tile_matches(int(gen.get("grid")[x + dx][y + dy]), "floor", pixie):
						clear = false
						break
				if not clear:
					break
			if not clear:
				continue
			var cell: Vector2i = world.call("_grid_to_cell", Vector2i(x, y)) as Vector2i
			if not blocks.has(cell):
				return cell
	return Vector2i(-99999, -99999)

func _restore_torch(world: Node, cell: Vector2i, path: String = TORCH_PATH) -> Node:
	world.call("_restore_placed_block", cell, {
		"x": cell.x, "y": cell.y, "name": "Torch", "path": path, "color": "",
	})
	return (world.get("_placed_blocks") as Dictionary)[cell]["node"] as Node

func _torch_drops(world: Node) -> Array:
	var out: Array = []
	for child in world.get_children():
		if not child.is_in_group("Items"):
			continue
		var d = child.get("item_data")
		if d is ItemData and (d as ItemData).is_torch:
			out.append(child)
	return out

func _mine_torch(world: Node, torch: Node, tool_path: String) -> Dictionary:
	Global.Hotbar.fill(null)
	Global.Hotbar[0] = {"data": load(tool_path), "quantity": 1}
	torch.call("_try_start_breaking")
	var started := bool(torch.get("_breaking"))
	var bare := bool(torch.get("_barehanded"))
	# Let a just-picked drop finish queue_free before counting the new drop.
	await get_tree().process_frame
	var before := _torch_drops(world).size()
	torch.call("_add_break_progress", 100.0)
	await get_tree().process_frame
	var drops := _torch_drops(world)
	return {"started": started, "bare": bare, "new_drops": drops.size() - before,
		"drops": drops}

func _pickup_torch(drop: Node, expected: ItemData) -> bool:
	Global.Hotbar.fill(null)
	Global.Inventory.fill(null)
	drop.call("pickup_item")
	for slot in Global.Hotbar:
		if slot != null and (slot as Dictionary).get("data") == expected:
			return true
	for slot in Global.Inventory:
		if slot != null and (slot as Dictionary).get("data") == expected:
			return true
	return false

# A Wisp is a Game-owned companion, not a Mob. Verify the safety flags, the
# single cached light, smooth follow, transition/death snapping, duplicate
# cleanup, and the Game lifecycle hook.
func _test_wisp_companion() -> void:
	var old_player: Node = Global.player_node
	var old_game: Node = Global.game_node
	var old_dead: bool = Global.player_is_dead
	for node in get_tree().get_nodes_in_group("WispCompanion"):
		if is_instance_valid(node):
			node.queue_free()
	await get_tree().process_frame

	var player := CharacterBody2D.new()
	player.add_to_group("Player")
	player.collision_layer = 4
	player.collision_mask = 1
	player.position = Vector2(100, 100)
	add_child(player)
	Global.player_node = player
	var wisp: Node2D = load("res://scenes/companions/Wisp.tscn").instantiate()
	add_child(wisp)
	await get_tree().physics_frame
	await get_tree().physics_frame
	var light := wisp.get_node_or_null("WispLight") as PointLight2D
	check(wisp.is_in_group("WispCompanion") and not wisp.is_in_group("Mob")
		and wisp.collision_layer == 0 and wisp.collision_mask == 1
		and not wisp.has_method("take_hit"),
		"Wisp is a non-blocking, non-hostile companion ignored by mob combat")
	check(light != null and light.enabled and light.energy > 0.0
		and light.texture is GradientTexture2D
		and wisp.get_node_or_null("WispSprite") is Sprite2D
		and wisp.find_children("*", "GPUParticles2D", true, false).is_empty(),
		"Wisp owns one working cached-texture light and a pixel-art sprite")

	# Move the player and let the follow steering catch up without snap-jumps.
	player.global_position += Vector2(180, 0)
	var max_step := 0.0
	var previous := wisp.global_position
	for i in range(100):
		await get_tree().physics_frame
		max_step = maxf(max_step, wisp.global_position.distance_to(previous))
		previous = wisp.global_position
	check(wisp.global_position.distance_to(player.global_position) < 100.0
		and max_step < 8.0
		and light.global_position.distance_to(wisp.global_position) < 12.0,
		"Wisp follows smoothly and its light stays attached")

	# All four world-transition signals are connected and snap to a safe spot.
	check(Global.cave_entered.is_connected(Callable(wisp, "_on_cave_entered"))
		and Global.cave_exited.is_connected(Callable(wisp, "_on_cave_exited"))
		and Global.dungeon_entered.is_connected(Callable(wisp, "_on_dungeon_entered"))
		and Global.dungeon_exited.is_connected(Callable(wisp, "_on_dungeon_exited"))
		and Global.player_spawned.is_connected(Callable(wisp, "_on_player_spawned")),
		"Wisp listens to every cave, dungeon and respawn transition")
	player.global_position = Vector2(900, 700)
	wisp.call("_on_cave_entered", "cave")
	await get_tree().process_frame
	check(wisp.global_position.distance_to(player.global_position) < 90.0
		and light.enabled and light.energy > 1.6 and light.texture_scale > 0.65,
		"cave transition boosts the Wisp light so it actually lights the cave")
	player.global_position = Vector2(-400, 500)
	wisp.call("_on_cave_entered", "pixie")
	await get_tree().process_frame
	check(wisp.global_position.distance_to(player.global_position) < 90.0
		and light.enabled and light.energy > 1.4 and light.texture_scale > 0.58,
		"Pixie Cave transition uses its own boosted Wisp light profile")
	player.global_position = Vector2(-500, 400)
	wisp.call("_on_dungeon_entered", 1)
	await get_tree().process_frame
	check(wisp.global_position.distance_to(player.global_position) < 90.0
		and not light.enabled,
		"dungeon transition recovers the Wisp with its light switched off")
	wisp.call("_on_dungeon_exited", 1)
	await get_tree().process_frame
	check(light.enabled and light.energy > 0.9,
		"leaving the dungeon restores the overworld Wisp light")

	# Death hides the light; respawn restores it beside the player.
	wisp.call("_on_player_died", player.global_position)
	check(not wisp.visible,
		"Wisp hides while the player is dead")
	player.global_position = Vector2.ZERO
	Global.player_is_dead = false
	wisp.call("_on_player_spawned", Vector2.ZERO)
	await get_tree().process_frame
	check(wisp.visible
		and wisp.global_position.distance_to(player.global_position) < 90.0,
		"respawn restores the Wisp beside the player")

	# A waypoint recall has no transition signal; the distance leash still
	# recovers it instead of letting it fly across the whole map.
	player.global_position = Vector2(3000, 2000)
	await get_tree().physics_frame
	await get_tree().physics_frame
	check(wisp.global_position.distance_to(player.global_position) < 90.0,
		"distance leash safely recovers the Wisp after a long teleport")

	# Creating a stale duplicate must leave exactly one companion.
	var second: Node2D = load("res://scenes/companions/Wisp.tscn").instantiate()
	add_child(second)
	await get_tree().process_frame
	var live_wisps := 0
	for node in get_tree().get_nodes_in_group("WispCompanion"):
		if is_instance_valid(node) and not node.is_queued_for_deletion():
			live_wisps += 1
	check(live_wisps == 1,
		"duplicate Wisp instances collapse to one companion")

	var game_src := FileAccess.get_file_as_string("res://scenes/game_instance.gd")
	check(game_src.contains("_setup_wisp")
		and game_src.contains("WispCompanion")
		and game_src.contains("WISP_SCENE"),
		"Game owns the Wisp lifecycle and singleton guard")

	for node in get_tree().get_nodes_in_group("WispCompanion"):
		if is_instance_valid(node):
			node.queue_free()
	player.queue_free()
	Global.player_node = old_player if is_instance_valid(old_player) else null
	Global.game_node = old_game if is_instance_valid(old_game) else null
	Global.player_is_dead = old_dead
	await get_tree().process_frame

func _test_torches() -> void:
	var old_world := Global.world_node
	var old_player := Global.player_node
	var old_time := Global.time_of_day
	var player := CharacterBody2D.new()
	player.add_to_group("Player")
	add_child(player)
	Global.player_node = player

	# ── Overworld support predicate (no full world generation needed) ──
	var world_script: GDScript = load("res://scripts/world.gd")
	var ow: Node = world_script.new()
	var block_scene: PackedScene = load("res://scenes/objects/PlaceableBlock.tscn")
	var make_block := func(data: ItemData) -> Node:
		var n: Node = block_scene.instantiate()
		n.call("setup", data)
		ow.add_child(n)
		return n
	var blocks: Dictionary = {}
	ow.set("_placed_blocks", blocks)
	var probe_cell := Vector2i(0, 0)
	check(not bool(ow.call("torch_support", probe_cell)), "overworld empty cell is not torch support")
	blocks[probe_cell] = {"node": make_block.call(load("res://resources/items/wooden_floor.tres")), "name": "Floor"}
	check(not bool(ow.call("torch_support", probe_cell)), "overworld floor is not torch support")
	blocks[probe_cell] = {"node": make_block.call(load(TORCH_PATH)), "name": "Torch"}
	check(not bool(ow.call("torch_support", probe_cell)), "overworld torch is not torch support")
	blocks[probe_cell] = {"node": make_block.call(load(BONFIRE_PATH)), "name": "Bonfire"}
	check(not bool(ow.call("torch_support", probe_cell)), "overworld bonfire is not torch support")
	blocks[probe_cell] = {"node": make_block.call(load(STONE_PATH)), "name": "Stone"}
	check(bool(ow.call("torch_support", probe_cell)), "overworld solid block is torch support")
	blocks[probe_cell] = {"node": make_block.call(load(STONE_PATH)), "name": "Stone", "natural": true}
	check(bool(ow.call("torch_support", probe_cell)), "overworld natural stone is torch support")
	ow.free()

	var torch_data: ItemData = load(TORCH_PATH)
	var dev_data: ItemData = load(TORCH_CONNECTED_PATH)
	check(torch_data.is_torch and dev_data.is_torch,
		"torch variants share the torch item identity")
	check(dev_data.torch_drop_item == torch_data, "connected torch variant drops normal torch")
	check(dev_data.place_animation_sheet != dev_data.torch_connected_sheet,
		"connected torch variant has a distinct normal sheet")

	# ── Large cave ──
	var cave := CaveWorld.new()
	add_child(cave)
	cave.setup(313131, Vector2.ZERO)
	Global.world_node = cave

	var wall_cell := _find_floor_cell(cave, false, "wall", "floor")
	if wall_cell.x != -99999:
		var torch := _restore_torch(cave, wall_cell)
		await get_tree().process_frame
		check(bool(torch.get("_torch_connected")), "cave torch beside wall connects")
		cave.call("_break_tile", wall_cell + Vector2i(-1, 0))
		await get_tree().process_frame
		check(not bool(torch.get("_torch_connected")),
			"cave torch disconnects when its wall is mined")
	else:
		check(false, "cave generated a wall-adjacent torch cell")

	var aux_cell := _find_clear_floor_cell(cave, false)
	if aux_cell.x == -99999:
		aux_cell = _find_floor_cell(cave, false, "floor", "floor")
	if aux_cell.x != -99999:
		var torch_aux := _restore_torch(cave, aux_cell)
		_restore_torch(cave, aux_cell + Vector2i(-1, 0))
		await get_tree().process_frame
		check(not bool(torch_aux.get("_torch_connected")),
			"cave torch does not connect to another torch")
		var torch2: Node = (cave.get("_placed_blocks") as Dictionary)[aux_cell + Vector2i(-1, 0)]["node"]
		cave.call("unregister_block", aux_cell + Vector2i(-1, 0))
		torch2.queue_free()
		cave.call("_restore_placed_block", aux_cell + Vector2i(-1, 0), {
			"x": aux_cell.x - 1, "y": aux_cell.y, "name": "Bonfire",
			"path": BONFIRE_PATH, "color": "",
		})
		await get_tree().process_frame
		check(not bool(torch_aux.get("_torch_connected")),
			"cave torch does not connect to a bonfire")
		cave.call("unregister_block", aux_cell + Vector2i(-1, 0))
		await get_tree().process_frame

		# Connection art is horizontal only; vertical/diagonal solids must not
		# trigger it.
		var above_cell := aux_cell + Vector2i(0, -1)
		if not bool(cave.call("_cell_is_wall", above_cell)):
			cave.call("_restore_placed_block", above_cell, {
				"x": above_cell.x, "y": above_cell.y, "name": "Stone",
				"path": STONE_PATH, "color": "",
			})
			await get_tree().process_frame
			check(not bool(torch_aux.get("_torch_connected")),
				"cave torch does not connect vertically")
			cave.call("unregister_block", above_cell)
			await get_tree().process_frame
		var diagonal_cell := aux_cell + Vector2i(1, -1)
		if not bool(cave.call("_cell_is_wall", diagonal_cell)):
			cave.call("_restore_placed_block", diagonal_cell, {
				"x": diagonal_cell.x, "y": diagonal_cell.y, "name": "Stone",
				"path": STONE_PATH, "color": "",
			})
			await get_tree().process_frame
			check(not bool(torch_aux.get("_torch_connected")),
				"cave torch does not connect diagonally")
			cave.call("unregister_block", diagonal_cell)
			await get_tree().process_frame

		var stone_cell := aux_cell + Vector2i(-1, 0)
		cave.call("_restore_placed_block", stone_cell, {
			"x": stone_cell.x, "y": stone_cell.y, "name": "Stone",
			"path": STONE_PATH, "color": "",
		})
		await get_tree().process_frame
		check(bool(torch_aux.get("_torch_connected")),
			"cave torch connects to a placed solid block")
		var connected_result: Dictionary = await _mine_torch(cave, torch_aux, WOODEN_PICK_PATH)
		check(int(connected_result["new_drops"]) == 1,
			"cave connected torch drops once with a pickaxe")
		var connected_drops: Array = connected_result["drops"]
		if not connected_drops.is_empty():
			check(_pickup_torch(connected_drops.back() as Node, torch_data),
				"cave connected-torch drop is collectible")

		var torch_iso := _restore_torch(cave, aux_cell)
		await get_tree().process_frame
		check(bool(torch_iso.get("_torch_connected")),
			"replacement cave torch connects to the remaining block")
		var stone: Node = (cave.get("_placed_blocks") as Dictionary)[stone_cell]["node"]
		cave.call("unregister_block", stone_cell)
		stone.queue_free()
		await get_tree().process_frame
		check(not bool(torch_iso.get("_torch_connected")),
			"cave torch disconnects when its block is removed")

		var pick_result: Dictionary = await _mine_torch(cave, torch_iso, WOODEN_PICK_PATH)
		check(bool(pick_result["started"]) and not bool(pick_result["bare"]) \
			and int(pick_result["new_drops"]) == 1,
			"cave isolated torch drops once with a pickaxe")
		var pick_drops: Array = pick_result["drops"]
		if not pick_drops.is_empty():
			check(_pickup_torch(pick_drops.back() as Node, torch_data),
				"cave dropped torch is collectible")

		var axe_torch := _restore_torch(cave, aux_cell)
		var axe_result: Dictionary = await _mine_torch(cave, axe_torch, WOODEN_AXE_PATH)
		check(bool(axe_result["started"]) and not bool(axe_result["bare"]) \
			and int(axe_result["new_drops"]) == 1,
			"cave torch drops once with an axe")
		var axe_drops: Array = axe_result["drops"]
		if not axe_drops.is_empty():
			check(_pickup_torch(axe_drops.back() as Node, torch_data),
				"cave axe-mined torch is collectible")

		var variant_torch := _restore_torch(cave, aux_cell, TORCH_CONNECTED_PATH)
		await get_tree().process_frame
		check(not bool(variant_torch.get("_torch_connected")) \
			and (variant_torch.get("_sprite") as Sprite2D).texture == torch_data.place_animation_sheet,
			"cave connected variant uses isolated art without support")
		var variant_result: Dictionary = await _mine_torch(cave, variant_torch, WOODEN_PICK_PATH)
		var variant_drops: Array = variant_result["drops"]
		check(int(variant_result["new_drops"]) == 1 and not variant_drops.is_empty() \
			and (variant_drops.back() as Node).get("item_data") == torch_data,
			"cave connected variant drops the normal torch")
		if not variant_drops.is_empty():
			check(_pickup_torch(variant_drops.back() as Node, torch_data),
				"cave connected-variant drop is collectible as a normal torch")

		# Full inventory: the drop must remain on the ground, not vanish.
		var full_torch := _restore_torch(cave, aux_cell)
		Global.Hotbar.fill(null)
		Global.Inventory.fill(null)
		var stone_data: ItemData = load(STONE_PATH)
		Global.Hotbar[0] = {"data": load(WOODEN_PICK_PATH), "quantity": 1}
		for i in range(1, Global.Hotbar.size()):
			Global.Hotbar[i] = {"data": stone_data, "quantity": Global.MAX_STACK}
		for i in range(Global.Inventory.size()):
			Global.Inventory[i] = {"data": stone_data, "quantity": Global.MAX_STACK}
		full_torch.call("_try_start_breaking")
		await get_tree().process_frame
		var before_full := _torch_drops(cave).size()
		full_torch.call("_add_break_progress", 100.0)
		await get_tree().process_frame
		var full_drops := _torch_drops(cave)
		check(full_drops.size() == before_full + 1,
			"cave torch still drops when inventory is full")
		if full_drops.size() > before_full:
			var full_drop := full_drops.back() as Node
			full_drop.call("pickup_item")
			check(is_instance_valid(full_drop),
				"full inventory leaves the torch drop on the ground")
	else:
		check(false, "cave generated an isolated torch cell")

	# Torch block survives cave state save/apply (same path used on re-entry).
	var state_torch := _restore_torch(cave, aux_cell)
	var cave_snapshot: Dictionary = cave.snapshot_state()
	check((cave_snapshot.get("blocks", []) as Array).size() >= 1,
		"cave state includes placed torch blocks")
	var cave_restored := CaveWorld.new()
	add_child(cave_restored)
	cave_restored.setup(313131, Vector2.ZERO)
	cave_restored.apply_state(cave_snapshot)
	var restored_blocks: Dictionary = cave_restored.get("_placed_blocks") as Dictionary
	check(restored_blocks.has(aux_cell), "cave torch block restores after state load")
	if restored_blocks.has(aux_cell):
		var restored_torch: Node = (restored_blocks[aux_cell] as Dictionary)["node"]
		check((restored_torch.get("item_data") as ItemData) == torch_data,
			"restored cave block keeps torch identity")
	cave_restored.queue_free()
	await get_tree().process_frame
	state_torch.queue_free()
	cave.queue_free()
	await get_tree().process_frame

	# ── Pixie cave ──
	var pixie := PixieCaveWorld.new()
	add_child(pixie)
	pixie.setup(414141, Vector2.ZERO)
	Global.world_node = pixie
	var pixie_wall_cell := _find_floor_cell(pixie, true, "wall", "floor")
	if pixie_wall_cell.x != -99999:
		var pixie_torch := _restore_torch(pixie, pixie_wall_cell)
		await get_tree().process_frame
		check(bool(pixie_torch.get("_torch_connected")),
			"pixie torch beside wall connects")
		var pixie_connected_result: Dictionary = await _mine_torch(
			pixie, pixie_torch, WOODEN_PICK_PATH)
		check(int(pixie_connected_result["new_drops"]) == 1,
			"pixie connected torch drops once with a pickaxe")
		var pixie_connected_drops: Array = pixie_connected_result["drops"]
		if not pixie_connected_drops.is_empty():
			check(_pickup_torch(pixie_connected_drops.back() as Node, torch_data),
				"pixie connected-torch drop is collectible")
		var pixie_wall_torch := _restore_torch(pixie, pixie_wall_cell)
		await get_tree().process_frame
		pixie.call("_break_tile", pixie_wall_cell + Vector2i(-1, 0))
		await get_tree().process_frame
		check(not bool(pixie_wall_torch.get("_torch_connected")),
			"pixie torch disconnects when its wall is mined")
	else:
		check(false, "pixie generated a wall-adjacent torch cell")

	var ore_run := _find_horizontal_floor_run(pixie, true)
	if not ore_run.is_empty():
		# Make the left floor tile a crystal ore so the middle torch has a
		# guaranteed horizontal ore neighbour; the right tile stays floor for
		# the isolated-torch drop check.
		var ore_grid: Vector2i = ore_run["left"] as Vector2i
		pixie.generator.grid[ore_grid.x][ore_grid.y] = PixieCaveGenerator.Tile.CRYSTAL_COPPER
		var ore_neighbor: Vector2i = pixie.call("_grid_to_cell", ore_grid) as Vector2i
		pixie.call("_paint_cell", ore_neighbor,
			PixieCaveGenerator.Tile.CRYSTAL_COPPER, ore_grid)
		var ore_cell: Vector2i = pixie.call("_grid_to_cell", ore_run["mid"]) as Vector2i
		var isolated_cell: Vector2i = pixie.call("_grid_to_cell", ore_run["right"]) as Vector2i
		var ore_torch := _restore_torch(pixie, ore_cell)
		await get_tree().process_frame
		check(bool(ore_torch.get("_torch_connected")),
			"pixie torch beside crystal ore connects")
		pixie.call("_break_tile", ore_neighbor)
		await get_tree().process_frame
		check(not bool(ore_torch.get("_torch_connected")),
			"pixie torch disconnects when its ore is mined")
		Global.time_of_day = fposmod(Global.time_of_day + 0.5, 1.0)
		pixie.call("_check_ore_regeneration")
		await get_tree().process_frame
		check(bool(ore_torch.get("_torch_connected")),
			"pixie torch reconnects when the ore regenerates")
		# The ore regen above may have restored the torch; mine it with a pick.
		var pixie_mine := _restore_torch(pixie, isolated_cell)
		var pixie_result: Dictionary = await _mine_torch(pixie, pixie_mine, WOODEN_PICK_PATH)
		check(int(pixie_result["new_drops"]) == 1,
			"pixie isolated torch drops once with a pickaxe")
		var pixie_drops: Array = pixie_result["drops"]
		if not pixie_drops.is_empty():
			check(_pickup_torch(pixie_drops.back() as Node, torch_data),
				"pixie dropped torch is collectible")
	else:
		check(false, "pixie generated a horizontal floor run for the torch test")

	var pixie_state_cell := _find_clear_floor_cell(pixie, true)
	if pixie_state_cell.x != -99999:
		var pixie_state_torch := _restore_torch(pixie, pixie_state_cell)
		var pixie_snapshot: Dictionary = pixie.snapshot_state()
		var pixie_restored := PixieCaveWorld.new()
		add_child(pixie_restored)
		pixie_restored.setup(414141, Vector2.ZERO)
		pixie_restored.apply_state(pixie_snapshot)
		var pixie_blocks: Dictionary = pixie_restored.get("_placed_blocks") as Dictionary
		check(pixie_blocks.has(pixie_state_cell),
			"pixie torch block restores after state load")
		if pixie_blocks.has(pixie_state_cell):
			var pixie_restored_torch: Node = (pixie_blocks[pixie_state_cell] as Dictionary)["node"]
			check((pixie_restored_torch.get("item_data") as ItemData) == torch_data,
				"restored pixie block keeps torch identity")
		pixie_restored.queue_free()
		await get_tree().process_frame
		pixie_state_torch.queue_free()

	pixie.queue_free()
	await get_tree().process_frame

	Global.time_of_day = old_time
	Global.Hotbar.fill(null)
	Global.Inventory.fill(null)
	Global.player_node = old_player if is_instance_valid(old_player) else null
	Global.world_node = old_world if is_instance_valid(old_world) else null
	player.queue_free()
	await get_tree().process_frame


func _test_algorithmica_color() -> void:
	var cactus_data: ItemData = load("res://resources/items/cactus.tres")
	var old_hotbar: Array = Global.Hotbar.duplicate(true)
	var old_inventory: Array = Global.Inventory.duplicate(true)
	var old_world := Global.world_node

	check(AlgorithmicaAPI.STATION_FUNCTIONS.has("craft_color"),
		"Algorithmica allows craft_color for crafting stations")
	var api_found := false
	var api_desc := ""
	for entry in APIReference.CUSTOM_PYTHON_STATION:
		if str((entry as Dictionary).get("sig", "")).begins_with("craft_color("):
			api_found = true
			api_desc = str((entry as Dictionary).get("desc", ""))
			break
	check(api_found, "craft_color is present in the in-game Algorithmica reference")
	check(api_desc.contains("Cactus") and api_desc.contains("255")
		and api_desc.contains("take_output"),
		"craft_color reference documents RGB range, cost, output and example")
	check(AlgorithmicaAPI.foreign_calls(
		"craft_color(1, 2, 3, 4)", AlgorithmicaAPI.FURNACE).has("craft_color"),
		"craft_color is rejected in furnace-only Algorithmica programs")
	var transpiler := PythonTranspiler.new()
	var transpiled = transpiler.transpile(
		"def main():\n    craft_color(255, 0, 0, 2)\n")
	check(bool(transpiled[0]), "Python transpiler accepts craft_color")

	Global.Hotbar.fill(null)
	Global.Inventory.fill(null)
	Global.world_node = null
	var station: Node = load("res://scenes/objects/CraftingStation.tscn").instantiate()
	add_child(station)
	await get_tree().process_frame

	var red: ItemData = ColorBlock.get_block(255, 0, 0)
	var green: ItemData = ColorBlock.get_block(0, 255, 0)
	check(red != null and green != null and red != green,
		"different RGB values produce distinct color items")
	check(red == ColorBlock.get_block(255, 0, 0),
		"same RGB values reuse one stackable color item")
	var color_slot: Dictionary = {"data": red, "quantity": 2}
	var color_roundtrip = Global.deserialize_item(Global.serialize_item(color_slot))
	check(color_roundtrip != null
		and (color_roundtrip as Dictionary).get("data") == red
		and int((color_roundtrip as Dictionary).get("quantity")) == 2,
		"custom RGB color survives inventory/save serialization")

	Global.add_item({"data": cactus_data, "quantity": 10})
	station.call("run_program",
		"def main():\n    craft_color(255, 0, 0, 2)\n    take_output()\n")
	await get_tree().process_frame
	check(Global.count_item(cactus_data) == 8,
		"craft_color consumes exactly one Cactus per block")
	check(Global.count_item(red) == 2,
		"craft_color produces the requested red block count")

	Global.Hotbar.fill(null)
	Global.Inventory.fill(null)
	Global.add_item({"data": cactus_data, "quantity": 1})
	station.call("run_program",
		"def main():\n    craft_color(0, 255, 0, 2)\n")
	await get_tree().process_frame
	check(Global.count_item(cactus_data) == 1
		and Global.count_item(green) == 0
		and int(station.call("get_output_quantity")) == 0,
		"insufficient Cactus fails without consuming materials")

	Global.add_item({"data": cactus_data, "quantity": 5})
	station.call("craft_color_request", 300, 0, 0, 1)
	station.call("craft_color_request", 0, 0, 0, 1)
	station.call("craft_color_request", 255, 255, 255, 1)
	station.call("craft_color_request", 0, 0, 0, 0)
	station.call("craft_color_request", 0, 0, 0, -1)
	station.call("craft_color_request", 0, 0, 0, 33)
	station.call("craft_color_request", "red", 0, 0, 1)
	station.call("craft_color_request", 255.0, 0, 0, 1)
	check(Global.count_item(cactus_data) == 6
		and int(station.call("get_output_quantity")) == 0,
		"invalid RGB/amount/type requests consume nothing")

	# Output-slot identity: crafting a different color must not merge or
	# consume Cactus while the first color is pending.
	station.call("craft_color_request", 255, 0, 0, 1)
	var before_block := Global.count_item(cactus_data)
	station.call("craft_color_request", 0, 255, 0, 1)
	check(int(station.call("get_output_quantity")) == 1
		and (station.call("get_output_item") as ItemData) == red
		and Global.count_item(cactus_data) == before_block,
		"a different pending color is rejected without consuming Cactus")

	# Algorithmica is code-only: the recipe picker, input slot and output/color
	# inspector are intentionally absent. take_output() is the collection path,
	# and the Python signature is unchanged.
	station.set("program_code", "# code is untouched")
	var menu: Control = station.get("_ui") as Control
	check(menu != null and menu.get("_code_edit") != null
		and menu.get("_auto_grid") == null
		and menu.get("_input_section") == null
		and menu.get("_output_slot") == null
		and station.get("program_code") == "# code is untouched",
		"Algorithmica exposes only the code panel")

	# Save/load keeps the custom RGB output identity and quantity.
	var station_save: Dictionary = station.call("get_station_save_data")
	check((station_save.get("output") as Dictionary).get("color", "") == "FF0000",
		"station save persists the custom RGB color key")
	station.call("set_station_save_data", station_save)
	check((station.call("get_output_item") as ItemData) == red
		and int(station.call("get_output_quantity")) == 1,
		"station load restores the custom color output")

	# Full inventory leaves the output safely in the station (take_output
	# never deletes items it cannot place).
	var stone: ItemData = load("res://resources/items/stone.tres")
	Global.Hotbar.fill(null)
	Global.Inventory.fill(null)
	for i in range(Global.Hotbar.size()):
		Global.Hotbar[i] = {"data": stone, "quantity": Global.MAX_STACK}
	for i in range(Global.Inventory.size()):
		Global.Inventory[i] = {"data": stone, "quantity": Global.MAX_STACK}
	check(int(station.call("take_output")) == 0
		and int(station.call("get_output_quantity")) == 1,
		"full inventory leaves crafted color in the station output")

	station.queue_free()
	await get_tree().process_frame
	Global.Hotbar = old_hotbar
	Global.Inventory = old_inventory
	Global.world_node = old_world if is_instance_valid(old_world) else null


func _test_cactus_and_worm() -> void:
	var world_script: GDScript = load("res://scripts/world.gd")
	var constants: Dictionary = world_script.get_script_constant_map()
	check(is_equal_approx(float(constants.get("CACTUS_SPAWN_INTERVAL", 0.0)), 60.0),
		"cactus spawn interval is increased to 60 seconds")
	check(int(constants.get("CACTUS_SPAWN_SAFE_RADIUS", 0)) >= 1
		and int(constants.get("CACTUS_SPAWN_ENTRANCE_CLEAR", 0)) >= 1,
		"cactus spawning protects spawn and entrance clearances")

	var cactus_data: ItemData = load("res://resources/items/cactus.tres")
	var old_world := Global.world_node
	Global.world_node = null
	var worm_scene: PackedScene = load("res://scenes/mobs/Worm.tscn")

	for _i in range(12):
		var worm: Node = worm_scene.instantiate()
		add_child(worm)
		worm.call("_die")
		worm.call("_die")
		await get_tree().process_frame
		var bundles: Array = []
		for child in get_children():
			if child.get("item_data") == cactus_data:
				bundles.append(child)
		check(bundles.size() == 1,
			"one defeated worm produces exactly one cactus bundle")
		if bundles.size() == 1:
			var qty: int = int((bundles[0] as Node).get("quantity"))
			check(qty >= 5 and qty <= 10,
				"worm cactus bundle quantity is 5-10 inclusive")
			(bundles[0] as Node).queue_free()
		await get_tree().process_frame

	# Exercise the actual damage/defeat path, not only _die() directly.
	var damage_worm: Node = worm_scene.instantiate()
	add_child(damage_worm)
	damage_worm.set("_mob_health", 1.0)
	damage_worm.call("take_hit", 100.0, Vector2.ZERO)
	await get_tree().process_frame
	var damage_bundles := 0
	for child in get_children():
		if child.get("item_data") == cactus_data:
			damage_bundles += 1
	check(damage_bundles == 1, "worm damage defeat produces one cactus bundle")
	for child in get_children():
		if child.get("item_data") == cactus_data:
			(child as Node).queue_free()
	await get_tree().process_frame

	var cleanup_worm: Node = worm_scene.instantiate()
	add_child(cleanup_worm)
	cleanup_worm.call("_die", false)
	await get_tree().process_frame
	var cleanup_drops := 0
	for child in get_children():
		if child.get("item_data") == cactus_data:
			cleanup_drops += 1
	check(cleanup_drops == 0, "worm cleanup death does not award cactus loot")

	var despawn_worm: Node = worm_scene.instantiate()
	add_child(despawn_worm)
	despawn_worm.call("_apply_despawn_zone", 2, 0.0)
	despawn_worm.call("_apply_despawn_zone", 2, 99999.0)
	await get_tree().process_frame
	var despawn_drops := 0
	for child in get_children():
		if child.get("item_data") == cactus_data:
			despawn_drops += 1
	check(despawn_drops == 0, "worm despawn/cleanup does not award cactus loot")

	Global.world_node = old_world if is_instance_valid(old_world) else null


func _test_fish_and_automatica() -> void:
	var glep: ItemData = load("res://resources/items/glep_glorp.tres")
	var pim: ItemData = load("res://resources/items/pimpim.tres")
	var cooked_glep: ItemData = load("res://resources/items/cooked_glep_glorp.tres")
	var cooked_pim: ItemData = load("res://resources/items/cooked_pimpim.tres")
	check(glep.item_name == "Glep" and glep.item_id() == "glep_glorp",
		"Glep fish display name is corrected without changing its scripting id")
	check(pim.item_name == "Pim" and pim.item_id() == "pimpim",
		"Pim fish display name is corrected without changing its scripting id")
	check(cooked_glep.item_name == "Cooked Glep" and cooked_glep.item_id() == "cooked_glep_glorp",
		"cooked Glep keeps its stable id")
	check(cooked_pim.item_name == "Cooked Pim" and cooked_pim.item_id() == "cooked_pimpim",
		"cooked Pim keeps its stable id")

	var automatica: ItemData = load("res://resources/items/lua.tres")
	check(automatica.item_name == "Automatica" and automatica.item_id() == "lua",
		"Automatica item display name is renamed with the legacy lua id preserved")
	var sections: Array = APIReference.encyclopedia_sections()
	if sections.size() > 1:
		var auto_section: Dictionary = sections[1]
		check(str(auto_section.get("title", "")).contains("Automatica")
			and not str(auto_section.get("title", "")).contains("LUA Robot"),
			"Programming Encyclopedia labels the robot Automatica")
	else:
		check(false, "Programming Encyclopedia exposes the Automatica section")

	var old_world := Global.world_node
	Global.world_node = null
	var npc: Node = load("res://scenes/objects/LuaNPC.tscn").instantiate()
	add_child(npc)
	await get_tree().process_frame
	var display_name := str(npc.call("get_display_name"))
	check(display_name.begins_with("Automatica"),
		"default robot label uses Automatica, not LUA")
	npc.queue_free()
	await get_tree().process_frame
	Global.world_node = old_world if is_instance_valid(old_world) else null


func _test_headless_fish_loot() -> void:
	var fish_items: Array = [
		load("res://resources/items/charlie.tres"),
		load("res://resources/items/glep_glorp.tres"),
		load("res://resources/items/allan.tres"),
		load("res://resources/items/pimpim.tres"),
	]
	var old_world := Global.world_node
	var old_player := Global.player_node
	Global.world_node = null
	Global.player_node = null
	var fish: Node = load("res://scenes/mobs/HeadlessFish.tscn").instantiate()
	add_child(fish)
	await get_tree().process_frame
	fish.call("_die")
	fish.call("_die")
	await get_tree().process_frame
	var drops: Array = []
	for child in get_children():
		if fish_items.has(child.get("item_data")):
			drops.append(child)
	check(drops.size() == 1, "one defeated Headless Fish produces exactly one fish drop")
	if drops.size() == 1:
		var item: ItemData = (drops[0] as Node).get("item_data") as ItemData
		check(item != null and fish_items.has(item)
			and int((drops[0] as Node).get("quantity")) == 1,
			"Headless Fish drops one valid existing raw fish")
		(drops[0] as Node).queue_free()
	await get_tree().process_frame

	var despawned: Node = load("res://scenes/mobs/HeadlessFish.tscn").instantiate()
	add_child(despawned)
	await get_tree().process_frame
	despawned.call("_apply_despawn_zone", 2, 99999.0)
	await get_tree().process_frame
	var extra := 0
	for child in get_children():
		if fish_items.has(child.get("item_data")):
			extra += 1
			(child as Node).queue_free()
	check(extra == 0, "Headless Fish despawn cleanup does not award fish")
	Global.world_node = old_world if is_instance_valid(old_world) else null
	Global.player_node = old_player if is_instance_valid(old_player) else null


func _test_rare_chest_generation() -> void:
	var dg := DungeonGenerator.new()
	var found := 0
	for seed in range(1, 81):
		dg.generate(seed, 0, 1, 3)
		if dg.rare_chest_positions.is_empty():
			continue
		found += 1
		check(dg.rare_chest_positions.size() == 1,
			"a dungeon places at most one rare chest")
		var cell: Vector2i = dg.rare_chest_positions[0] as Vector2i
		var in_bonus := false
		for room_value in dg.bonus_rooms:
			var room: Dictionary = room_value as Dictionary
			if _point_in_room(cell, room):
				in_bonus = true
				break
		check(in_bonus, "rare dungeon chest is in an eligible bonus room")
		check(dg.grid[cell.x][cell.y] == DungeonGenerator.Tile.FLOOR,
			"rare dungeon chest is on a floor tile")
		var clear_floor := true
		for dx in range(-1, 2):
			for dy in range(-1, 2):
				if dg.grid[cell.x + dx][cell.y + dy] != DungeonGenerator.Tile.FLOOR:
					clear_floor = false
		check(clear_floor, "rare dungeon chest has a clear 3x3 footprint")
		check(cell != dg.player_spawn_pos and cell != dg.knowledge_altar_pos
			and cell != dg.quiz_altar_pos,
			"rare dungeon chest is clear of spawn and altars")
	check(found > 0 and found < 80,
		"rare dungeon chests appear occasionally, not every dungeon")

	var rare: ItemData = load("res://resources/items/rare_dungeon_chest.tres")
	check(rare != null and rare.icon != null and rare.place_scene_path.ends_with("ChestBlock.tscn"),
		"rare chest reuses the existing chest scene and asset")
	var automation_pool: Array = RareChestLoot.AUTOMATION_POOL
	var food_pool: Array = RareChestLoot.FOOD_POOL
	for seed in range(1, 6):
		var rng := RandomNumberGenerator.new()
		rng.seed = seed
		var rolled: Array = RareChestLoot.roll(rng)
		var has_automation := false
		var has_food := false
		for slot in rolled:
			for entry in automation_pool:
				if (entry as Dictionary)["item"] == (slot as Dictionary)["data"]:
					has_automation = true
			for entry in food_pool:
				if (entry as Dictionary)["item"] == (slot as Dictionary)["data"]:
					has_food = true
		check(rolled.size() >= 2 and rolled.size() <= 3
			and has_automation and has_food,
			"rare chest loot mixes Automatica materials and food")

	var probe_cell := Vector2i(7, 9)
	Global.set_dungeon_chest_state(4, probe_cell, {"slots": [null], "removed": false})
	check(not Global.get_dungeon_chest_state(4, probe_cell).is_empty(),
		"rare dungeon chest state round-trips through the global store")
	Global.dungeon_chest_states.erase(Global._dungeon_chest_key(4, probe_cell))

	# Verify both cave generators can roll and place the shared rare chest.
	var old_world := Global.world_node
	var cave_found := false
	for seed in range(1, 26):
		var cave := CaveWorld.new()
		add_child(cave)
		cave.setup(seed, Vector2.ZERO)
		if bool(cave.get("_rare_chest_spawned")):
			cave_found = true
			var cell: Vector2i = cave.get("_rare_chest_cell") as Vector2i
			check((cave.get("_placed_blocks") as Dictionary).has(cell),
				"large cave rare chest is registered as a cave block")
			var snap: Dictionary = cave.call("snapshot_state")
			check(snap.has("rare_chest"), "large cave snapshot stores rare chest state")
			cave.queue_free()
			await get_tree().process_frame
			break
		cave.queue_free()
		await get_tree().process_frame
	check(cave_found, "large cave can generate a rare chest")
	Global.world_node = old_world if is_instance_valid(old_world) else null

	var pixie_found := false
	for seed in range(1, 26):
		var pixie := PixieCaveWorld.new()
		add_child(pixie)
		pixie.setup(seed, Vector2.ZERO)
		if bool(pixie.get("_rare_chest_spawned")):
			pixie_found = true
			var cell: Vector2i = pixie.get("_rare_chest_cell") as Vector2i
			check((pixie.get("_placed_blocks") as Dictionary).has(cell),
				"pixie cave rare chest is registered as a cave block")
			var snap: Dictionary = pixie.call("snapshot_state")
			check(snap.has("rare_chest"), "pixie cave snapshot stores rare chest state")
			pixie.queue_free()
			await get_tree().process_frame
			break
		pixie.queue_free()
		await get_tree().process_frame
	check(pixie_found, "pixie cave can generate a rare chest")
	Global.world_node = old_world if is_instance_valid(old_world) else null


func _test_minimap_lua_legend() -> void:
	var constants: Dictionary = load("res://scripts/minimap.gd").get_script_constant_map()
	check(constants.has("C_LUA") and str(constants.get("LUA_LEGEND", "")) == "LUA",
		"minimap exposes a LUA legend matching the Automatica marker colour")
	var minimap := Minimap.new()
	check(minimap != null, "minimap still instantiates with the LUA legend")
	minimap.free()


func _point_in_room(cell: Vector2i, room: Dictionary) -> bool:
	var p: Vector2i = room["pos"]
	var s: Vector2i = room["size"]
	return cell.x >= p.x and cell.y >= p.y and cell.x < p.x + s.x and cell.y < p.y + s.y


func _test_knowledge_altar_pages() -> void:
	var old_learned: Dictionary = Global.learned_entries.duplicate(true)
	var entries: Array = Global.knowledge_entries.values()
	if entries.size() < 10:
		check(false, "knowledge database has enough entries for pagination probe")
		Global.learned_entries = old_learned
		return
	var altar := KnowledgeAltar.new()
	add_child(altar)
	await get_tree().process_frame
	altar.set("_entry", entries[0] as KnowledgeEntry)
	Global.learned_entries.clear()
	altar.call("_show")
	await get_tree().process_frame

	var archive_box: VBoxContainer = altar.get("_archive_box") as VBoxContainer
	var page_label: Label = altar.get("_archive_page_label") as Label
	var prev_btn: Button = altar.get("_archive_prev") as Button
	var next_btn: Button = altar.get("_archive_next") as Button
	check(archive_box != null and archive_box.get_child_count() == 1
		and not prev_btn.visible and not next_btn.visible,
		"knowledge altar handles zero archive entries")

	for i in range(3):
		Global.learned_entries[(entries[i] as KnowledgeEntry).id()] = true
	Global.knowledge_updated.emit()
	await get_tree().process_frame
	check(int(altar.call("_archive_page_count")) == 1
		and page_label.visible and page_label.text == "Page 1 / 1"
		and prev_btn.disabled and next_btn.disabled,
		"knowledge altar handles an exactly full single page")

	for i in range(3, 7):
		Global.learned_entries[(entries[i] as KnowledgeEntry).id()] = true
	Global.knowledge_updated.emit()
	await get_tree().process_frame
	check(int(altar.call("_archive_page_count")) == 3
		and page_label.text == "Page 1 / 3"
		and prev_btn.disabled and not next_btn.disabled,
		"knowledge altar paginates multiple archive pages")
	altar.call("_change_archive_page", 1)
	check(int(altar.get("_archive_page")) == 1 and page_label.text == "Page 2 / 3",
		"knowledge altar next-page navigation works")
	altar.call("_change_archive_page", 99)
	check(int(altar.get("_archive_page")) == 2 and next_btn.disabled,
		"knowledge altar clamps at the last page")
	altar.call("_change_archive_page", -99)
	check(int(altar.get("_archive_page")) == 0 and prev_btn.disabled,
		"knowledge altar clamps at the first page")

	var page_count_before: int = int(altar.call("_archive_page_count"))
	for i in range(7, 10):
		Global.learned_entries[(entries[i] as KnowledgeEntry).id()] = true
	Global.knowledge_updated.emit()
	await get_tree().process_frame
	check(int(altar.call("_archive_page_count")) > page_count_before
		and (altar.get("_archive_entries") as Array).size() == 10,
		"knowledge altar updates pagination while open when knowledge unlocks")

	altar.queue_free()
	await get_tree().process_frame
	Global.learned_entries = old_learned
	Global.knowledge_updated.emit()


func _test_mission_events() -> void:
	var old_smelt: Dictionary = Global._find_mission("smelt_iron").duplicate(true)
	var old_place: Dictionary = Global._find_mission("place_blocks").duplicate(true)
	var smelt: Dictionary = Global._find_mission("smelt_iron")
	smelt["completed"] = false
	smelt["progress"] = 0
	var place: Dictionary = Global._find_mission("place_blocks")
	place["completed"] = false
	place["progress"] = 0

	var iron_ore: ItemData = load("res://resources/items/iron_ore.tres")
	var charcoal: ItemData = load("res://resources/items/charcoal.tres")
	var recipe: SmeltingRecipe = load("res://resources/recipes/smelt_iron.tres")
	check(recipe.mission_id == "smelt_iron",
		"iron smelting recipe declares its authoritative mission id")
	var furnace: Node = load("res://scripts/object_item.gd").new()
	furnace.set("input_item", iron_ore)
	furnace.set("input_quantity", 5)
	furnace.set("fuel_item", charcoal)
	furnace.set("fuel_quantity", 5)
	check(int(furnace.call("smelt_request", 2)) == 2
		and int(Global._find_mission("smelt_iron").get("progress")) == 2,
		"smelting two iron bars increments smelt_iron exactly twice")
	furnace.set("fuel_quantity", 0)
	var progress: int = int(Global._find_mission("smelt_iron").get("progress"))
	check(int(furnace.call("smelt_request", 1)) == 0
		and int(Global._find_mission("smelt_iron").get("progress")) == progress,
		"failed smelting does not increment smelt_iron")
	furnace.free()

	Global.record_block_placed()
	check(int(Global._find_mission("place_blocks").get("progress")) == 1,
		"successful placement event increments place_blocks once")
	Global.record_block_placed()
	check(int(Global._find_mission("place_blocks").get("progress")) == 2,
		"repeated successful placement events increment exactly once each")

	smelt["completed"] = bool(old_smelt.get("completed", false))
	smelt["progress"] = int(old_smelt.get("progress", 0))
	place["completed"] = bool(old_place.get("completed", false))
	place["progress"] = int(old_place.get("progress", 0))
	Global.mission_updated.emit()


# Tools are ordinary inventory data, so verify the shared ItemData helpers from
# every direction: resource flags, add_item splitting, migration, ordinary
# stacking, and the wood mission's shared log classification.
func _test_tool_stacking_and_wood_mission() -> void:
	var old_hotbar: Array = Global.Hotbar.duplicate(true)
	var old_inventory: Array = Global.Inventory.duplicate(true)
	var old_pending: Array = Global.pending_overflow_items.duplicate(true)
	var old_selected: int = Global.hotbar_selected
	var collect: Dictionary = Global._find_mission("collect_wood")
	var side: Dictionary = Global._find_mission("side_woodcutter")
	var old_collect: Dictionary = collect.duplicate(true)
	var old_side: Dictionary = side.duplicate(true)
	Global.Hotbar.fill(null)
	Global.Inventory.fill(null)
	Global.pending_overflow_items.clear()
	Global.hotbar_selected = 0

	var tool_paths: Array = [
		"woodenaxe.tres", "wooden_pickaxe.tres", "woodensword.tres",
		"ironaxe.tres", "iron_pickaxe.tres", "iron_sword.tres",
		"diamond_axe.tres", "diamond_pickaxe.tres", "diamond_sword.tres",
		"iron_hoe.tres", "fishing_rod.tres", "bucket.tres", "water_bucket.tres",
	]
	var tools_ok := true
	for fname in tool_paths:
		var data := load("res://resources/items/" + str(fname)) as ItemData
		if data == null or not data.is_tool() or data.stack_limit() != 1 \
				or data.can_stack() or data.stackable or data.max_stack_size != 1:
			tools_ok = false
	check(tools_ok,
		"all axe/pickaxe/sword/hoe/rod/bucket tools are authored unstackable with limit 1")

	var axe: ItemData = load("res://resources/items/woodenaxe.tres")
	var wood: ItemData = load("res://resources/items/wood.tres")
	var birch: ItemData = load("res://resources/items/birch_wood.tres")
	var snowy: ItemData = load("res://resources/items/snowy_wood.tres")
	var bread: ItemData = load("res://resources/items/bread.tres")
	check(wood.can_stack() and wood.stack_limit() == 32 \
		and bread.can_stack() and bread.stack_limit() == 32,
		"ordinary resources and food remain stackable")

	check(Global.add_item({"data": axe, "quantity": 3}),
		"three collected tools fit into empty inventory slots")
	var axe_slots := 0
	var separate := true
	for arr in [Global.Hotbar, Global.Inventory]:
		for slot in arr:
			if slot is Dictionary and (slot as Dictionary)["data"] == axe:
				axe_slots += 1
				if int((slot as Dictionary)["quantity"]) != 1:
					separate = false
	check(axe_slots == 3 and separate and Global.count_item(axe) == 3,
		"each collected tool occupies its own slot with quantity 1")

	# Full inventory: an all-or-nothing tool add must not create a partial stack.
	for i in range(Global.Hotbar.size()):
		Global.Hotbar[i] = {"data": wood, "quantity": 1}
	for i in range(Global.Inventory.size()):
		Global.Inventory[i] = {"data": wood, "quantity": 1}
	check(not Global.add_item({"data": axe, "quantity": 1})
		and Global.count_item(axe) == 0 and Global.space_for_item(axe) == 0,
		"a full inventory rejects a tool add without changing item counts")

	# Simulate an old save that stored three axes in one slot.
	Global.Hotbar.fill(null)
	Global.Inventory.fill(null)
	Global.Hotbar[0] = {"data": axe, "quantity": 3}
	Global._migrate_loaded_inventory_stacks()
	axe_slots = 0
	separate = true
	for arr in [Global.Hotbar, Global.Inventory]:
		for slot in arr:
			if slot is Dictionary and (slot as Dictionary)["data"] == axe:
				axe_slots += 1
				if int((slot as Dictionary)["quantity"]) != 1:
					separate = false
	check(axe_slots == 3 and separate and Global.count_item(axe) == 3,
		"loaded stacked tools split into individual slots without loss")

	# No free slot: keep one tool and queue the rest for overflow recovery.
	for i in range(Global.Hotbar.size()):
		Global.Hotbar[i] = {"data": wood, "quantity": 1}
	for i in range(Global.Inventory.size()):
		Global.Inventory[i] = {"data": wood, "quantity": 1}
	Global.Hotbar[0] = {"data": axe, "quantity": 3}
	Global._migrate_loaded_inventory_stacks()
	var queued_axes := 0
	for entry in Global.pending_overflow_items:
		if (entry as Dictionary).get("data") == axe:
			queued_axes += int((entry as Dictionary).get("quantity", 0))
	check(Global.count_item(axe) == 1 and queued_axes == 2,
		"tool-stack migration queues overflow instead of deleting it")
	Global.pending_overflow_items.clear()

	# Ordinary stackable material still merges in normal play.
	Global.Hotbar.fill(null)
	Global.Inventory.fill(null)
	check(Global.add_item({"data": wood, "quantity": 5})
		and Global.Hotbar[0] != null
		and int((Global.Hotbar[0] as Dictionary)["quantity"]) == 5,
		"ordinary wood still stacks into one slot")

	# Birch/snowy logs are wood by shared ItemData metadata, not by name.
	collect["completed"] = false
	collect["progress"] = 0
	side["completed"] = false
	side["progress"] = 0
	Global.Hotbar.fill(null)
	Global.Inventory.fill(null)
	Global.add_item({"data": birch, "quantity": 4})
	var after_birch: int = int(collect.get("progress", 0))
	Global.add_item({"data": snowy, "quantity": 3})
	var after_snowy: int = int(collect.get("progress", 0))
	Global.add_item({"data": wood, "quantity": 13})
	check(after_birch == 4 and after_snowy == 7
		and int(collect.get("progress", 0)) == 20
		and bool(collect.get("completed", false))
		and Global.wood_in_inventory() == 20,
		"birch/snowy/plain logs all count toward Collect 20 Wood")
	# Transfer/reload-style duplicate tracking must not add progress again.
	Global._track_craft_missions(birch, 4)
	Global._track_craft_missions(birch, 4)
	check(int(collect.get("progress", 0)) == 20,
		"wood mission progress is idempotent across repeated transfer tracking")

	# Container transfer: a chest deposit must also split tools.
	var chest: Node = load("res://scenes/objects/ChestBlock.tscn").instantiate()
	add_child(chest)
	chest.call("setup", load("res://resources/items/chest.tres") as ItemData)
	var chest_slots: Array = chest.get("slots") as Array
	var deposit_ok: bool = bool(chest.call("deposit_item", {"data": axe, "quantity": 2}))
	var chest_axes := 0
	var chest_separate := true
	for slot in chest_slots:
		if slot is Dictionary and (slot as Dictionary)["data"] == axe:
			chest_axes += 1
			if int((slot as Dictionary)["quantity"]) != 1:
				chest_separate = false
	check(deposit_ok and chest_axes == 2 and chest_separate,
		"container deposits keep each tool in its own slot")
	chest.queue_free()

	Global.Hotbar = old_hotbar
	Global.Inventory = old_inventory
	Global.pending_overflow_items = old_pending
	Global.hotbar_selected = old_selected
	collect["completed"] = bool(old_collect.get("completed", false))
	collect["progress"] = int(old_collect.get("progress", 0))
	side["completed"] = bool(old_side.get("completed", false))
	side["progress"] = int(old_side.get("progress", 0))
	Global.mission_updated.emit()


# Every ore that the world/ores expose must be accepted by the real furnace
# path and produce the intended refined item. This intentionally exercises
# smelt_request(), not just the .tres files, so a broken input/output reference
# cannot pass as "recipe present".
func _test_smelting_recipes() -> void:
	var pairs: Array = [
		["copper_ore", "copper"],
		["iron_ore", "ironbar"],
		["silicon_ore", "silicon"],
		["diamond_ore", "diamond"],
		["crystal_copper_ore", "copper"],
		["crystal_iron_ore", "ironbar"],
		["crystal_silicon_ore", "silicon"],
		["crystal_diamond_ore", "diamond"],
	]
	var charcoal: ItemData = load("res://resources/items/charcoal.tres")
	var recipe_inputs: Dictionary = {}
	for fname in ResourceLoader.list_directory("res://resources/recipes/"):
		if not fname.ends_with(".tres"):
			continue
		var resource: Resource = load("res://resources/recipes/" + fname)
		if resource is SmeltingRecipe:
			var rec: SmeltingRecipe = resource
			if rec.input_item != null:
				recipe_inputs[rec.input_item.resource_path] = rec
	for pair in pairs:
		var input_path: String = "res://resources/items/%s.tres" % str(pair[0])
		var expected_path: String = "res://resources/items/%s.tres" % str(pair[1])
		var input_item: ItemData = load(input_path)
		var expected: ItemData = load(expected_path)
		var rec: SmeltingRecipe = recipe_inputs.get(input_path)
		check(input_item != null and expected != null and rec != null
			and rec.output_item != null
			and rec.output_item.resource_path == expected_path,
			"%s has a valid smelting recipe producing %s" % [str(pair[0]), str(pair[1])])
		if rec == null or input_item == null or expected == null:
			continue
		var furnace: Node = load("res://scripts/object_item.gd").new()
		furnace.set("input_item", input_item)
		furnace.set("input_quantity", 3)
		furnace.set("fuel_item", charcoal)
		furnace.set("fuel_quantity", 3)
		check(furnace.call("_can_cook") == rec,
			"%s is selectable by the timed furnace cook" % str(pair[0]))
		var made: int = int(furnace.call("smelt_request", 2))
		check(made == 2
			and int(furnace.get("input_quantity")) == 1
			and int(furnace.get("fuel_quantity")) == 1
			and furnace.get("output_item") == expected
			and int(furnace.get("output_quantity")) == 2,
			"%s smelts through the furnace into %s with exact input/fuel use"
				% [str(pair[0]), str(pair[1])])
		furnace.free()

	# Sheep meat must be a real furnace input, not just an edible item. There
	# must be exactly one recipe so two cooks can never race on the same input.
	var sheep_meat: ItemData = load("res://resources/items/sheep_meat.tres")
	var cooked_sheep: ItemData = load("res://resources/items/cooked_sheep_meat.tres")
	var sheep_recipe: SmeltingRecipe = null
	var sheep_recipe_count := 0
	for fname in ResourceLoader.list_directory("res://resources/recipes/"):
		if not fname.ends_with(".tres"):
			continue
		var resource: Resource = load("res://resources/recipes/" + fname)
		if resource is SmeltingRecipe and (resource as SmeltingRecipe).input_item == sheep_meat:
			sheep_recipe_count += 1
			sheep_recipe = resource as SmeltingRecipe
	check(sheep_recipe_count == 1 and sheep_recipe != null
		and sheep_recipe.output_item == cooked_sheep,
		"sheep meat has exactly one furnace recipe producing cooked sheep meat")
	if sheep_recipe != null:
		var sheep_furnace: Node = load("res://scripts/object_item.gd").new()
		sheep_furnace.set("input_item", sheep_meat)
		sheep_furnace.set("input_quantity", 2)
		sheep_furnace.set("fuel_item", charcoal)
		sheep_furnace.set("fuel_quantity", 2)
		check(sheep_furnace.call("_can_cook") == sheep_recipe,
			"sheep meat is selectable by the timed furnace cook")
		check(int(sheep_furnace.call("smelt_request", 1)) == 1
			and sheep_furnace.get("output_item") == cooked_sheep
			and int(sheep_furnace.get("output_quantity")) == 1
			and int(sheep_furnace.get("input_quantity")) == 1
			and int(sheep_furnace.get("fuel_quantity")) == 1,
			"raw sheep meat cooks into cooked sheep meat using one fuel")
		var old_hotbar: Array = Global.Hotbar.duplicate(true)
		var old_inventory: Array = Global.Inventory.duplicate(true)
		Global.Hotbar.fill(null)
		Global.Inventory.fill(null)
		var collected: int = int(sheep_furnace.call("take_output"))
		check(collected == 1 and Global.count_item(cooked_sheep) == 1
			and int(sheep_furnace.get("output_quantity")) == 0,
			"cooked sheep meat can be collected without duplicating the output")
		Global.Hotbar = old_hotbar
		Global.Inventory = old_inventory
		Global.Hotbar_updated.emit()
		Global.Inventory_updated.emit()
		sheep_furnace.free()

	# Guard rails: failed smelts must not consume input/fuel, and a full output
	# slot must leave the batch untouched.
	var copper_ore: ItemData = load("res://resources/items/copper_ore.tres")
	var copper: ItemData = load("res://resources/items/copper.tres")
	var guard: Node = load("res://scripts/object_item.gd").new()
	guard.set("input_item", copper_ore)
	guard.set("input_quantity", 2)
	guard.set("fuel_item", charcoal)
	guard.set("fuel_quantity", 0)
	check(int(guard.call("smelt_request", 1)) == 0
		and int(guard.get("input_quantity")) == 2,
		"smelting without fuel consumes no ore")
	guard.set("fuel_quantity", 2)
	guard.set("output_item", copper)
	guard.set("output_quantity", 999)
	check(int(guard.call("smelt_request", 1)) == 0
		and int(guard.get("input_quantity")) == 2
		and int(guard.get("fuel_quantity")) == 2,
		"a full output slot consumes no ore or fuel")
	guard.set("output_item", null)
	guard.set("output_quantity", 0)
	var save_data: Dictionary = guard.call("get_furnace_save_data")
	var restored: Node = load("res://scripts/object_item.gd").new()
	restored.call("set_furnace_save_data", save_data)
	check(restored.get("input_item") == copper_ore
		and int(restored.get("input_quantity")) == 2
		and int(restored.get("fuel_quantity")) == 2,
		"furnace input/fuel/output state round-trips through save data")
	restored.free()
	guard.set("input_quantity", 1)
	check(int(guard.call("smelt_request", 5)) == 1
		and int(guard.get("input_quantity")) == 0
		and int(guard.get("fuel_quantity")) == 1
		and int(guard.get("output_quantity")) == 1,
		"an oversized smelt batch is capped by the available input and fuel")
	guard.free()

func _test_held_damage_display() -> void:
	var tooltip: CanvasLayer = load("res://scripts/item_tooltip.gd").new() as CanvasLayer
	add_child(tooltip)
	await get_tree().process_frame
	var pickaxe: ItemData = load("res://resources/items/wooden_pickaxe.tres")
	var axe: ItemData = load("res://resources/items/woodenaxe.tres")
	var sword: ItemData = load("res://resources/items/woodensword.tres")
	var torch: ItemData = load("res://resources/items/Torch.tres")
	check(pickaxe.held_damage_display() == 1 and axe.held_damage_display() == 1
		and torch.held_damage_display() == 1,
		"non-sword held items display the 1.0 token damage")
	check(sword.held_damage_display() == sword.sword_damage(),
		"sword display uses the sword tier damage")
	check(str(tooltip.call("_effect_text", pickaxe)).contains("Damage 1")
		and not str(tooltip.call("_effect_text", pickaxe)).contains("Damage 4"),
		"tooltip shows the authoritative non-sword damage")
	check(str(tooltip.call("_effect_text", sword)).contains("Damage %d" % sword.sword_damage()),
		"sword tooltip shows the sword damage")
	var zero_probe := ItemData.new()
	zero_probe.is_sword = false
	zero_probe.sword_level = 0
	check(zero_probe.held_damage_display() == 1,
		"positive held damage never displays as zero")
	tooltip.queue_free()
	await get_tree().process_frame


func _test_mining_tool_switch() -> void:
	var old_hotbar: Array = Global.Hotbar.duplicate(true)
	var old_selected: int = Global.hotbar_selected
	var old_world := Global.world_node
	var old_player := Global.player_node
	var old_pnc_hold: bool = Global.pnc_hold_active
	Global.Hotbar.resize(Global.HOTBAR_SIZE)
	Global.Hotbar.fill(null)
	var axe: ItemData = load("res://resources/items/woodenaxe.tres")
	var pick: ItemData = load("res://resources/items/wooden_pickaxe.tres")
	Global.Hotbar[0] = {"data": axe, "quantity": 1}
	Global.Hotbar[1] = {"data": pick, "quantity": 1}
	Global.set_hotbar_selection(0)
	var axe_id: String = Global.held_tool_id()
	Global.set_hotbar_selection(1)
	var pick_id: String = Global.held_tool_id()
	check(not axe_id.is_empty() and axe_id != pick_id,
		"held_tool_id tracks a real hotbar tool switch")
	Global.set_hotbar_selection(0)
	check(Global.held_tool_id() == axe_id,
		"held_tool_id is stable for the same selected item")

	# Tapping a hotbar slot keeps a PNC lock alive; the block/tree then restarts
	# its timer with the new tool. This helper is what player._input uses to
	# distinguish a hotbar tap from a tap elsewhere.
	var slot_probe := Control.new()
	slot_probe.position = Vector2(10, 10)
	slot_probe.size = Vector2(40, 40)
	slot_probe.add_to_group("hotbar_slot")
	add_child(slot_probe)
	check(Global.is_point_over_hotbar(Vector2(20, 20))
		and not Global.is_point_over_hotbar(Vector2(80, 80)),
		"hotbar taps are distinguished from taps elsewhere")
	slot_probe.queue_free()

	Global.pnc_hold_active = true
	var swing_probe := SwingProbe.new()
	add_child(swing_probe)
	Global.player_node = swing_probe
	var block: Node = load("res://scenes/objects/PlaceableBlock.tscn").instantiate()
	block.set("item_data", load("res://resources/items/wood.tres"))
	add_child(block)
	await get_tree().process_frame
	block.set("_player_nearby", true)
	block.set("_hovered", false)
	block.set("_mouse_held", true)
	block.set_process(true)
	await get_tree().process_frame
	# A PNC order walked here from a distant tap: the real cursor/camera moved,
	# so the cached hover is stale. The synthetic press must rebuild hover from
	# the PNC target cursor and still start mining.
	Global.set_touch_mouse(Vector2(-9999, -9999))
	var pnc_press := InputEventMouseButton.new()
	pnc_press.button_index = MOUSE_BUTTON_LEFT
	pnc_press.pressed = true
	pnc_press.position = get_viewport().get_canvas_transform() * block.global_position
	block.call("_input", pnc_press)
	check(bool(block.get("_breaking")),
		"PNC synthetic press starts mining after a stale-hover approach")
	var block_old_dur: float = float(block.get("_break_duration"))
	block.call("_add_break_progress", 0.5)
	var block_before: float = float(block.get("_break_progress"))
	var block_swings: int = swing_probe.swing_count
	Global.set_hotbar_selection(1)
	await get_tree().process_frame
	await get_tree().process_frame
	var block_after: float = float(block.get("_break_progress"))
	check(str(block.get("_break_tool_id")) == pick_id
		and block_before > 0.0 and block_after < block_before,
		"switching to a pickaxe restarts a wood block's break bar")
	check(float(block.get("_break_duration")) > block_old_dur,
		"the restarted block bar uses the new tool's duration")
	check(swing_probe.swing_count > block_swings,
		"continuous block mining repeatedly swings the held tool")
	block.queue_free()
	await get_tree().process_frame

	Global.set_hotbar_selection(0)
	var tree: Node = load("res://scenes/objects/Tree.tscn").instantiate()
	add_child(tree)
	await get_tree().process_frame
	tree.set("_player_nearby", true)
	tree.set("_hovered", true)
	tree.set("_pnc_auto_chop", true)
	tree.set_process(true)
	tree.call("chop", 0.25)
	var tree_old_dur: float = float(tree.get("_break_duration"))
	var tree_before: float = float(tree.get("_break_progress"))
	Global.set_hotbar_selection(1)
	await get_tree().process_frame
	await get_tree().process_frame
	var tree_after: float = float(tree.get("_break_progress"))
	check(str(tree.get("_break_tool_id")) == pick_id
		and tree_before > 0.0 and tree_after < tree_before,
		"switching to a pickaxe restarts a tree's break bar")
	check(float(tree.get("_break_duration")) > tree_old_dur,
		"the restarted tree bar uses the new tool's duration")
	tree.queue_free()
	await get_tree().process_frame

	Global.pnc_hold_active = old_pnc_hold
	Global.clear_touch_mouse()
	Global.Hotbar = old_hotbar
	Global.set_hotbar_selection(old_selected)
	Global.player_node = old_player if is_instance_valid(old_player) else null
	Global.world_node = old_world if is_instance_valid(old_world) else null
	swing_probe.queue_free()
	await get_tree().process_frame


func _test_pickaxe_blockers() -> void:
	var old_world := Global.world_node
	var cave := CaveWorld.new()
	add_child(cave)
	cave.setup(565656, Vector2.ZERO)
	Global.world_node = cave
	var wall := Vector2i(-9999, -9999)
	var wall_tile := -1
	for x in range(2, cave.generator.size - 2):
		for y in range(2, cave.generator.size - 2):
			var t := int(cave.generator.grid[x][y])
			if t != CaveGenerator.Tile.FLOOR:
				wall = cave.call("_grid_to_cell", Vector2i(x, y))
				wall_tile = t
				break
		if wall.x != -9999:
			break
	if wall.x != -9999:
		cave.set("_mine_tile", wall)
		var item: ItemData = (cave.get("_wall_items") as Dictionary).get(wall_tile) as ItemData
		cave.call("_spawn_mine_overlay", item, wall)
		await get_tree().physics_frame
		var blocker: Node = cave.get("_mine_blocker")
		check(blocker != null and is_instance_valid(blocker)
			and (blocker as StaticBody2D).collision_layer == 1
			and cave._tilemap.get_cell_tile_data(wall) == null,
			"cave mining keeps a solid collision blocker while the tile is hidden")
		var query := PhysicsShapeQueryParameters2D.new()
		var probe := CircleShape2D.new()
		probe.radius = 4.0
		query.shape = probe
		query.transform = Transform2D(0.0, cave._tilemap.to_global(cave._tilemap.map_to_local(wall)))
		query.collision_mask = 1
		var hit_blk := false
		for hit in cave.get_world_2d().direct_space_state.intersect_shape(query, 4):
			if hit.get("collider") == blocker:
				hit_blk = true
				break
		check(hit_blk, "cave mining blocker is physically collidable")
		cave.call("_destroy_mine_overlay", true)
		await get_tree().process_frame
		check(not is_instance_valid(cave.get("_mine_blocker"))
			and cave._tilemap.get_cell_tile_data(wall) != null,
			"cancelling cave mining restores collision and the wall tile")
	else:
		check(false, "cave generated a wall for the mining collision probe")
	cave.queue_free()
	await get_tree().process_frame

	var pixie := PixieCaveWorld.new()
	add_child(pixie)
	pixie.setup(787878, Vector2.ZERO)
	Global.world_node = pixie
	var pwall := Vector2i(-9999, -9999)
	var ptile := -1
	for x in range(2, pixie.generator.width - 2):
		for y in range(2, pixie.generator.height - 2):
			var t := int(pixie.generator.grid[x][y])
			if t != PixieCaveGenerator.Tile.FLOOR:
				pwall = pixie.call("_grid_to_cell", Vector2i(x, y))
				ptile = t
				break
		if pwall.x != -9999:
			break
	if pwall.x != -9999:
		pixie.set("_mine_tile", pwall)
		var pitem: ItemData = (pixie.get("_wall_items") as Dictionary).get(ptile) as ItemData
		pixie.call("_spawn_mine_overlay", pitem, pwall)
		await get_tree().physics_frame
		var pblocker: Node = pixie.get("_mine_blocker")
		check(pblocker != null and is_instance_valid(pblocker)
			and (pblocker as StaticBody2D).collision_layer == 1,
			"pixie mining keeps a solid collision blocker")
		var pquery := PhysicsShapeQueryParameters2D.new()
		var pprobe := CircleShape2D.new()
		pprobe.radius = 4.0
		pquery.shape = pprobe
		pquery.transform = Transform2D(0.0, pixie._tilemap.to_global(pixie._tilemap.map_to_local(pwall)))
		pquery.collision_mask = 1
		var phit := false
		for hit in pixie.get_world_2d().direct_space_state.intersect_shape(pquery, 4):
			if hit.get("collider") == pblocker:
				phit = true
				break
		check(phit, "pixie mining blocker is physically collidable")
		pixie.call("_destroy_mine_overlay", true)
		await get_tree().process_frame
		check(pixie._tilemap.get_cell_tile_data(pwall) != null,
			"cancelling pixie mining restores the wall tile")
	else:
		check(false, "pixie generated a wall for the mining collision probe")
	pixie.queue_free()
	await get_tree().process_frame
	Global.world_node = old_world if is_instance_valid(old_world) else null


func _test_cave_pickup() -> void:
	var old_world := Global.world_node
	var old_player := Global.player_node
	var old_hotbar: Array = Global.Hotbar.duplicate(true)
	var old_inventory: Array = Global.Inventory.duplicate(true)
	Global.reset_pause_state()
	Global.Hotbar.resize(Global.HOTBAR_SIZE)
	Global.Inventory.resize(Global.INVENTORY_SIZE)
	Global.Hotbar.fill(null)
	Global.Inventory.fill(null)
	var player := CharacterBody2D.new()
	player.add_to_group("Player")
	player.collision_layer = 4
	player.collision_mask = 1
	var pshape := CollisionShape2D.new()
	var prect := RectangleShape2D.new()
	prect.size = Vector2(20, 12)
	pshape.shape = prect
	pshape.position = Vector2(0, 17)
	player.add_child(pshape)
	add_child(player)
	Global.player_node = player
	var item: ItemData = load("res://resources/items/stone.tres")

	var cave := CaveWorld.new()
	add_child(cave)
	cave.setup(909090, Vector2.ZERO)
	Global.world_node = cave
	player.global_position = cave.call("get_player_spawn_position")
	var drop: Node = load("res://scenes/ui/InventoryItem.tscn").instantiate()
	drop.call("set_item_data", item, 2)
	cave.add_child(drop)
	drop.global_position = player.global_position
	await get_tree().process_frame
	await get_tree().physics_frame
	await get_tree().process_frame
	check(not is_instance_valid(drop) or bool(drop.get("player_in_range")),
		"cave drop enters pickup range")
	check(Global.count_item(item) == 2,
		"cave underfoot drop is collected with its full quantity")
	cave.queue_free()
	await get_tree().process_frame

	var pixie := PixieCaveWorld.new()
	add_child(pixie)
	pixie.setup(919191, Vector2.ZERO)
	Global.world_node = pixie
	Global.Hotbar.fill(null)
	Global.Inventory.fill(null)
	player.global_position = pixie.call("get_player_spawn_position")
	var pdrop: Node = load("res://scenes/ui/InventoryItem.tscn").instantiate()
	pdrop.call("set_item_data", item, 1)
	pixie.add_child(pdrop)
	pdrop.global_position = player.global_position
	await get_tree().process_frame
	await get_tree().physics_frame
	await get_tree().process_frame
	check(Global.count_item(item) == 1,
		"pixie-cave underfoot drop is collected")
	pixie.queue_free()
	await get_tree().process_frame
	Global.Hotbar = old_hotbar
	Global.Inventory = old_inventory
	Global.world_node = old_world if is_instance_valid(old_world) else null
	Global.player_node = old_player if is_instance_valid(old_player) else null
	player.queue_free()
	await get_tree().process_frame


# Pixies use their own script (not BestiaryMob), so verify both the shared loot
# table and the actual world-drop path produce the Pixie Stone pick-up.
func _test_pixie_loot() -> void:
	var old_player: Node = Global.player_node
	Global.player_node = null
	var table := load("res://resources/mobs/pixie.tres") as MobCombatData
	var has_entry := false
	for entry_value in table.drops:
		if entry_value is Dictionary:
			var entry: Dictionary = entry_value as Dictionary
			if str(entry.get("item_path", "")).ends_with("pixie_cave_stone.tres"):
				has_entry = true
	check(has_entry,
		"Pixie loot table includes the Pixie Cave Stone")

	var pixie: Node2D = load("res://scenes/mobs/Pixie.tscn").instantiate()
	add_child(pixie)
	pixie.set_physics_process(false)
	pixie.global_position = Vector2(40000, 40000)
	await get_tree().process_frame
	pixie.call("_drop_loot")
	await get_tree().process_frame
	var dropped := 0
	var drop_nodes: Array = []
	for child in get_children():
		var item: Variant = child.get("item_data")
		if item is ItemData and (item as ItemData).item_name == "Pixie Stone":
			dropped += int(child.get("quantity"))
			drop_nodes.append(child)
	check(dropped == 1,
		"Pixie death loot spawns one Pixie Cave Stone pickup")
	for child in drop_nodes:
		if is_instance_valid(child):
			child.queue_free()
	pixie.queue_free()
	Global.player_node = old_player if is_instance_valid(old_player) else null
	await get_tree().process_frame

func _test_worm_water_guard() -> void:
	var layer := TileMapLayer.new()
	var ts := TileSet.new()
	ts.tile_size = Vector2i(32, 32)
	var img := Image.create_empty(32, 32, false, Image.FORMAT_RGBA8)
	var tex := ImageTexture.create_from_image(img)
	var src := TileSetAtlasSource.new()
	src.texture = tex
	src.texture_region_size = Vector2i(32, 32)
	src.create_tile(Vector2i(0, 0))
	ts.add_source(src, 0)
	layer.tile_set = ts
	layer.set_cell(Vector2i(0, 0), 0, Vector2i(0, 0))
	var mob := CharacterBody2D.new()
	mob.global_position = Vector2(16, 0)
	var ai := WormAI.new()
	var into_water: Vector2 = ai.call("_water_safe", mob, layer, Vector2(0, 64), 0.016)
	var away: Vector2 = ai.call("_water_safe", mob, layer, Vector2(0, -64), 0.016)
	check(into_water == Vector2.ZERO, "worm movement is blocked at a water boundary")
	check(away.length() > 0.0, "worm movement away from water remains allowed")
	mob.free()
	layer.free()


func _test_escape() -> void:
	var menu: Control = load("res://scenes/ui/main_menu_ver.tscn").instantiate() as Control
	add_child(menu)
	await get_tree().process_frame
	Global.set_online_mode(false)
	menu.call("_refresh_online_visibility")
	var go_online_btn: Button = menu.get("_go_online_btn") as Button
	var online_row: HBoxContainer = menu.get("_online_row") as HBoxContainer
	check(go_online_btn != null and go_online_btn.visible and not online_row.visible,
		"offline main menu exposes a Go Online button")
	Global.set_online_mode(true)
	menu.call("_refresh_online_visibility")
	check(not go_online_btn.visible and online_row.visible,
		"online main menu hides the offline Go Online button")
	Global.set_online_mode(false)
	menu.call("_refresh_online_visibility")
	var settings: Control = menu.get("_settings_overlay")
	settings.visible = true
	check(bool(menu.call("_close_top_overlay")) and not settings.visible,
		"Escape-style back closes the top menu overlay")
	var confirm: Control = menu.get("_confirm_overlay")
	confirm.visible = true
	var destructive := [false]
	menu.set("_confirm_cb", func() -> void: destructive[0] = true)
	check(bool(menu.call("_close_top_overlay")) and not confirm.visible,
		"back dismisses the confirmation overlay")
	check(not destructive[0], "back cancels a destructive dialog instead of confirming it")
	menu.queue_free()
	await get_tree().process_frame


# The shared Escape/Android-Back dispatcher must dismiss only the newest valid
# overlay, then reveal the layer underneath on the next request.
func _test_ui_back_stack() -> void:
	var under: Control = Control.new()
	var over: Control = Control.new()
	var hidden: Control = Control.new()
	add_child(under)
	add_child(over)
	add_child(hidden)
	under.visible = true
	over.visible = true
	hidden.visible = false
	var calls: Array = []

	Global.register_ui_back(under, func() -> void: calls.append("under"))
	Global.register_ui_back(over, func() -> void: calls.append("over"))
	Global.register_ui_back(hidden, func() -> void: calls.append("hidden"))
	var first_event := InputEventAction.new()
	first_event.action = "escape"
	first_event.pressed = true
	var second_event := InputEventAction.new()
	second_event.action = "escape"
	second_event.pressed = true
	check(Global.request_ui_back(first_event) and calls == ["over"],
		"back ignores a hidden stale overlay and dismisses the top visible one")
	check(not Global.request_ui_back(first_event) and calls == ["over"],
		"one key event cannot dismiss a second UI layer")
	check(Global.request_ui_back(second_event) and calls == ["over", "under"],
		"a new back event falls through to the underlying overlay")
	check(not Global.request_ui_back(second_event),
		"back does nothing when no dismissible UI remains")
	Global.unregister_ui_back(under)
	Global.unregister_ui_back(over)
	Global.unregister_ui_back(hidden)
	under.queue_free()
	over.queue_free()
	hidden.queue_free()
	await get_tree().process_frame

# Exercise the same registered back action on real panel scripts. These are the
# lightweight panels that can be built without a world/player; heavier altars
# are covered by their own pause/teardown tests.
func _test_ui_back_actual() -> void:
	var crafting: Control = load("res://scripts/crafting_menu.gd").new() as Control
	add_child(crafting)
	await get_tree().process_frame
	crafting.call("show_menu")
	check(crafting.visible and Global.request_ui_back() and not crafting.visible,
		"back closes the real crafting station panel")
	crafting.queue_free()

	var smelting: Control = load("res://scripts/smelting_menu.gd").new() as Control
	add_child(smelting)
	await get_tree().process_frame
	smelting.call("show_menu")
	check(smelting.visible and Global.request_ui_back() and not smelting.visible,
		"back closes the real furnace smelting panel")
	smelting.queue_free()

	var color: Control = load("res://scripts/color_crafter_menu.gd").new() as Control
	add_child(color)
	await get_tree().process_frame
	color.call("open")
	var color_close: Button = color.get("_close_btn") as Button
	var color_panel: PanelContainer = null
	if color_close != null:
		color_panel = color_close.get_parent().get_parent().get_parent() as PanelContainer
	check(color_close != null and color_close.visible and color_panel != null
		and color_panel.get_global_rect().encloses(color_close.get_global_rect())
		and Global.any_ui_open(),
		"color crafter shows an X button inside its paused panel")
	if color_close != null:
		color_close.emit_signal("pressed")
	check(not color.visible and not Global.any_ui_open(),
		"the Color Crafter X closes only that panel and releases the pause")
	color.call("open")
	check(color.visible and Global.request_ui_back() and not color.visible,
		"back closes the real color crafter panel")
	color.queue_free()

	var furnace_panel: Control = load("res://scripts/furnace_programming_panel.gd").new() as Control
	add_child(furnace_panel)
	await get_tree().process_frame
	furnace_panel.call("open", null)
	check(furnace_panel.visible and Global.request_ui_back() and not furnace_panel.visible,
		"back closes the real furnace Algorithmica editor")
	furnace_panel.queue_free()

	var pause: Control = load("res://scripts/pause_menu.gd").new() as Control
	add_child(pause)
	await get_tree().process_frame
	pause.call("show_menu")
	check(pause.visible and Global.request_ui_back() and not pause.visible,
		"back closes the real pause menu")
	pause.queue_free()

	var inv_layer := CanvasLayer.new()
	add_child(inv_layer)
	var inventory: Control = load("res://scenes/ui/inventory_ui.tscn").instantiate() as Control
	inv_layer.add_child(inventory)
	await get_tree().process_frame
	inv_layer.visible = true
	Global.open_ui()
	Global.register_ui_back(inventory, Callable(inventory, "dismiss_back"))
	check(Global.request_ui_back() and not inv_layer.visible,
		"back closes the real inventory panel and releases its pause")

	# The X button calls _close() directly, and a docked chest can close the
	# same panel when the player walks away. Both must emit the visibility
	# signal or the HUD/hotbar remain hidden after the inventory disappears.
	var inv_events: Array = []
	var on_inv := func(is_open: bool) -> void: inv_events.append(is_open)
	Global.inventory_toggled.connect(on_inv)
	inv_events.clear()
	inv_layer.visible = true
	Global.open_ui()
	Global.register_ui_back(inventory, Callable(inventory, "dismiss_back"))
	inventory.call("_close")
	await get_tree().process_frame
	check(not inv_layer.visible and inv_events == [false] and not Global.any_ui_open(),
		"inventory X button restores the HUD/hotbar via one close signal")
	inv_events.clear()
	inv_layer.visible = true
	Global.open_ui()
	Global.register_ui_back(inventory, Callable(inventory, "dismiss_back"))
	var fake_chest := Node.new()
	add_child(fake_chest)
	inventory.set("_chest", fake_chest)
	inventory.call("close_chest", fake_chest)
	await get_tree().process_frame
	check(not inv_layer.visible and inv_events == [false] and not Global.any_ui_open(),
		"chest auto-close restores the HUD/hotbar via one close signal")
	fake_chest.queue_free()
	Global.inventory_toggled.disconnect(on_inv)
	inv_layer.queue_free()

	# The Lua editor's own X button/Escape closes its panel directly, not
	# through LuaUI.close_editor(); it must still restore the HUD.
	var lua_editor: Control = load("res://scenes/ui/LuaEditorUI.tscn").instantiate() as Control
	add_child(lua_editor)
	await get_tree().process_frame
	var modal_events: Array = []
	var on_modal := func(is_open: bool) -> void: modal_events.append(is_open)
	Global.modal_hud_changed.connect(on_modal)
	Global.open_ui()
	Global.modal_hud_changed.emit(true)
	lua_editor.call("open_panel")
	lua_editor.call("close_panel")
	await get_tree().process_frame
	check(not lua_editor.visible and modal_events == [true, false]
		and not Global.any_ui_open(),
		"Lua editor close restores the HUD via one modal signal")
	Global.modal_hud_changed.disconnect(on_modal)
	lua_editor.queue_free()

	# The inventory keeps the hotbar alive above its dim layer; true modals
	# (station/editor/documentation/map) still hide the whole HUD.
	var hotbar: Control = load("res://scenes/ui/Hotbar.tscn").instantiate() as Control
	add_child(hotbar)
	await get_tree().process_frame
	var hotbar_canvas: CanvasLayer = hotbar.get_node("CanvasLayer") as CanvasLayer
	Global.inventory_toggled.emit(true)
	check(hotbar_canvas.visible and hotbar_canvas.layer == 13,
		"inventory keeps the nested hotbar canvas visible above its dim overlay")
	Global.modal_hud_changed.emit(true)
	Global.inventory_toggled.emit(false)
	check(not hotbar_canvas.visible,
		"a station/editor/documentation/map modal keeps the hotbar hidden after inventory closes")
	Global.modal_hud_changed.emit(false)
	check(hotbar_canvas.visible, "closing the last modal restores the hotbar")
	hotbar.queue_free()

	await get_tree().process_frame
	Global.reset_pause_state()

func _test_sync_loading() -> void:
	var old_online: bool = Global.online_mode
	var old_status: int = Global.cloud_status
	var events: Array = []
	var on_progress := func(info: Dictionary) -> void: events.append(info)
	CloudSync.sync_progress_changed.connect(on_progress)
	Global.set_online_mode(false)
	var summary: Dictionary = await CloudSync.sync_all()
	check(summary is Dictionary and summary.has("uploaded") and summary.has("failed")
		and events.size() > 0
		and str((events[events.size() - 1] as Dictionary).get("stage", "")) == "offline",
		"cloud sync exposes an offline progress event and a complete summary")
	CloudSync.sync_progress_changed.disconnect(on_progress)
	Global.set_online_mode(old_online)
	Global.set_cloud_status(old_status)

	# The shared account panel owns the sign-in/create busy bar; the main menu
	# reuses it as a determinate world-sync bar.
	var account: Control = load("res://scripts/online_account_panel.gd").new() as Control
	add_child(account)
	await get_tree().process_frame
	account.call("open_login")
	await get_tree().process_frame
	var bar: ProgressBar = account.get("_busy_bar") as ProgressBar
	account.call("_set_busy", true, "Signing in...")
	check(bar != null and bar.visible and bar.indeterminate,
		"account sign-in/create shows an indeterminate loading bar")
	account.call("set_operation_progress", "Syncing your worlds...", 50.0)
	check(bar != null and bar.visible and not bar.indeterminate
		and int(round(bar.value)) == 50,
		"account panel can show determinate cloud-sync progress")
	account.call("set_operation_progress", "", 100.0, false)
	check(bar != null and not bar.visible,
		"account panel hides its loading bar when the operation finishes")
	account.queue_free()
	await get_tree().process_frame

	var startup_src := FileAccess.get_file_as_string("res://scripts/startup_mode.gd")
	var menu_src := FileAccess.get_file_as_string("res://scripts/main_menu_ver.gd")
	var game_src := FileAccess.get_file_as_string("res://scenes/game_instance.gd")
	check(startup_src.contains("_progress_bar")
		and startup_src.contains("await CloudSync.sync_all()"),
		"startup sign-in is a cloud-sync barrier with a loading bar")
	check(menu_src.contains("set_operation_progress")
		and menu_src.contains("await CloudSync.sync_all()"),
		"in-menu sign-in waits for cloud sync before refreshing worlds")
	check(game_src.contains("_loading_bar")
		and game_src.contains("_finish_loading_fade")
		and game_src.contains('"modulate:a"'),
		"world loading has a progress bar and fades out into the world")


func _test_inventory_hotbar() -> void:
	var old_override: int = Global.mobile_platform_override
	var old_scale: float = Global.ui_scale
	var old_viewport: Vector2 = Global.ui_viewport_size
	var old_insets: Vector4 = Global.ui_safe_insets
	var old_hotbar: Array = Global.Hotbar.duplicate(true)
	var old_inventory: Array = Global.Inventory.duplicate(true)
	var old_selected: int = Global.hotbar_selected

	Global.mobile_platform_override = 0
	Global.ui_scale = 1.0
	Global.ui_viewport_size = Vector2(1280, 720)
	Global.ui_safe_insets = Vector4.ZERO
	ThemeDB.fallback_font_size = Global.ui_font_size(float(Global.UI_FALLBACK_FONT_BASE))
	Global.Hotbar.resize(Global.HOTBAR_SIZE)
	Global.Hotbar.fill(null)
	Global.Inventory.resize(Global.INVENTORY_SIZE)
	Global.Inventory.fill(null)

	var wood := load("res://resources/items/wood.tres") as ItemData
	var stone := load("res://resources/items/stone.tres") as ItemData
	Global.Hotbar[0] = {"data": wood, "quantity": 3}
	Global.set_hotbar_selection(2)

	var hotbar: Control = load("res://scenes/ui/Hotbar.tscn").instantiate() as Control
	add_child(hotbar)
	await get_tree().process_frame
	var hotbar_canvas: CanvasLayer = hotbar.get_node("CanvasLayer") as CanvasLayer
	var hotbar_slots: Array = hotbar.get("slots")

	Global.inventory_toggled.emit(true)
	check(hotbar_canvas.visible and hotbar_canvas.layer == 13,
		"opening the inventory keeps the persistent hotbar visible above its dim layer")
	check(Global.Hotbar[0] != null and int(Global.Hotbar[0]["quantity"]) == 3
		and Global.hotbar_selected == 2,
		"opening the inventory preserves hotbar contents and selected slot")
	check(is_equal_approx(Global.hotbar_hud_height(), 76.0),
		"the desktop hotbar reports its full bottom HUD band")

	var target_slot: Control = null
	if hotbar_slots.size() > 1:
		target_slot = hotbar_slots[1] as Control
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	if target_slot != null:
		target_slot.call("_gui_input", press)
	check(Global.hotbar_selected == 1,
		"hotbar slots stay interactive while the inventory is open")

	Global.modal_hud_changed.emit(true)
	check(not hotbar_canvas.visible and hotbar_canvas.layer == 10,
		"a station/editor/documentation/map modal still hides the hotbar")
	Global.modal_hud_changed.emit(false)
	check(hotbar_canvas.visible and hotbar_canvas.layer == 13,
		"closing that modal restores the hotbar above the still-open inventory")
	Global.inventory_toggled.emit(false)
	check(hotbar_canvas.visible and hotbar_canvas.layer == 10
		and Global.hotbar_selected == 1 and int(Global.Hotbar[0]["quantity"]) == 3,
		"closing the inventory returns the hotbar to normal with state intact")

	# Desktop inventory: panel/scroll ends above the persistent hotbar band.
	var inv_layer := CanvasLayer.new()
	add_child(inv_layer)
	var inventory: Control = load("res://scenes/ui/inventory_ui.tscn").instantiate() as Control
	inv_layer.add_child(inventory)
	await get_tree().process_frame
	await get_tree().process_frame
	var main_scroll: ScrollContainer = null
	for child in inventory.get_children():
		if child is ScrollContainer:
			main_scroll = child as ScrollContainer
			break
	var expected_bottom: float = -(Global.ui_safe_insets.w + Global.hotbar_hud_height()
		+ 12.0 * Global.ui_scale)
	check(main_scroll != null and is_equal_approx(main_scroll.offset_bottom, expected_bottom),
		"desktop inventory reserves the hotbar band above its content")

	# Both drag directions use the existing slot rules, not a parallel copy.
	var inv_slots: Array = inventory.get("_slots")
	Global.Inventory[0] = {"data": wood, "quantity": 4}
	Global.Hotbar[0] = null
	if hotbar_slots.size() > 0:
		(hotbar_slots[0] as Control).call("_drop_data", Vector2.ZERO,
			{"from_index": 0, "item": Global.Inventory[0], "source": "inventory"})
	check(Global.Hotbar[0] != null and int(Global.Hotbar[0]["quantity"]) == 4
		and Global.Inventory[0] == null,
		"dragging an inventory stack into a hotbar slot moves it exactly once")
	var from_hotbar: Dictionary = {"from_index": 0, "item": Global.Hotbar[0], "source": "hotbar"}
	if inv_slots.size() > 1:
		(inv_slots[1] as Control).call("_drop_data", Vector2.ZERO, from_hotbar)
	check(Global.Inventory[1] != null and int(Global.Inventory[1]["quantity"]) == 4
		and Global.Hotbar[0] == null,
		"dragging a hotbar stack into an inventory slot moves it exactly once")

	# Cross-container swap preserves both stacks.
	Global.Inventory[2] = {"data": stone, "quantity": 2}
	Global.Hotbar[2] = {"data": wood, "quantity": 5}
	if hotbar_slots.size() > 2:
		(hotbar_slots[2] as Control).call("_drop_data", Vector2.ZERO,
			{"from_index": 2, "item": Global.Inventory[2], "source": "inventory"})
	check(Global.Hotbar[2] != null
		and (Global.Hotbar[2]["data"] as ItemData) == stone
		and Global.Inventory[2] != null
		and (Global.Inventory[2]["data"] as ItemData) == wood,
		"inventory/hotbar drops swap stacks without duplication or loss")

	# Mobile inventory uses the same persistent-hotbar rule and reserve.
	Global.mobile_platform_override = 1
	Global.inventory_toggled.emit(true)
	check(hotbar_canvas.visible and hotbar_canvas.layer == 13
		and is_equal_approx(Global.hotbar_hud_height(), 80.0),
		"mobile inventory keeps the hotbar visible with its own touch-sized band")
	Global.inventory_toggled.emit(false)

	var mobile_layer := CanvasLayer.new()
	add_child(mobile_layer)
	var mobile_inv: Control = load("res://scenes/ui/inventory_ui.tscn").instantiate() as Control
	mobile_layer.add_child(mobile_inv)
	await get_tree().process_frame
	await get_tree().process_frame
	var mobile_scroll: ScrollContainer = null
	for child in mobile_inv.get_children():
		if child is ScrollContainer:
			mobile_scroll = child as ScrollContainer
			break
	var mobile_expected: float = -(Global.ui_safe_insets.w + Global.hotbar_hud_height()
		+ 12.0 * Global.ui_scale)
	check(mobile_scroll != null and is_equal_approx(mobile_scroll.offset_bottom, mobile_expected),
		"mobile inventory reserves the same persistent-hotbar band")

	inv_layer.queue_free()
	mobile_layer.queue_free()
	hotbar.queue_free()
	await get_tree().process_frame
	Global.inventory_toggled.emit(false)
	Global.modal_hud_changed.emit(false)
	Global.mobile_platform_override = old_override
	Global.ui_scale = old_scale
	Global.ui_viewport_size = old_viewport
	Global.ui_safe_insets = old_insets
	Global.Hotbar = old_hotbar
	Global.Inventory = old_inventory
	Global.set_hotbar_selection(old_selected)
	ThemeDB.fallback_font_size = Global.ui_font_size(float(Global.UI_FALLBACK_FONT_BASE))


func _test_chest_inventory_panel() -> void:
	var old_inventory: Array = Global.Inventory.duplicate(true)
	var old_player: Node = Global.player_node
	var wood := load("res://resources/items/wood.tres") as ItemData
	var chest_data := load("res://resources/items/chest.tres") as ItemData
	var player_stub := CharacterBody2D.new()
	player_stub.name = "PlayerStub"
	add_child(player_stub)
	var layer := CanvasLayer.new()
	layer.name = "InventoryUI"
	layer.layer = 12
	player_stub.add_child(layer)
	var ui: Control = load("res://scenes/ui/inventory_ui.tscn").instantiate() as Control
	layer.add_child(ui)
	layer.visible = true
	Global.player_node = player_stub
	for i in range(Global.INVENTORY_SIZE):
		Global.Inventory[i] = null
	Global.Inventory[0] = {"data": wood, "quantity": 4}
	Global.Inventory_updated.emit()

	var chest: Node = load("res://scenes/objects/ChestBlock.tscn").instantiate()
	add_child(chest)
	chest.call("setup", chest_data)
	var chest_slots: Array = chest.get("slots") as Array
	chest_slots[0] = {"data": wood, "quantity": 12}
	chest_slots[1] = {"data": wood, "quantity": 3}
	chest.set("_player_nearby", true)
	ui.call("attach_chest", chest)
	await get_tree().process_frame
	chest.set("_open_ui", ui)

	var header_icon: TextureRect = ui.get("_chest_icon") as TextureRect
	var header_title: Label = ui.get("_chest_title") as Label
	var trash_row: HBoxContainer = ui.get("_trash_row") as HBoxContainer
	var inv_body: HBoxContainer = ui.get("_inv_body") as HBoxContainer
	check(bool((ui.get("_chest_section") as Control).visible)
		and (ui.get("_chest_slots") as Array).size() == 8
		and header_title != null and header_title.text == "Chest",
		"opening a chest adds the labelled Chest drawer under the inventory")
	check(header_icon != null and header_icon.texture == chest_data.icon,
		"the Chest drawer shows the chest item icon")
	check(trash_row != null and trash_row.alignment == BoxContainer.ALIGNMENT_END,
		"the delete control is aligned to the inventory's bottom-right")
	check(inv_body != null
		and inv_body.size_flags_vertical == Control.SIZE_SHRINK_BEGIN,
		"the player grid moves up when the chest drawer is open")

	# A plain click/tap only selects/inspects; it must not take the stack.
	var chest_slot_0: Control = (ui.get("_chest_slots") as Array)[0] as Control
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	chest_slot_0.call("_gui_input", press)
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.pressed = false
	chest_slot_0.call("_gui_input", release)
	check(chest_slots[0] is Dictionary
		and int((chest_slots[0] as Dictionary)["quantity"]) == 12
		and Global.Inventory[1] == null,
		"clicking a chest slot does not auto-transfer its stack")

	var preview: Control = chest_slot_0.call("_make_drag_preview", chest_slots[0]) as Control
	var preview_has_icon := false
	var preview_qty := ""
	if preview != null:
		for child in preview.get_children():
			if child is TextureRect and (child as TextureRect).texture != null:
				preview_has_icon = true
			elif child is Label:
				preview_qty = (child as Label).text
	check(preview != null and preview_has_icon and preview_qty == "12",
		"chest drag preview shows the item icon and stack count")
	if preview != null:
		preview.queue_free()

	var payload0: Variant = chest.call("make_drag_data", 0, true)
	check(payload0 is Dictionary
		and not bool(chest.call("can_accept_drop", 99, false, payload0))
		and not bool(chest.call("can_accept_drop", 0, true, payload0)),
		"chest drops reject out-of-range targets and the source slot")
	chest.call("accept_drop", 99, false, payload0)
	check(chest_slots[0] is Dictionary
		and int((chest_slots[0] as Dictionary)["quantity"]) == 12,
		"an invalid/cancelled chest drop leaves the source stack intact")

	# Chest -> player drag.
	var chest_payload: Variant = chest.call("make_drag_data", 0, true)
	var player_slot: Control = (ui.get("_slots") as Array)[1] as Control
	player_slot.call("_drop_data", Vector2.ZERO, chest_payload)
	var inv_one: Variant = Global.Inventory[1]
	check(inv_one is Dictionary and (inv_one as Dictionary)["data"] == wood
		and chest_slots[0] == null,
		"dragging a chest stack into the player grid moves it out of the chest")

	# Player -> chest drag.
	var inv_payload := {"from_index": 1, "item": Global.Inventory[1], "source": "inventory"}
	var chest_slot: Control = (ui.get("_chest_slots") as Array)[4] as Control
	chest_slot.call("_drop_data", Vector2.ZERO, inv_payload)
	check(chest_slots[4] is Dictionary and (chest_slots[4] as Dictionary)["data"] == wood
		and Global.Inventory[1] == null,
		"dragging a player stack into the chest stores it in the chest")

	# Partial merge respects the stack limit; the remainder stays in the chest.
	var merge_slot: Control = (ui.get("_slots") as Array)[3] as Control
	Global.Inventory[3] = {"data": wood, "quantity": 30}
	chest_slots[5] = {"data": wood, "quantity": 5}
	var merge_payload: Variant = chest.call("make_drag_data", 5, true)
	merge_slot.call("_drop_data", Vector2.ZERO, merge_payload)
	check(Global.Inventory[3] is Dictionary
		and int((Global.Inventory[3] as Dictionary)["quantity"]) == 32
		and chest_slots[5] is Dictionary
		and int((chest_slots[5] as Dictionary)["quantity"]) == 3,
		"chest-to-inventory merge caps at the stack limit and leaves the remainder")

	# A full matching stack rejects the move without deleting anything.
	var full_slot: Control = (ui.get("_slots") as Array)[4] as Control
	Global.Inventory[4] = {"data": wood, "quantity": 32}
	chest_slots[6] = {"data": wood, "quantity": 4}
	var full_payload: Variant = chest.call("make_drag_data", 6, true)
	full_slot.call("_drop_data", Vector2.ZERO, full_payload)
	check(Global.Inventory[4] is Dictionary
		and int((Global.Inventory[4] as Dictionary)["quantity"]) == 32
		and chest_slots[6] is Dictionary
		and int((chest_slots[6] as Dictionary)["quantity"]) == 4,
		"a full matching inventory stack leaves the chest stack untouched")

	# Different items swap, matching the normal inventory occupied-slot rule.
	var stone: ItemData = load("res://resources/items/stone.tres")
	var swap_slot: Control = (ui.get("_slots") as Array)[5] as Control
	Global.Inventory[5] = {"data": stone, "quantity": 2}
	chest_slots[7] = {"data": wood, "quantity": 3}
	var swap_payload: Variant = chest.call("make_drag_data", 7, true)
	swap_slot.call("_drop_data", Vector2.ZERO, swap_payload)
	check(Global.Inventory[5] is Dictionary
		and (Global.Inventory[5] as Dictionary)["data"] == wood
		and chest_slots[7] is Dictionary
		and (chest_slots[7] as Dictionary)["data"] == stone,
		"dropping a chest stack on an occupied slot swaps without losing items")

	# Trash receives chest-origin drags too (not Global.Inventory[from_index]).
	chest_slots[2] = {"data": wood, "quantity": 2}
	var trash: Control = ui.get("_trash") as Control
	trash.call("_drop_data", Vector2.ZERO,
		{"from_index": 2, "item": chest_slots[2], "source": "chest"})
	check(chest_slots[2] == null,
		"dragging a chest stack to delete removes it from the chest")

	ui.call("detach_chest")
	check(inv_body.size_flags_vertical == Control.SIZE_EXPAND_FILL,
		"closing the chest restores the normal inventory layout")
	Global.unregister_ui_back(ui)
	layer.visible = false
	layer.queue_free()
	chest.queue_free()
	player_stub.queue_free()
	await get_tree().process_frame
	Global.player_node = old_player if is_instance_valid(old_player) else null
	Global.Inventory = old_inventory
	Global.Inventory_updated.emit()


func _test_cloud_save_identity() -> void:
	var uid_a := "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
	var uid_b := "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
	var meta: Dictionary = {"world_uid": uid_a, "revision": 4, "checksum": "sum4"}
	check(CloudSync.classify_sync(uid_a, 3, "sum3", {}) == "upload",
		"a new cloud slot is uploadable")
	check(CloudSync.classify_sync(uid_a, 4, "sum4", meta) == "synced",
		"identical cloud save checksum is already synced")
	check(CloudSync.classify_sync(uid_b, 4, "other", meta) == "pending",
		"a different world in the same slot is a conflict")
	check(CloudSync.classify_sync(uid_a, 5, "sum5", meta) == "upload",
		"a strictly newer local revision uploads")
	check(CloudSync.classify_sync(uid_a, 3, "sum3", meta) == "pending",
		"an older local revision never overwrites the cloud")
	check(CloudSync.classify_sync(uid_a, 4, "sumX", meta) == "pending",
		"equal revisions with different bytes are an independent-edit conflict")
	check(CloudSync.classify_sync(uid_a, 1, "sum1",
		{"world_uid": "", "revision": 0, "checksum": "sum0"}) == "pending",
		"legacy cloud metadata is not auto-overwritten")

func _test_android_config() -> void:
	var presets := FileAccess.get_file_as_string("res://export_presets.cfg")
	var project_version := str(ProjectSettings.get_setting("application/config/version", ""))
	check(presets.contains('package/unique_name="com.sandee.alpha"')
		and not project_version.is_empty()
		and presets.contains('version/name="%s"' % project_version)
		and presets.contains("architectures/arm64-v8a=true")
		and presets.contains("permissions/internet=true"),
		"Android release preset has a stable package id, version and INTERNET")
	check(presets.contains('name="Android Emulator"')
		and presets.contains("architectures/x86_64=true"),
		"Android emulator preset is available for x86_64 testing")
	check(bool(ProjectSettings.get_setting(
		"input_devices/pointing/emulate_mouse_from_touch", true)),
		"Android first-touch mouse emulation stays enabled for UI controls")
	check(str(ProjectSettings.get_setting(
		"rendering/renderer/rendering_method.mobile", "")) == "gl_compatibility",
		"Android uses the GLES3 compatibility renderer")
	check(str(ProjectSettings.get_setting(
		"display/window/stretch/mode.mobile", "")) == "canvas_items",
		"Android uses responsive canvas scaling for phone/tablet screens")
	check(not bool(ProjectSettings.get_setting(
		"application/config/quit_on_go_back", true)),
		"Android Back does not quit without giving the player a pause menu")
	var manifest := FileAccess.get_file_as_string("res://android/build/src/main/AndroidManifest.xml")
	check(presets.contains("user_data_backup/allow=false")
		and presets.contains("package/retain_data_on_uninstall=false")
		and manifest.contains('android:allowBackup="false"'),
		"Android backup/retain-data are disabled so a reinstall starts signed out")

func _test_android_input_and_safe_area() -> void:
	Global.reset_pause_state()
	var old_player: Node = Global.player_node
	var old_move: Vector2 = Global.mobile_move
	var old_shift: bool = Global.mobile_shift
	var old_pnc: bool = Global.pnc_hold_active
	var old_size: Vector2 = Global.ui_viewport_size
	var old_insets: Vector4 = Global.ui_safe_insets
	var old_scale: float = Global.ui_scale

	# Opening any modal/pause must cancel the tap-to-control order and held
	# touch input via the same path used by Global.open_ui().
	var probe := CancelProbe.new()
	add_child(probe)
	Global.player_node = probe
	Global.mobile_move = Vector2.RIGHT
	Global.mobile_shift = true
	Global.pnc_hold_active = true
	var cancelled_events: Array = []
	var on_cancel := func() -> void: cancelled_events.append(true)
	Global.gameplay_input_cancelled.connect(on_cancel)
	Global.cancel_gameplay_input()
	check(probe.cancelled == 1 and cancelled_events.size() == 1
		and Global.mobile_move == Vector2.ZERO and not Global.mobile_shift
		and not Global.pnc_hold_active,
		"opening an interface cancels PNC, held touch movement and sprint")
	Global.gameplay_input_cancelled.disconnect(on_cancel)
	probe.queue_free()
	Global.player_node = old_player if is_instance_valid(old_player) else null
	Global.mobile_move = old_move
	Global.mobile_shift = old_shift
	Global.pnc_hold_active = old_pnc

	# UI hit-testing must use the event's own viewport position. Android's
	# secondary-touch bridge and emulated first touch can deliver a click away
	# from the current OS cursor; using the cursor let UI taps leak into world
	# mining/attacking.
	var hit_probe := Control.new()
	hit_probe.position = Vector2(2, 2)
	hit_probe.size = Vector2(8, 8)
	hit_probe.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(hit_probe)
	await get_tree().process_frame
	var inside := InputEventMouseButton.new()
	inside.button_index = MOUSE_BUTTON_LEFT
	inside.pressed = true
	inside.position = Vector2(5, 5)
	var outside := InputEventMouseButton.new()
	outside.button_index = MOUSE_BUTTON_LEFT
	outside.pressed = true
	outside.position = Vector2(40, 40)
	check(Global.is_mouse_event_over_ui(inside)
		and not Global.is_mouse_event_over_ui(outside),
		"mouse/UI hit-testing follows the event position, not a stale cursor")
	hit_probe.queue_free()
	await get_tree().process_frame

	# UI hit-testing must only walk UI roots. The overworld has ~40k world
	# nodes; scanning them from the Viewport used to cost ~35 ms per call.
	var ui_layer := CanvasLayer.new()
	ui_layer.visible = false
	var ui_control := Control.new()
	ui_control.position = Vector2(200, 200)
	ui_control.size = Vector2(40, 40)
	ui_control.mouse_filter = Control.MOUSE_FILTER_STOP
	ui_layer.add_child(ui_control)
	add_child(ui_layer)
	await get_tree().process_frame
	check(not Global.is_point_over_ui(Vector2(210, 210)),
		"a hidden UI layer never blocks world input")
	ui_layer.visible = true
	check(Global.is_point_over_ui(Vector2(210, 210)),
		"a runtime-added CanvasLayer joins the UI hit-test roots")
	ui_control.mouse_filter = Control.MOUSE_FILTER_IGNORE
	check(not Global.is_point_over_ui(Vector2(210, 210)),
		"mouse-ignore controls do not block world input")
	ui_layer.queue_free()
	await get_tree().process_frame
	check(not Global.is_point_over_ui(Vector2(210, 210)),
		"freed UI roots are pruned from the hit-test cache")

	var roots_before: int = (Global.get("_ui_roots") as Array).size()
	var world_probe := Node2D.new()
	for i in range(100):
		world_probe.add_child(Node2D.new())
	add_child(world_probe)
	await get_tree().process_frame
	check((Global.get("_ui_roots") as Array).size() == roots_before,
		"non-UI world nodes never enter the UI hit-test cache")
	world_probe.queue_free()

	# Safe-area helper: all four insets become full-rect offsets, and content
	# rect math matches them. This is what centres modal/scrolled panels away
	# from a notch or system bar.
	Global.ui_viewport_size = Vector2(1152, 648)
	Global.ui_safe_insets = Vector4(80, 24, 40, 32)
	var safe_probe := Control.new()
	safe_probe.set_anchors_preset(Control.PRESET_FULL_RECT)
	Global.apply_safe_area(safe_probe)
	var content := Global.ui_content_rect()
	check(is_equal_approx(safe_probe.offset_left, 80.0)
		and is_equal_approx(safe_probe.offset_top, 24.0)
		and is_equal_approx(safe_probe.offset_right, -40.0)
		and is_equal_approx(safe_probe.offset_bottom, -32.0)
		and is_equal_approx(content.size.x, 1032.0)
		and is_equal_approx(content.size.y, 592.0),
		"safe-area helper maps notches/system bars into full-rect offsets")
	safe_probe.free()

	Global.ui_viewport_size = old_size
	Global.ui_safe_insets = old_insets
	Global.ui_scale = old_scale

	# Control-scheme state must not depend on the workstation's saved settings
	# (a developer with auto-sprint on must still run the same matrix).
	var old_pnc_scheme: bool = Global.point_and_click
	var old_auto_sprint: bool = Global.point_and_click_auto_sprint
	Global.point_and_click = false
	Global.point_and_click_auto_sprint = false

	# Touch-ID bridge: primary touch remains Godot-emulated; secondary touches
	# are explicitly tracked and released on modal open. Hide the HUD root so
	# this test exercises state without relying on the tiny headless viewport
	# for control coordinates.
	var mobile: Node = load("res://scripts/mobile_ui.gd").new()
	add_child(mobile)
	await get_tree().process_frame
	mobile.call("_set_controls_enabled", true)
	var build_btn: Button = mobile.get("_btn_build") as Button
	var interact_btn: Button = mobile.get("_btn_interact") as Button
	var sprint_btn: Button = mobile.get("_btn_shift") as Button
	var stick: Control = mobile.get("_stick") as Control
	# Approved circular action cluster: INTERACT is the large bottom-right
	# circle, SPRINT sits left of it, and BUILD sits above INTERACT.
	check(build_btn != null and interact_btn != null and sprint_btn != null
		and interact_btn.size.x > sprint_btn.size.x
		and interact_btn.position.x > sprint_btn.position.x
		and is_equal_approx(interact_btn.position.y + interact_btn.size.y * 0.5,
			sprint_btn.position.y + sprint_btn.size.y * 0.5)
		and is_equal_approx(build_btn.position.x + build_btn.size.x * 0.5,
			interact_btn.position.x + interact_btn.size.x * 0.5)
		and build_btn.position.y < interact_btn.position.y,
		"Android action buttons use the circular INTERACT/SPRINT/BUILD layout")
	var action_hits := true
	for key in ["_btn_build", "_btn_shift", "_btn_interact"]:
		var action := mobile.get(key) as Control
		if action == null or not Global.is_point_over_ui(
				action.get_global_rect().get_center()):
			action_hits = false
	check(action_hits,
		"Android BUILD/SPRINT/INTERACT are recognised as UI hit targets")
	# The explicit HUD registry must work even if the generic CanvasLayer root
	# cache has not picked up MobileUI yet (the original leak path).
	var roots: Array = Global.get("_ui_roots")
	var mobile_root_index: int = roots.find(mobile)
	if mobile_root_index >= 0:
		roots.remove_at(mobile_root_index)
	var explicit_mobile_hit := Global.is_point_over_ui(
		build_btn.get_global_rect().get_center())
	if mobile_root_index >= 0:
		roots.insert(mobile_root_index, mobile)
	check(explicit_mobile_hit and Global.is_point_over_mobile_hud(
		build_btn.get_global_rect().get_center()),
		"explicit mobile HUD registry catches action-button touches")
	Global.guard_mobile_ui_touch()
	var world_press := InputEventMouseButton.new()
	world_press.button_index = MOUSE_BUTTON_LEFT
	world_press.pressed = true
	world_press.position = Vector2(9999, 9999)
	check(Global.is_mouse_event_over_ui(world_press),
		"a UI touch briefly suppresses a mismapped world mouse press")
	Global.set("_mobile_ui_touch_guard_until_ms", 0)
	var tagged_press := InputEventMouseButton.new()
	tagged_press.button_index = MOUSE_BUTTON_LEFT
	tagged_press.pressed = true
	tagged_press.position = Vector2(9999, 9999)
	tagged_press.set_meta("mobile_ui_touch", true)
	check(Global.is_mouse_event_over_ui(tagged_press),
		"secondary UI bridge presses are always treated as UI")

	# A: PnC off, auto-sprint off — stick visible, BUILD right, SPRINT shown.
	var metrics: Dictionary = mobile.call("_layout_metrics", Global.ui_scale)
	var left_pad: float = metrics["left_pad"]
	var right_pad: float = metrics["right_pad"]
	var vp_width: float = (metrics["vp"] as Vector2).x
	var interact_size: float = metrics["interact_size"]
	var stick_size: float = metrics["stick_size"]
	var right_build_center: float = vp_width - right_pad - interact_size * 0.5
	var left_build_center: float = left_pad + stick_size * 0.5
	check(stick != null and stick.visible and build_btn.visible
		and sprint_btn.visible
		and absf(build_btn.get_global_rect().get_center().x
			- right_build_center) < 1.0,
		"Android A: joystick on, BUILD right, SPRINT visible")
	# B: PnC off, auto-sprint on — stick visible, BUILD right, SPRINT hidden.
	Global.point_and_click_auto_sprint = true
	mobile.call("_set_controls_enabled", true)
	check(stick.visible and build_btn.visible and not sprint_btn.visible
		and absf(build_btn.get_global_rect().get_center().x
			- right_build_center) < 1.0,
		"Android B: auto-sprint hides SPRINT and keeps BUILD right")
	# C: PnC on, auto-sprint off — stick hidden, BUILD takes the left slot,
	# SPRINT shown again.
	Global.point_and_click = true
	Global.point_and_click_auto_sprint = false
	mobile.call("_set_controls_enabled", true)
	check(not stick.visible and build_btn.visible and sprint_btn.visible
		and absf(build_btn.get_global_rect().get_center().x
			- left_build_center) < 1.0,
		"Android C: point-and-click hides the stick and moves BUILD left")
	# D: PnC on, auto-sprint on — stick and SPRINT hidden, BUILD still left.
	Global.point_and_click_auto_sprint = true
	mobile.call("_set_controls_enabled", true)
	check(not stick.visible and build_btn.visible and not sprint_btn.visible
		and absf(build_btn.get_global_rect().get_center().x
			- left_build_center) < 1.0,
		"Android D: PnC + auto-sprint hide stick and SPRINT")
	# Returning to manual joystick control restores the stick immediately.
	Global.point_and_click = false
	Global.point_and_click_auto_sprint = false
	mobile.call("_set_controls_enabled", true)
	check(stick.visible and sprint_btn.visible,
		"Android shows the joystick and SPRINT again in manual mode")
	Global.point_and_click = old_pnc_scheme
	Global.point_and_click_auto_sprint = old_auto_sprint
	mobile.call("_set_controls_enabled", true)
	var mobile_root: Control = mobile.get("_root") as Control
	if mobile_root != null:
		mobile_root.visible = false
	var primary := InputEventScreenTouch.new()
	primary.index = 11
	primary.position = Vector2(30, 30)
	primary.pressed = true
	mobile.call("_input", primary)
	check(int(mobile.get("_primary_touch")) == 11
		and (mobile.get("_bridged_touches") as Dictionary).is_empty(),
		"mobile primary touch stays in the normal emulated-mouse path")
	var secondary := InputEventScreenTouch.new()
	secondary.index = 12
	secondary.position = Vector2(45, 30)
	secondary.pressed = true
	mobile.call("_input", secondary)
	check((mobile.get("_bridged_touches") as Dictionary).has(12),
		"mobile secondary touch is tracked and bridged as one gesture")
	var secondary_up := InputEventScreenTouch.new()
	secondary_up.index = 12
	secondary_up.position = Vector2(45, 30)
	secondary_up.pressed = false
	mobile.call("_input", secondary_up)
	check((mobile.get("_bridged_touches") as Dictionary).is_empty(),
		"mobile secondary touch release releases exactly its tracked gesture")
	# Opening a modal resets all gesture state, including a still-down primary.
	Global.open_ui()
	var modal_touch := InputEventScreenTouch.new()
	modal_touch.index = 13
	modal_touch.position = Vector2(30, 30)
	modal_touch.pressed = true
	mobile.call("_input", modal_touch)
	check(int(mobile.get("_primary_touch")) == -1
		and (mobile.get("_bridged_touches") as Dictionary).is_empty(),
		"mobile touch bridge is disabled/reset while a modal owns the screen")
	Global.close_ui()
	Global.reset_pause_state()

	# A secondary-finger hotbar tap must switch the held slot directly. It must
	# never become a synthetic mouse press (the joystick's active mouse focus can
	# swallow it) and must not clear the primary joystick touch.
	var old_selected: int = Global.hotbar_selected
	var old_move_for_hotbar: Vector2 = Global.mobile_move
	var hotbar_probe := TextureRect.new()
	hotbar_probe.set_script(load("res://scripts/hotbar_slot.gd"))
	hotbar_probe.position = Vector2(320, 220)
	hotbar_probe.size = Vector2(56, 56)
	hotbar_probe.mouse_filter = Control.MOUSE_FILTER_STOP
	hotbar_probe.add_to_group("hotbar_slot")
	hotbar_probe.set("slot_index", 3)
	add_child(hotbar_probe)
	await get_tree().process_frame
	Global.mobile_move = Vector2(0.8, 0.1)
	primary = InputEventScreenTouch.new()
	primary.index = 21
	primary.position = Vector2(20, 20)
	primary.pressed = true
	mobile.call("_input", primary)
	secondary = InputEventScreenTouch.new()
	secondary.index = 22
	secondary.position = hotbar_probe.get_global_rect().get_center()
	secondary.pressed = true
	mobile.call("_input", secondary)
	check(Global.hotbar_selected == 3
		and Global.mobile_move == Vector2(0.8, 0.1)
		and int(mobile.get("_primary_touch")) == 21
		and (mobile.get("_bridged_touches") as Dictionary).is_empty(),
		"secondary hotbar taps switch items without stopping joystick movement")
	var bridge_release := InputEventMouseButton.new()
	bridge_release.button_index = MOUSE_BUTTON_LEFT
	bridge_release.pressed = false
	bridge_release.set_meta("mobile_touch_bridge", true)
	stick.set("_touch_id", 0)
	stick.call("_gui_input", bridge_release)
	check(int(stick.get("_touch_id")) == 0,
		"joystick ignores synthetic secondary-touch bridge releases")
	stick.call("reset_stick")
	secondary_up = InputEventScreenTouch.new()
	secondary_up.index = 22
	secondary_up.position = hotbar_probe.get_global_rect().get_center()
	secondary_up.pressed = false
	mobile.call("_input", secondary_up)
	primary = InputEventScreenTouch.new()
	primary.index = 21
	primary.position = Vector2(20, 20)
	primary.pressed = false
	mobile.call("_input", primary)
	hotbar_probe.queue_free()
	Global.hotbar_selected = old_selected
	Global.mobile_move = old_move_for_hotbar
	Global.hotbar_selection_changed.emit(Global.hotbar_selected)
	mobile.queue_free()
	await get_tree().process_frame
	Global.reset_pause_state()


# Android touch play has no tooltip popups. Verify both the floating item
# tooltip and the tap-tooltip node are suppressed while desktop hover still
# creates the normal item tooltip.
func _test_pc_controls_overlay() -> void:
	Global.reset_pause_state()
	get_viewport().gui_release_focus()
	var old_scale: float = Global.ui_scale
	var old_insets: Vector4 = Global.ui_safe_insets
	var old_pnc: bool = Global.point_and_click
	var old_dead: bool = Global.player_is_dead
	Global.ui_scale = 1.25
	Global.ui_safe_insets = Vector4.ZERO
	Global.point_and_click = false
	Global.player_is_dead = false

	var sv := SubViewport.new()
	sv.size = Vector2i(1152, 648)
	sv.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(sv)
	var overlay: Node = load("res://scripts/controls_overlay.gd").new()
	sv.add_child(overlay)
	await get_tree().process_frame
	await get_tree().process_frame
	check(bool(overlay.call("is_open")) and overlay.visible,
		"PC controls guide is on by default")
	check(overlay.visible, "PC controls guide is visible when the world starts")

	overlay.call("set_open", true)
	await get_tree().process_frame
	await get_tree().process_frame
	var movement := overlay.get("_movement_cluster") as Control
	var action := overlay.get("_action_cluster") as Control
	check(overlay.visible and movement != null and action != null
		and movement.position.x < float(sv.size.x) * 0.5
		and action.position.x > float(sv.size.x) * 0.5
		and movement.position.y > float(sv.size.y) * 0.6
		and action.position.y > float(sv.size.y) * 0.6
		and movement.position.x + movement.size.x < action.position.x,
		"PC controls cluster along the bottom left/right, clear of the hotbar")
	check(movement.size.x <= 240.0 and action.size.x <= 360.0
		and movement.size.y <= 180.0 and action.size.y <= 200.0,
		"the bottom control clusters are compact and panel-free")
	var off_labels := _overlay_chip_labels(overlay)
	check(off_labels.has("USE") and off_labels.has("BUILD"),
		"the standard action cluster shows a contextual LMB chip and build")
	var lmb_label := overlay.get("_lmb_label") as Label
	var lmb_shift := overlay.get("_lmb_shift_cap") as Control
	var lmb_sep := overlay.get("_lmb_sep") as Control
	check(lmb_label != null and lmb_label.text == "USE"
		and lmb_shift != null and not lmb_shift.visible,
		"one merged LMB chip starts with the contextual USE label")
	var lmb_caps := 0
	for entry in (overlay.get("_caps") as Array):
		var spec: Dictionary = entry.get("spec", {}) as Dictionary
		if int(spec.get("mouse", -1)) == MOUSE_BUTTON_LEFT:
			lmb_caps += 1
	check(lmb_caps == 1, "similar LMB actions share one keycap")
	overlay.call("_apply_context", "CHASE", false)
	check(lmb_label.text == "CHASE", "the LMB label follows an enemy hover")
	overlay.call("_apply_context", "DESTROY", true)
	check(lmb_label.text == "DESTROY" and lmb_shift.visible and lmb_sep.visible,
		"Shift attaches to the same LMB chip for destroy")
	overlay.call("_apply_context", "USE", false)
	check(lmb_label.text == "USE" and not lmb_shift.visible,
		"the merged LMB chip returns to its plain context")

	var move_cap: Control = null
	var move_code: int = 0
	for entry in (overlay.get("_caps") as Array):
		var spec: Dictionary = entry.get("spec", {}) as Dictionary
		for binding in spec.get("bindings", []):
			var code: int = int((binding as Dictionary).get("physical", 0))
			if code != 0 and code != KEY_SHIFT:
				move_cap = entry.get("cap") as Control
				move_code = code
				break
		if move_cap != null:
			break
	var key_down := InputEventKey.new()
	key_down.physical_keycode = move_code
	key_down.keycode = move_code
	key_down.pressed = true
	Input.parse_input_event(key_down)
	Input.flush_buffered_events()
	await get_tree().process_frame
	overlay.call("_update_caps")
	check(move_cap != null and bool(move_cap.get("pressed")),
		"holding a movement key highlights its floating keycap")
	overlay.notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	overlay.call("_update_caps")
	check(move_cap != null and not bool(move_cap.get("pressed")),
		"window focus loss clears a held key highlight")
	overlay.notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)
	var key_up := InputEventKey.new()
	key_up.physical_keycode = move_code
	key_up.keycode = move_code
	key_up.pressed = false
	Input.parse_input_event(key_up)
	Input.flush_buffered_events()
	await get_tree().process_frame
	overlay.call("_update_caps")
	check(move_cap != null and not bool(move_cap.get("pressed")),
		"releasing a movement key clears the floating highlight")

	var ctrl_cap: Control = _overlay_cap_with_physical(overlay, KEY_CTRL)
	var ctrl_down := InputEventKey.new()
	ctrl_down.physical_keycode = KEY_CTRL
	ctrl_down.keycode = KEY_CTRL
	ctrl_down.pressed = true
	Input.parse_input_event(ctrl_down)
	Input.flush_buffered_events()
	await get_tree().process_frame
	overlay.call("_update_caps")
	check(ctrl_cap != null and bool(ctrl_cap.get("pressed")),
		"pressing the build key highlights the action keycap")
	var ctrl_up := InputEventKey.new()
	ctrl_up.physical_keycode = KEY_CTRL
	ctrl_up.keycode = KEY_CTRL
	ctrl_up.pressed = false
	Input.parse_input_event(ctrl_up)
	Input.flush_buffered_events()
	await get_tree().process_frame
	overlay.call("_update_caps")
	check(ctrl_cap != null and not bool(ctrl_cap.get("pressed")),
		"releasing the build key clears the action highlight")

	Global.point_and_click = true
	overlay.call("_rebuild")
	await get_tree().process_frame
	await get_tree().process_frame
	var on_labels := _overlay_chip_labels(overlay)
	check(on_labels.has("MOVE") and on_labels.has("BUILD"),
		"switching point-and-click on rebuilds the LMB chip for click movement")
	var on_movement := overlay.get("_movement_cluster") as Control
	check(on_movement != null and on_movement.get_child_count() <= 2,
		"point-and-click mode hides the WASD overlay and keeps only Shift")
	Global.point_and_click = old_pnc

	overlay.call("set_open", false)
	var f1 := InputEventKey.new()
	f1.physical_keycode = KEY_F1
	f1.keycode = KEY_F1
	f1.pressed = true
	overlay.call("_input", f1)
	check(bool(overlay.call("is_open")) and overlay.visible,
		"F1 opens the PC controls overlay")
	overlay.call("set_open", false)
	check(not bool(overlay.call("is_open")) and not overlay.visible,
		"toggling F1 again hides the PC controls overlay")

	var game_src := FileAccess.get_file_as_string("res://scenes/game_instance.gd")
	var help_src := FileAccess.get_file_as_string("res://scripts/help_panel.gd")
	check(game_src.contains("CONTROLS_OVERLAY_SCRIPT")
		and game_src.contains("if not Global.is_mobile():")
		and game_src.contains("set_hud_suppressed"),
		"Game creates the PC overlay only on desktop and suppresses it with the HUD")
	check(help_src.contains("on-screen control hints"),
		"Help & Documentation advertises the F1 overlay")

	sv.queue_free()
	await get_tree().process_frame
	Global.ui_scale = old_scale
	Global.ui_safe_insets = old_insets
	Global.point_and_click = old_pnc
	Global.player_is_dead = old_dead
	Global.reset_pause_state()


func _overlay_chip_labels(overlay: Node) -> PackedStringArray:
	var labels := PackedStringArray()
	for entry in (overlay.get("_chips") as Array):
		var lbl := entry.get("label") as Label
		if lbl != null and is_instance_valid(lbl) and not lbl.text.is_empty():
			labels.append(lbl.text)
	return labels


func _overlay_cap_with_physical(overlay: Node, code: int) -> Control:
	for entry in (overlay.get("_caps") as Array):
		var spec: Dictionary = entry.get("spec", {}) as Dictionary
		for binding in spec.get("bindings", []):
			if int((binding as Dictionary).get("physical", 0)) == code:
				return entry.get("cap") as Control
	return null


func _test_settings_tour() -> void:
	var guide_src := FileAccess.get_file_as_string("res://scripts/tutorial_guide.gd")
	var tour_src := FileAccess.get_file_as_string("res://scripts/settings_tour.gd")
	check(guide_src.contains("SETTINGS_TOUR_SCRIPT")
		and guide_src.contains("settings_tour_done")
		and tour_src.contains("tutorial_show_category")
		and tour_src.contains("set_target"),
		"the tutorial starts a settings tour after onboarding")
	check(tour_src.contains("NEXT") and tour_src.contains("SKIP")
		and tour_src.contains("__category__")
		and tour_src.contains("__back__"),
		"the settings tour walks category, setting and back controls")

	var target: Control = load("res://scripts/tutorial_ui_target.gd").new() as Control
	add_child(target)
	var probe_btn := Button.new()
	probe_btn.text = "Probe"
	add_child(probe_btn)
	target.call("set_target", probe_btn, "No arrow", false)
	check(not bool(target.get("_show_arrow")),
		"settings highlights omit the pointing arrow")
	target.call("set_target", probe_btn, "Normal")
	check(bool(target.get("_show_arrow")),
		"normal tutorial highlights keep their arrow")
	target.queue_free()
	probe_btn.queue_free()
	await get_tree().process_frame

	var panel: Control = load("res://scripts/settings_panel.gd").new() as Control
	add_child(panel)
	await get_tree().process_frame
	await get_tree().process_frame
	panel.call("tutorial_show_category", "Audio")
	check(panel.call("tutorial_find_control", "Master Volume") != null
		and panel.call("tutorial_category_button", "Audio") != null
		and panel.call("tutorial_back_button") != null,
		"the settings panel exposes tour targets for categories and rows")
	panel.call("tutorial_show_category", "Display")
	check(panel.call("tutorial_find_control", "Camera Zoom") != null,
		"the settings tour resolves display rows")
	panel.call("tutorial_show_category", "Controls")
	check(panel.call("tutorial_find_control", "Point-and-Click Movement") != null,
		"the settings tour resolves control rows")
	panel.queue_free()
	await get_tree().process_frame

	var old_game: Node = Global.game_node
	var fake := SettingsTourGameProbe.new()
	add_child(fake)
	var pause: Control = load("res://scripts/pause_menu.gd").new() as Control
	pause.name = "PauseMenu"
	add_child(pause)
	fake.pause_menu = pause
	Global.game_node = fake
	var tour: Node = load("res://scripts/settings_tour.gd").new()
	add_child(tour)
	tour.call("start")
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	check(bool(tour.get("_active")) and bool(tour.get("_started"))
		and tour.get("_settings") != null,
		"the settings tour opens the real settings panel after onboarding")
	var focus: Control = tour.get("_focus") as Control
	check(focus != null and not bool(focus.get("_show_arrow")),
		"the active settings tour uses highlight-only targets")
	var first_progress := (tour.get("_progress") as Label).text
	tour.call("_on_next")
	await get_tree().process_frame
	await get_tree().process_frame
	check((tour.get("_progress") as Label).text != first_progress,
		"settings tour NEXT advances to another setting")
	tour.call("_finish", true)
	await get_tree().process_frame
	Global.game_node = old_game
	Global.reset_pause_state()
	pause.queue_free()
	fake.queue_free()
	await get_tree().process_frame


func _test_android_tooltip_suppression() -> void:
	var old_override: int = Global.mobile_platform_override
	var old_tip: Variant = Global.get("_item_tooltip")
	if old_tip is Node and is_instance_valid(old_tip):
		(old_tip as Node).queue_free()
	Global.set("_item_tooltip", null)
	var wood := load("res://resources/items/wood.tres") as ItemData

	Global.mobile_platform_override = 1
	Global.show_item_tooltip({"data": wood, "quantity": 1})
	check(Global.get("_item_tooltip") == null,
		"Android suppresses the floating item tooltip")
	Global.item_hold_start({"data": wood, "quantity": 1})
	check((Global.get("_hold_item") as Dictionary).is_empty(),
		"Android suppresses the press-and-hold item tooltip")
	Global.item_hold_end()
	var tap_tip: Node = load("res://scripts/tooltip_tap.gd").new()
	add_child(tap_tip)
	await get_tree().process_frame
	check(not is_instance_valid(tap_tip) or tap_tip.is_queued_for_deletion(),
		"Android removes the tap-tooltip popup node")

	Global.mobile_platform_override = 0
	Global.show_item_tooltip({"data": wood, "quantity": 1})
	var desktop_tip: Variant = Global.get("_item_tooltip")
	check(desktop_tip is Node and is_instance_valid(desktop_tip),
		"desktop still creates the normal item tooltip")
	Global.hide_item_tooltip()
	if desktop_tip is Node and is_instance_valid(desktop_tip):
		(desktop_tip as Node).queue_free()
	Global.set("_item_tooltip", null)
	Global.mobile_platform_override = old_override
	await get_tree().process_frame

func _test_android_keyboard_layout() -> void:
	# Regression: the Android keyboard is reported in physical pixels. A
	# high-DPI phone used to hand the sign-in form an inset larger than the
	# whole logical viewport, collapsing the scroll area and pushing the
	# username/password fields above the screen.
	var old_scale: float = Global.ui_scale
	var old_size: Vector2 = Global.ui_viewport_size
	var old_insets: Vector4 = Global.ui_safe_insets
	var old_override: float = Global.keyboard_height_override

	Global.ui_scale = 1.35
	Global.ui_viewport_size = Vector2(1152, 648)
	Global.ui_safe_insets = Vector4.ZERO
	Global.keyboard_height_override = 360.0

	var sub := SubViewport.new()
	sub.size = Vector2i(1152, 648)
	add_child(sub)
	var panel: Control = load("res://scripts/online_account_panel.gd").new()
	panel.call("set_dim_enabled", false)
	sub.add_child(panel)
	panel.call("open_login")
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame

	var fields: Dictionary = panel.get("_fields")
	var scroll: ScrollContainer = panel.get("_scroll") as ScrollContainer
	var panel_rect: Rect2 = (panel.get("_panel") as Control).get_global_rect()
	var scroll_rect: Rect2 = scroll.get_global_rect()
	var fields_visible: bool = fields.has("username") and fields.has("password") \
		and scroll_rect.intersects((fields["username"] as Control).get_global_rect()) \
		and scroll_rect.intersects((fields["password"] as Control).get_global_rect())
	check(scroll.size.y > 1.0 and panel_rect.position.y >= 0.0 and fields_visible,
		"Android keyboard keeps the sign-in fields inside the scrollable viewport")

	Global.keyboard_height_override = old_override
	Global.ui_scale = old_scale
	Global.ui_viewport_size = old_size
	Global.ui_safe_insets = old_insets
	panel.queue_free()
	sub.queue_free()
	await get_tree().process_frame


func _test_ambient_birds() -> void:
	var old_player: Node = Global.player_node
	var old_day: bool = Global.is_daytime
	# CharacterBody2D, not Node2D: live fish AI probes Global.player_node.get_rid().
	var probe_player := CharacterBody2D.new()
	probe_player.global_position = Vector2(400, 300)
	add_child(probe_player)
	Global.player_node = probe_player

	var birds: Node2D = load("res://scripts/ambient_birds.gd").new()
	add_child(birds)
	await get_tree().process_frame

	Global.is_daytime = true
	birds.call("_try_spawn")
	var day_kinds: Array = []
	for b in birds.get("_birds"):
		day_kinds.append(str((b as Dictionary).get("kind", "")))
	var first: AnimatedSprite2D = null
	if not (birds.get("_birds") as Array).is_empty():
		first = (birds.get("_birds")[0] as Dictionary)["node"] as AnimatedSprite2D
	var day_ok: bool = int(birds.call("bird_count")) > 0 \
		and day_kinds.has("finch") and not day_kinds.has("kite")
	var frames_ok: bool = first != null and first.sprite_frames != null \
		and first.sprite_frames.get_frame_count("fly") == 4 \
		and first.z_index == 2000

	for b in birds.get("_birds"):
		var n: Node = (b as Dictionary)["node"]
		if n != null and is_instance_valid(n):
			n.queue_free()
	(birds.get("_birds") as Array).clear()
	Global.is_daytime = false
	birds.call("_try_spawn")
	var night_kinds: Array = []
	for b in birds.get("_birds"):
		night_kinds.append(str((b as Dictionary).get("kind", "")))
	var night_ok: bool = not night_kinds.is_empty() and not night_kinds.has("finch") \
		and night_kinds.has("kite")
	check(day_ok and frames_ok and night_ok,
		"ambient birds use 4-frame wing strips and switch finch/kite by day/night")

	Global.player_node = old_player if is_instance_valid(old_player) else null
	Global.is_daytime = old_day
	birds.queue_free()
	probe_player.queue_free()
	await get_tree().process_frame


func _test_automatica_api() -> void:
	# The Lua helper preamble is the shared source of truth for the built-in
	# Automatica helpers. Run EVERY domain through Lua and ensure the Rust
	# bridge still accepts it, then cross-check the documented API surface.
	var editor_script: GDScript = load("res://scripts/lua_editor_ui.gd") as GDScript
	var preamble: String = str(editor_script.get_script_constant_map().get("LUA_PREAMBLE", ""))
	check(preamble.length() > 1000, "Automatica exposes its Lua helper preamble")

	var lua := LuaState.new()
	add_child(lua)
	var failed := [""]
	var ok := [false]
	var printed: Array = []
	lua.connect("code_failed", func(e: String) -> void: failed[0] = e)
	lua.connect("code_executed", func() -> void: ok[0] = true)
	lua.connect("signal_print", func(s: String) -> void: printed.append(s))
	lua.set("held_item", "Wood")
	lua.set("held_item_quantity", 2)
	lua.set("station_recipe", "Planks")
	lua.set("station_output_item", "Plank")
	lua.set("station_output_count", 3)
	var code: String = preamble + """
move(1, 0)
place_item()
place_item(1, 2)
place_at(0, 0)
select_block(0)
withdraw("Wood", 1)
build_line(0, 0, 3, 0)
build_rect(0, 1, 2, 2, true)
build_circle(2, false)
build_ring(2)
build_spiral(0, 0)
build_wave(3, 1)
build_stairs(2)
chop_trees(4)
auto_work()
deposit_chest()
chest_contents()
return_to_spawn()
craft_example()
attack()
drop_item(1)
mine("Stone", 4)
rename("Birdy")
input_slot(1)
put_input("Wood", 1)
set_recipe("Planks")
craft(1)
take_output()
combat_mode(false)
list_items()
print(held_item.name)
print(held_item.quantity)
print(station_recipe)
print(station_output_item)
print(station_output_count)
"""
	lua.set("code", code)
	lua.call("run_code")
	await get_tree().process_frame
	await get_tree().process_frame
	var globals_ok: bool = printed.size() >= 5 \
		and str(printed[printed.size() - 5]).strip_edges() == "Wood" \
		and str(printed[printed.size() - 4]).strip_edges() == "2" \
		and str(printed[printed.size() - 3]).strip_edges() == "Planks" \
		and str(printed[printed.size() - 2]).strip_edges() == "Plank" \
		and str(printed[printed.size() - 1]).strip_edges() == "3"
	check(ok[0] and failed[0].is_empty() and globals_ok,
		"every Automatica helper/function runs and held/station globals are readable")
	lua.queue_free()

	# Every documented Automatica name must exist in the Lua preamble or the
	# Rust bridge. This catches an API reference drifting ahead of the runtime.
	var editor_src: String = FileAccess.get_file_as_string("res://scripts/lua_editor_ui.gd")
	check(editor_src.contains('set("station_recipe"')
		and editor_src.contains('set("station_output_item"')
		and editor_src.contains('set("station_output_count"')
		and preamble.contains("__place_item"),
		"Automatica publishes station globals and supports no-offset place_item()")

	var lua_src: String = FileAccess.get_file_as_string("res://extension/src/runner/lua.rs")
	var documented: Dictionary = {}
	for e in APIReference.automatica_entries():
		var sig: String = str(e.get("sig", ""))
		for part in sig.split("/"):
			var name: String = part.strip_edges().split("(")[0].split("=")[0].strip_edges()
			if not name.is_empty():
				documented[name] = true
	var missing: Array = []
	for name in documented:
		var in_preamble: bool = preamble.contains("function %s(" % name)
		var in_rust: bool = lua_src.contains('globals.set("%s"' % name)
		if not in_preamble and not in_rust:
			missing.append(name)
	check(missing.is_empty(),
		"the Automatica reference lists only implemented helpers/functions")

	# Algorithmica station/furnace bases must expose the documented names too.
	var station_src: String = FileAccess.get_file_as_string("res://resources/godot_station_base.gd")
	var furnace_src: String = FileAccess.get_file_as_string("res://resources/godot_furnace_base.gd")
	var algo_missing: Array = []
	for e in APIReference.CUSTOM_PYTHON_STATION:
		var name: String = str(e.get("sig", "")).split("(")[0].strip_edges()
		if not station_src.contains("func %s(" % name) or not AlgorithmicaAPI.STATION_FUNCTIONS.has(name):
			algo_missing.append(name)
	for e in APIReference.CUSTOM_PYTHON_FURNACE:
		var name: String = str(e.get("sig", "")).split("(")[0].strip_edges()
		if not furnace_src.contains("func %s(" % name) or not AlgorithmicaAPI.FURNACE_FUNCTIONS.has(name):
			algo_missing.append(name)
	check(algo_missing.is_empty(),
		"the Algorithmica reference matches both Python host bases")


func _test_automatica_build_queue() -> void:
	# Build helpers emit a whole loop of place_item() calls in one Lua frame.
	# They must be serialized and consume exactly the captured build slots, not
	# race each other into placing more blocks than the robot carried.
	var old_world: Node = Global.world_node
	var fake := BuildWorldProbe.new()
	add_child(fake)
	Global.world_node = fake
	var npc: Node = load("res://scenes/objects/LuaNPC.tscn").instantiate()
	add_child(npc)
	await get_tree().process_frame
	(npc.get_node("Robot") as Node2D).position = Vector2.ZERO
	var stone: ItemData = load("res://resources/items/stone.tres")
	var wood: ItemData = load("res://resources/items/wood.tres")
	var palette: Array = npc.get("_build_palette")
	palette[0] = {"data": stone, "quantity": 1}
	palette[1] = {"data": wood, "quantity": 1}
	npc.set("_selected_slot", 0)
	npc.call("_on_lua_place_at", 10, 10)
	npc.set("_selected_slot", 1)
	npc.call("_on_lua_place_at", 11, 10)
	npc.set("_selected_slot", 0)
	npc.call("_on_lua_place_at", 12, 10)
	await get_tree().create_timer(0.8).timeout
	var cells: Array = []
	for p in fake.placed:
		cells.append((p as Dictionary)["cell"])
	check(fake.placed.size() == 2 and cells.has(Vector2i(10, 10))
		and cells.has(Vector2i(11, 10)) and not cells.has(Vector2i(12, 10))
		and palette[0] == null and palette[1] == null,
		"queued build helpers place once per block and respect the captured slot")
	Global.world_node = old_world
	npc.queue_free()
	fake.queue_free()
	await get_tree().process_frame


func _test_algorithmica_templates() -> void:
	var craft_script: GDScript = load("res://scripts/crafting_menu.gd")
	var furnace_script: GDScript = load("res://scripts/furnace_programming_panel.gd")
	var craft_consts: Dictionary = craft_script.get_script_constant_map()
	var furnace_consts: Dictionary = furnace_script.get_script_constant_map()
	var station_template: String = str(craft_consts.get("STATION_TEMPLATE", ""))
	var furnace_template: String = str(furnace_consts.get("FURNACE_TEMPLATE", ""))
	var tutorial_template: String = str(furnace_consts.get("TUTORIAL_TEMPLATE", ""))
	check(station_template.contains('set_recipe("Planks")')
		and station_template.contains("craft(1)")
		and station_template.contains("take_output()"),
		"the Algorithmica station template is a complete craft program")
	check(furnace_template.contains('feed("iron_ore"')
		and furnace_template.contains('fuel("charcoal"')
		and furnace_template.contains("smelt(5)")
		and furnace_template.contains("take_output()"),
		"the Algorithmica furnace template is a complete smelt program")
	check(tutorial_template.strip_edges() == 'print("Algorithmica ready")',
		"the tutorial starter is ready-to-run code, not a commented example")

	var craft_src := FileAccess.get_file_as_string("res://scripts/crafting_menu.gd")
	var furnace_src := FileAccess.get_file_as_string(
		"res://scripts/furnace_programming_panel.gd")
	var tutorial_src := FileAccess.get_file_as_string("res://scripts/tutorial_guide.gd")
	check(craft_src.contains('_make_action_btn("TEMPLATE"')
		and craft_src.contains("_on_load_template")
		and furnace_src.contains('template_btn.text = "TEMPLATE"')
		and furnace_src.contains("_load_template"),
		"both Algorithmica editors expose a TEMPLATE example button")
	check(tutorial_src.contains("algorithmica_template_ready")
		and furnace_src.contains("algorithmica_template_ready"),
		"the tutorial marks the furnace editor for the ready-to-run starter")

	var had_flag: bool = Global.tutorial_flags.has("algorithmica_template_ready")
	var old_flag: Variant = Global.tutorial_flags.get("algorithmica_template_ready", null)
	Global.tutorial_flags["algorithmica_template_ready"] = true
	var probe := FurnaceTemplateProbe.new()
	add_child(probe)
	var panel: Control = load("res://scripts/furnace_programming_panel.gd").new() as Control
	add_child(panel)
	await get_tree().process_frame
	panel.call("open", probe)
	await get_tree().process_frame
	check(str(panel.call("tutorial_code_text")).strip_edges()
		== 'print("Algorithmica ready")',
		"the tutorial furnace opens with ready-to-run print code")
	panel.call("_load_template")
	var loaded: String = str(panel.call("tutorial_code_text"))
	check(loaded.contains('feed("iron_ore"') and loaded.contains("smelt(5)"),
		"the furnace TEMPLATE button loads the smelting example")
	panel.call("close")
	probe.program_code = 'print("custom")'
	panel.call("open", probe)
	await get_tree().process_frame
	check(str(panel.call("tutorial_code_text")).contains('print("custom")'),
		"the tutorial starter never overwrites custom furnace code")
	panel.call("close")
	panel.queue_free()
	probe.queue_free()
	if had_flag:
		Global.tutorial_flags["algorithmica_template_ready"] = old_flag
	else:
		Global.tutorial_flags.erase("algorithmica_template_ready")
	Global.reset_pause_state()
	await get_tree().process_frame


func _test_quiz_reward_ui() -> void:
	check(QuizAltar.stars_for_penalties(0) == 3
		and QuizAltar.stars_for_penalties(1) == 2
		and QuizAltar.stars_for_penalties(2) == 1
		and QuizAltar.stars_for_penalties(3) == 0
		and QuizAltar.stars_for_penalties(9) == 0,
		"quiz penalties award 3 / 2 / 1 / 0 blue stars and never go negative")

	var mission: DungeonMissionData = null
	for m in Global.dungeon_missions.values():
		var dm := m as DungeonMissionData
		if dm != null and not dm.questions.is_empty() \
				and not Global.is_dungeon_cleared(dm.dungeon_index):
			mission = dm
			break
	if mission == null:
		check(false, "quiz mission available for reward UI test")
		return

	var altar := QuizAltar.new()
	add_child(altar)
	altar.setup(mission)
	altar.call("_start_quiz")
	await get_tree().process_frame
	check(altar.get("_hint_btn") != null,
		"quiz altar exposes a top-right hint button")

	# Compiler output is boxed in a rectangle, not bare text on the panel.
	var comp_q := DungeonQuestion.new()
	comp_q.type = DungeonQuestion.Type.COMPILER
	comp_q.language = "lua"
	comp_q.answer_output = "hint"
	var comp_questions: Array[DungeonQuestion] = [comp_q]
	altar.set("_questions", comp_questions)
	altar.set("_index", 0)
	altar.call("_show_question")
	await get_tree().process_frame
	var out := altar.get("_compiler_output") as RichTextLabel
	check(out != null and out.get_parent() is PanelContainer,
		"quiz compiler output is wrapped in a rectangle")
	var hint_code := str(altar.call("_hint_code_for", comp_q))
	check(hint_code.contains("print(") and hint_code.contains("hint"),
		"compiler hints generate a print of the expected output")

	# HINT reveals the current question without answering/advancing it; the
	# same button becomes NEXT and only NEXT dismisses the hint.
	var q1 := DungeonQuestion.new()
	q1.type = DungeonQuestion.Type.MCQ
	q1.question = "Pick A"
	q1.answer_a = "A"
	q1.answer_b = "B"
	q1.correct_index = 0
	var q2 := DungeonQuestion.new()
	q2.type = DungeonQuestion.Type.MCQ
	q2.question = "Pick C"
	q2.answer_a = "C"
	q2.answer_b = "D"
	q2.correct_index = 0
	var mc_questions: Array[DungeonQuestion] = [q1, q2]
	altar.set("_questions", mc_questions)
	altar.set("_index", 0)
	altar.set("_hints_used", 0)
	altar.set("_penalties", 0)
	altar.set("_answered", 0)
	altar.call("_show_question")
	await get_tree().process_frame
	altar.call("_on_hint_button_pressed")
	var hint_btn := altar.get("_hint_btn") as Button
	var hint_panel := altar.get("_hint_panel") as Control
	check(int(altar.get("_hints_used")) == 1
		and bool(altar.get("_hint_open")) and bool(hint_panel.visible)
		and hint_btn.text == "NEXT" and int(altar.get("_index")) == 0
		and int(altar.get("_answered")) == 0,
		"HINT reveals a hint on the same question and becomes NEXT")
	var mc_highlighted := false
	for b in (altar.get("_answer_buttons") as Array):
		if not (b is Button):
			continue
		if str((b as Button).get_meta("answer_value", "")) != str(q1.correct_option_index()):
			continue
		var hsb := (b as Button).get_theme_stylebox("normal") as StyleBoxFlat
		mc_highlighted = hsb != null and hsb.border_color == Color(1.0, 0.84, 0.30, 1.0)
	check(mc_highlighted and int(altar.get("_answered")) == 0,
		"HINT highlights the correct MCQ answer without submitting it")
	# Rapid duplicate presses are debounced and cannot create another hint event.
	altar.call("_on_hint_button_pressed")
	check(int(altar.get("_hints_used")) == 1 and bool(altar.get("_hint_open")),
		"rapid HINT presses cannot duplicate a single hint reveal")
	await get_tree().create_timer(0.3).timeout
	altar.call("_on_hint_button_pressed")
	check(not bool(altar.get("_hint_open")) and not hint_panel.visible
		and hint_btn.text == "HINT" and int(altar.get("_index")) == 0
		and int(altar.get("_answered")) == 0,
		"NEXT dismisses the hint without advancing or answering the question")
	var mc_cleared := true
	for b in (altar.get("_answer_buttons") as Array):
		if b is Button:
			var csb := (b as Button).get_theme_stylebox("normal") as StyleBoxFlat
			if csb != null and csb.border_color == Color(1.0, 0.84, 0.30, 1.0):
				mc_cleared = false
	check(mc_cleared, "NEXT clears the MCQ answer highlight")

	# The hint cycle must also preserve compiler code and allow a second reveal.
	var keep_q := DungeonQuestion.new()
	keep_q.type = DungeonQuestion.Type.COMPILER
	keep_q.language = "lua"
	keep_q.answer_output = "kept"
	var keep_questions: Array[DungeonQuestion] = [keep_q]
	altar.set("_questions", keep_questions)
	altar.set("_index", 0)
	altar.set("_hints_used", 0)
	altar.set("_hint_open", false)
	altar.call("_show_question")
	await get_tree().process_frame
	await get_tree().create_timer(0.3).timeout
	var code_entry := altar.get("_code_entry") as CodeEdit
	code_entry.text = "print(\"wrong\")"
	altar.call("_on_hint_button_pressed")
	var code_filled: bool = code_entry.text == "print(\"kept\")" \
		and str(altar.call("tutorial_code_text")) == "print(\"kept\")" \
		and not bool(altar.get("_running"))
	altar.set("_captured_output", "wrong")
	altar.call("_grade_compiler", keep_q)
	check(bool(altar.call("tutorial_hint_run_failed")),
		"a failed hinted run flags the NEXT hint step")
	await get_tree().create_timer(0.3).timeout
	altar.call("_on_hint_button_pressed")
	await get_tree().create_timer(0.3).timeout
	var code_kept: bool = code_entry.text == "print(\"kept\")"
	altar.call("_on_hint_button_pressed")
	await get_tree().create_timer(0.3).timeout
	altar.call("_on_hint_button_pressed")
	await get_tree().create_timer(0.3).timeout
	check(code_filled and code_kept and code_entry.text == "print(\"kept\")"
		and int(altar.get("_hints_used")) == 2
		and not bool(altar.get("_hint_open")),
		"Hint/Next fills and preserves compiler code without auto-running it")

	# A wrong submission records exactly one penalty per call and can drive the
	# score to zero without blocking completion.
	Global.dungeon_quiz_penalties.clear()
	altar.set("_penalties", 0)
	altar.call("_record_incorrect_submission")
	var one_penalty := int(altar.get("_penalties"))
	altar.call("_record_incorrect_submission")
	altar.call("_record_incorrect_submission")
	check(one_penalty == 1 and int(altar.get("_penalties")) == 3
		and Global.dungeon_quiz_penalties_for(mission.dungeon_index) == 3,
		"each wrong code submission records one star penalty")
	Global.dungeon_quiz_penalties.erase(mission.dungeon_index)

	# Results screen: achievements, 3-star layout and Done returns to world.
	altar.set("_answered", 2)
	altar.call("_show_reward_screen", 2)
	await get_tree().process_frame
	var scroll := altar.get("_panel_scroll") as ScrollContainer
	var reward_root := altar.get("_reward_root") as Control
	var done_found := false
	if reward_root != null:
		for child in reward_root.find_children("*", "Button", true, false):
			if (child as Button).text.contains("DONE"):
				done_found = true
	check(bool(altar.get("_reward_visible"))
		and int(altar.get("_reward_stars")) == 2
		and scroll != null and not scroll.visible and done_found,
		"quiz results screen shows achievements and a Done/return button")
	altar.call("_show_reward_screen", 0)
	await get_tree().process_frame
	check(int(altar.get("_reward_stars")) == 0,
		"a three-penalty dungeon shows zero blue stars but still reaches the reward screen")
	altar.call("_show_reward_screen", 2)
	await get_tree().process_frame

	var old_game: Node = Global.game_node
	var probe := ExitGameProbe.new()
	add_child(probe)
	Global.game_node = probe
	altar.call("_on_reward_done")
	await get_tree().process_frame
	check(probe.exit_calls == 1,
		"quiz results Done teleports back to the overworld")
	Global.game_node = old_game if is_instance_valid(old_game) else null
	probe.queue_free()
	altar.queue_free()
	await get_tree().process_frame
	Global.reset_pause_state()


func _test_altar_mobile_layout() -> void:
	var old_scale: float = Global.ui_scale
	var old_viewport: Vector2 = Global.ui_viewport_size
	var old_insets: Vector4 = Global.ui_safe_insets
	Global.ui_scale = 1.25
	Global.ui_viewport_size = Vector2(1024, 473)
	Global.ui_safe_insets = Vector4.ZERO
	ThemeDB.fallback_font_size = Global.ui_font_size(float(Global.UI_FALLBACK_FONT_BASE))

	var knowledge := KnowledgeAltar.new()
	knowledge.set("_entry", load("res://resources/entries/entry_11_lua.tres"))
	add_child(knowledge)
	knowledge.call("_build_panel")
	await get_tree().process_frame
	await get_tree().process_frame
	var kp: PanelContainer = null
	for p in knowledge.find_children("*", "PanelContainer", true, false):
		if (p as PanelContainer).size.x > 100.0:
			kp = p as PanelContainer
			break
	check(kp != null and kp.size.x <= 1025.0 and kp.size.y <= 474.0,
		"knowledge altar panel is capped to the mobile viewport")
	var body_scroll := knowledge.find_child("BodyScroll", true, false) as ScrollContainer
	check(body_scroll != null and kp != null and body_scroll.size.y < kp.size.y,
		"knowledge altar body scrolls inside the capped panel")
	if body_scroll != null:
		var body_rect: Rect2 = body_scroll.get_global_rect()
		var touch_at := Vector2(body_rect.position.x + body_rect.size.x * 0.5,
			body_rect.position.y + 10.0)
		var touch := InputEventScreenTouch.new()
		touch.index = 0
		touch.position = touch_at
		touch.pressed = true
		knowledge.call("_handle_touch_scroll", touch)
		for i in range(6):
			var drag := InputEventScreenDrag.new()
			drag.index = 0
			drag.position = touch_at + Vector2(0, -float(i + 1) * 20.0)
			drag.relative = Vector2(0, -20)
			knowledge.call("_handle_touch_scroll", drag)
		check(body_scroll.scroll_vertical > 0,
			"knowledge altar body follows a finger drag on mobile")
		touch.pressed = false
		knowledge.call("_handle_touch_scroll", touch)
	knowledge.queue_free()
	await get_tree().process_frame

	var quiz := QuizAltar.new()
	add_child(quiz)
	quiz.call("_build_panel")
	var q := DungeonQuestion.new()
	q.type = DungeonQuestion.Type.MCQ
	q.question = "A long mobile quiz question that must wrap inside the panel without widening the whole modal, followed by four long answer choices so the body needs scrolling."
	q.answer_a = "A very long multiple-choice answer that must wrap instead of widening the whole panel."
	q.answer_b = "Another long multiple-choice answer that also wraps across several lines on a phone."
	q.answer_c = "A third long multiple-choice answer so the quiz body is taller than the visible viewport."
	q.answer_d = "A fourth long multiple-choice answer to guarantee the question body scrolls."
	q.correct_index = 0
	var qs: Array[DungeonQuestion] = [q]
	quiz.set("_questions", qs)
	quiz.set("_index", 0)
	quiz.call("_rebuild_controls")
	await get_tree().process_frame
	await get_tree().process_frame
	var qp: PanelContainer = null
	for p in quiz.find_children("*", "PanelContainer", true, false):
		if (p as PanelContainer).size.x > 100.0:
			qp = p as PanelContainer
			break
	check(qp != null and qp.size.x <= 1025.0 and qp.size.y <= 474.0,
		"quiz altar panel is capped to the mobile viewport")
	var question_scroll := quiz.find_child("QuestionScroll", true, false) as ScrollContainer
	check(question_scroll != null and qp != null and question_scroll.size.y < qp.size.y,
		"quiz question and answers scroll inside the capped panel")
	var qtext := quiz.get("_q_text") as Label
	check(qtext != null and qtext.text.strip_edges() == q.question.strip_edges()
		and qtext.size.x > 100.0 and question_scroll != null
		and question_scroll.scroll_vertical == 0,
		"quiz opens showing readable question text at the top of the scroll")
	if question_scroll != null:
		var q_rect: Rect2 = question_scroll.get_global_rect()
		var q_touch_at := Vector2(q_rect.position.x + q_rect.size.x * 0.5,
			q_rect.position.y + 10.0)
		var q_touch := InputEventScreenTouch.new()
		q_touch.index = 0
		q_touch.position = q_touch_at
		q_touch.pressed = true
		quiz.call("_handle_touch_scroll", q_touch)
		for i in range(6):
			var q_drag := InputEventScreenDrag.new()
			q_drag.index = 0
			q_drag.position = q_touch_at + Vector2(0, -float(i + 1) * 20.0)
			q_drag.relative = Vector2(0, -20)
			quiz.call("_handle_touch_scroll", q_drag)
		check(question_scroll.scroll_vertical > 0,
			"quiz question body follows a finger drag on mobile")
		q_touch.pressed = false
		quiz.call("_handle_touch_scroll", q_touch)
	quiz.queue_free()
	await get_tree().process_frame

	Global.ui_scale = old_scale
	Global.ui_viewport_size = old_viewport
	Global.ui_safe_insets = old_insets
	ThemeDB.fallback_font_size = Global.ui_font_size(float(Global.UI_FALLBACK_FONT_BASE))


func _test_quiz_compiler_layout() -> void:
	var old_scale: float = Global.ui_scale
	var old_viewport: Vector2 = Global.ui_viewport_size
	var old_insets: Vector4 = Global.ui_safe_insets
	Global.ui_scale = 1.0
	Global.ui_viewport_size = Vector2(1280, 720)
	Global.ui_safe_insets = Vector4.ZERO

	var altar := QuizAltar.new()
	add_child(altar)
	altar.call("_build_panel")
	var q := DungeonQuestion.new()
	q.type = DungeonQuestion.Type.COMPILER
	q.language = "lua"
	q.answer_output = "hello"
	var compiler_questions: Array[DungeonQuestion] = [q]
	altar.set("_questions", compiler_questions)
	altar.set("_index", 0)
	altar.call("_rebuild_controls")
	await get_tree().process_frame

	var run_btn := altar.get("_run_btn") as Button
	var hint_btn := altar.get("_hint_btn") as Button
	check(run_btn != null and hint_btn != null and run_btn.visible
		and run_btn.get_parent() == hint_btn.get_parent()
		and run_btn.get_index() == hint_btn.get_index() + 1,
		"quiz Run button sits directly beside Hint in the header")

	var grid := altar.get("_compiler_grid") as GridContainer
	var code_entry := altar.get("_code_entry") as TextEdit
	var out := altar.get("_compiler_output") as RichTextLabel
	check(grid != null and grid.columns == 2 and code_entry != null and out != null
		and grid.is_ancestor_of(code_entry) and grid.is_ancestor_of(out)
		and code_entry.get_parent() != out.get_parent(),
		"wide quiz screens place code and output side by side in two columns")

	Global.ui_viewport_size = Vector2(620, 720)
	altar.call("_update_compiler_columns")
	check(grid != null and grid.columns == 1,
		"narrow quiz screens stack code above output in one column")

	var mcq := DungeonQuestion.new()
	mcq.type = DungeonQuestion.Type.MCQ
	mcq.question = "Pick one"
	mcq.answer_a = "A"
	mcq.answer_b = "B"
	mcq.correct_index = 0
	var mcq_questions: Array[DungeonQuestion] = [mcq]
	altar.set("_questions", mcq_questions)
	altar.set("_index", 0)
	altar.call("_rebuild_controls")
	await get_tree().process_frame
	check(run_btn != null and is_instance_valid(run_btn) and not run_btn.visible,
		"quiz header Run button is hidden for multiple-choice questions")

	altar.queue_free()
	await get_tree().process_frame
	Global.ui_scale = old_scale
	Global.ui_viewport_size = old_viewport
	Global.ui_safe_insets = old_insets
	ThemeDB.fallback_font_size = Global.ui_font_size(float(Global.UI_FALLBACK_FONT_BASE))


func _test_display_frame_cap() -> void:
	var panel_src := FileAccess.get_file_as_string("res://scripts/settings_panel.gd")
	var global_src := FileAccess.get_file_as_string("res://scripts/global.gd")
	var game_src := FileAccess.get_file_as_string("res://scenes/game_instance.gd")
	var old_max: int = Engine.max_fps
	Global.apply_frame_settings()
	check(Global.FRAME_CAP == 60 and Engine.max_fps == 60,
		"the game applies a fixed 60 FPS cap through Engine.max_fps")
	check(not Global.has_method("set_fps_limit") and not Global.has_method("set_show_fps"),
		"the obsolete FPS limit/display setters are removed")
	check(not panel_src.contains("FPS Limit") and not panel_src.contains("Show FPS")
		and panel_src.contains("VSync")
		and panel_src.contains("if not Global.is_mobile():"),
		"settings expose VSync only, with no FPS display/limit controls")
	check(global_src.contains("DisplayServer.VSYNC_ENABLED")
		and global_src.contains("DisplayServer.VSYNC_DISABLED")
		and global_src.contains("Engine.max_fps = FRAME_CAP"),
		"VSync remains available and cannot raise the fixed frame cap")
	check(not game_src.contains("FPS_OVERLAY")
		and not FileAccess.file_exists("res://scripts/fps_overlay.gd"),
		"the user-facing FPS overlay is removed")
	var old_vsync: bool = Global.vsync_enabled
	Global.vsync_enabled = false
	Global.apply_frame_settings()
	check(Engine.max_fps == 60, "VSync off still caps the game at 60 FPS")
	Global.vsync_enabled = old_vsync
	Global.apply_frame_settings()
	Engine.max_fps = old_max

func _test_removed_debug_surfaces() -> void:
	var game_src := FileAccess.get_file_as_string("res://scenes/game_instance.gd")
	var help_src := FileAccess.get_file_as_string("res://scripts/help_panel.gd")
	check(not FileAccess.file_exists("res://scripts/chat_console.gd")
		and not game_src.contains("CHAT_CONSOLE_SCRIPT")
		and not help_src.contains("command console")
		and not help_src.contains("/ or T"),
		"the slash-command console and its help entry are removed")
	var wire := load("res://resources/items/wire.tres") as ItemData
	check(wire != null and wire.description.length() > 20
		and wire.description.to_lower().contains("crafting station")
		and wire.description.to_lower().contains("cpu")
		and wire.description.to_lower().contains("fishing rod"),
		"wire description matches its actual crafted-component use")

func _test_ui_scaling() -> void:
	var desktop := Global.compute_ui_scale(Vector2(1920, 1080), false)
	var hd := Global.compute_ui_scale(Vector2(1280, 720), false)
	var qhd := Global.compute_ui_scale(Vector2(2560, 1440), false)
	var phone := Global.compute_ui_scale(Vector2(1152, 648), true)
	check(desktop >= 1.45 and desktop <= 1.55,
		"1080p desktop defaults to the Large UI scale")
	check(hd >= Global.UI_MIN_SCALE and hd < desktop,
		"smaller desktop windows get a smaller but still readable scale")
	check(qhd <= Global.UI_MAX_SCALE + 0.001,
		"high-resolution desktop UI is capped instead of becoming oversized")
	check(phone >= Global.UI_MOBILE_MIN_SCALE,
		"phones keep a comfortable minimum touch/readability scale")
	var ultrawide := Global.compute_ui_scale(Vector2(3440, 1440), false)
	check(is_equal_approx(ultrawide, qhd),
		"ultrawide aspect ratio does not inflate UI scale")
	check(is_equal_approx(Global.compute_ui_scale(Vector2(800, 600), false),
		Global.UI_MIN_SCALE), "tiny windows clamp to the readable minimum")

	# DisplayServer.virtual_keyboard_get_height() reports PHYSICAL pixels. On a
	# high-DPI phone the raw value can exceed the logical viewport, which used to
	# collapse keyboard-aware panels and push their text fields off-screen.
	check(is_equal_approx(Global.keyboard_height_in_viewport(900.0, 2.25, 648.0), 400.0),
		"Android keyboard height is converted from physical pixels to viewport units")
	check(is_equal_approx(Global.keyboard_height_in_viewport(2000.0, 1.0, 648.0), 647.0),
		"a bogus keyboard height is clamped inside the viewport")
	check(is_zero_approx(Global.keyboard_height_in_viewport(0.0, 2.25, 648.0)),
		"a hidden keyboard reports zero viewport height")

	# Algorithmica/quiz editors use the stricter rule: only a DOCKED keyboard
	# (activity resized via adjustResize) may move the panel. A floating keyboard
	# stays at full viewport height and must not lift the whole editor; a hidden
	# or stale height must bring it back down.
	check(is_equal_approx(Global.editor_keyboard_inset(300.0, 348.0, 648.0, true), 300.0),
		"a docked keyboard shrinks Algorithmica panels")
	check(is_zero_approx(Global.editor_keyboard_inset(300.0, 648.0, 648.0, true)),
		"a floating keyboard leaves the whole Algorithmica panel in place")
	check(is_zero_approx(Global.editor_keyboard_inset(0.0, 648.0, 648.0, true)),
		"a hidden keyboard clears the Algorithmica panel inset")
	check(is_zero_approx(Global.editor_keyboard_inset(300.0, 348.0, 648.0, false)),
		"Algorithmica panels stay put when no text field is focused")

	var old_editor_max: float = float(Global.get("_editor_viewport_max_h"))
	var kb_old_override: float = Global.keyboard_height_override
	var kb_old_viewport: Vector2 = Global.ui_viewport_size
	var focus_probe := LineEdit.new()
	add_child(focus_probe)
	focus_probe.grab_focus()
	await get_tree().process_frame
	Global.keyboard_height_override = 0.0
	Global.ui_viewport_size = Vector2(1152, 648)
	check(is_zero_approx(Global.keyboard_panel_inset()),
		"hidden keyboard leaves the live Algorithmica panel at the bottom")
	Global.keyboard_height_override = 300.0
	check(is_zero_approx(Global.keyboard_panel_inset()),
		"floating keyboard keeps the live Algorithmica panel full-screen")
	Global.ui_viewport_size = Vector2(1152, 348)
	check(is_equal_approx(Global.keyboard_panel_inset(), 300.0),
		"docked keyboard lifts the live Algorithmica panel by its covered height")
	Global.keyboard_height_override = 0.0
	Global.ui_viewport_size = Vector2(1152, 648)
	check(is_zero_approx(Global.keyboard_panel_inset()),
		"dismissing the docked keyboard drops the Algorithmica panel back down")
	Global.set("_editor_viewport_max_h", old_editor_max)
	Global.keyboard_height_override = kb_old_override
	Global.ui_viewport_size = kb_old_viewport
	focus_probe.queue_free()

	var old_size: Vector2 = Global.ui_viewport_size
	var old_insets: Vector4 = Global.ui_safe_insets
	var old_scale: float = Global.ui_scale
	Global.ui_viewport_size = Vector2(800, 600)
	Global.ui_safe_insets = Vector4.ZERO
	Global.ui_scale = Global.UI_MIN_SCALE
	var fitted: Vector2 = Global.ui_fit_min_size(Vector2(1080, 540))
	check(fitted.x <= 800.0 and fitted.y <= 600.0,
		"large modal panels are clamped inside a compact viewport")
	Global.ui_viewport_size = old_size
	Global.ui_safe_insets = old_insets
	Global.ui_scale = old_scale
	ThemeDB.fallback_font_size = Global.ui_font_size(float(Global.UI_FALLBACK_FONT_BASE))

	Global.ui_scale = 1.5
	var expected_body: int = int(round(
		float(Global.UI_TYPE_BODY) * 1.5 * Global.UI_FONT_SCALE))
	check(Global.ui_font_size(float(Global.UI_TYPE_BODY)) == expected_body
		and Global.ui_type_size(Global.UI_TYPE_BODY) == expected_body
		and expected_body > int(round(float(Global.UI_TYPE_BODY) * 1.5)),
		"font sizes track ui_scale with the readability boost at the same scale")
	ThemeDB.fallback_font_size = Global.ui_font_size(float(Global.UI_FALLBACK_FONT_BASE))
	Global.ui_scale = old_scale
	ThemeDB.fallback_font_size = Global.ui_font_size(float(Global.UI_FALLBACK_FONT_BASE))

	# The mission tracker sits under the top-right pause button. With the
	# responsive UI scale the button grew taller than the old fixed top offset,
	# so the tracker now derives its top edge from the button's real bottom.
	var old_pause_bottom: float = Global.ui_pause_bottom
	var old_tracker_viewport: Vector2 = Global.ui_viewport_size
	var old_tracker_insets: Vector4 = Global.ui_safe_insets
	var old_tracker_scale: float = Global.ui_scale
	Global.ui_scale = 1.0
	Global.ui_safe_insets = Vector4.ZERO
	Global.ui_viewport_size = Vector2(1152, 648)
	Global.ui_pause_bottom = 120.0
	var tracker: Control = load("res://scripts/mission_ui.gd").new()
	add_child(tracker)
	tracker.call("_refit")
	var tracker_panel := tracker.get("_panel") as Control
	check(tracker_panel != null and tracker_panel.position.y >= 124.0,
		"mission tracker starts below the pause button instead of overlapping it")
	tracker.free()
	Global.ui_pause_bottom = old_pause_bottom
	Global.ui_viewport_size = old_tracker_viewport
	Global.ui_safe_insets = old_tracker_insets
	Global.ui_scale = old_tracker_scale
	ThemeDB.fallback_font_size = Global.ui_font_size(float(Global.UI_FALLBACK_FONT_BASE))

	var settings_src := FileAccess.get_file_as_string("res://scripts/settings_panel.gd")
	var global_src := FileAccess.get_file_as_string("res://scripts/global.gd")
	check(not settings_src.contains("UI Scale")
		and not settings_src.contains("_on_ui_scale_preset"),
		"the obsolete user-facing UI scale control is gone")
	check(settings_src.contains("Automatic Sprint")
		and settings_src.contains("set_point_and_click_auto_sprint")
		and settings_src.contains("auto_btn.disabled = not Global.point_and_click"),
		"Controls settings expose and gate the PNC automatic-sprint option")
	check(not global_src.contains('save_data["ui_scale"]')
		and not global_src.contains('data.has("ui_scale")')
		and not global_src.contains("ui_scale_set"),
		"old per-save UI scale preferences are ignored and no longer written")
	check(global_src.contains("point_and_click_auto_sprint")
		and global_src.contains("point_and_click_auto_sprint_changed")
		and global_src.contains('"point_and_click_auto_sprint", point_and_click_auto_sprint'),
		"PNC automatic-sprint preference is loaded and saved globally")

func _test_title_panorama() -> void:
	var script: GDScript = load("res://scripts/title_panorama.gd") as GDScript
	var constants: Dictionary = script.get_script_constant_map()
	var languages: Array = constants.get("PANORAMA_LANGUAGES", []) as Array
	var cycle_min: float = float(constants.get("CYCLE_MIN_SEC", 0.0))
	var cycle_max: float = float(constants.get("CYCLE_MAX_SEC", 0.0))
	check(languages.size() == 2 and languages.has("lua") and languages.has("python")
		and cycle_min > 0.0 and cycle_max > cycle_min,
		"title panorama covers both dungeon languages and a randomized cycle interval")
	var tp: Node = script.new()
	add_child(tp)
	var lua_choices: Array = tp.call("_missions_for_language", "lua") as Array
	var py_choices: Array = tp.call("_missions_for_language", "python") as Array
	var lang_ok := true
	for idx_value in lua_choices:
		if Global.dungeon_language(int(idx_value)) != "lua":
			lang_ok = false
	for idx_value in py_choices:
		if Global.dungeon_language(int(idx_value)) != "python":
			lang_ok = false
	check(lua_choices.size() == 15 and py_choices.size() == 10 and lang_ok,
		"title panorama can pick from every ready Lua and Python dungeon")
	var panorama_src := FileAccess.get_file_as_string("res://scripts/title_panorama.gd")
	check(panorama_src.contains("DungeonWorld.new()")
		and panorama_src.contains("static var _textures")
		and panorama_src.contains("randf_range(CYCLE_MIN_SEC, CYCLE_MAX_SEC)"),
		"title panoramas are rendered from dungeons and cycle per launch")
	tp.queue_free()
	await get_tree().process_frame


func _test_interpreters() -> void:
	var lua := LuaState.new()
	add_child(lua)
	var lua_failed := [false]
	var lua_ok := [false]
	lua.connect("code_failed", func(_e: String) -> void: lua_failed[0] = true)
	lua.connect("code_executed", func() -> void: lua_ok[0] = true)
	lua.set("code", "this is not valid lua !!!")
	lua.call("run_code")
	await get_tree().process_frame
	check(lua_failed[0] or lua_ok[0], "invalid Lua does not crash")
	lua.queue_free()

	var lua2 := LuaState.new()
	add_child(lua2)
	var lua2_ok := [false]
	lua2.connect("code_executed", func() -> void: lua2_ok[0] = true)
	lua2.set("code", "print('qa')")
	lua2.call("run_code")
	await get_tree().process_frame
	check(lua2_ok[0], "valid Lua executes")
	lua2.queue_free()

	var py := PythonState.new()
	add_child(py)
	var py_ok := [false]
	py.connect("code_executed", func() -> void: py_ok[0] = true)
	py.set("code", "print('qa')")
	py.call("run_code")
	await get_tree().process_frame
	check(py_ok[0], "valid Python executes")
	py.queue_free()

	var py2 := PythonState.new()
	add_child(py2)
	var py2_failed := [false]
	py2.connect("code_failed", func(_e: String) -> void: py2_failed[0] = true)
	py2.connect("code_executed", func() -> void: pass)
	py2.set("code", "def broken(:\n    pass")
	py2.call("run_code")
	await get_tree().process_frame
	check(py2_failed[0], "invalid Python reports an error without crashing")
	py2.queue_free()

	# A generated-program runtime error must not masquerade as success.
	var py3 := PythonState.new()
	add_child(py3)
	var py3_failed := [false]
	py3.connect("code_failed", func(_e: String) -> void: py3_failed[0] = true)
	py3.connect("code_executed", func() -> void: pass)
	py3.set("code", "print(1 / 0)")
	py3.call("run_code")
	await get_tree().process_frame
	check(py3_failed[0], "Python runtime errors are reported through code_failed")
	py3.queue_free()

	# GDScript types cannot be used as variable names. Catch the collision before
	# GDScript.reload() so unsupported Python (e.g. `int = 2026`) returns an
	# ordinary compiler error instead of hitting the engine parser.
	var py4 := PythonState.new()
	add_child(py4)
	var py4_failed := [""]
	py4.connect("code_failed", func(e: String) -> void: py4_failed[0] = e)
	py4.set("code", "int = 2026")
	py4.call("run_code")
	await get_tree().process_frame
	check(py4_failed[0].contains("reserved"),
		"Python reports reserved GDScript type assignments without a parser crash")
	py4.queue_free()


func _test_crash_logger() -> void:
	var path: String = str(CrashLogger.call("get_current_log_path"))
	check(path != "" and FileAccess.file_exists(path), "crash logger has an active log file")
	CrashLogger.report("QA regression diagnostic marker")
	CrashLogger.begin_script_capture()
	push_error("QA runtime error sentinel")
	await get_tree().process_frame
	check(CrashLogger.end_script_capture(), "script errors are captured for runtime grading")
	var text := FileAccess.get_file_as_string(path)
	check(text.contains("QA regression diagnostic marker"), "manual diagnostics reach the log")
	check(text.contains("QA runtime error sentinel"), "script errors reach the log")
	check(text.contains("at ") or text.contains("SCRIPT_ERROR"), "script backtrace/log tag is present")


const PARITY_MOVE_ACTIONS: Array[String] = [
	"gameplay_left", "gameplay_right", "gameplay_up", "gameplay_down",
]


func _release_parity_moves() -> void:
	for action in PARITY_MOVE_ACTIONS:
		Input.action_release(action)


func _movement_snapshot(player: Node) -> Dictionary:
	var sprite: AnimatedSprite2D = player.get("sprite") as AnimatedSprite2D
	return {
		"dir": player.get("input_direction") as Vector2,
		"vel": player.get("velocity") as Vector2,
		"sprint": bool(player.get("_sprinting")),
		"anim": str(sprite.animation) if sprite != null else "",
	}


func _test_control_scheme_parity() -> void:
	var old_hotbar: Array = Global.Hotbar.duplicate(true)
	var old_inventory: Array = Global.Inventory.duplicate(true)
	var old_selected: int = Global.hotbar_selected
	var old_player := Global.player_node
	var old_world := Global.world_node
	var old_pnc: bool = Global.point_and_click
	var old_auto_sprint: bool = Global.point_and_click_auto_sprint
	var old_block_mode: bool = Global.block_mode
	var old_mobile_move: Vector2 = Global.mobile_move
	var old_mobile_shift: bool = Global.mobile_shift
	var old_stamina: float = Global.stamina
	var old_snowstorm: bool = Global.snowstorm_active
	var old_pause: bool = Global.pause_menu_open
	var old_pending: bool = Global.has_pending_pos
	var old_pending_pos: Vector2 = Global.pending_player_pos

	_release_parity_moves()
	Global.reset_pause_state()
	Global.Hotbar.resize(Global.HOTBAR_SIZE)
	Global.Inventory.resize(Global.INVENTORY_SIZE)
	Global.Hotbar.fill(null)
	Global.Inventory.fill(null)
	Global.Hotbar[0] = {"data": load("res://resources/items/wooden_pickaxe.tres"), "quantity": 1}
	Global.set_hotbar_selection(0)
	Global.point_and_click = false
	Global.point_and_click_auto_sprint = false
	# Enabling PNC while build mode is active must return the player to movement
	# instead of silently ignoring clicks and placing blocks.
	Global.block_mode = true
	Global.block_mode_changed.emit(true)
	Global.set_point_and_click(true, false)
	check(Global.point_and_click and not Global.block_mode,
		"enabling point-and-click leaves build mode")
	Global.block_mode = true
	Global.set_point_and_click(true, false)
	check(not Global.block_mode,
		"re-enabling an already-on point-and-click also leaves build mode")
	Global.point_and_click = false
	Global.block_mode = false
	Global.block_mode_changed.emit(false)
	Global.clear_touch_mouse()
	Global.mobile_move = Vector2.ZERO
	Global.mobile_shift = false
	Global.snowstorm_active = false
	Global.pause_menu_open = false
	Global.has_pending_pos = false
	Global.stamina = 100.0
	Global.player_node = null
	Global.world_node = null

	var player: Node = load("res://scenes/player/player.tscn").instantiate()
	add_child(player)
	await get_tree().process_frame
	await get_tree().physics_frame
	player.set_physics_process(false)
	player.set("_move_mission_done", true)
	player.global_position = Vector2(100, 100)
	player.velocity = Vector2.ZERO

	# PNC replays a mining press into the viewport. It must use viewport-local
	# coordinates: Input.parse_input_event() treats the position as WINDOW
	# coordinates, which scales it away from the block on Android's canvas_items
	# stretch (the PNC walked to the block but never mined it).
	var pnc_input := PNCInputProbe.new()
	add_child(pnc_input)
	var hold_world := Vector2(180, 140)
	player.set("_pnc_hold_pos", hold_world)
	player.set("_pnc_hold_click", true)
	Global.pnc_hold_active = true
	player.call("_pnc_hold_emit", true)
	var hold_screen: Vector2 = get_viewport().get_canvas_transform() * hold_world
	check(pnc_input.press_count == 1
		and pnc_input.last_position.is_equal_approx(hold_screen),
		"PNC synthetic hold is pushed in viewport-local coordinates")
	Global.pnc_hold_active = false
	player.set("_pnc_hold_click", false)
	pnc_input.queue_free()
	await get_tree().process_frame

	# Wolves are not click-to-attack targets: the tap becomes a move order.
	var wolf_probe := Node2D.new()
	wolf_probe.global_position = player.global_position + Vector2(60, 0)
	add_child(wolf_probe)
	wolf_probe.add_to_group("Mob")
	wolf_probe.add_to_group("Wolf")
	player.call("_pnc_handle_click", wolf_probe.global_position)
	check(bool(player.get("_pnc_active"))
		and player.get("_pnc_chase") == null
		and str(player.get("_pnc_pending")) == "",
		"clicking a wolf creates a move order, not a chase/attack order")
	player.call("_pnc_cancel")

	# Other mobs keep their original click-to-attack behavior.
	var mob_probe := Node2D.new()
	mob_probe.global_position = player.global_position + Vector2(40, 0)
	add_child(mob_probe)
	mob_probe.add_to_group("Mob")
	player.call("_pnc_handle_click", mob_probe.global_position)
	check(player.get("_pnc_chase") == mob_probe,
		"clicking a non-wolf mob still starts a chase/attack order")
	player.call("_pnc_cancel")

	# A tap on walkable ground beside a mob is a move order, not an attack.
	# Mob targeting uses the sprite bounds (with a small fallback), not a wide
	# origin radius that swallowed nearby ground taps.
	player.call("_pnc_handle_click", mob_probe.global_position + Vector2(30, 0))
	check(bool(player.get("_pnc_active"))
		and player.get("_pnc_chase") == null
		and str(player.get("_pnc_pending")) == "",
		"tapping the ground beside a mob still issues a move order")
	player.call("_pnc_cancel")

	# Sheep share Wolf/Mob groups for AI dispatch but must remain clickable.
	var sheep_probe := Node2D.new()
	sheep_probe.global_position = player.global_position + Vector2(0, -40)
	add_child(sheep_probe)
	sheep_probe.add_to_group("Mob")
	sheep_probe.add_to_group("Wolf")
	sheep_probe.add_to_group("Sheep")
	player.call("_pnc_handle_click", sheep_probe.global_position)
	check(player.get("_pnc_chase") == sheep_probe,
		"clicking a sheep still starts a chase/attack order")
	player.call("_pnc_cancel")

	# Validate the precise target box against a real mob sprite, not just the
	# fallback used by the lightweight fake probes above.
	var real_sheep: Node2D = load("res://scenes/mobs/Sheep.tscn").instantiate() as Node2D
	add_child(real_sheep)
	await get_tree().process_frame
	real_sheep.set_physics_process(false)
	real_sheep.global_position = player.global_position + Vector2(0, 120)
	var mob_rect: Rect2 = player.call("_pnc_mob_click_rect", real_sheep)
	check(mob_rect.size.x > 38.0 and mob_rect.size.y > 38.0
		and mob_rect.has_point(real_sheep.global_position + Vector2(0, -8))
		and not mob_rect.has_point(real_sheep.global_position + Vector2(30, 0)),
		"real mob taps use sprite bounds, not a wide origin radius")
	player.call("_pnc_handle_click", real_sheep.global_position + Vector2(0, -8))
	check(player.get("_pnc_chase") == real_sheep,
		"tapping a real mob sprite still starts a chase/attack order")
	player.call("_pnc_cancel")
	real_sheep.queue_free()
	await get_tree().process_frame

	# A dying mob can be freed between frames while the chase reference is
	# still stored. Steering must cancel cleanly instead of throwing on the
	# freed object (which froze/error-looped the game in play).
	var dying_probe := Node2D.new()
	dying_probe.global_position = player.global_position + Vector2(0, 40)
	add_child(dying_probe)
	dying_probe.add_to_group("Mob")
	player.call("_pnc_handle_click", dying_probe.global_position)
	check(player.get("_pnc_chase") == dying_probe,
		"a living mob becomes the PNC chase target")
	# Simulate the mob dying and being freed before the next steering frame.
	dying_probe.free()
	Global.point_and_click = true
	Global.pause_menu_open = false
	Global.block_mode = false
	Global.player_is_dead = false
	player.call("_pnc_steer", 0.016)
	check(not bool(player.get("_pnc_active")),
		"PNC cancels safely when its chase target was freed mid-combat")
	player.call("_pnc_cancel")

	wolf_probe.queue_free()
	mob_probe.queue_free()
	sheep_probe.queue_free()
	await get_tree().process_frame

	# A new PNC order must not build a grid path before checking line of sight;
	# eager pathfinding was a 2-65 ms hitch on every tap.
	player.call("_pnc_begin", player.global_position + Vector2(320, 0),
		null, "", "move")
	check(not bool(player.get("_pnc_path_attempted"))
		and (player.get("_pnc_path") as PackedVector2Array).is_empty(),
		"PNC starts direct and defers grid pathfinding until the line is blocked")
	player.call("_pnc_cancel")

	# Canopy taps still resolve through the new spatial tree buckets.
	var tree_probe := Node2D.new()
	tree_probe.global_position = player.global_position + Vector2(0, 200)
	var tree_sprite := Sprite2D.new()
	tree_sprite.name = "Sprite2D"
	tree_sprite.texture = load("res://sprites/tree/tree.png")
	tree_probe.add_child(tree_sprite)
	tree_probe.add_to_group("Tree")
	add_child(tree_probe)
	await get_tree().process_frame
	check(player.call("_pnc_tree_at",
		tree_probe.global_position + Vector2(0, -24)) == tree_probe,
		"PNC still resolves canopy taps from its spatial tree index")
	tree_probe.queue_free()
	await get_tree().process_frame

	# Interactables must be walked to their own origin, then opened directly.
	# Tapping a tall sprite used to stop at the click point outside the object's
	# real interact radius, then replay a left-click that made the player swing.
	var interact_probe := PncInteractProbe.new()
	interact_probe.global_position = player.global_position + Vector2(240, 0)
	add_child(interact_probe)
	interact_probe.add_to_group("Chest")
	await get_tree().process_frame
	Global.point_and_click = true
	Global.block_mode = false
	Global.pause_menu_open = false
	Global.player_is_dead = false
	var interact_click := interact_probe.global_position + Vector2(0, -20)
	player.call("_pnc_handle_click", interact_click)
	check(str(player.get("_pnc_pending")) == "interact"
		and player.get("_pnc_interact_target") == interact_probe
		and player.get("_pnc_dest") == interact_probe.global_position
		and player.get("_pnc_interact_point") == interact_click
		and not bool(player.get("_pnc_hold_click")),
		"PNC stores the interactable's origin and click point instead of replaying a swing")

	# The synthetic replay is for the target only; it must never make the player
	# latch a held attack (the old continuous-swing bug).
	player.set("_attack_held", false)
	var synthetic_click := InputEventMouseButton.new()
	synthetic_click.button_index = MOUSE_BUTTON_LEFT
	synthetic_click.pressed = true
	synthetic_click.position = Vector2(32, 32)
	synthetic_click.set_meta("pnc_synthetic", true)
	player.call("_input", synthetic_click)
	check(not bool(player.get("_attack_held")) and player.get("_active_swing") == null,
		"PNC synthetic clicks are ignored by the player and cannot start a swing")

	player.global_position = interact_probe.global_position + Vector2(30, 0)
	player.call("_pnc_steer", 0.016)
	check(interact_probe.opened == 1 and not bool(player.get("_pnc_active"))
		and player.get("_pnc_interact_target") == null
		and not bool(player.get("_pnc_hold_click")),
		"PNC opens an interactable directly after arriving within one block")
	player.call("_pnc_cancel")
	interact_probe.queue_free()
	await get_tree().process_frame
	# Verify the resolver against a real chest scene (not only a fake probe).
	var real_chest: Node2D = load("res://scenes/objects/ChestBlock.tscn").instantiate() as Node2D
	add_child(real_chest)
	await get_tree().process_frame
	real_chest.global_position = player.global_position + Vector2(160, 0)
	check(player.call("_pnc_interact_target_at",
		real_chest.global_position + Vector2(0, -8)) == real_chest,
		"PNC target resolution finds a real chest sprite")
	real_chest.queue_free()
	await get_tree().process_frame
	Global.point_and_click = false

	# Cardinal and diagonal taps must produce the exact same direction, speed
	# and animation as the equivalent held WASD action.
	var dirs: Array = [
		{"label": "right", "actions": ["gameplay_right"], "vec": Vector2(1, 0)},
		{"label": "left", "actions": ["gameplay_left"], "vec": Vector2(-1, 0)},
		{"label": "up", "actions": ["gameplay_up"], "vec": Vector2(0, -1)},
		{"label": "down", "actions": ["gameplay_down"], "vec": Vector2(0, 1)},
		{"label": "down-right", "actions": ["gameplay_right", "gameplay_down"], "vec": Vector2(1, 1)},
		{"label": "down-left", "actions": ["gameplay_down", "gameplay_left"], "vec": Vector2(-1, 1)},
		{"label": "up-right", "actions": ["gameplay_right", "gameplay_up"], "vec": Vector2(1, -1)},
		{"label": "up-left", "actions": ["gameplay_up", "gameplay_left"], "vec": Vector2(-1, -1)},
	]
	for d in dirs:
		_release_parity_moves()
		player.call("_pnc_cancel")
		Global.point_and_click = false
		for action in (d["actions"] as Array):
			Input.action_press(str(action))
		player.call("get_input", 0.016)
		player.call("_update_animation")
		var wasd := _movement_snapshot(player)
		_release_parity_moves()

		player.call("_pnc_cancel")
		Global.point_and_click = true
		player.set("_pnc_active", true)
		player.set("_pnc_dest", player.global_position + (d["vec"] as Vector2) * 1000.0)
		player.set("_pnc_last_pos", player.global_position)
		player.set("_pnc_last_progress_ms", Time.get_ticks_msec())
		player.call("get_input", 0.016)
		player.call("_update_animation")
		var pnc := _movement_snapshot(player)

		var wd: Vector2 = wasd["dir"]
		var pd: Vector2 = pnc["dir"]
		var wv: Vector2 = wasd["vel"]
		var pv: Vector2 = pnc["vel"]
		check(wd.is_equal_approx(pd) and wv.is_equal_approx(pv),
			"tap %s produces the same direction and speed as WASD" % str(d["label"]))
		check(str(wasd["anim"]) == str(pnc["anim"]),
			"tap %s plays the same movement animation as WASD" % str(d["label"]))

	# Sprint parity, including the animation state.
	Global.point_and_click = false
	player.call("_pnc_cancel")
	player.set("_stamina_exhausted", false)
	Global.stamina = 100.0
	Global.mobile_shift = true
	Input.action_press("gameplay_right")
	player.call("get_input", 0.016)
	player.call("_update_animation")
	var wasd_sprint := _movement_snapshot(player)
	_release_parity_moves()

	player.call("_pnc_cancel")
	Global.point_and_click = true
	player.set("_pnc_active", true)
	player.set("_pnc_dest", player.global_position + Vector2(1000, 0))
	player.set("_pnc_last_pos", player.global_position)
	player.set("_pnc_last_progress_ms", Time.get_ticks_msec())
	player.call("get_input", 0.016)
	player.call("_update_animation")
	var pnc_sprint := _movement_snapshot(player)
	check((wasd_sprint["vel"] as Vector2).is_equal_approx(pnc_sprint["vel"] as Vector2)
		and (wasd_sprint["vel"] as Vector2).length() > 100.0,
		"tap sprint matches WASD sprint speed")
	check(bool(wasd_sprint["sprint"]) and bool(pnc_sprint["sprint"])
		and str(wasd_sprint["anim"]) == str(pnc_sprint["anim"]),
		"tap sprint uses the same sprint state and animation")
	Global.mobile_shift = false

	# Optional point-and-click auto-sprint: PNC orders sprint without Shift, but
	# direct WASD/joystick control still requires Shift and stamina gates apply.
	Global.point_and_click_auto_sprint = true
	Global.point_and_click = true
	Global.stamina = 100.0
	player.set("_stamina_exhausted", false)
	player.call("_pnc_cancel")
	player.set("_pnc_active", true)
	player.set("_pnc_dest", player.global_position + Vector2(1000, 0))
	player.set("_pnc_last_pos", player.global_position)
	player.set("_pnc_last_progress_ms", Time.get_ticks_msec())
	player.call("get_input", 0.016)
	player.call("_update_animation")
	var auto_pnc := _movement_snapshot(player)
	check(bool(auto_pnc["sprint"])
		and (auto_pnc["vel"] as Vector2).length() > 100.0
		and str(auto_pnc["anim"]).begins_with("sprint_"),
		"PNC auto-sprint uses the sprint state, speed and animation")

	Global.point_and_click = false
	player.call("_pnc_cancel")
	Input.action_press("gameplay_right")
	player.call("get_input", 0.016)
	player.call("_update_animation")
	var manual_auto := _movement_snapshot(player)
	_release_parity_moves()
	check(not bool(manual_auto["sprint"]),
		"auto-sprint does not apply to direct WASD movement")

	Global.point_and_click_auto_sprint = false
	Global.point_and_click = true
	player.call("_pnc_cancel")
	player.set("_pnc_active", true)
	player.set("_pnc_dest", player.global_position + Vector2(1000, 0))
	player.set("_pnc_last_pos", player.global_position)
	player.set("_pnc_last_progress_ms", Time.get_ticks_msec())
	player.call("get_input", 0.016)
	player.call("_update_animation")
	var auto_off := _movement_snapshot(player)
	check(not bool(auto_off["sprint"]),
		"turning automatic sprint off returns PNC movement to walking")

	Global.point_and_click_auto_sprint = true
	Global.stamina = 0.0
	player.set("_stamina_exhausted", true)
	player.call("_pnc_cancel")
	player.set("_pnc_active", true)
	player.set("_pnc_dest", player.global_position + Vector2(1000, 0))
	player.set("_pnc_last_pos", player.global_position)
	player.set("_pnc_last_progress_ms", Time.get_ticks_msec())
	player.call("get_input", 0.016)
	var auto_exhausted := _movement_snapshot(player)
	check(not bool(auto_exhausted["sprint"]),
		"stamina exhaustion still blocks PNC auto-sprint")
	player.set("_stamina_exhausted", false)
	Global.stamina = 100.0
	Global.point_and_click_auto_sprint = false

	# Snowstorm is a shared movement modifier, not a control-scheme modifier.
	Global.snowstorm_active = true
	player.call("_pnc_cancel")
	Global.point_and_click = false
	Input.action_press("gameplay_right")
	player.call("get_input", 0.016)
	player.call("_update_animation")
	var wasd_storm := _movement_snapshot(player)
	_release_parity_moves()
	player.call("_pnc_cancel")
	Global.point_and_click = true
	player.set("_pnc_active", true)
	player.set("_pnc_dest", player.global_position + Vector2(1000, 0))
	player.set("_pnc_last_pos", player.global_position)
	player.set("_pnc_last_progress_ms", Time.get_ticks_msec())
	player.call("get_input", 0.016)
	player.call("_update_animation")
	var pnc_storm := _movement_snapshot(player)
	check((wasd_storm["vel"] as Vector2).is_equal_approx(pnc_storm["vel"] as Vector2),
		"snowstorm slowdown applies identically to tap and WASD movement")
	Global.snowstorm_active = false

	# Stop: releasing the direction/Canceling the order settles both schemes.
	player.call("_pnc_cancel")
	Global.point_and_click = false
	_release_parity_moves()
	player.call("get_input", 0.016)
	player.call("_update_animation")
	var stopped := _movement_snapshot(player)
	check((stopped["dir"] as Vector2) == Vector2.ZERO
		and (stopped["vel"] as Vector2) == Vector2.ZERO
		and str(stopped["anim"]).begins_with("idle_"),
		"releasing movement input stops the shared movement path")

	# A UI opening cancels the tap order and produces no movement.
	Global.point_and_click = true
	player.set("_pnc_active", true)
	player.set("_pnc_dest", player.global_position + Vector2(1000, 0))
	player.set("_pnc_last_pos", player.global_position)
	player.set("_pnc_last_progress_ms", Time.get_ticks_msec())
	Global.pause_menu_open = true
	player.call("get_input", 0.016)
	var ui_stopped := _movement_snapshot(player)
	check(not bool(player.get("_pnc_active"))
		and (ui_stopped["dir"] as Vector2) == Vector2.ZERO
		and (ui_stopped["vel"] as Vector2) == Vector2.ZERO,
		"opening a UI cancels tap movement without moving the player")
	Global.pause_menu_open = false

	# Turning tap-to-control off cancels the order immediately.
	Global.point_and_click = true
	player.set("_pnc_active", true)
	player.set("_pnc_dest", player.global_position + Vector2(1000, 0))
	Global.point_and_click = false
	Global.point_and_click_changed.emit(false)
	player.call("get_input", 0.016)
	check(not bool(player.get("_pnc_active"))
		and (player.get("input_direction") as Vector2) == Vector2.ZERO,
		"switching tap-to-control off clears movement immediately")

	# A real tap must use its OWN event position. A stale touch-cursor override
	# (for example after a previous PNC hold) must not redirect the new order.
	Global.point_and_click = true
	player.call("_pnc_cancel")
	Global.set_touch_mouse(Vector2(-9999, -9999))
	var expected_dest := Vector2(300, 100)
	var tap := InputEventMouseButton.new()
	tap.button_index = MOUSE_BUTTON_LEFT
	tap.pressed = true
	tap.position = get_viewport().get_canvas_transform() * expected_dest
	player.call("_input", tap)
	check((player.get("_pnc_dest") as Vector2).distance_to(expected_dest) <= 1.0,
		"a new PNC tap ignores a stale shared-cursor position")
	player.call("_pnc_cancel")
	Global.clear_touch_mouse()

	# Simultaneous manual input wins once, cancelling the tap order rather than
	# applying both direction sources in the same physics tick.
	Global.point_and_click = true
	player.set("_pnc_active", true)
	player.set("_pnc_dest", player.global_position + Vector2(-1000, 0))
	Input.action_press("gameplay_right")
	player.call("get_input", 0.016)
	player.call("_update_animation")
	check(not bool(player.get("_pnc_active"))
		and (player.get("input_direction") as Vector2).is_equal_approx(Vector2.RIGHT),
		"manual input cancels tap movement without double-processing")
	_release_parity_moves()

	# Focus loss clears tap orders, held joystick input and sprint state.
	Global.point_and_click = true
	player.set("_pnc_active", true)
	player.set("_pnc_dest", player.global_position + Vector2(1000, 0))
	Input.action_press("gameplay_right")
	Global.mobile_move = Vector2.RIGHT
	Global.mobile_shift = true
	player.set("_attack_held", true)
	get_window().focus_exited.emit()
	var focus_lost := _movement_snapshot(player)
	check(not bool(player.get("_pnc_active"))
		and (focus_lost["dir"] as Vector2) == Vector2.ZERO
		and (focus_lost["vel"] as Vector2) == Vector2.ZERO
		and Global.mobile_move == Vector2.ZERO
		and not Global.mobile_shift
		and not bool(player.get("_attack_held"))
		and not Input.is_action_pressed("gameplay_right"),
		"window focus loss clears tap movement and held input")

	# Collision parity: the same wall stops both schemes at the same position.
	# The wall is offset below the ray so the tap steers straight (the player's
	# wider collision box still meets it), making the paths directly comparable.
	Global.point_and_click = false
	player.call("_pnc_cancel")
	Global.mobile_move = Vector2.ZERO
	Global.mobile_shift = false
	player.set_physics_process(false)
	var wall := StaticBody2D.new()
	wall.collision_layer = 1
	wall.collision_mask = 0
	wall.global_position = Vector2(160, 130)
	var wall_shape := CollisionShape2D.new()
	var wall_rect := RectangleShape2D.new()
	wall_rect.size = Vector2(20, 40)
	wall_shape.shape = wall_rect
	wall.add_child(wall_shape)
	add_child(wall)
	await get_tree().physics_frame

	# Isolate the collision probe from any stray knockback left by earlier QA
	# combat tests, and make the player immune for the duration of the run.
	player.set("_knockback", Vector2.ZERO)
	player.set("_invincible_until_ms", Time.get_ticks_msec() + 100000)
	player.set("_hit_flash_until_ms", 0)
	player.set("_stamina_exhausted", false)
	player.global_position = Vector2(100, 100)
	player.velocity = Vector2.ZERO
	player.set_physics_process(true)
	Input.action_press("gameplay_right")
	for i in range(100):
		await get_tree().physics_frame
	Input.action_release("gameplay_right")
	var wasd_wall_x: float = (player as Node2D).global_position.x
	player.set_physics_process(false)

	player.global_position = Vector2(100, 100)
	player.velocity = Vector2.ZERO
	player.set("_knockback", Vector2.ZERO)
	player.set("_invincible_until_ms", Time.get_ticks_msec() + 100000)
	Global.point_and_click = true
	player.set("_pnc_active", true)
	player.set("_pnc_dest", Vector2(300, 100))
	player.set("_pnc_last_pos", player.global_position)
	player.set("_pnc_last_progress_ms", Time.get_ticks_msec())
	player.set_physics_process(true)
	for i in range(100):
		await get_tree().physics_frame
	var pnc_wall_x: float = (player as Node2D).global_position.x
	player.set_physics_process(false)
	Global.point_and_click = false
	player.call("_pnc_cancel")
	check(absf(wasd_wall_x - pnc_wall_x) <= 1.0 and wasd_wall_x > 130.0,
		"tap and WASD collision against a wall resolve at the same position")

	wall.queue_free()
	player.queue_free()
	await get_tree().process_frame
	Global.point_and_click = old_pnc
	Global.point_and_click_auto_sprint = old_auto_sprint
	Global.block_mode = old_block_mode
	Global.block_mode_changed.emit(old_block_mode)
	Global.mobile_move = old_mobile_move
	Global.mobile_shift = old_mobile_shift
	Global.stamina = old_stamina
	Global.snowstorm_active = old_snowstorm
	Global.pause_menu_open = old_pause
	Global.has_pending_pos = old_pending
	Global.pending_player_pos = old_pending_pos
	Global.Hotbar = old_hotbar
	Global.Inventory = old_inventory
	Global.set_hotbar_selection(old_selected)
	Global.player_node = old_player if is_instance_valid(old_player) else null
	Global.world_node = old_world if is_instance_valid(old_world) else null
	_release_parity_moves()


# ── Helpers ──────────────────────────────────────────────────────────────

func _test_pause_menu_short_layout() -> void:
	# The pause card now sits inside a scroll root so short landscape screens
	# can still reach the bottom Help/Settings/Quit controls.
	Global.reset_pause_state()
	var old_vp: Vector2 = Global.ui_viewport_size
	var old_insets: Vector4 = Global.ui_safe_insets
	var old_scale: float = Global.ui_scale
	Global.ui_viewport_size = Vector2(640.0, 360.0)
	Global.ui_safe_insets = Vector4.ZERO
	Global.ui_scale = 1.25
	var vp := SubViewport.new()
	vp.size = Vector2i(640, 360)
	add_child(vp)
	var pause: Control = load("res://scenes/ui/PauseMenu.tscn").instantiate() as Control
	vp.add_child(pause)
	await get_tree().process_frame
	pause.call("show_menu")
	await get_tree().process_frame
	var scroll: ScrollContainer = pause.get("_pause_center") as ScrollContainer
	var bar: VScrollBar = scroll.get_v_scroll_bar() if scroll != null else null
	check(scroll != null and bar != null and bar.max_value > bar.page + 1.0,
		"pause menu becomes scrollable on a 640x360 landscape screen")
	if scroll != null:
		scroll.scroll_vertical = int(bar.max_value)
	await get_tree().process_frame
	var quit_button: Button = null
	for node in pause.find_children("*", "Button", true, false):
		if (node as Button).text == "Quit to Menu":
			quit_button = node as Button
			break
	var content := Global.ui_content_rect()
	check(quit_button != null and content.encloses(quit_button.get_global_rect()),
		"the bottom pause-menu controls are reachable inside the safe area")
	pause.call("hide_menu")
	vp.queue_free()
	await get_tree().process_frame
	Global.ui_viewport_size = old_vp
	Global.ui_safe_insets = old_insets
	Global.ui_scale = old_scale
	Global.reset_pause_state()


func _test_tutorial_help_and_cursors() -> void:
	# ?? Tutorial compass arrow ????????????????????????????????????????
	Global.reset_pause_state()
	var old_player: Node = Global.player_node
	var old_viewport: Vector2 = Global.ui_viewport_size
	var old_insets: Vector4 = Global.ui_safe_insets
	var old_scale: float = Global.ui_scale
	var fake_player := Node2D.new()
	add_child(fake_player)
	fake_player.global_position = Vector2(500.0, 500.0)
	Global.player_node = fake_player
	var arrow: Node2D = load("res://scripts/tutorial_arrow.gd").new() as Node2D
	fake_player.add_child(arrow)
	await get_tree().process_frame
	arrow.call("set_target", fake_player.global_position + Vector2(320.0, 0.0), "Target")
	await get_tree().process_frame
	var arrow_dir: Vector2 = arrow.get("_dir") as Vector2
	check(arrow.visible and arrow_dir.x > 0.9 and absf(arrow_dir.y) < 0.1,
		"tutorial compass points at an off-screen target and stays player-anchored")
	var arrow_target: Vector2 = arrow.get("_target")
	fake_player.global_position = arrow_target + Vector2(0.0, 30.0)
	await get_tree().process_frame
	check(not arrow.visible, "tutorial compass hides on arrival")
	arrow.call("clear_target")
	check(not arrow.visible, "clearing a tutorial target hides the compass")

	# A UI modal must not leave the compass floating over panels.
	arrow.call("set_target", fake_player.global_position + Vector2(320.0, 0.0), "Target")
	await get_tree().process_frame
	Global.open_ui()
	await get_tree().process_frame
	var hidden_by_ui: bool = not arrow.visible
	Global.close_ui()
	await get_tree().process_frame
	check(hidden_by_ui and arrow.visible, "tutorial compass hides while UI is open and returns afterwards")
	fake_player.queue_free()
	Global.player_node = old_player
	Global.reset_pause_state()

	var guide_src := FileAccess.get_file_as_string("res://scripts/tutorial_guide.gd")
	var marker_src := FileAccess.get_file_as_string("res://scripts/tutorial_marker.gd")
	check(guide_src.contains("ARROW_SCRIPT") and guide_src.contains("_setup_guide_arrow")
		and guide_src.contains("_guide_arrow.call(\"set_target\"") and guide_src.contains("_guide_arrow.call(\"clear_target\")"),
		"tutorial guide attaches and drives the world compass arrow")
	check(marker_src.contains("var arrows: Array") and marker_src.contains("draw_colored_polygon")
		and marker_src.contains("Vector2(0.0, -off)") and marker_src.contains("Vector2(0.0, off)"),
		"tutorial tile marker draws four inward arrowheads")

	# ?? Dialogue skip button ?????????????????????????????????????????
	Global.ui_viewport_size = Vector2(1152.0, 648.0)
	Global.ui_safe_insets = Vector4(40.0, 12.0, 28.0, 16.0)
	Global.ui_scale = 1.5
	var layer := CanvasLayer.new()
	add_child(layer)
	var dlg: Control = load("res://scripts/tutorial_dialogue.gd").new() as Control
	layer.add_child(dlg)
	await get_tree().process_frame
	var opened := bool(dlg.call("show_conversation", [
		{"speaker": "Py-San", "portrait": "res://sprites/char/pysan.png", "text": "First line."},
		{"speaker": "LUA", "portrait": "res://sprites/char/lua/front.png", "text": "Second line."},
	]))
	dlg.call("_layout")
	var skip_btn: Button = dlg.get("_skip_button") as Button
	var safe := Global.ui_content_rect()
	var skip_rect := skip_btn.get_global_rect() if skip_btn != null else Rect2()
	var skip_h := maxf(36.0 * 1.5, float(Global.ui_font_size(10)) + 18.0 * 1.5)
	var mobile_dialogue := TutorialDialogue.panel_rect(safe, 1.5, true, skip_h)
	var desktop_dialogue := TutorialDialogue.panel_rect(safe, 1.5, false, skip_h)
	check(safe.encloses(mobile_dialogue)
		and mobile_dialogue.position.y >= safe.position.y + skip_h
		and not mobile_dialogue.intersects(skip_rect),
		"Android tutorial dialogue sits at the top below the Skip control")
	check(safe.encloses(desktop_dialogue)
		and desktop_dialogue.end.y <= safe.end.y - 8.0,
		"desktop tutorial dialogue keeps its bottom placement")
	check(opened and skip_btn != null and skip_btn.visible,
		"active dialogue exposes a real top-right skip button")
	check(skip_btn != null and safe.encloses(skip_rect)
		and skip_rect.position.x > safe.position.x + safe.size.x * 0.6,
		"dialogue skip button stays inside the safe content area at the top right")
	var skip_hits := [0]
	var on_skip := func() -> void: skip_hits[0] += 1
	dlg.skip_requested.connect(on_skip)
	if skip_btn != null:
		skip_btn.emit_signal("pressed")
	check(skip_hits[0] == 1 and bool(dlg.call("is_active")),
		"the skip button emits skip_requested without force-closing the dialogue")
	# The dialogue's own _input must leave the skip-button rect for the GUI.
	var skip_event := InputEventMouseButton.new()
	skip_event.button_index = MOUSE_BUTTON_LEFT
	skip_event.pressed = true
	skip_event.position = skip_rect.get_center()
	var line_before: int = int(dlg.call("current_line_index"))
	dlg.call("_input", skip_event)
	check(bool(dlg.call("is_active")) and int(dlg.call("current_line_index")) == line_before,
		"clicking the skip button rectangle does not advance the dialogue line")
	if dlg.skip_requested.is_connected(on_skip):
		dlg.skip_requested.disconnect(on_skip)
	dlg.call("dismiss")
	check(not skip_btn.visible, "closing a dialogue hides the skip button")
	layer.queue_free()
	await get_tree().process_frame
	Global.reset_pause_state()
	check(guide_src.contains("_dialogue.skip_requested.connect(_on_dialogue_skip_requested)"),
		"tutorial guide consumes the dialogue skip signal")

	# Behavioural skip flow: the guide must dismiss the current dialogue (so it
	# cannot re-open the skipped lesson) and advance exactly one step.
	var old_tut_stage: int = Global.tutorial_stage
	var old_tut_completed: bool = Global.tutorial_completed
	var old_tut_version: int = Global.tutorial_version
	Global.reset_pause_state()
	Global.tutorial_stage = 0
	Global.tutorial_completed = false
	var guide: Node = load("res://scripts/tutorial_guide.gd").new() as Node
	add_child(guide)
	var skip_dlg: Control = load("res://scripts/tutorial_dialogue.gd").new() as Control
	add_child(skip_dlg)
	await get_tree().process_frame
	guide.set("_dialogue", skip_dlg)
	guide.set("_current_step", 0)
	guide.set("_finished", false)
	guide.set("_step_complete", false)
	var dismissed_cb := Callable(guide, "_on_dialogue_dismissed")
	if not skip_dlg.dismissed.is_connected(dismissed_cb):
		skip_dlg.dismissed.connect(dismissed_cb)
	var welcome_open := bool(skip_dlg.call("show_conversation", [
		{"speaker": "Py-San", "portrait": "res://sprites/char/pysan.png", "text": "Welcome lesson."},
	]))
	guide.call("_on_dialogue_skip_requested")
	await get_tree().process_frame
	await get_tree().process_frame
	check(welcome_open and int(guide.get("_current_step")) == 1
		and Global.tutorial_stage == 1 and bool(guide.call("_step_id") == "move_one")
		and not bool(skip_dlg.call("is_active")),
		"dialogue skip advances exactly one lesson and dismisses the skipped dialogue")
	if skip_dlg.call("is_active"):
		skip_dlg.call("dismiss")
	await get_tree().process_frame

	# Skipping the travel lesson must never start its automatic teleport.
	var step_ids: Array = guide.get_script().get_script_constant_map().get("STEPS", []) as Array
	var travel_idx: int = step_ids.find("dungeon_travel")
	if travel_idx >= 0:
		guide.set("_current_step", travel_idx)
		guide.set("_step_complete", false)
		guide.set("_finished", false)
		guide.set("_travel_started", false)
		guide.call("_on_dialogue_skip_requested")
		await get_tree().process_frame
		await get_tree().process_frame
		check(not bool(guide.get("_travel_started"))
			and int(guide.get("_current_step")) == step_ids.find("automatica"),
			"skipping the dungeon lesson does not start its teleport")
	guide.queue_free()
	skip_dlg.queue_free()
	await get_tree().process_frame
	Global.tutorial_stage = old_tut_stage
	Global.tutorial_completed = old_tut_completed
	Global.tutorial_version = old_tut_version
	Global.reset_pause_state()

	# ?? Help panel content and pause-menu integration ????????????????
	Global.ui_viewport_size = Vector2(1152.0, 648.0)
	Global.ui_safe_insets = Vector4.ZERO
	Global.ui_scale = 1.5
	var help_script: Script = load("res://scripts/help_panel.gd")
	var categories: Array = help_script.get_script_constant_map().get("CATEGORIES", []) as Array
	check(categories.size() == 9, "help panel exposes nine player-facing documentation categories")
	var all_help := ""
	var category_ids: Array = []
	var category_titles: Array = []
	for value in categories:
		var entry: Dictionary = value as Dictionary
		category_ids.append(str(entry.get("id", "")))
		category_titles.append(str(entry.get("title", "")))
		var body := str(entry.get("body", ""))
		all_help += body + "\n"
		check(body.length() > 450 and not body.contains("TODO") and not body.contains("draft only"),
			"help category '%s' contains substantive documentation" % str(entry.get("title", "")))
	check(category_titles.has("Start Here") and category_titles.has("Controls")
		and category_titles.has("Dungeons & Bestiary") and category_titles.has("Settings & Troubleshooting"),
		"help covers onboarding, controls, dungeons and troubleshooting")
	for term in ["Automatica", "Algorithmica", "Bestiary", "Cloud saves", "Furnace",
			"Color Crafter", "Point-and-Click", "SKIP LESSON", "INV", "Knowledge Altar",
			"Quiz Altar", "Bonfire", "stamina", "seed", "waypoint", "SKIP", "save"]:
		check(all_help.to_lower().contains(term.to_lower()),
			"help documents '%s'" % term)
	var help_panel: Control = help_script.new() as Control
	add_child(help_panel)
	await get_tree().process_frame
	var help_buttons: Dictionary = help_panel.get("_category_buttons") as Dictionary
	var help_content: RichTextLabel = help_panel.get("_content") as RichTextLabel
	check(help_buttons.size() == categories.size() and help_content != null,
		"help panel builds a category sidebar and scrollable content pane")
	var dungeons_button: Button = help_buttons.get("dungeons") as Button
	if dungeons_button != null:
		dungeons_button.emit_signal("pressed")
	check(str(help_panel.get("_current_category")) == "dungeons"
		and help_content.text.to_upper().contains("KNOWLEDGE ALTAR"),
		"selecting a help category swaps the documentation content")
	remove_child(help_panel)
	help_panel.free()

	# The panel's combined minimum must fit representative safe areas.
	var profiles := [
		{"vp": Vector2(1152, 648), "insets": Vector4.ZERO, "scale": 1.5},
		{"vp": Vector2(1024, 600), "insets": Vector4(90, 0, 60, 0), "scale": 1.25},
		{"vp": Vector2(800, 480), "insets": Vector4(40, 0, 20, 0), "scale": 1.25},
		{"vp": Vector2(640, 360), "insets": Vector4.ZERO, "scale": 1.25},
		{"vp": Vector2(1920, 1080), "insets": Vector4.ZERO, "scale": 1.65},
	]
	for profile_value in profiles:
		var profile: Dictionary = profile_value as Dictionary
		Global.ui_viewport_size = profile["vp"] as Vector2
		Global.ui_safe_insets = profile["insets"] as Vector4
		Global.ui_scale = float(profile["scale"])
		var probe_help: Control = help_script.new() as Control
		add_child(probe_help)
		await get_tree().process_frame
		var usable := Global.ui_content_rect()
		var minimum := probe_help.get_combined_minimum_size()
		check(minimum.x <= usable.size.x + 1.0 and minimum.y <= usable.size.y + 1.0,
			"help panel fits a %dx%d safe area" % [int(usable.size.x), int(usable.size.y)])
		probe_help.queue_free()
		await get_tree().process_frame

	Global.reset_pause_state()
	Global.ui_scale = 1.5
	var pause: Control = load("res://scripts/pause_menu.gd").new() as Control
	add_child(pause)
	await get_tree().process_frame
	pause.call("show_menu")
	var help_center: CenterContainer = pause.get("_help_center") as CenterContainer
	var pause_center: ScrollContainer = pause.get("_pause_center") as ScrollContainer
	var menu_has_help := false
	for node in pause.find_children("*", "Button", true, false):
		if (node as Button).text == "Help & Documentation":
			menu_has_help = true
			break
	check(menu_has_help, "pause menu exposes Help & Documentation")
	pause.call("_on_open_help")
	var help_panel_node: Control = help_center.get_node_or_null("HelpPanel") as Control if help_center != null else null
	check(help_center != null and help_center.visible and not pause_center.visible
		and help_panel_node != null,
		"Help & Documentation replaces the pause panel and opens its documentation view")
	var back_button: Button = null
	if help_panel_node != null:
		for node in help_panel_node.find_children("*", "Button", true, false):
			if (node as Button).text == "< Back":
				back_button = node as Button
				break
	if back_button != null:
		back_button.emit_signal("pressed")
	check(back_button != null and not help_center.visible and pause_center.visible,
		"help Back button returns to the pause panel")
	pause.call("_on_open_help")
	var help_back_ok := Global.request_ui_back()
	check(help_back_ok and not help_center.visible and pause_center.visible,
		"Escape/Back closes Help one layer before the pause menu")
	pause.call("hide_menu")
	pause.queue_free()
	await get_tree().process_frame
	Global.reset_pause_state()

	# ?? Contextual desktop cursor manager ????????????????????????????
	var cursor_script: Script = load("res://scripts/cursor_manager.gd")
	var cursor_src := FileAccess.get_file_as_string("res://scripts/cursor_manager.gd")
	check(cursor_src.contains("Global.is_mobile()") and cursor_src.contains("headless"),
		"contextual cursor host guard covers Android and headless runs")
	var cursor_files: Dictionary = cursor_script.get_script_constant_map().get("CURSOR_FILES", {}) as Dictionary
	var all_cursors_24 := true
	for key in cursor_files:
		var path := str(cursor_files[key])
		var tex := load(path) as Texture2D if ResourceLoader.exists(path) else null
		if tex == null or tex.get_width() != 24 or tex.get_height() != 24:
			all_cursors_24 = false
	check(cursor_files.size() == 6 and all_cursors_24,
		"all six approved 24x24 cursor sprites are imported and registered")
	var hotspot: Vector2 = cursor_script.get_script_constant_map().get("HOTSPOT", Vector2.ZERO) as Vector2
	check(hotspot.x >= 0.0 and hotspot.y >= 0.0 and hotspot.x < 24.0 and hotspot.y < 24.0,
		"custom cursor hotspot stays inside the 24x24 artwork")
	var cursor_manager: Node = cursor_script.new() as Node
	add_child(cursor_manager)
	await get_tree().process_frame
	check(not cursor_manager.is_processing(), "contextual cursor director is disabled in headless/mobile environments")

	# Build mode is for placing/demolishing, so interaction cursors must not
	# suggest that a chest/station is about to open.
	var cursor_old_player: Node = Global.player_node
	var cursor_old_world: Node = Global.world_node
	var cursor_old_build: bool = Global.block_mode
	var cursor_player := Node2D.new()
	var cursor_world := Node2D.new()
	add_child(cursor_player)
	add_child(cursor_world)
	Global.player_node = cursor_player
	Global.world_node = cursor_world
	var build_probe := CursorProbe.new()
	add_child(build_probe)
	build_probe.add_to_group("Chest")
	Global.block_mode = true
	cursor_manager.set("_current", "movement")
	cursor_manager.call("_refresh_cursor")
	check(str(cursor_manager.get("_current")) == "default",
		"contextual cursor falls back to the OS arrow in build mode")
	Global.block_mode = bool(cursor_old_build)
	build_probe.queue_free()
	cursor_player.queue_free()
	cursor_world.queue_free()
	await get_tree().process_frame
	Global.player_node = cursor_old_player
	Global.world_node = cursor_old_world

	var chest_probe := CursorProbe.new()
	add_child(chest_probe)
	chest_probe.add_to_group("Chest")
	check(str(cursor_manager.call("_kind_at", Vector2.ZERO)) == "chest",
		"cursor resolves a nearby chest")
	chest_probe.queue_free()
	await get_tree().process_frame

	var station_probe := CursorProbe.new()
	add_child(station_probe)
	station_probe.add_to_group("CraftingStation")
	check(str(cursor_manager.call("_kind_at", Vector2.ZERO)) == "crafting",
		"cursor resolves a crafting station")
	station_probe.queue_free()
	await get_tree().process_frame

	var color_probe := CursorProbe.new()
	add_child(color_probe)
	color_probe.add_to_group("ColorCrafter")
	check(str(cursor_manager.call("_kind_at", Vector2.ZERO)) == "color",
		"cursor resolves a Color Crafter")
	color_probe.queue_free()
	await get_tree().process_frame

	var furnace_data := ItemData.new()
	furnace_data.item_name = "Furnace"
	var furnace_probe := CursorProbe.new()
	furnace_probe.item_data = furnace_data
	add_child(furnace_probe)
	furnace_probe.add_to_group("TouchInteractable")
	check(str(cursor_manager.call("_kind_at", Vector2.ZERO)) == "furnace",
		"cursor resolves a furnace from its interactable item data")
	furnace_probe.queue_free()
	await get_tree().process_frame

	var generic_probe := CursorProbe.new()
	add_child(generic_probe)
	generic_probe.add_to_group("PlainClickBlock")
	check(str(cursor_manager.call("_kind_at", Vector2.ZERO)) == "generic",
		"cursor resolves doors and other plain-click blocks")
	generic_probe.queue_free()
	await get_tree().process_frame

	var waypoint_probe := CursorProbe.new()
	waypoint_probe.global_position = Vector2(50.0, 50.0)
	add_child(waypoint_probe)
	waypoint_probe.add_to_group("WorldWaypoint")
	check(str(cursor_manager.call("_kind_at", Vector2(50.0, 50.0))) == "generic",
		"cursor resolves a nearby world waypoint")
	waypoint_probe._player_nearby = false
	check(str(cursor_manager.call("_kind_at", Vector2(50.0, 50.0))) == "movement",
		"cursor ignores a waypoint while the player is out of range")
	waypoint_probe.queue_free()
	await get_tree().process_frame

	var dungeon_step_probe := CursorProbe.new()
	add_child(dungeon_step_probe)
	dungeon_step_probe.add_to_group("DungeonWaypoint")
	check(str(cursor_manager.call("_kind_at", Vector2.ZERO)) == "movement",
		"cursor does not imply a click action on the step-only dungeon waypoint")
	dungeon_step_probe.queue_free()
	await get_tree().process_frame

	var portal_probe := CursorPortalProbe.new()
	add_child(portal_probe)
	portal_probe.add_to_group("CavePortal")
	check(str(cursor_manager.call("_kind_at", Vector2.ZERO)) == "generic",
		"cursor resolves a nearby cave entrance")
	portal_probe._player_nearby = false
	check(str(cursor_manager.call("_kind_at", Vector2.ZERO)) == "movement",
		"cursor ignores a cave entrance while the player is out of range")
	portal_probe.queue_free()
	await get_tree().process_frame

	check(str(cursor_manager.call("_kind_at", Vector2(100000.0, 100000.0))) == "movement",
		"cursor falls back to movement over empty ground")
	cursor_manager.queue_free()
	await get_tree().process_frame
	Global.ui_viewport_size = old_viewport
	Global.ui_safe_insets = old_insets
	Global.ui_scale = old_scale
	Global.player_node = old_player
	Global.reset_pause_state()


func _test_tree_canopy_occupancy() -> void:
	var world: Node = load("res://scripts/world.gd").new()
	var cell := Vector2i(10, 10)
	world.call("_mark_tree_occupied", cell)
	var occupied: Dictionary = world.get("_tree_occupied_tiles") as Dictionary
	check(occupied.has(Vector2i(10, 7)) and occupied.has(Vector2i(9, 10)) \
		and occupied.has(Vector2i(10, 11)),
		"tree occupancy covers the canopy, trunk and base")
	check(not occupied.has(Vector2i(10, 6)) and not occupied.has(Vector2i(8, 10)) \
		and not occupied.has(Vector2i(10, 12)),
		"tree occupancy matches the visible 3x3-tile sprite footprint")
	check(bool(world.call("_scatter_canopy_blocked", Vector2i(10, 14))),
		"scattered tree crown cannot overlap an existing tree")
	check(not bool(world.call("_scatter_canopy_blocked", Vector2i(14, 10))),
		"scattered tree crown permits horizontal clearance")
	world.call("_unmark_tree_occupied", cell)
	check(occupied.is_empty(), "chopping a tree clears its full canopy occupancy")
	world.free()


func _test_decorative_structures() -> void:
	var templates: Array = []
	var coverage: Dictionary = {}
	for file_name in ResourceLoader.list_directory("res://resources/structures/"):
		if not file_name.begins_with("decor_") or not file_name.ends_with(".tres"):
			continue
		var template := load("res://resources/structures/" + file_name) as GeneratedStructure
		check(template != null and template.is_valid(),
			"decor template loads and validates: " + file_name)
		if template == null or not template.is_valid():
			continue
		templates.append(template)
		coverage[template.decor_kind + ":" + template.biome] = true
		var layout: Dictionary = template.build_layout(12345)
		var layout_again: Dictionary = template.build_layout(12345)
		var cells: Dictionary = layout.get("cells", {})
		var size: Vector2i = layout.get("size", Vector2i.ZERO)
		check(not layout.is_empty() and cells.size() >= 4,
			"decor template builds a non-empty layout: " + file_name)
		check(layout == layout_again,
			"decor layout is deterministic for a seed: " + file_name)
		var floors := 0
		var solids := 0
		var invalid_paths := 0
		for cell_value in cells.keys():
			var cell := cell_value as Vector2i
			if cell.x < 0 or cell.y < 0 or cell.x >= size.x or cell.y >= size.y:
				invalid_paths += 1
			var path := str(cells[cell_value])
			if not ResourceLoader.exists(path):
				invalid_paths += 1
				continue
			var data := load(path) as ItemData
			if data == null or not data.is_placeable or data.place_scene_path.is_empty() \
					or not ResourceLoader.exists(data.place_scene_path):
				invalid_paths += 1
				continue
			if data.is_floor:
				floors += 1
			else:
				solids += 1
		check(invalid_paths == 0,
			"decor layout uses existing placeable blocks only: " + file_name)
		if template.decor_kind == "house":
			check(floors > 0 and solids > 0 and not template.roof_blocks.is_empty(),
				"house layout has floor, walls and roof blocks: " + file_name)
			check(size.x >= template.min_width \
				and size.x <= template.max_width + 2 \
				and size.y >= template.min_height \
				and size.y <= template.max_height + 3,
				"house footprint stays within template dimensions: " + file_name)
		else:
			check(floors == 0 and solids > 0,
				"pillar layout is built from solid column blocks: " + file_name)
			check(size.x >= template.min_width and size.x <= template.max_width \
				and size.y >= template.min_height and size.y <= template.max_height,
				"pillar footprint stays within template dimensions: " + file_name)
	check(templates.size() >= 6, "six biome-specific house/pillar templates exist")
	for biome_name in ["plain", "desert", "snowy"]:
		for kind_name in ["house", "pillar"]:
			check(coverage.has(kind_name + ":" + biome_name),
				"%s template exists for the %s biome" % [kind_name, biome_name])

	# Save persistence logic: every expected generated cell is present, except
	# cells the player mined/replaced. This exercises the same comparison used by
	# get_world_save_data without generating a whole world in the QA suite.
	var house_template: GeneratedStructure = null
	for candidate in templates:
		if (candidate as GeneratedStructure).decor_kind == "house":
			house_template = candidate as GeneratedStructure
			break
	if house_template != null:
		var layout: Dictionary = house_template.build_layout(777)
		var cells: Dictionary = layout.get("cells", {})
		var anchor := Vector2i(20, 20)
		var def := {
			"template_path": house_template.resource_path,
			"anchor_x": anchor.x,
			"anchor_y": anchor.y,
			"seed": 777,
			"biome": house_template.biome,
			"layout_version": 1,
		}
		var placed: Dictionary = {}
		for cell_value in cells.keys():
			placed[anchor + (cell_value as Vector2i)] = {
				"node": null,
				"name": "generated",
				"decor_generated": true,
				"decor_index": 0,
			}
		var world: Node = load("res://scripts/world.gd").new()
		world.set("_decor_structures", [def])
		world.set("_placed_blocks", placed)
		var removed: Array = world.call("_decor_save_removed") as Array
		check(removed.is_empty(),
			"intact generated structure records no removed cells")
		var removed_cell: Vector2i = anchor + (cells.keys()[0] as Vector2i)
		placed.erase(removed_cell)
		world.set("_placed_blocks", placed)
		removed = world.call("_decor_save_removed") as Array
		check(removed.size() == 1,
			"mined generated block is recorded as removed")
		placed[removed_cell] = {"node": null, "name": "player block"}
		world.set("_placed_blocks", placed)
		removed = world.call("_decor_save_removed") as Array
		check(removed.size() == 1,
			"player replacement still records the original structure cell as removed")
		world.free()


func _test_waypoints() -> void:
	# The production assets are the approved draft sheets copied verbatim.
	var py_tex := load("res://sprites/waypoints/portal_python_stonegate_sheet.png") as Texture2D
	var lua_tex := load("res://sprites/waypoints/portal_lua_ancient_sheet.png") as Texture2D
	var tower_tex := load("res://sprites/waypoints/world_waypoint_tower_sheet.png") as Texture2D
	check(py_tex != null and py_tex.get_width() == 1280 and py_tex.get_height() == 128,
		"Python waypoint sheet is the approved 8x160x128 animation")
	check(lua_tex != null and lua_tex.get_width() == 1536 and lua_tex.get_height() == 160,
		"Lua waypoint sheet is the approved 8x192x160 animation")
	check(tower_tex != null and tower_tex.get_width() == 1280 and tower_tex.get_height() == 224,
		"world waypoint tower sheet is the approved 8x160x224 animation")
	var frames := WaypointAnim.build(py_tex, Vector2i(160, 128))
	check(frames.get_frame_count("idle") == 8,
		"waypoint helper builds all eight animation frames")
	check(is_equal_approx(frames.get_animation_speed("idle"), 10.0)
		and frames.get_animation_loop("idle"),
		"waypoint animation is a 10 fps infinite loop")
	var first := frames.get_frame_texture("idle", 0) as AtlasTexture
	var last := frames.get_frame_texture("idle", 7) as AtlasTexture
	check(first != null and first.region.position == Vector2.ZERO
		and last != null and last.region.position == Vector2(1120, 0),
		"waypoint sheet frames slice horizontally from source art")

	var world_script := load("res://scripts/world.gd") as GDScript
	var constants: Dictionary = world_script.get_script_constant_map()
	check(constants.get("WORLD_WAYPOINT_SIZE") == Vector2i(5, 7),
		"world waypoint towers reserve a 5x7 footprint")
	check(float(constants.get("WORLD_WAYPOINT_DENSITY", 0.0)) > 0.0
		and int(constants.get("DUNGEON_NEAR_CHUNK_RADIUS", 0)) >= 3,
		"world towers have a density target and dungeons prefer nearby chunks")
	check(constants.get("DUNGEON_ENTRANCE_PYTHON_SIZE") == Vector2i(5, 4)
		and constants.get("DUNGEON_ENTRANCE_LUA_SIZE") == Vector2i(6, 5),
		"dungeon entrances use native 5x4 Python and 6x5 Lua large portals")

	var tower := WorldWaypointTower.new()
	tower.setup("ww_10_20", "Skyglass Waypoint 01", Vector2i(10, 20))
	check(tower.waypoint_id == "ww_10_20" and tower.foot_cell == Vector2i(12, 26),
		"world tower setup derives a stable id and bottom-centre foot")
	add_child(tower)
	var tower_groups := tower.is_in_group("WorldWaypoint")
	var tower_constants: Dictionary = tower.get_script().get_script_constant_map()
	var click_rect: Rect2 = tower_constants.get("CLICK_RECT", Rect2()) as Rect2
	check(click_rect.has_point(Vector2(0, -220))
		and click_rect.has_point(Vector2(80, -10))
		and click_rect.has_point(Vector2(0, 18)),
		"the full tower facade and shaded base are clickable")
	var tower_shadow := tower.get_node_or_null("TowerShadow") as Sprite2D
	var tower_base := tower.get_node_or_null("TowerBaseShade") as Polygon2D
	check(tower_shadow != null and tower_shadow.texture != null
		and tower_base != null and tower_base.polygon.size() >= 4,
		"world towers cast a soft floor shadow and shaded base")
	remove_child(tower)
	tower.free()
	check(tower_groups, "world tower joins the permanent waypoint map group")

	var world_src := FileAccess.get_file_as_string("res://scripts/world.gd")
	var recall_src := FileAccess.get_file_as_string("res://scripts/waypoint_recall_fx.gd")
	check(world_src.contains("WAYPOINT_RECALL_FX_SCRIPT")
		and world_src.contains("WAYPOINT_WHITE_FADE_IN_SEC")
		and world_src.contains('call_deferred("_run_waypoint_recall"')
		and recall_src.contains("draw_colored_polygon"),
		"waypoint travel plays a recall beacon and white screen fade")

	var temp := DungeonWaypoint.new()
	temp.setup(11, "lua", null, Vector2i(1, 2))
	check(temp.language == "lua" and temp.dungeon_index == 11
		and temp.anchor_cell == Vector2i(1, 2),
		"temporary dungeon waypoint setup keeps dungeon identity and anchor")
	add_child(temp)
	var temp_is_dungeon := temp.is_in_group("DungeonWaypoint")
	var temp_is_world := temp.is_in_group("WorldWaypoint")
	var temp_sprite := temp.get_node_or_null("WaypointSprite") as Sprite2D
	var temp_step := temp.get_node_or_null("StepArea") as Area2D
	check(temp_sprite != null and temp_sprite.texture != null
		and temp_sprite.texture.resource_path == "res://sprites/dungeon/dungeon_portal.png",
		"temporary waypoint uses the existing 3x3 dungeon-portal sprite")
	check(temp_step != null and temp_step.collision_mask == 4,
		"temporary waypoint has a player step trigger")
	remove_child(temp)
	temp.free()
	check(temp_is_dungeon and not temp_is_world,
		"temporary dungeon waypoint is excluded from permanent map destinations")

	var world: Node = world_script.new()
	var fake_wp := FakeWaypointNode.new()
	fake_wp.anchor_cell = Vector2i(4, 5)
	fake_wp.language = "python"
	world.set("_dungeon_waypoint_nodes", {7: fake_wp})
	world.set("_world_waypoints", [{"id": "ww_a", "label": "A", "x": 1, "y": 2}])
	var temp_rows: Array = world.call("_dungeon_waypoint_save_data") as Array
	var tower_rows: Array = world.call("_world_waypoint_save_data") as Array
	check(temp_rows.size() == 1 and int((temp_rows[0] as Dictionary)["index"]) == 7
		and str((temp_rows[0] as Dictionary)["language"]) == "python",
		"temporary waypoint save rows preserve dungeon index and language")
	check(tower_rows.size() == 1 and str((tower_rows[0] as Dictionary)["id"]) == "ww_a",
		"permanent world waypoint save rows preserve stable ids")
	world.free()
	fake_wp.free()

	# Selection closes the map only after the world reports a successful
	# teleport, and the source map uses the real minimap overlay lifecycle.
	Global.reset_pause_state()
	var old_world: Node = Global.world_node
	var fake_world := FakeWorldNode.new()
	Global.world_node = fake_world
	var minimap_src := FileAccess.get_file_as_string("res://scripts/minimap.gd")
	check(minimap_src.contains('get_nodes_in_group("WorldWaypoint")')
		and minimap_src.contains('"World Waypoint"')
		and minimap_src.contains("_map_close_rect"),
		"the overworld map draws world waypoints, legends them and exposes an X close control")
	var mm := Minimap.new()
	add_child(mm)
	var opened := bool(mm.call("open_world_waypoint_map", "source"))
	check(opened and bool(mm.get("_waypoint_mode")) and bool(mm.get("_expanded")),
		"world waypoint map opens through the existing exclusive map overlay")
	# Headless runs use a 64x64 viewport; simulate a real screen so the
	# fullscreen safe-area layout can be checked for containment and sizing.
	var old_ui_viewport: Vector2 = Global.ui_viewport_size
	var old_ui_insets: Vector4 = Global.ui_safe_insets
	Global.ui_viewport_size = Vector2(1920, 1080)
	Global.ui_safe_insets = Vector4.ZERO
	var content := Global.ui_content_rect()
	var panel: Rect2 = mm.call("_expanded_panel_rect") as Rect2
	var map_rect: Rect2 = mm.call("_expanded_map_rect") as Rect2
	var legend_rect: Rect2 = mm.call("_expanded_legend_rect") as Rect2
	var close_rect: Rect2 = mm.call("_map_close_rect") as Rect2
	var margin: float = Minimap.MARGIN * Global.ui_scale
	var pad: float = 18.0 * Global.ui_scale
	var gap: float = 16.0 * Global.ui_scale
	check(absf(panel.position.x - (content.position.x + margin)) <= 1.0
		and absf(panel.size.x - (content.size.x - margin * 2.0)) <= 1.0
		and absf(panel.size.y - (content.size.y - margin * 2.0)) <= 1.0,
		"the expanded map fills the safe content area")
	check(map_rect.size.x > 0.0 and map_rect.size.y > 0.0
		and legend_rect.size.x > 0.0
		and absf(map_rect.size.y - legend_rect.size.y) <= 1.0
		and absf(map_rect.size.x + gap + legend_rect.size.x
			- (panel.size.x - pad * 2.0)) <= 1.0
		and legend_rect.position.x >= map_rect.end.x
		and panel.has_point(map_rect.position)
		and panel.has_point(legend_rect.end - Vector2(1, 1))
		and panel.has_point(close_rect.get_center()),
		"the fullscreen map fills its rectangle with the legend list on the right")
	var map_layer: CanvasLayer = mm.get("_map_layer") as CanvasLayer
	check(map_layer != null and map_layer.layer >= 100
		and mm.get_parent() == map_layer
		and bool(mm.get("_hud_hidden_by_map")),
		"the expanded map is promoted above the HUD and hides the gameplay HUD")
	mm.set("_waypoint_hitboxes", [{"id": "dest", "label": "Destination",
		"pos": Vector2(24, 24)}])
	var selected := bool(mm.call("_try_select_waypoint", Vector2(24, 24)))
	check(selected and fake_world.teleported_id == "dest"
		and not bool(mm.get("_expanded")),
		"selecting a waypoint teleports and closes the map")
	# The X button closes without selecting a waypoint.
	var reopened := bool(mm.call("open_world_waypoint_map", "source"))
	var close_rect_2: Rect2 = mm.call("_map_close_rect") as Rect2
	var close_event := InputEventMouseButton.new()
	close_event.button_index = MOUSE_BUTTON_LEFT
	close_event.pressed = true
	close_event.position = close_rect_2.get_center()
	mm.call("_input", close_event)
	check(reopened and not bool(mm.get("_expanded"))
		and mm.get("_map_layer") == null
		and not bool(mm.get("_hud_hidden_by_map")),
		"the fullscreen map X button closes it and restores the HUD layer")
	Global.ui_viewport_size = old_ui_viewport
	Global.ui_safe_insets = old_ui_insets
	remove_child(mm)
	mm.free()
	Global.world_node = old_world
	fake_world.free()
	Global.reset_pause_state()


func _saved_missions_version(path: String) -> int:
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if data is Dictionary:
		return int(data.get("missions_version", 0))
	return 0


func _write_world(slot: int, world_name: String, created_version: String) -> void:
	var data := JSON.stringify({
		"slot": slot,
		"world_name": world_name,
		"created_version": created_version,
		"timestamp": int(Time.get_unix_time_from_system()),
		"missions": [],
	})
	# Use the production install path so the encrypted owner sidecar is created.
	Global.install_cloud_save_bytes(slot, data.to_utf8_buffer())
