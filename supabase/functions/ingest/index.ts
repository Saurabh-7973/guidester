import { createClient } from "jsr:@supabase/supabase-js@2";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "content-type",
};

function json(o: unknown, status: number, extra: Record<string, string> = {}) {
  return new Response(JSON.stringify(o), {
    status,
    headers: { ...cors, "content-type": "application/json", ...extra },
  });
}
const str = (v: unknown) =>
  typeof v === "string" && v.length > 0 ? v.slice(0, 200) : null;
const num = (v: unknown) =>
  typeof v === "number" && Number.isFinite(v) ? v : null;
// §5.4. The client ships inside a tester's APK and can send anything, so the
// six values are enforced here as well as by the CHECK constraint in
// migration 0002 — an unrecognised type must not reach the insert and 500.
// Kept in sync by hand with 0002_issue_type.sql, the SDK enum and the
// dashboard enum.
const ISSUE_TYPES = [
  "looks_wrong",
  "doesnt_work",
  "confusing",
  "crash",
  "slow",
  "idea",
] as const;
// §5.4, same reasoning: the client ships inside a tester's APK. Kept in sync by
// hand with 0003_impact.sql and packages/guidester/lib/src/impact.dart.
//
// Absent is valid and means the default — an older SDK build predating the
// impact chips sends nothing, and its comments are 'annoying' like any
// untouched row. Present-but-unrecognised is a rejection.
const IMPACTS = ["blocked", "annoying", "cosmetic"] as const;

// One per platform view on screen. A real screen has one or two; twenty is
// already pathological and the cap exists to bound the row, not to be reached.
const MAX_BLANK_REGIONS = 20;

// The SDK sends at most three, oldest first, each already trimmed on the
// device. Enforced again here for the same reason as everything else: the
// client ships inside a tester's APK and can send whatever it likes.
const MAX_ERRORS = 3;
const MAX_EXCEPTION_CHARS = 600;
const MAX_STACK_CHARS = 4200;
const MAX_ERROR_FIELD_CHARS = 100;

// The offline queue's idempotency key, made once on the device per comment and
// resent with every retry. Same shape as migration 0011's check, plus a
// character set: it is compared, never displayed, and nothing that is not an
// id needs to be stored in it.
const CLIENT_ID = /^[A-Za-z0-9_-]{8,64}$/;

// The SDK's context is a fixed set of short scalars, well under 1 KB.
const MAX_CONTEXT_BYTES = 16_384;

// A finite 0..1 fraction, or null. Same contract as the tap coordinates: a
// value outside the frame cannot describe a region of it.
const frac01 = (v: unknown): number | null => {
  if (typeof v !== "number" || !Number.isFinite(v)) return null;
  return v >= 0 && v <= 1 ? v : null;
};
const DEFAULT_IMPACT = "annoying";
// Tap coordinates are normalised 0..1. Out-of-range values are stored happily
// by `real` and then push the dashboard pin outside the screenshot, so reject
// anything that cannot be a fraction of the captured frame.
const frac = (v: unknown) => {
  const n = num(v);
  return n === null || n < 0 || n > 1 ? null : n;
};

// --------------------------------------------------------------------------
// Keys, since 0006
// --------------------------------------------------------------------------
//
// The key a build holds is a row now, not a column on the project. Revoking is
// what rotation actually does — a revoked key must stop being accepted while
// the comments it already carried keep pointing at it.
// One factory, so the helpers below can name the client's type without
// restating its generics — createClient's defaults are not the type this call
// actually produces.
const adminClient = () =>
  createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  );
type Admin = ReturnType<typeof adminClient>;

type ProjectKeyRow = {
  id: string;
  project_id: string;
  revoked_at: string | null;
};

type KeyLookup = {
  keyId?: string;
  projectId?: string;
  error?: string;
  status?: number;
};

async function lookupKey(admin: Admin, apiKey: string): Promise<KeyLookup> {
  const { data, error } = await admin
    .from("project_keys")
    .select("id, project_id, revoked_at")
    .eq("key", apiKey)
    .maybeSingle();
  if (error) return { error: "lookup_failed", status: 500 };
  const row = data as ProjectKeyRow | null;
  if (!row) return { error: "invalid_key", status: 401 };
  // Distinct from invalid_key on purpose. "This build's key was turned off" is
  // a different sentence to a tester than "this build was never configured",
  // and it is the one that tells them to install a newer build.
  if (row.revoked_at) return { error: "key_revoked", status: 401 };
  return { keyId: row.id, projectId: row.project_id };
}

