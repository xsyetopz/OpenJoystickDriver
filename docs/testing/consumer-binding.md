# Consumer-Binding Evidence

Use this record to interpret compatibility claims. It preserves exact physical modes, consumer versions, observed results, and missing evidence. For the user-facing summary, see [virtual HID profiles](../../wiki/Using-the-App.md).

Status marks used in the tables below:

- ✅ hardware-verified for the named physical mode and consumer
- ⚠️ source-backed candidate that still needs live consumer evidence
- 🧪 reported failure or experimental result
- 🔬 research only
- ❌ unavailable

## Recorded Fallback and Consumer Limits

- GameSir G7 Pro `3537:100A` and `3537:1022` are input-only. OJD does not switch modes or force re-enumeration; hold the controller's physical Menu+Share combination before connecting to expose a configuration-ready identity and its additional features.
- GameSir's shared Microsoft Bluetooth identities `045E:02FD` and `045E:02FF` remain on Microsoft or Generic HID handling. OJD does not assign them a GameSir model without an exact hardware capture.
- GameSir `3537:1004` remains the Linux-backed XUSB identity shared with T4 Kaleid; the reported White G7 Pro dongle collision is not enough to change that route. Linux-backed `3537:100F` and `3537:1010` also retain their XUSB and GIP paths.
- Generic HID maps descriptor-defined controls but cannot infer vendor protocols.
- Raw and vendor-specific USB controllers use direct IOUSBHost when macOS permits app ownership. Entitlement-restricted models require OJD's signed USB DriverKit extension.
- Recorded results for a published Xbox Series `045E:0B13` "Xbox Wireless Controller" identity: GameController.framework bound it on GameSir G7 SE USB GIP. A custom SDL 3.4.16 HIDAPI+IOKit build (no GameController.framework) bound the same identity as HIDAPI xboxone over Bluetooth (`bus_type` 2) and took the 17-byte BLE path, not USB GIP. Interrupt IN streams idle 17-byte Series reports (`0x01` plus 0x8000 sticks, official BLE rest). HIDAPI xboxone BLE `HandleStatePacket` maps those to signed 0 (`raw - 0x8000`) before jitter. A 12s interrupt watch saw 48 idle reports and no physical button bit. A packer-built A-pressed 17-byte Series report decodes SOUTH true through the same BLE layout; that is not a physical press. Steam `hid_init` hangs (Steam bundled SDL 3.5.0, 5s watchdog). sdlHIDAPI remains source-backed; this is not a Steam HIDAPI result. A published DualShock 4 `054C:09CC` "Wireless Controller" (USB, 64-byte report `0x01`, descriptor 114 bytes) and DualSense `054C:0CE6` "Wireless Controller" (USB, 64-byte report `0x01`, descriptor 273 bytes) both returned `GCController.supportsHIDDevice` yes and custom SDL HIDAPI `SDL_OpenGamepad` as ps4/ps5. A published Switch Pro `057E:2009` "Pro Controller" (USB Joystick, 64-byte reports, descriptor 203 bytes) returned `supportsHIDDevice` yes without hang and custom HIDAPI `SDL_OpenGamepad` as switchpro. A published `045E:028E` "Xbox 360 Wired Controller" (USB Joystick, 14-byte reports, `bcdDevice` 0x0114, descriptor 201 bytes) returned `supportsHIDDevice` yes and custom HIDAPI `SDL_OpenGamepad` as xbox360. Ignore leftover IOHID `045E:028E` `AppleGCSyntheticDevice` "GamePad-1" when it is not the OJD user-space device: GameController creates that 360 HID shim when it binds an Xbox identity (`045E:0B13` included). OJD excludes synthetic registry markers before any user-client open; the product name `GamePad-1` alone does not exclude a physical device. Stock SDL match-all deadlocks on a leftover wedged shim. Physical GIP on this GameSir G7 SE completes Hello (`0x02`) plus one rest input (`0x20`, 36-byte Share report, all-zero payload). Further `0x20` frames follow the GIP change-only rule, so a later packet-log window of 8-byte status (`0x03`) keepalives is not a failed handshake; the 48-entry log ages out that rest `0x20`. A 20s `controller trace` with no physical press saw only status. Steam `hid_init` hangs.
- Recorded browser results: Xbox Series `045E:0B13` in Blink and WebKit, and `045E:02E0` in Gecko, with the same stick/trigger ordering, hat-only D-pad, and standard B0–B16 mapping; Firefox's native remapper does not expose Xbox Share as B17. Automatic selection does not depend on the consumer.
- Recorded Xbox One Bluetooth `045E:02FD` experiments with the BT1 and BT2 descriptors reported no usable SDL HIDAPI input. `SDLCompatible` publishes `045E:0B0C` with an approximated descriptor, which GameController does not bind. In a test with the same descriptor on `045E:02FD`, Steam, PCSX2 and DuckStation read it through SDL, and GameController bound it with no input; SDL consumers on `045E:0B0C` are not hardware-verified.
- ASTRO C40 `9886:0024` is not a spoof target. It is a DualShock-style third-party pad; SDL HIDAPI's Xbox 360 driver special-cases it, but OJD does not impersonate it.
- No virtual HID VID/PID universally supplies Windows XInput/GIP semantics on macOS. Consumer identity, descriptor, transport, and report behavior must be tested separately.

