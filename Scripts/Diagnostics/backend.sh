#!/usr/bin/env bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../Platform/environment.sh"

cmd="${1:-}"
shift || true

SDL3_PROBE_DIR="$PROJECT_DIR/Tools/SDLGamepadProbe"

build_sdl3_probe() {
  [[ -f "$SDL3_PROBE_DIR/xmake.lua" ]] || die "Missing probe project: $SDL3_PROBE_DIR"
  echo "Building SDL3 probe (native)..."
  xmake build -P "$SDL3_PROBE_DIR" SDLGamepadProbe
}

print_sdl3_probe_banner() {
  echo
  echo "Running SDLGamepadProbe $*"
  echo "Tip: if it prints 'Found 0 joystick(s)', grant Input Monitoring to your terminal app:"
  echo "  System Settings -> Privacy & Security -> Input Monitoring"
  echo
}

run_sdl3_probe_native() {
  build_sdl3_probe
  print_sdl3_probe_banner "$@"
  xmake run -P "$SDL3_PROBE_DIR" SDLGamepadProbe -- "$@"
}

# The SDL hints that make SDL read controllers through GameController come from
# `ojd virtual launch --sdl-gamecontroller-backend`, which also needs a published gamepad.
run_sdl3_gamecontroller_probe() {
  require_ojd_app_cli
  build_sdl3_probe
  print_sdl3_probe_banner --gc-prewarm --wait-devices 8 --rumble --expect-rumble "$@"
  (ojd_cli "$OJD_APP_CLI" virtual launch --sdl-gamecontroller-backend -- \
    xmake run -P "$SDL3_PROBE_DIR" SDLGamepadProbe -- \
    --gc-prewarm --wait-devices 8 --rumble --expect-rumble "$@")
}

run_sdl3_hidapi_x360_probe() {
  SDL_GAMECONTROLLER_ALLOW_STEAM_VIRTUAL_GAMEPAD=1 \
    SDL_JOYSTICK_MFI=0 \
    SDL_JOYSTICK_IOKIT=0 \
    SDL_JOYSTICK_HIDAPI=1 \
    SDL_JOYSTICK_HIDAPI_XBOX=1 \
    SDL_JOYSTICK_HIDAPI_XBOX_360=1 \
    SDL_JOYSTICK_HIDAPI_XBOX_360_WIRELESS=0 \
    SDL_JOYSTICK_HIDAPI_XBOX_ONE=0 \
    SDL_JOYSTICK_HIDAPI_GIP=0 \
    run_sdl3_probe_native --wait-devices 8 --rumble --expect-rumble "$@"
}

run_gamecontroller_probe() {
  local seconds="${1:-5}"
  local rumble="${2:-0}"
  local ROOT
  ROOT="$PROJECT_DIR"
  local PROBE="$ROOT/.build/debug/OpenJoystickDriverGameControllerProbe"

  if [[ ! -x "$PROBE" ]]; then
    echo "Building GameController probe..."
    (cd "$ROOT" && swift build --product OpenJoystickDriverGameControllerProbe)
  fi

  [[ -x "$PROBE" ]] || die "Missing probe binary: $PROBE"
  local args=(--seconds "$seconds")
  if [[ "$rumble" == "1" ]]; then
    args+=(--rumble)
  fi
  "$PROBE" "${args[@]}"
}

run_backend_acceptance_loop() {
  require_ojd_app_cli
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

  local failed=0
  run_step() {
    local label="$1" status=0
    shift
    echo "$label"
    run_limited "$step_timeout" "$@" || status=$?
    echo "Step exit status: $status"
    if (( status != 0 )); then
      failed=$((failed + 1))
    fi
    echo
  }

  run_step "0) CLI status:" ojd_cli "$OJD_APP_CLI" status
  run_step "3) DriverKit backend diagnostics:" /usr/bin/env bash "$SCRIPT_DIR/dext/diagnose.sh"
  run_step "4) SDL3 consumer probe:" /usr/bin/env bash "$0" sdl3 --seconds "$seconds" \
    --expect-single-neutral-ojd
  run_step "5) GameController.framework consumer probe:" /usr/bin/env bash "$0" gamecontroller \
    --seconds "$seconds"

  if (( failed != 0 )); then
    echo "$failed backend step(s) failed."
    return 1
  fi
  echo "All backend steps passed."
}

if [[ "$cmd" == "sdl3" ]]; then
  run_sdl3_probe_native "$@"
  exit 0
fi

if [[ "$cmd" == "sdl3-gamecontroller" ]]; then
  run_sdl3_gamecontroller_probe "$@"
  exit 0
fi

if [[ "$cmd" == "sdl3-hidapi-x360" ]]; then
  run_sdl3_hidapi_x360_probe "$@"
  exit 0
fi

if [[ "$cmd" == "gamecontroller" ]]; then
  seconds="5"
  rumble="0"
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --seconds)
        [[ -n "${2:-}" ]] || die "--seconds requires a value"
        seconds="$2"
        shift 2
        ;;
      --rumble)
        rumble="1"
        shift
        ;;
      *)
        die "Unknown gamecontroller option: $1"
        ;;
    esac
  done
  run_gamecontroller_probe "$seconds" "$rumble"
  exit 0
fi

if [[ "$cmd" == "backends" ]]; then
  seconds="5"
  if [[ "${1:-}" == "--seconds" && -n "${2:-}" ]]; then
    seconds="$2"
  fi
  run_backend_acceptance_loop "$seconds"
  exit $?
fi

die "Unknown diagnostics command: $cmd"
