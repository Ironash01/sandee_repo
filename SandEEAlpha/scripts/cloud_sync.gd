extends Node
## Automatic cloud-save synchronization.
##
## Two-way at startup and conflict-safe:
##   * cloud-only worlds are downloaded into their free local slot;
##   * for the SAME world (world_uid), the strictly newer revision wins
##     (clock-independent);
##   * a different world in the same slot, equal revisions with different
##     bytes, or legacy metadata without identity are reported as Pending and
##     resolved manually from Cloud Saves;
##   * automatic downloads never replace a different local world.
##
## Triggers:
##   * online initialization / sign-in -> sync_all()
##   * every successful Global.save_game (60 s autosave, quit, window close)
##   * Global.world_loaded (joining a world)
##
## All calls are no-ops unless the game is in Online mode with a signed-in user.


signal sync_completed(summary: Dictionary)

var _syncing: Dictionary = {}   # slot -> true while a request is in flight
var _dirty: Dictionary = {}     # slot -> true when a save arrived mid-sync
var _batch_running := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if not Global.game_saved.is_connected(_on_game_saved):
		Global.game_saved.connect(_on_game_saved)
	if not Global.world_loaded.is_connected(_on_world_loaded):
		Global.world_loaded.connect(_on_world_loaded)
	if not Global.mission_star_earned.is_connected(_on_mission_star_earned):
		Global.mission_star_earned.connect(_on_mission_star_earned)
	if not Global.online_state_changed.is_connected(_on_online_state_changed):
		Global.online_state_changed.connect(_on_online_state_changed)


func is_enabled() -> bool:
	return Global.online_mode and Supabase.is_signed_in()


func _on_online_state_changed() -> void:
	if not Global.online_mode:
		_syncing.clear()
		_dirty.clear()


func _on_game_saved(slot: int) -> void:
	sync_slot(slot)


func _on_world_loaded(slot: int) -> void:
	sync_slot(slot)
	# Loading a world is also the recovery path for missions completed offline
	# (and the one-time "cloud is 0 but this world has stars" migration).
	sync_progress()


func _on_mission_star_earned(reward_id: String) -> void:
	# Legacy worlds (created before 0.9.3.0) keep their local missions but never
	# update the account/leaderboard stars.
	if not Global.world_progress_eligible(Global.active_save_slot):
		return
	claim_reward_ids([reward_id])


## Claims every completed mission/clear in the CURRENT world. The server ignores
## unknown ids and repeats, so this is safe to run on every load/login.
func sync_progress() -> void:
	if not is_enabled():
		return
	if not Global.world_progress_eligible(Global.active_save_slot):
		return
	var ids: Array = []
	for m in Global.missions:
		if not bool(m.get("completed", false)):
			continue
		var id := str(m.get("id", ""))
		if id.is_empty():
			continue
		ids.append(("dungeon_mission:" + id) if m.has("dungeon_index") else ("mission:" + id))
	for idx in Global.cleared_dungeons:
		ids.append("dungeon_clear:%d" % int(idx))
	if not ids.is_empty():
		await claim_reward_ids(ids)


## Scans every local save file and claims the completed missions/clears found in
## them. Used on startup/sign-in so offline progress in ANY world is reflected in
## the account stars without requiring that world to be loaded first. Safe:
## ids are whitelisted server-side and each is claimable once per account.
func sync_all_progress() -> void:
	if not is_enabled():
		return
	var ids: Dictionary = {}
	for slot in Global.list_worlds():
		# Old worlds must never contribute to account/leaderboard stars.
		if not Global.world_progress_eligible(int(slot)):
			continue
		var info: Dictionary = Global.get_save_info(int(slot))
		var saved_missions: Variant = info.get("missions", [])
		if saved_missions is Array:
			for entry in saved_missions:
				if typeof(entry) != TYPE_DICTIONARY:
					continue
				var row: Dictionary = entry
				if not bool(row.get("completed", false)):
					continue
				var id := str(row.get("id", ""))
				if id.is_empty():
					continue
				ids[("dungeon_mission:" + id) if id.begins_with("dungeon_") else ("mission:" + id)] = true
		var cleared: Variant = info.get("cleared_dungeons", [])
		if cleared is Array:
			for idx in cleared:
				ids["dungeon_clear:%d" % int(idx)] = true
	if ids.is_empty():
		return
	await claim_reward_ids(ids.keys())


## Sends a batch of whitelisted reward ids, then refreshes the cached profile so
## the mission tracker can show the new account totals.
func claim_reward_ids(ids: Array) -> void:
	if ids.is_empty() or not is_enabled():
		return
	var result: Dictionary = await Supabase.claim_missions(ids)
	if not result.ok:
		_apply_failure(result)
		return
	var claimed := 0
	if result.data is Array and (result.data as Array).size() == 1:
		claimed = int((result.data as Array)[0].get("claimed", 0))
	# Refresh even when nothing was new, so the local display is not stale.
	await Supabase.refresh_profile()
	Global.stars_updated.emit()
	if claimed > 0:
		Global.mission_updated.emit()


