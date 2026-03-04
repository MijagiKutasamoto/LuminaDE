# Modern UX Spec (LuminaDE)

## Cel
Zapewnić nowoczesny wygląd i zachowanie środowiska: szybkie, płynne, przewidywalne, keyboard-first, ale przyjazne też dla myszy i touchpada.

## Zasady UX
- Domyślny motyw: dark, wysoki kontrast, czytelna typografia.
- Spójna siatka spacingu i zaokrągleń między panelem, launcherem i ustawieniami.
- Motion jako wsparcie orientacji użytkownika, nie „efekt dla efektu”.
- Czas reakcji UI < 100 ms dla interakcji lokalnych.
- Mouse-first + keyboard parity: mysz/touchpad są pierwszorzędne, a wszystkie kluczowe akcje nadal dostępne z klawiatury.

## Panel
- Wysokość 36 px (domyślnie), modułowy układ.
- Czytelne workspace indicators i status systemowy.
- Opcjonalny smart-hide dla małych ekranów.

## Launcher
- Centralny overlay, szybkie fuzzy search.
- Sekcje: aplikacje, polecenia, pliki, ostatnie.
- Priorytet wyników na bazie historii użycia.
- Ranking i domyślna liczba wyników adaptowane do `interaction_mode` (mouse/balanced/keyboard).

## Ustawienia
- Jedno centrum konfiguracji desktop + system.
- Moduły MVP: Wygląd, Ekrany, Wejście, Skróty.
- Tryb zarządzania oknami: `tiling` / `floating` / `hybrid`.
- Tryb interakcji: `mouse_first` / `balanced` / `keyboard_first`.
- `interaction_mode` kontroluje focus policy i docelowy rozmiar hitboxów UI.
- Layout Manager: `window_mode` + `tiling_algorithm` + `master_ratio_percent` + `layout_gap`.
- Edge-case policy: zamknięcie okna wywołuje natychmiastowy re-layout, a floating windows mają clamp do aktywnego outputu.
- Model akcji GUI (`gui-action`) obsługuje toggle/cycle/set i zapisuje profil bezpośrednio po akcji.
- Dispatcher widget events (`gui-click`) mapuje `widget-id` -> akcja profilu / profile per-device / apply-input.
- Tryb „Apply/Preview/Revert” dla zmian ryzykownych (np. ekran).

## i18n
- EN + PL na start.
- Docelowo locale chain i tłumaczenia kontekstowe.

## Dostępność
- Reduced motion.
- Skalowanie UI.
- Tryb wysokiego kontrastu.
- Konfigurowalna wielkość czcionki.

## Wejście: mysz i touchpad
- `pointer_sensitivity` w zakresie `-100..100`.
- `pointer_accel_profile`: `adaptive` lub `flat`.
- `natural_scroll`: niezależnie konfigurowany.
- `tap_to_click`: niezależnie konfigurowany.
- Te ustawienia wpływają na focus policy, target hitbox i domyślne zachowanie launchera.
- Integracja runtime: `apply-input` wykonuje mapowanie per-device przez `riverctl input <device> ...` (z trybem `--dry-run`).
- Profile per-device: reguły matcher + override (`pointer_sensitivity`, `pointer_accel_profile`, `natural_scroll`, `tap_to_click`).
