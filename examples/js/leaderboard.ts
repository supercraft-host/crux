/**
 * Weekly leaderboard, end-to-end.
 *
 * Run:
 *   npm install @supercraft/gsb tsx
 *   GSB_URL=https://crux.supercraft.host \
 *   GSB_PROJECT=proj_xxx GSB_ENV=env_xxx GSB_KEY=gsb_apikey_xxx \
 *   tsx examples/js/leaderboard.ts
 */
import { GSBClient } from "@supercraft/gsb";

const url        = process.env.GSB_URL     ?? "https://crux.supercraft.host";
const projectId  = process.env.GSB_PROJECT ?? "proj_xxx";
const envId      = process.env.GSB_ENV     ?? "env_xxx";
const apiKey     = process.env.GSB_KEY     ?? "gsb_apikey_xxx";
const leaderboard = "weekly";

async function main() {
  const gsb = GSBClient.forPlayer(url, projectId, envId, apiKey);

  const auth = await gsb.loginAnonymous();
  console.log(`logged in as ${auth.player_id}`);

  const score = Math.floor(Math.random() * 10_000);
  await gsb.submitScore(leaderboard, auth.player_id, score);
  console.log(`submitted ${score}`);

  const top = await gsb.getTop(leaderboard, 10);
  console.log(`top ${top.length}:`);
  top.forEach(e => console.log(`  #${e.rank.toString().padStart(2)} ${e.player_id} → ${e.score}`));

  const me = await gsb.getPlayerStanding(leaderboard, auth.player_id);
  console.log(`my standing: ${me?.rank ?? "unranked"}`);

  const neighbours = await gsb.getAroundPlayer(leaderboard, auth.player_id, 2);
  console.log(`neighbours (±2):`);
  neighbours.forEach(e => console.log(`  #${e.rank} ${e.player_id} → ${e.score}`));
}

main().catch(e => {
  console.error(e);
  process.exit(1);
});
