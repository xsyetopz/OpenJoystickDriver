## ADDED Requirements

### Requirement: Three personas

OJD SHALL provide three virtual personas as bundled `VirtualDevice` records: `Generic`, `SDLCompatible` and `GameControllerCompatible`.

#### Scenario: Generic record

- **WHEN** the `Generic` record is read
- **THEN** it has vendor `1209` and product `4A4F` and is a standard HID gamepad

#### Scenario: SDLCompatible record

- **WHEN** the `SDLCompatible` record is read
- **THEN** it has vendor `045E` and product `0B0C` and uses Xbox One GIP reports that SDL reads
- **AND** the ID is one that Apple's GameController framework does not bind on a virtual device

#### Scenario: GameControllerCompatible record

- **WHEN** the `GameControllerCompatible` record is read
- **THEN** it has vendor `045E` and product `0B13` and uses the Xbox Series Bluetooth report that Apple's GameController framework reads

### Requirement: Automatic persona selection

Automatic selection SHALL publish `SDLCompatible` when the controller's primary controls fit it and `Generic` otherwise, unless the user selects a persona. Automatic selection SHALL NOT publish `GameControllerCompatible`, because SDL reads its reports as GIP packets.

#### Scenario: Controls do not fit SDLCompatible

- **WHEN** a controller is served virtually, the user has set no persona and its primary controls do not fit `SDLCompatible`
- **THEN** the virtual device reports `1209:4A4F`

#### Scenario: Automatic selection skips GameControllerCompatible

- **WHEN** a controller is served virtually and the user has set no persona
- **THEN** the virtual device does not report `045E:0B13`

#### Scenario: Fresh install

- **WHEN** a controller is served virtually and the user has set no persona
- **THEN** the virtual device reports `045E:0B0C`

#### Scenario: Choose Generic

- **WHEN** the user runs `ojd virtual set generic <ref>`
- **THEN** the virtual device for that controller reports `1209:4A4F`

#### Scenario: Choose GameControllerCompatible

- **WHEN** the user runs `ojd virtual set game-controller-compatible <ref>`
- **THEN** the virtual device for that controller reports `045E:0B13` and GameController reads its input

### Requirement: No Microsoft id outside the Xbox personas

No code, record, sample, test fixture or HIDTool subcommand SHALL use a Microsoft vendor id except the `SDLCompatible` and `GameControllerCompatible` persona records and the seven granted extension IDs. The retired id `4F4A:4449` SHALL NOT remain as a live identity. The SDK sample SHALL use `1209:0001`, which pid.codes reserves for private testing, and no bundled record or persona SHALL use it.

#### Scenario: Scan

- **WHEN** the repository check scans for `045E` outside the allowed files
- **THEN** it finds none

### Requirement: SDLCompatible status

Documentation SHALL state that PCSX2 2.8.2 (SDL 3.4.12) and DuckStation (SDL 3.4.16) map `SDLCompatible` as an Xbox pad with default hints, and that Steam is untested.

#### Scenario: Documentation

- **WHEN** a reader opens the persona page
- **THEN** it states the SDL versions tested and that Steam is untested

### Requirement: Persona document

A `VirtualDevice` SHALL hold `layout`, `transport`, identity (`vendorID`, `productID`, `version`, `productName`, `manufacturer`) and `labels`, and `match` by model or port. Persona ids on the CLI are lowercase kebab-case forms of the enum values.

#### Scenario: Invalid persona id

- **WHEN** the user passes an unknown persona id
- **THEN** the CLI exits non-zero and lists the valid ids
