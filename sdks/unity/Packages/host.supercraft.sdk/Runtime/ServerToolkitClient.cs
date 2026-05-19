using System;
using System.Text;
using System.Threading;
using System.Threading.Tasks;
using UnityEngine;
using UnityEngine.Networking;

namespace Supercraft.GSB
{
    /// <summary>
    /// GSB client for Unity. Supports two modes:
    /// <list type="bullet">
    ///   <item><see cref="ForServer"/> - dedicated game server, uses a server token.</item>
    ///   <item><see cref="ForPlayer"/> - game client, uses an API key for auth then stores the player JWT internally.</item>
    /// </list>
    /// </summary>
    public sealed class GSBClient
    {
        private readonly GSBOptions _opts;
        private string _playerToken;
        private string _refreshToken;

        public string PlayerId { get; private set; }

        private GSBClient(GSBOptions opts) => _opts = opts;

        public static GSBClient ForServer(string baseUrl, string projectId, string environmentId, string serverToken)
            => new GSBClient(new GSBOptions
            {
                BaseUrl       = baseUrl,
                ProjectId     = projectId,
                EnvironmentId = environmentId,
                ServerToken   = serverToken,
            });

        public static GSBClient ForPlayer(string baseUrl, string projectId, string environmentId, string apiKey)
            => new GSBClient(new GSBOptions
            {
                BaseUrl       = baseUrl,
                ProjectId     = projectId,
                EnvironmentId = environmentId,
                ApiKey        = apiKey,
            });

        // ── Auth ─────────────────────────────────────────────────────────────

        public Task<AuthResult> LoginAnonymousAsync(CancellationToken ct = default)
            => AuthAsync("POST", "/v1/auth/anonymous", "{}", useApiKey: true, ct);

        public Task<AuthResult> LoginEmailAsync(string email, string password, CancellationToken ct = default)
            => AuthAsync("POST", "/v1/auth/login",
                $"{{\"email\":{JsonStr(email)},\"password\":{JsonStr(password)}}}",
                useApiKey: true, ct);

        public Task<AuthResult> RegisterEmailAsync(string email, string password, CancellationToken ct = default)
            => AuthAsync("POST", "/v1/auth/register",
                $"{{\"email\":{JsonStr(email)},\"password\":{JsonStr(password)}}}",
                useApiKey: true, ct);

        public Task<AuthResult> RefreshTokenAsync(CancellationToken ct = default)
        {
            if (string.IsNullOrEmpty(_refreshToken))
                throw new InvalidOperationException("No refresh token. Call a Login method first.");
            return AuthAsync("POST", "/v1/auth/refresh",
                $"{{\"refresh_token\":{JsonStr(_refreshToken)}}}",
                useApiKey: true, ct);
        }

        public async Task LogoutAsync(CancellationToken ct = default)
        {
            await SendAsync("POST", "/v1/auth/logout", "{}", authHeader: "Bearer " + _playerToken, ct: ct);
            _playerToken  = null;
            _refreshToken = null;
            PlayerId      = null;
        }

        private async Task<AuthResult> AuthAsync(string method, string path, string body, bool useApiKey, CancellationToken ct)
        {
            var auth = useApiKey ? "ApiKey " + _opts.ApiKey : "Bearer " + _playerToken;
            var json = await SendTextAsync(method, path, body, auth, ct);
            var result = JsonUtility.FromJson<AuthResult>(json);
            _playerToken  = result.access_token;
            _refreshToken = result.refresh_token;
            PlayerId      = result.player_id;
            return result;
        }

        // ── Player Documents ──────────────────────────────────────────────────

        public async Task<PlayerDocument> GetPlayerDocumentAsync(string playerId, string key, CancellationToken ct = default)
        {
            var json = await SendTextAsync("GET", EnvPath($"/players/{Esc(playerId)}/documents/{Esc(key)}"), null, RuntimeAuth(), ct);
            return ParseDocument(json, key);
        }

