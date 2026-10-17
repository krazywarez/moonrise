// Aurora alert rules. Pure functions; the Worker supplies data and sends.

/**
 * Geomagnetic latitude of the auroral oval's equatorward edge for a Kp value,
 * after NOAA SWPC's Kp-to-latitude chart (66.5° at Kp 0, about 2° lower per Kp).
 */
export function ovalEdge(kp: number): number {
  return 66.5 - 2.04 * kp;
}

/** Aurora low on the poleward horizon is often visible about this far beyond the oval's edge. */
export const HORIZON_MARGIN = 6;

/** Lowest geomagnetic latitude (absolute) where aurora may be seen on the horizon. */
export function visibleFrom(kp: number): number {
  return ovalEdge(kp) - HORIZON_MARGIN;
}

/** 5° bands, identified by their equatorward edge: 52 covers 52–57°N, -57 covers 52–57°S. */
export function bandFor(geomagneticLatitude: number): number {
  const b = Math.floor(Math.abs(geomagneticLatitude) / 5) * 5;
  return geomagneticLatitude < 0 ? -(b + 5) : b;
}

/** Bands whose poleward edge reaches the visible region for this Kp. */
export function alertBands(kp: number, bands: number[]): number[] {
  const limit = visibleFrom(kp);
  return bands.filter((b) => (b >= 0 ? b + 5 : -b) > limit);
}

/** Local hours treated as dark enough to bother someone: 20:00 to 04:00. */
export function isNight(now: Date, utcOffsetMinutes: number): boolean {
  const hour = (now.getUTCHours() + now.getUTCMinutes() / 60 + utcOffsetMinutes / 60 + 48) % 24;
  return hour >= 20 || hour < 4;
}

/** One alert per band per 12-hour UTC window. */
export function eventKey(now: Date): string {
  const d = now.toISOString().slice(0, 10);
  return `${d}${now.getUTCHours() < 12 ? "a" : "b"}`;
}

/** Kp to act on: the larger of now and the forecast for the next 3 hours. */
export function actionableKp(kpNow: number, forecast: { start: Date; kp: number }[], now: Date): number {
  const soon = forecast.filter((f) => f.start.getTime() <= now.getTime() + 3 * 3600_000 && f.start.getTime() + 3 * 3600_000 > now.getTime());
  return Math.max(kpNow, ...soon.map((f) => f.kp));
}
