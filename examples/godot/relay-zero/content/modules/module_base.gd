extends Node2D

var module_id: String = ""
var cooldown: float = 0.0
var duration: float = 0.0
var is_active: bool = false
var owner_player_id: int = 0


func activate() -> bool:
	return false


func deactivate() -> void:
	is_active = false


func tick(delta: float) -> void:
	if is_active and duration > 0:
		duration -= delta
		if duration <= 0:
			deactivate()
