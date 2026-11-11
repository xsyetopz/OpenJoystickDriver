## ADDED Requirements

### Requirement: Activation Needs a User Action

OJD SHALL send a driver extension activation request only when the user asks for it: with the repair button, with `ojd transport-extension activate`, or by claiming a model that needs the extension. OJD MUST NOT send one at launch, at service start, or when a controller connects.

#### Scenario: First launch with no controller

- **WHEN** the user starts OJD on a Mac where the extension is not active
- **THEN** macOS shows no system extension prompt

#### Scenario: Controller that does not need the extension

- **WHEN** a controller served on the direct USB route or over HID connects
- **THEN** OJD sends no activation request

### Requirement: Banner Appears Only When a Connected Controller Needs the Extension

OJD SHALL show the Xbox USB driver banner only while a connected controller's route is the driver extension and the extension is not serving it.

#### Scenario: No Microsoft controller

- **WHEN** no connected controller needs the extension
- **THEN** the main window shows no Xbox USB driver banner, whatever the extension's state

#### Scenario: Claimed model with an inactive extension

- **WHEN** a connected controller's route is the extension and the extension is not active
- **THEN** the banner names that controller and offers the repair button

### Requirement: Repair Shows Progress

OJD SHALL show that a repair request is running from the click until macOS answers, and MUST disable the repair button for that time.

#### Scenario: Click on the repair button

- **WHEN** the user clicks the repair button
- **THEN** the banner shows a progress state and the button is disabled

### Requirement: Repair Shows the Result

OJD SHALL show a distinct state for each result of a repair request: done, waiting for the user's approval, cancelled, timed out, and failed.

#### Scenario: Approval needed

- **WHEN** macOS answers that the user must approve the extension
- **THEN** the banner says so and offers a button that opens the approval pane of System Settings

#### Scenario: Request succeeds

- **WHEN** macOS reports the extension active
- **THEN** the banner disappears

#### Scenario: Request times out

- **WHEN** macOS gives no answer within the limit
- **THEN** the banner says the request timed out and offers Try Again

### Requirement: Repair Shows the macOS Error

OJD SHALL show the error domain, code, and text that macOS returns for a failed repair request, with the next step for the user.

#### Scenario: macOS refuses the request

- **WHEN** the activation request fails with an error
- **THEN** the banner shows the error's domain, code, and text
- **AND** the text differs from the text shown before the click

### Requirement: No Button That Cannot Act

OJD SHALL show the repair button only in a state where a click sends a request. In any other state it MUST show the reason.

#### Scenario: App bundle without the extension

- **WHEN** the running app holds no embedded driver extension
- **THEN** the banner states that this build has no driver extension and shows no repair button

### Requirement: Command Reference Names the Real Command

The command reference SHALL document the driver extension commands under the name the command line accepts.

#### Scenario: Reference matches the command line

- **WHEN** a user runs each driver extension command exactly as `wiki/Command-Reference.md` prints it
- **THEN** the command line accepts it
