extends Node

const ANON_ID_FILE := "user://anonymous_id.cfg"
const ANON_ID_KEY := "anonymous_id"

var _initialized: bool = false
var _is_server_mode: bool = false
var _anonymous_id: String = ""
var _project_id: String = ""
var _env_id: String = ""
var _base_url: String = ""


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func initialize_player_mode(crux_url: String, project_id: String, env_id: String, api_key: String) -> void:
	_is_server_mode = false
	_project_id = project_id
	_env_id = env_id
	_base_url = crux_url.rstrip("/")
	Crux.init_player(crux_url, project_id, env_id, api_key)
	_initialized = true
	DemoEvents.record("AUTH", "Initialized player mode", "project=%s env=%s" % [project_id, env_id], 0, true)


func initialize_server_mode(crux_url: String, project_id: String, env_id: String, server_token: String) -> void:
	_is_server_mode = true
	_project_id = project_id
	_env_id = env_id
	_base_url = crux_url.rstrip("/")
	Crux.init_server(crux_url, project_id, env_id, server_token)
	_initialized = true
	print("CruxSession: Server mode initialized")


func is_initialized() -> bool:
	return _initialized


func get_project_id() -> String:
	return _project_id


func get_environment_id() -> String:
	return _env_id


func get_player_access_token() -> String:
	return Crux.get_player_access_token()


func _ensure_initialized() -> Dictionary:
	if _initialized:
		return {}
	return {"error": "not_initialized"}


func _get_persistent_anonymous_id() -> String:
	if not _anonymous_id.is_empty():
		return _anonymous_id
	var config := ConfigFile.new()
	if config.load(ANON_ID_FILE) == OK:
		_anonymous_id = str(config.get_value("identity", ANON_ID_KEY, ""))
	if _anonymous_id.is_empty():
		_anonymous_id = "anon-%d-%d" % [Time.get_unix_time_from_system(), randi()]
		config.set_value("identity", ANON_ID_KEY, _anonymous_id)
		config.save(ANON_ID_FILE)
	return _anonymous_id


func login_anonymous_persistent() -> Dictionary:
	var init_error := _ensure_initialized()
	if not init_error.is_empty():
		return init_error
	var start_time := Time.get_ticks_msec()
	var result := await Crux.login_anonymous(_get_persistent_anonymous_id())
	var elapsed := Time.get_ticks_msec() - start_time
	if _is_error(result):
		DemoEvents.record("AUTH", "Guest authentication failed", str(result.get("error", "unknown")), elapsed, false)
		return _as_error(result)
	var pid := str(result.get("player_id", ""))
	if pid.is_empty():
		return {"error": "authentication_returned_no_player_id"}
	var generated_name := "Operator %04d" % (randi() % 10000)
	AppState.set_player_identity(pid, str(result.get("display_name", generated_name)))
	DemoEvents.record("AUTH", "Guest authenticated", "pid=%s" % pid.substr(0, 8), elapsed, true)
	return result


func verify_player_token(player_jwt: String) -> Dictionary:
	if not _is_server_mode:
		return {"error": "not_server_mode"}
	if player_jwt.is_empty():
		return {"error": "missing_player_token"}
	var result := await Crux.verify_player_token(player_jwt)
	# Crux has no /auth/verify endpoint yet; the SDK call 404s. Until it exists,
	# fall back to proving the token against a player-scoped endpoint.
	if _is_error(result) and int(result.get("status", 0)) == 404:
		return await _verify_player_token_by_probe(player_jwt)
	return result


## Authoritative check without /auth/verify.
##
## The player_id in the JWT payload is read but NOT trusted: it only says which
## player-scoped resource to probe. The probe is what proves identity. Crux
## answers 200 only when the token is validly signed, unexpired, and belongs to
## that exact player; a forged payload fails signature validation (401) and a
## valid token aimed at another player is refused (403). So a 200 proves the
## bearer really is claimed_id.
##
## Replace this with Crux.verify_player_token() once the endpoint ships.
func _verify_player_token_by_probe(player_jwt: String) -> Dictionary:
	var claims := _decode_jwt_claims(player_jwt)
	if claims.is_empty():
		return {"error": "token_malformed"}
	var claimed_id := str(claims.get("player_id", ""))
	if claimed_id.is_empty():
		return {"error": "token_has_no_player_id"}
	# Cheap local screens; the probe below is the authority.
	if str(claims.get("project_id", "")) != _project_id:
		return {"error": "token_project_mismatch"}
	var expiry := int(claims.get("exp", 0))
	if expiry > 0 and Time.get_unix_time_from_system() >= float(expiry):
		return {"error": "token_expired"}

	var status := await _probe_player_scope(claimed_id, player_jwt)
	match status:
		200:
			return {
				"player_id": claimed_id,
				"project_id": _project_id,
				"environment_id": _env_id,
				"display_name": str(claims.get("display_name", "")),
			}
		401:
			return {"error": "token_invalid"}
		403:
			return {"error": "player_id_mismatch"}
		_:
			# Never fail open: an unreachable verifier rejects the join.
			return {"error": "verifier_unavailable", "status": status}


