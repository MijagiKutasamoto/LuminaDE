# Mature Panel + Launcher Spec

## Panel (dojrzały)
- Stabilny top bar z modułami: workspace, task area, tray, audio, sieć, bateria, zegar, powiadomienia.
- Tryby: always visible / smart-hide / auto-hide per display profile.
- Multi-monitor awareness: osobny panel per output, niezależna konfiguracja.
- Fullscreen surfaces per output (panel i UI renderowane per monitor, bez sztywnych wymiarów).
- Integracja z compositor state: aktywne okno, fullscreen, scratchpad, mode hints.
- Szybkie akcje systemowe: dźwięk, jasność, sieć, zasilanie bez otwierania ustawień.
- Spójna animacja i feedback focus/hover/press.

## Launcher (dojrzały)
- Pokazuje wszystkie zainstalowane programy (indeks PATH + desktop entries).
- Fullscreen launcher overlay na aktywnym monitorze + możliwość mirror na wszystkie monitory.
- Fuzzy search z rankingiem: trafność + częstotliwość + recency.
- Kategorie: Applications, Commands, Files, Recent, System actions.
- Szybkie skróty: Enter uruchamia, Tab autouzupełnia, Ctrl+K czyści, Alt+1..9 quick-select.
- Tryb command runner (np. shell commands) i tryb app launcher.
- Historia i personalizacja priorytetów wyników.

## UX i wydajność
- Czas otwarcia launchera docelowo < 60 ms na typowym sprzęcie.
- Aktualizacja panelu event-driven, bez kosztownego polling loop.
- Graceful degradation przy dużej liczbie aplikacji.
- Dynamiczne wykrywanie rozdzielczości i zmian outputów (hotplug monitorów).

## Integracja i18n
- Wszystkie etykiety i stany tłumaczone (EN/PL + kolejne locale).
- Różne formaty daty/czasu i liczby zależnie od locale.
