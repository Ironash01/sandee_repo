extends Node2D
# ── Dungeon Portal (world entrance) ─────────────────────────────────
# Spawned by world.gd for each language's current dungeon mission (see
# world.gd's _ensure_current_dungeon_entrances) — NOT placed by the player
# (the old "Dungeon Spawner" placeable-item flow was removed).
# The entrance structure is a 3x3 sprite whose cells are all walkable (see
# sample_structure.tres's door_rect), and this node sits on its CENTRE tile.
# Walking onto it shows the confirm dialog that dispatches to
# Global.game_node.enter_dungeon(dungeon_index) — the same parent-scene
# pattern CavePortal uses, instead of the old change_scene_to_file (which
# destroyed Player/UI — see game_instance.gd). A left-click on the centre
# tile works too.
#
# Dungeon mapping comes from the DungeonMissionData the index points at (see
# _portal_title) — each language runs its own sequential track, so the same
# portal tile may serve the Lua or the Python dungeon depending on dungeon_index.

# ── Glow + luminescent motes ──────────────────────────────────────
# A pulsing blue PointLight2D on the middle tile, plus drifting glowing
# motes that float around it. The overworld's WorldEnvironment glow makes
# both bloom. Purely cosmetic — no gameplay effect.
const GLOW_COLOR:        Color = Color(0.45, 0.55, 1.0)
const GLOW_ENERGY_BASE:  float = 1.4
const GLOW_ENERGY_AMP:   float = 0.55
const GLOW_PULSE_SPEED:  float = 2.5
const GLOW_TEXTURE_SCALE: float = 1.1
const GLOW_TEXTURE_SIZE: int   = 128
var _glow:      PointLight2D = null
var _glow_time: float        = 0.0

# ── Theme ─────────────────────────────────────────────────────────
const C_PANEL   := Color(0.08, 0.10, 0.20, 0.97)
const C_BORDER  := Color(0.40, 0.25, 0.70, 1.00)
const C_TITLE   := Color(0.85, 0.70, 1.00, 1.00)
const C_MUTED   := Color(0.60, 0.55, 0.80, 1.00)
const C_ENTER   := Color(0.20, 0.45, 0.20, 1.00)
const C_CANCEL  := Color(0.40, 0.20, 0.20, 1.00)
const C_OVERLAY := Color(0.00, 0.00, 0.00, 0.55)

# ── Door hitbox ────────────────────────────────────────────────────
# The confirm only pops on a left-click that lands ON the portal. This node's
# origin sits on the entrance structure's CENTRE tile (see world.gd's
# _place_dungeon_entrance_structure), so the door is a small rect centered
# at the origin — the visible portal in the middle of the 3x3 art, plus a
# little click slack. A click anywhere else (the surrounding frames, the
# ground nearby) does nothing.
const DOOR_HITBOX := Rect2(-18.0, -20.0, 36.0, 40.0)  # px, centered on the door tile

# ── Door highlight ─────────────────────────────────────────────────
# A yellow outline drawn around the door tile whenever the player is close
# enough to click it (same _player_nearby condition the click handler
# checks), so the clickable block reads as clickable. Drawn here in _draw()
# like cave_portal.gd's entrance marker, at z_index = tile bucket + 1 so the
# outline always sits on top of the entrance sprites and the player.
const TILE_SIZE:         int   = 32
const C_DOOR_HIGHLIGHT:  Color = Color(1.0, 0.9, 0.2, 1.0)

# ── State ─────────────────────────────────────────────────────────
var dungeon_index: int = 1      # set by world.gd at spawn
var _player_nearby:  bool = false
var _confirm_ui:     Control = null
# Beckoning animation that plays on approach; the Enter prompt only appears
# once it has finished (see _play_beacon / _on_beacon_done).
var _beaconing:      bool = false
const BEACON_DURATION: float = 0.6

@onready var _interact: Area2D   = $InteractArea

# ── Dissolve (dungeon cleared) ──────────────────────────────────────
# When a dungeon is cleared, world.gd calls begin_dissolve() instead of
# freeing the portal outright. The overworld is normally OFF-TREE at that
# moment (the player is inside the dungeon), so the animation is DEFERRED
# until the portal is back in the tree — i.e. the moment the player returns
# to the surface and can actually see it. A slow ring of "mellow" sprites
# blooms out of the portal while the painted entrance sinks, fades and
# vanishes.
const MELLOW_TEX:         Texture2D = preload("res://sprites/particles_effects/mellow_effect.png")
const MELLOW_FRAMES:      int   = 5    # mellow_effect.png is 80x16 = 5 frames of 16x16
const MELLOW_FRAME_SIZE:  int   = 16
const MELLOW_COUNT:       int   = 10
const MELLOW_FPS:         float = 8.0
const DISSOLVE_DURATION:  float = 3.0

