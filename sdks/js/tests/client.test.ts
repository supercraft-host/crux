/**
 * Tests for @supercraft/gsb. Mock fetch via Vitest, assert the request
 * shape and the error/retry behaviour.
 *
 * These tests guard the *contract* - header construction, retries on
 * 429/503, error mapping. They don't talk to a real Crux instance.
 */
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { GSBClient, GSBError } from "../src/index.js";

type FetchInput = Parameters<typeof fetch>[0];
type FetchInit = Parameters<typeof fetch>[1];

interface CapturedCall {
  url: string;
  method: string;
  headers: Record<string, string>;
  body: string | null;
}

function captureFetch(responses: Response[]): CapturedCall[] {
  const captured: CapturedCall[] = [];
  let i = 0;
  vi.stubGlobal("fetch", (input: FetchInput, init?: FetchInit) => {
    const headers: Record<string, string> = {};
    for (const [k, v] of Object.entries(init?.headers ?? {})) {
      headers[k] = v as string;
    }
    captured.push({
      url: typeof input === "string" ? input : (input as URL).toString(),
      method: init?.method ?? "GET",
      headers,
      body: (init?.body as string | null) ?? null,
    });
    const resp = responses[Math.min(i, responses.length - 1)];
    i++;
    return Promise.resolve(resp);
  });
  return captured;
}

function jsonResp(status: number, body: unknown, headers: Record<string, string> = {}): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json", ...headers },
  });
}

beforeEach(() => {
  vi.useFakeTimers();
});

afterEach(() => {
  vi.unstubAllGlobals();
  vi.useRealTimers();
});

describe("auth headers", () => {
  it("forPlayer uses ApiKey on login and Bearer on subsequent calls", async () => {
    const captured = captureFetch([
      jsonResp(200, { access_token: "JWT", refresh_token: "REF", player_id: "p1" }),
      jsonResp(200, {}),
    ]);
    const gsb = GSBClient.forPlayer("https://gsb.example", "proj_1", "env_1", "gsb_apikey_abc");
    await gsb.loginAnonymous();
    await gsb.submitScore("weekly", "p1", 100);

    expect(captured[0].headers.Authorization).toBe("ApiKey gsb_apikey_abc");
    expect(captured[1].headers.Authorization).toBe("Bearer JWT");
  });

  it("forServer uses ServerToken on every call", async () => {
    const captured = captureFetch([
      jsonResp(200, []),
    ]);
    const gsb = GSBClient.forServer("https://gsb.example", "proj_1", "env_1", "gsb_servertoken_xyz");
    await gsb.listServers({});
    expect(captured[0].headers.Authorization).toBe("ServerToken gsb_servertoken_xyz");
  });

  it("runtime calls without auth raise GSBError", async () => {
    captureFetch([jsonResp(200, {})]);
    const gsb = GSBClient.forPlayer("https://gsb.example", "proj_1", "env_1", "gsb_apikey_abc");
    // No login → no playerToken → runtimeAuth() throws.
    await expect(gsb.submitScore("weekly", "p1", 100)).rejects.toBeInstanceOf(GSBError);
  });

  it("server-only methods reject when run from a player client", async () => {
    captureFetch([jsonResp(200, {})]);
    const gsb = GSBClient.forPlayer("https://gsb.example", "proj_1", "env_1", "gsb_apikey_abc");
    await expect(
      gsb.registerServer({
        server_id: "s", name: "n", region: "r", map_name: "m", game_mode: "g",
        player_count: 0, max_players: 1, address: "127.0.0.1", port: 1, version: "1",
      })
    ).rejects.toBeInstanceOf(GSBError);
  });
});

describe("URL shape", () => {
  it("scopes player endpoints under /v1/projects/{proj}/environments/{env}", async () => {
    const captured = captureFetch([
      jsonResp(200, { access_token: "JWT", refresh_token: "R", player_id: "p1" }),
      jsonResp(200, { value: { gold: 0 }, version: 1 }),
    ]);
    const gsb = GSBClient.forPlayer("https://gsb.example", "proj_1", "env_1", "k");
    await gsb.loginAnonymous();
    await gsb.getPlayerDocument("p1", "inventory");

    expect(captured[1].url).toBe(
      "https://gsb.example/v1/projects/proj_1/environments/env_1/players/p1/documents/inventory"
    );
  });

  it("url-encodes player IDs and keys", async () => {
    const captured = captureFetch([
      jsonResp(200, { access_token: "JWT", refresh_token: "R", player_id: "p" }),
      jsonResp(200, { value: {}, version: 1 }),
    ]);
    const gsb = GSBClient.forPlayer("https://gsb.example", "proj_1", "env_1", "k");
    await gsb.loginAnonymous();
    await gsb.getPlayerDocument("u/has slash", "key with spaces");
    expect(captured[1].url).toContain("/players/u%2Fhas%20slash/documents/key%20with%20spaces");
  });
});

