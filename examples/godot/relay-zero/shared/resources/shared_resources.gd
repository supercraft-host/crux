class_name SharedResources
extends RefCounted

const MODULES := {
	"pulse_shield": {
		"name": "Pulse Shield",
		"description": "Block incoming projectiles for a short duration.",
		"cooldown": 8.0,
		"duration": 2.0,
		"cost": 500,
	},
	"scanner": {
		"name": "Signal Scanner",
		"description": "Reveal cores and enemies within range.",
		"cooldown": 12.0,
		"duration": 4.0,
		"radius": 400.0,
		"cost": 400,
	},
	"repulsor": {
		"name": "Repulsor",
		"description": "Push enemies away from the carrier.",
		"cooldown": 6.0,
		"radius": 200.0,
		"force": 300.0,
		"cost": 450,
	},
	"decoy": {
		"name": "Decoy Beacon",
		"description": "Deploy a decoy that redirects enemies.",
		"cooldown": 15.0,
		"duration": 6.0,
		"cost": 550,
	},
	"repair_field": {
		"name": "Repair Field",
		"description": "Restore team integrity in an area.",
		"cooldown": 10.0,
		"duration": 3.0,
		"radius": 150.0,
		"heal_per_tick": 5.0,
		"cost": 600,
	},
}

const CONSUMABLES := {
	"signal_booster": {"name": "Signal Booster", "description": "+25% signal earned this run.", "cost": 100},
	"health_kit": {"name": "Health Kit", "description": "Restore 50 health instantly.", "cost": 150},
	"speed_stim": {"name": "Speed Stim", "description": "+30% movement speed for 15s.", "cost": 120},
	"revive_token": {"name": "Revive Token", "description": "Self-revive once per run.", "cost": 300},
}

const COSMETICS := {
	"frame_default": {"name": "Default Frame", "type": "frame", "cost": 0},
	"frame_rust": {"name": "Rust Frame", "type": "frame", "cost": 200},
	"frame_carbon": {"name": "Carbon Frame", "type": "frame", "cost": 400},
	"frame_neon": {"name": "Neon Frame", "type": "frame", "cost": 800},
	"trail_signal_white": {"name": "Signal White", "type": "trail", "cost": 0},
	"trail_signal_blue": {"name": "Signal Blue", "type": "trail", "cost": 250},
	"trail_signal_red": {"name": "Signal Red", "type": "trail", "cost": 500},
	"trail_signal_gold": {"name": "Signal Gold", "type": "trail", "cost": 1000},
}

const ROOM_MODULES := [
	{"id": "corridor_straight", "size": Vector2(16, 8)},
	{"id": "corridor_corner", "size": Vector2(8, 8)},
	{"id": "corridor_t", "size": Vector2(16, 16)},
	{"id": "chamber_small", "size": Vector2(12, 12)},
	{"id": "chamber_medium", "size": Vector2(20, 20)},
	{"id": "chamber_large", "size": Vector2(28, 28)},
	{"id": "relay_room", "size": Vector2(16, 16)},
	{"id": "nest_room", "size": Vector2(20, 20)},
	{"id": "extraction_room", "size": Vector2(24, 24)},
	{"id": "hazard_room", "size": Vector2(16, 20)},
	{"id": "junction", "size": Vector2(12, 12)},
	{"id": "dead_end", "size": Vector2(8, 8)},
]

const LEADERBOARDS := {
	"weekly_recovery_score": "Weekly Recovery Score",
	"fastest_full_extraction": "Fastest Full Extraction",
	"longest_extraction_streak": "Longest Extraction Streak",
}

const GAME_MODES := {
	"quick": "Quick Match",
	"private": "Private Code",
}

const REGIONS := {
	"eu-west": "Europe West",
	"us-east": "US East",
	"aus": "Australia",
}

const DEFAULT_PROFILE := {
	"display_name": "",
	"created_at": "",
	"tutorial_complete": false,
	"selected_frame": "frame_default",
	"lifetime_runs": 0,
	"lifetime_extractions": 0,
}

const DEFAULT_LOADOUT := {
	"module": "pulse_shield",
	"consumable": "",
	"cosmetic_trail": "signal_white",
}

const DEFAULT_PROGRESSION := {
	"level": 1,
	"xp": 0,
	"unlocked_modules": ["pulse_shield"],
	"best_streak": 0,
	"current_streak": 0,
}
