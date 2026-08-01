class_name GameSimulation
extends RefCounted

const CORE_POSITIONS := [Vector2(-260, -140), Vector2(250, -170), Vector2(-180, 210)]
const RELAY_POSITIONS := [Vector2(250, 130), Vector2(-240, 150), Vector2(200, -210)]
const EXTRACTION_POSITION := Vector2(0, 260)

var _objects: Dictionary = {}
var _players: Dictionary = {}
var _phase: int = GameProtocol.MatchPhase.DEPLOYING
var _pressure_level: int = 0
var _cores_recovered: int = 0
var _signal_earned: int = 0
var _time_remaining: float = 300.0
var _match_time_limit: float = 300.0
var _max_cores: int = 3
var _extraction_active: bool = false
var _extraction_timer: float = 30.0
var _next_object_id: int = 100
var _next_bot_id: int = 1000
var _tick: int = 0
var _modifier_id: String = ""
var _config_version: String = ""
var _active_core_id: int = 0
var _active_relay_id: int = 0


func initialize(settings: Dictionary) -> void:
	clear()
	_match_time_limit = float(settings.get("time_limit", 300.0))
	_max_cores = clampi(int(settings.get("max_cores", 3)), 1, CORE_POSITIONS.size())
	_modifier_id = str(settings.get("modifier_id", ""))
	_config_version = str(settings.get("config_version", ""))
	_time_remaining = _match_time_limit
	_phase = GameProtocol.MatchPhase.RECOVERING
	_spawn_sector(0)


func add_player(player_id: int, name: String, module: String, consumable: String) -> void:
	_players[player_id] = {
		"name": name,
		"module": module,
		"consumable": consumable,
		"is_bot": false,
		"alive": true,
		"extracted": false,
		"position": Vector2.ZERO,
	}
	var obj := GameProtocol.ObjectState.new()
	obj.object_id = player_id
	obj.object_type = GameProtocol.ObjectType.PLAYER
	obj.metadata = {"name": name, "is_bot": false}
	_objects[player_id] = obj


func add_bot(bot_id: int) -> void:
	if _players.has(bot_id):
		return
	_players[bot_id] = {
		"name": "Bot-%d" % bot_id,
		"module": "pulse_shield",
		"consumable": "",
		"is_bot": true,
		"alive": true,
		"extracted": false,
		"position": Vector2(randf_range(-40.0, 40.0), randf_range(-40.0, 40.0)),
	}
	var obj := GameProtocol.ObjectState.new()
	obj.object_id = bot_id
	obj.object_type = GameProtocol.ObjectType.PLAYER
	obj.position = _players[bot_id]["position"]
	obj.metadata = {"name": "Bot-%d" % bot_id, "is_bot": true}
	_objects[bot_id] = obj


func add_next_bot() -> int:
	while _players.has(_next_bot_id):
		_next_bot_id += 1
	var bot_id := _next_bot_id
	_next_bot_id += 1
	add_bot(bot_id)
	return bot_id


func remove_one_bot() -> bool:
	for player_id in _players.keys():
		if bool(_players[player_id].get("is_bot", false)):
			remove_player(player_id)
			return true
	return false


func remove_player(player_id: int) -> void:
	if _objects.has(player_id):
		var player_obj: GameProtocol.ObjectState = _objects[player_id]
		if player_obj.carrying > 0 and _objects.has(player_obj.carrying):
			var core: GameProtocol.ObjectState = _objects[player_obj.carrying]
			core.carried_by = 0
			core.position = player_obj.position
	_objects.erase(player_id)
	_players.erase(player_id)
	if _phase in [GameProtocol.MatchPhase.RECOVERING, GameProtocol.MatchPhase.EXTRACTING] and get_human_player_count() == 0:
		_end_match(false)


