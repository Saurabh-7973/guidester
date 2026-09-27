#!/usr/bin/env bash
# Exercises supabase/functions/ingest/index.ts locally, without Supabase.
#
# Covers every branch that runs BEFORE the first database call: method routing,
# CORS preflight, JSON parsing, and field validation. Those paths never touch
# Supabase, so they are fully testable here. Anything past the project lookup
# (invalid_key 401, upload, insert) needs a real deployment.
#
# Requires: deno. No network, no Supabase account.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FN="$HERE/../functions/ingest/index.ts"
LOG=/tmp/guidester_ingest_test.log

# createClient() does no I/O at construction, so placeholders are enough to boot.
export SUPABASE_URL="https://dummy.invalid"
export SUPABASE_SERVICE_ROLE_KEY="dummy-not-a-real-key"

# index.ts calls Deno.serve() with no options, so the port is Deno's default and
# is NOT configurable via $PORT. Discover it from the server's own banner instead
# of assuming, so this keeps working if that default ever changes.
: > "$LOG"
deno run --allow-net --allow-env "$FN" >"$LOG" 2>&1 &
PID=$!
trap 'kill $PID 2>/dev/null' EXIT
URL=""
for _ in $(seq 1 30); do
  URL="$(grep -om1 'http://localhost:[0-9]*' "$LOG" || true)"
  [ -n "$URL" ] && curl -s -o /dev/null "$URL" 2>/dev/null && break
  URL=""
  perl -e 'select undef,undef,undef,0.4'
done
if [ -z "$URL" ]; then
  echo "could not start the function; deno said:"; cat "$LOG"; exit 1
fi
echo "==> function listening on $URL"

FAILED=0
check () { # label  expected_status  expected_body_fragment  curl_args...
  local label="$1" want_status="$2" want_body="$3"; shift 3
  local out status body
  out="$(curl -s -w '\n%{http_code}' "$@" "$URL")"
  status="${out##*$'\n'}"; body="${out%$'\n'*}"
  if [ "$status" = "$want_status" ] && [[ "$body" == *"$want_body"* ]]; then
    printf '  PASS  %-32s %s %s\n' "$label" "$status" "$body"
  else
    printf '  FAIL  %-32s got %s %s (wanted %s %s)\n' "$label" "$status" "$body" "$want_status" "$want_body"
    FAILED=1
  fi
}

J=(-H 'content-type: application/json')
echo "==> ingest function, pre-database branches"
check "OPTIONS preflight"      200 ok            -X OPTIONS
check "GET rejected"           405 method_not_allowed -X GET
check "PUT rejected"           405 method_not_allowed -X PUT
check "malformed JSON"         400 bad_json      -X POST "${J[@]}" -d 'not json'
check "empty object"           400 missing_fields -X POST "${J[@]}" -d '{}'
check "api_key without body"   400 missing_fields -X POST "${J[@]}" -d '{"api_key":"k"}'
check "body without api_key"   400 missing_fields -X POST "${J[@]}" -d '{"body":"hi"}'
check "whitespace-only body"   400 missing_fields -X POST "${J[@]}" -d '{"api_key":"k","body":"   "}'
check "body over 2000 chars"   400 body_too_long  -X POST "${J[@]}" -d "{\"api_key\":\"k\",\"body\":\"$(python3 -c 'print("x"*2001)')\"}"

# Type confusion: §4.3 does String(p.body ?? ""), which happily coerces a number,
# object or array into "12345" / "[object Object]" / "1,2" and stores it.
check "body as a number rejected"   400 missing_fields -X POST "${J[@]}" -d '{"api_key":"k","body":12345}'
check "body as an object rejected"  400 missing_fields -X POST "${J[@]}" -d '{"api_key":"k","body":{"a":1}}'
check "body as an array rejected"   400 missing_fields -X POST "${J[@]}" -d '{"api_key":"k","body":[1,2]}'
check "api_key as an object rejected" 400 missing_fields -X POST "${J[@]}" -d '{"api_key":{"x":1},"body":"probe"}'
# Postgres text cannot hold U+0000; unchecked it reaches the insert and 500s.
check "null byte in body rejected"  400 invalid_body   -X POST "${J[@]}" -d '{"api_key":"k","body":"before\u0000after"}' 

