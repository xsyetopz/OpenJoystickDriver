# Native Repository Tools

Use these probes only for intentional hardware tests.

Build the maintained `SDLGamepadProbe` and `SDL2GamepadProbe` without opening hardware, and run the tests of the WebRTC bridge package:

```bash
just check-tools
```

`SDLGamepadProbe` builds with Apple Clang, the system `SDL3` package found through `pkg-config`, and the Foundation and GameController frameworks.

To test a connected controller for 10 seconds:

```bash
just diagnose-sdl3 --seconds 10
```

`--seconds` takes a whole number from 1 to 3600 and defaults to 10; other values exit with code 2.

Expected result: the probe lists SDL gamepad events and exits after 10 seconds. Axis events print once per excursion for each gamepad and axis: `GAMEPAD_AXIS which=3 axis=4 left-rest value=8006` when the axis passes 8000, then `GAMEPAD_AXIS which=3 axis=4 rest value=0 peak=32767` when it falls below 2000, with the signed value of largest magnitude as `peak`. Add `--rumble` only when you intend to activate output on every SDL gamepad.

## SDL 2 Probe

`Tools/SDL2GamepadProbe/` prints what an SDL 2 library reads from each joystick. It loads the library at run time, so it tests the SDL 2 a game ships and builds without SDL 2 installed. The default library is CrossOver's `lib64/libSDL2-2.0.0.dylib`, the SDL 2 its Wine uses for controllers. That library is x86_64 only, so the probe builds for x86_64 and runs under Rosetta.

```bash
just diagnose-sdl2 --seconds 10
just diagnose-sdl2 --seconds 10 --library /path/to/libSDL2-2.0.0.dylib
SDL_JOYSTICK_HIDAPI_XBOX=0 just diagnose-sdl2
```

`--seconds` takes a whole number from 1 to 3600 and defaults to 10; other values exit with code 2. A `--library` must be built for x86_64. SDL reads its hints from the environment, as in the last line.

Expected result: one `ADDED` line per joystick with its VID:PID, name, whether SDL has a gamepad mapping for it (`gamecontroller=1`), GUID, and counts. Then a line each time a joystick's state changes: seconds since start, instance ID, the axes, `|`, one digit per button, and `hN` hat values. For example, `0.450 id=1 0 15 0 0 -32768 -32768 | 100000000000000` is South held at rest on an Xbox pad. A joystick that appears or goes away during the run prints `ADDED` or `REMOVED`.

## WebRTC Bridge

`Tools/WebRTCBridge/` is a separate Swift package with its own `Package.swift`. It depends on LiveKitWebRTC, and the root package and `swift test` at the repository root do not fetch or build it. `just check-tools` builds both SDL probes and then runs `swift test` in the bridge package. To test it on its own:

```bash
cd Tools/WebRTCBridge
swift test
```

`Tools/BridgeCore/` is the part of the bridge without WebRTC: the endpoint client, `HostBridge`, `PlayerBridge` and the peer messages. It is a package with no dependencies, and the root package takes it for its endpoint tests.

The first build downloads the LiveKitWebRTC XCFramework, about 70 MB. See [WebRTC Bridge](../docs/sdk/webrtc-bridge.md) for the roles and the steps.
