# Compatibility modes

Start with `sdl2-3`. Change the identity only when a game, browser, or native macOS app needs a different HID shape.

Status marks appear only in the support lists below:

- ✅ tested project behavior
- ⚠️ usable with a known limitation
- 🚧 implemented from source but short of hardware evidence
- ❌ unavailable

## Choose an identity

### `sdl2-3`

Use for most games, Steam, emulators, Moonlight, and other SDL software. OJD owns the VID/PID and ships an SDL mapping.

### `apple-gamecontroller`

Use for native applications that read `GCController`. The identity publishes an Xbox-style HID surface with GameController haptics. SDL MFI enumeration still needs targeted testing.

### `generic-hid`

Use for direct HID testing or as a non-spoof fallback. The descriptor exposes a plain gamepad under OJD VID/PID. Vendor-specific controls may be absent.

### `x360-hid`

Use only when software expects an Xbox 360-style HID report. The identity is experimental and does not implement Windows XInput or XUSB. Test SDL output reports with `./scripts/ojd diagnose sdl3-hidapi-x360 --seconds 5`.

### `xone-hid`

Use only when software expects an Xbox One-style HID identity. The identity is experimental and does not turn macOS into an Xbox transport host.

Set an identity from the installed CLI:

```bash
/Applications/OpenJoystickDriver.app/Contents/MacOS/OpenJoystickDriver --headless compat sdl2-3
/Applications/OpenJoystickDriver.app/Contents/MacOS/OpenJoystickDriver --headless compat apple-gamecontroller
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
- Browser Gamepad mappings vary by browser, identity, macOS release, and stale device state.
- The DriverKit relay is an integrity-test transport, not a consumer gamepad.

### ❌ Not implemented

Bluetooth support does not extend to arbitrary controllers. Only the named DS3, DS4, DualSense, and Switch Pro parser paths exist.

## Apple GameController support

Live detection by `GCController.supportsHIDDevice` and a hardware test determine whether the active virtual controller works with GameController.framework. The private current-system mapping catalog is only an optional developer comparison for exact physical OJD record VID/PID pairs; a missing pair does not prove incompatibility. See [Xbox fallback identity evidence](../development/xbox-identities.md).

## DriverKit Relay

The generated SwifterKit DriverKit relay publishes a vendor-defined HID device,
not a Generic Desktop GamePad. This prevents it from becoming a stale or duplicate
controller beside the Compatibility `IOHIDUserDevice`. Its role is an integrity
path between the application service, the host-side relay, and DriverKit HID
delivery; it is not an alternative consumer output mode.

Run the shared CLI/GUI self-test even while Compatibility mode is active:

```bash
/Applications/OpenJoystickDriver.app/Contents/MacOS/OpenJoystickDriver --headless selftest 5
```

A passed relay verdict is based on observed relay input delivery when macOS exposes
it, or on a successful SwifterKit HID submission when those observations are not
available. The command reads the signed host's
`com.apple.developer.driverkit.userclient-access` entitlement. An entitled host
must pass the relay check. Without that entitlement, relay diagnostics are optional
and inconclusive, while the Compatibility check still controls command success.
The Compatibility probe uses neutral reports and does not change controller state.
A self-test does not prove system-extension approval, signing validity, or behavior
on a different macOS version or hardware configuration.

## App rumble

OJD forwards app rumble only when the virtual report and physical parser agree on an output format. Supported inputs are Xbox One report ID `3`, the eight-byte Xbox 360 packet, OJD compact report `0x4F`, and DualShock 4 Bluetooth report `0x11`.

Xbox 360 and DualShock 4 use their two main motors. GIP controllers may also use trigger motors. DualShock 4 ignores trigger values. DriverKit relay bytes that do not match a supported report are ignored.

## Input integrity

Before a parsed packet reaches an output backend, OJD reduces its events to the packet’s final net controller state. It drops duplicate transitions and contradictory press/release pulses that end unchanged, emits one canonical D-pad direction, rejects non-finite analog values by retaining the prior component, and clamps sticks to `-1...1` and triggers to `0...1`. This integrity gate does not add a timing delay or a new global deadzone. Protocol-specific deadzones remain in their parsers.

The normalized batch is delivered only to the active Compatibility `IOHIDUserDevice` backend.

## Browser mapping

### `sdl2-3` and `generic-hid`

- **`B0` / `B1` / `B2` / `B3`** — A / B / X / Y
- **`B4` / `B5`** — LB / RB
- **`B6` / `B7`** — L3 / R3
- **`B8` / `B9`** — Menu / View
- **`B10`** — Xbox/Home
- **`B11` / `B12` / `B13` / `B14`** — D-pad Up / Down / Left / Right
- **`B15`** — Share
- **`A0` / `A1`** — Left stick X / Y
- **`A2`** — LT
- **`A3` / `A4`** — Right stick X / Y
- **`A5`** — RT

LT and RT idle at zero. D-pad is button-backed only.

### `apple-gamecontroller`, `x360-hid`, and `xone-hid`

- **`B0` / `B1` / `B2` / `B3`** — A / B / X / Y
- **`B4` / `B5`** — LB / RB
- **`B6` / `B7`** — LT / RT
- **`B8` / `B9`** — View / Menu
- **`B10` / `B11`** — L3 / R3
- **`B12` / `B13` / `B14` / `B15`** — D-pad Up / Down / Left / Right
- **`B16`** — Xbox/Home

### Repeatable browser diagnostic

Serve OJD's local-only test page from the main CLI:

```bash
./.build/debug/OpenJoystickDriver --headless diagnose browser-gamepad \
  --seconds 300 --open all
