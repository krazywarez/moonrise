// Launch Library 2 (The Space Devs). Anonymous limit: 15 requests per hour.
// Images are not used: their licences are often "Unknown".

export const UPCOMING_URL = "https://ll.thespacedevs.com/2.3.0/launches/upcoming/?limit=20&mode=normal";
/** Recent launches, for the international designator, which is assigned only after liftoff. */
export const PREVIOUS_URL = "https://ll.thespacedevs.com/2.3.0/launches/previous/?limit=10&mode=normal";
/** One launch, polled on its own around liftoff. */
export const launchURL = (id: string) => `https://ll.thespacedevs.com/2.3.0/launches/${encodeURIComponent(id)}/?mode=normal`;

export interface Launch {
  id: string;
  name: string;
  net: string;
  windowStart: string | null;
  windowEnd: string | null;
  status: string;
  statusName: string;
  provider: string;
  rocket: string;
  mission: string | null;
  missionType: string | null;
  missionDescription: string | null;
  orbit: string | null;
  pad: string;
  location: string;
  padLatitude: number | null;
  padLongitude: number | null;
  lastUpdated: string;
  /** International designator, e.g. "2026-232"; null before launch. */
  designator: string | null;
}

interface Raw {
  id: string;
  name: string;
  net: string;
  window_start?: string | null;
  window_end?: string | null;
  last_updated: string;
  launch_designator?: string | null;
  status: { abbrev: string; name: string };
  launch_service_provider: { name: string };
  rocket: { configuration: { full_name?: string; name: string } };
  mission?: { name?: string; type?: string; description?: string; orbit?: { abbrev?: string } | null } | null;
  pad: { name: string; latitude?: string | number | null; longitude?: string | number | null; location: { name: string } };
}

const num = (v: string | number | null | undefined) => (v == null || v === "" ? null : Number(v));

export function normalize(r: Raw): Launch {
  return {
    id: r.id,
    name: r.name,
    net: r.net,
    windowStart: r.window_start ?? null,
    windowEnd: r.window_end ?? null,
    status: r.status.abbrev,
    statusName: r.status.name,
    provider: r.launch_service_provider.name,
    rocket: r.rocket.configuration.full_name ?? r.rocket.configuration.name,
    mission: r.mission?.name ?? null,
    missionType: r.mission?.type ?? null,
    missionDescription: r.mission?.description?.trim() ?? null,
    orbit: r.mission?.orbit?.abbrev ?? null,
    pad: r.pad.name,
    location: r.pad.location.name,
    padLatitude: num(r.pad.latitude),
    padLongitude: num(r.pad.longitude),
    lastUpdated: r.last_updated,
    designator: r.launch_designator ?? null,
  };
}

/** `apiKey` lifts the anonymous per-IP limit, which Cloudflare's shared egress IPs often exhaust (HTTP 429). */
async function get<T>(url: string, apiKey?: string): Promise<T> {
  const headers: Record<string, string> = { "user-agent": "moonrise-server (sh.krz.moonrise)" };
  if (apiKey) headers.authorization = `Token ${apiKey}`;
  const res = await fetch(url, { headers });
  if (!res.ok) throw new Error(`LL2 ${res.status}`);
  return (await res.json()) as T;
}

export async function fetchLaunches(url: string, apiKey?: string): Promise<Launch[]> {
  return (await get<{ results: Raw[] }>(url, apiKey)).results.map(normalize);
}

export async function fetchLaunch(id: string, apiKey?: string): Promise<Launch> {
  return normalize(await get<Raw>(launchURL(id), apiKey));
}
