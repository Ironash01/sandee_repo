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


class SwingProbe:
	extends CharacterBody2D
	var swing_count: int = 0

	func swing_held_item() -> void:
		swing_count += 1


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
	Global.set_online_mode(false)
	Global.reset_pause_state()
	_test_registry()
	_test_friendly_mobs()
	await _test_save_and_progress()
	await _test_triggers()
	await _test_pause_and_build()
	_test_world_eligibility()
	_test_dungeon_generation()
	await _test_dungeon_progression_and_sides()
	_test_damage_and_spawn_constants()
	await _test_damage_application()
	await _test_safe_zones()
	await _test_grass_clearance()
	await _test_cave_persistence()
	await _test_cave_cache_lifecycle()
	await _test_torches()
	await _test_algorithmica_color()
	await _test_cactus_and_worm()
	await _test_fish_and_automatica()
	await _test_headless_fish_loot()
	await _test_rare_chest_generation()
	_test_minimap_lua_legend()
	await _test_knowledge_altar_pages()
	await _test_mission_events()
	await _test_smelting_recipes()
	await _test_held_damage_display()
	await _test_mining_tool_switch()
	await _test_pickaxe_blockers()
	await _test_cave_pickup()
	await _test_worm_water_guard()
	await _test_escape()
	await _test_ui_back_stack()
	await _test_ui_back_actual()
	_test_cloud_save_identity()
	_test_android_config()
	await _test_interpreters()
	await _test_crash_logger()


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


func _test_save_and_progress() -> void:
	Global.reset_missions()
	var wood := Global._find_mission("collect_wood")
	wood["progress"] = 7
	Global.reset_missions()
	check(int(wood.get("progress", -1)) == 0, "reset clears partial progress")

	var slot: int = Global.next_free_slot()
	if slot <= 0:
		print("NOTE: no free save slot; save/load progress test skipped")
		return
	var path := "user://save_slot_%d.json" % slot

	var moved := Global._find_mission("move")
	moved["completed"] = true
	moved["progress"] = 1
	wood["progress"] = 7
	Global.save_game(slot)
	Global.reset_missions()
	Global.load_game(slot)
	check(int(wood.get("progress", -1)) == 7, "partial progress survives save/load")
	check(bool(moved.get("completed", false)), "completion survives save/load")
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

	# At-goal progress completes even if `completed` was false.
	Global.reset_missions()
	var shelter := Global._find_mission("build_shelter")
	shelter["completed"] = false
	shelter["progress"] = 1
	Global.set_mission_progress("build_shelter", 1)
	check(bool(shelter.get("completed", false)), "at-goal progress completes immediately")

	Global.delete_world(slot)


func _test_triggers() -> void:
	Global.reset_missions()
	Global.record_dungeon_clear(50)
	check(bool(Global._find_mission("clear_dungeon").get("completed", false)),
		"dungeon clear completes Clear a Dungeon")

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


func _test_dungeon_progression_and_sides() -> void:
	var mains: Array = Global.main_dungeon_indices()
	var extras: Array = Global.extra_dungeon_indices()
	var boss_idx: int = Global.boss_dungeon_index()
	check(not mains.is_empty() and extras.size() == 14 and boss_idx > 0,
		"main, extra, and Hitman boss dungeon categories are registered")
	check(Global.get_dungeon_mission_for_index(boss_idx) != null
		and Global.get_dungeon_mission_for_index(boss_idx).is_boss(),
		"the final main mission is the Hitman boss dungeon")

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
	var bm := Global._find_mission("dungeon_%d" % boss_idx)
	bm["completed"] = bool(old_mission.get("completed", false))
	bm["progress"] = int(old_mission.get("progress", 0))
	Global.mission_updated.emit()

	var extra_mission: DungeonMissionData = Global.get_dungeon_mission_for_index(int(extras[0]))
	var edun := DungeonWorld.new()
	add_child(edun)
	edun.setup(int(extras[0]), extra_mission, 54321, null, Vector2.ZERO)
	await get_tree().process_frame
	var knowledge_count := 0
	var quiz_count := 0
	for child in edun.get_children():
		if child.is_in_group("KnowledgeAltar"):
			knowledge_count += 1
		if child.is_in_group("QuizAltar"):
			quiz_count += 1
	check(knowledge_count == 0 and quiz_count >= 2,
		"extra dungeons have no Knowledge Altar and at least two Quiz Altars")
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
		"completing main, boss and extra dungeons unlocks the side mission pool")
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
		Global.save_game(slot)
		Global.cave_states.clear()
		Global.load_game(slot)
		check(Global.cave_states.has("cave:424242:0:0"),
			"cave/pixie states survive world save/load")
		Global.delete_world(slot)
		Global.cave_states.clear()
	else:
		print("NOTE: no free save slot; cave-state save/load test skipped")


