extends Control

# A second copy of the pixel break ring, anchored to the right of the hotbar.
# The world-space ring is drawn by the object being broken; this HUD copy makes
# the same progress visible while the target is partly off-screen or behind the
# player. It is purely visual and never accepts input.

var anchor_control: Control = null

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	set_process(true)

func _process(_delta: float) -> void:
	if not Global.break_hud_visible() or Global.any_ui_open() or Global.pause_menu_open:
		visible = false
		return
	_layout()
	visible = true
	queue_redraw()

func _layout() -> void:
	if anchor_control == null or not is_instance_valid(anchor_control):
		return
	var s: float = maxf(Global.ui_scale, 0.5)
	var ring_size: float = Global.break_ring_size()
	var anchor_rect: Rect2 = anchor_control.get_global_rect()
	size = Vector2(ring_size, ring_size)
	position = Vector2(
		anchor_rect.end.x + 8.0 * s,
		anchor_rect.position.y + (anchor_rect.size.y - ring_size) * 0.5)

func _draw() -> void:
	Global.draw_break_ring(self, size * 0.5, Global.break_hud_progress, false)
