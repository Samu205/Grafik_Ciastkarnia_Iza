-- =============================================================================
-- Uprawnienia i Row Level Security
--
-- Zasada: rola `anon` nie ma dostępu do niczego. Rola `authenticated` ma tylko te
-- uprawnienia, które są potrzebne, a RLS zawęża je do właściwych wierszy.
-- Przypisania pracowników do zmian i zamiany idą WYŁĄCZNIE przez funkcje RPC
-- (security definer) – dlatego kolumna shifts.employee_id nie jest zapisywalna wprost.
-- =============================================================================

-- Dodatkowe funkcje pomocnicze dla polityk ----------------------------------------

create function public.current_department()
returns public.department
language sql stable security definer
set search_path = public
as $$
  select department from public.employees where id = auth.uid() and active
$$;

create function public.is_month_collecting(d date)
returns boolean
language sql stable security definer
set search_path = public
as $$
  select exists (
    select 1 from public.schedule_months
    where month = public.month_start(d) and status = 'collecting'
  )
$$;

-- Najpierw zabieramy wszystko, potem nadajemy dokładnie to, co trzeba ---------

revoke all on all tables in schema public from anon, authenticated;
revoke all on all sequences in schema public from anon, authenticated;

alter table public.employees       enable row level security;
alter table public.schedules       enable row level security;
alter table public.shift_templates enable row level security;
alter table public.schedule_months enable row level security;
alter table public.shifts          enable row level security;
alter table public.availability    enable row level security;
alter table public.swap_requests   enable row level security;
alter table public.notifications   enable row level security;
alter table public.audit_log       enable row level security;

-- employees -----------------------------------------------------------------------
grant select, insert, update, delete on public.employees to authenticated;

create policy employees_select on public.employees
  for select to authenticated
  using (public.current_app_role() is not null and (active or public.is_manager() or id = auth.uid()));

create policy employees_insert on public.employees
  for insert to authenticated
  with check (public.is_owner());

create policy employees_update on public.employees
  for update to authenticated
  using (public.is_owner())
  with check (public.is_owner());

create policy employees_delete on public.employees
  for delete to authenticated
  using (public.is_owner() and id <> auth.uid());

-- schedules ----------------------------------------------------------------------
-- Usuwanie tylko przez delete_schedule() (z potwierdzeniem nazwy).
grant select, insert, update on public.schedules to authenticated;

create policy schedules_select on public.schedules
  for select to authenticated
  using (public.current_app_role() is not null and (archived_at is null or public.is_owner()));

create policy schedules_insert on public.schedules
  for insert to authenticated
  with check (public.is_owner() and archived_at is null);

create policy schedules_update on public.schedules
  for update to authenticated
  using (public.is_owner())
  with check (public.is_owner());

-- shift_templates ----------------------------------------------------------------
grant select, insert, update, delete on public.shift_templates to authenticated;

create policy shift_templates_select on public.shift_templates
  for select to authenticated
  using (public.current_app_role() is not null);

create policy shift_templates_write on public.shift_templates
  for all to authenticated
  using (public.is_manager())
  with check (public.is_manager());

-- schedule_months ----------------------------------------------------------------
grant select, insert, delete on public.schedule_months to authenticated;
grant update (status, availability_deadline) on public.schedule_months to authenticated;

create policy schedule_months_select on public.schedule_months
  for select to authenticated
  using (public.current_app_role() is not null);

create policy schedule_months_insert on public.schedule_months
  for insert to authenticated
  with check (public.is_manager());

create policy schedule_months_update on public.schedule_months
  for update to authenticated
  using (public.is_manager())
  with check (public.is_manager());

create policy schedule_months_delete on public.schedule_months
  for delete to authenticated
  using (public.is_manager() and status <> 'published');

-- shifts -------------------------------------------------------------------------
-- Halina tworzy zmiany i zmienia godziny wprost; osoby przypisuje assign_shift().
-- Usunąć wprost można tylko nieobsadzoną zmianę.
grant select on public.shifts to authenticated;
grant insert (schedule_id, date, start_time, end_time, template_id) on public.shifts to authenticated;
grant update (start_time, end_time, template_id) on public.shifts to authenticated;
grant delete on public.shifts to authenticated;

create policy shifts_select on public.shifts
  for select to authenticated
  using (
    public.is_manager()
    or (public.current_app_role() is not null and public.is_month_published(date))
  );

create policy shifts_insert on public.shifts
  for insert to authenticated
  with check (public.is_manager() and employee_id is null);

create policy shifts_update on public.shifts
  for update to authenticated
  using (public.is_manager())
  with check (public.is_manager());

create policy shifts_delete on public.shifts
  for delete to authenticated
  using (public.is_manager() and employee_id is null);

-- availability -------------------------------------------------------------------
-- Pracownik edytuje swoją dyspozycyjność tylko w czasie zbierania;
-- Halina i Iza mogą zawsze.
grant select, insert, update, delete on public.availability to authenticated;

create policy availability_select on public.availability
  for select to authenticated
  using (employee_id = auth.uid() or public.is_manager());

create policy availability_write on public.availability
  for all to authenticated
  using (
    public.is_manager()
    or (employee_id = auth.uid() and public.current_app_role() is not null and public.is_month_collecting(date))
  )
  with check (
    public.is_manager()
    or (employee_id = auth.uid() and public.current_app_role() is not null and public.is_month_collecting(date))
  );

-- swap_requests ------------------------------------------------------------------
-- Tylko odczyt; wszystkie zmiany przez funkcje RPC.
grant select on public.swap_requests to authenticated;

create policy swap_requests_select on public.swap_requests
  for select to authenticated
  using (
    public.is_manager()
    or requester_id = auth.uid()
    or target_id = auth.uid()
    or accepted_by = auth.uid()
    or (
      target_id is null
      and status = 'open'
      and public.current_department() = (
        select e.department from public.employees e where e.id = swap_requests.requester_id
      )
    )
  );

-- notifications ------------------------------------------------------------------
grant select on public.notifications to authenticated;
grant update (read_at) on public.notifications to authenticated;

create policy notifications_select on public.notifications
  for select to authenticated
  using (employee_id = auth.uid());

create policy notifications_update on public.notifications
  for update to authenticated
  using (employee_id = auth.uid())
  with check (employee_id = auth.uid());

-- audit_log ----------------------------------------------------------------------
grant select on public.audit_log to authenticated;

create policy audit_log_select on public.audit_log
  for select to authenticated
  using (public.is_manager());
