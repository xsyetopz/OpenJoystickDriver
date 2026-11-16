## ADDED Requirements

### Requirement: A Validation Leaves the Mac Only Through the User's Own Submission

OJD SHALL show the full validation text and its destination before anything leaves the Mac, and MUST send it only by opening a prefilled issue that the user submits in the browser.

#### Scenario: User validates a controller

- **WHEN** a guided check ends with every declared control responded and the user chooses Validate
- **THEN** OJD shows the validation text and `github.com/xsyetopz/OpenJoystickDriver` as its destination, and opens the `controller-validation.yml` form only after the user confirms

#### Scenario: Check with a failed control

- **WHEN** a guided check ends with a control not responded or another control moved
- **THEN** OJD offers Report a Problem and does not offer Validate

### Requirement: A Validation Holds Only the Facts It Needs

A validation SHALL hold the VID:PID, mode `id`, connection, record source, app version, macOS version, and per-control results, and MUST NOT hold a serial number, unit ID, Bluetooth address, user name, or file path.

#### Scenario: Controller with a serial number

- **WHEN** the validated controller reports a serial number
- **THEN** the validation text holds no serial number

### Requirement: A Record Mode With a Validation Is Community Verified

A record SHALL carry a `validations` list of issue number, mode `id`, app version, and date, and a mode with at least one validation MUST show "Community verified" in the supported-controllers list, the controller detail, and `ojd record show`.

#### Scenario: Accepted validation

- **WHEN** a record lists a validation for mode `xinput`
- **THEN** each surface shows that mode as community verified with a link to the issue

#### Scenario: Validation for a mode the record lacks

- **WHEN** a record lists a validation whose mode `id` names no mode of the record
- **THEN** the record reader refuses the record and names the key path

### Requirement: Lookup Opens the Controller's Entry

OJD SHALL offer Lookup for a connected controller, which MUST open its entry in the supported-controllers list, or a GitHub search for its VID:PID when no record exists.

#### Scenario: Controller with no record

- **WHEN** the user chooses Lookup for a controller with no record
- **THEN** the browser opens a GitHub search for its VID:PID

### Requirement: The App Declares the Data It Lets the User Submit

The app SHALL ship a privacy manifest with `NSPrivacyTracking` false and one collected data type, `NSPrivacyCollectedDataTypeOtherDiagnosticData`, linked, not tracking, for app functionality.

#### Scenario: Built app

- **WHEN** the release build is archived
- **THEN** its bundle holds `PrivacyInfo.xcprivacy` with that entry, and `plutil -lint` accepts it
