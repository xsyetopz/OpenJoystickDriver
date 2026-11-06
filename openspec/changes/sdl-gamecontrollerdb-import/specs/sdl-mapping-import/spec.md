## ADDED Requirements

### Requirement: Pinned database shipped as data

OpenJoystickDriver SHALL ship SDL_GameControllerDB as generated data, reduced to `platform:Mac OS X` lines, from a revision and SHA-256 pinned in `ControllerSources.lock.json`. The shipped file SHALL keep the upstream zlib license text, and `THIRD_PARTY_NOTICES.md` SHALL name the upstream repository, the pinned revision and the license. The generated file SHALL NOT be edited by hand.

#### Scenario: Regeneration check

- **WHEN** `./Scripts/ojd catalog regenerate --check` runs on a clean tree
- **THEN** it exits 0, including the database resource

#### Scenario: Hash mismatch

- **WHEN** the downloaded database does not match the pinned SHA-256
- **THEN** generation fails and writes nothing

#### Scenario: Attribution

- **WHEN** the shipped database resource is read
- **THEN** it starts with the upstream license header

### Requirement: Lines for protocol-family pads are skipped

The generated database SHALL NOT contain a line whose vendor and product belong to a pad that OpenJoystickDriver drives with a protocol family or that SDL drives through HIDAPI, and generation SHALL report how many lines it skipped for each reason.

#### Scenario: Controller list pad

- **WHEN** a Mac line names a vendor and product that appear in the pinned SDL controller list
- **THEN** the line is not in the shipped database and the skip count includes it

### Requirement: Conversion at connect

When a HID pad with no controller record connects and its report descriptor passes the HID descriptor contract, OpenJoystickDriver SHALL look for a database line by the pad's SDL GUID (bus, CRC16 of the name, vendor, product, version) and, on a match, SHALL convert the line against the pad's live element list into a usage map that drives the pad.

#### Scenario: Matching line

- **WHEN** an unrecorded pad connects and the database has a Mac line for its GUID
- **THEN** the pad is driven by the converted usage map and its controls follow the line

#### Scenario: Exact tier first

- **WHEN** the database has a line for the exact GUID and another for the GUID with a zero name CRC
- **THEN** the exact line is used and the match tier is reported as `ExactGUID`

#### Scenario: Name-independent tier

- **WHEN** only a line with a zero name CRC matches
- **THEN** that line is used and the match tier is reported as `GUIDWithoutNameCRC`

#### Scenario: GUID with no match

- **WHEN** an unrecorded pad connects and the database has no line for its GUID
- **THEN** the pad keeps the standard HID usage map and its mapping source is reported as `StandardHIDUsageMap`

#### Scenario: Version-independent tiers

- **WHEN** no line matches the version
- **THEN** a line with the exact CRC and no version matches as `GUIDWithoutVersion`, else a line with no version and a zero name CRC matches as `GUIDWithoutVersionAndNameCRC`

#### Scenario: Duplicate GUID

- **WHEN** the database holds two lines with the same GUID
- **THEN** the last one is used

#### Scenario: Descriptor rejected

- **WHEN** the pad's descriptor fails the HID descriptor contract and the database has a line for it
- **THEN** the pad stays unbound and the unbound entry says a database line exists

### Requirement: SDL element order

The conversion SHALL index database fields against three lists built from the live element list: axes, hats and buttons. Each list SHALL be sorted ascending by usage number, ties SHALL keep arrival order, and an element that repeats a listed cookie SHALL be dropped.

#### Scenario: Duplicate cookie

- **WHEN** the element list holds two elements with the same cookie
- **THEN** only the first is listed and the indexes of later elements do not shift

#### Scenario: Tie in usage number

- **WHEN** two axes have the same usage number
- **THEN** they keep the order in which the element list delivered them

### Requirement: SDL list membership