func _probe_player_scope(player_id: String, player_jwt: String) -> int:
	var http := HTTPRequest.new()
	add_child(http)
	var url := "%s/v1/projects/%s/environments/%s/players/%s/documents" % [
		_base_url, _project_id, _env_id, player_id.uri_encode()]
	var err := http.request(url, ["Authorization: Bearer " + player_jwt], HTTPClient.METHOD_GET)
	if err != OK:
		http.queue_free()
		return -1
	var response: Array = await http.request_completed
	http.queue_free()
	# response = [result, response_code, headers, body]
	if int(response[0]) != HTTPRequest.RESULT_SUCCESS:
		return -1
	return int(response[1])


func _decode_jwt_claims(token: String) -> Dictionary:
	var parts := token.split(".")
	if parts.size() != 3:
		return {}
	var payload := str(parts[1]).replace("-", "+").replace("_", "/")
	while payload.length() % 4 != 0:
		payload += "="
	var decoded := Marshalls.base64_to_utf8(payload)
	if decoded.is_empty():
		return {}
	var parsed = JSON.parse_string(decoded)
	return parsed if parsed is Dictionary else {}


func get_player_document(pid: String, key: String) -> Dictionary:
	var init_error := _ensure_initialized()
	if not init_error.is_empty():
		return init_error
	var result := await Crux.get_player_document(pid, key)
	return result if result is Dictionary else {"error": "invalid_response"}


func _get_or_create_document(pid: String, key: String, default_value: Dictionary) -> Dictionary:
	var result := await get_player_document(pid, key)
	if not _is_error(result):
		return result
	if int(result.get("status", 0)) != 404:
		return result
	var created := await Crux.set_player_document(pid, key, default_value)
	if _is_error(created):
		return created
	return {"key": key, "value": default_value, "version": int(created.get("version", 0))}


func get_profile(pid: String) -> Dictionary:
	var start_time := Time.get_ticks_msec()
	var default_profile: Dictionary = SharedResources.DEFAULT_PROFILE.duplicate(true)
	default_profile["display_name"] = AppState.display_name if not AppState.display_name.is_empty() else "Operator"
	default_profile["created_at"] = Time.get_datetime_string_from_system(true)
	var result := await _get_or_create_document(pid, "profile", default_profile)
	var elapsed := Time.get_ticks_msec() - start_time
	DemoEvents.record("PLAYER_DATA", "Profile loaded" if not _is_error(result) else "Profile load failed", "pid=%s" % pid.substr(0, 8), elapsed, not _is_error(result))
	return result


func get_loadout(pid: String) -> Dictionary:
	return await _get_or_create_document(pid, "loadout", SharedResources.DEFAULT_LOADOUT.duplicate(true))


func get_progression(pid: String) -> Dictionary:
	return await _get_or_create_document(pid, "progression", SharedResources.DEFAULT_PROGRESSION.duplicate(true))


func save_profile(pid: String, value: Dictionary, version: int = -1) -> Dictionary:
	return await Crux.set_player_document(pid, "profile", value, version)


func save_loadout(pid: String, value: Dictionary, version: int = -1) -> Dictionary:
	return await Crux.set_player_document(pid, "loadout", value, version)


func save_progression(pid: String, value: Dictionary, version: int = -1) -> Dictionary:
	return await Crux.set_player_document(pid, "progression", value, version)


func claim_reward_receipt(pid: String, run_id: String) -> Dictionary:
	var doc := await get_player_document(pid, "reward_receipts")
	var value: Dictionary = {"recent_run_ids": []}
	var version := -1
	if not _is_error(doc):
		value = doc.get("value", value)
		version = int(doc.get("version", -1))
	elif int(doc.get("status", 0)) != 404:
		return doc
	var recent: Array = value.get("recent_run_ids", [])
	if run_id in recent:
		return {"error": "duplicate_run"}
	recent.push_front(run_id)
	if recent.size() > 100:
		recent.resize(100)
	var updated := {"recent_run_ids": recent}
	var result := await Crux.set_player_document(pid, "reward_receipts", updated, version)
	if _is_error(result):
		return _as_error(result)
	return {"ok": true, "version": result.get("version", version + 1)}