# §5.4 — the chip set is fixed and the client is in a tester's APK, so an
# unrecognised type is rejected here rather than trusted through to the CHECK
# constraint. Absent and null stay valid: the column is nullable and an older
# SDK build never sends one.
echo "==> issue_type (§5.4)"
check "unknown issue_type rejected"  400 invalid_issue_type -X POST "${J[@]}" -d '{"api_key":"k","body":"probe","issue_type":"urgent"}'
check "issue_type casing rejected"   400 invalid_issue_type -X POST "${J[@]}" -d '{"api_key":"k","body":"probe","issue_type":"CRASH"}'
check "issue_type as a number"       400 invalid_issue_type -X POST "${J[@]}" -d '{"api_key":"k","body":"probe","issue_type":7}'
check "issue_type as an object"      400 invalid_issue_type -X POST "${J[@]}" -d '{"api_key":"k","body":"probe","issue_type":{"a":1}}'
check "issue_type as an array"       400 invalid_issue_type -X POST "${J[@]}" -d '{"api_key":"k","body":"probe","issue_type":["crash"]}'
check "empty issue_type rejected"    400 invalid_issue_type -X POST "${J[@]}" -d '{"api_key":"k","body":"probe","issue_type":""}'
check "SQL-ish issue_type rejected"  400 invalid_issue_type -X POST "${J[@]}" -d '{"api_key":"k","body":"probe","issue_type":"crash'"'"'); drop table comments;--"}'

# Each of the six must get PAST validation. They cannot reach the insert here
# (no database), so the tell is that they fail at the project lookup instead —
# a different error than the one validation would have produced.
for t in looks_wrong doesnt_work confusing crash slow idea; do
  check "issue_type $t accepted" 500 lookup_failed -X POST "${J[@]}" -d "{\"api_key\":\"k\",\"body\":\"probe\",\"issue_type\":\"$t\"}"
done
check "issue_type null accepted"    500 lookup_failed -X POST "${J[@]}" -d '{"api_key":"k","body":"probe","issue_type":null}'

# Impact (D51). Same reasoning as issue_type — the client ships inside an APK —
# with one difference: the column is NOT NULL with a default, so absent and null
# both mean 'annoying' rather than "no value". That is what lets the dashboard
# give impact a colour without ever rendering an empty one.
echo "==> impact (D51)"
check "unknown impact rejected"      400 invalid_impact -X POST "${J[@]}" -d '{"api_key":"k","body":"probe","impact":"urgent"}'
check "impact casing rejected"       400 invalid_impact -X POST "${J[@]}" -d '{"api_key":"k","body":"probe","impact":"Blocked"}'
check "impact as a number"           400 invalid_impact -X POST "${J[@]}" -d '{"api_key":"k","body":"probe","impact":2}'
check "impact as an object"          400 invalid_impact -X POST "${J[@]}" -d '{"api_key":"k","body":"probe","impact":{"a":1}}'
check "impact as an array"           400 invalid_impact -X POST "${J[@]}" -d '{"api_key":"k","body":"probe","impact":["blocked"]}'
check "empty impact rejected"        400 invalid_impact -X POST "${J[@]}" -d '{"api_key":"k","body":"probe","impact":""}'
check "SQL-ish impact rejected"      400 invalid_impact -X POST "${J[@]}" -d '{"api_key":"k","body":"probe","impact":"blocked'"'"'); drop table comments;--"}'
check "severity word rejected"       400 invalid_impact -X POST "${J[@]}" -d '{"api_key":"k","body":"probe","impact":"critical"}'

for i in blocked annoying cosmetic; do
  check "impact $i accepted" 500 lookup_failed -X POST "${J[@]}" -d "{\"api_key\":\"k\",\"body\":\"probe\",\"impact\":\"$i\"}"
done
# An older SDK build sends neither field and must still be accepted.
check "impact absent accepted"       500 lookup_failed -X POST "${J[@]}" -d '{"api_key":"k","body":"probe"}'
check "impact null accepted"         500 lookup_failed -X POST "${J[@]}" -d '{"api_key":"k","body":"probe","impact":null}'

