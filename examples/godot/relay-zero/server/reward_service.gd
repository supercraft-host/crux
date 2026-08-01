class_name RewardService
extends RefCounted

const MAX_REWARD_PER_MATCH := 1000
const XP_PER_LEVEL := 1000


static func grant_rewards(pid: String, result: GameProtocol.MatchResult) -> Dictionary:
	# This claim-before-grant fallback is at-most-once. Production Crux should
	# additionally support a backend idempotency key spanning economy and score
	# writes so a crash after the claim cannot lose a reward.
	var claim := await CruxSession.claim_reward_receipt(pid, result.run_id)
	if claim.has("error"):
		return claim
	var economy_result := await _grant_economy(pid, result)
	if economy_result.has("error"):
		return {"error": "economy_grant_failed", "detail": economy_result}
	var leaderboard_results := await _submit_leaderboards(pid, result)
	var progress_result := await _update_player_records(pid, result)
	return {
		"ok": true,
		"economy": economy_result,
		"leaderboards": leaderboard_results,
		"progression": progress_result,
		"idempotency_key": "run_%s:player_%s:reward" % [result.run_id, pid],
	}


## Advance the lifetime counters and progression that the profile/progression
## documents have carried as zeroes until now. Runs inside the reward claim, so
## a replayed run_id cannot double-count it.
static func _update_player_records(pid: String, result: GameProtocol.MatchResult) -> Dictionary:
	var survived := result.team_survived
	var outcome := {}

	var profile_doc := await CruxSession.get_profile(pid)
	if not profile_doc.has("error"):
		var profile: Dictionary = profile_doc.get("value", {})
		# Always reassign both: JSON round-trips numbers as floats, so a field left
		# untouched on a failed run would persist as 2.0 instead of 2.
		profile["lifetime_runs"] = int(profile.get("lifetime_runs", 0)) + 1
		profile["lifetime_extractions"] = int(profile.get("lifetime_extractions", 0)) + (1 if survived else 0)
		var saved := await CruxSession.save_profile(pid, profile, int(profile_doc.get("version", -1)))
		outcome["profile"] = "conflict" if saved.has("error") else "updated"
		outcome["lifetime_runs"] = profile["lifetime_runs"]
	else:
		outcome["profile"] = "unavailable"

	var progression_doc := await CruxSession.get_progression(pid)
	if not progression_doc.has("error"):
		var progression: Dictionary = progression_doc.get("value", {})
		progression["xp"] = int(progression.get("xp", 0)) + maxi(0, result.signal_earned)
		progression["level"] = 1 + int(progression["xp"] / XP_PER_LEVEL)
		var streak := int(progression.get("current_streak", 0))
		streak = streak + 1 if survived else 0
		progression["current_streak"] = streak
		progression["best_streak"] = maxi(int(progression.get("best_streak", 0)), streak)
		var saved := await CruxSession.save_progression(pid, progression, int(progression_doc.get("version", -1)))
		outcome["progression"] = "conflict" if saved.has("error") else "updated"
		outcome["level"] = progression["level"]
		outcome["xp"] = progression["xp"]
		outcome["best_streak"] = progression["best_streak"]
	else:
		outcome["progression"] = "unavailable"

	return outcome


static func _grant_economy(pid: String, result: GameProtocol.MatchResult) -> Dictionary:
	var signal_amount := clampi(result.signal_earned, 0, MAX_REWARD_PER_MATCH)
	# Crux keys these by `key`, not id: /economy/adjust 400s on currency_id/item_id.
	var balance_adjustments := [{"currency_key": "signal", "amount": signal_amount}]
	var inventory_adjustments: Array = []
	for item in result.items_found:
		inventory_adjustments.append({"item_key": item, "quantity": 1})
	var outcome := await CruxSession.adjust_economy(pid, balance_adjustments, inventory_adjustments)
	if outcome.has("error"):
		return outcome
	return {"signal_earned": signal_amount, "items_granted": result.items_found.size()}


static func _submit_leaderboards(pid: String, result: GameProtocol.MatchResult) -> Array:
	var submissions: Array = []
	var weekly_id := _leaderboard_id("weekly_recovery_score", "LEADERBOARD_WEEKLY_ID")
	var fastest_id := _leaderboard_id("fastest_full_extraction", "LEADERBOARD_FASTEST_ID")
	var metadata := result.to_dict()
	if not weekly_id.is_empty():
		var score := result.cores_recovered * 1000 + maxi(0, 300000 - int(result.time_taken * 1000))
		var weekly_result := await CruxSession.submit_score(weekly_id, pid, score, metadata)
		submissions.append({"board": weekly_id, "score": score, "ok": not weekly_result.has("error")})
	if result.cores_recovered >= 3 and not fastest_id.is_empty():
		var time_ms := int(result.time_taken * 1000)
		var fastest_result := await CruxSession.submit_score(fastest_id, pid, time_ms, metadata)
		submissions.append({"board": fastest_id, "score": time_ms, "ok": not fastest_result.has("error")})
	return submissions


static func _leaderboard_id(config_key: String, environment_key: String) -> String:
	var configured := LiveConfig.get_leaderboard_id(config_key)
	return configured if not configured.is_empty() else OS.get_environment(environment_key)
