extends Node2D
class_name QuizAltar
# ── Quiz Altar (final dungeon room object) ────────────────────────
# Placed by the dungeon generator in the last room. Presents every question
# embedded in the mission's `questions` (Array[DungeonQuestion], MCQ or COMPILER)
# one at a time. Answering ALL of them correctly clears the dungeon: the reward
# is granted, the mission/star state is recorded, and a results screen shows the
# player's achievements and 0-3 blue stars. HINT reveals the current question's
# hint (the button becomes NEXT to dismiss it); each hint or wrong code run
# removes one star, except that hints are free in the first dungeon. Done
# teleports back to the overworld, so quiz dungeons no longer use a physical
# exit tile.
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

var _panel:        Control = null
var _panel_scroll: ScrollContainer = null
var _content_scroll: ScrollContainer = null
var _touch_scroll_active: bool = false
var _touch_scroll_accum:  float = 0.0
var _q_progress: Label = null
var _q_text:     Label = null
var _feedback:   Label = null
var _controls:   Control = null
var _close_btn:  Button = null
var _hint_btn:   Button = null
var _run_btn:    Button = null
var _hint_panel: PanelContainer = null
var _hint_label: Label = null
var _answer_buttons: Array[Button] = []
var _hints_used: int = 0
var _hint_open:  bool = false
var _penalties:  int = 0
var _hint_busy:  bool = false
var _hint_last_press_ms: int = -1000
var _hint_run_failed: bool = false
var _answered:   int = 0
var _reward_root: Control = null
var _reward_visible: bool = false
var _reward_stars: int = 3
var _done_btn: Button = null
var _exiting: bool = false

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
var _compiler_grid:    GridContainer = null
var _error_label:      Label = null
var _lua_state:        Node = null
var _python_state:     PythonState = null
var _compiler_q:       DungeonQuestion = null
var _captured_output:  String = ""
# Async interpreter callbacks can arrive after the panel/altar was closed or
# freed. Only results from the current run may touch the UI.
var _accept_results:   bool = false
var _running:          bool = false
# Whether this altar currently holds a Global.open_ui() reference.
var _ui_registered:    bool = false

func _ready() -> void:
	add_to_group("QuizAltar")
	var tex := AtlasTexture.new()
	tex.atlas = SPRITE_TEXTURE
	# y=96 is the altar-art row in the dungeon atlas; y=128 is the floor row.
	tex.region = Rect2(352, 96, 32, 32)
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
	if _panel == null or _exiting:
		return
	var was_visible: bool = _panel.visible
	var was_reward: bool = _reward_visible
	var saved_stars: int = _reward_stars
	var saved_hints: int = _hints_used
	var saved_penalties: int = _penalties
	var saved_answered: int = _answered
	var saved_code: String = _code_entry.text if _code_entry != null \
			and is_instance_valid(_code_entry) else ""
	var canvas: Node = _panel.get_parent()
	if canvas != null:
		canvas.queue_free()
	_panel = null
	_panel_scroll = null
	_content_scroll = null
	_q_progress = null; _q_text = null; _feedback = null
	_controls = null; _close_btn = null; _hint_btn = null
	_run_btn = null; _compiler_grid = null
	_hint_panel = null; _hint_label = null
	_reward_root = null
	_code_entry = null; _compiler_output = null; _error_label = null
	if was_visible:
		_panel = _build_panel()
		_panel.visible = true
		if _ui_registered:
			Global.register_ui_back(_panel, Callable(self, "_escape_close"))
		_hints_used = saved_hints
		_penalties = saved_penalties
		_answered = saved_answered
		if was_reward:
			_reward_stars = saved_stars
			_show_reward_screen(saved_stars)
		else:
			_reward_visible = false
			_show_question()
			if _code_entry != null and is_instance_valid(_code_entry):
				_code_entry.text = saved_code

func _process(delta: float) -> void:
	if _panel != null and _panel.visible and _panel_scroll != null:
		var want: float = -(Global.ui_safe_insets.w + Global.keyboard_panel_inset())
		if not is_equal_approx(_panel_scroll.offset_bottom, want):
			_panel_scroll.offset_bottom = want
			# The panel itself no longer floats for a floating keyboard, but a
			# docked keyboard still shrinks the visible area: keep only the
			# focused code field scrolled into view.
			_ensure_editor_visible()
	_update_compiler_columns()
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
		if _reward_visible:
			return
		if _panel != null and _panel.visible:
			_panel.visible = false
			_release_ui()

func _input(event: InputEvent) -> void:
	if _panel != null and _panel.visible:
		if _reward_visible:
			if event.is_action_pressed("escape"):
				get_viewport().set_input_as_handled()
			return
		if _handle_touch_scroll(event):
			return
		if event.is_action_pressed("escape"):
			get_viewport().set_input_as_handled()
			if not Global.request_ui_back(event) and not Global.is_ui_back_event_consumed(event):
				_escape_close()
		return
	if _cleared or not _player_nearby or Global.block_mode or Global.any_ui_open():
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_start_quiz()

## ScrollContainer does not consume finger drags on Android. _input runs before
## GUI, so scroll the question body here while leaving taps/buttons untouched.
## A drag that starts on the code editor is excluded so touch text selection
## still works.
func _handle_touch_scroll(event: InputEvent) -> bool:
	if _content_scroll == null or not is_instance_valid(_content_scroll):
		return false
	if event is InputEventScreenTouch:
		var t := event as InputEventScreenTouch
		if t.pressed:
			var over_code: bool = _code_entry != null \
				and is_instance_valid(_code_entry) \
				and _code_entry.get_global_rect().has_point(t.position)
			_touch_scroll_active = not over_code \
				and _content_scroll.get_global_rect().has_point(t.position) \
				and not _touch_over_button(t.position)
			_touch_scroll_accum = 0.0
		else:
			_touch_scroll_active = false
		return false
	if event is InputEventScreenDrag and _touch_scroll_active:
		var d := event as InputEventScreenDrag
		_touch_scroll_accum -= d.relative.y
		var step: int = int(_touch_scroll_accum)
		if step != 0:
			_content_scroll.scroll_vertical += step
			_touch_scroll_accum -= float(step)
		get_viewport().set_input_as_handled()
		return true
	return false

