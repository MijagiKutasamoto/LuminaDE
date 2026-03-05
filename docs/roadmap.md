# LuminaDE Roadmap

## Wersja aktualna: v0.5-dev

### Plan v0.4.1 (rozbudowa panelu + wejscie w Etap 2)
- [x] Pixel-pass wygladu panel/launcher/settings (Aurora Glass)
- [x] Strict native mode toggle dla panelu: `LUMINADE_NATIVE_PANEL_REQUIRED=1` (bez fallback-first)
- [x] Domkniecie natywnej sciezki `layer-shell` dla testow srodowiska (configure/ack + commit)
- [x] Wydzielenie stanu panelu per-output dla natywnego backendu (domyslnie `.luminade/native-panel-state-<output>.tsv`)
- [ ] Native loop `wl_surface`/`zwlr_layer_surface_v1` jako primary path (bez bridge TSV jako sciezki glownej)
- [x] Integracja akcji systemowych panelu z Etapem 2 (audio/siec/zasilanie) jako stale widgety (MVP)
- [x] Statusowe widgety panelu (Net/Vol/Bat) z fallback probe chain
- [x] Wspolny helper akcji systemowych w `luminade-core` (panel + settings)
- [x] Skrypt smoke testow `scripts/smoke-v041.sh` (prepare + run)

### Plan v0.4.2 (onboarding / first-run)
- [x] Nowa aplikacja `welcome` (first-run onboarding po instalacji)
- [x] Ekran "co gdzie jest" (panel / launcher / settings / skróty)
- [x] Kreator podstawowej konfiguracji (język, tryb interakcji, layout, input)
- [x] Zapis wyborów do `.luminade/profile.conf`
- [x] Znacznik ukończenia first-run (`.luminade/first-run.done`)
- [x] Integracja z launcherem i sesją (uruchomienie tylko dla nowej instalacji)

### Zakres wydania v0.4 (zamknięty)
- [x] GUI-first runtime dla `panel` / `launcher` / `settings`
- [x] Dojrzały `sessiond` (supervisor, restart policy, IPC socket + fallback queue)
- [x] Mysz-first UX: click/context, quick actions, anti-flood
- [x] Multi-monitor: `widget@output`, workspace click routing per output
- [x] Session/login packaging: wpis sesji, autostart, skrypt instalacyjny
- [x] Settings vNext: i18n PL/EN + `System & Power` + akcje audio

### Cel v0.5 (następny release)
- [x] Domknięcie natywnego panelu `layer-shell` (bez fallback-first): sukces native oznacza realny lifecycle `create + configure/ack + commit`
- [x] Native-primary runtime: po pierwszym sukcesie native panel nie wraca do bridge TSV (domyślnie `LUMINADE_NATIVE_PANEL_PRIMARY=1`)
- [x] Stabilizacja integralności źródeł UI (`panel`/`launcher`/`settings`): cleanup zdublowanych końcówek plików i błędów scope
- [x] Rozszerzenie ustawień: ekrany (scale/układ), skróty, domyślne aplikacje
- [x] Rozszerzenie ustawień (MVP): ekrany scale/układ zapisane w profilu + obsługa w Settings
- [x] i18n pełne: tłumaczenia panel/launcher + fallback locale chain
- [x] Welcome app v1 polish: content/help flows + telemetry-free UX checks
- [x] Fundament systemu motywów (tokeny, profile, load/save, fallback)
- [x] Theming end-to-end: tokeny/profil podpięte do dekoracji wszystkich powierzchni (`launcher/settings/welcome` + spójny panel)
- [x] Kontrakt persistencji ustawień użytkownika (`.luminade/*.conf`) + load-on-login

### Cel v0.5.1 (appearance + themes)
- [ ] Zakładka `Wygląd` w Settings (kolorystyka, ikony, warianty)
- [ ] Live preview motywu (panel/launcher/settings)
- [ ] Import/export profili motywów
- [ ] Presety motywów (minimum 3) + migracja kompatybilności

## Etap 0 (zrobione)
- Monorepo Zig + trzy binarki
- Wspólny core
- i18n (PL/EN)
- Strategia forka River

## Etap 1 (MVP sesji)
- [x] Pełny `luminade-sessiond` (supervisor + restart policy + unix socket IPC + event routing + state snapshot)

## Etap 1.5 (GUI runtime)
- [x] GUI-first flow panel/launcher/settings
- [x] Layout Manager (tiling/floating/hybrid + master_stack/grid)
- [x] Device profiles + `apply-input` bridge
- [x] Native panel bridge adapter (`NativePanelSession` + frame commit state)
- [x] Native-first probe socketu Wayland (`XDG_RUNTIME_DIR` + `WAYLAND_DISPLAY`) z automatycznym fallbackiem bridge
- [x] Layer-shell bootstrap klienta: `wl_registry` discovery + smoke-create panel surface (`anchor` + `exclusive_zone`)
- [x] Hardening native panel: anti-flood throttling/backoff + dedupe fallback + atomowy zapis state
- [x] Hardening native panel v2: anti-log-flood + circuit-breaker dla błędów protokołu Wayland
- [x] Launcher favorites: pin/unpin/list + ranking pinned-first + integracja ze settings
- [x] Launcher mouse UX: click-to-launch + context actions (favorite add/remove, remove-history) przez GUI event queue
- [x] Settings live preview: miniatura layoutu generowana przez `ui.applyWindowLayout`
- [x] Panel mouse UX: quick-launch icons + click-to-launch + context actions przez GUI event queue
- [x] Panel pointer bridge v1: mapowanie `UiEvent(x,y)` -> hit-test widget -> akcje `click/context/scroll`
- [x] Panel multi-monitor UX: adresowanie `widget@output` + per-output anti-flood launch guard
- [x] Panel workspace UX: `ws-*@output` click z backendem River (`focus-output` + `set-focused-tags`)
- [x] Session login-ready: `wayland-sessions` desktop entry + autostart sessiond + installer script
- [x] Settings vNext: i18n PL/EN dla GUI + sekcja System & Power (lock/suspend/logout/audio)
- [x] Pełny natywny panel `layer-shell` (MVP gotowy do testow srodowiska)

## Etap 2 (system integration) dla wersji 0.5.2 powinno być dociągnięte
- [ ] Audio, sieć, zasilanie (partial: settings + panel maja akcje MVP, w tym open-network)
- [x] Unified Event Bus v0 (sessiond): `SUB/UNSUB/PUB` + fan-out przez UNIX datagram
- [x] Standaryzacja storage runtime i ładowania ustawień na starcie sesji
- [ ] Portal integration
- [ ] Polkit agent
- [ ] Indeksacja aplikacji: PATH + .desktop + cache i incremental refresh (MVP++: partial refresh per `.desktop` source + prune removed)
- [ ] Unified notification center + quick settings panel
- [ ] Event-driven monitor management (hotplug, primary switch, per-output state) (partial: hotplug refresh działa dla panel/launcher)
- [x] Watcher outputów: automatyczny refresh `OutputProfile` + render spec/scaling po hotplug

## Etap 3 (dojrzałość) ver 1.0 open
- [ ] Stability hardening
- [ ] Telemetria opt-in
- [ ] QA i release cycle dla Fedora/Arch
- [ ] Pełne accessibility profile (reduced motion, high contrast, font scaling)
- [ ] `luminade-ui` v1: Wayland-native backend + renderer GPU + API dla zewnętrznych aplikacji
