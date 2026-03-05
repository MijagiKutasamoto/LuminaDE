# LuminaDE

LuminaDE to autorskie środowisko graficzne oparte o **River** jako kompozytor Wayland i komponenty pisane w **Zig**.

Projekt jest przygotowany pod dwa warianty dystrybucji:
- Arch-based
- Fedora-based

## Założenia

- Kompozytor: fork `river` (kontrola nad aktualizacjami upstream)
- Komponenty UI w Zig:
	- panel (`luminade-panel`)
	- launcher (`luminade-launcher`)
	- ustawienia (`luminade-settings`)
- Wielojęzyczność (na start EN/PL)
- Integracja ustawień desktop + system

## Komentarze Srodowiska (PL)

- `panel`: gorna belka sesji (workspace, szybkie akcje, statusy `Net/Vol/Bat`).
- `launcher`: centralny overlay do wyszukiwania aplikacji i polecen.
- `settings`: centrum konfiguracji desktop + podstawowe akcje systemowe.
- `welcome`: onboarding pierwszego uruchomienia (jezyk, tryb interakcji, layout).
- `sessiond`: supervisor aplikacji sesji (start/restart/routing zdarzen).
- `luminade-core`: wspolny runtime, profile, i18n, helpery systemowe.
- `luminade-ui`: kontrakt GUI + dekoracje + model ikon `icon:<nazwa> <tekst>`.

## Struktura repo

- `apps/panel` – panel
- `apps/launcher` – launcher
- `apps/settings` – aplikacja ustawień
- `libs/luminade-core` – wspólny core (config + i18n)
- `config` – pliki sesji River + locale
- `scripts` – automatyzacja forka/sync River
- `docs` – architektura, roadmapa, pakietowanie

## Wymagania

- Zig `0.13+`
- River + Wayland stack (dla realnej sesji)

## Build i uruchomienie

```bash
zig build
zig build run-panel
zig build run-launcher
zig build run-settings
zig build run-sessiond
```

## Planowany wyglad (referencja)

Aktualny kierunek wizualny LuminaDE (dla dalszych iteracji UI) jest oparty o dwa mockupy w root repo:
- `Gemini_Generated_Image_gbpm1zgbpm1zgbpm.png`
- `Gemini_Generated_Image_hd4otahd4otahd4o.png`

Domyslne parametry profilu zostaly przesuniete pod ten kierunek:
- `panel_height=42`
- `corner_radius=18`
- `blur_sigma=20`
- `launcher_width=960`
- `workspace_gaps=12`
- `layout_gap=12`
- `default_terminal_app=foot`
- `default_browser_app=firefox`
- `default_files_app=thunar`

### Ikony SVG LuminaDE

Czy ikony sa podpiete i powinny sie wyswietlac?
- Tak: pliki `.desktop` maja wpisane `Icon=` (`luminade`, `luminade-settings`).
- Tak: instalator kopiuje ikony do `hicolor/scalable` i `hicolor/symbolic`.
- Tak: tworzone sa aliasy Freedesktop (`network-wireless-symbolic`, `audio-volume-high-symbolic`, itd.).
- Warunek runtime: po instalacji uruchomic `scripts/install-session-files.sh` (najlepiej jako `root`) i odswiezyc cache ikon.

Repo zawiera natywny zestaw ikon SVG:
- `assets/icons/luminade.svg` (logo glowne)
- `assets/icons/luminade-panel.svg`
- `assets/icons/luminade-launcher.svg`
- `assets/icons/luminade-settings.svg`
- `assets/icons/luminade-wifi.svg`
- `assets/icons/luminade-bluetooth.svg`
- `assets/icons/luminade-audio.svg`
- `assets/icons/luminade-volume-muted.svg`
- `assets/icons/luminade-battery.svg`
- `assets/icons/luminade-power.svg`
- `assets/icons/luminade-lock.svg`
- `assets/icons/luminade-suspend.svg`
- `assets/icons/luminade-logout.svg`
- `assets/icons/luminade-terminal.svg`
- `assets/icons/luminade-browser.svg`
- `assets/icons/luminade-files.svg`
- `assets/icons/luminade-workspaces.svg`
- `assets/icons/luminade-notifications.svg`
- `assets/icons/luminade-display.svg`
- `assets/icons/luminade-brightness.svg`
- `assets/icons/luminade-airplane-mode.svg`
- `assets/icons/luminade-keyboard.svg`
- `assets/icons/luminade-mouse.svg`
- `assets/icons/luminade-theme-dark.svg`
- `assets/icons/luminade-theme-light.svg`
- `assets/icons/luminade-network-offline.svg`

