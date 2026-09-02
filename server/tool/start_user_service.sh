#!/usr/bin/env bash
set -euo pipefail

app_root="${PRESENTATION_CAPTURE_ROOT:-$HOME/presentation-capture/server}"
runtime_dir="${PRESENTATION_CAPTURE_RUNTIME_DIR:-$HOME/.cache/presentation-capture}"
mkdir -p "$runtime_dir"

pid_file="$runtime_dir/server.pid"
if [[ -s "$pid_file" ]] && kill -0 "$(cat "$pid_file")" 2>/dev/null; then
  exit 0
fi

nohup "$app_root/tool/user_service.sh" \
  >> "$runtime_dir/server.log" 2>&1 </dev/null &
