#!/usr/bin/env bash
# Relay Zero launcher.
#
#   ./tools/play.sh            # solo offline match (playable)
#   ./tools/play.sh online     # boot against Crux, land in the main menu
#   ./tools/play.sh server     # headless dedicated server (needs .env)
#   ./tools/play.sh build      # export web + dedicated-server artifacts
#   ./tools/play.sh doctor     # check the local setup
#   ./tools/play.sh install-godot   # unpack a Godot zip from ~/Downloads
#
# Override the engine with GODOT_BIN=/path/to/godot or --godot=/path/to/godot.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
PACKAGED_CONFIG="$PROJECT_DIR/client/boot/client_config.cfg"
STASH_PATH="$PROJECT_DIR/client/boot/.client_config.cfg.playbak"
USER_CONFIG_DIR="$HOME/.local/share/godot/app_userdata/Relay Zero"

RED=$'\033[31m'; YLW=$'\033[33m'; GRN=$'\033[32m'; DIM=$'\033[2m'; OFF=$'\033[0m'
say()  { printf '%s\n' "$*"; }
warn() { printf '%s%s%s\n' "$YLW" "$*" "$OFF" >&2; }
die()  { printf '%s%s%s\n' "$RED" "$*" "$OFF" >&2; exit 1; }
ok()   { printf '%s%s%s\n' "$GRN" "$*" "$OFF"; }

COMMAND=""
for arg in "$@"; do
  case "$arg" in
    --godot=*) GODOT_BIN="${arg#--godot=}" ;;
    -h|--help) awk 'NR>1 && /^#/ {sub(/^# ?/,""); print; next} NR>1 {exit}' "${BASH_SOURCE[0]}"; exit 0 ;;
    -*)        die "Unknown option: $arg" ;;
    *)         COMMAND="$arg" ;;
  esac
done
COMMAND="${COMMAND:-offline}"

# Self-heal: a previous run that was SIGKILLed (or whose machine lost power)
# leaves the placeholder in place with the real config parked beside it.
if [[ -e "$STASH_PATH" ]]; then
  warn "Recovering client_config.cfg from an interrupted previous run."
  mv -f "$STASH_PATH" "$PACKAGED_CONFIG"
fi

# ── Locate the engine ────────────────────────────────────────────────────────
find_godot() {
  if [[ -n "${GODOT_BIN:-}" ]]; then
    [[ -x "$GODOT_BIN" ]] || die "GODOT_BIN is not executable: $GODOT_BIN"
    printf '%s' "$GODOT_BIN"; return
  fi
  local candidate
  for candidate in godot godot4 Godot_v4.7.1-stable_linux.x86_64; do
    if command -v "$candidate" >/dev/null 2>&1; then
      command -v "$candidate"; return
    fi
  done
  for candidate in \
      "$HOME/.local/opt/Godot_v4.7.1-stable_linux.x86_64" \
      "$HOME/.local/bin/godot" \
      /opt/godot/godot; do
    [[ -x "$candidate" ]] && { printf '%s' "$candidate"; return; }
  done
  # Last resort: an unpacked copy sitting next to the downloaded zip.
  candidate="$(find "$HOME/Downloads" -maxdepth 2 -name 'Godot_v4*_linux.x86_64' -type f -perm -u+x 2>/dev/null | head -1)"
  [[ -n "$candidate" ]] && { printf '%s' "$candidate"; return; }

  local zip
  zip="$(find "$HOME/Downloads" -maxdepth 2 -name 'Godot_v4*_linux.x86_64.zip' 2>/dev/null | sort | tail -1)"
  if [[ -n "$zip" ]]; then
    die "Godot is not installed, but an unextracted zip is sitting in Downloads:
  $zip

Install it with:
  ./tools/play.sh install-godot"
  fi
  die "Godot not found. Install it with './tools/play.sh install-godot'
(after downloading a Godot 4.x Linux build to ~/Downloads), or pass
--godot=/path/to/godot."
}

