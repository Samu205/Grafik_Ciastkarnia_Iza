# Plan implementacji – Grafik Ciastkarnia Iza

Plan budowy pierwszej wersji (MVP) jako **aplikacji webowej** działającej wygodnie na telefonie. Aplikacje na Androida i iPhone'a powstaną później z tego samego kodu.

Reguły biznesowe opisuje [`ZASADY_DZIALANIA.md`](./ZASADY_DZIALANIA.md). Ten plik mówi, **jak** je zbudować i w jakiej kolejności.

---

## 1. Stos technologiczny

| Warstwa           | Wybór                                                    | Uwagi                                                                   |
| ----------------- | -------------------------------------------------------- | ----------------------------------------------------------------------- |
| Frontend          | **Expo + React Native for Web**, TypeScript              | Expo Router do nawigacji. Ten sam kod posłuży później do Androida i iOS |
| Backend i baza    | **Supabase** (PostgreSQL)                                | Auth, baza, Row Level Security, funkcje SQL, Edge Functions             |
| Logowanie         | Magic link (e-mail), ewentualnie kod SMS                 | Bez haseł. Konta zakłada Iza                                            |
| Logika krytyczna  | Ograniczenia i funkcje w Postgresie                      | Patrz rozdział 3                                                        |
| Zadania cykliczne | Supabase Edge Functions + `pg_cron`                      | Alert 24 h, przypomnienia o dyspozycyjności, wygaszanie próśb           |
| Powiadomienia     | E-mail (np. Resend przez Edge Function)                  | Push dopiero w aplikacji mobilnej                                       |
| Hosting strony    | Vercel / Netlify / EAS Hosting                           | Darmowe plany wystarczą                                                 |
| Testy             | Vitest/Jest (TS), pgTAP lub testy SQL przez Supabase CLI | Testy reguł w bazie są obowiązkowe                                      |
| Repozytorium      | GitHub, pull requesty z review                           | Każdy PR czyta co najmniej jedna druga osoba                            |

---

## 2. Struktura repozytorium (docelowa)

```
.
├── CLAUDE.md                  # zasady dla Claude Code i dla zespołu
├── docs/
│   ├── ZASADY_DZIALANIA.md    # reguły biznesowe (źródło prawdy)
│   └── PLAN_IMPLEMENTACJI.md  # ten plik
├── app/                       # ekrany (Expo Router)
│   ├── (auth)/                # logowanie
│   ├── (pracownik)/           # moje zmiany, dyspozycyjność, prośby
│   ├── (halina)/              # układanie grafiku, zatwierdzenia
│   └── (iza)/                 # grafiki, pracownicy
├── components/                # komponenty UI wielokrotnego użytku
├── lib/
│   ├── supabase.ts            # klient Supabase
│   ├── types/database.ts      # typy generowane z bazy (supabase gen types)
│   └── ...                    # hooki, formatowanie dat, komunikaty
├── supabase/
│   ├── migrations/            # migracje SQL (jedyny sposób zmiany bazy)
│   ├── functions/             # Edge Functions (powiadomienia, cron)
│   ├── tests/                 # testy SQL (pgTAP)
│   └── seed.sql               # dane testowe (4 grafiki, kilku pracowników)
└── package.json
```

---

## 3. Model danych

Nazwy w kodzie i bazie są **po angielsku**, teksty w interfejsie **po polsku**.

