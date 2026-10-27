extends Node

# ── Contextual cursor director ──────────────────────────────────────
# Applies the approved 24x24 cursor concepts on desktop. The cursor follows the
# same interaction rules as the user-facing controls: it only changes over a
# real world target, never over UI, and it falls back to the normal OS arrow
# when the world is paused or a modal is open.
#
# Android is intentionally excluded: touch has no pointer, and changing the
# custom cursor there would be meaningless.
#
# Hotspots are the upper-left pointer notch used by every draft sprite.

const CURSOR_DIR := "res://sprites/ui/cursors/"
const SCAN_INTERVAL := 0.10
const HOTSPOT := Vector2(2, 2)

const CURSOR_FILES := {
	"movement": CURSOR_DIR + "movement.png",
	"chest": CURSOR_DIR + "open_chest.png",
	"crafting": CURSOR_DIR + "open_crafting.png",
	"furnace": CURSOR_DIR + "open_furnace.png",
	"color": CURSOR_DIR + "open_color_crafter.png",
	"generic": CURSOR_DIR + "generic_interact.png",
}

var _scan_accum: float = 0.0
var _current: String = ""
var _textures: Dictionary = {}

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if Global.is_mobile() or DisplayServer.get_name() == "headless":
		set_process(false)
		return
	_set_cursor("default")

func _exit_tree() -> void:
	if not Global.is_mobile() and DisplayServer.get_name() != "headless":
		Input.set_custom_mouse_cursor(null, Input.CURSOR_ARROW, Vector2.ZERO)

func _process(delta: float) -> void:
	_scan_accum += delta
	if _scan_accum < SCAN_INTERVAL:
		return
	_scan_accum = 0.0
	_refresh_cursor()

func _refresh_cursor() -> void:
	var vp := get_viewport()
	if vp == null:
		_set_cursor("default")
		return
	if Global.any_ui_open() or Global.pause_menu_open or Global.block_mode \
			or get_tree().paused \
			or not is_instance_valid(Global.player_node) \
			or not is_instance_valid(Global.world_node):
		_set_cursor("default")
		return
	var screen_pos: Vector2 = vp.get_mouse_position()
	if not vp.get_visible_rect().has_point(screen_pos):
		_set_cursor("default")
		return
	# Hovering any HUD/panel uses the platform cursor, not a world context.
	if Global.is_point_over_ui(screen_pos):
		_set_cursor("default")
		return
	var world_pos: Vector2 = vp.get_canvas_transform().affine_inverse() * screen_pos
	_set_cursor(_kind_at(world_pos))

func _kind_at(world_pos: Vector2) -> String:
	# Storage/interaction classes take priority over the generic hand.
	for node in get_tree().get_nodes_in_group("Chest"):
		if _cursor_over(node, world_pos):
			return "chest"
	for node in get_tree().get_nodes_in_group("CraftingStation"):
		if _cursor_over(node, world_pos):
			return "crafting"
	for node in get_tree().get_nodes_in_group("ColorCrafter"):
		if _cursor_over(node, world_pos):
			return "color"
	for node in get_tree().get_nodes_in_group("TouchInteractable"):
		if not _cursor_over(node, world_pos):
			continue
		var data: Variant = node.get("item_data")
		var item_name: String = ""
		if data is ItemData:
			item_name = (data as ItemData).item_name.to_lower()
		if item_name.contains("furnace"):
			return "furnace"
		return "generic"

	# Plain-click blocks: doors and bonfires.
	for node in get_tree().get_nodes_in_group("PlainClickBlock"):
		if _cursor_over(node, world_pos):
			return "generic"

	# Point-and-click objects whose click surface is a simple nearby area.
	if _group_near("WorldWaypoint", world_pos, 260.0):
		return "generic"
	if _group_near("KnowledgeAltar", world_pos, 64.0):
		return "generic"
	if _group_near("QuizAltar", world_pos, 64.0):
		return "generic"
	if _group_near("TutorialNPC", world_pos, 56.0):
		return "generic"
	if _group_near("LuaNPC", world_pos, 56.0):
		return "generic"

	for node in get_tree().get_nodes_in_group("CavePortal"):
		if _nearby_ok(node) and node.has_method("_click_is_on_entrance") \
				and bool(node.call("_click_is_on_entrance")):
			return "generic"
	for node in get_tree().get_nodes_in_group("DungeonPortal"):
		if _nearby_ok(node) and node.has_method("_click_is_on_door") \
				and bool(node.call("_click_is_on_door")):
			return "generic"
	return "movement"

func _cursor_over(node: Variant, world_pos: Vector2) -> bool:
	if node == null or not is_instance_valid(node) or not (node is Node2D):
		return false
	var n := node as Node2D
	if not n.is_visible_in_tree():
		return false
	var nearby: Variant = n.get("_player_nearby")
	if nearby != null and not bool(nearby):
		return false
	if n.has_method("_cursor_over"):
		return bool(n.call("_cursor_over", world_pos))
	return n.global_position.distance_to(world_pos) <= 24.0

func _group_near(group: String, world_pos: Vector2, radius: float) -> bool:
	for node in get_tree().get_nodes_in_group(group):
		if node == null or not is_instance_valid(node) or not (node is Node2D):
			continue
		var n := node as Node2D
		if n.is_visible_in_tree() and _nearby_ok(n) \
				and n.global_position.distance_to(world_pos) <= radius:
			return true
	return false

func _nearby_ok(node: Variant) -> bool:
	if node == null or not is_instance_valid(node):
		return false
	var nearby: Variant = node.get("_player_nearby")
	return nearby == null or bool(nearby)

func _set_cursor(kind: String) -> void:
	if kind == _current:
		return
	_current = kind
	if kind == "default" or not CURSOR_FILES.has(kind):
		Input.set_custom_mouse_cursor(null, Input.CURSOR_ARROW, Vector2.ZERO)
		return
	if not _textures.has(kind):
		var path: String = str(CURSOR_FILES[kind])
		_textures[kind] = load(path) if ResourceLoader.exists(path) else null
	var tex: Texture2D = _textures[kind] as Texture2D
	if tex == null:
		Input.set_custom_mouse_cursor(null, Input.CURSOR_ARROW, Vector2.ZERO)
		return
	Input.set_custom_mouse_cursor(tex, Input.CURSOR_ARROW, HOTSPOT)