# Unpack a downloaded Godot zip into ~/.local/opt and link it onto PATH.
install_godot() {
  local zip target link
  zip="$(find "$HOME/Downloads" -maxdepth 2 -name 'Godot_v4*_linux.x86_64.zip' 2>/dev/null | sort | tail -1)"
  [[ -n "$zip" ]] || die "No Godot_v4*_linux.x86_64.zip found in ~/Downloads.
Download a Linux build from https://godotengine.org/download first."
  command -v unzip >/dev/null 2>&1 || die "unzip is not installed."

  mkdir -p "$HOME/.local/opt" "$HOME/.local/bin"
  say "Extracting $(basename "$zip") ..."
  unzip -o -q "$zip" -d "$HOME/.local/opt"
  target="$(find "$HOME/.local/opt" -maxdepth 1 -name 'Godot_v4*_linux.x86_64' -type f | sort | tail -1)"
  [[ -n "$target" ]] || die "Extraction did not produce a Godot binary in ~/.local/opt."
  chmod +x "$target"
  link="$HOME/.local/bin/godot"
  ln -sf "$target" "$link"

  ok "Installed $("$link" --version 2>/dev/null | head -1)"
  say "  binary  $target"
  say "  link    $link"
  case ":$PATH:" in
    *":$HOME/.local/bin:"*) ;;
    *) warn "~/.local/bin is not on your PATH. This script finds it anyway, but for
      bare 'godot' add:  export PATH=\"\$HOME/.local/bin:\$PATH\"" ;;
  esac
}