Wersje panelowe `symbolic` (monochromatyczne):
- `assets/icons/symbolic/*-symbolic.svg`

Dodatkowo instalator tworzy aliasy zgodne z Freedesktop, m.in.:
- `network-wireless-symbolic`
- `audio-volume-high-symbolic`
- `audio-volume-muted-symbolic`
- `battery-good-symbolic`
- `system-shutdown-symbolic`
- `system-suspend-symbolic`
- `system-lock-screen-symbolic`
- `preferences-system-symbolic`
- `video-display-symbolic`

Panel, Settings i Launcher używają konwencji etykiet widgetów:
- `icon:<nazwa-ikony> <tekst>`

Przyklad:
- `icon:audio-volume-muted-symbolic Mute`

Konwencja jest obslugiwana centralnie przez `luminade-ui`:
- `ui.composeIconLabel(...)`
- `ui.parseIconLabel(...)`

Skrypt `scripts/install-session-files.sh` instaluje je do:
- `/usr/share/icons/hicolor/scalable/apps/`
- `/usr/share/icons/hicolor/symbolic/apps/`

Po instalacji skrypt odswieza cache ikon (`gtk-update-icon-cache`) jesli narzedzie jest dostepne.

Przełączenie języka:

```bash
LUMINADE_LANG=pl zig build run-settings
```

Pliki jezykowe sa trzymane w:
- `config/locales/en.json`
- `config/locales/pl.json`

Locale sa podzielone na sekcje (`panel.*`, `launcher.*`, `settings.*`).
W plikach JSON opisy sekcji sa realizowane przez klucze `_comment.*`
(JSON nie wspiera natywnych komentarzy).

Opcjonalnie mozna wskazac inny katalog locale:

```bash
LUMINADE_LOCALES_DIR=/etc/luminade/locales LUMINADE_LANG=pl zig build run-panel
```

## Persistencja ustawien (load przy logowaniu)

Ustawienia uzytkownika sa trzymane w katalogu runtime projektu:
- `.luminade/profile.conf` - glowny profil desktopu (theme, layout, input, gaps, itp.)
- `.luminade/lang.conf` - zapamietany jezyk UI
- `.luminade/first-run.done` - marker ukonczenia welcome (z opcja "nie pokazuj wiecej")
- `.luminade/device-profiles.conf` - profile wejscia per urzadzenie

Przy starcie aplikacji (`panel`, `launcher`, `settings`, `welcome`) `RuntimeConfig.init()` laduje:
1. profil z `.luminade/profile.conf` (albo modern defaults, gdy brak),
2. jezyk z `LUMINADE_LANG` albo z `.luminade/lang.conf`.

To oznacza, ze po kazdym logowaniu sesja czyta ten sam zestaw ustawien bez dodatkowego kroku migracji.

Etap 1 MVP (działające komendy):

```bash
# GUI-first panel (daemon domyślnie)
zig build run-panel

# panel click/context (myszka)
cat > .luminade/gui-panel-events.tsv <<'EOF'
click	app-terminal@eDP-1
click	ws-2@eDP-1
context	app-terminal@eDP-1	favorite-add
context	app-terminal@eDP-1	favorite-remove
context	app-terminal@eDP-1	remove-history
EOF

# GUI-first launcher (query z pliku .luminade/gui-launcher-query.txt)
echo "firefox" > .luminade/gui-launcher-query.txt
zig build run-launcher

# klik/context menu launchera przez event queue
cat > .luminade/gui-launcher-events.tsv <<'EOF'
click	result-0
context	result-0	favorite-add
context	result-0	favorite-remove
context	result-0	remove-history
EOF

# favorites (pinned) w launcherze
zig build run-launcher -- favorite add terminal
zig build run-launcher -- favorite list
zig build run-launcher -- favorite remove terminal

# cache indeksu aplikacji z plikow .desktop
# (domyslnie: .luminade/launcher-desktop-index.tsv)
LUMINADE_LAUNCHER_DESKTOP_CACHE=.luminade/launcher-desktop-index.tsv zig build run-launcher -- --all

# GUI-first settings (event queue)
cat > .luminade/gui-settings-events.tsv <<'EOF'
window-mode
natural-scroll
pointer-sensitivity	25
save-device-profile	touchpad	natural_scroll	true
apply-input	--dry-run
EOF
zig build run-settings

# pełna sesja (supervisor + routing eventów)
zig build run-sessiond -- --foreground
```

