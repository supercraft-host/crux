extends Node

const DEFAULT_PORT := 9080
const MAX_PLAYERS := 4
const MATCH_TIME_LIMIT := 300.0
const HEARTBEAT_INTERVAL := 30.0
const BOT_SPAWN_DELAY := 5.0

var _crux_url: String = "https://crux.supercraft.host"
var _project_id: String = ""
var _env_id: String = ""
var _server_token: String = ""
var _server_id: String = ""
var _server_name: String = ""
var _region: String = "eu-west"
var _port: int = DEFAULT_PORT
var _bind_address: String = "*"
var _public_address: String = ""
var _match_id: String = ""
var _expected_join_token: String = ""
var _allow_insecure_dev_auth: bool = false

var _simulation: GameSimulation
var _players: Dictionary = {} # network peer ID -> trusted player record
var _bot_timer: float = BOT_SPAWN_DELAY
var _heartbeat_timer: float = 0.0
var _match_started: bool = false
var _ending_match: bool = false
var _shutting_down: bool = false
var _server_registered: bool = false


func _ready() -> void:
	OS.low_processor_usage_mode = true
	_load_config()
	if not _validate_config():
		get_tree().quit(2)
		return
	CruxSession.initialize_server_mode(_crux_url, _project_id, _env_id, _server_token)
	await LiveConfig.refresh()
	_initialize_simulation()
	if not _start_listening():
		get_tree().quit(3)
		return
	var registration := await _register_server()
	if registration.has("error"):
		push_error("Relay Zero Server: registry registration failed: %s" % registration)
		NetworkSession.stop()
		get_tree().quit(4)
		return
	print("Relay Zero Server: Ready on %s:%d as %s" % [_bind_address, _port, _server_id])


func _process(delta: float) -> void:
	if _shutting_down:
		return
	if _match_started and not _ending_match:
		_bot_timer -= delta
		if _bot_timer <= 0.0:
			_bot_timer = BOT_SPAWN_DELAY
			_spawn_bots_as_needed()
	if _server_registered:
		_heartbeat_timer += delta
		if _heartbeat_timer >= HEARTBEAT_INTERVAL:
			_heartbeat_timer = 0.0
			_send_heartbeat()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_CRASH:
		_shutdown.call_deferred()


func _load_config() -> void:
	var config := ConfigFile.new()
	if config.load("res://server/server_config.cfg") == OK:
		_crux_url = str(config.get_value("crux", "url", _crux_url))
		_project_id = str(config.get_value("crux", "project_id", ""))
		_env_id = str(config.get_value("crux", "env_id", ""))
		_server_token = str(config.get_value("crux", "server_token", ""))
		_server_id = str(config.get_value("server", "server_id", ""))
		_server_name = str(config.get_value("server", "name", "Relay Zero"))
		_region = str(config.get_value("server", "region", _region))
		_port = int(config.get_value("server", "port", DEFAULT_PORT))
		_public_address = str(config.get_value("server", "public_address", ""))

	_crux_url = _env_override("CRUX_URL", _crux_url)
	_project_id = _env_override("CRUX_PROJECT_ID", _project_id)
	_env_id = _env_override("CRUX_ENVIRONMENT_ID", _env_id)
	_server_token = _env_override("CRUX_SERVER_TOKEN", _server_token)
	_server_id = _env_override("SERVER_ID", _server_id)
	_server_name = _env_override("SERVER_NAME", _server_name)
	_region = _env_override("REGION", _region)
	_bind_address = _env_override("BIND_ADDRESS", _bind_address)
	_public_address = _env_override("PUBLIC_ADDRESS", _public_address)
	_match_id = OS.get_environment("MATCH_ID")
	_expected_join_token = OS.get_environment("EXPECTED_JOIN_TOKEN")
	_allow_insecure_dev_auth = OS.get_environment("RELAY_ALLOW_INSECURE_DEV_AUTH") == "1"
	var port_value := OS.get_environment("PORT")
	if not port_value.is_empty():
		_port = int(port_value)
	_parse_command_line()

	if _is_placeholder(_server_id):
		_server_id = _generate_server_id()
	if _server_name.is_empty() or _is_placeholder(_server_name):
		_server_name = "relay-%s-%d" % [_region, _port]
	if _public_address.is_empty() and _allow_insecure_dev_auth:
		_public_address = "127.0.0.1"


