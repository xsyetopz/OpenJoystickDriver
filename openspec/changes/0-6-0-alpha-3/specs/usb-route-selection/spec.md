## ADDED Requirements

### Requirement: An Unowned Microsoft Model Uses the Direct Route

OJD SHALL serve a Microsoft GIP controller on the direct USB route when no driver owns its GIP interface.

#### Scenario: Model with no Apple driver

- **WHEN** an Xbox One controller `045E:02D1` connects and OJD's driver extension is not active
- **THEN** OJD opens the GIP interface on the direct route and publishes input

#### Scenario: Extension never installed

- **WHEN** the user has never activated the driver extension and connects a model that no driver owns
- **THEN** the controller works and OJD shows no driver prompt

### Requirement: The Extension Route Needs an Active Extension

OJD SHALL select the driver extension route for a controller only when OJD's extension is active and owns that controller's interface.

#### Scenario: Extension active and matched

- **WHEN** OJD's extension is active and has matched the connected controller
- **THEN** `ojd controller show` reports the driver extension route

#### Scenario: Extension inactive

- **WHEN** OJD's extension is not active
- **THEN** OJD selects the extension route for no controller

### Requirement: A Model Apple's Driver Holds Is Shown as Served by macOS

OJD SHALL list a connected controller whose interface Apple's driver owns as served by macOS, and MUST offer the claim action for it.

#### Scenario: Xbox Series controller without OJD's extension

- **WHEN** an Xbox Series controller `045E:0B12` connects and Apple's driver owns it
- **THEN** the controller row reads "Served by macOS" and offers Claim
- **AND** OJD opens no session for it

### Requirement: Claim and Release Move a Model Between Owners

OJD SHALL take a model Apple's driver holds when the user claims it, by requesting the driver extension, and SHALL give it back to macOS when the user releases it.

#### Scenario: Claim

- **WHEN** the user runs `ojd controller claim` for a model Apple's driver holds and approves the extension
- **THEN** OJD serves that model through the extension after the controller reconnects

#### Scenario: Release

- **WHEN** the user runs `ojd controller release` for a claimed model
- **THEN** macOS serves that model after the controller reconnects

### Requirement: Route Policy Is Documented

`docs/development/apple-controller-ownership.md` SHALL state which models Apple's driver holds, which route serves each Microsoft model, and what the driver extension is for.

#### Scenario: Reader asks why a driver exists

- **WHEN** a reader opens the ownership document
- **THEN** it names the models Apple's driver holds on the tested macOS version and says the extension exists to take those models
