# Flydigi Vader 4 Pro (Bluetooth)

Bluetooth Low Energy identity `D7D7:0041`, firmware 6.9.5.5, observed on
macOS 26.5. The 2.4 GHz dongle and wired modes enumerate as different
identities and are not covered by this record.

## Why the record exists

The device advertises Generic Desktop GamePad usage, so descriptor-driven
discovery finds it, but three descriptor properties defeat the generic parser:

- the right stick is published on `Z`/`Rz`, which the generic parser maps to
  triggers;
- the analog triggers are published on Simulation page `0x02` as Brake and
  Accelerator, which the generic parser does not read;
- button usages are non-contiguous (1, 2, 4, 5, 7…15), so every index after
  the first gap shifts.

Observed generic-parser behavior before the record: right stick drove the
triggers, LT and RT reported stick clicks, X reported Y, Y reported left
bumper, RB reported Start, LB reported Back, Select reported Guide, Start
reported nothing, and left-stick Y was inverted. The D-pad was correct.

## Report layout

Report ID `0x01`, 15 bytes. Neutral:
`01 FF FF FF FF 00 00 00 00 00 00 00 00 00 00`.

| Offset | Contents |
| --- | --- |
| 1 | Left stick X, signed, `0x7F` right |
| 2 | Left stick Y, signed, `0x80` up |
| 3 | Right stick X, signed, `0x7F` right |
| 4 | Right stick Y, signed, `0x80` up |
| 9 | Low nibble D-pad hat, `1` up increasing clockwise; `0x10` A, `0x20` B, `0x40` X, `0x80` Y |
| 10 | `0x01` LB, `0x02` RB, `0x04` LT digital, `0x08` RT digital, `0x10` Select, `0x20` Start, `0x40` L3, `0x80` R3 |
| 11 | `0x01` C, `0x02` Z, `0x04` M1, `0x08` M2, `0x10` M3, `0x20` M4 |
| 12 | `0x80` Home |
| 13 | Left trigger, unsigned `0...255` |
| 14 | Right trigger, unsigned `0...255` |

Bytes 5 through 8 were `0x00` in every observed report.

The digital trigger bits in byte 10 accompany the analog values rather than
replacing them, so the parser reads position from bytes 13 and 14 only.

C, Z, and M1 through M4 are decoded but have no `Button` case and no bit in
the 16-button compatibility report, so they do not reach a consumer.

## Status

Input decoding is verified against captured reports for every control in the
table. Not yet verified on this hardware:

- consumer-visible input through a signed build and the virtual device;
- reconnect after the controller sleeps;
- rumble or any other physical output;
- the 2.4 GHz dongle and wired identities.

## Procedure

Pair the controller over Bluetooth, then confirm the runtime selects this
record rather than the generic fallback:

```bash
/Applications/OpenJoystickDriver.app/Contents/MacOS/OpenJoystickDriver \
  --headless controller list
```

The entry should report `protocol=flydigi`. Then check each control:

```bash
/Applications/OpenJoystickDriver.app/Contents/MacOS/OpenJoystickDriver \
  --headless controller state
```

Push the left stick fully up and confirm the reported Y is negative. Deflect
the right stick and confirm the triggers stay at rest. Press each face button,
bumper, stick click, Select, Start, and Home in turn and confirm the reported
name matches the physical label.
