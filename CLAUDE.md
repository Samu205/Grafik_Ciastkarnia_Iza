# CLAUDE.md – Grafik Ciastkarnia Iza

Aplikacja do układania i sprawdzania grafiku pracy dla pracowników Ciastkarni Iza (4 grafiki, 12–16 osób). Pierwsza wersja to aplikacja **webowa** (Expo + React Native for Web) z backendem **Supabase**. Później ten sam kod posłuży do aplikacji na Androida i iOS.

Zespół to junior software engineerowie – wyjaśniaj nietrywialne decyzje i proponuj prostsze rozwiązania, gdy istnieją.

## Dokumenty, które trzeba znać

- `docs/ZASADY_DZIALANIA.md` – **reguły biznesowe, źródło prawdy**. Przeczytaj przed każdą pracą nad grafikiem, dyspozycyjnością lub zamianami.
- `docs/PLAN_IMPLEMENTACJI.md` – stos, model danych, funkcje RPC, etapy prac z checklistami.

Jeśli zadanie jest sprzeczne z `ZASADY_DZIALANIA.md`, **zatrzymaj się i zapytaj** zamiast zgadywać.

## Najważniejsze reguły domeny (skrót)

- Role: `owner` (Iza), `scheduler` (Halina), `employee`.
- Grafiki mają typ `sales` lub `production`; pracownicy mają dział `sales` lub `production`.
- **Jedna osoba = najwyżej jedna zmiana dziennie, we wszystkich grafikach łącznie.** Kolizja = blokada z komunikatem podającym grafik, datę i godziny.
- Zamiany tylko w obrębie działu (sprzedaż ↔ sprzedaż między punktami, produkcja ↔ produkcja).
- Kolizje przy zamianach liczymy na stanie **po** zamianie: wymiana w ten sam dzień jest OK, oddanie komuś, kto już ma zmianę tego dnia – nie.
- Przypisanie poza dyspozycyjnością = **ostrzeżenie**, nie blokada.
- Flaga `swaps_require_approval` u którejkolwiek strony → zamiana czeka na decyzję Haliny.
- Usuwanie grafiku: najpierw archiwizacja; trwałe usunięcie tylko po wpisaniu nazwy.

## Zasady architektury

1. **Reguły krytyczne egzekwuje baza danych**, nie tylko UI: ograniczenia, triggery, RLS i funkcje RPC w Postgresie. Frontend tylko wyświetla czytelne komunikaty.
2. **Pracownicy nie piszą bezpośrednio do `shifts`** – przypisania i zamiany idą wyłącznie przez funkcje RPC (`assign_shift`, `accept_swap_request`, `decide_swap` …).
3. Operacje zamiany są **jedną transakcją**, z blokadą wiersza (`select ... for update`) przeciw wyścigom "kto pierwszy, ten bierze".
4. Ograniczenie `unique (employee_id, date)` jest `DEFERRABLE INITIALLY DEFERRED` (wymiana w ten sam dzień). Ponieważ sprawdza się dopiero przy commicie, funkcje RPC muszą **same jawnie sprawdzić kolizje** wcześniej, żeby zwrócić czytelny komunikat.
5. Każda zmiana schematu bazy = **nowa migracja** w `supabase/migrations/`. Nigdy nie edytuj już zastosowanej migracji.
6. Każda operacja zmieniająca grafik zapisuje wpis w `audit_log`.

## Konwencje kodu

- TypeScript w trybie `strict`. Bez `any` – używaj typów generowanych z bazy (`lib/types/database.ts`).
- Nazwy w kodzie i bazie **po angielsku**; teksty w interfejsie i komunikaty błędów **po polsku**.
- Daty jako `date` w bazie i stringi `YYYY-MM-DD` w TS; strefa czasowa `Europe/Warsaw`. Nie używaj lokalnych getterów `Date` do formatowania dat w logice.
- Komponenty w `components/`, ekrany w `app/` (Expo Router), logika wspólna w `lib/`.
- Interfejs projektuj najpierw na telefon (mała szerokość), potem na desktop.

