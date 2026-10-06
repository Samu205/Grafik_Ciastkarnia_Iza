-- Układanie grafiku przez Halinę: kolizje, dyspozycyjność, powiadomienia.
begin;
select plan(14);

do $$ begin
  perform tests.create_employee('Iza', 'owner', 'sales');
  perform tests.create_employee('Halina', 'scheduler', 'sales');
  perform tests.create_employee('Ania', 'employee', 'sales');
  perform tests.create_employee('Kasia', 'employee', 'sales');
  perform tests.make_month('2030-03-01', 'drafting');

  perform tests.make_shift('Ogrody', '2030-03-05', '10:00', '14:00', tests.emp('Ania'));
  perform tests.make_shift('Liszki', '2030-03-05', '07:00', '14:00');
  perform tests.make_shift('Liszki', '2030-03-06', '07:00', '14:00');
  perform tests.make_shift('Liszki', '2030-03-07', '07:00', '14:00');
  perform tests.make_shift('Liszki', '2030-03-08', '07:00', '14:00');
  perform tests.make_shift('Liszki', '2030-03-09', '07:00', '14:00');

  insert into public.availability (employee_id, date, kind, start_time, end_time) values
    (tests.emp('Kasia'), '2030-03-06', 'unavailable', null, null),
    (tests.emp('Kasia'), '2030-03-07', 'hours', '07:00', '12:00'),
    (tests.emp('Kasia'), '2030-03-09', 'all_day', null, null);
end $$;

create temp table s on commit drop as
  select date, id from public.shifts where schedule_id = tests.schedule_id('Liszki');
grant select on s to authenticated;

-- Uprawnienia -------------------------------------------------------------------
do $$ begin perform tests.login_as(tests.emp('Ania')); end $$;
select throws_like(
  $$ select public.assign_shift((select id from s where date = '2030-03-05'), tests.emp('Kasia')) $$,
  '%Tylko Halina albo Iza%',
  'Pracownik nie może przypisywać zmian'
);

-- Kolizja: komunikat z grafikiem, datą i godzinami ------------------------------
do $$ begin perform tests.login_as(tests.emp('Halina')); end $$;
select throws_ok(
  $$ select public.assign_shift((select id from s where date = '2030-03-05'), tests.emp('Ania')) $$,
  'P0001',
  'Ania ma już zmianę ' || public.pl_date('2030-03-05') || ' – Ogrody, 10:00–14:00',
  'Druga zmiana tego samego dnia jest blokowana, a komunikat podaje grafik, datę i godziny'
);

-- Dyspozycyjność: ostrzeżenie, nie blokada --------------------------------------
select alike(
  public.assign_shift((select id from s where date = '2030-03-06'), tests.emp('Kasia')) ->> 'warning',
  '%nie może pracować%',
  'Przypisanie w dniu "nie mogę" zwraca ostrzeżenie'
);
select is(
  tests.shift_owner((select id from s where date = '2030-03-06')), tests.emp('Kasia'),
  '...ale przypisanie mimo to się wykonuje'
);
select alike(
  public.assign_shift((select id from s where date = '2030-03-07'), tests.emp('Kasia')) ->> 'warning',
  '%tylko w godzinach 07:00–12:00%',
  'Zmiana wykraczająca poza zgłoszone godziny zwraca ostrzeżenie'
);
select alike(
  public.assign_shift((select id from s where date = '2030-03-08'), tests.emp('Kasia')) ->> 'warning',
  '%nie podał(a) dyspozycyjności%',
  'Brak dyspozycyjności zwraca ostrzeżenie'
);
select is(
  public.assign_shift((select id from s where date = '2030-03-09'), tests.emp('Kasia')) ->> 'warning',
  null,
  'Przypisanie zgodne z dyspozycyjnością nie ma ostrzeżenia'
);

-- Powiadomienia -----------------------------------------------------------------
select is(
  tests.notification_count(tests.emp('Kasia'), 'shift_assigned'), 0::bigint,
  'W wersji roboczej pracownik nie dostaje powiadomień o przypisaniach'
);

select lives_ok($$ select public.publish_month('2030-03-01') $$, 'Halina publikuje grafik');
select is(
  tests.notification_count(tests.emp('Ania'), 'month_published'), 1::bigint,
  'Po publikacji każdy pracownik dostaje powiadomienie'
);

do $$ begin perform public.assign_shift((select id from s where date = '2030-03-09'), tests.emp('Ania')); end $$;
select ok(
  tests.notification_count(tests.emp('Kasia'), 'shift_removed') = 1
  and tests.notification_count(tests.emp('Ania'), 'shift_assigned') = 1,
  'Zmiana obsady w opublikowanym grafiku powiadamia obie osoby'
);

update public.shifts set end_time = '13:00' where id = (select id from s where date = '2030-03-09');
select is(
  tests.notification_count(tests.emp('Ania'), 'shift_changed'), 1::bigint,
  'Zmiana godzin opublikowanej zmiany powiadamia pracownika'
);

-- Zmiana obsady anuluje aktywne prośby o zamianę ---------------------------------
do $$ begin perform tests.login_as(tests.emp('Ania')); end $$;
create temp table req on commit drop as
  select public.create_swap_request((select id from s where date = '2030-03-09')) as id;

do $$ begin perform tests.login_as(tests.emp('Halina')); end $$;
do $$ begin perform public.assign_shift((select id from s where date = '2030-03-09'), tests.emp('Kasia')); end $$;
select is(
  tests.swap_status((select id from req)), 'cancelled'::public.swap_status,
  'Gdy Halina zmienia obsadę zmiany, aktywna prośba o zamianę zostaje anulowana'
);

-- Historia ----------------------------------------------------------------------
do $$ begin perform tests.logout(); end $$;
select ok(
  (select count(*) from public.audit_log where action = 'assign_shift') >= 5,
  'Każde przypisanie trafia do historii zmian'
);

select * from finish();
rollback;
