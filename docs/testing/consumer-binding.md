# Consumer-Binding Evidence

Evidence behind compatibility claims. User summary: [virtual HID profiles](../../wiki/Using-the-App.md).

| Mark | Meaning |
| --- | --- |
| ✅ | hardware-verified for the named physical mode and consumer |
| ⚠️ | source support, needs live consumer evidence |
| 🧪 | reported failure or experimental result |
| 🔬 | research only |
| ❌ | unavailable |

## Recorded Fallback and Consumer Limits

| Topic | Recorded result |
| --- | --- |
| GameSir G7 Pro 3537:100A, 3537:1022 | Input-only. OJD does not switch modes or force re-enumeration; to expose a configuration-ready identity, hold Menu+Share before connecting. |
| GameSir Microsoft Bluetooth identities 045E:02FD, 045E:02FF | Shared; Microsoft or Generic HID handling. No GameSir model without an exact hardware capture. |
| GameSir 3537:1004 | Linux-backed XUSB identity T4 Kaleid shares. The reported White G7 Pro dongle collision does not justify changing that route. Linux-backed 3537:100F and 3537:1010 also use XUSB and GIP. |
| Generic HID | Maps descriptor-defined controls; cannot infer vendor protocols. |
| Raw and vendor-specific USB | Direct IOUSBHost when macOS permits app ownership; entitlement-restricted models need OJD's signed USB DriverKit extension. |
| Steam | `hid_init` hangs (bundled SDL 3.5.0, 5s watchdog). sdlHIDAPI has source support, no Steam HIDAPI result. |
| Browsers | Xbox Series 045E:0B13 in Blink and WebKit, 045E:02E0 in Gecko: same stick/trigger ordering, hat-only D-pad, standard B0-B16 mapping. Firefox's native remapper does not expose Xbox Share as B17. |
| ASTRO C40 9886:0024 | DualShock-style third-party pad that SDL HIDAPI's Xbox 360 driver special-cases. No spoof target; OJD does not impersonate it. |
| Windows semantics | No virtual HID VID/PID supplies XInput/GIP semantics on macOS in every case. Test identity, descriptor, transport, and report behavior separately. |

- Xbox Series BLE input: Interrupt IN streams idle 17-byte Series reports (`0x01` plus 0x8000 sticks, official BLE rest); HIDAPI xboxone BLE HandleStatePacket maps them to signed 0 (`raw - 0x8000`). A 12s watch saw 48 idle reports, no button bit. A packer-built A-pressed report decodes SOUTH true through the same layout (no physical press).
- Leftover IOHID 045E:028E AppleGCSyntheticDevice "GamePad-1": Ignore it: GameController creates that 360 HID shim when it binds an Xbox identity (045E:0B13 included). OJD excludes synthetic registry markers before any user-client open; the name GamePad-1 alone excludes no physical device. Stock SDL match-all deadlocks on a leftover wedged shim.
- Physical GIP, GameSir G7 SE: Completes Hello (`0x02`) plus one rest input (`0x20`, 36-byte Share report, all-zero payload); further `0x20` frames follow the GIP change-only rule. A later window of 8-byte status (`0x03`) keepalives is no failed handshake: the 48-entry log ages out that rest `0x20`. A 20s `controller trace` with no press saw only status.
- Xbox One Bluetooth 045E:02FD: BT1 and BT2 descriptors: no usable SDL HIDAPI input. SDLCompatible publishes 045E:0B0C with an approximated descriptor GameController does not bind. On 045E:02FD that descriptor reads through SDL in Steam, PCSX2, and DuckStation; GameController binds it with no input. SDL consumers on 045E:0B0C: no hardware check.

Published-identity results (SDL: custom SDL 3.4.16 HIDAPI+IOKit build, no GameController.framework):

| Identity | Transport, report | GameController | SDL |
| --- | --- | --- | --- |
| Xbox Series 045E:0B13 "Xbox Wireless Controller" | BLE 17-byte, `bus_type` 2, not USB GIP | bound on GameSir G7 SE USB GIP | HIDAPI xboxone over Bluetooth |
| DualShock 4 054C:09CC "Wireless Controller" | USB, 64-byte report `0x01`, descriptor 114 bytes | supportsHIDDevice yes | `SDL_OpenGamepad` opened ps4 |
| DualSense 054C:0CE6 "Wireless Controller" | USB, 64-byte report `0x01`, descriptor 273 bytes | supportsHIDDevice yes | `SDL_OpenGamepad` opened ps5 |
| Switch Pro 057E:2009 "Pro Controller" | USB Joystick, 64-byte reports, descriptor 203 bytes | supportsHIDDevice yes, no hang | `SDL_OpenGamepad` opened switchpro |
| 045E:028E "Xbox 360 Wired Controller" | USB Joystick, 14-byte reports, `bcdDevice` 0x0114, descriptor 201 bytes | supportsHIDDevice yes | `SDL_OpenGamepad` opened xbox360 |

## Browser Gamepad API Testing

