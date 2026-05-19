# Contributing

Thanks for considering a PR. This is a multi-SDK monorepo; the rules
below keep that workable.

## Repository conventions

- **One MR per SDK** for ordinary feature/bugfix work. Touching every
  SDK in one MR is fine for cross-cutting renames or API-shape changes.
- **The OpenAPI spec is the source of truth** for HTTP wire format. If
  you're adding a new endpoint or field, update [`openapi/v1.yaml`](openapi/v1.yaml)
  first.
- **Each SDK keeps its own CHANGELOG** (`sdks/<name>/CHANGELOG.md`).
  The monorepo `CHANGELOG.md` only tracks repo-level changes (new SDKs,
  spec bumps, CI changes).
- **MIT only.** Any third-party code copied in must be MIT-compatible
  and attributed in the relevant SDK's README.

## Dev setup per SDK

### JavaScript / TypeScript

```bash
cd sdks/js
npm install
npm test          # vitest, runs in CI on Node 18/20/22
npm run build     # tsc → dist/
```

### Godot

Open the SDK in Godot 4.1+ as a standalone project (the addon under
`sdks/godot/addons/gsb/`). There's no Godot CI today — changes are
manually smoke-tested against a local GSB.

### Unity

Open `sdks/unity/Packages/host.supercraft.sdk/` as a UPM package in
Unity 2021.3 LTS or newer. There's no Unity CI today — changes are
manually smoke-tested.

### Roblox

Use [Rojo](https://rojo.space/) to sync `sdks/roblox/GSB.lua` into a
local Studio session. No Roblox CI today.

## PR checklist

- [ ] Code change matches the equivalent change in the OpenAPI spec.
- [ ] If JS: `npm test` passes locally.
- [ ] SDK README updated if the public surface changed.
- [ ] SDK CHANGELOG has an "Unreleased" entry describing the change.
- [ ] No secrets or per-tenant data in any file (search for `gsb_apikey_`,
      `gsb_servertoken_`, `Bearer`).

## Adding a new language

Want to add a Python / Rust / Unreal SDK? Steps:

1. **Open an issue first.** We'll agree on directory layout, package
   manager target, and CI plumbing before you start.
2. Add the source under `sdks/<lang>/` matching the per-SDK conventions
   (own README, own LICENSE, own CHANGELOG).
3. Generate the initial scaffold from `openapi/v1.yaml` if it helps,
   then hand-polish the ergonomic surface.
4. Wire it into `.gitlab-ci.yml` with at least lint + build.
5. Add a row to the top-level README's "What each SDK covers" matrix
   that's honest about coverage gaps.

## Code style per SDK

| SDK | Formatter | Linter | Tests |
|---|---|---|---|
| JS | Prettier (default) | TypeScript strict | Vitest |
| Godot | Godot's default GDScript style | n/a | manual |
| Unity | C# `dotnet format` | Roslyn analyzers | manual |
| Roblox | StyLua | Selene (recommended) | manual |

## Releasing

Maintainers only. Each SDK has its own release cadence:

- **JS** — `npm publish` from `sdks/js/`, tag `v<sdk>/<semver>` e.g.
  `v-js/1.1.0`.
- **Godot** — bump `version` in `addons/gsb/plugin.cfg`, tag
  `v-godot/<semver>`, submit to Godot Asset Library.
- **Unity** — bump `version` in `Packages/host.supercraft.sdk/package.json`,
  tag `v-unity/<semver>`.
- **Roblox** — bump `wally.toml`, tag `v-roblox/<semver>`, push to Wally.

Repo-level changes get tagged `v-repo/<date>` and only update
`CHANGELOG.md` at the root.