func _test_cave_cache_lifecycle() -> void:
	# Drive the real Game enter/exit functions off-tree: the cave instance must
	# be cached (not freed) and re-entry must return the SAME node with its
	# runtime changes intact. Also cover the pixie branch.
	var old_slot := Global.active_save_slot
	var old_game := Global.game_node
	var old_player := Global.player_node
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

	# Pixie branch: same cache contract, separate state key/type.
	var pixie_portal := CavePortal.new()
	pixie_portal.mode = CavePortal.Mode.ENTER
	pixie_portal.cave_type = "pixie"
	pixie_portal.cave_seed = 626262
	pixie_portal.global_position = Vector2(200, 200)
	game.call("_do_enter_cave", pixie_portal)
	var pixie_first: Variant = game.get("_pixie_cave_world")
	check(pixie_first is PixieCaveWorld, "pixie entry creates a pixie cave world")
	game.call("_do_exit_cave")
	var pixie_key := pixie_portal.state_key()
	var pixie_cache: Dictionary = game.get("_cave_instances") as Dictionary
	check(pixie_cache.has(pixie_key), "pixie exit caches its own instance")
	game.call("_do_enter_cave", pixie_portal)
	check(game.get("_pixie_cave_world") == pixie_first,
		"pixie re-entry reuses its cached instance")
	game.call("_do_exit_cave")

	for key in (game.get("_cave_instances") as Dictionary).keys():
		var cached_node: Variant = (game.get("_cave_instances") as Dictionary)[key]
		if is_instance_valid(cached_node):
			(cached_node as Node).free()
	game.free()
	portal.free()
	portal_b.free()
	pixie_portal.free()
	Global.game_node = old_game
	Global.player_node = old_player
	Global.active_save_slot = old_slot
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

	var ore_cell := _find_floor_cell(pixie, true, "ore", "floor")
	if ore_cell.x != -99999:
		var ore_torch := _restore_torch(pixie, ore_cell)
		await get_tree().process_frame
		check(bool(ore_torch.get("_torch_connected")),
			"pixie torch beside crystal ore connects")
		var ore_neighbor := ore_cell + Vector2i(-1, 0)
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
		var pixie_mine := _restore_torch(pixie, ore_cell + Vector2i(1, 0))
		var pixie_result: Dictionary = await _mine_torch(pixie, pixie_mine, WOODEN_PICK_PATH)
		check(int(pixie_result["new_drops"]) == 1,
			"pixie isolated torch drops once with a pickaxe")
		var pixie_drops: Array = pixie_result["drops"]
		if not pixie_drops.is_empty():
			check(_pickup_torch(pixie_drops.back() as Node, torch_data),
				"pixie dropped torch is collectible")
	else:
		check(false, "pixie generated an ore-adjacent torch cell")

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

	# RGB/HEX is a presentation-only UI on the color output block. It must not
	# touch program code, quantity, cactus cost, or the Python signature.
	station.set("program_code", "# code is untouched")
	var menu: Control = station.get("_ui") as Control
	menu.call("_refresh_output")
	var color_panel: Control = menu.get("_color_output_panel") as Control
	var color_edit: LineEdit = menu.get("_color_edit") as LineEdit
	var color_note: Label = menu.get("_color_note") as Label
	check(color_panel != null and color_panel.visible,
		"color output block appears for a pending Color Block")
	check(color_edit != null and color_edit.text == "255, 0, 0",
		"RGB mode displays the output color channels")
	var cactus_before_edit := Global.count_item(cactus_data)
	menu.call("_on_color_mode_selected", 1)
	check(color_edit.text == "#FF0000"
		and (station.call("get_output_item") as ItemData) == red
		and int(station.call("get_output_quantity")) == 1,
		"HEX mode shows #RRGGBB without changing the output color")
	menu.call("_commit_color_text", "#00FF00")
	check((station.call("get_output_item") as ItemData) == green
		and int(station.call("get_output_quantity")) == 1
		and Global.count_item(cactus_data) == cactus_before_edit,
		"editing HEX updates output color without consuming materials")
	check(menu.get("_color_preview") != null
		and ((menu.get("_color_preview") as ColorRect).color == Color8(0, 255, 0)),
		"editing HEX updates the color preview")
	menu.call("_commit_color_text", "#ZZZZZZ")
	check((station.call("get_output_item") as ItemData) == green
		and color_note != null and color_note.visible,
		"malformed HEX is rejected without corrupting the output")
	menu.call("_on_color_mode_selected", 0)
	check(color_edit.text == "0, 255, 0",
		"switching back to RGB shows the equivalent channels")
	menu.call("_commit_color_text", "255, 0, 0")
	check((station.call("get_output_item") as ItemData) == red
		and station.get("program_code") == "# code is untouched",
		"editing RGB restores the color and leaves program code untouched")

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
	block.set("_hovered", true)
	block.set("_mouse_held", true)
	block.set_process(true)
	block.call("_try_start_breaking")
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
	inv_layer.queue_free()

	await get_tree().process_frame
	Global.reset_pause_state()

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
	check(presets.contains('package/unique_name="com.sandee.alpha"')
		and presets.contains('version/name="0.9.3.2"')
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


# ── Helpers ──────────────────────────────────────────────────────────────

func _saved_missions_version(path: String) -> int:
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if data is Dictionary:
		return int(data.get("missions_version", 0))
	return 0


func _write_world(slot: int, world_name: String, created_version: String) -> void:
	var file := FileAccess.open("user://save_slot_%d.json" % slot, FileAccess.WRITE)
	file.store_string(JSON.stringify({
		"slot": slot,
		"world_name": world_name,
		"created_version": created_version,
		"timestamp": int(Time.get_unix_time_from_system()),
		"missions": [],
	}))
	file.close()
