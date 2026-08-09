---
description: Handoff kontekstu rozmowy między PC-tami (user pracuje na 2 maszynach). Tryb domyślny (/handoff) zapisuje stan pracy do .handoff/CURRENT.md i robi lokalny commit. Tryb load (/handoff load) wczytuje najnowszy handoff na nowym PC.
---

Handoff kontekstu rozmowy między PC-tami (user pracuje na 2 maszynach). Tryb domyślny: zapisz stan pracy do .handoff/CURRENT.md i zrób lokalny commit. Tryb load: wczytaj najnowszy handoff.

## Tryb 1: SAVE (domyślny - wywołany jako `/handoff` lub `/handoff save`)

Zrzuć aktualny stan pracy do `.handoff/CURRENT.md` (rolling - nadpisz całość).

### Krok 1: Zbierz z rozmowy

- **Co zostało zrobione** w tej sesji (2-4 bullety, konkret)
- **W trakcie** - na czym dokładnie stanęło (np. "utworzony bucket, nie skonfigurowany policy")
- **Następne kroki** - co jest kolejną rzeczą do zrobienia
- **Pliki dotknięte w sesji** - ścieżki względne
- **Niecommitowane zmiany w repo** - uruchom `git status`, wypisz lub napisz "czysto"
- **Środowisko wykonania** - skąd user odpala komendy (AWS CloudShell / instancja EC2 / laptop z `aws configure` / inne) + region + ewentualne quirki (np. "MY_IP z checkip.amazonaws.com = IP CloudShell, nie laptopa")
- **Decyzje z sesji** - co user wybrał w tej konwersacji (np. "strategia pełnego recreate", "keypair odstawiony na bok")
- **Do sprawdzenia przed startem** - prerequisites które user musi mieć na nowym PC żeby kontynuować (np. "`~/devops-vars.sh` istnieje", "region CloudShell = eu-central-1", "`$MAVEN_AMI` ustawione")

### Krok 2: Zapisz plik w tym formacie

```markdown
# Handoff - <TEMAT/USŁUGA>

Ostatnia aktualizacja: YYYY-MM-DD HH:MM | PC: <hostname> | branch: <branch>

## Co zostało zrobione
- ...

## W trakcie (gdzie stanęło)
- ...

## Następne kroki
- ...

## Pliki dotknięte w sesji
- path/to/file.sh
- path/to/notes.md

## Niecommitowane zmiany w repo
- (lista z `git status` albo "czysto")

## Środowisko wykonania
- (skąd user odpala komendy AWS + region + quirki IP/etc)

## Decyzje z sesji
- (co user wybrał w tej rozmowie)

## Do sprawdzenia przed startem (prerequisites)
- (co musi być gotowe na nowym PC żeby kontynuować)
```

Timestamp z `date +"%Y-%m-%d %H:%M"`, hostname z `hostname`, branch z `git rev-parse --abbrev-ref HEAD`.

### Krok 2.5: Pokaż userowi plik do akceptacji (opcjonalnie, ale zalecane przy długich sesjach)

Po zapisaniu pokaż userowi krótko ścieżkę pliku + streść co w nim jest (albo poproś o `cat .handoff/CURRENT.md`). Czekaj na feedback, dopuszczaj poprawki. Dopiero po akceptacji rób Krok 3 (git).

Dla krótkich / prostych sesji ten krok można pominąć. Dla długich, wielowątkowych, lub z wieloma decyzjami - **zawsze pokazuj**.

### Krok 3: Git

1. `git add .handoff/CURRENT.md` (TYLKO ten plik - nie stage'uj niczego innego bez pytania usera)
2. `git commit -m "chore: handoff <temat> (<data>)"`
3. **NIE pushuj automatycznie.** Pokaż userowi komendę:
   ```
   git push
   ```
   Plus przypomnienie: na PC2 zacznij od `git pull`.

### Krok 4: Potwierdzenie

Pokaż userowi krótko: ścieżkę pliku + "zcommitowano lokalnie, puszuj przed przejściem na PC2 (`git push`)".

---

## Tryb 2: LOAD (wywołany jako `/handoff load`)

1. Przeczytaj `.handoff/CURRENT.md`
2. Streść userowi w 4-6 bulletach: co było zrobione, gdzie stanęło, co dalej, ważny kontekst
3. Zapytaj: "od czego zaczynamy?" albo jeśli następny krok jest jasny z handoffa - zaproponuj go
4. **Nie wchodź w tryb implementacji bez potwierdzenia usera**

Jeśli `.handoff/CURRENT.md` nie istnieje - powiedz userowi że nie ma handoffa do wczytania i zapytaj od czego zaczyna.

---

## Zasady twarde

- **Krótki i skanowalny** - CURRENT.md to scratchpad, nie esej. Max ~50 linii.
- **Nie kopiuj całej rozmowy** - koncentruj się na stanie pracy i tym co trzeba do kontynuacji.
- **Konkrety nie ogólniki** - "utworzony bucket `moj-test-bucket` w eu-west-1" zamiast "zrobione S3".
- **Niecommitowane zmiany są kluczowe** - user musi wiedzieć czy musi coś commitować przed zmianą PC.
- **Nie pushuj automatycznie** - decyzja o pushu należy do usera (bezpieczeństwo: hooks, inne branche, WIP).
- **Nie stage'uj niczego poza .handoff/CURRENT.md** - reszta z `git status` to może być user's WIP.
