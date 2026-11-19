# Test an Xbox 360 Wireless Receiver

An Xbox 360 wireless receiver is a small USB box that lets up to four wireless Xbox 360 controllers talk to a computer. See [issue #9][1]. Linux's `xpad.c` lists three Microsoft receiver IDs, and OJD imported them as records that nobody has confirmed on hardware yet.

| ID | Name |
| --- | --- |
| 045e:0291 | Xbox 360 Wireless Receiver (XBOX) |
| 045e:02a9 | Unofficial receiver identity |
| 045e:0719 | Xbox 360 Wireless Receiver |

The receiver wraps every message in a four-byte envelope, like a letter in an envelope. The parser reads Linux's envelope and the presence, state, rumble, and ring-light commands inside it. A state report is 18 bytes inside the envelope, and its inner type byte is zero. Its inner length byte was 13 in the captures from [issue #9][1] (045e:0719) and [pull request #54](https://github.com/xsyetopz/OpenJoystickDriver/pull/54) (045e:02a9). Only a wired controller must say 14. Decoder tests replay those 29-byte packets. No hardware test has confirmed virtual output, rumble, or lights.

Only connected controllers are listed and get output. A presence message or a valid state report connects a slot, and a disconnect message removes it.

Checking the file needs no signing. These IDs aren't in Apple's production USB entitlement, so capture tries IOUSBHost directly. Try a development DEXT only if the ownership report shows direct access isn't available.

[1]: https://github.com/xsyetopz/OpenJoystickDriver/issues/9

## Direct USB Input Results (Pull Request #54)

2026-10-25, Intel iMac20,1, macOS 26.7.1, 045e:02a9 on interface 0 (endpoints 81/01), a patched `OpenJoystickDriverHIDTool --record-probe`, the bundled record. The capture isn't in the repository.

| Capture | Result |
| --- | --- |
| 25 s | 903 packets, 890 snapshots, zero parse errors |
| Sticks and triggers | Both sticks reached the full range, -32767...32767; both triggers 0...65535 |
| Buttons | Every D-pad direction, A, X, Guide, both shoulders |
| 15 s | 14 packets, 13 snapshots, zero parse errors; B, Y, Start, Back |
| Reconnecting | Done on purpose; messages were sent and reading started again |

The next capture covers the stick clicks. That build had no virtual-HID output, so empty-slot publishing, games, rumble, and lights need a run with a provisioned app.

## Direct USB Input Results (PR #54 Merge Commit)

A source probe built from `9bade60d2` in a separate Swift 6.3 compatibility copy, 045e:02a9.

| Capture | Result |
| --- | --- |
| 60 s | 3,371 packets, 3,363 snapshots, zero parse errors |
| Seen | Face buttons, shoulders, both stick clicks, every D-pad direction, the full range of both sticks and triggers |
| Second capture | Start, Back, Guide, disconnect and reconnect; stopped by hand, so no final summary |
| Input Test | The paired controller showed up and its controls responded in the separate, ad-hoc-signed app |

Next, on a provisioned build with the virtual HID entitlement: virtual output, games, rumble, lights, and virtual publishing of empty slots.

## Find and Check the Receiver Record

1. Find the PID in System Information or the OJD HID tool.
2. Pick its file under `Sources/OpenJoystickDriverKit/Resources/Controllers/`. For 045e:0719:

   ```bash
   just diagnose-record \
     Sources/OpenJoystickDriverKit/Resources/Controllers/045e/045e-0719.plist --validate-only
   ```

## Capture Connecting and Input

1. Quit Steam, games, and other controller tools.
2. Plug in the receiver, pair one controller, and run:

   ```bash
   just diagnose-record \
     Sources/OpenJoystickDriverKit/Resources/Controllers/045e/045e-0719.plist --seconds 45
   ```

3. Look for, and write down:
   - `USB_TX` with the "who's there?" message `08 00 0F C0 00…` at startup
   - `CONTROLLER_CONNECTION state=connected` after pairing
   - `USB_TX` with the Player 1 ring-light packet wrapped for the receiver
   - `USB_RX`, then correct `EVENT` lines for every control
   - `CONTROLLER_CONNECTION state=disconnected` after you turn the controller off
   - no buttons stuck down after a disconnect and reconnect

4. If the USB interface isn't available, keep the road OJD chose and the program that holds it. OJD never detaches the device or falls back to another kind of connection.
5. Add the output to issue #9 (read raw packets first) with your macOS version, Mac model, receiver VID/PID and branding, controller model, OJD commit, road, reconnect results, and any wrong or missing inputs.

## Capture Receiver Slots

A slot is one of the receiver's four seats for a controller. OJD runs one pipeline per slot. A slot is an interface with class triple FF/5D/81 and one interrupt IN and one OUT endpoint. OJD takes them in interface order, at most four, and each one sends the "who's there?" message at startup. A slot connects when it reports a controller or sends a valid state report, and the manager gives it a player light from a shared pool.

On 045e:02a9 and 045e:0719, slot 0 is interface 0, endpoints 81/01. [Pull request #54](https://github.com/xsyetopz/OpenJoystickDriver/pull/54) reports interfaces 0, 2, 4, 6 (input endpoints 81, 83, 85, 87) on 045e:02a9, but only interface 0 sent input. Step 1 below records the other 045e:0719 slot interfaces.

1. Plug in the receiver and write down the interface numbers:

   ```bash
   ioreg -p IOUSB -l -w0
   ioreg -r -c IOUSBHostInterface -l -w0
   ```

   Paste each receiver `IOUSBHostInterface` with `bInterfaceNumber`, `bInterfaceClass`, `bInterfaceSubClass`, `bInterfaceProtocol`, plus `kUSBCurrentConfiguration` before and after OJD starts.
2. List controllers (`ojd` is the [command-line tool](../../wiki/Command-Line.md)):

   ```bash
   ojd controller list --json
   ```

   Expect one entry with `protocol` `XboxXUSB:Receiver` for each paired controller, and none for an empty slot. `ojd controller show <ID> --json` gives each entry's `interfaceNumber` (`N`) for a FF/5D/81 interface. Paste it.
3. Pair one controller at a time. Write down which entry gets input and which quarter of the ring light turns on.
4. Pair controllers on slot 0 and on a later slot, then restart OJD with the receiver still plugged in. No slot should send SET_CONFIGURATION, because the device is already set up, and every paired slot should get input again. If only slot 0 reconnects during a run (after a transfer error, say), the later slots keep their input.
5. Turn off one controller. Only its slot should disconnect.

Then check both rumble motors and all four ring-light patterns. To count as hardware-verified, presence, input, reconnect, rumble, and light checks must all pass.
