#!/usr/bin/env bash
#
# Apply migrations and run policy tests against a plain PostgreSQL server.
#
# This is the fallback path for environments without Docker (CI containers,
# restricted sandboxes). The supported local workflow is `supabase start` +
# `supabase db reset`, which runs the real auth schema — use that when you can.
#
# What this trades away: supabase/tests/00_auth_shim.sql is an approximation of
# Supabase's auth schema, so a difference between the shim and the real thing
# will not be caught here. CI runs the genuine stack for exactly that reason.
#
# Usage:
#   scripts/db-local.sh [--seed] [--keep]
#
# Env:
#   PGPORT   port to start on (default 5433)
#   PGDATA   data directory (default /tmp/friends-pgdata)

set -euo pipefail

PORT="${PGPORT:-5433}"
DATA="${PGDATA:-/tmp/friends-pgdata}"
DB=friends_local
SEED=0
KEEP=0

for arg in "$@"; do
  case "$arg" in
    --seed) SEED=1 ;;
    --keep) KEEP=1 ;;
    *) echo "unknown argument: $arg" >&2; exit 2 ;;
  esac
done

PGBIN="$(ls -d /usr/lib/postgresql/*/bin 2>/dev/null | sort -V | tail -1 || true)"
if [[ -z "$PGBIN" ]]; then
  echo "PostgreSQL not found. Install it (apt-get install postgresql-16) or use 'supabase start'." >&2
  exit 1
fi
export PATH="$PGBIN:$PATH"

if ! pg_isready -h 127.0.0.1 -p "$PORT" >/dev/null 2>&1; then
  echo "starting postgres on port $PORT"
  if [[ ! -d "$DATA/base" ]]; then
    mkdir -p "$DATA"
    chown -R postgres:postgres "$DATA" 2>/dev/null || true
    su postgres -c "$PGBIN/initdb -D $DATA -A trust" >/dev/null
  fi
  su postgres -c "$PGBIN/pg_ctl -D $DATA -l /tmp/friends-pg.log -o '-p $PORT' start" >/dev/null
  sleep 2
fi

export PGHOST=127.0.0.1 PGPORT="$PORT" PGUSER=postgres

psql -q -c "drop database if exists $DB;" -c "create database $DB;" postgres

echo "applying auth shim (local only — not a migration)"
psql -q -v ON_ERROR_STOP=1 -d "$DB" -f supabase/tests/00_auth_shim.sql

echo "applying migrations"
for f in supabase/migrations/*.sql; do
  echo "  $(basename "$f")"
  psql -q -v ON_ERROR_STOP=1 -d "$DB" -f "$f"
done

if [[ "$SEED" == "1" ]]; then
  echo "seeding"
  psql -q -v ON_ERROR_STOP=1 -d "$DB" -f supabase/seed.sql
fi

echo "running policy tests"
for f in supabase/tests/[0-9][1-9]_*.sql; do
  echo "  $(basename "$f")"
  psql -q -v ON_ERROR_STOP=1 -d "$DB" -f "$f"
done

echo "OK — migrations applied and policy tests passed against $DB"

if [[ "$KEEP" == "0" ]]; then
  psql -q -c "drop database if exists $DB;" postgres
fi
