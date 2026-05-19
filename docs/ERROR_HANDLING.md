# Error handling

Every GSB SDK exposes failures in the language-native way (exceptions
in JS/C#, `{ ok = false, status, message }` tables in Lua, error
dictionaries in GDScript). Under that surface, the semantics are
shared.

## HTTP status → meaning

| status | meaning | what to do |
|---|---|---|
| `400 Bad Request` | The request body or query string is malformed. | Fix the call. Not retryable. |
| `401 Unauthorized` | Missing or invalid auth header. | Log in / refresh token. |
| `403 Forbidden` | Auth is valid but doesn't have permission for this action. | Check the auth mode (API key vs server token vs JWT). |
| `404 Not Found` | The resource doesn't exist. | For `getPlayerDocument`, this is normal first-write behaviour — handle it as `null` / empty. |
| `409 Conflict` | Optimistic-concurrency conflict on a versioned write. | Re-read, merge, retry. |
| `412 Precondition Failed` | You passed an `If-Match` / version that doesn't match server state. | Re-read and retry. |
| `429 Too Many Requests` | Rate limit hit. | Honour `Retry-After`; SDKs do this for you. |
| `500 Internal Server Error` | GSB is unhappy. | Surface the error; retry only if idempotent. |
| `503 Service Unavailable` | Transient — GSB is degraded. | SDKs auto-retry up to 3× with exponential backoff. |

## Automatic retries

The SDKs all retry on the same conditions:

- `429` — respect `Retry-After` header.
- `503` — exponential backoff, 1s → 2s → 4s, then give up.
- Network errors (timeout, DNS failure) — same backoff.

No other status is retried — `400`, `401`, `403`, `404`, `409`, `412`,
`500` are surfaced immediately. Don't paper over them with your own
retry loop; investigate the cause.

## Per-SDK error type

### JavaScript

```ts
import { GSBClient, GSBError } from "@supercraft/gsb";

try {
  await gsb.getPlayerDocument(playerId, "inventory");
} catch (e) {
  if (e instanceof GSBError) {
    if (e.statusCode === 404) { /* first write */ }
    if (e.statusCode === 409) { /* concurrency */ }
    console.error(`HTTP ${e.statusCode}: ${e.message}`);
  }
}
```

### Godot

```gdscript
var result = await GSB.get_player_document(pid, "inventory")
if result.has("error"):
    if result.status == 404:
        # first write
        pass
    elif result.status == 409:
        # concurrency conflict
        pass
    push_warning("GSB %d: %s" % [result.status, result.error])
```

### Unity

```csharp
try {
    var doc = await gsb.GetPlayerDocumentAsync(playerId, "inventory");
} catch (GSBException ex) {
    if (ex.StatusCode == 404) { /* first write */ }
    if (ex.StatusCode == 409) { /* concurrency */ }
    Debug.LogError($"HTTP {ex.StatusCode}: {ex.Message}");
}
```

### Roblox

```lua
local ok, result = pcall(function()
    return gsb:GetPlayerEconomy(player.UserId)
end)
if not ok then
    warn("GSB call failed: " .. tostring(result))
end
-- For methods that return result tables:
local res = gsb:GetLeaderboardTop("weekly", 10)
if res.error then
    warn("GSB " .. res.status .. ": " .. res.error)
end
```

## Optimistic concurrency on documents

`setPlayerDocument` accepts an optional `version` argument. When you
pass it, GSB compares the version to the one currently stored and
returns `409 Conflict` if they differ. Pattern:

```ts
const doc = await gsb.getPlayerDocument(playerId, "inventory");
const updated = { ...doc.value, gold: doc.value.gold + 100 };
try {
  await gsb.setPlayerDocument(playerId, "inventory", updated, doc.version);
} catch (e) {
  if (e instanceof GSBError && e.statusCode === 409) {
    // Someone else wrote first — re-read and re-merge.
    return retryWithFreshRead();
  }
  throw e;
}
```

If you don't pass `version`, GSB performs a last-write-wins update.
That's fine for some workloads (e.g. UI preferences), wrong for others
(e.g. currency balances — use the `adjustEconomy` API for those, which
is atomic on the server side).