func apply_input(input: GameProtocol.InputFrame) -> void:
	if not _objects.has(input.player_id):
		return
	var obj: GameProtocol.ObjectState = _objects[input.player_id]
	if not obj.is_alive or bool(_players[input.player_id].get("extracted", false)):
		return
	match input.input_type:
		GameProtocol.InputType.MOVE:
			var direction := input.move_dir.limit_length(1.0)
			obj.position += direction * _get_player_speed(input.player_id) / float(NetworkSession.TICK_RATE)
			_players[input.player_id]["position"] = obj.position
		GameProtocol.InputType.AIM:
			if input.aim_dir.length_squared() > 0.01:
				obj.rotation = input.aim_dir.angle()
		GameProtocol.InputType.PRIMARY_TOOL:
			if input.pressed:
				_fire_primary(input.player_id, input.aim_dir)
		GameProtocol.InputType.SECONDARY_TOOL, GameProtocol.InputType.USE_MODULE:
			if input.pressed:
				_use_module(input.player_id)
		GameProtocol.InputType.DASH:
			if input.pressed:
				_dash(input.player_id, input.move_dir)
		GameProtocol.InputType.INTERACT:
			if input.pressed:
				_interact(input.player_id)


func tick(delta: float) -> void:
	if _phase in [GameProtocol.MatchPhase.COMPLETE, GameProtocol.MatchPhase.ABORTED]:
		return
	_tick += 1
	_update_carried_objects()
	_update_bots(delta)
	_update_projectiles(delta)
	_time_remaining = maxf(0.0, _time_remaining - delta)
	if _time_remaining <= 0.0 and not _extraction_active:
		_activate_extraction()
	if _phase == GameProtocol.MatchPhase.EXTRACTING:
		_extraction_timer -= delta
		if _extraction_timer <= 0.0:
			_end_match(_cores_recovered > 0)


func _spawn_sector(index: int) -> void:
	_active_core_id = _next_object_id
	var core := GameProtocol.ObjectState.new()
	core.object_id = _next_object_id
	core.object_type = GameProtocol.ObjectType.DATA_CORE
	core.position = CORE_POSITIONS[index]
	core.metadata = {"sector": index, "active": true}
	_objects[core.object_id] = core
	_next_object_id += 1

	_active_relay_id = _next_object_id
	var relay := GameProtocol.ObjectState.new()
	relay.object_id = _next_object_id
	relay.object_type = GameProtocol.ObjectType.RELAY_TOWER
	relay.position = RELAY_POSITIONS[index]
	relay.metadata = {"sector": index, "active": true, "complete": false}
	_objects[relay.object_id] = relay
	_next_object_id += 1


func _get_player_speed(player_id: int) -> float:
	return 120.0 if _is_carrying(player_id) else 200.0


func _fire_primary(player_id: int, direction: Vector2) -> void:
	var player_obj: GameProtocol.ObjectState = _objects[player_id]
	var shot_direction := direction.normalized() if direction.length_squared() > 0.01 else Vector2.RIGHT.rotated(player_obj.rotation)
	var projectile := GameProtocol.ObjectState.new()
	projectile.object_id = _next_object_id
	projectile.object_type = GameProtocol.ObjectType.PROJECTILE
	projectile.position = player_obj.position + shot_direction * 20.0
	projectile.velocity = shot_direction * 500.0
	projectile.metadata = {"owner_id": player_id, "lifetime": 0.45, "age": 0.0}
	_objects[projectile.object_id] = projectile
	_next_object_id += 1


func _use_module(player_id: int) -> void:
	if str(_players[player_id].get("module", "")) == "repair_field":
		_heal_nearby_players(player_id, 30.0, 150.0)


func _dash(player_id: int, direction: Vector2) -> void:
	var obj: GameProtocol.ObjectState = _objects[player_id]
	var dash_direction := direction.normalized() if direction.length_squared() > 0.01 else Vector2.RIGHT.rotated(obj.rotation)
	obj.position += dash_direction * 120.0
	_players[player_id]["position"] = obj.position


func _interact(player_id: int) -> void:
	if _extraction_active and _try_extract(player_id):
		return
	if _is_carrying(player_id):
		_try_connect_core(player_id)
	else:
		_try_pickup_core(player_id)


func _try_pickup_core(player_id: int) -> bool:
	if not (_objects.has(_active_core_id) and _objects.has(player_id)):
		return false
	var player_obj: GameProtocol.ObjectState = _objects[player_id]
	var core: GameProtocol.ObjectState = _objects[_active_core_id]
	if not core.is_alive or core.carried_by != 0:
		return false
	if player_obj.position.distance_to(core.position) > 55.0:
		return false
	core.carried_by = player_id
	player_obj.carrying = core.object_id
	return true