describe("retries", () => {
  it("retries on 503 then succeeds", async () => {
    const captured = captureFetch([
      jsonResp(503, { error: "transient" }),
      jsonResp(200, []),
    ]);
    const gsb = GSBClient.forServer("https://gsb.example", "p", "e", "gsb_servertoken_x");
    const promise = gsb.listServers({});
    await vi.runAllTimersAsync();
    await promise;
    expect(captured).toHaveLength(2);
  });

  it("honours Retry-After on 429", async () => {
    const captured = captureFetch([
      jsonResp(429, { error: "rate limit" }, { "Retry-After": "2" }),
      jsonResp(200, []),
    ]);
    const gsb = GSBClient.forServer("https://gsb.example", "p", "e", "gsb_servertoken_x");
    const promise = gsb.listServers({});
    await vi.advanceTimersByTimeAsync(2000);
    await promise;
    expect(captured).toHaveLength(2);
  });

  it("does NOT retry on 4xx other than 429", async () => {
    const captured = captureFetch([jsonResp(400, { message: "bad request" })]);
    const gsb = GSBClient.forServer("https://gsb.example", "p", "e", "gsb_servertoken_x");
    await expect(gsb.listServers({})).rejects.toMatchObject({
      statusCode: 400,
    });
    expect(captured).toHaveLength(1);
  });
});

describe("error mapping", () => {
  it("parses JSON error bodies for the message field", async () => {
    captureFetch([jsonResp(409, { message: "version mismatch" })]);
    const gsb = GSBClient.forServer("https://gsb.example", "p", "e", "gsb_servertoken_x");
    try {
      await gsb.listServers({});
      throw new Error("should have thrown");
    } catch (e) {
      expect(e).toBeInstanceOf(GSBError);
      expect((e as GSBError).statusCode).toBe(409);
      expect((e as GSBError).message).toContain("version mismatch");
    }
  });

  it("falls back to raw text on non-JSON errors", async () => {
    captureFetch([new Response("Internal Server Error", { status: 500 })]);
    const gsb = GSBClient.forServer("https://gsb.example", "p", "e", "gsb_servertoken_x");
    try {
      await gsb.listServers({});
    } catch (e) {
      expect((e as GSBError).message).toContain("Internal Server Error");
    }
  });
});

describe("leaderboards", () => {
  it("submitScore POSTs to /leaderboards/{id}/scores with player_id + score", async () => {
    const captured = captureFetch([
      jsonResp(200, { access_token: "JWT", refresh_token: "R", player_id: "p1" }),
      jsonResp(200, {}),
    ]);
    const gsb = GSBClient.forPlayer("https://gsb.example", "p", "e", "k");
    await gsb.loginAnonymous();
    await gsb.submitScore("weekly", "p1", 1234, { run_id: "abc" });

    expect(captured[1].method).toBe("POST");
    expect(captured[1].url).toContain("/leaderboards/weekly/scores");
    expect(JSON.parse(captured[1].body!)).toEqual({
      player_id: "p1",
      score: 1234,
      metadata: { run_id: "abc" },
    });
  });

  it("getTop returns the parsed entries array", async () => {
    const entries = [
      { rank: 1, player_id: "alice", score: 9999 },
      { rank: 2, player_id: "bob",   score: 5000 },
    ];
    captureFetch([
      jsonResp(200, { access_token: "JWT", refresh_token: "R", player_id: "p" }),
      jsonResp(200, entries),
    ]);
    const gsb = GSBClient.forPlayer("https://gsb.example", "p", "e", "k");
    await gsb.loginAnonymous();
    const top = await gsb.getTop("weekly", 2);
    expect(top).toEqual(entries);
  });
});
