# 8BitDo Ultimate 2C Wireless

The Ultimate 2C Wireless enumerates as a different identity in each mode. Test and report each mode separately.

Capture paths in this page are relative to `openspec/changes/0-6-0-alpha-3/evidence/`.

| Mode | VID:PID | Route | Status |
| --- | --- | --- | --- |
| 2.4 GHz receiver, XInput | `2DC8:310A` | `XboxXUSB` | Captured: every control reports (`2c-receiver-310a/ordered-controls-100s.txt`); rumble packets sent, felt result not in the capture; unassigned rear buttons send no bit (`2c-receiver-310a/rear-unassigned-with-a-b-45s.txt`) |
| Cable, XInput or DInput | `2DC8:310A` | `XboxXUSB` | Captured: the cable enumerates as `310A` after X + Home and after B + Home (`2c-cable/mode-attempts.txt`); same report as the receiver's `310A`; unassigned rear buttons send no bit (`2c-cable/310a-rear-unassigned-45s.txt`) |
| Bluetooth LE | `2DC8:301B` | `HIDDescriptor` | Captured: every control raw and decoded (`2c-bluetooth-301b/ordered-controls-120s.txt`, `2c-bluetooth-301b/ojd-watch-120s.txt`); battery byte reads 0 at 100% and at 90%; rumble write fails |
| Unknown | `2DC8:301D` | `HIDDescriptor` | Unverified: no mode of the pad enumerated as this identity (`2c-cable/mode-attempts.txt`) |
| Unknown | `2DC8:3109` | `XboxXUSB` | Unverified: no mode of the pad enumerated as this identity (`2c-cable/mode-attempts.txt`); the maintainer owns no 8BitDo adapter other than the pad's receiver |
| 2.4 GHz receiver, DInput | `2DC8:301C` | `HIDDescriptor` | Captured: every control reports (`2c-receiver-301c/ordered-controls-150s.txt`); the mode `unlinked` matches the product string `IDLE`, is `idle: NoControllerLinked` and reports `NoControllerLinked`; the default mode serves the linked pad with the HID descriptor and has no input map until the capture is mapped to usages; unassigned L4 sets byte 1 bit 2 and unassigned R4 sets bit 5 (`2c-receiver-301c/rear-unassigned-60s.txt`) |

## Results

Each Results table is read from the capture named in its heading. The press order of the three `ordered-controls` captures is the same: A, B, X, Y, LB, RB, left trigger, right trigger, Back, Start, Guide, left stick click, right stick click, D-pad up, down, left, right, left stick, right stick. Control names in the 310A and 301C tables follow that order; the captures hold no OJD decode for those two identities, so the "OJD decode" column is "not in capture" there.

### Receiver as `2DC8:310A`

Source: `2c-receiver-310a/ordered-controls-100s.txt`. One report is 20 bytes: `00 14`, buttons (bytes 2 and 3), left trigger (byte 4), right trigger (byte 5), four signed 16-bit stick values (bytes 6 to 13), then `10 1C 30 64 00 10`. Those last six bytes are the same in every report of every 310A capture.

| Control | Raw (bytes that change) | OJD decode |
| --- | --- | --- |
| A, B, X, Y | byte 3 = `10`, `20`, `40`, `80` | not in capture |
| LB, RB | byte 3 = `01`, `02` | not in capture |
| Left, right trigger | byte 4, byte 5: 0 to 255 | not in capture |
| Back, Start | byte 2 = `20`, `10` | not in capture |
| Guide | byte 3 = `04` | not in capture |
| Left, right stick click | byte 2 = `40`, `80` | not in capture |
| D-pad up, down, left, right | byte 2 = `01`, `02`, `04`, `08` | not in capture |
| Left stick X, Y | bytes 6 to 9: -32768 to 32767 | not in capture |
| Right stick X, Y | bytes 10 to 13: -32768 to 32767 | not in capture |

