# 8BitDo Ultimate 2C Wireless

The Ultimate 2C Wireless enumerates as a different identity in each mode. Test and report each mode separately.

| Mode | VID:PID | Route | Status |
| --- | --- | --- | --- |
| 2.4 GHz dongle, XInput | `2DC8:310A` | `XboxXUSB` | Hardware-verified by two testers on `0.5.0-beta.4` tester build `1.5.71`: buttons, sticks, triggers at rest, D-pad, stick clicks, rumble |
| Bluetooth LE | `2DC8:301B` | `HIDDescriptor` | Unverified: the mapping was confirmed on hardware from a patch ([#34](https://github.com/xsyetopz/OpenJoystickDriver/issues/34)), and this record has no capture |
| Wired, DInput | `2DC8:301D` | `HIDDescriptor` | Unverified: the record reuses the Bluetooth usage map, and no source or capture of this mode exists |
| USB adapter | `2DC8:3109` | `XboxXUSB` | Unverified: the record stays `XboxXUSB` over a wired link, and what the standby identity means is not known |
| HID receiver | `2DC8:301C` | `HIDDescriptor` | Idle receiver: the record is `idle`, maps no controls and reports `IdleIdentity`; the pad is assumed to re-enumerate as `310A` once it connects; not verified |

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

`2DC8:3208` and `2DC8:5750` are 8BitDo bootloader identities. A write to a pad in bootloader state risks a bad firmware image, so OJD sends these identities no transfer of any kind: no descriptor read beyond what macOS publishes, no startup step, no probe, no keep-alive, no rumble or light output and no configuration packet. The refusal holds with or without a record, including when an interface signature or a gamepad descriptor would bind a protocol for any other device. The classifier returns the unbound reason `BootloaderIdentity` before it looks at a record or an interface, the log has one `left unbound` line that names the VID:PID and the reason, and the controller detail reads "This controller is in bootloader mode. OJD sends it no data." `ojd diagnose record` refuses a record file for either identity before it opens the device. `BootloaderGuardTests` covers the raw-USB and HID paths and the mode probe, and `ControllerRecordProbePlanTests` covers the record probe.

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
