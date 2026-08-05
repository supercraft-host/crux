# Supercraft Crux - Unity SDK

Unity UPM package for [Crux (Game Services Backend)](https://supercraft.dev). Covers player auth, documents, leaderboards, economy, matchmaking, server registry, and config delivery.

## Installation

Add to your project's `Packages/manifest.json`:

```json
{
  "dependencies": {
    "host.supercraft.crux": "file:../../sdks/unity/Packages/host.supercraft.crux"
  }
}
```

Or via **Package Manager → Add package from disk...** pointing at `host.supercraft.crux/package.json`.

## Quick start - game client

```csharp
using Supercraft.Crux;

// 1. Create client with your project's public API key
var crux = ServerToolkitClient.ForPlayer(
    baseUrl:       "https://crux.supercraft.host",
    projectId:     "<PROJECT_ID>",
    environmentId: "<ENVIRONMENT_ID>",
    apiKey:        "YOUR_API_KEY..."
);

// 2. Log in (anonymous, email, or OAuth)
var auth = await crux.LoginAnonymousAsync();
Debug.Log($"Player: {auth.player_id}");

// 3. Save player data (arbitrary JSON)
await crux.SetPlayerDocumentAsync(auth.player_id, "profile", "{\"name\":\"Ada\",\"level\":5}");

// 4. Submit a leaderboard score
await crux.SubmitScoreAsync("global-score", auth.player_id, 1234);

// 5. Get top 10
var top = await crux.GetTopAsync("global-score", 10);
foreach (var e in top)
    Debug.Log($"#{e.rank} {e.player_id}: {e.score}");
```

## Quick start - dedicated game server

```csharp
using Supercraft.Crux;

var crux = ServerToolkitClient.ForServer(
    baseUrl:       "https://crux.supercraft.host",
    projectId:     "<PROJECT_ID>",
    environmentId: "<ENVIRONMENT_ID>",
    serverToken:   "YOUR_SERVER_TOKEN..."
);

// Register this server instance
var server = await crux.RegisterServerAsync(new ServerRegistration
{
    server_id    = "my-server-01",
    name         = "Deathmatch EU #1",
    region       = "eu-west",
    map_name     = "de_dust2",
    game_mode    = "deathmatch",
    player_count = 0,
    max_players  = 16,
    address      = "198.51.100.1",
    port         = 27015,
});

// Heartbeat loop (call every 30s)
await crux.HeartbeatAsync(server.server_id);

// Read a player document server-authoritatively
var doc = await crux.GetPlayerDocumentAsync("player-uuid", "inventory");
Debug.Log(doc.raw_value); // raw JSON string
```

## API reference

### Auth
| Method | Description |
|--------|-------------|
| `LoginAnonymousAsync()` | Guest login (no credentials) |
| `LoginEmailAsync(email, password)` | Email + password login |
| `RegisterEmailAsync(email, password)` | Email + password registration |
| `RefreshTokenAsync()` | Refresh the player access token |
| `LogoutAsync()` | Revoke the current session |

### Player Documents
| Method | Description |
|--------|-------------|
| `GetPlayerDocumentAsync(playerId, key)` | Get a JSON document by key |
| `SetPlayerDocumentAsync(playerId, key, valueJson, version?)` | Write a JSON document |
| `DeletePlayerDocumentAsync(playerId, key)` | Delete a document |
| `BatchGetPlayerDocumentsAsync(playerId, keys[])` | Fetch multiple keys in one call |
| `BatchWritePlayerDocumentsAsync(playerId, writes[])` | Write multiple keys atomically |

### Leaderboards
| Method | Description |
|--------|-------------|
| `SubmitScoreAsync(leaderboardId, playerId, score, metadata?)` | Submit a score |
| `GetTopAsync(leaderboardId, limit)` | Get top N entries |
| `GetPlayerStandingAsync(leaderboardId, playerId)` | Get rank + score for a player |
| `GetAroundPlayerAsync(leaderboardId, playerId, radius)` | Get neighbours in the ranking |

### Economy
| Method | Description |
|--------|-------------|
| `GetPlayerEconomyAsync(playerId)` | Get balances + inventory |
| `AdjustEconomyAsync(playerId, balances?, inventory?)` | Atomic credit/deduct |

### Matchmaking
| Method | Description |
|--------|-------------|
| `JoinMatchmakingAsync(playerId, gameMode, region)` | Join a matchmaking queue |
| `GetMatchmakingStatusAsync()` | Poll for match result |
| `LeaveMatchmakingAsync(playerId)` | Leave the queue |

### Server Registry *(server token required)*
| Method | Description |
|--------|-------------|
| `RegisterServerAsync(ServerRegistration)` | Register this server instance |
| `HeartbeatAsync(serverId)` | Send a keepalive heartbeat |
| `DeregisterServerAsync(serverId)` | Remove from registry on shutdown |
| `ListServersAsync(region?, mapName?, gameMode?)` | Browse available servers |

### Config
| Method | Description |
|--------|-------------|
| `DownloadActiveConfigBundleAsync()` | Download the active config bundle as `byte[]` |