At rest (`2c-receiver-310a/idle-12s.txt`) buttons, triggers and sticks read 0 in the first 200 reports; three later reports carry small stick values, and 100 more read 0.

The rear buttons: `2c-receiver-310a/rear-square-star-45s.txt` holds seven presses. They report byte 2 = `20`, byte 3 = `10`, byte 2 = `10`, byte 2 = `10`, byte 3 = `10`, byte 3 = `10`, byte 3 = `10`: only bits that other controls own, and no report holds a separate rear bit. The tail of `ordered-controls-100s.txt` shows the same: bytes 2 = `20`, `10` and byte 3 = `10` only. With both assignments cleared (the pad's mapping light stays dark on a press), `2c-receiver-310a/rear-unassigned-with-a-b-45s.txt` holds A, L4, L4, B, R4, R4, A: the reports change only to byte 3 = `10`, `20`, `10`, so A and B report and the rear buttons send nothing. `rear-unassigned-60s.txt` holds five presses each of L4 and R4, as the maintainer reports them, and also changes only to byte 3 = `10` and `20`. An unassigned rear button sends no bit as `310A`.

### Cable

Source: `2c-cable/mode-attempts.txt`. By cable the pad enumerates as `2DC8:310A` after X + Home, after B + Home, and after it was moved from the receiver in DInput mode. The report has the `310A` layout; its last six bytes read `1A 1B 30 6D 00 00` or `11 1B 30 6D 00 00` instead of the receiver's constant `10 1C 30 64 00 10`. In `2c-cable/310a-rear-unassigned-45s.txt` the first reports carry byte 3 = `40`, X held from X + Home; then A (`10`) and B (`20`) report, and the unassigned rear buttons send nothing.

Rumble: `2c-receiver-310a/rumble-6s.txt` shows two writes, `00 08 00 00 C8 00 00 00` and 1.5 s later `00 08 00 00 00 00 00 00`. The capture does not record whether a motor ran. Two testers reported rumble working on `0.5.0-beta.4` tester build `1.5.71`; no capture file backs that report.

### Receiver as `2DC8:301C`

Source: `2c-receiver-301c/ordered-controls-150s.txt`, pad in DInput mode. One report is 10 bytes: `01`, buttons (bytes 1 and 2), hat (byte 3), four unsigned 8-bit stick values (bytes 4 to 7), then two trigger bytes (8 and 9). At rest the report is `01 00 00 0F 7F 7F 7F 7F 00 00`.

| Control | Raw (bytes that change) | OJD decode |
| --- | --- | --- |
| A, B, X, Y | byte 1 = `01`, `02`, `08`, `10` | not in capture |
| LB, RB | byte 1 = `40`, `80` | not in capture |
| Left, right trigger | byte 9 rises 0 to `FF` with byte 2 = `01`; byte 8 rises 0 to `FF` with byte 2 = `02` | not in capture |
| Back, Start, Guide | byte 2 = `04`, `08`, `10` | not in capture |
| Left, right stick click | byte 2 = `20`, `40` | not in capture |
| D-pad | byte 3 = `0`, `4`, `6`, `2` in press order up, down, left, right; `F` at rest | not in capture |
| Left stick X, Y | bytes 4 and 5: 0 to 255, rest `7F` | not in capture |
| Right stick X, Y | bytes 6 and 7: 0 to 255, rest `7F` | not in capture |

Rear buttons:

- `2c-receiver-301c/rear-r4-cleared-45s.txt`: with the R4 assignment cleared, R4 reports byte 1 = `20` (bit 5), twice at 11.07 s and 11.32 s; the other presses report byte 2 = `04` and byte 1 = `01`.
- `2c-receiver-301c/rear-unassigned-60s.txt`: with both assignments cleared, L4 reports byte 1 = `04` (bit 2) in 164 reports and R4 reports byte 1 = `20` (bit 5) in 142 reports, five presses each.
- `2c-receiver-301c/rear-l4-assigned-60s.txt`: with L4 assigned, no report sets byte 1 bit 2 (`04`) or bit 5 (`20`); the presses report byte 2 = `04` and byte 1 = `01`.
- `2c-receiver-301c/ordered-controls-150s.txt`: the presses after the sticks (28 s to 39 s) report byte 2 = `04`, byte 1 = `01` and byte 2 = `08` only; no report sets byte 1 bit 2 or bit 5.

Rumble: `2c-receiver-301c/rumble-writes.txt` lists eight `IOHIDDeviceSetReport` writes (report 1 with `C8`, `64` and `FF` payloads, each followed by zeros, and report 5 `64 64 00 00` then zeros). All return `result=0`, and the maintainer felt no rumble. The 63-byte vendor output report `0x81` and a write on the interrupt OUT pipe were not tried.

### Bluetooth LE as `2DC8:301B`

Raw source: `2c-bluetooth-301b/ordered-controls-120s.txt`. OJD decode source: `2c-bluetooth-301b/ojd-watch-120s.txt`, from `ojd controller watch` on `0.6.0-alpha.2`. One report is 11 bytes: `01`, hat (byte 1), four unsigned 8-bit stick values (bytes 2 to 5), two trigger bytes (6 and 7), then three button bytes (8, 9 and 10). At rest the report is `01 0F 7F 7F 7F 7F 00 00 00 00 00`.

| Control | Raw (bytes that change) | OJD decode |
| --- | --- | --- |
| A, B, X, Y | byte 8 = `01`, `02`, `08`, `10` | South, East, West, North |
| LB, RB | byte 8 = `40`, `80` | LeftShoulder, RightShoulder |
| Left trigger | byte 7 rises 0 to 255 with byte 9 = `01` | LeftTrigger, LT up to 65535 |
| Right trigger | byte 6 rises 0 to 255 with byte 9 = `02` | RightTrigger, RT up to 65535 |
| Back, Start, Guide | byte 9 = `04`, `08`, `10` | Back, Start, Guide |
| Left, right stick click | byte 9 = `20`, `40` | LeftStickClick, RightStickClick |
| D-pad up, down, left, right | byte 1 = `0`, `4`, `6`, `2`; `F` at rest | north, south, west, east; neutral at rest |
| Left stick X, Y | bytes 2 and 3: 0 to 255 | LS from -32767 to 32767; rest reads (-128,-128) |
| Right stick X, Y | bytes 4 and 5: 0 to 255 | RS from -32767 to 32767; rest reads (-128,-128) |

The trigger rows follow the press order: the OJD capture lists LeftTrigger before RightTrigger, and the raw capture raises byte 7 before byte 6.

Battery: byte 10 reads `00` in every report of the capture. `ojd controller show 2DC8:301B` prints `Battery none` (`2c-bluetooth-301b/serving.txt`). The capture records no charge level. At 100%, as `system_profiler SPBluetoothDataType` reads it from the pad's Bluetooth battery service, byte 10 reads `00` in all 653 reports (`2c-bluetooth-301b/battery-100-percent.txt`). At 90%, as the macOS Bluetooth menu shows it, byte 10 reads `00` in all 545 reports (`2c-bluetooth-301b/battery-90-percent.txt`). The byte is constant, and the report carries no charge level.

Rear buttons: at the end of the capture one press sets byte 8 = `04` (bit 2) and two set byte 8 = `20` (bit 5); `tasks.md` 2.3 names them L4 and R4. The decode in `ojd-watch-120s.txt` lists neither bit, because the record maps neither.

Rumble: `2c-bluetooth-301b/rumble-writes.txt` shows `IOHIDDeviceSetReport` of output report 5, with and without the report ID byte, returning `e00002f0` (`kIOReturnNotFound`) for all eight writes while macOS serves the pad. The maintainer reports one rumble when the pad connected. When OJD serves the pad, `ojd controller rumble` exits 1 with `error[E2013]: 8BitDo Ultimate 2C Wireless has no rumble motor.` (`2c-bluetooth-301b/serving.txt`). With a user patch that gives the mode a rumble template for output report 5, OJD's session sends the write while OJD serves the pad, and it fails with the same `kIOReturnNotFound` (`2c-bluetooth-301b/rumble-writes.txt`). Over Bluetooth LE the record declares no rumble.

### Unverified

| Row | Missing |
| --- | --- |
| Device that produces `2DC8:301D` | A capture of that identity. Receiver, cable, and Bluetooth LE in XInput and DInput produce `310A`, `301C`, and `301B` only (`2c-cable/mode-attempts.txt`). |
| Device that produces `2DC8:3109` | A capture of that identity, from an 8BitDo adapter other than the pad's receiver. |
| `2DC8:301C` rumble | A write of vendor report `0x81` or on the interrupt OUT pipe that the maintainer feels. |

## Why Bluetooth Needs a Record

Over Bluetooth the controller advertises a standard GamePad descriptor. The generic mapping read it wrong: the right stick drove LT/RT, the triggers rested at half travel, and several buttons were shifted. Three properties of the descriptor cause this:

- the right stick is on `Z`/`Rz`, not `Rx`/`Ry`;
- the analog triggers are on Simulation page `0x02`: Accelerator is RT and Brake is LT;
- button usages follow Android order with gaps.

The record binds `HIDDescriptor` with the same layout as the GameSir G7 SE:

| Button usage | Control |
| --- | --- |
| 1 | A |
| 2 | B |
| 4 | X |
| 5 | Y |
| 7 | LB |
| 8 | RB |
| 11 | View |
| 12 | Menu |
| 13 | Home |
| 14 | L3 |
| 15 | R3 |

Usages 3 and 6 are the rear buttons and 9 and 10 repeat the triggers as digital bits. They are not mapped, and `Rx` and `Ry` (usages 51 and 52) map to nothing. The `301D` record uses this table and the same stick. The rear buttons of the 2C default to L3 and R3 on the pad, so no record maps a paddle until a capture shows a separate bit.

## Bootloader Identities

`2DC8:3208` and `2DC8:5750` are 8BitDo bootloader identities. A write to a pad in bootloader state risks a bad firmware image, so OJD sends these identities no transfer of any kind: no descriptor read beyond what macOS publishes, no startup step, no probe, no keep-alive, no rumble or light output and no configuration packet. Each identity has a bundled record whose default mode is `idle: Bootloader`, so the refusal holds when an interface signature or a gamepad descriptor would bind a protocol for any other device. The classifier returns the unbound reason `BootloaderIdentity` from that record before it looks at an interface; a user or package file that adds or patches either identity is refused, the log has one `left unbound` line that names the VID:PID and the reason, and the controller detail reads "This controller is in bootloader mode. OJD sends it no data." `ojd diagnose record` refuses a record file for either identity before it opens the device. `BootloaderGuardTests` covers the raw-USB and HID paths and the mode probe, `BootloaderRecordTests` covers the records and the refused files, and `ControllerRecordProbePlanTests` covers the record probe.

## Procedure

Connect the controller in the mode under test, then confirm the route (`ojd` is the [command-line tool](../../wiki/Command-Line.md), and `<controller>` is an ID from the list or its `VVVV:PPPP`):

```bash
ojd controller list
ojd controller show <controller>
```

In `show`, Bluetooth and the HID receiver should report the protocol `HIDDescriptor`; the XInput dongle reports `XboxXUSB`. Then watch the controls:

```bash
ojd controller watch <controller>
```

With the controller at rest, both triggers must read 0. Move the right stick and confirm the triggers stay at 0. Press each button in the table and confirm the reported name matches the label on the controller. Report the result with the mode and VID:PID on [#34](https://github.com/xsyetopz/OpenJoystickDriver/issues/34).
