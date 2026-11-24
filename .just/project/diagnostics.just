# Diagnostics against the installed app, the DriverKit extension, and the games' input stacks.
# The SDL probes read their hints from the environment, so a run such as
# `SDL_JOYSTICK_HIDAPI_XBOX=0 just diagnose-sdl2` reaches the probe.

sdl3_probe := "xmake run -P Tools/SDLGamepadProbe SDLGamepadProbe --"
sdl_probe_tip := "echo 'If the probe lists no joystick, grant Input Monitoring to your terminal app: System Settings > Privacy & Security > Input Monitoring.'"

# Run the dext diagnostics: activation, codesign, IORegistry, app service.
diagnose-dext:
    Scripts/Diagnostics/dext/diagnose.sh

# Launch the installed app in Xcode's UI test runner and fail if it offers a driver repair while the driver is active.
diagnose-driver-ui:
    TEST_RUNNER_OJD_SYSEXT_LIST="$(systemextensionsctl list)" xcodebuild test -quiet -project OpenJoystickDriver.xcodeproj -scheme OpenJoystickDriverApp -only-testing:OpenJoystickDriverUITests/InstalledDriverUITests -destination 'platform=macOS'

# Validate or probe a canonical controller record through the USB dext.
diagnose-record record *args:
    {{ env }} swift run OpenJoystickDriverHIDTool --record-probe "$(realpath {{ record }})" {{ args }}

# Print an authorized device's USB descriptor facts (hex vid and pid).
diagnose-usb-passive vid pid:
    {{ env }} swift run OpenJoystickDriverHIDTool --usb-passive --vid {{ vid }} --pid {{ pid }}

[private]
build-sdl3-probe:
    {{ env }} xmake build -P Tools/SDLGamepadProbe SDLGamepadProbe

# Run the SDL3 probe against the virtual device.
[positional-arguments]
diagnose-sdl3 *args: build-sdl3-probe
    @{{ sdl_probe_tip }}
    {{ env }} {{ sdl3_probe }} "$@"

# Run the SDL2 probe (x86_64), by default against CrossOver's SDL2, which its Wine uses.
[positional-arguments]
diagnose-sdl2 *args:
    {{ env }} xmake build -P Tools/SDL2GamepadProbe SDL2GamepadProbe
    @{{ sdl_probe_tip }}
    {{ env }} xmake run -P Tools/SDL2GamepadProbe SDL2GamepadProbe "$@"

# Run SDL3 through GameController and test rumble; `ojd virtual launch` sets the SDL hints and needs a published gamepad.
[positional-arguments]
diagnose-sdl3-gamecontroller *args: build-sdl3-probe
    #!/usr/bin/env bash
    set -euo pipefail
    source Scripts/Platform/environment.sh
    require_ojd_app_cli
    {{ sdl_probe_tip }}
    (ojd_cli "$OJD_APP_CLI" virtual launch --sdl-gamecontroller-backend -- \
      {{ sdl3_probe }} --gc-prewarm --wait-devices 8 --rumble --expect-rumble "$@")

# Run SDL3 through the Xbox 360 HIDAPI backend and test rumble.
[positional-arguments]
diagnose-sdl3-hidapi-x360 *args: build-sdl3-probe
    @{{ sdl_probe_tip }}
    SDL_GAMECONTROLLER_ALLOW_STEAM_VIRTUAL_GAMEPAD=1 SDL_JOYSTICK_MFI=0 SDL_JOYSTICK_IOKIT=0 \
      SDL_JOYSTICK_HIDAPI=1 SDL_JOYSTICK_HIDAPI_XBOX=1 SDL_JOYSTICK_HIDAPI_XBOX_360=1 \
      SDL_JOYSTICK_HIDAPI_XBOX_360_WIRELESS=0 SDL_JOYSTICK_HIDAPI_XBOX_ONE=0 SDL_JOYSTICK_HIDAPI_GIP=0 \
      {{ env }} {{ sdl3_probe }} --wait-devices 8 --rumble --expect-rumble "$@"

# Run the GameController.framework probe; pass --seconds N and --rumble.
[positional-arguments]
diagnose-gamecontroller *args:
    {{ env }} swift run OpenJoystickDriverGameControllerProbe "$@"

