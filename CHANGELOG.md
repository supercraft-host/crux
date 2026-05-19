# Monorepo changelog

This file tracks **repo-level** changes — new SDKs added, spec version
bumps, CI changes, layout refactors. Per-SDK changes live in
`sdks/<name>/CHANGELOG.md`.

## [Unreleased]

### Added
- Monorepo bootstrap.
- Top-level README, RESEARCH, CONTRIBUTING, LICENSE (MIT).
- `docs/ARCHITECTURE.md` — multi-SDK design + OpenAPI-first explainer.
- `docs/AUTH.md` — the three auth flows (api key / server token / player JWT).
- `docs/ERROR_HANDLING.md` — shared error model and HTTP status mapping.
- `openapi/v1.yaml` — OpenAPI 3.0.3 spec, the source of truth for every
  SDK in this repo.
- `sdks/js/` — TypeScript SDK polished from the in-house copy.
- `sdks/godot/` — Godot 4 addon polished from the in-house copy.
- `sdks/unity/` — Unity UPM package polished from the in-house copy.
- `sdks/roblox/` — Roblox Luau module polished from the in-house copy.
- `examples/` — one canonical leaderboard example per SDK.
- `.gitlab-ci.yml` — per-SDK lint/test/build matrix.
