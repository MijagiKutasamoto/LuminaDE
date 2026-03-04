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

## Zakres v1
- Wayland-native backend (xdg-shell/layer-shell)
- GPU renderer (wgpu/vulkan lub OpenGL ES)
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
