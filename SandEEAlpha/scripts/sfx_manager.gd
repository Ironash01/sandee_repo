extends Node

# ── SandEE SFX manager ─────────────────────────────────────────────
# Autoloaded as `SFX`. Owns every one-shot and looping sound effect, keeps the
# Master/Music/SFX bus layout meaningful, and exposes a tiny cue-based API so
# gameplay code never has to know a file path.
#
# Cue list + selected primary files live in `res://sfx/sfx_manifest.json`,
# generated from design_drafts/sfx_audio/open_source_8bit/cue_source_map.csv.
# `sfx_hotbar` is deliberately absent: hotbar selection stays silent.

const MANIFEST_PATH := "res://sfx/sfx_manifest.json"
const SFX_BUS := "SFX"
const MUSIC_BUS := "Music"
const MAX_PLAYERS_PER_KIND := 24

var _cues: Dictionary = {}
var _stream_cache: Dictionary = {}
var _players: Array = []
var _players_2d: Array = []
var _loop_players: Dictionary = {}
var _last_played_ms: Dictionary = {}
var _warned_missing: Dictionary = {}
var _rng := RandomNumberGenerator.new()
var _low_health_active: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_rng.randomize()
	_ensure_buses()
	_load_manifest()
	_apply_volumes()
	_connect_global_signals()
	get_tree().node_added.connect(_on_node_added)
	call_deferred("_wire_existing_buttons")


# ── Public API ─────────────────────────────────────────────────────

## Play a one-shot cue. `pos` may be a Vector2 for spatial cues; omit it for UI.
## `variant` selects a specific primary file (useful when the files are distinct
## sub-events, e.g. save/load/delete), otherwise a random variant is used.
func play(cue: String, pos: Variant = null, volume_db: float = 0.0,
		pitch: float = 1.0, variant: int = -1) -> void:
	var data: Dictionary = _cue(cue)
	if data.is_empty():
		return
	if bool(data.get("loop", false)):
		play_loop(cue, pos, "", volume_db)
		return
	var now: int = Time.get_ticks_msec()
	var min_ms: int = int(data.get("min_interval_ms", 0))
	if min_ms > 0 and now - int(_last_played_ms.get(cue, -1000000)) < min_ms:
		return
	_last_played_ms[cue] = now

	var files: Array = data.get("files", [])
	if files.is_empty():
		return
	var idx: int = variant if variant >= 0 and variant < files.size() else _rng.randi_range(0, files.size() - 1)
	var stream: AudioStream = _stream_for(str(files[idx]), cue)
	if stream == null:
		return

	var spatial: bool = bool(data.get("spatial", true)) and pos is Vector2
	var max_voices: int = maxi(1, int(data.get("max_voices", 4)))
	_limit_cue_voices(cue, max_voices)

	var player: Node = _get_voice(spatial)
	if player == null:
		return
	player.set_meta("cue", cue)
	player.set_meta("started_ms", now)
	var vol: float = float(data.get("volume_db", 0.0)) + volume_db
	var vary: float = float(data.get("pitch_variation", 0.0))
	var final_pitch: float = clampf(pitch * (1.0 + _rng.randf_range(-vary, vary)), 0.35, 2.5)
	if spatial:
		var p2d := player as AudioStreamPlayer2D
		p2d.stream = stream
		p2d.volume_db = vol
		p2d.pitch_scale = final_pitch
		p2d.global_position = pos as Vector2
		p2d.play()
	else:
		var p := player as AudioStreamPlayer
		p.stream = stream
		p.volume_db = vol
		p.pitch_scale = final_pitch
		p.play()


func play_ui(cue: String, variant: int = -1, volume_db: float = 0.0) -> void:
	play(cue, null, volume_db, 1.0, variant)


func play_at(cue: String, pos: Vector2, variant: int = -1, volume_db: float = 0.0) -> void:
	play(cue, pos, volume_db, 1.0, variant)


