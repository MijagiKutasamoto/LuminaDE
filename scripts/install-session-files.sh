#!/usr/bin/env bash
set -euo pipefail

PREFIX="${PREFIX:-/usr}"
ETC_PREFIX="${ETC_PREFIX:-/etc}"

install -d "${PREFIX}/bin"
install -d "${PREFIX}/share/wayland-sessions"
install -d "${PREFIX}/share/icons/hicolor/scalable/apps"
install -d "${PREFIX}/share/icons/hicolor/symbolic/apps"
install -d "${ETC_PREFIX}/luminade"
install -d "${ETC_PREFIX}/xdg/autostart"

install -m 0755 config/luminade-session "${PREFIX}/bin/luminade-session"
install -m 0755 config/luminade-session-autostart "${PREFIX}/bin/luminade-session-autostart"
install -m 0755 scripts/sessionctl.sh "${PREFIX}/bin/luminade-sessionctl"

install -m 0644 config/wayland-sessions/luminade.desktop "${PREFIX}/share/wayland-sessions/luminade.desktop"
for icon in assets/icons/*.svg; do
	install -m 0644 "$icon" "${PREFIX}/share/icons/hicolor/scalable/apps/$(basename "$icon")"
done
for icon in assets/icons/symbolic/*.svg; do
	install -m 0644 "$icon" "${PREFIX}/share/icons/hicolor/symbolic/apps/$(basename "$icon")"
done

SYMBOLIC_DIR="${PREFIX}/share/icons/hicolor/symbolic/apps"

# Freedesktop-compatible aliases -> LuminaDE symbolic icon set.
ln -sfn luminade-wifi-symbolic.svg "${SYMBOLIC_DIR}/network-wireless-symbolic.svg"
ln -sfn luminade-wifi-symbolic.svg "${SYMBOLIC_DIR}/network-wireless-signal-good-symbolic.svg"
ln -sfn luminade-network-offline-symbolic.svg "${SYMBOLIC_DIR}/network-wireless-offline-symbolic.svg"
ln -sfn luminade-network-offline-symbolic.svg "${SYMBOLIC_DIR}/network-offline-symbolic.svg"
ln -sfn luminade-airplane-mode-symbolic.svg "${SYMBOLIC_DIR}/airplane-mode-symbolic.svg"
ln -sfn luminade-audio-symbolic.svg "${SYMBOLIC_DIR}/audio-volume-high-symbolic.svg"
ln -sfn luminade-audio-symbolic.svg "${SYMBOLIC_DIR}/audio-volume-medium-symbolic.svg"
ln -sfn luminade-volume-muted-symbolic.svg "${SYMBOLIC_DIR}/audio-volume-muted-symbolic.svg"
ln -sfn luminade-battery-symbolic.svg "${SYMBOLIC_DIR}/battery-good-symbolic.svg"
ln -sfn luminade-battery-symbolic.svg "${SYMBOLIC_DIR}/battery-full-symbolic.svg"
ln -sfn luminade-power-symbolic.svg "${SYMBOLIC_DIR}/system-shutdown-symbolic.svg"
ln -sfn luminade-suspend-symbolic.svg "${SYMBOLIC_DIR}/system-suspend-symbolic.svg"
ln -sfn luminade-lock-symbolic.svg "${SYMBOLIC_DIR}/system-lock-screen-symbolic.svg"
ln -sfn luminade-settings-symbolic.svg "${SYMBOLIC_DIR}/preferences-system-symbolic.svg"
ln -sfn luminade-display-symbolic.svg "${SYMBOLIC_DIR}/video-display-symbolic.svg"
ln -sfn luminade-notifications-symbolic.svg "${SYMBOLIC_DIR}/preferences-system-notifications-symbolic.svg"
ln -sfn luminade-logout-symbolic.svg "${SYMBOLIC_DIR}/system-log-out-symbolic.svg"

install -m 0644 config/autostart/luminade-sessiond.desktop "${ETC_PREFIX}/xdg/autostart/luminade-sessiond.desktop"
install -m 0755 config/river.init "${ETC_PREFIX}/luminade/river.init"

if command -v gtk-update-icon-cache >/dev/null 2>&1; then
	gtk-update-icon-cache -f -t "${PREFIX}/share/icons/hicolor" || true
fi

echo "Installed LuminaDE session files:"
echo "- ${PREFIX}/share/wayland-sessions/luminade.desktop"
echo "- ${PREFIX}/share/icons/hicolor/scalable/apps/*.svg"
echo "- ${PREFIX}/share/icons/hicolor/symbolic/apps/*-symbolic.svg"
echo "- Freedesktop symbolic aliases in ${PREFIX}/share/icons/hicolor/symbolic/apps/"
echo "- ${PREFIX}/bin/luminade-session"
echo "- ${PREFIX}/bin/luminade-session-autostart"
echo "- ${PREFIX}/bin/luminade-sessionctl"
echo "- ${ETC_PREFIX}/luminade/river.init"
echo "- ${ETC_PREFIX}/xdg/autostart/luminade-sessiond.desktop"
