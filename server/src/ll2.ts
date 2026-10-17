// Launch Library 2 (The Space Devs). Anonymous limit: 15 requests per hour.
// Images are not used: their licences are often "Unknown".

export const UPCOMING_URL = "https://ll.thespacedevs.com/2.3.0/launches/upcoming/?limit=20&mode=normal";

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
}

interface Raw {
  id: string;
  name: string;
  net: string;
  window_start?: string | null;
  window_end?: string | null;
  last_updated: string;
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
  };
}

export async function fetchUpcoming(): Promise<Launch[]> {
  const res = await fetch(UPCOMING_URL, { headers: { "user-agent": "moonrise-server (sh.krz.moonrise)" } });
  if (!res.ok) throw new Error(`LL2 ${res.status}`);
  const body = (await res.json()) as { results: Raw[] };
  return body.results.map(normalize);
}