# Blank regions. Caller-controlled, so the shape is bounded and not just the
# count: twenty elements carrying a megabyte string each is the same unbounded
# write as no cap at all. Rejected BEFORE the project lookup and the screenshot
# upload, so a malformed payload costs nothing.
echo "==> blank_regions (bounded shape, early)"
check "regions must be an array"      400 invalid_blank_regions -X POST "${J[@]}" -d '{"api_key":"k","body":"probe","blank_regions":"nope"}'
check "a region must be an object"    400 invalid_blank_regions -X POST "${J[@]}" -d '{"api_key":"k","body":"probe","blank_regions":["nope"]}'
check "a region needs its geometry"   400 invalid_blank_regions -X POST "${J[@]}" -d '{"api_key":"k","body":"probe","blank_regions":[{"kind":"RenderAndroidView"}]}'
check "geometry must be numeric"      400 invalid_blank_regions -X POST "${J[@]}" -d '{"api_key":"k","body":"probe","blank_regions":[{"x":"a","y":0,"w":1,"h":1}]}'
check "geometry must be 0..1"         400 invalid_blank_regions -X POST "${J[@]}" -d '{"api_key":"k","body":"probe","blank_regions":[{"x":0,"y":0,"w":9,"h":1}]}'
check "negative geometry rejected"    400 invalid_blank_regions -X POST "${J[@]}" -d '{"api_key":"k","body":"probe","blank_regions":[{"x":-1,"y":0,"w":1,"h":1}]}'
check "NaN geometry rejected"         400 invalid_blank_regions -X POST "${J[@]}" -d '{"api_key":"k","body":"probe","blank_regions":[{"x":null,"y":0,"w":1,"h":1}]}'

# 21 regions, one over the cap.
MANY="$(python3 -c "import json;print(json.dumps([{'kind':'T','x':0,'y':0,'w':0.1,'h':0.1}]*21))")"
check "too many regions rejected"     400 too_many_blank_regions -X POST "${J[@]}" -d "{\"api_key\":\"k\",\"body\":\"probe\",\"blank_regions\":$MANY}"

check "a well-formed region accepted" 500 lookup_failed -X POST "${J[@]}" -d '{"api_key":"k","body":"probe","blank_regions":[{"kind":"RenderAndroidView","x":0,"y":0.2,"w":1,"h":0.5}]}'
check "no regions accepted"           500 lookup_failed -X POST "${J[@]}" -d '{"api_key":"k","body":"probe","blank_regions":[]}'

# The context blob has been stored verbatim since day one. The SDK sends well
# under a kilobyte; this only ever rejects something that is not our client.
echo "==> context bounds"
check "context must be an object"     400 invalid_context -X POST "${J[@]}" -d '{"api_key":"k","body":"probe","context":"nope"}'
check "context array rejected"        400 invalid_context -X POST "${J[@]}" -d '{"api_key":"k","body":"probe","context":[1,2,3]}'
BIG="$(python3 -c "print('x'*20000)")"
check "oversized context rejected"    413 context_too_large -X POST "${J[@]}" -d "{\"api_key\":\"k\",\"body\":\"probe\",\"context\":{\"a\":\"$BIG\"}}"
check "normal context accepted"       500 lookup_failed -X POST "${J[@]}" -d '{"api_key":"k","body":"probe","context":{"text_scale_factor":1.0}}'
check "issue_type absent accepted"  500 lookup_failed -X POST "${J[@]}" -d '{"api_key":"k","body":"probe"}'