func _parse_command_line() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--port="):
			_port = int(argument.trim_prefix("--port="))
		elif argument.begins_with("--region="):
			_region = argument.trim_prefix("--region=")
		elif argument.begins_with("--public-address="):
			_public_address = argument.trim_prefix("--public-address=")


func _env_override(key: String, current: String) -> String:
	var value := OS.get_environment(key)
	return value if not value.is_empty() else current


func _validate_config() -> bool:
	var errors: Array[String] = []
	if _is_placeholder(_project_id):
		errors.append("CRUX_PROJECT_ID")
	if _is_placeholder(_env_id):
		errors.append("CRUX_ENVIRONMENT_ID")
	if _is_placeholder(_server_token):
		errors.append("CRUX_SERVER_TOKEN")
	if _public_address.is_empty():
		errors.append("PUBLIC_ADDRESS")
	if not _allow_insecure_dev_auth:
		if _match_id.is_empty():
			errors.append("MATCH_ID")
		if _expected_join_token.is_empty():
			errors.append("EXPECTED_JOIN_TOKEN")
	if not errors.is_empty():
		push_error("Relay Zero Server: missing production configuration: %s" % ", ".join(errors))
		return false
	return true


func _is_placeholder(value: String) -> bool:
	return value.is_empty() or value.begins_with("your-") or value.begins_with("<") or value == "placeholder-token"


func _initialize_simulation() -> void:
	_simulation = GameSimulation.new()
	_simulation.initialize({
		"time_limit": MATCH_TIME_LIMIT,
		"max_cores": 3,
		"modifier_id": LiveConfig.get_daily_event().get("id", ""),
		"config_version": LiveConfig.get_version(),
	})


func _start_listening() -> bool:
	var err := NetworkSession.start_server(_port, MAX_PLAYERS, _bind_address)
	if err != OK:
		push_error("Relay Zero Server: failed to listen (%d)" % err)
		return false
	NetworkSession.player_joined.connect(_on_transport_peer_joined)
	NetworkSession.player_left.connect(_on_player_left)
	NetworkSession.message_received.connect(_on_message_received)
	NetworkSession.server_tick.connect(_on_server_tick)
	NetworkSession.snapshot_due.connect(_on_snapshot_due)
	return true


func _register_server() -> Dictionary:
	var reg := {
		"server_id": _server_id,
		"name": _server_name,
		"region": _region,
		"map_name": "facility_a",
		"game_mode": "quick",
		"player_count": 0,
		"max_players": MAX_PLAYERS,
		"address": _public_address,
		"port": _port,
		"version": "0.1.0",
	}
	var result := await CruxSession.register_server(reg)
	_server_registered = not result.has("error")
	return result


func _on_transport_peer_joined(peer_id: int, player_data: Dictionary) -> void:
	print("Server: transport peer %d connected in slot %d; awaiting authentication" % [peer_id, player_data.get("slot", -1)])


func _on_player_left(peer_id: int, reason: String) -> void:
	print("Server: Player %d disconnected: %s" % [peer_id, reason])
	if _players.has(peer_id):
		_players.erase(peer_id)
		_simulation.remove_player(peer_id)


func _on_message_received(sender_id: int, method: String, payload: Variant) -> void:
	match method:
		"join":
			_authenticate_and_join(sender_id, payload)
		"input":
			_handle_input(sender_id, payload)


