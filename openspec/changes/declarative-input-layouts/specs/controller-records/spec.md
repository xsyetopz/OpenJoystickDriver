## ADDED Requirements

### Requirement: Bit-addressed input fields

An input layout SHALL address every button, axis, trigger and hat field by `bitOffset` and `bitSize`, where bit 0 is the least significant bit of report byte 0. A button field SHALL be 1 to 32 bits and an axis or trigger field 1 to 32 bits. A field SHALL NOT include the report ID byte and SHALL lie inside the report length. The keys `byte`, `mask` and `bits` SHALL be rejected as unknown keys of an input field.

#### Scenario: Twelve-bit stick across a byte

- **WHEN** a record declares `LeftStickX` as 12 bits at `bitOffset` 4 of report 1 with `signed` false
- **THEN** the parser reads bits 4 to 15 as one unsigned value and reports a normalized value from -1 to 1

#### Scenario: Field in the report ID byte

- **WHEN** a layout with report ID 1 declares a field at `bitOffset` 0
- **THEN** the record is rejected and listed as a problem

#### Scenario: Size out of range

- **WHEN** a field declares `bitSize` 0 or 33
- **THEN** the record is rejected and listed as a problem

#### Scenario: Removed keys

- **WHEN** a field uses `byte` and `mask`
- **THEN** the record is rejected as an unknown key and no fallback reader accepts it

### Requirement: Wide value normalization

An axis or trigger SHALL support `signed` (two's complement over `bitSize`), `byteOrder` (`LittleEndian` when absent, or `BigEndian`), and `min` and `max` within the 32-bit range. `BigEndian` SHALL be accepted only for a field whose `bitOffset` is divisible by 8 and whose `bitSize` is 16, 24 or 32.

#### Scenario: Signed 16-bit big endian

- **WHEN** a record declares a signed 16-bit `BigEndian` axis at `bitOffset` 16 and the report bytes at 2 and 3 are `FF FE`
- **THEN** the raw value is -2

#### Scenario: Unaligned big endian

- **WHEN** a record declares `BigEndian` at `bitOffset` 3
- **THEN** the record is rejected and listed as a problem

#### Scenario: Default byte order

- **WHEN** a multi-byte axis has no `byteOrder`
- **THEN** it is read as `LittleEndian`

### Requirement: Input report length ceiling

An input layout SHALL select reports of 1 to 64 bytes, counting the report ID byte. A longer length SHALL be rejected with a named problem.

#### Scenario: Layout for a 65-byte report

- **WHEN** a layout declares `length` `exactly` 65
- **THEN** the record is rejected and the problem names the 64-byte ceiling

### Requirement: Conditional input layouts

A mode's `input` SHALL list one or more `layouts`, each selected by report ID and length. The selectors of two layouts SHALL NOT match the same report. A report that no layout selects SHALL be ignored. A layout SHALL change only the controls it names; every other control SHALL keep its last value.

#### Scenario: Two report modes

- **WHEN** a record lists a layout for report 0x30 with core buttons and a layout for report 0x31 with core buttons and an accelerometer, and report 0x31 arrives and then report 0x30
- **THEN** each report is decoded by its own layout, and the accelerometer keeps the value from report 0x31 after report 0x30

#### Scenario: Overlapping selectors

- **WHEN** two layouts select report ID 1 with `atLeast` 8 and `exactly` 10
- **THEN** the record is rejected and listed as a problem

#### Scenario: Unselected report

- **WHEN** a report arrives with an ID that no layout selects
- **THEN** the report is ignored and the controls keep their values

### Requirement: Half-axis usage binding

A `hidUsageMap` SHALL support the kind `HalfAxis`, which binds one `half` (`Positive` or `Negative`) of an element's range to `LeftTrigger` or `RightTrigger`, rescaled to 0 through 1.

#### Scenario: Combined trigger axis

- **WHEN** a map binds the positive half of Z to `LeftTrigger` and the negative half of Z to `RightTrigger`
- **THEN** a Z value at its maximum reads `LeftTrigger` 1 and `RightTrigger` 0, and a Z value at its minimum reads `LeftTrigger` 0 and `RightTrigger` 1

### Requirement: Axis-driven D-pad direction

A `hidUsageMap` SHALL support the kind `AxisDpad`, which presses a D-pad direction while the travel of one `half` is at or past a required `threshold` above 0 and below 1.

#### Scenario: Axis drives a D-pad direction

- **WHEN** a map binds the negative half of X to `DpadLeft` with `threshold` 0.5 and X travels 60% toward its minimum
- **THEN** `DpadLeft` is pressed

#### Scenario: Axis below threshold

- **WHEN** the same axis travels 40% toward its minimum
- **THEN** `DpadLeft` is not pressed

### Requirement: Axis-to-button usage binding

A `hidUsageMap` SHALL support the kind `AxisButton`, which presses a button control while the travel of one `half` is at or past a required `threshold`. A missing `threshold` SHALL be rejected.

#### Scenario: Missing threshold

- **WHEN** an `AxisButton` entry has no `threshold`
- **THEN** the record is rejected and listed as a problem

### Requirement: Button-to-trigger usage binding

A `hidUsageMap` SHALL support the kind `ButtonTrigger`, which reads `LeftTrigger` or `RightTrigger` as 1 while the element value is nonzero and 0 otherwise.

#### Scenario: Button drives a trigger

- **WHEN** a map binds Button 7 to `RightTrigger` and Button 7 is pressed
- **THEN** `RightTrigger` reads 1

### Requirement: Usage map uniqueness per half

A usage MAY appear in several `hidUsageMap` entries only when every entry is a `HalfAxis`, `AxisDpad` or `AxisButton` and no two entries name the same `half`. An `Axis`, `Button`, `Hat` or `ButtonTrigger` entry SHALL be the only entry of its usage.

#### Scenario: Both halves of one usage

- **WHEN** a map has a `HalfAxis` for the positive half and an `AxisDpad` for the negative half of the same usage
- **THEN** the map is accepted

#### Scenario: Same half twice

- **WHEN** a map has two entries for the positive half of one usage
- **THEN** the map is rejected and the problem names the usage and the half

#### Scenario: Whole axis and half axis

- **WHEN** a map has an `Axis` entry and a `HalfAxis` entry for the same usage
- **THEN** the map is rejected and listed as a problem

### Requirement: Swift validates input layouts

Swift SHALL decode and validate input layouts and usage maps. A repository tool in Python SHALL NOT re-implement these rules and SHALL read records only through Swift output. Generated records SHALL be regenerated, not edited.

#### Scenario: Regeneration after the conversion

- **WHEN** the authored inputs use `bitOffset` and `bitSize` and `./Scripts/ojd catalog regenerate --write` has run
- **THEN** `./Scripts/ojd catalog regenerate --check` exits 0 and the decoded frames of every converted record equal the recorded snapshots
