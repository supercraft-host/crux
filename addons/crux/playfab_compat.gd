## PlayFab-client-API-shaped surface backed by Crux.
##
## Keeps an existing PlayFab codebase compiling while the backend underneath
## changes. Method names, request keys and the {code, status, data} envelope
## match PlayFab's; the transport underneath is Crux.
##
## Usage:
##   var pf = CruxPlayFabCompat.new(Crux)                 # the autoload
##   var res = await pf.LoginWithCustomID({"CustomId": OS.get_unique_id()})
##   var data = await pf.GetUserData({"Keys": ["save"]})
##
## Every method is `await`-ed, because every Crux call is. PlayFab's JS/C# SDKs
## take a callback; GDScript's idiom is await, so that is what this exposes.
##
## NOT AFFILIATED WITH MICROSOFT. PlayFab is a trademark of Microsoft. This file
## contains no PlayFab code; it is an independent adapter that accepts the same
## request shapes. It is not endorsed or supported by Microsoft.

class_name CruxPlayFabCompat
extends RefCounted

var _crux: Node
var _player_id: String
var _user_data_key: String


## `crux` is the Crux autoload (or a manually instantiated one). `player_id` may
## be passed if you already know it; otherwise call a Login* method first.
func _init(crux: Node, player_id: String = "", user_data_key: String = "playfab_user_data") -> void:
	if crux == null:
		push_error("CruxPlayFabCompat: needs a Crux instance; pass the Crux autoload")
	_crux          = crux
	_player_id     = player_id
	_user_data_key = user_data_key


func get_player_id() -> String:
	return _player_id


# ── envelopes ─────────────────────────────────────────────────────────────────
# GDScript has no exceptions, so an unsupported call cannot throw the way the JS
# and C# adapters do. It does the next best thing: pushes an error AND returns an
# envelope whose code is 501, never a success shape. Silence is the one outcome
# ruled out - a stub that looks like it worked is, for SubtractUserVirtualCurrency
# or a receipt check, somebody's money.

func _ok(data: Variant) -> Dictionary:
	return {"code": 200, "status": "OK", "data": data}


func _fail(code: int, message: String) -> Dictionary:
	push_error("CruxPlayFabCompat: " + message)
	return {"code": code, "status": "Error", "data": null,
			"error": "CruxCompatError", "errorCode": code, "errorMessage": message}


## Reasons are specific, and each names the alternative. A bare "not supported"
## just sends the integrator back to us with a support ticket.
const UNSUPPORTED := {
	"ExecuteCloudScript":
		"Crux does not execute customer code. Use outbound webhooks, or call your existing Azure Function directly - if your CloudScript already runs on Azure Functions, only the invocation path changes.",
	"GetCharacterData":
		"Crux has no character entity. Model characters as player document keys.",
	"GetAllUsersCharacters":
		"Crux has no character entity. Model characters as player document keys.",
	"ValidateIOSReceipt":
		"Receipt validation is not implemented. Validate with the store SDK on your own server, then apply the grant with a Crux server token.",
	"ValidateGooglePlayPurchase":
		"Receipt validation is not implemented. Validate with the store SDK on your own server, then apply the grant with a Crux server token.",
	"ValidateAmazonIAPReceipt":
		"Receipt validation is not implemented. Validate with the store SDK on your own server, then apply the grant with a Crux server token.",
	"GetContentDownloadUrl":
		"Crux does not host CDN content. Serve assets from your own bucket or CDN.",
	"CreateSharedGroup":
		"Crux has no shared-group concept. Use a project document, or a player document keyed by group id.",
	"OpenTrade":
		"Player trading is not implemented. Mediate trades on your own server using economy adjustments with a server token.",
	"WritePlayerEvent":
		"Crux does not ingest gameplay events. Use a dedicated analytics product (PostHog, Mixpanel, GameAnalytics).",
	"GetUserReadOnlyData":
		"Crux documents have no read-only flag. Keep server-authoritative fields in a player document your server alone writes, or in stats - stat writes already require a server token.",
	"GetAccountInfo":
		"Crux has no account-info aggregate. The login response carries the player id; fetch the specific pieces you need (documents, stats, balances) directly.",
	"GetPlayerProfile":
		"Crux has no profile aggregate. Read the player documents and stats you actually display instead of one kitchen-sink call.",
	"GetPlayerSegments":
		"Segments and analytics are not implemented.",
	"AndroidDevicePushNotificationRegistration":
		"Push notifications are not implemented. Use Firebase Cloud Messaging or APNs directly.",
	"GetPhotonAuthenticationToken":
		"Photon relay tokens are not issued by Crux.",
}


