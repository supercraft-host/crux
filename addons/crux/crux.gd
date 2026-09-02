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

# Secret API key used only by an editor/CI deployment workflow. Never put this
# value in a shipped client; player builds should use init_player() instead.
var _runtime_control_key: String
var _runtime_session_token: String
var _runtime_session_id: String
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


## Configure the editor/CI Runtime deployment surface. The key must be a
## SECRET API key and must stay outside a shipped game binary.
func init_runtime_control(base_url: String, project_id: String, environment_id: String, secret_api_key: String) -> void:
	_base_url           = base_url.rstrip("/")
	_project_id         = project_id
	_env_id             = environment_id
	_runtime_control_key = secret_api_key


## Configure a running authoritative server with its session-scoped Runtime
## credential. This token is safe to use only for the matching session context
## and trusted result endpoints; it is not a project API key.
func init_runtime_session(base_url: String, project_id: String, environment_id: String, session_id: String, session_token: String) -> void:
	_base_url              = base_url.rstrip("/")
	_project_id            = project_id
	_env_id                = environment_id
	_runtime_session_id    = session_id
	_runtime_session_token = session_token


## Initialize the Runtime session API from the environment variables injected by
## the isolated Crux Runtime Agent: CRUX_PROJECT_ID, CRUX_ENVIRONMENT_ID,
## CRUX_SESSION_ID, and CRUX_RUNTIME_SESSION_TOKEN.
func init_runtime_session_from_environment(base_url: String = "https://crux.supercraft.host") -> bool:
	var project := OS.get_environment("CRUX_PROJECT_ID")
	var environment := OS.get_environment("CRUX_ENVIRONMENT_ID")
	var session := OS.get_environment("CRUX_SESSION_ID")
	var token := OS.get_environment("CRUX_RUNTIME_SESSION_TOKEN")
	if project.is_empty() or environment.is_empty() or session.is_empty() or token.is_empty():
		push_error("Crux: Runtime session environment is incomplete")
		return false
	init_runtime_session(base_url, project, environment, session, token)
	return true


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


# ── Project Documents ─────────────────────────────────────────────────────────
# Environment-wide JSON shared by every player. Reads are open to any runtime
# caller; WRITES are server-authoritative, so a player token gets 401 - use
# init_server(), or an api key.
#
# RESERVED NAMESPACE: a key beginning with "server:" is readable and writable
# only with a server token; a player token gets 403. Put loot tables, anti-cheat
# thresholds and anything else players must not read behind it.

## Metadata for every project document: Array of {key, version, created_at,
## updated_at}. Values are NOT included - fetch keys individually.
func list_project_document_keys() -> Array:
	return await _request_array("GET", _env("/documents"), {}, _runtime_auth())


## Read one project document. Returns {key, value, version, created_at, updated_at}.
func get_project_document(key: String) -> Dictionary:
	return await _request("GET", _env("/documents/%s" % key), {}, _runtime_auth())


## Write one project document. Pass version for optimistic locking; a mismatch
## answers 409.
func set_project_document(key: String, value: Variant, version: int = -1) -> Dictionary:
	var body := {"value": value}
	if version >= 0:
		body["version"] = version
	return await _request("PUT", _env("/documents/%s" % key), body, _server_or_api_auth())


## Delete a project document.
func delete_project_document(key: String) -> void:
	await _request("DELETE", _env("/documents/%s" % key), {}, _server_or_api_auth())


## Read several project documents at once. Keys that do not exist are simply
## absent from the result.
func batch_get_project_documents(keys: Array) -> Array:
	return await _request_array("POST", _env("/documents/batch-read"), {"keys": keys}, _runtime_auth())


## Write several project documents at once.
## documents: Array of {key, value} or {key, value, version} Dictionaries.
func batch_write_project_documents(documents: Array) -> Array:
	return await _request_array("POST", _env("/documents/batch-write"), {"documents": documents}, _server_or_api_auth())


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


# ── Stats & Achievements ──────────────────────────────────────────────────────
# Reads are open to any runtime caller - a player seeing their own progress is
# the point. WRITES need a server token (init_server), for the same reason
# economy writes do: a guest token is free to anyone who downloads the game, so
# a client-writable stat is a client-writable achievement and reward.