# Run the backend acceptance loop: CLI status, dext diagnostics, and the SDL3 and GameController probes.
[positional-arguments]
diagnose-backends *args:
    #!/usr/bin/env bash
    set -uo pipefail
    source Scripts/Platform/environment.sh
    require_ojd_app_cli
    seconds=5
    if [[ "${1:-}" == --seconds ]]; then
      [[ -n "${2:-}" ]] || die "--seconds requires a value"
      seconds="$2"
    elif [[ $# -gt 0 ]]; then
      die "diagnose-backends takes only --seconds N"
    fi
    limit=$((seconds + 15))
    failed=0
    # Each step gets the probe time plus 15 seconds, then is stopped so one hung step cannot stall the loop.
    step() {
      local label="$1" status=0 pid elapsed=0
      shift
      echo "$label"
      "$@" &
      pid=$!
      while kill -0 "$pid" 2>/dev/null; do
        if (( elapsed >= limit )); then
          echo "WARN: timed out after ${limit}s: $*"
          kill "$pid" 2>/dev/null || true
          break
        fi
        sleep 1
        elapsed=$((elapsed + 1))
      done
      wait "$pid" || status=$?
      echo "Step exit status: $status"
      (( status == 0 )) || failed=$((failed + 1))
      echo
    }
    echo "=== OpenJoystickDriver backend acceptance loop ==="
    echo
    step "1) CLI status:" ojd_cli "$OJD_APP_CLI" status
    step "2) DriverKit backend diagnostics:" just diagnose-dext
    step "3) SDL3 consumer probe:" just diagnose-sdl3 --seconds "$seconds" --expect-single-neutral-ojd
    step "4) GameController.framework consumer probe:" just diagnose-gamecontroller --seconds "$seconds"
    if (( failed != 0 )); then
      echo "$failed backend step(s) failed."
      exit 1
    fi
    echo "All backend steps passed."

# Feed every control to each browser's Gamepad API and report its slot.
diagnose-browsers *args:
    python3 -m Scripts.Diagnostics.browser_gamepad {{ args }}

# Identify each physical rumble actuator, pausing between steps.
diagnose-rumble-motors vid pid intensity="160" duration_ms="500":
    #!/usr/bin/env bash
    set -euo pipefail
    source Scripts/Platform/environment.sh
    require_ojd_app_cli
    controller="$(printf '%04X:%04X' "$(({{ vid }}))" "$(({{ pid }}))")"
    duration="$(({{ duration_ms }} / 1000)).$(printf '%03d' $(({{ duration_ms }} % 1000)))"
    stop_rumble() {
      (ojd_cli "$OJD_APP_CLI" controller rumble "$controller" --left 0 --right 0 >/dev/null 2>&1) || true
    }
    trap stop_rumble EXIT INT TERM
    channels=(low-frequency high-frequency left-trigger right-trigger)
    options=(--left --right --left-trigger --right-trigger)
    echo "Testing {{ vid }}:{{ pid }} at intensity {{ intensity }} for {{ duration_ms }} ms."
    echo "Hold the controller normally and note the exact location for each numbered step."
    for index in "${!channels[@]}"; do
      step=$((index + 1))
      read -r -p "Press Return for $step/4 ${channels[$index]} (or Ctrl-C to stop)... "
      stop_rumble
      # A controller without this channel makes the command fail; the sequence goes on.
      if ! (ojd_cli "$OJD_APP_CLI" controller rumble "$controller" "${options[$index]}" {{ intensity }} --duration "$duration"); then
        echo "Record $step: ${channels[$index]} -> not present"
        continue
      fi
      # The command returns at once; the daemon stops the channel when the duration ends.
      sleep "$duration"
      stop_rumble
      echo "Record $step: ${channels[$index]} -> left trigger / right trigger / left grip / right grip / none / other"
    done
    echo "Sequence complete; all rumble channels were explicitly stopped."

# Kill stale DriverKit process copies after an upgrade.
repair-stale-dext:
    python3 -m Scripts.Diagnostics.dext.repair
