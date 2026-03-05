#!/usr/bin/env bash
set -euo pipefail

# LuminaDE v0.4.1 smoke test helper
#
# Usage:
#   ./scripts/smoke-v041.sh --prepare-only
#   ./scripts/smoke-v041.sh --run
#
# Notes:
# - --prepare-only writes fixture event/query files and prints next commands.
# - --run executes a minimal smoke flow (requires zig + target runtime tools).

MODE="prepare"
if [[ "${1:-}" == "--run" ]]; then
  MODE="run"
elif [[ "${1:-}" == "--prepare-only" || -z "${1:-}" ]]; then
  MODE="prepare"
else
  echo "Unknown option: ${1:-}"
  echo "Usage: $0 [--prepare-only|--run]"
  exit 1
fi

mkdir -p .luminade

cat > .luminade/gui-panel-events.tsv <<'EOF'
# action	widget-id	[menu-action]
click	ws-2@eDP-1
click	sys-audio@eDP-1
click	sys-net@eDP-1
click	sys-power@eDP-1
context	app-terminal@eDP-1	favorite-add
EOF

cat > .luminade/gui-launcher-query.txt <<'EOF'
firefox
EOF

cat > .luminade/gui-launcher-events.tsv <<'EOF'
# action	widget-id	[menu-action]
click	result-0
context	result-0	favorite-add
EOF

cat > .luminade/gui-settings-events.tsv <<'EOF'
# widget-id	[arg1]	[arg2]
window-mode
natural-scroll
apply-input	--dry-run
system-network
audio-volume-up
EOF

echo "Prepared smoke fixtures in .luminade/"
echo "- gui-panel-events.tsv"
echo "- gui-launcher-query.txt"
echo "- gui-launcher-events.tsv"
echo "- gui-settings-events.tsv"

if [[ "$MODE" == "prepare" ]]; then
  cat <<'EOF'

Next (manual run on target Linux/Wayland):
1) LUMINADE_NATIVE_PANEL_REQUIRED=1 zig build run-panel -- --daemon
2) zig build run-launcher -- --daemon
3) zig build run-settings
4) Optional full flow: zig build run-sessiond -- --foreground
EOF
  exit 0
fi

if ! command -v zig >/dev/null 2>&1; then
  echo "zig not found in PATH. Install Zig and rerun with --run."
  exit 1
fi

echo "[smoke] build"
zig build

echo "[smoke] panel strict-native (background)"
LUMINADE_NATIVE_PANEL_REQUIRED=1 zig build run-panel -- --daemon > .luminade/smoke-panel.log 2>&1 &
PANEL_PID=$!
sleep 3
kill "$PANEL_PID" >/dev/null 2>&1 || true
wait "$PANEL_PID" 2>/dev/null || true

echo "[smoke] launcher query path"
zig build run-launcher -- --query firefox --limit 5 > .luminade/smoke-launcher.log 2>&1 || true

echo "[smoke] settings profile show"
zig build run-settings -- show > .luminade/smoke-settings.log 2>&1 || true

echo "Smoke run finished. Logs:"
echo "- .luminade/smoke-panel.log"
echo "- .luminade/smoke-launcher.log"
echo "- .luminade/smoke-settings.log"