```

The page does not change the active compatibility identity and does not upload results. Run it once per identity and browser engine:

```bash
./.build/debug/OpenJoystickDriver --headless compat sdl2-3
./.build/debug/OpenJoystickDriver --headless diagnose browser-gamepad --open all

./.build/debug/OpenJoystickDriver --headless compat generic-hid
./.build/debug/OpenJoystickDriver --headless diagnose browser-gamepad --open all
```

Capture the JSON snapshot from Safari/WebKit, Firefox/Gecko, and Chrome/Blink. The page can submit a snapshot only to its loopback OJD session after an explicit button press. For a combined CLI export, pass `--output /path/to/snapshots.json`; the command prints the accepted snapshot count while the session is active. It records the browser's Gamepad ID and mapping, button/axis counts, duplicate instances, requestAnimationFrame cadence, a ten-second hands-off misfire/drift sample, connection events, and only the haptic effect names exposed by that browser. Haptic buttons remain disabled unless the actuator reports the corresponding effect. The current Gamepad specification defines both [`dual-rumble` and `trigger-rumble`](https://www.w3.org/TR/gamepad/#gamepadhapticeffecttype-enum); browser and platform exposure still varies.

A snapshot is evidence for that exact browser, compatibility identity, macOS version, and hardware path. It is not sufficient to mark another combination supported.

## SDL mapping

`Resources/SDL/openjoystickdriver.gamecontrollerdb.txt` maps `sdl2-3` like this:

- **`a` / `b` / `x` / `y`** — **HID source:** `b0` / `b1` / `b2` / `b3`
- **`leftshoulder` / `rightshoulder`** — **HID source:** `b4` / `b5`
- **`leftstick` / `rightstick`** — **HID source:** `b6` / `b7`
- **`start` / `back` / `guide`** — **HID source:** `b8` / `b9` / `b10`
- **`dpup` / `dpdown` / `dpleft` / `dpright`** — **HID source:** `b11` / `b12` / `b13` / `b14`
- **`misc1`** — **HID source:** `b15`
- **`leftx` / `lefty`** — **HID source:** `a0` / `a1`
- **`lefttrigger`** — **HID source:** `a2`
- **`rightx` / `righty`** — **HID source:** `a3` / `a4`
- **`righttrigger`** — **HID source:** `a5`

## Manual Checks

Before marking a mapping verified, you must check the exact app and mode:

1. Browser Gamepad API: buttons and axes match the active identity table.
2. SDL 2/3: `A2` and `A5` idle at zero, D-pad releases cleanly.
3. Parsec macOS to Windows: D-pad and A/B/X/Y stay stable on the Windows host.
4. Rumble: app output report reaches the physical controller if the controller supports rumble.
