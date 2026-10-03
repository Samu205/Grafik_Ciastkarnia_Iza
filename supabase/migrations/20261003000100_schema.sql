-- =============================================================================
-- Grafik Ciastkarnia Iza – schemat bazy
-- Reguły biznesowe: docs/ZASADY_DZIALANIA.md
-- Nazwy w bazie po angielsku, komunikaty dla użytkownika po polsku.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- Typy
-- -----------------------------------------------------------------------------
create type public.app_role as enum ('owner', 'scheduler', 'employee');
comment on type public.app_role is 'owner = Iza, scheduler = Halina, employee = pracownik';

create type public.department as enum ('sales', 'production');
comment on type public.department is 'Dział pracownika i typ grafiku: sprzedaż albo produkcja';

create type public.month_status as enum ('collecting', 'drafting', 'published');
comment on type public.month_status is 'collecting = zbieranie dyspozycyjności, drafting = układanie, published = opublikowany';

create type public.availability_kind as enum ('all_day', 'hours', 'unavailable');

create type public.swap_status as enum (
  'open',               -- czeka na chętnego / odpowiedź adresata
  'awaiting_requester', -- przejmujący zaproponował wymianę, autor musi ją potwierdzić
  'pending_approval',   -- czeka na decyzję Haliny (flaga zatwierdzania)
  'done',               -- wykonana
  'rejected',           -- odrzucona przez adresata albo Halinę
  'cancelled',          -- anulowana przez autora albo przez zmianę w grafiku
  'expired'             -- zmiana już się zaczęła
);

-- -----------------------------------------------------------------------------
-- Tabele
-- -----------------------------------------------------------------------------
create table public.employees (
  id                     uuid primary key references auth.users (id) on delete cascade,
  full_name              text not null check (length(btrim(full_name)) > 0),
  role                  public.app_role not null default 'employee',
  department             public.department not null,
  swaps_require_approval boolean not null default false,
  active                 boolean not null default true,
  created_at             timestamptz not null default now()
);
comment on table public.employees is
  'Wspólna lista pracowników (jedna dla wszystkich grafików). E-mail jest w auth.users – nie dublujemy go tutaj, żeby nie był widoczny dla współpracowników';
comment on column public.employees.swaps_require_approval is 'Zamiany tej osoby wymagają zatwierdzenia przez Halinę (np. nowa osoba)';

create table public.schedules (
  id          uuid primary key default gen_random_uuid(),
  name        text not null unique check (length(btrim(name)) > 0),
  type        public.department not null,
  archived_at timestamptz,
  created_at  timestamptz not null default now()
);
comment on table public.schedules is 'Grafiki (miejsca pracy): Liszki, Lodołamacz Piekary, Ogrody, Produkcja Liszki';
comment on column public.schedules.archived_at is 'Ustawione = grafik zarchiwizowany ("usunięty", ale do przywrócenia)';

create table public.shift_templates (
  id          uuid primary key default gen_random_uuid(),
  schedule_id uuid not null references public.schedules (id) on delete cascade,
  name        text not null check (length(btrim(name)) > 0),
  start_time  time not null,
  end_time    time not null,
  created_at  timestamptz not null default now(),
  constraint shift_template_hours_valid check (end_time > start_time),
  constraint shift_template_name_unique unique (schedule_id, name)
);
comment on table public.shift_templates is 'Stałe zmiany grafiku, np. "Ranna 6:00–14:00"';

create table public.schedule_months (
  id                    uuid primary key default gen_random_uuid(),
  month                 date not null unique check (extract(day from month) = 1),
  status                public.month_status not null default 'collecting',
  availability_deadline date,
  reminder_sent_at      timestamptz,
  published_at          timestamptz,
  created_at            timestamptz not null default now()
);
comment on table public.schedule_months is 'Miesięczny cykl grafiku; month = pierwszy dzień miesiąca';

create table public.shifts (
  id          uuid primary key default gen_random_uuid(),
  schedule_id uuid not null references public.schedules (id) on delete cascade,
  date        date not null,
  start_time  time not null,
  end_time    time not null,
  employee_id uuid references public.employees (id) on delete set null,
  template_id uuid references public.shift_templates (id) on delete set null,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  constraint shift_hours_valid check (end_time > start_time),
  -- Zasada nadrzędna: jedna osoba, jedna zmiana dziennie, we wszystkich grafikach.
  -- DEFERRABLE, żeby wymiana w ten sam dzień przeszła w jednej transakcji.
  -- Funkcje RPC sprawdzają kolizje jawnie wcześniej, żeby zwrócić czytelny komunikat;
  -- to ograniczenie jest ostatnią linią obrony.
  constraint one_shift_per_day unique (employee_id, date) deferrable initially deferred
);
comment on column public.shifts.employee_id is 'null = zmiana nieobsadzona';

