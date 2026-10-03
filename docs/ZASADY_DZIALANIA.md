# Zasady działania – Grafik Ciastkarnia Iza

Ten dokument opisuje **jak aplikacja ma działać** z punktu widzenia ciastkarni. Jest źródłem prawdy dla reguł biznesowych. Jeśli kod zachowuje się inaczej niż ten dokument, to błąd w kodzie albo dokument wymaga aktualizacji po uzgodnieniu z Izą i Haliną.

## 1. Problem, który rozwiązujemy

- Grafik układa Halina na kartce w kratkę.
- Grafik wisi w jednym miejscu, więc kto nie jest w pracy, ten go nie widzi.
- Pracownicy zamieniają się zmianami "na gębę" i **nikt o tym nie wie** – kartka pokazuje stary stan, ktoś nie przychodzi albo przychodzą dwie osoby.

**Cel:** jedno źródło prawdy o grafiku, dostępne z telefonu, w którym żadna zamiana nie może się wydarzyć poza grafikiem.

## 2. Role

| Rola | Kto | Co może |
|---|---|---|
| **Iza** (właścicielka) | Iza | Wszystko, co Halina, plus: dodawanie, archiwizowanie i usuwanie grafików, zarządzanie pracownikami i ich rolami |
| **Halina** (układająca) | Halina | Otwiera zbieranie dyspozycyjności, układa i publikuje grafiki, edytuje zmiany, zatwierdza zamiany osób z flagą zatwierdzania, dostaje alerty |
| **Pracownik** | 12–16 osób | Widzi opublikowany grafik i swoje zmiany, zgłasza dyspozycyjność, wysyła i przyjmuje prośby o zamianę |

## 3. Grafiki (miejsca pracy)

| Grafik | Typ |
|---|---|
| Liszki | sprzedaż |
| Lodołamacz Piekary | sprzedaż |
| Ogrody | sprzedaż |
| Produkcja Liszki | produkcja |

- Każdy grafik ma **typ**: `sprzedaż` albo `produkcja`. Typ decyduje, kto z kim może się zamieniać.
- Grafiki dodaje tylko **Iza**. Nowy grafik od razu działa według tych samych zasad co istniejące.
- **Usuwanie jest zabezpieczone dwustopniowo:**
  1. "Usuń" = **archiwizacja**. Grafik znika z widoków, ale dane zostają i Iza może go przywrócić.
  2. **Trwałe usunięcie** zarchiwizowanego grafiku wymaga wpisania jego dokładnej nazwy w oknie potwierdzenia. Przypadkowe kliknięcie nic nie robi.

## 4. Pracownicy

- Jest jedna **wspólna lista pracowników** (nie osobna dla każdego grafiku).
- Każdy pracownik ma **dział**: `sprzedaż` albo `produkcja`.
- Pracownik ze sprzedaży może pracować w różnych punktach sprzedaży (np. raz Liszki, raz Ogrody).
- Każdy pracownik ma flagę **"zamiany wymagają zatwierdzenia"** (domyślnie wyłączona). Halina włącza ją np. nowym osobom.

## 5. Zmiany

- Każdy grafik ma **szablony zmian** (np. "Ranna 6:00–14:00", "Popołudniowa 14:00–20:00").
- Halina tworzy zmiany w grafiku z szablonów jednym kliknięciem.
- Godziny można edytować:
  - w szablonie (dotyczy nowych zmian),
  - w konkretnym dniu (np. Wigilia krócej) – bez wpływu na resztę grafiku.

### Zasada nadrzędna: jedna osoba, jedna zmiana dziennie

- Pracownik może mieć **najwyżej jedną zmianę w danym dniu, we wszystkich grafikach łącznie**.
- Próba przypisania drugiej zmiany tego samego dnia jest **zablokowana**.
- Komunikat zawsze podaje **grafik, datę i godziny** kolidującej zmiany, np.:
  > Ania ma już zmianę 14.10 (wtorek) – Ogrody, 10:00–14:00
- Zasada obowiązuje wszędzie: przy układaniu grafiku przez Halinę, przy edycji, przy zamianach.

## 6. Dyspozycyjność i miesięczny cykl grafiku

Grafik układa się **co miesiąc**. Przed ułożeniem każdy mówi, kiedy może pracować.

1. **Halina otwiera zbieranie** dyspozycyjności na kolejny miesiąc i ustawia termin (np. do 25-go).
2. **Pracownicy dostają powiadomienie** i zaznaczają dla każdego dnia:
   - cały dzień,
   - konkretne godziny (od–do),
   - nie mogę.
   Dostępny jest skrót "skopiuj z poprzedniego miesiąca".
3. **Przed terminem** osoby, które nic nie wpisały, dostają przypomnienie. Halina widzi listę: kto oddał, kto nie.
4. **Halina układa grafik** i przy każdej osobie i dniu widzi jej dyspozycyjność (np. zielony – może, czerwony – nie może, szary – nie podała).
5. **Przypisanie poza dyspozycyjnością = ostrzeżenie, nie blokada.** Halina może świadomie przypisać osobę (np. po rozmowie).
6. **Publikacja.** Do czasu publikacji grafik jest wersją roboczą widoczną tylko dla Haliny i Izy. Po kliknięciu "opublikuj" wszyscy dostają powiadomienie.