        public async Task<PlayerDocument> SetPlayerDocumentAsync(string playerId, string key, string valueJson, int? version = null, CancellationToken ct = default)
        {
            var body = version.HasValue
                ? $"{{\"value\":{valueJson},\"version\":{version}}}"
                : $"{{\"value\":{valueJson}}}";
            var json = await SendTextAsync("PUT", EnvPath($"/players/{Esc(playerId)}/documents/{Esc(key)}"), body, RuntimeAuth(), ct);
            return ParseDocument(json, key);
        }

        public async Task<PlayerDocument> PatchPlayerDocumentAsync(string playerId, string key, DocumentPatchOperation[] operations, int? version = null, CancellationToken ct = default)
        {
            var ops = new string[operations.Length];
            for (int i = 0; i < operations.Length; i++)
            {
                var op = operations[i];
                var opName = string.IsNullOrEmpty(op.op) ? "set" : op.op;
                var pathJson = SerializeArray(op.path, JsonStr);
                if (opName == "remove")
                {
                    ops[i] = $"{{\"op\":{JsonStr(opName)},\"path\":{pathJson}}}";
                    continue;
                }

                var valueJson = string.IsNullOrEmpty(op.value_json) ? "null" : op.value_json;
                ops[i] = $"{{\"op\":{JsonStr(opName)},\"path\":{pathJson},\"value\":{valueJson},\"create_missing\":{op.create_missing.ToString().ToLowerInvariant()}}}";
            }

            var body = version.HasValue
                ? $"{{\"operations\":[{string.Join(",", ops)}],\"version\":{version}}}"
                : $"{{\"operations\":[{string.Join(",", ops)}]}}";
            var json = await SendTextAsync("PATCH", EnvPath($"/players/{Esc(playerId)}/documents/{Esc(key)}"), body, RuntimeAuth(), ct);
            return ParseDocument(json, key);
        }

        public Task DeletePlayerDocumentAsync(string playerId, string key, CancellationToken ct = default)
            => SendAsync("DELETE", EnvPath($"/players/{Esc(playerId)}/documents/{Esc(key)}"), null, RuntimeAuth(), ct);

        public async Task<PlayerDocument[]> BatchGetPlayerDocumentsAsync(string playerId, string[] keys, CancellationToken ct = default)
        {
            var keyArray = "[" + string.Join(",", System.Array.ConvertAll(keys, JsonStr)) + "]";
            var json = await SendTextAsync("POST", EnvPath($"/players/{Esc(playerId)}/documents/batch-read"),
                $"{{\"keys\":{keyArray}}}", RuntimeAuth(), ct);
            // response: {"documents":[{key,value,version,updated_at},...]}
            return ParseDocumentArray(json);
        }

        public Task BatchWritePlayerDocumentsAsync(string playerId, DocumentWrite[] writes, CancellationToken ct = default)
        {
            var items = new string[writes.Length];
            for (int i = 0; i < writes.Length; i++)
            {
                var w = writes[i];
                items[i] = w.has_version
                    ? $"{{\"key\":{JsonStr(w.key)},\"value\":{w.value_json},\"version\":{w.version}}}"
                    : $"{{\"key\":{JsonStr(w.key)},\"value\":{w.value_json}}}";
            }
            var body = $"{{\"items\":[{string.Join(",", items)}]}}";
            return SendAsync("POST", EnvPath($"/players/{Esc(playerId)}/documents/batch-write"), body, RuntimeAuth(), ct);
        }

        // ── Leaderboards ──────────────────────────────────────────────────────

        public Task SubmitScoreAsync(string leaderboardId, string playerId, double score, string metadataJson = null, CancellationToken ct = default)
        {
            var meta = metadataJson ?? "{}";
            var body = $"{{\"player_id\":{JsonStr(playerId)},\"score\":{score},\"metadata\":{meta}}}";
            return SendAsync("POST", EnvPath($"/leaderboards/{Esc(leaderboardId)}/scores"), body, RuntimeAuth(), ct);
        }

