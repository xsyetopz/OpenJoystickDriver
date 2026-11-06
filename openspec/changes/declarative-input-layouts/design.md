# Design: declarative input layouts

Status: proposal.

## Context

Evidence read on `main`:

- Schema: `inputAxis` allows `bits` 8 or 16 at a whole `byte` 0-63 (`Resources/Schemas/controller.schema.json:945-960`); `inputField` is `byte` plus an 8-bit `mask` (`:892-908`); `inputButton` repeats both (`:909-944`); the report length ceiling is 64 (`:670-688`).
- Swift: `ReportBitField` is `byte` plus `mask` (`ControllerInputLayout.swift:2-14`); `Axis.bits` is 8 or 16 (`:34`, `:52-58`, `:67`); the layout guard is `1...64` (`:151`) and fields must lie after the report ID (`:157`); the decoder rejects unknown keys per section (`ControllerRecordDocument+InputLayout.swift`).
- HID usage maps hold `Button`, `Axis`, `Hat` (`HIDUsageMap.swift:10-17`), reject a usage named twice (`:104-105`) and a button on a D-pad control (`:109`); the decoder says "kind is Button, Axis or Hat" (`ControllerRecordDocument+HIDUsageMap.swift:132`).
- Use today: five authored files use `mask` (all contiguous masks: 1, 2, 4, 8, 16, 32, 64, 128, 15, 240, 255) and generated copies of two exist under `Sources/OpenJoystickDriverKit/Resources/Controllers/`. `Scripts/` has no `byte` or `mask` reader.
- Drivers that read reports over 64 bytes: DualSense Bluetooth, 78 bytes (`DualSenseDriver.swift:18`), and DualShock 4 Bluetooth, 78 and 79 bytes (`DualShock4Driver+Reports.swift:236-256`). Both are Swift protocol drivers, not layout records. `Switch2Driver.swift:6` reads a 64-byte state report.
- The Wii report modes 0x30-0x3F come from WiiBrew as summarized in the research notes (`input-config.md:6`); no Wii file is in the repository.

## Goals / Non-Goals

Goals: implement the spec scenario "Twelve-bit stick"; select among layouts by report ID and length; add the usage map kinds the SDL import needs; keep one shape for each document part.

Non-goals: see the proposal's Out of scope.

## Decisions

