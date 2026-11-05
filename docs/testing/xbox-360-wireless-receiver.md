# Test an Xbox 360 Wireless Receiver

This request covers [OpenJoystickDriver issue #9][1]. Linux `xpad.c` identifies three Microsoft receiver IDs that OJD imports as unverified records:

- `045e:0291` — Xbox 360 Wireless Receiver (XBOX)
- `045e:02a9` — unofficial receiver identity
- `045e:0719` — Xbox 360 Wireless Receiver

The parser handles the four-byte receiver envelope, controller presence transitions, state reports, two-motor rumble, and ring-light commands. Wireless input needs at least 18 bytes including the envelope; the inner report type is zero and its length byte is not checked against the wired report's `14`. A `045e:02a9` capture contains 29-byte packets with inner header `00 13` and changing stick values. The decoder has a regression test for that capture. Direct USB input through the patched driver is hardware-tested below; virtual output through the patched app, rumble, and LEDs are not hardware-verified.

Only connected controllers appear in controller lists and qualify for virtual output. OJD keeps up to four internal receiver slots open to detect pairing. A presence notification or valid input connects a slot; a disconnect notification removes that controller and neutralizes its output. Valid input establishes presence even when the startup inquiry reply is missed.

Record validation is signing-free. These receiver pairs are not in the current production Apple USB entitlement, so physical capture tries direct IOUSBHost. Use an exact development DEXT experiment only if live ownership evidence proves direct access is unavailable.

[1]: https://github.com/xsyetopz/OpenJoystickDriver/issues/9

## Direct USB Input Evidence

On 2026-10-25, an Intel iMac20,1 running macOS 26.7.1 tested `045e:02a9` on interface 0, endpoints `81`/`01`, using the patched `OpenJoystickDriverHIDTool --record-probe` and the bundled receiver record. The source is an uncommitted patch on `3552be925d7dacef3fd895ac0c6cbf39e9d3cd70`, built in an isolated Swift 6.3 compatibility copy. The installed app was not running or replaced.

- A 25-second capture received 903 packets and decoded 890 controller snapshots with zero parse errors.
- Both axes of both sticks reached the canonical full range, `-32767...32767`; both triggers reached `0...65535`.
- Every D-pad direction, A, X, Guide and both shoulders registered. A second 15-second capture decoded 13 snapshots from 14 packets with zero parse errors and registered B, Y, Start and Back.
- The receiver sent disconnect and reconnect notifications during a user-confirmed deliberate reconnection, and decoding resumed.

Stick clicks were not observed in the direct USB captures. After launching the isolated patched app, the user tested the controller and confirmed that all input worked. The app log showed the paired controller connected on interface 0 with all four receiver input loops running.

Virtual-HID output was unavailable because the test build lacked `com.apple.developer.hid.virtual.device`. Empty-slot publication, games, rumble and LEDs still need a provisioned app test.

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

OJD runs one pipeline per receiver slot: each interface with triple FF/5D/81 and one interrupt IN and OUT endpoint, in interface order, at most four. Each slot sends the presence inquiry at startup. A presence notification or valid input connects its controller and lights its assigned player indicator. The observed `045e:02a9` interfaces are 0, 2, 4, and 6, with input endpoints 81, 83, 85, and 87. During capture, only interface 0 delivered controller input.

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

   Expect one entry with `protocol` `XboxXUSB:Receiver` per paired controller, not per empty slot. With one paired controller, expect one entry; with none, expect no entries. `ojd controller show <ID> --json` gives each entry's `interfaceNumber` (`N`) for a FF/5D/81 interface. Paste the output.
3. Pair one controller at a time. For each, record which interface's entry receives input and which ring-light quadrant lights. Slot order is interface order: the lowest interface is player 1.
4. With controllers paired on slot 0 and a later slot, restart OJD without unplugging the receiver. The device is already configured, so no slot, including slot 0, should send SET_CONFIGURATION. Confirm every paired slot resumes input. If slot 0 alone reconnects during a run (for example after a transfer error), confirm the later slots keep their input.
5. Power off one controller. Confirm only its slot reports disconnected.

After input passes, use the app or the output checks from `ojd controller show` to verify both rumble motors and all four ring-light player patterns. Mark records hardware-verified only after physical receiver presence, input, reconnect, rumble, and LED checks pass.
