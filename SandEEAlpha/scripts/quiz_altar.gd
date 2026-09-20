extends Node2D
class_name QuizAltar
# ── Quiz Altar (final dungeon room object) ────────────────────────
# Placed by the dungeon generator in the last room. Presents every question
# embedded in the mission's `questions` (Array[DungeonQuestion], MCQ or COMPILER)
# one at a time. When the player answers ALL of them correctly the exit opens
# and the dungeon is cleared: the reward is granted, the matching
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
const C_ERROR      := Color(1.00, 0.55, 0.55, 1.00)
const C_OK         := Color(0.45, 0.95, 0.55, 1.00)
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
var _questions:     Array[DungeonQuestion] = []
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

# ── Compiler (COMPILER) state ─────────────────────────────────────
# The in-dungeon editor reuses the project's existing CodeEdit widget
# (scripts/code_edit.gd) plus the shared LanguageSpecification resources, so
# the dungeon gets the same syntax highlighting, auto-indent and brace/code
# completion the test CodeEditor has — instead of a plain undecorated TextEdit.
const CODE_EDIT_SCRIPT: GDScript = preload("res://scripts/code_edit.gd")
const CODE_FONT: FontFile = preload("res://fonts/monogram-extended.ttf")
const LUA_SPEC:    LanguageSpecification = preload("uid://df7rqt8d0p5if")
const PYTHON_SPEC: LanguageSpecification = preload("uid://dwisajvglb4eu")

var _code_entry:       TextEdit = null
var _compiler_output:  RichTextLabel = null
var _error_label:      Label = null
var _lua_state:        Node = null
var _python_state:     PythonState = null
var _compiler_q:       DungeonQuestion = null
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
	interact.collision_mask  = 4   # player is on layer 4 (see player.tscn)
	interact.body_entered.connect(_on_body_entered)
	interact.body_exited.connect(_on_body_exited)
	add_child(interact)
	call_deferred("_fix_z_index")
	if not Global.ui_scale_changed.is_connected(_on_ui_scale):
		Global.ui_scale_changed.connect(_on_ui_scale)

# The quiz panel is built at the current UI scale and cached — rebuild it in
# place (keeping the current question) so a scale change applies live.
func _on_ui_scale(_s: float) -> void:
	if _panel == null:
		return
	var was_visible: bool = _panel.visible
	var canvas: Node = _panel.get_parent()
	if canvas != null:
		canvas.queue_free()
	_panel = null
	_q_progress = null; _q_text = null; _feedback = null
	_controls = null; _close_btn = null
	_code_entry = null; _compiler_output = null; _error_label = null
	if was_visible:
		_panel = _build_panel()
		_panel.visible = true
		_show_question()

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
		_questions = mission.questions.duplicate()

func _on_body_entered(body: Node) -> void:
	if body.is_in_group("Player"):
		_player_nearby = true

func _on_body_exited(body: Node) -> void:
	if body.is_in_group("Player"):
		_player_nearby = false
		if _panel != null and _panel.visible:
			_panel.visible = false
			Global.close_ui()

func _input(event: InputEvent) -> void:
	if _cleared or not _player_nearby or Global.block_mode or Global.any_ui_open():
		return
	if _panel != null and _panel.visible:
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_start_quiz()

func _start_quiz() -> void:
	if _questions.is_empty():
		if mission != null and mission.questions.is_empty():
			# Mission with no questions is trivially clearable.
			_complete_dungeon()
		return
	_index = 0
	if _panel == null:
		_panel = _build_panel()
	_panel.visible = true
	Global.open_ui()
	_show_question()

func _show_question() -> void:
	if _index >= _questions.size():
		_complete_dungeon()
		return
	_rebuild_controls()

func _rebuild_controls() -> void:
	var q: DungeonQuestion = _questions[_index]
	_q_progress.text = "Question %d / %d" % [_index + 1, _questions.size()]
	_q_text.text = q.question

	for child in _controls.get_children().duplicate():
		child.queue_free()
	# The nodes just freed are gone at end of frame — drop the references so a
	# late print/error signal can never touch a freed object.
	_code_entry      = null
	_compiler_output = null
	_error_label     = null

	if q.is_compiler():
		_build_compiler_controls(q)
	else:
		# MCQ — one button per non-empty choice, graded by correct_index.
		var opts := q.options()
		var labels := ["A", "B", "C", "D"]
		for i in range(opts.size()):
			if opts[i].is_empty():
				continue
			_controls.add_child(_make_answer_btn(labels[i], str(i), q, opts[i]))

	_feedback.text = ""