func _unsupported(method_name: String) -> Dictionary:
	var reason: String = UNSUPPORTED.get(method_name,
		"Not supported by the Crux compatibility layer.")
	return _fail(501, "%s is not supported. %s" % [method_name, reason])


## Player-scoped calls need a player. PlayFab infers it from the session ticket;
## Crux addresses players explicitly, so the adapter must be told once.
##
## Returns {} when a player is set, otherwise the failure envelope to return as
## is. Returning the envelope rather than a bool keeps the caller from raising a
## second, blander error and handing THAT one back - the caller needs the message
## that says what to do, not "needs a player".
func _require_player(method_name: String) -> Dictionary:
	if _player_id.is_empty():
		return _fail(400, "%s needs a player. Call a Login* method first, or construct with a player_id." % method_name)
	return {}


# ── auth ──────────────────────────────────────────────────────────────────────

func LoginWithCustomID(request: Dictionary = {}) -> Dictionary:
	var auth: Dictionary = await _crux.login_anonymous(str(request.get("CustomId", "")))
	return _login_result(auth, "LoginWithCustomID")


func LoginWithEmailAddress(request: Dictionary = {}) -> Dictionary:
	var auth: Dictionary = await _crux.login_email(str(request.get("Email", "")), str(request.get("Password", "")))
	return _login_result(auth, "LoginWithEmailAddress")


func RegisterPlayFabUser(request: Dictionary = {}) -> Dictionary:
	var auth: Dictionary = await _crux.register_email(str(request.get("Email", "")), str(request.get("Password", "")))
	return _login_result(auth, "RegisterPlayFabUser")


func _login_result(auth: Dictionary, method_name: String) -> Dictionary:
	if auth.is_empty() or not auth.has("player_id"):
		return _fail(401, "%s failed; Crux returned no player" % method_name)
	_player_id = str(auth["player_id"])
	return _ok({
		"PlayFabId":     _player_id,
		"SessionTicket": str(auth.get("access_token", "")),
		"NewlyCreated":  false,
	})


# ── player data ───────────────────────────────────────────────────────────────
# PlayFab has a flat per-player key/value namespace. Crux has versioned
# documents. Keeping the whole namespace in ONE document preserves the atomicity
# callers assume when writing several keys at once.

func GetUserData(request: Dictionary = {}) -> Dictionary:
	var guard := _require_player("GetUserData")
	if not guard.is_empty():
		return guard
	var doc: Dictionary = await _crux.get_player_document(_player_id, _user_data_key)
	var value: Dictionary = doc.get("value", {}) if doc.get("value") is Dictionary else {}
	var keys: Array = request.get("Keys", [])
	var out := {}
	for k in value.keys():
		if keys.is_empty() or keys.has(k):
			out[k] = {"Value": str(value[k]), "LastUpdated": str(doc.get("updated_at", ""))}
	return _ok({"Data": out, "DataVersion": int(doc.get("version", 0))})


## Merges. PlayFab callers assume untouched keys survive, a null deletes, and
## KeysToRemove deletes. The read version is passed back for optimistic
## concurrency, so a concurrent write is rejected rather than silently lost.
func UpdateUserData(request: Dictionary = {}) -> Dictionary:
	var guard := _require_player("UpdateUserData")
	if not guard.is_empty():
		return guard
	var doc: Dictionary = await _crux.get_player_document(_player_id, _user_data_key)
	var value: Dictionary = doc.get("value", {}).duplicate() if doc.get("value") is Dictionary else {}

	var updates: Dictionary = request.get("Data", {})
	for k in updates.keys():
		if updates[k] == null:
			value.erase(k)
		else:
			value[k] = str(updates[k])
	for k in request.get("KeysToRemove", []):
		value.erase(k)

	var version: int = int(doc.get("version", -1)) if doc.has("version") else -1
	var written: Dictionary = await _crux.set_player_document(_player_id, _user_data_key, value, version)
	return _ok({"DataVersion": int(written.get("version", 0))})


func GetTitleData(request: Dictionary = {}) -> Dictionary:
	var doc: Dictionary = await _crux.get_project_document(str(request.get("KeyName", "title_data")))
	var value: Dictionary = doc.get("value", {}) if doc.get("value") is Dictionary else {}
	var keys: Array = request.get("Keys", [])
	var out := {}
	for k in value.keys():
		if keys.is_empty() or keys.has(k):
			out[k] = str(value[k])
	return _ok({"Data": out})


# ── leaderboards & statistics ─────────────────────────────────────────────────

