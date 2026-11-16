#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../Platform/environment.sh"

vid="$1"
pid="$2"
intensity="${3:-160}"
duration_ms="${4:-500}"
require_ojd_app_cli
controller="$(printf '%04X:%04X' "$((vid))" "$((pid))")"
duration="$((duration_ms / 1000)).$(printf '%03d' $((duration_ms % 1000)))"

stop_rumble() {
  (ojd_cli "$OJD_APP_CLI" controller rumble "$controller" --left 0 --right 0 >/dev/null 2>&1) || true
}
trap stop_rumble EXIT INT TERM

channels=(low-frequency high-frequency left-trigger right-trigger)
options=(--left --right --left-trigger --right-trigger)
echo "Testing $vid:$pid at intensity $intensity for $duration_ms ms."
echo "Hold the controller normally and note the exact location for each numbered step."
for index in "${!channels[@]}"; do
  step=$((index + 1))
  read -r -p "Press Return for $step/4 ${channels[$index]} (or Ctrl-C to stop)... "
  stop_rumble
  # A controller without this channel makes the command fail; the sequence goes on.
  if ! (ojd_cli "$OJD_APP_CLI" controller rumble "$controller" "${options[$index]}" "$intensity" \
    --duration "$duration"); then
    echo "Record $step: ${channels[$index]} -> not present"
    continue
  fi
  # The command returns at once; the daemon stops the channel when the duration ends.
  sleep "$duration"
  stop_rumble
  echo "Record $step: ${channels[$index]} -> left trigger / right trigger / left grip / right grip / none / other"
done
echo "Sequence complete; all rumble channels were explicitly stopped."
