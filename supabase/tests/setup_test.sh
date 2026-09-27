#!/usr/bin/env bash
# Runs supabase/setup.sh against stand-ins for supabase, flutter and curl, in a
# copy of the repository, so it can be checked without a Supabase project and
# without touching this checkout's dashboard settings.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$HERE/../.."
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT

mkdir -p "$T/repo/supabase" "$T/repo/apps/dashboard/tool" "$T/bin"
cp "$REPO/supabase/setup.sh" "$T/repo/supabase/"
cp -R "$REPO/supabase/migrations" "$T/repo/supabase/"
cp "$REPO/apps/dashboard/tool/build_web.sh" "$T/repo/apps/dashboard/tool/"
LOG="$T/calls.log"

# Each stand-in records its arguments and whether it was handed the password.
cat > "$T/bin/supabase" <<'SH'
#!/usr/bin/env bash
echo "supabase $* | pw=${SUPABASE_DB_PASSWORD:+set}" >> "$CALLS"
case "$1 $2" in
  "projects api-keys") echo '[{"name":"anon","api_key":"anon-key-123"},{"name":"service_role","api_key":"SECRET-service"}]' ;;
esac
exit 0
SH
cat > "$T/bin/flutter" <<'SH'
#!/usr/bin/env bash
echo "flutter $*" >> "$CALLS"
SH
cat > "$T/bin/curl" <<'SH'
#!/usr/bin/env bash
echo "curl $*" >> "$CALLS"
echo "${CURL_ANSWER-{\"error\":\"missing_fields\"}}"
SH
chmod +x "$T/bin/"*
export CALLS="$LOG"
export PATH="$T/bin:$PATH"

FAILED=0
pass() { printf '  PASS  %s\n' "$1"; }
fail() { printf '  FAIL  %s\n' "$1"; FAILED=1; }
expect() { if eval "$2"; then pass "$1"; else fail "$1"; fi; }

REF=abcdefghijklmnopqrst
SETUP="$T/repo/supabase/setup.sh"
DEFINES="$T/repo/apps/dashboard/dart_defines.local.json"

echo "==> full run"
: > "$LOG"
out="$(SUPABASE_DB_PASSWORD=hunter2-secret "$SETUP" --project-ref $REF 2>&1)"; code=$?
expect "exits 0"                               '[ $code -eq 0 ]'
order="$(grep -oE '^supabase (link|db push|functions deploy)' "$LOG" | tr '\n' ',')"
expect "link, then push, then deploy"          '[ "$order" = "supabase link,supabase db push,supabase functions deploy," ]'
expect "push includes every migration"         'grep -q "db push --linked --include-all" "$LOG"'
expect "push never waits on a prompt"          'grep -q "db push .*--yes" "$LOG"'
expect "deploy skips the JWT check"            'grep -q "functions deploy ingest --no-verify-jwt --project-ref $REF" "$LOG"'
expect "link and push get the password"        '[ "$(grep -cE "^supabase (link|db push).*pw=set" "$LOG")" = 2 ]'
expect "the password is never an argument"     '! grep -q hunter2-secret "$LOG"'
expect "the password is never printed"         '! grep -q hunter2-secret <<<"$out"'
expect "checks the function with an empty body" 'grep -q "curl .*-d {} https://$REF.supabase.co/functions/v1/ingest" "$LOG"'
expect "dashboard gets the URL and anon key"   'grep -q "\"https://$REF.supabase.co\"" "$DEFINES" && grep -q anon-key-123 "$DEFINES"'
expect "never the service_role key"            '! grep -q SECRET-service "$DEFINES"'
expect "builds the dashboard"                  'grep -q "flutter build web" "$LOG"'
expect "prints the endpoint and the next steps" 'grep -q "GUIDESTER_ENDPOINT=https://$REF.supabase.co/functions/v1/ingest" <<<"$out" && grep -q "Site URL" <<<"$out"'

echo "==> a dashboard set up for another project is kept"
echo '{"SUPABASE_URL": "https://otherprojectrefxxxx.supabase.co"}' > "$DEFINES"
SUPABASE_DB_PASSWORD=x "$SETUP" --project-ref $REF >/dev/null 2>&1
expect "old settings saved as .bak"            'grep -q otherprojectrefxxxx "$DEFINES.bak"'

echo "==> a project with only the newer keys"
cat > "$T/bin/supabase" <<'SH'
#!/usr/bin/env bash
echo "supabase $* | pw=${SUPABASE_DB_PASSWORD:+set}" >> "$CALLS"
case "$1 $2" in
  "projects api-keys") echo '[{"name":"default","type":"secret","api_key":"SECRET-new"},{"name":"default","type":"publishable","api_key":"sb_publishable_xyz"}]' ;;
esac
exit 0
SH
chmod +x "$T/bin/supabase"
SUPABASE_DB_PASSWORD=x "$SETUP" --project-ref $REF >/dev/null 2>&1
expect "falls back to the publishable key"     'grep -q sb_publishable_xyz "$DEFINES"'
expect "  and never the new secret key"        '! grep -q SECRET-new "$DEFINES"'

echo "==> backend only"
: > "$LOG"
SUPABASE_DB_PASSWORD=x "$SETUP" --project-ref $REF --skip-dashboard >/dev/null 2>&1
expect "--skip-dashboard never calls flutter"  '! grep -q "^flutter" "$LOG"'

echo "==> refusals"
: > "$LOG"
"$SETUP" >/dev/null 2>&1;                       expect "no ref is refused"      '[ $? -ne 0 ]'
"$SETUP" --project-ref Not-A-Ref >/dev/null 2>&1; expect "a malformed ref is refused" '[ $? -ne 0 ]'
expect "  and nothing was run for either"      '! grep -q "^supabase link" "$LOG"'
out="$(CURL_ANSWER='<html>502</html>' SUPABASE_DB_PASSWORD=x "$SETUP" --project-ref $REF --skip-dashboard 2>&1)"
expect "a function that does not answer fails" '[ $? -ne 0 ] && grep -q "did not answer as expected" <<<"$out"'

echo "==> dry run"
: > "$LOG"
out="$("$SETUP" --project-ref $REF --dry-run 2>&1)"
expect "changes nothing"                       '! grep -qE "^supabase (link|db push|functions)" "$LOG"'
expect "and says so"                           'grep -q "nothing was changed" <<<"$out"'

echo
if [ "$FAILED" -eq 0 ]; then echo "ALL CHECKS PASSED"; else echo "FAILURES ABOVE"; exit 1; fi
