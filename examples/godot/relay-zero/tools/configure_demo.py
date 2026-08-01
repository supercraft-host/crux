#!/usr/bin/env python3
"""Write Relay Zero client/server configuration from known Crux resource IDs.

This tool deliberately does not claim to create backend resources. Create the
project, environment, credentials, currency, and leaderboards in Crux first,
then use this script to make the checked-out demo reproducible.
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def quote(value: str) -> str:
    return json.dumps(value)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--crux-url", default="https://crux.supercraft.host")
    parser.add_argument("--project-id", required=True)
    parser.add_argument("--environment-id", required=True)
    parser.add_argument("--client-api-key", required=True)
    parser.add_argument("--server-token", required=True)
    parser.add_argument("--weekly-leaderboard-id", required=True)
    parser.add_argument("--fastest-leaderboard-id", required=True)
    parser.add_argument("--streak-leaderboard-id", default="")
    args = parser.parse_args()

    client = f'''[crux]\nurl={quote(args.crux_url)}\nproject_id={quote(args.project_id)}\nenv_id={quote(args.environment_id)}\napi_key={quote(args.client_api_key)}\n\n[match]\ndefault_region="eu-west"\ndefault_mode="quick"\n'''
    (ROOT / "client/boot/client_config.cfg").write_text(client)

    server = f'''[crux]\nurl={quote(args.crux_url)}\nproject_id={quote(args.project_id)}\nenv_id={quote(args.environment_id)}\nserver_token=""\n\n[server]\nserver_id=""\nname="Relay Zero"\nregion="eu-west"\nport=9080\npublic_address=""\n'''
    (ROOT / "server/server_config.cfg").write_text(server)

    manifest_path = ROOT / "content/config_defaults/manifest.json"
    manifest = json.loads(manifest_path.read_text())
    manifest["leaderboards"] = {
        "weekly_recovery_score": args.weekly_leaderboard_id,
        "fastest_full_extraction": args.fastest_leaderboard_id,
        "longest_extraction_streak": args.streak_leaderboard_id,
    }
    manifest_path.write_text(json.dumps(manifest, indent=2) + "\n")

    print("Configured client IDs and leaderboard UUIDs.")
    print("The server token remains runtime-only; export CRUX_SERVER_TOKEN.")


if __name__ == "__main__":
    main()
