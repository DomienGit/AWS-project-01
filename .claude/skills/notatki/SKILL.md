---
description: Zapisz najważniejsze komendy, pojęcia i uwagi z bieżącej rozmowy jako notatki .md do nauki AWS/DevOps. Wywoływany ręcznie jako /notatki na koniec ćwiczenia lub sesji.
---

Zapisz najważniejsze komendy, pojęcia i uwagi z bieżącej rozmowy jako notatki .md do nauki AWS/DevOps. Wywoływany ręcznie jako /notatki.

## Krok 1: Ustal temat i ścieżkę

- Zidentyfikuj temat rozmowy (usługa AWS, problem, ćwiczenie). Jeśli nieoczywisty - zapytaj usera.
- Zaproponuj ścieżkę pliku na podstawie tematu i **istniejącej** struktury repo. Nie wymyślaj katalogów - jeśli nie ma jeszcze folderu, zaproponuj np. `<temat>/NOTES.md` i zapytaj czy pasuje. User może zmienić.
- Jeśli plik już istnieje -> **DOPISUJ / aktualizuj sekcje**, nie nadpisuj całości. Zachowaj dotychczasowy układ.

## Krok 2: Zawartość notatki

Język: **PL + EN terminologia** - polskie wyjaśnienia, ale nazwy usług, komendy, flagi, nazwy zasobów (bucket, instance, IAM role) po angielsku. Ułatwia wyszukiwanie w docs.

Użyj sekcji, które mają sens dla danego ćwiczenia (nie pakuj wszystkich na siłę):

- **Cel** - co robimy i dlaczego (1-2 zdania)
- **Pojęcia** - kluczowe terminy z krótkim wyjaśnieniem (np. *Bucket* - pojemnik na obiekty w S3)
- **Komendy** - bloki ```bash z komentarzem nad każdą komendą wyjaśniającym **dlaczego**, nie tylko co
- **Gotchas / uwagi** - pułapki, zaskoczenia, niestandardowe zachowanie, rzeczy które kosztowały czas
- **Linki** - URL do oficjalnych docs AWS, **tylko jeśli faktycznie padły w rozmowie** - nie wymyślaj URL-i
- **Następne kroki** - co warto zrobić potem (opcjonalnie)

## Krok 3: Zasady twarde

- **Nie wymyślaj komend** - używaj tylko tych, które faktycznie padły w rozmowie lub plikach projektu.
- **Nie kopiuj ścian tekstu** - notatka ma być wyszukiwalna i zwięzła, koncentruj się na tym co nowe / nieoczywiste.
- **Każda komenda musi mieć komentarz wyjaśniający** (dlaczego, nie tylko co) - bez tego za 3 miesiące będzie martwy tekst.
- **Pliki .sh to osobny materiał** - nie dubluj ich zawartości w notatkach bez potrzeby; odsyłaj do nich (`patrz ec2/launch-instance.sh`).
- **Zachowaj terminologię AWS po angielsku** - nie tłumacz "bucket" na "wiadro".

## Krok 4: Po zapisaniu

Pokaż userowi krótkie potwierdzenie: ścieżkę pliku + 1-3 wypunktowania co zostało dodane. Bez lania wody.