## Two-way startup sync. The safe automatic rules are:
##   * cloud-only world -> download it into its free local slot;
##   * same world_uid and cloud revision newer -> download the cloud copy;
##   * same world_uid and local revision newer -> upload the local copy;
##   * different worlds, equal revisions with different bytes, or legacy
##     metadata without identity -> leave both intact and report Pending.
## Cloud-only downloads never overwrite an existing local world; conflicts are
## resolved from Cloud Saves.
func sync_all() -> void:
	if not is_enabled() or _batch_running:
		return
	_batch_running = true
	Global.set_cloud_status(Global.CloudStatus.SYNCING, "Syncing worlds?")
	var summary: Dictionary = {
		"uploaded": 0, "downloaded": 0, "synced": 0, "pending": 0,
		"failed": 0, "total": 0,
	}
	var cloud := await Supabase.list_saves()
	if not is_enabled():
		_batch_running = false
		Global.set_cloud_status(Global.CloudStatus.OFFLINE)
		sync_completed.emit(summary)
		return
	if not cloud.ok:
		_batch_running = false
		_apply_failure(cloud)
		summary["failed"] = 1
		sync_completed.emit(summary)
		return

	var cloud_by_slot: Dictionary = {}
	if cloud.data is Array:
		for row_value in (cloud.data as Array):
			if typeof(row_value) != TYPE_DICTIONARY:
				continue
			var row: Dictionary = row_value
			var slot: int = int(row.get("slot", 0))
			if slot >= 1 and slot <= Global.MAX_WORLDS:
				cloud_by_slot[slot] = row

	var processed: Dictionary = {}
	for slot_value in cloud_by_slot.keys():
		if not is_enabled():
			_batch_running = false
			Global.set_cloud_status(Global.CloudStatus.OFFLINE)
			sync_completed.emit(summary)
			return
		var slot: int = int(slot_value)
		var result: String
		if not Global.has_save(slot):
			result = await _install_cloud_save(slot, cloud_by_slot[slot])
		else:
			result = await _reconcile_slot(slot, cloud_by_slot[slot])
		processed[slot] = true
		_count_sync(summary, result)

	# Local worlds with no cloud row are uploaded automatically.
	for slot_value in Global.list_worlds():
		if not is_enabled():
			_batch_running = false
			Global.set_cloud_status(Global.CloudStatus.OFFLINE)
			sync_completed.emit(summary)
			return
		var slot: int = int(slot_value)
		if processed.has(slot):
			continue
		var result: String = await sync_slot(slot)
		_count_sync(summary, result)

	await sync_progress()
	# Scan every saved world, so offline progress in another world is not
	# stranded until that world is opened again.
	await sync_all_progress()
	_batch_running = false
	if not is_enabled():
		Global.set_cloud_status(Global.CloudStatus.OFFLINE)
		sync_completed.emit(summary)
		return
	_finish_sync_status(summary)
	CrashLogger.event("CLOUD", "startup sync complete %s" % str(summary))
	sync_completed.emit(summary)


func _count_sync(summary: Dictionary, result: String) -> void:
	if result == "skipped":
		return
	var key: String = result
	if result == "error":
		key = "pending" if Global.cloud_status == Global.CloudStatus.PENDING else "failed"
	summary["total"] = int(summary.get("total", 0)) + 1
	if summary.has(key):
		summary[key] = int(summary[key]) + 1


func _finish_sync_status(summary: Dictionary) -> void:
	if int(summary.get("failed", 0)) > 0:
		Global.set_cloud_status(Global.CloudStatus.ERROR,
			"Some worlds could not be synced.")
	elif int(summary.get("pending", 0)) > 0:
		Global.set_cloud_status(Global.CloudStatus.PENDING,
			"Some cloud worlds need attention in Cloud Saves.")
	elif int(summary.get("uploaded", 0)) + int(summary.get("downloaded", 0)) > 0:
		Global.set_cloud_status(Global.CloudStatus.SYNCED)
	else:
		Global.set_cloud_status(Global.CloudStatus.ACTIVE)


