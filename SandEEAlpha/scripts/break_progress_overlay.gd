extends Control

# World-space mining ring drawn on a high CanvasLayer. Keeping it out of the
# block/tree node's own _draw() means sprites, y-sorted neighbours and other
# world nodes can never cover the progress ring. The hotbar copy is a separate
# HUD control reading the same Global break state.

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	visible = false
	set_process(true)

func _process(_delta: float) -> void:
	if not Global.break_hud_visible() or Global.any_ui_open() or Global.pause_menu_open:
		visible = false
		return
	size = get_viewport_rect().size
	visible = true
	queue_redraw()

func _draw() -> void:
	var world_center: Vector2 = Global.break_world_pos \
		+ Vector2(0.0, Global.break_world_y_offset * Global.ui_scale)
	var screen_center: Vector2 = get_viewport().get_canvas_transform() * world_center
	Global.draw_break_ring(self, screen_center, Global.break_hud_progress, false)
