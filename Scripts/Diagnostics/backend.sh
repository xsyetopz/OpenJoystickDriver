#!/usr/bin/env bash
# Diagnostics helper for OpenJoystickDriver.
#
# Human-facing entrypoint:
#   ./Scripts/ojd diagnose <subcommand>
#
# Subcommands:
#   dext (default), sdl3, sdl3-gamecontroller, sdl3-hidapi-x360, backends
#
# Runs all checks regardless of individual failures.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../Platform/environment.sh"

cmd="${1:-}"
shift || true

if [[ "$cmd" == "-h" || "$cmd" == "--help" || "$cmd" == "help" ]]; then
  cat <<'TXT'
Usage:
  ./Scripts/ojd diagnose sdl3 [--seconds N] [--rumble] [other args]
  ./Scripts/ojd diagnose sdl3-gamecontroller [--seconds N] [--rumble]
  ./Scripts/ojd diagnose sdl3-hidapi-x360 [--seconds N] [--rumble]
  ./Scripts/ojd diagnose gamecontroller [--seconds N] [--rumble]
  ./Scripts/ojd diagnose backends [--seconds N]
TXT
  exit 0
fi

run_sdl3_probe_native() {
  local ROOT
  ROOT="$PROJECT_DIR"
  local PROBE_DIR="$ROOT/Tools/SDLGamepadProbe"
  [[ -f "$PROBE_DIR/xmake.lua" ]] || die "Missing probe project: $PROBE_DIR"

  echo "Building SDL3 probe (native)..."
  xmake build -P "$PROBE_DIR" SDLGamepadProbe

  echo
  echo "Running SDLGamepadProbe $*"
  echo "Tip: if it prints 'Found 0 joystick(s)', grant Input Monitoring to your terminal app:"
  echo "  System Settings -> Privacy & Security -> Input Monitoring"
  echo
  xmake run -P "$PROBE_DIR" SDLGamepadProbe -- "$@"
}

reset_ojd_virtual_profile_overrides() {
  local ROOT
  ROOT="$PROJECT_DIR"
  local APP_BIN="/Applications/OpenJoystickDriver.app/Contents/MacOS/OpenJoystickDriver"
  local CLI_BIN="${OJD_CLI:-$APP_BIN}"
  if [[ ! -x "$CLI_BIN" ]]; then
    CLI_BIN="$ROOT/.build/debug/OpenJoystickDriver"
  fi

  [[ -x "$CLI_BIN" ]] || die "OpenJoystickDriver CLI not found at $CLI_BIN or $APP_BIN"

  run_limited_command 8 "$CLI_BIN" --headless controller virtual reset --all >/dev/null || {
    echo "WARN: could not reset OJD virtual HID profile overrides" >&2
  }
}

run_sdl3_gamecontroller_probe() {
  reset_ojd_virtual_profile_overrides
  SDL_JOYSTICK_MFI=1 \
    SDL_JOYSTICK_ALLOW_BACKGROUND_EVENTS=1 \
    SDL_JOYSTICK_IOKIT=0 \
    SDL_JOYSTICK_HIDAPI=0 \
    SDL_JOYSTICK_HIDAPI_XBOX=0 \
    SDL_JOYSTICK_HIDAPI_XBOX_360=0 \
    SDL_JOYSTICK_HIDAPI_XBOX_360_WIRELESS=0 \
    SDL_JOYSTICK_HIDAPI_XBOX_ONE=0 \
    SDL_JOYSTICK_HIDAPI_GIP=0 \
    run_sdl3_probe_native --gc-prewarm --wait-devices 8 --rumble --expect-rumble "$@"
}

run_sdl3_hidapi_x360_probe() {
  reset_ojd_virtual_profile_overrides
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

run_limited_command() {
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
  local APP_BIN="/Applications/OpenJoystickDriver.app/Contents/MacOS/OpenJoystickDriver"
  local ROOT
  ROOT="$PROJECT_DIR"
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
    run_limited "$step_timeout" ojd_cli "$CLI_BIN" status || true
    echo

  else
    echo "0) SKIP: OpenJoystickDriver CLI not found at:"
    echo "   $APP_BIN"
    echo
  fi

  echo "3) DriverKit backend diagnostics:"
  run_limited "$step_timeout" /usr/bin/env bash "$SCRIPT_DIR/dext/diagnose.sh" || true
  echo

  echo "4) SDL3 consumer probe:"
  run_limited "$step_timeout" /usr/bin/env bash "$0" sdl3 --seconds "$seconds" \
    --expect-single-neutral-ojd || true
  echo

  echo "5) GameController.framework consumer probe:"
  run_limited "$step_timeout" /usr/bin/env bash "$0" gamecontroller --seconds "$seconds" || true
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
  exit 0
fi

die "Unknown diagnostics command: $cmd"
