# Supercraft GSB — Godot 4 SDK

> GDScript addon for [GSB — Supercraft Game Services Backend](https://gsb.supercraft.host/).
> Requires Godot 4.1+.

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

---

## Install

### From the Godot Asset Library

Project → Asset Library → search "Supercraft GSB" → Download → Install
to `res://addons/gsb/`.

### From source (this repo)

1. Copy [`addons/gsb/`](addons/gsb/) into your project's `addons/`
   directory.
2. Enable the plugin: **Project → Project Settings → Plugins → GSB →
   Enable**.
3. *(Recommended)* Add `GSB` as an Autoload for global access:
   **Project → Project Settings → Autoload → add
   `res://addons/gsb/gsb.gd` as `GSB`**.

After autoload, every script can just call `GSB.submit_score(...)`
without an import line.

---

## Quick start — game client

```gdscript
extends Node

func _ready() -> void:
    # Initialise with your project's public API key.
    GSB.init_player(
        "https://gsb.supercraft.host",
        "proj_xxx", "env_xxx", "gsb_apikey_xxx"
    )

    # Log in anonymously (or use login_email / register_email).
    var auth = await GSB.login_anonymous()
    print("Player: ", auth.player_id)

    # Save arbitrary structured data.
    await GSB.set_player_document(auth.player_id, "settings", {
        "volume": 0.8, "lang": "en"
    })

    # Submit a score, then read the top 10.
    await GSB.submit_score("weekly", auth.player_id, 4200.0)
    var entries = await GSB.get_top("weekly", 10)
    for e in entries:
        print("#%d  %s  %.0f" % [e.rank, e.player_id, e.score])
```

## Quick start — dedicated server

```gdscript
extends Node

var _server_id := "my-server-01"

func _ready() -> void:
    GSB.init_server(
        "https://gsb.supercraft.host",
        "proj_xxx", "env_xxx", "gsb_servertoken_xxx"
    )

    var info = await GSB.register_server({
        "server_id":    _server_id,
        "name":         "Deathmatch EU #1",
        "region":       "eu-west",
        "map_name":     "forest",
        "game_mode":    "deathmatch",
        "player_count": 0,
        "max_players":  16,
        "address":      "198.51.100.1",
        "port":         7777,
        "version":      "1.2.0",
    })
    print("Registered: ", info.id)
    _start_heartbeat()

func _start_heartbeat() -> void:
    while true:
        await get_tree().create_timer(30.0).timeout
        await GSB.heartbeat(_server_id)

func _notification(what: int) -> void:
    if what == NOTIFICATION_WM_CLOSE_REQUEST:
        await GSB.deregister_server(_server_id)
```

> **Don't ship a server token in a player build.** It has full
> project authority. See [`docs/AUTH.md`](../../docs/AUTH.md).

---

## API reference

### Init

| Call | Description |
|---|---|
| `GSB.init_player(url, project_id, env_id, api_key)` | Client-side mode |
| `GSB.init_server(url, project_id, env_id, server_token)` | Server-side mode |

### Auth — [concepts](https://gsb.supercraft.host/blog/guest-login-and-account-upgrade)

| Call | Returns | Description |
|---|---|---|
| `await GSB.login_anonymous()` | `Dictionary` | Guest login |
| `await GSB.login_email(email, password)` | `Dictionary` | Email login |
| `await GSB.register_email(email, password)` | `Dictionary` | Email registration |
| `await GSB.refresh_token()` | `Dictionary` | Refresh access token |
| `await GSB.logout()` | `void` | Revoke the session |

### Player Documents — [concepts](https://gsb.supercraft.host/blog/cross-progression-and-cross-save-backend)

| Call | Description |
|---|---|
| `await GSB.get_player_document(pid, key)` | Get a document |
| `await GSB.set_player_document(pid, key, value, version = -1)` | Write a document; pass `version` for optimistic concurrency |
| `await GSB.patch_player_document(pid, key, operations, version = -1)` | JSON-Patch a document in place |
| `await GSB.delete_player_document(pid, key)` | Delete a document |
| `await GSB.batch_get_player_documents(pid, keys)` | Fetch multiple keys |
| `await GSB.batch_write_player_documents(pid, writes)` | Write multiple keys atomically |

### Leaderboards — [concepts](https://gsb.supercraft.host/blog/esports-tournament-backends-scaling-million-viewer-events)

| Call | Description |
|---|---|
| `await GSB.submit_score(leaderboard_id, pid, score, metadata = {})` | Submit a score |
| `await GSB.get_top(leaderboard_id, limit = 10)` | Top N entries |
| `await GSB.get_player_standing(leaderboard_id, pid)` | Player's rank + score |
| `await GSB.get_around_player(leaderboard_id, pid, radius = 3)` | Neighbours in the ranking |

### Economy

| Call | Description |
|---|---|
| `await GSB.get_player_economy(pid)` | Balances + inventory |
| `await GSB.adjust_economy(pid, balance_adjustments, inventory_adjustments)` | Atomic credit / deduct |

### Matchmaking — [architecture](https://gsb.supercraft.host/blog/skill-based-matchmaking-architecture-2026)

| Call | Description |
|---|---|
| `await GSB.join_matchmaking(pid, game_mode, region = "global")` | Join a queue |
| `await GSB.get_matchmaking_status()` | Poll for result |
| `await GSB.leave_matchmaking(pid)` | Leave the queue |

### Server Registry — [orchestration guide](https://gsb.supercraft.host/blog/game-server-orchestration-guide)

*Server token required.*

| Call | Description |
|---|---|
| `await GSB.register_server(reg: Dictionary)` | Register this instance |
| `await GSB.heartbeat(server_id)` | Send a keepalive |
| `await GSB.deregister_server(server_id)` | Remove on shutdown |
| `await GSB.list_servers(region, map_name, game_mode)` | Browse the registry (any arg `""` = wildcard) |

### Config delivery

| Call | Returns | Description |
|---|---|---|
| `await GSB.download_active_config_bundle()` | `PackedByteArray` | Signed config blob |

---

## Error handling

Async calls return a `Dictionary`. On error, the dictionary has an
`error` key (string message) and a `status` key (HTTP status code):

```gdscript
var result = await GSB.get_player_document(pid, "inventory")
if result.has("error"):
    match result.status:
        404:
            # First write — no document exists yet.
            pass
        409:
            # Optimistic-concurrency conflict — re-read and retry.
            pass
        _:
            push_warning("GSB %d: %s" % [result.status, result.error])
```

The SDK already retries on `429`/`503` with exponential backoff. Don't
add your own retry loop. See
[`docs/ERROR_HANDLING.md`](../../docs/ERROR_HANDLING.md).

---

## Examples

- [`examples/godot/leaderboard.gd`](../../examples/godot/leaderboard.gd)
  — weekly leaderboard end-to-end.

---

## FAQ

**Does it work on Godot 3.x?**  No — the addon uses Godot 4
typed-GDScript and `await`. Sticking with 3.x? Open an issue and we'll
discuss a back-port.

**Does it work in HTML5 / web export?**  Yes — Godot 4 ships with a
WebAssembly HTTP client. Set CORS appropriately on your custom backend
if you're not using `gsb.supercraft.host`.

**Does it work on mobile (iOS / Android)?**  Yes. The HTTP layer uses
Godot's `HTTPRequest` which is cross-platform.

**Where do I see real-world game examples?**  See the [GSB game backend
patterns blog series](https://gsb.supercraft.host/blog/game-backend-as-a-service-complete-guide).

---

## Don't want to host a backend?

[**gsb.supercraft.host**](https://gsb.supercraft.host/) runs GSB for
you. Pricing: [/pricing](https://gsb.supercraft.host/pricing). Sizing
calculator: [/cost-calculator](https://gsb.supercraft.host/cost-calculator).

Moving from another backend?
[PlayFab](https://gsb.supercraft.host/blog/migrate-from-playfab-to-supercraft-gsb),
[Firebase](https://gsb.supercraft.host/blog/firebase-for-games-alternative-supercraft-gsb-2026),
[Beamable](https://gsb.supercraft.host/blog/beamable-vs-supercraft-gsb-comparison),
[Nakama](https://gsb.supercraft.host/blog/nakama-open-source-vs-managed-backend).

## License

[MIT](LICENSE).