# Errors. The stack is what makes a report actionable, so the bound here is
# generous — and everything else about it is as strict as the rest of the
# payload, because this arrives from an APK in a stranger's hands.
echo "==> errors (the stack that explains the comment)"
check "errors must be an array"       400 invalid_errors  -X POST "${J[@]}" -d '{"api_key":"k","body":"probe","errors":"boom"}'
check "an error must be an object"    400 invalid_errors  -X POST "${J[@]}" -d '{"api_key":"k","body":"probe","errors":["boom"]}'
check "an error needs an exception"   400 invalid_errors  -X POST "${J[@]}" -d '{"api_key":"k","body":"probe","errors":[{"stack":"#0 x"}]}'
check "an empty exception rejected"   400 invalid_errors  -X POST "${J[@]}" -d '{"api_key":"k","body":"probe","errors":[{"exception":""}]}'
check "exception as an object"        400 invalid_errors  -X POST "${J[@]}" -d '{"api_key":"k","body":"probe","errors":[{"exception":{"a":1}}]}'
FOUR="$(python3 -c "import json;print(json.dumps([{'exception':'e','stack':'#0 x'}]*4))")"
check "a fourth error rejected"       400 too_many_errors -X POST "${J[@]}" -d "{\"api_key\":\"k\",\"body\":\"probe\",\"errors\":$FOUR}"

# Past validation: the tell is the lookup, as everywhere else here.
check "a well-formed error accepted"  500 lookup_failed   -X POST "${J[@]}" -d '{"api_key":"k","body":"probe","errors":[{"at":"2026-09-09T05:00:00Z","exception":"RenderFlex overflowed by 42 pixels","stack":"#0 Foo.build (foo.dart:12)","library":"rendering library","screen":"HOME"}]}'
# A dead platform channel throws with no Dart frames. That error is still the
# most useful thing in the report.
check "an error with no stack ok"     500 lookup_failed   -X POST "${J[@]}" -d '{"api_key":"k","body":"probe","errors":[{"exception":"MissingPluginException"}]}'
check "no errors key accepted"        500 lookup_failed   -X POST "${J[@]}" -d '{"api_key":"k","body":"probe"}'
check "an empty error list accepted"  500 lookup_failed   -X POST "${J[@]}" -d '{"api_key":"k","body":"probe","errors":[]}'
# A stack long enough to be a payload rather than a stack is truncated, not
# rejected: losing the whole report over its last frames would be the wrong
# trade.
LONGSTACK="$(python3 -c "print('#0 Foo.build (foo.dart:12) ' * 1000)")"
check "an enormous stack truncated"   500 lookup_failed   -X POST "${J[@]}" -d "{\"api_key\":\"k\",\"body\":\"probe\",\"errors\":[{\"exception\":\"boom\",\"stack\":\"$LONGSTACK\"}]}"

# The launch ping (product spec §3.2). It carries no comment, so it has to be
# handled before every field check a comment goes through — and it must never
# be a way to write a comment without one.
echo "==> ping (§3.2 connection check)"
check "ping needs a key"              400 missing_fields -X POST "${J[@]}" -d '{"ping":true}'
# Past validation with no body at all: the tell is the lookup, the same one a
# well-formed comment reaches.
check "ping needs no body"            500 lookup_failed  -X POST "${J[@]}" -d '{"api_key":"k","ping":true}'
check "ping carries device context"   500 lookup_failed  -X POST "${J[@]}" -d '{"api_key":"k","ping":true,"device_model":"Pixel 7","os_version":"Android 15"}'
# Only the literal true. A truthy string or 1 must go down the comment path and
# be rejected for having no body, so a malformed client cannot skip validation
# by sending something ping-ish.
check "ping:1 is not a ping"          400 missing_fields -X POST "${J[@]}" -d '{"api_key":"k","ping":1}'
check "ping:\"true\" is not a ping"   400 missing_fields -X POST "${J[@]}" -d '{"api_key":"k","ping":"true"}'
check "ping:false is not a ping"      400 missing_fields -X POST "${J[@]}" -d '{"api_key":"k","ping":false}'
# A ping alongside a comment is still a ping, and stores nothing.
check "ping outranks a body"          500 lookup_failed  -X POST "${J[@]}" -d '{"api_key":"k","ping":true,"body":"probe"}'

# --------------------------------------------------------------------------
# The return leg (0008). Everything before the project lookup is testable here;
# the lookup itself needs a deployment, so `lookup_failed` is how a request that
# passed validation reports in.
# --------------------------------------------------------------------------
echo "==> tester verdicts"

