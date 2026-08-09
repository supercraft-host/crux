## Crux - Supercraft Game Services Backend SDK for Godot 4
##
## Enabling the addon (Project → Project Settings → Plugins → Crux) registers
## this script as an autoload named "Crux", so it is globally available with no
## further setup. You can also instantiate it manually and add_child() it.
##
## NOTE: deliberately no `class_name`. An autoload and a global class cannot
## share a name in Godot, and the autoload is the documented entry point.
##
## Usage (server mode - dedicated game server):
##   Crux.init_server("https://crux.supercraft.host", "<PROJECT_ID>", "<ENVIRONMENT_ID>", "<SERVER_TOKEN>")
##
## Usage (player mode - game client):
##   Crux.init_player("https://crux.supercraft.host", "<PROJECT_ID>", "<ENVIRONMENT_ID>", "<API_KEY>")
##
## PROJECT_ID and ENVIRONMENT_ID are UUIDs; API_KEY / SERVER_TOKEN are the secret
## strings issued on the Credentials page of your Crux dashboard.
##   var auth = await Crux.login_anonymous()
##   var doc  = await Crux.get_player_document(auth.player_id, "inventory")

extends Node

# ── Configuration ─────────────────────────────────────────────────────────────

var _base_url:      String = "https://crux.supercraft.host"
var _project_id:    String
var _env_id:        String
var _server_token:  String
var _api_key:       String
var _player_token:  String
var _refresh_token: String

var player_id: String

const MAX_RETRIES  := 3
const BASE_BACKOFF := 1.0

## Where the guest device id is kept. user:// is per-project and survives
## relaunches, which is the entire point - see login_anonymous().
const ANON_ID_PATH := "user://crux_anonymous_id.txt"


func init_server(base_url: String, project_id: String, environment_id: String, server_token: String) -> void:
	_base_url     = base_url.rstrip("/")
	_project_id   = project_id
	_env_id       = environment_id
	_server_token = server_token


func init_player(base_url: String, project_id: String, environment_id: String, api_key: String) -> void:
	_base_url   = base_url.rstrip("/")
	_project_id = project_id
	_env_id     = environment_id
	_api_key    = api_key


# ── Auth ──────────────────────────────────────────────────────────────────────

## Anonymous (guest) login. Returns {player_id, access_token, refresh_token, expires_in}.
##
## The device id is stored under user:// and reused automatically, so the same
## install returns to the same player - and therefore the same saves - after a
## relaunch. Pass an explicit anonymous_id only if your game already has its own
## stable device identifier.
func login_anonymous(anonymous_id: String = "") -> Dictionary:
	# This used to mint "anon-<time>-<rand>" and store it NOWHERE, despite a
	# comment telling the reader to persist it. Every relaunch therefore created
	# a brand new player and silently orphaned the previous save - the flagship
	# cloud-save flow failing at HTTP 200, with nothing in any log to show it.
	if anonymous_id == "":
		anonymous_id = _load_anonymous_id()

	var body := {}
	if anonymous_id != "":
		body["anonymous_id"] = anonymous_id

	var result := await _auth_request("/v1/auth/anonymous", body)

	# The server mints an id when we send none and returns it so we can keep it;
	# older servers return nothing, in which case we keep what we sent.
	var issued := str(result.get("anonymous_id", ""))
	if issued != "":
		_store_anonymous_id(issued)
	elif anonymous_id != "":
		_store_anonymous_id(anonymous_id)

	return result


## Forget the stored device id. The next login_anonymous() starts a fresh guest
## player - use this for a "sign out of guest account" or "reset progress"
## action, never on normal startup.
func clear_anonymous_id() -> void:
	if FileAccess.file_exists(ANON_ID_PATH):
		DirAccess.remove_absolute(ANON_ID_PATH)


func _load_anonymous_id() -> String:
	if not FileAccess.file_exists(ANON_ID_PATH):
		return ""
	var f := FileAccess.open(ANON_ID_PATH, FileAccess.READ)
	if f == null:
		return ""
	var stored := f.get_as_text().strip_edges()
	f.close()
	return stored


