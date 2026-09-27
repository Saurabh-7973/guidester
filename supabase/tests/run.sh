#!/usr/bin/env bash
# Verifies supabase/migrations/*.sql against a real PostgreSQL instance.
#
# Spins up a throwaway cluster, installs a minimal stand-in for the Supabase-managed
# objects (auth.users, auth.uid, storage.*), applies the migration UNMODIFIED, then
# asserts the §4.2 security model behaviourally. Tears the cluster down on exit.
#
# Requires: postgresql client+server on PATH (brew install postgresql@17).
# Does NOT require Docker, a Supabase account, or network access.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MIGRATION="$HERE/../migrations/0001_init.sql"
# Every migration, in order. 0002-0004 went unverified for as long as this only
# applied 0001 — which is how the delete policies could have shipped untested.
MIGRATIONS=("$HERE"/../migrations/*.sql)
PGBIN="${PGBIN:-/opt/homebrew/opt/postgresql@17/bin}"
[ -d "$PGBIN" ] && export PATH="$PGBIN:$PATH"

DATA="$(mktemp -d)/pgdata"
SOCK="$(mktemp -d /tmp/gtest.XXXXXX)"   # short path: sockets cap at 103 bytes
PORT="${PGPORT_TEST:-55432}"
cleanup() { pg_ctl -D "$DATA" stop -m immediate >/dev/null 2>&1 || true; rm -rf "$DATA" "$SOCK"; }
trap cleanup EXIT

echo "==> initdb"
initdb -D "$DATA" -U postgres --no-locale --encoding=UTF8 >/dev/null
echo "==> start postgres on :$PORT"
pg_ctl -D "$DATA" -o "-p $PORT -k $SOCK -c listen_addresses=" -l "$DATA/pg.log" start >/dev/null
export PGHOST="$SOCK" PGPORT="$PORT" PGUSER=postgres PGDATABASE=guidester_test
psql -d postgres -q -c "create database guidester_test;"

echo "==> install Supabase stand-ins"
# Supabase pre-installs pgcrypto into the `extensions` schema, NOT public, and
# that schema is not on the default search_path. Mirroring it here is what makes
# this suite able to catch an unqualified gen_random_bytes() — the exact bug that
# passed locally and then failed on the real project.
psql -q -v ON_ERROR_STOP=1 \
  -c "create schema if not exists extensions;" \
  -c "create extension if not exists pgcrypto with schema extensions;" \
  -f "$HERE/harness.sql"

echo "==> backfill: rows that disagree before 0009, checked after it"
psql -d postgres -q -c "create database guidester_backfill;"
BF=(-d guidester_backfill -q -v ON_ERROR_STOP=1)
psql "${BF[@]}" -c "create schema if not exists extensions;" \
  -c "create extension if not exists pgcrypto with schema extensions;" \
  -f "$HERE/harness.sql"
for m in "${MIGRATIONS[@]}"; do
  case "$(basename "$m")" in 0009_*) break ;; esac
  psql "${BF[@]}" -f "$m"
done
psql "${BF[@]}" -f "$HERE/backfill_test.sql"
for m in "${MIGRATIONS[@]}"; do
  case "$(basename "$m")" in 0009_*|001[0-9]_*) psql "${BF[@]}" -f "$m" ;; esac
done
psql "${BF[@]}" -v phase_assert=1 -f "$HERE/backfill_test.sql" 2>&1 | sed 's/^NOTICE:  //'

echo "==> apply migrations (unmodified, in order)"
for m in "${MIGRATIONS[@]}"; do
  echo "    $(basename "$m")"
  psql -q -v ON_ERROR_STOP=1 -f "$m"
done

echo "==> assert security model"
psql -q -v ON_ERROR_STOP=1 -f "$HERE/rls_test.sql" 2>&1 | sed 's/^NOTICE:  //'

echo "==> idempotency (expected to FAIL: 0001_init is not re-runnable)"
if psql -q -v ON_ERROR_STOP=1 -f "$MIGRATION" >/dev/null 2>&1; then
  echo "    unexpected: migration re-applied cleanly"
else
  echo "    confirmed non-idempotent, as documented"
fi

echo
echo "ALL CHECKS PASSED"
