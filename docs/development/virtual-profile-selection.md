# Virtual profile selection: what GameController and SDL3 read

Tasks 9.13 and 9.14 of `openspec/changes/0-6-0-alpha-3/tasks.md`. Question for 9.13: is there one virtual gamepad profile that both GameController.framework and SDL read? Question for 9.14: what would it take to choose the profile by the app in front? This document records measurements for a later change. It changes no profile selection code.

Measured on the maintainer's Mac (macOS 27, Darwin 27.2.0) with the installed app `0.6.0-alpha.2+build.1.27.48.sha.448cfab83661.dirty`, SDL 3.4.20, and an 8BitDo Ultimate 2C Wireless (`2DC8:301B`) over Bluetooth LE.

## Result

| Question | Answer |
| --- | --- |
| One profile read by both GameController and SDL's HIDAPI drivers | None found. GameController reads input only from the Xbox Bluetooth report layout. SDL's HIDAPI drivers read input only from `045E:0B0C` over the Xbox One GIP layout. |
| A profile both read, with a condition | `045E:0B13` (`GameControllerCompatible`) or `045E:0B20` over the Bluetooth layout, when SDL runs with `SDL_JOYSTICK_HIDAPI=0`. SDL then reads the pad through its GameController backend. This is what `ojd virtual launch --sdl-gamecontroller-backend` sets up (`wiki/Playing-Games.md:24`). |
| Home (Guide) | Reached OJD but neither probe in any run reported it. Both probes ran in the background. Unresolved. |
| Replacing the published gamepad | SDL sees a remove within 36 ms, then an add 2.0 s later with a new instance ID. GameController sees connect or disconnect within 76 ms. See [Replacing the published gamepad](#replacing-the-published-gamepad). |

## Method

All logs are in `docs/development/virtual-profile-selection/`. They end in `.txt` because the repository ignores `*.log` (`.gitignore:186`).

Scripts:

- `run.sh <profile> <tag> <probe...>` publishes a bundled profile with `ojd virtual feed --as <profile>` and feeds it `frames.jsonl`. It starts the probe 1.5 s later. The log ends with `# probe exit:` and `# feed exit:`. The feed's output goes to `<profile>.<tag>.feed.txt`. No controller was connected during these runs.
- `candidate.sh <name> <persona> <vid> <pid> <version> <productName> <seconds> [parallel] [tags...]` publishes the 2C's own virtual gamepad under another identity. It writes a user file `~/Library/Application Support/OpenJoystickDriver/VirtualDevices/2dc8-301b.plist` with `match`, `persona`, and `identity` (format: `wiki/Controller-Records.md:493`). The service keeps the persona's report layout and swaps in the identity (`Sources/OpenJoystickDriverKit/Output/Profiles/VirtualDeviceProfile.swift:51-65`). `candidate.sh --clear` removes the file. Each log starts with `ojd virtual show`.
- `replace.sh <name>` runs both probes for 45 s while `ojd virtual set` and `ojd virtual reset` replace the 2C's gamepad. Every line carries the wall clock.

`ojd virtual feed` publishes only the bundled identities. `makeVirtualFeedDevice` in `Sources/OpenJoystickDriverService/Runtime/ApplicationServiceRuntime+UserSpaceDispatcherFactory.swift` does not apply a user identity. So the candidates use the 2C as the input source, and the maintainer pressed each control.

`frames.jsonl` holds a 6 s neutral lead-in, then each control held for 700 ms with 300 ms neutral between. Order: South, East, West, North, LeftShoulder, RightShoulder, LeftTrigger and RightTrigger as buttons, LeftStickClick, RightStickClick, Start, Back, Guide, DpadUp/Down/Left/Right, then LeftStickX, LeftStickY, RightStickX, RightStickY, LeftTrigger, and RightTrigger as axes at 1.0.

Probes:

- GameController: `just diagnose-gamecontroller --seconds N` (`Sources/OpenJoystickDriverGameControllerProbe/main.swift`). It lists HID gamepads with `GCController.supportsHIDDevice` and lists `GCController`s. It prints a `button:` line for each button change and a `direction:` line for each d-pad or stick change. The closing `evidence` line has `live_input=true` once any input arrived.
- SDL3: `just diagnose-sdl3 --seconds N --wait-devices 5` (`Tools/SDLGamepadProbe/main.m`). It prints `GAMEPAD_BUTTON`, `GAMEPAD_AXIS`, `GAMEPAD_ADDED`, and `GAMEPAD_REMOVED`. It prints nothing for a joystick without a gamepad mapping. SDL's HIDAPI drivers ran three ways: default (unset), `SDL_JOYSTICK_HIDAPI=1`, and `SDL_JOYSTICK_HIDAPI=0`.
- `ojd controller watch 2DC8:301B --output --duration N` shows what OJD received from the 2C and what it sent (`out buttons=0x…`). It proves that a press reached OJD in a run where a probe saw nothing.

SDL gamepad numbering: buttons 0 South, 1 East, 2 West, 3 North, 4 Back, 5 Guide, 6 Start, 7 left stick, 8 right stick, 9 left shoulder, 10 right shoulder, 11 to 14 d-pad up, down, left, and right. Axes: 0 to 3 are left X, left Y, right X, and right Y; 4 is the left trigger; 5 is the right trigger.

The 2C's buttons are named as in `docs/testing/8bitdo-ultimate-2c.md:119-121`. View is the small button left of center and reaches games as Back. Menu is the small button right of center and reaches games as Start. Home is the round center button and reaches games as Guide.

Stray device: most GameController logs list a `045E:028E` pad (`GamePad-1` or `GamePad-2`) that none of these runs published. It is ignored.

## Bundled profiles

Logs: `<profile>.<tag>.txt` for `sdl-compatible`, `game-controller-compatible`, and `generic`, with tags `gc`, `sdl-hidapi-default`, `sdl-hidapi-on`, and `sdl-hidapi-off`. Every log ends with `# probe exit: 0` and `# feed exit: 0`.

| Profile | Identity seen | GameController | SDL default and `HIDAPI=1` | SDL `HIDAPI=0` |
| --- | --- | --- | --- | --- |
| `sdl-compatible` | `045E:0B0C`, layout Xbox One GIP | HID `gamecontroller=yes`, 0 controllers, `connect=false` | gamepad "Xbox Adaptive Controller", GUID `0300faeb5e0400000c0b000000006800`, every control | `Found 0 joystick(s)` |
| `game-controller-compatible` | `045E:0B13`, layout Xbox Series Bluetooth | controller "Xbox Wireless Controller", `extended_profile=true live_input=true`, every control but Home | gamepad "Xbox Series X Controller", GUID `0300c6515e040000130b000000006800`, 0 events | gamepad, `ver=0xa33b`, GUID `0500509d5e040000130b00003ba36d04`, every control but Guide |
| `generic` | `1209:4A4F`, OJD generic layout | HID `gamecontroller=no`, 0 controllers | joystick, `is_gamepad=no`, GUID `0300be1c091200004f4a000008040000`, 0 events | same |

Each control that was fed:

| Control | `sdl-compatible`, SDL default and `HIDAPI=1` | `game-controller-compatible`, GameController | `game-controller-compatible`, SDL `HIDAPI=0` |
| --- | --- | --- | --- |
| South, East, West, North | buttons 0 to 3 | Button A, B, X, Y | buttons 0 to 3 |
| LeftShoulder, RightShoulder | buttons 9, 10 | Left Shoulder, Right Shoulder | buttons 9, 10 |
| LeftTrigger, RightTrigger (button and axis) | axes 4, 5, 2 presses each | Left Trigger, Right Trigger, 2 presses each | axes 4, 5, 2 presses each |
| LeftStickClick, RightStickClick | buttons 7, 8 | Left, Right Thumbstick Button | buttons 7, 8 |
| Start | button 6 | Button Menu | button 6 |
| Back | button 4 | Button Options | button 4 |
| Guide | button 5 | no line | no event |
| DpadUp/Down/Left/Right | buttons 11 to 14 | `direction: Direction Pad`, 8 lines | buttons 11 to 14 |
| Left stick X, Y; right stick X, Y | axes 0 to 3 | `direction: Left Thumbstick` and `Right Thumbstick`, 4 lines each | axes 0 to 3 |

Every other cell reads nothing:

- `sdl-compatible`: GameController has no controller, and SDL `HIDAPI=0` finds no joystick.
- `game-controller-compatible`: SDL default and `HIDAPI=1` list the gamepad but print no event.
- `generic`: no consumer prints an event. The SDL probe prints no raw joystick events, so it does not show whether the raw buttons of the generic joystick change. The generic profile has an SDL mapping only when `ojd virtual launch` or `ojd virtual export-mapping` supplies one (`wiki/Command-Reference.md:240`). These runs did not use either.

## Candidate identities

Each candidate publishes the 2C's virtual gamepad with another Microsoft identity over one of the three layouts. Logs: `candidates/<name>.<tag>.txt`. Enumeration runs had no input. Press runs used `parallel` with the maintainer pressing each control.

Layouts: GIP is `SDLCompatible`'s Xbox One GIP layout over a USB transport. BT is `GameControllerCompatible`'s Xbox Series Bluetooth layout over a Bluetooth transport. Generic is the OJD generic layout. The identity's `version` was 0.

| Candidate | GameController | SDL default and `HIDAPI=1` | SDL `HIDAPI=0` |
| --- | --- | --- | --- |
| G1 `0B13` "Xbox Wireless Controller" over GIP | controller, `extended_profile=true` | gamepad "Xbox Series X Controller" | gamepad, `ver=0xa33b` |
| G2 `0B12` over GIP | HID `gamecontroller=yes`, 0 controllers | 0 joysticks (also in `G2-0b12-over-gip.repeat.sdl-hidapi-default.txt`) | 0 joysticks |
| G3 `02EA` over GIP | HID `gamecontroller=no`, 0 controllers | 0 joysticks (also in `G3-02ea-over-gip.repeat.sdl-hidapi-default.txt`) | 0 joysticks |
| B1 `0B0C` "Xbox Adaptive Controller" over BT | HID `gamecontroller=yes`, 0 controllers | gamepad "Xbox Adaptive Controller" | 0 joysticks |
| B2 `0B20` over BT | controller, `extended_profile=true`, no Share | gamepad "Xbox One S Controller" | gamepad seen as `045E:02E0`, `ver=0x5326`, GUID `0500a54b5e040000e002000026536d04` |
| B3 `02FD` over BT | controller, `extended_profile=true` | gamepad "Xbox One S Controller" | gamepad seen as `045E:02E0` |
| N1 `0B13` over generic | controller, `extended_profile=true` | gamepad "Xbox Series X Controller" | gamepad, `ver=0xa33b` |

A GameController controller is listed by VID:PID. With `HIDAPI=0`, SDL lists a pad only when GameController has one. SDL's GameController backend then reports its own VID:PID and version (`02E0`, `0x5326`) for the BT candidates.

Press runs:

| Candidate | GameController | SDL default | SDL `HIDAPI=0` | Logs |
| --- | --- | --- | --- | --- |
| G1 `0B13` over GIP | 0 lines, `live_input=false` | axes 4 and 5 only, 6 events | 0 events | `G1-0b13-over-gip.press.*` |
| N1 `0B13` over generic | 0 lines, `live_input=false` | 0 events | 0 events | `N1-0b13-over-generic.press3.*` |
| B2 `0B20` over BT | every control but Home | 0 events | every control but Guide | `B2-0b20-over-bt.press.*`, `press2.*`, `view-menu.*` |

- N1: `N1-0b13-over-generic.press3.ojd-watch.txt` shows 88 `buttons=` lines and `out buttons=0x1` and others, so the presses reached OJD and were sent. The two earlier tries (`N1-0b13-over-generic.press.*`) also read 0 events. The maintainer was not shown which button to press first, so those runs prove nothing about input.
- B2: GameController printed Button A, B, X, Y, Left and Right Shoulder, Left and Right Trigger (analog), both Thumbstick Buttons, Button Menu, Button Options, `Direction Pad`, `Left Thumbstick`, and `Right Thumbstick`. SDL `HIDAPI=0` printed buttons 0 to 4, 6 to 14, and axes 0 to 5. The first run started listening after A, B, X, Y, and LB were pressed; `press2` covers them.
- B2 View and Menu, from `B2-0b20-over-bt.view-menu.*`: View reaches OJD as Back (`out buttons=0x200`), then GameController `Button Options`, then SDL button 4. Menu reaches OJD as Start (`0x100`), then GameController `Button Menu`, then SDL button 6.
- B2 Home: `B2-0b20-over-bt.press.ojd-watch.txt` shows `buttons=[Guide]` and `out buttons=0x400`. GameController printed no `Button Home` line, and SDL printed no button 5. The GameController probe states that Home reaches only the frontmost app (`Sources/OpenJoystickDriverGameControllerProbe/main.swift:217-221`), and the probe ran in the background. `OpenJoystickDriverGameControllerViewer` was not used, so this stays open.

## Choosing the profile by the app in front (9.14)

### How the service learns the frontmost app

The service already tracks it for per-app remapping. `WorkspaceRemappingForegroundApplication` observes `NSWorkspace.didActivateApplicationNotification` and reads the bundle identifier (`Sources/OpenJoystickDriverService/Remapping/SystemEvents/RemappingForegroundApplication.swift:16-39`). `ApplicationServiceRuntime` creates it at `Sources/OpenJoystickDriverService/Runtime/ApplicationServiceRuntime.swift:71`. A profile choice by app can read the same tracker and needs no new observer.

### How to tell a GameController app from an SDL app

`apps/scan.txt` lists each installed app whose executable links GameController.framework or that bundles a `libSDL` library:

| App | Executable links GameController | Bundled SDL |
| --- | --- | --- |
| DuckStation | no | `libSDL3.0.dylib` |
| PCSX2 2.8.2 | no | `libSDL3.0.dylib` |
| Melvor2 (Godot) | yes | none |
| OpenJoystickDriver | yes | none |

The bundled `libSDL3.0.dylib` of DuckStation and PCSX2 links GameController.framework itself (`apps/scan.txt`, "SDL3 links GameController"). So "links GameController" does not mark a GameController-only app. A test for a bundled `libSDL*` file, or a static SDL found by symbol, is needed first. Browsers and Steam showed neither link in their main executable. They may load GameController through a framework (inferred, not checked), so a link scan can miss them. A user-set list of apps is the reliable fallback (inferred).

### What a running game observes when OJD replaces the gamepad

Logs: `replace/run1.*` and `replace/run2.*`. The 2C was published as `SDLCompatible`. At 12 s `ojd virtual set game-controller-compatible 2DC8:301B` switched it to `0B13` over the BT layout, and at 27 s `ojd virtual reset 2DC8:301B` switched it back.

| Event | run1 | run2 |
| --- | --- | --- |
| `ojd virtual set` runs until it returns | 0.521 s | 0.501 s |
| SDL `GAMEPAD_REMOVED` after `set` returned | 27 ms | 36 ms |
| SDL `GAMEPAD_ADDED` after that remove | 1.992 s | 1.979 s |
| GameController `connect:` after `set` returned | 36 ms | 76 ms |
| `ojd virtual reset` runs until it returns | 0.520 s | 0.503 s |
| SDL `GAMEPAD_REMOVED` after `reset` returned | 27 ms | 18 ms |
| SDL `GAMEPAD_ADDED` after that remove | 1.999 s | 1.997 s |
| GameController `disconnect:` after `reset` returned | 10 ms | 4 ms |

What a game sees:

- SDL gives each published gamepad a new instance ID (`which=1`, then 3, then 4). A game that opens gamepads only at startup loses the pad at the first replacement. The probe itself opens gamepads only at startup.
- The pad is missing from SDL for about 2 s on each replacement.
- After the switch to `0B13`, SDL with its HIDAPI drivers adds a gamepad that reads no input, as in the bundled-profile table.

### What the user's override means then

Inferred, not measured. The override is a per-model choice that beats automatic selection (`wiki/Playing-Games.md:28-34`). A choice by app would be a new step in automatic selection, so the override can keep its meaning: it pins the kind for the model and turns the per-app choice off. Each switch costs the game about 2 s without a pad and a new SDL instance, so switching should happen only on an app change, never while a game is in front. While a user `VirtualDevices` file holds an `identity`, `ojd virtual reset` refuses with E2006, so an identity file pins the kind as well.

## Not measured

- Rumble, output reports, battery, and trigger rumble. These runs read input only.
- Home (Guide) with a frontmost GameController app such as `OpenJoystickDriverGameControllerViewer`.
- Real games (PCSX2, Steam) during a replacement.
- Run-to-run repeats of the press runs. Each press cell comes from one run.