Site: ControllerTest.io (<https://controllertest.io/>); observations: [Browser Gamepad API Manual Evidence](browser-gamepad-api.md). One browser's result says nothing about another; enumeration or rumble alone proves no support.

Generic HID uses `mapping: n/a`: sticks on axes 0-3, analog LT/RT pressure on axes 4-5, digital controls on B0-B5 and B8-B17. Digital-only trigger sources use full-scale values on axes 4-5. No B6/B7 or D-pad axis.

## Unimplemented Routes and Recorded Spoof Results

ASTRO C40 PS4 mode 9886:0025 is a possible third-party DS4-family candidate, research only: no complete descriptor, feature/calibration, input, or output contract, no spoof. Official DS4/DS5 identities are preferred once their exact protocol tuples are proven.

OJD publishes no per-family spoofed identity (a distinct Xbox 360, Switch Pro, or DualShock/DualSense virtual gamepad per consumer). Three profiles exist: SDLCompatible or Generic, picked by declared controls, and any of the three, picked by a per-model or per-controller override. GameControllerCompatible publishes the first row's Xbox Series 045E:0B13 identity with its Bluetooth report layout. The table records consumer-bind results for per-family identities published during testing; none is selectable. Browser reports stay per-engine: Blink, WebKit, and Gecko can map a family differently.

| Physical family/mode | SDL/HIDAPI | Apple GameController |
| --- | --- | --- |
| Xbox GIP, exact GameSir G7 SE mode | ⚠️ Series 045E:0B13; custom HIDAPI xboxone BLE idle rest `0x8000`→0; no physical button; not Steam | ✅ Xbox Series 045E:0B13 |
| Xbox GIP, other modes | ⚠️ first-party Series unless a reported failure tuple exists | ⚠️ Xbox Series profile |
| Xbox 360 physical family | ⚠️ sdl2-3 (Microsoft 045E:028E) | 🔬 Series BT not used for 360 |
| XInputHID/XUSB wire protocol | ❌ no macOS emulation claim | ❌ no macOS emulation claim |
| Xbox One Bluetooth 045E:02FD | 🧪 BT1/BT2 experiments reported no SDL input | 🔬 not verified |
| Nintendo Switch Pro | ⚠️ switchpro USB packer; explicit G7 SE publish: custom HIDAPI switchpro SDL_OpenGamepad ok, not Steam | ⚠️ switchpro; explicit G7 SE supportsHIDDevice yes |
| PlayStation DS4/DS5 | ⚠️ dualshock4 / dualsense; explicit G7 SE publish: custom HIDAPI ps4/ps5 SDL_OpenGamepad ok, not Steam | ⚠️ first-party packers; explicit G7 SE supportsHIDDevice yes |
| Other | 🔬 no cross-family spoof | 🔬 no cross-family spoof |

Automatic selection ignores this table. The Xbox One Bluetooth row records the BT1 and BT2 experiments, not SDLCompatible.

## Apple GameController Support

Test with GCController.supportsHIDDevice and hardware. Select GameControllerCompatible with `ojd virtual set game-controller-compatible CONTROLLER`. The OJD probe checks whether macOS created GCXboxGamepad, buttonShare, and any paddle inputs.

With a Razer Wolverine Tournament Edition (1532:0A15), GameController binds SDLCompatible's reports on 045E:02FD as `Xbox Wireless Controller (Xbox One)` and receives no input; the probe reports `live_input=false`.

A browser may omit Share even when GameController.framework exposes it. A missing pair in the optional private mapping catalog does not prove incompatibility. See [Xbox fallback identity evidence](../development/xbox-identities.md).

By hand: `swift run OpenJoystickDriverGameControllerViewer` lists every input element of each connected controller and prints each change as one JSON line with `time`, `controller`, `element`, and `pressed` and `value` (button or trigger) or `x` and `y` (D-pad or stick). A listed controller with no change on a press is bound but gets no input. Home and Share reach the viewer only while it is frontmost.

For Firefox, Chrome, and Safari, run `just diagnose-browsers` ([Automated Run](browser-gamepad-api.md#automated-run)) with each browser's window in front. Other controllers may stay connected.

## Input Integrity

Before a parsed packet reaches an output backend, OJD reduces its events to the final net state: it drops duplicate transitions and press/release pulses that end unchanged, emits one canonical D-pad direction, keeps the prior value for non-finite analog input, and clamps sticks to `-1...1` and triggers to `0...1`. No timing delay, no global deadzone; protocol-specific deadzones stay in their parsers.

OJD delivers the batch to one persistent virtual gamepad per physical controller, so SDL hot-plug state stays stable. It persists only a per-model override, not automatic selection.

## Manual Checks

Before marking a mapping verified, check the app and mode:

1. SDL2/3: `A2` and `A5` idle at zero; the D-pad releases cleanly.
2. Parsec macOS to Windows: the D-pad and A/B/X/Y stay stable on the Windows host.
3. Rumble: the app output report reaches the physical controller, if it supports rumble.

## Further Reading

- [Browser Gamepad API Manual Evidence](browser-gamepad-api.md)
- [Xbox Fallback Identity Evidence](../development/xbox-identities.md)
