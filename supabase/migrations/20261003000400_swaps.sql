-- =============================================================================
-- Zamiany i oddawanie zmian
-- Reguły: docs/ZASADY_DZIALANIA.md §7
--
--  * Zamiana tylko w obrębie działu (sprzedaż ↔ sprzedaż, produkcja ↔ produkcja).
--  * Kolizje liczymy na stanie PO zamianie (wymiana w ten sam dzień jest OK).
--  * Flaga swaps_require_approval u którejkolwiek strony → decyduje Halina.
--  * "Kto pierwszy, ten bierze": prośba jest blokowana (FOR UPDATE) przy przyjęciu.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- Sprawdzenie reguł
-- -----------------------------------------------------------------------------

-- Czy zmiana nadaje się do zamiany (opublikowana i jeszcze się nie zaczęła)?
create function app_private.shift_swap_problem(p_shift public.shifts, p_now timestamptz)
returns text
language plpgsql stable
set search_path = public
as $$
begin
  if not public.is_month_published(p_shift.date) then
    return 'Grafik na ' || public.pl_month(p_shift.date) || ' nie jest jeszcze opublikowany.';
  end if;
  if public.shift_starts_at(p_shift.date, p_shift.start_time) <= p_now then
    return 'Zmiana ' || app_private.shift_label(p_shift.id) || ' już się rozpoczęła.';
  end if;
  return null;
end;
$$;

-- Zwraca powód, dla którego p_taker nie może przejąć zmiany p_shift_id
-- (oddanie, gdy p_exchange_shift_id = null; wymiana, gdy podana), albo null.
create function app_private.swap_problem(
  p_shift_id uuid,
  p_taker_id uuid,
  p_exchange_shift_id uuid,
  p_now timestamptz default now()
)
returns text
language plpgsql stable
set search_path = public
as $$
declare
  v_shift public.shifts%rowtype;
  v_exchange public.shifts%rowtype;
  v_requester public.employees%rowtype;
  v_taker public.employees%rowtype;
  v_problem text;
begin
  select * into v_shift from public.shifts where id = p_shift_id;
  if not found then
    return 'Zmiana nie istnieje.';
  end if;
  if v_shift.employee_id is null then
    return 'Ta zmiana nie jest nikomu przypisana.';
  end if;

  select * into v_requester from public.employees where id = v_shift.employee_id;
  select * into v_taker from public.employees where id = p_taker_id;

  if not found or not v_taker.active then
    return 'Wybrana osoba nie jest aktywnym pracownikiem.';
  end if;
  if v_taker.id = v_requester.id then
    return 'Nie można zamienić się z samym sobą.';
  end if;
  if v_taker.department <> v_requester.department then
    return v_requester.full_name || ' i ' || v_taker.full_name
      || ' pracują w różnych działach – zamiany są możliwe tylko w obrębie sprzedaży albo produkcji.';
  end if;

  v_problem := app_private.shift_swap_problem(v_shift, p_now);
  if v_problem is not null then
    return v_problem;
  end if;

  if p_exchange_shift_id is not null then
    select * into v_exchange from public.shifts where id = p_exchange_shift_id;
    if not found then
      return 'Zmiana proponowana do wymiany nie istnieje.';
    end if;
    if v_exchange.employee_id is distinct from v_taker.id then
      return 'Zmiana proponowana do wymiany nie należy do ' || v_taker.full_name || '.';
    end if;
    v_problem := app_private.shift_swap_problem(v_exchange, p_now);
    if v_problem is not null then
      return v_problem;
    end if;
  end if;

  -- Stan PO zamianie: przejmujący dostaje dzień v_shift.date (oddaje ewentualnie v_exchange).
  v_problem := app_private.collision_message(
    v_taker.id, v_shift.date, array_remove(array[p_exchange_shift_id], null));
  if v_problem is not null then
    return 'Po zamianie ' || v_taker.full_name || ' miał(a)by dwie zmiany jednego dnia. ' || v_problem || '.';
  end if;

  -- Autor dostaje dzień v_exchange.date (oddaje v_shift).
  if p_exchange_shift_id is not null then
    v_problem := app_private.collision_message(v_requester.id, v_exchange.date, array[v_shift.id]);
    if v_problem is not null then
      return 'Po zamianie ' || v_requester.full_name || ' miał(a)by dwie zmiany jednego dnia. ' || v_problem || '.';
    end if;
  end if;

  return null;