# Load .env without clobbering anything already in the environment, so
# `PORT=9099 ./tools/play.sh server` beats the value in the file.
load_env() {
  [[ -f "$PROJECT_DIR/.env" ]] || die "No .env in $PROJECT_DIR. Run tools/configure_demo.py first."
  local key value
  while IFS='=' read -r key value; do
    key="${key%%[[:space:]]}"
    [[ "$key" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || continue
    [[ -n "${!key:-}" ]] && continue
    value="${value%$'\r'}"
    value="${value%\"}"; value="${value#\"}"
    export "$key=$value"
  done < <(grep -vE '^[[:space:]]*(#|$)' "$PROJECT_DIR/.env")
}

# ── Commands ─────────────────────────────────────────────────────────────────

# Offline is reached by the boot failing to find usable credentials. Rather than
# deleting the real config we swap in a placeholder and always put the original
# back, including on Ctrl-C or a crash.
run_offline() {
  local godot
  godot="$(find_godot)"
  # Stash beside the original, never in /tmp: a temp-file reaper or a sandboxed
  # TMPDIR can delete it mid-run, and then the placeholder becomes permanent.
  local stash="$STASH_PATH"

  if [[ -e "$USER_CONFIG_DIR/client_config.cfg" ]]; then
    warn "Note: $USER_CONFIG_DIR/client_config.cfg overrides the packaged config."
    warn "      Remove it if the game boots online instead of offline."
  fi

  local godot_pid=0
  restore() {
    # Take the engine down with us; otherwise it would keep the placeholder live.
    [[ "$godot_pid" -ne 0 ]] && kill "$godot_pid" 2>/dev/null
    if [[ -e "$stash" ]]; then
      mv -f "$stash" "$PACKAGED_CONFIG" && say "${DIM}Restored client_config.cfg${OFF}"
    elif grep -q 'written by tools/play.sh' "$PACKAGED_CONFIG" 2>/dev/null; then
      warn "client_config.cfg is still the play.sh placeholder and the backup is gone."
      warn "Re-run tools/configure_demo.py to regenerate it."
    fi
    return 0
  }
  trap restore EXIT INT TERM HUP

  if [[ -e "$PACKAGED_CONFIG" ]]; then
    mv "$PACKAGED_CONFIG" "$stash"
  fi
  cat > "$PACKAGED_CONFIG" <<'PLACEHOLDER'
# Temporary placeholder written by tools/play.sh to force offline mode.
# The real file is restored when the game exits.
[crux]
url="https://crux.supercraft.host"
project_id="your-project-id-here"
env_id="your-environment-id-here"
api_key="your-client-api-key-here"

[match]
default_region="eu-west"
default_mode="quick"
PLACEHOLDER

  say "Starting ${GRN}offline solo${OFF} match."
  say "${DIM}WASD move | E interact (cores/relays/extract) | Space dash | Tab dev panel | Esc menu${OFF}"
  say "${DIM}Goal: carry 3 data cores to their relays, then reach the extraction beacon.${OFF}"
  say ""
  # Backgrounded + wait, so a signal to this script runs the trap right away.
  # A foreground child would make bash defer the trap until the engine exits.
  "$godot" --path "$PROJECT_DIR" &
  godot_pid=$!
  wait "$godot_pid" || true
}

run_online() {
  local godot; godot="$(find_godot)"
  [[ -e "$PACKAGED_CONFIG" ]] || die "Missing $PACKAGED_CONFIG - run tools/configure_demo.py."
  if grep -q 'your-project-id-here' "$PACKAGED_CONFIG"; then
    die "client_config.cfg still holds placeholders. Run tools/configure_demo.py."
  fi
  say "Booting ${GRN}online${OFF} (guest auth -> profile -> main menu)."
  warn "Heads up: PLAY will report 'Matchmaking failed' - Crux has no matchmaking"
  warn "endpoints yet, and Server Browser is not implemented. Use 'offline' to play."
  say ""
  "$godot" --path "$PROJECT_DIR" || true
}

run_server() {
  local godot; godot="$(find_godot)"
  load_env
  : "${PORT:=9080}"
  : "${PUBLIC_ADDRESS:=127.0.0.1}"
  for required in CRUX_PROJECT_ID CRUX_ENVIRONMENT_ID CRUX_SERVER_TOKEN; do
    [[ -n "${!required:-}" ]] || die "$required is not set in .env"
  done
  if [[ "${RELAY_ALLOW_INSECURE_DEV_AUTH:-0}" != "1" ]]; then
    [[ -n "${MATCH_ID:-}" && -n "${EXPECTED_JOIN_TOKEN:-}" ]] || \
      die "Set MATCH_ID and EXPECTED_JOIN_TOKEN, or RELAY_ALLOW_INSECURE_DEV_AUTH=1 in .env"
  fi
  say "Starting ${GRN}dedicated server${OFF} on port $PORT (Ctrl-C to stop)."
  say "${DIM}No client can reach it from the UI yet - direct-connect is not wired up.${OFF}"
  say ""
  "$godot" --headless --path "$PROJECT_DIR" res://server/server_main.tscn -- \
    --port="$PORT" --public-address="$PUBLIC_ADDRESS" --region="${REGION:-eu-west}"
}

run_build() {
  local godot; godot="$(find_godot)"
  GODOT_BIN="$godot" "$SCRIPT_DIR/build_exports.sh"
}

run_doctor() {
  local godot problems=0
  say "Relay Zero setup check"
  say "----------------------"
  if godot="$(find_godot 2>/dev/null)"; then
    ok  "engine            $godot ($("$godot" --version 2>/dev/null | head -1))"
  else
    warn "engine            NOT FOUND"; problems=$((problems+1))
  fi

  local tdir="$HOME/.local/share/godot/export_templates"
  if compgen -G "$tdir/*/linux_release.x86_64" >/dev/null 2>&1; then
    ok  "export templates  $(ls "$tdir" | tr '\n' ' ')"
  else
    warn "export templates  missing (only needed for 'build')"
  fi

  if [[ -f "$PROJECT_DIR/.env" ]]; then
    ok  ".env              present"
  else
    warn ".env              missing (only needed for 'server')"
  fi

  if [[ -e "$PACKAGED_CONFIG" ]] && ! grep -q 'your-project-id-here' "$PACKAGED_CONFIG"; then
    ok  "client config     configured (online boot available)"
  else
    warn "client config     placeholder - only offline mode will work"
  fi

  if [[ -e "$USER_CONFIG_DIR/client_config.cfg" ]]; then
    warn "user override     $USER_CONFIG_DIR/client_config.cfg exists and wins over the packaged config"
  fi

  say ""
  [[ $problems -eq 0 ]] && ok "Ready. Run: ./tools/play.sh" || die "Fix the items above first."
}

case "$COMMAND" in
  offline)       run_offline ;;
  install-godot) install_godot ;;
  online)        run_online ;;
  server)        run_server ;;
  build)         run_build ;;
  doctor)        run_doctor ;;
  *)             die "Unknown command: $COMMAND (try: offline, online, server, build, doctor, install-godot)" ;;
esac
