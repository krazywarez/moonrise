// CelesTrak GP data. CelesTrak updates every 2 hours and blocks IPs that fetch more
// often or keep requesting after errors, so poll every 2 hours and stop on any non-200.
// A failed poll is tried once more 33 minutes later: at most 2 errors in 2 hours.

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

export type Row = Record<string, unknown>;

export function pick(rows: Row[]): OMM[] {
  return rows.map((r) => Object.fromEntries(KEYS.map((k) => [k, r[k]])) as unknown as OMM);
}

/** Objects grouped by launch, keyed by international designator ("2026-232"). */
export function byDesignator(rows: Row[]): Map<string, Row[]> {
  const groups = new Map<string, Row[]>();
  for (const r of rows) {
    const launch = String(r.OBJECT_ID).slice(0, 8);
    groups.set(launch, [...(groups.get(launch) ?? []), r]);
  }
  return groups;
}

const isStarlink = (r: Row) => String(r.OBJECT_NAME).startsWith("STARLINK");

/** The Starlink satellite with the median mean motion, named "Starlink train (<label>)". */
function train(rows: Row[], label: string): OMM | null {
  const sorted = rows.filter(isStarlink).sort((a, b) => Number(a.MEAN_MOTION) - Number(b.MEAN_MOTION));
  if (!sorted.length) return null;
  return { ...pick([sorted[Math.floor(sorted.length / 2)]])[0], OBJECT_NAME: `Starlink train (${label})` };
}

/** One element set per launch, keyed by label, whose Starlink satellites are still low enough to be seen as a train. */
export function starlinkTrains(groups: Map<string, Row[]>): OMM[] {
  const out: OMM[] = [];
  for (const [label, rows] of groups) {
    const t = train(rows, label);
    if (t && t.MEAN_MOTION > TRAIN_MEAN_MOTION) out.push(t);
  }
  return out;
}

// SupGP: pre-launch and post-deployment Starlink sets from SpaceX data. OBJECT_ID and
// NORAD_CAT_ID are placeholders (a pre-launch OBJECT_ID can be a designator already given to
// another launch), so SupGP sets are tied to launches by file name and epoch only.

/** "Starlink Group 15-15" → "starlink-g15-15"; null for other missions. */
export function supgpFile(mission: string | null): string | null {
  const m = mission?.match(/^Starlink Group (\d+)-(\d+)$/);
  return m ? `starlink-g${m[1]}-${m[2]}` : null;
}

/** An unknown FILE is answered with HTTP 200 and plain text; anything but complete element sets is no data. */
export function parseSupGP(text: string): Row[] {
  let rows: unknown;
  try {
    rows = JSON.parse(text);
  } catch {
    return [];
  }
  return Array.isArray(rows) ? rows.filter(complete) : [];
}

function complete(r: unknown): r is Row {
  if (typeof r !== "object" || r === null) return false;
  const o = r as Row;
  return typeof o.OBJECT_NAME === "string" && typeof o.OBJECT_ID === "string" && typeof o.EPOCH === "string" && !Number.isNaN(epoch(o)) &&
    KEYS.every((k) => k === "OBJECT_NAME" || k === "EPOCH" || (typeof o[k] === "number" && Number.isFinite(o[k])));
}

const epoch = (r: Row) => Date.parse(`${r.EPOCH}Z`);

/**
 * Starlink deployment is one to two hours after liftoff (Group 15-15: 1 h 57 min): before launch, sets must be epoched
 * 0–3 h after NET, which rejects a file left over from an earlier time; after launch, any time after NET.
 */
export function fitsLaunch(rows: Row[], net: string, now: Date): Row[] {
  const t = Date.parse(net);
  return rows.filter((r) => epoch(r) >= t && (t < now.getTime() || epoch(r) <= t + 3 * 3600_000));
}

export interface LaunchRef {
  id: string;
  mission: string | null;
  provider: string;
  net: string;
  designator: string | null;
}

/** SpaceX Starlink launches from 3 days ago to 48 h ahead, nearest first, at most 4 (one SupGP request each). */
export function supgpLaunches(launches: LaunchRef[], now: Date): LaunchRef[] {
  const from = now.getTime() - 3 * 86400_000, to = now.getTime() + 48 * 3600_000;
  return launches
    .filter((l) => l.provider === "SpaceX" && supgpFile(l.mission) && Date.parse(l.net) >= from && Date.parse(l.net) <= to)
    .sort((a, b) => Math.abs(Date.parse(a.net) - now.getTime()) - Math.abs(Date.parse(b.net) - now.getTime()))
    .slice(0, 4);
}

