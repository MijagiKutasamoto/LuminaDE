# LuminaDE Architecture

## Cel
LuminaDE to dojrzałe środowisko graficzne dla dwóch wariantów dystrybucji (Fedora i Arch), z kompozytorem River oraz komponentami UI napisanymi w Zig.

## Warstwy
1. **Compositor Layer**: fork `river` utrzymywany w `vendor/river`.
2. **Session Layer**: uruchamianie sesji i usług (`config/river.init`, docelowo `luminade-sessiond`).
3. **UI Toolkit Layer (Zig)**:
   - `luminade-ui` (wspólny toolkit GUI)
   - theme tokens
   - widget model i event loop
4. **UI Apps Layer (Zig)**:
   - `luminade-panel`
   - `luminade-launcher`
   - `luminade-settings`
5. **Core Layer (Zig lib)**:
   - konfiguracja runtime
   - i18n
   - współdzielony model ustawień
6. **System Integration**:
   - logind/polkit
   - network manager
   - audio (PipeWire)
   - display management

## Moduły ustawień (MVP -> full)
- Wygląd (motyw, tapeta, czcionki)
- Ekrany (układ, scaling, refresh)
- Wejście (klawiatura, układ, touchpad, mouse)
- Dźwięk
- Sieć
- Zasilanie
- Skróty
- Aplikacje domyślne

## i18n
- Minimalny runtime oparty o `LUMINADE_LANG`.
- Pliki tłumaczeń trzymane w `config/locales/*.json`.
- Docelowo: fallback chain (`pl-PL` -> `pl` -> `en`).

## Strategie dojrzałości
- Stabilne API między komponentami przez `luminade-core`.
- Wersjonowanie semantyczne.
- Testy integracyjne dla sesji River.
- CI z matrixem Fedora/Arch.
