extends Node

# ── Minecraft-style ambient BGM ─────────────────────────────────────
# One persistent autoload across the title screen, overworld, caves and
# dungeons. Each context owns a small variation pool; a track is picked
# randomly, never repeated back-to-back, then the manager waits a randomised
# quiet gap before the next one. Context changes cross-fade instead of cutting.
#
# Volume is routed through a real "Music" bus so the existing Settings →
# Music Volume slider works. The player itself stays on Master.

const TRACKS: Dictionary = {
	"menu": [
		"res://bgm/main_menu.mp3",
	],
	"overworld_day": [
		"res://bgm/overworld_1.mp3",
		"res://bgm/overworld_2.mp3",
	],
	"overworld_night": [
		"res://bgm/overworld_night1.mp3",
		"res://bgm/overworld_night2.mp3",
	],
	"snowy": [
		"res://bgm/snowy.mp3",
	],
	"cave": [
		"res://bgm/cave1.mp3",
		"res://bgm/cave2.mp3",
	],
	# The four dungeon variations are the Minecraft-style random pool.
	"dungeon": [
		"res://bgm/dungeon_1.mp3",
		"res://bgm/dungeon_2.mp3",
		"res://bgm/dungeon_3.mp3",
		"res://bgm/dungeon_4.mp3",
	],
	"shelter": [
		"res://bgm/is_this_a_shelter.mp3",
	],
}

# Quiet time between tracks, in seconds. Minecraft leaves long silences between
# ambient pieces; shorter gaps are used for the menu and tense dungeon rooms.
const GAPS: Dictionary = {
	"menu": [12.0, 30.0],
	"overworld_day": [45.0, 115.0],
	"overworld_night": [45.0, 115.0],
	"snowy": [60.0, 140.0],
	"cave": [30.0, 75.0],
	"dungeon": [20.0, 60.0],
	"shelter": [35.0, 90.0],
}

const FADE_IN_SEC: float = 2.0
const FADE_OUT_SEC: float = 1.2
const SWITCH_GAP_SEC: float = 0.8
const WORLD_POLL_SEC: float = 4.0
const SILENT_DB: float = -40.0

var _player: AudioStreamPlayer = null
var _timer: Timer = null
var _rng := RandomNumberGenerator.new()
var _context: String = ""
var _last_track: String = ""
var _playing: bool = false
var _world_mode: bool = false
var _fade_tween: Tween = null
var _generation: int = 0
var _poll_accum: float = 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_rng.randomize()
	_ensure_music_bus()

	_player = AudioStreamPlayer.new()
	_player.name = "MusicPlayer"
	_player.bus = "Music"
	_player.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_player)
	_player.finished.connect(_on_track_finished)

	_timer = Timer.new()
	_timer.name = "NextTrackTimer"
	_timer.one_shot = true
	_timer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_timer)
	_timer.timeout.connect(_on_wait_finished)


func _ensure_music_bus() -> void:
	var idx: int = AudioServer.get_bus_index("Music")
	if idx == -1:
		AudioServer.add_bus()
		idx = AudioServer.bus_count - 1
		AudioServer.set_bus_name(idx, "Music")
		AudioServer.set_bus_send(idx, "Master")
	AudioServer.set_bus_volume_db(idx,
		linear_to_db(maxf(Global.music_volume, 0.0001)))


func _process(delta: float) -> void:
	# The world context is re-checked periodically so walking into snow, a
	# player-built shelter, or through day/night follows the music without a
	# scene transition. Menus/caves/dungeons set their context explicitly.
	if not _world_mode:
		return
	_poll_accum += delta
	if _poll_accum < WORLD_POLL_SEC:
		return
	_poll_accum = 0.0
	var want := current_world_context()
	if want != _context:
		play_context(want)


## Menu, cave and dungeon callers use this directly.
func play_context(context: String) -> void:
	if context.is_empty() or not TRACKS.has(context):
		return
	_world_mode = context != "menu"
	if context == _context and (_playing or _timer.time_left > 0.0):
		return
	_context = context
	_generation += 1
	var gen := _generation
	_timer.stop()
	if _fade_tween != null and _fade_tween.is_valid():
		_fade_tween.kill()
	if _playing:
		var fade := create_tween()
		fade.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
		_fade_tween = fade
		fade.tween_property(_player, "volume_db", SILENT_DB, FADE_OUT_SEC)
		fade.tween_callback(func() -> void:
			if gen != _generation:
				return
			_player.stop()
			_playing = false
			_schedule_switch(gen)
		)
	else:
		_schedule_switch(gen)


## Called by Game when the overworld is (re)entered and by the scene's first
## ready. Keeps the day/night/snow/shelter context current.
func play_overworld() -> void:
	_world_mode = true
	play_context(current_world_context())


func current_world_context() -> String:
	if Global.is_in_dungeon:
		return "dungeon"
	var world: Node = Global.world_node
	if world is CaveWorld or world is PixieCaveWorld:
		return "cave"
	var p: Node2D = Global.player_node as Node2D
	if Global.player_indoors:
		return "shelter"
	if p != null and world != null and world.has_method("is_snow_biome_at"):
		if bool(world.call("is_snow_biome_at", p.global_position)):
			return "snowy"
	return "overworld_day" if _is_daytime() else "overworld_night"


func _is_daytime() -> bool:
	var cycle: Node = Global.day_night_cycle
	if cycle != null and is_instance_valid(cycle) and cycle.has_method("is_daytime"):
		return bool(cycle.call("is_daytime"))
	# Before DayNightCycle enters the tree, use the persisted clock value.
	return Global.time_of_day < 0.58


func _schedule_switch(gen: int) -> void:
	if gen != _generation:
		return
	_timer.start(SWITCH_GAP_SEC)


func _on_wait_finished() -> void:
	if _context.is_empty():
		return
	_play_random()


func _play_random() -> void:
	var pool: Array = TRACKS.get(_context, []) as Array
	if pool.is_empty():
		return
	var path := _pick_track(pool)
	if path.is_empty():
		return
	var stream := load(path) as AudioStream
	if stream == null:
		_schedule_next()
		return
	_player.stop()
	_player.stream = stream
	_player.volume_db = SILENT_DB
	_player.play()
	_playing = true
	_last_track = path
	if _fade_tween != null and _fade_tween.is_valid():
		_fade_tween.kill()
	var fade := create_tween()
	fade.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_fade_tween = fade
	fade.tween_property(_player, "volume_db", 0.0, FADE_IN_SEC)


func _pick_track(pool: Array) -> String:
	var choices: Array = pool.duplicate()
	if choices.size() > 1 and not _last_track.is_empty():
		choices.erase(_last_track)
	if choices.is_empty():
		choices = pool.duplicate()
	return str(choices[_rng.randi_range(0, choices.size() - 1)])


func _on_track_finished() -> void:
	_playing = false
	_schedule_next()


func _schedule_next() -> void:
	if _context.is_empty():
		return
	var gap: Array = GAPS.get(_context, [45.0, 110.0]) as Array
	var lo: float = float(gap[0]) if gap.size() > 0 else 45.0
	var hi: float = float(gap[1]) if gap.size() > 1 else lo + 30.0
	_timer.start(_rng.randf_range(lo, maxf(lo, hi)))


func current_context() -> String:
	return _context


func current_track() -> String:
	return _last_track
