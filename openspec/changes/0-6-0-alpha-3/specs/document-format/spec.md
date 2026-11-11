## ADDED Requirements

### Requirement: Stored Documents Are XML Property Lists

OJD SHALL store every document that carries `apiVersion` and `kind` as an XML property list in UTF-8 with the extension `.plist`. This covers bundled documents and every document in a user store or a package.

#### Scenario: Saved profile

- **WHEN** the user saves a profile in the app
- **THEN** the Profiles folder holds a `.plist` file that `plutil -lint` accepts

#### Scenario: Bundled data

- **WHEN** the repository check runs
- **THEN** every bundled document is an XML property list and no bundled document is a `.json` file

### Requirement: One Form per Document

OJD SHALL refuse a stored document in any other form with a named error that gives the file and the form found.

#### Scenario: Binary property list

- **WHEN** a store holds a document saved as a binary property list
- **THEN** the reader refuses it and the error names the file and says the file is binary

#### Scenario: JSON text in a `.plist` file

- **WHEN** a `.plist` file holds JSON text
- **THEN** the reader refuses it with the named error

### Requirement: One Schema for Bundled and User Documents

OJD SHALL check a user-written record, patch, or profile with the same schema and the same rules as a bundled one. The JSON Schema files MUST accept every bundled document, read from its property list.

#### Scenario: User record

- **WHEN** a user copies a bundled record into `Controllers/` and changes one control
- **THEN** OJD loads it with no other change to the file

#### Scenario: Schema check of bundled data

- **WHEN** `just check-schemas` runs
- **THEN** it reads each bundled property list and validates it against the schema for its kind

### Requirement: Only Schema Types Are Accepted

OJD SHALL refuse a document that holds a property-list `date` or `data` value, and the error MUST name the key path.

#### Scenario: Date value

- **WHEN** a record holds a `date` value under any key
- **THEN** the reader refuses the record and names that key path

### Requirement: Number Types Are Kept

OJD SHALL keep integers as integers and reals as reals when it reads and writes a document, across the full signed and unsigned 64-bit range.

#### Scenario: Rewrite of a document

- **WHEN** OJD reads a document and writes it back unchanged
- **THEN** every integer in the file is an `integer` element and every real is a `real` element, with equal values

### Requirement: Written Files Are Canonical

OJD SHALL write a document with sorted keys in the form `PropertyListSerialization` produces. Every bundled document MUST equal its own canonical form.

#### Scenario: Stable difference

- **WHEN** OJD reads a canonical document and writes it back unchanged
- **THEN** the file's bytes are identical

#### Scenario: Bundled file with a comment

- **WHEN** a bundled document holds an XML comment
- **THEN** the repository check fails and names the file

### Requirement: A Patch Removes Keys Through a Remove List

A patch document SHALL delete keys of a record through `remove`, a list of dotted key paths. OJD MUST apply `remove` before it merges `patch`, and MUST refuse a path that names no property of the record schema.

#### Scenario: Remove a section

- **WHEN** a patch holds `remove` with the path `tuning`
- **THEN** the patched record has no `tuning` section

#### Scenario: Remove then set

- **WHEN** a patch removes `input.rumble` and its `patch` sets `input.rumble` to a full value
- **THEN** the patched record holds only the value from `patch`

#### Scenario: Path the record does not hold

- **WHEN** a patch removes a valid path that the record does not hold
- **THEN** the patch applies and the record is unchanged at that path

#### Scenario: Path with a wrong name

- **WHEN** a patch removes `tunning`
- **THEN** OJD refuses the patch and names the path

### Requirement: A Patch Changes One Mode by Its Identifier

A patch SHALL merge each entry of `patch.modes` into the record's mode with the same `id`, MUST add an entry whose `id` the record does not hold, and MUST remove a mode through the `remove` path `modes.<id>`. Every other array in `patch` replaces the whole array.

#### Scenario: Change one mode

- **WHEN** a patch holds one `modes` entry with the `id` of a mode of the record and one changed endpoint
- **THEN** the patched record holds every mode of the record, and that mode differs only in the endpoint

#### Scenario: Add a mode

- **WHEN** a patch holds a `modes` entry with an `id` the record does not hold
- **THEN** the patched record holds the record's modes and the added mode

#### Scenario: Remove a mode

- **WHEN** a patch removes `modes.wired`
- **THEN** the patched record has no mode with the `id` `wired`

#### Scenario: Migration of a patch that replaces the modes

- **WHEN** `ojd migrate` converts a `v1alpha2` patch whose `patch` holds `modes`
- **THEN** the converted patch holds the path `modes` in `remove`, and the patched record holds only the modes the patch lists

### Requirement: A Patch Reaches Every Section of a Record

A patch SHALL be able to set and remove every property of a record other than its identity, `capabilities` included. OJD MUST check the patched record by the rules of a record.

#### Scenario: Capability removed by a patch

- **WHEN** a patch removes `capabilities.rumble` and adds a mode
- **THEN** OJD applies the patch and checks the result as a record

#### Scenario: Identity

- **WHEN** a patch sets `vendorID`
- **THEN** OJD refuses the patch and names the path

### Requirement: An Absent Crosswalk Key Means No Equivalent

The crosswalk SHALL state that a control has no equivalent in a standard by leaving that standard's key out.

#### Scenario: Control with no W3C equivalent

- **WHEN** a control has no equivalent in the W3C mapping
- **THEN** its crosswalk entry has no `w3c` key
- **AND** a lookup for that control in that standard returns no equivalent

### Requirement: Messages Stay JSON

OJD SHALL keep `--json` command output, the local endpoint, and report files as JSON.

#### Scenario: Command output

- **WHEN** the user runs `ojd controller list --json`
- **THEN** the output is JSON that the published command output schema accepts

### Requirement: The Wiki Describes the Format

`wiki/Controller-Records.md` and `wiki/Writing-Controller-Mods.md` SHALL show every example as an XML property list, and MUST show how to convert between JSON and a property list with `plutil`.

#### Scenario: Example in the wiki

- **WHEN** a reader copies a record example from the wiki into `Controllers/`
- **THEN** OJD loads it
