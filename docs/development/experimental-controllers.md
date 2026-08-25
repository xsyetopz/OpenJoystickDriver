# Experimental controller status

Experimental entries have implementation work but incomplete accepted hardware evidence. Do not set `provenance.verified` to `true` because a fixture passes.

For parser or record changes, run the parser validation gates in `AGENTS.md`.

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

The issue #8 wired report reaches macOS as lizard-mode keyboard input; gamepad-only monitoring does not find it. Profile-backed discovery covers that case. Run [the Steam Controller request](../testing/steam-controller.md) to check it.

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

Reporter packet evidence from an IOUSBHost harness verifies the GIP handshake,
player LED, every input including Guide, and rumble for `045E:02D1`. The record
carries the observed `0x81`/`0x01` endpoints, configuration-1-before-claim
requirement, and verified provenance. OJD's generated USBDriverKit extension and
host wrapper have not passed on this hardware. Complete the [model 1537 test](../testing/xbox/1537.md).

## Razer Wolverine V2

The source-backed GIP record for `1532:0A29` has a local-hardware patch for the captured interface-0 endpoints `0x81`/`0x01`. Input mapping, reconnect, LED, and rumble behavior remain unverified pending the [Wolverine V2 hardware test](../testing/razer/wolverine-v2.md).

## Nacon Revolution X Pro

The local `3285:0634` override selects GIP/xboxOne on interface 0 with the
captured interrupt endpoints `0x87`/`0x07`. The profile disables OJD's periodic
host-side GIP `0x03` transmission because the issue's working WebUSB trace
shows the device emitting `0x03` status frames and remaining stable without a
synthetic host packet. The parser also accepts split or stacked transfers,
base-128 payload lengths, and requested ACK frames using the Linux/xone layout.
Chunk headers are drained and acknowledged, but payload reassembly is not yet
implemented because no issue capture requires a multi-chunk input report.

Current Linux `xpad.c` supports the Nacon vendor and Xbox One fallback, but does
not name this exact PID. That supports classification only; it does not prove
the captured endpoint addresses or the OJD USBDriverKit session. Keep
`provenance.verified` false until the [Nacon hardware procedure](../testing/nacon-revolution-x.md)
passes input, continuous-read, reconnect, and no-host-keep-alive checks.

## Xbox Adaptive Joystick

No parser claim exists. Product descriptions do not provide a packet layout. Capture neutral, every button, stick axes, stick click, report IDs, and checksums with [the packet request](../testing/xbox-adaptive-joystick.md) before adding a record.

## Generic HID

Descriptor-driven fallback handles standard buttons, stick pairs, triggers, and an eight-way hat. Known protocol parsers still consume their raw reports. Vendor-defined layouts need a record and parser instead of more guesses in Generic HID.
