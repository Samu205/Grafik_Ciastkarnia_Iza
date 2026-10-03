-- =============================================================================
-- Układanie grafiku: przypisania, grafiki, miesiące, powiadomienia, historia
--
-- Funkcje wewnętrzne są w schemacie `app_private`, którego API (PostgREST)
-- nie wystawia – pracownik nie może ich wywołać bezpośrednio.
-- Funkcje w `public` to RPC dla aplikacji; same sprawdzają uprawnienia.
-- =============================================================================

create schema app_private;
revoke all on schema app_private from public, anon, authenticated;

-- -----------------------------------------------------------------------------
-- Formatowanie
-- -----------------------------------------------------------------------------

-- "listopad 2026"
create function public.pl_month(d date)
returns text
language sql immutable
as $$
  select (array['styczeń', 'luty', 'marzec', 'kwiecień', 'maj', 'czerwiec', 'lipiec',
                'sierpień', 'wrzesień', 'październik', 'listopad', 'grudzień'])
           [extract(month from d)::int] || ' ' || extract(year from d)::int
$$;

-- "Ogrody, 14.10.2026 (środa), 10:00–14:00"
create function app_private.shift_label(p_shift_id uuid)
returns text
language sql stable
set search_path = public
as $$
  select sc.name || ', ' || public.pl_date(s.date) || ', ' || public.pl_hours(s.start_time, s.end_time)
  from public.shifts s
  join public.schedules sc on sc.id = s.schedule_id
  where s.id = p_shift_id
$$;

-- -----------------------------------------------------------------------------
-- Powiadomienia i historia
-- -----------------------------------------------------------------------------

create function app_private.notify(
  p_employee_id uuid,
  p_kind text,
  p_message text,
  p_payload jsonb default '{}'::jsonb
)
returns void
language sql
set search_path = public
as $$
  insert into public.notifications (employee_id, kind, message, payload)
  select p_employee_id, p_kind, p_message, p_payload
  where p_employee_id is not null
$$;

-- Powiadomienie dla Haliny (rola scheduler); gdy jej nie ma – dla Izy.
create function app_private.notify_managers(
  p_kind text,
  p_message text,
  p_payload jsonb default '{}'::jsonb
)
returns void
language plpgsql
set search_path = public
as $$
begin
  insert into public.notifications (employee_id, kind, message, payload)
  select id, p_kind, p_message, p_payload
  from public.employees
  where active and role = 'scheduler';

  if not found then
    insert into public.notifications (employee_id, kind, message, payload)
    select id, p_kind, p_message, p_payload
    from public.employees
    where active and role = 'owner';
  end if;
end;
$$;

create function app_private.log_action(p_action text, p_payload jsonb default '{}'::jsonb)
returns void
language sql
set search_path = public
as $$
  insert into public.audit_log (actor_id, action, payload)
  values (auth.uid(), p_action, p_payload)
$$;

-- -----------------------------------------------------------------------------
-- Kolizje: jedna osoba, jedna zmiana dziennie
-- -----------------------------------------------------------------------------

-- Zwraca komunikat o kolizji albo null, gdy pracownik nie ma innej zmiany tego dnia.
-- p_exclude = zmiany, których nie liczymy (np. ta, którą oddaje przy wymianie).
create function app_private.collision_message(
  p_employee_id uuid,
  p_date date,
  p_exclude uuid[] default '{}'
)
returns text
language sql stable
set search_path = public
as $$
  select e.full_name || ' ma już zmianę ' || public.pl_date(s.date) || ' – ' || sc.name || ', '
         || public.pl_hours(s.start_time, s.end_time)
  from public.shifts s
  join public.schedules sc on sc.id = s.schedule_id
  join public.employees e on e.id = s.employee_id
  where s.employee_id = p_employee_id
    and s.date = p_date
    and s.id <> all (coalesce(p_exclude, '{}'))
  limit 1
$$;