func _make_answer_btn(label: String, value: String, q: DungeonQuestion, opt_text: String = "") -> Button:
	var s: float = Global.ui_scale
	var btn := Button.new()
	btn.text = (label + "  —  " + opt_text) if not opt_text.is_empty() else label
	btn.custom_minimum_size = Vector2(int(150 * s), int(42 * s))
	btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	btn.add_theme_font_size_override("font_size", int(13 * s))
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.14, 0.18, 0.34, 1.0); sb.border_color = C_BORDER
	sb.set_border_width_all(int(1 * s)); sb.set_corner_radius_all(int(4 * s))
	btn.add_theme_stylebox_override("normal",  sb)
	btn.add_theme_stylebox_override("hover",   sb)
	btn.add_theme_stylebox_override("pressed", sb)
	btn.add_theme_color_override("font_color", C_QUESTION)
	btn.pressed.connect(func() -> void: _grade(q, value))
	return btn

# ── Compiler (Shape.COMPILER) controls ─────────────────────────────
# The code editor (a CodeEdit carrying the language's real syntax
# highlighting / auto-indent / brace + code completion, prefilled with the
# question's starter code), the ERROR line directly underneath it, then the
# live output console and a Run button. The player's program runs through the
# game's LuaState compiler (the same interpreter the Lua robot uses) or the
# PythonState transpiler; print() output is captured and compared to
# answer_output on completion.
func _build_compiler_controls(q: DungeonQuestion) -> void:
	var s: float = Global.ui_scale
	var lang: String = q.language
	var entry := CodeEdit.new()
	entry.set_script(CODE_EDIT_SCRIPT)
	entry.custom_minimum_size = Vector2(int(440 * s), int(150 * s))
	entry.placeholder_text = "-- write your %s code here\nprint(\"...\")" % lang
	entry.text = q.starter_code
	entry.add_theme_font_override("font", CODE_FONT)
	entry.add_theme_font_size_override("font_size", int(14 * s))
	entry.gutters_draw_line_numbers     = true
	entry.code_completion_enabled       = true
	entry.indent_use_spaces             = true
	entry.indent_automatic              = true
	entry.auto_brace_completion_enabled = true
	entry.wrap_mode = TextEdit.LINE_WRAPPING_NONE
	# Highlighting + completion come from the shared language spec; an unknown
	# language keeps the plain editor so the question never soft-locks.
	var spec: LanguageSpecification = null
	if lang == "lua":
		spec = LUA_SPEC
	elif lang == "python":
		spec = PYTHON_SPEC
	if spec != null:
		entry.call("load_language_spec", spec)
		entry.text_changed.connect(Callable(entry, "code_completion_request"))
	_controls.add_child(entry)
	_code_entry = entry

	# ERROR line: sits DIRECTLY under the code box (the panel-bottom _feedback
	# label is reserved for MCQ answers / rubric results) so a failed compile
	# is read right where the code was typed.
	var err := Label.new()
	err.custom_minimum_size = Vector2(int(440 * s), int(18 * s))
	err.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	err.add_theme_font_size_override("font_size", int(12 * s))
	err.add_theme_color_override("font_color", C_ERROR)
	_controls.add_child(err)
	_error_label = err

	var out := RichTextLabel.new()
	out.bbcode_enabled = true
	out.custom_minimum_size = Vector2(int(440 * s), int(80 * s))
	out.scroll_following = true
	out.add_theme_font_size_override("font_size", int(13 * s))
	out.add_theme_color_override("default_color", C_MUTED)
	_controls.add_child(out)
	_compiler_output = out

	# Lua runs through LuaState; Python is transpiled to GDScript and run. Both
	# have a real interpreter now, so both get a "Run" button.
	var is_interp: bool = lang == "lua" or lang == "python"
	if not is_interp:
		# Unknown language: show the editor as a typed-code answer and grade it
		# by string comparison so the dungeon never soft-locks.
		var note := Label.new()
		note.text = "[%s] interpreter not available yet — type the correct code and press Check." % lang
		note.add_theme_font_size_override("font_size", int(11 * s))
		note.add_theme_color_override("font_color", Color(1.0, 0.85, 0.5, 1.0))
		note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_controls.add_child(note)

	var check_btn := Button.new()
	check_btn.text = "▶  %s" % ("Run" if is_interp else "Check")
	check_btn.custom_minimum_size = Vector2(int(140 * s), int(38 * s))
	check_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	check_btn.add_theme_font_size_override("font_size", int(13 * s))
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.14, 0.34, 0.20, 1.0); sb.border_color = C_BORDER
	sb.set_border_width_all(int(1 * s)); sb.set_corner_radius_all(int(4 * s))
	check_btn.add_theme_stylebox_override("normal",  sb)
	check_btn.add_theme_stylebox_override("hover",   sb)
	check_btn.add_theme_stylebox_override("pressed", sb)
	check_btn.add_theme_color_override("font_color", Color(0.70, 1.0, 0.80, 1.0))
	check_btn.pressed.connect(func() -> void: _run_compiler(q, entry.text))
	_controls.add_child(check_btn)

