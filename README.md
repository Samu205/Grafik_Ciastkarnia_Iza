# Grafik Ciastkarnia Iza

Aplikacja do układania i sprawdzania grafiku pracy dla pracowników Ciastkarni Iza: grafiki punktów sprzedaży i produkcji, miesięczne zbieranie dyspozycyjności oraz zamiany zmian między pracownikami, które od razu trafiają do grafiku.

## Dokumentacja

- [Zasady działania](docs/ZASADY_DZIALANIA.md) – reguły biznesowe (źródło prawdy)
- [Plan implementacji](docs/PLAN_IMPLEMENTACJI.md) – stos, model danych, etapy prac
- [CLAUDE.md](CLAUDE.md) – zasady pracy dla zespołu i Claude Code

## Stos

Expo SDK 57 (React Native for Web) + TypeScript, Supabase (PostgreSQL). Pierwsza wersja: aplikacja web; później Android i iOS z tego samego kodu.

## Struktura

```
app/                 ekrany (Expo Router): logowanie, Moje zmiany, Powiadomienia, Konto
components/          wspólne komponenty UI
constants/           kolory i odstępy
lib/                 klient Supabase, logowanie, formatowanie dat, typy bazy
supabase/migrations/ schemat bazy, uprawnienia (RLS), logika grafiku i zamian
supabase/tests/      testy pgTAP reguł biznesowych
supabase/seed.sql    4 grafiki i przykładowe szablony zmian
supabase/cron.sql    zadania cykliczne (alerty, przypomnienia)
scripts/db/          testy bazy bez Dockera, generator typów
```

## Pierwsze uruchomienie

1. **Zależności**

   ```bash
   npm install
   ```

   Pierwsza osoba commituje powstały `package-lock.json` (potem w CI zmieniamy `npm install` na `npm ci`).

2. **Supabase (projekt DEV)**
   - Załóż projekt na [supabase.com](https://supabase.com).
   - Zainstaluj [Supabase CLI](https://supabase.com/docs/guides/local-development/cli/getting-started) i w katalogu repo:

     ```bash
     supabase init          # utworzy supabase/config.toml, nie rusza migracji
     supabase link --project-ref <id-projektu>
     supabase db push       # wgrywa migracje z supabase/migrations
     ```

   - Wgraj dane startowe: zawartość `supabase/seed.sql` w SQL Editorze.
   - Włącz rozszerzenie **pg_cron** i uruchom `supabase/cron.sql` w SQL Editorze.
   - Authentication → URL Configuration: **Site URL** `http://localhost:8081`, a w **Redirect URLs** dodaj `http://localhost:8081/**`.

3. **Zmienne środowiskowe**

   ```bash
   cp .env.example .env
   ```

   Uzupełnij URL projektu i klucz publiczny (anon / publishable) z Settings → API.

4. **Start aplikacji**

   ```bash
   npm run web
   ```

5. **Pierwsza właścicielka (Iza)**

   Zaloguj się w aplikacji linkiem z maila. Zobaczysz komunikat "Konto nie jest jeszcze aktywne". Następnie w SQL Editorze:

   ```sql
   insert into public.employees (id, full_name, role, department)
   select id, 'Iza', 'owner', 'sales' from auth.users where email = 'adres-izy@example.com';
   ```

   Odśwież aplikację. Kolejnych pracowników będzie dodawać Iza z panelu (Etap 1, w budowie).

## Testy bazy danych

Reguły biznesowe (kolizje, zamiany, uprawnienia) są w bazie i mają testy pgTAP.

- Z Supabase CLI i Dockerem: `supabase db reset && supabase test db`
- Bez Dockera, na zwykłym PostgreSQL 16 z pgTAP: `npm run db:test` (zmienne `PGHOST`, `PGPORT`, `PGUSER`)

CI uruchamia testy bazy przy każdym pull requeście.