## All of a player's stats: Array of {player_id, key, value, created_at, updated_at}.
func list_player_stats(pid: String) -> Array:
	return await _request_array("GET", _env("/players/%s/stats" % pid), {}, _runtime_auth())


## One stat. A stat never written reads as value 0 rather than erroring -
## "no kills yet" and "0 kills" are the same fact.
func get_player_stat(pid: String, key: String) -> Dictionary:
	return await _request("GET", _env("/players/%s/stats/%s" % [pid, key]), {}, _runtime_auth())


## Set a stat outright. Returns {stat, unlocked}, where unlocked lists ONLY the
## achievements this write earned - so you can grant rewards from it without
## double-awarding on a retry.
func set_player_stat(pid: String, key: String, value: int) -> Dictionary:
	return await _request("PUT", _env("/players/%s/stats/%s" % [pid, key]),
		{"value": value}, _server_auth())


## Add to a stat. delta may be negative. Same return shape as set_player_stat().
func increment_player_stat(pid: String, key: String, delta: int) -> Dictionary:
	return await _request("PUT", _env("/players/%s/stats/%s" % [pid, key]),
		{"value": delta, "increment": true}, _server_auth())


## The achievement catalogue, including ones nobody has earned.
func list_achievements() -> Array:
	return await _request_array("GET", _env("/achievements"), {}, _runtime_auth())


## The whole catalogue annotated for one player: unlocked_at is null on the ones
## they have not earned, so a UI can show locked and unlocked together.
func list_player_achievements(pid: String) -> Array:
	return await _request_array("GET", _env("/players/%s/achievements" % pid), {}, _runtime_auth())


## Award an achievement outright, for the ones no counter can express.
## Returns {unlocked, achievement}; unlocked is false when the player already
## had it, so a retry cannot pay a reward twice.
func unlock_achievement(pid: String, key: String) -> Dictionary:
	return await _request("POST", _env("/players/%s/achievements/%s/unlock" % [pid, key]), {}, _server_auth())


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


# ── Social ────────────────────────────────────────────────────────────────────
# NOTE: these responses mirror stored rows and use PascalCase keys, unlike the
# rest of the API. The server sends JSON null rather than [] when a list is
# empty; _request_array turns that into [], so you can always iterate.
#
# PLAYER TOKEN ONLY. These handlers take the player from the TOKEN, and only a
# player token carries one - init_server() + a server token gets 401 here, unlike
# the document routes, which do read the player id from the URL.
#
# So `pid` below only fills the URL path; it is NOT the identity the server acts
# on. Passing another player's id does not touch their friends, it silently
# operates on your own.

## List this player's friendships. Array of {FriendID, Status, CreatedAt, UpdatedAt},
## where Status is "pending" until the recipient accepts, then "accepted".
func list_friends(pid: String) -> Array:
	return await _request_array("GET", _env("/players/%s/social/friends" % pid), {}, _runtime_auth())


## List friend requests sent TO this player. Array of {PlayerID, CreatedAt},
## where PlayerID is the sender.
func list_pending_friend_requests(pid: String) -> Array:
	return await _request_array("GET", _env("/players/%s/social/friends/requests" % pid), {}, _runtime_auth())


## Send a friend request. Rejected with 403 if the target has blocked this player.
func send_friend_request(pid: String, friend_id: String) -> void:
	await _request("POST", _env("/players/%s/social/friends/request" % pid),
		{"friend_id": friend_id}, _runtime_auth())


## Accept a request. friend_id is the player who SENT it.
func accept_friend_request(pid: String, friend_id: String) -> void:
	await _request("POST", _env("/players/%s/social/friends/accept" % pid),
		{"friend_id": friend_id}, _runtime_auth())


## Remove a friend. Also withdraws a still-pending request, and succeeds even
## when there was no friendship.
func remove_friend(pid: String, friend_id: String) -> void:
	await _request("DELETE", _env("/players/%s/social/friends/%s" % [pid, friend_id]), {}, _runtime_auth())


## Block a player. Idempotent. A blocked player cannot send this player requests.
func block_player(pid: String, target_id: String) -> void:
	await _request("POST", _env("/players/%s/social/blocks" % pid),
		{"target_id": target_id}, _runtime_auth())


## Unblock a player.
func unblock_player(pid: String, target_id: String) -> void:
	await _request("DELETE", _env("/players/%s/social/blocks/%s" % [pid, target_id]), {}, _runtime_auth())


