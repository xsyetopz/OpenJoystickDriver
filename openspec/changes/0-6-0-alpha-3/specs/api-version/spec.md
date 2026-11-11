## ADDED Requirements

### Requirement: Current API Version

OJD SHALL write `apiVersion: openjoystickdriver/v1alpha3` into every document it writes, and every bundled document MUST carry that version.

#### Scenario: Saved profile

- **WHEN** the user saves a profile
- **THEN** the stored file carries `openjoystickdriver/v1alpha3`

#### Scenario: Bundled data

- **WHEN** the repository check runs
- **THEN** it finds no bundled document with another `apiVersion`

### Requirement: Other Versions Are Refused

OJD SHALL refuse a document whose `apiVersion` is not `openjoystickdriver/v1alpha3` with error `E5001`. The error MUST name the file, the version found, and the migrate command.

#### Scenario: Stored alpha.2 file

- **WHEN** a reader opens a document that carries `openjoystickdriver/v1alpha2`
- **THEN** it fails with `E5001`, the file's path, the text `openjoystickdriver/v1alpha2`, and `ojd migrate`

#### Scenario: Document with no version

- **WHEN** a reader opens a document with no `apiVersion`
- **THEN** it fails with `E5001` and names the file

### Requirement: Schemas Are Published per Version

The schema files SHALL be published under `schemas/v1alpha3/`, and each schema's `$id` MUST point there.

#### Scenario: Schema identifier

- **WHEN** a client reads the `$id` of a schema file from this release
- **THEN** the `$id` contains `schemas/v1alpha3/`

### Requirement: The Update Path Is Documented

`CHANGELOG.md` SHALL list, under 0.6.0-alpha.3, each change that makes a `v1alpha2` document invalid, and MUST name `ojd migrate` as the way to convert.

#### Scenario: Reader with stored alpha.2 files

- **WHEN** a user reads the 0.6.0-alpha.3 section of `CHANGELOG.md`
- **THEN** it lists the format change, the removed properties, the patch `remove` list, and the migrate command
