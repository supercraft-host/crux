# Supercraft Crux - Godot 4 SDK

GDScript addon for [Crux (Game Services Backend)](https://crux.supercraft.host). Requires Godot 4.1+.

Migrating off PlayFab? The addon also ships a **PlayFab-shaped compatibility layer** that
keeps your existing call sites working - see [PlayFab compatibility](#playfab-compatibility).

## Installation

1. Copy the `addons/crux/` folder into your project's `addons/` directory.
2. Enable the plugin: **Project → Project Settings → Plugins → Crux → Enable**.
3. *(Optional)* Add `Crux` as an Autoload for global access: **Project → Project Settings → Autoload → add `addons/crux/crux.gd` as `Crux`**.

## Quick start - game client

```gdscript
extends Node

# Copy these four values from your Crux dashboard (https://crux.supercraft.host):
#   PROJECT_ID / ENV_ID  - UUIDs on the Projects + Environments pages
#   API_KEY              - the PUBLISHABLE key from the Credentials page. Safe to
#                          ship in a game client: it authenticates players and
#                          nothing else. The secret key beside it is server-side
#                          only - never put that one in a build you distribute.
#   LEADERBOARD_ID       - key OR UUID of a leaderboard you created (Leaderboards page)
const PROJECT_ID     := "00000000-0000-0000-0000-000000000000"
const ENV_ID         := "00000000-0000-0000-0000-000000000000"
const API_KEY        := "<YOUR_API_KEY>"
const LEADERBOARD_ID := "00000000-0000-0000-0000-000000000000"

func _ready() -> void:
    Crux.init_player("https://crux.supercraft.host", PROJECT_ID, ENV_ID, API_KEY)

    # Log in anonymously (guest account, created on the fly)
    var auth = await Crux.login_anonymous()
    var player_id: String = auth["player_id"]
    print("Player: ", player_id)

    # Save arbitrary data
    await Crux.set_player_document(player_id, "settings", {"volume": 0.8, "lang": "en"})

    # Submit a score. Leaderboards are addressed by UUID or by the key you gave them.
    await Crux.submit_score(LEADERBOARD_ID, player_id, 4200.0)

    # Get the top 10
    var entries = await Crux.get_top(LEADERBOARD_ID, 10)
    for e in entries:
        print("#%d  %s  %.0f" % [e["rank"], e["player_id"], e["score"]])
```

## Quick start - dedicated game server

```gdscript
extends Node

var _server_id := "my-server-01"

func _ready() -> void:
    # PROJECT_ID / ENV_ID are UUIDs; the server token is a secret string issued
    # on the Credentials page of your Crux dashboard (server tokens are trusted -
    # keep them on the server, never ship them in a client build).
    Crux.init_server("https://crux.supercraft.host", "<PROJECT_ID>", "<ENV_ID>", "<SERVER_TOKEN>")

    var info = await Crux.register_server({
        "server_id":    _server_id,
        "name":         "Deathmatch EU #1",
        "region":       "eu-west",
        "map_name":     "forest",
        "game_mode":    "deathmatch",
        "player_count":   0,
        "ip_address":     "198.51.100.1",
        "port":           7777,
        "server_version": "1.2.0",
    })
    # Those are all the fields the registry stores. There is no capacity field -
    # keep max players in a project document if your browser needs it.
    print("Registered: ", info["id"])
    _start_heartbeat()

func _start_heartbeat() -> void:
    while true:
        await get_tree().create_timer(30.0).timeout
        await Crux.heartbeat(_server_id)

func _notification(what: int) -> void:
    if what == NOTIFICATION_WM_CLOSE_REQUEST:
        await Crux.deregister_server(_server_id)
```

## API reference

### Init
| Call | Description |
|------|-------------|
| `Crux.init_server(url, project_id, env_id, server_token)` | Server-side mode |
| `Crux.init_player(url, project_id, env_id, api_key)` | Client-side mode |

### Auth
| Call | Description |
|------|-------------|
| `await Crux.login_anonymous()` | Guest login |
| `await Crux.login_email(email, password)` | Email login |
| `await Crux.register_email(email, password)` | Email registration |
| `await Crux.refresh_token()` | Refresh the access token |
| `await Crux.logout()` | Revoke the session |

### Player Documents
| Call | Description |
|------|-------------|
| `await Crux.get_player_document(player_id, key)` | Get a document |
| `await Crux.set_player_document(player_id, key, value, version?)` | Write a document |
| `await Crux.delete_player_document(player_id, key)` | Delete a document |
| `await Crux.batch_get_player_documents(player_id, keys[])` | Fetch multiple keys |
| `await Crux.patch_player_document(player_id, key, operations, version?)` | Apply JSON-patch style operations to one document |
| `await Crux.batch_write_player_documents(player_id, writes[])` | Write multiple keys atomically |

### Project Documents
Shared by every player in the environment - server capacity, event flags, drop tables, seasonal switches. Reading needs any authenticated caller; **writing needs an API key or a server token**, so a game client cannot rewrite the rules it is handed.

| Call | Description |
|------|-------------|
| `await Crux.list_project_document_keys()` | Keys with size and version, no bodies |
| `await Crux.get_project_document(key)` | Get a shared document |
| `await Crux.set_project_document(key, value, version?)` | Write one |
| `await Crux.delete_project_document(key)` | Delete one |
| `await Crux.batch_get_project_documents(keys)` | Fetch multiple keys |
| `await Crux.batch_write_project_documents(documents)` | Write multiple keys atomically |

### Stats
Named 64-bit counters the backend owns, so progression is queryable instead of buried in a save blob. **Writing a stat settles every achievement bound to it in the same transaction** - the write response tells you what was earned, exactly once, so a reward can never pay twice.

| Call | Description |
|------|-------------|
| `await Crux.list_player_stats(player_id)` | Every stat for a player |
| `await Crux.get_player_stat(player_id, key)` | One stat |
| `await Crux.set_player_stat(player_id, key, value)` | Set to an absolute value *(server token)* |
| `await Crux.increment_player_stat(player_id, key, delta)` | Add a delta, negative to subtract *(server token)* |

Both writes return a dictionary with `stat` and `unlocked`, where `unlocked` is the achievements that crossed their threshold on this call.

**Stat writes and direct unlocks require a server token.** Reading takes any runtime credential, but a player token gets `403 server token required` on a write - progression is server-authoritative, so a modified client cannot award itself anything. Call these from your dedicated server or a trusted backend, not from the game client.

### Achievements
| Call | Description |
|------|-------------|
| `await Crux.list_achievements()` | The catalogue defined for this environment |
| `await Crux.list_player_achievements(player_id)` | What this player has unlocked |
| `await Crux.unlock_achievement(player_id, key)` | Grant one directly *(server token)* |

`unlock_achievement` is idempotent: it reports `true` on the call that actually granted it and `false` on every repeat, so it is safe to call from a retrying client.

### Leaderboards
| Call | Description |
|------|-------------|
| `await Crux.submit_score(leaderboard_id, player_id, score, metadata?)` | Submit a score |
| `await Crux.get_top(leaderboard_id, limit)` | Top N entries |
| `await Crux.get_player_standing(leaderboard_id, player_id)` | A player's rank + score |
| `await Crux.get_around_player(leaderboard_id, player_id, radius)` | Neighbours in the ranking |

`leaderboard_id` accepts either the leaderboard's **UUID** (returned by create / shown in the dashboard) **or its key**, e.g. `"weekly"`. A UUID-shaped value is resolved as an id first.

### Economy
| Call | Description |
|------|-------------|
| `await Crux.get_player_economy(player_id)` | Balances + inventory |
| `await Crux.adjust_economy(player_id, balances?, inventory?)` | Atomic credit/deduct *(server token)* |

### Social
| Call | Description |
|------|-------------|
| `await Crux.list_friends(player_id)` | Accepted friendships |
| `await Crux.list_pending_friend_requests(player_id)` | Incoming requests |
| `await Crux.send_friend_request(player_id, friend_id)` | Send a request |
| `await Crux.accept_friend_request(player_id, friend_id)` | Accept one |
| `await Crux.remove_friend(player_id, friend_id)` | Remove a friendship |
| `await Crux.block_player(player_id, target_id)` | Block |
| `await Crux.unblock_player(player_id, target_id)` | Unblock |

### Matchmaking
| Call | Description |
|------|-------------|
| `await Crux.join_matchmaking(player_id, game_mode, region, runtime_build_id?)` | Join a legacy queue or opt into a ready Runtime build |
| `await Crux.get_matchmaking_status()` | Poll for result |
| `await Crux.leave_matchmaking(player_id)` | Leave the queue |
| `await Crux.start_match(match_id)` | Mark a formed match as in-progress *(server token)* |
| `await Crux.complete_match(match_id)` | Mark a match finished, releasing its slots *(server token)* |

A formed legacy match carries the live server it was placed on, drawn from your own registry - matchmaking only picks a server that is currently heartbeating, so a crashed host is never handed out as a destination. Pass a ready Runtime build UUID as the fourth argument to provision an ephemeral authoritative session instead; poll until `match.runtime.status == "ready"`, then request a player-specific Runtime join ticket with `issue_runtime_join_ticket`. Call `start_match` when the session begins and `complete_match` when it ends; Runtime match completion also requests the Runtime session to stop.

### Server Registry *(server token required)*
| Call | Description |
|------|-------------|
| `await Crux.register_server(reg: Dictionary)` | Register this instance |
| `await Crux.heartbeat(server_id)` | Send a keepalive |
| `await Crux.deregister_server(server_id)` | Remove on shutdown |
| `await Crux.list_servers(region?, map_name?, game_mode?)` | Browse servers |

### Config
| Call | Description |
|------|-------------|
| `await Crux.download_active_config_bundle()` | Returns `PackedByteArray` |

### Crux Runtime *(Godot dedicated server deployment)*

Runtime is the shortest path from a Linux x86-64 Godot dedicated-server export
to a joinable authoritative session. It accepts the raw ZIP export, packages
it on the Crux side, starts it on an isolated EU Runtime Agent, and returns a
short-lived endpoint/join ticket. Docker, a container registry, and a cloud
account are not required.

The deployment calls below are for an editor or CI process only. Configure them
with a **secret API key** using `init_runtime_control()` and never include that
key in a player build. The Runtime Agent injects `CRUX_JOIN_TICKET_SECRET` into
the dedicated server; it is not returned to clients.

```gdscript
Crux.init_runtime_control(BASE_URL, PROJECT_ID, ENVIRONMENT_ID, SECRET_API_KEY)
var build := await Crux.create_runtime_build("build-1", "server/game.x86_64", {
    "readiness_delay_seconds": 1,
    # Optional: terminate a quiet session after 15 minutes without a server heartbeat.
    "idle_timeout_seconds": 900,
})
var uploaded := await Crux.upload_runtime_build_artifact(build.id, zip_bytes)
var deployment := await Crux.activate_runtime_build(uploaded.id)
var session := await Crux.create_runtime_session(uploaded.id)
var allowance := await Crux.get_runtime_admission()
var evidence := await Crux.get_runtime_validation_summary()
```

`activate_runtime_build()` makes that immutable build the active version for
new sessions; it remembers the previous ready build. Use
`rollback_runtime_deployment()` to swap back without rebuilding. Poll
`get_runtime_session(session.id)` until `state == "ready"`, then obtain a
player-specific ticket with `issue_runtime_join_ticket(session.id)` from that
player's token, or with `issue_runtime_join_ticket(session.id, player_id)` from
the game's server token. The response contains `endpoint`, `ticket`, and
`expires_at`. The ticket is valid for five minutes and is bound to this
session, project, environment, and player.

`get_runtime_admission()` returns the project's `remaining_seconds`,
`active_sessions`, `max_concurrent_sessions`, and one-hour
`max_session_seconds`. Free projects receive three hours total; paid projects
are marked `metered` and their finalized runtime/egress usage is retained for
billing.
`get_runtime_validation_summary()` returns observed project-level build, session,
startup, result, runtime-time, and egress counters. It does not claim that an
external pilot or paying customer exists; those gates require human evidence.

`create_runtime_session()` may omit `build_id` after a deployment has been
activated; it then uses the active ready build. Passing a build id remains
supported for explicit canary or rollback testing.

## Session-scoped server context and results

The isolated Runtime Agent injects these environment variables into the
authoritative server process:

```text
CRUX_PROJECT_ID
CRUX_ENVIRONMENT_ID
CRUX_SESSION_ID
CRUX_RUNTIME_SESSION_TOKEN
```

If `idle_timeout_seconds` is configured in the build manifest, the server
should call `await Crux.heartbeat_runtime_session()` periodically (for example
every 15-30 seconds) while it is accepting players or simulating. This is an
application-level heartbeat and is intentionally separate from the Agent's
node heartbeat; leaving the manifest value at `0` disables idle enforcement.

The server can opt into the narrow Runtime session surface without receiving a
project API key:

```gdscript
Crux.init_runtime_session_from_environment()
var context := await Crux.get_runtime_session_context()
await Crux.heartbeat_runtime_session()
await Crux.submit_runtime_session_result({
    "winner": "player-1",
    "scores": {"player-1": 12, "player-2": 8},
}, true)
```

The credential is bound to one session and grants only
`runtime.activity.write`, `runtime.context.read`, and `match.result.write`. It
cannot authenticate the general BaaS routes or address another project,
environment, or session.

For a headless CI/editor canary, the addon ships a command helper. It reads the
secret control key from the environment, so no credential is written into the
project:

```bash
CRUX_RUNTIME_API_URL=https://gsb.supercraft.host \
CRUX_PROJECT_ID=<project-uuid> \
CRUX_ENVIRONMENT_ID=<environment-uuid> \
CRUX_RUNTIME_CONTROL_KEY=<secret-api-key> \
CRUX_RUNTIME_ARTIFACT=.godot/export/server.zip \
CRUX_RUNTIME_ENTRYPOINT=server/game.x86_64 \
godot --headless --path . \
  --script addons/crux/tools/runtime_deploy.gd -- \
  --artifact "$CRUX_RUNTIME_ARTIFACT" \
  --version "canary-$(date -u +%Y%m%dT%H%M%SZ)" \
  --entrypoint "$CRUX_RUNTIME_ENTRYPOINT" \
  --player-id runtime-canary
```

The helper creates an immutable build, waits for a ready session, requests a
canary ticket, fetches session logs, and stops the session. The repository also
contains `tools/runtime-canary.bash` for Relay Zero and approved pilot projects.

```gdscript
# Player client, after login_anonymous()/login_email():
var join := await Crux.issue_runtime_join_ticket(session_id)
# Pass join.ticket to the authoritative server's admission code.
```

Runtime v0 is intentionally limited to one EU region, native clients using
UDP/ENet, ephemeral sessions, and one fixed server shape. Web transports,
persistent worlds, autoscaling, and additional regions remain validation-gated.

## PlayFab compatibility

`CruxPlayFabCompat` presents a **PlayFab-client-API-shaped** surface backed by Crux, so a
title mid-migration keeps working while the backend changes underneath it.

```gdscript
const PFCompat = preload("res://addons/crux/playfab_compat.gd")

func _ready() -> void:
    Crux.init_player("https://crux.supercraft.host", PROJECT_ID, ENV_ID, API_KEY)
    var PlayFabClientAPI := PFCompat.new(Crux)

    # unchanged from your PlayFab codebase, bar the await:
    var login := await PlayFabClientAPI.LoginWithCustomID({"CustomId": OS.get_unique_id()})
    print("player ", login.data.PlayFabId)

    var save := await PlayFabClientAPI.GetUserData({"Keys": ["save"]})
```

Every method is awaited, because every Crux call is. PlayFab's JS and C# SDKs take a
callback; GDScript's idiom is `await`, so that is what this exposes.

> **Not affiliated with Microsoft.** PlayFab is a trademark of Microsoft. This addon contains
> **no PlayFab code**; it is an independent adapter accepting the same request shapes. It is
> not endorsed or supported by Microsoft.

### Implemented

| Area | Methods |
|---|---|
| Auth | `LoginWithCustomID`, `LoginWithEmailAddress`, `RegisterPlayFabUser` |
| Player data | `GetUserData`, `UpdateUserData` |
| Title data | `GetTitleData` |
| Leaderboards & stats | `GetLeaderboard`, `GetLeaderboardAroundPlayer`, `UpdatePlayerStatistics`, `GetPlayerStatistics` |
| Economy | `GetUserInventory`, `AddUserVirtualCurrency`, `SubtractUserVirtualCurrency` |
| Friends | `GetFriendsList`, `AddFriend`, `RemoveFriend` |

**Everything else answers `501`** with the reason and the alternative, and pushes an error.
GDScript has no exceptions, so it cannot throw the way the JS and C# adapters do - but the
one outcome ruled out is silence. A stub that looks like it worked is, on
`SubtractUserVirtualCurrency` or a receipt check, somebody's money.

Unsupported methods still **exist** as functions, so feature-detection finds them and gets a
loud 501 rather than concluding the feature is simply unavailable.

### Behavioural differences you must know about

Each is covered by a test in `tests/`.

- **`AddFriend` returns `Created: false`.** PlayFab friends immediately; Crux sends a request
  the other player accepts. Reporting `true` would be a lie.
- **Leaderboard `Position` is 0-based**, matching PlayFab. Crux ranks from 1 and the adapter
  converts. An off-by-one here silently corrupts every rank UI.
- **`GetUserData`/`UpdateUserData` share one Crux document** (`playfab_user_data`). PlayFab
  has a flat per-player namespace; one document preserves the atomicity callers assume when
  writing several keys at once. `UpdateUserData` merges, treats `null` as delete, honours
  `KeysToRemove`, and passes the read version through for optimistic concurrency.
- **`GetPlayerStatistics` reads two stores.** PlayFab has one statistic store that is both
  readable and leaderboard-ranked; Crux splits it, and stat writes need a *server* token. As
  a client surface, `UpdatePlayerStatistics` writes the leaderboard side, so the read merges
  server-owned stats with the player's own leaderboard standing for explicitly requested
  names. Update-then-get round-trips. With no `StatisticNames`, only server-owned stats come
  back - a client cannot enumerate the leaderboards it posted to. `Version` is always 0.
- **A player must be established** before player-scoped calls. Call a `Login*` method, or
  construct with a `player_id`. The error says so.
- **`ExecuteCloudScript` is unsupported.** Crux does not execute customer code. Call your
  existing Azure Function directly - if your CloudScript already runs there, only the
  invocation path changes.

Not implemented at all: characters, receipt validation, shared groups, player trading,
segments/analytics, ads and attribution, push notifications, CDN content, Photon tokens.

### Running the tests

```bash
godot --headless --path sdks/sdk-godot/tests --script test_playfab_compat.gd
```

55 conformance assertions against an in-memory Crux stand-in, asserting on the calls actually
made rather than the adapter's own account of itself. The two highest-consequence ones (the
negative currency delta and the statistics round-trip) are sabotage-verified: each was
confirmed to fail when the behaviour it guards is broken.

`tests/` is a minimal Godot project used only to run these headless; its `addons` entry is a
symlink to the real one, so a Windows checkout without symlink support may need it replaced
with a copy before the suite runs. None of that affects the addon - installation is still
"copy `addons/crux/` into your project".

Full method-by-method mapping: [`docs/playfab-compat-map.md`](../../docs/playfab-compat-map.md).
