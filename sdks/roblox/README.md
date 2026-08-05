# Crux SDK for Roblox

A drop-in alternative to `DataStoreService` and `OrderedDataStore`, plus
seasonal leaderboards, economy, matchmaking and the server registry. One
ModuleScript, no dependencies beyond `HttpService`.

Backed by [Crux](https://crux.supercraft.host/). MIT licensed.

---

## Install

**Wally**

```toml
[server-dependencies]
Crux = "supercraft/crux@2.0.0"
```

**Manual**

Copy `Crux.lua` into `ServerScriptService` as a ModuleScript named `Crux`.

Either way it is **server-only**. `Crux.lua` calls `HttpService` and carries a
ServerToken, so requiring it from a LocalScript will not work and would expose
your token to clients. That is why the Wally package declares
`realm = "server"`.

## Enable HTTP requests

Roblox blocks outbound HTTP by default. In Studio: **Game Settings → Security →
Allow HTTP Requests**. Without it every call fails with
`Http requests are not enabled`.

## Quick start

```lua
local Crux = require(game.ServerScriptService.Crux)

local crux = Crux.init(
    "YOUR_PROJECT_ID",     -- from GET /v1/projects, or the dashboard
    "YOUR_SERVER_TOKEN",   -- project dashboard -> Tokens
    "YOUR_ENVIRONMENT_ID"  -- from GET /v1/projects/{id}/environments
)
```

### Player documents

`GetDataStore` returns a handle with a `DataStoreService`-shaped API, so most
existing code ports by changing the two setup lines.

```lua
local store = crux:GetDataStore("save")

local data, version = store:GetAsync(player.UserId)  -- nil if never saved
store:SetAsync(player.UserId, { coins = 100, level = 7 })
```

`GetAsync` returns the value **and** its version. Pass the version back on write
to get optimistic locking, so two servers saving the same player cannot silently
clobber each other, which is the failure mode plain DataStores are prone to.

### Leaderboards

```lua
crux:SubmitScore("weekly", player.UserId, 1500, { level = 7 })
local top      = crux:GetLeaderboardTop("weekly", 10)
local standing = crux:GetPlayerStanding("weekly", player.UserId)
local around   = crux:GetPlayersAroundPlayer("weekly", player.UserId, 5)
```

### Economy

```lua
local wallet = crux:GetPlayerEconomy(player.UserId)
crux:AdjustEconomy(player.UserId, { coins = -50 }, { potion = 1 })
```

Balances are server-authoritative: the adjustment is applied and validated by
Crux, not by your place, so an exploiter editing client state cannot mint
currency.

### Matchmaking and servers

```lua
crux:JoinMatchmaking(player.UserId, "ranked", "us-east", { mmr = 1200 })
local status = crux:GetMatchStatus(player.UserId)
crux:LeaveMatchmaking(player.UserId)

local servers = crux:GetServers({ region = "us-east" })
local config  = crux:GetActiveConfig()
```

### Verifying a player

```lua
local player = crux:VerifyPlayer(robloxUserId)
```

## Retries

Requests retry up to 3 times on `429` and `503` with exponential back-off
starting at 1 second. Other failures raise immediately, so wrap calls in
`pcall` where a failure should not break the round.

## Full API

Every method maps to a documented REST endpoint. See the
[OpenAPI spec](https://crux.supercraft.host/openapi/v1.yaml) and the
[interactive docs](https://crux.supercraft.host/docs).
