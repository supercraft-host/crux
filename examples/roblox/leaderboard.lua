-- Weekly leaderboard, end-to-end.
--
-- Put under ServerScriptService alongside Crux.lua. Replace IDs below.
-- See sdks/roblox/README.md for installation.

local Crux = require(game.ServerScriptService.Crux)

local PROJECT_ID    = "<PROJECT_ID>"
local SERVER_TOKEN  = "<SERVER_TOKEN>"
local ENVIRONMENT   = "<ENVIRONMENT_ID>"
local LEADERBOARD   = "weekly"

local gsb = Crux.init(PROJECT_ID, SERVER_TOKEN, ENVIRONMENT)

local Players = game:GetService("Players")

Players.PlayerAdded:Connect(function(player)
    -- Establish the player's Crux record.
    local verify = gsb:VerifyPlayer(player.UserId)
    if verify.error then
        warn(("Crux verify failed (%d): %s"):format(verify.status, verify.error))
        return
    end

    -- Submit a placeholder score (you'd compute this from gameplay).
    local score = math.random(0, 10_000)
    gsb:SubmitScore(LEADERBOARD, player.UserId, score)

    -- Tell the player their rank.
    local me = gsb:GetPlayerStanding(LEADERBOARD, player.UserId)
    if me and me.rank then
        print(("[%s] #%d on %s"):format(player.Name, me.rank, LEADERBOARD))
    else
        print(("[%s] unranked on %s"):format(player.Name, LEADERBOARD))
    end

    -- Show the top 10 in the console.
    local top = gsb:GetLeaderboardTop(LEADERBOARD, 10)
    if top and not top.error then
        print(("top of %s:"):format(LEADERBOARD))
        for _, e in ipairs(top.entries or top) do
            print(("  #%d  %s -> %d"):format(e.rank, e.player_id, e.score))
        end
    end
end)
