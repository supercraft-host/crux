# `@supercraft/gsb` - JavaScript / TypeScript SDK

> Fetch-based client for [Crux - Crux](https://crux.supercraft.host/).
> Works in Node.js 18+, browsers, Deno, Bun, Cloudflare Workers, and any
> runtime with native `fetch`.

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![npm](https://img.shields.io/npm/v/@supercraft/gsb.svg)](https://www.npmjs.com/package/@supercraft/gsb)

---

## Install

```bash
npm install @supercraft/gsb
# or: pnpm add @supercraft/gsb
# or: yarn add @supercraft/gsb
```

No native dependencies. ESM-only - if you're stuck on CommonJS, use a
dynamic `import()`.

## Quick start - game client

```ts
import { GSBClient } from "@supercraft/gsb";

const gsb = GSBClient.forPlayer(
  "https://crux.supercraft.host",
  "proj_xxx",
  "env_xxx",
  "gsb_apikey_xxx"
);

const auth = await gsb.loginAnonymous();
console.log("Player:", auth.player_id);

await gsb.setPlayerDocument(auth.player_id, "settings", {
  volume: 0.8,
  lang: "en",
});

await gsb.submitScore("weekly", auth.player_id, 9900);

const top = await gsb.getTop("weekly", 10);
top.forEach(e => console.log(`#${e.rank}  ${e.player_id}  ${e.score}`));
```

## Quick start - dedicated server / your backend

```ts
import { GSBClient } from "@supercraft/gsb";

const gsb = GSBClient.forServer(
  "https://crux.supercraft.host",
  "proj_xxx",
  "env_xxx",
  "gsb_servertoken_xxx"
);

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

setInterval(() => gsb.heartbeat(server.server_id), 30_000);

process.on("SIGTERM", async () => {
  await gsb.deregisterServer(server.server_id);
  process.exit(0);
});
```

> **Don't ship server tokens to browser builds.** They grant full
> project authority. See [`docs/AUTH.md`](../../docs/AUTH.md).

---

## API reference

### Static factories

| Call | Description |
|---|---|
| `GSBClient.forPlayer(url, projectId, envId, apiKey)` | Client-side (game client) |
| `GSBClient.forServer(url, projectId, envId, serverToken)` | Server-side (dedicated game server, your backend) |

### Auth - [concepts](https://crux.supercraft.host/blog/guest-login-and-account-upgrade)

| Method | Returns | Description |
|---|---|---|
| `loginAnonymous()` | `AuthResult` | Guest login |
| `loginEmail(email, password)` | `AuthResult` | Email login |
| `registerEmail(email, password)` | `AuthResult` | Email registration |
| `refreshAccessToken()` | `AuthResult` | Refresh access token (called automatically by the SDK before expiry) |
| `logout()` | `void` | Revoke the current session |

### Player Documents - [concepts](https://crux.supercraft.host/blog/cross-progression-and-cross-save-backend)

| Method | Description |
|---|---|
| `getPlayerDocument<T>(playerId, key)` | Get a typed document |
| `setPlayerDocument<T>(playerId, key, value, version?)` | Write a document; pass `version` for optimistic concurrency |
| `deletePlayerDocument(playerId, key)` | Delete a document |
| `batchGetPlayerDocuments<T>(playerId, keys[])` | Fetch multiple keys in one call |
| `batchWritePlayerDocuments<T>(playerId, writes[])` | Write multiple keys atomically |

See [Player data schema - NoSQL vs SQL on crux.supercraft.host](https://crux.supercraft.host/blog/player-data-schema-design-nosql-vs-sql)
for design guidance on what to keep in documents vs. dedicated tables.

### Leaderboards - [concepts](https://crux.supercraft.host/blog/esports-tournament-backends-scaling-million-viewer-events)

| Method | Description |
|---|---|
| `submitScore(leaderboardId, playerId, score, metadata?)` | Submit a score |
| `getTop(leaderboardId, limit)` | Top N entries |
| `getPlayerStanding(leaderboardId, playerId)` | Player's rank + score (or `null`) |
| `getAroundPlayer(leaderboardId, playerId, radius)` | Neighbours in the ranking |

### Economy - [live-ops patterns](https://crux.supercraft.host/blog/live-ops-backend-features-comparison)

| Method | Description |
|---|---|
| `getPlayerEconomy(playerId)` | Balances + inventory |
| `adjustEconomy(playerId, balances?, inventory?)` | Atomic credit / deduct on the server |

### Matchmaking - [architecture](https://crux.supercraft.host/blog/skill-based-matchmaking-architecture-2026)

| Method | Description |
|---|---|
| `joinMatchmaking(playerId, gameMode, region)` | Join a queue |
| `getMatchmakingStatus()` | Poll for match result |
| `leaveMatchmaking(playerId)` | Leave the queue |

### Server Registry - [orchestration guide](https://crux.supercraft.host/blog/game-server-orchestration-guide)

*Requires a server token (`forServer`).*

| Method | Description |
|---|---|
| `registerServer(registration)` | Register this instance |
| `heartbeat(serverId)` | Send a keepalive |
| `deregisterServer(serverId)` | Remove on shutdown |
| `listServers({region?, mapName?, gameMode?})` | Browse the registry |

### Config delivery

| Method | Description |
|---|---|
| `downloadActiveConfigBundle()` | Returns `Promise<ArrayBuffer>` - your signed config blob |

---

## Error handling

All methods throw `GSBError` on HTTP failures:

```ts
import { GSBClient, GSBError } from "@supercraft/gsb";

try {
  const doc = await gsb.getPlayerDocument(playerId, "inventory");
} catch (e) {
  if (e instanceof GSBError) {
    if (e.statusCode === 404) {
      // First write - there is no document yet.
    } else if (e.statusCode === 409) {
      // Optimistic-concurrency conflict - re-read and retry.
    } else {
      console.error(`HTTP ${e.statusCode}: ${e.message}`);
    }
  }
}
```

The SDK already retries on `429` and `503` with exponential backoff -
don't wrap calls in your own retry loops. See
[`docs/ERROR_HANDLING.md`](../../docs/ERROR_HANDLING.md).

---

## Runtime support

| Runtime | Tested | Notes |
|---|---|---|
| Node.js 18+ | ✅ | Uses native `fetch`. |
| Node.js < 18 | ❌ | No native `fetch`; polyfill `globalThis.fetch` if you must. |
| Modern browsers | ✅ | Chrome 76+, Firefox 75+, Safari 14+. |
| Bun | ✅ | Native fetch. |
| Deno | ✅ | Native fetch. |
| Cloudflare Workers | ✅ | Native fetch; remember to set `compatibility_date`. |
| React Native | ⚠️ | Works if you polyfill `URLSearchParams`; otherwise fine. |

---

## TypeScript

The SDK is shipped with full `.d.ts` files. Strict mode friendly. The
`<T>` parameters on document methods let you keep your save schema
typed end-to-end:

```ts
interface PlayerSave {
  level: number;
  gold: number;
  inventory: string[];
}

const doc = await gsb.getPlayerDocument<PlayerSave>(playerId, "save");
// doc.value is PlayerSave
```

---

## Examples

- [`examples/js/leaderboard.ts`](../../examples/js/leaderboard.ts) -
  weekly leaderboard wired end-to-end (init → login → submit → fetch).

---

## FAQ

**Why ESM-only?**  Every supported runtime has native ESM as of 2023.
CommonJS adds dual-publish complexity for no real benefit.

**Does it bundle any HTTP library?**  No - just `fetch`. The wheel
file is a few KB.

**Can I use it from a service worker?**  Yes, but the worker needs the
right `fetch` permissions for `https://crux.supercraft.host`.

**Why not just generate the SDK from the OpenAPI spec?**  See
[`docs/ARCHITECTURE.md#openapi-first`](../../docs/ARCHITECTURE.md#openapi-first).
TL;DR: ergonomics. If you need a generated client (e.g. for a Python
data pipeline), use the spec - it's the source of truth.

---

## Don't want to host a backend?

You don't have to. [**crux.supercraft.host**](https://crux.supercraft.host/)
runs Crux so you don't have to operate it. Pricing at
[/pricing](https://crux.supercraft.host/pricing), cost calculator at
[/cost-calculator](https://crux.supercraft.host/cost-calculator),
migration guides:

- [from PlayFab](https://crux.supercraft.host/blog/migrate-from-playfab-to-supercraft-gsb)
- [from Firebase](https://crux.supercraft.host/blog/firebase-for-games-alternative-supercraft-gsb-2026)
- [vs Beamable](https://crux.supercraft.host/blog/beamable-vs-supercraft-gsb-comparison)
- [vs AccelByte](https://crux.supercraft.host/blog/accelbyte-vs-supercraft-gsb-comparison)
- [vs Nakama (self-hosted)](https://crux.supercraft.host/blog/nakama-open-source-vs-managed-backend)

This SDK is MIT - use it against your own backend if you'd rather. The
Crux HTTP contract is fully documented in [`openapi/v1.yaml`](../../openapi/v1.yaml).

## License

[MIT](LICENSE).