func GetLeaderboard(request: Dictionary = {}) -> Dictionary:
	var rows: Array = await _crux.get_top(str(request.get("StatisticName", "")), int(request.get("MaxResultsCount", 10)))
	return _ok({"Leaderboard": _to_entries(rows)})


func GetLeaderboardAroundPlayer(request: Dictionary = {}) -> Dictionary:
	var pid: String = str(request.get("PlayFabId", _player_id))
	if pid.is_empty():
		return _fail(400, "GetLeaderboardAroundPlayer needs a player")
	var radius: int = maxi(1, int(request.get("MaxResultsCount", 10)) / 2)
	var rows: Array = await _crux.get_around_player(str(request.get("StatisticName", "")), pid, radius)
	return _ok({"Leaderboard": _to_entries(rows)})


## PlayFab Position is 0-based; Crux ranks from 1. This single off-by-one
## silently corrupts every rank UI if it is missed.
func _to_entries(rows: Array) -> Array:
	var list := []
	for r in rows:
		if r is Dictionary:
			list.append({
				"PlayFabId": str(r.get("player_id", "")),
				"StatValue": int(r.get("score", 0)),
				"Position":  int(r.get("rank", 1)) - 1,
			})
	return list


func UpdatePlayerStatistics(request: Dictionary = {}) -> Dictionary:
	var guard := _require_player("UpdatePlayerStatistics")
	if not guard.is_empty():
		return guard
	for s in request.get("Statistics", []):
		if s is Dictionary:
			await _crux.submit_score(str(s.get("StatisticName", "")), _player_id, float(s.get("Value", 0)))
	return _ok({})


## PlayFab keeps ONE statistic store that is both readable and leaderboard-ranked.
## Crux splits it: server-owned stats (writing them needs a server token) and
## leaderboard scores (runtime token). This adapter is a CLIENT surface, so
## UpdatePlayerStatistics necessarily writes the leaderboard side - meaning a read
## that consulted only the stats service would return nothing it had just written.
##
## So it reads both: the enumerable server-owned stats, plus - for any name
## explicitly requested and not found there - that player's own leaderboard
## standing. Update-then-get round-trips, which every PlayFab call site assumes.
##
## Limit, stated rather than hidden: with no StatisticNames only server-owned
## stats come back, because a client cannot enumerate the leaderboards it posted
## to. Note also that the fallback read logs a Crux HTTP 404 for a statistic the
## player has never been ranked on; that is the SDK's normal error reporting, not
## a fault in this adapter.
##
## Version is always 0. Crux has no per-statistic version, and inventing one
## would break any caller using it for optimistic concurrency.
func GetPlayerStatistics(request: Dictionary = {}) -> Dictionary:
	var guard := _require_player("GetPlayerStatistics")
	if not guard.is_empty():
		return guard
	var wanted: Array = request.get("StatisticNames", [])
	var stats: Array = await _crux.list_player_stats(_player_id)

	var out := []
	var seen := {}
	for st in stats:
		if st is Dictionary:
			var key: String = str(st.get("key", ""))
			if wanted.is_empty() or wanted.has(key):
				out.append({"StatisticName": key, "Value": int(st.get("value", 0)), "Version": 0})
				seen[key] = true

	for name in wanted:
		if seen.has(name):
			continue
		var standing: Dictionary = await _crux.get_player_standing(str(name), _player_id)
		# Absent stays absent: a fabricated 0 is indistinguishable from a real 0.
		if not standing.is_empty() and standing.has("score"):
			out.append({"StatisticName": str(name), "Value": int(standing["score"]), "Version": 0})

	return _ok({"Statistics": out})


# ── economy ───────────────────────────────────────────────────────────────────

func GetUserInventory(_request: Dictionary = {}) -> Dictionary:
	var guard := _require_player("GetUserInventory")
	if not guard.is_empty():
		return guard
	var eco: Dictionary = await _crux.get_player_economy(_player_id)
	var currency := {}
	for b in eco.get("balances", []):
		if b is Dictionary:
			currency[str(b.get("currency_id", ""))] = int(b.get("amount", 0))
	var inventory := []
	for i in eco.get("inventory", []):
		if i is Dictionary:
			inventory.append({
				"ItemId":        str(i.get("item_id", "")),
				"DisplayName":   str(i.get("item_name", "")),
				"RemainingUses": int(i.get("quantity", 0)),
			})
	return _ok({"VirtualCurrency": currency, "Inventory": inventory})


func AddUserVirtualCurrency(request: Dictionary = {}) -> Dictionary:
	return await _adjust_currency(request, false, "AddUserVirtualCurrency")


func SubtractUserVirtualCurrency(request: Dictionary = {}) -> Dictionary:
	return await _adjust_currency(request, true, "SubtractUserVirtualCurrency")


