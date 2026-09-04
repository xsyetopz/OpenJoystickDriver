# Compatibility modes

Choose the route for the actual consumer. Enumeration alone is not evidence that
the consumer can read input; every route names its protocol family and evidence
status. Automatic routing is conservative and selects only an exact,
catalog-backed tuple. `sdl2-3` remains an explicit route for its ASTRO C40
Xbox-mode evidence, specific to SDL/HIDAPI-style consumers.

Status marks appear only in the support lists below:

- ✅ hardware-verified for the named physical mode and consumer
- ⚠️ source-backed candidate; live consumer evidence still required
- 🧪 reported failure or experimental result; never auto-selected
- 🔬 research-only; no production spoof
- ❌ unavailable

## Choose an identity

### `sdl2-3`

Use for applications that consume SDL 2 or SDL 3, including Steam and PCSX2.
The virtual device publishes the ASTRO C40 `9886:0024` identity with its exact
Xbox 360 HIDAPI descriptor and report format. PCSX2 Nightly accepted input and
sent working physical rumble through this route on the tested GameSir G7 SE.
The previous GameStop `1BAD:F901` mapping identity was removed after it produced
input but no dependable rumble.

### `apple-gamecontroller`

Use only to test native applications that read `GCController`. This selectable
route uses the Xbox Series Bluetooth tuple `045E:0B13`. Its primary input report
includes the Consumer Record usage that GameController.framework exposes as
`GCXboxGamepad.buttonShare`. View and Share remain separate inputs. Selecting
it does not republish the foreground identity or create a second virtual device.

GameController clients control macOS controller gestures. If an app leaves a
gesture enabled, macOS may delay View or reserve Guide and Share. The OJD probe
can disable those gestures for its own test, but OJD cannot change another
app's gesture settings.
`GCController.supportsHIDDevice`, connect, extended-profile, input, and
reconnect results are diagnostic evidence, not guarantees. Do not claim
haptics without a physical/runtime observation.

### `generic-hid`

Use for unknown or unsupported consumers that fit none of the specialized
profiles. The descriptor exposes a plain gamepad under OJD VID/PID.
Vendor-specific controls may be absent.

### `xbox360-hid`

Use only for a consumer that needs the OJD Xbox 360-family HID descriptor and
report shape. This is a generic HID compatibility profile, not Windows XUSB or
XInputHID emulation. It uses the OJD Xbox 360 HID report format and remains
research-only until a named consumer is tested.

Set an explicit identity from the installed CLI:

```bash
/Applications/OpenJoystickDriver.app/Contents/MacOS/OpenJoystickDriver --headless compat set sdl2-3
/Applications/OpenJoystickDriver.app/Contents/MacOS/OpenJoystickDriver --headless compat set apple-gamecontroller
```

Only explicit identities are persistence guarantees: a successful selection is
stored and rebuilt on service startup. With `automatic`, the persisted value is
the automatic intent, not a fixed identity. Foreground-consumer routing may
replace or retire the per-controller user-space backend at runtime and does not
persist that temporary choice.

## Controller support

### ✅ Hardware-backed paths

- GameSir G7 SE through GIP, including four-motor output
- Flydigi Vader 5S through GIP; the record sets USB configuration 1 before claim
- DualShock 4 USB and Bluetooth input, rumble, and RGB lightbar
- Xbox 360 USB parsing; individual model coverage still varies

### 🚧 Source-backed paths needing hardware checks

- DualShock 3 USB and Bluetooth input, operational-mode setup, two motors, and player LEDs
- DualSense USB and Bluetooth input, compatible rumble, player LEDs, and RGB lightbar
- Steam Controller wired and wireless input, lifecycle, trackpad haptics, and LED brightness
- Switch Pro USB and Bluetooth input, startup reports, HD rumble, and player LEDs
- Linux xpad-derived Xbox records that have not been tested on their matching hardware

### ⚠️ Fallback and consumer limits

- Generic HID maps descriptor-defined controls but cannot infer vendor protocols.
- Raw and vendor-specific USB controllers use direct IOUSBHost when macOS permits app ownership.
  Entitlement-restricted models require OJD's signed USB DriverKit extension.
- `045E:0B13` is used only for the explicit Apple GameController route.
- Earlier Xbox One Bluetooth `045E:02FD` spoof experiments reported no usable
  SDL HIDAPI input and are gone from selectable identities; unknown persisted
  identity strings sanitize to `automatic` on load.
  `9886:0024` is hardware-verified only for SDL HIDAPI-style consumers.
- No virtual HID VID/PID universally supplies Windows XInput/GIP semantics on
  macOS. Consumer identity, descriptor, transport, and report behavior must
  be tested separately.

ASTRO C40 PS4 mode `9886:0025` is research-only: it is a possible third-party
DS4-family candidate, not an implemented spoof. Official DS4/DS5 identities
remain preferred when their exact protocol tuples are proven.

## Browser Gamepad API testing

For manual browser testing, **Hardwaretester remains the canonical external manual site**:

**<https://hardwaretester.com/gamepad>**

