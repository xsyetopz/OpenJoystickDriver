## ADDED Requirements

### Requirement: Package manifest lists

`mod.json` MUST list the package files by document kind in `controllers`, `patches`, `profiles` and `virtualDevices`, and MUST list at least one file.
`controllers` names `Controller` files and `patches` names `ControllerPatch` files, both in `Controllers/`; `profiles` names `Profile` files in `Profiles/`; `virtualDevices` names `VirtualDevice` files in `VirtualDevices/`.

#### Scenario: Sample package lists

- **WHEN** `ojd mod validate docs/sdk/sample --json` runs
- **THEN** the package is accepted with its `controllers`, `profiles` and `virtualDevices` files

#### Scenario: Unknown list names

- **WHEN** `ojd mod validate FOLDER` reads a `mod.json` with `records` or `personas`
- **THEN** the command exits non-zero and names E4001

#### Scenario: File kind does not match the list

- **WHEN** a `Controller` file is listed under `patches`, or a `ControllerPatch` file under `controllers`
- **THEN** the command exits non-zero, names E4003, and says which kind the file holds and which list names it

### Requirement: Package files carry a header

`mod.json` and every file that it lists MUST carry `apiVersion` and `kind`: `mod.json` has `apiVersion: openjoystickdriver/v1alpha2` and `kind: ModPackage`, and a listed file has the `kind` of its document.
A missing or unsupported `apiVersion` MUST be refused with E5001, any other invalid `mod.json` with E4001, and any other invalid listed file with E4003.

#### Scenario: Unsupported apiVersion

- **WHEN** `ojd mod validate FOLDER` reads a package whose `mod.json` or a listed file has an unsupported `apiVersion`
- **THEN** the command exits non-zero and names E5001

#### Scenario: Wrong manifest kind

- **WHEN** `ojd mod validate FOLDER` reads a package whose `mod.json` has the supported `apiVersion` and a `kind` other than `ModPackage`
- **THEN** the command exits non-zero and names E4001

### Requirement: Snapshot requires the package profile list

`ApplicationServiceRemappingSnapshotPayload` MUST carry `packageProfiles`, a list of `{profileID, package}`, and a payload without the key MUST fail to decode.

#### Scenario: Snapshot with a package profile

- **WHEN** a package profile is served
- **THEN** the remapping snapshot lists `{profileID, package}` for it

#### Scenario: Payload without the key is refused

- **WHEN** a snapshot payload without `packageProfiles` is decoded
- **THEN** decoding fails

## MODIFIED Requirements

### Requirement: REQ-6 `ojd mod validate`

`ojd mod validate FOLDER` MUST check a package folder with `ModPackageStore.validate` and report the result as JSON with `--json`, exiting non-zero with the package's E4xxx code, or E5001 for an unsupported `apiVersion`, when the package is refused.

#### Scenario: Valid package

- **WHEN** the user runs `ojd mod validate FOLDER --json` on a valid package
- **THEN** the command prints the validation result as JSON and exits 0

#### Scenario: Refused package

- **WHEN** the package is refused
- **THEN** the command exits non-zero and names the package's E4xxx code, or E5001 for an unsupported `apiVersion`

### Requirement: REQ-10 Mod output envelopes

Each `ojd mod` command MUST print the `apiVersion`/`kind` envelope with `apiVersion: openjoystickdriver/v1alpha2`, and `Resources/Schemas/cli-output.schema.json` MUST have one `$defs` entry per `ojd mod` command path.

#### Scenario: JSON output matches the schema

- **WHEN** any `ojd mod` command runs with `--json`
- **THEN** its output has the `apiVersion`/`kind` envelope and validates against that command's `$defs` entry

## REMOVED Requirements

### Requirement: REQ-4 Snapshot lists package profiles
