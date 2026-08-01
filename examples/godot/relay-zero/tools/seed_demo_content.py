#!/usr/bin/env python3
"""Seed demo content: generate default config bundle files."""

import json
import os
import sys

OUT_DIR = os.path.join(os.path.dirname(__file__), "..", "content", "config_defaults")

MANIFEST = {
    "version": "demo-0.1.0",
    "description": "Relay Zero default configuration",
    "created_at": "2026-08-01T00:00:00Z",
    "files": [
        "balance.json",
        "enemy_table.json",
        "loot_table.json",
        "daily_event.json",
        "map_rotation.json",
    ],
}

BALANCE = {
    "base_reward_per_core": 50,
    "extraction_bonus": 100,
    "team_size_multiplier": [1.0, 1.2, 1.35, 1.5],
    "difficulty_weight": 0.15,
    "time_bonus_max": 50,
    "time_bonus_per_second": 0.5,
}

ENEMY_TABLE = {
    "common": {"hp": 60, "speed": 120, "damage": 10, "xp": 10, "signal": 5},
    "fast": {"hp": 40, "speed": 220, "damage": 8, "xp": 15, "signal": 8},
    "heavy": {"hp": 200, "speed": 80, "damage": 25, "xp": 30, "signal": 20},
    "artillery": {"hp": 80, "speed": 40, "damage": 20, "xp": 20, "signal": 15},
    "shielder": {"hp": 120, "speed": 100, "damage": 12, "xp": 25, "signal": 18},
    "swarm": {"hp": 25, "speed": 180, "damage": 5, "xp": 5, "signal": 3},
    "elite_assassin": {"hp": 350, "speed": 160, "damage": 40, "xp": 80, "signal": 50},
    "elite_juggernaut": {"hp": 600, "speed": 60, "damage": 50, "xp": 100, "signal": 75},
}

LOOT_TABLE = {
    "common": [
        {"item": "signal", "amount": 10, "weight": 40},
        {"item": "health_kit", "amount": 1, "weight": 15},
    ],
    "rare": [
        {"item": "signal", "amount": 50, "weight": 30},
        {"item": "signal_booster", "amount": 1, "weight": 10},
        {"item": "speed_stim", "amount": 1, "weight": 8},
    ],
    "elite": [
        {"item": "signal", "amount": 150, "weight": 25},
        {"item": "revive_token", "amount": 1, "weight": 10},
    ],
}

DAILY_EVENTS = {
    "none": {
        "id": "none",
        "name": "Standard Protocol",
        "reward_multiplier": 1.0,
        "enemy_speed": 1.0,
        "visibility": 1.0,
    },
    "blackout": {
        "id": "blackout",
        "name": "Blackout Protocol",
        "visibility": 0.55,
        "enemy_speed": 1.10,
        "reward_multiplier": 1.25,
    },
    "overclock": {
        "id": "overclock",
        "name": "Overclock",
        "enemy_speed": 1.4,
        "reward_multiplier": 1.5,
        "visibility": 0.8,
    },
    "reinforcements": {
        "id": "reinforcements",
        "name": "Reinforcements",
        "enemy_spawn_rate": 2.0,
        "reward_multiplier": 1.35,
        "visibility": 1.0,
    },
    "low_resources": {
        "id": "low_resources",
        "name": "Low Resources",
        "item_drop_rate": 0.5,
        "reward_multiplier": 1.15,
        "visibility": 0.9,
    },
    "double_time": {
        "id": "double_time",
        "name": "Double Time",
        "match_time_multiplier": 0.7,
        "reward_multiplier": 1.4,
        "visibility": 0.7,
    },
}

MAP_ROTATION = {
    "available": ["facility_a"],
    "default": "facility_a",
}

def main():
    os.makedirs(OUT_DIR, exist_ok=True)

    files = {
        "manifest.json": MANIFEST,
        "balance.json": BALANCE,
        "enemy_table.json": ENEMY_TABLE,
        "loot_table.json": LOOT_TABLE,
        "daily_event.json": json.loads(json.dumps(DAILY_EVENTS["none"])),
        "map_rotation.json": MAP_ROTATION,
    }

    for filename, data in files.items():
        path = os.path.join(OUT_DIR, filename)
        with open(path, "w") as f:
            json.dump(data, f, indent=2)
        print("  Wrote: %s" % path)

    os.makedirs(os.path.join(OUT_DIR, "events"), exist_ok=True)
    for event_id, event_data in DAILY_EVENTS.items():
        if event_id == "none":
            continue
        path = os.path.join(OUT_DIR, "events", "%s.json" % event_id)
        with open(path, "w") as f:
            json.dump(event_data, f, indent=2)
        print("  Wrote: %s" % path)

    print()
    print("Default config content generated in: %s" % OUT_DIR)
    print("Upload these files to your Crux config bundle.")


if __name__ == "__main__":
    main()
