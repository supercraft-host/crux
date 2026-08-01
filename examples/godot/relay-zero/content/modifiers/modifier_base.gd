extends RefCounted

var modifier_id: String = ""
var name: String = ""
var starts_at: String = ""
var ends_at: String = ""
var visibility: float = 1.0
var enemy_speed: float = 1.0
var reward_multiplier: float = 1.0
var enemy_spawn_rate: float = 1.0
var item_drop_rate: float = 1.0
var match_time_multiplier: float = 1.0


func apply_to_config(config: LiveConfig) -> void:
	var event := config.get_daily_event()
	visibility = event.get("visibility", 1.0)
	enemy_speed = event.get("enemy_speed", 1.0)
	reward_multiplier = event.get("reward_multiplier", 1.0)
	enemy_spawn_rate = event.get("enemy_spawn_rate", 1.0)
	item_drop_rate = event.get("item_drop_rate", 1.0)
	match_time_multiplier = event.get("match_time_multiplier", 1.0)
	modifier_id = event.get("id", "none")
	name = event.get("name", "Standard Protocol")
