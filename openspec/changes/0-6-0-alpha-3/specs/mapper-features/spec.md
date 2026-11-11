## ADDED Requirements

### Requirement: A Live View Is Drawn From the Controller's Record

OJD SHALL show a live view of a served controller that draws every control its record or its HID descriptor declares, laid out by the control's kind, with each control's value as the user operates it. The view MUST need no drawing made for one model.

#### Scenario: Bundled record

- **WHEN** the user opens the live view for a controller that any bundled record serves
- **THEN** the view shows each control the record declares, and a pressed button and a moved stick change in it

#### Scenario: Controller with no record

- **WHEN** OJD serves a controller by its HID descriptor
- **THEN** the view shows the controls the descriptor declares

### Requirement: Sticks and Triggers Have a Calibration View

OJD SHALL show, for each stick and trigger, the raw value, the value after tuning, and the dead zone, and MUST store a value the user sets there as tuning for that controller.

#### Scenario: Set a dead zone

- **WHEN** the user sets a stick's dead zone in the view
- **THEN** the drawn dead zone and the value after tuning follow it, and `ojd controller show` reports the same value

### Requirement: A Profile Template Fits Any Controller

OJD SHALL offer profile templates that bind controls by their standard names, so one template makes a profile for any served controller. A template MUST skip a binding whose control the controller lacks and MUST list each one it skipped.

#### Scenario: Template for a pad with every control

- **WHEN** the user creates a profile for a controller from a template
- **THEN** the profile holds each binding of the template

#### Scenario: Pad with no rear buttons

- **WHEN** the template binds a rear button and the controller has none
- **THEN** the profile lacks that binding and the sheet lists it as skipped

### Requirement: A Profile Converts to Another Controller Model

OJD SHALL convert a profile to another controller model, keeping each binding whose source control the target has. It MUST list each binding it left out, and MUST leave the original profile unchanged.

#### Scenario: Convert in the app

- **WHEN** the user converts a profile for one model to a second model that has every source control
- **THEN** a second profile for the second model holds every binding

#### Scenario: Convert from the command line

- **WHEN** the user runs the conversion command for a target that lacks one source control
- **THEN** the command writes the converted profile and names the binding it left out

### Requirement: Profiles Can Be Sorted and Annotated

The Profiles area SHALL sort the list by name, by controller, or by last use, and a binding MUST be able to hold a note the user writes.

#### Scenario: Note on a binding

- **WHEN** the user writes a note on a binding and saves the profile
- **THEN** the editor shows the note beside the binding the next time it opens

### Requirement: A Keyboard Shortcut Pauses and Resumes Every Controller

OJD SHALL let the user set one system-wide keyboard shortcut that pauses and resumes every controller. No shortcut MUST be set on a fresh installation.

#### Scenario: Shortcut pressed in a game

- **WHEN** the user presses the shortcut while another app is in front
- **THEN** every controller is paused, and a second press resumes them

### Requirement: An Idle Wireless Controller Can Disconnect

OJD SHALL offer a setting that disconnects a Bluetooth controller after a time with no input. The setting MUST be off on a fresh installation.

#### Scenario: Idle time passes

- **WHEN** the setting is 15 minutes and a Bluetooth controller sends no changed input for 15 minutes
- **THEN** OJD disconnects it

#### Scenario: Cable

- **WHEN** a controller is connected by cable
- **THEN** the setting does not apply to it

### Requirement: Bindings Cover the Common System Actions

A binding SHALL be able to open Launchpad, lock the screen, take a screenshot, show the desktop, and type a text the user enters.

#### Scenario: Screenshot

- **WHEN** a button is bound to the screenshot action and the user presses it
- **THEN** macOS takes a screenshot

#### Scenario: Type text

- **WHEN** a button is bound to a text and the user presses it in a text field
- **THEN** the field receives the text

### Requirement: The App Says What Changed After an Update

After an update, the first opening of the main window SHALL show the changes of the installed version from `CHANGELOG.md`, once.

#### Scenario: First open after an update

- **WHEN** the user opens the main window for the first time after an update
- **THEN** the window shows the changes of that version, and does not show them at the next opening
