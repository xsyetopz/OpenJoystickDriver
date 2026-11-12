# Test an Xbox 360 Wireless Receiver

This request covers [OpenJoystickDriver issue #9][1]. Linux `xpad.c` identifies three Microsoft receiver IDs that OJD imports as unverified records:

- `045e:0291` — Xbox 360 Wireless Receiver (XBOX)
- `045e:02a9` — unofficial receiver identity
- `045e:0719` — Xbox 360 Wireless Receiver

The parser handles Linux's four-byte receiver envelope, controller presence transitions, state reports, two-motor rumble, and ring-light commands. A receiver state report needs 18 bytes including the envelope, and its inner type byte is zero. Its inner length byte is `13` in the captures of [issue #9][1] (`045e:0719`) and [pull request #54](https://github.com/xsyetopz/OpenJoystickDriver/pull/54) (`045e:02a9`), so only a wired pad is held to `14`. The decoder tests replay those captured 29-byte packets. Decoding is verified against the captures; virtual output, rumble, and LEDs through OJD are not hardware-verified.

Only connected controllers appear in controller lists and qualify for virtual output. OJD keeps all four receiver slots open to detect pairing. A presence notification or a valid state report connects a slot, so a missed notification does not hide a controller; a disconnect notification removes it.

Record validation is signing-free. These receiver pairs are not in the current production Apple USB entitlement, so physical capture tries direct IOUSBHost. Use an exact development DEXT experiment only if live ownership evidence proves direct access is unavailable.

[1]: https://github.com/xsyetopz/OpenJoystickDriver/issues/9

## Direct USB Input Evidence Reported in Pull Request #54

On 2026-10-25, the pull request's author ran an Intel iMac20,1 on macOS 26.7.1 against `045e:02a9` on interface 0, endpoints `81`/`01`, with a patched `OpenJoystickDriverHIDTool --record-probe` and the bundled receiver record. This repository holds none of that capture; the figures are the author's report.

- A 25-second capture received 903 packets and decoded 890 controller snapshots with zero parse errors.
- Both axes of both sticks reached the canonical full range, `-32767...32767`; both triggers reached `0...65535`.
- Every D-pad direction, A, X, Guide and both shoulders registered. A second 15-second capture decoded 13 snapshots from 14 packets with zero parse errors and registered B, Y, Start and Back.
- The receiver sent disconnect and reconnect notifications during a deliberate reconnection, and decoding resumed.

Stick clicks were not observed. Virtual-HID output was unavailable in that build, so empty-slot publication, games, rumble and LEDs still need a provisioned app test.

## Find and Validate the Receiver Record

Use System Information or the OJD HID tool to identify the receiver PID, then select the matching JSON file under `Sources/OpenJoystickDriverKit/Resources/Controllers/`.

For the common `045e:0719` receiver:

```bash
just diagnose-record \
  Sources/OpenJoystickDriverKit/Resources/Controllers/045e/045e-0719.plist --validate-only
```

## Capture Connection and Input

Quit Steam, games, and other controller tools. Connect the receiver, pair one controller, then run:

```bash
just diagnose-record \
  Sources/OpenJoystickDriverKit/Resources/Controllers/045e/045e-0719.plist --seconds 45
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

OJD runs one pipeline per receiver slot: each interface with triple FF/5D/81 and one interrupt IN and OUT endpoint, in interface order, at most four. Slot n (from 0) sends the presence inquiry at startup, connects when the slot reports a controller present or sends a valid state report, then lights player n+1. The observed `045e:02a9` and `045e:0719` slot 0 is interface 0 with endpoints `81`/`01`; [pull request #54](https://github.com/xsyetopz/OpenJoystickDriver/pull/54) reports interfaces 0, 2, 4 and 6 with input endpoints `81`, `83`, `85` and `87` on `045e:02a9`, where only interface 0 delivered input.

1. Record the configuration descriptor and interface numbers with the receiver plugged in:

   ```bash
   ioreg -p IOUSB -l -w0
   ioreg -r -c IOUSBHostInterface -l -w0
   ```

   Paste every `IOUSBHostInterface` under the receiver with its `bInterfaceNumber`, `bInterfaceClass`, `bInterfaceSubClass` and `bInterfaceProtocol`, plus `kUSBCurrentConfiguration` on the device before and after OJD starts.
2. Start OJD and list controllers (`ojd` is the [command-line tool](../../wiki/Command-Line.md)):

   ```bash
   ojd controller list --json
   ```

   Expect one entry with `protocol` `XboxXUSB:Receiver` per paired controller, none for an empty slot. `ojd controller show <ID> --json` gives each entry's `interfaceNumber` (`N`) for a FF/5D/81 interface. Paste the output.
3. Pair one controller at a time. For each, record which interface's entry receives input and which ring-light quadrant lights. Slot order is interface order: the lowest interface is player 1.
4. With controllers paired on slot 0 and a later slot, restart OJD without unplugging the receiver. The device is already configured, so no slot, including slot 0, should send SET_CONFIGURATION. Confirm every paired slot resumes input. If slot 0 alone reconnects during a run (for example after a transfer error), confirm the later slots keep their input.
5. Power off one controller. Confirm only its slot reports disconnected.

After input passes, use the app or the output checks from `ojd controller show` to verify both rumble motors and all four ring-light player patterns. Mark records hardware-verified only after physical receiver presence, input, reconnect, rumble, and LED checks pass.
