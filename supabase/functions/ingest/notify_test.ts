import { messageText, notify, payload, serviceOf } from "./notify.ts";

function eq(a: unknown, b: unknown, label: string) {
  if (JSON.stringify(a) !== JSON.stringify(b)) {
    throw new Error(
      `${label}: expected ${JSON.stringify(b)}, got ${JSON.stringify(a)}`,
    );
  }
}

Deno.test("only the three services' webhook hosts, over https", () => {
  eq(serviceOf("https://hooks.slack.com/services/T0/B0/xyz"), "slack", "slack");
  eq(serviceOf("https://discord.com/api/webhooks/1/abc"), "discord", "discord");
  eq(
    serviceOf("https://discordapp.com/api/webhooks/1/abc"),
    "discord",
    "discordapp",
  );
  eq(
    serviceOf("https://acme.webhook.office.com/webhookb2/x"),
    "teams",
    "teams",
  );

  for (
    const bad of [
      "http://hooks.slack.com/services/T0/B0/xyz", // not https
      "https://hooks.slack.com.evil.com/services/x", // lookalike host
      "https://evil.com/hooks.slack.com/services/x",
      "https://hooks.slack.com/other/x", // wrong path
      "https://user:pw@hooks.slack.com/services/x", // credentials
      "https://hooks.slack.com:8443/services/x", // port
      "https://169.254.169.254/latest/meta-data",
      "https://localhost/api/webhooks/1",
      "https://discord.com/other",
      "https://webhook.office.com/x", // no tenant
      "https://a.b.webhook.office.com/x", // nested
      "file:///etc/passwd",
      "not a url",
      "",
    ]
  ) {
    eq(serviceOf(bad), null, bad);
  }
});

Deno.test("the message names the impact, project, screen and who", () => {
  const t = messageText({
    project: "Shop",
    body: "Pay button\nhides",
    screen: "CHECKOUT",
    impact: "blocked",
    tester: "Priya",
    device: "Pixel 7",
    os: "Android 15",
    build: "1.0.1",
    errors: 2,
  });
  eq(
    t,
    "[BLOCKED] Shop / CHECKOUT: “Pay button hides” — Priya · Pixel 7, Android 15 · 1.0.1 · 2 errors attached",
    "text",
  );
});

Deno.test("a tester cannot ping the channel or inject markup", () => {
  const t = messageText({
    project: "Shop",
    body: "@channel <!everyone> <https://evil|click>",
    screen: "HOME",
    impact: "annoying",
    errors: 0,
  });
  if (t.includes("@channel") || t.includes("<") || t.includes(">")) {
    throw new Error(`unsafe: ${t}`);
  }
  eq(
    payload("discord", "x"),
    { content: "x", allowed_mentions: { parse: [] } },
    "discord",
  );
  eq(payload("slack", "x"), { text: "x" }, "slack");
});

Deno.test("a long comment is cut", () => {
  const t = messageText({
    project: "P",
    body: "x".repeat(1000),
    screen: "S",
    impact: "cosmetic",
    errors: 0,
  });
  if (t.length > 400) throw new Error(`too long: ${t.length}`);
});

Deno.test("never fetches a disallowed URL, never throws", async () => {
  let calls = 0;
  const fake = ((_u: string, _i: RequestInit) => {
    calls++;
    return Promise.resolve(new Response("ok"));
  }) as unknown as typeof fetch;
  const a = {
    project: "P",
    body: "b",
    screen: "S",
    impact: "blocked",
    errors: 0,
  };
  eq(await notify("https://169.254.169.254/x", a, fake), false, "blocked host");
  eq(calls, 0, "no fetch for a disallowed host");

  eq(
    await notify("https://hooks.slack.com/services/a", a, fake),
    true,
    "slack ok",
  );
  eq(calls, 1, "one fetch");

  const failing =
    (() => Promise.reject(new Error("down"))) as unknown as typeof fetch;
  eq(
    await notify("https://hooks.slack.com/services/a", a, failing),
    false,
    "down",
  );
});

Deno.test("redirects are refused, and it times out", async () => {
  let init: RequestInit | undefined;
  const spy = ((_u: string, i: RequestInit) => {
    init = i;
    return Promise.resolve(new Response("ok"));
  }) as unknown as typeof fetch;
  await notify("https://discord.com/api/webhooks/1/a", {
    project: "P",
    body: "b",
    screen: "S",
    impact: "blocked",
    errors: 0,
  }, spy);
  eq(init?.redirect, "error", "redirect");
  if (!(init?.signal instanceof AbortSignal)) throw new Error("no timeout");
});