func _touch_over_button(pos: Vector2) -> bool:
	for b in _content_scroll.find_children("*", "Button", true, false):
		if (b as Control).get_global_rect().has_point(pos):
			return true
	return false

func _start_quiz() -> void:
	if mission != null and Global.is_dungeon_cleared(mission.dungeon_index):
		return
	if _panel == null:
		_panel = _build_panel()
	if _reward_root != null:
		_reward_root.queue_free()
		_reward_root = null
	_reward_visible = false
	_done_btn = null
	_index = 0
	_hints_used = 0
	_penalties = 0
	_answered = 0
	_hint_open = false
	_hint_busy = false
	_hint_run_failed = false
	if mission != null:
		_hints_used = Global.dungeon_quiz_hints_for(mission.dungeon_index)
		_penalties = Global.dungeon_quiz_penalties_for(mission.dungeon_index)
	_exiting = false
	_panel.visible = true
	_panel_scroll.visible = true
	if _content_scroll != null:
		_content_scroll.scroll_vertical = 0
	if _panel_scroll != null:
		_panel_scroll.scroll_vertical = 0
	if _hint_btn != null:
		_hint_btn.visible = true
		_hint_btn.disabled = false
	if _run_btn != null:
		_run_btn.visible = false
	if _close_btn != null:
		_close_btn.visible = true
	# Clear any stale compiler-run suspension before registering this opening;
	# otherwise a previous interrupted Run can leave the quiz visibly open while
	# the world keeps simulating.
	Global.resume_ui_pause(self)
	Global.open_ui()
	_ui_registered = true
	Global.register_ui_back(_panel, Callable(self, "_escape_close"))
	# open_ui() is the normal path; this explicit fallback guarantees the quiz
	# always autopauses even if an older UI refcount edge case slipped through.
	if not get_tree().paused:
		get_tree().paused = true
	if _questions.is_empty():
		# Mission with no questions is trivially clearable (still shows the
		# reward summary and Done button).
		_complete_dungeon()
		return
	_show_question()

func _show_question() -> void:
	if _cleared or _reward_visible:
		return
	if _index >= _questions.size():
		_complete_dungeon()
		return
	_hint_busy = false
	_hint_open = false
	_hint_run_failed = false
	if _hint_btn != null:
		_hint_btn.disabled = false
		_hint_btn.visible = true
		_hint_btn.text = "HINT"
	if _hint_panel != null:
		_hint_panel.visible = false
	_rebuild_controls()
	if _content_scroll != null:
		_content_scroll.scroll_vertical = 0
	call_deferred("_scroll_content_top")

func _rebuild_controls() -> void:
	var q: DungeonQuestion = _questions[_index]
	_q_progress.text = "Question %d / %d" % [_index + 1, _questions.size()]
	_q_text.text = q.question

	for child in _controls.get_children().duplicate():
		child.queue_free()
	_answer_buttons.clear()
	# The nodes just freed are gone at end of frame — drop the references so a
	# late print/error signal can never touch a freed object.
	_code_entry      = null
	_compiler_output = null
	_error_label     = null
	_compiler_grid   = null
	_hint_open = false
	_hint_run_failed = false
	if _hint_panel != null:
		_hint_panel.visible = false
	if _hint_btn != null:
		_hint_btn.text = "HINT"
	if _run_btn != null:
		_run_btn.visible = false
		_run_btn.disabled = false

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
	btn.custom_minimum_size = Vector2(0, int(42 * s))
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	btn.add_theme_font_size_override("font_size", Global.ui_font_size(13))
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.14, 0.18, 0.34, 1.0); sb.border_color = C_BORDER
	sb.set_border_width_all(int(1 * s)); sb.set_corner_radius_all(int(4 * s))
	btn.add_theme_stylebox_override("normal",  sb)
	btn.add_theme_stylebox_override("hover",   sb)
	btn.add_theme_stylebox_override("pressed", sb)
	btn.add_theme_color_override("font_color", C_QUESTION)
	btn.set_meta("answer_value", value)
	btn.set_meta("base_style", sb)
	btn.pressed.connect(func() -> void: _grade(q, value))
	_answer_buttons.append(btn)
	return btn

func _scroll_content_top() -> void:
	if _content_scroll != null and is_instance_valid(_content_scroll):
		_content_scroll.scroll_vertical = 0

# Brings only the focused code field into view inside the question scroll. The
# panel itself stays put, which is what a floating Android keyboard needs.
func _ensure_editor_visible() -> void:
	if _code_entry == null or not is_instance_valid(_code_entry):
		return
	if not _code_entry.has_focus():
		return
	if _content_scroll != null and is_instance_valid(_content_scroll):
		_content_scroll.call_deferred("ensure_control_visible", _code_entry)


## Each hint reveal or wrong code run costs one blue star, except that hints are
## free in the first main dungeon. Completion itself is independent of score.
static func stars_for_penalties(penalties: int) -> int:
	return clampi(3 - maxi(0, penalties), 0, 3)

## Backwards-compatible alias used by older callers/tests.
static func stars_for_hints(hints_used: int) -> int:
	return stars_for_penalties(hints_used)