Status miesiąca: `zbieranie` → `układanie` → `opublikowany`.

## 7. Zamiany i oddawanie zmian

### Kto z kim

| Dział | Może się zamieniać z |
|---|---|
| sprzedaż | sprzedażą – także między punktami (np. Ogrody ↔ Liszki) |
| produkcja | produkcją |

Zamiana sprzedaż ↔ produkcja jest **zawsze zablokowana**.

### Dwa tryby prośby

**A. Do konkretnej osoby**
- Pracownik wybiera swoją zmianę → "poproś o zastępstwo" → wybiera osobę.
- Lista pokazuje **tylko osoby, które mogą przejąć** zmianę (ten sam dział, brak kolizji po zamianie).
- Adresat klika "przyjmuję" albo "odrzucam". Po odrzuceniu autor może poprosić kogoś innego.

**B. Do wszystkich ("giełda")**
- Powiadomienie dostają tylko osoby, które mogą przejąć zmianę.
- Przy osobach widać informację, czy zgłosiły dyspozycyjność na ten dzień.
- **Kto pierwszy, ten bierze.** Po przyjęciu prośba znika u pozostałych.

### Dwa warianty

- **Oddanie** – przejmujący bierze zmianę autora, nic w zamian.
- **Wymiana** – przejmujący bierze zmianę autora, a autor bierze jedną zmianę przejmującego.

### Sprawdzanie kolizji – liczy się stan PO zamianie

Aplikacja sprawdza, jak będzie wyglądał grafik obu osób **po** wykonaniu operacji. Jeśli ktokolwiek miałby dwie zmiany jednego dnia – blokada z podaniem grafiku i daty.

| Przykład | Wynik |
|---|---|
| Kasia nie ma zmiany 14.10, przejmuje (oddanie) zmianę Ani z 14.10 | ✅ dozwolone |
| Kasia ma zmianę 14.10, przejmuje (oddanie) zmianę Ani z 14.10 | ❌ blokada – Kasia miałaby dwie zmiany |
| Ania ma rano Liszki 14.10, Kasia popołudnie Ogrody 14.10 – wymiana | ✅ dozwolone – każda dalej ma jedną zmianę |
| Ania oddaje pon., bierze śr. Kasi; Ania w śr. wolna, Kasia w pon. wolna | ✅ dozwolone |
| Ania oddaje pon., bierze śr. Kasi; Ania ma już inną zmianę w śr. | ❌ blokada |
| Ania (sprzedaż) chce oddać zmianę Tomkowi (produkcja) | ❌ blokada – różne działy |

### Zatwierdzanie

- Domyślnie zamiany **przechodzą automatycznie** po przyjęciu przez drugą osobę.
- Jeśli **którakolwiek** strona ma flagę "zamiany wymagają zatwierdzenia", zamiana trafia do Haliny jako **"czeka na zatwierdzenie"**. W grafiku jest wyróżniona (np. na żółto) i do decyzji Haliny obowiązuje stary stan.
- Przed wykonaniem zatwierdzonej zamiany aplikacja **ponownie** sprawdza wszystkie reguły (grafik mógł się w międzyczasie zmienić).

### Brak chętnych

- Jeśli prośba nie została przyjęta, a do zmiany zostało **24 godziny**, Halina dostaje alert, np.:
  > Ania szuka zastępstwa na jutro 6:00 w Liszkach – nikt nie przyjął.
- Do czasu zamiany zmiana nadal należy do autora prośby.
- Prośba, której zmiana już się odbyła, automatycznie **wygasa**.

### Po każdej wykonanej zamianie

- Grafik aktualizuje się od razu.
- Powiadomienie dostają obie strony i Halina (informacyjnie).
- Operacja jest zapisana w historii: kto, co, kiedy.

## 8. Powiadomienia

| Zdarzenie | Kto dostaje |
|---|---|
| Otwarcie zbierania dyspozycyjności | wszyscy pracownicy |
| Przypomnienie przed terminem dyspozycyjności | ci, którzy nie oddali |
| Publikacja grafiku | wszyscy |
| Zmiana w opublikowanym grafiku dotycząca pracownika | ten pracownik |
| Nowa prośba o zamianę | adresat lub wszyscy uprawnieni |
| Przyjęcie / odrzucenie prośby | autor |
| Zamiana czeka na zatwierdzenie | Halina |
| Wykonana zamiana | obie strony + Halina |
| Brak chętnych 24 h przed zmianą | Halina |

W pierwszej wersji powiadomienia idą **e-mailem**. Push przyjdzie z aplikacją mobilną.

## 9. Poza pierwszą wersją (świadomie odłożone)

- Aplikacje na Androida i iPhone'a (z tego samego kodu).
- Powiadomienia push.
- Wyjątek od zasady jednej zmiany dziennie, odblokowywany tylko przez Izę.
- Automatyczne wyłączanie flagi zatwierdzania po okresie próbnym.
- Liczenie godzin do wypłaty, eksport do PDF, wydruk na zaplecze.
- Automatyczna propozycja grafiku z dyspozycyjności.

## 10. Otwarte pytania

- Czy wszyscy pracownicy mają e-mail, czy logowanie/powiadomienia muszą iść SMS-em?
- Czy konta usług (GitHub, Supabase, hosting, sklepy) zakładamy na ciastkarnię czy na osobę?