func _try_connect_core(player_id: int) -> bool:
	if not (_objects.has(_active_core_id) and _objects.has(_active_relay_id)):
		return false
	var player_obj: GameProtocol.ObjectState = _objects[player_id]
	if player_obj.carrying != _active_core_id:
		return false
	var relay: GameProtocol.ObjectState = _objects[_active_relay_id]
	if player_obj.position.distance_to(relay.position) > 65.0:
		return false
	_complete_sector(player_id)
	return true


func _complete_sector(player_id: int) -> void:
	var player_obj: GameProtocol.ObjectState = _objects[player_id]
	player_obj.carrying = 0
	if _objects.has(_active_core_id):
		_objects.erase(_active_core_id)
	if _objects.has(_active_relay_id):
		var relay: GameProtocol.ObjectState = _objects[_active_relay_id]
		relay.metadata["active"] = false
		relay.metadata["complete"] = true
	_cores_recovered += 1
	_pressure_level += 1
	_signal_earned = _calculate_total_signal()
	if _cores_recovered >= _max_cores:
		_activate_extraction()
	else:
		_spawn_sector(_cores_recovered)


func _activate_extraction() -> void:
	if _extraction_active:
		return
	_extraction_active = true
	_phase = GameProtocol.MatchPhase.EXTRACTING
	_extraction_timer = 30.0
	var beacon := GameProtocol.ObjectState.new()
	beacon.object_id = _next_object_id
	beacon.object_type = GameProtocol.ObjectType.EXTRACTION_BEACON
	beacon.position = EXTRACTION_POSITION
	beacon.metadata = {"timer": _extraction_timer}
	_objects[beacon.object_id] = beacon
	_next_object_id += 1


func _try_extract(player_id: int) -> bool:
	var player_obj: GameProtocol.ObjectState = _objects[player_id]
	for object_id in _objects:
		var obj: GameProtocol.ObjectState = _objects[object_id]
		if obj.object_type == GameProtocol.ObjectType.EXTRACTION_BEACON and player_obj.position.distance_to(obj.position) <= 80.0:
			_players[player_id]["extracted"] = true
			player_obj.is_alive = false
			if _all_humans_extracted():
				_end_match(true)
			return true
	return false


func _all_humans_extracted() -> bool:
	var human_count := 0
	for player_id in _players:
		if bool(_players[player_id].get("is_bot", false)):
			continue
		human_count += 1
		if not bool(_players[player_id].get("extracted", false)):
			return false
	return human_count > 0


func _end_match(success: bool) -> void:
	_phase = GameProtocol.MatchPhase.COMPLETE if success else GameProtocol.MatchPhase.ABORTED


func _update_carried_objects() -> void:
	if not _objects.has(_active_core_id):
		return
	var core: GameProtocol.ObjectState = _objects[_active_core_id]
	if core.carried_by > 0 and _objects.has(core.carried_by):
		core.position = _objects[core.carried_by].position + Vector2(0, -24)


func _update_bots(delta: float) -> void:
	for player_id in _players.keys():
		if not bool(_players[player_id].get("is_bot", false)):
			continue
		if not _objects.has(player_id):
			continue
		var target := Vector2.ZERO
		if _extraction_active:
			target = EXTRACTION_POSITION
		elif _is_carrying(player_id) and _objects.has(_active_relay_id):
			target = _objects[_active_relay_id].position
		elif _objects.has(_active_core_id):
			target = _objects[_active_core_id].position
		var bot_obj: GameProtocol.ObjectState = _objects[player_id]
		var direction := target - bot_obj.position
		if direction.length() > 12.0:
			bot_obj.position += direction.normalized() * _get_player_speed(player_id) * delta
			_players[player_id]["position"] = bot_obj.position
		else:
			_interact(player_id)


