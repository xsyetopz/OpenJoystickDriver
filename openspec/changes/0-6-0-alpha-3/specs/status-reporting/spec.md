## ADDED Requirements

### Requirement: Input Test Reports Activity Only After a Control Changes

Input Test SHALL show "Input active" only after a control of the controller leaves its rest value in the session. Before that, it MUST say that it waits for the user to press a control.

#### Scenario: Reports with every control at rest

- **WHEN** a controller sends input reports in which every control is at rest
- **THEN** Input Test shows that it waits for a press and does not show "Input active"

#### Scenario: First press

- **WHEN** the user presses a button
- **THEN** Input Test shows "Input active"

### Requirement: Every Reason a Controller Is Not Served Has a Sentence and a Next Step

OJD SHALL hold, for each reason it can give for not serving a connected controller, a localized sentence and a next step. The controller detail and `ojd controller show` MUST show both.

#### Scenario: Record that does not fit the device's interfaces

- **WHEN** a connected controller has a record and none of the record's modes fits the interfaces the device exposes
- **THEN** the controller detail says that the record does not fit this device and offers to draft a record from the device
- **AND** `ojd controller show` prints the same sentence and the draft command

#### Scenario: Reason with no text

- **WHEN** the source holds a reason that has no sentence in a language
- **THEN** the repository check fails and names the reason and the language

### Requirement: The User Sees and Controls What Holds a Controller

OJD SHALL list, for each connected controller, every process that has the controller's HID device or USB interface open, by process ID and name, and SHALL say whether OJD's own open is exclusive. `ojd controller show`, `ojd controller list --json`, and the controller detail MUST show the same holders and the same exclusive state, and suspend and resume MUST be reachable from the CLI and from the controller detail.

#### Scenario: Another app has the controller open

- **WHEN** Google Chrome has a user client on a connected controller's HID device
- **THEN** `ojd controller show` lists Google Chrome with its process ID
- **AND** the controller detail lists the same process

#### Scenario: OJD holds the controller exclusively

- **WHEN** OJD serves a controller through an exclusive open
- **THEN** `ojd controller show` and the controller detail say that OJD holds it exclusively and that another app can open it after the user suspends it
- **AND** the controller detail offers Suspend beside that sentence

#### Scenario: Suspended controller

- **WHEN** the user suspends a controller from either surface
- **THEN** both surfaces stop listing OJD as an exclusive holder and offer Resume

### Requirement: A Guided Check Builds the Controller Report

OJD SHALL offer a Guided Check in Input Test and as `ojd controller check`, which asks for each control the controller declares in turn, records whether it responded, another control moved, or the user skipped it, and MUST end in one report that the user saves, copies, or opens as a prefilled GitHub issue, with nothing sent by OJD.

#### Scenario: Every control responds

- **WHEN** the user presses or moves each control as asked
- **THEN** the report lists each control as responded

#### Scenario: Wrong control moves

- **WHEN** the step asks for A and the controller reports B
- **THEN** the report lists A with B named as the control that moved

#### Scenario: Open as an issue

- **WHEN** the user chooses to open the report as an issue
- **THEN** OJD saves the report as a file, reveals it, and opens the issue form in the browser with the short fields filled, and the URL holds no report body

### Requirement: A Document Refusal Names the Key Path, the Rule, and the Fix

OJD SHALL report each refusal of a record, patch, or package with the file, the key path, the rule the value breaks, and what to change, in the user's language. Each distinct rule MUST have its own message.

#### Scenario: Capability the mode's driver does not declare

- **WHEN** a user record gives a mode a capability that the mode's driver does not declare
- **THEN** the message names the file, the key path of that capability, and the rule, and says which capabilities that driver accepts

#### Scenario: Language other than English

- **WHEN** the user's language is German and a record is refused
- **THEN** the sentence around the key path is German
