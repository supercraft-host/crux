extends Node3D

# Stub scene for enemy entities
var enemy_type: String = "common"
var health: float = 100.0
var speed: float = 120.0

func _ready() -> void:
	print("Enemy Base: %s spawned at %s" % [enemy_type, position])