var _dissolving:       bool  = false
var _dissolve_started: bool  = false
var _dissolve_root:    Node2D = null
var _mellow_sf:        SpriteFrames = null

# Called by world.gd's remove_dungeon_entrance. Disables all interaction, then
# either starts the dissolve now (already in-tree) or waits for _process to
# see the overworld come back.
func begin_dissolve(entrance_root: Node2D) -> void:
	if _dissolving:
		return
	_dissolving    = true
	_dissolve_root = entrance_root
	_player_nearby = false
	set_process_input(false)
	_interact.set_deferred("monitoring", false)
	_interact.set_deferred("monitorable", false)
	if _confirm_ui != null:
		Global.unregister_ui_back(_confirm_ui)
		_confirm_ui.visible = false
		Global.close_ui()
	set_process(true)   # _process drives the deferred start + glow fade
	queue_redraw()

func _start_dissolve() -> void:
	if _dissolve_started:
		return
	_dissolve_started = true
	# Drop the painted entrance's collision immediately so the player can walk
	# out of it while the visuals fade — the walls stop blocking at once.
	if _dissolve_root != null and is_instance_valid(_dissolve_root):
		for c in _dissolve_root.get_children():
			if c is StaticBody2D:
				(c as StaticBody2D).set_deferred("collision_layer", 0)
				(c as StaticBody2D).set_deferred("collision_mask", 0)
	# Stop the motes; flash the glow up, then let it die out.
	var motes := get_node_or_null("PortalMotes") as GPUParticles2D
	if motes != null:
		motes.emitting = false
	if _glow != null:
		var ft := create_tween()
		ft.tween_property(_glow, "energy", 3.2, 0.25)
		ft.tween_property(_glow, "energy", 0.0, DISSOLVE_DURATION - 0.25)
	# Mellow sprites bloom out of the portal in a slow ring.
	for i in range(MELLOW_COUNT):
		_spawn_mellow(i)
	# Fade the entrance out ON THE SPOT — deliberately NO slide or scale, so it
	# vanishes exactly where it stood instead of appearing to move/relocate.
	if _dissolve_root != null and is_instance_valid(_dissolve_root):
		var t := create_tween()
		t.tween_property(_dissolve_root, "modulate:a", 0.0, DISSOLVE_DURATION) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	# Clean up once the show is over.
	var self_tw := create_tween()
	self_tw.tween_interval(DISSOLVE_DURATION)
	self_tw.tween_callback(_finish_dissolve)

func _spawn_mellow(index: int) -> void:
	var s: float = Global.ui_scale
	var spr := AnimatedSprite2D.new()
	spr.sprite_frames  = _mellow_frames()
	spr.z_index        = z_index + 4
	spr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	spr.modulate       = Color(0.80, 0.85, 1.0, 0.0)
	var ang:  float = TAU * float(index) / float(MELLOW_COUNT) + randf() * 0.4
	var dist: float = 18.0 + randf() * 10.0
	spr.position = Vector2(cos(ang), sin(ang)) * dist
	spr.scale    = Vector2(0.6, 0.6)
	add_child(spr)
	spr.play("mellow")
	var delay: float = randf() * 0.8
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(spr, "modulate:a", 0.95, 0.4).set_delay(delay)
	tw.tween_property(spr, "scale", Vector2(2.6, 2.6) * s, DISSOLVE_DURATION) \
		.set_delay(delay).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.tween_property(spr, "position", spr.position * 2.6, DISSOLVE_DURATION) \
		.set_delay(delay).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.tween_property(spr, "modulate:a", 0.0, DISSOLVE_DURATION * 0.6) \
		.set_delay(delay + DISSOLVE_DURATION * 0.4)

func _finish_dissolve() -> void:
	if _dissolve_root != null and is_instance_valid(_dissolve_root):
		_dissolve_root.queue_free()
	queue_free()

func _mellow_frames() -> SpriteFrames:
	if _mellow_sf != null:
		return _mellow_sf
	var sf := SpriteFrames.new()
	sf.add_animation("mellow")
	sf.set_animation_speed("mellow", MELLOW_FPS)
	sf.set_animation_loop("mellow", true)
	for i in range(MELLOW_FRAMES):
		var at := AtlasTexture.new()
		at.atlas  = MELLOW_TEX
		at.region = Rect2(i * MELLOW_FRAME_SIZE, 0, MELLOW_FRAME_SIZE, MELLOW_FRAME_SIZE)
		sf.add_frame("mellow", at)
	_mellow_sf = sf
	return _mellow_sf

