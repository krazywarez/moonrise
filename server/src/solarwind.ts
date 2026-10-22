// Real-time solar wind at L1 (SWPC RTSW: SOLAR-1, ACE or IMAP, whichever is active). The 1-minute files are
// about 1.5 and 2.5 MB; they are reduced here to 5-minute means over 6 hours for the app and the aurora rule.
import { USER_AGENT } from "./agent.ts";

export const MAG_URL = "https://services.swpc.noaa.gov/json/rtsw/rtsw_mag_1m.json";
export const WIND_URL = "https://services.swpc.noaa.gov/json/rtsw/rtsw_wind_1m.json";

export interface SolarWindPoint {
  /** Start of the 5-minute bin, ISO 8601. */
  t: string;
  speed: number | null;
  density: number | null;
  bz: number | null;
  bt: number | null;
}

export interface SolarWind {
  observedAt: string;
  source: string;
  series: SolarWindPoint[];
}

interface MagRow { time_tag: string; active: boolean; source: string; bz_gsm: number | null; bt: number | null }
interface WindRow { time_tag: string; active: boolean; source: string; proton_speed: number | null; proton_density: number | null }

const BIN = 5 * 60_000;
const HOURS = 6;

const mean = (xs: number[]) => (xs.length ? Math.round((xs.reduce((a, b) => a + b, 0) / xs.length) * 10) / 10 : null);
const ok = (v: number | null | undefined): v is number => typeof v === "number" && Number.isFinite(v);

export function reduce(mag: MagRow[], wind: WindRow[], now: Date): SolarWind | null {
  const start = Math.floor((now.getTime() - HOURS * 3600_000) / BIN) * BIN;
  const bins = new Map<number, { speed: number[]; density: number[]; bz: number[]; bt: number[] }>();
  const bin = (tag: string) => {
    const t = Date.parse(tag + "Z");
    if (!(t >= start)) return undefined;
    const k = Math.floor(t / BIN) * BIN;
    if (!bins.has(k)) bins.set(k, { speed: [], density: [], bz: [], bt: [] });
    return bins.get(k)!;
  };
  let observed = 0, source = "";
  for (const r of mag) {
    if (!r.active) continue;
    const b = bin(r.time_tag);
    if (!b) continue;
    if (ok(r.bz_gsm)) b.bz.push(r.bz_gsm);
    if (ok(r.bt)) b.bt.push(r.bt);
    const t = Date.parse(r.time_tag + "Z");
    if (t > observed) { observed = t; source = r.source; }
  }
  for (const r of wind) {
    if (!r.active) continue;
    const b = bin(r.time_tag);
    if (!b) continue;
    if (ok(r.proton_speed)) b.speed.push(r.proton_speed);
    if (ok(r.proton_density)) b.density.push(r.proton_density);
  }
  if (!bins.size) return null;
  const series = [...bins.entries()].sort((a, b) => a[0] - b[0]).map(([k, b]) => ({
    t: new Date(k).toISOString(), speed: mean(b.speed), density: mean(b.density), bz: mean(b.bz), bt: mean(b.bt),
  }));
  return { observedAt: new Date(observed).toISOString(), source, series };
}

/**
 * Southward field strong enough, for long enough, that aurora usually follows within the hour (the wind takes
 * about 30 to 60 minutes from L1): the last 30 minutes average Bz ≤ −10 nT and speed ≥ 450 km/s.
 * A rule of thumb, not a forecast; it raises alerts to the bands that see aurora at Kp 6.
 */
export function stormLikely(w: SolarWind | null, now: Date): boolean {
  if (!w) return false;
  const recent = w.series.filter((p) => Date.parse(p.t) >= now.getTime() - 30 * 60_000);
  const bz = recent.map((p) => p.bz).filter(ok), speed = recent.map((p) => p.speed).filter(ok);
  if (bz.length < 4 || speed.length < 4) return false;
  return mean(bz)! <= -10 && mean(speed)! >= 450;
}

export const STORM_KP = 6;

export async function fetchSolarWind(now: Date): Promise<SolarWind | null> {
  const headers = { "user-agent": USER_AGENT };
  const m = await fetch(MAG_URL, { headers });
  if (!m.ok) throw new Error(`RTSW mag ${m.status}`);
  const mag = (await m.json()) as MagRow[];
  const w = await fetch(WIND_URL, { headers });
  if (!w.ok) throw new Error(`RTSW wind ${w.status}`);
  return reduce(mag, (await w.json()) as WindRow[], now);
}
