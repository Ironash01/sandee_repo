extends "res://scripts/placeable_block.gd"

# ── Bonfire ──────────────────────────────────────────────────────────
# A placeable block that doubles as a TOGGLEABLE respawn point. A plain click
# (tap) on the bonfire sets it as the respawn point; clicking it again clears it
# (respawn falls back to the world spawn). Only ONE bonfire is active at a time
# (activating one deactivates the others). Breaking the ACTIVE bonfire clears
# the respawn point. It still lights + animates through the base PlaceableBlock
# (the item sets is_torch, which also makes it non-solid like a torch).

const ACTIVE_TINT:   Color = Color(1.0, 1.0, 1.0)      # full brightness while lit
const INACTIVE_TINT: Color = Color(0.62, 0.62, 0.62)   # dimmed while off

var _active: bool = false

func _ready() -> void:
	super()
	add_to_group("Bonfire")
	_set_active(false)

# A bonfire consumes a plain left-click (toggles the respawn point); SHIFT+click
# still mines it via the base _input.
func has_plain_click() -> bool:
	return true

func on_plain_click() -> void:
	_toggle_active()

func is_active() -> bool:
	return _active

# Contextual hover prompt (world.gd _update_hover shows this while hovering).
func hover_prompt() -> String:
	if _active:
		return "Bonfire — respawn set (click to clear)"
	return "Bonfire — click to set respawn"

func _toggle_active() -> void:
	if _active:
		_deactivate()
	else:
		_activate()

func _activate() -> void:
	if not _is_overworld():
		return
	# Only ONE active at a time: deactivate every other bonfire first.
	for b in get_tree().get_nodes_in_group("Bonfire"):
		if b != self and is_instance_valid(b) and b.has_method("_set_active"):
			b.call("_set_active", false)
	Global.set_spawn_point(global_position)
	_set_active(true)
	Global.notify("Respawn point set to this bonfire. Click it again to clear.")

func _deactivate() -> void:
	var was_active: bool = Global.has_spawn_point \
		and Global.spawn_point.distance_to(global_position) < 1.0
	if was_active:
		Global.clear_spawn_point()
	_set_active(false)
	if was_active:
		Global.notify("Respawn point cleared — you'll respawn at the world spawn.")

func _set_active(active: bool) -> void:
	_active = active
	if _sprite != null:
		_sprite.modulate = ACTIVE_TINT if active else INACTIVE_TINT

# Only the OVERWORLD sets a respawn point — a cave/dungeon bonfire's coordinates
# are structure-local and invalid for the overworld respawn.
func _is_overworld() -> bool:
	var world: Node = _world()
	if world != null and world.has_method("is_overworld") and not bool(world.call("is_overworld")):
		return false
	return true

func _break() -> void:
	# Breaking the ACTIVE bonfire resets the respawn to the world spawn.
	if _active:
		Global.clear_spawn_point()
		Global.notify("Respawn point reset — your bonfire was destroyed.")
	super()
