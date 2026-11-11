# Test an Xbox 360 Wireless Receiver

This request covers [OpenJoystickDriver issue #9][1]. Linux `xpad.c` identifies three Microsoft receiver IDs that OJD imports as unverified records:

- `045e:0291` — Xbox 360 Wireless Receiver (XBOX)
- `045e:02a9` — unofficial receiver identity
- `045e:0719` — Xbox 360 Wireless Receiver

The parser handles Linux's four-byte receiver envelope, controller presence transitions, state reports, two-motor rumble, and ring-light commands. A receiver state report needs 18 bytes including the envelope, and its inner type byte is zero. Its inner length byte is `13` in the captures of [issue #9][1] (`045e:0719`) and [pull request #54](https://github.com/xsyetopz/OpenJoystickDriver/pull/54) (`045e:02a9`), so only a wired pad is held to `14`. The decoder tests replay those captured 29-byte packets. Decoding is verified against the captures; virtual output, rumble, and LEDs through OJD are not hardware-verified.

Only connected controllers appear in controller lists and qualify for virtual output. OJD keeps all four receiver slots open to detect pairing. A presence notification or a valid state report connects a slot, so a missed notification does not hide a controller; a disconnect notification removes it.

Record validation is signing-free. These receiver pairs are not in the current production Apple USB entitlement, so physical capture tries direct IOUSBHost. Use an exact development DEXT experiment only if live ownership evidence proves direct access is unavailable.

[1]: https://github.com/xsyetopz/OpenJoystickDriver/issues/9

## Direct USB Input Evidence

On an Intel Mac with receiver `045e:02a9`, a source probe built from PR #54's merge commit `9bade60d2` in an isolated Swift 6.3 compatibility copy received 3,371 packets and decoded 3,363 snapshots with zero parse errors in 60 seconds. Face buttons, shoulders, both stick clicks, all D-pad directions, and the full ranges of both sticks and triggers were observed. A subsequent capture observed Start, Back, Guide and disconnect/reconnect; it required manual termination and has no final summary.

The user also reported that the paired controller appeared and controls responded in the isolated patched app's Input Test. The ad-hoc-signed build lacked the virtual HID entitlement; virtual output, games, rumble, LEDs and empty-slot virtual publication were not verified. The installed app was not replaced.

## Find and Validate the Receiver Record

Use System Information or the OJD HID tool to identify the receiver PID, then select the matching JSON file under `Sources/OpenJoystickDriverKit/Resources/Controllers/`.

For the common `045e:0719` receiver:

```bash
./Scripts/ojd diagnose record \
  Sources/OpenJoystickDriverKit/Resources/Controllers/045e/045e-0719.plist --validate-only
```

## Capture Connection and Input

Quit Steam, games, and other controller tools. Connect the receiver, pair one controller, then run:

```bash
./Scripts/ojd diagnose record \
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

OJD runs one pipeline per receiver slot: each interface with triple FF/5D/81 and one interrupt IN and OUT endpoint, in interface order, at most four. Each slot sends the presence inquiry at startup and connects when it reports a controller present or sends a valid state report. The manager assigns a player indicator from its pool. The observed `045e:02a9` interfaces are 0, 2, 4 and 6, with input endpoints `81`, `83`, `85` and `87`; only interface 0 delivered controller input. The observed `045e:0719` slot 0 is interface 0 with endpoints `81`/`01`; the interface numbers of its other slots are not captured.

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
3. Pair one controller at a time. For each, record which interface's entry receives input and which ring-light quadrant lights.
4. With controllers paired on slot 0 and a later slot, restart OJD without unplugging the receiver. The device is already configured, so no slot, including slot 0, should send SET_CONFIGURATION. Confirm every paired slot resumes input. If slot 0 alone reconnects during a run (for example after a transfer error), confirm the later slots keep their input.
5. Power off one controller. Confirm only its slot reports disconnected.

After input passes, use the app or the output checks from `ojd controller show` to verify both rumble motors and all four ring-light player patterns. Mark records hardware-verified only after physical receiver presence, input, reconnect, rumble, and LED checks pass.
