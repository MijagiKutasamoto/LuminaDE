#!/usr/bin/env bash
set -euo pipefail

PREFIX="${PREFIX:-/usr}"
ETC_PREFIX="${ETC_PREFIX:-/etc}"

install -d "${PREFIX}/bin"
install -d "${PREFIX}/share/wayland-sessions"
install -d "${ETC_PREFIX}/luminade"
install -d "${ETC_PREFIX}/xdg/autostart"

install -m 0755 config/luminade-session "${PREFIX}/bin/luminade-session"
install -m 0755 config/luminade-session-autostart "${PREFIX}/bin/luminade-session-autostart"
install -m 0755 scripts/sessionctl.sh "${PREFIX}/bin/luminade-sessionctl"

install -m 0644 config/wayland-sessions/luminade.desktop "${PREFIX}/share/wayland-sessions/luminade.desktop"
install -m 0644 config/autostart/luminade-sessiond.desktop "${ETC_PREFIX}/xdg/autostart/luminade-sessiond.desktop"
install -m 0755 config/river.init "${ETC_PREFIX}/luminade/river.init"

echo "Installed LuminaDE session files:"
echo "- ${PREFIX}/share/wayland-sessions/luminade.desktop"
echo "- ${PREFIX}/bin/luminade-session"
echo "- ${PREFIX}/bin/luminade-session-autostart"
echo "- ${PREFIX}/bin/luminade-sessionctl"
echo "- ${ETC_PREFIX}/luminade/river.init"
echo "- ${ETC_PREFIX}/xdg/autostart/luminade-sessiond.desktop"