// What answered and when. This is the whole of the onboarding connection
// check: without it the screen has to ask the developer whether it worked.
//
// Never fatal. A comment that reached the table is not failed because the
// timestamp beside it did not move.
async function touchKey(
  admin: Admin,
  keyId: string,
  p: Record<string, unknown>,
): Promise<void> {
  try {
    await admin.from("project_keys").update({
      last_used_at: new Date().toISOString(),
      last_used_device: str(p.device_model),
      last_used_os: str(p.os_version),
    }).eq("id", keyId);
  } catch {
    // Bookkeeping only.
  }
}


// --------------------------------------------------------------------------
// Rate limits, since 0012
// --------------------------------------------------------------------------
//
// Per key, per minute. The key ships in every tester build and is assumed to
// leak; without these, anybody holding it could post comments and screenshots
// as fast as the network allows. Set for a whole team sharing one build: a
// tester writes a comment in tens of seconds, so thirty a minute is a dozen
// people at full speed, and the SDK's offline queue sends one at a time.
const RATE_WINDOW_SECONDS = 60;
const RATE_LIMITS = {
  comment: 30,
  ping: 120, // one per launch
  verdict: 60,
} as const;
type RateBucket = keyof typeof RATE_LIMITS;

// Counts this request against its key. True when it may go ahead.
//
// Fails open: a limiter that cannot be reached (a database before 0012, a bad
// minute) must not turn every tester's report into a refusal. It is there to
// stop abuse, and losing real reports to it would be the worse failure.
async function withinLimit(
  admin: Admin,
  keyId: string,
  bucket: RateBucket,
): Promise<boolean> {
  try {
    const { data, error } = await admin.rpc("ingest_allow", {
      p_key: keyId,
      p_bucket: bucket,
      p_limit: RATE_LIMITS[bucket],
      p_window_seconds: RATE_WINDOW_SECONDS,
    });
    if (error) return true;
    return data !== false;
  } catch {
    return true;
  }
}

// The 429. Retry-After is the rest of the window, so a client that honours it
// comes back exactly when it would be counted again.
function rateLimited() {
  const into = Math.floor(Date.now() / 1000) % RATE_WINDOW_SECONDS;
  return json({ error: "rate_limited" }, 429, {
    "Retry-After": String(RATE_WINDOW_SECONDS - into),
  });
}

// How many pending retests a launch can be told about.
//
// Bounded for the same reason every other list here is: this response leaves
// the system to a caller holding a key that is extractable from any APK. A
// tester with forty unverified fixes has a process problem the SDK cannot fix
// by scrolling.
const MAX_RETESTS = 20;

// What a tester is allowed to say about their own report.
const TESTER_VERDICTS = ["accepted", "rejected"] as const;

