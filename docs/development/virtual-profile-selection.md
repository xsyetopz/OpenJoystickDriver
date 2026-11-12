# Virtual profile selection: what GameController and SDL3 read

Task 9.13 of `openspec/changes/0-6-0-alpha-3/tasks.md`, first slice. Goal: find one virtual gamepad profile that both GameController.framework and SDL read. This slice records the two built-in profiles, plus `Generic`. It changes no source code.

Status of the parts of 9.13:

| Part | Status |
| --- | --- |
| `SDLCompatible` (`045E:0B0C`), `GameControllerCompatible` (`045E:0B13`), `Generic` (`1209:4A4F`) published and probed | done, below |
| Candidate identities and report descriptors | **not yet run**; see "Publishing another identity" |
| A profile both consumers read | not found yet; no built-in profile is read by both |

## Method

All logs are in `docs/development/virtual-profile-selection/`. `run.sh` starts `ojd virtual feed --as <profile>` (installed app build 3817de06a, argv[0] `ojd`) with `frames.jsonl` on stdin and, 1.5 s later, a probe. Each log starts with the probe command and ends with `# probe exit:` and `# feed exit:`; the feed's own output is in `<profile>.<tag>.feed.log`.

`frames.jsonl` holds a 6 s neutral lead-in, then each control pressed for 700 ms with 300 ms neutral in between, in this order: South, East, West, North, LeftShoulder, RightShoulder, LeftTrigger and RightTrigger as buttons, LeftStickClick, RightStickClick, Start, Back, Guide, DpadUp/Down/Left/Right, then LeftStickX, LeftStickY, RightStickX, RightStickY, LeftTrigger, RightTrigger as axes at 1.0.

Probes:

- GameController: `just diagnose-gamecontroller --seconds 34` (`Sources/OpenJoystickDriverGameControllerProbe/main.swift`). It lists HID gamepads with `GCController.supportsHIDDevice`, lists `GCController`s, and prints a `button:` line for each change of a `GCControllerButtonInput` only. It does not print d-pad or stick direction changes, so those are "not observed" for GameController, not "absent".
- SDL3 3.4.20: `just diagnose-sdl3 --seconds 34 --wait-devices 5` (`Tools/SDLGamepadProbe/main.m`), which prints mapped gamepad events (`GAMEPAD_BUTTON`, `GAMEPAD_AXIS`) and nothing for a joystick that has no gamepad mapping. SDL HIDAPI is default (unset), `SDL_JOYSTICK_HIDAPI=1`, or `SDL_JOYSTICK_HIDAPI=0`.

SDL gamepad numbering used below: buttons 0 South, 1 East, 2 West, 3 North, 4 Back, 5 Guide, 6 Start, 7 left stick, 8 right stick, 9 left shoulder, 10 right shoulder, 11 to 14 d-pad up, down, left, right. Axes 0 to 3 left X, left Y, right X, right Y; 4 left trigger; 5 right trigger.

Stray devices: every GameController probe log also lists two `045E:028E` virtual pads (`GamePad-1`, `GamePad-2`). They are not from these runs, which only publish one profile each; the first build log `_build-gc.log` already shows one with no feed running. They are ignored.

Lead-in note: the first `SDL_JOYSTICK_HIDAPI=1` run of `sdl-compatible` used a 4 s lead-in and SDL started listening after South had played, so it lacks button 0 (`sdl-compatible.sdl-hidapi-on.run1-missed-south.log`). The lead-in became 6 s and that run was repeated (`sdl-compatible.sdl-hidapi-on.log`). The default-HIDAPI `sdl-compatible` run and the `HIDAPI=0` run used the 4 s lead-in; the default one saw South anyway.

## Summary

| Profile | VID:PID seen | GameController lists a controller | SDL default | SDL `HIDAPI=1` | SDL `HIDAPI=0` |
| --- | --- | --- | --- | --- | --- |
| `sdl-compatible` | `045E:0B0C` | no (HID says supported, 0 controllers) | gamepad "Xbox Adaptive Controller", all controls | same | no joystick |
| `game-controller-compatible` | `045E:0B13` | yes, "Xbox Wireless Controller", extended | gamepad "Xbox Series X Controller", no events | same | gamepad, events for all controls but Guide |
| `generic` | `1209:4A4F` | no (HID says unsupported) | joystick, not a gamepad, no mapped events | same | same |

Result of this slice: SDL with its HIDAPI backend reads only `0B0C`, and GameController lists only `0B13`. `0B13` is read by both only when SDL runs with `SDL_JOYSTICK_HIDAPI=0` (SDL then reads it through GameController/IOKit); that is the combination the wiki says needs `--sdl-gamecontroller-backend`. Its Guide button reaches neither.

## Profile `sdl-compatible` (`045E:0B0C`)

Logs: GC `sdl-compatible.gc.log`; SDL default `sdl-compatible.sdl-hidapi-default.log`; `HIDAPI=1` `sdl-compatible.sdl-hidapi-on.log`; `HIDAPI=0` `sdl-compatible.sdl-hidapi-off.log`. Exit codes in each log: probe 0, feed 0.