-- Ostrzeżenie, gdy przypisanie jest poza dyspozycyjnością (null = wszystko w porządku).
create function app_private.availability_warning(p_employee_id uuid, p_shift_id uuid)
returns text
language plpgsql stable
set search_path = public
as $$
declare
  v_shift public.shifts%rowtype;
  v_av public.availability%rowtype;
  v_name text;
begin
  select * into v_shift from public.shifts where id = p_shift_id;
  select full_name into v_name from public.employees where id = p_employee_id;
  select * into v_av from public.availability
    where employee_id = p_employee_id and date = v_shift.date;

  if not found then
    return v_name || ' nie podał(a) dyspozycyjności na ' || public.pl_date(v_shift.date) || '.';
  end if;

  if v_av.kind = 'unavailable' then
    return v_name || ' zaznaczył(a), że nie może pracować ' || public.pl_date(v_shift.date) || '.';
  end if;

  if v_av.kind = 'hours'
     and (v_shift.start_time < v_av.start_time or v_shift.end_time > v_av.end_time) then
    return v_name || ' może pracować ' || public.pl_date(v_shift.date) || ' tylko w godzinach '
      || public.pl_hours(v_av.start_time, v_av.end_time) || '.';
  end if;

  return null;
end;
$$;

-- Anuluje aktywne prośby o zamianę dotyczące danej zmiany (np. po zmianie przez Halinę).
create function app_private.cancel_requests_for_shift(p_shift_id uuid, p_reason text)
returns void
language plpgsql
set search_path = public
as $$
declare
  r public.swap_requests%rowtype;
begin
  for r in
    update public.swap_requests
      set status = 'cancelled', resolved_at = now()
    where status in ('open', 'awaiting_requester', 'pending_approval')
      and (shift_id = p_shift_id or exchange_shift_id = p_shift_id)
    returning *
  loop
    perform app_private.notify(r.requester_id, 'swap_cancelled',
      'Prośba o zamianę zmiany ' || app_private.shift_label(r.shift_id) || ' została anulowana: ' || p_reason,
      jsonb_build_object('swap_request_id', r.id));
    perform app_private.notify(r.accepted_by, 'swap_cancelled',
      'Prośba o zamianę zmiany ' || app_private.shift_label(r.shift_id) || ' została anulowana: ' || p_reason,
      jsonb_build_object('swap_request_id', r.id));
  end loop;
end;
$$;

-- -----------------------------------------------------------------------------
-- RPC: przypisanie osoby do zmiany (Halina, Iza)
-- -----------------------------------------------------------------------------