Nowoczesny profil UX przez zmienne środowiskowe:

```bash
LUMINADE_THEME=dark LUMINADE_DENSITY=comfortable LUMINADE_MOTION=smooth zig build run-panel
LUMINADE_PANEL_AUTOHIDE=true zig build run-panel
LUMINADE_WINDOW_MODE=hybrid LUMINADE_INTERACTION_MODE=mouse_first zig build run-panel
LUMINADE_POINTER_SENSITIVITY=25 LUMINADE_POINTER_ACCEL_PROFILE=adaptive LUMINADE_NATURAL_SCROLL=true LUMINADE_TAP_TO_CLICK=true zig build run-panel
LUMINADE_DEFAULT_TERMINAL_APP=kitty LUMINADE_DEFAULT_BROWSER_APP=chromium LUMINADE_DEFAULT_FILES_APP=dolphin zig build run-panel

# fullscreen + multi-output override (opcjonalnie)
LUMINADE_OUTPUTS="eDP-1:2560x1600@1.0,HDMI-1:1920x1080@1.0" zig build run-launcher -- --all
```

`luminade-ui` wykrywa outputy automatycznie (`LUMINADE_OUTPUTS` → `wlr-randr` → `xrandr --query`), a gdy to niemożliwe używa fallback do jednego ekranu 1920x1080.
Powierzchnie panel/launcher/settings są domyślnie konfigurowane jako fullscreen per output.
W trybie `--daemon` panel i launcher używają watchera outputów: po podłączeniu/odłączeniu monitora odświeżają listę `OutputProfile` i przeliczają render spec + scaling.
Watcher wybiera backend automatycznie w kolejności: `wayland` (sesja `WAYLAND_DISPLAY`) → `udev` (`udevadm monitor --subsystem-match=drm`) → `poll`.

`interaction_mode` wpływa na runtime zachowanie:
- `mouse_first`: większe cele interakcji (44px), focus hover-first, launcher pokazuje więcej wyników domyślnie.
- `balanced`: kompromis między myszką i klawiaturą.
- `keyboard_first`: mniejsze cele, fokus i ranking zoptymalizowany pod wpisywanie.

Profil pointer/touchpad (`pointer_sensitivity`, `pointer_accel_profile`, `natural_scroll`, `tap_to_click`) wpływa na hitbox/focus policy i ranking launchera; docelowo te same wartości będą mapowane 1:1 na konfigurację urządzeń wejściowych Wayland.

Profil domyślnych aplikacji (`default_terminal_app`, `default_browser_app`, `default_files_app`) jest współdzielony przez Settings, Launcher i quick-launch w Panelu.

`Layout Manager` (w `luminade-ui`) wspiera:
- `window_mode`: `tiling` / `floating` / `hybrid`
- `tiling_algorithm`: `master_stack` / `grid`
- edge cases: recompute geometrii po zamknięciu okna (re-layout), clamp okien pływających do obszaru outputu, `z-index` z wyniesieniem okna fokusowanego.

GUI pass (panel/launcher/settings) jest aktywny przez model `GuiFrame` + `GuiWidget` + dekoracje (titlebar + przyciski). To jest warstwa GUI runtime i dekoracji, ale **natywny panel Wayland (`layer-shell`) nadal pozostaje kolejnym krokiem**.

Panel ma już adapter natywny (`NativePanelSession`) z `native-first` bootstrap: przy dostępności `XDG_RUNTIME_DIR` + `WAYLAND_DISPLAY` wykonywany jest realny handshake Wayland (`wl_registry` discovery), wykrycie `wl_compositor` + `zwlr_layer_shell_v1`, a następnie minimalny smoke-create surface (`anchor: top+left+right`, `exclusive_zone = panel_height`). Gdy bootstrap się nie powiedzie, frame trafia do per-output state fallback (domyślnie: `.luminade/native-panel-state-<output>.tsv`).