func _authenticate_and_join(peer_id: int, payload: Variant) -> void:
	if not (payload is Dictionary):
		_reject_peer(peer_id, "invalid_join_payload")
		return
	if _players.has(peer_id):
		return
	if _players.size() >= MAX_PLAYERS:
		_reject_peer(peer_id, "server_full")
		return
	var request := GameProtocol.JoinRequest.from_dict(payload)
	var identity := await PlayerAuthenticator.authenticate(
		request,
		_match_id,
		_expected_join_token,
		_allow_insecure_dev_auth,
	)
	# Authentication is asynchronous; the peer may have disconnected meanwhile.
	if NetworkSession.get_peer_data(peer_id).is_empty():
		return
	if not bool(identity.get("verified", false)):
		_reject_peer(peer_id, str(identity.get("error", "authentication_failed")))
		return
	var pid := str(identity["player_id"])
	for existing_peer in _players:
		if _players[existing_peer].get("player_id", "") == pid:
			_reject_peer(peer_id, "player_already_connected")
			return

	var profile_doc := await CruxSession.get_profile(pid)
	var loadout_doc := await CruxSession.get_loadout(pid)
	if profile_doc.has("error") or loadout_doc.has("error"):
		_reject_peer(peer_id, "player_data_unavailable")
		return
	var profile: Dictionary = profile_doc.get("value", {})
	var loadout: Dictionary = loadout_doc.get("value", {})
	var player_name := str(profile.get("display_name", identity.get("display_name", "Operator")))
	var module := str(loadout.get("module", "pulse_shield"))
	if not SharedResources.MODULES.has(module):
		module = "pulse_shield"
	var consumable := str(loadout.get("consumable", ""))
	if not consumable.is_empty() and not SharedResources.CONSUMABLES.has(consumable):
		consumable = ""

	_players[peer_id] = {
		"player_id": pid,
		"name": player_name,
		"module": module,
		"consumable": consumable,
		"verified": true,
	}
	_simulation.remove_one_bot()
	_simulation.add_player(peer_id, player_name, module, consumable)
	var spawn_pos := Vector2(randf_range(-100.0, 100.0), randf_range(-100.0, 100.0))
	_simulation.apply_player_spawn(peer_id, spawn_pos)
	NetworkSession.send_to_peer(peer_id, "match_started", {
		"peer_id": peer_id,
		"match_id": _match_id,
		"position": {"x": spawn_pos.x, "y": spawn_pos.y},
	})
	if not _match_started:
		_start_match()


func _reject_peer(peer_id: int, reason: String) -> void:
	NetworkSession.send_to_peer(peer_id, "join_rejected", reason)
	await get_tree().create_timer(0.1).timeout
	NetworkSession.disconnect_peer(peer_id)


func _handle_input(peer_id: int, payload: Variant) -> void:
	if not (_players.has(peer_id) and bool(_players[peer_id].get("verified", false)) and payload is Dictionary):
		return
	var input := GameProtocol.InputFrame.from_dict(payload)
	input.player_id = peer_id
	_simulation.apply_input(input)


func _start_match() -> void:
	_match_started = true
	_ending_match = false
	_bot_timer = BOT_SPAWN_DELAY
	NetworkSession.set_match_active(true)
	print("Server: Match %s started with %d authenticated player(s)" % [_match_id, _players.size()])


func _on_server_tick(_tick: int) -> void:
	if not (_match_started and not _ending_match):
		return
	_simulation.tick(1.0 / float(NetworkSession.TICK_RATE))
	var phase := _simulation.get_phase()
	if phase in [GameProtocol.MatchPhase.COMPLETE, GameProtocol.MatchPhase.ABORTED]:
		_end_match()


func _on_snapshot_due(_tick: int) -> void:
	if _match_started:
		NetworkSession.broadcast("snapshot", _simulation.get_snapshot().to_dict())


func _spawn_bots_as_needed() -> void:
	var missing := MAX_PLAYERS - _simulation.get_alive_player_count()
	for _index in range(maxi(0, missing)):
		_simulation.add_next_bot()


func _end_match() -> void:
	if _ending_match:
		return
	_ending_match = true
	_match_started = false
	NetworkSession.set_match_active(false)
	var result := _simulation.get_match_result()
	result.match_id = _match_id
	var base_result := result.to_dict()
	for peer_id in _players:
		var pid := str(_players[peer_id].get("player_id", ""))
		var player_result := base_result.duplicate(true)
		if not pid.is_empty():
			player_result["reward"] = await RewardService.grant_rewards(pid, result)
		NetworkSession.send_to_peer(peer_id, "match_ended", player_result)
	print("Server: Match ended. Cores: %d, Signal: %d, Run: %s" % [result.cores_recovered, result.signal_earned, result.run_id])


func _send_heartbeat() -> void:
	var result := await CruxSession.server_heartbeat(_server_id)
	if result.has("error"):
		push_warning("Server heartbeat failed: %s" % result)


func _shutdown() -> void:
	if _shutting_down:
		return
	_shutting_down = true
	NetworkSession.set_match_active(false)
	if _server_registered:
		await CruxSession.deregister_server(_server_id)
	NetworkSession.stop()
	print("Server: Shutdown complete.")
	get_tree().quit()


func _generate_server_id() -> String:
	var chars := "abcdefghijklmnopqrstuvwxyz0123456789"
	var generated := "relay-"
	for _index in range(8):
		generated += chars[randi() % chars.length()]
	return generated
