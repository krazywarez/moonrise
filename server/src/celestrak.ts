// CelesTrak GP data. CelesTrak updates every 2 hours and blocks IPs that fetch more
// often or keep requesting after errors, so poll every 2 hours and stop on any non-200.

/** ISS, Tiangong (CSS Tianhe) and Hubble; all three are in the visual group. */
export const FEATURED = [25544, 48274, 20580];

/** Median mean motion above which a Starlink launch is still low enough to be seen as a train (about 400 km). */
const TRAIN_MEAN_MOTION = 15.45;

export interface OMM {
  OBJECT_NAME: string;
  NORAD_CAT_ID: number;
  EPOCH: string;
  MEAN_MOTION: number;
  ECCENTRICITY: number;
  INCLINATION: number;
  RA_OF_ASC_NODE: number;
  ARG_OF_PERICENTER: number;
  MEAN_ANOMALY: number;
  BSTAR: number;
}

const KEYS: (keyof OMM)[] = ["OBJECT_NAME", "NORAD_CAT_ID", "EPOCH", "MEAN_MOTION", "ECCENTRICITY", "INCLINATION", "RA_OF_ASC_NODE", "ARG_OF_PERICENTER", "MEAN_ANOMALY", "BSTAR"];

export function pick(rows: Record<string, unknown>[]): OMM[] {
  return rows.map((r) => Object.fromEntries(KEYS.map((k) => [k, r[k]])) as unknown as OMM);
}

/**
 * One element set per recent Starlink launch still low enough to be seen as a train,
 * the satellite with the median mean motion, named "Starlink train (2026-232)".
 */
export function starlinkTrains(rows: Record<string, unknown>[]): OMM[] {
  const groups = new Map<string, Record<string, unknown>[]>();
  for (const r of rows) {
    if (!String(r.OBJECT_NAME).startsWith("STARLINK")) continue;
    const launch = String(r.OBJECT_ID).slice(0, 8);
    groups.set(launch, [...(groups.get(launch) ?? []), r]);
  }
  const out: OMM[] = [];
  for (const [launch, sats] of groups) {
    const sorted = [...sats].sort((a, b) => Number(a.MEAN_MOTION) - Number(b.MEAN_MOTION));
    const median = sorted[Math.floor(sorted.length / 2)];
    if (Number(median.MEAN_MOTION) <= TRAIN_MEAN_MOTION) continue;
    out.push({ ...pick([median])[0], OBJECT_NAME: `Starlink train (${launch})` });
  }
  return out;
}

async function group(name: string): Promise<Record<string, unknown>[]> {
  const res = await fetch(`https://celestrak.org/NORAD/elements/gp.php?GROUP=${name}&FORMAT=JSON`, {
    headers: { "user-agent": "moonrise-server (sh.krz.moonrise)" },
  });
  if (res.status !== 200) throw new Error(`CelesTrak ${res.status} for ${name}`);
  return (await res.json()) as Record<string, unknown>[];
}

/** The visual group (about 150 bright objects) and Starlink trains; throws on the first non-200 so nothing more is requested. */
export async function fetchElements(): Promise<OMM[]> {
  const visual = pick(await group("visual"));
  const recent = await group("last-30-days");
  return [...visual, ...starlinkTrains(recent)];
}
