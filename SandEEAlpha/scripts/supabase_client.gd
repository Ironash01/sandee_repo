extends Node
## `Supabase` autoload — the game's only gateway to the SandEE cloud backend.
##
## Responsibilities:
##   * username/password auth (sign up, sign in by username, email fallback,
##     refresh, sign out) with the session cached in `user://`
##   * profile reads, star leaderboards and idempotent reward claims
##   * private cloud saves in the `cloud-saves` Storage bucket + metadata table
##
## Everything is opt-in: `_ready()` only reads the cached session from disk and
## never touches the network, so the game stays fully playable offline.
##
## The client uses the publishable key from `SupabaseConfig` only. Rules about
## what a signed-in player may read or write live in the database (RLS + column
## grants), not in this script. Access tokens are never printed to the console.

signal auth_changed(signed_in: bool)
signal request_failed(context: String, message: String)

const _CONFIG := preload("res://scripts/supabase_config.gd")

var access_token := ""
var refresh_token := ""
var expires_at := 0.0
var user: Dictionary = {}
## Cached `profiles` row for the signed-in player (username + star totals).
var profile: Dictionary = {}
## Set by username_available() when the check itself failed (network), so the
## registration form can show a connection error instead of "username taken".
var last_username_check_error: String = ""

const _SESSION_IV_BYTES := 16


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_load_session()


# ── Session state ─────────────────────────────────────────────────────────

func is_signed_in() -> bool:
	return access_token != "" and not user.is_empty()


func user_id() -> String:
	return str(user.get("id", ""))


func username() -> String:
	var meta: Variant = user.get("user_metadata", {})
	if typeof(meta) == TYPE_DICTIONARY and meta.has("username"):
		return str(meta["username"])
	return str(user.get("username", ""))


## Canonical username from the profile row (falls back to the auth metadata).
func display_username() -> String:
	var from_profile := str(profile.get("username", "")).strip_edges()
	return from_profile if not from_profile.is_empty() else username()


func email() -> String:
	return str(user.get("email", ""))


func has_stored_session() -> bool:
	return access_token != "" or refresh_token != ""


# ── Session persistence ───────────────────────────────────────────────────
# Tokens are written through `FileAccess.open_encrypted_with_pass`, so
# `user://supabase_session.bin` is an encrypted file, not a plaintext credential
# store. The passphrase is derived from this device's identity, making the file
# device-bound. This is not an OS keychain (that would need a native plugin);
# passwords themselves are never persisted.

func _session_pass() -> String:
	var device_id := OS.get_unique_id().strip_edges()
	if device_id.is_empty():
		device_id = str(ProjectSettings.globalize_path("user://"))
	return "SandEE|cloud-session|v1|" + device_id + "|" + OS.get_processor_name()


func _load_session() -> void:
	_remove_legacy_session_file()
	if not FileAccess.file_exists(_CONFIG.SESSION_PATH):
		return
	var file := FileAccess.open_encrypted_with_pass(
		_CONFIG.SESSION_PATH, FileAccess.READ, _session_pass()
	)
	if file == null:
		_wipe_session_file()
		return
	var text := file.get_as_text()
	file.close()
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		_wipe_session_file()
		return
	access_token = str(parsed.get("access_token", ""))
	refresh_token = str(parsed.get("refresh_token", ""))
	expires_at = float(parsed.get("expires_at", 0.0))
	var stored_user: Variant = parsed.get("user", {})
	if typeof(stored_user) == TYPE_DICTIONARY:
		user = stored_user


func _save_session() -> void:
	if access_token == "":
		_clear_session()
		return
	var tmp_path := _CONFIG.SESSION_PATH + ".tmp"
	var file := FileAccess.open_encrypted_with_pass(tmp_path, FileAccess.WRITE, _session_pass())
	if file == null:
		return   # never fall back to plaintext
	file.store_string(JSON.stringify({
		"access_token": access_token,
		"refresh_token": refresh_token,
		"expires_at": expires_at,
		"user": user,
	}))
	file.close()
	var abs_path := ProjectSettings.globalize_path(_CONFIG.SESSION_PATH)
	var abs_tmp := ProjectSettings.globalize_path(tmp_path)
	DirAccess.remove_absolute(abs_path)
	if DirAccess.rename_absolute(abs_tmp, abs_path) != OK:
		DirAccess.remove_absolute(abs_tmp)