func _hint_code_for(q: DungeonQuestion) -> String:
	# Both supported quiz languages print the expected output. c_escape keeps
	# quotes/newlines/backslashes valid inside the generated string literal.
	if q.language == "lua" or q.language == "python":
		return "print(\"%s\")" % q.answer_output.c_escape()
	# Unknown/non-interpreted languages grade typed code against answer_output,
	# so the hint must fill that exact code instead of a print() wrapper.
	return q.answer_output


func _hint_text_for(q: DungeonQuestion) -> String:
	if q == null:
		return ""
	if q.is_compiler():
		var base := q.hint.strip_edges()
		if base.is_empty():
			base = "Expected output: %s" % q.answer_output
		return base + "\nThe correct code is filled in. Press RUN to check it."
	# MCQ: the hint highlights the correct button, so keep the text short.
	return "The correct answer is highlighted. Tap it when you are ready."


## HINT prepares the current question's answer without submitting it:
## * COMPILER: fills the editor with the expected print() program.
## * MCQ: highlights the correct answer button.
## The player still presses RUN / the answer button manually.
func _on_hint_button_pressed() -> void:
	if _cleared or _reward_visible or _running or _index >= _questions.size():
		return
	var now := Time.get_ticks_msec()
	if now - _hint_last_press_ms < 220:
		return
	_hint_last_press_ms = now
	if _hint_open:
		_hide_hint()
	else:
		_reveal_hint()


func _reveal_hint() -> void:
	var q: DungeonQuestion = _questions[_index]
	_hints_used += 1
	if mission != null:
		_penalties += Global.record_quiz_hint(mission.dungeon_index)
	_hint_open = true
	_hint_run_failed = false
	if q.is_compiler():
		# Prepare the answer in the editor but do NOT run it. The player must
		# still press RUN, so the hint never bypasses execution or grading.
		if _code_entry != null and is_instance_valid(_code_entry):
			var answer: String = _hint_code_for(q)
			_code_entry.text = answer
			_code_entry.set_caret_line(0)
			_code_entry.set_caret_column(answer.length())
		if _error_label != null:
			_error_label.text = ""
	else:
		_highlight_correct_answer(q)
	if _hint_panel != null:
		_hint_panel.visible = true
	if _hint_label != null:
		_hint_label.text = _hint_text_for(q)
	if _hint_btn != null:
		_hint_btn.text = "NEXT"
		_hint_btn.disabled = false
	if _feedback != null and not q.is_compiler():
		_feedback.text = ""


func _hide_hint() -> void:
	_hint_open = false
	_hint_run_failed = false
	if _hint_panel != null:
		_hint_panel.visible = false
	if _hint_btn != null:
		_hint_btn.text = "HINT"
		_hint_btn.disabled = false
	# Compiler code stays in the editor so the player can run it manually.
	# MCQ highlighting is dismissed with the hint panel.
	_clear_answer_highlight()


func _highlight_correct_answer(q: DungeonQuestion) -> void:
	if q == null:
		return
	var correct := str(q.correct_option_index())
	var s: float = Global.ui_scale
	for btn in _answer_buttons:
		if not is_instance_valid(btn):
			continue
		if str(btn.get_meta("answer_value", "")) != correct:
			continue
		var base: Variant = btn.get_meta("base_style", null)
		if not (base is StyleBoxFlat):
			continue
		var sb := (base as StyleBoxFlat).duplicate() as StyleBoxFlat
		sb.bg_color = Color(0.28, 0.24, 0.10, 1.0)
		sb.border_color = Color(1.0, 0.84, 0.30, 1.0)
		sb.set_border_width_all(maxi(2, int(round(2.0 * s))))
		btn.add_theme_stylebox_override("normal", sb)
		btn.add_theme_stylebox_override("hover", sb)
		btn.add_theme_stylebox_override("pressed", sb)
		btn.add_theme_color_override("font_color", Color(1.0, 0.94, 0.68, 1.0))


func _clear_answer_highlight() -> void:
	for btn in _answer_buttons:
		if not is_instance_valid(btn):
			continue
		var base: Variant = btn.get_meta("base_style", null)
		if not (base is StyleBoxFlat):
			continue
		btn.add_theme_stylebox_override("normal", base as StyleBoxFlat)
		btn.add_theme_stylebox_override("hover", base as StyleBoxFlat)
		btn.add_theme_stylebox_override("pressed", base as StyleBoxFlat)
		btn.add_theme_color_override("font_color", C_QUESTION)