func _update_projectiles(delta: float) -> void:
	var expired: Array[int] = []
	for object_id in _objects:
		var obj: GameProtocol.ObjectState = _objects[object_id]
		if obj.object_type != GameProtocol.ObjectType.PROJECTILE:
			continue
		obj.position += obj.velocity * delta
		obj.metadata["age"] = float(obj.metadata.get("age", 0.0)) + delta
		if float(obj.metadata["age"]) >= float(obj.metadata.get("lifetime", 0.45)):
			expired.append(object_id)
	for object_id in expired:
		_objects.erase(object_id)


func _heal_nearby_players(healer_id: int, amount: float, radius: float) -> void:
	var healer_position: Vector2 = _objects[healer_id].position
	for object_id in _objects:
		var obj: GameProtocol.ObjectState = _objects[object_id]
		if obj.object_type == GameProtocol.ObjectType.PLAYER and obj.is_alive and healer_position.distance_to(obj.position) < radius:
			obj.health = minf(obj.max_health, obj.health + amount)


func _is_carrying(player_id: int) -> bool:
	return _objects.has(player_id) and _objects[player_id].carrying > 0


func apply_player_spawn(player_id: int, position: Vector2) -> void:
	if not _objects.has(player_id):
		return
	var obj: GameProtocol.ObjectState = _objects[player_id]
	obj.is_alive = true
	obj.health = obj.max_health
	obj.position = position
	_players[player_id]["position"] = position


func get_snapshot() -> GameProtocol.WorldSnapshot:
	var snapshot := GameProtocol.WorldSnapshot.new()
	snapshot.tick = _tick
	snapshot.phase = _phase
	snapshot.pressure_level = _pressure_level
	snapshot.cores_recovered = _cores_recovered
	snapshot.signal_earned = _signal_earned
	snapshot.time_remaining = _time_remaining
	snapshot.modifier_id = _modifier_id
	snapshot.config_version = _config_version
	snapshot.objects.assign(_objects.values())
	return snapshot


func get_match_result() -> GameProtocol.MatchResult:
	var result := GameProtocol.MatchResult.new()
	result.players = []
	for player_id in _players:
		if not bool(_players[player_id].get("is_bot", false)):
			result.players.append(player_id)
	result.cores_recovered = _cores_recovered
	result.time_taken = _match_time_limit - _time_remaining
	result.party_size = get_human_player_count()
	result.difficulty_multiplier = 1.0 + (_pressure_level * 0.25)
	result.signal_earned = _calculate_total_signal()
	result.modifier_id = _modifier_id
	result.items_found = []
	# _end_match() already resolved success into the phase: COMPLETE on extraction
	# or on a timer expiry with cores banked, ABORTED otherwise.
	result.team_survived = _phase == GameProtocol.MatchPhase.COMPLETE
	result.run_id = "run_%d_%d" % [Time.get_unix_time_from_system(), randi()]
	return result


func _calculate_total_signal() -> int:
	var base := _cores_recovered * int(LiveConfig.get_balance().get("base_reward_per_core", 50))
	var multiplier := LiveConfig.get_reward_multiplier() * (1.0 + _pressure_level * 0.25)
	return int(base * multiplier)


func get_phase() -> int:
	return _phase


func get_pressure_level() -> int:
	return _pressure_level


func get_time_remaining() -> float:
	return _time_remaining


func get_alive_player_count() -> int:
	var count := 0
	for player_id in _players:
		if bool(_players[player_id].get("alive", true)) and not bool(_players[player_id].get("extracted", false)):
			count += 1
	return count


func get_human_player_count() -> int:
	var count := 0
	for player_id in _players:
		if not bool(_players[player_id].get("is_bot", false)):
			count += 1
	return count


func get_object(object_id: int) -> GameProtocol.ObjectState:
	return _objects.get(object_id)


func clear() -> void:
	_objects.clear()
	_players.clear()
	_phase = GameProtocol.MatchPhase.DEPLOYING
	_pressure_level = 0
	_cores_recovered = 0
	_signal_earned = 0
	_time_remaining = _match_time_limit
	_extraction_active = false
	_extraction_timer = 30.0
	_next_object_id = 100
	_next_bot_id = 1000
	_tick = 0
	_active_core_id = 0
	_active_relay_id = 0
