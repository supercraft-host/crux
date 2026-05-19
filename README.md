# GSB SDKs

> Open-source client SDKs for [GSB — Supercraft Game Services Backend](https://gsb.supercraft.host/).
> One backend, four first-party SDKs, an [OpenAPI spec](openapi/v1.yaml) for the rest.

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

GSB is the hosted backend behind your game: player auth, persistent
documents, seasonal leaderboards, economy, matchmaking, a server
registry, and signed config delivery. See
[**gsb.supercraft.host**](https://gsb.supercraft.host/) for the product,
[`/pricing`](https://gsb.supercraft.host/pricing) for tiers,
[`/cost-calculator`](https://gsb.supercraft.host/cost-calculator) for
sizing, and the [SDK landing page](https://gsb.supercraft.host/sdk) for
non-technical docs.

This repository ships the four first-party SDKs that bind every supported
engine to the GSB HTTP API. All are MIT.

---

## The four SDKs

| SDK | Status | Channel | Folder | README |
|---|---|---|---|---|
| **JavaScript / TypeScript** | stable | npm: [`@supercraft/gsb`](https://www.npmjs.com/package/@supercraft/gsb) | [`sdks/js/`](sdks/js/) | [`sdks/js/README.md`](sdks/js/README.md) |
| **Godot 4** | stable | Godot Asset Library | [`sdks/godot/`](sdks/godot/) | [`sdks/godot/README.md`](sdks/godot/README.md) |
| **Unity** | stable | UPM (Git URL) + Asset Store | [`sdks/unity/`](sdks/unity/) | [`sdks/unity/README.md`](sdks/unity/README.md) |
| **Roblox (Luau)** | stable | Wally + Toolbox | [`sdks/roblox/`](sdks/roblox/) | [`sdks/roblox/README.md`](sdks/roblox/README.md) |

Need a language we don't list? The [`openapi/v1.yaml`](openapi/v1.yaml)
spec is the source of truth — generate a client with
[openapi-generator](https://openapi-generator.tech/) and you're done.
See [`docs/ARCHITECTURE.md#openapi-first`](docs/ARCHITECTURE.md#openapi-first).

---

## What each SDK covers

| Feature | JS | Godot | Unity | Roblox |
|---|---|---|---|---|
| Anonymous + email auth | ✅ | ✅ | ✅ | ⚠️ Roblox-native |
| JWT refresh / logout | ✅ | ✅ | ✅ | n/a |
| Player Documents (versioned) | ✅ | ✅ | ✅ | ✅ (DataStore-compatible API) |
| Document patch (JSON-Patch) | ❌ | ✅ | ✅ | ✅ |
| Batch document read/write | ✅ | ✅ | ✅ | ❌ |
| Seasonal Leaderboards | ✅ | ✅ | ✅ | ✅ |
| Player Economy | ✅ | ✅ | ✅ | ✅ |
| Matchmaking | ✅ | ✅ | ✅ | ✅ |
| Server Registry | ✅ | ✅ | ✅ | n/a (Roblox JobId) |
| Signed Config Delivery | ✅ | ✅ | ✅ | ✅ |

`⚠️ Roblox-native` means we use [`HttpService:GetAsync`-based player
verification](https://gsb.supercraft.host/blog/roblox-httpservice-external-backend)
instead of email/password — Roblox already has its own identity layer.
The "n/a" rows are intentional, not gaps; see each README's "Roblox
differences" section for the why.

---

## Quick links into the product

### Backend concepts (the same docs across every SDK)
- [Cross-progression / cross-save patterns](https://gsb.supercraft.host/blog/cross-progression-and-cross-save-backend)
- [Player data schema — NoSQL vs SQL](https://gsb.supercraft.host/blog/player-data-schema-design-nosql-vs-sql)
- [Guest login and account upgrade](https://gsb.supercraft.host/blog/guest-login-and-account-upgrade)
- [Skill-based matchmaking architecture](https://gsb.supercraft.host/blog/skill-based-matchmaking-architecture-2026)
- [Game server orchestration guide](https://gsb.supercraft.host/blog/game-server-orchestration-guide)
- [Dedicated server hosting + backend, unified stack](https://gsb.supercraft.host/blog/dedicated-server-hosting-and-backend-unified-stack)
- [Live-ops backend features compared](https://gsb.supercraft.host/blog/live-ops-backend-features-comparison)
- [Game backend as a service — complete guide](https://gsb.supercraft.host/blog/game-backend-as-a-service-complete-guide)

### Coming from somewhere else?
- [Migrate from PlayFab](https://gsb.supercraft.host/blog/migrate-from-playfab-to-supercraft-gsb)
- [Firebase for games — what to use instead](https://gsb.supercraft.host/blog/firebase-for-games-alternative-supercraft-gsb-2026)
- [Beamable vs Supercraft GSB](https://gsb.supercraft.host/blog/beamable-vs-supercraft-gsb-comparison)
- [AccelByte vs Supercraft GSB](https://gsb.supercraft.host/blog/accelbyte-vs-supercraft-gsb-comparison)
- [Nakama (open source) vs managed backend](https://gsb.supercraft.host/blog/nakama-open-source-vs-managed-backend)
- [Colyseus vs managed backend](https://gsb.supercraft.host/blog/colyseus-vs-managed-backend)

### Roblox-specific
- [Roblox HttpService → external backend](https://gsb.supercraft.host/blog/roblox-httpservice-external-backend)
- [Roblox DataStore vs external database](https://gsb.supercraft.host/blog/roblox-datastore-vs-external-database)
- [Roblox cross-experience progression](https://gsb.supercraft.host/blog/roblox-cross-experience-progression)

---

## Repository layout

```
gsb-sdks/
├── README.md             you are here
├── RESEARCH.md           why these SDKs exist, OSS landscape, sources
├── CHANGELOG.md          monorepo-level changes
├── CONTRIBUTING.md       dev setup, PR rules, how to add a new language
├── LICENSE               MIT
├── docs/
│   ├── ARCHITECTURE.md   how the SDKs are organized + OpenAPI-first story
│   ├── AUTH.md           the three auth flows (api key / server token / player jwt)
│   └── ERROR_HANDLING.md error model shared across SDKs
├── openapi/
│   └── v1.yaml           OpenAPI 3.0.3 spec — the source of truth
├── sdks/
│   ├── js/               TypeScript SDK (`@supercraft/gsb`)
│   ├── godot/            Godot 4 GDScript addon
│   ├── unity/            Unity UPM package (`host.supercraft.gsb`)
│   └── roblox/           Roblox Luau module
└── examples/
    ├── js/leaderboard.ts
    ├── godot/leaderboard.gd
    ├── unity/Leaderboard.cs
    └── roblox/leaderboard.lua
```

---

## Quick start by stack

Five-minute integrations, in their natural form for each engine. Each
points at the SDK's own README for the full surface.

### Browser / Node.js — `@supercraft/gsb`

```bash
npm install @supercraft/gsb
```

```ts
import { GSBClient } from "@supercraft/gsb";

const gsb = GSBClient.forPlayer(
  "https://gsb.supercraft.host",
  "proj_xxx", "env_xxx", "gsb_apikey_xxx"
);
const auth = await gsb.loginAnonymous();
await gsb.submitScore("weekly", auth.player_id, 9900);
const top = await gsb.getTop("weekly", 10);
```
See [`sdks/js/README.md`](sdks/js/README.md).

### Godot 4 — drop-in addon

```gdscript
GSB.init_player("https://gsb.supercraft.host", "proj_xxx", "env_xxx", "gsb_apikey_xxx")
var auth = await GSB.login_anonymous()
await GSB.submit_score("weekly", auth.player_id, 9900.0)
```
See [`sdks/godot/README.md`](sdks/godot/README.md).

### Unity — UPM via Git URL

```
git+https://gitlab.com/supercraft1/game-server-backend.git?path=sdks/unity/Packages/host.supercraft.sdk
```

```csharp
var gsb = GSBClient.ForPlayer(
    "https://gsb.supercraft.host", "proj_xxx", "env_xxx", "gsb_apikey_xxx");
var auth = await gsb.LoginAnonymousAsync();
await gsb.SubmitScoreAsync("weekly", auth.player_id, 9900);
```
See [`sdks/unity/README.md`](sdks/unity/README.md).

### Roblox — `require()` the module

```lua
local GSB = require(game.ServerScriptService.GSB)
local gsb = GSB.init("proj_xxx", "gsb_servertoken_xxx", "env_xxx")
gsb:SubmitScore("weekly", player.UserId, 9900)
```
See [`sdks/roblox/README.md`](sdks/roblox/README.md).

---

## OpenAPI-first

The HTTP wire format is documented in [`openapi/v1.yaml`](openapi/v1.yaml).
Every first-party SDK in this repo is hand-written against that spec, but
nothing stops you from autogenerating one for any language:

```bash
docker run --rm -v "${PWD}:/local" openapitools/openapi-generator-cli \
    generate -i /local/openapi/v1.yaml -g python -o /local/generated-python
```

See [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) for why we hand-write
the four first-party SDKs anyway (ergonomics) and when an autogenerated
client is enough (CI scripts, dashboards, batch jobs).

---

## Contributing

PRs welcome inside the per-SDK scope. Cross-SDK refactors (renaming a
method on all four at once) should land in a single MR. See
[`CONTRIBUTING.md`](CONTRIBUTING.md).

Want to add a new language (Unreal, Rust, Python, Defold, Haxe, …)? Open
an issue first so we can sketch the directory layout and CI plumbing.

---

## License

[MIT](LICENSE). Use these SDKs however you like, including in commercial
games and in tools that talk to non-GSB backends. The OpenAPI spec is
also MIT — autogenerated clients inherit the same terms.
