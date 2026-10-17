// NOAA SWPC feeds. Responses carry cache-control max-age=60; poll no faster.

export const KP_NOW_URL = "https://services.swpc.noaa.gov/json/planetary_k_index_1m.json";
export const KP_FORECAST_URL = "https://services.swpc.noaa.gov/products/noaa-planetary-k-index-forecast.json";

export interface SpaceWeather {
  kpNow: number;
  observedAt: string;
  forecast: { start: Date; kp: number; predicted: boolean }[];
}

/** SWPC time tags are UTC without a zone designator. */
function parse(tag: string): Date {
  return new Date(tag.endsWith("Z") ? tag : `${tag}Z`);
}

export function decode(nowJson: unknown, forecastJson: unknown): SpaceWeather {
  const minutes = nowJson as { time_tag: string; estimated_kp: number }[];
  const last = minutes.at(-1);
  if (!last) throw new Error("empty Kp feed");
  const rows = forecastJson as { time_tag: string; kp: number; observed: string }[];
  return {
    kpNow: last.estimated_kp,
    observedAt: parse(last.time_tag).toISOString(),
    forecast: rows.map((r) => ({ start: parse(r.time_tag), kp: r.kp, predicted: r.observed !== "observed" })),
  };
}

export async function fetchSpaceWeather(): Promise<SpaceWeather> {
  const [a, b] = await Promise.all([fetch(KP_NOW_URL), fetch(KP_FORECAST_URL)]);
  if (!a.ok || !b.ok) throw new Error(`SWPC ${a.status}/${b.status}`);
  return decode(await a.json(), await b.json());
}

/** Highest predicted Kp in the next 24 hours. */
export function next24h(w: SpaceWeather, now: Date): number | null {
  const end = now.getTime() + 24 * 3600_000;
  const kps = w.forecast.filter((f) => f.predicted && f.start.getTime() + 3 * 3600_000 > now.getTime() && f.start.getTime() <= end).map((f) => f.kp);
  return kps.length ? Math.max(...kps) : null;
}