end;
$$;

-- Wykonuje zamianę (zakłada, że wiersz prośby jest już zablokowany FOR UPDATE).
create function app_private.execute_swap(p_request_id uuid)
returns void
language plpgsql
set search_path = public
as $$
declare
  r public.swap_requests%rowtype;
  v_problem text;
  v_label text;
  v_exchange_label text;
begin
  select * into r from public.swap_requests where id = p_request_id;

  -- Blokujemy obie zmiany, żeby nikt ich w międzyczasie nie przestawił.
  perform 1 from public.shifts
    where id in (r.shift_id, r.exchange_shift_id) order by id for update;

  if not exists (select 1 from public.shifts where id = r.shift_id and employee_id = r.requester_id) then
    raise exception 'Zmiana nie należy już do autora prośby – grafik zmienił się w międzyczasie.';
  end if;

  v_problem := app_private.swap_problem(r.shift_id, r.accepted_by, r.exchange_shift_id);
  if v_problem is not null then
    raise exception '%', v_problem;
  end if;

  v_label := app_private.shift_label(r.shift_id);
  v_exchange_label := app_private.shift_label(r.exchange_shift_id);

  update public.shifts set employee_id = r.accepted_by where id = r.shift_id;
  if r.exchange_shift_id is not null then
    update public.shifts set employee_id = r.requester_id where id = r.exchange_shift_id;
  end if;

  update public.swap_requests
    set status = 'done', resolved_at = now()
  where id = r.id;

  -- Inne aktywne prośby dotyczące tych zmian tracą sens.
  update public.swap_requests
    set status = 'cancelled', resolved_at = now()
  where id <> r.id
    and status in ('open', 'awaiting_requester', 'pending_approval')
    and (shift_id in (r.shift_id, r.exchange_shift_id)
         or exchange_shift_id in (r.shift_id, r.exchange_shift_id));

  if r.exchange_shift_id is null then
    perform app_private.notify(r.requester_id, 'swap_done',
      'Oddałeś/aś zmianę ' || v_label || '.', jsonb_build_object('swap_request_id', r.id));
    perform app_private.notify(r.accepted_by, 'swap_done',
      'Przejąłeś/ęłaś zmianę ' || v_label || '.', jsonb_build_object('swap_request_id', r.id));
    perform app_private.notify_managers('swap_done',
      (select full_name from public.employees where id = r.accepted_by) || ' przejmuje od '
        || (select full_name from public.employees where id = r.requester_id) || ' zmianę ' || v_label || '.',
      jsonb_build_object('swap_request_id', r.id));
  else
    perform app_private.notify(r.requester_id, 'swap_done',
      'Wymiana wykonana: oddajesz ' || v_label || ', bierzesz ' || v_exchange_label || '.',
      jsonb_build_object('swap_request_id', r.id));
    perform app_private.notify(r.accepted_by, 'swap_done',
      'Wymiana wykonana: oddajesz ' || v_exchange_label || ', bierzesz ' || v_label || '.',
      jsonb_build_object('swap_request_id', r.id));
    perform app_private.notify_managers('swap_done',
      'Wymiana: ' || (select full_name from public.employees where id = r.requester_id) || ' bierze '
        || v_exchange_label || ', ' || (select full_name from public.employees where id = r.accepted_by)
        || ' bierze ' || v_label || '.',
      jsonb_build_object('swap_request_id', r.id));
  end if;

  perform app_private.log_action('swap_done', jsonb_build_object(
    'swap_request_id', r.id,
    'shift_id', r.shift_id,
    'exchange_shift_id', r.exchange_shift_id,
    'requester_id', r.requester_id,
    'taker_id', r.accepted_by
  ));