The axes list SHALL hold Generic Desktop X, Y, Z, Rx, Ry, Rz, Slider, Dial and Wheel and Simulation Rudder, Throttle, Accelerator and Brake. The buttons list SHALL hold the Button page, then the Consumer page, then Generic Desktop D-pad, Start, Select and System Main Menu.

#### Scenario: Consumer page button

- **WHEN** a pad has 10 Button-page buttons and one Consumer-page button
- **THEN** the Consumer-page button is `b10`

#### Scenario: Line with half axes

- **WHEN** a line maps `lefttrigger:+a2` and `righttrigger:-a2`
- **THEN** the third listed axis drives `LeftTrigger` from its positive half and `RightTrigger` from its negative half

### Requirement: Fields that cannot be mapped are named

A database field that the conversion cannot express SHALL be listed by name as unmapped, and the remaining fields SHALL still apply. A line that indexes an element the pad does not have SHALL be rejected whole, the pad SHALL keep the standard HID usage map, and the rejection SHALL be reported with its reason.

#### Scenario: Unmapped control

- **WHEN** a line maps a control that OpenJoystickDriver has no id for
- **THEN** that control is listed as unmapped and the other controls work

#### Scenario: Index past the list

- **WHEN** a line names `b14` and the pad has 12 listed buttons
- **THEN** the line is rejected, the pad uses the standard HID usage map, and the report shows the rejection reason

#### Scenario: D-pad direction on a button

- **WHEN** a line maps `dpup:b3`
- **THEN** `dpup` is listed as unmapped and the other controls work

### Requirement: Mapping source is named

`ojd status`, `ojd diagnose`, `ojd controller show` and the app SHALL say where a HID pad's input mapping comes from: `Record`, `SDLGameControllerDB` or `StandardHIDUsageMap`. For `SDLGameControllerDB` they SHALL show the text "mapped from SDL_GameControllerDB", the GUID, the match tier and the unmapped controls. `ojd controller show --json` SHALL carry the same facts in `inputMapping` and SHALL leave `record` absent for a pad with no record.

#### Scenario: Show a mapped pad

- **WHEN** a pad driven by a database line is shown with `ojd controller show`
- **THEN** the Input mapping row reads "mapped from SDL_GameControllerDB" with the GUID and the match tier

#### Scenario: Show a pad with the standard map

- **WHEN** an unrecorded pad with no matching line is shown
- **THEN** the Input mapping row reads "standard HID usage map"

#### Scenario: JSON output

- **WHEN** `ojd controller show CONTROLLER --json` runs for a database-mapped pad
- **THEN** `inputMapping.source` is `SDLGameControllerDB`, `inputMapping` has `guid`, `match` and `unmapped`, and `record` is absent

### Requirement: A record ignores the database

A pad with a controller record from the catalog, a package or the user SHALL NOT consult the database.

#### Scenario: Pad with a record

- **WHEN** a pad with a user record connects and the database has a line for its GUID
- **THEN** the record drives the pad and the Input mapping row reads `Record`

### Requirement: Saving the converted mapping

`ojd record draft CONTROLLER --from-sdl` SHALL write the converted mapping as a controller record with a usage map, and SHALL fail with a named error when the pad has no matching line, when the line does not convert, or when the model already has a record. A rejected line SHALL be reported under error code `E5008` by this command and by `ojd diagnose`. The record SHALL carry no mark of its origin.

#### Scenario: Save and reuse

- **WHEN** a user saves the converted mapping as a record and reconnects the pad
- **THEN** the Input mapping row reads `Record`

#### Scenario: No line to save

- **WHEN** the command runs for a pad with no matching line
- **THEN** it exits with an error that says no database line matched

#### Scenario: Line that does not convert

- **WHEN** the command runs for a pad whose matching line indexes an element the pad lacks
- **THEN** it exits with error `E5008` and the reason, and writes no record

#### Scenario: Model with a record

- **WHEN** the command runs for a model that has a bundled record
- **THEN** it exits with an error that says the model has a record, and writes no record
