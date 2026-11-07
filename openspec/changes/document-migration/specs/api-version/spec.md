## MODIFIED Requirements

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