- GC log: `- 045E:0B0C "Xbox Adaptive Controller" transport=Virtual gamecontroller=yes`, then `Initial controllers: 0` and `connect=false extended_profile=false live_input=false`. No `connect:` line appears during the 34 s.
- SDL default and `HIDAPI=1` logs: `Found 1 joystick(s)`, `vid=0x045e pid=0x0b0c`, `gamepad_name=Xbox Adaptive Controller`, GUID `0300faeb5e0400000c0b000000006800`.
- SDL `HIDAPI=0` log: `Found 0 joystick(s)`.

| Control fed | GameController | SDL default | SDL `HIDAPI=1` | SDL `HIDAPI=0` |
| --- | --- | --- | --- | --- |
| South | no controller | button 0 | button 0 | no joystick |
| East | no controller | button 1 | button 1 | no joystick |
| West | no controller | button 2 | button 2 | no joystick |
| North | no controller | button 3 | button 3 | no joystick |
| LeftShoulder | no controller | button 9 | button 9 | no joystick |
| RightShoulder | no controller | button 10 | button 10 | no joystick |
| LeftTrigger (button and axis) | no controller | axis 4, 2 presses | axis 4, 2 presses | no joystick |
| RightTrigger (button and axis) | no controller | axis 5, 2 presses | axis 5, 2 presses | no joystick |
| LeftStickClick / RightStickClick | no controller | buttons 7 / 8 | buttons 7 / 8 | no joystick |
| Start | no controller | button 6 | button 6 | no joystick |
| Back | no controller | button 4 | button 4 | no joystick |
| Guide | no controller | button 5 | button 5 | no joystick |
| DpadUp/Down/Left/Right | no controller | buttons 11 to 14 | buttons 11 to 14 | no joystick |
| LeftStick X, Y; RightStick X, Y | no controller | axes 0, 1, 2, 3 | axes 0, 1, 2, 3 | no joystick |

Each SDL cell is backed by the `GAMEPAD_BUTTON down/up which=1 button=N` and `GAMEPAD_AXIS which=1 axis=N` lines of its log. The GameController column is backed by `sdl-compatible.gc.log` (no controller).

## Profile `game-controller-compatible` (`045E:0B13`)

Logs: GC `game-controller-compatible.gc.log`; SDL default `game-controller-compatible.sdl-hidapi-default.log`; `HIDAPI=1` `game-controller-compatible.sdl-hidapi-on.log`; `HIDAPI=0` `game-controller-compatible.sdl-hidapi-off.log`. Exit codes in each log: probe 0, feed 0.

- GC log: `- 045E:0B13 "Xbox Wireless Controller" transport=Virtual gamecontroller=yes`; `connect: vendor="Xbox Wireless Controller" category="Xbox One" extended=true micro=true haptics=true`; `inputs: ... xbox=true share=true paddles=0`; `evidence ... connect=true extended_profile=true live_input=true`.
- SDL default and `HIDAPI=1` logs: `vid=0x045e pid=0x0b13 ver=0x0000`, GUID `0300c6515e040000130b000000006800`, `is_gamepad=yes gamepad_name=Xbox Series X Controller`, zero `GAMEPAD_` events in 34 s. This reproduces the wiki's "SDL reads no input from `045E:0B13`".
- SDL `HIDAPI=0` log: `ver=0xa33b`, GUID `0500509d5e040000130b00003ba36d04` (the version and GUID differ from the HIDAPI path, so SDL reads this device through another backend), mapping `a:b0,b:b1,x:b6,y:b7,back:b4,guide:b2,start:b3,...,misc1:b5`, 44 `GAMEPAD_` events.

| Control fed | GameController | SDL default | SDL `HIDAPI=1` | SDL `HIDAPI=0` |
| --- | --- | --- | --- | --- |
| South | Button A | no event | no event | button 0 |
| East | Button B | no event | no event | button 1 |
| West | Button X | no event | no event | button 2 |
| North | Button Y | no event | no event | button 3 |
| LeftShoulder | Left Shoulder | no event | no event | button 9 |
| RightShoulder | Right Shoulder | no event | no event | button 10 |
| LeftTrigger (button and axis) | Left Trigger, 2 presses | no event | no event | axis 4, 2 presses |
| RightTrigger (button and axis) | Right Trigger, 2 presses | no event | no event | axis 5, 2 presses |
| LeftStickClick / RightStickClick | Left / Right Thumbstick Button | no event | no event | buttons 7 / 8 |
| Start | Button Menu | no event | no event | button 6 |
| Back | Button Options | no event | no event | button 4 |
| Guide | no `Button Home` line | no event | no event | no event (button 5 absent) |
| DpadUp/Down/Left/Right | not observed (probe prints buttons only) | no event | no event | buttons 11 to 14 |
| LeftStick X, Y; RightStick X, Y | not observed (probe prints buttons only) | no event | no event | axes 0, 1, 2, 3 |

