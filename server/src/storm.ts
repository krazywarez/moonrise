// Geomagnetic storm Live Activity updates over APNs broadcast channels: one channel per storm and environment,
// so a follower never receives the end message of an earlier storm and the server never learns who follows.

const MINUTE = 60_000;
/** Seconds between the Unix epoch and 2001-01-01, the reference date of Swift's default Date coding. */
const REFERENCE_DATE = 978_307_200;
/** G1. */
export const STORM_START_KP = 5;
/** A storm ends after this long without Kp 5, a forecast of it within 3 hours, or a strongly southward wind. */
export const CALM_MS = 3 * 60 * MINUTE;
/** Updates without a change go out this often, to refresh the solar wind and the stale date. */
const REFRESH_MS = 30 * MINUTE;
const STALE_MS = 45 * MINUTE;

export interface StormState {
  /** Latest 1-minute estimated Kp. */
  kp: number;
  /** The higher of `kp` and the forecast for the 3-hour periods now and next. */
  expectedKp: number;
  /** Bz at or below −10 nT and speed at or above 450 km/s for 30 minutes. */
  early: boolean;
  bz: number | null;
  speed: number | null;
}

export interface StormPush {
  payload: { aps: Record<string, unknown> };
  priority: 5 | 10;
}

const unix = (ms: number) => Math.floor(ms / 1000);
const scale = (kp: number) => (kp >= STORM_START_KP ? Math.min(Math.floor(kp) - 4, 5) : 0);

export const stormActive = (s: StormState) => s.expectedKp >= STORM_START_KP || s.early;

/** Matches StormActivityAttributes.ContentState, decoded with Swift's default strategies; null values are left out. */
export function contentState(s: StormState, now: Date): Record<string, unknown> {
  const c: Record<string, unknown> = { kp: s.kp, expectedKp: s.expectedKp, early: s.early, updated: unix(now.getTime()) - REFERENCE_DATE };
  if (s.bz !== null) c.bz = s.bz;
  if (s.speed !== null) c.speed = s.speed;
  return c;
}

/**
 * The update for the current state, or null when the last one sent still stands: a change of G level (now or
 * expected) or of the early warning goes at once, anything else every 30 minutes. A rise goes at priority 10.
 */
export function stormUpdate(sent: { state: StormState; at: Date } | null, current: StormState, now: Date): StormPush | null {
  const rose = !sent || scale(current.kp) > scale(sent.state.kp) || scale(current.expectedKp) > scale(sent.state.expectedKp) || (current.early && !sent.state.early);
  const changed = rose || scale(current.kp) !== scale(sent!.state.kp) || scale(current.expectedKp) !== scale(sent!.state.expectedKp) || current.early !== sent!.state.early;
  if (!changed && now.getTime() - sent!.at.getTime() < REFRESH_MS) return null;
  return {
    payload: { aps: { timestamp: unix(now.getTime()), event: "update", "content-state": contentState(current, now), "stale-date": unix(now.getTime() + STALE_MS) } },
    priority: rose ? 10 : 5,
  };
}

/** The end of a storm, left on the Lock Screen for an hour. */
export function stormEnd(current: StormState, now: Date): StormPush {
  return {
    payload: { aps: { timestamp: unix(now.getTime()), event: "end", "content-state": contentState(current, now), "dismissal-date": unix(now.getTime() + 60 * MINUTE) } },
    priority: 5,
  };
}