## Subtracting sends a NEGATIVE delta. A sign error here mints currency instead
## of spending it, so the sign is computed in one place and tested.
static func signed_amount(amount: int, subtract: bool) -> int:
	return -amount if subtract else amount


func _adjust_currency(request: Dictionary, subtract: bool, method_name: String) -> Dictionary:
	var guard := _require_player(method_name)
	if not guard.is_empty():
		return guard
	var currency: String = str(request.get("VirtualCurrency", ""))
	var delta: int = signed_amount(int(request.get("Amount", 0)), subtract)
	var eco: Dictionary = await _crux.adjust_economy(_player_id, [{"currency_id": currency, "delta": delta}], [])
	var balance := 0
	for b in eco.get("balances", []):
		if b is Dictionary and str(b.get("currency_id", "")) == currency:
			balance = int(b.get("amount", 0))
	return _ok({"VirtualCurrency": currency, "Balance": balance, "BalanceChange": delta})


# ── friends ───────────────────────────────────────────────────────────────────

func GetFriendsList(_request: Dictionary = {}) -> Dictionary:
	var guard := _require_player("GetFriendsList")
	if not guard.is_empty():
		return guard
	var friends: Array = await _crux.list_friends(_player_id)
	var out := []
	for f in friends:
		if f is Dictionary:
			out.append({
				"FriendPlayFabId": str(f.get("player_id", "")),
				"TitleDisplayName": str(f.get("display_name", "")),
			})
	return _ok({"Friends": out})


## Created is false on purpose. PlayFab friends immediately; Crux sends a request
## the other player accepts. Reporting true would be a lie.
func AddFriend(request: Dictionary = {}) -> Dictionary:
	var guard := _require_player("AddFriend")
	if not guard.is_empty():
		return guard
	await _crux.send_friend_request(_player_id, str(request.get("FriendPlayFabId", "")))
	return _ok({"Created": false})


func RemoveFriend(request: Dictionary = {}) -> Dictionary:
	var guard := _require_player("RemoveFriend")
	if not guard.is_empty():
		return guard
	await _crux.remove_friend(_player_id, str(request.get("FriendPlayFabId", "")))
	return _ok({})


# ── unsupported ───────────────────────────────────────────────────────────────
# Present, not absent: feature-detection that checks for the method finds it and
# gets a loud 501, instead of concluding the feature is simply unavailable.

func ExecuteCloudScript(_request: Dictionary = {}) -> Dictionary:
	return _unsupported("ExecuteCloudScript")


func GetUserReadOnlyData(_request: Dictionary = {}) -> Dictionary:
	return _unsupported("GetUserReadOnlyData")


func GetAccountInfo(_request: Dictionary = {}) -> Dictionary:
	return _unsupported("GetAccountInfo")


func GetPlayerProfile(_request: Dictionary = {}) -> Dictionary:
	return _unsupported("GetPlayerProfile")

func GetCharacterData(_request: Dictionary = {}) -> Dictionary:
	return _unsupported("GetCharacterData")

func GetAllUsersCharacters(_request: Dictionary = {}) -> Dictionary:
	return _unsupported("GetAllUsersCharacters")

func ValidateIOSReceipt(_request: Dictionary = {}) -> Dictionary:
	return _unsupported("ValidateIOSReceipt")

func ValidateGooglePlayPurchase(_request: Dictionary = {}) -> Dictionary:
	return _unsupported("ValidateGooglePlayPurchase")

func ValidateAmazonIAPReceipt(_request: Dictionary = {}) -> Dictionary:
	return _unsupported("ValidateAmazonIAPReceipt")

func GetContentDownloadUrl(_request: Dictionary = {}) -> Dictionary:
	return _unsupported("GetContentDownloadUrl")

func CreateSharedGroup(_request: Dictionary = {}) -> Dictionary:
	return _unsupported("CreateSharedGroup")

func OpenTrade(_request: Dictionary = {}) -> Dictionary:
	return _unsupported("OpenTrade")

func WritePlayerEvent(_request: Dictionary = {}) -> Dictionary:
	return _unsupported("WritePlayerEvent")

func GetPlayerSegments(_request: Dictionary = {}) -> Dictionary:
	return _unsupported("GetPlayerSegments")

func AndroidDevicePushNotificationRegistration(_request: Dictionary = {}) -> Dictionary:
	return _unsupported("AndroidDevicePushNotificationRegistration")

func GetPhotonAuthenticationToken(_request: Dictionary = {}) -> Dictionary:
	return _unsupported("GetPhotonAuthenticationToken")
