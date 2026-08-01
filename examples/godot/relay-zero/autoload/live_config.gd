extends Node

const DEFAULTS_DIR := "res://content/config_defaults/"
const TEMP_BUNDLE_PATH := "user://live_config_download.tmp.zip"
const LAST_KNOWN_GOOD := "user://live_config_last_good.zip"
const REQUIRED_FILES := [
	"manifest.json",
	"balance.json",
	"enemy_table.json",
	"loot_table.json",
	"daily_event.json",
	"map_rotation.json",
]

var _manifest: Dictionary = {}
var _balance: Dictionary = {}
var _enemy_table: Dictionary = {}
var _loot_table: Dictionary = {}
var _daily_event: Dictionary = {}
var _map_rotation: Dictionary = {}
var _bundle_version: String = ""
var _bundle_loaded: bool = false
var _refresh_interval: float = 300.0
var _time_since_refresh: float = 0.0
var _refresh_in_progress: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if not _load_cached_bundle():
		_load_packaged_defaults()


func _process(delta: float) -> void:
	if not AppState.is_client():
		return
	if AppState.current_state not in [AppState.State.MAIN_MENU, AppState.State.MATCHMAKING]:
		return
	_time_since_refresh += delta
	if _time_since_refresh >= _refresh_interval and not _refresh_in_progress:
		_time_since_refresh = 0.0
		refresh.call_deferred()


func refresh() -> bool:
	if _refresh_in_progress:
		return false
	_refresh_in_progress = true
	var bundle := await CruxSession.download_active_config_bundle()
	_refresh_in_progress = false
	if bundle.is_empty():
		return false
	if not _install_bundle(bundle, true):
		DemoEvents.record("LIVE_CONFIG", "Rejected invalid bundle", "last_good=%s" % _bundle_version, 0, false)
		return false
	DemoEvents.record(
		"LIVE_CONFIG",
		"Bundle: %s" % _bundle_version,
		"modifier=%s" % _daily_event.get("id", "none"),
		0,
		true,
	)
	return true


func _install_bundle(bundle: PackedByteArray, persist: bool) -> bool:
	if not _write_bytes(TEMP_BUNDLE_PATH, bundle):
		return false
	var parsed := _parse_zip(TEMP_BUNDLE_PATH)
	if parsed.is_empty():
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEMP_BUNDLE_PATH))
		return false
	_activate(parsed)
	if persist:
		# Only a fully parsed and validated bundle is promoted to last-known-good.
		if not _write_bytes(LAST_KNOWN_GOOD, bundle):
			push_warning("LiveConfig: active bundle could not be cached")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEMP_BUNDLE_PATH))
	return true


func _parse_zip(path: String) -> Dictionary:
	var zip := ZIPReader.new()
	var err := zip.open(path)
	if err != OK:
		push_warning("LiveConfig: cannot open bundle (%d)" % err)
		return {}
	for required_path in REQUIRED_FILES:
		if not zip.file_exists(required_path):
			push_warning("LiveConfig: bundle is missing %s" % required_path)
			zip.close()
			return {}
	var parsed := {
		"manifest": _read_zip_json(zip, "manifest.json"),
		"balance": _read_zip_json(zip, "balance.json"),
		"enemy_table": _read_zip_json(zip, "enemy_table.json"),
		"loot_table": _read_zip_json(zip, "loot_table.json"),
		"daily_event": _read_zip_json(zip, "daily_event.json"),
		"map_rotation": _read_zip_json(zip, "map_rotation.json"),
	}
	zip.close()
	if not _validate(parsed):
		return {}
	return parsed


func _validate(parsed: Dictionary) -> bool:
	var manifest: Dictionary = parsed.get("manifest", {})
	if str(manifest.get("version", "")).is_empty():
		push_warning("LiveConfig: manifest has no version")
		return false
	if not parsed.get("balance", {}).has("base_reward_per_core"):
		push_warning("LiveConfig: balance.json has no base_reward_per_core")
		return false
	if not parsed.get("daily_event", {}).has("id"):
		push_warning("LiveConfig: daily_event.json has no id")
		return false
	return true


func _activate(parsed: Dictionary) -> void:
	_manifest = parsed["manifest"].duplicate(true)
	_balance = parsed["balance"].duplicate(true)
	_enemy_table = parsed["enemy_table"].duplicate(true)
	_loot_table = parsed["loot_table"].duplicate(true)
	_daily_event = parsed["daily_event"].duplicate(true)
	_map_rotation = parsed["map_rotation"].duplicate(true)
	_bundle_version = str(_manifest.get("version", ""))
	_bundle_loaded = true


func _load_cached_bundle() -> bool:
	if not FileAccess.file_exists(LAST_KNOWN_GOOD):
		return false
	var file := FileAccess.open(LAST_KNOWN_GOOD, FileAccess.READ)
	if file == null:
		return false
	var bundle := file.get_buffer(file.get_length())
	file.close()
	return _install_bundle(bundle, false)


func _load_packaged_defaults() -> void:
	var parsed := {
		"manifest": _read_res_json(DEFAULTS_DIR + "manifest.json"),
		"balance": _read_res_json(DEFAULTS_DIR + "balance.json"),
		"enemy_table": _read_res_json(DEFAULTS_DIR + "enemy_table.json"),
		"loot_table": _read_res_json(DEFAULTS_DIR + "loot_table.json"),
		"daily_event": _read_res_json(DEFAULTS_DIR + "daily_event.json"),
		"map_rotation": _read_res_json(DEFAULTS_DIR + "map_rotation.json"),
	}
	if _validate(parsed):
		_activate(parsed)
		return
	push_error("LiveConfig: packaged defaults are invalid")
	_activate({
		"manifest": {"version": "emergency-default"},
		"balance": {"base_reward_per_core": 50},
		"enemy_table": {},
		"loot_table": {},
		"daily_event": {"id": "none", "name": "Standard Protocol", "reward_multiplier": 1.0, "enemy_speed": 1.0, "visibility": 1.0},
		"map_rotation": {"available": ["facility_a"]},
	})


func _read_zip_json(zip: ZIPReader, path: String) -> Dictionary:
	var parsed = JSON.parse_string(zip.read_file(path).get_string_from_utf8())
	return parsed if parsed is Dictionary else {}


func _read_res_json(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var parsed = JSON.parse_string(file.get_as_text())
	file.close()
	return parsed if parsed is Dictionary else {}


func _write_bytes(path: String, bytes: PackedByteArray) -> bool:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_warning("LiveConfig: cannot write %s" % path)
		return false
	file.store_buffer(bytes)
	file.close()
	return true


func is_active() -> bool:
	return _bundle_loaded


func get_manifest() -> Dictionary:
	return _manifest


func get_daily_event() -> Dictionary:
	return _daily_event


func get_balance() -> Dictionary:
	return _balance


func get_enemy_table() -> Dictionary:
	return _enemy_table


func get_loot_table() -> Dictionary:
	return _loot_table


func get_map_rotation() -> Dictionary:
	return _map_rotation


func get_leaderboard_id(key: String) -> String:
	var leaderboards: Dictionary = _manifest.get("leaderboards", {})
	return str(leaderboards.get(key, ""))


func get_modifier_name() -> String:
	return str(_daily_event.get("name", "Standard Protocol"))


func get_reward_multiplier() -> float:
	return float(_daily_event.get("reward_multiplier", 1.0))


func get_enemy_speed_multiplier() -> float:
	return float(_daily_event.get("enemy_speed", 1.0))


func get_visibility_multiplier() -> float:
	return float(_daily_event.get("visibility", 1.0))


func get_version() -> String:
	return _bundle_version
