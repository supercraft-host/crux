extends Node

const TICK_RATE := 20
const SNAPSHOT_RATE := 15
const INTERPOLATION_MS := 100
const RECONNECT_TIMEOUT := 60.0
const MAX_PLAYERS := 4
const MAX_BOTS := 8
const SUBPROTOCOL := "relay-zero-v1"

signal connected_to_server()
signal player_joined(peer_id: int, player_data: Dictionary)
signal player_left(peer_id: int, reason: String)
signal message_received(sender_id: int, method: String, payload: Variant)
signal connection_failed(reason: String)
signal server_tick(tick: int)
signal snapshot_due(tick: int)

var _peer: WebSocketMultiplayerPeer = null
var _is_host: bool = false
var _connected_peers: Dictionary = {}
var _match_active: bool = false
var _tick: int = 0
var _tick_timer: float = 0.0
var _snapshot_timer: float = 0.0
var _player_slots: Array[int] = []
var _max_peers: int = MAX_PLAYERS


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_bind_multiplayer_signals()


func _process(delta: float) -> void:
	if not (_match_active and _is_host):
		return
	_tick_timer += delta
	_snapshot_timer += delta
	var tick_interval := 1.0 / float(TICK_RATE)
	while _tick_timer >= tick_interval:
		_tick_timer -= tick_interval
		_tick += 1
		server_tick.emit(_tick)
	if _snapshot_timer >= 1.0 / float(SNAPSHOT_RATE):
		_snapshot_timer = 0.0
		snapshot_due.emit(_tick)


func _bind_multiplayer_signals() -> void:
	if not multiplayer.peer_connected.is_connected(_on_peer_connected):
		multiplayer.peer_connected.connect(_on_peer_connected)
	if not multiplayer.peer_disconnected.is_connected(_on_peer_disconnected):
		multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	if not multiplayer.connected_to_server.is_connected(_on_connected_to_server):
		multiplayer.connected_to_server.connect(_on_connected_to_server)
	if not multiplayer.connection_failed.is_connected(_on_connection_failed):
		multiplayer.connection_failed.connect(_on_connection_failed)
	if not multiplayer.server_disconnected.is_connected(_on_server_disconnected):
		multiplayer.server_disconnected.connect(_on_server_disconnected)


func start_client(ws_url: String) -> int:
	stop()
	_bind_multiplayer_signals()
	_is_host = false
	_peer = WebSocketMultiplayerPeer.new()
	_peer.supported_protocols = PackedStringArray([SUBPROTOCOL])
	var err := _peer.create_client(ws_url)
	if err != OK:
		_peer = null
		connection_failed.emit("Failed to create WebSocket client: %d" % err)
		return err
	multiplayer.multiplayer_peer = _peer
	print("NetworkSession: Connecting to %s" % ws_url)
	return OK


func start_server(port: int, max_peers: int = MAX_PLAYERS, bind_address: String = "*") -> int:
	stop()
	_bind_multiplayer_signals()
	_is_host = true
	_max_peers = max_peers
	_player_slots.resize(_max_peers)
	_player_slots.fill(0)
	_peer = WebSocketMultiplayerPeer.new()
	_peer.supported_protocols = PackedStringArray([SUBPROTOCOL])
	# Public WSS termination belongs in the ingress/reverse proxy. The Godot
	# process listens on plain WebSocket inside the trusted container network.
	var err := _peer.create_server(port, bind_address)
	if err != OK:
		_peer = null
		connection_failed.emit("Failed to create WebSocket server: %d" % err)
		return err
	multiplayer.multiplayer_peer = _peer
	print("NetworkSession: Server listening on %s:%d, max players %d" % [bind_address, port, max_peers])
	return OK


func stop() -> void:
	_match_active = false
	_tick = 0
	_tick_timer = 0.0
	_snapshot_timer = 0.0
	if _peer != null:
		_peer.close()
	_peer = null
	_connected_peers.clear()
	_player_slots.clear()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()


func send_to_server(method: String, payload: Variant = null) -> void:
	if not is_session_connected() or _is_host:
		return
	_receive_message.rpc_id(1, method, payload)


func send_to_peer(peer_id: int, method: String, payload: Variant = null) -> void:
	if not (_is_host and is_session_connected()):
		return
	if not _connected_peers.has(peer_id):
		return
	_receive_message.rpc_id(peer_id, method, payload)


func broadcast(method: String, payload: Variant = null) -> void:
	if not (_is_host and is_session_connected()):
		return
	_receive_message.rpc(method, payload)


@rpc("any_peer", "call_remote", "reliable")
func _receive_message(method: String, payload: Variant) -> void:
	var sender_id := multiplayer.get_remote_sender_id()
	message_received.emit(sender_id, method, payload)


func _on_peer_connected(peer_id: int) -> void:
	if not _is_host:
		return
	var slot := _find_empty_slot()
	if slot < 0:
		print("NetworkSession: Server full, rejecting peer %d" % peer_id)
		disconnect_peer(peer_id)
		return
	_player_slots[slot] = peer_id
	_connected_peers[peer_id] = {"slot": slot}
	print("NetworkSession: Peer %d connected in slot %d" % [peer_id, slot])
	player_joined.emit(peer_id, {"slot": slot})


func _on_peer_disconnected(peer_id: int) -> void:
	var slot := _player_slots.find(peer_id)
	if slot >= 0:
		_player_slots[slot] = 0
	_connected_peers.erase(peer_id)
	player_left.emit(peer_id, "disconnected")


func _on_connected_to_server() -> void:
	print("NetworkSession: Connection established as peer %d" % multiplayer.get_unique_id())
	connected_to_server.emit()


func _on_connection_failed() -> void:
	connection_failed.emit("Connection failed")


func _on_server_disconnected() -> void:
	connection_failed.emit("Server disconnected")


func _find_empty_slot() -> int:
	for i in range(_player_slots.size()):
		if _player_slots[i] == 0:
			return i
	return -1


func disconnect_peer(peer_id: int) -> void:
	if _peer != null and _is_host:
		_peer.disconnect_peer(peer_id)


func get_connected_count() -> int:
	return _connected_peers.size() if _is_host else int(is_session_connected())


func get_peer_data(peer_id: int) -> Dictionary:
	return _connected_peers.get(peer_id, {})


func get_local_peer_id() -> int:
	return multiplayer.get_unique_id() if is_session_connected() else 0


func is_host() -> bool:
	return _is_host


func is_session_connected() -> bool:
	return _peer != null and _peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED


func set_match_active(active: bool) -> void:
	_match_active = active
	if active:
		_tick = 0
		_tick_timer = 0.0
		_snapshot_timer = 0.0


func get_tick() -> int:
	return _tick
