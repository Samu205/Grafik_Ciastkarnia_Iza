-- Reguły wymuszane przez sam schemat (ograniczenia i triggery).
begin;
select plan(9);

do $$ begin
  perform tests.create_employee('Ania', 'employee', 'sales');
  perform tests.create_employee('Tomek', 'employee', 'production');
end $$;

-- Jedna osoba, jedna zmiana dziennie – ograniczenie w bazie (ostatnia linia obrony).
set constraints public.one_shift_per_day immediate;
do $$ begin perform tests.make_shift('Liszki', '2030-03-05', '07:00', '14:00', tests.emp('Ania')); end $$;
select throws_ok(
  $$ select tests.make_shift('Ogrody', '2030-03-05', '14:00', '20:00', tests.emp('Ania')) $$,
  '23505', null,
  'Baza nie pozwala dać tej samej osobie dwóch zmian jednego dnia, nawet w różnych grafikach'
);
set constraints public.one_shift_per_day deferred;

select lives_ok(
  $$ select tests.make_shift('Ogrody', '2030-03-06', '14:00', '20:00', tests.emp('Ania')) $$,
  'Zmiana innego dnia w innym punkcie sprzedaży jest dozwolona'
);

select throws_like(
  $$ select tests.make_shift('Liszki', '2030-03-07', '07:00', '14:00', tests.emp('Tomek')) $$,
  '%pracuje w dziale "produkcja"%',
  'Pracownika produkcji nie da się przypisać do grafiku sprzedaży'
);

select lives_ok(
  $$ select tests.make_shift('Produkcja Liszki', '2030-03-07', '05:00', '13:00', tests.emp('Tomek')) $$,
  'Pracownika produkcji da się przypisać do grafiku produkcji'
);

update public.schedules set archived_at = now() where name = 'Lodołamacz Piekary';
select throws_like(
  $$ select tests.make_shift('Lodołamacz Piekary', '2030-03-08', '07:00', '14:00', tests.emp('Ania')) $$,
  '%jest zarchiwizowany%',
  'Do zarchiwizowanego grafiku nie da się przypisać osoby'
);

select throws_ok(
  $$ select tests.make_shift('Liszki', '2030-03-09', '14:00', '07:00') $$,
  '23514', null,
  'Zmiana musi kończyć się po rozpoczęciu'
);

select throws_ok(
  $$ insert into public.availability (employee_id, date, kind) values (tests.emp('Ania'), '2030-03-10', 'hours') $$,
  '23514', null,
  'Dyspozycyjność "od–do" wymaga podania godzin'
);

select throws_like(
  $$ insert into public.shifts (schedule_id, date, start_time, end_time, template_id)
     select tests.schedule_id('Liszki'), '2030-03-11', '05:00', '13:00', t.id
     from public.shift_templates t where t.schedule_id = tests.schedule_id('Produkcja Liszki') limit 1 $$,
  '%Szablon zmiany należy do innego grafiku%',
  'Szablon zmiany musi pochodzić z tego samego grafiku'
);

do $$ begin perform tests.make_month('2030-03-01', 'published'); end $$;
select throws_like(
  $$ update public.schedule_months set status = 'drafting' where month = '2030-03-01' $$,
  '%nie można cofnąć%',
  'Opublikowanego miesiąca nie da się cofnąć do wersji roboczej'
);

select * from finish();
rollback;