# ── Matchmaking ───────────────────────────────────────────────────────────────

## Join a matchmaking queue. The API answers 202 with no body, so there is
## nothing to return - poll get_matchmaking_status() for the ticket and, later,
## the match. Matching is by exact (game_mode, region) and currently forms pairs.
## region is compared as an opaque string, so two players only meet if they pass
## the same value: "global" is a convention here, not a wildcard.
##
## PLAYER TOKEN ONLY, and pid is ignored: the server queues whoever the token
## identifies. A server token gets 401.
func join_matchmaking(pid: String, game_mode: String, region: String = "global", runtime_build_id: String = "") -> void:
	var body := {"player_id": pid, "game_mode": game_mode, "region": region}
	if not runtime_build_id.is_empty():
		body["runtime_build_id"] = runtime_build_id
	await _request("POST", _env("/matchmaking/join"), body, _runtime_auth())


## Poll queue / match status. Returns {status, queue?, match?}.
## status is one of: "none" (not queued, not matched), "queued", "matched".
## queue is present only when queued; match only when matched.
##
## match.server is the server the match was placed on: the emptiest one
## heartbeating in the match's region AND game_mode when it formed. Only live
## servers are eligible, so a crashed one is never chosen. It is ABSENT when
## nothing suitable was live - the match is still valid, so fall back to
## list_servers().
func get_matchmaking_status() -> Dictionary:
	return await _request("GET", _env("/matchmaking/status"), {}, _runtime_auth())


## Report that a match has begun, moving it from "forming" to "active".
##
## SERVER TOKEN ONLY (init_server), and keyed on the match rather than a player:
## the game server is the only party that knows a session actually started.
## Idempotent - a repeat call is a 404 rather than reopening a finished match.
##
## Call it. A match nobody starts is swept to "expired" after five minutes, and
## until that sweep existed an unreported match pinned its players forever.
func start_match(match_id: String) -> void:
	await _request("POST", _env("/matchmaking/matches/%s/start" % match_id), {}, _server_auth())


## Report that a match has ended, releasing its players to queue again. Accepts
## a match still in "forming" as well as one that is "active".
func complete_match(match_id: String) -> void:
	await _request("POST", _env("/matchmaking/matches/%s/complete" % match_id), {}, _server_auth())


## Leave the matchmaking queue.
func leave_matchmaking(pid: String) -> void:
	await _request("POST", _env("/matchmaking/leave"), {"player_id": pid}, _runtime_auth())


# ── Crux Runtime ─────────────────────────────────────────────────────────────

## Issue a short-lived join ticket for a READY Runtime session.
##
## A player token may omit player_id and can only receive its own ticket. A
## server token must pass player_id. The returned ticket is safe to give to a
## client; the per-session validation secret is injected into the dedicated
## server process by Crux and is never returned here.
func issue_runtime_join_ticket(session_id: String, pid: String = "") -> Dictionary:
	var body := {}
	if not pid.is_empty():
		body["player_id"] = pid
	return await _request("POST", _env("/runtime/sessions/%s/join" % session_id), body, _runtime_auth())


## Issue a ticket from an editor/CI canary using the secret control key. This is
## intentionally separate from issue_runtime_join_ticket(): a control key is
## never accepted by a shipped client and this helper makes that boundary
## visible to callers.
func issue_runtime_join_ticket_control(session_id: String, pid: String) -> Dictionary:
	if pid.is_empty():
		push_error("Crux: a control-plane join ticket needs player_id")
		return {}
	return await _request("POST", _env("/runtime/sessions/%s/join" % session_id), {
		"player_id": pid,
	}, _runtime_control_auth())


## Create a Runtime build record. Editor/CI control token only.
func create_runtime_build(version: String, entrypoint: String, manifest: Dictionary = {}) -> Dictionary:
	return await _request("POST", _env("/runtime/builds"), {
		"version": version, "entrypoint": entrypoint, "manifest": manifest,
	}, _runtime_control_auth())


## Upload a raw ZIP Godot dedicated-server export. Crux packages and runs it;
## developers do not need to create a Dockerfile or publish an image.
func upload_runtime_build_artifact(build_id: String, artifact: PackedByteArray) -> Dictionary:
	return await _request_raw("PUT", _env("/runtime/builds/%s/artifact" % build_id), artifact, "application/zip", _runtime_control_auth())


