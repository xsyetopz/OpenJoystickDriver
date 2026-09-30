# Shanwan PS3/PC pads

Many cheap "PS3/PC" pads use a Shanwan chip. They are not DualShock 3 controllers and do not speak Sony's protocol. OJD has one record for this family:

| Controller | Mode | VID:PID | Route |
| --- | --- | --- | --- |
| Ant Esports GP100, wired | PS3/PC | `2563:0575` | `vendor.shanwan` |

The GP100 starts in XInput mode. In that mode macOS sees no input. Hold **Select** and **B** while plugging it in to switch to PS3/PC mode ([#38](https://github.com/xsyetopz/OpenJoystickDriver/issues/38)).

## Why the pad needs its own driver

In PS3/PC mode the descriptor's axis ranges do not match the values the pad sends, so the generic HID mapping read the sticks wrong. The `vendor.shanwan` driver reads the report by byte offset. The offsets come from a GP100 owner's raw HID probe and match SDL's `PS3ThirdParty` driver. [PR #42](https://github.com/xsyetopz/OpenJoystickDriver/pull/42) by kartinul is independent hardware evidence for the same offsets: it verified a Shanwan "PS3/PC Gamepad" (`2563:0575`) for buttons, D-pad with diagonals, both sticks and both triggers, input only, with a separate parser rather than this driver.

## Report layout

The offsets are for the report as macOS delivers it, and byte 0 is not read. SDL accepts reports of 19 bytes or more.

| Offset | Contents |
| --- | --- |
| 1 | `0x01` Select, `0x02` Start, `0x04` L3, `0x08` R3, `0x10` Home (Home from SDL only) |
| 2 | Low nibble D-pad hat (not read; the pressure bytes are used instead) |
| 3, 4 | Left stick X, Y; unsigned, center `0x80`, up and left low |
| 5, 6 | Right stick X, Y; same encoding |
| 7–10 | D-pad pressure: right, left, up, down |
| 11–14 | Face pressure: Triangle, Circle, Cross, Square |
| 15, 16 | L1, R1 pressure |
| 17, 18 | L2, R2 analog |

The driver treats a pressure byte as pressed when bit 7 is set (`0x80` or higher), so light pressure or noise does not register a press. Byte 0 also carries digital button bits in SDL's layout. Nobody has checked them on the GP100, so the driver does not read them.

## Not supported

- Rumble. SDL sends no output reports to Shanwan pads because some pads then rumble without stopping. Two unverified formats exist: Linux `hid-shanwan` sends `02 08 <right> <left> FF 00 00 00`, and a script posted for the GP100 sends `02 00 <a> <b> 00 00 00 00`.
- Motion. Bytes 19 onward carry accelerometer data, which the driver ignores.
- Other Shanwan identities. Report their VID:PID and a raw capture in a new issue.

## Procedure

Plug the pad in PS3/PC mode, then confirm the route:

```bash
/Applications/OpenJoystickDriver.app/Contents/MacOS/OpenJoystickDriver \
  --headless controller list
```

The entry should report `protocol=vendor.shanwan`. Then watch the controls:

```bash
/Applications/OpenJoystickDriver.app/Contents/MacOS/OpenJoystickDriver \
  --headless controller state
```

Push each stick fully right and fully up; confirm positive X and negative Y. Confirm both triggers rest at 0. Press every button, D-pad direction, and Home, and confirm the reported name matches the label. Report the result on [#38](https://github.com/xsyetopz/OpenJoystickDriver/issues/38).