Run each matrix row from a clean browser document and record the exact browser
version, Gamepad `id`, mapping, slot/count, every button and axis, timestamps,
disconnect/reconnect behavior, and exposed actuator fields. The optional
[local Gamepad API probe](../testing/browser-gamepad-api.md) runs only through
localhost and requires explicit Start/Stop; it exports redacted observed state
for deeper event and polling detail. A result in one browser does not establish
support in another, and enumeration or rumble alone is not a support claim.
See the [Plan 06 browser matrix](../testing/browser-gamepad-api.md#exact-beta3-matrix).

### ❌ Not implemented

Bluetooth support does not extend to arbitrary controllers. The ASTRO C40 PS4
mode `9886:0025` is experimental research only: the repository lacks a
complete descriptor, feature/calibration, input, and output contract, so it is
not a supported spoof route.

Compatibility selection is keyed by **physical protocol family × target
consumer × evidence**. Xbox GIP/XInput/XUSB inputs may use an Xbox-adjacent
identity only when that consumer evidence exists; the OJD `xbox360-hid` route
is generic HID and is not XUSB/XInputHID emulation. Nintendo and PlayStation
inputs require their own adjacent supported identity. The SDL ASTRO C40 route
does not cross those family boundaries merely because SDL accepts it. When no
verified adjacent identity exists, OJD uses generic HID rather than guessing.
Browser reports remain per-engine because Chromium, WebKit, and Gecko can map
the same family differently.

| Physical family/mode | SDL/HIDAPI | Apple GameController | Automatic result |
| --- | --- | --- | --- |
| Xbox GIP, exact GameSir G7 SE mode | ❌ Generic HID (no adjacent tuple) | ⚠️ Xbox Series profile exposes Share separately | Do not substitute ASTRO C40 automatically |
| Xbox GIP, other modes | 🔬 no verified adjacent tuple | ⚠️ Xbox Series profile; test each controller | Generic HID; no ASTRO substitution |
| Xbox 360 physical family | 🔬 no verified adjacent tuple | ⚠️ separate test | Generic HID |
| XInputHID/XUSB wire protocol | ❌ no macOS emulation claim | ❌ no macOS emulation claim | Generic HID |
| Xbox One Bluetooth `045E:02FD` | 🧪 BT1/BT2 reported no SDL input; route retired | 🔬 use `apple-gamecontroller` or `generic-hid` | Generic HID |
| Nintendo Switch Pro | 🔬 no adjacent verified route | 🔬 no adjacent verified route | Generic HID |
| PlayStation DS4/DS5 | 🔬 official tuple required | 🔬 official tuple required | Generic HID unless tuple is proven |
| Other | 🔬 no cross-family spoof | 🔬 no cross-family spoof | Generic HID |

## Apple GameController support

Use live detection by `GCController.supportsHIDDevice` and a hardware test to
determine whether the active virtual controller works with
GameController.framework. The `apple-gamecontroller` profile publishes
`045E:0B13`; the OJD probe confirms whether macOS created `GCXboxGamepad`,
`buttonShare`, and any paddle inputs. Browser Gamepad API results are separate:
a browser may omit Share even when native GameController.framework exposes it.
The private current-system mapping catalog is optional. A missing pair does not
prove incompatibility. See
[Xbox fallback identity evidence](../development/xbox-identities.md).

## USB DriverKit extension

`OpenJoystickDriverUSB` selects between direct app-side IOUSBHost and
`com.openjoystickdriver.XboxUSBDevice`. The DEXT is used only for an observed
DEXT-owned service or an Apple-entitled Microsoft Xbox GIP model; it is not
the generic path for every controller. OJD does not use libusb or publish a
second controller. Development and production DEXT matching are both limited
to the VID/PID pairs in OJD's Apple-issued entitlement. Accessible third-party
controllers, including the GameSir G7 SE, use direct app-side IOUSBHost instead.

Run the shared CLI self-test even while Compatibility mode is active:

```bash
/Applications/OpenJoystickDriver.app/Contents/MacOS/OpenJoystickDriver --headless test 5
```

The self-test checks the current Compatibility virtual-HID backend. For an
explicit identity, that backend is rebuilt from the persisted identity after
service startup. In `automatic` mode, foreground routing may replace or retire
the per-controller backend while the persisted value remains the automatic
intent; the self-test therefore does not prove a universally persistent
backend. On macOS 10.15–14 the active backend uses `IOHIDUserDevice`; on macOS
15 and later it uses CoreHID `HIDVirtualDevice`. A self-test does not prove USB
system-extension approval, signing validity, or behavior on a different macOS
version or hardware.

## App rumble

OJD forwards app rumble only when the virtual report and physical parser agree on an output format. Supported inputs are Xbox One report ID `3`, the eight-byte Xbox 360 packet, OJD compact report `0x4F`, and DualShock 4 Bluetooth report `0x11`.

Xbox 360 and DualShock 4 use their two main motors. GIP controllers may also use trigger motors. DualShock 4 ignores trigger values.

## Input integrity

Before a parsed packet reaches an output backend, OJD reduces its events to the packet's final net controller state. It drops duplicate transitions and contradictory press/release pulses that end unchanged. It also emits one canonical D-pad direction, rejects non-finite analog values by retaining the prior component, and clamps sticks to `-1...1` and triggers to `0...1`. This integrity gate does not add a timing delay or a new global deadzone. Protocol-specific deadzones remain in their parsers.

For an explicit identity, the normalized batch is delivered to one persistent
virtual-HID device per physical controller. Focusing or opening a consumer does
not replace that device, so SDL hot-plug state remains stable. In `automatic`
mode, foreground routing may replace or retire the per-controller backend;
only the automatic intent is persisted, not that temporary consumer choice.

## Manual checks

Before marking a mapping verified, you must check the exact app and mode:

1. SDL2/3: `A2` and `A5` idle at zero, D-pad releases cleanly.
2. Parsec macOS to Windows: D-pad and A/B/X/Y stay stable on the Windows host.
3. Rumble: app output report reaches the physical controller if the controller supports rumble.
