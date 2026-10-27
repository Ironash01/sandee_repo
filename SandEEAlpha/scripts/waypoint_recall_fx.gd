extends Node2D
class_name WaypointRecallFX

# Short additive beacon played at the player's feet when a world-waypoint
# destination is selected. The white transition overlay is handled by world.gd;
# this node only supplies the in-world recall column, rings and motes.

var duration: float = 0.9
var color: Color = Color(0.42, 1.0, 0.94, 1.0)
var _elapsed: float = 0.0
var _light: PointLight2D = null


func _ready() -> void:
	z_as_relative = false
	z_index = 4000
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	material = mat
	_light = PointLight2D.new()
	_light.texture = Global.get_smooth_light_texture(128)
	_light.color = color
	_light.energy = 1.15
	_light.texture_scale = 0.75
	_light.blend_mode = Light2D.BLEND_MODE_ADD
	add_child(_light)


func _process(delta: float) -> void:
	_elapsed += delta
	queue_redraw()
	if _elapsed >= duration:
		queue_free()


func _draw() -> void:
	var p: float = clampf(_elapsed / maxf(duration, 0.001), 0.0, 1.0)
	var intensity: float = pow(sin(p * PI), 0.7)
	if intensity <= 0.005:
		return
	var height: float = 178.0 * (0.82 + 0.18 * p)
	var half_w: float = 20.0 * (0.90 + 0.10 * sin(p * PI * 3.0))
	var beam := PackedVector2Array([
		Vector2(-half_w, 0.0),
		Vector2(half_w, 0.0),
		Vector2(half_w * 0.62, -height),
		Vector2(-half_w * 0.62, -height),
	])
	draw_colored_polygon(beam, Color(color.r, color.g, color.b, 0.13 * intensity))
	var inner := PackedVector2Array([
		Vector2(-half_w * 0.42, 0.0),
		Vector2(half_w * 0.42, 0.0),
		Vector2(half_w * 0.22, -height),
		Vector2(-half_w * 0.22, -height),
	])
	draw_colored_polygon(inner, Color(0.82, 1.0, 0.99, 0.20 * intensity))
	draw_rect(Rect2(Vector2(-2.0, -height), Vector2(4.0, height)),
		Color(1.0, 1.0, 1.0, 0.10 * intensity))

	# Pixel rings expanding across the floor.
	for i in range(3):
		var rp: float = fmod(p + float(i) * 0.22, 1.0)
		var radius: float = 12.0 + rp * 70.0
		var alpha: float = (1.0 - rp) * 0.78 * intensity
		draw_arc(Vector2.ZERO, radius, 0.0, TAU, 32,
			Color(color.r, color.g, color.b, alpha), 2.0)
		if i == 0:
			draw_circle(Vector2.ZERO, 8.0 * intensity, Color(0.9, 1.0, 1.0, 0.22 * intensity))

	# Sparse rising motes keep it readable without looking like a particle spam.
	for i in range(12):
		var mt: float = fmod(p + float(i) * 0.097, 1.0)
		var mx: float = sin(float(i) * 2.31 + p * 7.0) * 24.0 * (1.0 - mt * 0.35)
		var my: float = -mt * height
		var mote := Color(0.78, 1.0, 1.0, (1.0 - mt) * 0.8 * intensity)
		draw_rect(Rect2(Vector2(mx - 1.0, my - 1.0), Vector2(2.0, 2.0)), mote)