end;
$$;

-- Po uzgodnieniu stron: albo do zatwierdzenia przez Halinę, albo od razu wykonanie.
create function app_private.finalize_agreed_swap(p_request_id uuid)
returns public.swap_status
language plpgsql
set search_path = public
as $$
declare
  r public.swap_requests%rowtype;
  v_needs_approval boolean;
begin
  select * into r from public.swap_requests where id = p_request_id;

  select bool_or(swaps_require_approval) into v_needs_approval
  from public.employees where id in (r.requester_id, r.accepted_by);

  if v_needs_approval then
    update public.swap_requests set status = 'pending_approval' where id = r.id;
    perform app_private.notify_managers('swap_pending_approval',
      'Zamiana czeka na Twoje zatwierdzenie: '
        || (select full_name from public.employees where id = r.requester_id) || ' → '
        || (select full_name from public.employees where id = r.accepted_by) || ', '
        || app_private.shift_label(r.shift_id)
        || coalesce(' (w zamian: ' || app_private.shift_label(r.exchange_shift_id) || ')', '') || '.',
      jsonb_build_object('swap_request_id', r.id));
    perform app_private.notify(r.requester_id, 'swap_pending_approval',
      'Zamiana zmiany ' || app_private.shift_label(r.shift_id) || ' czeka na zatwierdzenie przez Halinę.',
      jsonb_build_object('swap_request_id', r.id));
    perform app_private.notify(r.accepted_by, 'swap_pending_approval',
      'Zamiana zmiany ' || app_private.shift_label(r.shift_id) || ' czeka na zatwierdzenie przez Halinę.',
      jsonb_build_object('swap_request_id', r.id));
    return 'pending_approval';
  end if;

  perform app_private.execute_swap(r.id);
  return 'done';
end;
$$;

-- -----------------------------------------------------------------------------
-- RPC dla aplikacji
-- -----------------------------------------------------------------------------

-- Do podpowiedzi w UI: dlaczego p_taker nie może przejąć zmiany (null = może).
create function public.swap_problem(p_shift_id uuid, p_taker_id uuid, p_exchange_shift_id uuid default null)
returns text
language plpgsql stable
security definer
set search_path = public
as $$
begin
  if public.current_app_role() is null then
    raise exception 'Brak uprawnień.';
  end if;
  return app_private.swap_problem(p_shift_id, p_taker_id, p_exchange_shift_id);
end;
$$;

-- Osoby, które mogą przejąć zmianę bez wymiany (lista do prośby "do konkretnej osoby").
create function public.eligible_takers(p_shift_id uuid)
returns table (employee_id uuid, full_name text, declared_available boolean)
language plpgsql stable
security definer
set search_path = public
as $$
declare
  v_shift public.shifts%rowtype;
begin
  select * into v_shift from public.shifts where id = p_shift_id;
  if not found then
    raise exception 'Zmiana nie istnieje.';
  end if;
  if v_shift.employee_id is distinct from auth.uid() and not public.is_manager() then
    raise exception 'To nie jest Twoja zmiana.';
  end if;

  return query
    select e.id, e.full_name,
      exists (
        select 1 from public.availability a
        where a.employee_id = e.id and a.date = v_shift.date and a.kind <> 'unavailable'
      )
    from public.employees e
    where app_private.swap_problem(p_shift_id, e.id, null) is null
    order by 3 desc, e.full_name;
end;
$$;