// The return leg. `dev_verdict = fixed` and the tester has not accepted it.
//
// Scoped to one tester_id inside one project, and read through the
// `pending_retests` view rather than `comments` so the column list is fixed in
// the schema instead of in this select — see migration 0008.
//
// tester_id is a random value generated on the device. Somebody who extracts
// the api_key still has to know one to read anything, and a wrong one returns
// an empty list rather than an error, so this is not an oracle either.
async function pendingRetests(
  admin: Admin,
  projectId: string,
  testerId: string | null,
): Promise<unknown[]> {
  if (!testerId) return [];
  try {
    const { data, error } = await admin
      .from("pending_retests")
      .select("id, excerpt, screen_name, fixed_in_build, created_at")
      .eq("project_id", projectId)
      .eq("tester_id", testerId)
      .order("created_at", { ascending: false })
      .limit(MAX_RETESTS);
    if (error) return [];
    return data ?? [];
  } catch {
    // A launch must never fail because the retest list could not be built.
    return [];
  }
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405);

  const admin = adminClient();

  let p: Record<string, unknown>;
  try {
    p = await req.json();
  } catch {
    return json({ error: "bad_json" }, 400);
  }

  // DEVIATION FROM §4.3 — see DECISIONS.md D39.
  // §4.3 used String(p.api_key ?? "") and String(p.body ?? ""), which coerce
  // rather than validate: a number, object or array becomes "12345",
  // "[object Object]" or "1,2" and is stored as a real comment. Require actual
  // strings instead.
  const apiKey = typeof p.api_key === "string" ? p.api_key : "";

  // A launch, not a comment. `Guidester.init` sends one of these so onboarding
  // can state that the SDK reached the backend instead of asking the developer
  // whether it did — self-reported success is the weakest check in that flow,
  // and people click Yes to get past it.
  //
  // It writes nothing but the key's own last-used columns: no comment row, no
  // upload, no screenshot. Handled here, before every field check below, because
  // a ping carries none of the fields those checks are about.
  if (p.ping === true) {
    if (!apiKey) return json({ error: "missing_fields" }, 400);
    const pk = await lookupKey(admin, apiKey);
    if (pk.error) return json({ error: pk.error }, pk.status!);
    if (!(await withinLimit(admin, pk.keyId!, "ping"))) return rateLimited();
    await touchKey(admin, pk.keyId!, p);
    // The return leg rides the request that already exists. A launch is
    // exactly when a tester can act on "this is fixed, please re-check", and
    // adding a second endpoint for it would mean a second attack surface
    // reachable from every shipped APK to answer a question this call is
    // already authenticated for.
    const retests = await pendingRetests(admin, pk.projectId!, str(p.tester_id));
    return json({ ok: true, ping: true, retests }, 200);
  }

  // A tester answering the ask. The only write in the system that is not a new
  // comment, and the only one a tester can make about an existing row.
  //
  // Ownership is checked twice over: the row must belong to the key's project
  // AND carry the tester_id that is claiming it. Without the second test, one
  // extracted key would let anybody close every report in a project.
  if (typeof p.verdict === "string") {
    if (!apiKey) return json({ error: "missing_fields" }, 400);
    if (!(TESTER_VERDICTS as readonly string[]).includes(p.verdict)) {
      return json({ error: "invalid_verdict" }, 400);
    }
    const commentId = str(p.comment_id);
    const testerId = str(p.tester_id);
    if (!commentId || !testerId) return json({ error: "missing_fields" }, 400);

    const vk = await lookupKey(admin, apiKey);
    if (vk.error) return json({ error: vk.error }, vk.status!);
    if (!(await withinLimit(admin, vk.keyId!, "verdict"))) return rateLimited();

    const { data: row, error: rErr } = await admin
      .from("comments")
      .select("id, dev_verdict, tester_verdict, app_version")
      .eq("id", commentId)
      .eq("project_id", vk.projectId!)
      .eq("tester_id", testerId)
      .maybeSingle();
    if (rErr) return json({ error: "lookup_failed" }, 500);
    // Not found and not yours are the same answer on purpose: distinguishing
    // them would confirm that a comment id exists in someone else's project.
    if (!row) return json({ error: "not_found" }, 404);

    const before = (row as Record<string, unknown>).tester_verdict as string;
    const { error: uErr } = await admin
      .from("comments")
      .update({ tester_verdict: p.verdict })
      .eq("id", commentId);
    if (uErr) return json({ error: "update_failed" }, 500);

    // The history is the point. A verdict with no event is the spreadsheet
    // problem again: a cell that changed with nothing saying when or why.
    try {
      await admin.from("comment_events").insert([{
        comment_id: commentId,
        actor: str(p.tester_name) ?? "a tester",
        kind: p.verdict === "rejected" ? "reopened" : "verdict_changed",
        field: "tester_verdict",
        from_value: before,
        to_value: p.verdict,
        body: str(p.note),
        build: str(p.app_version),
      }]);
    } catch {
      // The verdict moved. Losing its event must not fail the request.
    }

    await touchKey(admin, vk.keyId!, p);
    return json({ ok: true, verdict: p.verdict }, 200);
  }

  const rawBody = typeof p.body === "string" ? p.body : "";
  const body = rawBody.trim();
  if (!apiKey || !body) return json({ error: "missing_fields" }, 400);
  if (body.length > 2000) return json({ error: "body_too_long" }, 400);
  // Postgres text cannot store U+0000. Unchecked it reaches the insert and
  // fails there as a 500, losing the comment with no actionable error.
  if (body.includes("\u0000")) return json({ error: "invalid_body" }, 400);

  // Absent or null is valid — the column is nullable and older SDK builds
  // never send one. Present-but-unrecognised is a rejection, not a silent drop:
  // a client sending a type we do not store should hear about it.
  let issueType: string | null = null;
  if (p.issue_type !== undefined && p.issue_type !== null) {
    if (
      typeof p.issue_type !== "string" ||
      !(ISSUE_TYPES as readonly string[]).includes(p.issue_type)
    ) {
      return json({ error: "invalid_issue_type" }, 400);
    }
    issueType = p.issue_type;
  }

  // Which backend the build points at. Free text: teams name their own
  // environments, and a CHECK here would reject "preprod" for no gain. Capped
  // and trimmed like every other string field.
  const environment = str(p.environment);

  // Regions of the screen the platform composited, which the screenshot could
  // not record. Caller-controlled, so it is normalised to exactly five known
  // fields rather than stored as sent: capping the array length alone bounds
  // the count and not the size, and twenty elements carrying a megabyte string
  // each is the same unbounded write with extra steps.
  //
  // Validated here, with the other field checks — before the project lookup and
  // before the screenshot upload — so a malformed payload is rejected before any
  // work is done on its behalf.
  const blankRegions: Array<Record<string, unknown>> = [];
  if (p.blank_regions !== undefined && p.blank_regions !== null) {
    if (!Array.isArray(p.blank_regions)) {
      return json({ error: "invalid_blank_regions" }, 400);
    }
    if (p.blank_regions.length > MAX_BLANK_REGIONS) {
      return json({ error: "too_many_blank_regions" }, 400);
    }
    for (const raw of p.blank_regions) {
      if (!raw || typeof raw !== "object" || Array.isArray(raw)) {
        return json({ error: "invalid_blank_regions" }, 400);
      }
      const r = raw as Record<string, unknown>;
      const rect = ["x", "y", "w", "h"].map((k) => frac01(r[k]));
      if (rect.some((v) => v === null)) {
        return json({ error: "invalid_blank_regions" }, 400);
      }
      blankRegions.push({
        // A render-object type name. Anything longer is not one.
        kind: typeof r.kind === "string" ? r.kind.slice(0, 64) : "unknown",
        x: rect[0],
        y: rect[1],
        w: rect[2],
        h: rect[3],
      });
    }
  }

  // What the app threw before the comment was written. Same treatment as the
  // blank regions: normalised to exactly the fields we store rather than kept
  // as sent, and checked here, before the project lookup and the upload.
  //
  // A stack is the one field where a generous bound is the point — truncate it
  // to a tweet and it stops naming the host's own file, which is the only line
  // a developer actually opens.
  const errors: Array<Record<string, unknown>> = [];
  if (p.errors !== undefined && p.errors !== null) {
    if (!Array.isArray(p.errors)) return json({ error: "invalid_errors" }, 400);
    if (p.errors.length > MAX_ERRORS) {
      return json({ error: "too_many_errors" }, 400);
    }
    for (const raw of p.errors) {
      if (!raw || typeof raw !== "object" || Array.isArray(raw)) {
        return json({ error: "invalid_errors" }, 400);
      }
      const e = raw as Record<string, unknown>;
      // An error with no exception text describes nothing and is a client bug,
      // not a report. A missing stack is fine: a platform channel that dies
      // has no Dart frames to give.
      if (typeof e.exception !== "string" || e.exception.length === 0) {
        return json({ error: "invalid_errors" }, 400);
      }
      errors.push({
        at: typeof e.at === "string"
          ? e.at.slice(0, MAX_ERROR_FIELD_CHARS)
          : null,
        exception: e.exception.slice(0, MAX_EXCEPTION_CHARS),
        stack: typeof e.stack === "string" ? e.stack.slice(0, MAX_STACK_CHARS) : "",
        library: typeof e.library === "string"
          ? e.library.slice(0, MAX_ERROR_FIELD_CHARS)
          : null,
        screen: typeof e.screen === "string"
          ? e.screen.slice(0, MAX_ERROR_FIELD_CHARS)
          : null,
      });
    }
  }

  // The context blob is caller-controlled too, and has been stored verbatim
  // since day one. The SDK's own payload is well under a kilobyte; a cap this
  // generous only ever rejects something that is not our client.
  if (p.context !== undefined && p.context !== null) {
    if (typeof p.context !== "object" || Array.isArray(p.context)) {
      return json({ error: "invalid_context" }, 400);
    }
    if (JSON.stringify(p.context).length > MAX_CONTEXT_BYTES) {
      return json({ error: "context_too_large" }, 413);
    }
  }

  let impact: string = DEFAULT_IMPACT;
  if (p.impact !== undefined && p.impact !== null) {
    if (
      typeof p.impact !== "string" ||
      !(IMPACTS as readonly string[]).includes(p.impact)
    ) {
      return json({ error: "invalid_impact" }, 400);
    }
    impact = p.impact;
  }

  // Absent is valid: every SDK build before the offline queue sends none.
  let clientId: string | null = null;
  if (p.client_id !== undefined && p.client_id !== null) {
    if (typeof p.client_id !== "string" || !CLIENT_ID.test(p.client_id)) {
      return json({ error: "invalid_client_id" }, 400);
    }
    clientId = p.client_id;
  }

  const key = await lookupKey(admin, apiKey);
  if (key.error) return json({ error: key.error }, key.status!);
  // Before the duplicate check and the upload: the screenshot is the
  // expensive part of a comment, and the part a flood would be made of.
  if (!(await withinLimit(admin, key.keyId!, "comment"))) return rateLimited();
  const project = { id: key.projectId! };

  // A retry of a comment that already arrived. The first attempt's response
  // was lost (a timeout, a tunnel), not its insert, so the device is told it
  // succeeded and stops sending. Checked before the upload so a retry costs no
  // second screenshot in the bucket.
  if (clientId) {
    const { data: seen, error: dErr } = await admin
      .from("comments")
      .select("id")
      .eq("project_id", project.id)
      .eq("client_id", clientId)
      .maybeSingle();
    if (dErr) return json({ error: "lookup_failed" }, 500);
    if (seen) return json({ ok: true, duplicate: true }, 200);
  }

  let screenshotPath: string | null = null;
  const b64 = p.screenshot_b64;
  if (typeof b64 === "string" && b64.length > 0) {
    if (b64.length > 4_000_000) return json({ error: "screenshot_too_large" }, 413);
    // atob() throws on malformed base64. Uncaught, that surfaces as a bare
    // "Internal Server Error" 500 and the comment is lost — a truncated upload
    // on a flaky mobile network is enough to trigger it.
    let bytes: Uint8Array;
    try {
      bytes = Uint8Array.from(atob(b64), (c) => c.charCodeAt(0));
    } catch {
      return json({ error: "bad_screenshot" }, 400);
    }
    const path = `${project.id}/${crypto.randomUUID()}.png`;
    const { error: sErr } = await admin.storage
      .from("screenshots")
      .upload(path, bytes, { contentType: "image/png", upsert: false });
    if (sErr) return json({ error: "upload_failed" }, 500);
    screenshotPath = path;
  }

  const ctx: Record<string, unknown> = (p.context && typeof p.context === "object")
    ? { ...p.context as Record<string, unknown> }
    : {};
  if (blankRegions.length > 0) ctx.blank_regions = blankRegions;

  const { error: cErr } = await admin.from("comments").insert({
    project_id: project.id,
    body,
    screen_name: str(p.screen_name) ?? "UNKNOWN",
    tap_x: frac(p.tap_x),
    tap_y: frac(p.tap_y),
    screenshot_path: screenshotPath,
    tester_name: str(p.tester_name),
    tester_id: str(p.tester_id),
    device_model: str(p.device_model),
    os_version: str(p.os_version),
    app_version: str(p.app_version),
    issue_type: issueType,
    impact,
    environment,
    // G5: app_version has been captured since day one and never used. The
    // bugsheet's whole release workflow turns on which build a bug was found
    // in, so it becomes a column rather than a jsonb key nobody queries.
    found_in_build: str(p.app_version),
    project_key_id: key.keyId,
    client_id: clientId,
    errors,
    context: ctx,
  });
  if (cErr) {
    // Two attempts of the same comment raced past the check above, and the
    // other one won. Its row is the comment; this upload is an orphan.
    if (clientId && cErr.code === "23505") {
      if (screenshotPath) {
        try {
          await admin.storage.from("screenshots").remove([screenshotPath]);
        } catch {
          // An orphaned file costs storage, not a comment.
        }
      }
      return json({ ok: true, duplicate: true }, 200);
    }
    return json({ error: "insert_failed" }, 500);
  }

  // Last, and unawaited for its result: a comment that arrived is not lost
  // because the bookkeeping column behind it failed to update.
  await touchKey(admin, key.keyId!, p);

  return json({ ok: true }, 200);
});
