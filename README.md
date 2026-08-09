# Crux - game backend SDK for Godot 4

Player accounts, cloud saves, **leaderboards**, economy, matchmaking and a server browser,
as a single GDScript autoload. No servers to run. MIT licensed. Requires Godot 4.1+.

Lost SilentWolf? This covers the same primitives (leaderboards, accounts, player data) and more,
hosted, with a free tier. Dashboard and docs: https://crux.supercraft.host

## Install

**From the Godot editor (recommended):** open the **AssetLib** tab, search **Crux**, Download, Install.
Then **Project → Project Settings → Plugins → Crux → Enable**. That is the whole install —
enabling the plugin registers the `Crux` autoload for you, so there is no manual autoload step.

**Manual:** copy `addons/crux/` into your project's `addons/` folder, then enable the plugin as above.

## Your first leaderboard in 15 minutes

1. Sign up at https://crux.supercraft.host and create a project. A default environment is created for you.
2. On the **Leaderboards** page, create a leaderboard. Sort **Descending**, update strategy **Best**.
   Copy its **ID** (a UUID).
3. On the **Credentials** page, copy your **API key**. Note your **Project ID** and **Environment ID**
   (both UUIDs).
4. Drop this on any node, fill in the four constants, press Play:

```gdscript
extends Node

const PROJECT_ID     := "00000000-0000-0000-0000-000000000000" # UUID from the dashboard
const ENV_ID         := "00000000-0000-0000-0000-000000000000" # UUID from the dashboard
const API_KEY        := "<YOUR_API_KEY>"                       # Credentials page
const LEADERBOARD_ID := "00000000-0000-0000-0000-000000000000" # the leaderboard's UUID

func _ready() -> void:
    Crux.init_player("https://crux.supercraft.host", PROJECT_ID, ENV_ID, API_KEY)

    # Guest login. Creates a player on the fly, no signup UI needed.
    var auth = await Crux.login_anonymous()
    var player_id: String = auth["player_id"]
    print("logged in as ", player_id)

    # Save whatever JSON shape you like
    await Crux.set_player_document(player_id, "save", { "level": 4, "coins": 250 })

    # Submit a score, then read the board back
    await Crux.submit_score(LEADERBOARD_ID, player_id, 4200.0)
    for e in await Crux.get_top(LEADERBOARD_ID, 10):
        print("#%d  %s  %.0f" % [e["rank"], e["player_id"], e["score"]])
```

You will see the top list in the Output panel, and the score on the Leaderboards page in the dashboard.

The **API key is project-scoped and safe to ship in a game build** - it only lets players authenticate
and touch their own data. For trusted server-side code use a **server token** via `Crux.init_server(...)`.

## What else is in the SDK

| Area | Methods |
|---|---|
| Auth | `login_anonymous`, `login_email`, `register_email`, `refresh_token`, `logout` |
| Cloud saves | `get_player_document`, `set_player_document`, `patch_player_document`, `delete_player_document`, batch read/write |
| Leaderboards | `submit_score`, `get_top`, `get_player_standing`, `get_around_player` |
| Economy | `get_player_economy`, `adjust_economy` |
| Matchmaking | `join_matchmaking`, `get_matchmaking_status`, `leave_matchmaking` |
| Server browser | `register_server`, `heartbeat`, `deregister_server`, `list_servers` |

Every method is documented inline in `addons/crux/crux.gd`.

## Notes

- Saves are **versioned documents**. `set_player_document` accepts the version you read, so two writers
  (co-op, or one player on two devices) fail loudly instead of silently overwriting each other.
- Leaderboard scores are validated server-side, so a submitted number is a claim to check rather than a
  fact to store.
- Everything you store is exportable at any time through the same open HTTP API you write with.

## Links

- Dashboard and docs: https://crux.supercraft.host
- SDK quickstart (curl, JavaScript, Godot, Unity): https://crux.supercraft.host/sdk/
- Data and exit guarantee: https://crux.supercraft.host/guarantee/

## License

MIT. See [LICENSE](LICENSE).