func _remove_legacy_session_file() -> void:
	if not FileAccess.file_exists(_CONFIG.LEGACY_SESSION_PATH):
		return
	var dir := DirAccess.open("user://")
	if dir != null and dir.file_exists("supabase_session.json"):
		dir.remove("supabase_session.json")


func _wipe_session_file() -> void:
	var dir := DirAccess.open("user://")
	if dir != null and dir.file_exists("supabase_session.bin"):
		dir.remove("supabase_session.bin")


func _clear_session() -> void:
	var was_signed_in := is_signed_in()
	access_token = ""
	refresh_token = ""
	expires_at = 0.0
	user = {}
	profile = {}
	_wipe_session_file()
	if was_signed_in:
		auth_changed.emit(false)


func _apply_session(payload: Dictionary) -> void:
	var session: Dictionary = payload
	if typeof(payload.get("session")) == TYPE_DICTIONARY:
		session = payload["session"]
	if payload.has("access_token"):
		access_token = str(payload["access_token"])
	elif session.has("access_token"):
		access_token = str(session["access_token"])
	if payload.has("refresh_token"):
		refresh_token = str(payload["refresh_token"])
	elif session.has("refresh_token"):
		refresh_token = str(session["refresh_token"])
	var expires_in := float(payload.get("expires_in", session.get("expires_in", 3600)))
	expires_at = Time.get_unix_time_from_system() + expires_in
	var payload_user: Variant = payload.get("user", null)
	if typeof(payload_user) == TYPE_DICTIONARY:
		# A different account must never inherit the previous profile cache.
		if str(user.get("id", "")) != str((payload_user as Dictionary).get("id", "")):
			profile = {}
		user = payload_user
	elif typeof(session.get("user")) == TYPE_DICTIONARY:
		user = session["user"]
	_save_session()
	auth_changed.emit(true)


# ── Authentication ────────────────────────────────────────────────────────

## Creates an account. `username` is stored in the signup metadata and turned
## into a `profiles` row by the database trigger. Check `username_available()`
## first; the trigger falls back to a generated name on a race.
func sign_up(email: String, password: String, username: String) -> Dictionary:
	var result := await _request("POST", "/auth/v1/signup", {
		"email": email,
		"password": password,
		"data": {"username": username},
	}, false)
	if result.ok:
		_apply_session(result.data)
	return result


## Registers with only a username and password. Supabase Auth needs an
## email-shaped identifier, so it is derived privately from the username
## (`<lowercase username>@users.sandee.invalid`) and is never collected, shown
## or emailed. `.invalid` is reserved by RFC 2606.
func register(username_value: String, password: String) -> Dictionary:
	var uname := username_value.strip_edges()
	var account_email := uname.to_lower() + "@" + _CONFIG.ACCOUNT_EMAIL_DOMAIN
	return await sign_up(account_email, password, uname)


## Signs in with a username through the `login-with-username` Edge Function.
func sign_in(username_value: String, password: String) -> Dictionary:
	var result := await _request("POST", "/functions/v1/login-with-username", {
		"username": username_value,
		"password": password,
	}, false)
	if result.ok:
		_apply_session(result.data)
	return result


## Email/password fallback if the Edge Function is unavailable.
func sign_in_with_email(email: String, password: String) -> Dictionary:
	var result := await _request("POST", "/auth/v1/token?grant_type=password", {
		"email": email,
		"password": password,
	}, false)
	if result.ok:
		_apply_session(result.data)
	return result


func refresh_session(timeout: float = -1.0) -> bool:
	if refresh_token == "":
		return false
	var result := await _request("POST", "/auth/v1/token?grant_type=refresh_token", {
		"refresh_token": refresh_token,
	}, false, {}, timeout)
	if result.ok:
		_apply_session(result.data)
		return true
	# A network outage must NOT destroy a valid refresh token: only a definitive
	# auth rejection (4xx) clears the stored session.
	if result.status >= 400 and result.status < 500:
		_clear_session()
	return false


## Restores and validates the stored session against the live backend.
## Returns true only when the profile row was actually retrieved. The short
## default timeout keeps the startup screen from waiting on a dead session.
func validate_session(timeout: float = 6.0) -> bool:
	if not await ensure_session(timeout):
		return false
	var result := await get_profile(timeout)
	if result.ok and result.data is Array and (result.data as Array).size() == 1:
		profile = (result.data as Array)[0]
		return true
	if result.status == 401 or result.status == 403:
		_clear_session()
	return false