func _run_compiler(q: DungeonQuestion, code: String) -> void:
	code = code.strip_edges()
	if code.is_empty():
		_set_status("✘ Write some code first.", C_ERROR)
		return
	_set_status("", C_MUTED)   # a fresh run clears the previous error line
	# Python is transpiled to GDScript and executed by PythonState (its signals
	# mirror LuaState's, so the same capture/grade flow below is reused).
	if q.language == "python":
		_run_python(q, code)
		return
	# Unknown non-interpreted language: grade the typed code directly (the
	# answer_output field holds the expected code).
	if q.language != "lua":
		_grade_code_text(q, code)
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

# Runs Python through the transpiler (PythonState). Same pause/drain/grade
# flow as the Lua path above.
func _run_python(q: DungeonQuestion, code: String) -> void:
	if _python_state == null:
		_python_state = PythonState.new()
		add_child(_python_state)
		_python_state.connect("signal_print", _on_quiz_print)
		_python_state.connect("code_executed", _on_quiz_executed)
		_python_state.connect("code_failed", _on_quiz_failed)
	_compiler_q   = q
	_captured_output = ""
	if _compiler_output != null:
		_compiler_output.text = ""
	get_tree().paused = false
	_python_state.set("code", code)
	_python_state.call("run_code")

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
		_set_status("✘ " + error, C_ERROR)

# Compiler-question status — errors AND the rubric result — goes to the line
# directly under the code box, so it appears where the player was typing; MCQ
# questions (no editor) keep the panel-bottom _feedback label.
func _set_status(text: String, col: Color) -> void:
	var lbl: Label = _error_label if _error_label != null else _feedback
	if lbl == null:
		return
	lbl.text = text
	lbl.add_theme_color_override("font_color", col)

func _grade_compiler(q: DungeonQuestion) -> void:
	if q == null:
		return
	if _normalize_text(_captured_output) == _normalize_text(q.answer_output):
		_set_status("✔ Correct!", C_OK)
		_index += 1
		await get_tree().create_timer(0.6).timeout
		if _panel != null and _panel.visible:
			_show_question()
	else:
		_set_status("✘ Not quite — try again.", C_ERROR)

# Grades a non-interpreted language's typed code against the expected code in
# answer_output (normalized comparison) — the old LONG behaviour under COMPILER.
func _grade_code_text(q: DungeonQuestion, code: String) -> void:
	if _normalize_text(code) == _normalize_text(q.answer_output):
		_set_status("✔ Correct!", C_OK)
		_index += 1
		await get_tree().create_timer(0.6).timeout
		if _panel != null and _panel.visible:
			_show_question()
	else:
		_set_status("✘ Not quite — try again.", C_ERROR)