-- Tworzy prośbę. p_target_id = null → do wszystkich ("giełda").
-- p_exchange_shift_id = konkretna zmiana adresata, którą autor chce wziąć w zamian.
create function public.create_swap_request(
  p_shift_id uuid,
  p_target_id uuid default null,
  p_exchange_shift_id uuid default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_shift public.shifts%rowtype;
  v_problem text;
  v_id uuid;
  v_requester_name text;
  v_taker record;
begin
  if public.current_app_role() is null then
    raise exception 'Brak uprawnień.';
  end if;

  select * into v_shift from public.shifts where id = p_shift_id for update;
  if not found then
    raise exception 'Zmiana nie istnieje.';
  end if;
  if v_shift.employee_id is distinct from v_uid then
    raise exception 'To nie jest Twoja zmiana.';
  end if;

  if p_target_id is null and p_exchange_shift_id is not null then
    raise exception 'Konkretną zmianę do wymiany można zaproponować tylko konkretnej osobie.';
  end if;

  if exists (
    select 1 from public.swap_requests
    where shift_id = p_shift_id and status in ('open', 'awaiting_requester', 'pending_approval')
  ) then
    raise exception 'Na tę zmianę jest już aktywna prośba o zamianę.';
  end if;

  if p_target_id is not null then
    v_problem := app_private.swap_problem(p_shift_id, p_target_id, p_exchange_shift_id);
  else
    v_problem := app_private.shift_swap_problem(v_shift, now());
  end if;
  if v_problem is not null then
    raise exception '%', v_problem;
  end if;

  insert into public.swap_requests (requester_id, shift_id, target_id, exchange_shift_id)
  values (v_uid, p_shift_id, p_target_id, p_exchange_shift_id)
  returning id into v_id;

  select full_name into v_requester_name from public.employees where id = v_uid;

  if p_target_id is not null then
    perform app_private.notify(p_target_id, 'swap_request',
      v_requester_name || ' prosi Cię o '
        || case when p_exchange_shift_id is null then 'przejęcie zmiany ' else 'wymianę: '
           || 'dostajesz ' end
        || app_private.shift_label(p_shift_id)
        || coalesce(', w zamian oddajesz ' || app_private.shift_label(p_exchange_shift_id), '') || '.',
      jsonb_build_object('swap_request_id', v_id));
  else
    for v_taker in select employee_id from public.eligible_takers(p_shift_id) loop
      perform app_private.notify(v_taker.employee_id, 'swap_request',
        v_requester_name || ' szuka zastępstwa: ' || app_private.shift_label(p_shift_id) || '.',
        jsonb_build_object('swap_request_id', v_id));
    end loop;
  end if;

  perform app_private.log_action('swap_requested', jsonb_build_object(
    'swap_request_id', v_id, 'shift_id', p_shift_id, 'target_id', p_target_id,
    'exchange_shift_id', p_exchange_shift_id));

  return v_id;
end;
$$;

-- Przyjęcie prośby. Kto pierwszy, ten bierze.
-- p_exchange_shift_id = zmiana przejmującego oferowana w zamian (opcjonalnie);
-- taka propozycja wymaga potwierdzenia przez autora prośby.
create function public.accept_swap_request(p_request_id uuid, p_exchange_shift_id uuid default null)
returns public.swap_status
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  r public.swap_requests%rowtype;
  v_exchange uuid;
  v_problem text;
begin
  if public.current_app_role() is null then
    raise exception 'Brak uprawnień.';
  end if;

  select * into r from public.swap_requests where id = p_request_id for update;
  if not found then
    raise exception 'Prośba nie istnieje.';
  end if;
  if r.status <> 'open' then
    raise exception 'Ta prośba jest już nieaktualna – ktoś ją przyjął albo została zamknięta.';
  end if;
  if r.requester_id = v_uid then
    raise exception 'Nie możesz przyjąć własnej prośby.';
  end if;
  if r.target_id is not null and r.target_id <> v_uid then
    raise exception 'Ta prośba nie jest skierowana do Ciebie.';
  end if;

  if r.exchange_shift_id is not null then
    if p_exchange_shift_id is not null and p_exchange_shift_id <> r.exchange_shift_id then
      raise exception 'Autor prośby zaproponował konkretną zmianę do wymiany.';
    end if;
    v_exchange := r.exchange_shift_id;
  else
    v_exchange := p_exchange_shift_id;
  end if;

  v_problem := app_private.swap_problem(r.shift_id, v_uid, v_exchange);
  if v_problem is not null then
    raise exception '%', v_problem;
  end if;

  update public.swap_requests
    set accepted_by = v_uid, exchange_shift_id = v_exchange
  where id = r.id;

  -- Przejmujący sam zaproponował wymianę → autor musi ją potwierdzić.
  if r.exchange_shift_id is null and v_exchange is not null then
    update public.swap_requests set status = 'awaiting_requester' where id = r.id;
    perform app_private.notify(r.requester_id, 'swap_offer',
      (select full_name from public.employees where id = v_uid) || ' weźmie Twoją zmianę '
        || app_private.shift_label(r.shift_id) || ', jeśli w zamian weźmiesz '
        || app_private.shift_label(v_exchange) || '. Potwierdź albo odrzuć.',
      jsonb_build_object('swap_request_id', r.id));
    return 'awaiting_requester';
  end if;

  return app_private.finalize_agreed_swap(r.id);
end;
$$;

-- Autor odpowiada na propozycję wymiany złożoną przez przejmującego.
create function public.respond_to_swap_offer(p_request_id uuid, p_accept boolean)
returns public.swap_status
language plpgsql
security definer
set search_path = public
as $$
declare
  r public.swap_requests%rowtype;
begin
  select * into r from public.swap_requests where id = p_request_id for update;
  if not found or r.requester_id is distinct from auth.uid() then
    raise exception 'Prośba nie istnieje albo nie jest Twoja.';
  end if;
  if r.status <> 'awaiting_requester' then
    raise exception 'Ta propozycja jest już nieaktualna.';
  end if;

  if not p_accept then
    update public.swap_requests
      set status = 'open', accepted_by = null, exchange_shift_id = null
    where id = r.id;
    perform app_private.notify(r.accepted_by, 'swap_offer_declined',
      (select full_name from public.employees where id = r.requester_id)
        || ' nie przyjął/ęła Twojej propozycji wymiany za ' || app_private.shift_label(r.shift_id) || '.',
      jsonb_build_object('swap_request_id', r.id));
    return 'open';
  end if;

  return app_private.finalize_agreed_swap(r.id);
end;
$$;

-- Adresat odrzuca prośbę skierowaną do niego.
create function public.reject_swap_request(p_request_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  r public.swap_requests%rowtype;
begin
  select * into r from public.swap_requests where id = p_request_id for update;
  if not found or r.target_id is distinct from auth.uid() then
    raise exception 'Prośba nie istnieje albo nie jest skierowana do Ciebie.';
  end if;
  if r.status <> 'open' then
    raise exception 'Ta prośba jest już nieaktualna.';
  end if;

  update public.swap_requests set status = 'rejected', resolved_at = now() where id = r.id;
  perform app_private.notify(r.requester_id, 'swap_rejected',
    (select full_name from public.employees where id = r.target_id)
      || ' odrzucił(a) prośbę o zamianę zmiany ' || app_private.shift_label(r.shift_id)
      || '. Możesz poprosić kogoś innego.',
    jsonb_build_object('swap_request_id', r.id));
  perform app_private.log_action('swap_rejected', jsonb_build_object('swap_request_id', r.id));
end;
$$;

-- Autor wycofuje swoją prośbę.
create function public.cancel_swap_request(p_request_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  r public.swap_requests%rowtype;
begin
  select * into r from public.swap_requests where id = p_request_id for update;
  if not found or r.requester_id is distinct from auth.uid() then
    raise exception 'Prośba nie istnieje albo nie jest Twoja.';
  end if;
  if r.status not in ('open', 'awaiting_requester', 'pending_approval') then
    raise exception 'Ta prośba jest już zamknięta.';
  end if;

  update public.swap_requests set status = 'cancelled', resolved_at = now() where id = r.id;
  perform app_private.notify(coalesce(r.accepted_by, r.target_id), 'swap_cancelled',
    (select full_name from public.employees where id = r.requester_id)
      || ' wycofał(a) prośbę o zamianę zmiany ' || app_private.shift_label(r.shift_id) || '.',
    jsonb_build_object('swap_request_id', r.id));
  perform app_private.log_action('swap_cancelled', jsonb_build_object('swap_request_id', r.id));
end;
$$;

-- Halina (lub Iza) zatwierdza albo odrzuca zamianę oczekującą na decyzję.
-- Przed wykonaniem wszystkie reguły są sprawdzane ponownie.
create function public.decide_swap(p_request_id uuid, p_approve boolean)
returns public.swap_status
language plpgsql
security definer
set search_path = public
as $$
declare
  r public.swap_requests%rowtype;
begin
  if not public.is_manager() then
    raise exception 'Tylko Halina albo Iza mogą zatwierdzać zamiany.';
  end if;

  select * into r from public.swap_requests where id = p_request_id for update;
  if not found then
    raise exception 'Prośba nie istnieje.';
  end if;
  if r.status <> 'pending_approval' then
    raise exception 'Ta zamiana nie czeka na zatwierdzenie.';
  end if;

  update public.swap_requests set decided_by = auth.uid() where id = r.id;

  if p_approve then
    perform app_private.execute_swap(r.id);
    return 'done';
  end if;

  update public.swap_requests set status = 'rejected', resolved_at = now() where id = r.id;
  perform app_private.notify(r.requester_id, 'swap_rejected',
    'Halina nie zatwierdziła zamiany zmiany ' || app_private.shift_label(r.shift_id) || '.',
    jsonb_build_object('swap_request_id', r.id));
  perform app_private.notify(r.accepted_by, 'swap_rejected',
    'Halina nie zatwierdziła zamiany zmiany ' || app_private.shift_label(r.shift_id) || '.',
    jsonb_build_object('swap_request_id', r.id));
  perform app_private.log_action('swap_rejected_by_manager', jsonb_build_object('swap_request_id', r.id));
  return 'rejected';
end;
$$;

-- -----------------------------------------------------------------------------
-- Zadanie cykliczne: wygaszanie próśb i alert "brak chętnych" 24 h przed zmianą
-- -----------------------------------------------------------------------------
create function app_private.process_swap_deadlines(p_now timestamptz default now())
returns jsonb
language plpgsql
set search_path = public
as $$
declare
  r record;
  v_expired integer := 0;
  v_alerted integer := 0;
begin
  for r in
    update public.swap_requests sr
      set status = 'expired', resolved_at = p_now
    from public.shifts s
    where s.id = sr.shift_id
      and sr.status in ('open', 'awaiting_requester', 'pending_approval')
      and public.shift_starts_at(s.date, s.start_time) <= p_now
    returning sr.id, sr.requester_id, sr.shift_id
  loop
    v_expired := v_expired + 1;
    perform app_private.notify(r.requester_id, 'swap_expired',
      'Prośba o zamianę zmiany ' || app_private.shift_label(r.shift_id) || ' wygasła.',
      jsonb_build_object('swap_request_id', r.id));
  end loop;

  for r in
    update public.swap_requests sr
      set alerted_at = p_now
    from public.shifts s
    where s.id = sr.shift_id
      and sr.status in ('open', 'awaiting_requester')
      and sr.alerted_at is null
      and public.shift_starts_at(s.date, s.start_time) <= p_now + interval '24 hours'
    returning sr.id, sr.requester_id, sr.shift_id
  loop
    v_alerted := v_alerted + 1;
    perform app_private.notify_managers('swap_no_taker',
      (select full_name from public.employees where id = r.requester_id)
        || ' szuka zastępstwa na ' || app_private.shift_label(r.shift_id) || ' – nikt jeszcze nie przyjął.',
      jsonb_build_object('swap_request_id', r.id));
  end loop;

  return jsonb_build_object('expired', v_expired, 'alerted', v_alerted);
end;
$$;

-- -----------------------------------------------------------------------------
-- Uprawnienia do funkcji
-- -----------------------------------------------------------------------------
-- anon nie wywołuje niczego; authenticated tylko funkcji z public
-- (każda RPC sama sprawdza rolę). Schemat app_private jest niedostępny dla API.
revoke execute on all functions in schema public from public, anon;
grant execute on all functions in schema public to authenticated, service_role;
revoke execute on all functions in schema app_private from public, anon, authenticated;