func _store_anonymous_id(value: String) -> void:
	var f := FileAccess.open(ANON_ID_PATH, FileAccess.WRITE)
	if f == null:
		push_warning("Crux: could not write %s - this guest player will not be recoverable after a relaunch." % ANON_ID_PATH)
		return
	f.store_string(value)
	f.close()


## Email + password login.
func login_email(email: String, password: String) -> Dictionary:
	return await _auth_request("/v1/auth/login", {"email": email, "password": password})


## Email + password registration.
func register_email(email: String, password: String) -> Dictionary:
	return await _auth_request("/v1/auth/register", {"email": email, "password": password})


## Refresh the player access token using the stored refresh token.
func refresh_token() -> Dictionary:
	if _refresh_token.is_empty():
		push_error("Crux: no refresh token - call a login method first")
		return {}
	return await _auth_request("/v1/auth/refresh", {"refresh_token": _refresh_token})


## Revoke the current session.
func logout() -> void:
	await _request("POST", "/v1/auth/logout", {}, "Bearer " + _player_token)
	_player_token  = ""
	_refresh_token = ""
	player_id      = ""


func _auth_request(path: String, body: Dictionary) -> Dictionary:
	var result = await _request("POST", path, body, "ApiKey " + _api_key)
	if result.has("access_token"):
		_player_token  = result.get("access_token",  "")
		_refresh_token = result.get("refresh_token", "")
		player_id      = result.get("player_id",     "")
	return result


# ── Player Documents ──────────────────────────────────────────────────────────

## Get a player document by key. Returns {key, value, version, updated_at}.
## value is a Godot Dictionary/Array (parsed from JSON).
func get_player_document(pid: String, key: String) -> Dictionary:
	return await _request("GET", _env("/players/%s/documents/%s" % [pid, key]), {}, _runtime_auth())


## Write a player document. Pass optional version for optimistic locking.
func set_player_document(pid: String, key: String, value: Variant, version: int = -1) -> Dictionary:
	var body := {"value": value}
	if version >= 0:
		body["version"] = version
	return await _request("PUT", _env("/players/%s/documents/%s" % [pid, key]), body, _runtime_auth())


## Apply document patch operations. operations is an Array of:
## {op="set"|"remove", path=["nested","field"], value=..., create_missing=true}
func patch_player_document(pid: String, key: String, operations: Array, version: int = -1) -> Dictionary:
	var body := {"operations": operations}
	if version >= 0:
		body["version"] = version
	return await _request("PATCH", _env("/players/%s/documents/%s" % [pid, key]), body, _runtime_auth())


## Delete a player document.
func delete_player_document(pid: String, key: String) -> void:
	await _request("DELETE", _env("/players/%s/documents/%s" % [pid, key]), {}, _runtime_auth())


## Fetch multiple document keys in a single call. Returns Array of documents.
func batch_get_player_documents(pid: String, keys: Array) -> Array:
	return await _request_array("POST", _env("/players/%s/documents/batch-read" % pid), {"keys": keys}, _runtime_auth())


## Write multiple documents atomically.
## writes: Array of {key, value} or {key, value, version} Dictionaries.
func batch_write_player_documents(pid: String, writes: Array) -> void:
	await _request("POST", _env("/players/%s/documents/batch-write" % pid), {"items": writes}, _runtime_auth())


# ── Leaderboards ──────────────────────────────────────────────────────────────

## Submit a score. metadata is an optional Dictionary.
func submit_score(leaderboard_id: String, pid: String, score: float, metadata: Dictionary = {}) -> void:
	await _request("POST", _env("/leaderboards/%s/scores" % leaderboard_id),
		{"player_id": pid, "score": score, "metadata": metadata}, _runtime_auth())


## Get the top N entries. Returns Array of {rank, player_id, score, metadata}.
func get_top(leaderboard_id: String, limit: int = 10) -> Array:
	return await _request_array("GET", _env("/leaderboards/%s/top?limit=%d" % [leaderboard_id, limit]), {}, _runtime_auth())


## Get a player's rank and score. Returns {rank, player_id, score} or empty dict if not ranked.
func get_player_standing(leaderboard_id: String, pid: String) -> Dictionary:
	return await _request("GET", _env("/leaderboards/%s/players/%s" % [leaderboard_id, pid]), {}, _runtime_auth())


