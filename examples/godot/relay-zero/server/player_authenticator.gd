class_name PlayerAuthenticator
extends RefCounted


static func authenticate(
	request: GameProtocol.JoinRequest,
	expected_match_id: String,
	expected_join_token: String,
	allow_insecure_dev: bool,
) -> Dictionary:
	if request.player_token.is_empty():
		return {"verified": false, "error": "missing_player_token"}
	var identity := await CruxSession.verify_player_token(request.player_token)
	if identity.has("error"):
		return {"verified": false, "error": identity.get("error", "token_invalid")}
	if bool(identity.get("revoked", false)):
		return {"verified": false, "error": "token_revoked"}
	var verified_player_id := str(identity.get("player_id", ""))
	if verified_player_id.is_empty():
		return {"verified": false, "error": "token_has_no_player_id"}
	if not request.player_id.is_empty() and request.player_id != verified_player_id:
		return {"verified": false, "error": "player_id_mismatch"}
	if not expected_match_id.is_empty() and request.match_id != expected_match_id:
		return {"verified": false, "error": "match_id_mismatch"}
	if not expected_join_token.is_empty():
		if not _constant_time_equal(request.join_token, expected_join_token):
			return {"verified": false, "error": "join_token_invalid"}
	elif not allow_insecure_dev:
		return {"verified": false, "error": "join_token_verifier_not_configured"}
	return {
		"verified": true,
		"player_id": verified_player_id,
		"project_id": str(identity.get("project_id", "")),
		"environment_id": str(identity.get("environment_id", "")),
		"display_name": str(identity.get("display_name", "")),
	}


static func _constant_time_equal(left: String, right: String) -> bool:
	var difference := left.length() ^ right.length()
	var count := maxi(left.length(), right.length())
	for index in range(count):
		var left_code := left.unicode_at(index) if index < left.length() else 0
		var right_code := right.unicode_at(index) if index < right.length() else 0
		difference |= left_code ^ right_code
	return difference == 0