        public async Task<LeaderboardEntry[]> GetTopAsync(string leaderboardId, int limit = 10, CancellationToken ct = default)
        {
            var json = await SendTextAsync("GET", EnvPath($"/leaderboards/{Esc(leaderboardId)}/top?limit={limit}"), null, RuntimeAuth(), ct);
            return ParseEntryArray(json);
        }

        public async Task<PlayerStanding> GetPlayerStandingAsync(string leaderboardId, string playerId, CancellationToken ct = default)
        {
            var json = await SendTextAsync("GET", EnvPath($"/leaderboards/{Esc(leaderboardId)}/players/{Esc(playerId)}"), null, RuntimeAuth(), ct);
            return JsonUtility.FromJson<PlayerStanding>(json);
        }

        public async Task<LeaderboardEntry[]> GetAroundPlayerAsync(string leaderboardId, string playerId, int radius = 3, CancellationToken ct = default)
        {
            var json = await SendTextAsync("GET", EnvPath($"/leaderboards/{Esc(leaderboardId)}/players/{Esc(playerId)}/around?radius={radius}"), null, RuntimeAuth(), ct);
            return ParseEntryArray(json);
        }

        // ── Economy ───────────────────────────────────────────────────────────

        public async Task<PlayerEconomy> GetPlayerEconomyAsync(string playerId, CancellationToken ct = default)
        {
            var json = await SendTextAsync("GET", EnvPath($"/players/{Esc(playerId)}/economy"), null, RuntimeAuth(), ct);
            return JsonUtility.FromJson<PlayerEconomy>(json);
        }

        public Task AdjustEconomyAsync(string playerId, BalanceAdjustment[] balances = null, InventoryAdjustment[] inventory = null, CancellationToken ct = default)
        {
            var balJson = SerializeArray(balances, b => $"{{\"currency_id\":{JsonStr(b.currency_id)},\"amount\":{b.amount}}}");
            var invJson = SerializeArray(inventory, i => $"{{\"item_id\":{JsonStr(i.item_id)},\"quantity\":{i.quantity}}}");
            var body = $"{{\"balance_adjustments\":{balJson},\"inventory_adjustments\":{invJson}}}";
            return SendAsync("POST", EnvPath($"/players/{Esc(playerId)}/economy/adjust"), body, RuntimeAuth(), ct);
        }

        // ── Matchmaking ───────────────────────────────────────────────────────

        public async Task<MatchmakingTicket> JoinMatchmakingAsync(string playerId, string gameMode, string region = "global", CancellationToken ct = default)
        {
            var body = $"{{\"player_id\":{JsonStr(playerId)},\"game_mode\":{JsonStr(gameMode)},\"region\":{JsonStr(region)}}}";
            var json = await SendTextAsync("POST", EnvPath("/matchmaking/join"), body, RuntimeAuth(), ct);
            return JsonUtility.FromJson<MatchmakingTicket>(json);
        }

        public async Task<MatchmakingStatus> GetMatchmakingStatusAsync(CancellationToken ct = default)
        {
            var json = await SendTextAsync("GET", EnvPath("/matchmaking/status"), null, RuntimeAuth(), ct);
            return JsonUtility.FromJson<MatchmakingStatus>(json);
        }

        public Task LeaveMatchmakingAsync(string playerId, CancellationToken ct = default)
            => SendAsync("POST", EnvPath("/matchmaking/leave"), $"{{\"player_id\":{JsonStr(playerId)}}}", RuntimeAuth(), ct);

        // ── Server Registry ───────────────────────────────────────────────────

        public async Task<ServerInfo> RegisterServerAsync(ServerRegistration reg, CancellationToken ct = default)
        {
            var body = JsonUtility.ToJson(reg);
            var json = await SendTextAsync("POST", EnvPath("/servers"), body, ServerAuth(), ct);
            return JsonUtility.FromJson<ServerInfo>(json);
        }