## Compatibility alias for callers/tests from the old auto-complete flow.
func _use_hint() -> void:
	_on_hint_button_pressed()


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
	entry.custom_minimum_size = Vector2(int(320 * s), int(150 * s))
	entry.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	entry.placeholder_text = "-- write your %s code here\nprint(\"...\")" % lang
	entry.text = q.starter_code
	entry.add_theme_font_override("font", CODE_FONT)
	entry.add_theme_font_size_override("font_size", Global.ui_font_size(14))
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
	# Do not auto-scroll to the editor on focus: opening a compiler question
	# must leave the question text visible. The keyboard-offset path scrolls to
	# the editor only after the player has actually focused it.
	_code_entry = entry
	entry.focus_entered.connect(_ensure_editor_visible)

	# ERROR line: sits DIRECTLY under the code box (the panel-bottom _feedback
	# label is reserved for MCQ answers / rubric results) so a failed compile
	# is read right where the code was typed.
	var err := Label.new()
	err.custom_minimum_size = Vector2(0, int(18 * s))
	err.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	err.add_theme_font_size_override("font_size", Global.ui_font_size(12))
	err.add_theme_color_override("font_color", C_ERROR)
	_error_label = err

	# Code and output share a responsive grid: side-by-side on wide/mobile
	# landscape screens, stacked vertically when the viewport is narrow.
	var grid := GridContainer.new()
	grid.name = "CompilerColumns"
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", int(12 * s))
	grid.add_theme_constant_override("v_separation", int(8 * s))
	_controls.add_child(grid)
	_compiler_grid = grid

	var code_col := VBoxContainer.new()
	code_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	code_col.size_flags_vertical = Control.SIZE_EXPAND_FILL
	code_col.add_theme_constant_override("separation", int(4 * s))
	grid.add_child(code_col)
	var code_lbl := Label.new()
	code_lbl.text = "CODE"
	code_lbl.add_theme_font_size_override("font_size", Global.ui_font_size(10))
	code_lbl.add_theme_color_override("font_color", C_MUTED)
	code_col.add_child(code_lbl)
	code_col.add_child(entry)
	code_col.add_child(err)

	var out_col := VBoxContainer.new()
	out_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	out_col.size_flags_vertical = Control.SIZE_EXPAND_FILL
	out_col.add_theme_constant_override("separation", int(4 * s))
	grid.add_child(out_col)
	var out_lbl := Label.new()
	out_lbl.text = "OUTPUT"
	out_lbl.add_theme_font_size_override("font_size", Global.ui_font_size(10))
	out_lbl.add_theme_color_override("font_color", C_MUTED)
	out_col.add_child(out_lbl)

	var out_box := PanelContainer.new()
	out_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	out_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	out_box.custom_minimum_size = Vector2(int(260 * s), int(150 * s))
	var obs := StyleBoxFlat.new()
	obs.bg_color = Color(0.05, 0.07, 0.14, 1.0)
	obs.border_color = C_BORDER
	obs.set_border_width_all(int(1 * s))
	obs.set_corner_radius_all(int(4 * s))
	obs.content_margin_left = int(8 * s)
	obs.content_margin_right = int(8 * s)
	obs.content_margin_top = int(6 * s)
	obs.content_margin_bottom = int(6 * s)
	out_box.add_theme_stylebox_override("panel", obs)
	var out := RichTextLabel.new()
	out.bbcode_enabled = true
	out.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	out.size_flags_vertical = Control.SIZE_EXPAND_FILL
	out.scroll_following = true
	out.add_theme_font_size_override("font_size", Global.ui_font_size(13))
	out.add_theme_color_override("default_color", C_MUTED)
	out_box.add_child(out)
	out_col.add_child(out_box)
	_compiler_output = out
	_update_compiler_columns()

	# Lua runs through LuaState; Python is transpiled to GDScript and run. Both
	# have a real interpreter now, so both get a "Run" button.
	var is_interp: bool = lang == "lua" or lang == "python"
	if not is_interp:
		# Unknown language: show the editor as a typed-code answer and grade it
		# by string comparison so the dungeon never soft-locks.
		var note := Label.new()
		note.text = "[%s] interpreter not available yet — type the correct code and press Check." % lang
		note.add_theme_font_size_override("font_size", Global.ui_font_size(11))
		note.add_theme_color_override("font_color", Color(1.0, 0.85, 0.5, 1.0))
		note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_controls.add_child(note)
	if _run_btn != null:
		_run_btn.visible = true
		_run_btn.disabled = false
		_run_btn.text = "▶  %s" % ("RUN" if is_interp else "CHECK")
		_run_btn.tooltip_text = "Run the current code and compare its output." \
			if is_interp else "Check the typed code against the expected answer."

# The header Run/Check button is the only run trigger for compiler questions.
func _on_run_pressed() -> void:
	if _running or _index < 0 or _index >= _questions.size():
		return
	var q: DungeonQuestion = _questions[_index]
	if q == null or not q.is_compiler():
		return
	if _code_entry == null or not is_instance_valid(_code_entry):
		return
	_run_compiler(q, _code_entry.text)

# Keep code and output side by side whenever the usable width can show two
# readable columns; narrow/portrait screens stack them instead. Re-evaluated
# every frame so rotation, safe-area changes and keyboard insets reflow live.
func _update_compiler_columns() -> void:
	if _compiler_grid == null or not is_instance_valid(_compiler_grid):
		return
	var s: float = Global.ui_scale
	var content_w: float = Global.ui_content_rect().size.x
	if content_w <= 0.0:
		var vp := get_viewport()
		content_w = vp.get_visible_rect().size.x if vp != null else 0.0
	var columns: int = 2 if content_w >= 700.0 * s else 1
	if _compiler_grid.columns != columns:
		_compiler_grid.columns = columns

func _run_compiler(q: DungeonQuestion, code: String) -> void:
	if _running:
		return
	code = code.strip_edges()
	if code.is_empty():
		_set_status("✘ Write some code first.", C_ERROR)
		return
	CrashLogger.code(q.language, "QUIZ_RUN", "question=%s chars=%d\n%s" % [
		(q.question.left(80) if q != null else "?"), code.length(), code])
	_set_status("", C_MUTED)   # a fresh run clears the previous error line
	if _hint_btn != null:
		_hint_btn.disabled = true
	# Python is transpiled to GDScript and executed by PythonState (its signals
	# mirror LuaState's, so the same capture/grade flow below is reused).
	if q.language == "python":
		_running = true
		_accept_results = true
		_set_run_busy(true)
		_run_python(q, code)
		return
	# Unknown non-interpreted language: grade the typed code directly (the
	# answer_output field holds the expected code).
	if q.language != "lua":
		_grade_code_text(q, code)
		return
	_running = true
	_accept_results = true
	_set_run_busy(true)
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
	Global.suspend_ui_pause(self)
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
	Global.suspend_ui_pause(self)
	_python_state.set("code", code)
	_python_state.call("run_code")

func _on_quiz_print(text: String) -> void:
	if not _accept_results:
		return
	if _compiler_q != null and _compiler_q.language == "lua":
		CrashLogger.code("lua", "OUT", "quiz: " + text)
	_captured_output += text + "\n"
	if _compiler_output != null:
		_compiler_output.append_text("[color=#aaddff]» %s[/color]\n" % text)

