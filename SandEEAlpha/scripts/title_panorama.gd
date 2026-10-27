extends Node

# ── Title-screen dungeon panoramas ─────────────────────────────────────────
# The main menu background is built from the game's own themed dungeon rooms:
# one Lua Ancient Rune Sanctum capture and one Python Stonegate Foundry capture.
# Both are re-rolled on every launch (random mission, layout seed, room, and
# camera framing), then cycled with a fresh randomized interval.
#
# The generated textures live in a process-wide static cache so the sign-in
# screen and the title menu share the same panoramas for this launch. Nothing is
# written into a save slot, and the preview dungeons are never registered as
# Global.world_node.

signal panorama_ready(texture: Texture2D)

const CAPTURE_W: int = 1600
const CAPTURE_H: int = 480
const TILE_SIZE: float = 32.0
const CYCLE_MIN_SEC: float = 20.0
const CYCLE_MAX_SEC: float = 40.0
const PANORAMA_LANGUAGES: Array[String] = ["lua", "python"]

# Static process cache: a new game launch creates new random captures; menu
# reopen / UI-scale rebuild within the same launch reuses them.
static var _textures: Array = []
static var _texture_index: int = 0
static var _generation_started: bool = false

var _generating_self: bool = false
var _cycle_timer: Timer = null
var _announced: bool = false
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()


# The current captured texture, or null while the first random pair is still
# generating (menus show their plain fallback colour in the meantime).
func load_cached() -> Texture2D:
	if _textures.is_empty():
		return null
	return _textures[_texture_index] as Texture2D


func ensure_panorama() -> void:
	if _is_headless():
		return
	if not _textures.is_empty():
		_begin_cycle()
		if not _announced:
			_announced = true
			panorama_ready.emit(load_cached())
		return
	if _generation_started:
		return
	_generation_started = true
	_generating_self = true
	_run.call_deferred()


func _exit_tree() -> void:
	# If this menu closes before the deferred capture finishes, let the next
	# menu start a fresh attempt instead of leaving the static guard stuck.
	if _generating_self:
		_generation_started = false
		_generating_self = false
	if _cycle_timer != null and is_instance_valid(_cycle_timer):
		_cycle_timer.stop()


func _is_headless() -> bool:
	return DisplayServer.get_name() == "headless"


func _run() -> void:
	var generated: Array = await _generate_all()
	_generation_started = false
	_generating_self = false
	if generated.is_empty():
		return
	_textures = generated
	_texture_index = _rng.randi_range(0, _textures.size() - 1)
	_begin_cycle()
	_announced = true
	panorama_ready.emit(load_cached())


# ── Randomized cycling ─────────────────────────────────────────────────────
func _begin_cycle() -> void:
	if _textures.size() < 2:
		return
	if _cycle_timer == null or not is_instance_valid(_cycle_timer):
		_cycle_timer = Timer.new()
		_cycle_timer.one_shot = true
		_cycle_timer.process_mode = Node.PROCESS_MODE_ALWAYS
		_cycle_timer.timeout.connect(_on_cycle_timeout)
		add_child(_cycle_timer)
	if _cycle_timer.is_stopped():
		_schedule_next_cycle()


func _schedule_next_cycle() -> void:
	if _cycle_timer == null:
		return
	_cycle_timer.wait_time = _rng.randf_range(CYCLE_MIN_SEC, CYCLE_MAX_SEC)
	_cycle_timer.start()


func _on_cycle_timeout() -> void:
	if _textures.size() < 2:
		return
	_texture_index = (_texture_index + 1) % _textures.size()
	panorama_ready.emit(load_cached())
	_schedule_next_cycle()


# ── Capture generation ─────────────────────────────────────────────────────
func _generate_all() -> Array:
	var out: Array = []
	var saved_world: Node = Global.world_node
	for lang in PANORAMA_LANGUAGES:
		var tex: Texture2D = await _render_dungeon_panorama(lang)
		if tex != null:
			out.append(tex)
		await get_tree().process_frame
	Global.world_node = saved_world
	return out


func _missions_for_language(lang: String) -> Array:
	var out: Array = []
	for idx_value in Global.main_dungeon_indices():
		var idx: int = int(idx_value)
		if Global.dungeon_language(idx) != lang:
			continue
		if not Global.is_dungeon_mission_ready(idx):
			continue
		out.append(idx)
	return out


func _render_dungeon_panorama(lang: String) -> Texture2D:
	var options: Array = _missions_for_language(lang)
	if options.is_empty():
		return null
	var mission_index: int = int(options[_rng.randi_range(0, options.size() - 1)])
	var mission: DungeonMissionData = Global.get_dungeon_mission_for_index(mission_index)
	if mission == null:
		return null

	var vp := SubViewport.new()
	vp.size = Vector2i(CAPTURE_W, CAPTURE_H)
	vp.transparent_bg = false
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	vp.disable_3d = true
	add_child(vp)

	var dungeon := DungeonWorld.new()
	vp.add_child(dungeon)
	dungeon.setup(mission_index, mission, _rng.randi(), null, Vector2.ZERO)
	# The panorama is an art shot, not a combat preview. Hide hazards and enemies
	# so the themed masonry and architecture stay readable under the menu scrim.
	for group_name in ["DungeonTrap", "DungeonFlare", "Hitman", "Mob"]:
		for node in get_tree().get_nodes_in_group(group_name):
			if node is CanvasItem and is_instance_valid(node) and dungeon.is_ancestor_of(node):
				(node as CanvasItem).visible = false

	# Pick a real room and frame the themed architecture. A modest random zoom
	# gives each launch a different wide shot without cutting the room apart.
	var rooms: Array = []
	for room_value in [dungeon.generator.entrance_room,
			dungeon.generator.knowledge_room, dungeon.generator.quiz_room]:
		if not (room_value as Dictionary).is_empty():
			rooms.append(room_value)
	for room_value in dungeon.generator.bonus_rooms:
		rooms.append(room_value)
	var room: Dictionary = rooms[_rng.randi_range(0, rooms.size() - 1)] as Dictionary
	var p: Vector2i = room.get("pos", Vector2i.ZERO)
	var size: Vector2i = room.get("size", Vector2i(4, 4))
	var focus: Vector2 = dungeon.grid_to_world(p + size / 2)
	var cam := Camera2D.new()
	cam.position = focus + Vector2(0.0, -TILE_SIZE * 0.35)
	var zoom: float = _rng.randf_range(1.65, 1.95)
	cam.zoom = Vector2(zoom, zoom)
	vp.add_child(cam)
	cam.make_current()

	# Let the scene, lighting and animated architecture settle before capture.
	for _frame in range(4):
		await get_tree().process_frame
	await RenderingServer.frame_post_draw

	var tex: Texture2D = null
	if vp.get_texture() != null:
		var img: Image = vp.get_texture().get_image()
		if img != null and img.get_width() > 0 and img.get_height() > 0:
			tex = ImageTexture.create_from_image(img)

	remove_child(vp)
	vp.queue_free()
	return tex