# A verdict is only a verdict for the two words a tester can say. Anything else
# must be refused BEFORE the lookup, or an APK can push arbitrary strings at a
# CHECK constraint and turn a typo into a 500.
check "verdict rejects an unknown word" 400 invalid_verdict \
  -X POST "${J[@]}" -d '{"api_key":"k","verdict":"fixed","comment_id":"c","tester_id":"t"}'
check "verdict rejects a dev verdict"   400 invalid_verdict \
  -X POST "${J[@]}" -d '{"api_key":"k","verdict":"wont_fix","comment_id":"c","tester_id":"t"}'

# Both ids are required. Without tester_id the ownership test cannot run, and a
# verdict that skips it would let one extracted key close every report.
check "verdict needs a comment id"      400 missing_fields \
  -X POST "${J[@]}" -d '{"api_key":"k","verdict":"accepted","tester_id":"t"}'
check "verdict needs a tester id"       400 missing_fields \
  -X POST "${J[@]}" -d '{"api_key":"k","verdict":"accepted","comment_id":"c"}'
check "verdict needs a key"             400 missing_fields \
  -X POST "${J[@]}" -d '{"verdict":"accepted","comment_id":"c","tester_id":"t"}'

# A well-formed verdict gets as far as the lookup, which is where this harness
# stops. Both accepted words must reach it.
check "accepted reaches the lookup"     500 lookup_failed \
  -X POST "${J[@]}" -d '{"api_key":"k","verdict":"accepted","comment_id":"c","tester_id":"t"}'
check "rejected reaches the lookup"     500 lookup_failed \
  -X POST "${J[@]}" -d '{"api_key":"k","verdict":"rejected","comment_id":"c","tester_id":"t"}'

# A non-string verdict must not be coerced. This is D39's lesson: String(x)
# turned an object into "[object Object]" and stored it as a real comment.
check "verdict:true is not a verdict"   400 missing_fields \
  -X POST "${J[@]}" -d '{"api_key":"k","verdict":true,"comment_id":"c","tester_id":"t"}'
check "verdict:1 is not a verdict"      400 missing_fields \
  -X POST "${J[@]}" -d '{"api_key":"k","verdict":1,"comment_id":"c","tester_id":"t"}'

# A ping carrying a tester id is still a ping, and still reaches the lookup.
check "ping carries a tester id"        500 lookup_failed \
  -X POST "${J[@]}" -d '{"api_key":"k","ping":true,"tester_id":"tester-abc"}'
# Ping outranks a verdict, for the same reason it outranks a body: one branch
# has to win, and the cheapest one should.
check "ping outranks a verdict"         500 lookup_failed \
  -X POST "${J[@]}" -d '{"api_key":"k","ping":true,"verdict":"accepted","comment_id":"c","tester_id":"t"}'

# The offline queue's idempotency key. Checked with the other fields, before
# the key lookup, so a malformed one costs no database call.
check "client_id too short"             400 invalid_client_id \
  -X POST "${J[@]}" -d '{"api_key":"k","body":"b","client_id":"abc"}'
check "client_id not a string"          400 invalid_client_id \
  -X POST "${J[@]}" -d '{"api_key":"k","body":"b","client_id":12345678}'
check "client_id with a slash"          400 invalid_client_id \
  -X POST "${J[@]}" -d '{"api_key":"k","body":"b","client_id":"../../etc/passwd"}'
check "client_id over 64"               400 invalid_client_id \
  -X POST "${J[@]}" -d "{\"api_key\":\"k\",\"body\":\"b\",\"client_id\":\"$(printf 'a%.0s' $(seq 1 65))\"}"
check "valid client_id reaches lookup"  500 lookup_failed \
  -X POST "${J[@]}" -d '{"api_key":"k","body":"b","client_id":"0123456789abcdef0123456789abcdef"}'
check "null client_id is absent"        500 lookup_failed \
  -X POST "${J[@]}" -d '{"api_key":"k","body":"b","client_id":null}'

