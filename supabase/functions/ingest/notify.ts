// Tells the team a comment arrived: one message to the project's Slack,
// Discord or Microsoft Teams channel.
//
// The webhook URL is the only outbound address ingest ever calls, and it is
// set by the project's owner or an admin (0014). It is still checked here,
// every time, against the three services' own webhook hosts over https, so a
// row that says anything else is never fetched: ingest runs with the service
// role inside Supabase's network, and it must not become a way to reach
// arbitrary addresses from there.

export type Service = "slack" | "discord" | "teams";

/** Which service a webhook URL belongs to, or null if it is not one of them. */
export function serviceOf(raw: string): Service | null {
  let u: URL;
  try {
    u = new URL(raw);
  } catch {
    return null;
  }
  if (u.protocol !== "https:" || u.username || u.password || u.port) {
    return null;
  }
  const host = u.hostname.toLowerCase();
  if (host === "hooks.slack.com" && u.pathname.startsWith("/services/")) {
    return "slack";
  }
  if (
    (host === "discord.com" || host === "discordapp.com") &&
    u.pathname.startsWith("/api/webhooks/")
  ) {
    return "discord";
  }
  if (
    host.endsWith(".webhook.office.com") &&
    /^[a-z0-9-]+\.webhook\.office\.com$/.test(host)
  ) {
    return "teams";
  }
  return null;
}

export type Arrived = {
  project: string;
  body: string;
  screen: string;
  impact: string;
  tester?: string | null;
  device?: string | null;
  os?: string | null;
  build?: string | null;
  errors: number;
};

// Chat services render their own markup; a tester's text must not ping
// @channel, open a link preview or break the formatting around it.
function plain(s: string, max: number): string {
  const one = s.replace(/\s+/g, " ").trim();
  const cut = one.length > max ? one.slice(0, max - 1) + "…" : one;
  return cut
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/@/g, "@​");
}

/** The one line a channel shows. */
export function messageText(a: Arrived): string {
  const who = [a.tester, [a.device, a.os].filter(Boolean).join(", "), a.build]
    .filter((x) => x && String(x).trim())
    .map((x) => plain(String(x), 60))
    .join(" · ");
  const err = a.errors > 0
    ? ` · ${a.errors} error${a.errors === 1 ? "" : "s"} attached`
    : "";
  return `[${a.impact.toUpperCase()}] ${plain(a.project, 60)} / ` +
    `${plain(a.screen, 60)}: “${plain(a.body, 280)}”` +
    (who ? ` — ${who}` : "") + err;
}

/** The request body each service expects. */
export function payload(
  service: Service,
  text: string,
): Record<string, unknown> {
  switch (service) {
    case "discord":
      // allowed_mentions empty: nothing in the message pings anyone.
      return { content: text, allowed_mentions: { parse: [] } };
    case "slack":
    case "teams":
      return { text };
  }
}

/**
 * Posts, and never throws. A comment that reached the table is not failed by
 * a channel that is down, slow or gone. `redirect: "error"`: a webhook host
 * that answers with a redirect is not followed somewhere else.
 */
export async function notify(
  url: string,
  a: Arrived,
  fetcher: typeof fetch = fetch,
  timeoutMs = 3000,
): Promise<boolean> {
  const service = serviceOf(url);
  if (!service) return false;
  try {
    const res = await fetcher(url, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify(payload(service, messageText(a))),
      redirect: "error",
      signal: AbortSignal.timeout(timeoutMs),
    });
    return res.ok;
  } catch {
    return false;
  }
}
