#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
GODOT_BIN="${GODOT_BIN:-godot}"

: "${PORT:=9080}"
: "${CRUX_PROJECT_ID:?Set CRUX_PROJECT_ID}"
: "${CRUX_ENVIRONMENT_ID:?Set CRUX_ENVIRONMENT_ID}"
: "${CRUX_SERVER_TOKEN:?Set CRUX_SERVER_TOKEN}"
: "${PUBLIC_ADDRESS:=127.0.0.1}"
: "${RELAY_ALLOW_INSECURE_DEV_AUTH:=1}"

cd "$PROJECT_DIR"
exec "$GODOT_BIN" --headless res://server/server_main.tscn -- --port="$PORT" --public-address="$PUBLIC_ADDRESS"
