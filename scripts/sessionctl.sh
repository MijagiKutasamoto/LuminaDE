#!/usr/bin/env bash
set -euo pipefail

# LuminaDE sessiond control helper
# Usage examples:
#   ./scripts/sessionctl.sh ping
#   ./scripts/sessionctl.sh launcher-query "firefox"
#   ./scripts/sessionctl.sh settings-event window-mode
#   ./scripts/sessionctl.sh settings-event pointer-sensitivity 25
#   ./scripts/sessionctl.sh open-settings
#   ./scripts/sessionctl.sh restart launcher
#   ./scripts/sessionctl.sh shutdown

QUEUE_PATH="${LUMINADE_SESSIOND_COMMANDS:-.luminade/sessiond-commands.tsv}"
SOCKET_PATH="${LUMINADE_SESSIOND_SOCKET:-.luminade/sessiond.sock}"
mkdir -p "$(dirname "$QUEUE_PATH")"

append_cmd() {
  printf '%s\n' "$1" >> "$QUEUE_PATH"
}

send_socket() {
  local payload="$1"
  python3 - "$SOCKET_PATH" "$payload" <<'PY'
import socket
import sys

path = sys.argv[1]
payload = sys.argv[2]

sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
try:
    sock.connect(path)
    sock.sendall((payload + "\n").encode("utf-8"))
finally:
    sock.close()
PY
}

send_cmd() {
  local line="$1"
  if [[ -S "$SOCKET_PATH" ]]; then
    if send_socket "$line" 2>/dev/null; then
      echo "Sent command via socket $SOCKET_PATH"
      return 0
    fi
  fi

  append_cmd "$line"
  echo "Queued command into $QUEUE_PATH (socket unavailable)"
}

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 <command> [args...]"
  exit 1
fi

cmd="$1"
shift || true

case "$cmd" in
  ping)
    send_cmd "PING"
    ;;
  launcher-query)
    query="${1:-}"
    send_cmd "LAUNCHER_QUERY	${query}"
    ;;
  settings-event)
    if [[ $# -lt 1 ]]; then
      echo "Usage: $0 settings-event <widget-id> [args...]"
      exit 1
    fi
    line="SETTINGS_EVENT"
    while [[ $# -gt 0 ]]; do
      line+=$'\t'"$1"
      shift
    done
    send_cmd "$line"
    ;;
  open-settings)
    send_cmd "OPEN_SETTINGS"
    ;;
  stop-settings)
    send_cmd "STOP_SETTINGS"
    ;;
  restart)
    app="${1:-}"
    if [[ -z "$app" ]]; then
      echo "Usage: $0 restart <panel|launcher|settings>"
      exit 1
    fi
    send_cmd "RESTART	${app}"
    ;;
  shutdown)
    send_cmd "SHUTDOWN"
    ;;
  *)
    echo "Unknown command: $cmd"
    exit 1
    ;;
esac

echo "Processed command '$cmd'"
