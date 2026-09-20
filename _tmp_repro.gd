extends Node
var _world: Node
var _player: CharacterBody2D
var _t0 := 0
func _ready() -> void:
	_player = CharacterBody2D.new()
	add_child(_player)
	Global.set_player_reference(_player)
	_t0 = Time.get_ticks_msec()
	_world = load("res://scenes/world_gen.tscn").instantiate()
	_world.generation_complete.connect(_on_gen)
	add_child(_world)
func _process(_d: float) -> void:
	if Time.get_ticks_msec() - _t0 > 240000:
		print("TIMEOUT"); get_tree().quit()
func _on_gen() -> void:
	var occ: Dictionary = _world.get("_grass_occupied_tiles")
	for i in range(300):
		await get_tree().process_frame
		if occ.size() > 50: break
	var gl: TileMapLayer = _world.get("ground_layer")
	var tile: Vector2i = occ.keys()[0]
	var center: Vector2 = gl.to_global(gl.map_to_local(tile))
	_player.global_position = center - Vector2(0, 32)

	print("=== A) STALE FREED ENTRY (the reported crash) ===")
	var victim = occ[tile]
	victim.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	print("  entry valid before lookup: ", is_instance_valid(occ.get(tile)))
	print("  calling _cut_grass_row (would crash before the fix)...")
	_world.call("_cut_grass_row", _player)
	print("  SURVIVED; stale key erased: ", not occ.has(tile), " (expect true)")

	print("=== B) OFF-TREE GUARD (swing in a dungeon) ===")
	var occ2: Dictionary = _world.get("_grass_occupied_tiles")
	# Place a valid tuft in front of the player.
	var tile2: Vector2i = _grass_in_front(occ2)
	var count_before: int = occ2.size()
	remove_child(_world)
	var dungeon := Node.new()
	add_child(dungeon)
	Global.set("world_node", dungeon)
	print("  overworld in tree: ", _world.is_inside_tree())
	_world.call("_on_swing_performed")
	print("  off-tree swing did NOT cut overworld grass: ", occ2.size() == count_before, " (expect true)")
	print("DONE")
	get_tree().quit()
func _grass_in_front(occ: Dictionary) -> Vector2i:
	var gl: TileMapLayer = _world.get("ground_layer")
	var pt: Vector2i = gl.local_to_map(gl.to_local(_player.global_position))
	var want: Vector2i = pt + Vector2i(0, 1)
	if occ.has(want): return want
	return occ.keys()[0]
