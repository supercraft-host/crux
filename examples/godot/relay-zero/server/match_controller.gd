class_name MatchController
extends RefCounted

var _simulation: GameSimulation
var _phase: int
var _started: bool = false
var _bots: Array[int] = []
var _next_bot_id: int = 1000
var _players: Dictionary = {}


func initialize(simulation: GameSimulation, settings: Dictionary) -> void:
	_simulation = simulation
	_simulation.initialize(settings)
	_phase = GameProtocol.MatchPhase.WAITING


func add_player(peer_id: int, name: String, module: String, consumable: String) -> void:
	_players[peer_id] = {
		"name": name,
		"module": module,
		"consumable": consumable,
		"is_bot": false,
	}
	_simulation.add_player(peer_id, name, module, consumable)


func remove_player(peer_id: int) -> void:
	_players.erase(peer_id)
	_simulation.remove_player(peer_id)


func add_bot() -> int:
	var bot_id := _next_bot_id
	_next_bot_id += 1
	_bots.append(bot_id)
	_simulation.add_bot(bot_id)
	return bot_id


func fill_bots_to(target_count: int) -> void:
	var current := get_player_count()
	var needed := target_count - current
	for i in range(needed):
		add_bot()


func start_match() -> void:
	_started = true


func end_match() -> GameProtocol.MatchResult:
	_started = false
	return _simulation.get_match_result()


func tick(delta: float) -> void:
	_simulation.tick(delta)


func apply_input(input: GameProtocol.InputFrame) -> void:
	_simulation.apply_input(input)


func get_player_count() -> int:
	var count := 0
	for id in _players:
		count += 1
	return count


func is_started() -> bool:
	return _started


func get_phase() -> int:
	return _simulation.get_phase()


func get_snapshot() -> GameProtocol.WorldSnapshot:
	return _simulation.get_snapshot()