## Refreshes the cached profile row (username + star totals).
func refresh_profile() -> Dictionary:
	var result := await get_profile()
	if result.ok and result.data is Array and (result.data as Array).size() == 1:
		profile = (result.data as Array)[0]
	return result


## Returns true when a usable access token is available (refreshing if needed).
func ensure_session(timeout: float = -1.0) -> bool:
	if access_token == "":
		return false
	if expires_at <= 0.0:
		return true
	if Time.get_unix_time_from_system() + _CONFIG.REFRESH_MARGIN_SEC < expires_at:
		return true
	return await refresh_session(timeout)


func sign_out() -> void:
	if access_token == "":
		_clear_session()
		return
	var headers := _auth_headers()
	# Local sign-out is instant and must work offline: clear the session first,
	# then revoke the server session in the background (best effort, 3s timeout).
	_clear_session()
	_revoke_remote(headers)


func _revoke_remote(headers: PackedStringArray) -> void:
	await _send(
		"POST",
		_CONFIG.PROJECT_URL + "/auth/v1/logout",
		headers,
		PackedByteArray(),
		3.0
	)


# ── Profiles & progression ────────────────────────────────────────────────

func username_available(username_value: String) -> bool:
	last_username_check_error = ""
	if username_value.strip_edges() == "":
		return false
	# Availability is public and is checked before an account exists.
	var result := await _request(
		"POST", "/rest/v1/rpc/username_available", {"uname": username_value}, false
	)
	if not result.ok:
		last_username_check_error = str(result.error)
		return false
	return result.data == true


## Renames the signed-in player. Requires the account to be signed in.
func set_username(username_value: String) -> Dictionary:
	if not is_signed_in():
		return _error_result("not signed in")
	return await _request("PATCH", "/rest/v1/profiles?id=eq." + user_id(), {
		"username": username_value,
	})


func get_profile(timeout: float = -1.0) -> Dictionary:
	if not is_signed_in():
		return _error_result("not signed in")
	return await select(
		"profiles",
		"select=id,username,blue_stars,yellow_stars,created_at,updated_at&id=eq." + user_id(),
		timeout
	)


## Claims one or more whitelisted mission rewards. The server only accepts ids
## present in `mission_rewards`, awards a fixed amount and ignores repeats, so
## this is safe to call with the whole local mission list on every world load.
func claim_missions(reward_ids: Array, expected_account_id: String = "") -> Dictionary:
	if not expected_account_id.is_empty() and user_id() != expected_account_id:
		return _error_result("account changed")
	var ids: Array = []
	for entry in reward_ids:
		var rid := str(entry).strip_edges()
		if not rid.is_empty() and ids.size() < 200:
			ids.append(rid)
	if ids.is_empty():
		return {"ok": true, "status": 200, "data": [], "error": ""}
	if not expected_account_id.is_empty() and user_id() != expected_account_id:
		return _error_result("account changed")
	var result := await rpc_call("claim_missions", {"p_reward_ids": ids})
	if not expected_account_id.is_empty() and user_id() != expected_account_id:
		return _error_result("account changed")
	return result


func get_my_rewards() -> Dictionary:
	if not is_signed_in():
		return _error_result("not signed in")
	return await select(
		"reward_claims",
		"select=reward_id,blue_stars,yellow_stars,claimed_at&user_id=eq." + user_id()
		+ "&order=claimed_at.desc"
	)


## Distinguishes "no internet" from "internet works but Supabase is unreachable".
## Both probes are short and asynchronous, so the startup screen never freezes.
func check_connectivity() -> Dictionary:
	var health := await _request(
		"GET", "/auth/v1/health", null, false, {}, _CONFIG.PING_TIMEOUT_SEC
	)
	if health.ok:
		return {"internet": true, "backend": true, "detail": ""}
	var probe := await _send(
		"GET",
		_CONFIG.INTERNET_PROBE_URL,
		PackedStringArray(["Accept: */*"]),
		PackedByteArray(),
		_CONFIG.PING_TIMEOUT_SEC
	)
	var internet := int(probe.result) == HTTPRequest.RESULT_SUCCESS and int(probe.status) > 0
	return {
		"internet": internet,
		"backend": false,
		"detail": ("Sandee online service is unavailable." if internet
			else "Internet connection required."),
	}


# ── Cloud saves ───────────────────────────────────────────────────────────

