## ADDED Requirements

### Requirement: Every document carries apiVersion and kind

Every OJD-owned persisted or wire document SHALL carry `apiVersion: openjoystickdriver/v1alpha2` and a `kind`. This covers Controller, ControllerPatch, Profile, VirtualDevice, ModPackage, ErrorCatalog, AccessGrants, Settings, SupportDiagnostic data, CLI output and endpoint messages.

#### Scenario: Missing header

- **WHEN** the loader reads a file with no `apiVersion`
- **THEN** it rejects the file with an error that names the file and says no `apiVersion` was found

#### Scenario: Wrong kind

- **WHEN** a Profile document sits in the controllers folder
- **THEN** the loader rejects it with "expected Controller, found Profile"

### Requirement: Unknown version is rejected, never upgraded

A document whose `apiVersion` is not supported SHALL be rejected with a dedicated error code that names the found and supported versions. OJD SHALL NOT upgrade, alias or migrate documents, and SHALL NOT ship `ojd migrate`.

#### Scenario: 0.5.x file

- **WHEN** a 0.5.x profile is loaded
- **THEN** it is rejected and the file is left unchanged

### Requirement: Flat schema files with hosted ids

Schema sources SHALL be flat files `Resources/Schemas/<kind>.schema.json` with the version written inside each file. Each `$id` SHALL be `https://xsyetopz.github.io/OpenJoystickDriver/schemas/v1alpha2/<kind>.schema.json`. Instances SHALL NOT carry `$schema`. Schemas SHALL NOT be fetched at run time.

#### Scenario: No version folder

- **WHEN** `Resources/Schemas/` is listed
- **THEN** it has no `v1beta1` or `v1alpha2` directory

### Requirement: Single version constant

The version string SHALL come from one Swift constant, which Python tooling reads through `OJDRepositoryTool facts`, and a test SHALL assert it equals every schema's `apiVersion` const.

#### Scenario: Drift

- **WHEN** one schema holds a different version
- **THEN** the test fails

### Requirement: Value formats

Field names SHALL be lowerCamelCase, enum values UpperCamelCase, CLI argument values lowercase kebab-case mapped one to one, and raw bytes uppercase hex pairs with single spaces.

#### Scenario: CLI mapping

- **WHEN** the CLI receives `sdl-compatible`
- **THEN** it maps to `SDLCompatible` in documents

### Requirement: Validation coverage

`./Scripts/ojd check schemas` SHALL validate generated records, authored inputs, `docs/sdk/sample/**`, profile fixtures, access-grant fixtures, the error catalog and a live support report.

#### Scenario: Sample drift

- **WHEN** a sample document breaks its schema
- **THEN** the check fails