ASTRO C40 PS4 mode `9886:0025` is research-only: it is a possible third-party DS4-family candidate, not an implemented spoof. Official DS4/DS5 identities remain preferred when their exact protocol tuples are proven.

## Browser Gamepad API Testing

**ControllerTest.io is the canonical manual browser test site**:

**<https://controllertest.io/>**

Run each matrix row from a clean browser document and record the exact browser version, Gamepad `id`, mapping, slot/count, every button and axis, timestamps, disconnect/reconnect behavior, and exposed actuator fields. One browser's result does not establish another's support; neither enumeration nor rumble alone proves support. Generic HID is expected to use `mapping: n/a`, with sticks on axes 0–3, analog LT/RT pressure on axes 4–5, and digital controls on B0–B5 and B8–B17. Digital-only trigger sources use full-scale values on axes 4–5. It intentionally does not expose B6/B7 or a D-pad axis. See the [browser test protocol and reported observations](browser-gamepad-api.md).

## Not Implemented and Recorded Spoof Results

Bluetooth support does not extend to arbitrary controllers. The ASTRO C40 PS4 mode `9886:0025` is experimental research only: the repository lacks a complete descriptor, feature/calibration, input, and output contract, so it is not a supported spoof route.

OJD publishes no per-family spoofed identity (a distinct Xbox 360, Switch Pro, or DualShock/DualSense virtual device chosen for a target consumer): only the three profiles exist: `SDLCompatible` or `Generic` picked by declared controls, and any of the three by a per-model or per-controller override. `GameControllerCompatible` publishes the Xbox Series `045E:0B13` identity of the first row with its Bluetooth report layout. The table below records consumer-bind results for per-family identities published during testing; none of them is a selectable route. Browser reports remain per-engine because Blink, WebKit, and Gecko can map the same family differently.

