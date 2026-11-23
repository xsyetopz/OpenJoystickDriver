# Input Layout Fields

`input.layouts` tells OJD which bits of an input report hold each control. A `HIDReportLayout` record requires it. Other families take it to override the controls a layout names.

## Contents

- Report selection
- Bit positions
- Buttons
- Axes
- Hat
- Triggers
- Touch
- Example

## Report Selection

- `report.length` has exactly one key: `atLeast` or `exactly`, an integer N from 1 to 64.
- `report.id` (1 to 255) is optional. With it, byte 0 holds the ID and N counts it.
- No two layouts select the same report. A report no layout selects goes to the family driver, or is ignored by `HIDReportLayout`.
- A layout changes only the controls it names. Each other control keeps its last value.

## Bit Positions

- `bitOffset` counts bits from bit 0 (least significant) of byte 0 of the report as macOS delivers it. Bit 7 of byte 13 is 111.
- `bitSize` is 1 to 32 and stays inside the report length. With a report `id`, a field lies after byte 0.

## Buttons

- Each entry has `control`, `bitOffset`, `bitSize`. Pressed while any bit is set.
- Repeat a control to read it from several places.
- A button is never a D-pad direction or stick axis. A `LeftTrigger` or `RightTrigger` button is the digital press.

## Axes

- 1 to 4 entries with a stick-axis `control` (`LeftStickX`, `LeftStickY`, `RightStickX`, `RightStickY`).
- Unsigned unless `signed` is `true` (two's complement).
- `byteOrder`: `LittleEndian` (default) or `BigEndian`; big endian needs a byte-aligned `bitOffset` and a `bitSize` of 16, 24, or 32.
- `min` and `max` narrow the raw range; `max` minus `min` is at least 2.
- `inverted` flips the direction. X grows right, Y grows down.
- `symmetric` reads raw divided by `max`; it needs `signed`, a negative `min`, and a positive `max`.

## Hat

A list of sources; the first that reads a direction wins. Each has an `encoding`:

- `EightWay`: `bitSize` 3 to 8; 0 is north, clockwise to 7. Other values read centered. `neutralUntilNonzero` reads 0 as centered until the bits are nonzero once.
- `Directions`: `up`, `right`, `down`, `left`, each with `bitOffset` and `bitSize`. Opposites cancel.
- `Table`: `bitOffset`, `bitSize`, and `values`, mapping each decimal number to `North`, `NorthEast`, `East`, `SouthEast`, `South`, `SouthWest`, `West`, or `NorthWest`.

## Triggers

`leftTrigger` and `rightTrigger` take an analog field (`bitOffset`, `bitSize`, plus `byteOrder`, `signed`, `min`, `max`), a `button` field, or both. The analog value reads `min` to `max` as 0 to 1. The `button` field reads as fully pulled.

## Touch

`touch` maps multi-touch contacts to controls, for a pad that taps a phone screen. It names `contacts` (slots with `bitOffset`, `stride`, `slots`, `count`, and per-slot `tip`, `id`, `x`, `y`), `radius`, and `spots`, `sticks`, or both. Read the Controller Records wiki page before writing one.

## Example

An 8-byte report with no ID: eight buttons in byte 0, an eight-way hat in byte 1, four stick bytes, and two trigger bytes.

```json
{
  "apiVersion": "openjoystickdriver/v1alpha3",
  "kind": "Controller",
  "vendorID": 4617,
  "productID": 1,
  "modes": [{ "id": "default", "protocol": { "family": "HIDReportLayout" } }],
  "input": { "layouts": [{
    "report": { "length": { "atLeast": 8 } },
    "buttons": [
      { "control": "South", "bitOffset": 0, "bitSize": 1 },
      { "control": "East", "bitOffset": 1, "bitSize": 1 },
      { "control": "West", "bitOffset": 2, "bitSize": 1 },
      { "control": "North", "bitOffset": 3, "bitSize": 1 },
      { "control": "LeftShoulder", "bitOffset": 4, "bitSize": 1 },
      { "control": "RightShoulder", "bitOffset": 5, "bitSize": 1 },
      { "control": "Back", "bitOffset": 6, "bitSize": 1 },
      { "control": "Start", "bitOffset": 7, "bitSize": 1 }
    ],
    "hat": [{ "bitOffset": 8, "bitSize": 4, "encoding": "EightWay" }],
    "axes": [
      { "control": "LeftStickX", "bitOffset": 16, "bitSize": 8 },
      { "control": "LeftStickY", "bitOffset": 24, "bitSize": 8 },
      { "control": "RightStickX", "bitOffset": 32, "bitSize": 8 },
      { "control": "RightStickY", "bitOffset": 40, "bitSize": 8 }
    ],
    "leftTrigger": { "bitOffset": 48, "bitSize": 8 },
    "rightTrigger": { "bitOffset": 56, "bitSize": 8 }
  }] }
}
```

`4617:1` is `1209:0001`, a pid.codes test ID. A shared record uses the real VID and PID.