func _on_quiz_executed() -> void:
	if not _accept_results:
		return
	CrashLogger.code("lua" if _compiler_q != null and _compiler_q.language == "lua" else "python",
		"QUIZ_OK", "question=%s" % ((_compiler_q.question.left(80) if _compiler_q != null else "?")))
	# Code ran cleanly; wait briefly for the queued print signals to drain out
	# of physics_process, then re-pause and grade the captured output.
	await get_tree().create_timer(0.35).timeout
	if not _accept_results or not is_inside_tree():
		return
	if _panel == null or not _panel.visible:
		return  # quiz closed while the code was running
	_accept_results = false
	_running = false
	Global.resume_ui_pause(self)
	# A successful run from the dungeon quiz counts for "Run your first Lua
	# program" just like a run from the Lua robot editor.
	if _compiler_q != null and _compiler_q.language == "lua":
		Global.complete_mission("run_program")
		Global.add_mission_progress("side_lua_automator", 1)
	_grade_compiler(_compiler_q)

func _on_quiz_failed(error: String) -> void:
	if not _accept_results:
		return
	CrashLogger.code("lua" if _compiler_q != null and _compiler_q.language == "lua" else "python",
		"QUIZ_FAIL", "question=%s: %s" % [
			(_compiler_q.question.left(80) if _compiler_q != null else "?"), error])
	_accept_results = false
	_running = false
	_record_incorrect_submission()
	_hint_run_failed = _hint_open
	if _panel != null and _panel.visible:
		Global.resume_ui_pause(self)
		_hint_busy = false
		if _hint_btn != null:
			_hint_btn.disabled = false
		_set_run_busy(false)
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

func _set_run_busy(busy: bool) -> void:
	if _run_btn != null and is_instance_valid(_run_btn):
		_run_btn.disabled = busy


func _record_incorrect_submission() -> void:
	if mission == null:
		return
	_penalties += Global.record_quiz_mistake(mission.dungeon_index)

func _grade_compiler(q: DungeonQuestion) -> void:
	if q == null:
		return
	if _normalize_text(_captured_output) == _normalize_text(q.answer_output):
		_set_status("✔ Correct!", C_OK)
		_index += 1
		_answered += 1
		await get_tree().create_timer(0.6).timeout
		if not is_inside_tree():
			return
		if _panel != null and _panel.visible:
			_show_question()
	else:
		_set_status("✘ Not quite — try again.", C_ERROR)
		_record_incorrect_submission()
		_hint_run_failed = _hint_open
		_hint_busy = false
		if _hint_btn != null:
			_hint_btn.disabled = false
		_set_run_busy(false)

# Grades a non-interpreted language's typed code against the expected code in
# answer_output (normalized comparison) — the old LONG behaviour under COMPILER.
func _grade_code_text(q: DungeonQuestion, code: String) -> void:
	if _normalize_text(code) == _normalize_text(q.answer_output):
		_set_status("✔ Correct!", C_OK)
		_index += 1
		_answered += 1
		await get_tree().create_timer(0.6).timeout
		if not is_inside_tree():
			return
		if _panel != null and _panel.visible:
			_show_question()
	else:
		_set_status("✘ Not quite — try again.", C_ERROR)
		_record_incorrect_submission()
		_hint_run_failed = _hint_open
		_hint_busy = false
		if _hint_btn != null:
			_hint_btn.disabled = false
		_set_run_busy(false)

# MCQ grading: the button passes the option index (0..3); it's correct when it
# matches the question's correct_index.
func _grade(q: DungeonQuestion, input_text: String) -> void:
	if q.correct_option_index() == input_text.to_int():
		_feedback.text = "✔ Correct!"
		_feedback.add_theme_color_override("font_color", Color(0.45, 0.95, 0.55, 1.0))
		_index += 1
		_answered += 1
		await get_tree().create_timer(0.6).timeout
		if not is_inside_tree():
			return
		if _panel != null and _panel.visible:
			_show_question()
	else:
		_feedback.text = "✘ Not quite — try again."
		_feedback.add_theme_color_override("font_color", Color(1.0, 0.55, 0.55, 1.0))
		_hint_run_failed = _hint_open

# Whitespace/case-insensitive comparison for compiler output grading.
var _ws_re: RegEx = null
func _normalize_text(text: String) -> String:
	if _ws_re == null:
		_ws_re = RegEx.new()
		_ws_re.compile("\\s+")
	return _ws_re.sub(text.strip_edges(), " ", true).to_lower()

func _complete_dungeon() -> void:
	if mission == null or _cleared:
		return
	# Extra dungeons can contain multiple Quiz Altars. The first completion
	# clears the dungeon; later altars must not grant the reward again.
	if Global.is_dungeon_cleared(mission.dungeon_index):
		_cleared = true
		if _panel != null:
			_panel.visible = false
		_release_ui()
		return
	_cleared = true
	_accept_results = false
	_running = false
	_hint_busy = false
	_answered = maxi(_answered, _questions.size())
	_reward_stars = stars_for_penalties(_penalties)

	Global.grant_item(mission.reward_item_path, 1)
	var mission_id: String = "dungeon_%d" % mission.dungeon_index
	Global.complete_mission(mission_id)
	# Mission star (1) + clear star (>=2) + perfect bonus (3). The reward
	# screen stays open until the player reviews it and presses Done.
	Global.record_dungeon_clear(mission.dungeon_index, _reward_stars)
	cleared.emit(mission.dungeon_index)
	_show_reward_screen(_reward_stars)


