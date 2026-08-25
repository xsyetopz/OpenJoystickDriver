# Compatibility modes

Start with `sdl2-3`. Change the identity only when a game or native macOS app needs a different HID shape.

Status marks appear only in the support lists below:

- ✅ tested project behavior
- ⚠️ usable with a known limitation
- 🚧 implemented from source but short of hardware evidence
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

Use only to test native applications that read `GCController`. CoreHID virtual
device access does not itself create `GCController.haptics`. On the tested
GameSir G7 SE setup, GameController exposed neither input nor a public haptics
engine for this identity.

### `generic-hid`

Use for unknown or unsupported consumers that fit none of the specialized
profiles. The descriptor exposes a plain gamepad under OJD VID/PID.
Vendor-specific controls may be absent.

### `xone-hid`

Use only when software expects an Xbox One-style XInput/XUSB-compatible HID
identity. The identity is experimental and does not turn macOS into an Xbox
transport host. The tested
GameSir G7 SE published the virtual identity and kept its LED on, but PCSX2
Nightly received no input; do not use it as a fallback.

Set an identity from the installed CLI:

```bash
/Applications/OpenJoystickDriver.app/Contents/MacOS/OpenJoystickDriver --headless compat set sdl2-3
/Applications/OpenJoystickDriver.app/Contents/MacOS/OpenJoystickDriver --headless compat set apple-gamecontroller
```

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

### ❌ Not implemented

Bluetooth support does not extend to arbitrary controllers. Only the named DS3, DS4, DualSense, and Switch Pro parser paths exist.

## Apple GameController support

Use live detection by `GCController.supportsHIDDevice` and a hardware test to determine whether the active virtual controller works with GameController.framework. The private current-system mapping catalog is optional. Developers can use it to compare exact physical OJD record VID/PID pairs, but a missing pair does not prove incompatibility. See [Xbox fallback identity evidence](../development/xbox-identities.md).

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

The self-test checks the persistent Compatibility virtual-HID backend. On macOS 10.15–14
that backend uses `IOHIDUserDevice`; on macOS 15 and later it uses CoreHID
`HIDVirtualDevice`. A self-test does not prove USB system-extension approval,
signing validity, or behavior on a different macOS version or hardware.

## App rumble

OJD forwards app rumble only when the virtual report and physical parser agree on an output format. Supported inputs are Xbox One report ID `3`, the eight-byte Xbox 360 packet, OJD compact report `0x4F`, and DualShock 4 Bluetooth report `0x11`.

Xbox 360 and DualShock 4 use their two main motors. GIP controllers may also use trigger motors. DualShock 4 ignores trigger values.

## Input integrity

Before a parsed packet reaches an output backend, OJD reduces its events to the packet’s final net controller state. It drops duplicate transitions and contradictory press/release pulses that end unchanged. It also emits one canonical D-pad direction, rejects non-finite analog values by retaining the prior component, and clamps sticks to `-1...1` and triggers to `0...1`. This integrity gate does not add a timing delay or a new global deadzone. Protocol-specific deadzones remain in their parsers.

The normalized batch is delivered to one persistent virtual-HID device per
physical controller. Focusing or opening a consumer does not replace that
device, so SDL hot-plug state remains stable.

## Manual checks

Before marking a mapping verified, you must check the exact app and mode:

1. SDL2/3: `A2` and `A5` idle at zero, D-pad releases cleanly.
2. Parsec macOS to Windows: D-pad and A/B/X/Y stay stable on the Windows host.
3. Rumble: app output report reaches the physical controller if the controller supports rumble.
