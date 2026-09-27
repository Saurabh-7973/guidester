# Security

## Reporting a vulnerability

Please **do not open a public issue** for a security problem. Use GitHub's private
reporting instead: **Security → Report a vulnerability** on this repository. You will get
a reply within a few days.

Helpful to include: what an attacker can do, the steps to reproduce it, and which part is
affected (the SDK in `packages/guidester`, the dashboard in `apps/dashboard`, or the
backend in `supabase/`).

## What is in scope

- The ingest edge function (`supabase/functions/ingest`), the only write path.
- Row-level security in `supabase/migrations`: anything that lets one project read or
  change another's comments or screenshots, or lets the anonymous role read anything.
- The SDK sending data it says it does not send, or sending when it should be off (no key,
  `enabled: false`, `--dart-define=GUIDESTER=false`).
- The setup script (`supabase/setup.sh`) leaking a secret: the database password, or the
  service-role key reaching the dashboard build.

## Known and by design

- **The project key is extractable from any test build.** It only lets someone post
  comments to that one project, each key is rate limited, and it can be revoked in
  Settings. See [PRIVACY.md](PRIVACY.md) and the self-hosting guide.
- **The Supabase anon key is in the dashboard build.** It is public by design; row-level
  security is what protects the data.

Guidester is self-hosted: every deployment is its owner's. Reports about a specific
deployment's configuration belong with that deployment's owner.
