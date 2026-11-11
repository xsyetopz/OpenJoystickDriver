## ADDED Requirements

### Requirement: One Setting Chooses Simple or Advanced

OJD SHALL offer one setting, "Interface", as a pop-up button with the options "Simple" and "Advanced" in the General pane of Settings and as two items of the View menu. A fresh installation MUST start in Simple.

#### Scenario: Fresh installation

- **WHEN** the user opens OJD for the first time
- **THEN** the interface is in Simple

#### Scenario: Update from 0.6.0-alpha.2

- **WHEN** migration converts a settings document that 0.6.0-alpha.2 wrote
- **THEN** the interface is in Advanced, so no control the user had is hidden

#### Scenario: Switch the level

- **WHEN** the user chooses "Advanced" from the pop-up button
- **THEN** every open window shows its Advanced controls without a restart
- **AND** the View menu shows the checkmark on "Advanced"

### Requirement: Simple Shows What Connecting and Playing Need

Simple SHALL show the controller list, each controller's state and its one next step, the profile choice, Test Input, and the permission steps. Advanced MUST add the virtual gamepad kind, the choice of who serves a controller, tuning, identifiers, records and patches, and the activity log.

#### Scenario: Controller detail in Simple

- **WHEN** the user opens a controller's detail in Simple
- **THEN** it shows no virtual gamepad kind, no choice of who serves the controller, and no vendor or product identifier

#### Scenario: Controller detail in Advanced

- **WHEN** the user opens the same detail in Advanced
- **THEN** it shows each of those controls

### Requirement: The Level Hides Controls and Changes No Behavior

The level SHALL change only which controls a window shows. A value set in Advanced MUST stay in force in Simple, and the service MUST NOT read the level.

#### Scenario: Value set in Advanced

- **WHEN** the user sets a virtual gamepad kind in Advanced and switches to Simple
- **THEN** the controller keeps that kind

#### Scenario: Command line

- **WHEN** the user runs any `ojd` command
- **THEN** its output is the same in both levels

### Requirement: Simple Shows That a Hidden Setting Is Changed

A view in Simple SHALL show one row when a control it hides holds a value other than its default. The row MUST state the count and offer to show the controls.

#### Scenario: Hidden value differs

- **WHEN** a controller has a virtual gamepad kind set by the user and the interface is in Simple
- **THEN** the controller's detail shows a row that reads that 1 advanced setting is changed, with a button that switches to Advanced

#### Scenario: All defaults

- **WHEN** every hidden control of a view holds its default
- **THEN** the view shows no such row

### Requirement: Developer Tools Are a Switch Inside Advanced

OJD SHALL show packet streams, raw reports, and contributor diagnostics only when the interface is in Advanced and the developer switch is on.

#### Scenario: Simple with the developer switch stored as on

- **WHEN** the interface is in Simple
- **THEN** no window shows a developer tool
