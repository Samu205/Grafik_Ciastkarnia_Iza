#!/usr/bin/env bash
# Uruchamia migracje i testy pgTAP na zwykłym PostgreSQL (bez Dockera i Supabase CLI).
# Przydatne w CI i w środowiskach, gdzie `supabase start` nie działa.
#
# Wymagania: psql oraz rozszerzenie pgTAP zainstalowane na serwerze.
# Połączenie: zmienne PGHOST, PGPORT, PGUSER (superuser), PGPASSWORD.
#
# Użycie:  scripts/db/test-local.sh
# Gdy masz Supabase CLI z Dockerem, używaj zamiast tego:  supabase db reset && supabase test db

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
DB="${TEST_DB_NAME:-grafik_test}"

psql_admin() { psql -v ON_ERROR_STOP=1 -X -q -d postgres "$@"; }
psql_db() { psql -v ON_ERROR_STOP=1 -X -q -d "$DB" "$@"; }

echo "==> Tworzę czystą bazę $DB"
psql_admin -c "drop database if exists $DB with (force);"
psql_admin -c "create database $DB;"
psql_admin -c "alter database $DB set search_path = \"\$user\", public, extensions;"

echo "==> Imitacja środowiska Supabase"
psql_db -f "$ROOT/scripts/db/supabase-shim.sql"
psql_db -c "create extension if not exists pgtap with schema extensions;"

echo "==> Migracje"
for f in "$ROOT"/supabase/migrations/*.sql; do
  echo "    $(basename "$f")"
  psql_db -f "$f"
done

echo "==> Seed"
psql_db -f "$ROOT/supabase/seed.sql"

echo "==> Testy"
failed=0
for f in "$ROOT"/supabase/tests/*.sql; do
  name="$(basename "$f")"
  if ! out="$(psql -X -q -t -A -v ON_ERROR_STOP=1 -d "$DB" -f "$f" 2>&1)"; then
    echo "    BŁĄD  $name"
    echo "$out" | sed 's/^/        /'
    failed=1
    continue
  fi
  if echo "$out" | grep -qE '^not ok|^# Looks like'; then
    echo "    NIE   $name"
    echo "$out" | grep -E '^not ok|^#' | sed 's/^/        /'
    failed=1
  else
    count="$(echo "$out" | grep -cE '^ok' || true)"
    echo "    OK    $name ($count asercji)"
  fi
done

if [ "$failed" -ne 0 ]; then
  echo "==> Testy NIE przeszły"
  exit 1
fi
echo "==> Wszystkie testy przeszły"
