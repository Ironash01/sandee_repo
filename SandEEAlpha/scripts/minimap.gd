extends Control
class_name Minimap

# ── Minimap ─────────────────────────────────────────────────────────
# Bottom-left minimap; press M (or click it) to open an exclusive full-screen
# map. In the expanded map: DRAG to pan, M to close (a click no longer closes),
# unexplored tiles are dimmed, and hovering an icon shows its tooltip.
#
# Terrain colours are sampled straight from the tilesets the world actually
# uses, drawn into a low-res image that is scaled up with NEAREST filtering —
# so it reads as a blocky, cartoony version of the real map.
#
# Markers:
#   • white circle  = player (centred unless panned)
#   • red circle    = enemies        ("Mob" group)
#   • green circle  = bonfires/flags ("Bonfire"/"Flag" groups — future)
#   • portal icon   = dungeon portals ("DungeonPortal"; tooltip = dungeon name)
#
# Bound to the VIEWPORT rect (a Control under a CanvasLayer is not auto-sized).
# STANDING RULE: text/markers scale with Global.ui_scale.

const TILE: int = 32
const GRID: int = 61              # cells sampled per side (odd → player centred)

const COLLAPSED_FRAC: float = 0.20
const COLLAPSED_CAP:  float = 0.32
const EXPANDED_FRAC:  float = 0.60
const EXPANDED_CAP:   float = 0.80
const MARGIN:         float = 16.0
const REFRESH_SEC:    float = 0.30
# Redraw cadence for the map itself. The marker lists + terrain blit don't need
# to run at 60fps; input handlers (pan/zoom/open) call queue_redraw() directly
# for instant feedback, so this only throttles the idle/while-walking case.
const REDRAW_SEC:     float = 0.033

# Fog-of-war: radius (tiles) around the player revealed as they move.
const EXPLORE_RADIUS: int = 26

const C_BG      := Color(0.05, 0.06, 0.12, 0.92)
const C_BORDER  := Color(0.22, 0.32, 0.58, 1.00)
const C_OVERLAY := Color(0.00, 0.00, 0.00, 0.55)
const C_PANEL   := Color(0.08, 0.10, 0.20, 0.98)
const C_TITLE   := Color(0.80, 0.90, 1.00, 1.00)
const C_MUTED   := Color(0.55, 0.65, 0.85, 1.00)
const C_FOG     := Color(0.04, 0.05, 0.09, 1.00)   # unexplored tint

const C_VOID    := Color(0.10, 0.11, 0.16)
const C_PLAYER  := Color(1.00, 1.00, 1.00)
const C_ENEMY   := Color(0.90, 0.20, 0.20)   # HOSTILE mobs
const C_FRIEND  := Color(0.95, 0.85, 0.25)   # PASSIVE mobs (yellow)
const C_GREEN   := Color(0.25, 0.85, 0.35)

const PORTAL_TEX: Texture2D = preload("res://sprites/map/dungeon_portal_icon.png")

var _expanded: bool = false
var _owns_ui:  bool = false
var _terrain:  Image = null
var _tex:      ImageTexture = null
var _since_sample: float = 999.0
var _redraw_accum: float = 999.0
# Set by pan/zoom/open so the next _process re-samples immediately (keeps those
# interactions responsive) instead of waiting out REFRESH_SEC.
var _force_sample: bool = false
var _player_tile: Vector2i = Vector2i(1 << 20, 1 << 20)
var _pan: Vector2i = Vector2i.ZERO
var _view_center: Vector2i = Vector2i(1 << 20, 1 << 20)
var _dragging: bool = false
var _drag_mouse: Vector2 = Vector2.ZERO
var _drag_pan:   Vector2i = Vector2i.ZERO

# Zoom (expanded map only): 1 = fit, >1 = zoomed in. Wheel or -/+ changes it.
var _zoom: float = 1.0
const ZOOM_MIN:  float = 0.5
const ZOOM_MAX:  float = 4.0
const ZOOM_STEP: float = 1.25

# Sampled tile colour, cached per (texture, atlas coord) so the per-tile
# texture pixel read happens once, not every refresh.
var _color_cache: Dictionary = {}

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter  = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST   # blocky / cartoony
	_terrain = Image.create_empty(GRID, GRID, false, Image.FORMAT_RGBA8)
	_terrain.fill(C_VOID)
	_tex = ImageTexture.create_from_image(_terrain)

