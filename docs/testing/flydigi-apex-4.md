# Flydigi Apex 4 (DInput)

USB identity `04B4:2412`, the DInput mode of the Flydigi Apex 4. The record is source-derived and unverified: no tester capture of this pad has replayed against it. Card F4 in [Flydigi tester checks](flydigi-tester-checks.md) lists the files a tester sends.

## Modes

| Mode | Identity | Record |
| --- | --- | --- |
| DInput | `04B4:2412` | This record |
| XInput | `045E:028E`, product name "Flydigi VADER3" | The Microsoft `045E:028E` record; the Flydigi record does not apply and is not changed |

## Source

The layout follows section 9 of the protocol notes of [flydigi-space-station-mac][1] at commit `649b9f36cbba80deb7e7ac11309615d44f382a8e` (MIT; see [Third-Party Notices](../../THIRD_PARTY_NOTICES.md) and [Compatibility Source Notes](../development/compatibility-sources.md)). The notes name a vendor HID interface of the pad on usage page `0xFFA0` with input report 4 and output report 5.

## Report layout

The record reads input report 4 as 32 bytes with the report ID in byte 0, the way the notes say IOHIDManager delivers it. A report with another ID or length is ignored, so the replies of the pad (`04 FF ...`, length 32) are not told apart by byte 1.

| Offset | Contents |
| --- | --- |
| 7 | Bit 0 C (Auxiliary 1), bit 1 Z (Auxiliary 2), bits 2 to 5 M1 to M4 (Left Paddle 1, Left Paddle 2, Right Paddle 1, Right Paddle 2) |
| 8 | Bit 3 Home (Guide) |
| 9 | Bits 0 to 3 D-pad up, right, down, left; bit 4 A, bit 5 B, bit 6 Select (Back), bit 7 X |
| 10 | Bit 0 Y, bit 1 Start, bit 2 LB, bit 3 RB, bit 4 digital LT, bit 5 digital RT, bit 6 L3, bit 7 R3 |
| 17, 19 | Left stick X and Y, `0` to `255`, centre `0x7F`, Y grows downwards |
| 21, 22 | Right stick X and Y |
| 23, 24 | Left and right trigger, `0` to `255` |

Not mapped: M5 and M6 (byte 7, bits 6 and 7), Fn/Menu and Turbo (byte 8, bits 0 and 1), the "Back" bit 4 of byte 8 (the notes list it next to Select without saying how the two differ), and the motion sensor bytes. The paddle order is a proposal until a tester names the buttons. The record sends no output: the pad has no rumble motors, and output report 5 carries configuration the record does not write.

## Status

Unverified. The `HIDReportLayout` record binds to every HID interface of the pad and decodes only report 4 of 32 bytes, so the other interfaces send nothing it reads. Tests replay reports built from the layout above, not captures. Not yet checked on hardware: the report length and ID in byte 0, the stick and trigger ranges, every button bit, and which HID interface the runtime binds.

## Procedure

Put the pad in DInput mode, then run (`ojd` is the [command-line tool](../../wiki/Command-Line.md)):

```bash
ojd controller list
ojd controller show 04B4:2412
ojd controller watch 04B4:2412
```

`show` should report the protocol `HIDReportLayout`. Press each control in turn and confirm the reported name matches the physical label.

[1]: https://github.com/uiltonlopes/flydigi-space-station-mac/blob/649b9f36cbba80deb7e7ac11309615d44f382a8e/docs/protocol.md
