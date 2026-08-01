# Relay Zero

A Godot 4 browser-first Crux showcase. The current vertical slice contains one
authoritative loop: recover three data cores, deliver them to relay towers, and
extract. The same `GameSimulation` runs offline and on the headless server.

## What this rescue patchset fixes

- Correct autoload setup and a browser-safe packaged configuration fallback.
- Validated live-config ZIP installation with last-known-good behavior.
- Explicit `MultiplayerAPI`/WebSocket RPC gateway and targeted messages.
- Peer-bound server input; clients cannot select another player actor.
- Player JWT verification and fail-closed match join-token validation.
- Server-owned loadouts, rewards, leaderboard UUIDs, and reward claims.
- Fixed-rate server simulation and authoritative snapshots.
- Minimal visible extraction game loop.
- Server environment parsing, export presets, Docker entrypoint, and health check.

## Configure

Create the Crux resources first, then run:

```bash
python3 tools/configure_demo.py \
  --project-id ... \
  --environment-id ... \
  --client-api-key ... \
  --server-token placeholder-runtime-only \
  --weekly-leaderboard-id ... \
  --fastest-leaderboard-id ...
```

Do not commit a real server token. Export it at runtime:

```bash
set -a
source .env
set +a
./tools/run_local_cluster.sh
```

The dedicated server requires Crux's trusted player-token verification endpoint.
The endpoint is wrapped by `Crux.verify_player_token()`. It should be documented
in the Crux OpenAPI contract before treating this demo as production-ready.

## Build

```bash
GODOT_BIN=/path/to/godot ./tools/build_exports.sh
# Produces a self-contained Linux server binary + PCK and the browser build.
docker compose --env-file .env -f deployment/compose.yaml build
```

Public browser traffic should terminate TLS at an ingress and proxy `wss://` to
the container's plain WebSocket port.

## Remaining work

This is a functional foundation, not the final showcase. Enemy combat, polished
rooms, reconnect handling, atomic backend idempotency, real allocation, and
integration/load tests still need implementation.
