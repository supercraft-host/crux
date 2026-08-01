extends Node2D

var room_id: String = ""
var room_size: Vector2 = Vector2(16, 8)
var exits: Array = []
var connections: Array = []


func _ready() -> void:
	draw_room_outline()


func initialize(p_room_id: String, p_size: Vector2) -> void:
	room_id = p_room_id
	room_size = p_size


func add_exit(direction: Vector2, position: Vector2) -> void:
	exits.append({"direction": direction, "position": position})


func draw_room_outline() -> void:
	queue_redraw()


func _draw() -> void:
	var half := room_size * 8.0
	var color := Color(0.15, 0.15, 0.18, 1.0)
	draw_rect(Rect2(-half, room_size * 16.0), color, false, 1.0)