func _vp() -> Vector2:
	return get_viewport_rect().size

func _process(delta: float) -> void:
	position = Vector2.ZERO
	size     = _vp()
	_since_sample += delta
	_redraw_accum  += delta
	var p: Node2D = Global.player_node as Node2D
	if p != null:
		var tile := Vector2i(floori(p.global_position.x / TILE), floori(p.global_position.y / TILE))
		# Reveal fog ONLY when the player actually crosses a tile — the ~2100
		# tile disc was previously written to the dictionary every single frame.
		if tile != _player_tile:
			_player_tile = tile
			_mark_explored()
	var vc: Vector2i = _player_tile + (_pan if _expanded else Vector2i.ZERO)
	# Re-sample at most every REFRESH_SEC (or immediately on pan/zoom/open).
	# The old code ALSO re-sampled on EVERY tile crossing, so walking triggered
	# a full 61x61 tile read + GPU texture upload several times a second — the
	# main walking stutter. The map still follows, just in small steps.
	if _force_sample or _since_sample >= REFRESH_SEC:
		_force_sample = false
		_view_center = vc
		_since_sample = 0.0
		_sample_terrain()
		_redraw_accum = REDRAW_SEC
	# Redraw throttled — _draw allocates the marker lists via get_nodes_in_group.
	if _redraw_accum >= REDRAW_SEC:
		_redraw_accum = 0.0
		queue_redraw()

# Reveal a disc of tiles around the player (fog of war).
func _mark_explored() -> void:
	var r: int = EXPLORE_RADIUS
	var r2: int = r * r
	for dx in range(-r, r + 1):
		for dy in range(-r, r + 1):
			if dx * dx + dy * dy > r2:
				continue
			Global.explored_tiles[_player_tile + Vector2i(dx, dy)] = true

# ── Input ───────────────────────────────────────────────────────────────
func _input(event: InputEvent) -> void:
	# M toggles the exclusive map.
	if event is InputEventKey and event.pressed and not event.echo \
			and (event.physical_keycode == KEY_M or event.keycode == KEY_M):
		if Global.is_text_input_focused() or Global.pause_menu_open:
			return
		if not _expanded and Global.any_ui_open():
			return
		_set_expanded(not _expanded)
		get_viewport().set_input_as_handled()
		return

	if not _expanded:
		# Collapsed: a click ON the corner map opens it.
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT \
				and _collapsed_rect().has_point(get_viewport().get_mouse_position()):
			if Global.is_text_input_focused() or Global.pause_menu_open or Global.any_ui_open():
				return
			_set_expanded(true)
			get_viewport().set_input_as_handled()
		return

	# Expanded: zoom with the wheel or - / +, drag to PAN.
	if event is InputEventMouseButton and event.pressed \
			and (event.button_index == MOUSE_BUTTON_WHEEL_UP or event.button_index == MOUSE_BUTTON_WHEEL_DOWN):
		_zoom_by(ZOOM_STEP if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / ZOOM_STEP)
		get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and event.pressed and not event.echo \
			and (event.keycode == KEY_EQUAL or event.keycode == KEY_PLUS or event.keycode == KEY_KP_ADD \
				or event.keycode == KEY_MINUS or event.keycode == KEY_KP_SUBTRACT):
		var zin: bool = event.keycode == KEY_MINUS or event.keycode == KEY_KP_SUBTRACT
		_zoom_by(1.0 / ZOOM_STEP if zin else ZOOM_STEP)
		get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_dragging   = true
			_drag_mouse = get_viewport().get_mouse_position()
			_drag_pan   = _pan
		else:
			_dragging = false
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion and _dragging:
		var cell_px: float = _expanded_map_rect().size.x / float(GRID)
		var d: Vector2 = get_viewport().get_mouse_position() - _drag_mouse
		_pan = _drag_pan - Vector2i(roundi(d.x / cell_px), roundi(d.y / cell_px))
		_force_sample = true
		queue_redraw()
		get_viewport().set_input_as_handled()

func _zoom_by(factor: float) -> void:
	_zoom = clampf(_zoom * factor, ZOOM_MIN, ZOOM_MAX)
	_force_sample = true   # re-sample immediately at the new zoom
	queue_redraw()

