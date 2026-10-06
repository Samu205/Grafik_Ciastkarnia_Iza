-- Zamiany i oddawanie zmian – przypadki z docs/ZASADY_DZIALANIA.md §7.
begin;
select plan(37);

do $$ begin
  perform tests.create_employee('Iza', 'owner', 'sales');
  perform tests.create_employee('Halina', 'scheduler', 'sales');
  perform tests.create_employee('Ania', 'employee', 'sales');
  perform tests.create_employee('Kasia', 'employee', 'sales');
  perform tests.create_employee('Ola', 'employee', 'sales');
  perform tests.create_employee('Nowa', 'employee', 'sales', true);
  perform tests.create_employee('Tomek', 'employee', 'production');
  perform tests.make_month('2030-03-01', 'published');
  perform tests.make_month('2030-04-01', 'drafting');
end $$;

-- Etykiety zmian -> id
create temp table sh (label text primary key, id uuid not null) on commit drop;
grant select on sh to authenticated;

insert into sh values
  ('a10', tests.make_shift('Liszki', '2030-03-10', '07:00', '14:00', tests.emp('Ania'))),
  ('a11', tests.make_shift('Liszki', '2030-03-11', '07:00', '14:00', tests.emp('Ania'))),
  ('k11', tests.make_shift('Ogrody', '2030-03-11', '14:00', '20:00', tests.emp('Kasia'))),
  ('a12', tests.make_shift('Liszki', '2030-03-12', '07:00', '14:00', tests.emp('Ania'))),
  ('k12', tests.make_shift('Ogrody', '2030-03-12', '14:00', '20:00', tests.emp('Kasia'))),
  ('a13', tests.make_shift('Liszki', '2030-03-13', '07:00', '14:00', tests.emp('Ania'))),
  ('k15', tests.make_shift('Ogrody', '2030-03-15', '14:00', '20:00', tests.emp('Kasia'))),
  ('a16', tests.make_shift('Liszki', '2030-03-16', '07:00', '14:00', tests.emp('Ania'))),
  ('k18', tests.make_shift('Ogrody', '2030-03-18', '14:00', '20:00', tests.emp('Kasia'))),
  ('a18', tests.make_shift('Lodołamacz Piekary', '2030-03-18', '07:00', '14:00', tests.emp('Ania'))),
  ('a20', tests.make_shift('Liszki', '2030-03-20', '07:00', '14:00', tests.emp('Ania'))),
  ('a21', tests.make_shift('Liszki', '2030-03-21', '07:00', '14:00', tests.emp('Ania'))),
  ('a22', tests.make_shift('Liszki', '2030-03-22', '07:00', '14:00', tests.emp('Ania'))),
  ('a23', tests.make_shift('Liszki', '2030-03-23', '07:00', '14:00', tests.emp('Ania'))),
  ('x23', tests.make_shift('Ogrody', '2030-03-23', '14:00', '20:00')),
  ('a25', tests.make_shift('Liszki', '2030-03-25', '07:00', '14:00', tests.emp('Ania'))),
  ('a26', tests.make_shift('Liszki', '2030-03-26', '07:00', '14:00', tests.emp('Ania'))),
  ('o27', tests.make_shift('Ogrody', '2030-03-27', '14:00', '20:00', tests.emp('Ola'))),
  ('a28', tests.make_shift('Liszki', '2030-03-28', '07:00', '14:00', tests.emp('Ania'))),
  ('a29', tests.make_shift('Liszki', '2030-03-29', '07:00', '14:00', tests.emp('Ania'))),
  ('a30', tests.make_shift('Liszki', '2030-03-30', '07:00', '14:00', tests.emp('Ania'))),
  ('k30', tests.make_shift('Ogrody', '2030-03-30', '14:00', '20:00', tests.emp('Kasia'))),
  ('a02', tests.make_shift('Liszki', '2030-04-02', '07:00', '14:00', tests.emp('Ania')));

create function pg_temp.sid(p_label text) returns uuid language sql stable
  as $$ select id from sh where label = p_label $$;

create temp table rq (label text primary key, id uuid not null) on commit drop;
grant select, insert on rq to authenticated;

create function pg_temp.rid(p_label text) returns uuid language sql stable
  as $$ select id from rq where label = p_label $$;

-- ============================================================================
-- Przypadki z tabeli w ZASADY_DZIALANIA §7
-- ============================================================================