func _show_reward_screen(stars: int) -> void:
	if _panel == null:
		return
	_touch_scroll_active = false
	_touch_scroll_accum = 0.0
	if _reward_root != null and is_instance_valid(_reward_root):
		_reward_root.queue_free()
	_reward_visible = true
	_reward_stars = clampi(stars, 0, 3)
	_panel_scroll.visible = false
	if _hint_btn != null:
		_hint_btn.visible = false
	if _run_btn != null:
		_run_btn.visible = false
	if _close_btn != null:
		_close_btn.visible = false

	var s: float = Global.ui_scale
	var root := Control.new()
	root.name = "RewardScreen"
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.process_mode = Node.PROCESS_MODE_ALWAYS
	_panel.add_child(root)
	_reward_root = root

	var dim := ColorRect.new()
	dim.color = Color(0.0, 0.0, 0.0, 0.58)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(dim)

	var scroll := ScrollContainer.new()
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	Global.apply_safe_area(scroll)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	root.add_child(scroll)

	var center := CenterContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	center.custom_minimum_size = Global.ui_content_rect().size
	scroll.add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Global.ui_fit_min_size(Vector2(540, 420))
	var ps := StyleBoxFlat.new()
	ps.bg_color = C_PANEL
	ps.border_color = C_BORDER
	ps.set_border_width_all(int(2 * s))
	ps.set_corner_radius_all(int(8 * s))
	ps.content_margin_left = int(26 * s)
	ps.content_margin_right = int(26 * s)
	ps.content_margin_top = int(20 * s)
	ps.content_margin_bottom = int(20 * s)
	panel.add_theme_stylebox_override("panel", ps)
	center.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", int(9 * s))
	panel.add_child(vbox)

	var title := Label.new()
	title.text = "DUNGEON CLEARED"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", Global.ui_font_size(22))
	title.add_theme_color_override("font_color", C_TITLE)
	vbox.add_child(title)

	var mission_name := mission.mission_name if mission != null else "Dungeon"
	if mission_name.strip_edges().is_empty():
		mission_name = "Dungeon %d" % (mission.dungeon_index if mission != null else 0)
	var name_lbl := Label.new()
	name_lbl.text = "%s  ·  %s" % [mission_name,
		Global.dungeon_difficulty(mission.dungeon_index) if mission != null else "Medium"]
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_lbl.add_theme_font_size_override("font_size", Global.ui_font_size(13))
	name_lbl.add_theme_color_override("font_color", C_MUTED)
	vbox.add_child(name_lbl)

	var div := ColorRect.new()
	div.color = Color(0.45, 0.25, 0.55, 1.0)
	div.custom_minimum_size = Vector2(0, int(1 * s))
	vbox.add_child(div)

	var ach := Label.new()
	ach.text = "ACHIEVEMENTS"
	ach.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ach.add_theme_font_size_override("font_size", Global.ui_font_size(11))
	ach.add_theme_color_override("font_color", C_MUTED)
	vbox.add_child(ach)

	_reward_row(vbox, "Questions answered",
		"%d / %d" % [_answered, _questions.size()])
	_reward_row(vbox, "Hints used", str(_hints_used))
	_reward_row(vbox, "Star penalties", str(_penalties))
	var reward_data: ItemData = null
	if mission != null and not mission.reward_item_path.is_empty():
		reward_data = load(mission.reward_item_path) as ItemData
	_reward_row(vbox, "Dungeon reward",
		reward_data.item_name if reward_data != null else "—")

	var div2 := ColorRect.new()
	div2.color = Color(0.45, 0.25, 0.55, 1.0)
	div2.custom_minimum_size = Vector2(0, int(1 * s))
	vbox.add_child(div2)

	var stars_lbl := Label.new()
	stars_lbl.text = "BLUE STARS EARNED"
	stars_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stars_lbl.add_theme_font_size_override("font_size", Global.ui_font_size(11))
	stars_lbl.add_theme_color_override("font_color", C_MUTED)
	vbox.add_child(stars_lbl)

	var stars_row := HBoxContainer.new()
	stars_row.alignment = BoxContainer.ALIGNMENT_CENTER
	stars_row.add_theme_constant_override("separation", int(10 * s))
	vbox.add_child(stars_row)
	for i in range(3):
		var star := StarIcon.new()
		stars_row.add_child(star)
		star.setup(StarIcon.BLUE if i < _reward_stars else Color(0.30, 0.34, 0.48, 0.9),
			28.0 * s)

	var note := Label.new()
	note.text = "3 stars start  ·  each hint or wrong run costs 1  ·  first-dungeon hints are free  ·  0 stars still clears"
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.add_theme_font_size_override("font_size", Global.ui_font_size(10))
	note.add_theme_color_override("font_color", C_MUTED)
	vbox.add_child(note)

	var done := Button.new()
	_done_btn = done
	done.text = "DONE — RETURN TO WORLD"
	done.custom_minimum_size = Vector2(int(260 * s), int(42 * s))
	done.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	done.add_theme_font_size_override("font_size", Global.ui_font_size(13))
	var db := StyleBoxFlat.new()
	db.bg_color = Color(0.15, 0.42, 0.22, 1.0)
	db.border_color = C_BORDER
	db.set_border_width_all(int(1 * s))
	db.set_corner_radius_all(int(4 * s))
	done.add_theme_stylebox_override("normal", db)
	done.add_theme_stylebox_override("hover", db)
	done.add_theme_stylebox_override("pressed", db)
	done.add_theme_color_override("font_color", Color(0.80, 1.0, 0.82, 1.0))
	done.pressed.connect(_on_reward_done)
	vbox.add_child(done)