## Get entries surrounding a player (radius entries above + below). Returns Array.
func get_around_player(leaderboard_id: String, pid: String, radius: int = 3) -> Array:
	return await _request_array("GET",
		_env("/leaderboards/%s/players/%s/around?radius=%d" % [leaderboard_id, pid, radius]), {}, _runtime_auth())


# ── Economy ───────────────────────────────────────────────────────────────────

## Get a player's balances and inventory.
## Returns {player_id, balances: [{currency_id, currency_name, amount}], inventory: [...]}
func get_player_economy(pid: String) -> Dictionary:
	return await _request("GET", _env("/players/%s/economy" % pid), {}, _runtime_auth())


## Atomically adjust balances and/or inventory.
## balance_adjustments: [{currency_id, amount}]
## inventory_adjustments: [{item_id, quantity}]
func adjust_economy(pid: String, balance_adjustments: Array = [], inventory_adjustments: Array = []) -> Dictionary:
	return await _request("POST", _env("/players/%s/economy/adjust" % pid), {
		"balance_adjustments":   balance_adjustments,
		"inventory_adjustments": inventory_adjustments,
	}, _runtime_auth())


# ── Matchmaking ───────────────────────────────────────────────────────────────

## Join a matchmaking queue. Returns the ticket dictionary.
func join_matchmaking(pid: String, game_mode: String, region: String = "global") -> Dictionary:
	return await _request("POST", _env("/matchmaking/join"),
		{"player_id": pid, "game_mode": game_mode, "region": region}, _runtime_auth())


## Poll for match result. Returns {status, match?}.
## status is one of: "waiting", "matched".
func get_matchmaking_status() -> Dictionary:
	return await _request("GET", _env("/matchmaking/status"), {}, _runtime_auth())


## Leave the matchmaking queue.
func leave_matchmaking(pid: String) -> void:
	await _request("POST", _env("/matchmaking/leave"), {"player_id": pid}, _runtime_auth())


# ── Server Registry ───────────────────────────────────────────────────────────

## Register this server instance. reg: Dictionary with server_id, name, region, map_name,
## game_mode, player_count, max_players, address, port, version.
func register_server(reg: Dictionary) -> Dictionary:
	return await _request("POST", _env("/servers"), reg, _server_auth())


## Send a heartbeat to keep this server in the registry.
func heartbeat(server_id: String) -> void:
	await _request("POST", _env("/servers/heartbeat"), {"server_id": server_id}, _server_auth())


## Deregister on clean shutdown.
func deregister_server(server_id: String) -> void:
	await _request("POST", _env("/servers/deregister"), {"server_id": server_id}, _server_auth())


## Browse available servers. Filter by region, map_name, game_mode (all optional).
## Returns Array of server Dictionaries.
func list_servers(region: String = "", map_name: String = "", game_mode: String = "") -> Array:
	var qs := _build_query({"region": region, "map_name": map_name, "game_mode": game_mode})
	return await _request_array("GET", _env("/browser" + qs), {}, _runtime_auth())


# ── Config ────────────────────────────────────────────────────────────────────

## Download the active config bundle as a PackedByteArray.
func download_active_config_bundle() -> PackedByteArray:
	return await _request_bytes(_env("/configs/active/bundle"), _runtime_auth())


# ── HTTP internals ────────────────────────────────────────────────────────────

func _env(suffix: String) -> String:
	return "/v1/projects/%s/environments/%s%s" % [_project_id, _env_id, suffix]


func _runtime_auth() -> String:
	if not _server_token.is_empty(): return "ServerToken " + _server_token
	if not _player_token.is_empty(): return "Bearer "      + _player_token
	push_error("Crux: no server token or player token - call init_server() or a login method first")
	return ""


func _server_auth() -> String:
	if not _server_token.is_empty(): return "ServerToken " + _server_token
	push_error("Crux: server token required - call init_server()")
	return ""


func _build_query(params: Dictionary) -> String:
	var parts := PackedStringArray()
	for k in params:
		var v: String = params[k]
		if not v.is_empty():
			parts.append("%s=%s" % [k, v.uri_encode()])
	if parts.is_empty():
		return ""
	return "?" + "&".join(parts)


