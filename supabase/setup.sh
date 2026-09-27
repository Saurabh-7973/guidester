#!/usr/bin/env bash
# Sets up your own Guidester backend and dashboard in one command.
#
#   ./supabase/setup.sh --project-ref <ref>
#
# Before you run it:
#   1. Create an empty project at https://supabase.com/dashboard (note its ref,
#      the 20 letters in its URL, and the database password you chose).
#   2. Install the Supabase CLI and run `supabase login`.
#   3. Install Flutter, unless you pass --skip-dashboard.
#
# What it does, in order: links the project, applies every migration, deploys
# the ingest function, checks the function answers, and builds the dashboard
# against your project. It prints the endpoint for your app and what to do next.
#
# It does not create an account or a key. Those are yours: you sign up in the
# dashboard it builds, create a project there, and the key is shown in Settings.
# A key belongs to a project and a project to an account, so nothing here can
# make one on your behalf without holding your password.
#
# Safe to re-run: migrations already applied are skipped, and the function is
# redeployed in place.
#
# Options:
#   --project-ref <ref>    required
#   --db-password <pw>     or set SUPABASE_DB_PASSWORD; asked for if neither
#   --skip-dashboard       backend only
#   --dry-run              print the commands instead of running them
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REF=""
PASSWORD="${SUPABASE_DB_PASSWORD:-}"
DASHBOARD=1
DRY=0

die() { echo "setup: $*" >&2; exit 1; }
step() { printf '\n==> %s\n' "$*"; }
run() {
  if [ "$DRY" -eq 1 ]; then echo "    [dry-run] $*"; else "$@"; fi
}

while [ $# -gt 0 ]; do
  case "$1" in
    --project-ref) REF="${2:-}"; shift 2 ;;
    --db-password) PASSWORD="${2:-}"; shift 2 ;;
    --skip-dashboard) DASHBOARD=0; shift ;;
    --dry-run) DRY=1; shift ;;
    -h|--help) sed -n '2,29p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) die "unknown option $1 (try --help)" ;;
  esac
done

[ -n "$REF" ] || die "--project-ref is required. It is the 20 letters in your project's dashboard URL."
[[ "$REF" =~ ^[a-z]{20}$ ]] || die "'$REF' does not look like a project ref (20 lowercase letters)."

step "Checking tools"
command -v supabase >/dev/null || die "the Supabase CLI is not installed: https://supabase.com/docs/guides/cli"
if [ "$DRY" -eq 0 ]; then
  supabase projects list >/dev/null 2>&1 || die "the Supabase CLI is not logged in. Run: supabase login"
fi
if [ "$DASHBOARD" -eq 1 ]; then
  command -v flutter >/dev/null || die "Flutter is not installed. Install it, or pass --skip-dashboard."
fi
echo "    ok"

if [ -z "$PASSWORD" ] && [ "$DRY" -eq 0 ]; then
  read -r -s -p "Database password for $REF: " PASSWORD; echo
  [ -n "$PASSWORD" ] || die "a database password is needed to apply the migrations."
fi
# Handed to the CLI through its environment, never as an argument: arguments
# are visible to every user of this machine in the process list.
export SUPABASE_DB_PASSWORD="$PASSWORD"

cd "$ROOT"

step "Linking $REF"
run supabase link --project-ref "$REF"

step "Applying migrations ($(ls supabase/migrations/*.sql | wc -l | tr -d ' ') files)"
# 0001 is not idempotent on its own, but push records what it applied, so a
# re-run only sends what is missing.
# --yes: the CLI otherwise stops to ask "push these migrations?". Found on the
# first real run (27 Sep); a one-command setup must not wait on a keypress.
run supabase db push --linked --include-all --yes

step "Deploying the ingest function"
# --no-verify-jwt: the SDK authenticates with the project key in the body, not
# a Supabase session. With JWT checks on, every comment would be refused.
run supabase functions deploy ingest --no-verify-jwt --project-ref "$REF"

ENDPOINT="https://$REF.supabase.co/functions/v1/ingest"

step "Checking the function answers"
if [ "$DRY" -eq 1 ]; then
  echo "    [dry-run] POST {} to $ENDPOINT, expecting 400 missing_fields"
else
  # An empty body is refused before any database work, so this writes nothing.
  answer="$(curl -s -m 20 -X POST -H 'content-type: application/json' -d '{}' "$ENDPOINT" || true)"
  case "$answer" in
    *missing_fields*) echo "    ok: $ENDPOINT" ;;
    *) die "the function did not answer as expected. Got: ${answer:-nothing}. Wait a minute and re-run." ;;
  esac
fi

DASH_DIR="$ROOT/apps/dashboard"
if [ "$DASHBOARD" -eq 1 ]; then
  step "Building the dashboard against your project"
  if [ "$DRY" -eq 1 ]; then
    echo "    [dry-run] read the anon key, write apps/dashboard/dart_defines.local.json, build web"
  else
    keys="$(supabase projects api-keys --project-ref "$REF" -o json)"
    ANON="$(printf '%s' "$keys" | python3 -c '
import json, sys
keys = json.load(sys.stdin)
# The legacy anon key where the project still has one; otherwise the newer
# publishable key, which does the same job for a browser client. Never a
# secret or service_role key.
pick = [k for k in keys if k.get("name") == "anon"] or \
       [k for k in keys if k.get("type") == "publishable"]
print(pick[0].get("api_key", "") if pick else "")
')"
    [ -n "$ANON" ] || die "could not read a public (anon or publishable) key for $REF."
    defines="$DASH_DIR/dart_defines.local.json"
    if [ -f "$defines" ] && ! grep -q "$REF" "$defines"; then
      cp "$defines" "$defines.bak"
      echo "    kept the old settings as dart_defines.local.json.bak"
    fi
    # The anon key is public by design. The service_role key never goes here.
    printf '{"SUPABASE_URL": "https://%s.supabase.co", "SUPABASE_ANON_KEY": "%s"}\n' \
      "$REF" "$ANON" > "$defines"
    (cd "$DASH_DIR" && flutter pub get >/dev/null && ./tool/build_web.sh)
  fi
fi

if [ "$DRY" -eq 1 ]; then
  printf '\nDry run: nothing was changed. Without --dry-run, this is what you get:\n'
fi
cat <<EOF

Done. Your backend is live.

  Endpoint for your app:  $ENDPOINT
EOF
if [ "$DASHBOARD" -eq 1 ]; then
  cat <<EOF
  Dashboard:              $DASH_DIR/build/web

Next:
  1. Serve the dashboard. To try it on this machine:
       cd apps/dashboard/build/web && python3 -m http.server 8765
     To share it, upload build/web to any static host.
  2. In Supabase: Authentication > URL Configuration, set the Site URL to where
     the dashboard is served, so the sign-up confirmation link opens it.
  3. Open the dashboard, sign up, confirm the email, create a project.
     Its key is in Settings.
EOF
else
  echo
  echo "Next: build and serve apps/dashboard, sign up, create a project; its key is in Settings."
fi
cat <<EOF
  4. Run your app with both values:
       flutter run --dart-define=GUIDESTER_KEY=<key from Settings> \\
                   --dart-define=GUIDESTER_ENDPOINT=$ENDPOINT
EOF
