#!/usr/bin/env bash
#
# Prove the policy suite actually fails when a policy is wrong.
#
# A SQL assertion suite can pass vacuously in ways that look identical to
# success: a typo'd table name, a query that returns no rows, a `set role` that
# silently did not apply. RLS is not enforced for superusers, so a suite run as
# the wrong role passes every test against completely open policies.
#
# This mutates a policy to be deliberately permissive, confirms the suite
# notices, then restores it. If this script ever reports that the suite passed
# against a broken policy, the suite is worthless and must be fixed before it is
# trusted again.

set -euo pipefail

PORT="${PGPORT:-5433}"
DB=friends_selfcheck

PGBIN="$(ls -d /usr/lib/postgresql/*/bin 2>/dev/null | sort -V | tail -1 || true)"
[[ -n "$PGBIN" ]] || { echo "PostgreSQL not found." >&2; exit 1; }
export PATH="$PGBIN:$PATH"
export PGHOST=127.0.0.1 PGPORT="$PORT" PGUSER=postgres

pg_isready -h 127.0.0.1 -p "$PORT" >/dev/null 2>&1 || {
  echo "No PostgreSQL on port $PORT. Run scripts/db-local.sh first." >&2; exit 1; }

psql -q -c "drop database if exists $DB;" -c "create database $DB;" postgres
psql -q -v ON_ERROR_STOP=1 -d "$DB" -f supabase/tests/00_auth_shim.sql
for f in supabase/migrations/*.sql; do
  psql -q -v ON_ERROR_STOP=1 -d "$DB" -f "$f"
done

echo "1/3 suite passes against correct policies"
if ! psql -q -v ON_ERROR_STOP=1 -d "$DB" -f supabase/tests/01_identity_policies.sql >/dev/null 2>&1; then
  echo "FAIL: suite does not pass against correct policies" >&2
  exit 1
fi

echo "2/3 breaking profiles_select — making every profile world-readable"
psql -q -d "$DB" -c "alter policy profiles_select on profiles using (true);"

if psql -q -v ON_ERROR_STOP=1 -d "$DB" -f supabase/tests/01_identity_policies.sql >/dev/null 2>&1; then
  echo "FAIL: suite PASSED against a world-readable profiles table." >&2
  echo "      The tests are not exercising RLS. Do not trust a green run." >&2
  psql -q -c "drop database if exists $DB;" postgres
  exit 1
fi
echo "      suite correctly failed"

echo "3/3 restoring and re-running"
psql -q -d "$DB" -c "drop policy profiles_select on profiles;"
psql -q -d "$DB" -c "create policy profiles_select on profiles for select using (
    id = auth.uid()
    or are_friends(id, auth.uid())
    or shares_group(id, auth.uid())
    or exists (
      select 1 from friendships f
      where f.status = 'pending'
        and ((f.requester_id = auth.uid() and f.addressee_id = profiles.id)
          or (f.addressee_id = auth.uid() and f.requester_id = profiles.id))
    )
  );"
if ! psql -q -v ON_ERROR_STOP=1 -d "$DB" -f supabase/tests/01_identity_policies.sql >/dev/null 2>&1; then
  echo "FAIL: suite does not pass after restoring the policy" >&2
  exit 1
fi

psql -q -c "drop database if exists $DB;" postgres
echo "OK — the policy suite detects a broken policy"