func _reconcile_slot(slot: int, meta: Dictionary) -> String:
	var path := "user://save_slot_%d.json" % slot
	if not FileAccess.file_exists(path):
		return await _install_cloud_save(slot, meta)
	var info: Dictionary = Global.get_save_info(slot)
	var local_uid := str(info.get("world_uid", "")).strip_edges()
	var local_rev: int = maxi(0, int(info.get("save_revision", 0)))
	if local_uid.is_empty() or local_rev <= 0:
		info = Global.ensure_save_identity(slot)
		local_uid = str(info.get("world_uid", "")).strip_edges()
		local_rev = maxi(0, int(info.get("save_revision", 0)))
	var local_checksum := FileAccess.get_sha256(path)
	var cloud_checksum := str(meta.get("checksum", ""))
	if not cloud_checksum.is_empty() and cloud_checksum == local_checksum:
		return "synced"
	var cloud_uid := str(meta.get("world_uid", "")).strip_edges()
	var cloud_rev: int = maxi(0, int(meta.get("revision", 0)))
	var cloud_data := PackedByteArray()

	# Before the identity migration is applied, metadata has no world_uid /
	# revision. The save FILE still carries both, so read it once and use those
	# values instead of treating every existing cloud row as a conflict.
	if cloud_uid.is_empty() or cloud_rev <= 0:
		var fetched: Dictionary = await _fetch_cloud_file(slot)
		if not fetched.get("ok", false):
			return "error"
		if str(fetched.get("checksum", "")) == local_checksum:
			return "synced"
		cloud_data = fetched.get("data", PackedByteArray()) as PackedByteArray
		var cloud_info: Dictionary = fetched.get("info", {})
		cloud_uid = str(cloud_info.get("world_uid", "")).strip_edges()
		cloud_rev = maxi(0, int(cloud_info.get("save_revision", 0)))

	# Never silently replace a different world or legacy metadata without any
	# identity at all.
	if cloud_uid.is_empty() or local_uid.is_empty() or cloud_uid != local_uid:
		return "pending"
	if cloud_rev > local_rev:
		if not cloud_data.is_empty():
			var install := await download_to_local(slot, "", cloud_data)
			return "downloaded" if install.get("ok", false) else "failed"
		return await _install_cloud_save(slot, meta)
	if local_rev > cloud_rev:
		return await sync_slot(slot, true)
	return "pending"


func _fetch_cloud_file(slot: int) -> Dictionary:
	var result := await Supabase.download_save(slot)
	if not result.ok or not (result.data is PackedByteArray):
		return {"ok": false, "error": str(result.get("error", "download failed"))}
	var data: PackedByteArray = result.data
	var parsed: Variant = JSON.parse_string(data.get_string_from_utf8())
	if not (parsed is Dictionary):
		return {"ok": false, "error": "invalid cloud save"}
	return {
		"ok": true,
		"data": data,
		"checksum": Supabase.checksum_bytes(data),
		"info": parsed,
	}


func _install_cloud_save(slot: int, meta: Dictionary) -> String:
	var expected := str(meta.get("checksum", ""))
	var result: Dictionary = await download_to_local(slot, expected)
	if result.get("ok", false):
		return "downloaded"
	return "failed"


## Downloads one cloud save and atomically installs it locally. Public so the
## Cloud Saves screen can use the same checksum validation and write path.
func download_to_local(slot: int, expected_checksum: String = "",
		preloaded: PackedByteArray = PackedByteArray()) -> Dictionary:
	var data := preloaded
	var status := 200
	if data.is_empty():
		var result := await Supabase.download_save(slot)
		if not result.ok or not (result.data is PackedByteArray):
			return result
		data = result.data
		status = int(result.get("status", 200))
	if not expected_checksum.is_empty() \
			and Supabase.checksum_bytes(data) != expected_checksum:
		return {"ok": false, "status": 0, "data": null,
			"error": "corrupt cloud save", "corrupt": true}
	var parsed: Variant = JSON.parse_string(data.get_string_from_utf8())
	if not (parsed is Dictionary):
		return {"ok": false, "status": 0, "data": null,
			"error": "invalid cloud save", "corrupt": true}
	if not _write_local_save(slot, data):
		return {"ok": false, "status": 0, "data": null,
			"error": "local write failed"}
	Global.ensure_save_identity(slot)
	CrashLogger.event("CLOUD", "downloaded slot=%d world=%s" % [
		slot, str((parsed as Dictionary).get("world_name", ""))])
	return {"ok": true, "status": status, "data": parsed, "error": ""}


func _write_local_save(slot: int, data: PackedByteArray) -> bool:
	var path := "user://save_slot_%d.json" % slot
	var tmp := path + ".tmp"
	var file := FileAccess.open(tmp, FileAccess.WRITE)
	if file == null:
		return false
	file.store_buffer(data)
	file.close()
	var abs_path := ProjectSettings.globalize_path(path)
	var abs_tmp := ProjectSettings.globalize_path(tmp)
	DirAccess.remove_absolute(abs_path + ".bak")
	if FileAccess.file_exists(path):
		DirAccess.rename_absolute(abs_path, abs_path + ".bak")
	if DirAccess.rename_absolute(abs_tmp, abs_path) != OK:
		DirAccess.rename_absolute(abs_path + ".bak", abs_path)
		return false
	return true


