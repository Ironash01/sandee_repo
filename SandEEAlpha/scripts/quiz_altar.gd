extends Node2D
class_name QuizAltar
# ── Quiz Altar (final dungeon room object) ────────────────────────
# Placed by the dungeon generator in the last room. Presents every
# QuizQuestion referenced by the mission (quiz_resource_files) one at a
# time. When the player answers ALL of them correctly the exit opens and
# the dungeon is cleared: the Lua Core reward is granted, the matching
# Global.mission is marked complete, and dungeon_cleared() fires so the
# dungeon world can teleport the player out and remove the entrance from
# the overworld map.
#
# Built entirely in code (no .tscn) like CavePortal — the dungeon generator
# instantiates it with .new().

signal cleared(dungeon_index: int)

const TILE_SIZE := 32

const C_PANEL      := Color(0.08, 0.10, 0.20, 0.97)
const C_BORDER     := Color(0.70, 0.40, 0.80, 1.00)
const C_TITLE      := Color(0.90, 0.80, 1.00, 1.00)
const C_MUTED      := Color(0.65, 0.55, 0.80, 1.00)
const C_QUESTION   := Color(0.90, 0.93, 1.00, 1.00)
const C_OVERLAY    := Color(0.00, 0.00, 0.00, 0.60)
const SPRITE_TEXTURE: Texture2D = preload("res://sprites/dungeon/SandEE_alpha_dungeontilesets.png")

# ── Altar glow ─────────────────────────────────────────────────────
# Small pulsing PointLight2D hugging the altar body (blooms via the dungeon's
# WorldEnvironment at the top of each pulse) — see knowledge_altar.gd for the
# shared rationale.
const GLOW_COLOR:       Color  = Color(0.75, 0.45, 0.95)
const GLOW_ENERGY_BASE: float = 1.4
const GLOW_ENERGY_AMP:  float = 0.5
const GLOW_BLINK_SPEED: float = 2.0  # sin(2t) → ~3.1s full cycle, slow
const GLOW_TEXTURE_SCALE: float = 0.35
const GLOW_TEXTURE_SIZE:   int   = 128

var mission:        DungeonMissionData = null
var _player_nearby: bool = false
var _questions:     Array[QuizQuestion] = []
var _index:         int = 0
var _cleared:       bool = false
var _glow:          PointLight2D = null
var _glow_time:     float = 0.0

var _panel:      Control = null
var _q_progress: Label = null
var _q_text:     Label = null
var _feedback:   Label = null
var _controls:   Control = null
var _close_btn:  Button = null

# ── Compiler (Shape.COMPILER) state ────────────────────────────────
var _code_entry:       TextEdit = null
var _compiler_output:  RichTextLabel = null
var _lua_state:        Node = null
var _compiler_q:       QuizQuestion = null
var _captured_output:  String = ""

func _ready() -> void:
	add_to_group("QuizAltar")
	var tex := AtlasTexture.new()
	tex.atlas = SPRITE_TEXTURE
	tex.region = Rect2(352, 128, 32, 32)
	var sprite := Sprite2D.new()
	sprite.texture = tex
	add_child(sprite)

	add_child(_build_solid_body())
	_add_glow()

	var interact := Area2D.new()
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(TILE_SIZE, TILE_SIZE)
	shape.shape = rect
	interact.add_child(shape)
	interact.collision_layer = 0
	interact.collision_mask  = 1
	interact.body_entered.connect(_on_body_entered)
	interact.body_exited.connect(_on_body_exited)
	add_child(interact)
	call_deferred("_fix_z_index")

func _process(delta: float) -> void:
	if _glow != null:
		_glow_time += delta
		_glow.energy = GLOW_ENERGY_BASE + sin(_glow_time * GLOW_BLINK_SPEED) * GLOW_ENERGY_AMP

# Solid body so the player can't walk through the altar (it previously only had
# a pass-through proximity Area2D). Layer 1 matches the player's collision mask.
func _build_solid_body() -> StaticBody2D:
	var body := StaticBody2D.new()
	body.collision_layer = 1
	body.collision_mask  = 0
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(24, 24)
	shape.shape = rect
	body.add_child(shape)
	return body

