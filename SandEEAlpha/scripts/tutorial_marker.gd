extends Node2D
class_name TutorialMarker

# A world-space targeting square for onboarding. It deliberately draws a pixel
# tile bracket/grid rather than a glowing circle so it reads like a build-grid
# cell and lines up with SandEE's 32px world tiles.
#
# Purely visual: no collision, no input interception, no gameplay state.

const TILE: float = 32.0

var pulse: float = 0.0
var color: Color = Color(0.36, 0.95, 0.88, 1.0)
var label_text: String = ""

func _ready() -> void:
	z_as_relative = false
	z_index = 4000
	set_process(true)

func _process(delta: float) -> void:
	pulse += delta
	queue_redraw()

func _draw() -> void:
	var wave: float = 0.5 + 0.5 * sin(pulse * 3.2)
	var rect := Rect2(-TILE * 0.5, -TILE * 0.5, TILE, TILE)
	var edge := Color(color.r, color.g, color.b, 0.68 + 0.25 * wave)
	var fill := Color(color.r, color.g, color.b, 0.055 + 0.035 * wave)
	draw_rect(rect, fill, true)
	draw_rect(rect, edge, false, 2.0)
	# Four corner brackets make the cell obvious even over busy terrain.
	var corner := 7.0
	for sx in [-1.0, 1.0]:
		for sy in [-1.0, 1.0]:
			var cx: float = sx * (TILE * 0.5 - corner)
			var cy: float = sy * (TILE * 0.5 - corner)
			draw_line(Vector2(cx - corner, cy), Vector2(cx + corner, cy), edge, 2.0)
			draw_line(Vector2(cx, cy - corner), Vector2(cx, cy + corner), edge, 2.0)
	# A faint 2x2 grid keeps the square tied to the tile lattice.
	var grid := Color(color.r, color.g, color.b, 0.20 + 0.16 * wave)
	draw_line(Vector2(0.0, -TILE * 0.5), Vector2(0.0, TILE * 0.5), grid, 1.0)
	draw_line(Vector2(-TILE * 0.5, 0.0), Vector2(TILE * 0.5, 0.0), grid, 1.0)
	# Four inward arrowheads reinforce the tile target and stay readable when
	# the camera/zoom changes; they pulse gently rather than glowing.
	var off: float = TILE * 0.5 + 12.0 + 3.0 * wave
	var a: float = 8.0
	var arrow_color := Color(color.r, color.g, color.b, 0.72 + 0.24 * wave)
	var arrows: Array = [
		PackedVector2Array([Vector2(-a, -off - a), Vector2(a, -off - a), Vector2(0.0, -off)]),
		PackedVector2Array([Vector2(-a, off + a), Vector2(a, off + a), Vector2(0.0, off)]),
		PackedVector2Array([Vector2(-off - a, -a), Vector2(-off - a, a), Vector2(-off, 0.0)]),
		PackedVector2Array([Vector2(off + a, -a), Vector2(off + a, a), Vector2(off, 0.0)]),
	]
	for points in arrows:
		draw_colored_polygon(points as PackedVector2Array, arrow_color)
		draw_polyline(points as PackedVector2Array, Color(0.02, 0.12, 0.14, 0.9), 1.0)
	var y: float = -off - 22.0
	if not label_text.is_empty():
		var font := ThemeDB.fallback_font
		var fs: int = Global.ui_font_size(10.0)
		var tw: float = font.get_string_size(label_text, HORIZONTAL_ALIGNMENT_CENTER, -1, fs).x
		var pos := Vector2(-tw * 0.5, y)
		for ox in [-1.0, 0.0, 1.0]:
			for oy in [-1.0, 0.0, 1.0]:
				if ox == 0.0 and oy == 0.0:
					continue
				draw_string(font, pos + Vector2(ox, oy), label_text,
					HORIZONTAL_ALIGNMENT_CENTER, -1, fs, Color(0, 0, 0, 0.9))
		draw_string(font, pos, label_text, HORIZONTAL_ALIGNMENT_CENTER, -1, fs,
			Color(0.94, 1.0, 0.99, 1.0))
