export * from "./types.js";
export * from "./worldpack.js";

import {
  CruxOptions,
  CruxError,
  AuthResult,
  PlayerDocument,
  DocumentWrite,
  DocumentPatchOperation,
  LeaderboardEntry,
  PlayerStanding,
  BalanceAdjustment,
  InventoryAdjustment,
  PlayerEconomy,
  MatchmakingTicket,
  MatchmakingStatus,
  ServerRegistration,
  ServerInfo,
} from "./types.js";

/**
 * Crux client for JavaScript / TypeScript.
 *
 * **Server mode** (Node.js game server / trusted backend):
 * ```ts
 * const gsb = CruxClient.forServer("https://crux.supercraft.host", "<PROJECT_ID>", "<ENVIRONMENT_ID>", "<SERVER_TOKEN>");
 * ```
 *
 * **Player mode** (browser or game client):
 * ```ts
 * const gsb = CruxClient.forPlayer("https://crux.supercraft.host", "<PROJECT_ID>", "<ENVIRONMENT_ID>", "<API_KEY>");
 * const auth = await gsb.loginAnonymous();
 * ```
 *
 * PROJECT_ID and ENVIRONMENT_ID are UUIDs; API_KEY / SERVER_TOKEN are the secret
 * strings issued on the Credentials page of the Crux dashboard.
 */
export class CruxClient {
  private readonly opts: Required<CruxOptions>;
  private playerToken:  string = "";
  private refreshToken: string = "";
  public  playerId:     string = "";

  private constructor(opts: CruxOptions) {
    this.opts = {
      baseUrl:       opts.baseUrl.replace(/\/$/, ""),
      projectId:     opts.projectId,
      environmentId: opts.environmentId,
      serverToken:   opts.serverToken  ?? "",
      apiKey:        opts.apiKey       ?? "",
      maxRetries:    opts.maxRetries   ?? 3,
      timeoutMs:     opts.timeoutMs    ?? 30_000,
    };
  }

  static forServer(baseUrl: string, projectId: string, environmentId: string, serverToken: string): CruxClient {
    return new CruxClient({ baseUrl, projectId, environmentId, serverToken });
  }

  static forPlayer(baseUrl: string, projectId: string, environmentId: string, apiKey: string): CruxClient {
    return new CruxClient({ baseUrl, projectId, environmentId, apiKey });
  }

  // ── Auth ───────────────────────────────────────────────────────────────────

  async loginAnonymous(anonymousId?: string): Promise<AuthResult> {
    const id = anonymousId ?? ((globalThis as any).crypto?.randomUUID?.()
      ?? ("anon-" + Date.now().toString(36) + Math.random().toString(36).slice(2)));
    return this.authRequest("/v1/auth/anonymous", { anonymous_id: id });
  }

  async loginEmail(email: string, password: string): Promise<AuthResult> {
    return this.authRequest("/v1/auth/login", { email, password });
  }

  async registerEmail(email: string, password: string): Promise<AuthResult> {
    return this.authRequest("/v1/auth/register", { email, password });
  }

  async refreshAccessToken(): Promise<AuthResult> {
    if (!this.refreshToken) throw new CruxError(0, "No refresh token - call a login method first.");
    return this.authRequest("/v1/auth/refresh", { refresh_token: this.refreshToken });
  }

  async logout(): Promise<void> {
    await this.send("POST", "/v1/auth/logout", {}, "Bearer " + this.playerToken);
    this.playerToken  = "";
    this.refreshToken = "";
    this.playerId     = "";
  }

  private async authRequest(path: string, body: Record<string, unknown>): Promise<AuthResult> {
    const result = await this.send<AuthResult>("POST", path, body, "ApiKey " + this.opts.apiKey);
    this.playerToken  = result.access_token  ?? "";
    this.refreshToken = result.refresh_token ?? "";
    this.playerId     = result.player_id     ?? "";
    return result;
  }

  // ── Player Documents ────────────────────────────────────────────────────────

  async getPlayerDocument<T = unknown>(playerId: string, key: string): Promise<PlayerDocument<T>> {
    return this.send("GET", this.env(`/players/${enc(playerId)}/documents/${enc(key)}`), null, this.runtimeAuth());
  }

  async setPlayerDocument<T = unknown>(playerId: string, key: string, value: T, version?: number): Promise<PlayerDocument<T>> {
    const body: Record<string, unknown> = { value };
    if (version !== undefined) body.version = version;
    return this.send("PUT", this.env(`/players/${enc(playerId)}/documents/${enc(key)}`), body, this.runtimeAuth());
  }