## Syncs one slot. Returns "uploaded", "synced", "pending", "error" or "skipped".
func sync_slot(slot: int, force_upload: bool = false) -> String:
	if slot < 1 or slot > Global.MAX_WORLDS or not is_enabled():
		return "skipped"
	if _syncing.has(slot):
		# A save landed while this slot was uploading; re-run when it finishes.
		_dirty[slot] = true
		return "skipped"
	var path := "user://save_slot_%d.json" % slot
	if not FileAccess.file_exists(path):
		return "skipped"

	_syncing[slot] = true
	Global.set_cloud_status(Global.CloudStatus.SYNCING, "Syncing world…")
	var local_info: Dictionary = Global.get_save_info(slot)
	var local_uid := str(local_info.get("world_uid", "")).strip_edges()
	var local_revision: int = maxi(0, int(local_info.get("save_revision", 0)))
	if local_uid.is_empty() or local_revision <= 0:
		local_info = Global.ensure_save_identity(slot)
		local_uid = str(local_info.get("world_uid", "")).strip_edges()
		local_revision = maxi(0, int(local_info.get("save_revision", 0)))
	var checksum := FileAccess.get_sha256(path)

	var cloud := await Supabase.list_saves()
	if not cloud.ok:
		_finish(slot)
		_apply_failure(cloud)
		return "error"
	var meta := _find_meta(cloud.data, slot)
	var decision := "upload" if force_upload else classify_sync(local_uid, local_revision, checksum, meta)
	if decision == "synced":
		Global.set_cloud_status(Global.CloudStatus.SYNCED)
		_finish(slot)
		return "synced"
	if decision == "pending":
		Global.set_cloud_status(Global.CloudStatus.PENDING,
			"Cloud copy is newer, diverged, or belongs to another world - resolve in Cloud Saves.")
		_finish(slot)
		return "pending"

	var data := FileAccess.get_file_as_bytes(path)
	if data.is_empty():
		_finish(slot)
		Global.set_cloud_status(Global.CloudStatus.ERROR, "Local save unreadable.")
		return "error"
	var upload := await Supabase.upload_save(slot, data, Global.world_name_of(slot),
		local_uid, local_revision)
	_finish(slot)
	if not upload.ok:
		_apply_failure(upload)
		return "error"
	Global.set_cloud_status(Global.CloudStatus.SYNCED)
	return "uploaded"


## Pure decision function used by sync_slot and the regression suite.
## Returns "upload" for no cloud row yet, "synced" for identical
## bytes, "upload" when this device's revision is strictly newer, and "pending"
## for every ambiguous/different-world/older/diverge case.
func classify_sync(local_uid: String, local_revision: int, local_checksum: String,
		meta: Dictionary) -> String:
	if meta.is_empty():
		return "upload"
	var cloud_checksum := str(meta.get("checksum", ""))
	if cloud_checksum == local_checksum:
		return "synced"
	var cloud_uid := str(meta.get("world_uid", "")).strip_edges()
	var cloud_revision: int = maxi(0, int(meta.get("revision", 0)))
	# Legacy metadata has no identity/revision. Never silently overwrite it.
	if cloud_uid.is_empty() or local_uid.strip_edges().is_empty():
		return "pending"
	if cloud_uid != local_uid.strip_edges():
		return "pending"
	# Equal revisions with different bytes means both devices saved independently
	# from the same base; a higher cloud revision means the other device is newer.
	if cloud_revision > local_revision:
		return "pending"
	if cloud_revision == local_revision:
		return "pending"
	return "upload"


func _finish(slot: int) -> void:
	_syncing.erase(slot)
	if _dirty.has(slot):
		_dirty.erase(slot)
		if is_enabled():
			sync_slot(slot)   # fire-and-forget catch-up for the newer save


func _find_meta(rows: Variant, slot: int) -> Dictionary:
	if not (rows is Array):
		return {}
	for row in rows:
		if typeof(row) == TYPE_DICTIONARY and int((row as Dictionary).get("slot", 0)) == slot:
			return row
	return {}


func _apply_failure(result: Dictionary) -> void:
	if str(result.get("error", "")) == "cloud_limit" or bool(result.get("limit", false)):
		# Automatic sync cannot open the replacement chooser; keep the local
		# world and tell the player to manage cloud saves manually.
		Global.set_cloud_status(Global.CloudStatus.PENDING,
			"Cloud limit (%d) reached — manage Cloud Saves." % SupabaseConfig.CLOUD_SAVE_LIMIT)
		return
	if result.status == 0:
		Global.set_cloud_status(Global.CloudStatus.OFFLINE, "No connection")
	elif result.status == 401 or result.status == 403:
		Global.set_cloud_status(Global.CloudStatus.ERROR, "Session expired")
	else:
		Global.set_cloud_status(Global.CloudStatus.PENDING,
			"Upload failed; local save kept.")
