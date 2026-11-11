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

### Requirement: A Document Refusal Names the Key Path, the Rule, and the Fix

OJD SHALL report each refusal of a record, patch, or package with the file, the key path, the rule the value breaks, and what to change, in the user's language. Each distinct rule MUST have its own message.

#### Scenario: Capability the mode's driver does not declare

- **WHEN** a user record gives a mode a capability that the mode's driver does not declare
- **THEN** the message names the file, the key path of that capability, and the rule, and says which capabilities that driver accepts

#### Scenario: Language other than English

- **WHEN** the user's language is German and a record is refused
- **THEN** the sentence around the key path is German
