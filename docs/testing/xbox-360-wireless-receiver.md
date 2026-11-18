# Test an Xbox 360 Wireless Receiver

[Issue #9][1]. Linux `xpad.c` lists three Microsoft receiver IDs, imported as unverified records.

| ID | Name |
| --- | --- |
| 045e:0291 | Xbox 360 Wireless Receiver (XBOX) |
| 045e:02a9 | Unofficial receiver identity |
| 045e:0719 | Xbox 360 Wireless Receiver |

The parser handles Linux's four-byte receiver envelope, presence, state, rumble, and ring-light commands. A state report is 18 bytes with envelope, inner type byte zero. Inner length byte: 13 in the captures of [issue #9][1] (045e:0719) and [pull request #54](https://github.com/xsyetopz/OpenJoystickDriver/pull/54) (045e:02a9); only a wired pad is held to 14. Decoder tests replay those 29-byte packets. No hardware verifies virtual output, rumble, LEDs.

Only connected controllers are listed and get output. A presence notification or valid state report connects a slot; a disconnect removes it.

Validation needs no signing. These pairs are outside the production Apple USB entitlement, so capture tries direct IOUSBHost; try a development DEXT only if ownership evidence shows direct access unavailable.

[1]: https://github.com/xsyetopz/OpenJoystickDriver/issues/9

## Direct USB Input Evidence (Pull Request #54)

2026-10-25, Intel iMac20,1, macOS 26.7.1, 045e:02a9 on interface 0 (endpoints 81/01), patched `OpenJoystickDriverHIDTool --record-probe`, bundled record. No capture in the repository.

| Capture | Result |
| --- | --- |
| 25 s | 903 packets, 890 snapshots, zero parse errors |
| Axes | Both sticks reached the canonical full range, -32767...32767; both triggers 0...65535 |
| Buttons | Every D-pad direction, A, X, Guide, both shoulders |
| 15 s | 14 packets, 13 snapshots, zero parse errors; B, Y, Start, Back |
| Reconnection | Deliberate; notifications sent, decoding resumed |

Not observed: stick clicks. Virtual-HID output unavailable: empty-slot publication, games, rumble, LEDs need a provisioned app test.

## Find and Validate the Receiver Record

1. Find the PID in System Information or the OJD HID tool.
2. Pick its file under `Sources/OpenJoystickDriverKit/Resources/Controllers/`. For 045e:0719:

   ```bash
   just diagnose-record \
     Sources/OpenJoystickDriverKit/Resources/Controllers/045e/045e-0719.plist --validate-only
   ```

## Capture Connection and Input

1. Quit Steam, games, other controller tools.
2. Connect the receiver, pair one controller, run:

   ```bash
   just diagnose-record \
     Sources/OpenJoystickDriverKit/Resources/Controllers/045e/045e-0719.plist --seconds 45
   ```

3. Record:
   - `USB_TX` presence inquiry `08 00 0F C0 00…` at startup.
   - `CONTROLLER_CONNECTION state=connected` after pairing.
   - `USB_TX` receiver-wrapped Player 1 ring-light packet.
   - `USB_RX`, then correct `EVENT` lines for every control.
   - `CONTROLLER_CONNECTION state=disconnected` after power-off.
   - No stale held buttons after disconnect and reconnect.

4. If the USB interface is unavailable, keep the route and registry owner; no detach or cross-transport fallback.
5. Attach the output (raw packets: inspect first) to issue #9 with macOS version, Mac model, receiver VID/PID and branding, controller model, OJD commit, route, reconnect results, wrong or missing inputs.

## Capture Receiver Slots

One pipeline per slot: an interface with class triple FF/5D/81 and one interrupt IN and OUT endpoint, in interface order, at most four, each sending the presence inquiry at startup. On 045e:02a9 and 045e:0719, slot 0 is interface 0, endpoints 81/01. [Pull request #54](https://github.com/xsyetopz/OpenJoystickDriver/pull/54) reports interfaces 0, 2, 4, 6 (input endpoints 81, 83, 85, 87) on 045e:02a9; only interface 0 delivered input.

1. Plug in the receiver; record interface numbers:

   ```bash
   ioreg -p IOUSB -l -w0
   ioreg -r -c IOUSBHostInterface -l -w0
   ```

   Paste each receiver `IOUSBHostInterface` with `bInterfaceNumber`, `bInterfaceClass`, `bInterfaceSubClass`, `bInterfaceProtocol`, plus `kUSBCurrentConfiguration` before and after OJD starts.
2. List controllers (`ojd` is the [command-line tool](../../wiki/Command-Line.md)):

   ```bash
   ojd controller list --json
   ```

   Expect one entry with `protocol` `XboxXUSB:Receiver` per paired controller, none for an empty slot. `ojd controller show <ID> --json` gives each entry's `interfaceNumber` (`N`) for a FF/5D/81 interface. Paste it.
3. Pair one controller at a time; record which entry gets input and which ring-light quadrant lights.
4. Pair controllers on slot 0 and a later slot; restart OJD, receiver plugged in. No slot sends SET_CONFIGURATION (device is configured); every paired slot resumes input. If slot 0 alone reconnects mid-run (say, a transfer error), later slots keep input.
5. Power off one controller: only its slot disconnects.

Then verify both rumble motors and all four ring-light patterns. Hardware-verified needs presence, input, reconnect, rumble, LED checks passing.
