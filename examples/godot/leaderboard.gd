# Weekly leaderboard, end-to-end.
#
# Drop this script onto any Node in a Godot 4.1+ project that has the Crux
# addon enabled. Fill in your project IDs at the top.
#
# See sdks/godot/README.md for installation.
extends Node

const URL          := "https://crux.supercraft.host"
const PROJECT_ID   := "<PROJECT_ID>"
const ENV_ID       := "<ENVIRONMENT_ID>"
const API_KEY      := "<API_KEY>"
const LEADERBOARD  := "weekly"

func _ready() -> void:
    Crux.init_player(URL, PROJECT_ID, ENV_ID, API_KEY)

    var auth = await Crux.login_anonymous()
    print("logged in as ", auth.player_id)

    var score := randi() % 10_000
    await Crux.submit_score(LEADERBOARD, auth.player_id, float(score))
    print("submitted ", score)

    var top = await Crux.get_top(LEADERBOARD, 10)
    print("top %d:" % top.size())
    for e in top:
        print("  #%2d  %s -> %d" % [e.rank, e.player_id, int(e.score)])

    var me = await Crux.get_player_standing(LEADERBOARD, auth.player_id)
    if me.has("rank"):
        print("my standing: #%d" % me.rank)
    else:
        print("my standing: unranked")

    var nbrs = await Crux.get_around_player(LEADERBOARD, auth.player_id, 2)
    print("neighbours (±2):")
    for e in nbrs:
        print("  #%d  %s -> %d" % [e.rank, e.player_id, int(e.score)])