Zmienne runtime:
- `LUMINADE_LAYER_SHELL_SMOKE_CREATE=0` wyłącza jednorazowy smoke-create i zostawia sam discovery/probe.
- `LUMINADE_LAYER_SHELL_SMOKE_CREATE=once` jest aliasem kompatybilności (native commit nadal wykonuje pełny lifecycle surface).
- `LUMINADE_LAYER_SHELL_SMOKE_CREATE=always` wymusza smoke-create przy każdym native probe.
- `LUMINADE_NATIVE_PANEL_PRIMARY=1` (domyślnie) utrzymuje panel na ścieżce native po pierwszym udanym commicie, bez powrotu do bridge TSV.
- `LUMINADE_NATIVE_PANEL_STATE` zmienia ścieżkę fallback state (obsługuje placeholder `{output}`).
- `LUMINADE_LAUNCHER_DESKTOP_CACHE` ustawia ścieżkę cache indeksu `.desktop` dla launchera (domyślnie `.luminade/launcher-desktop-index.tsv`).
- `LUMINADE_LAUNCHER_DESKTOP_REFRESH=1` wymusza przebudowę cache `.desktop` przy starcie launchera (bez czekania na mtime refresh).

Launcher cache `.desktop` działa incremental:
- pliki niezmienione są ładowane z cache,
- zmienione/new `.desktop` są parsowane ponownie,
- usunięte `.desktop` są automatycznie usuwane z indeksu.

ID wpisu launchera dla `.desktop` jest celowo proste i stabilne:
- domyślnie bazuje na nazwie pliku `.desktop` (bez rozszerzenia),
- opcjonalnie preferuje `X-Flatpak` lub `StartupWMClass`, jeśli są dostępne.
- przy kolizji ID launcher dopisuje suffix (`-2`, `-3`) zamiast pomijać wpis.

Zabezpieczenia anty-flood (panel natywny):
- throttling prób native `layer-shell` z exponential backoff (250ms → max 30s),
- deduplikacja fallback commit (hash frame + minimalny interwał 500ms),
- atomowy zapis fallback state (`*.tmp` + rename), aby uniknąć częściowych plików.
- anti-log-flood: limiter logów runtime (`min 250ms`) + licznik `suppressed` zamiast spamowania,
- circuit-breaker: po serii błędów protokołu Wayland (4x) native path jest czasowo otwierany dopiero po cooldownie 60s.

## Testy Wayland na Fedorze (po przejściu z Chromebooka)

Po starcie natywnej sesji Wayland na Fedora:

```bash
echo "$XDG_SESSION_TYPE"      # oczekiwane: wayland
echo "$WAYLAND_DISPLAY"       # np. wayland-0
echo "$XDG_RUNTIME_DIR"       # socket runtime
```

Test backendu i watchera:

```bash
zig build run-panel -- --daemon
zig build run-launcher -- --daemon
```

W logu powinno pojawić się: `[watcher] backend=wayland` (lub fallback `udev`/`poll`, jeśli sesja nie udostępnia socketu).

`luminade-settings apply-input` aktywuje bridge wejścia (etap 2):
- wykrywa urządzenia (`riverctl list-inputs`, fallback `libinput list-devices`),
- aplikuje per-device komendy `riverctl input <device> ...` dla `pointer-accel`, `accel-profile`, `natural-scroll`, `tap`,
- zapisuje plan i wykonanie do `./.luminade/runtime-input.env`.

Profile per-device (matcher substring) są zapisywane w `./.luminade/device-profiles.conf` i nadpisują globalny profil wejścia tylko dla pasujących urządzeń.

`--dry-run` pokazuje i zapisuje plan bez wykonywania komend (zalecane na pierwszy test po migracji z Chromebooka).

