#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../platform/environment.sh"

vid="$1"
pid="$2"
intensity="${3:-160}"
duration_ms="${4:-500}"
app="/Applications/OpenJoystickDriver.app/Contents/MacOS/OpenJoystickDriver"
if [[ ! -x "$app" ]]; then
  app="$PROJECT_DIR/.build/debug/OpenJoystickDriver.app/Contents/MacOS/OpenJoystickDriver"
fi
if [[ ! -x "$app" ]]; then
  "$PROJECT_DIR/scripts/ojd" build dev
fi
[[ -x "$app" ]] || die "OpenJoystickDriver is not installed or built; run ./scripts/ojd build install dev"

stop_rumble() {
  "$app" --headless controller output rumble "$vid" "$pid" \
    --left 0 --right 0 --lt 0 --rt 0 --duration-ms 0 >/dev/null 2>&1 || true
}
trap stop_rumble EXIT INT TERM

channels=(left-main right-main left-trigger right-trigger)
options=(--left --right --lt --rt)
echo "Testing $vid:$pid at intensity $intensity for $duration_ms ms."
echo "Hold the controller normally and note the exact location for each numbered step."
for index in "${!channels[@]}"; do
  step=$((index + 1))
  read -r -p "Press Return for $step/4 ${channels[$index]} (or Ctrl-C to stop)... "
  stop_rumble
  "$app" --headless controller output rumble "$vid" "$pid" \
    --left 0 --right 0 --lt 0 --rt 0 "${options[$index]}" "$intensity" \
    --duration-ms "$duration_ms"
  stop_rumble
  echo "Record $step: ${channels[$index]} -> left trigger / right trigger / left grip / right grip / none / other"
done
echo "Sequence complete; all rumble channels were explicitly stopped."
