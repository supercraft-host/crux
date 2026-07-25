/**
 * Weekly leaderboard, end-to-end.
 *
 * Run:
 *   npm install crux-sdk tsx
 *   CRUX_URL=https://crux.supercraft.host \
 *   CRUX_PROJECT=<PROJECT_ID> CRUX_ENV=<ENVIRONMENT_ID> CRUX_KEY=<API_KEY> \
 *   tsx examples/js/leaderboard.ts
 */
import { CruxClient } from "crux-sdk";

const url        = process.env.CRUX_URL     ?? "https://crux.supercraft.host";
const projectId  = process.env.CRUX_PROJECT ?? "<PROJECT_ID>";
const envId      = process.env.CRUX_ENV     ?? "<ENVIRONMENT_ID>";
const apiKey     = process.env.CRUX_KEY     ?? "<API_KEY>";
const leaderboard = "weekly";

async function main() {
  const gsb = CruxClient.forPlayer(url, projectId, envId, apiKey);

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