func _set_expanded(on: bool) -> void:
	if on == _expanded:
		return
	_expanded = on
	_force_sample = true
	if not on:
		_pan      = Vector2i.ZERO   # recentre on the player when closing
		_zoom     = 1.0
		_dragging = false
	if on:
		if not Global.any_ui_open():
			Global.open_ui()
			_owns_ui = true
	else:
		if _owns_ui:
			Global.close_ui()
			_owns_ui = false
	queue_redraw()

# ── Terrain sampling (real tileset colours) ─────────────────────────────
func _sample_terrain() -> void:
	var world: Node = Global.world_node
	var ground: TileMapLayer     = null
	var water:  TileMapLayer     = null
	var structs: TileMapLayer    = null
	if world != null:
		ground  = world.get_node_or_null("Ground") as TileMapLayer
		water   = world.get_node_or_null("Water") as TileMapLayer
		structs = world.get_node_or_null("Structures") as TileMapLayer
	var half: int = GRID / 2
	for gy in range(GRID):
		for gx in range(GRID):
			# Zoomed in → fewer world tiles across the same grid (repeat cells).
			var cell: Vector2i = _view_center + Vector2i(
				roundi((gx - half) / _zoom), roundi((gy - half) / _zoom))
			var c: Color = C_VOID
			if structs != null and structs.get_cell_source_id(cell) != -1:
				c = _tile_color(structs, cell)
			elif water != null and water.get_cell_source_id(cell) != -1:
				c = _tile_color(water, cell)
			else:
				c = _tile_color(ground, cell)
			if not Global.explored_tiles.has(cell):
				c = c.lerp(C_FOG, 0.62)   # dim unexplored, still readable
			_terrain.set_pixel(gx, gy, c)
	_tex.update(_terrain)

# Colour of the tile occupying `cell` on `layer`, read from its atlas texture
# and cached per (texture, atlas coord).
func _tile_color(layer: TileMapLayer, cell: Vector2i) -> Color:
	if layer == null or layer.tile_set == null:
		return C_VOID
	var src_id: int = layer.get_cell_source_id(cell)
	if src_id == -1:
		return C_VOID
	var src: TileSetSource = layer.tile_set.get_source(src_id)
	if not (src is TileSetAtlasSource):
		return C_VOID
	var atlas: TileSetAtlasSource = src as TileSetAtlasSource
	var tex: Texture2D = atlas.texture
	if tex == null:
		return C_VOID
	var coords: Vector2i = layer.get_cell_atlas_coords(cell)
	var key: String = "%d:%d,%d" % [tex.get_instance_id(), coords.x, coords.y]
	if _color_cache.has(key):
		return _color_cache[key]
	var img: Image = tex.get_image()
	if img == null:
		return C_VOID
	var region: Rect2i = atlas.get_tile_texture_region(coords, 0)
	var px: Vector2i = Vector2i(region.get_center())
	if px.x < 0 or px.y < 0 or px.x >= img.get_width() or px.y >= img.get_height():
		return C_VOID
	var col: Color = img.get_pixelv(px)
	col.a = 1.0
	_color_cache[key] = col
	return col

# ── Rect helpers ────────────────────────────────────────────────────────
func _collapsed_rect() -> Rect2:
	var s: float = Global.ui_scale
	var vp: Vector2 = _vp()
	var base: float = minf(vp.x, vp.y)
	var sz: float = minf(base * COLLAPSED_FRAC * s, base * COLLAPSED_CAP)
	return Rect2(Vector2(MARGIN * s, vp.y - sz - MARGIN * s), Vector2(sz, sz))

func _expanded_map_rect() -> Rect2:
	var s: float = Global.ui_scale
	var vp: Vector2 = _vp()
	var base: float = minf(vp.x, vp.y)
	var map_px: float = minf(base * EXPANDED_FRAC * s, base * EXPANDED_CAP)
	var total_h: float = 30.0 * s + map_px + 30.0 * s
	return Rect2(Vector2((vp.x - map_px) * 0.5, (vp.y - total_h) * 0.5), Vector2(map_px, map_px))

# ── Drawing ─────────────────────────────────────────────────────────────
func _draw() -> void:
	if _expanded:
		_draw_expanded()
	else:
		_draw_collapsed()

