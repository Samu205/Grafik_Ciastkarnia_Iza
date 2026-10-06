-- Funkcje pomocnicze dla testów pgTAP.
-- Ten plik NIE jest w transakcji – tworzy schemat `tests`, z którego korzystają
-- pozostałe pliki (uruchamiane alfabetycznie). Nie jest częścią migracji.

create extension if not exists pgtap with schema extensions;

drop schema if exists tests cascade;
create schema tests;
grant usage on schema tests to authenticated, anon;

-- Tworzy użytkownika auth i pracownika; zwraca jego id.
create function tests.create_employee(
  p_name text,
  p_role public.app_role default 'employee',
  p_department public.department default 'sales',
  p_requires_approval boolean default false
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id uuid := gen_random_uuid();
begin
  insert into auth.users (id, email) values (v_id, lower(replace(p_name, ' ', '.')) || '@example.com');
  insert into public.employees (id, full_name, role, department, swaps_require_approval)
  values (v_id, p_name, p_role, p_department, p_requires_approval);
  return v_id;
end;
$$;

-- Id pracownika po imieniu (wygodne w testach zamiast zmiennych psql).
create function tests.emp(p_name text)
returns uuid
language sql stable
security definer
set search_path = public
as $$
  select id from public.employees where full_name = p_name
$$;

-- Przełącza bieżącą transakcję na zalogowanego użytkownika (jak żądanie z aplikacji).
create function tests.login_as(p_user_id uuid)
returns void
language plpgsql
as $$
begin
  perform set_config('request.jwt.claims', json_build_object('sub', p_user_id, 'role', 'authenticated')::text, true);
  perform set_config('role', 'authenticated', true);
end;
$$;

create function tests.login_as_anon()
returns void
language plpgsql
as $$
begin
  perform set_config('request.jwt.claims', '{"role":"anon"}', true);
  perform set_config('role', 'anon', true);
end;
$$;

-- Wraca do roli administratora (właściciela bazy).
create function tests.logout()
returns void
language plpgsql
as $$
begin
  perform set_config('request.jwt.claims', '', true);
  perform set_config('role', 'postgres', true);
end;
$$;

create function tests.schedule_id(p_name text)
returns uuid
language sql stable
security definer
set search_path = public
as $$
  select id from public.schedules where name = p_name
$$;

-- Tworzy zmianę bezpośrednio (z pominięciem RPC); zwraca id.
create function tests.make_shift(
  p_schedule text,
  p_date date,
  p_start time,
  p_end time,
  p_employee uuid default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id uuid;
begin
  insert into public.shifts (schedule_id, date, start_time, end_time, employee_id)
  values (tests.schedule_id(p_schedule), p_date, p_start, p_end, p_employee)
  returning id into v_id;
  return v_id;
end;
$$;

-- Zakłada miesiąc w podanym statusie (bez powiadomień o otwarciu – status ustawiany wprost).
create function tests.make_month(p_month date, p_status public.month_status)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.schedule_months (month, status) values (public.month_start(p_month), p_status)
  on conflict (month) do update set status = excluded.status;
end;
$$;

create function tests.shift_owner(p_shift_id uuid)
returns uuid
language sql stable
security definer
set search_path = public
as $$
  select employee_id from public.shifts where id = p_shift_id
$$;

create function tests.swap_status(p_request_id uuid)
returns public.swap_status
language sql stable
security definer
set search_path = public
as $$
  select status from public.swap_requests where id = p_request_id
$$;

create function tests.notification_count(p_employee uuid, p_kind text)
returns bigint
language sql stable
security definer
set search_path = public
as $$
  select count(*) from public.notifications where employee_id = p_employee and kind = p_kind
$$;

grant execute on all functions in schema tests to authenticated, anon;

select plan(1);
select has_schema('tests', 'Schemat z pomocnikami testów istnieje');
select * from finish();