# MCQ grading: the button passes the option index (0..3); it's correct when it
# matches the question's correct_index.
func _grade(q: DungeonQuestion, input_text: String) -> void:
	if q.correct_option_index() == input_text.to_int():
		_feedback.text = "✔ Correct!"
		_feedback.add_theme_color_override("font_color", Color(0.45, 0.95, 0.55, 1.0))
		_index += 1
		await get_tree().create_timer(0.6).timeout
		if _panel != null and _panel.visible:
			_show_question()
	else:
		_feedback.text = "✘ Not quite — try again."
		_feedback.add_theme_color_override("font_color", Color(1.0, 0.55, 0.55, 1.0))

# Whitespace/case-insensitive comparison for compiler output grading.
var _ws_re: RegEx = null
func _normalize_text(text: String) -> String:
	if _ws_re == null:
		_ws_re = RegEx.new()
		_ws_re.compile("\\s+")
	return _ws_re.sub(text.strip_edges(), " ", true).to_lower()

func _complete_dungeon() -> void:
	if mission == null:
		return
	_cleared = true
	if _panel != null:
		_panel.visible = false
	Global.close_ui()

	Global.grant_item(mission.reward_item_path, 1)
	var mission_id: String = "dungeon_%d" % mission.dungeon_index
	Global.complete_mission(mission_id)
	# Star #1 of the dungeon's two — emitted after complete_mission (star #2)
	# so the mission UI popup that ends up on screen carries the clear flavor.
	Global.record_dungeon_clear(mission.dungeon_index)
	cleared.emit(mission.dungeon_index)

func _build_panel() -> Control:
	var s: float = Global.ui_scale
	var canvas := CanvasLayer.new()
	canvas.layer        = 30
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
	panel.custom_minimum_size = Vector2(int(520 * s), 0)
	var ps := StyleBoxFlat.new()
	ps.bg_color = C_PANEL; ps.border_color = C_BORDER
	ps.set_border_width_all(int(2 * s)); ps.set_corner_radius_all(int(8 * s))
	ps.content_margin_left = int(28 * s); ps.content_margin_right  = int(28 * s)
	ps.content_margin_top  = int(22 * s); ps.content_margin_bottom = int(22 * s)
	panel.add_theme_stylebox_override("panel", ps)
	center.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", int(14 * s))
	panel.add_child(vbox)

	var hdr := HBoxContainer.new()
	hdr.add_theme_constant_override("separation", int(8 * s))
	vbox.add_child(hdr)
	var icon := Label.new()
	icon.text = "❓"
	icon.add_theme_font_size_override("font_size", int(22 * s))
	hdr.add_child(icon)
	var title := Label.new()
	title.text = "Quiz Altar"
	title.add_theme_font_size_override("font_size", int(18 * s))
	title.add_theme_color_override("font_color", C_TITLE)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hdr.add_child(title)
	_q_progress = Label.new()
	_q_progress.add_theme_font_size_override("font_size", int(12 * s))
	_q_progress.add_theme_color_override("font_color", C_MUTED)
	hdr.add_child(_q_progress)

	var div := ColorRect.new()
	div.color = Color(0.45, 0.25, 0.55, 1.0); div.custom_minimum_size = Vector2(0, int(1 * s))
	vbox.add_child(div)

	_q_text = Label.new()
	_q_text.add_theme_font_size_override("font_size", int(15 * s))
	_q_text.add_theme_color_override("font_color", C_QUESTION)
	_q_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(_q_text)

	_controls = VBoxContainer.new()
	_controls.add_theme_constant_override("separation", int(10 * s))
	vbox.add_child(_controls)

	_feedback = Label.new()
	_feedback.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_feedback.add_theme_font_size_override("font_size", int(14 * s))
	vbox.add_child(_feedback)

	_close_btn = Button.new()
	_close_btn.text = "Close"
	_close_btn.custom_minimum_size = Vector2(int(120 * s), int(36 * s))
	_close_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_close_btn.pressed.connect(_close_quiz)
	vbox.add_child(_close_btn)

	return root

func _close_quiz() -> void:
	# Closing mid-quiz leaves progress untouched; reopening (_input → _start_quiz)
	# resets to question 1 so the player can pick up or restart at will.
	if _panel != null:
		_panel.visible = false
	Global.close_ui()
