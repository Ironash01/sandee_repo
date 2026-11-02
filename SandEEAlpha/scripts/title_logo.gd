extends HBoxContainer

# ── SandEE title mark ────────────────────────────────────────────────
# Official website branding for the title screen:
#   • website cartridge-tree favicon
#   • app-icon palette (navy / ink / green)
#   • white "Sand" + green "EE" wordmark
# Py-San and LUA flank the mark as the two guides of the game.
#
# The square app-icon "S" is deliberately NOT repeated here: the executable/app
# icon already carries that letter, so showing it again beside "SandEE" read as
# a duplicated S.

const PY_SAN_TEX: Texture2D = preload("res://sprites/char/pysan.png")
const LUA_TEX: Texture2D = preload("res://sprites/char/lua/front.png")
const WEB_LOGO: Texture2D = preload("res://sprites/mainmenu/sandee_logo.svg")

const C_INK: Color = Color(0.91, 0.94, 1.00, 1.00)
const C_ACCENT: Color = Color(0.55, 0.90, 0.60, 1.00)   # website --accent / icon green
const C_SHADOW: Color = Color(0.02, 0.03, 0.06, 1.00)

# 1-in-5 goofy title: Sand + 28 extra E's. The run is scaled down to fit the
# same row rather than pushing the guide sprites off-screen.
const EASTER_EGG_CHANCE: float = 0.2
const EXTENDED_EES: String = "EEEEEEEEEEEEEEEEEEEEEEEEEEEE"

static var _variant_rolled: bool = false
static var _extended_variant: bool = false

var title_font_base: float = 72.0
# Test/override seam: -1 = roll once per launch, 0 = normal, 1 = long title.
var force_extended: int = -1


func setup(font_base: float = 72.0) -> void:
	title_font_base = font_base
	if is_inside_tree():
		_build()


func _ready() -> void:
	_build()


func _use_extended_title() -> bool:
	if force_extended >= 0:
		return force_extended == 1
	if not _variant_rolled:
		_variant_rolled = true
		_extended_variant = randf() < EASTER_EGG_CHANCE
	return _extended_variant


func _build() -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	alignment = BoxContainer.ALIGNMENT_CENTER
	add_theme_constant_override("separation", int(10 * Global.ui_scale))
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	var s: float = Global.ui_scale
	add_child(_character(PY_SAN_TEX, Vector2(74, 74) * s))
	var centre := VBoxContainer.new()
	centre.alignment = BoxContainer.ALIGNMENT_CENTER
	centre.add_theme_constant_override("separation", int(2 * s))
	centre.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(centre)

	var logo_row := HBoxContainer.new()
	logo_row.alignment = BoxContainer.ALIGNMENT_CENTER
	logo_row.add_theme_constant_override("separation", int(10 * s))
	logo_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	centre.add_child(logo_row)

	var word := HBoxContainer.new()
	word.add_theme_constant_override("separation", 0)
	word.mouse_filter = Control.MOUSE_FILTER_IGNORE
	logo_row.add_child(word)
	var extended := _use_extended_title()
	var font_size: int = int(minf(float(Global.ui_font_size(title_font_base)),
		maxf(46.0, get_viewport_rect().size.y * 0.105)))
	if extended:
		# Fit the long E-run on the same line as Py-San and LUA.
		font_size = maxi(16, int(font_size * 0.38))
	var sand := _word_label("Sand", C_INK, font_size, s)
	var ee := _word_label(EXTENDED_EES if extended else "EE", C_ACCENT, font_size, s)
	word.add_child(sand)
	word.add_child(ee)

	var subtitle_row := HBoxContainer.new()
	subtitle_row.alignment = BoxContainer.ALIGNMENT_CENTER
	subtitle_row.add_theme_constant_override("separation", int(7 * s))
	subtitle_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	centre.add_child(subtitle_row)
	var web_logo := TextureRect.new()
	web_logo.texture = WEB_LOGO
	web_logo.custom_minimum_size = Vector2(18, 18) * s
	web_logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	web_logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	web_logo.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	web_logo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	subtitle_row.add_child(web_logo)

	add_child(_character(LUA_TEX, Vector2(40, 74) * s))


func _word_label(text: String, col: Color, font_size: int, s: float) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", col)
	label.add_theme_color_override("font_outline_color", C_SHADOW)
	label.add_theme_constant_override("outline_size", maxi(2, int(4 * s)))
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


func _character(tex: Texture2D, target: Vector2) -> TextureRect:
	var rect := TextureRect.new()
	rect.texture = tex
	rect.custom_minimum_size = target
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return rect
