# 8BitDo Ultimate 2C Wireless

The pad enumerates as a different identity per mode; test each mode separately. Capture paths are relative to the `evidence/` folder of the 0-6-0-alpha-3 change.

## Contents

- [Results](#results)
- [Why Bluetooth Needs a Record](#why-bluetooth-needs-a-record)
- [Bootloader Identities](#bootloader-identities)
- [Procedure](#procedure)
- [Further Reading](#further-reading)

| Mode | VID:PID | Route | Status |
| --- | --- | --- | --- |
| 2.4 GHz receiver, XInput | 2DC8:310A | XboxXUSB | Captured: every control reports (`2c-receiver-310a/ordered-controls-100s.txt`); rumble felt on release build 1.28.99 (`2c-procedure/modes.txt`); unassigned rear buttons send no bit (`2c-receiver-310a/rear-unassigned-with-a-b-45s.txt`) |
| Cable, XInput or DInput | 2DC8:310A | XboxXUSB | Captured: the cable enumerates as 310A after X + Home and after B + Home (`2c-cable/mode-attempts.txt`); same report as the receiver's 310A; unassigned rear buttons send no bit (`2c-cable/310a-rear-unassigned-45s.txt`) |
| Bluetooth LE | 2DC8:301B | HIDDescriptor | Captured: every control raw and decoded (`2c-bluetooth-301b/ordered-controls-120s.txt`, `2c-bluetooth-301b/ojd-watch-120s.txt`); battery byte reads 0 at 100% and at 90%; rumble write fails |
| Unknown | 2DC8:301D | HIDDescriptor | Unverified: no mode of the pad enumerated as this identity (`2c-cable/mode-attempts.txt`) |
| Unknown | 2DC8:3109 | XboxXUSB | Unverified: no mode of the pad enumerated as this identity (`2c-cable/mode-attempts.txt`); the maintainer owns no 8BitDo adapter other than the pad's receiver |
| 2.4 GHz receiver, DInput | 2DC8:301C | HIDDescriptor | Captured: every control reports (`2c-receiver-301c/ordered-controls-150s.txt`); the mode unlinked matches the product string IDLE, is idle: NoControllerLinked and reports NoControllerLinked; the default mode serves the linked pad with the HID descriptor and the Bluetooth LE usage table, which the receiver's descriptor and the capture match; unassigned L4 sets byte 1 bit 2 and unassigned R4 sets bit 5 (`2c-receiver-301c/rear-unassigned-60s.txt`) |

## Results

The three `ordered-controls` captures press A, B, X, Y, LB, RB, left trigger, right trigger, Back, Start, Guide, left stick click, right stick click, D-pad up, down, left, right, left stick, right stick. The 310A and 301C captures have no OJD decode.

### Receiver as 2DC8:310A

Source: `2c-receiver-310a/ordered-controls-100s.txt`. A report is 20 bytes: `00 14`, buttons (bytes 2 and 3), triggers (4 and 5), four signed 16-bit sticks (6 to 13), and `10 1C 30 64 00 10` in every report.

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

At rest (`2c-receiver-310a/idle-12s.txt`): 0 in the first 200 reports, small stick values in three later reports, then 0 in 100 more.

Rear buttons (unassigned, no separate rear bit as 310A):

| Capture | Presses | Reports |
| --- | --- | --- |
| `2c-receiver-310a/rear-square-star-45s.txt` | 7 | byte 2 = `20`, byte 3 = `10`, byte 2 = `10`, byte 2 = `10`, byte 3 = `10`, byte 3 = `10`, byte 3 = `10` (bits of other controls) |
| `2c-receiver-310a/rear-unassigned-with-a-b-45s.txt` | A, L4, L4, B, R4, R4, A, both assignments cleared (mapping light dark) | only byte 3 = `10`, `20`, `10`: A and B report, rear buttons send nothing |
| `rear-unassigned-60s.txt` | 5 each of L4 and R4 | only byte 3 = `10` and `20` |

The tail of `ordered-controls-100s.txt` agrees: byte 2 = `20`, `10` and byte 3 = `10` only.

### Cable

Source: `2c-cable/mode-attempts.txt`. By cable the pad enumerates as 2DC8:310A after X + Home, B + Home, and a move from the receiver in DInput mode. Same layout, but the last six bytes read `1A 1B 30 6D 00 00` or `11 1B 30 6D 00 00`, not `10 1C 30 64 00 10`. In `2c-cable/310a-rear-unassigned-45s.txt` the first reports carry byte 3 = `40` (X held from X + Home); then A (`10`) and B (`20`) report, rear buttons send nothing.

Rumble: `2c-receiver-310a/rumble-6s.txt` shows two writes, `00 08 00 00 C8 00 00 00` and 1.5 s later `00 08 00 00 00 00 00 00`; whether a motor ran is not recorded. On release build 1.28.99, `ojd controller rumble` exits 0 by receiver and by cable, and the maintainer felt both (`2c-procedure/modes.txt`).

### Receiver as 2DC8:301C

Source: `2c-receiver-301c/ordered-controls-150s.txt`, DInput. A report is 10 bytes: `01`, buttons (1 and 2), hat (3), four unsigned 8-bit sticks (4 to 7), triggers (8 and 9). At rest: `01 00 00 0F 7F 7F 7F 7F 00 00`.

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

| Capture | State | Reports |
| --- | --- | --- |
| `2c-receiver-301c/rear-r4-cleared-45s.txt` | R4 cleared | R4: byte 1 = `20` (bit 5) twice, at 11.07 s and 11.32 s; other presses: byte 2 = `04`, byte 1 = `01` |
| `2c-receiver-301c/rear-unassigned-60s.txt` | both cleared, 5 presses each | L4: byte 1 = `04` (bit 2) in 164 reports; R4: byte 1 = `20` (bit 5) in 142 |
| `2c-receiver-301c/rear-l4-assigned-60s.txt` | L4 assigned | no report sets byte 1 bit 2 (`04`) or bit 5 (`20`); presses: byte 2 = `04`, byte 1 = `01` |
| `2c-receiver-301c/ordered-controls-150s.txt` | presses after the sticks (28 s to 39 s) | byte 2 = `04`, byte 1 = `01`, byte 2 = `08` only; no byte 1 bit 2 or 5 |

Rumble: `2c-receiver-301c/rumble-writes.txt` lists eight `IOHIDDeviceSetReport` writes (report 1 with `C8`, `64` and `FF` payloads, each followed by zeros; report 5 `64 64 00 00` then zeros) and six more: report 1 in the SDL, XInput, and all-`FF` layouts, and the 63-byte vendor report `0x81`, each with and without the report ID first. All return `result=0`. No rumble felt.

The receiver's one interface has an interrupt OUT endpoint, `0x05`, 64 bytes. With macOS's HID driver detached through deviceCapture (root), six patterns (including report 1, report 5 in SDL's rumble layout, and report `0x81`) went out in full; no rumble felt. SDL's `SDL_hidapi_8bitdo.c` gives the Ultimate 2C no rumble support. The 301C record declares no rumble.

### Bluetooth LE as 2DC8:301B

Raw: `2c-bluetooth-301b/ordered-controls-120s.txt`. OJD decode: `2c-bluetooth-301b/ojd-watch-120s.txt` (`ojd controller watch`, 0.6.0-alpha.2). A report is 11 bytes: `01`, hat (1), four unsigned 8-bit sticks (2 to 5), triggers (6 and 7), buttons (8 to 10). At rest: `01 0F 7F 7F 7F 7F 00 00 00 00 00`.

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

Battery: byte 10 reads `00` in every report; no charge level. `ojd controller show 2DC8:301B` prints `Battery none` (`2c-bluetooth-301b/serving.txt`). At 100% (`system_profiler SPBluetoothDataType`, the pad's Bluetooth battery service): `00` in all 653 reports (`2c-bluetooth-301b/battery-100-percent.txt`). At 90% (macOS Bluetooth menu): `00` in all 545 reports (`2c-bluetooth-301b/battery-90-percent.txt`).

Rear buttons: at the end of the capture one press sets byte 8 = `04` (bit 2) and two set byte 8 = `20` (bit 5), identified by the maintainer as L4 and R4. `ojd-watch-120s.txt` (0.6.0-alpha.2) decodes neither bit. The record maps them as LeftPaddle1 and RightPaddle1.

Rumble: `2c-bluetooth-301b/rumble-writes.txt` shows `IOHIDDeviceSetReport` of output report 5, with and without the report ID byte, returning `e00002f0` (`kIOReturnNotFound`) for all eight writes while macOS serves the pad. The maintainer felt one rumble when the pad connected. When OJD serves the pad, `ojd controller rumble` exits 1 with `error[E2013]: 8BitDo Ultimate 2C Wireless has no rumble motor.` (`2c-bluetooth-301b/serving.txt`). With a user patch that adds a rumble template for output report 5, OJD's write fails with the same `kIOReturnNotFound` (`2c-bluetooth-301b/rumble-writes.txt`). The record declares no rumble over Bluetooth LE.

### Release Build, Every Mode

Source: `2c-procedure/`, release build 1.28.99. `watch-all.txt`: `ojd controller watch --all` across all mode switches. `modes.txt`: `show` and `rumble` per mode. `*-rumble-probe.txt` and `dinput-ble-gatt.txt`: the off-screen rumble probes.

| Mode set on the pad | Enumerates as | Controls | Rumble |
| --- | --- | --- | --- |
| XInput, 2.4 GHz receiver | 2DC8:310A | every button, hat, trigger and stick reports; no rear button bit | `ojd controller rumble` exits 0; the maintainer felt it |
| XInput, cable | 2DC8:310A | every button, hat, trigger and stick reports | `ojd controller rumble` exits 0; the maintainer felt it |
| DInput, cable | 2DC8:310A, the same unit as XInput by cable | as XInput by cable | as XInput by cable |
| DInput, 2.4 GHz receiver | 2DC8:301C | every button, hat, trigger and stick reports, with LeftPaddle1 and RightPaddle1 | E2013, the record declares none; the probe's report 1 writes in the Zeroplus layout return 0 with OJD suspended, and the maintainer felt nothing (`dinput-24ghz-rumble-probe.txt`) |
| DInput, Bluetooth LE | 2DC8:301B | every button, hat, trigger and stick reports; no paddle press in this run | E2013; report 5 writes and the Magnitude element value return `e00002f0` (`dinput-ble-rumble-probe.txt`) |
| XInput, Bluetooth LE | 2DC8:301B, the same unit as DInput over Bluetooth LE | every button, hat, trigger and stick reports, with LeftPaddle1 and RightPaddle1 | as DInput over Bluetooth LE: every probe write returns `e00002f0` |

While OJD serves 301C, its open is exclusive, so a probe gets `e00002c5` (`kIOReturnExclusiveAccess`) until `ojd controller suspend` releases it.

CoreBluetooth hides the HID service (`0x1812`) over Bluetooth LE and shows Device Information, Battery, and vendor service `00010203-0405-0607-0809-0A0B0C0D1912`, whose one writable characteristic, OTA, is the firmware update channel (`dinput-ble-gatt.txt`); nothing was written to it. The buzz on connect comes from firmware; the host has no rumble path over Bluetooth LE.

The 8-bit stick modes (301B, 301C) rest at `(-128,-128)`: the pad rests at 127 of 0 to 255, 1 step below center 127.5, which `HIDUsageMap.swift` maps to -128.

### Unverified Rows

| Row | Missing |
| --- | --- |
| Device that produces 2DC8:301D | A capture of that identity. Receiver, cable, and Bluetooth LE in XInput and DInput produce 310A, 301C, and 301B only (`2c-cable/mode-attempts.txt`). |
| Device that produces 2DC8:3109 | A capture of that identity, from an 8BitDo adapter other than the pad's receiver. |

## Why Bluetooth Needs a Record

The generic mapping misreads the Bluetooth GamePad descriptor: the right stick drives LT/RT, triggers rest at half travel, buttons shift. Causes:

- Right stick on `Z`/`Rz`; the generic mapping expects `Rx`/`Ry`.
- Analog triggers on Simulation page `0x02`: Accelerator is RT, Brake is LT.
- Button usages follow Android order with gaps.

The record binds HIDDescriptor with the GameSir G7 SE layout:

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

Usages 3 and 6 are the rear buttons. The 301B and 301C records map usage 3 to LeftPaddle1 (L4) and usage 6 to RightPaddle1 (R4), the bits the captures show while the buttons are unassigned; with an assignment the pad sends the assigned button's bit. Usages 9 and 10 (triggers as digital bits) and `Rx`/`Ry` (51, 52) map to nothing.

301C and 301D use this table and stick; 301D maps no rear button (no capture). The receiver's 301C descriptor puts button usage n on bit n - 1 of bytes 1 and 2, `X`, `Y`, `Z`, `Rz` on bytes 4 to 7, Accelerator on byte 8, Brake on byte 9; each control of the 301C capture lands on its usage here. As 310A, rear buttons send no bit of their own, so OJD sees them only through a pad assignment.

## Bootloader Identities

2DC8:3208 and 2DC8:5750 are 8BitDo bootloader identities. A write in bootloader state risks a bad firmware image, so OJD sends no transfer: no descriptor read beyond macOS's, startup step, probe, keep-alive, rumble, light output, or configuration packet.

Each has a bundled record, default mode `idle: Bootloader`. The classifier returns the unbound reason BootloaderIdentity before it looks at an interface, even if a signature or descriptor would bind a protocol. OJD refuses a user or package file that adds or patches either. The log has one `left unbound` line with VID:PID and reason. The controller detail reads "This controller is in bootloader mode. OJD sends it no data." `ojd diagnose record` refuses a record file for either before opening the device.

Tests:

- `BootloaderGuardTests`: raw-USB and HID paths, mode probe.
- `BootloaderRecordTests`: records, refused files.
- `ControllerRecordProbePlanTests`: record probe.

## Procedure

`ojd` is the [command-line tool](../../wiki/Command-Line.md); `<controller>` is a listed ID or its `VVVV:PPPP`.

1. Connect the controller in the mode under test.
2. Check the route:

   ```bash
   ojd controller list
   ojd controller show <controller>
   ```

   `show` reports HIDDescriptor for Bluetooth and the HID receiver, XboxXUSB for the XInput dongle.
3. Watch the controls:

   ```bash
   ojd controller watch <controller>
   ```

4. At rest, check both triggers read 0.
5. Move the right stick; check the triggers stay 0.
6. Press each button in the table; check the reported name matches the label.
7. Report the result with the mode and VID:PID on [#34](https://github.com/xsyetopz/OpenJoystickDriver/issues/34).

## Further Reading

- [8BitDo Tester Checks](8bitdo-tester-checks.md)
- [8BitDo Ultimate 2](8bitdo-ultimate-2.md)
