-- Minimalna imitacja środowiska Supabase dla zwykłego PostgreSQL.
-- Używana WYŁĄCZNIE przez scripts/db/test-local.sh (testy bez Dockera / Supabase CLI).
-- W prawdziwym Supabase te obiekty już istnieją – NIE dodawaj tego pliku do migracji.

do $$
begin
  if not exists (select 1 from pg_roles where rolname = 'anon') then
    create role anon nologin noinherit;
  end if;
  if not exists (select 1 from pg_roles where rolname = 'authenticated') then
    create role authenticated nologin noinherit;
  end if;
  if not exists (select 1 from pg_roles where rolname = 'service_role') then
    create role service_role nologin noinherit bypassrls;
  end if;
end;
$$;

create schema if not exists auth;
create schema if not exists extensions;

create table if not exists auth.users (
  id    uuid primary key default gen_random_uuid(),
  email text
);

-- Jak w Supabase: identyfikator użytkownika z claimów JWT.
create or replace function auth.uid()
returns uuid
language sql stable
as $$
  select coalesce(
    nullif(current_setting('request.jwt.claim.sub', true), ''),
    (nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'sub')
  )::uuid
$$;

grant usage on schema public, auth, extensions to anon, authenticated, service_role;
grant execute on function auth.uid() to anon, authenticated, service_role;

-- Domyślne uprawnienia jak w Supabase: nowe tabele i funkcje w public dostępne dla ról API.
alter default privileges in schema public grant all on tables to anon, authenticated, service_role;
alter default privileges in schema public grant all on sequences to anon, authenticated, service_role;
alter default privileges in schema public grant execute on functions to anon, authenticated, service_role;
