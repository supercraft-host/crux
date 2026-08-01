extends Control

@onready var health_bar: ProgressBar = $HBoxContainer/HealthBar
@onready var signal_label: Label = $HBoxContainer/SignalLabel
@onready var core_indicator: Label = $HBoxContainer/CoreIndicator
@onready var timer_label: Label = $HBoxContainer/TimerLabel
@onready var phase_label: Label = $HBoxContainer/PhaseLabel
@onready var objective_text: Label = $MarginContainer/ObjectiveText
@onready var pressure_indicator: HBoxContainer = $HBoxContainer/PressureIndicator
@onready var event_log: RichTextLabel = $Panel/EventLog


func _ready() -> void:
	var dev_overlay_scene := load("res://client/developer_overlay/dev_overlay.tscn")
	if dev_overlay_scene:
		add_child(dev_overlay_scene.instantiate())
	update_health(100.0, 100.0)
	update_pressure(0)


func apply_snapshot(snapshot: GameProtocol.WorldSnapshot, local_player_id: int) -> void:
	update_timer(snapshot.time_remaining)
	update_signal(snapshot.signal_earned)
	update_pressure(snapshot.pressure_level)
	update_cores(snapshot.cores_recovered, 3)
	update_phase(snapshot.phase)
	var carrying := false
	for obj in snapshot.objects:
		if obj.object_id == local_player_id:
			update_health(obj.health, obj.max_health)
			carrying = obj.carrying > 0
	show_core_carried(carrying)


func update_timer(time_remaining: float) -> void:
	var minutes := int(time_remaining / 60.0)
	var seconds := int(fmod(time_remaining, 60.0))
	timer_label.text = "%d:%02d" % [minutes, seconds]
	timer_label.modulate = Color(1, 0.2, 0.2) if time_remaining < 60.0 else Color.WHITE


func update_health(current: float, maximum: float) -> void:
	health_bar.max_value = maximum
	health_bar.value = current


func update_signal(amount: int) -> void:
	signal_label.text = "Signal: %d" % amount


func update_pressure(level: int) -> void:
	for child in pressure_indicator.get_children():
		child.queue_free()
	for index in range(5):
		var bar := ColorRect.new()
		bar.custom_minimum_size = Vector2(6, 16)
		bar.color = Color(1, 0.3, 0.1) if index < level else Color(0.2, 0.2, 0.2)
		pressure_indicator.add_child(bar)


func update_cores(count: int, total: int) -> void:
	core_indicator.text = "Cores: %d/%d" % [count, total]
	objective_text.text = "Carry the yellow core to the blue relay. Press E to interact."


func update_phase(phase: int) -> void:
	match phase:
		GameProtocol.MatchPhase.DEPLOYING: phase_label.text = "DEPLOYING"
		GameProtocol.MatchPhase.RECOVERING: phase_label.text = "RECOVER"
		GameProtocol.MatchPhase.ESCALATING: phase_label.text = "ESCALATE"
		GameProtocol.MatchPhase.EXTRACTING:
			phase_label.text = "EXTRACT!"
			objective_text.text = "Reach the green extraction beacon and press E."
		GameProtocol.MatchPhase.COMPLETE: phase_label.text = "COMPLETE"
		GameProtocol.MatchPhase.ABORTED: phase_label.text = "ABORTED"


func show_core_carried(is_carrying: bool) -> void:
	core_indicator.modulate = Color(1, 0.8, 0.2) if is_carrying else Color.WHITE
	if is_carrying and "[CARRYING]" not in core_indicator.text:
		core_indicator.text += " [CARRYING]"
