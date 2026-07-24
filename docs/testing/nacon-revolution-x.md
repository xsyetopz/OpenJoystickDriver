# Test Nacon Revolution X Pro

This procedure covers [OpenJoystickDriver issue #21](https://github.com/xsyetopz/OpenJoystickDriver/issues/21) for USB device `12933:1588` (`3285:0634` in hexadecimal).

The bundled record selects GIP/xboxOne on interface 0 with interrupt IN `0x87`
and OUT `0x07`. It disables the periodic host-side `0x03` packet reported to
destabilize native sessions. The record remains unverified: the issue's
WebUSB result is independent evidence, not an OJD SwiftUSB acceptance result.

## Validate the bundled record

From the repository root:

```bash
./scripts/ojd diagnose record \
  Sources/OpenJoystickDriverKit/Resources/Controllers/3285/3285-0634.json \
  --validate-only
```

Expected result:

```text
RECORD_VALIDATION result=valid
```

## Run the signing-free USB probe

Quit games, Steam, and other controller utilities. Connect the controller
directly by USB, then run:

```bash
./scripts/ojd diagnose record \
  Sources/OpenJoystickDriverKit/Resources/Controllers/3285/3285-0634.json \
  --seconds 45
```

Confirm `RECORD_HANDSHAKE` succeeds, `USB_RX` remains active, and the probe
reports `USB_KEEPALIVE result=disabled` without sending a transfer for this
record. Exercise every button,
D-pad direction, trigger, stick axis, stick click, and Guide control. Leave the
controller idle long enough to cover the normal four-second keep-alive cadence;
it must remain available without a host `0x03` packet. Unplug and reconnect,
then repeat the handshake and a representative control check.

If the interface is busy, repeat once with `--detach`, then unplug and reconnect
the controller afterward:

```bash
./scripts/ojd diagnose record \
  Sources/OpenJoystickDriverKit/Resources/Controllers/3285/3285-0634.json \
  --seconds 45 --detach
```

The parser test fixtures cover split, stacked, extended-length, and requested
ACK frames. A physical run must still establish that the native USB session is
stable and that the controls reach the installed virtual-gamepad output path.

## Check physical output with an installed app

LED and rumble checks require a separately installed current OpenJoystickDriver
app. Use the [physical-output procedure](physical-output.md) to generate a
device-specific plan:

```bash
OpenJoystickDriver --headless controller output list
OpenJoystickDriver --headless controller output plan 12933 1588
```

Attach the probe and output results to issue #21 with macOS version, Mac model,
controller firmware if known, exact OJD commit, whether `--detach` was needed,
and any `LIBUSB_ERROR_*` result. Keep `verified: false` until input, reconnect,
and any claimed output behavior pass on physical hardware.
