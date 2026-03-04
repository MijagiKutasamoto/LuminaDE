# Packaging Plan (Fedora + Arch)

## Arch
- Pakiet bazowy: `luminade-session`
- Dodatkowe: `luminade-panel`, `luminade-launcher`, `luminade-settings`
- River dependency: `river` (docelowo `river-luminade`)
- Artefakty: `PKGBUILD` + split packages

## Fedora
- Pakiet bazowy: `luminade-session`
- Komponenty jako osobne subpackages
- River dependency: `river` / `river-luminade`
- Artefakty: `luminade.spec` + COPR pipeline

## Wspólne zależności runtime
- `wayland`
- `wlroots`
- `xkbcommon`
- `libinput`
- `pipewire`
- `wireplumber`
- `polkit`

## Standard sesji
- `wayland-sessions/luminade.desktop`
- `/usr/bin/luminade-session` uruchamia `river -c /etc/luminade/river.init`
- `/etc/xdg/autostart/luminade-sessiond.desktop` uruchamia `luminade-session-autostart`

## Artefakty instalacyjne (session package)
- `/usr/share/wayland-sessions/luminade.desktop`
- `/usr/bin/luminade-session`
- `/usr/bin/luminade-session-autostart`
- `/usr/bin/luminade-sessionctl`
- `/etc/luminade/river.init`
- `/etc/xdg/autostart/luminade-sessiond.desktop`

Repo zawiera helper: `scripts/install-session-files.sh` (instalacja lokalna do testów).
