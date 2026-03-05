# LuminaDE: Dokumentacja Techniczna (PL)

## 1. Stan projektu

Aktualny milestone: `v0.5-dev`.

To, co juz dziala:
- modularna architektura (`panel`, `launcher`, `settings`, `welcome`, `sessiond`),
- i18n PL/EN z fallback chain,
- UI runtime oparty o `GuiFrame`/`GuiWidget`,
- natywny panel `layer-shell` z fallback state,
- IPC przez socket Unix + TSV fallback queue,
- launcher: `runner command mode`, szybka kalkulacja (`calc-result`), aliasy (`alias:*`) i ikony z `Icon=` (token `icon:<name>` w tagach),
- panel: `scroll` na audio/workspace i rozszerzone RMB (profil zasilania, kalendarz),
- sessiond: lekki pub/sub (`SUB`, `UNSUB`, `PUB`) z fan-out po socketach UNIX datagram,
- settings: sekcje `Appearance` i `Shortcuts` z zapisem profilu motywu i skrótów użytkownika,
- core: fundament motywów (`ThemeProfileName` + tokeny + load/save/fallback) oraz magazyn skrótów (`.luminade/shortcuts.conf`),
- dekoracje okien: aktywny profil motywu steruje dekoracjami wszystkich powierzchni DE (`panel`/`launcher`/`settings`/`welcome`) przez themed surface pipeline,
- welcome: rozszerzone flow pomocy (`Open Launcher`) i lokalny raport `telemetry-free UX checks`.

## 2. Czego brakuje do "pelnego srodowiska"

### 2.1 Asset Management

Braki:
- `IconResolver` w `luminade-core`.
- `TextureCache` w `luminade-ui`.

Co powinno wejsc:
- `IconResolver`:
	- rozwiązywanie nazwy ikony do realnej sciezki (hicolor + fallback),
	- cache mapowania `icon-name -> absolute-path`,
	- fallback do ikony domyslnej (`luminade`) i wariantu symbolic.
- `TextureCache`:
	- cache dekodowanych assetow (`svg/png`) pod renderer,
	- klucz: `path + scale + theme-variant`,
	- polityka ewikcji (LRU) i limity pamieci.

Kryterium "done":
- widget moze podac `icon:<name> text`,
- UI renderuje rzeczywista ikone bez ponownej dekodacji przy kazdej klatce,
- zmiana skali/tematu odswieza cache bez artefaktow.

### 2.2 Input Handling

Braki:
- w `luminade-ui` brak pelnej petli zdarzen pointer/keyboard,
- obecnie jest glownie model hitbox/focus policy (`pointer_target_px`) i event queue plikowa.

Co powinno wejsc:
- petla zdarzen pointer:
	- `pointer-enter`, `pointer-leave`, `pointer-motion`, `button-press/release`,
	- stan `hovered_widget`, `pressed_widget`, capture przy drag.
- petla zdarzen keyboard:
	- focus chain (`tab/shift-tab`),
	- aktywacja `Enter/Space`,
	- hotkeys globalne i per-surface.
- normalizacja eventow do wspolnego `UiEvent` niezaleznie od backendu.

Kryterium "done":
- interakcja bez TSV w krytycznej sciezce UX,
- spójne zachowanie klik/hover/focus/keyboard w panelu, launcherze i settings,
- testowalny event trace (debug log lub ring buffer).

### 2.3 Dokumentacja protokolow

Braki:
- brak jednego, precyzyjnego dokumentu formatu TSV i IPC.

Status:
- ta sekcja jest specyfikacja referencyjna na dzis.

## 3. IPC i protokoly

### 3.1 Model transportu

- Priorytet 1: socket Unix `LUMINADE_SESSIOND_SOCKET` (domyslnie `.luminade/sessiond.sock`).
- Priorytet 2: fallback queue TSV `LUMINADE_SESSIOND_COMMANDS` (domyslnie `.luminade/sessiond-commands.tsv`).
- `scripts/sessionctl.sh` najpierw probuje socket, potem dopisuje do kolejki.

### 3.2 Komendy sessiond (wire protocol)

Format jednej linii:

```text
COMMAND\targ1\targ2\n
```

Obslugiwane komendy:
- `PING`
- `SHUTDOWN`
- `OPEN_SETTINGS`
- `STOP_SETTINGS`
- `RESTART\t<panel|launcher|settings|welcome>`
- `LAUNCHER_QUERY\t<query>`
- `SETTINGS_EVENT\t<widget-id>\t[arg1]...`
- `SUB\t<topic>\t<unix-dgram-endpoint-path>`
- `UNSUB\t<topic>\t<unix-dgram-endpoint-path>`
- `PUB\t<topic>\t<event-name>\t[payload]...`

