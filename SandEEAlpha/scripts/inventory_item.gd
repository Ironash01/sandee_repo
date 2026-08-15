@tool
extends Node2D

@export var item_data: ItemData

var scene_path: String = "res://scenes/ui/InventoryItem.tscn"

@onready var icon_sprite: Sprite2D = $Sprite2D

var player_in_range: bool = false
var npc_in_range:    Node  = null   # LuaNPC that is close enough to collect

var quantity: int = 1
var _qty_label: Label

# ── Wobble ────────────────────────────────────────────────────────
const WOBBLE_SPEED:      float = 3.0   # rotations per second (radians)
const WOBBLE_AMPLITUDE:  float = 0.18  # radians (~10°)
const DROP_SCALE:        float = 0.55  # dropped items are smaller than full size
var   _wobble_time:      float = 0.0

# ── Despawn ───────────────────────────────────────────────────────
const DESPAWN_TIME:       float = 300.0  # 5 minutes on the ground
const DESPAWN_BLINK_TIME: float = 3.0    # flash before vanishing
const DESPAWN_BLINK_FREQ: float = 8.0    # flashes per second
var   _despawn_elapsed:   float = 0.0

func _ready() -> void:
	# Smaller scale for dropped items in the world
	scale = Vector2(DROP_SCALE, DROP_SCALE)
	# Random phase offset so items don't all wobble in sync
	_wobble_time = randf_range(0.0, TAU)

	if not Engine.is_editor_hint():
		if item_data != null:
			icon_sprite.texture = item_data.icon
		_qty_label = Label.new()
		_qty_label.add_theme_font_size_override("font_size", 12)
		_qty_label.add_theme_color_override("font_color", Color(1, 1, 1, 1))
		_qty_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1))
		_qty_label.add_theme_constant_override("outline_size", 3)
		_qty_label.position = Vector2(6, 6)
		_qty_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_qty_label)
		_update_qty_label()
		# Never spawn resting inside a placed block or solid wall. Deferred so
		# the caller's global_position assignment (which happens after
		# add_child in some drop paths) is already applied when the initial
		# nudge runs.
		_repel_from_blocks.call_deferred()

func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		if item_data != null:
			icon_sprite.texture = item_data.icon
		return

	# Wobble rotation
	_wobble_time += delta * WOBBLE_SPEED
	rotation = sin(_wobble_time) * WOBBLE_AMPLITUDE

	_despawn_elapsed += delta
	if _despawn_elapsed >= DESPAWN_TIME:
		queue_free()
		return
	if _despawn_elapsed >= DESPAWN_TIME - DESPAWN_BLINK_TIME:
		modulate.a = 1.0 if int(_despawn_elapsed * DESPAWN_BLINK_FREQ) % 2 == 0 else 0.15

	_repel_from_blocks()

	if player_in_range:
		pickup_item()

# ── Player pickup ─────────────────────────────────────────────────
func pickup_item() -> void:
	if item_data == null:
		return
	if Global.add_item({"quantity": quantity, "data": item_data}):
		queue_free()

# ── NPC pickup — called directly by LuaNPC after interact ─────────
func npc_pickup(npc: Node) -> bool:
	if item_data == null:
		return false
	# Set the item directly on LuaState so Lua can read held_item next run
	var lua_state: Node = npc.get_node_or_null("LuaState")
	if lua_state == null:
		return false
	lua_state.set("held_item", item_data.item_name)
	lua_state.set("held_item_quantity", 1)
	queue_free()
	return true

func set_item_data(data: ItemData, qty: int = 1) -> void:
	item_data = data
	quantity  = max(qty, 1)
	if icon_sprite:
		icon_sprite.texture = data.icon
	_update_qty_label()

func _update_qty_label() -> void:
	if _qty_label == null:
		return
	_qty_label.visible = quantity > 1
	_qty_label.text    = str(quantity)

func _on_area_2d_body_entered(body: Node2D) -> void:
	if body.is_in_group("Player"):
		player_in_range = true

func _on_area_2d_body_exited(body: Node2D) -> void:
	if body.is_in_group("Player"):
		player_in_range = false

# ── Block repulsion ───────────────────────────────────────────────
# Dropped items are pushed out of anything solid so they can't rest on
# top of it: every StaticBody2D (placed blocks, chests, altars, trees,
# grass — found via a physics-space query so nothing is missed no matter
# how the node is tracked) AND solid wall tiles (cave_world.gd /
# dungeon_world.gd build their shared tilesets with per-tile collision
# polygons, so a _tilemap cell whose TileData carries a collision
# polygon is treated as solid). The item's resting circle vs each solid
# rect is checked from _process (see _repel_from_blocks). Resolving an
# overlap always exits a block to the side or BELOW it, never upward, so
# an item is never left sitting on top of a block.
const ITEM_RADIUS:      float = 10.0   # dropped item's collision radius (px)
const BLOCK_SCAN_RADIUS: float = 48.0  # only solids this close get a full rect check
const REPEL_PASSES:     int   = 3      # resolve up to this many overlaps per frame

