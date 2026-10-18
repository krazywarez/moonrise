// CelesTrak GP data. CelesTrak updates every 2 hours and blocks IPs that fetch more
// often or keep requesting after errors, so poll every 2 hours and stop on any non-200.

/** ISS, Tiangong (CSS Tianhe) and Hubble. */
export const SATELLITES = [25544, 48274, 20580];

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

/** Fetches each satellite in turn; throws on the first non-200 so nothing more is requested. */
export async function fetchElements(): Promise<OMM[]> {
  const out: OMM[] = [];
  for (const id of SATELLITES) {
    const res = await fetch(`https://celestrak.org/NORAD/elements/gp.php?CATNR=${id}&FORMAT=JSON`, {
      headers: { "user-agent": "moonrise-server (sh.krz.moonrise)" },
    });
    if (res.status !== 200) throw new Error(`CelesTrak ${res.status} for ${id}`);
    out.push(...pick((await res.json()) as Record<string, unknown>[]));
  }
  return out;
}
