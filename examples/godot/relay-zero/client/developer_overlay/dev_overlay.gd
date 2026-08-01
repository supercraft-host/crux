extends Control

@onready var event_log: RichTextLabel = $Panel/VBoxContainer/EventLog
@onready var summary_label: Label = $Panel/VBoxContainer/SummaryLabel
@onready var mode_label: Label = $Panel/VBoxContainer/ModeLabel
@onready var close_button: Button = $Panel/VBoxContainer/CloseButton

var _is_open: bool = false
var _mode: int = 0


func _ready() -> void:
	hide()
	DemoEvents.event_recorded.connect(_on_event_recorded)
	close_button.pressed.connect(_on_close_pressed)


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_panel"):
		_toggle()


func _toggle() -> void:
	_is_open = not _is_open
	if _is_open:
		show()
		_refresh_log()
	else:
		hide()


func _on_event_recorded(entry: DemoEvents.EventEntry) -> void:
	if _is_open:
		var symbol := "[color=green]✓[/color]" if entry.success else "[color=red]✗[/color]"
		var color := "gray"
		match entry.category:
			"AUTH": color = "cyan"
			"PLAYER_DATA": color = "green"
			"MATCHMAKING": color = "yellow"
			"SERVER": color = "orange"
			"LIVE_CONFIG": color = "purple"
			"ECONOMY": color = "gold"
			"LEADERBOARD": color = "magenta"
		var line := "%s [color=%s][%s][/color] %s" % [symbol, color, entry.category, entry.operation]
		if not entry.detail.is_empty():
			line += "\n    %s" % entry.detail
		if entry.response_time_ms > 0:
			line += " (%dms)" % entry.response_time_ms
		event_log.append_text(line + "\n")


func _refresh_log() -> void:
	event_log.clear()
	var recent := DemoEvents.get_recent(30)
	for entry in recent:
		_on_event_recorded(entry)


func _on_close_pressed() -> void:
	_toggle()


func set_mode(mode: int) -> void:
	_mode = mode
	match mode:
		0:
			mode_label.text = "Player Mode"
			summary_label.hide()
		1:
			mode_label.text = "Developer Mode"
			summary_label.show()
		2:
			mode_label.text = "Architecture Mode"
			summary_label.show()
			summary_label.text = """Godot Web Client
    |
    ├── HTTPS / Player JWT ──> Crux
    |       auth, own documents, leaderboard reads
    |
    └── WSS ────────────────> Godot Dedicated Server
                                      |
                                      └── HTTPS / Server Token ──> Crux
                                              token verification
                                              rewards
                                              progression
                                              score submission
                                              registry heartbeat"""
