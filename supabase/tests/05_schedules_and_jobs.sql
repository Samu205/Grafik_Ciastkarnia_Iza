-- Grafiki (archiwizacja, usuwanie) oraz zadania cykliczne (alerty, przypomnienia).
begin;
select plan(15);

do $$ begin
  perform tests.create_employee('Iza', 'owner', 'sales');
  perform tests.create_employee('Halina', 'scheduler', 'sales');
  perform tests.create_employee('Ania', 'employee', 'sales');
  perform tests.create_employee('Kasia', 'employee', 'sales');
end $$;

-- ============================================================================
-- Archiwizacja i usuwanie grafiku
-- ============================================================================
do $$ begin perform tests.login_as(tests.emp('Halina')); end $$;
select throws_like($$ select public.archive_schedule(tests.schedule_id('Ogrody')) $$,
  '%Tylko Iza%', 'Tylko Iza archiwizuje grafiki');

do $$ begin perform tests.login_as(tests.emp('Iza')); end $$;
select throws_like($$ select public.delete_schedule(tests.schedule_id('Ogrody'), 'Ogrody') $$,
  '%Najpierw zarchiwizuj%', 'Nie da się trwale usunąć grafiku bez wcześniejszej archiwizacji');

select lives_ok($$ select public.archive_schedule(tests.schedule_id('Ogrody')) $$,
  'Iza archiwizuje grafik ("Usuń" = archiwizacja)');

do $$ begin perform tests.login_as(tests.emp('Ania')); end $$;
select is((select count(*) from public.schedules where name = 'Ogrody'), 0::bigint,
  'Zarchiwizowany grafik znika z widoku pracowników');

do $$ begin perform tests.login_as(tests.emp('Iza')); end $$;
select is((select count(*) from public.schedules where name = 'Ogrody'), 1::bigint,
  '...ale Iza dalej go widzi i może przywrócić');

select throws_like($$ select public.delete_schedule(tests.schedule_id('Ogrody'), 'ogrody') $$,
  '%nie zgadza się%', 'Trwałe usunięcie wymaga wpisania dokładnej nazwy (wielkość liter ma znaczenie)');
select is((select count(*) from public.schedules where name = 'Ogrody'), 1::bigint,
  '...a po błędnej nazwie nic nie zostaje usunięte');

select lives_ok($$ select public.restore_schedule(tests.schedule_id('Ogrody')) $$,
  'Iza przywraca zarchiwizowany grafik');

do $$ begin perform public.archive_schedule(tests.schedule_id('Ogrody')); end $$;
select lives_ok($$ select public.delete_schedule(tests.schedule_id('Ogrody'), 'Ogrody') $$,
  'Po wpisaniu dokładnej nazwy zarchiwizowany grafik zostaje trwale usunięty');
select is((select count(*) from public.schedules where name = 'Ogrody'), 0::bigint,
  '...i znika całkowicie');

-- ============================================================================
-- Zadania cykliczne
-- ============================================================================
do $$ begin
  perform tests.logout();
  perform tests.make_month('2030-03-01', 'published');
end $$;

create temp table j (label text primary key, id uuid) on commit drop;
grant select, insert on j to authenticated;
insert into j values
  ('a05', tests.make_shift('Liszki', '2030-03-05', '07:00', '14:00', tests.emp('Ania'))),
  ('a10', tests.make_shift('Liszki', '2030-03-10', '07:00', '14:00', tests.emp('Ania')));

do $$ begin perform tests.login_as(tests.emp('Ania')); end $$;
insert into j values
  ('r05', public.create_swap_request((select id from j where label = 'a05'))),
  ('r10', public.create_swap_request((select id from j where label = 'a10')));
do $$ begin perform tests.logout(); end $$;

-- 4 marca 2030, 8:00 czasu polskiego: do zmiany 5.03 o 7:00 zostało < 24 h.
select is(
  app_private.process_swap_deadlines(timestamptz '2030-03-04 08:00 Europe/Warsaw'),
  '{"expired": 0, "alerted": 1}'::jsonb,
  'Na mniej niż 24 h przed zmianą bez chętnych Halina dostaje alert');
select is(tests.notification_count(tests.emp('Halina'), 'swap_no_taker'), 1::bigint,
  '...jako powiadomienie "nikt nie przyjął"');
select is(
  app_private.process_swap_deadlines(timestamptz '2030-03-04 09:00 Europe/Warsaw'),
  '{"expired": 0, "alerted": 0}'::jsonb,
  'Alert dla tej samej prośby nie jest wysyłany drugi raz');

-- 5 marca 2030, 7:30: zmiana się zaczęła -> prośba wygasa.
select is(
  app_private.process_swap_deadlines(timestamptz '2030-03-05 07:30 Europe/Warsaw'),
  '{"expired": 1, "alerted": 0}'::jsonb,
  'Prośba o zmianę, która już się zaczęła, wygasa');

-- Przypomnienie o dyspozycyjności: 2 dni przed terminem, tylko dla osób bez wpisów.
insert into public.schedule_months (month, status, availability_deadline)
  values ('2030-06-01', 'collecting', '2030-05-25');
insert into public.availability (employee_id, date, kind) values (tests.emp('Kasia'), '2030-06-03', 'all_day');
-- Osobne zapytanie: funkcja stable w tym samym zapytaniu nie widziałaby nowych powiadomień.
do $$ begin perform app_private.send_availability_reminders(timestamptz '2030-05-23 09:00 Europe/Warsaw'); end $$;
select ok(
  tests.notification_count(tests.emp('Ania'), 'availability_reminder') = 1
  and tests.notification_count(tests.emp('Kasia'), 'availability_reminder') = 0,
  'Przypomnienie o dyspozycyjności trafia tylko do osób, które nic nie wpisały');

select * from finish();
rollback;
