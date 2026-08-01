extends Control

@onready var title_label: Label = $VBoxContainer/TitleLabel
@onready var stats_container: VBoxContainer = $VBoxContainer/StatsContainer
@onready var play_again_button: Button = $VBoxContainer/ActionButtons/PlayAgainButton
@onready var source_button: Button = $VBoxContainer/ActionButtons/SourceButton
@onready var architecture_button: Button = $VBoxContainer/ActionButtons/ArchitectureButton


func _ready() -> void:
	play_again_button.pressed.connect(_on_play_again)
	source_button.pressed.connect(_on_source)
	architecture_button.pressed.connect(_on_architecture)
	_display_results()


func _display_results() -> void:
	var result := AppState.last_match_result
	var summary := DemoEvents.get_post_run_summary()
	var success := bool(result.get("team_survived", false))
	title_label.text = "MISSION COMPLETE" if success else "MISSION ABORTED"
	if AppState.is_offline():
		title_label.text += " [OFFLINE]"
	var time_ms := int(result.get("time_ms", 0))
	var minutes := int(time_ms / 60000)
	var seconds := int(time_ms / 1000) % 60
	var stats_text := ""
	stats_text += "Cores Recovered: %d\n" % int(result.get("cores_recovered", 0))
	stats_text += "Time: %d:%02d\n" % [minutes, seconds]
	stats_text += "Team Survived: %s\n" % ("yes" if success else "no")
	stats_text += "Difficulty: %.2fx\n" % float(result.get("difficulty_multiplier", 1.0))
	stats_text += "Signal: %d\n" % int(result.get("signal", 0))
	stats_text += "Modifier: %s\n" % LiveConfig.get_modifier_name()
	stats_text += "\n--- Crux Operations ---\n"
	stats_text += "Auth: %d | Data: %d | Matchmaking: %d\n" % [summary.get("AUTH", 0), summary.get("PLAYER_DATA", 0), summary.get("MATCHMAKING", 0)]
	stats_text += "Server: %d | Config: %d | Economy: %d | Boards: %d\n" % [summary.get("SERVER", 0), summary.get("LIVE_CONFIG", 0), summary.get("ECONOMY", 0), summary.get("LEADERBOARD", 0)]
	var label := RichTextLabel.new()
	label.text = stats_text
	label.fit_content = true
	stats_container.add_child(label)


func _on_play_again() -> void:
	DemoEvents.clear()
	AppState.last_match_result = {}
	if AppState.is_offline():
		AppState.transition_to(AppState.State.OFFLINE_TRAINING)
		get_tree().change_scene_to_file("res://client/match/match_scene.tscn")
	else:
		get_tree().change_scene_to_file("res://client/menus/main_menu.tscn")


func _on_source() -> void:
	OS.shell_open("https://github.com/supercraft-host/relay-zero")


func _on_architecture() -> void:
	AppState.architecture_mode = not AppState.architecture_mode