## Start an ephemeral Runtime session. Editor/CI control token only.
func create_runtime_session(build_id: String = "", region: String = "eu", max_players: int = 16, cpu_millis: int = 1000, memory_bytes: int = 1073741824) -> Dictionary:
	return await _request("POST", _env("/runtime/sessions"), {
		"build_id": build_id, "region": region, "max_players": max_players,
		"cpu_millis": cpu_millis, "memory_bytes": memory_bytes,
	}, _runtime_control_auth())


func get_runtime_admission() -> Dictionary:
	return await _request("GET", _env("/runtime/admission"), {}, _runtime_control_auth())


## Read project-level Runtime validation evidence for the dashboard or a pilot
## script. This is a control-plane endpoint and is intentionally not available
## to a shipped player or RuntimeSession credential.
func get_runtime_validation_summary() -> Dictionary:
	return await _request("GET", "/v1/projects/%s/runtime/validation" % _project_id, {}, _runtime_control_auth())


func get_runtime_session(session_id: String) -> Dictionary:
	return await _request("GET", _env("/runtime/sessions/%s" % session_id), {}, _runtime_control_auth())


## Read the build currently active for sessions that omit an explicit build id.
func get_runtime_deployment() -> Dictionary:
	return await _request("GET", _env("/runtime/deployment"), {}, _runtime_control_auth())


## Make a ready immutable build the active deployment. Existing sessions keep
## their build; new sessions use this build when build_id is omitted.
func activate_runtime_build(build_id: String) -> Dictionary:
	return await _request("POST", _env("/runtime/deployment"), {"build_id": build_id}, _runtime_control_auth())


## Swap the active deployment with its previous ready build.
func rollback_runtime_deployment() -> Dictionary:
	return await _request("POST", _env("/runtime/deployment/rollback"), {}, _runtime_control_auth())


func get_runtime_session_logs(session_id: String, limit: int = 500) -> Array:
	return await _request_array("GET", _env("/runtime/sessions/%s/logs?limit=%d" % [session_id, limit]), {}, _runtime_control_auth())


func stop_runtime_session(session_id: String) -> Dictionary:
	return await _request("DELETE", _env("/runtime/sessions/%s" % session_id), {}, _runtime_control_auth())


## Read the narrow session context visible to the authoritative Runtime process.
func get_runtime_session_context(session_id: String = "") -> Dictionary:
	var target := session_id if not session_id.is_empty() else _runtime_session_id
	return await _request("GET", _env("/runtime/sessions/%s/context" % target), {}, _runtime_session_auth())


## Record application-level liveness from the authoritative Runtime process.
## When the build manifest sets idle_timeout_seconds, call this periodically
## (comfortably more often than that limit) while the game is serving players.
func heartbeat_runtime_session() -> Dictionary:
	return await _request("POST", _env("/runtime/sessions/%s/heartbeat" % _runtime_session_id), {}, _runtime_session_auth())


## Persist a trusted result for this Runtime session. Set complete=true when the
## match has ended; Crux then completes the optional Runtime-backed match and
## requests the ephemeral session to stop.
func submit_runtime_session_result(result: Dictionary, complete: bool = false) -> Dictionary:
	return await _request("POST", _env("/runtime/sessions/%s/result" % _runtime_session_id), {
		"result": result,
		"complete": complete,
	}, _runtime_session_auth())


