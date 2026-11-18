# Virtual Profile Selection: What GameController and SDL3 Read

Two questions: does one virtual gamepad profile exist that both GameController.framework and SDL read, and what would choosing the profile by the app in front take? Measurements only.

Measured on the maintainer's Mac (macOS 27, Darwin 27.2.0) with installed app `0.6.0-alpha.2+build.1.27.48.sha.448cfab83661.dirty`, SDL 3.4.20, and an 8BitDo Ultimate 2C Wireless (`2DC8:301B`) over Bluetooth LE.

## Result

| Question | Answer |
| --- | --- |
| One profile both GameController and SDL's HIDAPI drivers read | None found. GameController reads input only from the Xbox Bluetooth report layout. SDL's HIDAPI drivers read input only from 045E:0B0C over the Xbox One GIP layout. |
| A profile both read, with a condition | 045E:0B13 (GameControllerCompatible) or 045E:0B20 over the Bluetooth layout, with `SDL_JOYSTICK_HIDAPI=0`. SDL then reads the pad through its GameController backend. `ojd virtual launch --sdl-gamecontroller-backend` sets this up (see `wiki/Playing-Games.md`). |
| Home (Guide) | Reached OJD; neither probe reported it in any run. Both ran in the background. Unresolved. |
| Replacing the published gamepad | SDL sees a remove within 36 ms, then an add 2.0 s later with a different instance ID. GameController sees connect or disconnect within 76 ms. See [What a running game observes when OJD replaces the gamepad](#what-a-running-game-observes-when-ojd-replaces-the-gamepad). |

## Method

Logs: `docs/development/virtual-profile-selection/`, named `.txt` because the repository ignores `*.log` (`.gitignore:186`).

| Tool | What it does |
| --- | --- |
| `run.sh <profile> <tag> <probe...>` | Publishes a bundled profile with `ojd virtual feed --as <profile>`, feeding `frames.jsonl`. The probe starts 1.5 s later. The log ends with `# probe exit:` and `# feed exit:`; feed output goes to `<profile>.<tag>.feed.txt`. No controller was connected. |
| `candidate.sh <name> <persona> <vid> <pid> <version> <productName> <seconds> [parallel] [tags...]` | Publishes the 2C's virtual gamepad under another identity via the user file `~/Library/Application Support/OpenJoystickDriver/VirtualDevices/2dc8-301b.plist` (match, persona, identity; format in `wiki/Controller-Records.md`). The service keeps the persona's report layout and swaps in the identity (`Sources/OpenJoystickDriverKit/Output/Profiles/VirtualDeviceProfile.swift:51-65`). `candidate.sh --clear` removes the file. Each log starts with `ojd virtual show`. |
| `just diagnose-gamecontroller --seconds N` | GameController probe (`Sources/OpenJoystickDriverGameControllerProbe/main.swift`). Lists HID gamepads (`GCController.supportsHIDDevice`) and `GCController`s; prints a `button:` line per button change and a `direction:` line per d-pad or stick change. The closing evidence line has `live_input=true` once input arrived. |
| `just diagnose-sdl3 --seconds N --wait-devices 5` | SDL3 probe (`Tools/SDLGamepadProbe/main.m`). Prints `GAMEPAD_BUTTON`, `GAMEPAD_AXIS`, `GAMEPAD_ADDED`, `GAMEPAD_REMOVED`; nothing for a joystick without a gamepad mapping. HIDAPI ran default (unset), `SDL_JOYSTICK_HIDAPI=1`, `SDL_JOYSTICK_HIDAPI=0`. |
| `ojd controller watch 2DC8:301B --output --duration N` | Shows what OJD received from the 2C and sent (`out buttons=0x…`), proving a press reached OJD when a probe saw nothing. |

`ojd virtual feed` publishes only bundled identities: `makeVirtualFeedDevice` in `Sources/OpenJoystickDriverService/Runtime/ApplicationServiceRuntime+UserSpaceDispatcherFactory.swift` applies no user identity. Candidates use the 2C as input, and the maintainer pressed each control.

`frames.jsonl` has a 6 s neutral lead-in, then each control held 700 ms with 300 ms neutral between. Order: South, East, West, North, LeftShoulder, RightShoulder, LeftTrigger and RightTrigger as buttons, LeftStickClick, RightStickClick, Start, Back, Guide, DpadUp/Down/Left/Right, then LeftStickX, LeftStickY, RightStickX, RightStickY, LeftTrigger, RightTrigger as axes at 1.0.

SDL buttons: 0 South, 1 East, 2 West, 3 North, 4 Back, 5 Guide, 6 Start, 7 left stick, 8 right stick, 9 left shoulder, 10 right shoulder, 11 to 14 d-pad up, down, left, right. Axes: 0 to 3 left X, left Y, right X, right Y; 4 left trigger; 5 right trigger.

Button names follow `docs/testing/8bitdo-ultimate-2c.md`: View (small, left of center) reaches games as Back, Menu (right of center) as Start, Home (round, center) as Guide. Ignore the stray 045E:028E pad (`GamePad-1` or `GamePad-2`) in most GameController logs; no run published it.

## Bundled Profiles

Logs: `<profile>.<tag>.txt` for sdl-compatible, game-controller-compatible, generic; tags gc, sdl-hidapi-default, sdl-hidapi-on, sdl-hidapi-off. Each ends with `# probe exit: 0` and `# feed exit: 0`.

| Profile | Identity seen | GameController | SDL default and `HIDAPI=1` | SDL `HIDAPI=0` |
| --- | --- | --- | --- | --- |
| sdl-compatible | `045E:0B0C`, layout Xbox One GIP | HID gamecontroller=yes, 0 controllers, `connect=false` | gamepad "Xbox Adaptive Controller", GUID 0300faeb5e0400000c0b000000006800, every control | Found 0 joystick(s) |
| game-controller-compatible | `045E:0B13`, layout Xbox Series Bluetooth | controller "Xbox Wireless Controller", `extended_profile=true live_input=true`, every control but Home | gamepad "Xbox Series X Controller", GUID 0300c6515e040000130b000000006800, 0 events | gamepad, ver=0xa33b, GUID 0500509d5e040000130b00003ba36d04, every control but Guide |
| generic | `1209:4A4F`, OJD generic layout | HID gamecontroller=no, 0 controllers | joystick, is_gamepad=no, GUID 0300be1c091200004f4a000008040000, 0 events | same |

Fed controls:

| Control | sdl-compatible, SDL default and `HIDAPI=1` | game-controller-compatible, GameController | game-controller-compatible, SDL `HIDAPI=0` |
| --- | --- | --- | --- |
| South, East, West, North | buttons 0 to 3 | Button A, B, X, Y | buttons 0 to 3 |
| LeftShoulder, RightShoulder | buttons 9, 10 | Left Shoulder, Right Shoulder | buttons 9, 10 |
| LeftTrigger, RightTrigger (button and axis) | axes 4, 5, 2 presses each | Left Trigger, Right Trigger, 2 presses each | axes 4, 5, 2 presses each |
| LeftStickClick, RightStickClick | buttons 7, 8 | Left, Right Thumbstick Button | buttons 7, 8 |
| Start | button 6 | Button Menu | button 6 |
| Back | button 4 | Button Options | button 4 |
| Guide | button 5 | no line | no event |
| DpadUp/Down/Left/Right | buttons 11 to 14 | `direction: Direction Pad`, 8 lines | buttons 11 to 14 |
| Left stick X, Y; right stick X, Y | axes 0 to 3 | `direction: Left Thumbstick` and Right Thumbstick, 4 lines each | axes 0 to 3 |

Every other cell reads nothing:

- sdl-compatible: GameController has no controller, and SDL `HIDAPI=0` finds no joystick.
- game-controller-compatible: SDL default and `HIDAPI=1` list the gamepad but print no event.
- generic: no consumer prints an event. The SDL probe prints no raw joystick events, so it does not show whether the raw buttons of the generic joystick change. The generic profile has an SDL mapping only when `ojd virtual launch` or `ojd virtual export-mapping` supplies one (see `wiki/Command-Reference.md`). These runs did not use either.

Every other cell reads nothing:

- sdl-compatible: GameController has no controller; SDL `HIDAPI=0` finds no joystick.
- game-controller-compatible: SDL default and `HIDAPI=1` list the gamepad but print no event.
- generic: no consumer prints an event. The SDL probe prints no raw joystick events, so raw changes are unshown. Generic has an SDL mapping only from `ojd virtual launch` or `ojd virtual export-mapping` (see `wiki/Command-Reference.md`); these runs used neither.

## Candidate Identities

Each candidate publishes the 2C's virtual gamepad with another Microsoft identity over one of three layouts (identity version 0). Logs: `candidates/<name>.<tag>.txt`. Enumeration runs had no input; press runs used parallel with the maintainer pressing each control.

Layouts: GIP is SDLCompatible's Xbox One layout over USB transport. BT is GameControllerCompatible's Xbox Series layout over Bluetooth transport. Generic is the OJD generic layout.

| Candidate | GameController | SDL default and `HIDAPI=1` | SDL `HIDAPI=0` |
| --- | --- | --- | --- |
| G1 0B13 "Xbox Wireless Controller" over GIP | controller, `extended_profile=true` | gamepad "Xbox Series X Controller" | gamepad, ver=0xa33b |
| G2 0B12 over GIP | HID gamecontroller=yes, 0 controllers | 0 joysticks (also in `G2-0b12-over-gip.repeat.sdl-hidapi-default.txt`) | 0 joysticks |
| G3 02EA over GIP | HID gamecontroller=no, 0 controllers | 0 joysticks (also in `G3-02ea-over-gip.repeat.sdl-hidapi-default.txt`) | 0 joysticks |
| B1 0B0C "Xbox Adaptive Controller" over BT | HID gamecontroller=yes, 0 controllers | gamepad "Xbox Adaptive Controller" | 0 joysticks |
| B2 0B20 over BT | controller, `extended_profile=true`, no Share | gamepad "Xbox One S Controller" | gamepad seen as 045E:02E0, ver=0x5326, GUID `0500a54b5e040000e002000026536d04` |
| B3 02FD over BT | controller, `extended_profile=true` | gamepad "Xbox One S Controller" | gamepad seen as 045E:02E0 |
| N1 0B13 over generic | controller, `extended_profile=true` | gamepad "Xbox Series X Controller" | gamepad, ver=0xa33b |

GameController lists a controller by VID:PID. With `HIDAPI=0`, SDL lists a pad only when GameController has one, reporting its own VID:PID and version (02E0, `0x5326`) for BT candidates.

Press runs:

| Candidate | GameController | SDL default | SDL `HIDAPI=0` | Logs |
| --- | --- | --- | --- | --- |
| G1 0B13 over GIP | 0 lines, `live_input=false` | axes 4 and 5 only, 6 events | 0 events | `G1-0b13-over-gip.press.*` |
| N1 0B13 over generic | 0 lines, `live_input=false` | 0 events | 0 events | `N1-0b13-over-generic.press3.*` |
| B2 0B20 over BT | every control but Home | 0 events | every control but Guide | `B2-0b20-over-bt.press.*`, `press2.*`, `view-menu.*` |

| Run | Finding |
| --- | --- |
| N1 | `N1-0b13-over-generic.press3.ojd-watch.txt` shows 88 `buttons=` lines and `out buttons=0x1` and others: presses reached OJD and were sent. The two earlier tries (`N1-0b13-over-generic.press.*`) read 0 events but prove nothing; the maintainer was not told which button to press first. |
| B2 | GameController printed Button A, B, X, Y, Left and Right Shoulder, Left and Right Trigger (analog), both Thumbstick Buttons, Button Menu, Button Options, Direction Pad, Left Thumbstick, Right Thumbstick. SDL `HIDAPI=0` printed buttons 0 to 4, 6 to 14, axes 0 to 5. The first run started listening after A, B, X, Y, and LB were pressed; press2 covers them. |
| B2 View, Menu | `B2-0b20-over-bt.view-menu.*`: View reaches OJD as Back (`out buttons=0x200`), then Button Options, then SDL button 4. Menu reaches OJD as Start (`0x100`), then Button Menu, then SDL button 6. |
| B2 Home | `B2-0b20-over-bt.press.ojd-watch.txt` shows `buttons=[Guide]` and `out buttons=0x400`; GameController printed no Button Home and SDL no button 5. The probe says Home reaches only the frontmost app (`Sources/OpenJoystickDriverGameControllerProbe/main.swift:217-221`), and it ran in the background. `OpenJoystickDriverGameControllerViewer` was not used; still open. |

## Choosing the Profile by the App in Front (9.14)

### How the Service Learns the Frontmost App

Per-app remapping tracks it: `WorkspaceRemappingForegroundApplication` observes `NSWorkspace.didActivateApplicationNotification` and reads the bundle identifier (`Sources/OpenJoystickDriverService/Remapping/SystemEvents/RemappingForegroundApplication.swift:16-39`), created at `Sources/OpenJoystickDriverService/Runtime/ApplicationServiceRuntime.swift:71`. A per-app profile choice can read it.

### How to Tell a GameController App From an SDL App

`apps/scan.txt` lists installed apps whose executable links GameController.framework or bundles a `libSDL` library:

| App | Executable links GameController | Bundled SDL |
| --- | --- | --- |
| DuckStation | no | libSDL3.0.dylib |
| PCSX2 2.8.2 | no | libSDL3.0.dylib |
| Melvor2 (Godot) | yes | none |
| OpenJoystickDriver | yes | none |

DuckStation's and PCSX2's libSDL3.0.dylib links GameController.framework itself (`apps/scan.txt`, "SDL3 links GameController"), so a GameController link does not mark a GameController-only app. Test for a bundled `libSDL*` file, or a static SDL by symbol, first. Browsers and Steam showed neither link in their main executable; they may load GameController through a framework (inferred, not checked), so a link scan can miss them. A user-set app list is the reliable fallback (inferred).

### What a Running Game Observes When OJD Replaces the Gamepad

Logs: `replace/run1.*`, `replace/run2.*`. The 2C was published as SDLCompatible. At 12 s `ojd virtual set game-controller-compatible 2DC8:301B` switched it to 0B13 over BT; at 27 s `ojd virtual reset 2DC8:301B` switched it back.

| Event | run1 | run2 |
| --- | --- | --- |
| `ojd virtual set` runs until it returns | 0.521 s | 0.501 s |
| SDL GAMEPAD_REMOVED after set returned | 27 ms | 36 ms |
| SDL `GAMEPAD_ADDED after that remove | 1.992 s | 1.979 s |
| GameController `connect:` after set returned | 36 ms | 76 ms |
| `ojd virtual reset` runs until it returns | 0.520 s | 0.503 s |
| SDL GAMEPAD_REMOVED after reset returned | 27 ms | 18 ms |
| SDL `GAMEPAD_ADDED after that remove | 1.999 s | 1.997 s |
| GameController `disconnect:` after reset returned | 10 ms | 4 ms |

What a game sees:

- SDL gives each published gamepad a different instance ID (which=1, then 3, then 4). A game that opens gamepads only at startup loses the pad at the first replacement, as the probe does.
- The pad is missing from SDL for about 2 s per replacement.
- After the switch to 0B13, SDL with HIDAPI drivers adds a gamepad that reads no input (see Bundled Profiles).

### What the User's Override Means Then

Inferred, not measured. The override is a per-model choice that beats automatic selection (see `wiki/Playing-Games.md`); a per-app choice would be one more automatic step. The override pins the kind for the model and turns per-app choice off. Each switch costs the game about 2 s without a pad and a fresh SDL instance, so switch only when the front app changes. While a user `VirtualDevices` file holds an identity, `ojd virtual reset` refuses with E2006, so an identity file pins the kind too.

## Not Measured

- Rumble, output reports, battery, trigger rumble (runs read input only).
- Home (Guide) with a frontmost GameController app such as `OpenJoystickDriverGameControllerViewer`.
- Real games (PCSX2, Steam) during a replacement.
- Run-to-run repeats; each press cell comes from one run.
