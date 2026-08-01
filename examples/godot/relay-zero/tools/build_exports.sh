#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
GODOT_BIN="${GODOT_BIN:-godot}"

mkdir -p "$PROJECT_DIR/build/server" "$PROJECT_DIR/build/web"

"$GODOT_BIN" --headless --path "$PROJECT_DIR" \
  --export-release "Dedicated Server" "$PROJECT_DIR/build/server/relay-zero-server.x86_64"

"$GODOT_BIN" --headless --path "$PROJECT_DIR" \
  --export-release "Web" "$PROJECT_DIR/build/web/index.html"

chmod 0755 "$PROJECT_DIR/build/server/relay-zero-server.x86_64"

echo "Built:"
echo "  build/server/relay-zero-server.x86_64"
echo "  build/server/relay-zero-server.pck"
echo "  build/web/index.html"
