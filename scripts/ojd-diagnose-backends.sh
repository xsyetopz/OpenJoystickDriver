#!/usr/bin/env bash
# Backend acceptance diagnostics for ojd-diagnose.sh.

run_backend_acceptance_loop() {
  local APP_BIN="/Applications/OpenJoystickDriver.app/Contents/MacOS/OpenJoystickDriver"
  local ROOT
  ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
  local CLI_BIN="$ROOT/.build/debug/OpenJoystickDriver"
  if [[ ! -x "$CLI_BIN" ]]; then
    CLI_BIN="$APP_BIN"
  fi
  local seconds="${1:-5}"
  local step_timeout="$((seconds + 15))"

  echo "=== OpenJoystickDriver backend acceptance loop ==="
  echo

  run_limited() {
    local limit="$1"
    shift
    "$@" &
    local pid=$!
    local elapsed=0
    while kill -0 "$pid" 2>/dev/null; do
      if (( elapsed >= limit )); then
        echo "WARN: timed out after ${limit}s: $*"
        kill "$pid" 2>/dev/null || true
        wait "$pid" 2>/dev/null || true
        return 124
      fi
      sleep 1
      elapsed=$((elapsed + 1))
    done
    wait "$pid"
  }

  if [[ -x "$CLI_BIN" ]]; then
    echo "0) CLI status:"
    run_limited "$step_timeout" "$CLI_BIN" --headless status || true
    echo

    echo "1) Output mode:"
    run_limited "$step_timeout" "$CLI_BIN" --headless output status || true
    echo

    echo "2) User-space backend status:"
    run_limited "$step_timeout" "$CLI_BIN" --headless userspace status || true
    echo
  else
    echo "0) SKIP: OpenJoystickDriver CLI not found at:"
    echo "   $APP_BIN"
    echo
  fi

  echo "3) DriverKit backend diagnostics:"
  run_limited "$step_timeout" /usr/bin/env bash "$0" dext || true
  echo

  echo "4) SDL3 consumer probe:"
  run_limited "$step_timeout" /usr/bin/env bash "$0" sdl3 --seconds "$seconds" \
    --mappings-file "$ROOT/Resources/SDL/openjoystickdriver.gamecontrollerdb.txt" \
    --expect-single-neutral-ojd || true
  echo

  echo "5) GameController.framework consumer probe:"
  run_limited "$step_timeout" /usr/bin/env bash "$0" gamecontroller --seconds "$seconds" || true
}

