class_name GameProtocol
extends RefCounted

enum InputType {
	NONE,
	MOVE,
	AIM,
	PRIMARY_TOOL,
	SECONDARY_TOOL,
	DASH,
	INTERACT,
	USE_MODULE,
}

enum ObjectType {
	INVALID,
	PLAYER,
	ENEMY_COMMON,
	ENEMY_FAST,
	ENEMY_HEAVY,
	ENEMY_ARTILLERY,
	ENEMY_SHIELDER,
	ENEMY_SWARM,
	ENEMY_ELITE_ASSASSIN,
	ENEMY_ELITE_JUGGERNAUT,
	DATA_CORE,
	RELAY_TOWER,
	EXTRACTION_BEACON,
	PROJECTILE,
	PICKUP,
}

enum MatchPhase {
	WAITING,
	DEPLOYING,
	RECOVERING,
	ESCALATING,
	EXTRACTING,
	COMPLETE,
	ABORTED,
}

enum SectorState {
	INACTIVE,
	TRACKING,
	CORE_EXPOSED,
	CORE_CARRIED,
	SYNCHRONIZING,
	COMPLETE,
}

const HEADER_SIZE := 12

class InputFrame:
	var tick: int
	var player_id: int
	var input_type: int
	var move_dir: Vector2
	var aim_dir: Vector2
	var pressed: bool

	func _init(p_tick: int, p_player_id: int, p_input_type: int, p_move_dir: Vector2, p_aim_dir: Vector2, p_pressed: bool) -> void:
		tick = p_tick
		player_id = p_player_id
		input_type = p_input_type
		move_dir = p_move_dir
		aim_dir = p_aim_dir
		pressed = p_pressed

	func to_dict() -> Dictionary:
		return {
			"tick": tick,
			"pid": player_id,
			"type": input_type,
			"mx": move_dir.x,
			"my": move_dir.y,
			"ax": aim_dir.x,
			"ay": aim_dir.y,
			"p": pressed,
		}

	static func from_dict(d: Dictionary) -> InputFrame:
		return InputFrame.new(
			d.get("tick", 0),
			d.get("pid", 0),
			d.get("type", 0),
			Vector2(d.get("mx", 0.0), d.get("my", 0.0)),
			Vector2(d.get("ax", 0.0), d.get("ay", 0.0)),
			d.get("p", false),
		)


class ObjectState:
	var object_id: int
	var object_type: int
	var position: Vector2
	var rotation: float
	var health: float
	var max_health: float
	var velocity: Vector2
	var is_alive: bool
	var carrying: int
	var carried_by: int
	var metadata: Dictionary

	func _init() -> void:
		object_id = 0
		object_type = ObjectType.INVALID
		position = Vector2.ZERO
		rotation = 0.0
		health = 100.0
		max_health = 100.0
		velocity = Vector2.ZERO
		is_alive = true
		carrying = 0
		carried_by = 0
		metadata = {}

	func to_dict() -> Dictionary:
		return {
			"id": object_id,
			"t": object_type,
			"x": position.x,
			"y": position.y,
			"r": rotation,
			"hp": health,
			"mhp": max_health,
			"vx": velocity.x,
			"vy": velocity.y,
			"a": is_alive,
			"cr": carrying,
			"cb": carried_by,
			"m": metadata,
		}

	static func from_dict(d: Dictionary) -> ObjectState:
		var s := ObjectState.new()
		s.object_id = d.get("id", 0)
		s.object_type = d.get("t", ObjectType.INVALID)
		s.position = Vector2(d.get("x", 0.0), d.get("y", 0.0))
		s.rotation = d.get("r", 0.0)
		s.health = d.get("hp", 100.0)
		s.max_health = d.get("mhp", 100.0)
		s.velocity = Vector2(d.get("vx", 0.0), d.get("vy", 0.0))
		s.is_alive = d.get("a", true)
		s.carrying = d.get("cr", 0)
		s.carried_by = d.get("cb", 0)
		s.metadata = d.get("m", {})
		return s


class WorldSnapshot:
	var tick: int
	var phase: int
	var objects: Array[ObjectState]
	var pressure_level: int
	var cores_recovered: int
	var signal_earned: int
	var time_remaining: float
	var modifier_id: String
	var config_version: String

	func _init() -> void:
		tick = 0
		phase = MatchPhase.WAITING
		objects = []
		pressure_level = 0
		cores_recovered = 0
		signal_earned = 0
		time_remaining = 300.0
		modifier_id = ""
		config_version = ""

	func to_dict() -> Dictionary:
		var obj_arr: Array = []
		for o in objects:
			obj_arr.append(o.to_dict())
		return {
			"tick": tick,
			"phase": phase,
			"objects": obj_arr,
			"pressure": pressure_level,
			"cores": cores_recovered,
			"signal": signal_earned,
			"time": time_remaining,
			"modifier": modifier_id,
			"config": config_version,
		}

	static func from_dict(d: Dictionary) -> WorldSnapshot:
		var s := WorldSnapshot.new()
		s.tick = d.get("tick", 0)
		s.phase = d.get("phase", MatchPhase.WAITING)
		var objs: Array = d.get("objects", [])
		for o in objs:
			s.objects.append(ObjectState.from_dict(o))
		s.pressure_level = d.get("pressure", 0)
		s.cores_recovered = d.get("cores", 0)
		s.signal_earned = d.get("signal", 0)
		s.time_remaining = d.get("time", 300.0)
		s.modifier_id = d.get("modifier", "")
		s.config_version = d.get("config", "")
		return s


class MatchResult:
	var match_id: String
	var players: Array
	var cores_recovered: int
	var time_taken: float
	var party_size: int
	var difficulty_multiplier: float
	var modifier_id: String
	var signal_earned: int
	var items_found: Array
	var team_survived: bool
	var run_id: String

	func to_dict() -> Dictionary:
		return {
			"match_id": match_id,
			"players": players,
			"cores_recovered": cores_recovered,
			"time_ms": int(time_taken * 1000),
			"party_size": party_size,
			"difficulty_multiplier": difficulty_multiplier,
			"modifier": modifier_id,
			"signal": signal_earned,
			"items": items_found,
			"team_survived": team_survived,
			"run_id": run_id,
		}


class JoinRequest:
	var player_id: String
	var player_token: String
	var join_token: String
	var match_id: String
	var display_name: String
	var module: String
	var consumable: String

	func to_dict() -> Dictionary:
		return {
			"player_id": player_id,
			"token": player_token,
			"join_token": join_token,
			"match_id": match_id,
			"name": display_name,
			"module": module,
			"consumable": consumable,
		}

	static func from_dict(d: Dictionary) -> JoinRequest:
		var r := JoinRequest.new()
		r.player_id = d.get("player_id", "")
		r.player_token = d.get("token", "")
		r.join_token = d.get("join_token", "")
		r.match_id = d.get("match_id", "")
		r.display_name = d.get("name", "")
		r.module = d.get("module", "")
		r.consumable = d.get("consumable", "")
		return r
