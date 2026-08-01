#!/usr/bin/env bash
set -euo pipefail

: "${PORT:=9080}"
: "${CRUX_PROJECT_ID:?CRUX_PROJECT_ID must be set}"
: "${CRUX_ENVIRONMENT_ID:?CRUX_ENVIRONMENT_ID must be set}"
: "${CRUX_SERVER_TOKEN:?CRUX_SERVER_TOKEN must be set}"
: "${PUBLIC_ADDRESS:?PUBLIC_ADDRESS must be set}"

if [[ "${RELAY_ALLOW_INSECURE_DEV_AUTH:-0}" != "1" ]]; then
  : "${MATCH_ID:?MATCH_ID must be injected by the allocator}"
  : "${EXPECTED_JOIN_TOKEN:?EXPECTED_JOIN_TOKEN must be injected by the allocator}"
fi

exec /app/relay-zero-server.x86_64 --headless \
  -- \
  --port="$PORT" \
  --region="${REGION:-eu-west}" \
  --public-address="$PUBLIC_ADDRESS"