1. **One addressing form, `bitOffset` and `bitSize`.** Bit 0 is the least significant bit of report byte 0, as HID packs fields; byte 0 is the report ID when the layout has one, so offsets count the same bytes as today's `byte` (`ControllerInputLayout.swift:157`). A field may not touch the ID byte or pass the end of the report length. Reason: two forms (`byte`+`mask` and offset+size) would be two readers; the repository rule is no dual readers before `v1.0.0`. All current masks are contiguous, so each converts exactly (`mask` 240 is offset 4, size 4).
2. **Size 1 to 32.** Buttons use size 1 or more (any set bit presses, as for a mask; axes and triggers use 1 to 32. Decoding goes through a 64-bit integer, so a field never overflows. Normalization uses `Double`, then narrows to `Float`, because `Float` holds 24 bits of mantissa and a 32-bit field would lose steps.
3. **Endianness is named.** `byteOrder` is `LittleEndian` or `BigEndian`. Little endian is the bit-stream order HID uses and applies when the key is absent; the wiki states it and a test covers it. `BigEndian` needs `bitOffset` divisible by 8 and `bitSize` of 16, 24 or 32; any other combination is rejected, because a big-endian field that is not byte-aligned has no agreed meaning.
4. **Signedness and range.** `signed` is two's complement over `bitSize`. `min` and `max` default to the full range of that size and signedness and widen to the 32-bit range (`-2147483648` to `4294967295`) from today's `-32768` to `65535`. The existing `symmetric` rule is kept (`signed` required, `min` below 0, `max` above 0).
5. **Hat sources keep their encodings** (`EightWay`, `Directions`, `Table`) and take `bitOffset` and `bitSize` in place of `byte` and `mask`. The 8-way rule "at least 3 adjacent bits" becomes `bitSize` of 3 to 8; `Table` keys must fit `bitSize`.
6. **The 64-byte ceiling stays.** No layout-driven family reads a longer report; the two 78-byte readers are protocol drivers. Raising the ceiling would add an untested range. A test pins the rejection of a 65-byte layout with a named problem, so the limit is a behavior with a message and not an accident. The ceiling is raised in the change that adds a family needing it.
7. **Conditional layouts are a list.** `input.layouts` holds one or more layouts. A layout's selector is its existing `report` (`id`, and `length` as `atLeast` or `exactly`). Rules, each with a test:
   - Two layouts whose selectors can match the same report are rejected at validation. Reason: first-match order would be hidden behavior.
   - A report that no layout selects is ignored, as a short report is ignored today; the rule is named "Unselected report" in the wiki.
   - A layout decodes only the controls it names; every other control keeps its last value ("Layout carry"). Reason: Wii reports 0x30-0x3F carry the core buttons in all modes and add accelerometer, IR or extension data in some, so a report without accelerometer data must not zero it.
   - The union of the controls of all layouts is the record's declared input, which the "Full capability declaration" requirement compares with parser output.
8. **HID usage map kinds**, all keyed by page and usage like the existing three:
   - `HalfAxis`: `half` (`Positive` or `Negative`), `control` (`LeftTrigger` or `RightTrigger`), optional `inverted`. The chosen half of the element's range, from its center to its end, rescales to 0...1. Stick-axis targets are not offered: how SDL reads a half of a stick axis is not confirmed, so a line that needs it is reported as unmapped by the import.
   - `AxisDpad`: `half`, `control` (one of `DpadUp`, `DpadDown`, `DpadLeft`, `DpadRight`), `threshold` (above 0 and below 1, required). The direction is pressed while the half's travel is at or past `threshold`.
   - `AxisButton`: `half`, `control` (a button control), `threshold` (required).
   - `ButtonTrigger`: `control` (`LeftTrigger` or `RightTrigger`); the trigger reads 1 while the element value is nonzero and 0 otherwise.
   Reason for two threshold kinds: a button control and a D-pad control are different sets in the vocabulary, and `Button` already forbids D-pad controls (`HIDUsageMap.swift:109`). `threshold` has no default so no value is hidden; the SDL import names its own constant.
9. **Uniqueness per usage and half.** A usage may appear in several entries only when every entry is a `HalfAxis`, `AxisDpad` or `AxisButton`, with at most one entry per half. An `Axis`, `Button`, `Hat` or `ButtonTrigger` entry excludes every other entry of its usage. This relaxes `HIDUsageMap.swift:104-105` exactly as far as combined trigger axes and axis D-pads need. A D-pad direction driven by both a `Hat` and an `AxisDpad` is pressed when either source presses it.
10. **Swift is the validator, the schema carries the same shapes.** The schema states keys, enums and ranges; rules a schema cannot say (selector overlap, half uniqueness, byte alignment of `BigEndian`) are checked by Swift, and each gets a case in `Tests/OpenJoystickDriverKitTests/Protocol/Catalog/SchemaRejections/` (`"schema": true` only where the schema alone rejects). Python tools read Swift output and do not re-implement these rules.
11. **Equivalence.** The decoded frames of the five converted records must equal the `platform-neutral-redesign` task 1.1 snapshots (`Tests/EquivalenceSnapshots`), so the conversion changes no behavior.

## Risks

- Converting records by hand can shift a bit. Mitigation: the snapshot test of decision 11, run before and after.
- `Layout carry` can show a stale value when a pad stops sending a report. This is the same staleness any last-value state has; a keepalive or disconnect clears the state through the existing pipeline. Not verified here; a test covers a layout switch.
- `HalfAxis` rescale may differ from how SDL reads the same half. Mitigation: `Tools/SDLGamepadProbe` comparison in the hardware list, and the import reports such lines as unmapped until it agrees.
- The schema file is long and shared; a mistake in `inputAxis` breaks every record. Mitigation: `./Scripts/ojd check schemas` and the full SchemaRejections run.

## Open Questions

- Whether `AxisDpad` and `AxisButton` thresholds should accept separate press and release values (hysteresis). Not needed by the import; left out until a pad shows chatter.
- Whether the ceiling should rise with the Wii remote's longest report. WiiBrew lists the report modes; the lengths are to be read from the Wii change, not assumed here.