## Start a looping cue. `key` lets independent owners share the same cue
## without stopping each other (e.g. one robot per key). Omit it for global
## beds such as cave ambience or weather.
func play_loop(cue: String, pos: Variant = null, key: String = "",
		volume_db: float = 0.0) -> void:
	var data: Dictionary = _cue(cue)
	if data.is_empty():
		return
	var loop_key: String = cue if key.is_empty() else cue + ":" + key
	var existing: Variant = _loop_players.get(loop_key)
	if existing is AudioStreamPlayer and is_instance_valid(existing) and (existing as AudioStreamPlayer).playing:
		return

	var files: Array = data.get("files", [])
	if files.is_empty():
		return
	var stream: AudioStream = _stream_for(str(files[0]), cue)
	if stream == null:
		return

	var player: AudioStreamPlayer = null
	if existing is AudioStreamPlayer and is_instance_valid(existing):
		player = existing as AudioStreamPlayer
	else:
		player = AudioStreamPlayer.new()
		player.name = "Loop_" + loop_key.replace(":", "_")
		player.bus = SFX_BUS
		player.process_mode = Node.PROCESS_MODE_ALWAYS
		add_child(player)
		_loop_players[loop_key] = player
	player.stream = stream
	player.volume_db = float(data.get("volume_db", 0.0)) + volume_db
	player.pitch_scale = 1.0
	player.play()


func stop_loop(cue: String, key: String = "") -> void:
	var loop_key: String = cue if key.is_empty() else cue + ":" + key
	var player: Variant = _loop_players.get(loop_key)
	if player is AudioStreamPlayer and is_instance_valid(player):
		(player as AudioStreamPlayer).stop()
	_loop_players.erase(loop_key)


func stop_all() -> void:
	for p in _players:
		if is_instance_valid(p):
			p.stop()
	for p in _players_2d:
		if is_instance_valid(p):
			p.stop()
	for key in _loop_players.keys():
		var lp: Variant = _loop_players[key]
		if lp is AudioStreamPlayer and is_instance_valid(lp):
			(lp as AudioStreamPlayer).stop()
	_loop_players.clear()
	_low_health_active = false


func has_cue(cue: String) -> bool:
	return _cues.has(cue)


func cue_count() -> int:
	return _cues.size()


# ── Bus + manifest ─────────────────────────────────────────────────

func _ensure_buses() -> void:
	if AudioServer.get_bus_index("Master") == -1:
		AudioServer.add_bus(0)
		AudioServer.set_bus_name(0, "Master")
	for bus_name in [MUSIC_BUS, SFX_BUS]:
		if AudioServer.get_bus_index(bus_name) == -1:
			AudioServer.add_bus()
			var idx: int = AudioServer.bus_count - 1
			AudioServer.set_bus_name(idx, bus_name)
			AudioServer.set_bus_send(idx, "Master")


func _load_manifest() -> void:
	if not FileAccess.file_exists(MANIFEST_PATH):
		push_error("SFX manifest missing: " + MANIFEST_PATH)
		return
	var text: String = FileAccess.get_file_as_string(MANIFEST_PATH)
	var parsed: Variant = JSON.parse_string(text)
	if not (parsed is Dictionary):
		push_error("SFX manifest is not valid JSON")
		return
	var data: Dictionary = parsed as Dictionary
	var cues: Variant = data.get("cues", {})
	if not (cues is Dictionary):
		push_error("SFX manifest has no cues dictionary")
		return
	_cues = cues as Dictionary


func _apply_volumes() -> void:
	var master: float = float(Global.master_volume) if Global != null else 1.0
	var music: float = float(Global.music_volume) if Global != null else 1.0
	var sfx: float = float(Global.sfx_volume) if Global != null else 1.0
	AudioServer.set_bus_volume_db(0, linear_to_db(maxf(master, 0.0001)))
	var mi: int = AudioServer.get_bus_index(MUSIC_BUS)
	if mi != -1:
		AudioServer.set_bus_volume_db(mi, linear_to_db(maxf(music, 0.0001)))
	var si: int = AudioServer.get_bus_index(SFX_BUS)
	if si != -1:
		AudioServer.set_bus_volume_db(si, linear_to_db(maxf(sfx, 0.0001)))


func _cue(cue: String) -> Dictionary:
	var raw: Variant = _cues.get(cue)
	if raw is Dictionary:
		return raw as Dictionary
	if not _warned_missing.has(cue):
		_warned_missing[cue] = true
		push_warning("SFX cue not found: " + cue)
	return {}