func _add_glow() -> void:
	_glow = PointLight2D.new()
	_glow.texture       = _get_glow_texture()
	_glow.texture_scale = GLOW_TEXTURE_SCALE
	_glow.energy        = GLOW_ENERGY_BASE
	_glow.color         = GLOW_COLOR
	add_child(_glow)

static func _get_glow_texture() -> Texture2D:
	return Global.get_pixelated_light_texture(GLOW_TEXTURE_SIZE)

func _fix_z_index() -> void:
	z_index = int(global_position.y / TILE_SIZE)

func setup(m: DungeonMissionData) -> void:
	mission = m
	if mission != null:
		_questions = mission.quizzes()

func _on_body_entered(body: Node) -> void:
	if body.is_in_group("Player"):
		_player_nearby = true

func _on_body_exited(body: Node) -> void:
	if body.is_in_group("Player"):
		_player_nearby = false
		if _panel != null and _panel.visible:
			_panel.visible = false
			get_tree().paused = false

func _input(event: InputEvent) -> void:
	if _cleared or not _player_nearby or Global.block_mode or Global.any_ui_open():
		return
	if _panel != null and _panel.visible:
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_start_quiz()

func _start_quiz() -> void:
	if _questions.is_empty():
		if mission != null and mission.quiz_resource_files.is_empty():
			# Mission with no quizzes is trivially clearable.
			_complete_dungeon()
		return
	_index = 0
	if _panel == null:
		_panel = _build_panel()
	_panel.visible = true
	get_tree().paused = true
	_show_question()

func _show_question() -> void:
	if _index >= _questions.size():
		_complete_dungeon()
		return
	_rebuild_controls()

func _rebuild_controls() -> void:
	var q: QuizQuestion = _questions[_index]
	_q_progress.text = "Question %d / %d" % [_index + 1, _questions.size()]
	_q_text.text = q.question

	for child in _controls.get_children().duplicate():
		child.queue_free()

	if q.is_compiler():
		_build_compiler_controls(q)
	elif q.is_short():
		var opts := q.short_answers()
		var labels := ["A", "B", "C", "D"]
		for i in range(opts.size()):
			if opts[i].is_empty():
				continue
			_controls.add_child(_make_answer_btn(labels[i], str(i + 1), q, opts[i]))
	else:
		# Shape.LONG (enumeration) — typed answer. TextEdit is multi-line, so
		# code-style answers with indentation/line breaks can be typed as-is;
		# _normalize_answer_text() grades them tolerant of whitespace.
		var entry := TextEdit.new()
		entry.custom_minimum_size = Vector2(360, 90)
		entry.placeholder_text = "Type your answer…"
		entry.add_theme_font_size_override("font_size", 13)
		_controls.add_child(entry)
		var submit := Button.new()
		submit.text = "Submit"
		submit.custom_minimum_size = Vector2(0, 34)
		submit.pressed.connect(func() -> void: _grade(q, entry.text))
		_controls.add_child(submit)

	_feedback.text = ""

func _make_answer_btn(label: String, value: String, q: QuizQuestion, opt_text: String = "") -> Button:
	var btn := Button.new()
	btn.text = (label + "  —  " + opt_text) if not opt_text.is_empty() else label
	btn.custom_minimum_size = Vector2(150, 42)
	btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	btn.add_theme_font_size_override("font_size", 13)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.14, 0.18, 0.34, 1.0); sb.border_color = C_BORDER
	sb.set_border_width_all(1); sb.set_corner_radius_all(4)
	btn.add_theme_stylebox_override("normal",  sb)
	btn.add_theme_stylebox_override("hover",   sb)
	btn.add_theme_stylebox_override("pressed", sb)
	btn.add_theme_color_override("font_color", C_QUESTION)
	btn.pressed.connect(func() -> void: _grade(q, value))
	return btn

