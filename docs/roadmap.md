# LuminaDE Roadmap

## Wersja aktualna: v0.4 ZIG

### Zakres wydania v0.4 (zamknięty)
- [x] GUI-first runtime dla `panel` / `launcher` / `settings`
- [x] Dojrzały `sessiond` (supervisor, restart policy, IPC socket + fallback queue)
- [x] Mysz-first UX: click/context, quick actions, anti-flood
- [x] Multi-monitor: `widget@output`, workspace click routing per output
- [x] Session/login packaging: wpis sesji, autostart, skrypt instalacyjny
- [x] Settings vNext: i18n PL/EN + `System & Power` + akcje audio

### Cel v0.5 (następny release)
- [ ] Domknięcie natywnego panelu `layer-shell` (bez fallback-first)
- [ ] Rozszerzenie ustawień: ekrany (scale/układ), skróty, domyślne aplikacje
- [ ] i18n pełne: tłumaczenia panel/launcher + fallback locale chain

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
- [x] Panel multi-monitor UX: adresowanie `widget@output` + per-output anti-flood launch guard
- [x] Panel workspace UX: `ws-*@output` click z backendem River (`focus-output` + `set-focused-tags`)
- [x] Session login-ready: `wayland-sessions` desktop entry + autostart sessiond + installer script
- [x] Settings vNext: i18n PL/EN dla GUI + sekcja System & Power (lock/suspend/logout/audio)
- [ ] Pełny natywny panel `layer-shell`

## Etap 2 (system integration)
- [ ] Audio, sieć, zasilanie
- [ ] Portal integration
- [ ] Polkit agent
- [ ] Indeksacja aplikacji: PATH + .desktop + cache i incremental refresh
- [ ] Unified notification center + quick settings panel
- [ ] Event-driven monitor management (hotplug, primary switch, per-output state)
- [ ] Watcher outputów: automatyczny refresh `OutputProfile` + render spec/scaling po hotplug

## Etap 3 (dojrzałość)
- [ ] Stability hardening
- [ ] Telemetria opt-in
- [ ] QA i release cycle dla Fedora/Arch
- [ ] Pełne accessibility profile (reduced motion, high contrast, font scaling)
- [ ] `luminade-ui` v1: Wayland-native backend + renderer GPU + API dla zewnętrznych aplikacji
