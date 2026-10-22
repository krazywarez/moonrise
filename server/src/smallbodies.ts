// Comets near perihelion and bright main-belt asteroids from JPL's Small-Body Database, once a day (JPL's SSD API fair
// use: one request at a time, results cached). Output matches SkyEngine.SmallBody's Codable form.
import { USER_AGENT } from "./agent.ts";

const API = "https://ssd-api.jpl.nasa.gov/sbdb_query.api";

export interface SmallBody {
  name: string; q: number; e: number; i: number; node: number; peri: number; tp: number;
  brightness: { comet: { m1: number; k1: number } } | { asteroid: { h: number; g: number } };
}

/** Rows of [full_name, e, q, i, om, w, tp, M1|H, K1|G]; rows without a brightness are left out. */
export function parse(rows: (string | null)[][], kind: "comet" | "asteroid"): SmallBody[] {
  const out: SmallBody[] = [];
  for (const r of rows) {
    const [name, e, q, i, om, w, tp, b1, b2] = r;
    const n = [e, q, i, om, w, tp, b1].map((v) => Number(v));
    if (n.some((v) => !Number.isFinite(v)) || r[7] == null) continue;
    const base = { name: String(name).trim(), e: n[0], q: n[1], i: n[2], node: n[3], peri: n[4], tp: n[5] };
    out.push(kind === "comet"
      ? { ...base, brightness: { comet: { m1: n[6], k1: b2 == null ? 10 : Number(b2) } } }
      : { ...base, brightness: { asteroid: { h: n[6], g: b2 == null ? 0.15 : Number(b2) } } });
  }
  return out;
}

async function query(params: Record<string, string>): Promise<(string | null)[][]> {
  const res = await fetch(`${API}?${new URLSearchParams(params)}`, { headers: { "user-agent": USER_AGENT } });
  if (!res.ok) throw new Error(`SBDB ${res.status}`);
  return ((await res.json()) as { data?: (string | null)[][] }).data ?? [];
}

/** Comets with perihelion inside 3 AU within 400 days of now; numbered asteroids with H < 7 inside 6 AU. */
export async function fetchSmallBodies(now: Date): Promise<SmallBody[]> {
  const jd = Math.round(now.getTime() / 86_400_000 + 2440587.5);
  const comets = await query({
    fields: "full_name,e,q,i,om,w,tp,M1,K1", "sb-kind": "c",
    "sb-cdata": JSON.stringify({ AND: ["q|LT|3", `tp|RG|${jd - 400}|${jd + 400}`] }),
  });
  const asteroids = await query({
    fields: "full_name,e,q,i,om,w,tp,H,G", "sb-kind": "a", "sb-ns": "n",
    "sb-cdata": JSON.stringify({ AND: ["H|LT|7", "a|LT|6"] }),
  });
  return [...parse(comets, "comet"), ...parse(asteroids, "asteroid")];
}