# ── Compiler (Shape.COMPILER) controls ─────────────────────────────
# A code editor (plain TextEdit, prefilled with the question's starter code)
# plus a live output panel and a Run button. The player's program runs through
# the game's LuaState compiler (the same interpreter the Lua robot uses); its
# print() output is captured and compared to answer_output on completion.
func _build_compiler_controls(q: QuizQuestion) -> void:
	var entry := TextEdit.new()
	entry.custom_minimum_size = Vector2(380, 110)
	entry.placeholder_text = "-- write your %s code here\nprint(\"...\")" % q.language
	entry.text = q.starter_code
	entry.syntax_highlighter = null
	entry.add_theme_font_size_override("font_size", 13)
	_controls.add_child(entry)
	_code_entry = entry

	var out := RichTextLabel.new()
	out.bbcode_enabled = true
	out.custom_minimum_size = Vector2(380, 70)
	out.scroll_following = true
	out.add_theme_font_size_override("font_size", 13)
	out.add_theme_color_override("default_color", C_MUTED)
	_controls.add_child(out)
	_compiler_output = out

	var run_btn := Button.new()
	run_btn.text = "▶  Run"
	run_btn.custom_minimum_size = Vector2(140, 38)
	run_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	run_btn.add_theme_font_size_override("font_size", 13)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.14, 0.34, 0.20, 1.0); sb.border_color = C_BORDER
	sb.set_border_width_all(1); sb.set_corner_radius_all(4)
	run_btn.add_theme_stylebox_override("normal",  sb)
	run_btn.add_theme_stylebox_override("hover",   sb)
	run_btn.add_theme_stylebox_override("pressed", sb)
	run_btn.add_theme_color_override("font_color", Color(0.70, 1.0, 0.80, 1.0))
	run_btn.pressed.connect(func() -> void: _run_compiler(q, entry.text))
	_controls.add_child(run_btn)

func _run_compiler(q: QuizQuestion, code: String) -> void:
	code = code.strip_edges()
	if code.is_empty():
		_feedback.text = "✘ Write some code first."
		_feedback.add_theme_color_override("font_color", Color(1.0, 0.55, 0.55, 1.0))
		return
	# LuaState is the game's Lua compiler (the GDExtension the Lua robot uses).
	if _lua_state == null:
		_lua_state = LuaState.new()
		add_child(_lua_state)
		_lua_state.connect("signal_print", _on_quiz_print)
		_lua_state.connect("code_executed", _on_quiz_executed)
		_lua_state.connect("code_failed", _on_quiz_failed)
	_compiler_q   = q
	_captured_output = ""
	if _compiler_output != null:
		_compiler_output.text = ""
	# The compiler queues print() calls and emits them from physics_process
	# (one per frame), so the tree must be unpaused for the output to drain.
	get_tree().paused = false
	_lua_state.set("code", code)
	_lua_state.call("run_code")

func _on_quiz_print(text: String) -> void:
	_captured_output += text + "\n"
	if _compiler_output != null:
		_compiler_output.append_text("[color=#aaddff]» %s[/color]\n" % text)

func _on_quiz_executed() -> void:
	# Code ran cleanly; wait briefly for the queued print signals to drain out
	# of physics_process, then re-pause and grade the captured output.
	await get_tree().create_timer(0.35).timeout
	if _panel == null or not _panel.visible:
		return  # quiz closed while the code was running
	get_tree().paused = true
	_grade_compiler(_compiler_q)

func _on_quiz_failed(error: String) -> void:
	if _panel != null and _panel.visible:
		get_tree().paused = true
		_feedback.text = "✘ " + error
		_feedback.add_theme_color_override("font_color", Color(1.0, 0.55, 0.55, 1.0))

func _grade_compiler(q: QuizQuestion) -> void:
	if q == null:
		return
	if q.is_compiler_output_correct(_captured_output):
		_feedback.text = "✔ Correct!"
		_feedback.add_theme_color_override("font_color", Color(0.45, 0.95, 0.55, 1.0))
		_index += 1
		await get_tree().create_timer(0.6).timeout
		if _panel != null and _panel.visible:
			_show_question()
	else:
		_feedback.text = "✘ Not quite — try again."
		_feedback.add_theme_color_override("font_color", Color(1.0, 0.55, 0.55, 1.0))

