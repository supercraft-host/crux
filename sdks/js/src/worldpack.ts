// Reference reader for the Crux WorldPack format (`crux.worldpack.v1`).
// Dependency-free: zip parsing + raw-deflate inflate use the web-standard
// DecompressionStream (Node 18+ and modern browsers). See docs/worldpack-format.md.

export const WATER_INDEX = 255;
export const WORLDPACK_SCHEMA = "crux.worldpack.v1";

export interface BiomeLegend {
  index: number;
  name: string;
  color: [number, number, number];
}

export interface Poi {
  name: string;
  x: number; // normalized [0,1]
  y: number;
}

export class WorldPack {
  readonly seed: number;
  readonly width: number;
  readonly height: number;
  readonly seaLevel: number;
  /** Row-major elevation in [0,1], length width*height. */
  readonly heightMap: Float32Array;
  /** Row-major biome index; -1 means water/ocean. */
  readonly biome: Int16Array;
  readonly biomes: BiomeLegend[];
  readonly pois: Poi[];

  constructor(init: {
    seed: number;
    width: number;
    height: number;
    seaLevel: number;
    heightMap: Float32Array;
    biome: Int16Array;
    biomes: BiomeLegend[];
    pois: Poi[];
  }) {
    this.seed = init.seed;
    this.width = init.width;
    this.height = init.height;
    this.seaLevel = init.seaLevel;
    this.heightMap = init.heightMap;
    this.biome = init.biome;
    this.biomes = init.biomes;
    this.pois = init.pois;
  }

  private idx(x: number, y: number): number {
    return y * this.width + x;
  }

  heightAt(x: number, y: number): number {
    return this.heightMap[this.idx(x, y)];
  }

  isWater(x: number, y: number): boolean {
    return this.biome[this.idx(x, y)] < 0;
  }

  /** Biome legend entry at (x,y), or null for water. */
  biomeAt(x: number, y: number): BiomeLegend | null {
    const b = this.biome[this.idx(x, y)];
    return b < 0 ? null : this.biomes[b] ?? null;
  }
}

/** Parse a worldpack from already-extracted archive entries. */
export function parseWorldPack(entries: Record<string, Uint8Array>): WorldPack {
  const manifestBytes = entries["worldpack.json"];
  if (!manifestBytes) throw new Error("worldpack: missing worldpack.json");
  const manifest = JSON.parse(new TextDecoder().decode(manifestBytes));
  if (manifest.schema !== WORLDPACK_SCHEMA) {
    throw new Error(`worldpack: unsupported schema ${manifest.schema}`);
  }

  const width: number = manifest.size.width;
  const height: number = manifest.size.height;
  const cells = width * height;

  const heightRaw = entries["layers/height.u16"];
  if (!heightRaw || heightRaw.byteLength !== cells * 2) {
    throw new Error("worldpack: bad layers/height.u16");
  }
  const biomeRaw = entries["layers/biomes.u8"];
  if (!biomeRaw || biomeRaw.byteLength !== cells) {
    throw new Error("worldpack: bad layers/biomes.u8");
  }

  const heightMap = new Float32Array(cells);
  const view = new DataView(heightRaw.buffer, heightRaw.byteOffset, heightRaw.byteLength);
  for (let i = 0; i < cells; i++) {
    heightMap[i] = view.getUint16(i * 2, true) / 65535;
  }
  const biome = new Int16Array(cells);
  for (let i = 0; i < cells; i++) {
    biome[i] = biomeRaw[i] === WATER_INDEX ? -1 : biomeRaw[i];
  }

  const pois: Poi[] = [];
  const poiBytes = entries["objects/pois.geojson"];
  if (poiBytes) {
    const fc = JSON.parse(new TextDecoder().decode(poiBytes));
    for (const f of fc.features ?? []) {
      const c = f.geometry?.coordinates;
      if (Array.isArray(c) && c.length === 2) {
        pois.push({ name: f.properties?.name ?? "", x: c[0], y: c[1] });
      }
    }
  }

  return new WorldPack({
    seed: manifest.seed,
    width,
    height,
    seaLevel: manifest.sea_level,
    heightMap,
    biome,
    biomes: manifest.biomes ?? [],
    pois,
  });
}

/** Read a worldpack directly from ZIP bytes. */
export async function readWorldPack(data: Uint8Array | ArrayBuffer): Promise<WorldPack> {
  const bytes = data instanceof Uint8Array ? data : new Uint8Array(data);
  return parseWorldPack(await unzip(bytes));
}

// ----------------------------------------------------- minimal zip reader ----

/** Unzip a ZIP archive (stored + deflate) into name -> bytes. */
export async function unzip(bytes: Uint8Array): Promise<Record<string, Uint8Array>> {
  const view = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);
  const eocd = findEOCD(view, bytes.length);
  if (eocd < 0) throw new Error("worldpack: not a zip (no EOCD)");

  const count = view.getUint16(eocd + 10, true);
  let p = view.getUint32(eocd + 16, true); // central directory offset

  const out: Record<string, Uint8Array> = {};
  for (let i = 0; i < count; i++) {
    if (view.getUint32(p, true) !== 0x02014b50) throw new Error("worldpack: bad central directory");
    const method = view.getUint16(p + 10, true);
    const compSize = view.getUint32(p + 20, true);
    const nameLen = view.getUint16(p + 28, true);
    const extraLen = view.getUint16(p + 30, true);
    const commentLen = view.getUint16(p + 32, true);
    const localOff = view.getUint32(p + 42, true);
    const name = new TextDecoder().decode(bytes.subarray(p + 46, p + 46 + nameLen));

    // Local header: data starts after its (possibly different) name/extra fields.
    const lNameLen = view.getUint16(localOff + 26, true);
    const lExtraLen = view.getUint16(localOff + 28, true);
    const dataStart = localOff + 30 + lNameLen + lExtraLen;
    const comp = bytes.subarray(dataStart, dataStart + compSize);

    out[name] = method === 0 ? comp.slice() : await inflateRaw(comp);
    p += 46 + nameLen + extraLen + commentLen;
  }
  return out;
}

function findEOCD(view: DataView, len: number): number {
  // EOCD is 22 bytes + up to 64KB comment; scan backwards for the signature.
  const min = Math.max(0, len - 22 - 0xffff);
  for (let i = len - 22; i >= min; i--) {
    if (view.getUint32(i, true) === 0x06054b50) return i;
  }
  return -1;
}

async function inflateRaw(comp: Uint8Array): Promise<Uint8Array> {
  const ds = new DecompressionStream("deflate-raw");
  const writer = ds.writable.getWriter();
  // Copy into a fresh ArrayBuffer-backed view so the chunk types as BufferSource
  // regardless of the source buffer's origin (Node Buffer, subarray, etc.).
  void writer.write(new Uint8Array(comp));
  void writer.close();
  const buf = await new Response(ds.readable).arrayBuffer();
  return new Uint8Array(buf);
}
