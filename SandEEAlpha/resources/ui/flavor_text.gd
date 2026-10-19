extends Resource
class_name FlavorText

# ── Title-screen flavor text ────────────────────────────────────────
# A plain list of short lines shown beside the SandEE title (one at a time,
# re-rolled each time the title screen opens — Minecraft-splash style).
#
# Adding a line means editing resources/ui/flavor_text.tres ONLY: the title
# screen just loads this resource and asks for random_line(), so its selection
# logic never has to change.
#
# PackedStringArray (not Array[String]) so the .tres serializes with the same
# `lines = PackedStringArray(...)` form project.godot already uses for typed
# string lists — no custom-class load-order surprises.
@export var lines: PackedStringArray = PackedStringArray()

# A random entry, or "" when the collection is empty (the caller falls back).
func random_line() -> String:
	if lines.is_empty():
		return ""
	return lines[randi() % lines.size()]