func _grade(q: QuizQuestion, input_text: String) -> void:
	if q.is_answer_correct(input_text):
		_feedback.text = "✔ Correct!"
		_feedback.add_theme_color_override("font_color", Color(0.45, 0.95, 0.55, 1.0))
		_index += 1
		await get_tree().create_timer(0.6).timeout
		if _panel != null and _panel.visible:
			_show_question()
	else:
		_feedback.text = "✘ Not quite — try again."
		_feedback.add_theme_color_override("font_color", Color(1.0, 0.55, 0.55, 1.0))

func _complete_dungeon() -> void:
	if mission == null:
		return
	_cleared = true
	if _panel != null:
		_panel.visible = false
	get_tree().paused = false

	Global.grant_item(mission.reward_item_path, 1)
	var mission_id: String = "dungeon_%d" % mission.dungeon_index
	Global.complete_mission(mission_id)
	# Star #1 of the dungeon's two — emitted after complete_mission (star #2)
	# so the mission UI popup that ends up on screen carries the clear flavor.
	Global.record_dungeon_clear(mission.dungeon_index)
	cleared.emit(mission.dungeon_index)

func _build_panel() -> Control:
	var canvas := CanvasLayer.new()
	canvas.layer        = 15
	canvas.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(canvas)

	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.process_mode = Node.PROCESS_MODE_ALWAYS
	canvas.add_child(root)

	var overlay := ColorRect.new()
	overlay.color        = C_OVERLAY
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(overlay)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(520, 0)
	var ps := StyleBoxFlat.new()
	ps.bg_color = C_PANEL; ps.border_color = C_BORDER
	ps.set_border_width_all(2); ps.set_corner_radius_all(8)
	ps.content_margin_left = 28; ps.content_margin_right  = 28
	ps.content_margin_top  = 22; ps.content_margin_bottom = 22
	panel.add_theme_stylebox_override("panel", ps)
	center.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 14)
	panel.add_child(vbox)

	var hdr := HBoxContainer.new()
	hdr.add_theme_constant_override("separation", 8)
	vbox.add_child(hdr)
	var icon := Label.new()
	icon.text = "❓"
	icon.add_theme_font_size_override("font_size", 22)
	hdr.add_child(icon)
	var title := Label.new()
	title.text = "Quiz Altar"
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_color_override("font_color", C_TITLE)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hdr.add_child(title)
	_q_progress = Label.new()
	_q_progress.add_theme_font_size_override("font_size", 12)
	_q_progress.add_theme_color_override("font_color", C_MUTED)
	hdr.add_child(_q_progress)

	var div := ColorRect.new()
	div.color = Color(0.45, 0.25, 0.55, 1.0); div.custom_minimum_size = Vector2(0, 1)
	vbox.add_child(div)

	_q_text = Label.new()
	_q_text.add_theme_font_size_override("font_size", 15)
	_q_text.add_theme_color_override("font_color", C_QUESTION)
	_q_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(_q_text)

	_controls = VBoxContainer.new()
	_controls.add_theme_constant_override("separation", 10)
	vbox.add_child(_controls)

	_feedback = Label.new()
	_feedback.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_feedback.add_theme_font_size_override("font_size", 14)
	vbox.add_child(_feedback)

	_close_btn = Button.new()
	_close_btn.text = "Close"
	_close_btn.custom_minimum_size = Vector2(120, 36)
	_close_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_close_btn.pressed.connect(_close_quiz)
	vbox.add_child(_close_btn)

	return root

func _close_quiz() -> void:
	# Closing mid-quiz leaves progress untouched; reopening (_input → _start_quiz)
	# resets to question 1 so the player can pick up or restart at will.
	if _panel != null:
		_panel.visible = false
	get_tree().paused = false
