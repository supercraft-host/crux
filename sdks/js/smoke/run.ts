#!/usr/bin/env tsx
// Smoke test the JS SDK against a live Crux backend.
//
// Reads credentials from env; see smoke/.env.example for the shape. Exits 0
// on success, non-zero on failure. Each step prints a one-line status so a CI
// log makes the failure obvious.
//
//   CRUX_BASE_URL, CRUX_PROJECT_ID, CRUX_ENV_ID, CRUX_API_KEY
//
// The smoke test creates a short-lived anonymous player, writes/reads/patches
// a document, then removes the doc. The player row stays (anonymous players
// are rarely deleted by design), so reruns are idempotent because the
// anonymous_id is randomized per invocation.

import { CruxClient, CruxError } from "../src/index.js";

function env(name: string, fallback?: string): string {
  const v = process.env[name] ?? fallback;
  if (!v) {
    console.error(`missing required env var: ${name}`);
    process.exit(2);
  }
  return v;
}

const BASE_URL   = env("CRUX_BASE_URL", "https://gsb.test.supercraft.host");
const PROJECT_ID = env("CRUX_PROJECT_ID");
const ENV_ID     = env("CRUX_ENV_ID");
const API_KEY    = env("CRUX_API_KEY");

const run = async () => {
  const gsb = CruxClient.forPlayer(BASE_URL, PROJECT_ID, ENV_ID, API_KEY);

  const anonId = `smoke-${Date.now()}-${Math.random().toString(36).slice(2, 8)}`;
  // Anonymous login is the only path that doesn't need a pre-existing user;
  // it also exercises API-key auth + JWT minting in one call.
  const auth = await (async () => {
    const res = await fetch(`${BASE_URL}/v1/auth/anonymous`, {
      method: "POST",
      headers: { "Content-Type": "application/json", Authorization: `ApiKey ${API_KEY}` },
      body: JSON.stringify({ anonymous_id: anonId, display_name: anonId }),
    });
    if (!res.ok) throw new Error(`anonymous login failed: ${res.status} ${await res.text()}`);
    return res.json() as Promise<{ access_token: string; player_id: string }>;
  })();
  // Hand the token to the SDK so the runtime calls below pick it up.
  (gsb as unknown as { playerToken: string; playerId: string }).playerToken = auth.access_token;
  (gsb as unknown as { playerToken: string; playerId: string }).playerId    = auth.player_id;
  console.log(`ok   login anonymous  player=${auth.player_id}`);

  const DOC = "smoke-profile";

  const initial = await gsb.setPlayerDocument(auth.player_id, DOC, { xp: 10, level: 1 });
  if (initial.version !== 1) throw new Error(`expected v1, got v${initial.version}`);
  console.log(`ok   setPlayerDocument v${initial.version}`);

  const read = await gsb.getPlayerDocument<{ xp: number; level: number }>(auth.player_id, DOC);
  if (read.value.xp !== 10 || read.value.level !== 1) throw new Error(`read mismatch: ${JSON.stringify(read.value)}`);
  console.log(`ok   getPlayerDocument`);

  const patched = await gsb.patchPlayerDocument(auth.player_id, DOC, [
    { op: "set", path: ["xp"], value: 25 },
    { op: "remove", path: ["level"] },
  ], read.version);
  if (patched.version !== 2) throw new Error(`expected v2 after patch, got v${patched.version}`);
  console.log(`ok   patchPlayerDocument v${patched.version}`);

  // Optimistic-lock conflict: sending the stale version must be rejected as 409.
  let conflicted = false;
  try {
    await gsb.setPlayerDocument(auth.player_id, DOC, { xp: 999 }, initial.version);
  } catch (e) {
    if (e instanceof CruxError && e.statusCode === 409) conflicted = true;
    else throw e;
  }
  if (!conflicted) throw new Error("expected 409 on stale-version write");
  console.log(`ok   stale-version write → 409`);

  const batch = await gsb.batchGetPlayerDocuments(auth.player_id, [DOC]);
  if (batch.length !== 1 || batch[0].key !== DOC) throw new Error(`batch read mismatch: ${JSON.stringify(batch)}`);
  console.log(`ok   batchGetPlayerDocuments`);

  await gsb.deletePlayerDocument(auth.player_id, DOC);
  console.log(`ok   deletePlayerDocument`);

  console.log("SMOKE OK");
};

run().catch((e) => {
  console.error("SMOKE FAIL:", e instanceof Error ? e.message : e);
  process.exit(1);
});