# ── Ready ─────────────────────────────────────────────────────────
func _ready() -> void:
	add_to_group("DungeonPortal")
	_interact.body_entered.connect(_on_body_entered)
	_interact.body_exited.connect(_on_body_exited)
	_build_confirm_ui()
	_add_glow()
	_add_portal_particles()
	queue_redraw()
	if not Global.ui_scale_changed.is_connected(_on_ui_scale):
		Global.ui_scale_changed.connect(_on_ui_scale)

# Rebuild the confirm dialog at the new scale (when open) so a Small/Medium/
# Large change applies live rather than only on the next approach.
func _on_ui_scale(_s: float) -> void:
	if _confirm_ui == null:
		return
	var was_visible: bool = _confirm_ui.visible
	var canvas: Node = _confirm_ui.get_parent()
	if canvas != null:
		canvas.queue_free()
	_confirm_ui = null
	_build_confirm_ui()
	if _confirm_ui != null:
		_confirm_ui.visible = was_visible

# ── Glow pulse ─────────────────────────────────────────────────────
func _process(delta: float) -> void:
	if _dissolving:
		# Deferred until the overworld is back on screen (a clear happens while
		# the player is inside the dungeon, with the overworld off-tree).
		if not _dissolve_started and is_inside_tree():
			_start_dissolve()
		return
	if _glow == null:
		return
	_glow_time += delta
	_glow.energy = GLOW_ENERGY_BASE + sin(_glow_time * GLOW_PULSE_SPEED) * GLOW_ENERGY_AMP

# Soft radial light on the middle tile — blooms through the overworld's
# WorldEnvironment glow so the portal reads as magical.
func _add_glow() -> void:
	_glow = PointLight2D.new()
	_glow.texture       = Global.get_smooth_light_texture(GLOW_TEXTURE_SIZE)
	_glow.texture_scale = GLOW_TEXTURE_SCALE
	_glow.color         = GLOW_COLOR
	_glow.energy        = GLOW_ENERGY_BASE
	_glow.blend_mode    = Light2D.BLEND_MODE_ADD
	add_child(_glow)

# Blue luminescent motes that drift out from the middle tile and float
# upward — each fades in and out across its lifetime.
func _add_portal_particles() -> void:
	var p := GPUParticles2D.new()
	p.name          = "PortalMotes"
	p.texture       = Global.get_smooth_light_texture(64)
	p.amount        = 28
	p.lifetime      = 2.4
	p.preprocess    = 1.2
	p.local_coords  = false
	p.z_index       = 1
	p.emitting      = true

	var m := ParticleProcessMaterial.new()
	m.direction             = Vector3(0.0, -1.0, 0.0)
	m.spread                = 180.0
	m.gravity               = Vector3(0.0, -10.0, 0.0)
	m.initial_velocity_min  = 5.0
	m.initial_velocity_max  = 16.0
	m.scale_min             = 0.06
	m.scale_max             = 0.14
	m.color                 = Color(0.55, 0.70, 1.0, 0.9)
	m.emission_shape        = ParticleProcessMaterial.EMISSION_SHAPE_RING
	m.emission_ring_radius  = 14.0

	# Fade in → hold → fade out across the lifetime.
	var grad := Gradient.new()
	grad.colors = PackedColorArray([
		Color(0.55, 0.70, 1.0, 0.0),
		Color(0.60, 0.80, 1.0, 1.0),
		Color(0.55, 0.70, 1.0, 0.0),
	])
	grad.offsets = PackedFloat32Array([0.0, 0.5, 1.0])
	var ramp := GradientTexture1D.new()
	ramp.gradient = grad
	m.color_ramp = ramp

	# Each mote grows then shrinks — a breathing pulse.
	var curve := Curve.new()
	curve.add_point(Vector2(0.0, 0.35))
	curve.add_point(Vector2(0.5, 1.0))
	curve.add_point(Vector2(1.0, 0.35))
	var curve_tex := CurveTexture.new()
	curve_tex.curve = curve
	m.scale_curve = curve_tex

	p.process_material = m
	add_child(p)

