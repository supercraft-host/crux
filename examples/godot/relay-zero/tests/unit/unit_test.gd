extends Node


func _ready() -> void:
	print("Unit Tests: Running")
	_test_game_protocol()
	_test_game_simulation_loop()
	_test_match_controller()
	print("Unit Tests: Complete")


func _test_game_protocol() -> void:
	var request := GameProtocol.JoinRequest.new()
	request.player_id = "player-1"
	request.player_token = "jwt"
	request.join_token = "join"
	request.match_id = "match-1"
	var restored := GameProtocol.JoinRequest.from_dict(request.to_dict())
	assert(restored.player_id == request.player_id)
	assert(restored.join_token == request.join_token)


func _test_game_simulation_loop() -> void:
	var sim := GameSimulation.new()
	sim.initialize({"time_limit": 300.0, "max_cores": 3})
	assert(sim.get_phase() == GameProtocol.MatchPhase.RECOVERING)
	sim.add_player(1, "TestPlayer", "pulse_shield", "")
	assert(sim.get_human_player_count() == 1)
	var snapshot := sim.get_snapshot()
	assert(snapshot.objects.size() >= 3) # player + core + relay
	sim.tick(0.05)
	assert(sim.get_snapshot().tick == 1)


func _test_match_controller() -> void:
	var sim := GameSimulation.new()
	var controller := MatchController.new()
	controller.initialize(sim, {"time_limit": 300.0, "max_cores": 3})
	controller.add_player(1, "Test", "pulse_shield", "")
	assert(controller.get_player_count() == 1)
	controller.start_match()
	assert(controller.is_started())
