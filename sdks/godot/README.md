# Supercraft Crux - Godot 4 SDK

GDScript addon for [Crux (Game Services Backend)](https://supercraft.dev). Requires Godot 4.1+.

## Installation

1. Copy the `addons/crux/` folder into your project's `addons/` directory.
2. Enable the plugin: **Project → Project Settings → Plugins → Crux → Enable**.
3. *(Optional)* Add `Crux` as an Autoload for global access: **Project → Project Settings → Autoload → add `addons/crux/crux.gd` as `Crux`**.

## Quick start - game client

```gdscript
extends Node

# Copy these four values from your Crux dashboard (https://crux.supercraft.host):
#   PROJECT_ID / ENV_ID  - UUIDs on the Projects + Environments pages
#   API_KEY              - secret string from the Credentials page. Safe to ship
#                          in a game client: it is project-scoped and only lets
#                          players authenticate and touch their own data.
#   LEADERBOARD_ID       - UUID of a leaderboard you created (Leaderboards page)
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

    # Submit a score. Leaderboards are addressed by their UUID, not their key.
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
        "player_count": 0,
        "max_players":  16,
        "address":      "198.51.100.1",
        "port":         7777,
        "version":      "1.2.0",
    })
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
| `await Crux.batch_write_player_documents(player_id, writes[])` | Write multiple keys atomically |

### Leaderboards
| Call | Description |
|------|-------------|
| `await Crux.submit_score(leaderboard_id, player_id, score, metadata?)` | Submit a score |
| `await Crux.get_top(leaderboard_id, limit)` | Top N entries |
| `await Crux.get_player_standing(leaderboard_id, player_id)` | A player's rank + score |
| `await Crux.get_around_player(leaderboard_id, player_id, radius)` | Neighbours in the ranking |

`leaderboard_id` is the leaderboard's **UUID** (returned by create / shown in the dashboard), not its display key like `"weekly"`.

### Economy
| Call | Description |
|------|-------------|
| `await Crux.get_player_economy(player_id)` | Balances + inventory |
| `await Crux.adjust_economy(player_id, balances?, inventory?)` | Atomic credit/deduct |

### Matchmaking
| Call | Description |
|------|-------------|
| `await Crux.join_matchmaking(player_id, game_mode, region)` | Join a queue |
| `await Crux.get_matchmaking_status()` | Poll for result |
| `await Crux.leave_matchmaking(player_id)` | Leave the queue |

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