create index shifts_schedule_date_idx on public.shifts (schedule_id, date);
create index shifts_date_idx on public.shifts (date);

create table public.availability (
  employee_id uuid not null references public.employees (id) on delete cascade,
  date        date not null,
  kind        public.availability_kind not null,
  start_time  time,
  end_time    time,
  updated_at  timestamptz not null default now(),
  primary key (employee_id, date),
  constraint availability_hours_valid check (
    (kind = 'hours' and start_time is not null and end_time is not null and end_time > start_time)
    or (kind <> 'hours' and start_time is null and end_time is null)
  )
);
comment on table public.availability is 'Dyspozycyjność: kiedy pracownik może pracować';

create table public.swap_requests (
  id                uuid primary key default gen_random_uuid(),
  requester_id      uuid not null references public.employees (id) on delete cascade,
  shift_id          uuid not null references public.shifts (id) on delete cascade,
  target_id         uuid references public.employees (id) on delete cascade,
  exchange_shift_id uuid references public.shifts (id) on delete cascade,
  accepted_by       uuid references public.employees (id) on delete set null,
  status            public.swap_status not null default 'open',
  decided_by        uuid references public.employees (id) on delete set null,
  created_at        timestamptz not null default now(),
  resolved_at       timestamptz,
  alerted_at        timestamptz,
  constraint swap_target_not_requester check (target_id is null or target_id <> requester_id),
  constraint swap_exchange_not_same check (exchange_shift_id is null or exchange_shift_id <> shift_id)
);
comment on table public.swap_requests is
  'Prośby o zamianę. target_id null = do wszystkich. exchange_shift_id null = oddanie, ustawione = wymiana';

-- Na jedną zmianę może być tylko jedna aktywna prośba.
create unique index swap_requests_one_active_per_shift
  on public.swap_requests (shift_id)
  where status in ('open', 'awaiting_requester', 'pending_approval');

create index swap_requests_status_idx on public.swap_requests (status);

create table public.notifications (
  id          uuid primary key default gen_random_uuid(),
  employee_id uuid not null references public.employees (id) on delete cascade,
  kind        text not null,
  message     text not null,
  payload     jsonb not null default '{}'::jsonb,
  created_at  timestamptz not null default now(),
  read_at     timestamptz,
  emailed_at  timestamptz
);
comment on table public.notifications is
  'Skrzynka powiadomień. Edge Function wysyła e-maile dla wierszy z emailed_at = null';

create index notifications_employee_idx on public.notifications (employee_id, created_at desc);
create index notifications_unsent_idx on public.notifications (created_at) where emailed_at is null;

create table public.audit_log (
  id         bigint generated always as identity primary key,
  actor_id   uuid,
  action     text not null,
  payload    jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);
comment on table public.audit_log is 'Historia zmian w grafiku: kto, co, kiedy';

-- -----------------------------------------------------------------------------
-- Funkcje pomocnicze
-- -----------------------------------------------------------------------------

-- Rola zalogowanego, aktywnego pracownika (null, gdy brak konta lub nieaktywny).
create function public.current_app_role()
returns public.app_role
language sql stable security definer
set search_path = public
as $$
  select role from public.employees where id = auth.uid() and active
$$;

create function public.is_manager()
returns boolean
language sql stable security definer
set search_path = public
as $$
  select coalesce(public.current_app_role() in ('owner', 'scheduler'), false)
$$;
comment on function public.is_manager() is 'Iza albo Halina';

create function public.is_owner()
returns boolean
language sql stable security definer
set search_path = public
as $$
  select coalesce(public.current_app_role() = 'owner', false)
$$;

create function public.month_start(d date)
returns date
language sql immutable
as $$
  select date_trunc('month', d)::date
$$;

create function public.is_month_published(d date)
returns boolean
language sql stable security definer
set search_path = public
as $$
  select exists (
    select 1 from public.schedule_months
    where month = public.month_start(d) and status = 'published'
  )