-- 1. Oddanie osobie wolnej tego dnia -> dozwolone
do $$ begin perform tests.login_as(tests.emp('Ania')); end $$;
insert into rq values ('r1', public.create_swap_request(pg_temp.sid('a10'), tests.emp('Kasia')));
select is(tests.notification_count(tests.emp('Kasia'), 'swap_request'), 1::bigint,
  'Adresat prośby dostaje powiadomienie');

do $$ begin perform tests.login_as(tests.emp('Kasia')); end $$;
select is(public.accept_swap_request(pg_temp.rid('r1')), 'done'::public.swap_status,
  'Przypadek 1: Kasia wolna tego dnia przejmuje zmianę Ani');
select is(tests.shift_owner(pg_temp.sid('a10')), tests.emp('Kasia'),
  '...a grafik od razu pokazuje Kasię');
select ok(
  tests.notification_count(tests.emp('Ania'), 'swap_done') = 1
  and tests.notification_count(tests.emp('Halina'), 'swap_done') = 1,
  '...a Ania i Halina dostają powiadomienie o wykonanej zamianie');

-- 2. Oddanie osobie, która ma już zmianę tego dnia -> blokada
do $$ begin perform tests.login_as(tests.emp('Ania')); end $$;
select throws_ok(
  $$ select public.create_swap_request(pg_temp.sid('a11'), tests.emp('Kasia')) $$,
  'P0001',
  'Po zamianie Kasia miał(a)by dwie zmiany jednego dnia. Kasia ma już zmianę '
    || public.pl_date('2030-03-11') || ' – Ogrody, 14:00–20:00.',
  'Przypadek 2: nie da się oddać zmiany osobie, która ma już zmianę tego dnia (komunikat z grafikiem i datą)');

-- 3. Wymiana w ten sam dzień -> dozwolona
insert into rq values ('r3', public.create_swap_request(pg_temp.sid('a12'), tests.emp('Kasia'), pg_temp.sid('k12')));
do $$ begin perform tests.login_as(tests.emp('Kasia')); end $$;
select is(public.accept_swap_request(pg_temp.rid('r3')), 'done'::public.swap_status,
  'Przypadek 3: wymiana w ten sam dzień przechodzi');
select ok(
  tests.shift_owner(pg_temp.sid('a12')) = tests.emp('Kasia')
  and tests.shift_owner(pg_temp.sid('k12')) = tests.emp('Ania'),
  '...i obie zmiany zamieniają się właścicielkami');

-- 4. Wymiana na różne dni, obie osoby wolne -> dozwolona
do $$ begin perform tests.login_as(tests.emp('Ania')); end $$;
insert into rq values ('r4', public.create_swap_request(pg_temp.sid('a13'), tests.emp('Kasia'), pg_temp.sid('k15')));
do $$ begin perform tests.login_as(tests.emp('Kasia')); end $$;
select is(public.accept_swap_request(pg_temp.rid('r4')), 'done'::public.swap_status,
  'Przypadek 4: wymiana na różne dni, gdy obie osoby są wolne');
select ok(
  tests.shift_owner(pg_temp.sid('a13')) = tests.emp('Kasia')
  and tests.shift_owner(pg_temp.sid('k15')) = tests.emp('Ania'),
  '...i grafik jest zaktualizowany');

-- 5. Wymiana, po której autor miałby dwie zmiany -> blokada
do $$ begin perform tests.login_as(tests.emp('Ania')); end $$;
select throws_like(
  $$ select public.create_swap_request(pg_temp.sid('a16'), tests.emp('Kasia'), pg_temp.sid('k18')) $$,
  'Po zamianie Ania miał(a)by dwie zmiany jednego dnia. Ania ma już zmianę %Lodołamacz Piekary%',
  'Przypadek 5: wymiana blokowana, gdy autor ma już inną zmianę w dniu, który bierze');

-- 6. Sprzedaż -> produkcja -> blokada
select throws_like(
  $$ select public.create_swap_request(pg_temp.sid('a20'), tests.emp('Tomek')) $$,
  '%pracują w różnych działach%',
  'Przypadek 6: zamiana między sprzedażą a produkcją jest zablokowana');

