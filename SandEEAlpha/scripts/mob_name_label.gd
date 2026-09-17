extends Node2D
# ── Mob name label ────────────────────────────────────────────────
# Terraria-style enemy name shown above a mob when combat starts (the
# mob takes a hit, or lands a hit on the player).  Rides along as a
# child of the mob so it tracks its position, and fades out after a
# short time.  Created once per mob and re-flashed on each combat event.

const SHOW_TIME: float = 2.5   # seconds fully visible before fading
const FADE_TIME: float = 0.7   # seconds of fade at the end
const FONT_SIZE: int   = 11
const OFFSET_Y:  float = -34.0 # above the mob's origin
const C_TEXT:    Color = Color(1.0, 1.0, 1.0, 1.0)
const C_SHADOW:  Color = Color(0.0, 0.0, 0.0, 1.0)

var mob_name: String = ""

var _timer: float = 0.0
var _alpha: float = 0.0

func _ready() -> void:
	# Draw above nearby world sprites regardless of the mob's y-sort.
	z_as_relative = false
	z_index = 130
	visible = false

# Re-show the name (called on combat events).
func flash() -> void:
	if mob_name.is_empty():
		return
	_timer = SHOW_TIME + FADE_TIME
	_alpha = 1.0
	visible = true
	queue_redraw()

func _process(delta: float) -> void:
	if _timer <= 0.0:
		return
	_timer -= delta
	if _timer <= 0.0:
		_alpha = 0.0
		visible = false
	elif _timer < FADE_TIME:
		_alpha = _timer / FADE_TIME
	queue_redraw()

func _draw() -> void:
	if mob_name.is_empty() or _alpha <= 0.0:
		return
	var font := ThemeDB.fallback_font
	var w := font.get_string_size(mob_name, HORIZONTAL_ALIGNMENT_CENTER, -1, FONT_SIZE).x
	var pos := Vector2(-w * 0.5, OFFSET_Y)
	var shadow_col := Color(C_SHADOW.r, C_SHADOW.g, C_SHADOW.b, _alpha)
	var text_col := Color(C_TEXT.r, C_TEXT.g, C_TEXT.b, _alpha)
	# Cheap 8-direction outline so the name stays readable on any background.
	for ox in [-1, 0, 1]:
		for oy in [-1, 0, 1]:
			if ox == 0 and oy == 0:
				continue
			draw_string(font, pos + Vector2(ox, oy), mob_name,
				HORIZONTAL_ALIGNMENT_CENTER, -1, FONT_SIZE, shadow_col)
	draw_string(font, pos, mob_name,
		HORIZONTAL_ALIGNMENT_CENTER, -1, FONT_SIZE, text_col)