$$;

-- Moment rozpoczęcia zmiany w strefie czasowej ciastkarni.
create function public.shift_starts_at(d date, t time)
returns timestamptz
language sql immutable
as $$
  select (d + t) at time zone 'Europe/Warsaw'
$$;

-- "14.10.2026 (wtorek)"
create function public.pl_date(d date)
returns text
language sql immutable
as $$
  select to_char(d, 'DD.MM.YYYY') || ' (' ||
    (array['poniedziałek', 'wtorek', 'środa', 'czwartek', 'piątek', 'sobota', 'niedziela'])
      [extract(isodow from d)::int] || ')'
$$;

-- "10:00–14:00"
create function public.pl_hours(s time, e time)
returns text
language sql immutable
as $$
  select to_char(s, 'HH24:MI') || '–' || to_char(e, 'HH24:MI')
$$;

-- -----------------------------------------------------------------------------
-- Triggery spójności
-- -----------------------------------------------------------------------------

create function public.touch_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

create trigger shifts_touch_updated_at
  before update on public.shifts
  for each row execute function public.touch_updated_at();

create trigger availability_touch_updated_at
  before update on public.availability
  for each row execute function public.touch_updated_at();

-- Pracownik może być przypisany tylko do grafiku swojego działu
-- i tylko do grafiku, który nie jest zarchiwizowany.
create function public.check_shift_assignment()
returns trigger
language plpgsql
set search_path = public
as $$
declare
  v_schedule public.schedules%rowtype;
  v_employee public.employees%rowtype;
begin
  if new.employee_id is null then
    return new;
  end if;

  if tg_op = 'UPDATE' and new.employee_id is not distinct from old.employee_id
     and new.schedule_id = old.schedule_id then
    return new;
  end if;

  select * into v_schedule from public.schedules where id = new.schedule_id;
  select * into v_employee from public.employees where id = new.employee_id;

  if v_schedule.archived_at is not null then
    raise exception 'Grafik "%" jest zarchiwizowany – nie można do niego przypisywać osób.', v_schedule.name;
  end if;

  if v_employee.department <> v_schedule.type then
    raise exception '% pracuje w dziale "%", a grafik "%" jest typu "%".',
      v_employee.full_name,
      case v_employee.department when 'sales' then 'sprzedaż' else 'produkcja' end,
      v_schedule.name,
      case v_schedule.type when 'sales' then 'sprzedaż' else 'produkcja' end;
  end if;

  if not v_employee.active then
    raise exception '% jest nieaktywny/a – nie można przypisać zmiany.', v_employee.full_name;
  end if;

  return new;
end;
$$;

create trigger shifts_check_assignment
  before insert or update of employee_id, schedule_id on public.shifts
  for each row execute function public.check_shift_assignment();

-- Szablon zmiany musi należeć do tego samego grafiku co zmiana.
create function public.check_shift_template()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if new.template_id is not null and not exists (
    select 1 from public.shift_templates
    where id = new.template_id and schedule_id = new.schedule_id
  ) then
    raise exception 'Szablon zmiany należy do innego grafiku.';
  end if;
  return new;
end;
$$;

create trigger shifts_check_template
  before insert or update of template_id, schedule_id on public.shifts
  for each row execute function public.check_shift_template();

-- Nie zmieniamy typu grafiku, jeśli są do niego przypisane osoby.
create function public.check_schedule_type_change()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if new.type <> old.type and exists (
    select 1 from public.shifts where schedule_id = new.id and employee_id is not null
  ) then
    raise exception 'Nie można zmienić typu grafiku "%", bo są w nim przypisane osoby.', old.name;
  end if;
  return new;
end;
$$;

create trigger schedules_check_type_change
  before update of type on public.schedules
  for each row execute function public.check_schedule_type_change();

-- Opublikowanego miesiąca nie cofamy do wersji roboczej.
create function public.check_month_status_change()
returns trigger
language plpgsql
as $$
begin
  if old.status = 'published' and new.status <> 'published' then
    raise exception 'Opublikowanego grafiku nie można cofnąć do wersji roboczej.';
  end if;
  if new.status = 'published' and old.status <> 'published' then
    new.published_at := now();
  end if;
  return new;
end;
$$;

create trigger schedule_months_check_status
  before update of status on public.schedule_months
  for each row execute function public.check_month_status_change();