echo "==> CORS headers on preflight"
hdr="$(curl -s -D - -o /dev/null -X OPTIONS "$URL")"
for h in "Access-Control-Allow-Origin: \*" "Access-Control-Allow-Headers: content-type"; do
  if grep -qi "$h" <<<"$hdr"; then printf '  PASS  %s\n' "$h"; else printf '  FAIL  missing %s\n' "$h"; FAILED=1; fi
done

echo "==> rate limit, against a stub PostgREST"
# The branches above never reach the database. The limiter sits just past the
# key lookup, so it is checked here against a stand-in that accepts every key
# and answers ingest_allow however /__mode says.
kill $PID 2>/dev/null; wait $PID 2>/dev/null
STUB_PORT=54399
STUB_LOG=/tmp/guidester_stub.log
STUB="http://localhost:$STUB_PORT"
STUB_PORT=$STUB_PORT deno run --allow-net --allow-env "$HERE/stub_postgrest.ts" >"$STUB_LOG" 2>&1 &
SPID=$!
: > "$LOG"
SUPABASE_URL="$STUB" deno run --allow-net --allow-env "$FN" >"$LOG" 2>&1 &
PID=$!
trap 'kill $PID $SPID 2>/dev/null' EXIT
URL=""
for _ in $(seq 1 30); do
  URL="$(grep -om1 'http://localhost:[0-9]*' "$LOG" || true)"
  [ -n "$URL" ] && curl -s -o /dev/null "$URL" 2>/dev/null \
    && curl -s -o /dev/null "$STUB/__calls" 2>/dev/null && break
  URL=""
  perl -e 'select undef,undef,undef,0.4'
done
[ -z "$URL" ] && { echo "could not start function + stub"; cat "$LOG" "$STUB_LOG"; exit 1; }
mode () { curl -s -X POST -d "$1" "$STUB/__mode" >/dev/null; }
called () { # fragment
  if curl -s "$STUB/__calls" | grep -q "$1"; then printf '  PASS  limiter asked: %s\n' "$1"
  else printf '  FAIL  limiter never asked: %s\n' "$1"; FAILED=1; fi
}

mode allow
check "comment within the limit"       200 '"ok":true' \
  -X POST "${J[@]}" -d '{"api_key":"k","body":"hello"}'
called "bucket=comment limit=30"
mode deny
check "comment over the limit"         429 rate_limited \
  -X POST "${J[@]}" -d '{"api_key":"k","body":"hello"}'
if curl -s "$STUB/__calls" | grep -q "POST /rest/v1/comments"; then
  echo "  FAIL  a limited comment still reached the insert"; FAILED=1
else echo "  PASS  a limited comment stops before the insert"; fi
check "ping over the limit"            429 rate_limited \
  -X POST "${J[@]}" -d '{"api_key":"k","ping":true}'
called "bucket=ping limit=120"
check "verdict over the limit"         429 rate_limited \
  -X POST "${J[@]}" -d '{"api_key":"k","verdict":"accepted","comment_id":"c","tester_id":"t"}'
called "bucket=verdict limit=60"
ra="$(curl -s -D - -o /dev/null -X POST "${J[@]}" -d '{"api_key":"k","ping":true}' "$URL" | tr -d '\r' | awk -F': ' 'tolower($1)=="retry-after"{print $2}')"
if [[ "$ra" =~ ^[0-9]+$ ]] && [ "$ra" -ge 1 ] && [ "$ra" -le 60 ]; then
  printf '  PASS  Retry-After is the rest of the window (%ss)\n' "$ra"
else printf '  FAIL  Retry-After missing or wrong: "%s"\n' "$ra"; FAILED=1; fi
mode missing
check "no limiter (pre-0012) fails open" 200 '"ok":true' \
  -X POST "${J[@]}" -d '{"api_key":"k","body":"hello"}'
check "  and a ping still answers"     200 '"ping":true' \
  -X POST "${J[@]}" -d '{"api_key":"k","ping":true}'

echo
if [ "$FAILED" -eq 0 ]; then
  echo "ALL CHECKS PASSED"
  echo "Not covered here (needs a real deployment): invalid_key 401, screenshot upload, row insert."
else
  echo "FAILURES ABOVE"; exit 1
fi