func _draw_collapsed() -> void:
	var s: float = Global.ui_scale
	var rect: Rect2 = _collapsed_rect()
	draw_rect(rect, C_BG, true)
	if _tex != null:
		draw_texture_rect(_tex, rect, false)
	_draw_entities(rect, s)
	draw_rect(rect, C_BORDER, false, 2.0 * s)

func _draw_expanded() -> void:
	var s: float = Global.ui_scale
	var vp: Vector2 = _vp()
	var font: Font = ThemeDB.fallback_font
	draw_rect(Rect2(Vector2.ZERO, vp), C_OVERLAY, true)

	var panel: Rect2 = _expanded_map_rect()
	var bg := panel.grow(14.0 * s)
	bg.position.y -= 30.0 * s
	bg.size.y     += 30.0 * s
	draw_rect(bg, C_PANEL, true)
	draw_rect(bg, C_BORDER, false, 2.0 * s)

	draw_string(font, Vector2(panel.position.x, panel.position.y - 9 * s),
		"MAP", HORIZONTAL_ALIGNMENT_LEFT, -1, int(16 * s), C_TITLE)
	var hint := "drag to pan  ·  M to close"
	var hw: float = font.get_string_size(hint, HORIZONTAL_ALIGNMENT_LEFT, -1, int(11 * s)).x
	draw_string(font, Vector2(panel.end.x - hw, panel.position.y - 9 * s),
		hint, HORIZONTAL_ALIGNMENT_LEFT, -1, int(11 * s), C_MUTED)

	if _tex != null:
		draw_texture_rect(_tex, panel, false)
	_draw_entities(panel, s)
	draw_rect(panel, C_BORDER, false, 2.0 * s)

	# Legend
	var ly: float = panel.end.y + 18 * s
	var lx: float = panel.position.x
	lx = _legend_item(font, lx, ly, s, C_PLAYER, "You")
	lx = _legend_item(font, lx, ly, s, C_ENEMY, "Enemies")
	lx = _legend_item(font, lx, ly, s, C_FRIEND, "Friendly")
	lx = _legend_item(font, lx, ly, s, C_GREEN, "Bonfires / Flags")
	var isz: float = 16.0 * s
	draw_texture_rect(PORTAL_TEX, Rect2(Vector2(lx, ly - isz * 0.7), Vector2(isz, isz)), false)
	draw_string(font, Vector2(lx + isz + 4 * s, ly + 4 * s), "Dungeon",
		HORIZONTAL_ALIGNMENT_LEFT, -1, int(11 * s), C_TITLE)

	_tooltip(font, s)

func _legend_item(font: Font, x: float, y: float, s: float, col: Color, label: String) -> float:
	var r: float = 4.0 * s
	draw_circle(Vector2(x + r, y), r, col)
	draw_string(font, Vector2(x + r * 2 + 4 * s, y + 4 * s), label,
		HORIZONTAL_ALIGNMENT_LEFT, -1, int(11 * s), C_TITLE)
	return x + r * 2 + 12 * s + font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, int(11 * s)).x

# ── Entities + hover tooltips ───────────────────────────────────────────
func _draw_entities(map_rect: Rect2, s: float) -> void:
	var p: Node2D = Global.player_node as Node2D
	if p == null:
		return
	var cell_px: float = map_rect.size.x / float(GRID)
	var z: float = _zoom if _expanded else 1.0
	var ppt: float = cell_px * z   # screen px per world tile
	var center: Vector2 = map_rect.position + map_rect.size * 0.5
	for m in get_tree().get_nodes_in_group("Mob"):
		_marker(map_rect, center, ppt, m, C_ENEMY if _mob_is_hostile(m) else C_FRIEND, 3.0 * s)
	for grp in ["Bonfire", "Flag"]:
		for b in get_tree().get_nodes_in_group(grp):
			_marker(map_rect, center, ppt, b, C_GREEN, 3.0 * s)
	for d in get_tree().get_nodes_in_group("DungeonPortal"):
		_portal_marker(map_rect, center, ppt, d, s)
	var ppos: Vector2 = center + (p.global_position / TILE - Vector2(_view_center)) * ppt
	if not _expanded:
		ppos = center
	draw_circle(ppos, 3.5 * s, C_PLAYER)
	draw_arc(ppos, 3.5 * s, 0.0, TAU, 16, C_BORDER, 1.0 * s)