        public Task HeartbeatAsync(string serverId, CancellationToken ct = default)
            => SendAsync("POST", EnvPath("/servers/heartbeat"), $"{{\"server_id\":{JsonStr(serverId)}}}", ServerAuth(), ct);

        public Task DeregisterServerAsync(string serverId, CancellationToken ct = default)
            => SendAsync("POST", EnvPath("/servers/deregister"), $"{{\"server_id\":{JsonStr(serverId)}}}", ServerAuth(), ct);

        public async Task<ServerInfo[]> ListServersAsync(string region = null, string mapName = null, string gameMode = null, CancellationToken ct = default)
        {
            var qs = BuildQuery(("region", region), ("map_name", mapName), ("game_mode", gameMode));
            var json = await SendTextAsync("GET", EnvPath("/browser" + qs), null, RuntimeAuth(), ct);
            return ParseServerArray(json);
        }

        // ── Config ────────────────────────────────────────────────────────────

        public Task<byte[]> DownloadActiveConfigBundleAsync(CancellationToken ct = default)
            => SendBytesAsync(EnvPath("/configs/active/bundle"), RuntimeAuth(), ct);

        // ── HTTP internals ────────────────────────────────────────────────────

        private string RuntimeAuth()
        {
            if (!string.IsNullOrEmpty(_opts.ServerToken)) return "ServerToken " + _opts.ServerToken;
            if (!string.IsNullOrEmpty(_playerToken))      return "Bearer "      + _playerToken;
            throw new InvalidOperationException("GSB: no server token or player token available. Call Login first or use ForServer.");
        }

        private string ServerAuth()
        {
            if (!string.IsNullOrEmpty(_opts.ServerToken)) return "ServerToken " + _opts.ServerToken;
            throw new InvalidOperationException("GSB: server token required. Use GSBClient.ForServer(...).");
        }

        private string EnvPath(string suffix)
            => $"/v1/projects/{_opts.ProjectId}/environments/{_opts.EnvironmentId}{suffix}";

        private async Task<string> SendTextAsync(string method, string path, string jsonBody, string authHeader, CancellationToken ct)
        {
            var lastError = "";
            var backoff   = 1f;

            for (int attempt = 0; attempt <= _opts.MaxRetries; attempt++)
            {
                using var req = BuildRequest(method, path, jsonBody, authHeader);
                var op = req.SendWebRequest();
                while (!op.isDone)
                {
                    ct.ThrowIfCancellationRequested();
                    await Task.Yield();
                }

                if (req.responseCode == 429 || req.responseCode == 503)
                {
                    if (attempt < _opts.MaxRetries)
                    {
                        var retryAfter = float.TryParse(req.GetResponseHeader("Retry-After"), out var ra) ? ra : backoff;
                        await Task.Delay((int)(retryAfter * 1000), ct);
                        backoff *= 2;
                        continue;
                    }
                }

                if (req.result != UnityWebRequest.Result.Success)
                {
                    lastError = $"GSB HTTP {req.responseCode}: {req.downloadHandler?.text ?? req.error}";
                    if (attempt < _opts.MaxRetries && (req.responseCode == 0 || req.responseCode >= 500))
                    {
                        await Task.Delay((int)(backoff * 1000), ct);
                        backoff *= 2;
                        continue;
                    }
                    throw new GSBException((int)req.responseCode, lastError);
                }

                return req.downloadHandler.text;
            }

            throw new GSBException(0, lastError);
        }

        private async Task SendAsync(string method, string path, string jsonBody, string authHeader, CancellationToken ct)
            => await SendTextAsync(method, path, jsonBody, authHeader, ct);

        private async Task<byte[]> SendBytesAsync(string path, string authHeader, CancellationToken ct)
        {
            using var req = BuildRequest("GET", path, null, authHeader);
            req.downloadHandler = new DownloadHandlerBuffer();
            var op = req.SendWebRequest();
            while (!op.isDone)
            {
                ct.ThrowIfCancellationRequested();
                await Task.Yield();
            }
            if (req.result != UnityWebRequest.Result.Success)
                throw new GSBException((int)req.responseCode, req.error);
            return req.downloadHandler.data;
        }

