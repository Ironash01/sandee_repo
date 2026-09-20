extends Node2D
# ── Floating damage number ────────────────────────────────────────
# A short-lived red number that pops above a mob when it takes a hit, rises a
# little and fades out (Terraria-style damage indicator). Spawned by the mob's
# take_hit at its position; draws itself and frees on completion.

const LIFETIME:  float = 0.8
const RISE_PX:   float = 20.0
const FONT_SIZE: int   = 11
const C_TEXT:    Color = Color(1.0, 0.20, 0.20, 1.0)

var _text: String = ""

func _ready() -> void:
	z_index = 120  # above mobs/player
	var t := create_tween()
	t.tween_property(self, "position:y", position.y - RISE_PX, LIFETIME) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	t.parallel().tween_property(self, "modulate:a", 0.0, LIFETIME) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	t.tween_callback(queue_free)

func _draw() -> void:
	if _text.is_empty():
		return
	# Read the scale live at draw time — damage numbers are short-lived, so no
	# signal hookup is needed for a Small/Medium/Large change to take effect.
	var fs: int = int(FONT_SIZE * Global.ui_scale)
	var font := ThemeDB.fallback_font
	var w := font.get_string_size(_text, HORIZONTAL_ALIGNMENT_CENTER, -1, fs).x
	draw_string(font, Vector2(-w * 0.5, 0.0), _text,
		HORIZONTAL_ALIGNMENT_CENTER, -1, fs, C_TEXT)
