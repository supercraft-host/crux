extends Node2D

const PACKAGED_CONFIG_PATH := "res://client/boot/client_config.cfg"
const USER_CONFIG_PATH := "user://client_config.cfg"

var _boot_stage: int = 0
var _error_message: String = ""
var _crux_url: String = ""
var _project_id: String = ""
var _env_id: String = ""
var _api_key: String = ""


func _ready() -> void:
	OS.low_processor_usage_mode = false
	if not OS.has_feature("web"):
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED)
	AppState.transition_to(AppState.State.BOOTING)
	if not _load_config():
		return
	await _boot_sequence()


func _load_config() -> bool:
	var config := ConfigFile.new()
	var err := config.load(PACKAGED_CONFIG_PATH)
	if err != OK:
		_boot_failed("Packaged client configuration is missing.")
		return false

	# A user config is an optional local override. This keeps the browser build
	# bootable while still allowing developers to use their own project IDs.
	var override := ConfigFile.new()
	if override.load(USER_CONFIG_PATH) == OK:
		for section in override.get_sections():
			for key in override.get_section_keys(section):
				config.set_value(section, key, override.get_value(section, key))

	_crux_url = str(config.get_value("crux", "url", "https://crux.supercraft.host"))
	_project_id = str(config.get_value("crux", "project_id", ""))
	_env_id = str(config.get_value("crux", "env_id", ""))
	_api_key = str(config.get_value("crux", "api_key", ""))
	AppState.selected_region = str(config.get_value("match", "default_region", "eu-west"))
	AppState.selected_mode = str(config.get_value("match", "default_mode", "quick"))

	if _is_placeholder(_project_id) or _is_placeholder(_env_id) or _is_placeholder(_api_key):
		_boot_failed("Crux credentials are not configured; starting offline training.")
		return false
	return true


func _is_placeholder(value: String) -> bool:
	return value.is_empty() or value.begins_with("your-") or value.begins_with("<")


func _boot_sequence() -> void:
	_boot_stage = 1
	queue_redraw()
	print("Boot: Stage 1 - Initializing Crux services...")
	CruxSession.initialize_player_mode(_crux_url, _project_id, _env_id, _api_key)

	_boot_stage = 2
	queue_redraw()
	print("Boot: Stage 2 - Authenticating guest...")
	var auth_result := await CruxSession.login_anonymous_persistent()
	if auth_result.has("error"):
		_boot_failed("Authentication failed: %s" % auth_result.get("error", "unknown"))
		return

	_boot_stage = 3
	queue_redraw()
	print("Boot: Stage 3 - Loading player profile...")
	var profile_result := await CruxSession.get_profile(AppState.player_id)
	if profile_result.has("value"):
		var profile_data: Dictionary = profile_result["value"]
		AppState.display_name = profile_data.get("display_name", AppState.display_name)
		AppState.tutorial_complete = profile_data.get("tutorial_complete", false)
	var loadout_result := await CruxSession.get_loadout(AppState.player_id)
	if loadout_result.has("value"):
		var loadout_data: Dictionary = loadout_result["value"]
		AppState.active_module = loadout_data.get("module", "pulse_shield")
		AppState.active_consumable = loadout_data.get("consumable", "")
	await CruxSession.get_progression(AppState.player_id)

	_boot_stage = 4
	queue_redraw()
	print("Boot: Stage 4 - Downloading live config...")
	await LiveConfig.refresh()

	_boot_stage = 5
	queue_redraw()
	print("Boot: Stage 5 - Complete. Entering main menu.")
	AppState.transition_to(AppState.State.MAIN_MENU)
	get_tree().change_scene_to_file("res://client/menus/main_menu.tscn")


func _boot_failed(msg: String) -> void:
	if not _error_message.is_empty():
		return
	_error_message = msg
	push_warning("Boot: %s" % msg)
	AppState.run_mode = AppState.RunMode.OFFLINE
	AppState.display_name = "Operator Local"
	AppState.active_module = "pulse_shield"
	AppState.transition_to(AppState.State.OFFLINE_TRAINING)
	queue_redraw()
	_enter_offline_training.call_deferred()


func _enter_offline_training() -> void:
	await get_tree().create_timer(0.25).timeout
	get_tree().change_scene_to_file("res://client/match/match_scene.tscn")


func _draw() -> void:
	if _error_message:
		draw_rect(Rect2(Vector2.ZERO, get_viewport_rect().size), Color(0.1, 0.0, 0.0, 1.0))
	var center := get_viewport_rect().size / 2.0
	var font := ThemeDB.fallback_font
	var fsize := 24
	var stage_messages := PackedStringArray(["Initializing engine...", "Authenticating...", "Loading profile...", "Downloading config...", "Ready."])
	var status := stage_messages[clampi(_boot_stage - 1, 0, stage_messages.size() - 1)] if _boot_stage >= 1 else ""
	var messages := ["RELAY ZERO", "v0.1.0", "", status]
	if _error_message:
		messages.append(_error_message)
		messages.append("Running in offline mode - no rewards will be saved.")
	for i in range(messages.size()):
		if messages[i]:
			var color := Color(0.0, 0.8, 1.0) if i == 0 else Color(0.6, 0.6, 0.6)
			draw_string(font, center + Vector2(-180, -80 + i * 30), messages[i], HORIZONTAL_ALIGNMENT_LEFT, -1, fsize, color)
