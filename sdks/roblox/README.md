# Crux - Roblox SDK

> Luau module for [Crux - Crux](https://crux.supercraft.host/).
> Server-side only - runs inside a Roblox experience's `ServerScriptService`.

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

---

## Install

### Wally *(recommended)*

In your project's `wally.toml`:

```toml
[dependencies]
Crux = "supercraft/gsb@1.0.0"
```

Then `wally install`.

### Manual

Drag [`Crux.lua`](Crux.lua) into `ServerScriptService`. That's it.

### Rojo

Add to your `default.project.json`:

```json
"ServerScriptService": {
  "Crux": { "$path": "src/Crux.lua" }
}
```

---

## Quick start

```lua
local Crux = require(game.ServerScriptService.Crux)

-- Initialise once at server start. Use a server token only.
local gsb = Crux.init(
    "proj_xxx",                     -- project ID
    "gsb_servertoken_xxx",          -- server token
    "env_xxx"                       -- environment ID
)

-- Save player progression (DataStoreService-compatible API).
local saves = gsb:GetDataStore("saves")
saves:SetAsync(player.UserId, {
    level = 12,
    gold  = 4200,
})

-- Submit a leaderboard score.
gsb:SubmitScore("weekly", player.UserId, 9900)

-- Read top 10.
local top = gsb:GetLeaderboardTop("weekly", 10)
for _, e in ipairs(top.entries or top) do
    print(("#%d  %s  %d"):format(e.rank, e.player_id, e.score))
end
```

---

## Why the Roblox SDK looks different

The other Crux SDKs (JS / Godot / Unity) ship two modes: **client** and
**server**. Roblox doesn't work that way:

- Roblox already has its own identity layer (every player has a
  permanent `UserId`).
- Roblox scripts are split into "client" (runs on the user's device,
  untrusted) and "server" (runs in Roblox's datacenter, trusted).
- `HttpService` (the only way to make outbound HTTP calls) is **only
  available on server scripts**.

So the Roblox SDK runs server-side with a server token, identifies
players by their Roblox `UserId`, and presents a familiar
DataStoreService-shaped API where it makes sense. See
[Roblox HttpService → external backend on crux.supercraft.host](https://crux.supercraft.host/blog/roblox-httpservice-external-backend)
for the architectural picture, and
[Roblox DataStore vs external database](https://crux.supercraft.host/blog/roblox-datastore-vs-external-database)
for the trade-offs.

What this means in practice:

| Concept (other SDKs) | Roblox equivalent |
|---|---|
| `loginAnonymous()` | `gsb:VerifyPlayer(player.UserId)` |
| `setPlayerDocument(pid, key, value)` | `gsb:GetDataStore(key):SetAsync(pid, value)` |
| `getPlayerDocument(pid, key)` | `gsb:GetDataStore(key):GetAsync(pid)` |
| Server-registry (`registerServer`) | n/a - Roblox `game.JobId` already identifies servers |

---

## API reference

### Init

| Call | Description |
|---|---|
| `Crux.init(projectID, serverToken, environmentID)` | Configure the module (call once at server boot) |

### Player Documents (DataStore-shaped) - [concepts](https://crux.supercraft.host/blog/cross-progression-and-cross-save-backend)

| Call | Description |
|---|---|
| `gsb:GetDataStore(name)` | Returns a DataStore-shaped table |
| `store:GetAsync(key)` | Read a value |
| `store:SetAsync(key, value)` | Write a value |
| `store:UpdateAsync(key, mutator)` | Optimistic update (like `:UpdateAsync` on Roblox DataStore) |
| `store:RemoveAsync(key)` | Delete a value |

### Player verification

| Call | Description |
|---|---|
| `gsb:VerifyPlayer(robloxUserID)` | Establish (or get) a Crux player record for a Roblox user |

### Leaderboards - [esports backends post](https://crux.supercraft.host/blog/esports-tournament-backends-scaling-million-viewer-events)

| Call | Description |
|---|---|
| `gsb:SubmitScore(leaderboardID, playerID, score, metadata?)` | Submit a score |
| `gsb:GetLeaderboardTop(leaderboardID, limit)` | Top N |
| `gsb:GetPlayerStanding(leaderboardID, playerID)` | A player's rank + score |
| `gsb:GetPlayersAroundPlayer(leaderboardID, playerID, radius)` | Neighbours |

### Economy

| Call | Description |
|---|---|
| `gsb:GetPlayerEconomy(playerID)` | Balances + inventory |
| `gsb:AdjustEconomy(playerID, balanceAdjustments, inventoryAdjustments)` | Atomic credit / deduct |

### Matchmaking - [skill-based MM architecture](https://crux.supercraft.host/blog/skill-based-matchmaking-architecture-2026)

| Call | Description |
|---|---|
| `gsb:JoinMatchmaking(playerID, gameMode, region, metadata?)` | Join a queue |
| `gsb:GetMatchStatus(playerID)` | Poll for result |
| `gsb:LeaveMatchmaking(playerID)` | Leave the queue |

### Server browser

| Call | Description |
|---|---|
| `gsb:GetServers(filters)` | Browse the registry (Roblox can't *register* servers via Crux; use `game.JobId` to identify your own) |

### Config delivery

| Call | Description |
|---|---|
| `gsb:GetActiveConfig()` | Returns the active config bundle (decoded JSON) |

---

## Error handling

All blocking calls run inside `HttpService` and automatically retry on
`429`/`503`. Calls that return a result return a Lua table:

```lua
local top = gsb:GetLeaderboardTop("weekly", 10)
if top.error then
    warn(("Crux %d: %s"):format(top.status, top.error))
else
    -- success - iterate
end
```

For methods that don't return data (`SetAsync`, `RemoveAsync`,
`SubmitScore`, `Heartbeat`), wrap in `pcall` if you need to handle
failure explicitly:

```lua
local ok, err = pcall(function()
    return saves:SetAsync(player.UserId, payload)
end)
if not ok then
    warn("Crux write failed: " .. tostring(err))
end
```

See [`docs/ERROR_HANDLING.md`](../../docs/ERROR_HANDLING.md).

---

## Cross-experience progression

Crux's killer Roblox feature is **shared player data across different
Roblox experiences in your account**. Two experiences using the same
Crux `projectID` see the same player documents and economy:

```lua
-- In Experience A (a lobby):
saves:SetAsync(player.UserId, { gold = 100, skin = "knight" })

-- In Experience B (a battle arena):
local data = saves:GetAsync(player.UserId)
print(data.gold) -- 100 - set by Experience A
```

This is impossible with Roblox's built-in DataStoreService, which scopes
data per experience. See [Roblox cross-experience progression on
crux.supercraft.host](https://crux.supercraft.host/blog/roblox-cross-experience-progression).

---

## HTTP budget

Roblox `HttpService` has rate limits per game server. The SDK is
designed to fit comfortably inside them at typical traffic - every call
is one HTTP request, no polling. For high-traffic games batch your
writes via `UpdateAsync` rather than calling `SetAsync` from every
script that touches the data.

---

## Examples

- [`examples/roblox/leaderboard.lua`](../../examples/roblox/leaderboard.lua)
  - leaderboard end-to-end in a server script.

---

## FAQ

**Why does it require HttpService?**  Crux is an external service. You
must enable HttpService in Game Settings → Security → "Allow HTTP
Requests".

**Can I call Crux from a LocalScript?**  No. `HttpService` is server-only,
and exposing a server token to clients would be catastrophic. Have your
server script handle Crux calls and bridge results to clients via
RemoteEvents.

**Does it work in Roblox Studio?**  Yes - Studio's "Run" / "Start"
flow has HttpService enabled when you tick the setting. Test on a real
private-server place too.

---

## Don't want to operate this yourself?

[**crux.supercraft.host**](https://crux.supercraft.host/) is Crux managed.
Pricing: [/pricing](https://crux.supercraft.host/pricing). Sizing:
[/cost-calculator](https://crux.supercraft.host/cost-calculator). Roblox
deep-dives:
[HttpService → external backend](https://crux.supercraft.host/blog/roblox-httpservice-external-backend),
[DataStore vs external database](https://crux.supercraft.host/blog/roblox-datastore-vs-external-database),
[Cross-experience progression](https://crux.supercraft.host/blog/roblox-cross-experience-progression).

## License

[MIT](LICENSE).