  async patchPlayerDocument<T = unknown>(
    playerId: string,
    key: string,
    operations: DocumentPatchOperation<T>[],
    version?: number,
  ): Promise<PlayerDocument<T>> {
    const body: Record<string, unknown> = { operations };
    if (version !== undefined) body.version = version;
    return this.send("PATCH", this.env(`/players/${enc(playerId)}/documents/${enc(key)}`), body, this.runtimeAuth());
  }

  async deletePlayerDocument(playerId: string, key: string): Promise<void> {
    await this.send("DELETE", this.env(`/players/${enc(playerId)}/documents/${enc(key)}`), null, this.runtimeAuth());
  }

  async batchGetPlayerDocuments<T = unknown>(playerId: string, keys: string[]): Promise<PlayerDocument<T>[]> {
    return this.send<PlayerDocument<T>[]>(
      "POST", this.env(`/players/${enc(playerId)}/documents/batch-read`), { keys }, this.runtimeAuth(),
    );
  }

  async batchWritePlayerDocuments<T = unknown>(playerId: string, writes: DocumentWrite<T>[]): Promise<void> {
    await this.send("POST", this.env(`/players/${enc(playerId)}/documents/batch-write`), { items: writes }, this.runtimeAuth());
  }

  // ── Leaderboards ────────────────────────────────────────────────────────────

  async submitScore(leaderboardId: string, playerId: string, score: number, metadata: Record<string, unknown> = {}): Promise<void> {
    await this.send("POST", this.env(`/leaderboards/${enc(leaderboardId)}/scores`),
      { player_id: playerId, score, metadata }, this.runtimeAuth());
  }

  async getTop(leaderboardId: string, limit = 10): Promise<LeaderboardEntry[]> {
    return this.send<LeaderboardEntry[]>(
      "GET", this.env(`/leaderboards/${enc(leaderboardId)}/top?limit=${limit}`), null, this.runtimeAuth(),
    );
  }

  async getPlayerStanding(leaderboardId: string, playerId: string): Promise<PlayerStanding | null> {
    try {
      return await this.send<PlayerStanding>(
        "GET", this.env(`/leaderboards/${enc(leaderboardId)}/players/${enc(playerId)}`), null, this.runtimeAuth(),
      );
    } catch (e) {
      if (e instanceof CruxError && e.statusCode === 404) return null;
      throw e;
    }
  }

  async getAroundPlayer(leaderboardId: string, playerId: string, radius = 3): Promise<LeaderboardEntry[]> {
    return this.send<LeaderboardEntry[]>(
      "GET", this.env(`/leaderboards/${enc(leaderboardId)}/players/${enc(playerId)}/around?radius=${radius}`),
      null, this.runtimeAuth(),
    );
  }

  // ── Economy ─────────────────────────────────────────────────────────────────

  async getPlayerEconomy(playerId: string): Promise<PlayerEconomy> {
    return this.send("GET", this.env(`/players/${enc(playerId)}/economy`), null, this.runtimeAuth());
  }

  async adjustEconomy(
    playerId:             string,
    balanceAdjustments:   BalanceAdjustment[]   = [],
    inventoryAdjustments: InventoryAdjustment[]  = [],
  ): Promise<PlayerEconomy> {
    return this.send("POST", this.env(`/players/${enc(playerId)}/economy/adjust`), {
      balance_adjustments:   balanceAdjustments,
      inventory_adjustments: inventoryAdjustments,
    }, this.runtimeAuth());
  }

  // ── Matchmaking ─────────────────────────────────────────────────────────────

  async joinMatchmaking(playerId: string, gameMode: string, region = "global"): Promise<MatchmakingTicket> {
    return this.send("POST", this.env("/matchmaking/join"),
      { player_id: playerId, game_mode: gameMode, region }, this.runtimeAuth());
  }

  async getMatchmakingStatus(): Promise<MatchmakingStatus> {
    return this.send("GET", this.env("/matchmaking/status"), null, this.runtimeAuth());
  }

  async leaveMatchmaking(playerId: string): Promise<void> {
    await this.send("POST", this.env("/matchmaking/leave"), { player_id: playerId }, this.runtimeAuth());
  }

  // ── Server Registry ─────────────────────────────────────────────────────────

  async registerServer(registration: ServerRegistration): Promise<ServerInfo> {
    return this.send("POST", this.env("/servers"), { ...registration }, this.serverAuth());
  }