# Core HTTP + retry. Returns the parsed JSON body as a Variant - a Dictionary
# for object responses, an Array for collection responses (leaderboard
# standings, server browser, batch reads), or {} for an empty body / transport
# error / HTTP >= 400 (after logging). Callers pick the typed wrapper below.
func _send(method: String, path: String, body: Dictionary, auth_header: String) -> Variant:
	var http_method := _method_const(method)
	var url         := _base_url + path
	var headers     := PackedStringArray([
		"Authorization: " + auth_header,
		"Content-Type: application/json",
	])
	var body_bytes := PackedByteArray()
	if not body.is_empty() or method in ["POST", "PUT", "PATCH"]:
		body_bytes = JSON.stringify(body).to_utf8_buffer()

	var backoff := BASE_BACKOFF
	for attempt in range(MAX_RETRIES + 1):
		var http := HTTPRequest.new()
		add_child(http)
		var err := http.request_raw(url, headers, http_method, body_bytes)
		if err != OK:
			http.queue_free()
			push_error("Crux: HTTPRequest error %d on %s %s" % [err, method, path])
			return {}

		var response = await http.request_completed
		http.queue_free()

		# response: [result, response_code, headers, body: PackedByteArray]
		var response_code: int           = response[1]
		var body_raw:      PackedByteArray = response[3]
		var body_str:      String         = body_raw.get_string_from_utf8()

		if response_code in [429, 503]:
			if attempt < MAX_RETRIES:
				await get_tree().create_timer(backoff).timeout
				backoff *= 2.0
				continue

		if response_code >= 400:
			var parsed = _parse_json(body_str)
			var msg    = parsed.get("message", body_str)
			push_error("Crux: HTTP %d on %s %s - %s" % [response_code, method, path, msg])
			return {}

		return _parse_json_variant(body_str)

	push_error("Crux: max retries exceeded for %s %s" % [method, path])
	return {}


## Request whose response body is a JSON object. Returns {} on error or when the
## endpoint returns a non-object body.
func _request(method: String, path: String, body: Dictionary, auth_header: String) -> Dictionary:
	var result: Variant = await _send(method, path, body, auth_header)
	return result if result is Dictionary else {}


## Request whose response body is a JSON array (leaderboard standings, server
## browser results, batch document reads). Returns [] on error or when the
## endpoint returns a non-array body.
func _request_array(method: String, path: String, body: Dictionary, auth_header: String) -> Array:
	var result: Variant = await _send(method, path, body, auth_header)
	return result if result is Array else []


func _request_bytes(path: String, auth_header: String) -> PackedByteArray:
	var headers := PackedStringArray(["Authorization: " + auth_header])
	var http    := HTTPRequest.new()
	add_child(http)
	var err := http.request_raw(_base_url + path, headers, HTTPClient.METHOD_GET, PackedByteArray())
	if err != OK:
		http.queue_free()
		return PackedByteArray()
	var response = await http.request_completed
	http.queue_free()
	if response[1] >= 400:
		push_error("Crux: HTTP %d downloading bundle" % response[1])
		return PackedByteArray()
	return response[3]


func _parse_json(text: String) -> Dictionary:
	if text.is_empty():
		return {}
	var parsed = JSON.parse_string(text)
	if parsed is Dictionary:
		return parsed
	return {}


## Parse a JSON body into whatever it represents (Dictionary or Array). Returns
## {} for an empty body or a parse failure so callers always get a valid value.
func _parse_json_variant(text: String) -> Variant:
	if text.is_empty():
		return {}
	var parsed = JSON.parse_string(text)
	if parsed == null:
		return {}
	return parsed


func _method_const(method: String) -> int:
	match method:
		"GET":    return HTTPClient.METHOD_GET
		"POST":   return HTTPClient.METHOD_POST
		"PUT":    return HTTPClient.METHOD_PUT
		"DELETE": return HTTPClient.METHOD_DELETE
		"PATCH":  return HTTPClient.METHOD_PATCH
		_:        return HTTPClient.METHOD_GET