| Tabela            | Odpowiednik      | Najważniejsze kolumny                                                                                                                                                                                                                                                                             |
| ----------------- | ---------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `employees`       | pracownicy       | `id` (= `auth.users.id`), `full_name`, `role` (`owner` / `scheduler` / `employee`), `department` (`sales` / `production`), `swaps_require_approval`, `active`                                                                                                                                     |
| `schedules`       | grafiki          | `id`, `name`, `type` (`sales` / `production`), `archived_at`                                                                                                                                                                                                                                      |
| `shift_templates` | szablony zmian   | `id`, `schedule_id`, `name`, `start_time`, `end_time`                                                                                                                                                                                                                                             |
| `schedule_months` | miesiące grafiku | `id`, `month` (pierwszy dzień miesiąca), `status` (`collecting` / `drafting` / `published`), `availability_deadline`, `reminder_sent_at`, `published_at`                                                                                                                                          |
| `shifts`          | zmiany           | `id`, `schedule_id`, `date`, `start_time`, `end_time`, `employee_id` (null = nieobsadzona), `template_id`                                                                                                                                                                                         |
| `availability`    | dyspozycyjność   | `employee_id`, `date`, `kind` (`all_day` / `hours` / `unavailable`), `start_time`, `end_time`                                                                                                                                                                                                     |
| `swap_requests`   | prośby o zamianę | `id`, `requester_id`, `shift_id`, `target_id` (null = do wszystkich), `exchange_shift_id` (null = oddanie), `accepted_by`, `status` (`open` / `awaiting_requester` / `pending_approval` / `done` / `rejected` / `cancelled` / `expired`), `decided_by`, `created_at`, `resolved_at`, `alerted_at` |
| `notifications`   | powiadomienia    | `id`, `employee_id`, `kind`, `message`, `payload`, `created_at`, `read_at`, `emailed_at` – skrzynka; e-maile wysyła Edge Function                                                                                                                                                                 |
| `audit_log`       | historia         | `id`, `actor_id`, `action`, `payload` (jsonb), `created_at`                                                                                                                                                                                                                                       |

### Ograniczenia, które MUSZĄ być w bazie

```sql
-- Jedna osoba, jedna zmiana dziennie (we wszystkich grafikach).
-- DEFERRABLE, żeby wymiana w ten sam dzień przeszła w jednej transakcji.
alter table shifts
  add constraint one_shift_per_day
  unique (employee_id, date)
  deferrable initially deferred;

-- Dyspozycyjność: jeden wpis na osobę i dzień.
alter table availability
  add constraint one_availability_per_day unique (employee_id, date);

-- Godziny muszą mieć sens.
alter table shifts add constraint shift_hours_valid check (end_time > start_time);
```

Dodatkowo **trigger** na `shifts`: dział pracownika musi zgadzać się z typem grafiku (pracownik produkcji nie trafi do grafiku sprzedaży).

### Funkcje w bazie (RPC)

| Funkcja                                                         | Kto wywołuje         | Co robi                                                                                                                                               |
| --------------------------------------------------------------- | -------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------- |
| `assign_shift(shift_id, employee_id?)`                          | Halina, Iza          | Przypisuje (lub zdejmuje); przy kolizji błąd z grafikiem, datą i godzinami; zwraca `{warning}`, gdy poza dyspozycyjnością; anuluje prośby o tę zmianę |
| `publish_month(month)`                                          | Halina, Iza          | Zmienia status na `published`; trigger wysyła powiadomienia                                                                                           |
| `create_swap_request(shift_id, target_id?, exchange_shift_id?)` | pracownik            | Tworzy prośbę do osoby lub do wszystkich; sprawdza reguły z góry                                                                                      |
| `eligible_takers(shift_id)`                                     | autor zmiany, Halina | Lista osób, które mogą przejąć zmianę (ten sam dział, brak kolizji)                                                                                   |
| `swap_problem(shift_id, taker_id, exchange_shift_id?)`          | każdy                | Podpowiedź do UI: dlaczego zamiana jest niemożliwa (`null` = możliwa)                                                                                 |
| `accept_swap_request(request_id, exchange_shift_id?)`           | adresat / chętny     | Blokuje wiersz (`for update`), sprawdza reguły, wykonuje albo ustawia `pending_approval` / `awaiting_requester`                                       |
| `respond_to_swap_offer(request_id, accept)`                     | autor                | Potwierdza lub odrzuca wymianę zaproponowaną przez chętnego                                                                                           |
| `reject_swap_request(request_id)`                               | adresat              | Odrzuca prośbę skierowaną do niego                                                                                                                    |
| `cancel_swap_request(request_id)`                               | autor                | Wycofuje prośbę                                                                                                                                       |
| `decide_swap(request_id, approve)`                              | Halina, Iza          | Zatwierdza / odrzuca; przed wykonaniem ponownie sprawdza wszystkie reguły                                                                             |
| `archive_schedule(id)` / `restore_schedule(id)`                 | Iza                  | Archiwizacja i przywracanie                                                                                                                           |
| `delete_schedule(id, confirm_name)`                             | Iza                  | Trwałe usunięcie tylko zarchiwizowanego grafiku i tylko gdy `confirm_name` = nazwa                                                                    |

