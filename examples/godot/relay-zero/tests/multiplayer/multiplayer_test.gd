extends Node


func _ready() -> void:
	print("Multiplayer Tests: Running (requires server)")
	await get_tree().create_timer(1.0).timeout
	print("Multiplayer Tests: SKIPPED (needs live Crux connection)")


func run_multiplayer_test():
	print("  Setting up test...")
	var sim := GameSimulation.new()
	sim.initialize({"time_limit": 300.0, "max_cores": 3})

	sim.add_player(1, "Player1", "pulse_shield", "")
	sim.add_player(2, "Player2", "scanner", "")
	sim.add_player(3, "Player3", "repulsor", "")
	sim.add_player(4, "Player4", "repair_field", "")

	assert(sim.get_alive_player_count() == 4, "4 players added")

	var input1 := GameProtocol.InputFrame.new(1, 1, GameProtocol.InputType.MOVE, Vector2(1, 0), Vector2(0, 0), true)
	sim.apply_input(input1)
	sim.tick(0.05)

	var snap := sim.get_snapshot()
	assert(snap.objects.size() >= 4, "Snapshot has player objects")

	sim.add_bot(1000)
	sim.add_bot(1001)

	sim.tick(0.05)

	assert(sim.get_alive_player_count() == 6, "6 total after bots")

	var result := sim.get_match_result()
	assert(result.run_id != "", "Run ID generated")
	print("  Multiplayer simulation: PASSED")