## Production leaderboard. `kind` selects the ranking:
## "total_stars" (overall), "blue_stars" (dungeons) or "yellow_stars" (quests).
## `include_test` reads the test-only view; the production view never contains
## test profiles, so the game UI always uses the default.
func get_leaderboard(kind: String = "total_stars", limit: int = 50,
		include_test: bool = false) -> Dictionary:
	var column := "total_stars"
	if kind == "blue_stars" or kind == "dungeon":
		column = "blue_stars"
	elif kind == "yellow_stars" or kind == "quest" or kind == "general":
		column = "yellow_stars"
	var table := "leaderboard_test" if include_test else "leaderboard"
	var safe_limit := clampi(limit, 1, 100)
	return await select(
		table,
		"select=username,blue_stars,yellow_stars,total_stars&order=%s.desc,username.asc&limit=%d"
		% [column, safe_limit]
	)


## Uploads a save file (usually JSON text) and refreshes its metadata row.
## `slot` is 1..10, matching the `cloud_saves.slot` constraint.
func upload_save(slot: int, data: PackedByteArray, world_name: String = "",
		world_uid: String = "", revision: int = 0) -> Dictionary:
	if not is_signed_in():
		return _error_result("not signed in")
	var account_id := user_id()
	if account_id.is_empty():
		return _error_result("not signed in")
	if slot < 1 or slot > 10:
		return _error_result("slot out of range")
	# Cloud-save limit: 5 slots per account. Check before uploading to Storage
	# so a rejected save never leaves an orphaned object behind.
	var existing := await list_saves()
	if user_id() != account_id or not is_signed_in():
		return _error_result("account changed")
	if not existing.ok:
		return existing
	var rows: Array = existing.data if existing.data is Array else []
	var already_there := false
	for row in rows:
		if typeof(row) == TYPE_DICTIONARY and int((row as Dictionary).get("slot", -1)) == slot:
			already_there = true
			break
	if not already_there and rows.size() >= _CONFIG.CLOUD_SAVE_LIMIT:
		return {
			"ok": false,
			"status": 409,
			"data": null,
			"error": "cloud_limit",
			"limit": true,
		}
	var object_path := "%s/%d.json" % [account_id, slot]
	var headers := _auth_headers()
	headers.append("Content-Type: application/json")
	headers.append("x-upsert: true")
	var upload := await _send(
		"POST",
		"%s/storage/v1/object/%s/%s" % [_CONFIG.PROJECT_URL, _CONFIG.CLOUD_SAVE_BUCKET, object_path],
		headers,
		data
	)
	if user_id() != account_id or not is_signed_in():
		return _error_result("account changed")
	if int(upload.status) == 401:
		_clear_session()
	if not upload.ok:
		return _result_from_send(upload, "/storage upload")
	var checksum := _sha256(data)
	var meta := await _request("POST", "/rest/v1/cloud_saves", {
		"user_id": account_id,
		"slot": slot,
		"object_path": object_path,
		"world_name": world_name.substr(0, 64),
		"world_uid": world_uid.substr(0, 64),
		"revision": maxi(0, revision),
		"size_bytes": data.size(),
		"checksum": checksum,
	}, true, {"Prefer": "resolution=merge-duplicates,return=minimal"})
	# Compatibility with a database that has not applied the identity/revision
	# migration yet: keep cloud saves usable by storing the legacy columns.
	if not meta.ok and _is_legacy_cloud_meta_error(str(meta.get("error", ""))):
		meta = await _request("POST", "/rest/v1/cloud_saves", {
			"user_id": account_id,
			"slot": slot,
			"object_path": object_path,
			"world_name": world_name.substr(0, 64),
			"size_bytes": data.size(),
			"checksum": checksum,
		}, true, {"Prefer": "resolution=merge-duplicates,return=minimal"})
	if not meta.ok and not already_there:
		# Do not leave an orphaned first upload if its metadata row was rejected.
		# An existing slot is never deleted here: its previous object was already
		# replaced and deleting it would destroy a valid cloud save.
		await _send("DELETE",
			"%s/storage/v1/object/%s/%s" % [_CONFIG.PROJECT_URL,
				_CONFIG.CLOUD_SAVE_BUCKET, object_path],
			_auth_headers(), PackedByteArray())
	return meta