const newest = (rows: Row[]) => Math.max(...rows.map(epoch));

/** A Starlink train, then rocket bodies and other objects (no debris), at most 8. */
function launchElements(rows: Row[], label: string): OMM[] {
  const others = rows
    .filter((r) => !isStarlink(r) && !String(r.OBJECT_NAME).includes(" DEB"))
    .sort((a, b) => Number(String(b.OBJECT_NAME).includes("R/B")) - Number(String(a.OBJECT_NAME).includes("R/B")) || String(a.OBJECT_ID).localeCompare(String(b.OBJECT_ID)));
  const t = train(rows, label);
  return [...(t ? [t] : []), ...pick(others)].slice(0, 8);
}

export interface LaunchElements {
  /** "gp": CelesTrak GP matched by designator; "supgp": SpaceX data via CelesTrak SupGP. */
  source: "gp" | "supgp";
  elements: OMM[];
}

/**
 * The satellite list (visual group plus trains, labelled with the mission name where known) and element sets
 * per launch. For each launch the GP objects with its designator or its SupGP sets are used, whichever has the
 * newer epoch. A SupGP train joins the satellite list only once its epoch (predicted deployment) has passed,
 * since clients propagate that list from now.
 */
export function compose(visual: Row[], recent: Row[], launches: LaunchRef[], supgp: Record<string, Row[]>, now: Date): { satellites: OMM[]; launches: Record<string, LaunchElements> } {
  const gp = byDesignator(recent);
  const groups = new Map(gp);
  const out: Record<string, LaunchElements> = {};
  for (const l of launches) {
    const g = l.designator ? gp.get(l.designator) : undefined;
    const s = supgp[l.id]?.length ? supgp[l.id] : undefined;
    const source = s && (!g || newest(s) > newest(g)) ? "supgp" : "gp";
    const rows = source === "supgp" ? s : g;
    if (!rows) continue;
    const label = l.mission?.startsWith("Starlink ") ? l.mission.slice(9) : (l.mission ?? l.designator ?? l.id);
    if (l.designator) groups.delete(l.designator);
    if (source === "gp" || newest(rows) <= now.getTime()) groups.set(label, rows);
    out[l.id] = { source, elements: launchElements(rows, label) };
  }
  return { satellites: [...pick(visual), ...starlinkTrains(groups)], launches: out };
}

/** The 5-minute tick 33 minutes after each 2-hourly poll, which runs at minute 7 of even UTC hours. */
export const retryTick = (now: Date) => now.getUTCHours() % 2 === 0 && now.getUTCMinutes() === 40;

/** Whether this tick's 2-hourly poll failed and nothing has succeeded since. A failed retry is not retried. */
export function retryDue(now: Date, lastOk: string | null, lastError: string | null): boolean {
  if (!retryTick(now) || !lastError) return false;
  const error = Date.parse(lastError);
  return error >= now.getTime() - 33 * 60_000 && error < now.getTime() && (!lastOk || Date.parse(lastOk) < error);
}

const HEADERS = { "user-agent": "moonrise-server (sh.krz.moonrise)" };
const TIMEOUT_MS = 10_000;

async function group(name: string): Promise<Row[]> {
  const res = await fetch(`https://celestrak.org/NORAD/elements/gp.php?GROUP=${name}&FORMAT=JSON`, { headers: HEADERS, signal: AbortSignal.timeout(TIMEOUT_MS) });
  if (res.status !== 200) throw new Error(`CelesTrak ${res.status} for ${name}`);
  return (await res.json()) as Row[];
}

/** The visual group (about 150 bright objects) and the last 30 days' launches; throws on the first non-200 so nothing more is requested. */
export async function fetchGroups(): Promise<{ visual: Row[]; recent: Row[] }> {
  const visual = await group("visual");
  const recent = await group("last-30-days");
  return { visual, recent };
}

/** One SupGP file; throws on a non-200 so the caller stops. */
export async function fetchSupGP(file: string): Promise<Row[]> {
  const res = await fetch(`https://celestrak.org/NORAD/elements/supplemental/sup-gp.php?FILE=${file}&FORMAT=JSON`, { headers: HEADERS, signal: AbortSignal.timeout(TIMEOUT_MS) });
  if (res.status !== 200) throw new Error(`CelesTrak SupGP ${res.status} for ${file}`);
  return parseSupGP(await res.text());
}