        private UnityWebRequest BuildRequest(string method, string path, string jsonBody, string authHeader)
        {
            var url = _opts.BaseUrl.TrimEnd('/') + path;
            var req = new UnityWebRequest(url, method)
            {
                downloadHandler = new DownloadHandlerBuffer(),
                timeout         = _opts.TimeoutSeconds,
            };
            req.SetRequestHeader("Authorization", authHeader);
            if (!string.IsNullOrEmpty(jsonBody))
            {
                req.uploadHandler = new UploadHandlerRaw(Encoding.UTF8.GetBytes(jsonBody));
                req.SetRequestHeader("Content-Type", "application/json");
            }
            return req;
        }

        // ── Parsing helpers ───────────────────────────────────────────────────

        private static PlayerDocument ParseDocument(string json, string fallbackKey)
        {
            // Backend returns: {"key":"...","value":<arbitrary json>,"version":N,"updated_at":"..."}
            // We extract value as a raw substring since JsonUtility can't handle arbitrary JSON.
            var doc = new PlayerDocument { key = fallbackKey };
            doc.version    = ExtractInt(json,    "\"version\"");
            doc.updated_at = ExtractString(json, "updated_at");
            doc.key        = ExtractString(json, "key") ?? fallbackKey;
            doc.raw_value  = ExtractRawValue(json);
            return doc;
        }

        private static PlayerDocument[] ParseDocumentArray(string json)
        {
            // Minimal parse of {"documents":[...]} - split on top-level objects.
            var inner = ExtractArray(json, "documents");
            if (string.IsNullOrEmpty(inner)) return System.Array.Empty<PlayerDocument>();
            var items = SplitTopLevelObjects(inner);
            var result = new PlayerDocument[items.Length];
            for (int i = 0; i < items.Length; i++) result[i] = ParseDocument(items[i], "");
            return result;
        }

        private static LeaderboardEntry[] ParseEntryArray(string json)
        {
            var inner = ExtractArray(json, "entries");
            if (string.IsNullOrEmpty(inner)) return System.Array.Empty<LeaderboardEntry>();
            var items = SplitTopLevelObjects(inner);
            var result = new LeaderboardEntry[items.Length];
            for (int i = 0; i < items.Length; i++)
            {
                result[i] = new LeaderboardEntry
                {
                    rank      = ExtractInt(items[i],    "\"rank\""),
                    score     = ExtractDouble(items[i], "\"score\""),
                    player_id = ExtractString(items[i], "player_id"),
                };
            }
            return result;
        }

        private static ServerInfo[] ParseServerArray(string json)
        {
            var inner = ExtractArray(json, "servers");
            if (string.IsNullOrEmpty(inner)) return System.Array.Empty<ServerInfo>();
            var items = SplitTopLevelObjects(inner);
            var result = new ServerInfo[items.Length];
            for (int i = 0; i < items.Length; i++) result[i] = JsonUtility.FromJson<ServerInfo>(items[i]);
            return result;
        }

        // ── Minimal JSON extraction (no dependencies) ─────────────────────────

        private static string ExtractString(string json, string fieldName)
        {
            var needle = $"\"{fieldName}\":\"";
            var start  = json.IndexOf(needle, StringComparison.Ordinal);
            if (start < 0) return null;
            start += needle.Length;
            var end = json.IndexOf('"', start);
            return end < 0 ? null : json.Substring(start, end - start);
        }

        private static int ExtractInt(string json, string fieldName)
        {
            var needle = fieldName + ":";
            var start  = json.IndexOf(needle, StringComparison.Ordinal);
            if (start < 0) return 0;
            start += needle.Length;
            while (start < json.Length && (json[start] == ' ')) start++;
            var end = start;
            while (end < json.Length && (char.IsDigit(json[end]) || json[end] == '-')) end++;
            return int.TryParse(json.Substring(start, end - start), out var v) ? v : 0;
        }

