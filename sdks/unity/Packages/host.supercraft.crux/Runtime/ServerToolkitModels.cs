using System;

namespace Supercraft.Crux
{
    [Serializable]
    public sealed class ServerToolkitOptions
    {
        public string BaseUrl       = "https://crux.supercraft.host";
        public string ProjectId;
        public string EnvironmentId;
        /// <summary>Server token - for dedicated game servers.</summary>
        public string ServerToken;
        /// <summary>API key - for game clients. Set automatically via Login/Register calls.</summary>
        public string ApiKey;
        public int    TimeoutSeconds = 30;
        public int    MaxRetries     = 3;
    }

    // ── Auth ─────────────────────────────────────────────────────────────────

    [Serializable]
    public sealed class AuthResult
    {
        public string player_id;
        public string access_token;
        public string refresh_token;
        public int    expires_in;
    }

    // ── Player Documents ──────────────────────────────────────────────────────

    [Serializable]
    public sealed class PlayerDocument
    {
        public string key;
        /// <summary>Raw JSON string. Use JsonUtility.FromJson&lt;T&gt; or any JSON library to deserialize.</summary>
        public string raw_value;
        public int    version;
        public string updated_at;
    }

    [Serializable]
    public sealed class DocumentWrite
    {
        public string key;
        /// <summary>Serialized JSON to store as the document value.</summary>
        public string value_json;
        /// <summary>Optional: supply the last known version to enable optimistic locking.</summary>
        public int    version;
        public bool   has_version;
    }

    [Serializable]
    public sealed class DocumentPatchOperation
    {
        /// <summary>One of: "set", "remove". Defaults to "set".</summary>
        public string   op = "set";
        public string[] path;
        /// <summary>Serialized JSON value for set operations.</summary>
        public string   value_json;
        public bool     create_missing = true;
    }

    // ── Leaderboards ─────────────────────────────────────────────────────────

    [Serializable]
    public sealed class LeaderboardEntry
    {
        public int    rank;
        public string player_id;
        public double score;
        public string metadata_json;
    }

    [Serializable]
    public sealed class PlayerStanding
    {
        public int    rank;
        public double score;
        public string player_id;
    }

    // ── Economy ───────────────────────────────────────────────────────────────

    [Serializable]
    public sealed class BalanceAdjustment
    {
        public string currency_id;
        public long   amount;
    }

    [Serializable]
    public sealed class InventoryAdjustment
    {
        public string item_id;
        public int    quantity;
    }

    [Serializable]
    public sealed class CurrencyBalance
    {
        public string currency_id;
        public string currency_name;
        public long   amount;
    }

    [Serializable]
    public sealed class InventoryEntry
    {
        public string item_id;
        public string item_name;
        public int    quantity;
        public string metadata_json;
    }

    [Serializable]
    public sealed class PlayerEconomy
    {
        public string           player_id;
        public CurrencyBalance[] balances;
        public InventoryEntry[]  inventory;
    }

    // ── Matchmaking ───────────────────────────────────────────────────────────

    [Serializable]
    public sealed class MatchmakingTicket
    {
        public string ticket_id;
        public string status;
        public string player_id;
    }

    [Serializable]
    public sealed class MatchParticipant
    {
        public string player_id;
        public string team;
    }

    [Serializable]
    public sealed class MatchInfo
    {
        public string               id;
        public string               status;
        public string               game_mode;
        public string               region;
        public MatchParticipant[]   participants;
        public string               server_id;
        public string               server_address;
    }

    [Serializable]
    public sealed class MatchmakingStatus
    {
        /// <summary>One of: "waiting", "matched", "not_found".</summary>
        public string    status;
        public MatchInfo match;
    }

    // ── Server Registry ────────────────────────────────────────────────────────

    [Serializable]
    public sealed class ServerRegistration
    {
        public string server_id;
        public string name;
        public string region;
        public string map_name;
        public string game_mode;
        public int    player_count;
        public int    max_players;
        public string version;
        public string address;
        public int    port;
    }

    [Serializable]
    public sealed class ServerInfo
    {
        public string id;
        public string server_id;
        public string name;
        public string region;
        public string map_name;
        public string game_mode;
        public int    player_count;
        public int    max_players;
        public string address;
        public int    port;
        public string version;
        public string last_heartbeat;
        public string created_at;
    }
}
