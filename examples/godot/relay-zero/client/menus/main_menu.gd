extends Control

@onready var title_label: Label = $VBoxContainer/TitleLabel
@onready var callsign_label: Label = $VBoxContainer/CallsignLabel
@onready var play_button: Button = $VBoxContainer/Buttons/PlayButton
@onready var server_browser_button: Button = $VBoxContainer/Buttons/ServerBrowserButton
@onready var loadout_button: Button = $VBoxContainer/Buttons/LoadoutButton
@onready var leaderboard_button: Button = $VBoxContainer/Buttons/LeaderboardButton
@onready var settings_button: Button = $VBoxContainer/Buttons/SettingsButton
@onready var region_selector: OptionButton = $VBoxContainer/RegionSelector
@onready var mode_selector: OptionButton = $VBoxContainer/ModeSelector
@onready var module_selector: OptionButton = $VBoxContainer/Loadout/ModuleSelector
@onready var consumable_selector: OptionButton = $VBoxContainer/Loadout/ConsumableSelector
@onready var signal_label: Label = $VBoxContainer/SignalLabel
@onready var daily_event_label: Label = $VBoxContainer/DailyEventLabel
@onready var version_label: Label = $VBoxContainer/VersionLabel
@onready var dev_mode_checkbox: CheckBox = $VBoxContainer/DevModeCheckBox

var _is_joining: bool = false


func _ready() -> void:
	_setup_ui()
	_populate_regions()
	_populate_gamemodes()
	_populate_loadout()
	_refresh_economy()
	_update_modifier_display()


func _setup_ui() -> void:
	title_label.text = "RELAY ZERO"
	callsign_label.text = AppState.display_name if not AppState.display_name.is_empty() else "Operator"
	play_button.pressed.connect(_on_play_pressed)
	server_browser_button.pressed.connect(_on_server_browser_pressed)
	loadout_button.pressed.connect(_on_loadout_pressed)
	leaderboard_button.pressed.connect(_on_leaderboard_pressed)
	settings_button.pressed.connect(_on_settings_pressed)
	dev_mode_checkbox.toggled.connect(_on_dev_mode_toggled)
	version_label.text = "v0.1.0 | Config: %s | Modifier: %s" % [LiveConfig.get_version(), LiveConfig.get_modifier_name()]


func _populate_regions() -> void:
	region_selector.clear()
	for region_id in SharedResources.REGIONS:
		region_selector.add_item(SharedResources.REGIONS[region_id])
		if region_id == AppState.selected_region:
			region_selector.select(region_selector.item_count - 1)
	region_selector.item_selected.connect(func(idx: int):
		var keys := SharedResources.REGIONS.keys()
		if idx < keys.size():
			AppState.selected_region = keys[idx]
	)


func _populate_gamemodes() -> void:
	mode_selector.clear()
	for mode_id in SharedResources.GAME_MODES:
		mode_selector.add_item(SharedResources.GAME_MODES[mode_id])
	mode_selector.item_selected.connect(func(idx: int):
		var keys := SharedResources.GAME_MODES.keys()
		if idx < keys.size():
			AppState.selected_mode = keys[idx]
	)


func _populate_loadout() -> void:
	module_selector.clear()
	for module_id in SharedResources.MODULES:
		var data: Dictionary = SharedResources.MODULES[module_id]
		module_selector.add_item("%s (%d signal)" % [data["name"], data.get("cost", 0)])
	module_selector.item_selected.connect(func(idx: int):
		var keys := SharedResources.MODULES.keys()
		if idx < keys.size():
			AppState.active_module = keys[idx]
	)
	consumable_selector.clear()
	consumable_selector.add_item("None")
	for item_id in SharedResources.CONSUMABLES:
		var data: Dictionary = SharedResources.CONSUMABLES[item_id]
		consumable_selector.add_item("%s (%d signal)" % [data["name"], data.get("cost", 0)])
	consumable_selector.item_selected.connect(func(idx: int):
		if idx == 0:
			AppState.active_consumable = ""
		else:
			var keys := SharedResources.CONSUMABLES.keys()
			if idx - 1 < keys.size():
				AppState.active_consumable = keys[idx - 1]
	)