| Physical family/mode | SDL/HIDAPI | Apple GameController |
| --- | --- | --- |
| Xbox GIP, exact GameSir G7 SE mode | ⚠️ Series `045E:0B13`; custom HIDAPI xboxone BLE idle rest `0x8000`→0; no physical button; not Steam | ✅ Xbox Series `045E:0B13` |
| Xbox GIP, other modes | ⚠️ first-party Series unless a reported failure tuple exists | ⚠️ Xbox Series profile |
| Xbox 360 physical family | ⚠️ `sdl2-3` (Microsoft `045E:028E`) | 🔬 Series BT not used for 360 |
| XInputHID/XUSB wire protocol | ❌ no macOS emulation claim | ❌ no macOS emulation claim |
| Xbox One Bluetooth `045E:02FD` | 🧪 BT1/BT2 experiments reported no SDL input | 🔬 not yet verified |
| Nintendo Switch Pro | ⚠️ `switchpro` USB packer; explicit G7 SE publish: custom HIDAPI switchpro `SDL_OpenGamepad` ok, not Steam | ⚠️ `switchpro`; explicit G7 SE `supportsHIDDevice` yes |
| PlayStation DS4/DS5 | ⚠️ `dualshock4` / `dualsense`; explicit G7 SE publish: custom HIDAPI ps4/ps5 `SDL_OpenGamepad` ok, not Steam | ⚠️ first-party packers; explicit G7 SE `supportsHIDDevice` yes |
| Other | 🔬 no cross-family spoof | 🔬 no cross-family spoof |

Automatic does not use this table; see the declared-controls rule at the top. The Xbox One Bluetooth row records the BT1 and BT2 experiments, not the `SDLCompatible` profile.

## Apple GameController Support

Use live detection by `GCController.supportsHIDDevice` and a hardware test to determine whether the active virtual controller works with GameController.framework. Select `GameControllerCompatible` with `ojd virtual set game-controller-compatible CONTROLLER` for this test; the OJD probe checks whichever profile is currently published, and confirms whether macOS created `GCXboxGamepad`, `buttonShare`, and any paddle inputs. With a Razer Wolverine Tournament Edition (`1532:0A15`), GameController binds `SDLCompatible`'s reports on `045E:02FD` as `Xbox Wireless Controller (Xbox One)` and receives no input from them: the probe reports `live_input=false`. `SDLCompatible` publishes `045E:0B0C`, which GameController does not bind. Browser Gamepad API results are separate: a browser may omit Share even when native GameController.framework exposes it. The private current-system mapping catalog is optional. A missing pair does not prove incompatibility. See [Xbox fallback identity evidence](../development/xbox-identities.md).

To test GameController input by hand, run `swift run OpenJoystickDriverGameControllerViewer`. It reads controllers only through GameController and lists every input element of each connected controller with its current value. It prints each change as one JSON line with `time`, `controller`, `element`, and `pressed` and `value` for a button or trigger, or `x` and `y` for a D-pad or stick. A controller listed with no change on a press means GameController bound the device but receives no input from it. The viewer turns off the Home and Share system gestures for its elements; those buttons reach it only while it is the frontmost app.

To test the Gamepad API of Firefox, Chrome and Safari, run `just diagnose-browsers [--as PERSONA] [--browsers firefox,chrome,safari]`. It serves a logging page, opens it in each browser in turn, and feeds every control into one virtual gamepad with `ojd virtual feed`. For each control it prints the standard-mapping slot that the browser reported, as `ok`, `missing` or `differs`, and the browser's rumble result. The run writes `results.json` and `events.jsonl` under `.build/browser-gamepad/`. Keep each browser's window in front while it runs; other controllers may stay connected.

## Input Integrity

Before a parsed packet reaches an output backend, OJD reduces its events to the packet's final net controller state. It drops duplicate transitions and contradictory press/release pulses that end unchanged. It also emits one canonical D-pad direction, rejects non-finite analog values by retaining the prior component, and clamps sticks to `-1...1` and triggers to `0...1`. This integrity gate does not add a timing delay or a new global deadzone. Protocol-specific deadzones remain in their parsers.

The normalized batch is delivered to one persistent virtual-HID device per physical controller. Focusing or opening a consumer does not replace that device, so SDL hot-plug state remains stable. Automatic selection is not persisted; only a per-model override is.

## Manual Checks

Before marking a mapping verified, check the exact app and mode:

1. SDL2/3: `A2` and `A5` idle at zero, D-pad releases cleanly.
2. Parsec macOS to Windows: D-pad and A/B/X/Y stay stable on the Windows host.
3. Rumble: app output report reaches the physical controller if the controller supports rumble.