func _marker(map_rect: Rect2, center: Vector2, cell_px: float, node: Node, col: Color, r: float) -> void:
	if not (node is Node2D) or not is_instance_valid(node):
		return
	var pos: Vector2 = center + ((node as Node2D).global_position / TILE - Vector2(_view_center)) * cell_px
	if not map_rect.has_point(pos):
		return
	draw_circle(pos, r, col)

func _portal_marker(map_rect: Rect2, center: Vector2, cell_px: float, node: Node, s: float) -> void:
	if not (node is Node2D) or not is_instance_valid(node):
		return
	var isz: float = 13.0 * s
	var pos: Vector2 = center + ((node as Node2D).global_position / TILE - Vector2(_view_center)) * cell_px
	pos.x = clampf(pos.x, map_rect.position.x + isz, map_rect.end.x - isz)
	pos.y = clampf(pos.y, map_rect.position.y + isz, map_rect.end.y - isz)
	draw_texture_rect(PORTAL_TEX, Rect2(pos - Vector2(isz, isz) * 0.5, Vector2(isz, isz)), false)

# Nearest icon under the cursor → its tooltip text (portals = dungeon name).
func _hovered_icon() -> Dictionary:
	if not _expanded:
		return {}
	var map_rect: Rect2 = _expanded_map_rect()
	var cell_px: float = map_rect.size.x / float(GRID)
	var ppt: float = cell_px * _zoom
	var center: Vector2 = map_rect.position + map_rect.size * 0.5
	var mouse: Vector2 = get_viewport().get_mouse_position()
	var best_d: float = 14.0 * Global.ui_scale
	var best: Dictionary = {}
	var entries: Array = []
	for d in get_tree().get_nodes_in_group("DungeonPortal"):
		entries.append({"node": d, "text": _portal_name(d), "icon": true})
	for m in get_tree().get_nodes_in_group("Mob"):
		entries.append({"node": m, "text": _mob_name(m), "icon": false})
	for grp in [["Bonfire", "Bonfire"], ["Flag", "Flag"]]:
		for b in get_tree().get_nodes_in_group(grp[0]):
			entries.append({"node": b, "text": grp[1], "icon": false})
	for e in entries:
		var node: Node = e["node"]
		if not (node is Node2D) or not is_instance_valid(node):
			continue
		var pos: Vector2 = center + ((node as Node2D).global_position / TILE - Vector2(_view_center)) * ppt
		if not map_rect.has_point(pos):
			continue
		var d2: float = mouse.distance_to(pos)
		if d2 < best_d:
			best_d = d2
			best = {"text": e["text"], "pos": pos}
	return best

func _tooltip(font: Font, s: float) -> void:
	var h: Dictionary = _hovered_icon()
	if h.is_empty():
		return
	var text: String = str(h["text"])
	var fs: int = int(12 * s)
	var pad: float = 6.0 * s
	var tw: float = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var pos: Vector2 = h["pos"] + Vector2(10 * s, -10 * s)
	var box := Rect2(pos, Vector2(tw + pad * 2, fs + pad * 1.4))
	draw_rect(box, C_PANEL, true)
	draw_rect(box, C_BORDER, false, 1.5 * s)
	draw_string(font, Vector2(box.position.x + pad, box.position.y + fs + pad * 0.4),
		text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, C_TITLE)

func _portal_name(portal: Node) -> String:
	var idx = portal.get("dungeon_index")
	if idx == null:
		return "Dungeon"
	var dm = Global.get_dungeon_mission_for_index(int(idx))
	if dm != null and not dm.mission_name.is_empty():
		return dm.mission_name
	return "Dungeon"

func _mob_name(mob: Node) -> String:
	var data = mob.get("COMBAT_DATA")
	if data != null and data.get("mob_name") != null:
		var n: String = str(data.get("mob_name"))
		if not n.is_empty():
			return n
	return "Enemy"

# HOSTILE (Behavior 0) is red; PASSIVE (1) is yellow. Unknown data defaults to
# hostile so an unfamiliar mob is never quietly marked friendly.
func _mob_is_hostile(mob: Node) -> bool:
	var data = mob.get("COMBAT_DATA")
	if data == null:
		return true
	var beh = data.get("behavior")
	if beh == null:
		return true
	return int(beh) == 0
