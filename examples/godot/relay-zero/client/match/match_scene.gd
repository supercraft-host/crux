extends Node2D

var _client_simulation: GameSimulation
var _local_player_id: int = 0
var _pending_inputs: Array = []
var _queued_actions: Array[int] = []
var _entity_nodes: Dictionary = {}
var _input_tick_accumulator: float = 0.0
var _input_tick_interval: float = 1.0 / float(NetworkSession.TICK_RATE)
var _local_input_tick: int = 0
var _match_ended: bool = false
@onready var _hud = $CanvasLayer/HUD


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_client_simulation = GameSimulation.new()
	queue_redraw()
	NetworkSession.message_received.connect(_on_message_received)
	NetworkSession.connected_to_server.connect(_on_connected)
	NetworkSession.connection_failed.connect(_on_connection_failed)
	NetworkSession.player_left.connect(_on_player_left)
	if AppState.is_client():
		_connect_to_server()
	else:
		_start_offline_match()


func _exit_tree() -> void:
	if AppState.is_client():
		NetworkSession.stop()


func _process(delta: float) -> void:
	if _match_ended:
		return
	_input_tick_accumulator += delta
	while _input_tick_accumulator >= _input_tick_interval:
		_input_tick_accumulator -= _input_tick_interval
		_collect_tick_inputs()
		_flush_pending_inputs(AppState.is_client())
		if not AppState.is_client():
			_client_simulation.tick(_input_tick_interval)
			var offline_snapshot := _client_simulation.get_snapshot()
			_apply_snapshot(offline_snapshot)
			if offline_snapshot.phase in [GameProtocol.MatchPhase.COMPLETE, GameProtocol.MatchPhase.ABORTED] and not _match_ended:
				_on_match_ended(_client_simulation.get_match_result().to_dict())
	_update_entity_transforms()


func _input(event: InputEvent) -> void:
	if _match_ended or not event.is_pressed() or event.is_echo():
		return
	if event.is_action_pressed("use_module"):
		_queued_actions.append(GameProtocol.InputType.USE_MODULE)
	elif event.is_action_pressed("dash"):
		_queued_actions.append(GameProtocol.InputType.DASH)
	elif event.is_action_pressed("interact"):
		_queued_actions.append(GameProtocol.InputType.INTERACT)


func _connect_to_server() -> void:
	var err := NetworkSession.start_client(AppState.server_url)
	if err != OK:
		_connection_failed("Failed to create client: %d" % err)


func _start_offline_match() -> void:
	print("Match: Starting offline training match")
	_client_simulation.initialize({"time_limit": 300.0, "max_cores": 3})
	_local_player_id = 1
	_client_simulation.add_player(_local_player_id, AppState.display_name, AppState.active_module, AppState.active_consumable)
	_client_simulation.apply_player_spawn(_local_player_id, Vector2.ZERO)
	AppState.transition_to(AppState.State.PLAYING)
	DemoEvents.record("MATCH", "Offline training started", "", 0, true)
	_apply_snapshot(_client_simulation.get_snapshot())


func _on_connected() -> void:
	print("Match: Connected to server. Sending authenticated join request.")
	var join_request := GameProtocol.JoinRequest.new()
	join_request.player_id = AppState.player_id
	join_request.player_token = CruxSession.get_player_access_token()
	join_request.join_token = AppState.join_token
	join_request.match_id = AppState.match_id
	join_request.display_name = AppState.display_name
	join_request.module = AppState.active_module
	join_request.consumable = AppState.active_consumable
	NetworkSession.send_to_server("join", join_request.to_dict())


func _on_connection_failed(reason: String) -> void:
	if _match_ended or AppState.is_offline():
		return
	_connection_failed(reason)


func _connection_failed(reason: String) -> void:
	push_error("Connection failed: " + reason)
	DemoEvents.record("SERVER", "Connection failed", reason, 0, false)
	NetworkSession.stop()
	AppState.run_mode = AppState.RunMode.OFFLINE
	_start_offline_match()


func _on_player_left(peer_id: int, reason: String) -> void:
	print("Match: Player %d left (%s)" % [peer_id, reason])
	_client_simulation.remove_player(peer_id)
	_remove_entity(peer_id)


func _on_message_received(sender_id: int, method: String, payload: Variant) -> void:
	if sender_id != 1:
		return
	match method:
		"snapshot":
			if payload is Dictionary:
				_apply_snapshot(GameProtocol.WorldSnapshot.from_dict(payload))
		"match_started":
			_on_match_started(payload if payload is Dictionary else {})
		"match_ended":
			_on_match_ended(payload if payload is Dictionary else {})
		"join_rejected":
			_connection_failed(str(payload))


func _on_match_started(data: Dictionary) -> void:
	_local_player_id = int(data.get("peer_id", NetworkSession.get_local_peer_id()))
	print("Match: Started as peer %d" % _local_player_id)
	if _client_simulation.get_object(_local_player_id) == null:
		_client_simulation.add_player(_local_player_id, AppState.display_name, AppState.active_module, AppState.active_consumable)
	AppState.transition_to(AppState.State.PLAYING)


