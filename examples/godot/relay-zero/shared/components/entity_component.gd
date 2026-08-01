class_name EntityComponent
extends Node2D

var object_type: int = GameProtocol.ObjectType.INVALID
var object_id: int = 0
var target_position: Vector2 = Vector2.ZERO
var target_rotation: float = 0.0
var is_local_player: bool = false
var is_alive: bool = true
var metadata: Dictionary = {}


func _ready() -> void:
	z_index = 5
	queue_redraw()


func _process(delta: float) -> void:
	var speed := 18.0 if is_local_player else 10.0
	position = position.lerp(target_position, minf(1.0, delta * speed))
	rotation = lerp_angle(rotation, target_rotation, minf(1.0, delta * speed))


func apply_state(state: GameProtocol.ObjectState) -> void:
	object_type = state.object_type
	object_id = state.object_id
	target_position = state.position
	target_rotation = state.rotation
	is_alive = state.is_alive
	metadata = state.metadata.duplicate(true)
	if position == Vector2.ZERO and target_position != Vector2.ZERO:
		position = target_position
	visible = is_alive or object_type == GameProtocol.ObjectType.RELAY_TOWER
	queue_redraw()


func _draw() -> void:
	match object_type:
		GameProtocol.ObjectType.PLAYER:
			var player_color := Color(0.2, 0.95, 1.0) if is_local_player else Color(0.55, 0.75, 0.85)
			if bool(metadata.get("is_bot", false)):
				player_color = Color(0.55, 0.55, 0.65)
			draw_circle(Vector2.ZERO, 14.0, player_color)
			draw_line(Vector2.ZERO, Vector2.RIGHT * 22.0, Color.WHITE, 3.0)
		GameProtocol.ObjectType.DATA_CORE:
			var points := PackedVector2Array([Vector2(0, -13), Vector2(13, 0), Vector2(0, 13), Vector2(-13, 0)])
			draw_colored_polygon(points, Color(1.0, 0.78, 0.15))
		GameProtocol.ObjectType.RELAY_TOWER:
			var completed := bool(metadata.get("complete", false))
			var relay_color := Color(0.2, 0.9, 0.45) if completed else Color(0.25, 0.55, 1.0)
			draw_rect(Rect2(-18, -18, 36, 36), relay_color, false, 5.0)
			draw_circle(Vector2.ZERO, 6.0, relay_color)
		GameProtocol.ObjectType.EXTRACTION_BEACON:
			draw_circle(Vector2.ZERO, 34.0, Color(0.2, 1.0, 0.7, 0.22))
			draw_arc(Vector2.ZERO, 34.0, 0.0, TAU, 48, Color(0.2, 1.0, 0.7), 5.0)
		GameProtocol.ObjectType.PROJECTILE:
			draw_circle(Vector2.ZERO, 4.0, Color(0.85, 0.95, 1.0))
		_:
			draw_circle(Vector2.ZERO, 10.0, Color(1.0, 0.25, 0.25))


func get_type_name() -> String:
	match object_type:
		GameProtocol.ObjectType.PLAYER: return "Player"
		GameProtocol.ObjectType.DATA_CORE: return "Data Core"
		GameProtocol.ObjectType.RELAY_TOWER: return "Relay Tower"
		GameProtocol.ObjectType.EXTRACTION_BEACON: return "Extraction Beacon"
	return "Unknown"
