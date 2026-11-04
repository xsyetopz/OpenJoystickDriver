# Test Turtle Beach Rematch Advanced Wired Controller (Xbox)

This procedure covers USB device `4341:28958` (`10F5:711E` in hexadecimal), sold as
the PDP / Turtle Beach "Xbox Rematch Advanced Wired Controller". The USB vendor
string is `Voyetra Turtle Beach,Inc.`; the product string carries the colorway
(for example `Kyoto Bloom Reveal`).

Linux `xpad` accepts this vendor through `XPAD_XBOXONE_VENDOR(0x10f5)` but has
no explicit row for `0x711e`, so the pinned importer does not emit a record. The
authored `Controller` record adds the record with the GIP Xbox One parser, the
hardware-reported interrupt endpoints `0x81`/`0x02`, and USB configuration 1
before interface claim. The controller enumerates unconfigured with
`bDeviceClass 0xFF`, two vendor interfaces (`0xFF/0x47/0xD0`), and no kernel
driver, so `SetConfiguration1BeforeClaim` is required for the interface service to appear.

The controller sends the extended 36-byte GIP input report (payload length
`0x20`). The parser decodes it without errors.

## Descriptor Evidence

```text
config 1: bNumInterfaces=2 bmAttributes=0xa0 MaxPower=500mA
  IF 0 alt 0 class=0xff sub=0x47 proto=0xd0
    EP 0x81 IN  interrupt maxpkt=64 interval=4
    EP 0x02 OUT interrupt maxpkt=64 interval=4
  IF 1 alt 0 class=0xff sub=0x47 proto=0xd0 (no endpoints)
  IF 1 alt 1 class=0xff sub=0x47 proto=0xd0
    EP 0x03 OUT iso maxpkt=224 interval=1
    EP 0x83 IN  iso maxpkt=128 interval=1
```

## Validate The Bundled Record

From the repository root:

```bash
./Scripts/ojd diagnose record \
  Sources/OpenJoystickDriverKit/Resources/Controllers/10f5/10f5-711e.json \
  --validate-only
```

Expected result:

```text
RECORD_VALIDATION result=valid
```

## Run The IOUSBHost Probe

This model is not covered by the restricted USBDriverKit entitlement, so the
direct IOUSBHost route is the production route. Quit Steam, games, and every
browser first: Chromium-based browsers open GIP controllers exclusively for
their Gamepad API and the probe then reports zero matches or an open failure.
Connect the controller directly by USB, then run:

```bash
./Scripts/ojd diagnose record \
  Sources/OpenJoystickDriverKit/Resources/Controllers/10f5/10f5-711e.json \
  --seconds 30
```

Expected sequence:

```text
USB_CONFIGURATION value=1 result=set
USB_OPEN interface=0 route=ioUSBHost result=opened
USB_TX endpoint=0x2 bytes=05 20 01 01 00
USB_TX endpoint=0x2 bytes=0a 20 01 03 00 01 14
USB_TX endpoint=0x2 bytes=06 20 01 02 01 00
RECORD_HANDSHAKE driver=XboxGIP:USB result=complete
```

The last line reports that the startup writes completed. It does not confirm a
device-acknowledged GIP handshake.

Test neutral plus press/release for every face button, D-pad direction, trigger,
stick axis, and stick click. `RECORD_SUMMARY` must report `parse_errors=0`.

## Hardware Result (2026-09-18)

- macOS 26.6.2 (25G83), MacBook Pro (Apple silicon), source-built probe at
  commit `d431993` plus this record.
- `USB_MATCHES count=1`, configuration set, interface 0 opened over IOUSBHost,
  three startup packets accepted, handshake complete, keep-alive sent.
- 20-second capture: `RECORD_SUMMARY packets=1275 events=1650 parse_errors=0`.
- Verified controls: A, B, X, Y press/release, D-pad, left and right stick full
  travel, left and right trigger. Status packets `03 20 xx 04 80 00 00 00` and
  the `07 20 ...` frames arrive alongside the 36-byte `20 00 xx 20 ...` input
  reports.
- One earlier run failed with a transient `kIOReturnIOError` on the first read
  after the handshake, directly after a browser released the device. A retry
  succeeded; unplug and replug the controller if the first probe after closing
  a browser fails.
- Not verified: rumble, player indicator, Share/paddle buttons, and reconnect
  behavior of an installed signed app. This model does not use the DEXT route.
