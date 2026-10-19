extends Node

# ── Title-screen panorama ───────────────────────────────────────────
# Renders a small, DETERMINISTIC preview of SandEE's own procedural world and
# uses the capture as the title-screen background.
#
# Reuses the REAL generator (scenes/world_gen.tscn) inside a private SubViewport
# — no separate terrain generator. Isolation is explicit:
#   • the preview world is never registered as Global.world_node (the reference
#     is snapshotted and restored around the run),
#   • it is never written to a save slot, so it can never be loaded or modified
#     as a player world,
#   • it lives in its own SubViewport that is freed when the capture is done.
#
# Storage (user:// — the project's existing convention for saves/config):
#   user://title_world.json     { "seed": <int>, "panorama": "user://title_panorama.png" }
#   user://title_panorama.png   the cached capture
# The seed is rolled once and persisted, so the preview is reproducible; the
# cached PNG is reused on every later launch and only regenerated when it is
# missing or unreadable. Generation happens on a DEFERRED frame, so the main
# menu is never blocked waiting for it.

signal panorama_ready(texture: Texture2D)

const STATE_PATH: String    = "user://title_world.json"
const PANORAMA_PATH: String = "user://title_panorama.png"
const WORLD_SCENE: String   = "res://scenes/world_gen.tscn"
# A small preview is plenty for a background and keeps generation quick. The
# capture is deliberately WIDE (a 10:3 strip) so the title screen can PAN across
# the landscape — a square-ish image would have nothing to travel over.
const PREVIEW_TILES: int = 160
const CAPTURE_W: int = 1600
const CAPTURE_H: int = 480
# Give up waiting for generation after this long and fall back gracefully.
const GENERATE_TIMEOUT_SEC: float = 30.0

var _busy: bool = false

# The cached panorama, or null when there is none usable (missing, unreadable or
# invalid) — the caller then shows its plain fallback background.
func load_cached() -> Texture2D:
	if not FileAccess.file_exists(PANORAMA_PATH):
		return null
	var img: Image = Image.load_from_file(PANORAMA_PATH)
	if img == null or img.get_width() <= 0 or img.get_height() <= 0:
		return null
	return ImageTexture.create_from_image(img)

# The recorded preview seed, rolled and PERSISTED on first use so the same
# preview world can always be recreated.
func preview_seed() -> int:
	var st: Dictionary = _read_state()
	if st.has("seed"):
		return int(st["seed"])
	var seed_value: int = int(randi())
	st["seed"] = seed_value
	st["panorama"] = PANORAMA_PATH
	_write_state(st)
	return seed_value

func panorama_path() -> String:
	return PANORAMA_PATH

func _read_state() -> Dictionary:
	if not FileAccess.file_exists(STATE_PATH):
		return {}
	var f := FileAccess.open(STATE_PATH, FileAccess.READ)
	if f == null:
		return {}
	var d = JSON.parse_string(f.get_as_text())
	f.close()
	return d if d is Dictionary else {}

func _write_state(state: Dictionary) -> void:
	var f := FileAccess.open(STATE_PATH, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify(state))
	f.close()

# Renders the panorama on a later frame if there isn't a usable cached one.
# Never blocks the menu, and never runs twice at once.
func ensure_panorama() -> void:
	if _busy:
		return
	if load_cached() != null:
		return   # cached — nothing to do
	if _is_headless():
		return   # no renderer to capture with (headless / dummy renderer)
	_busy = true
	_run.call_deferred()

func _is_headless() -> bool:
	return DisplayServer.get_name() == "headless"

func _run() -> void:
	var tex: Texture2D = await _render_panorama()
	_busy = false
	if tex != null:
		panorama_ready.emit(tex)

func _render_panorama() -> Texture2D:
	var scene: PackedScene = load(WORLD_SCENE) as PackedScene
	if scene == null:
		return null

	# Snapshot the live world reference: world_gen.tscn registers itself as
	# Global.world_node in _ready, which must not leak into the real game.
	var saved_world: Node = Global.world_node

	var vp := SubViewport.new()
	vp.size = Vector2i(CAPTURE_W, CAPTURE_H)
	vp.transparent_bg = false
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	vp.disable_3d = true

	var world: Node2D = scene.instantiate() as Node2D
	if world == null:
		vp.free()
		Global.world_node = saved_world
		return null
	# Small preview grid + a recorded seed so the framing is reproducible.
	world.set("width", PREVIEW_TILES)
	world.set("height", PREVIEW_TILES)
	world.set("random_seed", preview_seed())

	var cam := Camera2D.new()
	cam.zoom = Vector2(0.5, 0.5)   # wide shot
	vp.add_child(world)
	vp.add_child(cam)
	cam.make_current()
	add_child(vp)

	# Wait for world-gen (bounded), then let a frame render before capturing.
	var done := [false]
	if world.has_signal("generation_complete"):
		world.connect("generation_complete", func() -> void: done[0] = true)
	var waited := 0.0
	while not done[0] and waited < GENERATE_TIMEOUT_SEC and is_inside_tree():
		await get_tree().process_frame
		waited += 0.05
	if is_inside_tree():
		await RenderingServer.frame_post_draw

	var tex: Texture2D = null
	var img: Image = null
	if vp.get_texture() != null:
		img = vp.get_texture().get_image()
	if img != null and img.get_width() > 0 and img.get_height() > 0:
		var err := img.save_png(PANORAMA_PATH)
		if err == OK:
			tex = ImageTexture.create_from_image(img)

	# Tear the preview down and restore the real world reference.
	remove_child(vp)
	vp.queue_free()
	Global.world_node = saved_world
	return tex