Zadania cykliczne (`supabase/cron.sql`, wywoływane przez pg_cron): `app_private.process_swap_deadlines()` i `app_private.send_availability_reminders()`.

Wszystkie operacje zamiany i przypisania działają w **jednej transakcji** i zapisują wpis do `audit_log`.

### Row Level Security (szkic)

- `employee`: czyta opublikowane zmiany wszystkich (żeby wiedzieć, z kim pracuje), czyta i pisze **swoją** dyspozycyjność, czyta prośby, które go dotyczą. Zmian nie edytuje bezpośrednio – tylko przez funkcje RPC.
- `scheduler` (Halina): czyta i pisze zmiany, szablony, miesiące; czyta całą dyspozycyjność i prośby.
- `owner` (Iza): wszystko, w tym `schedules` i `employees`.
- Wersje robocze (miesiąc w statusie innym niż `published`) widzą tylko `scheduler` i `owner`.

---

## 4. Etapy prac

Każdy etap kończy się czymś, co da się pokazać Halinie albo Izie. Etapy 2–4 można dzielić między osoby.

### Etap 0 – Przygotowanie

- [ ] Ustalić z Izą, na kogo zakładamy konta (GitHub, Supabase, hosting, później sklepy)
- [ ] Zasady pracy w repo: gałąź na zadanie, PR, review, zakaz pushowania na `main`
- [ ] Projekt Supabase: osobne środowiska **dev** i **prod**
- [x] Szkielet Expo z TypeScriptem (strict), ESLint, Prettier, Expo Router _(do potwierdzenia pierwszym `npm install` + commit `package-lock.json`)_
- [x] Migracje i `seed.sql` w repo _(do zrobienia lokalnie: `supabase init` – patrz README)_
- [x] CI na GitHub Actions: typecheck, lint, formatowanie, build web, testy bazy
- [ ] Szkice ekranów (papier / Figma) i przegląd z Haliną

### Etap 1 – Fundament

- [x] Migracje: wszystkie tabele z rozdziału 3 + ograniczenia + trigger działu
- [x] Generowanie typów TS z bazy (`npm run db:types`; zapasowo `scripts/db/gen-types.py`)
- [x] Logowanie magic linkiem, powiązanie konta z rekordem w `employees`
- [x] Polityki RLS dla trzech ról + testy RLS
- [ ] Panel Izy: dodawanie, edycja, archiwizacja, przywracanie i trwałe usuwanie grafików (z wpisywaniem nazwy) – _baza i testy gotowe, brak UI_
- [ ] Panel Izy: pracownicy – dział, rola, flaga zatwierdzania zamian, dezaktywacja
- [ ] Szablony zmian w każdym grafiku – _baza i przykładowe dane gotowe, brak UI; godziny do potwierdzenia z Haliną_

### Etap 2 – Dyspozycyjność

- [ ] Halina otwiera zbieranie na miesiąc i ustawia termin
- [ ] Ekran pracownika: kalendarz miesiąca, wybór "cały dzień / od–do / nie mogę"
- [ ] "Skopiuj z poprzedniego miesiąca"
- [ ] Widok Haliny: kto oddał, kto nie
- [ ] Edge Function + cron: przypomnienie e-mail przed terminem – _funkcja w bazie i `supabase/cron.sql` gotowe, brak wysyłki e-maili_