  async heartbeat(serverId: string): Promise<void> {
    await this.send("POST", this.env("/servers/heartbeat"), { server_id: serverId }, this.serverAuth());
  }

  async deregisterServer(serverId: string): Promise<void> {
    await this.send("POST", this.env("/servers/deregister"), { server_id: serverId }, this.serverAuth());
  }

  async listServers(filters: { region?: string; mapName?: string; gameMode?: string } = {}): Promise<ServerInfo[]> {
    const qs = buildQuery({ region: filters.region, map_name: filters.mapName, game_mode: filters.gameMode });
    return this.send<ServerInfo[]>("GET", this.env("/browser" + qs), null, this.runtimeAuth());
  }

  // ── Config ───────────────────────────────────────────────────────────────────

  async downloadActiveConfigBundle(): Promise<ArrayBuffer> {
    const url = this.opts.baseUrl + this.env("/configs/active/bundle");
    const resp = await fetch(url, {
      headers: { Authorization: this.runtimeAuth() },
      signal: AbortSignal.timeout(this.opts.timeoutMs),
    });
    if (!resp.ok) throw new CruxError(resp.status, `Crux ${resp.status} downloading config bundle`);
    return resp.arrayBuffer();
  }

  // ── HTTP internals ───────────────────────────────────────────────────────────

  private env(suffix: string): string {
    return `/v1/projects/${this.opts.projectId}/environments/${this.opts.environmentId}${suffix}`;
  }

  private runtimeAuth(): string {
    if (this.opts.serverToken) return "ServerToken " + this.opts.serverToken;
    if (this.playerToken)      return "Bearer "      + this.playerToken;
    throw new CruxError(0, "Crux: no server token or player token - call forServer() or a login method first.");
  }

  private serverAuth(): string {
    if (this.opts.serverToken) return "ServerToken " + this.opts.serverToken;
    throw new CruxError(0, "Crux: server token required - use CruxClient.forServer(...).");
  }

  private async send<T = unknown>(
    method:  string,
    path:    string,
    body:    Record<string, unknown> | null,
    auth:    string,
  ): Promise<T> {
    const url     = this.opts.baseUrl + path;
    const headers: Record<string, string> = { Authorization: auth };
    if (body !== null) headers["Content-Type"] = "application/json";

    let lastError: unknown;
    let backoff = 1000;

    for (let attempt = 0; attempt <= this.opts.maxRetries; attempt++) {
      let resp: Response;
      try {
        resp = await fetch(url, {
          method,
          headers,
          body:   body !== null ? JSON.stringify(body) : undefined,
          signal: AbortSignal.timeout(this.opts.timeoutMs),
        });
      } catch (e) {
        lastError = e;
        if (attempt < this.opts.maxRetries) {
          await delay(backoff);
          backoff *= 2;
          continue;
        }
        throw e;
      }

      if (resp.status === 429 || resp.status === 503) {
        if (attempt < this.opts.maxRetries) {
          const retryAfter = Number(resp.headers.get("Retry-After") ?? 0) * 1000 || backoff;
          await delay(retryAfter);
          backoff *= 2;
          continue;
        }
      }

      const text = await resp.text();
      if (!resp.ok) {
        let message = text;
        try { message = JSON.parse(text)?.message ?? text; } catch { /* ignore */ }
        throw new CruxError(resp.status, `Crux ${resp.status} ${method} ${path}: ${message}`);
      }

      if (!text) return {} as T;
      return JSON.parse(text) as T;
    }

    throw lastError ?? new CruxError(0, "Crux: max retries exceeded");
  }
}

function enc(s: string): string {
  return encodeURIComponent(s);
}

function delay(ms: number): Promise<void> {
  return new Promise(resolve => setTimeout(resolve, ms));
}

function buildQuery(params: Record<string, string | undefined>): string {
  const parts: string[] = [];
  for (const [k, v] of Object.entries(params)) {
    if (v) parts.push(`${k}=${encodeURIComponent(v)}`);
  }
  return parts.length ? "?" + parts.join("&") : "";
}

// ── Deprecated back-compat aliases (Crux* → Crux*, renamed in v0.2.0) ───────────
// Kept so existing imports keep working. Prefer the Crux* names in new code.

/** @deprecated Renamed to {@link CruxClient}. */
export const CruxClient = CruxClient;
/** @deprecated Renamed to {@link CruxOptions}. */
export type GSBOptions = CruxOptions;
/** @deprecated Renamed to {@link CruxError}. */
export { CruxError as GSBError };
