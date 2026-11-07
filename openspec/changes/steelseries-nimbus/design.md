# Design

## Context

The descriptor, as the brief gives it, has no capture behind it:

- Bytes 0 to 3: D-pad pressure, 0 to 255, usages `0x90` Up, `0x92` Right, `0x91` Down, `0x93` Left in descriptor order.
- Bytes 4 to 11: buttons 1 to 8 as pressure, A, B, X, Y, L1, R1, L2, R2 per SDL.
- Byte 12 bit 0: Consumer `0x0223`, the Menu button.
- Bytes 13 to 16: X, Y, Z, Rz, signed -127 to 127. SDL marks Y inverted.
- Output report: four player LEDs.

One capture shows only byte 14 (stick Y) moving, with the stick at rest near -3.

## Goals / Non-Goals

**Goals:** a record that reads every control from the descriptor; a D-pad that works for any descriptor with usages `0x90` to `0x93`; a controls list that matches what the pad declares.

**Non-Goals:** the player LEDs (the record format describes only rumble and startup writes), a Bluetooth record, and any claim that the thresholds or signs are verified.

## Decisions

- **Usage map, not report layout.** `HIDReportLayout` has no per-button threshold, so the record uses `hidUsageMap`: buttons 1 to 6 are `AxisButton` entries at 0.5, L2 and R2 are `Axis` entries so the trigger stays analog.
- **D-pad as `AxisDpad`, positive half, threshold 0.5.** Travel is measured from the range center, so 0.5 presses at about raw 191 of 255. The value is unvalidated and is a hardware check. The standard map and the SDL converter use the same entry, and the converter reads a `b#` D-pad binding as the positive half.
- **Menu is Start.** SDL calls Consumer `0x0223` `guide`, while the control crosswalk maps Apple's Menu button to Start. The record uses Start. A hardware check settles it.
- **Served by System.** The record sets no `server`, so macOS serves the pad and OJD reads input only. OJD publishes no virtual controller for it.
- **Controls list from the descriptor.** `HIDDescriptorDriver` filters the map's controls by the usages the report descriptor declares. With no descriptor it lists every control of the map.
- **No Bluetooth record.** `0111:1420` appears only in SDL's database, and the pad is not paired over Bluetooth here.

## Risks / Trade-offs

- The sticks' dead zone (0.05) and the inverted Y rest on SDL and one capture; a wrong sign shows in the hardware checks.
- A record now takes precedence over the SDL entry for `1038:1420`, so the generated catalog drops that SDL line.
- The LEDs stay dark under OJD until the format can describe a HID output report.
