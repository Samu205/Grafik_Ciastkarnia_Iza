-- Dane startowe: grafiki i szablony zmian.
-- Godziny szablonów są PRZYKŁADOWE – do potwierdzenia z Haliną.
-- Pracowników nie seedujemy: konto powstaje przy pierwszym logowaniu (magic link),
-- a rekord w `employees` dodaje Iza (pierwszą osobę – patrz README, sekcja "Pierwsza właścicielka").

insert into public.schedules (name, type) values
  ('Liszki', 'sales'),
  ('Lodołamacz Piekary', 'sales'),
  ('Ogrody', 'sales'),
  ('Produkcja Liszki', 'production')
on conflict (name) do nothing;

insert into public.shift_templates (schedule_id, name, start_time, end_time)
select s.id, t.name, t.start_time, t.end_time
from public.schedules s
cross join (values
  ('Ranna', time '07:00', time '14:00'),
  ('Popołudniowa', time '14:00', time '20:00')
) as t (name, start_time, end_time)
where s.type = 'sales'
on conflict (schedule_id, name) do nothing;

insert into public.shift_templates (schedule_id, name, start_time, end_time)
select s.id, t.name, t.start_time, t.end_time
from public.schedules s
cross join (values
  ('Poranna produkcja', time '05:00', time '13:00'),
  ('Dzienna produkcja', time '10:00', time '18:00')
) as t (name, start_time, end_time)
where s.name = 'Produkcja Liszki'
on conflict (schedule_id, name) do nothing;
