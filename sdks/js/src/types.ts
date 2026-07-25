// ── Options ──────────────────────────────────────────────────────────────────

export interface CruxOptions {
  baseUrl:       string;
  projectId:     string;
  environmentId: string;
  /** Server token - for dedicated game servers and trusted backends. */
  serverToken?:  string;
  /** API key - for game clients; set before calling login methods. */
  apiKey?:       string;
  maxRetries?:   number;
  timeoutMs?:    number;
}

// ── Auth ──────────────────────────────────────────────────────────────────────

export interface AuthResult {
  player_id:     string;
  access_token:  string;
  refresh_token: string;
  expires_in:    number;
}

// ── Player Documents ──────────────────────────────────────────────────────────

export interface PlayerDocument<T = unknown> {
  key:        string;
  value:      T;
  version:    number;
  updated_at: string;
}

export interface DocumentWrite<T = unknown> {
  key:      string;
  value:    T;
  /** Supply the last known version to enable optimistic locking. */
  version?: number;
}

export interface DocumentPatchOperation<T = unknown> {
  op?:             "set" | "remove";
  path:            string[];
  value?:          T;
  create_missing?: boolean;
}

// ── Leaderboards ──────────────────────────────────────────────────────────────

export interface LeaderboardEntry {
  rank:      number;
  player_id: string;
  score:     number;
  metadata:  Record<string, unknown>;
}

export interface PlayerStanding {
  rank:      number;
  player_id: string;
  score:     number;
}

// ── Economy ───────────────────────────────────────────────────────────────────

export interface BalanceAdjustment {
  currency_id: string;
  amount:      number;
}

export interface InventoryAdjustment {
  item_id:  string;
  quantity: number;
}

export interface CurrencyBalance {
  currency_id:   string;
  currency_name: string;
  amount:        number;
}

export interface InventoryEntry {
  item_id:   string;
  item_name: string;
  quantity:  number;
  metadata:  Record<string, unknown>;
}

export interface PlayerEconomy {
  player_id: string;
  balances:  CurrencyBalance[];
  inventory: InventoryEntry[];
}

// ── Matchmaking ───────────────────────────────────────────────────────────────

export interface MatchmakingTicket {
  ticket_id: string;
  status:    string;
  player_id: string;
}

export interface MatchParticipant {
  player_id: string;
  team:      string;
}

export interface MatchInfo {
  id:             string;
  status:         string;
  game_mode:      string;
  region:         string;
  participants:   MatchParticipant[];
  server_id?:     string;
  server_address?: string;
}

export interface MatchmakingStatus {
  /** "waiting" | "matched" */
  status: string;
  match?: MatchInfo;
}

// ── Server Registry ────────────────────────────────────────────────────────────

export interface ServerRegistration {
  server_id:    string;
  name:         string;
  region:       string;
  map_name?:    string;
  game_mode?:   string;
  player_count?: number;
  max_players?:  number;
  address?:      string;
  port?:         number;
  version?:      string;
}

export interface ServerInfo {
  id:             string;
  server_id:      string;
  name:           string;
  region:         string;
  map_name:       string;
  game_mode:      string;
  player_count:   number;
  max_players:    number;
  address:        string;
  port:           number;
  version:        string;
  last_heartbeat: string;
  created_at:     string;
}

// ── Errors ────────────────────────────────────────────────────────────────────

export class CruxError extends Error {
  constructor(
    public readonly statusCode: number,
    message: string,
  ) {
    super(message);
    this.name = "CruxError";
  }
}