-- ============================================================================
-- Zatwierdzanie przez Halinę (flaga swaps_require_approval)
-- ============================================================================
insert into rq values ('r21', public.create_swap_request(pg_temp.sid('a21'), tests.emp('Nowa')));
do $$ begin perform tests.login_as(tests.emp('Nowa')); end $$;
select is(public.accept_swap_request(pg_temp.rid('r21')), 'pending_approval'::public.swap_status,
  'Zamiana z osobą z flagą zatwierdzania czeka na Halinę');
select is(tests.shift_owner(pg_temp.sid('a21')), tests.emp('Ania'),
  '...a do decyzji obowiązuje stary stan grafiku');
select is(tests.notification_count(tests.emp('Halina'), 'swap_pending_approval'), 1::bigint,
  '...i Halina dostaje powiadomienie');
select throws_like(
  $$ select public.decide_swap(pg_temp.rid('r21'), true) $$,
  '%Tylko Halina albo Iza%',
  'Pracownik nie może sam zatwierdzić zamiany');

do $$ begin perform tests.login_as(tests.emp('Halina')); end $$;
select is(public.decide_swap(pg_temp.rid('r21'), true), 'done'::public.swap_status,
  'Halina zatwierdza zamianę');
select is(tests.shift_owner(pg_temp.sid('a21')), tests.emp('Nowa'),
  '...i dopiero wtedy grafik się zmienia');

do $$ begin perform tests.login_as(tests.emp('Ania')); end $$;
insert into rq values ('r22', public.create_swap_request(pg_temp.sid('a22'), tests.emp('Nowa')));
do $$ begin perform tests.login_as(tests.emp('Nowa')); end $$;
do $$ begin perform public.accept_swap_request(pg_temp.rid('r22')); end $$;
do $$ begin perform tests.login_as(tests.emp('Halina')); end $$;
select is(public.decide_swap(pg_temp.rid('r22'), false), 'rejected'::public.swap_status,
  'Halina może odrzucić zamianę');
select is(tests.shift_owner(pg_temp.sid('a22')), tests.emp('Ania'),
  '...wtedy zmiana zostaje u autora');

-- Ponowne sprawdzenie reguł przy zatwierdzaniu
do $$ begin perform tests.login_as(tests.emp('Ania')); end $$;
insert into rq values ('r23', public.create_swap_request(pg_temp.sid('a23'), tests.emp('Nowa')));
do $$ begin perform tests.login_as(tests.emp('Nowa')); end $$;
do $$ begin perform public.accept_swap_request(pg_temp.rid('r23')); end $$;
do $$ begin perform tests.login_as(tests.emp('Halina')); end $$;
do $$ begin perform public.assign_shift(pg_temp.sid('x23'), tests.emp('Nowa')); end $$;
select throws_like(
  $$ select public.decide_swap(pg_temp.rid('r23'), true) $$,
  '%Nowa miał(a)by dwie zmiany jednego dnia%',
  'Przed wykonaniem zatwierdzonej zamiany reguły są sprawdzane ponownie');

-- ============================================================================
-- Prośba do wszystkich: kto pierwszy, ten bierze
-- ============================================================================
do $$ begin perform tests.login_as(tests.emp('Ania')); end $$;
insert into rq values ('r25', public.create_swap_request(pg_temp.sid('a25')));
select ok(
  tests.notification_count(tests.emp('Ola'), 'swap_request') = 1
  and tests.notification_count(tests.emp('Tomek'), 'swap_request') = 0,
  'Prośbę do wszystkich dostają tylko osoby, które mogą przejąć zmianę');

do $$ begin perform tests.login_as(tests.emp('Kasia')); end $$;
select is(public.accept_swap_request(pg_temp.rid('r25')), 'done'::public.swap_status,
  'Pierwsza osoba przyjmuje prośbę do wszystkich');
do $$ begin perform tests.login_as(tests.emp('Ola')); end $$;
select throws_like(
  $$ select public.accept_swap_request(pg_temp.rid('r25')) $$,
  '%już nieaktualna%',
  'Druga osoba nie może już przyjąć tej samej prośby');

-- Przejmujący proponuje wymianę -> autor musi potwierdzić
do $$ begin perform tests.login_as(tests.emp('Ania')); end $$;
insert into rq values ('r26', public.create_swap_request(pg_temp.sid('a26')));
do $$ begin perform tests.login_as(tests.emp('Ola')); end $$;
select is(public.accept_swap_request(pg_temp.rid('r26'), pg_temp.sid('o27')), 'awaiting_requester'::public.swap_status,
  'Propozycja wymiany w odpowiedzi na prośbę do wszystkich czeka na autora');