        private static double ExtractDouble(string json, string fieldName)
        {
            var needle = fieldName + ":";
            var start  = json.IndexOf(needle, StringComparison.Ordinal);
            if (start < 0) return 0;
            start += needle.Length;
            while (start < json.Length && json[start] == ' ') start++;
            var end = start;
            while (end < json.Length && (char.IsDigit(json[end]) || json[end] == '-' || json[end] == '.')) end++;
            return double.TryParse(json.Substring(start, end - start), System.Globalization.NumberStyles.Float,
                System.Globalization.CultureInfo.InvariantCulture, out var v) ? v : 0;
        }

        private static string ExtractRawValue(string json)
        {
            var needle = "\"value\":";
            var start  = json.IndexOf(needle, StringComparison.Ordinal);
            if (start < 0) return "null";
            start += needle.Length;
            while (start < json.Length && json[start] == ' ') start++;
            if (start >= json.Length) return "null";
            return json[start] == '{' || json[start] == '['
                ? ExtractBalanced(json, start)
                : ExtractScalar(json, start);
        }

        private static string ExtractArray(string json, string fieldName)
        {
            var needle = $"\"{fieldName}\":";
            var start  = json.IndexOf(needle, StringComparison.Ordinal);
            if (start < 0) return null;
            start += needle.Length;
            while (start < json.Length && json[start] != '[') start++;
            if (start >= json.Length) return null;
            return ExtractBalanced(json, start + 1, ']', '[');
        }

        private static string ExtractBalanced(string json, int start, char close = '}', char open = '{')
        {
            int depth = 1, i = start;
            while (i < json.Length && depth > 0)
            {
                if      (json[i] == open)  depth++;
                else if (json[i] == close) depth--;
                i++;
            }
            return json.Substring(start, i - start - 1);
        }

        private static string ExtractScalar(string json, int start)
        {
            if (json[start] == '"')
            {
                var end = json.IndexOf('"', start + 1);
                return end < 0 ? "null" : json.Substring(start, end - start + 1);
            }
            var e = start;
            while (e < json.Length && json[e] != ',' && json[e] != '}' && json[e] != ']') e++;
            return json.Substring(start, e - start).Trim();
        }

        private static string[] SplitTopLevelObjects(string inner)
        {
            var result = new System.Collections.Generic.List<string>();
            int i = 0;
            while (i < inner.Length)
            {
                while (i < inner.Length && inner[i] != '{') i++;
                if (i >= inner.Length) break;
                var obj = ExtractBalanced(inner, i + 1);
                result.Add("{" + obj + "}");
                i += obj.Length + 2;
            }
            return result.ToArray();
        }

        private static string SerializeArray<T>(T[] arr, Func<T, string> serialize)
        {
            if (arr == null || arr.Length == 0) return "[]";
            return "[" + string.Join(",", System.Array.ConvertAll(arr, x => serialize(x))) + "]";
        }

        private static string BuildQuery(params (string key, string val)[] pairs)
        {
            var parts = new System.Collections.Generic.List<string>();
            foreach (var (k, v) in pairs)
                if (!string.IsNullOrEmpty(v)) parts.Add(k + "=" + UnityWebRequest.EscapeURL(v));
            return parts.Count > 0 ? "?" + string.Join("&", parts) : "";
        }

        private static string JsonStr(string s) => s == null ? "null" : "\"" + s.Replace("\\", "\\\\").Replace("\"", "\\\"") + "\"";
        private static string Esc(string s)     => UnityWebRequest.EscapeURL(s ?? "");
    }

    public sealed class GSBException : Exception
    {
        public int StatusCode { get; }
        public GSBException(int statusCode, string message) : base(message) => StatusCode = statusCode;
    }
}
