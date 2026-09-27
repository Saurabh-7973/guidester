// A stand-in for the few PostgREST routes the ingest function calls, so the
// rate limit's wiring can be checked without a Supabase project. Not a
// database: every key is valid, and the limiter answers whatever /__mode says.
//
//   allow    ingest_allow returns true
//   deny     ingest_allow returns false
//   missing  ingest_allow is a 404, as on a database before 0012
let mode = "allow";
const calls: string[] = [];

const port = Number(Deno.env.get("STUB_PORT") ?? "54399");
Deno.serve({ port, onListen: () => console.log(`stub on ${port}`) }, async (req) => {
  const url = new URL(req.url);
  const path = url.pathname;
  if (path === "/__mode") {
    mode = await req.text();
    calls.length = 0;
    return new Response("ok");
  }
  if (path === "/__calls") return Response.json(calls);
  calls.push(`${req.method} ${path}`);

  if (path === "/rest/v1/project_keys" && req.method === "GET") {
    return Response.json({ id: "key-1", project_id: "proj-1", revoked_at: null });
  }
  if (path === "/rest/v1/rpc/ingest_allow") {
    const args = await req.json();
    calls.push(`bucket=${args.p_bucket} limit=${args.p_limit}`);
    if (mode === "missing") {
      return Response.json(
        { code: "PGRST202", message: "Could not find the function" },
        { status: 404 },
      );
    }
    return Response.json(mode === "allow");
  }
  if (path === "/rest/v1/pending_retests") return Response.json([]);
  if (path === "/rest/v1/comments" && req.method === "GET") {
    return new Response(null, { status: 406 }); // maybeSingle: no row
  }
  return new Response(null, { status: 204 });
});
