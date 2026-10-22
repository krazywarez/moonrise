// Sun tab extras from SWPC, reduced for the app: the WSA-Enlil forecast at Earth (hourly), CCOR-2 coronagraph
// frames (one an hour for a day) and solar cycle 25 sunspot numbers (monthly).
import { USER_AGENT } from "./agent.ts";

const BASE = "https://services.swpc.noaa.gov";
const headers = { "user-agent": USER_AGENT };

export interface EnlilPoint { t: string; speed: number; density: number; cloud: boolean }
export interface Frame { t: string; url: string }
export interface CycleMonth { month: string; ssn: number | null; smoothed: number | null }
export interface CyclePrediction { month: string; ssn: number; high: number; low: number }
export interface Cycle { observed: CycleMonth[]; predicted: CyclePrediction[] }

async function get(path: string): Promise<Response> {
  const res = await fetch(BASE + path, { headers });
  if (!res.ok) throw new Error(`SWPC ${res.status} for ${path}`);
  return res;
}

interface EnlilRow { time_tag: string; earth_particles_per_cm3: number; v_r: number; cloud: number | null }

/** Hourly means from `from` on; an hour counts as in a CME cloud if any sample in it is. */
export function reduceEnlil(rows: EnlilRow[], from: Date): EnlilPoint[] {
  const hours = new Map<number, { v: number[]; n: number[]; cloud: boolean }>();
  for (const r of rows) {
    const t = Date.parse(r.time_tag + "Z");
    if (!(t >= from.getTime()) || !Number.isFinite(r.v_r)) continue;
    const k = Math.floor(t / 3600_000) * 3600_000;
    const h = hours.get(k) ?? { v: [], n: [], cloud: false };
    h.v.push(r.v_r);
    h.n.push(r.earth_particles_per_cm3);
    h.cloud ||= r.cloud != null && r.cloud > 0;
    hours.set(k, h);
  }
  const avg = (xs: number[]) => Math.round(xs.reduce((a, b) => a + b, 0) / xs.length * 10) / 10;
  return [...hours.entries()].sort((a, b) => a[0] - b[0])
    .map(([k, h]) => ({ t: new Date(k).toISOString(), speed: avg(h.v), density: avg(h.n), cloud: h.cloud }));
}

/** The last frame of each hour over the last day, from SWPC's directory listing. */
export function ccor2Frames(listing: string, now: Date): Frame[] {
  const byHour = new Map<string, Frame>();
  for (const m of listing.matchAll(/href="((\d{4})(\d{2})(\d{2})_(\d{2})(\d{2})_ccor2_1024by960\.jpg)"/g)) {
    const t = new Date(`${m[2]}-${m[3]}-${m[4]}T${m[5]}:${m[6]}:00Z`);
    if (now.getTime() - t.getTime() > 24 * 3600_000 || t > now) continue;
    byHour.set(t.toISOString().slice(0, 13), { t: t.toISOString(), url: `${BASE}/images/animations/ccor2/${m[1]}` });
  }
  return [...byHour.values()].sort((a, b) => a.t.localeCompare(b.t));
}

interface ObservedRow { "time-tag": string; ssn: number; smoothed_ssn: number }
interface PredictedRow { "time-tag": string; predicted_ssn: number; high_ssn: number; low_ssn: number }

/** Cycle 25 began in December 2019. SWPC marks missing smoothed values −1. */
export function reduceCycle(observed: ObservedRow[], predicted: PredictedRow[]): Cycle {
  return {
    observed: observed.filter((r) => r["time-tag"] >= "2019-12").map((r) => ({
      month: r["time-tag"], ssn: r.ssn >= 0 ? r.ssn : null, smoothed: r.smoothed_ssn >= 0 ? r.smoothed_ssn : null,
    })),
    predicted: predicted.map((r) => ({ month: r["time-tag"], ssn: r.predicted_ssn, high: r.high_ssn, low: r.low_ssn })),
  };
}

export async function fetchEnlil(now: Date): Promise<EnlilPoint[]> {
  return reduceEnlil(await (await get("/json/enlil_time_series.json")).json() as EnlilRow[], new Date(now.getTime() - 24 * 3600_000));
}

export async function fetchCcor2(now: Date): Promise<Frame[]> {
  return ccor2Frames(await (await get("/images/animations/ccor2/")).text(), now);
}

export async function fetchCycle(): Promise<Cycle> {
  const observed = await (await get("/json/solar-cycle/observed-solar-cycle-indices.json")).json() as ObservedRow[];
  const predicted = await (await get("/json/solar-cycle/predicted-solar-cycle.json")).json() as PredictedRow[];
  return reduceCycle(observed, predicted);
}
