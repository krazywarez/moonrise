// Spaceflight News API (The Space Devs). Free, no key. Used only for the daily news digest push.

export interface Article {
  id: number;
  title: string;
  news_site: string;
  published_at: string;
}

export const DIGEST_HOUR = 9;

/**
 * UTC offsets in minutes whose local time is in the digest hour, as two half-open ranges within ±14 hours
 * (either may be empty). The whole hour, so devices one run did not reach get the digest on a later run.
 */
export function dueOffsets(now: Date): [[number, number], [number, number]] {
  const start = DIGEST_HOUR * 60 - now.getUTCHours() * 60 - now.getUTCMinutes();
  const clip = (lo: number): [number, number] => [Math.max(lo, -840), Math.min(lo + 60, 841)];
  return [clip(start), clip(start + 1440)];
}

/** The device's local date, so each device gets one digest per local day. */
export function localDate(now: Date, utcOffsetMinutes: number): string {
  return new Date(now.getTime() + utcOffsetMinutes * 60_000).toISOString().slice(0, 10);
}

/** Up to three of the newest headlines from the last 24 hours, one per site, without APOD. */
export function pickHeadlines(articles: Article[], now: Date): Article[] {
  const since = now.getTime() - 86_400_000;
  const sites = new Set<string>();
  const out: Article[] = [];
  for (const a of [...articles].sort((x, y) => y.published_at.localeCompare(x.published_at))) {
    if (Date.parse(a.published_at) < since || a.title.startsWith("APOD:") || sites.has(a.news_site)) continue;
    sites.add(a.news_site);
    out.push(a);
    if (out.length === 3) break;
  }
  return out;
}

export function digestPayload(headlines: Article[]) {
  return {
    aps: {
      alert: { title: "Space news", body: headlines.map((a) => `${a.title} (${a.news_site})`).join("\n") },
      sound: "default",
    },
    tab: "news",
  };
}

export async function fetchLatest(): Promise<Article[]> {
  const res = await fetch("https://api.spaceflightnewsapi.net/v4/articles/?limit=50", {
    headers: { "user-agent": "moonrise-server (sh.krz.moonrise)" },
  });
  if (res.status !== 200) throw new Error(`SNAPI ${res.status}`);
  return ((await res.json()) as { results: Article[] }).results;
}