func _reward_row(parent: VBoxContainer, label_text: String, value_text: String) -> void:
	var s: float = Global.ui_scale
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", int(10 * s))
	parent.add_child(row)
	var l := Label.new()
	l.text = label_text
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.add_theme_font_size_override("font_size", Global.ui_font_size(12))
	l.add_theme_color_override("font_color", C_MUTED)
	row.add_child(l)
	var v := Label.new()
	v.text = value_text
	v.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	v.add_theme_font_size_override("font_size", Global.ui_font_size(12))
	v.add_theme_color_override("font_color", C_TITLE)
	row.add_child(v)


func _on_reward_done() -> void:
	if _exiting:
		return
	_exiting = true
	if _reward_root != null and is_instance_valid(_reward_root):
		_reward_root.visible = false
	if _panel != null:
		_panel.visible = false
	_release_ui()
	if is_instance_valid(Global.game_node) and Global.game_node.has_method("exit_dungeon"):
		Global.game_node.call("exit_dungeon")


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

	var scroll := ScrollContainer.new()
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	Global.apply_safe_area(scroll)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	root.add_child(scroll)
	_panel_scroll = scroll

	var center := CenterContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var content_size: Vector2 = Global.ui_content_rect().size
	center.custom_minimum_size = Vector2(
		maxf(1.0, content_size.x - 16.0 * s), content_size.y)
	scroll.add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Global.ui_fit_min_size(Vector2(520, 380))
	panel.mouse_filter = Control.MOUSE_FILTER_PASS
	var ps := StyleBoxFlat.new()
	ps.bg_color = C_PANEL; ps.border_color = C_BORDER
	ps.set_border_width_all(int(2 * s)); ps.set_corner_radius_all(int(8 * s))
	ps.content_margin_left = int(28 * s); ps.content_margin_right  = int(28 * s)
	ps.content_margin_top  = int(22 * s); ps.content_margin_bottom = int(22 * s)
	panel.add_theme_stylebox_override("panel", ps)
	center.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", int(14 * s))
	vbox.mouse_filter = Control.MOUSE_FILTER_PASS
	panel.add_child(vbox)

	var hdr := HBoxContainer.new()
	hdr.add_theme_constant_override("separation", int(8 * s))
	vbox.add_child(hdr)
	var icon := Label.new()
	icon.text = "❓"
	icon.add_theme_font_size_override("font_size", Global.ui_font_size(22))
	hdr.add_child(icon)
	var title := Label.new()
	title.text = "Quiz Altar"
	title.add_theme_font_size_override("font_size", Global.ui_font_size(18))
	title.add_theme_color_override("font_color", C_TITLE)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hdr.add_child(title)
	_q_progress = Label.new()
	_q_progress.add_theme_font_size_override("font_size", Global.ui_font_size(12))
	_q_progress.add_theme_color_override("font_color", C_MUTED)
	hdr.add_child(_q_progress)

	_hint_btn = Button.new()
	_hint_btn.text = "HINT"
	_hint_btn.tooltip_text = "Prepare this question's answer: fill the code or highlight the correct choice. NEXT dismisses the hint. Each hint costs one blue star except in the first dungeon."
	_hint_btn.custom_minimum_size = Vector2(int(76 * s), int(30 * s))
	_hint_btn.add_theme_font_size_override("font_size", Global.ui_font_size(11))
	var hb := StyleBoxFlat.new()
	hb.bg_color = Color(0.20, 0.16, 0.36, 1.0)
	hb.border_color = C_BORDER
	hb.set_border_width_all(int(1 * s))
	hb.set_corner_radius_all(int(4 * s))
	hb.content_margin_left = int(8 * s)
	hb.content_margin_right = int(8 * s)
	_hint_btn.add_theme_stylebox_override("normal", hb)
	_hint_btn.add_theme_stylebox_override("hover", hb)
	_hint_btn.add_theme_stylebox_override("pressed", hb)
	_hint_btn.add_theme_color_override("font_color", C_TITLE)
	_hint_btn.pressed.connect(_on_hint_button_pressed)
	hdr.add_child(_hint_btn)

	# Run/Check lives beside Hint in the header so the code/output area gets the
	# full width below it. It is visible only for COMPILER questions.
	_run_btn = Button.new()
	_run_btn.text = "▶  RUN"
	_run_btn.tooltip_text = "Run the current code and compare its output."
	_run_btn.custom_minimum_size = Vector2(int(96 * s), int(30 * s))
	_run_btn.add_theme_font_size_override("font_size", Global.ui_font_size(11))
	var rb := StyleBoxFlat.new()
	rb.bg_color = Color(0.14, 0.34, 0.20, 1.0)
	rb.border_color = C_BORDER
	rb.set_border_width_all(int(1 * s))
	rb.set_corner_radius_all(int(4 * s))
	rb.content_margin_left = int(8 * s)
	rb.content_margin_right = int(8 * s)
	_run_btn.add_theme_stylebox_override("normal", rb)
	_run_btn.add_theme_stylebox_override("hover", rb)
	_run_btn.add_theme_stylebox_override("pressed", rb)
	_run_btn.add_theme_color_override("font_color", Color(0.80, 1.0, 0.80, 1.0))
	_run_btn.visible = false
	_run_btn.pressed.connect(_on_run_pressed)
	hdr.add_child(_run_btn)

	var div := ColorRect.new()
	div.color = Color(0.45, 0.25, 0.55, 1.0); div.custom_minimum_size = Vector2(0, int(1 * s))
	vbox.add_child(div)

	# Question + answer controls scroll inside a viewport-capped panel, keeping
	# the title, HINT and Close reachable on phones instead of a panel that runs
	# off the bottom of the screen. The question starts at the top of the scroll;
	# any compiler-editor auto-scroll below is reset when a question is shown.
	var content_scroll := ScrollContainer.new()
	content_scroll.name = "QuestionScroll"
	content_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	content_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	content_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content_scroll.mouse_filter = Control.MOUSE_FILTER_STOP
	vbox.add_child(content_scroll)
	_content_scroll = content_scroll

	var content_vbox := VBoxContainer.new()
	content_vbox.add_theme_constant_override("separation", int(10 * s))
	content_vbox.mouse_filter = Control.MOUSE_FILTER_PASS
	# The scroll's child does not inherit its width automatically. Without this,
	# an autowrapped label (min width 1) collapses the whole VBox to ~2 px, so
	# every question and answer button renders as a vertical sliver.
	content_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content_scroll.add_child(content_vbox)

	_q_text = Label.new()
	_q_text.add_theme_font_size_override("font_size", Global.ui_font_size(15))
	_q_text.add_theme_color_override("font_color", C_QUESTION)
	_q_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_q_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content_vbox.add_child(_q_text)

	# Hint text lives in the question body, above the answer/code controls. It
	# persists across Hint/Next toggles and never replaces or advances the
	# current question.
	_hint_panel = PanelContainer.new()
	_hint_panel.name = "HintPanel"
	_hint_panel.visible = false
	var hpb := StyleBoxFlat.new()
	hpb.bg_color = Color(0.10, 0.14, 0.28, 0.98)
	hpb.border_color = Color(0.55, 0.72, 0.98, 0.95)
	hpb.set_border_width_all(int(1 * s))
	hpb.set_corner_radius_all(int(5 * s))
	hpb.content_margin_left = int(10 * s)
	hpb.content_margin_right = int(10 * s)
	hpb.content_margin_top = int(7 * s)
	hpb.content_margin_bottom = int(7 * s)
	_hint_panel.add_theme_stylebox_override("panel", hpb)
	_hint_label = Label.new()
	_hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint_label.add_theme_font_size_override("font_size", Global.ui_font_size(12))
	_hint_label.add_theme_color_override("font_color", Color(0.82, 0.92, 1.0, 1.0))
	_hint_panel.add_child(_hint_label)
	content_vbox.add_child(_hint_panel)

	_controls = VBoxContainer.new()
	_controls.add_theme_constant_override("separation", int(10 * s))
	_controls.mouse_filter = Control.MOUSE_FILTER_PASS
	content_vbox.add_child(_controls)

	_feedback = Label.new()
	_feedback.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_feedback.add_theme_font_size_override("font_size", Global.ui_font_size(14))
	_feedback.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_feedback.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content_vbox.add_child(_feedback)

	_close_btn = Button.new()
	_close_btn.text = "Close"
	_close_btn.custom_minimum_size = Vector2(int(120 * s), int(36 * s))
	_close_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_close_btn.pressed.connect(_close_quiz)
	vbox.add_child(_close_btn)

	return root