## Returns the raw bytes of a cloud save, or an error result.
func download_save(slot: int) -> Dictionary:
	if not is_signed_in():
		return _error_result("not signed in")
	var account_id := user_id()
	if account_id.is_empty():
		return _error_result("not signed in")
	if slot < 1 or slot > 10:
		return _error_result("slot out of range")
	var object_path := "%s/%d.json" % [account_id, slot]
	var download := await _send(
		"GET",
		"%s/storage/v1/object/%s/%s" % [_CONFIG.PROJECT_URL, _CONFIG.CLOUD_SAVE_BUCKET, object_path],
		_auth_headers(),
		PackedByteArray()
	)
	if user_id() != account_id or not is_signed_in():
		return _error_result("account changed")
	if int(download.status) == 401:
		_clear_session()
	if not download.ok:
		return _result_from_send(download, "/storage download")
	return {
		"ok": true,
		"status": download.status,
		"data": download.body,
		"error": "",
	}


## Convenience wrapper for JSON saves.
func download_save_json(slot: int) -> Dictionary:
	var result := await download_save(slot)
	if not result.ok:
		return result
	var parsed: Variant = JSON.parse_string(result.data.get_string_from_utf8())
	if typeof(parsed) != TYPE_DICTIONARY:
		return _error_result("cloud save is not valid JSON")
	return {"ok": true, "status": result.status, "data": parsed, "error": ""}


func list_saves() -> Dictionary:
	if not is_signed_in():
		return _error_result("not signed in")
	var account_id := user_id()
	if account_id.is_empty():
		return _error_result("not signed in")
	var result := await select(
		"cloud_saves",
		"select=*&user_id=eq." + account_id + "&order=slot.asc"
	)
	if user_id() != account_id or not is_signed_in():
		return _error_result("account changed")
	# Defense in depth: nothing in the UI or sync layer may consume a row that
	# does not explicitly belong to the captured account, even if a filter was
	# ignored or a proxy returned mixed data.
	if result.ok and result.data is Array:
		var owned_rows: Array = []
		for row in (result.data as Array):
			if typeof(row) == TYPE_DICTIONARY \
					and str((row as Dictionary).get("user_id", "")) == account_id:
				owned_rows.append(row)
		result["data"] = owned_rows
	return result


func delete_save(slot: int) -> Dictionary:
	if not is_signed_in():
		return _error_result("not signed in")
	var account_id := user_id()
	if account_id.is_empty():
		return _error_result("not signed in")
	if slot < 1 or slot > 10:
		return _error_result("slot out of range")
	var object_path := "%s/%d.json" % [account_id, slot]
	var removed := await _send(
		"DELETE",
		"%s/storage/v1/object/%s/%s" % [_CONFIG.PROJECT_URL, _CONFIG.CLOUD_SAVE_BUCKET, object_path],
		_auth_headers(),
		PackedByteArray()
	)
	if user_id() != account_id or not is_signed_in():
		return _error_result("account changed")
	if int(removed.status) == 401:
		_clear_session()
	var meta := await _request(
		"DELETE",
		"/rest/v1/cloud_saves?user_id=eq.%s&slot=eq.%d" % [account_id, slot],
		null,
		true,
		{"Prefer": "return=minimal"}
	)
	if not removed.ok:
		return _result_from_send(removed, "/storage delete")
	return meta


# ── PostgREST helpers ─────────────────────────────────────────────────────

func select(table: String, query: String = "", timeout: float = -1.0) -> Dictionary:
	var path := "/rest/v1/" + table
	if query != "":
		path += "?" + query
	return await _request("GET", path, null, true, {}, timeout)


func rpc_call(function_name: String, args: Dictionary = {}) -> Dictionary:
	return await _request("POST", "/rest/v1/rpc/" + function_name, args)


# ── HTTP plumbing ─────────────────────────────────────────────────────────

func _auth_headers() -> PackedStringArray:
	return PackedStringArray([
		"apikey: " + _CONFIG.PUBLISHABLE_KEY,
		"Authorization: Bearer " + access_token,
	])


