# Supercraft Crux - JavaScript / TypeScript SDK

Fetch-based SDK for [Crux (Game Services Backend)](https://supercraft.dev). Works in Node.js 18+, browsers, and any runtime with a native `fetch` API.

## Installation

```bash
npm install crux-sdk
```

## Getting your credentials

Create a project in the [Crux dashboard](https://crux.supercraft.host), then copy:

- **Project ID** and **Environment ID** — UUIDs shown on the Projects and Environments pages.
- **API key** — the secret string on the Credentials page. It is project-scoped and safe to ship in a game client (it only lets players authenticate and read/write their own data).
- **Server token** — for trusted backends and dedicated servers. Keep it server-side; never ship it in a client build.
- **Leaderboard ID** — the UUID of a leaderboard you created on the Leaderboards page. Runtime leaderboard calls take this UUID, not the display key.

## Quick start - game client (browser / web game)

```ts
import { CruxClient } from "crux-sdk";

const gsb = CruxClient.forPlayer(
  "https://crux.supercraft.host",
  "<PROJECT_ID>",      // UUID
  "<ENVIRONMENT_ID>",  // UUID
  "<API_KEY>",         // secret from the Credentials page
);

// Log in (guest)
const auth = await gsb.loginAnonymous();
console.log("Player:", auth.player_id);

// Save data
await gsb.setPlayerDocument(auth.player_id, "settings", { volume: 0.8 });

// Submit a score. The first argument is the leaderboard's UUID.
const LEADERBOARD_ID = "<LEADERBOARD_UUID>";
await gsb.submitScore(LEADERBOARD_ID, auth.player_id, 9900);

// Get leaderboard
const top = await gsb.getTop(LEADERBOARD_ID, 10);
top.forEach(e => console.log(`#${e.rank} ${e.player_id}: ${e.score}`));
```

## Quick start - server (Node.js backend / game server)

```ts
import { CruxClient } from "crux-sdk";

const gsb = CruxClient.forServer(
  "https://crux.supercraft.host",
  "<PROJECT_ID>",      // UUID
  "<ENVIRONMENT_ID>",  // UUID
  "<SERVER_TOKEN>",    // secret from the Credentials page - keep server-side
);

// Register
const server = await gsb.registerServer({
  server_id:    "node-01",
  name:         "Deathmatch EU #1",
  region:       "eu-west",
  map_name:     "forest",
  game_mode:    "deathmatch",
  player_count: 0,
  max_players:  16,
  address:      "198.51.100.1",
  port:         7777,
  version:      "1.0.0",
});

// Heartbeat (call every 30 s)
setInterval(() => gsb.heartbeat(server.server_id), 30_000);

// Clean deregister on shutdown
process.on("SIGTERM", async () => {
  await gsb.deregisterServer(server.server_id);
  process.exit(0);
});
```

## API reference

### Static factories
| Call | Description |
|------|-------------|
| `CruxClient.forServer(url, projectId, envId, serverToken)` | Server-side mode |
| `CruxClient.forPlayer(url, projectId, envId, apiKey)` | Client-side mode |

### Auth
| Method | Description |
|--------|-------------|
| `loginAnonymous()` | Guest login |
| `loginEmail(email, password)` | Email login |
| `registerEmail(email, password)` | Email registration |
| `refreshAccessToken()` | Refresh access token |
| `logout()` | Revoke the session |

### Player Documents
| Method | Description |
|--------|-------------|
| `getPlayerDocument<T>(playerId, key)` | Get a typed document |
| `setPlayerDocument<T>(playerId, key, value, version?)` | Write a document |
| `deletePlayerDocument(playerId, key)` | Delete a document |
| `batchGetPlayerDocuments<T>(playerId, keys[])` | Fetch multiple keys |
| `batchWritePlayerDocuments<T>(playerId, writes[])` | Write multiple keys atomically |

### Leaderboards
| Method | Description |
|--------|-------------|
| `submitScore(leaderboardId, playerId, score, metadata?)` | Submit a score |
| `getTop(leaderboardId, limit)` | Top N entries |
| `getPlayerStanding(leaderboardId, playerId)` | Player's rank + score (null if unranked) |
| `getAroundPlayer(leaderboardId, playerId, radius)` | Neighbours in the ranking |

> `leaderboardId` is the leaderboard's **UUID** (returned by create / shown in the dashboard), not its display key like `"weekly"`.

### Economy
| Method | Description |
|--------|-------------|
| `getPlayerEconomy(playerId)` | Balances + inventory |
| `adjustEconomy(playerId, balances?, inventory?)` | Atomic credit/deduct |

### Matchmaking
| Method | Description |
|--------|-------------|
| `joinMatchmaking(playerId, gameMode, region)` | Join a queue |
| `getMatchmakingStatus()` | Poll for result |
| `leaveMatchmaking(playerId)` | Leave the queue |

### Server Registry *(server token required)*
| Method | Description |
|--------|-------------|
| `registerServer(registration)` | Register this instance |
| `heartbeat(serverId)` | Send a keepalive |
| `deregisterServer(serverId)` | Remove on shutdown |
| `listServers({region?, mapName?, gameMode?})` | Browse servers |

### Config
| Method | Description |
|--------|-------------|
| `downloadActiveConfigBundle()` | Returns `Promise<ArrayBuffer>` |

## Error handling

All methods throw `CruxError` on HTTP errors:

```ts
import { CruxClient, CruxError } from "crux-sdk";

try {
  const doc = await gsb.getPlayerDocument(playerId, "inventory");
} catch (e) {
  if (e instanceof CruxError) {
    console.error(`HTTP ${e.statusCode}:`, e.message);
  }
}
```
