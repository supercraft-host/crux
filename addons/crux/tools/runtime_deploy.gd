extends SceneTree

## Headless Godot Runtime deployment helper.
##
## Run from a Godot project containing addons/crux:
##
##   godot --headless --path . --script addons/crux/tools/runtime_deploy.gd -- \
##     --artifact .godot/export/server.zip --version relay-zero-1 \
##     --entrypoint server/game.x86_64 --player-id canary-player
##
## CRUX_RUNTIME_CONTROL_KEY, CRUX_PROJECT_ID, CRUX_ENVIRONMENT_ID, and
## CRUX_RUNTIME_API_URL are read from the environment. The control key is never
## written to the project or printed by this script.

var _crux: Node


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var artifact := _option(args, "--artifact", "")
	var version := _option(args, "--version", "local-" + str(Time.get_unix_time_from_system()))
	var entrypoint := _option(args, "--entrypoint", "server/game.x86_64")
	var player_id := _option(args, "--player-id", "")
	var timeout := int(_option(args, "--timeout-seconds", "300"))
	var base_url := OS.get_environment("CRUX_RUNTIME_API_URL")
	var project_id := OS.get_environment("CRUX_PROJECT_ID")
	var environment_id := OS.get_environment("CRUX_ENVIRONMENT_ID")
	var control_key := OS.get_environment("CRUX_RUNTIME_CONTROL_KEY")
	if artifact.is_empty() or project_id.is_empty() or environment_id.is_empty() or control_key.is_empty():
		push_error("Runtime deploy needs --artifact plus CRUX_PROJECT_ID, CRUX_ENVIRONMENT_ID, and CRUX_RUNTIME_CONTROL_KEY")
		quit(2)
		return
	if base_url.is_empty():
		base_url = "https://gsb.supercraft.host"

	_crux = preload("res://addons/crux/crux.gd").new()
	root.add_child(_crux)
	_crux.init_runtime_control(base_url, project_id, environment_id, control_key)
	var result: Dictionary = await _crux.deploy_runtime_zip(artifact, version, entrypoint, {}, player_id, timeout)
	if result.is_empty():
		quit(1)
		return
	print(JSON.stringify(result))
	var session: Dictionary = result.get("session", {})
	if str(session.get("state", "")) != "ready":
		quit(1)
		return
	var session_id := str(session.get("id", ""))
	if not session_id.is_empty():
		var logs: Array = await _crux.get_runtime_session_logs(session_id)
		print(JSON.stringify({"session_id": session_id, "logs": logs}))
		await _crux.stop_runtime_session(session_id)
	quit(0)


func _option(args: PackedStringArray, name: String, fallback: String) -> String:
	var index := args.find(name)
	if index >= 0 and index + 1 < args.size():
		return args[index + 1]
	return fallback
