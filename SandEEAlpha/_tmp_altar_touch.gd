extends Node

func _ready() -> void:
	var win := get_window()
	win.mode = Window.MODE_WINDOWED
	win.size = Vector2i(1024, 473)
	await get_tree().process_frame
	await get_tree().process_frame
	var vp_size: Vector2 = get_viewport().get_visible_rect().size
	Global.ui_scale = 1.25
	Global.ui_viewport_size = vp_size
	Global.ui_safe_insets = Vector4.ZERO
	ThemeDB.fallback_font_size = Global.ui_font_size(float(Global.UI_FALLBACK_FONT_BASE))
	var altar := KnowledgeAltar.new()
	altar.set("_entry", load("res://resources/entries/entry_11_lua.tres"))
	add_child(altar)
	var altar_root = altar.call("_build_panel")
	altar.set("_panel", altar_root)
	await get_tree().process_frame
	await get_tree().process_frame
	var body := altar.find_child("BodyScroll", true, false) as ScrollContainer
	if body == null:
		print("TOUCH_NO_BODY")
		get_tree().quit(2)
		return
	var bar := body.get_v_scroll_bar()
	print("TOUCH_VIEWPORT=", vp_size, " BODY=", body.size,
		" MAX=", bar.max_value, " PAGE=", bar.page, " INIT=", body.scroll_vertical)
	var center: Vector2 = body.get_global_rect().get_center()

	# Wheel check.
	var wheel := InputEventMouseButton.new()
	wheel.button_index = MOUSE_BUTTON_WHEEL_DOWN
	wheel.pressed = true
	wheel.position = center
	wheel.global_position = center
	get_viewport().push_input(wheel, true)
	await get_tree().process_frame
	print("TOUCH_WHEEL=", body.scroll_vertical)
	body.scroll_vertical = 0

	# Touch check.
	var press := InputEventScreenTouch.new()
	press.index = 0
	press.position = center
	press.pressed = true
	altar.call("_input", press)
	await get_tree().process_frame
	for i in range(12):
		var drag := InputEventScreenDrag.new()
		drag.index = 0
		drag.position = center + Vector2(0.0, -float(i + 1) * 18.0)
		drag.relative = Vector2(0.0, -18.0)
		altar.call("_input", drag)
		await get_tree().process_frame
	var release := InputEventScreenTouch.new()
	release.index = 0
	release.position = center + Vector2(0.0, -216.0)
	release.pressed = false
	altar.call("_input", release)
	await get_tree().process_frame
	print("TOUCH_AFTER=", body.scroll_vertical, " DEADZONE=", body.scroll_deadzone)
	get_tree().quit(0)
