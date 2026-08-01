extends Node

enum State {
	BOOTING,
	MAIN_MENU,
	MATCHMAKING,
	CONNECTING,
	PLAYING,
	RESULTS,
	OFFLINE_TRAINING,
}

enum RunMode {
	CLIENT,
	DEDICATED_SERVER,
	OFFLINE,
}

var current_state: State = State.BOOTING
var run_mode: RunMode = RunMode.CLIENT
var player_id: String = ""
var display_name: String = ""
var join_token: String = ""
var match_id: String = ""
var server_url: String = ""
var is_carrying_core: bool = false
var active_module: String = ""
var active_consumable: String = ""
var selected_region: String = "eu-west"
var selected_mode: String = "quick"
var tutorial_complete: bool = false
var developer_mode: bool = false
var architecture_mode: bool = false
var last_match_result: Dictionary = {}

signal state_changed(from: State, to: State)
signal player_authenticated(player_id: String, display_name: String)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if not OS.has_feature("dedicated_server"):
		run_mode = RunMode.CLIENT
	else:
		run_mode = RunMode.DEDICATED_SERVER


func transition_to(new_state: State) -> void:
	var old_state = current_state
	current_state = new_state
	print("AppState: %s -> %s" % [State.keys()[old_state], State.keys()[new_state]])
	state_changed.emit(old_state, new_state)


func set_player_identity(id: String, name: String) -> void:
	player_id = id
	display_name = name
	player_authenticated.emit(id, name)


func set_match_info(p_match_id: String, p_join_token: String, p_server_url: String) -> void:
	match_id = p_match_id
	join_token = p_join_token
	server_url = p_server_url


func is_server() -> bool:
	return run_mode == RunMode.DEDICATED_SERVER


func is_client() -> bool:
	return run_mode == RunMode.CLIENT


func is_offline() -> bool:
	return run_mode == RunMode.OFFLINE
