--[[
    Crux (Game Services Backend) Roblox SDK
    Version: 2.0.0

    Drop-in replacement for DataStoreService, OrderedDataStore, and more.
    - Versioned documents with optimistic locking
    - Seasonal leaderboards
    - Virtual economy & matchmaking
    - Cross-experience data sharing via ProjectID
    - Automatic retry with exponential back-off on 429 / 503

    Usage (Server Script):
        local Crux = require(game.ServerScriptService.Crux)
        local crux = Crux.init("YOUR_PROJECT_ID", "YOUR_SERVER_TOKEN", "YOUR_ENV_ID")
]]

local Crux = {}
Crux.__index = Crux

local HttpService = game:GetService("HttpService")
local BASE_URL = "https://crux.supercraft.host/v1"

-- Retry policy
local MAX_RETRIES = 3
local BASE_BACKOFF_SECONDS = 1  -- doubles each attempt

------------------------------------------------------------------------
-- Core HTTP
------------------------------------------------------------------------

-- Request performs an HTTP call with automatic retry on transient errors.
-- Retries on: 429 (rate limited, respects Retry-After), 503 (unavailable).
-- Errors immediately on 4xx (except 429) and unexpected failures.
function Crux:Request(method, endpoint, body)
    local url = BASE_URL .. endpoint
    local headers = {
        ["Authorization"] = "ServerToken " .. self.SecretToken,
        ["Content-Type"]  = "application/json",
    }
    local encodedBody = body and HttpService:JSONEncode(body) or nil

    local lastError
    local backoff = BASE_BACKOFF_SECONDS

    for attempt = 1, MAX_RETRIES + 1 do
        local ok, response = pcall(function()
            return HttpService:RequestAsync({
                Url     = url,
                Method  = method,
                Headers = headers,
                Body    = encodedBody,
            })
        end)

        if not ok then
            -- Network-level failure (no response)
            lastError = "[Crux] Network error: " .. tostring(response)
            if attempt <= MAX_RETRIES then
                task.wait(backoff)
                backoff = backoff * 2
                continue
            end
            error(lastError, 2)
        end

        local data
        if response.Body and #response.Body > 0 then
            pcall(function() data = HttpService:JSONDecode(response.Body) end)
        end

        local status = response.StatusCode

        -- Retry on 429 (rate limited) and 503 (service unavailable)
        if (status == 429 or status == 503) and attempt <= MAX_RETRIES then
            local retryAfter = tonumber(
                response.Headers and (response.Headers["Retry-After"] or response.Headers["retry-after"])
            ) or backoff
            task.wait(retryAfter)
            backoff = backoff * 2
            lastError = "[Crux] Retrying after " .. retryAfter .. "s (status " .. status .. ")"
            continue
        end

        if not response.Success then
            local msg = (data and data.message) or response.StatusMessage or "Unknown Error"
            error("[Crux] API Error (" .. status .. "): " .. msg, 2)
        end

        return data, response
    end

    error(lastError or "[Crux] Max retries exceeded", 2)
end

------------------------------------------------------------------------
-- Constructor
------------------------------------------------------------------------

