-- Zadania cykliczne (pg_cron). NIE jest migracją – uruchom ręcznie raz na każdym
-- projekcie Supabase (dev i prod) w SQL Editorze, po włączeniu rozszerzenia pg_cron
-- (Database → Extensions → pg_cron).
--
-- pg_cron liczy czas w UTC. Same funkcje pracują w czasie polskim (Europe/Warsaw).

-- Co 15 minut: wygaszanie próśb o zamianę i alert dla Haliny 24 h przed zmianą bez chętnych.
select cron.schedule(
  'grafik-swap-deadlines',
  '*/15 * * * *',
  $$ select app_private.process_swap_deadlines(); $$
);

-- Codziennie ok. 8:00 czasu polskiego (6:00 UTC latem, 7:00 UTC zimą – wybieramy 6:00 UTC):
-- przypomnienie o dyspozycyjności 2 dni przed terminem.
select cron.schedule(
  'grafik-availability-reminders',
  '0 6 * * *',
  $$ select app_private.send_availability_reminders(); $$
);

-- Podgląd zaplanowanych zadań:   select * from cron.job;
-- Usunięcie zadania:             select cron.unschedule('grafik-swap-deadlines');