-- Przypisuje pracownika do zmiany (p_employee_id = null zdejmuje przypisanie).
-- Kolizja = błąd z podaniem grafiku, daty i godzin.
-- Poza dyspozycyjnością = przypisuje i zwraca {"warning": "..."}.
create function public.assign_shift(p_shift_id uuid, p_employee_id uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_shift public.shifts%rowtype;
  v_collision text;
  v_warning text;
  v_published boolean;
begin
  if not public.is_manager() then
    raise exception 'Tylko Halina albo Iza mogą przypisywać zmiany.';
  end if;

  select * into v_shift from public.shifts where id = p_shift_id for update;
  if not found then
    raise exception 'Zmiana nie istnieje.';
  end if;

  if v_shift.employee_id is not distinct from p_employee_id then
    return jsonb_build_object('warning', null, 'changed', false);
  end if;

  if p_employee_id is not null then
    if not exists (select 1 from public.employees where id = p_employee_id and active) then
      raise exception 'Wybrana osoba nie jest aktywnym pracownikiem.';
    end if;

    v_collision := app_private.collision_message(p_employee_id, v_shift.date, array[v_shift.id]);
    if v_collision is not null then
      raise exception '%', v_collision;
    end if;

    v_warning := app_private.availability_warning(p_employee_id, v_shift.id);
  end if;

  update public.shifts set employee_id = p_employee_id where id = p_shift_id;

  perform app_private.cancel_requests_for_shift(p_shift_id, 'Halina zmieniła obsadę tej zmiany.');

  v_published := public.is_month_published(v_shift.date);
  if v_published then
    perform app_private.notify(v_shift.employee_id, 'shift_removed',
      'Zdjęto Cię ze zmiany: ' || app_private.shift_label(p_shift_id),
      jsonb_build_object('shift_id', p_shift_id));
    perform app_private.notify(p_employee_id, 'shift_assigned',
      'Masz nową zmianę: ' || app_private.shift_label(p_shift_id),
      jsonb_build_object('shift_id', p_shift_id));
  end if;

  perform app_private.log_action('assign_shift', jsonb_build_object(
    'shift_id', p_shift_id,
    'from', v_shift.employee_id,
    'to', p_employee_id,
    'warning', v_warning
  ));

  return jsonb_build_object('warning', v_warning, 'changed', true);
end;
$$;

-- Zmiana godzin opublikowanej, obsadzonej zmiany → powiadomienie dla pracownika.
create function app_private.on_shift_hours_changed()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if (new.start_time, new.end_time) is distinct from (old.start_time, old.end_time)
     and new.employee_id is not null
     and public.is_month_published(new.date) then
    perform app_private.notify(new.employee_id, 'shift_changed',
      'Zmieniły się godziny Twojej zmiany: ' || app_private.shift_label(new.id),
      jsonb_build_object('shift_id', new.id));
    perform app_private.log_action('shift_hours_changed', jsonb_build_object(
      'shift_id', new.id,
      'from', public.pl_hours(old.start_time, old.end_time),
      'to', public.pl_hours(new.start_time, new.end_time)
    ));
  end if;
  return new;
end;
$$;

create trigger shifts_hours_changed
  after update of start_time, end_time on public.shifts
  for each row execute function app_private.on_shift_hours_changed();

-- -----------------------------------------------------------------------------
-- RPC: grafiki – archiwizacja, przywracanie, trwałe usunięcie (Iza)
-- -----------------------------------------------------------------------------

create function public.archive_schedule(p_schedule_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_name text;
  v_shift_id uuid;
begin
  if not public.is_owner() then
    raise exception 'Tylko Iza może archiwizować grafiki.';
  end if;

  update public.schedules set archived_at = now()
  where id = p_schedule_id and archived_at is null
  returning name into v_name;

  if v_name is null then
    raise exception 'Grafik nie istnieje albo jest już zarchiwizowany.';
  end if;

  for v_shift_id in select id from public.shifts where schedule_id = p_schedule_id loop
    perform app_private.cancel_requests_for_shift(v_shift_id, 'grafik "' || v_name || '" został zarchiwizowany.');
  end loop;

  perform app_private.log_action('archive_schedule', jsonb_build_object('schedule_id', p_schedule_id, 'name', v_name));
end;
$$;

create function public.restore_schedule(p_schedule_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_name text;
begin
  if not public.is_owner() then
    raise exception 'Tylko Iza może przywracać grafiki.';
  end if;

  update public.schedules set archived_at = null
  where id = p_schedule_id and archived_at is not null
  returning name into v_name;

  if v_name is null then
    raise exception 'Grafik nie istnieje albo nie jest zarchiwizowany.';
  end if;

  perform app_private.log_action('restore_schedule', jsonb_build_object('schedule_id', p_schedule_id, 'name', v_name));
end;
$$;

-- Trwałe usunięcie: tylko zarchiwizowany grafik i tylko po wpisaniu jego dokładnej nazwy.
create function public.delete_schedule(p_schedule_id uuid, p_confirm_name text)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_schedule public.schedules%rowtype;
begin
  if not public.is_owner() then
    raise exception 'Tylko Iza może usuwać grafiki.';
  end if;

  select * into v_schedule from public.schedules where id = p_schedule_id for update;
  if not found then
    raise exception 'Grafik nie istnieje.';
  end if;

  if v_schedule.archived_at is null then
    raise exception 'Najpierw zarchiwizuj grafik "%". Trwale usunąć można tylko zarchiwizowany grafik.', v_schedule.name;
  end if;

  if p_confirm_name is distinct from v_schedule.name then
    raise exception 'Wpisana nazwa nie zgadza się z nazwą grafiku "%". Nic nie zostało usunięte.', v_schedule.name;
  end if;

  delete from public.schedules where id = p_schedule_id;

  perform app_private.log_action('delete_schedule', jsonb_build_object('schedule_id', p_schedule_id, 'name', v_schedule.name));
end;
$$;

-- -----------------------------------------------------------------------------
-- Miesięczny cykl: otwarcie zbierania, publikacja, przypomnienia
-- -----------------------------------------------------------------------------

create function app_private.on_month_created()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.status = 'collecting' then
    insert into public.notifications (employee_id, kind, message, payload)
    select e.id, 'availability_open',
      'Zbieramy dyspozycyjność na ' || public.pl_month(new.month)
        || coalesce('. Termin: ' || to_char(new.availability_deadline, 'DD.MM.YYYY'), '') || '.',
      jsonb_build_object('month', new.month)
    from public.employees e
    where e.active;
  end if;

  perform app_private.log_action('month_created', jsonb_build_object('month', new.month, 'status', new.status));
  return new;
end;
$$;

create trigger schedule_months_created
  after insert on public.schedule_months
  for each row execute function app_private.on_month_created();

create function app_private.on_month_status_changed()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.status = 'published' and old.status <> 'published' then
    insert into public.notifications (employee_id, kind, message, payload)
    select e.id, 'month_published',
      'Grafik na ' || public.pl_month(new.month) || ' jest opublikowany.',
      jsonb_build_object('month', new.month)
    from public.employees e
    where e.active;
  end if;

  perform app_private.log_action('month_status_changed',
    jsonb_build_object('month', new.month, 'from', old.status, 'to', new.status));
  return new;
end;
$$;

create trigger schedule_months_status_changed
  after update of status on public.schedule_months
  for each row
  when (old.status is distinct from new.status)
  execute function app_private.on_month_status_changed();

-- Publikacja miesiąca (wygodny skrót dla aplikacji).
create function public.publish_month(p_month date)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_manager() then
    raise exception 'Tylko Halina albo Iza mogą publikować grafik.';
  end if;

  update public.schedule_months set status = 'published'
  where month = public.month_start(p_month) and status <> 'published';

  if not found then
    raise exception 'Miesiąc % nie istnieje albo jest już opublikowany.', public.pl_month(p_month);
  end if;
end;
$$;

-- Zadanie cykliczne: przypomnienie o dyspozycyjności na 2 dni przed terminem
-- dla osób, które nie wpisały nic na dany miesiąc.
create function app_private.send_availability_reminders(p_now timestamptz default now())
returns integer
language plpgsql
set search_path = public
as $$
declare
  m public.schedule_months%rowtype;
  v_count integer := 0;
  v_rows integer;
  v_today date := (p_now at time zone 'Europe/Warsaw')::date;
begin
  for m in
    select * from public.schedule_months
    where status = 'collecting'
      and reminder_sent_at is null
      and availability_deadline is not null
      and availability_deadline - 2 <= v_today
    for update
  loop
    insert into public.notifications (employee_id, kind, message, payload)
    select e.id, 'availability_reminder',
      'Przypomnienie: wpisz dyspozycyjność na ' || public.pl_month(m.month)
        || ' do ' || to_char(m.availability_deadline, 'DD.MM.YYYY') || '.',
      jsonb_build_object('month', m.month)
    from public.employees e
    where e.active
      and not exists (
        select 1 from public.availability a
        where a.employee_id = e.id
          and a.date >= m.month
          and a.date < (m.month + interval '1 month')::date
      );
    get diagnostics v_rows = row_count;
    v_count := v_count + v_rows;

    update public.schedule_months set reminder_sent_at = p_now where id = m.id;
  end loop;

  return v_count;
end;
$$;