The Guide cell for GameController may be the system taking Home, or the unfrontmost probe: the probe's own text says Home and Share reach only the frontmost app (`Sources/OpenJoystickDriverGameControllerProbe/main.swift:217-221`). It is not tested with `OpenJoystickDriverGameControllerViewer`, so it is open, not proven absent. Every other GameController cell is a `button:` line in `game-controller-compatible.gc.log`; every SDL cell comes from the `GAMEPAD_` lines (or their absence) of its log.

## Profile `generic` (`1209:4A4F`)

Logs: `generic.gc.log`, `generic.sdl-hidapi-default.log`, `generic.sdl-hidapi-on.log`, `generic.sdl-hidapi-off.log`. Exit codes: probe 0, feed 0.

- GC log: `- 1209:4A4F "OpenJoystickDriver Generic HID Gamepad" transport=Virtual gamecontroller=no`; `Initial controllers: 0`, `connect=false`.
- SDL, all three HIDAPI settings: `vid=0x1209 pid=0x4a4f ver=0x0408`, `is_gamepad=no gamepad_name=(null)`, zero `GAMEPAD_` events.

| Control fed | GameController | SDL default | SDL `HIDAPI=1` | SDL `HIDAPI=0` |
| --- | --- | --- | --- | --- |
| Every control (all 14 rows above) | no controller | joystick only, no gamepad mapping, no event | same | same |

The SDL probe prints no raw joystick events, so whether the generic HID joystick changes its raw buttons is not measured. The generic profile has no SDL mapping unless `ojd virtual launch` or `virtual export-mapping` supplies one (`wiki/Command-Reference.md:240`); this slice did not run with it.

## Not measured

- Rumble and output reports, battery, trigger rumble. This slice read input only.
- D-pad and stick directions in GameController (probe limit above), and the Guide button in GameController.
- Candidate identities and report descriptors: **not yet run**.
- Real applications (PCSX2, Steam), and `--sdl-gamecontroller-backend` launch (`just diagnose-sdl3-gamecontroller`).
- Run-to-run repetition: each cell is one run.

## Publishing another identity

There is no switch to publish an arbitrary VID:PID or descriptor through `ojd virtual feed`. Read, with no change made:

- `ojd virtual feed --as` takes only the three persona ids; `VirtualHIDProfileID` has exactly three cases and decoding any other value fails (`Sources/OpenJoystickDriverKit/Output/Profiles/VirtualHIDProfile.swift:5-13`).
- Each persona maps to a fixed report layout, which supplies the descriptor and codec: `makeProfile()` switches on the layout `xboxOneGIP`, `xboxSeriesBluetooth` or `ojdGenericGamepad` (`VirtualHIDProfile.swift:19-25`; layout enum at `Sources/OpenJoystickDriverKit/Output/Profiles/VirtualDevice.swift:6-10`). The descriptor comes from the layout's report format (`VirtualHIDProfile.swift:117,151,185`; `Output/HID/Xbox/XboxOneGIPReport.swift:117`).
- The identity (VID, PID, name, manufacturer, version, labels) of each persona is a bundled record, for example `Sources/OpenJoystickDriverKit/Resources/VirtualDevices/virtual-device.sdl-compatible.plist` (`layout` XboxOneGIP, `persona` SDLCompatible).
- A different VID:PID and name over an existing layout is possible: `VirtualDeviceProfile.applying(_:)` swaps in a persona's identity and keeps the transport and descriptor (`Sources/OpenJoystickDriverKit/Output/Profiles/VirtualDeviceProfile.swift:51-65`). The service applies it at `Sources/OpenJoystickDriverService/Runtime/ApplicationServiceRuntime+UserSpaceDispatcherFactory.swift:29-43` (`identityProvider` and `identityBuilder`), from a user `VirtualDevices` persona file with an `identity` (`wiki/Controller-Records.md:492`; override store at `Sources/OpenJoystickDriverKit/Output/Profiles/VirtualHIDProfileOverrideStore.swift:15`). That path needs a connected controller of the matching model, so it does not run with no hardware, and `virtual feed` was not checked for using it.
- A new descriptor needs a new layout case and `VirtualGamepadReportFormat` implementation (`Sources/OpenJoystickDriverKit/Output/HID/VirtualGamepadReportFormat.swift:68`), a new `VirtualHIDProfile` struct, a new persona id and a new bundled record in `Resources/VirtualDevices/`, plus the schema (`Resources/Schemas/virtual-device.schema.json`). That is the source change the later change will make; it is not done here.

Next slice: for each candidate (identity over `xboxOneGIP` or `xboxSeriesBluetooth` descriptors first, since `0B13` over GIP and `0B0C` over the Series descriptor are the untested crosses), run the same `frames.jsonl` and `run.sh`, add a table, and also add `OpenJoystickDriverGameControllerViewer` for Guide and d-pad/stick directions.