do $$ begin perform tests.login_as(tests.emp('Ania')); end $$;
select is(public.respond_to_swap_offer(pg_temp.rid('r26'), false), 'open'::public.swap_status,
  'Autor może odrzucić propozycję – prośba wraca na giełdę');
do $$ begin perform tests.login_as(tests.emp('Ola')); end $$;
do $$ begin perform public.accept_swap_request(pg_temp.rid('r26'), pg_temp.sid('o27')); end $$;
do $$ begin perform tests.login_as(tests.emp('Ania')); end $$;
select is(public.respond_to_swap_offer(pg_temp.rid('r26'), true), 'done'::public.swap_status,
  'Po potwierdzeniu przez autora wymiana się wykonuje');
select ok(
  tests.shift_owner(pg_temp.sid('a26')) = tests.emp('Ola')
  and tests.shift_owner(pg_temp.sid('o27')) = tests.emp('Ania'),
  '...i grafik jest zaktualizowany');

-- ============================================================================
-- Prośba do konkretnej osoby: tylko adresat, odrzucenie, wycofanie
-- ============================================================================
insert into rq values ('r28', public.create_swap_request(pg_temp.sid('a28'), tests.emp('Kasia')));
do $$ begin perform tests.login_as(tests.emp('Ola')); end $$;
select throws_like(
  $$ select public.accept_swap_request(pg_temp.rid('r28')) $$,
  '%nie jest skierowana do Ciebie%',
  'Prośbę do konkretnej osoby może przyjąć tylko ona');
do $$ begin perform tests.login_as(tests.emp('Kasia')); end $$;
select lives_ok($$ select public.reject_swap_request(pg_temp.rid('r28')) $$,
  'Adresat może odrzucić prośbę');
select ok(
  tests.swap_status(pg_temp.rid('r28')) = 'rejected'
  and tests.notification_count(tests.emp('Ania'), 'swap_rejected') >= 1,
  '...a autor dostaje o tym powiadomienie');

do $$ begin perform tests.login_as(tests.emp('Ania')); end $$;
insert into rq values ('r29', public.create_swap_request(pg_temp.sid('a29')));
select lives_ok($$ select public.cancel_swap_request(pg_temp.rid('r29')) $$,
  'Autor może wycofać swoją prośbę');
select is(tests.swap_status(pg_temp.rid('r29')), 'cancelled'::public.swap_status,
  '...i prośba jest anulowana');

-- ============================================================================
-- Inne zabezpieczenia
-- ============================================================================
do $$ begin perform tests.login_as(tests.emp('Kasia')); end $$;
select throws_like(
  $$ select public.create_swap_request(pg_temp.sid('a30')) $$,
  '%To nie jest Twoja zmiana%',
  'Nie można prosić o zamianę cudzej zmiany');

do $$ begin perform tests.login_as(tests.emp('Ania')); end $$;
select throws_like(
  $$ select public.create_swap_request(pg_temp.sid('a02')) $$,
  '%nie jest jeszcze opublikowany%',
  'Zmian z nieopublikowanego grafiku nie można zamieniać');

insert into rq values ('r30', public.create_swap_request(pg_temp.sid('a30')));
select throws_like(
  $$ select public.create_swap_request(pg_temp.sid('a30')) $$,
  '%już aktywna prośba%',
  'Na jedną zmianę może być tylko jedna aktywna prośba');

select ok(
  exists (select 1 from public.eligible_takers(pg_temp.sid('a30')) where employee_id = tests.emp('Ola'))
  and not exists (select 1 from public.eligible_takers(pg_temp.sid('a30')) where employee_id = tests.emp('Kasia'))
  and not exists (select 1 from public.eligible_takers(pg_temp.sid('a30')) where employee_id = tests.emp('Tomek')),
  'Lista osób do wyboru pomija osoby z kolizją i z innego działu');

select throws_ok(
  $$ update public.shifts set employee_id = tests.emp('Ania') where id = pg_temp.sid('k30') $$,
  '42501', null,
  'Pracownik nie może przepisać zmiany wprost, z pominięciem reguł');

select * from finish();
rollback;