func _stream_for(path: String, cue: String) -> AudioStream:
	var stream: AudioStream = _stream_cache.get(path) as AudioStream
	if stream == null:
		var res: Resource = load(path)
		if res is AudioStream:
			stream = res as AudioStream
			_stream_cache[path] = stream
		else:
			push_error("SFX file is not an AudioStream: " + path)
			return null
	var loop: bool = bool((_cue(cue)).get("loop", false))
	if stream is AudioStreamWAV:
		var wav := stream as AudioStreamWAV
		if loop:
			var frames: int = int(wav.get_length() * float(wav.mix_rate))
			wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
			wav.loop_begin = 0
			wav.loop_end = maxi(1, frames)
		else:
			wav.loop_mode = AudioStreamWAV.LOOP_DISABLED
	elif stream is AudioStreamOggVorbis:
		var ogg := stream as AudioStreamOggVorbis
		ogg.loop = loop
		ogg.loop_offset = 0.0
	return stream


# ── Voice pool ─────────────────────────────────────────────────────

func _get_voice(spatial: bool) -> Node:
	var pool: Array = _players_2d if spatial else _players
	for p in pool:
		if is_instance_valid(p) and not p.playing:
			return p
	if pool.size() < MAX_PLAYERS_PER_KIND:
		var p: Node = AudioStreamPlayer2D.new() if spatial else AudioStreamPlayer.new()
		p.name = ("SFX2D_" if spatial else "SFX_") + str(pool.size())
		p.bus = SFX_BUS
		p.process_mode = Node.PROCESS_MODE_ALWAYS
		if spatial:
			var p2d := p as AudioStreamPlayer2D
			p2d.max_distance = 1500.0
			p2d.attenuation = 1.0
			p2d.panning_strength = 0.6
		add_child(p)
		pool.append(p)
		if spatial:
			_players_2d = pool
		else:
			_players = pool
		return p
	# All voices busy: steal the oldest.
	var oldest: Variant = pool[0]
	var oldest_ms: int = int((oldest as Node).get_meta("started_ms", 0))
	for p in pool:
		var ms: int = int((p as Node).get_meta("started_ms", 0))
		if ms < oldest_ms:
			oldest_ms = ms
			oldest = p
	return oldest as Node


func _limit_cue_voices(cue: String, max_voices: int) -> void:
	var active: Array = []
	for p in _players:
		if is_instance_valid(p) and p.playing and str(p.get_meta("cue", "")) == cue:
			active.append(p)
	for p in _players_2d:
		if is_instance_valid(p) and p.playing and str(p.get_meta("cue", "")) == cue:
			active.append(p)
	while active.size() >= max_voices:
		var oldest: Variant = active[0]
		var oldest_ms: int = int((oldest as Node).get_meta("started_ms", 0))
		for p in active:
			var ms: int = int((p as Node).get_meta("started_ms", 0))
			if ms < oldest_ms:
				oldest_ms = ms
				oldest = p
		(oldest as Node).call("stop")
		active.erase(oldest)


# ── Global event wiring ────────────────────────────────────────────

func _connect_global_signals() -> void:
	_connect_signal("player_died", _on_player_died)
	_connect_signal("player_spawned", _on_player_spawned)
	_connect_signal("health_changed", _on_health_changed)
	_connect_signal("inventory_toggled", _on_inventory_toggled)
	_connect_signal("block_mode_changed", _on_block_mode_changed)
	_connect_signal("mission_completed", _on_mission_completed)
	_connect_signal("mission_star_earned", _on_mission_star)
	_connect_signal("knowledge_updated", _on_knowledge_updated)
	_connect_signal("bestiary_updated", _on_bestiary_updated)
	_connect_signal("dungeon_cleared", _on_dungeon_cleared)
	_connect_signal("dungeon_entered", _on_dungeon_entered)
	_connect_signal("dungeon_exited", _on_dungeon_exited)
	_connect_signal("cave_entered", _on_cave_entered)
	_connect_signal("cave_exited", _on_cave_exited)
	_connect_signal("day_started", _on_day_started)
	_connect_signal("night_started", _on_night_started)
	_connect_signal("snowstorm_changed", _on_snowstorm_changed)
	_connect_signal("game_saved", _on_game_saved)
	_connect_signal("world_loaded", _on_world_loaded)
	_connect_signal("world_deleted", _on_world_deleted)
	_connect_signal("cloud_status_changed", _on_cloud_status)
	_connect_signal("online_state_changed", _on_online_state)
	_connect_signal("account_context_changed", _on_account_context)


func _connect_signal(sig_name: String, callable: Callable) -> void:
	if not Global.has_signal(sig_name):
		return
	if not Global.is_connected(sig_name, callable):
		Global.connect(sig_name, callable)


