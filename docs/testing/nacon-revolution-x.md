# Test the Nacon Revolution X Pro

USB device 12933:1588 (3285:0634 hexadecimal), for [issue #21](https://github.com/xsyetopz/OpenJoystickDriver/issues/21).

The unverified record selects `XboxGIP` on interface 0, interrupt IN `0x87`, OUT `0x07`. It disables the periodic host `0x03` packet, reported to destabilize native sessions. The issue's WebUSB result is not an OJD USBDriverKit result.

## Validate the Bundled Record

From the repository root:

```bash
just diagnose-record \
  Sources/OpenJoystickDriverKit/Resources/Controllers/3285/3285-0634.plist \
  --validate-only
```

Expected:

```text
RECORD_VALIDATION result=valid
```

## Run the Raw USB Probe

The production Apple USB entitlement omits this VID/PID, so the facade tries IOUSBHost.

1. Quit games, Steam, and controller tools. Connect by USB.
2. Run:

   ```bash
   just diagnose-record \
     Sources/OpenJoystickDriverKit/Resources/Controllers/3285/3285-0634.plist \
     --seconds 45
   ```

3. Check `RECORD_HANDSHAKE` succeeds, `USB_RX` stays active, no `USB_KEEPALIVE` prints.
4. Press every button, D-pad direction, trigger, stick axis and click, and Guide.
5. Idle past the four-second keep-alive cadence. It must stay available without a host `0x03`.
6. Reconnect. Repeat the handshake and one control check.

Interface unavailable: record the route and registry owner. Add no detach fallback or broader production DEXT; use a development DEXT only if ownership evidence requires it.

Parser fixtures cover split, stacked, extended-length, and requested ACK frames. Physical runs must show a stable native USB session and controls reaching the virtual gamepad.

## Check Physical Output With an Installed App

Check LED and rumble in an installed app, planning per [physical output](physical-output.md) (`ojd` is the [command-line tool](../../wiki/Command-Line.md)):

```bash
ojd controller list
ojd controller show 3285:0634
```

Attach results to #21 with macOS version, Mac model, firmware (if known), OJD commit, USB route, ownership results, any transfer error.

Claim support after input, reconnect, and output pass on hardware.
