class_name StarIcon
extends Control
## Small 5-point star drawn in code so the leaderboard can show blue/yellow star
## counts without adding new art. Sizes itself from `Global.ui_scale`.

const BLUE := Color(0.42, 0.70, 1.00, 1.0)
const YELLOW := Color(0.98, 0.84, 0.30, 1.0)

var star_color: Color = BLUE


func setup(color: Color, px: float) -> void:
	star_color = color
	custom_minimum_size = Vector2(px, px)
	size = custom_minimum_size
	queue_redraw()


func _draw() -> void:
	var center := size * 0.5
	var radius := minf(size.x, size.y) * 0.5
	var points := PackedVector2Array()
	for i in range(10):
		var angle := -PI * 0.5 + float(i) * PI / 5.0
		var r := radius if i % 2 == 0 else radius * 0.44
		points.append(center + Vector2(cos(angle), sin(angle)) * r)
	draw_colored_polygon(points, star_color)
