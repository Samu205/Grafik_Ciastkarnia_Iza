-- Uprawnienia: kto co widzi i co może zmienić.
begin;
select plan(22);

do $$ begin
  perform tests.create_employee('Iza', 'owner', 'sales');
  perform tests.create_employee('Halina', 'scheduler', 'sales');
  perform tests.create_employee('Ania', 'employee', 'sales');
  perform tests.create_employee('Kasia', 'employee', 'sales');
  perform tests.create_employee('Tomek', 'employee', 'production');
  perform tests.make_month('2030-03-01', 'published');
  perform tests.make_month('2030-04-01', 'drafting');
  perform tests.make_month('2030-05-01', 'collecting');
  perform tests.make_shift('Liszki', '2030-03-05', '07:00', '14:00', tests.emp('Ania'));
  perform tests.make_shift('Liszki', '2030-04-05', '07:00', '14:00', tests.emp('Ania'));
  perform tests.make_shift('Liszki', '2030-04-06', '07:00', '14:00');
  insert into public.availability (employee_id, date, kind) values (tests.emp('Kasia'), '2030-05-10', 'all_day');
end $$;

-- Niezalogowany ------------------------------------------------------------------
do $$ begin perform tests.login_as_anon(); end $$;
select throws_ok($$ select * from public.employees $$, '42501', null,
  'Niezalogowany nie ma dostępu do listy pracowników');

-- Pracownik ----------------------------------------------------------------------
do $$ begin perform tests.login_as(tests.emp('Ania')); end $$;
select is((select count(*) from public.shifts where date between '2030-03-01' and '2030-03-31'), 1::bigint,
  'Pracownik widzi opublikowany grafik');
select is((select count(*) from public.shifts where date between '2030-04-01' and '2030-04-30'), 0::bigint,
  'Pracownik nie widzi wersji roboczej grafiku');
select throws_ok(
  $$ insert into public.shifts (schedule_id, date, start_time, end_time)
     values (tests.schedule_id('Liszki'), '2030-03-20', '07:00', '14:00') $$,
  '42501', null,
  'Pracownik nie może tworzyć zmian');
select is((select count(*) from public.availability where employee_id = tests.emp('Kasia')), 0::bigint,
  'Pracownik nie widzi dyspozycyjności innych osób');
select lives_ok(
  $$ insert into public.availability (employee_id, date, kind) values (tests.emp('Ania'), '2030-05-10', 'all_day') $$,
  'Pracownik wpisuje swoją dyspozycyjność, gdy trwa jej zbieranie');
select throws_ok(
  $$ insert into public.availability (employee_id, date, kind) values (tests.emp('Ania'), '2030-04-10', 'all_day') $$,
  '42501', null,
  'Po zakończeniu zbierania pracownik nie zmienia już dyspozycyjności');
select throws_ok(
  $$ insert into public.availability (employee_id, date, kind) values (tests.emp('Kasia'), '2030-05-11', 'all_day') $$,
  '42501', null,
  'Pracownik nie wpisuje dyspozycyjności za kogoś innego');
select throws_ok(
  $$ insert into public.schedules (name, type) values ('Nowy punkt', 'sales') $$,
  '42501', null,
  'Pracownik nie dodaje grafików');
select throws_ok(
  $$ select app_private.notify(tests.emp('Kasia'), 'spam', 'spam') $$,
  '42501', null,
  'Funkcje wewnętrzne (app_private) są niedostępne z aplikacji');
select is((select count(*) from public.audit_log), 0::bigint,
  'Pracownik nie widzi historii zmian');

update public.employees set role = 'owner' where id = tests.emp('Ania');
select is((select role from public.employees where id = tests.emp('Ania')), 'employee'::public.app_role,
  'Pracownik nie może nadać sobie innej roli');

do $$ begin perform public.create_swap_request(
  (select id from public.shifts where date = '2030-03-05' and employee_id = tests.emp('Ania'))); end $$;
select is((select count(*) from public.notifications where employee_id <> tests.emp('Ania')), 0::bigint,
  'Pracownik widzi tylko swoje powiadomienia');

do $$ begin perform tests.login_as(tests.emp('Kasia')); end $$;
select is((select count(*) from public.swap_requests), 1::bigint,
  'Prośbę do wszystkich widzą osoby z tego samego działu');
do $$ begin perform tests.login_as(tests.emp('Tomek')); end $$;
select is((select count(*) from public.swap_requests), 0::bigint,
  '...a osoby z innego działu jej nie widzą');

-- Halina -------------------------------------------------------------------------
do $$ begin perform tests.login_as(tests.emp('Halina')); end $$;
select is((select count(*) from public.shifts where date between '2030-04-01' and '2030-04-30'), 2::bigint,
  'Halina widzi wersję roboczą grafiku');
select is((select count(*) from public.availability where employee_id = tests.emp('Kasia')), 1::bigint,
  'Halina widzi dyspozycyjność wszystkich');
select lives_ok(
  $$ insert into public.shifts (schedule_id, date, start_time, end_time)
     values (tests.schedule_id('Liszki'), '2030-04-07', '07:00', '14:00') $$,
  'Halina tworzy zmiany');
select throws_ok(
  $$ insert into public.shifts (schedule_id, date, start_time, end_time, employee_id)
     values (tests.schedule_id('Liszki'), '2030-04-08', '07:00', '14:00', tests.emp('Kasia')) $$,
  '42501', null,
  'Osoby przypisuje się tylko przez assign_shift (z kontrolą kolizji), nie wprost');

delete from public.shifts where date in ('2030-04-05', '2030-04-06');
select is((select count(*) from public.shifts where date in ('2030-04-05', '2030-04-06')), 1::bigint,
  'Halina usuwa wprost tylko nieobsadzone zmiany');
select throws_ok(
  $$ insert into public.schedules (name, type) values ('Nowy punkt', 'sales') $$,
  '42501', null,
  'Halina nie dodaje grafików (to rola Izy)');

-- Iza ----------------------------------------------------------------------------
do $$ begin perform tests.login_as(tests.emp('Iza')); end $$;
select lives_ok(
  $$ insert into public.schedules (name, type) values ('Nowy punkt', 'sales') $$,
  'Iza dodaje nowe grafiki');

select * from finish();
rollback;