function Crux.init(projectID, secretToken, environmentID)
    assert(type(projectID)     == "string" and #projectID     > 0, "projectID required")
    assert(type(secretToken)   == "string" and #secretToken   > 0, "secretToken required")
    assert(type(environmentID) == "string" and #environmentID > 0, "environmentID required")

    return setmetatable({
        ProjectID     = projectID,
        SecretToken   = secretToken,
        EnvironmentID = environmentID,
    }, Crux)
end

------------------------------------------------------------------------
-- DataStore emulation
-- Mirrors Roblox DataStoreService semantics:
--   local ds = crux:GetDataStore("coins")
--   ds:GetAsync(player.UserId)   → GET /players/{userId}/documents/coins
--   ds:SetAsync(player.UserId, value)
--   ds:UpdateAsync(player.UserId, transformFn)
--   ds:IncrementAsync(player.UserId, delta)
--   ds:RemoveAsync(player.UserId)
------------------------------------------------------------------------

local DataStore = {}
DataStore.__index = DataStore

function Crux:GetDataStore(name)
    assert(type(name) == "string" and #name > 0, "DataStore name required")
    return setmetatable({ _gsb = self, _name = name }, DataStore)
end

function DataStore:_endpoint(playerID)
    return string.format(
        "/projects/%s/environments/%s/players/%s/documents/%s",
        self._gsb.ProjectID, self._gsb.EnvironmentID,
        tostring(playerID), self._name
    )
end

-- GetAsync returns the stored value, or nil if not found.
function DataStore:GetAsync(playerID)
    local ok, data = pcall(function()
        return self._gsb:Request("GET", self:_endpoint(playerID))
    end)
    if ok then
        return data and data.value, data and data.version
    end
    if string.find(tostring(data), "404") then
        return nil, nil
    end
    error(data, 2)
end

-- SetAsync unconditionally writes a value.
function DataStore:SetAsync(playerID, value)
    return self._gsb:Request("PUT", self:_endpoint(playerID), { value = value })
end

-- UpdateAsync fetches the current value, passes it to transformFn, and writes
-- the result with optimistic locking (version). Retries on conflict (409).
function DataStore:UpdateAsync(playerID, transformFn)
    local MAX_UPDATE_RETRIES = 5
    for i = 1, MAX_UPDATE_RETRIES do
        local current, version = self:GetAsync(playerID)
        local newValue = transformFn(current)
        if newValue == nil then
            return current -- transform returned nil = abort
        end

        local body = { value = newValue }
        if version then body.version = version end

        local ok, result = pcall(function()
            return self._gsb:Request("PUT", self:_endpoint(playerID), body)
        end)

        if ok then return result and result.value end

        -- 409 Conflict = version mismatch, retry
        if string.find(tostring(result), "409") and i < MAX_UPDATE_RETRIES then
            task.wait(0.1 * i)
        else
            error(result, 2)
        end
    end
    error("[Crux] UpdateAsync: too many version conflicts", 2)
end

-- IncrementAsync adds delta to a numeric value atomically.
function DataStore:IncrementAsync(playerID, delta)
    delta = delta or 1
    return self:UpdateAsync(playerID, function(current)
        return (tonumber(current) or 0) + delta
    end)
end

-- RemoveAsync deletes the document and returns the last value.
function DataStore:RemoveAsync(playerID)
    local last = self:GetAsync(playerID)
    pcall(function()
        self._gsb:Request("DELETE", self:_endpoint(playerID))
    end)
    return last
end

------------------------------------------------------------------------
-- Identity / Roblox verification
------------------------------------------------------------------------

-- VerifyPlayer validates a Roblox UserId against the backend.
-- Returns the Crux player record (creates one if new).
function Crux:VerifyPlayer(robloxUserID)
    local endpoint = string.format(
        "/projects/%s/environments/%s/auth/roblox/verify",
        self.ProjectID, self.EnvironmentID
    )
    return self:Request("POST", endpoint, { user_id = tostring(robloxUserID) })
end

------------------------------------------------------------------------
-- Leaderboards
------------------------------------------------------------------------

-- SubmitScore records a score for a player on a named leaderboard.
function Crux:SubmitScore(leaderboardID, playerID, score, metadata)
    local endpoint = string.format(
        "/projects/%s/environments/%s/leaderboards/%s/scores",
        self.ProjectID, self.EnvironmentID, leaderboardID
    )
    return self:Request("POST", endpoint, {
        player_id = tostring(playerID),
        score     = score,
        metadata  = metadata or {},
    })
end

-- GetLeaderboardTop returns the top N entries.
-- limit defaults to 10. Returns array of {player_id, score, rank}.
function Crux:GetLeaderboardTop(leaderboardID, limit)
    limit = limit or 10
    local endpoint = string.format(
        "/projects/%s/environments/%s/leaderboards/%s/top?limit=%d",
        self.ProjectID, self.EnvironmentID, leaderboardID, limit
    )
    return self:Request("GET", endpoint)
end

-- GetPlayerStanding returns rank and score for a specific player.
function Crux:GetPlayerStanding(leaderboardID, playerID)
    local endpoint = string.format(
        "/projects/%s/environments/%s/leaderboards/%s/players/%s",
        self.ProjectID, self.EnvironmentID, leaderboardID, tostring(playerID)
    )
    local ok, data = pcall(function()
        return self:Request("GET", endpoint)
    end)
    if ok then return data end
    if string.find(tostring(data), "404") then return nil end
    error(data, 2)
end

-- GetPlayersAroundPlayer returns entries within radius positions of a player.
function Crux:GetPlayersAroundPlayer(leaderboardID, playerID, radius)
    radius = radius or 3
    local endpoint = string.format(
        "/projects/%s/environments/%s/leaderboards/%s/players/%s/around?radius=%d",
        self.ProjectID, self.EnvironmentID, leaderboardID, tostring(playerID), radius
    )
    return self:Request("GET", endpoint)
end

------------------------------------------------------------------------
-- Economy
------------------------------------------------------------------------

function Crux:GetPlayerEconomy(playerID)
    local endpoint = string.format(
        "/projects/%s/environments/%s/players/%s/economy",
        self.ProjectID, self.EnvironmentID, tostring(playerID)
    )
    return self:Request("GET", endpoint)
end

function Crux:AdjustEconomy(playerID, balanceAdjustments, inventoryAdjustments)
    local endpoint = string.format(
        "/projects/%s/environments/%s/players/%s/economy/adjust",
        self.ProjectID, self.EnvironmentID, tostring(playerID)
    )
    return self:Request("POST", endpoint, {
        balance_adjustments   = balanceAdjustments   or {},
        inventory_adjustments = inventoryAdjustments or {},
    })
end

------------------------------------------------------------------------
-- Matchmaking
------------------------------------------------------------------------

function Crux:JoinMatchmaking(playerID, gameMode, region, metadata)
    local endpoint = string.format(
        "/projects/%s/environments/%s/matchmaking/join",
        self.ProjectID, self.EnvironmentID
    )
    return self:Request("POST", endpoint, {
        player_id = tostring(playerID),
        game_mode = gameMode,
        region    = region or "global",
        metadata  = metadata or {},
    })
end

function Crux:GetMatchStatus(playerID)
    local endpoint = string.format(
        "/projects/%s/environments/%s/matchmaking/status/%s",
        self.ProjectID, self.EnvironmentID, tostring(playerID)
    )
    return self:Request("GET", endpoint)
end

function Crux:LeaveMatchmaking(playerID)
    local endpoint = string.format(
        "/projects/%s/environments/%s/matchmaking/leave",
        self.ProjectID, self.EnvironmentID
    )
    return self:Request("POST", endpoint, { player_id = tostring(playerID) })
end

------------------------------------------------------------------------
-- Server registry
------------------------------------------------------------------------

function Crux:GetServers(filters)
    filters = filters or {}
    local endpoint = string.format(
        "/projects/%s/environments/%s/browser",
        self.ProjectID, self.EnvironmentID
    )
    local query = {}
    if filters.Region   then table.insert(query, "region="    .. filters.Region)   end
    if filters.MapName  then table.insert(query, "map_name="  .. filters.MapName)  end
    if filters.GameMode then table.insert(query, "game_mode=" .. filters.GameMode) end
    if #query > 0 then
        endpoint = endpoint .. "?" .. table.concat(query, "&")
    end
    return self:Request("GET", endpoint)
end

------------------------------------------------------------------------
-- Config delivery
------------------------------------------------------------------------

-- GetActiveConfig downloads the active config bundle for this environment.
-- Returns the raw bundle content as a string.
function Crux:GetActiveConfig()
    local endpoint = string.format(
        "/projects/%s/environments/%s/config/active/download",
        self.ProjectID, self.EnvironmentID
    )
    local _, response = self:Request("GET", endpoint)
    return response and response.Body
end

return Crux
