# Test an Xbox 360 Wireless Receiver

This request covers [OpenJoystickDriver issue #9][1]. Linux `xpad.c` identifies three Microsoft receiver IDs that OJD now imports as unverified records:

- `045e:0291` — Xbox 360 Wireless Receiver (XBOX)
- `045e:02a9` — unofficial receiver identity
- `045e:0719` — Xbox 360 Wireless Receiver

The parser handles Linux's four-byte receiver envelope, controller presence transitions, wrapped 20-byte state reports, two-motor rumble, and ring-light commands. These paths are source-backed but not hardware-verified.

Record validation is signing-free. These receiver pairs are not in the current production Apple USB entitlement, so physical capture tries direct IOUSBHost. Use an exact development DEXT experiment only if live ownership evidence proves direct access is unavailable.

[1]: https://github.com/xsyetopz/OpenJoystickDriver/issues/9

## Find and Validate the Receiver Record

Use System Information or the OJD HID tool to identify the receiver PID, then select the matching JSON file under `Sources/OpenJoystickDriverKit/Resources/Controllers/`.

For the common `045e:0719` receiver:

```bash
./Scripts/ojd diagnose record \
  Sources/OpenJoystickDriverKit/Resources/Controllers/045e/045e-0719.json --validate-only
```

## Capture Connection and Input

Quit Steam, games, and other controller tools. Connect the receiver, pair one controller, then run:

```bash
./Scripts/ojd diagnose record \
  Sources/OpenJoystickDriverKit/Resources/Controllers/045e/045e-0719.json --seconds 45
```

Record:

- `USB_TX` with the presence inquiry `08 00 0F C0 00…` at startup.
- `CONTROLLER_CONNECTION state=connected` after pairing.
- `USB_TX` with the receiver-wrapped Player 1 ring-light packet.
- `USB_RX` followed by correct `EVENT` lines for every control.
- `CONTROLLER_CONNECTION state=disconnected` after powering off the controller.
- No stale held buttons after disconnect and reconnect.

If the USB interface is unavailable, preserve the selected route and registry owner. There is no detach or cross-transport fallback.

Attach the complete command output to issue #9 with macOS version, Mac model, receiver VID/PID and branding, controller model, exact OJD commit, selected route, reconnect results, and any missing or incorrect inputs. Raw packet output is included; inspect it before publishing.

## Capture Receiver Slots

OJD runs one pipeline per receiver slot: each interface with triple FF/5D/81 and one interrupt IN and OUT endpoint, in interface order, at most four. Slot n (from 0) sends the presence inquiry at startup, ignores pad data until the slot reports a controller present, then lights player n+1. None of this has been verified on a real receiver yet; real slot interface numbers are unknown.

1. Record the configuration descriptor and interface numbers with the receiver plugged in:

   ```bash
   ioreg -p IOUSB -l -w0
   ioreg -r -c IOUSBHostInterface -l -w0
   ```

   Paste every `IOUSBHostInterface` under the receiver with its `bInterfaceNumber`, `bInterfaceClass`, `bInterfaceSubClass` and `bInterfaceProtocol`, plus `kUSBCurrentConfiguration` on the device before and after OJD starts.
1. Start OJD and list controllers (`ojd` is the [command-line tool](../../wiki/Command-Line.md)):

   ```bash
   ojd controller list --json
   ```

   Expect four entries with `protocol` `xbox.xusb:receiver`, one per slot. `ojd controller show <ID> --json` gives each entry's `interfaceNumber` (`N`) for a FF/5D/81 interface. Paste the output.
1. Pair one controller at a time. For each, record which interface's entry receives input and which ring-light quadrant lights. Slot order is interface order: the lowest interface is player 1.
1. With controllers paired on slot 0 and a later slot, restart OJD without unplugging the receiver. The device is already configured, so no slot, including slot 0, should send SET_CONFIGURATION. Confirm every paired slot resumes input. If slot 0 alone reconnects during a run (for example after a transfer error), confirm the later slots keep their input.
1. Power off one controller. Confirm only its slot reports disconnected.

After input passes, use the app or the output checks from `ojd controller show` to verify both rumble motors and all four ring-light player patterns. Mark records hardware-verified only after physical receiver presence, input, reconnect, rumble, and LED checks pass.
