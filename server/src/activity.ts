// Launch Live Activity updates over APNs broadcast channels: one channel per launch and environment,
// so the server never learns who follows a launch.

const MINUTE = 60_000;
/** A launch is polled on its own from T−60 to T+15. */
const FOCUS_BEFORE = 60 * MINUTE;
const FOCUS_AFTER = 15 * MINUTE;
/** Launch Library 2 status abbreviations that end the activity. */
export const OUTCOMES = ["Success", "Failure", "Partial Failure"];
/** Seconds between the Unix epoch and 2001-01-01, the reference date of Swift's default Date coding. */
const REFERENCE_DATE = 978_307_200;

export interface ActivityState {
  net: string;
  status: string;
}

export interface ActivityPush {
  payload: { aps: Record<string, unknown> };
  priority: 5 | 10;
  end: boolean;
}

const unix = (ms: number) => Math.floor(ms / 1000);

/** Earliest NET a launch can have and still be in focus or need a channel. */
export const sinceNet = (now: Date) => new Date(now.getTime() - FOCUS_AFTER).toISOString();

export function inFocus(l: ActivityState, now: Date): boolean {
  const t = Date.parse(l.net);
  return !OUTCOMES.includes(l.status) && t - FOCUS_BEFORE <= now.getTime() && now.getTime() <= t + FOCUS_AFTER;
}

/** Minutes between polls of the launch in focus: 5 anonymously (15 requests/hour), 2 with a Launch Library 2 key. */
export const focusEvery = (keyed: boolean) => (keyed ? 2 : 5);

/**
 * Whether the 5-minute or the 2-minute cron polls the launch in focus on this tick. With a key the 2-minute cron
 * takes the even minutes the 5-minute cron does not run on.
 */
export function focusPollDue(cron: 2 | 5, now: Date, keyed: boolean): boolean {
  const m = now.getUTCMinutes();
  return cron === 5 ? m % focusEvery(keyed) === 0 : keyed && m % 5 !== 0;
}

/** One launch per poll; launches in focus at the same time take turns. */
export function focusPick(ids: string[], now: Date, every = 5): string {
  return ids[Math.floor(now.getTime() / (every * MINUTE)) % ids.length];
}

/** Channels are handed out a day ahead, so a follow at any time before launch can subscribe. */
export function needsChannel(l: ActivityState, now: Date): boolean {
  const t = Date.parse(l.net);
  return !OUTCOMES.includes(l.status) && now.getTime() - FOCUS_AFTER <= t && t <= now.getTime() + 24 * 60 * MINUTE;
}

/**
 * The broadcast for a change from the last state sent to the current one, or null if nothing changed.
 * `content-state` matches LaunchActivityAttributes.ContentState, decoded by ActivityKit with Swift's default strategies.
 * The stale date matches the one the app sets when it starts the activity.
 */
export function activityPush(sent: ActivityState, current: ActivityState, now: Date): ActivityPush | null {
  if (sent.net === current.net && sent.status === current.status) return null;
  const end = OUTCOMES.includes(current.status);
  const net = Date.parse(current.net);
  const aps: Record<string, unknown> = {
    timestamp: unix(now.getTime()),
    event: end ? "end" : "update",
    "content-state": { net: unix(net) - REFERENCE_DATE, status: current.status },
  };
  if (end) aps["dismissal-date"] = unix(now.getTime() + 15 * MINUTE);
  else aps["stale-date"] = unix(net + 60 * MINUTE);
  return { payload: { aps }, priority: sent.status === current.status ? 5 : 10, end };
}
