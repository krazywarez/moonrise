// Live coverage of a crewed or lunar mission: its trajectory from JPL Horizons, cached while the event runs.
// To cover a new mission, add it to EVENTS (Horizons ID, window, phases) and deploy.

export interface LiveEvent {
  id: string;
  title: string;
  /** Horizons COMMAND, e.g. "-1023" for Artemis I. */
  horizonsId: string;
  /** ISO 8601 UTC. */
  launch: string;
  end: string;
  phases: { at: string; label: string }[];
}

export const EVENTS: LiveEvent[] = [
  {
    // Past mission, kept for testing with /v1/live?at=2022-11-21T12:00:00Z.
    id: "artemis-1", title: "Artemis I", horizonsId: "-1023",
    launch: "2022-11-16T06:47:44Z", end: "2022-12-11T17:40:00Z",
    phases: [
      { at: "2022-11-16T06:47:44Z", label: "Launch" },
      { at: "2022-11-21T12:44:00Z", label: "Outbound lunar flyby" },
      { at: "2022-11-25T21:52:00Z", label: "Distant retrograde orbit" },
      { at: "2022-12-01T21:53:00Z", label: "Leaves lunar orbit" },
      { at: "2022-12-05T16:43:00Z", label: "Return lunar flyby" },
      { at: "2022-12-11T17:40:00Z", label: "Splashdown" },
    ],
  },
];

export const STEP_MINUTES = 30;

/** The event whose window contains `at`, if any. */
export function activeEvent(at: Date, events = EVENTS): LiveEvent | undefined {
  return events.find((e) => Date.parse(e.launch) <= at.getTime() && at.getTime() <= Date.parse(e.end));
}

/** Horizons rows from a CSV vector table (VEC_TABLE 1): [unix seconds, x, y, z] km. */
export function parseVectors(result: string): number[][] {
  const start = result.indexOf("$$SOE"), stop = result.indexOf("$$EOE");
  if (start < 0 || stop < 0) return [];
  return result.slice(start + 5, stop).trim().split("\n").map((line) => {
    const f = line.split(",").map((s) => s.trim());
    const jd = Number(f[0]);
    return [Math.round((jd - 2440587.5) * 86400), Number(f[2]), Number(f[3]), Number(f[4])];
  }).filter((r) => r.every(Number.isFinite));
}

/**
 * The limit in Horizons' "No ephemeris for target ... prior to A.D. 2022-NOV-16 08:46:00.3328 TDB"
 * (or "after A.D. ...") reply.
 */
export function ephemerisLimit(result: string, which: "prior to" | "after"): Date | undefined {
  const m = result.match(new RegExp(`${which} A\\.D\\. (\\d{4})-([A-Z]{3})-(\\d{2}) (\\d{2}):(\\d{2})`));
  if (!m) return undefined;
  const month = ["JAN", "FEB", "MAR", "APR", "MAY", "JUN", "JUL", "AUG", "SEP", "OCT", "NOV", "DEC"].indexOf(m[2]);
  return new Date(Date.UTC(Number(m[1]), month, Number(m[3]), Number(m[4]), Number(m[5])));
}

/**
 * Geocentric positions on J2000 ecliptic axes from launch to `until`, every STEP_MINUTES. Horizons data
 * for a spacecraft usually starts after launch and may end before the event does; the request is
 * narrowed to what Horizons says it has.
 */
export async function fetchTrajectory(e: LiveEvent, until: Date, from = new Date(e.launch), to = new Date(e.end)): Promise<number[][]> {
  const start = from;
  const stop = new Date(Math.min(until.getTime(), to.getTime()));
  if (stop <= start) return [];
  const fmt = (d: Date) => d.toISOString().slice(0, 16).replace("T", " ");
  const params = new URLSearchParams({
    format: "json", COMMAND: `'${e.horizonsId}'`, EPHEM_TYPE: "'VECTORS'", CENTER: "'500@399'", REF_PLANE: "'ECLIPTIC'",
    START_TIME: `'${fmt(start)}'`, STOP_TIME: `'${fmt(stop)}'`, STEP_SIZE: `'${STEP_MINUTES}m'`,
    VEC_TABLE: "'1'", OUT_UNITS: "'KM-S'", CSV_FORMAT: "'YES'", OBJ_DATA: "'NO'", MAKE_EPHEM: "'YES'",
  });
  const res = await fetch(`https://ssd.jpl.nasa.gov/api/horizons.api?${params}`, { headers: { "user-agent": "moonrise-server (sh.krz.moonrise)" } });
  if (res.status !== 200) throw new Error(`Horizons ${res.status}`);
  const result = ((await res.json()) as { result: string }).result;
  const first = ephemerisLimit(result, "prior to");
  if (first && first > from) return fetchTrajectory(e, until, new Date(first.getTime() + 60_000), to);
  const last = ephemerisLimit(result, "after");
  if (last && last < stop) return fetchTrajectory(e, until, from, new Date(last.getTime() - 60_000));
  return parseVectors(result);
}
