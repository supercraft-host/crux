# Research — why GSB SDKs are open source (May 2026)

This document captures the strategy and competitive landscape behind
publishing the GSB client SDKs under MIT. We keep it in-repo so future
contributors (and future-us) can verify the assumptions still hold.

## Strategy in one paragraph

GSB itself is a hosted, commercial service. The SDKs are useless
without the service, so publishing them as MIT carries zero competitive
risk — every install is a signal that someone is committing to the GSB
HTTP contract. We get the discovery and trust benefits of being a
first-class citizen in each engine's package ecosystem (npm, Godot
Asset Library, UPM, Wally), and the community handles the long tail of
languages we'd otherwise have to staff.

## The competitive landscape

Other backends-as-a-service for games (sources verified May 2026):

| Vendor | License model | Engines covered (first-party) | OSS SDK story |
|---|---|---|---|
| [Nakama](https://github.com/heroiclabs) | Open core (Apache 2.0 server + SDKs) | Unity, Unreal, Godot, JS, C#, Cocos, Defold | Multi-repo, MIT/Apache, very strong |
| [PlayFab](https://playfab.com) | Proprietary | Unity, Unreal, JS, C#, C++, Cocos | Closed-source binaries on most engines |
| [Beamable](https://beamable.com) | Proprietary | Unity-first, partial Unreal | Closed |
| [AccelByte](https://accelbyte.io) | Proprietary | Unity, Unreal | Closed |
| [LootLocker](https://lootlocker.com) | Proprietary | Unity, Unreal, JS, Godot | Open client SDKs (MIT), closed server |
| [Photon](https://www.photonengine.com) | Proprietary | Unity, Unreal | Closed |

Two observations:

1. **The proprietary-SDK model is a competitive weakness, not a moat.**
   Closed-source SDKs limit who can audit, fork, embed, or hot-fix the
   client. Nakama and LootLocker treat their SDKs as marketing surface;
   PlayFab and AccelByte treat them as IP. Indie devs notice the
   difference and choose accordingly.
2. **The single biggest correlate of SDK adoption is being natively
   listed in the engine's package channel.** Godot Asset Library
   effectively requires public source; UPM via Git URL requires a
   public repo; npm doesn't *require* OSS but registries discount
   private packages; Wally is GitHub-backed. Closed SDKs miss every one
   of these channels.

## Sources

- [Best Real-Time Game Backends 2026 — Namazu studios](https://namazustudios.com/best-real-time-game-backends/)
- [Best Game Backend Service in 2026 — Leadr](https://www.leadr.gg/blog/the-best-backend-service-for-your-game-in-2026)
- [Best Mobile Game Backend Providers 2026 — Metaplay](https://www.metaplay.io/blog/best-game-backend-providers)
- [Why Studios Are Re-Evaluating PlayFab — AccelByte](https://accelbyte.io/blog/why-studios-are-re-evaluating-playfab-and-how-accelbyte-compares)
- [Nakama Alternatives — SourceForge](https://sourceforge.net/software/product/Nakama-Game-Server/alternatives)
- [Beamable vs Nakama](https://beamable.com/blog/choosing-the-right-backend-beamable-vs-nakama)
- [Top PlayFab Alternatives — Slashdot](https://slashdot.org/software/p/PlayFab/alternatives)
- [Nakama vs PlayFab — Code Wizards](https://codewizards.io/nakama-vs-playfab-online-player-services/)
- [Selecting the Right Backend — LootLocker](https://lootlocker.com/blog/selecting-the-right-backend-for-your-game)
- [Heroic Labs (Nakama) GitHub](https://github.com/heroiclabs/)

## Distribution channels we target

| SDK | Native channel | Requires public source? | Discovery payoff |
|---|---|---|---|
| JS | npm | no, but very strongly preferred | weekly downloads on npm, GitHub stars feed |
| Godot | [Godot Asset Library](https://godotengine.org/asset-library) | **yes** | only listing path for Godot addons |
| Unity | UPM via Git URL, Asset Store | yes for UPM-Git, optional for Asset Store | community standard since Unity 2018 |
| Roblox | [Wally](https://wally.run/) + Toolbox | yes for Wally | Toolbox is opaque; Wally is open |

Closed-source SDKs participate in **zero** of these properly. That's
the upside we're capturing.

## What stays closed

Out of scope for this repo:

- **The GSB server** — that's the product. Hosted at
  [gsb.supercraft.host](https://gsb.supercraft.host/), self-hosting is
  not on the roadmap. See the [Nakama comparison post](https://gsb.supercraft.host/blog/nakama-open-source-vs-managed-backend)
  for why we don't compete on the "you can run it yourself" axis.
- **Internal admin tools and dashboards.**
- **Webhook signing keys and any per-tenant secrets** — those never
  appear in this repo or the OpenAPI spec.

## Future SDKs (community-first)

We'll happily accept community-maintained SDKs in this repo as long as
they (a) consume the [OpenAPI spec](openapi/v1.yaml), (b) ship under
MIT, (c) have a maintainer who answers issues, and (d) follow the
folder layout in [`CONTRIBUTING.md`](CONTRIBUTING.md). Highest priority
gaps:

1. **Unreal Engine (C++ + Blueprint nodes)** — biggest demand after JS.
2. **Rust** — Bevy is small but loud, and adds OSS-credibility surface.
3. **C# (non-Unity)** — Stride, MonoGame, server-side game services.
4. **Python** — tooling, leaderboard analytics, data pipelines.
5. **Defold, Haxe, GDevelop** — niche but loyal communities; each gives
   us a foothold in an ecosystem competitors don't bother with.

The OpenAPI spec gives anyone a 70%-done client in minutes via
`openapi-generator`; the work that's worth doing by hand is the
ergonomic layer (typed builders, retries, batching, idiomatic async).
