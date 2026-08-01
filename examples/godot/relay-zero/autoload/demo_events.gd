extends Node

class EventEntry:
	var timestamp: float
	var category: String
	var operation: String
	var detail: String
	var response_time_ms: int
	var success: bool

	func _init(p_category: String, p_operation: String, p_detail: String, p_response_time_ms: int, p_success: bool) -> void:
		timestamp = Time.get_ticks_msec() / 1000.0
		category = p_category
		operation = p_operation
		detail = p_detail
		response_time_ms = p_response_time_ms
		success = p_success


## Newline-delimited JSON so a run can be reviewed after the process exits.
## The in-memory ring only survives while the game is running.
##
## One file per session, never a shared one: a client and a dedicated server
## (or two clients) run as separate processes against the same user:// dir, and
## Godot has no append mode - each FileAccess carries its own offset, so
## concurrent writers interleave and corrupt each other's lines.
const LOG_DIR := "user://events"
const MAX_SESSION_FILES := 20

var events: Array[EventEntry] = []
var operation_counts: Dictionary = {}
var total_operations: int = 0
var _max_events: int = 200
var _log: FileAccess = null
var _session_id: String = ""
var _log_path: String = ""

signal event_recorded(entry: EventEntry)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_open_log()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_PREDELETE:
		_close_log()


func record(category: String, operation: String, detail: String, response_time_ms: int, success: bool) -> void:
	var entry := EventEntry.new(category, operation, detail, response_time_ms, success)
	events.append(entry)
	if events.size() > _max_events:
		events.pop_front()
	total_operations += 1
	if not operation_counts.has(category):
		operation_counts[category] = 0
	operation_counts[category] += 1
	_write_line({
		"t": Time.get_datetime_string_from_system(true),
		"uptime": entry.timestamp,
		"kind": "event",
		"category": category,
		"operation": operation,
		"detail": detail,
		"ms": response_time_ms,
		"ok": success,
	})
	event_recorded.emit(entry)


## Record a non-Crux milestone (match start/end, state changes) in the same stream.
func record_note(kind: String, fields: Dictionary) -> void:
	var line := {
		"t": Time.get_datetime_string_from_system(true),
		"uptime": Time.get_ticks_msec() / 1000.0,
		"kind": kind,
	}
	line.merge(fields, true)
	_write_line(line)


func get_log_path() -> String:
	return ProjectSettings.globalize_path(_log_path)


func get_log_dir() -> String:
	return ProjectSettings.globalize_path(LOG_DIR)


func _open_log() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(LOG_DIR))
	var role := "server" if OS.has_feature("dedicated_server") else "client"
	_session_id = "%s-%s-%d" % [
		role,
		Time.get_datetime_string_from_system(true).replace(":", "").replace("-", ""),
		OS.get_process_id(),
	]
	_log_path = "%s/%s.jsonl" % [LOG_DIR, _session_id]
	_log = FileAccess.open(_log_path, FileAccess.WRITE)
	if _log == null:
		push_warning("DemoEvents: could not open %s; events stay in memory only." % _log_path)
		return
	_prune_old_sessions()
	record_note("session_start", {
		"session": _session_id,
		"role": role,
		"version": ProjectSettings.get_setting("application/config/version", "0.0.0"),
		"headless": DisplayServer.get_name() == "headless",
	})


func _prune_old_sessions() -> void:
	var names := DirAccess.get_files_at(ProjectSettings.globalize_path(LOG_DIR))
	var logs: Array[String] = []
	for name in names:
		if name.ends_with(".jsonl"):
			logs.append(name)
	if logs.size() <= MAX_SESSION_FILES:
		return
	logs.sort()  # session ids are timestamp-prefixed, so lexical order is chronological
	for i in range(logs.size() - MAX_SESSION_FILES):
		DirAccess.remove_absolute(ProjectSettings.globalize_path("%s/%s" % [LOG_DIR, logs[i]]))


func _write_line(line: Dictionary) -> void:
	if _log == null:
		return
	if not line.has("session"):
		line["session"] = _session_id
	_log.store_line(JSON.stringify(line))
	_log.flush()


func _close_log() -> void:
	if _log == null:
		return
	record_note("session_end", {"total_operations": total_operations})
	_log.close()
	_log = null


func get_recent(count: int = 20) -> Array:
	var result: Array = []
	var start := maxi(0, events.size() - count)
	for i in range(start, events.size()):
		result.append(events[i])
	return result


func get_summary() -> Dictionary:
	return {
		"total_operations": total_operations,
		"counts": operation_counts,
		"recent": get_recent(5),
	}


func get_post_run_summary() -> Dictionary:
	var counts := {
		"AUTH": operation_counts.get("AUTH", 0),
		"PLAYER_DATA": operation_counts.get("PLAYER_DATA", 0),
		"MATCHMAKING": operation_counts.get("MATCHMAKING", 0),
		"SERVER": operation_counts.get("SERVER", 0),
		"LIVE_CONFIG": operation_counts.get("LIVE_CONFIG", 0),
		"ECONOMY": operation_counts.get("ECONOMY", 0),
		"LEADERBOARD": operation_counts.get("LEADERBOARD", 0),
	}
	return counts


func clear() -> void:
	events.clear()
	operation_counts.clear()
	total_operations = 0