func _on_match_ended(data: Dictionary) -> void:
	_match_ended = true
	AppState.last_match_result = data.duplicate(true)
	_log_match_summary(data)
	AppState.transition_to(AppState.State.RESULTS)
	await get_tree().create_timer(0.5).timeout
	get_tree().change_scene_to_file("res://client/menus/results_scene.tscn")


func _log_match_summary(data: Dictionary) -> void:
	var time_ms := int(data.get("time_ms", 0))
	var summary := {
		"offline": AppState.is_offline(),
		"run_id": str(data.get("run_id", "")),
		"match_id": str(data.get("match_id", "")),
		"survived": bool(data.get("team_survived", false)),
		"cores_recovered": int(data.get("cores_recovered", 0)),
		"time_ms": time_ms,
		"signal": int(data.get("signal", 0)),
		"party_size": int(data.get("party_size", 0)),
		"modifier": str(data.get("modifier", "")),
		"reward": data.get("reward", null),
	}
	DemoEvents.record_note("match_end", summary)
	print("Match: %s | cores %d/3 | %d:%02d | signal %d | %s" % [
		"SURVIVED" if summary["survived"] else "ABORTED",
		summary["cores_recovered"],
		int(time_ms / 60000), int(time_ms / 1000) % 60,
		summary["signal"],
		"offline" if summary["offline"] else "online",
	])


func _collect_tick_inputs() -> void:
	if _local_player_id == 0:
		_queued_actions.clear()
		return
	_local_input_tick += 1
	var move_dir := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	var aim_dir := _get_aim_direction()
	var movement_type := GameProtocol.InputType.MOVE if move_dir.length_squared() > 0.001 else GameProtocol.InputType.AIM
	_pending_inputs.append(GameProtocol.InputFrame.new(_local_input_tick, _local_player_id, movement_type, move_dir, aim_dir, true))
	if Input.is_action_pressed("primary_tool"):
		_pending_inputs.append(GameProtocol.InputFrame.new(_local_input_tick, _local_player_id, GameProtocol.InputType.PRIMARY_TOOL, move_dir, aim_dir, true))
	for action_type in _queued_actions:
		_pending_inputs.append(GameProtocol.InputFrame.new(_local_input_tick, _local_player_id, action_type, move_dir, aim_dir, true))
	_queued_actions.clear()


func _get_aim_direction() -> Vector2:
	if Input.get_connected_joypads().size() > 0:
		var stick := Input.get_vector("aim_left", "aim_right", "aim_up", "aim_down")
		return stick.normalized() if stick.length_squared() > 0.01 else Vector2.RIGHT
	var player_pos := Vector2.ZERO
	if _entity_nodes.has(_local_player_id):
		player_pos = _entity_nodes[_local_player_id].position
	var direction := get_global_mouse_position() - player_pos
	return direction.normalized() if direction.length_squared() > 0.01 else Vector2.RIGHT


func _flush_pending_inputs(send_remote: bool) -> void:
	for input in _pending_inputs:
		# Local prediction is deliberately limited to the local actor. The next
		# authoritative snapshot corrects any divergence.
		_client_simulation.apply_input(input)
		if send_remote and NetworkSession.is_session_connected():
			NetworkSession.send_to_server("input", input.to_dict())
	_pending_inputs.clear()


func _apply_snapshot(snapshot: GameProtocol.WorldSnapshot) -> void:
	var seen: Dictionary = {}
	for obj in snapshot.objects:
		seen[obj.object_id] = true
		if not _entity_nodes.has(obj.object_id):
			_spawn_entity(obj)
		_entity_nodes[obj.object_id].apply_state(obj)
	for object_id in _entity_nodes.keys():
		if not seen.has(object_id):
			_remove_entity(object_id)
	_hud.apply_snapshot(snapshot, _local_player_id)


func _spawn_entity(state: GameProtocol.ObjectState) -> void:
	var entity := EntityComponent.new()
	entity.is_local_player = state.object_id == _local_player_id
	entity.object_id = state.object_id
	add_child(entity)
	entity.apply_state(state)
	_entity_nodes[state.object_id] = entity


func _remove_entity(object_id: int) -> void:
	if not _entity_nodes.has(object_id):
		return
	_entity_nodes[object_id].queue_free()
	_entity_nodes.erase(object_id)


func _update_entity_transforms() -> void:
	pass


func _draw() -> void:
	var bounds := Rect2(-430, -300, 860, 600)
	draw_rect(bounds, Color(0.025, 0.035, 0.06), true)
	draw_rect(bounds, Color(0.15, 0.28, 0.4), false, 3.0)
	for x in range(-400, 401, 40):
		draw_line(Vector2(x, -280), Vector2(x, 280), Color(0.08, 0.13, 0.18), 1.0)
	for y in range(-280, 281, 40):
		draw_line(Vector2(-400, y), Vector2(400, y), Color(0.08, 0.13, 0.18), 1.0)