func _repel_from_blocks() -> void:
	var rects := _collect_repel_rects()
	if rects.is_empty():
		return
	for _pass in range(REPEL_PASSES):
		var best_rect: Rect2 = Rect2()
		var best_depth: float = 0.0
		for r: Variant in rects:
			var rect: Rect2 = r as Rect2
			var depth: float = ITEM_RADIUS - global_position.distance_to(_closest_rect_point(rect, global_position))
			if depth > best_depth:
				best_depth = depth
				best_rect = rect
		if best_depth <= 0.0:
			break
		global_position = _resolve_rect_repel(best_rect, global_position, ITEM_RADIUS)

func _collect_repel_rects() -> Array:
	var rects: Array = []
	var world: Node = Global.world_node
	if world == null:
		return rects
	# Every solid StaticBody2D within scan range, found through the physics
	# server instead of a tracked-dictionary walk — the player/mobs are
	# CharacterBody2D (filtered out) and tilemap walls are TileMapLayer
	# bodies (handled per-cell below).
	var space := get_world_2d().direct_space_state
	if space != null:
		var query := PhysicsShapeQueryParameters2D.new()
		var scan := CircleShape2D.new()
		scan.radius = BLOCK_SCAN_RADIUS
		query.shape = scan
		query.transform = Transform2D(0.0, global_position)
		query.collision_mask = 1
		query.collide_with_areas = false
		query.collide_with_bodies = true
		for hit in space.intersect_shape(query, 16):
			var body: Variant = hit.get("collider")
			if body is StaticBody2D and is_instance_valid(body):
				rects.append(_block_collision_rect(body as Node))
	# Solid wall tiles (cave/dungeon) — scanned per-cell because a TileMapLayer
	# body doesn't expose individual tile rects.
	var tilemap: Variant = world.get("_tilemap")
	if tilemap is TileMapLayer:
		var tml: TileMapLayer = tilemap as TileMapLayer
		var cell: Vector2i = tml.local_to_map(tml.to_local(global_position))
		for dx in range(-1, 2):
			for dy in range(-1, 2):
				var c: Vector2i = cell + Vector2i(dx, dy)
				var td: TileData = tml.get_cell_tile_data(c)
				if td == null or td.get_collision_polygons_count(0) == 0:
					continue
				var center: Vector2 = tml.to_global(tml.map_to_local(c))
				rects.append(Rect2(center - Vector2(16.0, 16.0), Vector2(32.0, 32.0)))
	return rects

func _resolve_rect_repel(rect: Rect2, item_pos: Vector2, radius: float) -> Vector2:
	# Push the item out of the block to the SIDE or BELOW it — never upward,
	# so it can't be left resting on top of a block. The exit points toward
	# the player (the usual drop source), which drops the item beside the
	# block at the player's feet; without a player, default to the left.
	var target: Vector2 = rect.get_center() + Vector2(0.0, 1.0)
	var player: Node2D = Global.player_node as Node2D
	if player != null and is_instance_valid(player):
		target = player.global_position
	var dir: Vector2 = target - rect.get_center()
	if dir.length_squared() < 0.0001:
		dir = Vector2(0.0, 1.0)
	dir = dir.normalized()
	if absf(dir.x) > absf(dir.y) or dir.y <= 0.0:
		if dir.x >= 0.0:
			return Vector2(rect.end.x + radius + 1.0, item_pos.y)
		return Vector2(rect.position.x - radius - 1.0, item_pos.y)
	return Vector2(item_pos.x, rect.end.y + radius + 1.0)

func _closest_rect_point(rect: Rect2, pos: Vector2) -> Vector2:
	return Vector2(
		clampf(pos.x, rect.position.x, rect.end.x),
		clampf(pos.y, rect.position.y, rect.end.y))

# Finds a solid body's real collision rect wherever its StaticBody2D
# lives in the node tree (direct child for blocks/chests/altars, under
# Sprite2D for ObjectItem scenes), falling back to a full tile centered
# on the body origin.
func _block_collision_rect(block_node: Node) -> Rect2:
	var rect := _find_block_rect(block_node)
	if rect.size == Vector2.ZERO:
		return Rect2((block_node as Node2D).global_position - Vector2(16.0, 16.0), Vector2(32.0, 32.0))
	return rect

func _find_block_rect(root: Node) -> Rect2:
	# Iterative walk (explicit stack) instead of recursion — a dropped item
	# scans on every break, and a deep node subtree under a scanned body could
	# otherwise overflow the call stack.
	var stack: Array = [root]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		if not is_instance_valid(node):
			continue
		for child in node.get_children():
			if not is_instance_valid(child):
				continue
			if child is StaticBody2D:
				for col in child.get_children():
					if col is CollisionShape2D and (col as CollisionShape2D).shape is RectangleShape2D:
						var shape: RectangleShape2D = (col as CollisionShape2D).shape
						var size: Vector2 = shape.size
						return Rect2((col as CollisionShape2D).global_position - size * 0.5, size)
			stack.append(child)
	return Rect2()