Tryb GUI-first:
- `settings` czyta event queue z `.luminade/gui-settings-events.tsv` (lub `LUMINADE_SETTINGS_GUI_EVENTS`),
- `settings` ma i18n PL/EN (etykiety GUI + profile/usage) zależnie od `LUMINADE_LANG`,
- `settings` ma sekcję `System & Power` (`system-lock`, `system-suspend`, `system-logout`, `audio-volume-up/down/mute`) przez `gui-click` i `gui-action`,
- `launcher` czyta zapytanie z `.luminade/gui-launcher-query.txt` (lub `LUMINADE_LAUNCHER_QUERY_PATH`),
- `launcher` czyta akcje myszki z `.luminade/gui-launcher-events.tsv` (lub `LUMINADE_LAUNCHER_GUI_EVENTS`) i mapowanie wyników z `.luminade/gui-launcher-bindings.tsv` (lub `LUMINADE_LAUNCHER_BINDINGS`),
- `panel` czyta akcje myszki z `.luminade/gui-panel-events.tsv` (lub `LUMINADE_PANEL_GUI_EVENTS`),
- `panel` ma quick-launch ikony (`app-terminal`, `app-browser`, `app-files`) i wspiera `click` + `context` (`favorite-add`, `favorite-remove`, `remove-history`),
- dla multi-monitor użyj `widget-id@output-name` (np. `app-browser@HDMI-1`); limiter antyflood działa osobno per output,
- workspace badge też działają per output (`ws-1@eDP-1`); przy River wykonywane jest `riverctl focus-output` + `set-focused-tags`,
- `launcher` ma trwałe favorites (`.luminade/launcher-favorites.tsv` lub `LUMINADE_LAUNCHER_FAVORITES`) i pokazuje pinned wyniki na górze,
- `settings` wspiera zarządzanie favorites przez `launcher-favorite <list|add|remove|clear>`,
- `panel` domyślnie działa jako daemon GUI.

## Sessiond (pełny)

`luminade-sessiond` działa jako centralny supervisor sesji:
- uruchamia i monitoruje `panel`, `launcher` (+ `settings` on-demand),
- ma restart policy z backoff i budżetem restartów,
- routuje komendy przez Unix socket `.luminade/sessiond.sock` (fallback: `.luminade/sessiond-commands.tsv`),
- zapisuje snapshot stanu do `.luminade/sessiond-state.tsv`,
- kieruje eventy do GUI settings i query launchera.

Zmienne środowiskowe IPC:
- `LUMINADE_SESSIOND_SOCKET` (domyślnie `.luminade/sessiond.sock`)
- `LUMINADE_SESSIOND_COMMANDS` (fallback queue)

Sterowanie helperem:

```bash
./scripts/sessionctl.sh ping
./scripts/sessionctl.sh launcher-query "firefox"
./scripts/sessionctl.sh settings-event window-mode
./scripts/sessionctl.sh settings-event pointer-sensitivity 25
./scripts/sessionctl.sh open-settings
./scripts/sessionctl.sh restart launcher
./scripts/sessionctl.sh shutdown
```

## Logowanie do sesji LuminaDE (DM)

Po instalacji binarek uruchom instalator plików sesji/autostartu:

```bash
sudo ./scripts/install-session-files.sh
```

To instaluje:
- `/usr/share/wayland-sessions/luminade.desktop` (widoczne na ekranie logowania),
- `/usr/bin/luminade-session` (entrypoint sesji),
- `/etc/luminade/river.init` (bootstrap River),
- `/etc/xdg/autostart/luminade-sessiond.desktop` + `/usr/bin/luminade-session-autostart` (autostart supervisora),
- `/usr/bin/luminade-sessionctl` (helper komend sesji).

Po wylogowaniu wybierz sesję **LuminaDE** w GDM/SDDM i zaloguj się normalnie.

## Fork River (ważne)

1. Zaloguj się do GitHub CLI: `gh auth login`
2. Uruchom:

```bash
./scripts/fork-river.sh <twoj-user-lub-org>
```

Synchronizacja forka z upstream:

```bash
./scripts/sync-river-upstream.sh
```

Szczegóły polityki: `docs/river-fork-policy.md`

Profil runtime zapisywany jest domyślnie do `./.luminade/profile.conf`
(`LUMINADE_PROFILE_PATH` pozwala zmienić lokalizację).

## Dokumentacja

- `docs/architecture.md`
- `docs/roadmap.md`
- `docs/packaging-fedora-arch.md`
- `docs/river-fork-policy.md`
- `docs/modern-ux.md`
- `docs/mature-panel-launcher.md`
- `docs/luminade-ui.md`

## Status

Aktualnie: **v0.5-dev** (native panel, launcher/settings po pixel-pass, domyslne aplikacje, onboarding, i18n PL/EN).
Kolejny krok: domkniecie punktow `v0.5` z roadmapy (pelny i18n chain, polish welcome, fundament systemu motywow).