func _refresh_economy() -> void:
	var economy := await CruxSession.get_player_economy(AppState.player_id)
	# Crux omits balances entirely for a player with no economy record yet, and
	# keys entries by "Key"/"Amount" rather than currency_id/amount.
	var balances = economy.get("balances")
	if balances is Array:
		for balance in balances:
			if not (balance is Dictionary):
				continue
			if str(balance.get("Key", balance.get("key", ""))) == "signal":
				signal_label.text = "Signal: %d" % int(balance.get("Amount", balance.get("amount", 0)))
				return
	signal_label.text = "Signal: ---"


func _update_modifier_display() -> void:
	var event := LiveConfig.get_daily_event()
	if event.get("id", "none") != "none":
		daily_event_label.text = "%s (x%.2f rewards)" % [event["name"], event.get("reward_multiplier", 1.0)]
		daily_event_label.modulate = Color(0.0, 0.8, 1.0)
	else:
		daily_event_label.text = "Standard conditions"
		daily_event_label.modulate = Color(0.5, 0.5, 0.5)


func _on_play_pressed() -> void:
	if _is_joining:
		return
	_is_joining = true
	play_button.disabled = true
	play_button.text = "SEARCHING..."
	AppState.transition_to(AppState.State.MATCHMAKING)
	var result := await CruxSession.join_matchmaking(AppState.player_id, AppState.selected_mode, AppState.selected_region)
	if result.has("error"):
		show_error("Matchmaking failed: %s" % result.get("error", "unknown"))
		_is_joining = false
		play_button.disabled = false
		play_button.text = "PLAY"
		AppState.transition_to(AppState.State.MAIN_MENU)
		return
	var poll_start := Time.get_ticks_msec()
	var max_wait := 8000
	while Time.get_ticks_msec() - poll_start < max_wait:
		var status := await CruxSession.poll_matchmaking()
		var st: String = status.get("status", "")
		play_button.text = "MATCHING..."
		if st == "matched":
			_on_matched(status.get("match", {}))
			return
		await get_tree().create_timer(0.5).timeout
	_on_timeout()


func _on_matched(match: Dictionary) -> void:
	var connect_url: String = match.get("connect_url", "")
	var join_token: String = match.get("join_token", "")
	var match_id: String = match.get("match_id", "")
	if connect_url.is_empty():
		_on_timeout()
		return
	AppState.set_match_info(match_id, join_token, connect_url)
	AppState.transition_to(AppState.State.CONNECTING)
	get_tree().change_scene_to_file("res://client/match/match_scene.tscn")


func _on_timeout() -> void:
	show_error("No match found. Entering solo training...")
	await get_tree().create_timer(2.0).timeout
	AppState.run_mode = AppState.RunMode.OFFLINE
	AppState.transition_to(AppState.State.OFFLINE_TRAINING)
	get_tree().change_scene_to_file("res://client/match/match_scene.tscn")


func _on_server_browser_pressed() -> void:
	print("Server browser not yet implemented")


func _on_loadout_pressed() -> void:
	print("Loadout customization not yet implemented")


func _on_leaderboard_pressed() -> void:
	print("Leaderboard view not yet implemented")


func _on_settings_pressed() -> void:
	print("Settings not yet implemented")


func _on_dev_mode_toggled(enabled: bool) -> void:
	AppState.developer_mode = enabled


func show_error(msg: String) -> void:
	print("ERROR: " + msg)
	play_button.text = "ERROR - RETRY?"
	play_button.disabled = false
	_is_joining = false
	AppState.transition_to(AppState.State.MAIN_MENU)
