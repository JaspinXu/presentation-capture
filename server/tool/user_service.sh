#!/usr/bin/env bash
set -euo pipefail

app_root="${PRESENTATION_CAPTURE_ROOT:-$HOME/presentation-capture/server}"
config_file="${PRESENTATION_CAPTURE_ENV:-$HOME/.config/presentation-capture/server.env}"
runtime_dir="${PRESENTATION_CAPTURE_RUNTIME_DIR:-$HOME/.cache/presentation-capture}"
node_binary="${PRESENTATION_CAPTURE_NODE:-$HOME/.local/opt/node/bin/node}"

mkdir -p "$runtime_dir"
exec 9>"$runtime_dir/server.lock"
flock -n 9 || exit 0
printf '%s\n' "$$" > "$runtime_dir/server.pid"

child_pid=''
stop_service() {
  if [[ -n "$child_pid" ]]; then
    kill "$child_pid" 2>/dev/null || true
    wait "$child_pid" 2>/dev/null || true
  fi
  rm -f "$runtime_dir/server.pid"
  exit 0
}
trap stop_service INT TERM EXIT

set -a
# shellcheck disable=SC1090
source "$config_file"
set +a
umask 027

while true; do
  "$node_binary" "$app_root/src.js" &
  child_pid="$!"
  wait "$child_pid" || true
  child_pid=''
  sleep 5
done