func _player_pos() -> Vector2:
	var p: Node2D = Global.player_node as Node2D
	return p.global_position if p != null and is_instance_valid(p) else Vector2.ZERO


func _on_player_died(pos: Vector2) -> void:
	stop_loop("sfx_player_low_health")
	play("sfx_player_death", pos)


func _on_player_spawned(pos: Vector2) -> void:
	play("sfx_player_respawn", pos)


func _on_health_changed(value: float, max_value: float) -> void:
	var low: bool = max_value > 0.0 and value > 0.0 and value / max_value <= 0.3
	if low and not _low_health_active and not Global.player_is_dead:
		_low_health_active = true
		play_loop("sfx_player_low_health")
	elif not low and _low_health_active:
		_low_health_active = false
		stop_loop("sfx_player_low_health")


func _on_inventory_toggled(is_open: bool) -> void:
	play_ui("sfx_inventory_open_close", 0 if is_open else 1)


func _on_block_mode_changed(enabled: bool) -> void:
	play_ui("sfx_build_mode", 0 if enabled else 1)


func _on_mission_completed(_mission_id: String) -> void:
	play_ui("sfx_mission", 1)


func _on_mission_star(_reward_id: String) -> void:
	play_ui("sfx_mission", 1, -2.0)


func _on_knowledge_updated() -> void:
	play_ui("sfx_knowledge_bestiary", 0)


func _on_bestiary_updated() -> void:
	play_ui("sfx_knowledge_bestiary", 1)


func _on_dungeon_cleared(_index: int) -> void:
	play_ui("sfx_dungeon_clear")


func _on_dungeon_entered(_index: int) -> void:
	stop_loop("sfx_weather_wind")
	play_ui("sfx_dungeon_portal", 0)
	play_loop("sfx_dungeon_ambience")


func _on_dungeon_exited(_index: int) -> void:
	play_ui("sfx_dungeon_portal", 1)
	stop_loop("sfx_dungeon_ambience")
	play_loop("sfx_weather_wind")


func _on_cave_entered(_kind: String) -> void:
	stop_loop("sfx_weather_wind")
	play_ui("sfx_cave_travel", 0)
	play_loop("sfx_cave_ambience")


func _on_cave_exited(_kind: String) -> void:
	play_ui("sfx_cave_travel", 1)
	stop_loop("sfx_cave_ambience")
	play_loop("sfx_weather_wind")


func _on_day_started() -> void:
	play_ui("sfx_day_night", 0)


func _on_night_started() -> void:
	play_ui("sfx_day_night", 1)


func _on_snowstorm_changed(active: bool) -> void:
	if active:
		play_loop("sfx_snowstorm")
	else:
		stop_loop("sfx_snowstorm")


func _on_game_saved(_slot: int) -> void:
	play_ui("sfx_save_load", 0)


func _on_world_loaded(_slot: int) -> void:
	play_ui("sfx_save_load", 1)


func _on_world_deleted(_slot: int, _uid: String, _checksum: String) -> void:
	play_ui("sfx_save_load", 2)


func _on_cloud_status(_status: int) -> void:
	play_ui("sfx_account_cloud", 0, -3.0)


func _on_online_state() -> void:
	play_ui("sfx_account_cloud", 0, -3.0)


func _on_account_context(_id: String) -> void:
	play_ui("sfx_account_cloud", 1, -3.0)


# ── Generic UI buttons ─────────────────────────────────────────────
# One consistent click for every BaseButton. Hotbar slots are TextureRects, so
# `sfx_hotbar` remains untouched by this hook.

func _on_node_added(node: Node) -> void:
	if node is BaseButton:
		_wire_button(node as BaseButton)


func _wire_existing_buttons() -> void:
	if get_tree() == null:
		return
	_wire_button_tree(get_tree().root)


func _wire_button_tree(node: Node) -> void:
	if node is BaseButton:
		_wire_button(node as BaseButton)
	for child in node.get_children():
		_wire_button_tree(child)


func _wire_button(btn: BaseButton) -> void:
	if btn == null or not is_instance_valid(btn) or btn.has_meta("sfx_wired"):
		return
	btn.set_meta("sfx_wired", true)
	btn.pressed.connect(func() -> void:
		if is_instance_valid(btn) and btn.visible and not btn.disabled:
			play_ui("sfx_ui_interaction")
	)