# ── Draw ───────────────────────────────────────────────────────────
# Recomputed here rather than _ready() — callers set global_position AFTER
# add_child() (which is when _ready() fires), so computing it there would
# permanently bucket every portal at y=0 (same caveat cave_portal.gd notes).
func _draw() -> void:
	z_index = int(global_position.y / TILE_SIZE) + 1
	if _player_nearby:
		var half: float = TILE_SIZE * 0.5
		draw_rect(Rect2(-half, -half, TILE_SIZE, TILE_SIZE), C_DOOR_HIGHLIGHT, false, 2.0 * Global.ui_scale)

# ── Input ─────────────────────────────────────────────────────────
func _input(event: InputEvent) -> void:
	if Global.is_mouse_event_over_ui(event):
		return
	# Escape cancels the confirm dialog safely (never enters).
	if _confirm_ui != null and _confirm_ui.visible and event.is_action_pressed("escape"):
		get_viewport().set_input_as_handled()
		if not Global.request_ui_back(event) and not Global.is_ui_back_event_consumed(event):
			_cancel()
		return
	if not _player_nearby or Global.block_mode or Global.any_ui_open() or Global.pause_menu_open:
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if _click_is_on_door():
			_show_confirm()

# True when the click position is on the door sprite — the portal's origin
# sits on the structure's door tile, so the mouse just has to land inside
# DOOR_HITBOX around it.
func _click_is_on_door() -> bool:
	return DOOR_HITBOX.has_point(to_local(Global.mouse_world(self)))

# ── Proximity ─────────────────────────────────────────────────────
# The area is the walkable centre tile — stepping onto it plays the beckoning
# pulse, and the Enter prompt only pops once that pulse has finished.
func _on_body_entered(body: Node) -> void:
	if _dissolving:
		return
	if body.is_in_group("Player"):
		_player_nearby = true
		queue_redraw()
		if not Global.block_mode and not Global.any_ui_open() and not Global.pause_menu_open:
			_play_beacon()

func _on_body_exited(body: Node) -> void:
	if body.is_in_group("Player"):
		_player_nearby = false
		queue_redraw()
		if _confirm_ui != null and _confirm_ui.visible:
			Global.unregister_ui_back(_confirm_ui)
			_confirm_ui.visible = false
			Global.close_ui()

# A beckoning pulse expanding out of the portal. The prompt is deferred to
# the end of this animation so stepping in never instantly slams a dialog up.
func _play_beacon() -> void:
	if _beaconing:
		return
	_beaconing = true
	var pulse := Sprite2D.new()
	pulse.texture = Global.get_smooth_light_texture(128)
	pulse.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	pulse.modulate = Color(0.75, 0.85, 1.0, 0.85)
	pulse.scale = Vector2(0.35, 0.35)
	pulse.z_index = z_index + 3
	add_child(pulse)
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(pulse, "scale", Vector2(1.7, 1.7), BEACON_DURATION) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(pulse, "modulate:a", 0.0, BEACON_DURATION)
	get_tree().create_timer(BEACON_DURATION).timeout.connect(_on_beacon_done.bind(pulse))

func _on_beacon_done(pulse: Node) -> void:
	if is_instance_valid(pulse):
		pulse.queue_free()
	_beaconing = false
	# Only prompt if the player is still standing on the tile and nothing else
	# has taken over the UI meanwhile.
	if _player_nearby \
			and not Global.block_mode and not Global.any_ui_open() and not Global.pause_menu_open:
		_show_confirm()

# ── Confirm UI ────────────────────────────────────────────────────
# "Python Dungeon — While Loops": the language band + the mission's own name,
# read from the DungeonMissionData this portal's index points at. Both tracks
# share one entrance structure sprite, so this label is how the player tells
# the two live entrances apart.
func _portal_title() -> String:
	var dm := Global.get_dungeon_mission_for_index(dungeon_index)
	var mission_name: String = dm.mission_name if dm != null else "Unknown Dungeon"
	var lang: String = Global.dungeon_language(dungeon_index)
	var difficulty := Global.dungeon_difficulty(dungeon_index)
	if lang.is_empty():
		return "%s — %s" % [mission_name, difficulty]
	return "%s Dungeon — %s — %s" % [lang.capitalize(), mission_name, difficulty]

