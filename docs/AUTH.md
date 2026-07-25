# Authentication

Crux has three authentication modes. Every SDK in this repo speaks all
three; the differences are only in how the values are passed at init.

## The three modes

| Mode | Header | Used by | Carries |
|---|---|---|---|
| **API key** | `Authorization: ApiKey <API_KEY>` | game clients (player-side) | project + environment identity |
| **Server token** | `Authorization: ServerToken <SERVER_TOKEN>` | dedicated game servers, your backend | project authority (full access) |
| **Player JWT** | `Authorization: Bearer eyJ…` | game clients, after login | a specific player's identity |

In typical use:

- A **game client** initializes with an API key, then calls one of the
  login methods (`loginAnonymous`, `loginEmail`). The SDK stores the
  returned JWT and attaches `Bearer …` to every subsequent call.
- A **dedicated game server** (or your backend service) initializes
  with a server token. No login step - the server token authenticates
  every call.

See also: [Guest login and account upgrade - crux.supercraft.host](https://crux.supercraft.host/blog/guest-login-and-account-upgrade).

## Choosing the right mode

```
                ┌──────────────────────┐
                │  Where does the code │
                │       run?           │
                └──────────┬───────────┘
                           │
            ┌──────────────┼──────────────┐
            ▼                             ▼
   ┌──────────────────┐         ┌──────────────────┐
   │   Game client    │         │ Server / backend │
   │  (player device) │         │  (your machine)  │
   └────────┬─────────┘         └────────┬─────────┘
            │                            │
            ▼                            ▼
   ┌──────────────────┐         ┌──────────────────┐
   │  API key + then  │         │  Server token    │
   │   login → JWT    │         │   (no login)     │
   └──────────────────┘         └──────────────────┘
```

Rules:

- **Never ship a server token in a client build.** It carries full
  project authority - anyone who extracts it from your `.exe`, `.ipa`,
  Unity build, or Roblox place can read and write every player's data.
- **API keys are fine to ship in clients.** They identify the project
  and environment, but cannot do anything until a player logs in.
- **Player JWTs are short-lived** (~1 hour by default). The SDK
  refreshes them automatically using the refresh token returned at
  login.

## Roblox

Roblox is the exception. Roblox already has its own identity layer
(every player has a `UserId`), so the Roblox SDK *uses the server
token* and verifies players via `HttpService` + the player's
`UserId`. There is no client-side init in the Roblox SDK - every call
runs on a server script inside the Roblox experience.

See [Roblox HttpService → external backend on crux.supercraft.host](https://crux.supercraft.host/blog/roblox-httpservice-external-backend)
for the architectural picture.

## Per-SDK init signatures

### JavaScript

```ts
const player = CruxClient.forPlayer(baseUrl, projectId, envId, apiKey);
const server = CruxClient.forServer(baseUrl, projectId, envId, serverToken);
```

### Godot

```gdscript
Crux.init_player(base_url, project_id, env_id, api_key)
Crux.init_server(base_url, project_id, env_id, server_token)
```

### Unity

```csharp
var player = CruxClient.ForPlayer(baseUrl, projectId, envId, apiKey);
var server = CruxClient.ForServer(baseUrl, projectId, envId, serverToken);
```

### Roblox (server-only)

```lua
local gsb = Crux.init(projectId, serverToken, envId)
```

## Rotating keys

If a key leaks, rotate it immediately from the Crux dashboard
([crux.supercraft.host](https://crux.supercraft.host/) → your project →
*API Keys*). Rotation is instant - old keys stop working on the next
request. Bake the new key into your next client build (for API keys)
or restart your server pool (for server tokens).

## JWT details

Player JWTs are signed JWS tokens, RS256, 1-hour TTL by default. The
SDKs verify only that the token *parses* - they trust Crux to have
signed it. Your own server code that consumes player JWTs (e.g. for
authenticating webhooks or out-of-band requests) should verify the
signature against the public key published at
`https://crux.supercraft.host/.well-known/jwks.json`.
