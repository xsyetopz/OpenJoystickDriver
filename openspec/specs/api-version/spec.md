# api-version Specification

## Purpose
TBD - created by archiving change api-version-v1alpha2. Update Purpose after archive.

## Requirements

### Requirement: Current API Version

`OpenJoystickDriverAPI.version` SHALL be `openjoystickdriver/v1alpha2`, and every schema `$id` SHALL start with `https://xsyetopz.github.io/OpenJoystickDriver/schemas/v1alpha2/`. Every document OJD writes or prints SHALL carry that `apiVersion`.

#### Scenario: Schema Agrees with the Constant

- **WHEN** the schema tests read `Resources/Schemas/*.schema.json`
- **THEN** each `$id` starts with the `v1alpha2` base and each `apiVersion` const is `openjoystickdriver/v1alpha2`

#### Scenario: Written Document

- **WHEN** `ojd profile export` writes a profile
- **THEN** the file's `apiVersion` is `openjoystickdriver/v1alpha2`

### Requirement: Stored alpha.1 Files Are Refused

A stored document with `apiVersion: openjoystickdriver/v1alpha1` SHALL be refused with `E5001`, a
message that names both versions, and the file left unchanged. A reader SHALL NOT read, rewrite or
migrate it; `ojd migrate` converts it.

#### Scenario: Alpha.1 Profile

- **WHEN** `ojd profile validate` reads a profile whose `apiVersion` is `openjoystickdriver/v1alpha1`
- **THEN** it exits with code 1 and `E5001`, and the message names `openjoystickdriver/v1alpha1`

#### Scenario: Alpha.1 Settings at Launch

- **WHEN** the app starts with a `v1alpha1` `Settings.json`
- **THEN** it shows the refused-settings alert and leaves the file in place until the user chooses

### Requirement: Update Path Is Documented

The wiki SHALL have a page that lists each kind of stored file refused after the update, what OJD shows for it, and the step that brings it back. The CHANGELOG entry SHALL link the page.

#### Scenario: Tester Reads the Release Notes

- **WHEN** a tester opens the 0.6.0-alpha.2 CHANGELOG entry
- **THEN** it marks the version change **BREAKING** and links the update page