func _build_confirm_ui() -> void:
	var s: float = Global.ui_scale
	var canvas := CanvasLayer.new()
	canvas.layer        = 30
	canvas.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(canvas)

	_confirm_ui = Control.new()
	_confirm_ui.set_anchors_preset(Control.PRESET_FULL_RECT)
	_confirm_ui.process_mode = Node.PROCESS_MODE_ALWAYS
	_confirm_ui.visible      = false
	canvas.add_child(_confirm_ui)

	var overlay := ColorRect.new()
	overlay.color        = C_OVERLAY
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_confirm_ui.add_child(overlay)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_confirm_ui.add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(int(360 * s), int(180 * s))
	var ps := StyleBoxFlat.new()
	ps.bg_color = C_PANEL; ps.border_color = C_BORDER
	ps.set_border_width_all(int(2 * s)); ps.set_corner_radius_all(int(8 * s))
	ps.content_margin_left = int(20 * s); ps.content_margin_right  = int(20 * s)
	ps.content_margin_top  = int(16 * s); ps.content_margin_bottom = int(16 * s)
	panel.add_theme_stylebox_override("panel", ps)
	center.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", int(12 * s))
	panel.add_child(vbox)

	# Icon + title row
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", int(8 * s))
	vbox.add_child(header)
	var icon_lbl := Label.new()
	icon_lbl.text = "🌀"
	icon_lbl.add_theme_font_size_override("font_size", int(20 * s))
	header.add_child(icon_lbl)
	var title := Label.new()
	title.text = _portal_title()
	title.add_theme_font_size_override("font_size", int(14 * s))
	title.add_theme_color_override("font_color", C_TITLE)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)

	var div := ColorRect.new()
	div.color = Color(0.30, 0.20, 0.55, 1.0); div.custom_minimum_size = Vector2(0, int(1 * s))
	vbox.add_child(div)

	var hint := Label.new()
	hint.text = "Enter the dungeon?"
	hint.add_theme_font_size_override("font_size", int(12 * s))
	hint.add_theme_color_override("font_color", C_MUTED)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(hint)

	var btn_row := HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", int(10 * s))
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(btn_row)

	var enter_btn := Button.new()
	enter_btn.text = "  Enter  "
	enter_btn.custom_minimum_size = Vector2(int(120 * s), int(36 * s))
	enter_btn.add_theme_font_size_override("font_size", int(13 * s))
	var es := StyleBoxFlat.new()
	es.bg_color = C_ENTER; es.border_color = C_BORDER
	es.set_border_width_all(int(1 * s)); es.set_corner_radius_all(int(4 * s))
	es.content_margin_top = int(6 * s); es.content_margin_bottom = int(6 * s)
	enter_btn.add_theme_stylebox_override("normal",  es)
	enter_btn.add_theme_stylebox_override("hover",   es)
	enter_btn.add_theme_color_override("font_color", Color(0.8, 1.0, 0.8, 1.0))
	enter_btn.pressed.connect(_enter_dungeon)
	btn_row.add_child(enter_btn)

	var cancel_btn := Button.new()
	cancel_btn.text = "  Cancel  "
	cancel_btn.custom_minimum_size = Vector2(int(100 * s), int(36 * s))
	cancel_btn.add_theme_font_size_override("font_size", int(13 * s))
	var cs := StyleBoxFlat.new()
	cs.bg_color = C_CANCEL; cs.border_color = C_BORDER
	cs.set_border_width_all(int(1 * s)); cs.set_corner_radius_all(int(4 * s))
	cs.content_margin_top = int(6 * s); cs.content_margin_bottom = int(6 * s)
	cancel_btn.add_theme_stylebox_override("normal",  cs)
	cancel_btn.add_theme_stylebox_override("hover",   cs)
	cancel_btn.add_theme_color_override("font_color", Color(1.0, 0.8, 0.8, 1.0))
	cancel_btn.pressed.connect(_cancel)
	btn_row.add_child(cancel_btn)

func _show_confirm() -> void:
	if _confirm_ui != null:
		_confirm_ui.visible = true
		Global.open_ui()
		Global.register_ui_back(_confirm_ui, Callable(self, "_cancel"))

func _cancel() -> void:
	if _confirm_ui != null:
		Global.unregister_ui_back(_confirm_ui)
		Global.unregister_ui_back(_confirm_ui)
		_confirm_ui.visible = false
		Global.close_ui()

func _enter_dungeon() -> void:
	if _confirm_ui != null:
		Global.unregister_ui_back(_confirm_ui)
		Global.unregister_ui_back(_confirm_ui)
		_confirm_ui.visible = false
		Global.close_ui()
	if is_instance_valid(Global.game_node) and Global.game_node.has_method("enter_dungeon"):
		Global.game_node.call("enter_dungeon", dungeon_index)
	else:
		push_error("DungeonPortal: game node has no enter_dungeon(%d)" % dungeon_index)