func _request(
	method: String,
	path: String,
	body: Variant = null,
	requires_auth: bool = true,
	extra_headers: Dictionary = {},
	timeout: float = -1.0
) -> Dictionary:
	var headers := PackedStringArray([
		"apikey: " + _CONFIG.PUBLISHABLE_KEY,
		"Accept: application/json",
	])
	if requires_auth:
		var has_session: bool = await ensure_session()
		if not has_session:
			return _error_result("not signed in")
		headers.append("Authorization: Bearer " + access_token)
	var payload := PackedByteArray()
	if body != null:
		headers.append("Content-Type: application/json")
		if typeof(body) == TYPE_STRING:
			payload = (body as String).to_utf8_buffer()
		else:
			payload = JSON.stringify(body).to_utf8_buffer()
	for key: String in extra_headers:
		headers.append("%s: %s" % [key, str(extra_headers[key])])
	var sent := await _send(method, _CONFIG.PROJECT_URL + path, headers, payload, timeout)
	var parsed: Variant = null
	var text: String = sent.body.get_string_from_utf8()
	if text != "":
		parsed = JSON.parse_string(text)
	if not sent.ok:
		var message := _send_error(sent, parsed)
		request_failed.emit(path, message)
		if requires_auth and sent.status == 401:
			# An expired/revoked bearer token must revoke the local account
			# context immediately, not just fail one request.
			_clear_session()
		return {"ok": false, "status": sent.status, "data": parsed, "error": message}
	return {"ok": true, "status": sent.status, "data": parsed, "error": ""}


func _send(method: String, url: String, headers: PackedStringArray, payload: PackedByteArray,
		timeout: float = -1.0) -> Dictionary:
	var http := HTTPRequest.new()
	http.timeout = _CONFIG.TIMEOUT_SEC if timeout <= 0.0 else timeout
	http.use_threads = false
	add_child(http)
	var http_method := HTTPClient.METHOD_GET
	match method:
		"POST":
			http_method = HTTPClient.METHOD_POST
		"PUT":
			http_method = HTTPClient.METHOD_PUT
		"PATCH":
			http_method = HTTPClient.METHOD_PATCH
		"DELETE":
			http_method = HTTPClient.METHOD_DELETE
	# `HTTPRequest.request()` (Godot 4.6) takes the body as a String; all cloud
	# payloads are UTF-8 JSON, and Godot re-encodes the text as UTF-8.
	var err := http.request(url, headers, http_method, payload.get_string_from_utf8())
	if err != OK:
		http.queue_free()
		return {
			"ok": false,
			"status": 0,
			"body": PackedByteArray(),
			"result": err,
		}
	var response: Array = await http.request_completed
	http.queue_free()
	var result_code := int(response[0])
	var http_code := int(response[1])
	var body: PackedByteArray = response[3]
	return {
		"ok": result_code == HTTPRequest.RESULT_SUCCESS and http_code >= 200 and http_code < 300,
		"status": http_code,
		"body": body,
		"result": result_code,
	}


func _result_from_send(sent: Dictionary, context: String) -> Dictionary:
	var text: String = sent.body.get_string_from_utf8()
	var parsed: Variant = null
	if text != "":
		parsed = JSON.parse_string(text)
	var message := _send_error(sent, parsed)
	request_failed.emit(context, message)
	return {"ok": false, "status": sent.status, "data": parsed, "error": message}


func _send_error(sent: Dictionary, parsed: Variant) -> String:
	if int(sent.result) != HTTPRequest.RESULT_SUCCESS:
		return _result_text(int(sent.result))
	if typeof(parsed) == TYPE_DICTIONARY:
		for key: String in ["message", "msg", "error_description", "error"]:
			if parsed.has(key) and str(parsed[key]) != "":
				return "%d: %s" % [sent.status, str(parsed[key])]
	return "HTTP %d" % sent.status


func _result_text(result: int) -> String:
	match result:
		HTTPRequest.RESULT_CANT_CONNECT:
			return "offline: cannot connect"
		HTTPRequest.RESULT_CANT_RESOLVE:
			return "offline: cannot resolve host"
		HTTPRequest.RESULT_CONNECTION_ERROR:
			return "offline: connection error"
		HTTPRequest.RESULT_TIMEOUT:
			return "offline: request timed out"
		HTTPRequest.RESULT_TLS_HANDSHAKE_ERROR:
			return "offline: TLS handshake failed"
		_:
			return "request failed (%d)" % result


func _error_result(message: String) -> Dictionary:
	return {"ok": false, "status": 0, "data": null, "error": message}


func _is_legacy_cloud_meta_error(message: String) -> bool:
	var lower := message.to_lower()
	var identity_column := lower.contains("world_uid") or lower.contains("revision")
	var schema_error := lower.contains("column") or lower.contains("schema cache") \
		or lower.contains("does not exist") or lower.contains("could not find")
	return identity_column and schema_error

## Public, allocation-free checksum helper shared by upload/download validation.
func checksum_bytes(data: PackedByteArray) -> String:
	return _sha256(data)


func _sha256(data: PackedByteArray) -> String:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(data)
	return context.finish().hex_encode()
