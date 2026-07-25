// Smoke test for the WorldPack reader. Reads a .worldpack produced by the Go
// genbuilder and verifies the parsed layers. Run:
//   npx tsx smoke/worldpack.ts /tmp/sdk.worldpack
import { readFileSync } from "node:fs";
import { readWorldPack, WATER_INDEX } from "../src/worldpack.js";

const path = process.argv[2] ?? "/tmp/sdk.worldpack";
const bytes = readFileSync(path);

const wp = await readWorldPack(bytes);

const assert = (cond: boolean, msg: string) => {
  if (!cond) {
    console.error("FAIL:", msg);
    process.exit(1);
  }
};

assert(wp.width > 0 && wp.height > 0, "size");
assert(wp.heightMap.length === wp.width * wp.height, "heightMap length");
assert(wp.biome.length === wp.width * wp.height, "biome length");

let min = 1,
  max = 0,
  water = 0,
  land = 0;
for (let i = 0; i < wp.heightMap.length; i++) {
  min = Math.min(min, wp.heightMap[i]);
  max = Math.max(max, wp.heightMap[i]);
  if (wp.biome[i] < 0) water++;
  else land++;
}
assert(max - min > 0.1, "height varies");
assert(water > 0 && land > 0, "has water and land");
assert(wp.biomes.length > 0, "biome legend present");

// Spot-check the helper API agrees with the raw arrays.
const sample = wp.biomeAt(0, 0);
assert(
  (wp.isWater(0, 0) && sample === null) || (!wp.isWater(0, 0) && sample !== null),
  "biomeAt/isWater agree at (0,0)"
);

console.log(
  `OK ${path}: ${wp.width}x${wp.height} seed=${wp.seed} height ${min.toFixed(3)}..${max.toFixed(
    3
  )} land=${land} water=${water} biomes=${wp.biomes.length} pois=${wp.pois.length} (WATER_INDEX=${WATER_INDEX})`
);
