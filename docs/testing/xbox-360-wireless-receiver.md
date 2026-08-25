# Test an Xbox 360 wireless receiver

This request covers [OpenJoystickDriver issue #9](https://github.com/xsyetopz/OpenJoystickDriver/issues/9). Linux `xpad.c` identifies three Microsoft receiver IDs that OJD now imports as unverified records:

- `045e:0291` — Xbox 360 Wireless Receiver (XBOX)
- `045e:02a9` — unofficial receiver identity
- `045e:0719` — Xbox 360 Wireless Receiver

The parser handles Linux's four-byte receiver envelope, controller presence transitions, wrapped 20-byte state reports, two-motor rumble, and ring-light commands. These paths are source-backed but not hardware-verified.

Record validation is signing-free. These receiver pairs are not in the current
production Apple USB entitlement, so physical capture tries direct IOUSBHost.
Use an exact development DEXT experiment only if live ownership evidence proves
direct access is unavailable.

## Find and validate the receiver record

Use System Information or the OJD HID tool to identify the receiver PID, then select the matching JSON file under `Sources/OpenJoystickDriverKit/Resources/Controllers/`.

For the common `045e:0719` receiver:

```bash
./scripts/ojd diagnose record   Sources/OpenJoystickDriverKit/Resources/Controllers/045e/045e-0719.json   --validate-only
```

## Capture connection and input

Quit Steam, games, and other controller tools. Connect the receiver, pair one controller, then run:

```bash
./scripts/ojd diagnose record   Sources/OpenJoystickDriverKit/Resources/Controllers/045e/045e-0719.json   --seconds 45
```

The useful evidence is:

- `CONTROLLER_CONNECTION state=connected` after pairing.
- `USB_TX` with the receiver-wrapped Player 1 ring-light packet.
- `USB_RX` followed by correct `EVENT` lines for every control.
- `CONTROLLER_CONNECTION state=disconnected` after powering off the controller.
- No stale held buttons after disconnect and reconnect.

If the USB interface is unavailable, preserve the selected route and registry
owner. There is no detach or cross-transport fallback.

Attach the complete command output to issue #9 with macOS version, Mac model,
receiver VID/PID and branding, controller model, exact OJD commit, selected route,
reconnect results, and any missing or incorrect inputs. Raw packet output is
included; inspect it before publishing.

After input passes, use the app or application service-backed `physical-output plan` workflow to verify both rumble motors and all four ring-light player patterns. Do not mark these records hardware-verified until receiver presence, input, reconnect, rumble, and LEDs pass on physical hardware.
