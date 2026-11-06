## MODIFIED Requirements

### Requirement: REQ-13 Sample package

`docs/sdk/sample/` MUST hold a package that `ojd mod validate` accepts, with at least one controller record, one profile, and one virtual device, all for the pid.codes test ID `1209:0001`, and `swift test` MUST validate it and run `ojd record test` on its record.
Every file of the package MUST validate against the `v1alpha2` schemas, and `./Scripts/ojd check schemas` MUST cover `docs/sdk/sample/**`.

#### Scenario: Validate the sample

- **WHEN** `swift test` runs `ojd mod validate docs/sdk/sample --json`
- **THEN** the package is accepted
- **AND** `ojd record test` passes on its record

#### Scenario: Schema check

- **WHEN** `./Scripts/ojd check schemas` runs
- **THEN** it validates `mod.json` and each file in `Controllers/`, `Profiles/` and `VirtualDevices/` of the sample against its schema

### Requirement: REQ-14 Mod documentation

`wiki/Writing-Controller-Mods.md` MUST state first that the USB extension's product list is Apple-signed and cannot be extended, and `wiki/Command-Line.md`, `wiki/Command-Reference.md`, `wiki/Controller-Records.md`, and `wiki/_Sidebar.md` MUST describe what ships, including that a record can describe modes, probes and input layouts, so that a clone or a controller that no record covers needs no source change.

#### Scenario: Reader opens the mod page

- **WHEN** a reader opens `wiki/Writing-Controller-Mods.md`
- **THEN** its first statement says the USB extension's product list is Apple-signed and cannot be extended