func check_reward_idempotency(pid: String, run_id: String) -> bool:
	var result := await get_player_document(pid, "reward_receipts")
	if _is_error(result):
		return false
	return run_id in result.get("value", {}).get("recent_run_ids", [])


func record_reward_receipt(pid: String, run_id: String, value: Dictionary, version: int) -> Dictionary:
	var recent: Array = value.get("recent_run_ids", [])
	if run_id not in recent:
		recent.push_front(run_id)
	if recent.size() > 100:
		recent.resize(100)
	return await Crux.set_player_document(pid, "reward_receipts", {"recent_run_ids": recent}, version)


func join_matchmaking(pid: String, game_mode: String, region: String) -> Dictionary:
	var start_time := Time.get_ticks_msec()
	var result := await Crux.join_matchmaking(pid, game_mode, region)
	var elapsed := Time.get_ticks_msec() - start_time
	DemoEvents.record("MATCHMAKING", "Ticket created" if not _is_error(result) else "Join failed", "%s / %s" % [game_mode, region], elapsed, not _is_error(result))
	return result


func poll_matchmaking() -> Dictionary:
	return await Crux.get_matchmaking_status()


func leave_matchmaking(pid: String) -> void:
	await Crux.leave_matchmaking(pid)


func register_server(reg: Dictionary) -> Dictionary:
	if not _is_server_mode:
		return {"error": "not_server_mode"}
	var result := await Crux.register_server(reg)
	DemoEvents.record("SERVER", "Server registered" if not _is_error(result) else "Registration failed", str(reg.get("region", "")), 0, not _is_error(result))
	return result


func server_heartbeat(server_id: String) -> Dictionary:
	if not _is_server_mode:
		return {"error": "not_server_mode"}
	return await Crux.heartbeat(server_id)


func deregister_server(server_id: String) -> void:
	if _is_server_mode:
		await Crux.deregister_server(server_id)


func list_servers(region: String = "", map_name: String = "", game_mode: String = "") -> Array:
	return await Crux.list_servers(region, map_name, game_mode)


func submit_score(leaderboard_id: String, pid: String, score: float, metadata: Dictionary = {}) -> Dictionary:
	if leaderboard_id.is_empty():
		return {"error": "leaderboard_id_missing"}
	var start_time := Time.get_ticks_msec()
	var result := await Crux.submit_score(leaderboard_id, pid, score, metadata)
	var elapsed := Time.get_ticks_msec() - start_time
	DemoEvents.record("LEADERBOARD", "Score submitted" if not _is_error(result) else "Score rejected", "board=%s score=%.0f" % [leaderboard_id, score], elapsed, not _is_error(result))
	return result


func get_leaderboard_top(leaderboard_id: String, limit: int = 10) -> Array:
	return await Crux.get_top(leaderboard_id, limit)


func get_player_standing(leaderboard_id: String, pid: String) -> Dictionary:
	return await Crux.get_player_standing(leaderboard_id, pid)


func get_player_economy(pid: String) -> Dictionary:
	return await Crux.get_player_economy(pid)


func adjust_economy(pid: String, balance_adjustments: Array = [], inventory_adjustments: Array = []) -> Dictionary:
	var start_time := Time.get_ticks_msec()
	var result := await Crux.adjust_economy(pid, balance_adjustments, inventory_adjustments)
	var elapsed := Time.get_ticks_msec() - start_time
	DemoEvents.record("ECONOMY", "Economy adjusted" if not _is_error(result) else "Adjustment failed", "pid=%s" % pid.substr(0, 8), elapsed, not _is_error(result))
	return result


func download_active_config_bundle() -> PackedByteArray:
	if not _initialized:
		return PackedByteArray()
	var start_time := Time.get_ticks_msec()
	var bundle := await Crux.download_active_config_bundle()
	var elapsed := Time.get_ticks_msec() - start_time
	DemoEvents.record("LIVE_CONFIG", "Bundle downloaded" if not bundle.is_empty() else "Bundle download failed", "%d bytes" % bundle.size(), elapsed, not bundle.is_empty())
	return bundle


func _is_error(result: Variant) -> bool:
	return not (result is Dictionary) or result.is_empty() or result.has("error")


func _as_error(result: Variant) -> Dictionary:
	return result if result is Dictionary else {"error": "invalid_response"}
