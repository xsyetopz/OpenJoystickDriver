# Experimental controller status

Experimental means that production parser or output code exists but accepted hardware evidence is incomplete. Do not set `provenance.verified` to `true` because a fixture passes.

## Validation

Run these checks after parser or record changes:

```bash
swift build
swift test
./scripts/ojd test parsers-macos14
./scripts/ojd validate profiles
./scripts/ojd validate scripts
git diff --check
```

The macOS 14 harness and Swift test targets share the maintained compatibility
floor for parser and runtime behavior.

## DualSense

Implemented:

- USB report `0x01` and Bluetooth report `0x31` input
- Bluetooth input CRC32 validation with seed `0xA1`
- compatible rumble over USB and Bluetooth
- five player-indicator LEDs
- RGB lightbar output
- Bluetooth sequence framing and output CRC32 with seed `0xA2`

Needed: physical USB and Bluetooth checks for input, reconnect, rumble, indicators, and color. Records remain unverified.

## DualShock 3

Implemented:

- USB and Bluetooth input report `0x01`
- transport-specific operational-mode setup
- bogus Bluetooth status report filtering
- analog large motor and binary small motor
- four numbered player LEDs

Not claimed: sensors, battery reporting, or pairing support. USB control-transfer behavior and Bluetooth operation need hardware checks.

## Steam Controller

Implemented:

- wired and wireless records
- exact VID/PID discovery even when lizard mode exposes keyboard or mouse collections
- wireless connect, disconnect, and status fallback
- input parsing and lizard-mode feature reports
- left and right trackpad haptics
- home-button LED brightness

The wired report for issue #8 reached macOS as lizard-mode keyboard input while the old gamepad-only monitor found no device. Profile-backed discovery now covers that case. Run [the Steam Controller request](../testing/steam-controller.md) to check the new path.

## Switch Pro

Implemented:

- USB startup handshake and full-report command
- Bluetooth input without the USB-only startup sequence
- 12-bit stick, button, and D-pad parsing
- independent HD-rumble frames
- four player LEDs
- startup and output rate limits

Needed: calibration, IMU, reconnect, rumble, and LED checks on USB and Bluetooth hardware.

## Xbox 360 wireless receiver

Implemented from Linux `xpad.c`:

- receiver records for `045e:0291`, `045e:02a9`, and `045e:0719`
- logical-controller presence and disconnect handling
- wrapped state reports
- receiver rumble and player-light packets

Run [the receiver request](../testing/xbox-360-wireless-receiver.md) with real receiver hardware.

## Razer Wolverine V3 Tournament Edition

The bundled GIP record replaces the ineffective Generic HID fallback for `1532:0A43`. Endpoint, handshake, input, and output behavior still need the [Razer hardware test](../testing/razer/v3-te.md).

## Microsoft Xbox One Controller (model 1537)

Reporter packet evidence from an IOUSBHost harness verifies the GIP handshake, player LED, every input including Guide, and rumble for `045E:02D1`. The record therefore carries the observed `0x81`/`0x01` endpoints, configuration-1-before-claim requirement, and verified provenance. OJD's libusb/SwiftUSB device-open path has not passed on this hardware and remains pending the [model 1537 regression test](../testing/xbox/1537.md) after the upstream lifetime fix.

## Razer Wolverine V2

The source-backed GIP record for `1532:0A29` has a local-hardware patch for the captured interface-0 endpoints `0x81`/`0x01`. Input mapping, reconnect, LED, and rumble behavior remain unverified pending the [Wolverine V2 hardware test](../testing/razer/wolverine-v2.md).

## Xbox Adaptive Joystick

No parser claim exists. Product descriptions do not provide a packet layout. Capture neutral, every button, stick axes, stick click, report IDs, and checksums with [the packet request](../testing/xbox-adaptive-joystick.md) before adding a record.

## Generic HID

Descriptor-driven fallback handles standard buttons, stick pairs, triggers, and an eight-way hat. Known protocol parsers still consume their raw reports. Vendor-defined layouts need a record and parser instead of more guesses in Generic HID.

## Browser evidence

The local Gamepad diagnostic accepts an explicit same-origin snapshot submission and exports up to 12 bounded snapshots. Use it to record browser IDs, mappings, duplicate instances, button and axis counts, and actuator exposure. A browser snapshot proves only the tested browser, macOS build, identity, and hardware path.
