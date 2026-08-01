class_name RegistryService
extends RefCounted

var _server_id: String = ""
var _server_name: String = ""
var _region: String = ""
var _game_mode: String = "quick"
var _map_name: String = "facility_a"
var _version: String = "0.1.0"
var _registered: bool = false
var _heartbeat_interval: float = 30.0


func initialize(server_id: String, server_name: String, region: String) -> void:
	_server_id = server_id
	_server_name = server_name
	_region = region


func register(address: String, port: int, max_players: int) -> Dictionary:
	var reg := {
		"server_id": _server_id,
		"name": _server_name,
		"region": _region,
		"map_name": _map_name,
		"game_mode": _game_mode,
		"player_count": 0,
		"max_players": max_players,
		"address": address,
		"port": port,
		"version": _version,
	}
	var result := await CruxSession.register_server(reg)
	_registered = not result.has("error")
	return result


func heartbeat(player_count: int, match_state: String, current_modifier: String, accepts_joins: bool) -> void:
	if not _registered:
		return
	await CruxSession.server_heartbeat(_server_id)


func deregister() -> void:
	if not _registered:
		return
	await CruxSession.deregister_server(_server_id)
	_registered = false


func is_registered() -> bool:
	return _registered


static func list_servers(region: String = "", map_name: String = "", game_mode: String = "") -> Array:
	return await CruxSession.list_servers(region, map_name, game_mode)