### Etap 3 – Układanie i publikacja grafiku

- [ ] Widok miesiąca dla grafiku: dni × zmiany
- [ ] Tworzenie zmian z szablonów (np. "wypełnij miesiąc szablonami")
- [ ] `assign_shift`: przypisanie z podglądem dyspozycyjności – _funkcja i testy gotowe, brak UI_
- [x] Blokada kolizji z komunikatem: grafik, data, godziny (w bazie)
- [x] Ostrzeżenie przy przypisaniu poza dyspozycyjnością (w bazie)
- [ ] Edycja godzin pojedynczej zmiany
- [ ] `publish_month` + e-mail do wszystkich – _publikacja i powiadomienia w bazie gotowe, brak wysyłki e-maili_
- [x] Widok **"Moje zmiany"** – wszystkie zmiany pracownika ze wszystkich grafików w jednym miejscu

### Etap 4 – Zamiany

- [x] Funkcje `create_swap_request`, `eligible_takers`, `accept_swap_request`, `decide_swap` (+ `respond_to_swap_offer`, `reject_swap_request`, `cancel_swap_request`)
- [x] **Testy SQL wszystkich przypadków z tabeli w `ZASADY_DZIALANIA.md` §7** – przed UI
- [ ] UI: prośba do konkretnej osoby (lista tylko uprawnionych)
- [ ] UI: prośba do wszystkich – kto pierwszy, ten bierze (test wyścigu dwóch osób)
- [ ] Wariant oddania i wymiany, w tym wymiana w ten sam dzień
- [ ] Kolejka "czeka na zatwierdzenie" dla Haliny, wyróżnienie w grafiku
- [ ] Powiadomienia o prośbach i wykonanych zamianach – _w aplikacji (ekran Powiadomienia) gotowe, brak e-maili_
- [x] Cron: alert dla Haliny 24 h przed zmianą bez chętnych, wygaszanie starych próśb (`supabase/cron.sql` do uruchomienia na projekcie)

### Etap 5 – Dopracowanie

- [ ] Każdy ekran sprawdzony na małym telefonie
- [ ] PWA – strona instalowalna na ekranie telefonu
- [ ] Historia zmian w grafiku (widok `audit_log` dla Haliny i Izy)
- [ ] Kopie zapasowe bazy prod i spisana procedura przywracania
- [ ] Krótka instrukcja dla pracowników (jedna strona ze zrzutami ekranu)

---

## 5. Wdrożenie

1. **Testy automatyczne reguł** przechodzą w CI.
2. **Pokaz dla Haliny i Izy** po etapie 3: Halina układa próbny grafik na jeden punkt.
3. **Pilotaż** na jednym grafiku (np. Ogrody) z 3–4 osobami przez 2 tygodnie.
4. **Pierwszy pełny miesiąc** w aplikacji, kartka wisi równolegle jako zabezpieczenie.
5. **Przejście na aplikację** – kartka znika, zamiany tylko przez aplikację.
6. **15 minut pokazu** dla pracowników na zebraniu.

---

## 6. Definicja "zrobione" dla każdego zadania

- [ ] Kod przechodzi `typecheck`, `lint` i testy
- [ ] Reguła biznesowa ma test (jeśli zadanie jej dotyczy)
- [ ] Zmiana bazy jest migracją w `supabase/migrations/`
- [ ] Ekran sprawdzony na szerokości telefonu
- [ ] PR przejrzany przez drugą osobę z zespołu
- [ ] Jeśli zmieniła się reguła – zaktualizowany `ZASADY_DZIALANIA.md`

---

## 7. Później (po MVP)

- Build Android (Google Play: 25 USD jednorazowo) i iOS (Apple: 99 USD rocznie) przez EAS
- Powiadomienia push (Expo Notifications)
- Pozostałe punkty z `ZASADY_DZIALANIA.md` §9