## Complete the normal v0 deployment path from a raw ZIP export. The returned
## dictionary contains build, session, and (when player_id is supplied) a
## short-lived join ticket. This is editor/CI functionality only; the secret
## control key is never persisted by the SDK.
func deploy_runtime_zip(artifact_path: String, version: String, entrypoint: String, manifest: Dictionary = {}, player_id: String = "", timeout_seconds: int = 300, poll_seconds: float = 2.0) -> Dictionary:
	if not FileAccess.file_exists(artifact_path):
		push_error("Crux: Runtime artifact does not exist: " + artifact_path)
		return {}
	var artifact := FileAccess.get_file_as_bytes(artifact_path)
	if artifact.is_empty():
		push_error("Crux: Runtime artifact is empty: " + artifact_path)
		return {}
	var build := await create_runtime_build(version, entrypoint, manifest)
	if build.is_empty() or not build.has("id"):
		return {}
	var uploaded := await upload_runtime_build_artifact(str(build["id"]), artifact)
	if uploaded.is_empty() or not uploaded.has("id"):
		return {}
	var deployment := await activate_runtime_build(str(uploaded["id"]))
	if deployment.is_empty() or not deployment.has("active_build_id"):
		return {"build": uploaded, "deployment": deployment}
	var session := await create_runtime_session(str(uploaded["id"]))
	if session.is_empty() or not session.has("id"):
		return {}
	var session_id := str(session["id"])
	var deadline := Time.get_ticks_msec() + maxi(1, timeout_seconds) * 1000
	while Time.get_ticks_msec() < deadline:
		var current := await get_runtime_session(session_id)
		var state := str(current.get("state", ""))
		if state == "ready":
			var result := {"build": uploaded, "deployment": deployment, "session": current}
			if not player_id.is_empty():
				result["join"] = await issue_runtime_join_ticket_control(session_id, player_id)
			return result
		if state == "failed" or state == "stopped":
			push_error("Crux: Runtime session ended before readiness: " + state)
			return {"build": uploaded, "deployment": deployment, "session": current}
		await get_tree().create_timer(maxf(0.25, poll_seconds)).timeout
	push_error("Crux: Runtime session did not become ready before the timeout")
	return {"build": uploaded, "deployment": deployment, "session": await get_runtime_session(session_id)}


# ── Server Registry ───────────────────────────────────────────────────────────

## Register this server instance, or update it by re-sending the same server_id.
##
## reg keys the API accepts: server_id (required), name, region, ip_address,
## port, map_name, game_mode, player_count, server_version.
##
## The fields are ip_address and server_version - NOT "address" and "version",
## which earlier versions of this comment advertised. Anything else in reg is
## ignored by the server, so a registration using the old names went in with no
## address at all, which is fatal for a server browser: the address is the one
## thing a client needs in order to connect. There is no max_players field.
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


## For routes the API gates on "server token OR api key" - project-document
## writes. Using _server_auth() there would refuse a perfectly valid api-key
## caller locally, before the request was ever sent.
func _server_or_api_auth() -> String:
	if not _server_token.is_empty(): return "ServerToken " + _server_token
	if not _api_key.is_empty():      return "ApiKey "      + _api_key
	push_error("Crux: writing project documents needs a server token or an api key; a player token is not accepted")
	return ""


func _runtime_control_auth() -> String:
	if _runtime_control_key.is_empty():
		push_error("Crux: Runtime deployment needs a secret API key - call init_runtime_control() from editor/CI only")
		return ""
	return "ApiKey " + _runtime_control_key


func _runtime_session_auth() -> String:
	if _runtime_session_token.is_empty() or _runtime_session_id.is_empty():
		push_error("Crux: Runtime session API needs init_runtime_session() or init_runtime_session_from_environment()")
		return ""
	return "RuntimeSession " + _runtime_session_token


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
			# The API answers {"error":{"code","message"}}. Reading a TOP-LEVEL
			# "message" found nothing, so the server's careful, field-naming
			# explanation was replaced by the raw JSON envelope in the console.
			var parsed = _parse_json(body_str)
			var err_obj: Dictionary = parsed.get("error", {})
			var msg: String = body_str
			if err_obj is Dictionary and err_obj.has("message"):
				msg = str(err_obj["message"])
			elif parsed.has("message"):
				msg = str(parsed["message"])
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


func _request_raw(method: String, path: String, body: PackedByteArray, content_type: String, auth_header: String) -> Dictionary:
	var headers := PackedStringArray([
		"Authorization: " + auth_header,
		"Content-Type: " + content_type,
	])
	var http := HTTPRequest.new()
	add_child(http)
	var err := http.request_raw(_base_url + path, headers, _method_const(method), body)
	if err != OK:
		http.queue_free()
		push_error("Crux: HTTPRequest error %d on %s %s" % [err, method, path])
		return {}
	var response = await http.request_completed
	http.queue_free()
	var response_code: int = response[1]
	var body_str: String = response[3].get_string_from_utf8()
	if response_code >= 400:
		var parsed := _parse_json(body_str)
		var err_obj: Dictionary = parsed.get("error", {})
		var msg: String = body_str
		if err_obj.has("message"):
			msg = str(err_obj["message"])
		push_error("Crux: HTTP %d on %s %s - %s" % [response_code, method, path, msg])
		return {}
	return _parse_json(body_str)


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
