extends RefCounted
class_name WaypointAnim

# Builds the 8-frame SpriteFrames used by waypoint AnimatedSprite2Ds from a
# horizontal sheet. Draft artwork is copied verbatim into sprites/waypoints;
# no redesign happens here.

const FRAME_COUNT: int = 8
const FPS: float = 10.0

static func build(sheet: Texture2D, frame_size: Vector2i,
		animation_name: String = "idle") -> SpriteFrames:
	var frames := SpriteFrames.new()
	if frames.has_animation("default"):
		frames.remove_animation("default")
	frames.add_animation(animation_name)
	frames.set_animation_speed(animation_name, FPS)
	frames.set_animation_loop(animation_name, true)
	if sheet == null or frame_size.x <= 0 or frame_size.y <= 0:
		return frames
	for i in range(FRAME_COUNT):
		var frame := AtlasTexture.new()
		frame.atlas = sheet
		frame.region = Rect2(i * frame_size.x, 0, frame_size.x, frame_size.y)
		frames.add_frame(animation_name, frame)
	return frames
