# luminade-ui (Zig GUI Toolkit)

## Cel
Własna biblioteka GUI w Zig dla LuminaDE, by panel/launcher/settings miały wspólny renderer, widgety i spójny system motywów.

## Zakres v0
- Theme tokens (spacing, radius, blur, colors)
- Surface spec (panel, launcher, settings)
- GUI frame model: `GuiFrame` + `GuiWidget` + pass renderowania dla panel/launcher/settings
- Podstawowe widgety: text, button, list, input, icon
- Event model: keyboard, pointer, focus
- Layout: row/column/stack z constraints
- Layout Manager: `tiling` / `floating` / `hybrid` + algorytmy `master_stack` / `grid`
- Output watcher: `wayland` session backend + event-driven (`udev` DRM) + fallback polling
- Render spec: physical/logical size + scale per output
- Dekoracje: model titlebar, drag region, close/maximize/minimize buttons

## Domyślny profil motywu (v0.4.1+)
`luminade-ui` przyjmuje profil bazowy zgodny z planowanym lookiem:
- `corner_radius = 18`
- `spacing_unit = 10`
- `blur_sigma = 20`

Domyślne dekoracje:
- launcher titlebar: `42`
- settings titlebar: `44`

Motywy są teraz podpinane globalnie przez `SurfaceDecorationTheme`:
- `fullscreenSurfaceThemed(...)`
- `launcherSurfaceThemed(...)`
- `settingsSurfaceThemed(...)`

`SurfaceDecorationTheme` jest mapowany z tokenów (`ThemeTokens`) i kontroluje:
- wysokość titlebara launchera,
- wysokość titlebara settings,
- round corners/shadow dla wszystkich dekorowanych powierzchni.

## Zakres v1
- Wayland-native backend (xdg-shell/layer-shell)
- GPU renderer (wgpu/vulkan lub OpenGL ES)

## Konwencja ikon w widgetach

`luminade-ui` wspiera konwencje etykiet ikonowych:
- format: `icon:<icon-name> <text>`

API:
- `parseIconLabel(label)` -> rozbija etykiete na `icon_name` i `text`
- `composeIconLabel(allocator, icon_name, text)` -> buduje etykiete w formacie konwencji

To jest wspolna sciezka uzywana przez `panel`, `launcher` i `settings`.
- Animacje i transitions
- Accessibility hooks (reduced motion, high contrast)

## API Design
- Declarative widget tree
- Immutable frame model + diffing
- Zero-cost abstractions gdzie to możliwe
- Priorytet backendów output watchera: `wayland` -> `udev` -> `poll`
- Re-layout edge cases: close window => recompute, floating clamp to output, z-index z wyniesieniem focusu

## Dla ekosystemu
- Dokumentowane API i przykłady, aby inne aplikacje Zig mogły użyć tej biblioteki.