Uwaga implementacyjna:
- parser ignoruje puste tokeny,
- komentarze zaczynajace sie od `#` sa pomijane.

## 4. Specyfikacja plikow TSV

### 4.1 `.luminade/sessiond-commands.tsv`

Naglowek:

```text
# cmd\targ1\targ2
```

Przyklad:

```text
OPEN_SETTINGS
LAUNCHER_QUERY\tfirefox
SETTINGS_EVENT\twindow-mode
RESTART\tlauncher
```

### 4.2 `.luminade/sessiond-state.tsv`

Zapisywany cyklicznie przez `sessiond`.

Naglowek:

```text
timestamp_ms\t<epoch_ms>
name\trunning\tpid\trestarts\tpending\tlast_exit_kind\tlast_exit_code
```

Przyklad rekordu:

```text
panel\ttrue\t12345\t0\tfalse\tnone\t0
```

### 4.3 `.luminade/gui-panel-events.tsv`

Naglowek:

```text
# action\twidget-id\t[menu-action]
```

Akcje:
- `click\t<widget-id[@output]>`
- `context\t<widget-id[@output]>\t<favorite-add|favorite-remove|remove-history>`
- `scroll\t<widget-id[@output]>\t<up|down|+1|-1>`

Rozszerzone `context` (panel):
- `context\tsys-power@...\t<power-save|balanced|performance>`
- `context\tclock@...\t<open-calendar|calendar-popup>`

Przyklad:

```text
click\tapp-terminal@eDP-1
click\tws-2@eDP-1
context\tapp-terminal@eDP-1\tfavorite-add
```

### 4.4 `.luminade/gui-launcher-events.tsv`

Naglowek:

```text
# action\twidget-id\t[menu-action]
```

Akcje:
- `click\tresult-0`
- `context\tresult-0\t<favorite-add|favorite-remove|remove-history>`

### 4.5 `.luminade/gui-launcher-bindings.tsv`

Generowany przez launcher po renderze wynikow.

Naglowek:

```text
# widget-id\tentry-id\tcommand
```

Przyklad:

```text
result-0\tbrowser\tfirefox
```

### 4.6 `.luminade/gui-settings-events.tsv`

Naglowek:

```text
# widget-id\t[arg1]\t[arg2]
```

Przyklad:

```text
window-mode
display-layout
display-scale-plus
system-network
audio-volume-up
```

### 4.7 `.luminade/gui-welcome-events.tsv`

Naglowek:

```text
# widget-id
```

Przyklad:

```text
lang-pl
mode-balanced
finish
```

### 4.8 `.luminade/launcher-favorites.tsv`

Naglowek:

```text
# launcher favorites (entry ids)
```

Kazda kolejna linia: `entry-id`.

### 4.9 `.luminade/launcher-history.tsv`

Format rekordu:

```text
entry-id\tcount
```

Przyklad:

```text
terminal\t42
browser\t17
```

### 4.10 `.luminade/launcher-desktop-index.tsv`

Aktualny format:

```text
# source-path\tsource-mtime\tid\ttitle\tcommand\ttags
```

Wspierany format legacy:

```text
id\ttitle\tcommand\ttags
```

Uwaga:
- `tags` moze zawierac tokeny specjalne:
	- `icon:<icon-name>` (mapowanie `Icon=` z `.desktop`),
	- `alias:<token>` (dokladne aliasy wyszukiwania).

### 4.11 `.luminade/ui-events.tsv`

Minimalny format zdarzen wejsciowych (`luminade-ui`):

```text
# motion\t<x>\t<y>
# button\t<left|middle|right|other>\t<press|release>\t<x>\t<y>
# scroll\t<dx>\t<dy>\t<x>\t<y>
```

## 5. Ograniczenia formatu TSV

- separator to pojedynczy `\t`,
- brak mechanizmu escape dla `\t` i `\n` w polach,
- bezpieczne jest trzymanie argumentow bez tabulatorow i nowych linii,
- parsery ignoruja linie puste i komentarze `#`.

## 6. Delta na v0.5+ (proponowane kroki wdrozenia)

Krok 1: `IconResolver` (`luminade-core`)
- API `resolveIconPath(name, variant, size, theme) -> ?[]u8`.

Krok 2: `TextureCache` (`luminade-ui`)
- API `getOrLoadTexture(path, scale) -> TextureHandle`.

Krok 3: pelny input loop (`luminade-ui`)
- wspolny `UiEvent` + backend adapters (Wayland native, fallback file-event).

Krok 4: testy kontraktowe IPC
- fixture TSV + test parserow i zgodnosci komend `sessiond`.