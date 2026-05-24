# Crux - Unity SDK

> Unity UPM package for [Crux - Crux](https://crux.supercraft.host/).
> Unity 2021.3 LTS or newer.

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

---

## Install

### Option A - UPM via Git URL *(recommended)*

In Unity: **Window → Package Manager → + → Add package from git URL…**
and paste:

```
https://gitlab.com/supercraft1/crux.git?path=sdks/unity/Packages/host.supercraft.sdk
```

UPM will fetch the package and add it to `Packages/manifest.json`. Pin
a version by appending `#v-unity/1.0.0`.

### Option B - Local manifest entry

```json
{
  "dependencies": {
    "host.supercraft.gsb": "https://gitlab.com/supercraft1/crux.git?path=sdks/unity/Packages/host.supercraft.sdk"
  }
}
```

### Option C - Add package from disk

If you've cloned this repo locally, **Window → Package Manager → + →
Add package from disk…** and point at
`Packages/host.supercraft.sdk/package.json`.

---

## Quick start - game client

```csharp
using Supercraft.Crux;
using UnityEngine;

public class GsbBootstrap : MonoBehaviour
{
    async void Start()
    {
        var gsb = GSBClient.ForPlayer(
            baseUrl:       "https://crux.supercraft.host",
            projectId:     "proj_xxx",
            environmentId: "env_xxx",
            apiKey:        "gsb_apikey_xxx"
        );

        // Log in (anonymous, email, or OAuth).
        var auth = await gsb.LoginAnonymousAsync();
        Debug.Log($"Player: {auth.player_id}");

        // Save player data - any JSON shape works.
        await gsb.SetPlayerDocumentAsync(
            auth.player_id, "profile",
            "{\"name\":\"Ada\",\"level\":5}"
        );

        // Submit a leaderboard score.
        await gsb.SubmitScoreAsync("global-score", auth.player_id, 1234);

        // Get top 10.
        var top = await gsb.GetTopAsync("global-score", 10);
        foreach (var e in top)
            Debug.Log($"#{e.rank} {e.player_id}: {e.score}");
    }
}
```

## Quick start - dedicated server

```csharp
using Supercraft.Crux;

var gsb = GSBClient.ForServer(
    baseUrl:       "https://crux.supercraft.host",
    projectId:     "proj_xxx",
    environmentId: "env_xxx",
    serverToken:   "gsb_servertoken_xxx"
);

var server = await gsb.RegisterServerAsync(new ServerRegistration {
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

// Heartbeat every 30 seconds.
await gsb.HeartbeatAsync(server.server_id);

// Read a player document server-authoritatively.
var doc = await gsb.GetPlayerDocumentAsync("player-uuid", "inventory");
Debug.Log(doc.raw_value); // raw JSON string
```

> **Don't ship a server token in a player build.** It carries full
> project authority. See [`docs/AUTH.md`](../../docs/AUTH.md).

---

## API reference

### Static factories

| Method | Description |
|---|---|
| `GSBClient.ForPlayer(baseUrl, projectId, environmentId, apiKey)` | Client mode |
| `GSBClient.ForServer(baseUrl, projectId, environmentId, serverToken)` | Server mode |

### Auth - [concepts](https://crux.supercraft.host/blog/guest-login-and-account-upgrade)

| Method | Description |
|---|---|
| `LoginAnonymousAsync()` | Guest login |
| `LoginEmailAsync(email, password)` | Email login |
| `RegisterEmailAsync(email, password)` | Email registration |
| `RefreshTokenAsync()` | Refresh access token (called automatically by the SDK) |
| `LogoutAsync()` | Revoke the current session |

### Player Documents - [concepts](https://crux.supercraft.host/blog/cross-progression-and-cross-save-backend)

| Method | Description |
|---|---|
| `GetPlayerDocumentAsync(playerId, key)` | Get a JSON document by key |
| `SetPlayerDocumentAsync(playerId, key, valueJson, version?)` | Write a JSON document |
| `PatchPlayerDocumentAsync(playerId, key, operations, version?)` | JSON-Patch a document in place |
| `DeletePlayerDocumentAsync(playerId, key)` | Delete a document |
| `BatchGetPlayerDocumentsAsync(playerId, keys[])` | Fetch multiple keys |
| `BatchWritePlayerDocumentsAsync(playerId, writes[])` | Write multiple keys atomically |

### Leaderboards - [concepts](https://crux.supercraft.host/blog/esports-tournament-backends-scaling-million-viewer-events)

| Method | Description |
|---|---|
| `SubmitScoreAsync(leaderboardId, playerId, score, metadataJson?)` | Submit a score |
| `GetTopAsync(leaderboardId, limit)` | Top N entries |
| `GetPlayerStandingAsync(leaderboardId, playerId)` | Rank + score for a player |
| `GetAroundPlayerAsync(leaderboardId, playerId, radius)` | Neighbours in the ranking |

### Economy

| Method | Description |
|---|---|
| `GetPlayerEconomyAsync(playerId)` | Balances + inventory |
| `AdjustEconomyAsync(playerId, balances?, inventory?)` | Atomic credit / deduct |

### Matchmaking - [architecture](https://crux.supercraft.host/blog/skill-based-matchmaking-architecture-2026)

| Method | Description |
|---|---|
| `JoinMatchmakingAsync(playerId, gameMode, region)` | Join a queue |
| `GetMatchmakingStatusAsync()` | Poll for result |
| `LeaveMatchmakingAsync(playerId)` | Leave the queue |

### Server Registry - [orchestration guide](https://crux.supercraft.host/blog/game-server-orchestration-guide)

*Server token required.*

| Method | Description |
|---|---|
| `RegisterServerAsync(ServerRegistration)` | Register this instance |
| `HeartbeatAsync(serverId)` | Send a keepalive |
| `DeregisterServerAsync(serverId)` | Remove on shutdown |
| `ListServersAsync(region?, mapName?, gameMode?)` | Browse the registry |

### Config delivery

| Method | Description |
|---|---|
| `DownloadActiveConfigBundleAsync()` | Returns `byte[]` |

Every async method takes an optional `CancellationToken`.

---

## Error handling

All methods throw `GSBException` on HTTP failures:

```csharp
try {
    var doc = await gsb.GetPlayerDocumentAsync(playerId, "inventory");
} catch (GSBException ex) {
    switch (ex.StatusCode)
    {
        case 404: /* first write - no document yet */ break;
        case 409: /* optimistic-concurrency conflict - re-read + retry */ break;
        default:  Debug.LogError($"HTTP {ex.StatusCode}: {ex.Message}"); break;
    }
}
```

The SDK already retries on `429`/`503` with exponential backoff. See
[`docs/ERROR_HANDLING.md`](../../docs/ERROR_HANDLING.md).

---

## Unity version support

| Unity | Status | Notes |
|---|---|---|
| 2021.3 LTS | ✅ | Minimum supported. |
| 2022.3 LTS | ✅ | Tested. |
| 2023.x / 6.x | ✅ | Tested. |
| 2020.x | ❌ | `Task`-friendly APIs not available. |

Works in: standalone (Win/Mac/Linux), iOS, Android, WebGL, dedicated
server (headless) builds. WebGL CORS: ensure your backend serves the
right `Access-Control-Allow-Origin` headers, or use `crux.supercraft.host`
(already configured for browser games).

---

## Examples

- [`examples/unity/Leaderboard.cs`](../../examples/unity/Leaderboard.cs)
  - weekly leaderboard scene script.

---

## FAQ

**Does the SDK pull any third-party packages?**  No. Pure C# + `HttpClient`.

**Can I use it on the IL2CPP backend?**  Yes - no reflection, no dynamic
code generation.

**Can I use it on Dedicated Server Build Target?**  Yes - that's the
recommended target for `ForServer` mode.

**Where can I see end-to-end Unity examples?**  See
[Survival/co-op game backend patterns](https://crux.supercraft.host/blog/survival-coop-game-backend-patterns)
and [VR/AR/spatial computing backends](https://crux.supercraft.host/blog/vr-ar-spatial-computing-game-backends).

---

## Don't want to host a backend?

[**crux.supercraft.host**](https://crux.supercraft.host/) runs Crux so you
don't have to. Pricing: [/pricing](https://crux.supercraft.host/pricing).
Sizing: [/cost-calculator](https://crux.supercraft.host/cost-calculator).
Migration guides:
[PlayFab](https://crux.supercraft.host/blog/migrate-from-playfab-to-supercraft-gsb),
[Beamable](https://crux.supercraft.host/blog/beamable-vs-supercraft-gsb-comparison),
[AccelByte](https://crux.supercraft.host/blog/accelbyte-vs-supercraft-gsb-comparison),
[Firebase](https://crux.supercraft.host/blog/firebase-for-games-alternative-supercraft-gsb-2026).

## License

[MIT](LICENSE).