func _close_quiz() -> void:
	# The reward summary must be reviewed and dismissed with Done; it is the
	# only path back to the overworld for quiz dungeons.
	if _reward_visible:
		return
	# Closing mid-quiz leaves progress untouched; reopening (_input → _start_quiz)
	# resets to question 1 so the player can pick up or restart at will.
	if _panel != null:
		_panel.visible = false
	_release_ui()

## Esc is a back action, but typed code is unsaved. Refuse quietly and let the
## player use the deliberate Close button if they mean to discard it.
func _escape_close() -> void:
	if _reward_visible:
		# Results are mandatory; keep the modal back entry alive for any later
		# Back press even though request_ui_back() popped it before calling here.
		if _panel != null and _panel.visible:
			Global.register_ui_back(_panel, Callable(self, "_escape_close"))
		return
	if _code_entry != null and is_instance_valid(_code_entry) \
			and not _code_entry.text.strip_edges().is_empty():
		_set_status("Use Close to discard the code you typed.", C_MUTED)
		# request_ui_back() consumes the stack entry before invoking this action;
		# keep the panel registered so Back/Escape can still protect it later.
		if _panel != null and _panel.visible:
			Global.register_ui_back(_panel, Callable(self, "_escape_close"))
		return
	_close_quiz()

# Releases the pause suspension + the open_ui() reference exactly once. Called
# on Close, on walking away, on completion and on tree exit (death/transition).
func _release_ui() -> void:
	_touch_scroll_active = false
	_touch_scroll_accum = 0.0
	_accept_results = false
	_running = false
	if _panel != null:
		Global.unregister_ui_back(_panel)
	Global.resume_ui_pause(self)
	if _ui_registered:
		_ui_registered = false
		Global.close_ui()

# ── Tutorial focus API ──────────────────────────────────────────────
func tutorial_is_open() -> bool:
	return _panel != null and is_instance_valid(_panel) and _panel.visible

func tutorial_hint_button() -> Control:
	return _hint_btn

func tutorial_hint_open() -> bool:
	return _hint_open

func tutorial_hint_run_failed() -> bool:
	return _hint_run_failed

func tutorial_hint_panel() -> Control:
	return _hint_panel

func tutorial_run_button() -> Control:
	return _run_btn

func tutorial_code_text() -> String:
	if _code_entry == null or not is_instance_valid(_code_entry):
		return ""
	return _code_entry.text.strip_edges()

func tutorial_question_label() -> Control:
	return _q_text

func tutorial_answers_control() -> Control:
	return _controls

func tutorial_reward_done() -> Control:
	return _done_btn

func tutorial_reward_visible() -> bool:
	return _reward_visible

func tutorial_question_index() -> int:
	return _index

func tutorial_question_count() -> int:
	return _questions.size()

# The altar can be torn down with the dungeon while its panel is open. Without
# this, Global's open_ui() refcount leaks and the overworld returns paused
# (which also makes the build-mode toggle look broken).
func _exit_tree() -> void:
	_accept_results = false
	_running = false
	if _panel != null and is_instance_valid(_panel):
		_panel.visible = false
	_release_ui()
