# Self-hosting

The SDK ships no backend URL. You run the backend — everything it needs is in this
repository — and pass its ingest URL the same way as the key.

## Point the SDK at it

```dart
Guidester.init(
  apiKey: const String.fromEnvironment('GUIDESTER_KEY'),
  endpoint: const String.fromEnvironment('GUIDESTER_ENDPOINT'),
);
```

```bash
flutter run --dart-define=GUIDESTER_KEY=<key> \
            --dart-define=GUIDESTER_ENDPOINT=https://<your-project>.supabase.co/functions/v1/ingest
```

An empty endpoint disables the SDK, and it says so in the console:
`[guidester] disabled — GUIDESTER_ENDPOINT is empty`. It never falls back to anyone
else's backend.

## The quick way

`setup.sh` needs bash, `python3`, the Supabase CLI and, for the dashboard, Flutter. On
macOS and Linux that is everything; on Windows, run it from WSL or Git Bash.

Create an empty project at [supabase.com](https://supabase.com/dashboard), install the
Supabase CLI and run `supabase login`, then from a clone of the repository:

```bash
./supabase/setup.sh --project-ref <your project ref>
```

It links the project, applies every migration, deploys the ingest function, checks
that it answers, and builds the dashboard against your project. It prints your
endpoint and the remaining steps: serve the dashboard, set the Site URL in Supabase
Auth, sign up, create a project, and copy its key from Settings. It asks for your
database password rather than taking it on the command line, and it is safe to
re-run. `--dry-run` shows what it would do; `--skip-dashboard` sets up the backend only.

The script makes no account and no key. A key belongs to a project, a project to an
account, and the account is yours to create in the dashboard.

## What you need to run

If you would rather do it by hand, this is everything the script does, from the repository
root:

```bash
supabase link --project-ref <ref>
supabase db push --linked --include-all
supabase functions deploy ingest --no-verify-jwt --project-ref <ref>

# The dashboard, against your project. The anon (or publishable) key is public by
# design; never put the service_role key here.
echo '{"SUPABASE_URL": "https://<ref>.supabase.co", "SUPABASE_ANON_KEY": "<anon key>"}' \
  > apps/dashboard/dart_defines.local.json
cd apps/dashboard && ./tool/build_web.sh
```

`--no-verify-jwt` is required: the SDK authenticates with the project key in the request
body, not a Supabase session, and with JWT checks on every comment is refused.

What that sets up:


- The migrations in `supabase/migrations`, applied in order. **`0001_init.sql` is not
  idempotent** — a partially failed push cannot be re-run, so apply to a fresh project.
- The `ingest` edge function. It is the only write path in the system.
- A **private** storage bucket named `screenshots`. Public buckets defeat the signed-URL
  model entirely.

## What you inherit

Row-level security on every table, verified behaviourally rather than by inspection: the
anonymous role reads nothing and writes nothing, tenants are isolated in both directions,
and screenshots are scoped by project folder. `supabase/tests/run.sh` asserts all of it
against a real Postgres, with the default grants applied so that security policy is the
only thing standing.

Run it before you trust your copy:

```bash
./supabase/tests/run.sh
./supabase/tests/ingest_test.sh
```

Neither needs Docker, a network, or an account.

## What you are taking on

The key is extractable from any build by design, so anyone who has one of your test builds
can post to your project. Each key is rate limited (migration 0012): 30 comments, 120
launches and 60 tester verdicts a minute, answered with `429 rate_limited` and a
`Retry-After`. That bounds a flood rather than stopping one; revoke a key that leaks, in
Settings. The screenshots are your testers' data on your Supabase project, and so is the
storage bill.