## Komendy

```bash
npm run web            # start aplikacji web (Expo SDK 57)
npm run typecheck      # tsc --noEmit (najpierw raz `npm run web`, żeby powstał expo-env.d.ts)
npm run lint           # expo lint
npm run format         # prettier --write .
npm run build:web      # eksport statycznej strony do dist/

# Baza – z Supabase CLI i Dockerem
supabase start
supabase db reset      # migracje + seed od zera
supabase test db       # testy pgTAP z supabase/tests
npm run db:types       # typy TS z bazy do lib/types/database.ts

# Baza – bez Dockera (zwykły PostgreSQL 16 + pgTAP), tak samo jak w CI
npm run db:test
TEST_DB_NAME=grafik_test python3 scripts/db/gen-types.py > lib/types/database.ts
```

## Mapa kodu

- `supabase/migrations/` – schemat (`…_schema.sql`), uprawnienia (`…_rls.sql`), układanie grafiku (`…_scheduling.sql`), zamiany (`…_swaps.sql`).
- Funkcje wewnętrzne bazy są w schemacie `app_private` (niedostępny z API); RPC dla aplikacji w `public`.
- Powiadomienia trafiają do tabeli `notifications` (skrzynka); wysyłka e-maili to osobna Edge Function (do zrobienia).
- `supabase/tests/00_helpers.sql` – pomocnicy testów: `tests.create_employee`, `tests.login_as`, `tests.make_shift`, `tests.make_month`…
- `lib/types/database.ts` – typy generowane, nie edytuj ręcznie.
- `lib/auth.tsx` – sesja i profil pracownika (`useAuth()`), `lib/format.ts` – polskie daty bez lokalnych getterów `Date`.

## Jak pracujemy

- Przed implementacją większej funkcji: **najpierw plan** (plan mode), dopiero potem kod.
- Reguły biznesowe: **najpierw test** (SQL lub TS) opisujący przypadek z `ZASADY_DZIALANIA.md`, potem implementacja.
- W testach pgTAP nie łącz w jednym zapytaniu wywołania funkcji zmieniającej dane i sprawdzenia jej efektu – zapytanie widzi stan sprzed wywołania. Najpierw `do $$ begin perform …; end $$;`, potem asercja.
- Po każdej zmianie schematu: nowa migracja → testy → regeneracja `lib/types/database.ts`.
- Po zmianach zawsze uruchom `typecheck`, `lint` i testy, zanim uznasz zadanie za skończone.
- Każde zadanie na osobnej gałęzi, zmiany przez pull request. **Nie pushuj na `main`.**
- Po ukończeniu zadania odhacz je w `docs/PLAN_IMPLEMENTACJI.md`.
- Jeśli zmienia się reguła biznesowa, zaktualizuj `docs/ZASADY_DZIALANIA.md` w tym samym PR.

## Bezpieczeństwo

- Klucze Supabase tylko w `.env` (w `.gitignore`). Nigdy nie commituj `service_role` key; w kodzie frontendu tylko `anon` key.
- Narzędzia z dostępem do bazy (CLI, MCP) podłączaj **tylko do dev**, nigdy do produkcji.
- Każda nowa tabela ma włączone RLS i polityki dla trzech ról, z testem.
- Supabase domyślnie pozwala rolom API wywoływać każdą nową funkcję. Migracja dodająca funkcje kończy się więc `revoke execute … from public, anon` (i grantem dla `authenticated` tylko tam, gdzie trzeba). Funkcje wewnętrzne trzymaj w schemacie `app_private`, a RPC w `public` niech same sprawdzają rolę (`is_manager()`, `is_owner()`).
- Dane pracowników to dane osobowe – nie loguj ich niepotrzebnie i nie wrzucaj prawdziwych danych do `seed.sql`.
