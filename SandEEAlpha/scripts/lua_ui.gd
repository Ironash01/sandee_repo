extends Node

# ── Lua station UI component ────────────────────────────────────────
# Owns EVERYTHING presentational for one Lua station: the world-space name label
# above the robot, and the code-editor panel (a CanvasLayer + the LuaEditorUI
# scene, which in turn owns the build/tool slot widgets).
#
# The gameplay node (lua_npc.gd) keeps NO UI state: it talks to this component
# through a handful of methods — setup / open_editor / close_editor /
# is_editor_open / set_name_text — and this component never reaches back into LUA
# execution, AI, navigation or custom-function dispatch. Presentation can
# therefore change without touching gameplay.
#
# The editor panel is added as a CHILD of this node, which is itself a child of
# the Lua station — so the editor's own _find_npc() walk up the tree still finds
# the station that owns it, and the editor's signals keep working unchanged.

const EDITOR_SCENE: String = "res://scenes/ui/LuaEditorUI.tscn"
const LABEL_FONT_SIZE: int  = 12
# Sits just above the robot sprite; x/width stay centered on the robot origin.
const LABEL_POS:  Vector2 = Vector2(-60, -42)
const LABEL_SIZE: Vector2 = Vector2(120, 16)

# The Lua station (LuaNPC) this UI belongs to. Only used to hand the editor its
# owner — never to drive gameplay.
var npc: Node = null

var _editor: Control = null
var _label:  Label   = null

# `robot` is the moving Node2D the name label must follow.
func setup(owner_npc: Node, robot: Node2D) -> void:
	npc = owner_npc
	_build_label(robot)
	_build_editor()

# ── Name label ────────────────────────────────────────────────────
func _build_label(robot: Node2D) -> void:
	_label = Label.new()
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.add_theme_font_size_override("font_size", LABEL_FONT_SIZE)
	_label.add_theme_color_override("font_color", Color(0.85, 0.95, 1.0, 1.0))
	_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	_label.add_theme_constant_override("outline_size", 3)
	_label.position = LABEL_POS
	_label.size     = LABEL_SIZE
	_label.visible  = false
	if robot != null and is_instance_valid(robot):
		robot.add_child(_label)

func set_name_text(text: String) -> void:
	if _label == null or not is_instance_valid(_label):
		return
	_label.text    = text
	_label.visible = true

# ── Editor panel ──────────────────────────────────────────────────
func _build_editor() -> void:
	var scene: PackedScene = load(EDITOR_SCENE) as PackedScene
	if scene == null:
		push_warning("LuaUI: %s missing — the LUA editor cannot open" % EDITOR_SCENE)
		return
	var canvas := CanvasLayer.new()
	canvas.layer        = 12
	canvas.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(canvas)
	_editor = scene.instantiate() as Control
	if _editor == null:
		return
	canvas.add_child(_editor)
	_editor.visible = false

func is_editor_open() -> bool:
	return _editor != null and is_instance_valid(_editor) and _editor.visible

# Open the editor and register the shared UI pause. Returns false when it was
# already open (or unavailable) so a caller never double-pauses.
func open_editor() -> bool:
	if _editor == null or not is_instance_valid(_editor) or _editor.visible:
		return false
	Global.open_ui()
	# open_panel() re-syncs RUN/STOP with the robot's real state — plainly
	# setting visible = true would leave STOP disabled (and a still-running robot
	# unstoppable) after a close/reopen.
	if _editor.has_method("open_panel"):
		_editor.call("open_panel")
	else:
		_editor.visible = true
	return true

# Hide the editor and release the pause it took. Safe to call when already
# closed, so it doubles as the "close all UI" handler. Routed through the
# editor's close_panel() so a suspended pause (robot still working) is released
# with it — otherwise a stale suspension would stop later UIs from pausing.
func close_editor() -> void:
	if _editor == null or not is_instance_valid(_editor):
		return
	if not _editor.visible:
		return
	if _editor.has_method("close_panel"):
		_editor.call("close_panel")
	else:
		Global.close_ui()
		_editor.visible = false

# A station freed (or its world swapped out) while its editor was open must not
# leave the tree paused with no visible UI — which reads as the game freezing.
func _exit_tree() -> void:
	close_editor()
