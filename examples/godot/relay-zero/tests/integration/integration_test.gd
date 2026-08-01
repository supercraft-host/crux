extends Node

var test_crux: Node


func _ready() -> void:
	print("Integration Tests: Running")
	await get_tree().create_timer(1.0).timeout
	_test_game_protocol()
	_test_shared_resources()
	_test_demo_events()
	print("Integration Tests: Complete")


func _test_game_protocol() -> void:
	print("  Testing GameProtocol...")
	var snap := GameProtocol.WorldSnapshot.new()
	assert(snap != null, "WorldSnapshot created")
	var d := snap.to_dict()
	var restored := GameProtocol.WorldSnapshot.from_dict(d)
	assert(restored.tick == snap.tick, "Snapshot roundtrip: tick")
	var input := GameProtocol.InputFrame.new(1, 5, GameProtocol.InputType.MOVE, Vector2(1, 0), Vector2(0, 1), true)
	var input_d := input.to_dict()
	var restored_input := GameProtocol.InputFrame.from_dict(input_d)
	assert(restored_input.tick == 1, "Input roundtrip: tick")
	print("  GameProtocol: PASSED")


func _test_shared_resources() -> void:
	print("  Testing SharedResources...")
	assert(SharedResources.MODULES.has("pulse_shield"), "Module: pulse_shield exists")
	assert(SharedResources.CONSUMABLES.has("health_kit"), "Consumable: health_kit exists")
	assert(SharedResources.LEADERBOARDS.has("weekly_recovery_score"), "Leaderboard: weekly_recovery_score exists")
	assert(SharedResources.REGIONS.has("eu-west"), "Region: eu-west exists")
	assert(SharedResources.GAME_MODES.has("quick"), "Game mode: quick exists")
	print("  SharedResources: PASSED")


func _test_demo_events() -> void:
	print("  Testing DemoEvents...")
	DemoEvents.record("AUTH", "test_operation", "test_detail", 42, true)
	assert(DemoEvents.total_operations == 1, "Event recorded")
	var summary := DemoEvents.get_post_run_summary()
	assert(summary["AUTH"] == 1, "Summary counts events")
	DemoEvents.clear()
	assert(DemoEvents.total_operations == 0, "Events cleared")
	print("  DemoEvents: PASSED")
