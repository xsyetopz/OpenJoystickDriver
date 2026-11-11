## ADDED Requirements

### Requirement: The Menu Bar Item Has a Stated Purpose

The menu bar item SHALL do five things: show the state of each connected controller, choose a controller's profile, pause or resume a controller, open the window or Settings, and quit. The menu MUST hold no command outside these five and the problem row.

#### Scenario: Menu with one controller and no problem

- **WHEN** the user opens the menu with one controller connected and no problem
- **THEN** the menu holds, in order, the controller's row, "Open OpenJoystickDriver", "Settings...", and "Quit OpenJoystickDriver"

#### Scenario: Help commands

- **WHEN** the user opens the menu
- **THEN** it holds no "Activity Log", "Explain Error Code...", "Report Problem...", or "Project Website" item
- **AND** the Help menu of the main menu holds each of them

### Requirement: The Icon Shows a Problem by Its Shape

The menu bar icon SHALL change its shape while a problem needs the user's action, and MUST NOT signal a problem by color alone. A state with no controller connected MUST NOT count as a problem.

#### Scenario: Missing permission

- **WHEN** a permission OJD needs is missing
- **THEN** the icon differs in shape from the icon of the ready state

#### Scenario: No controller connected

- **WHEN** OJD is ready and no controller is connected
- **THEN** the icon equals the icon of the ready state

### Requirement: A Problem Row Names the Problem and Opens Its Fix

The menu SHALL show one row for each problem that needs the user's action. The row MUST name the problem in its title, and choosing it MUST open the place that fixes it.

#### Scenario: Missing permission

- **WHEN** the Input Monitoring permission is missing and the user opens the menu
- **THEN** the first row names Input Monitoring, and choosing it opens the Access area at that permission

#### Scenario: Service not running

- **WHEN** the app cannot reach the service
- **THEN** the first row says that the service is not running and offers to start it
- **AND** the menu shows no "Needs attention" text without a named problem

#### Scenario: No problem

- **WHEN** no problem needs the user's action
- **THEN** the menu holds no problem row

### Requirement: Each Connected Controller Is a Top-Level Row

The menu SHALL list each connected controller as a row of the menu itself. The row MUST show the controller's name, its battery level when the controller reports one, and the profile in force.

#### Scenario: Two controllers

- **WHEN** two controllers are connected, one with a battery level and a profile
- **THEN** the menu holds two controller rows, and the first shows its name, its battery level, and the profile's name

#### Scenario: Paused controller

- **WHEN** a controller is paused
- **THEN** its row says so

#### Scenario: No controller

- **WHEN** no controller is connected
- **THEN** the menu holds one unavailable row that reads "No Controller Connected"

### Requirement: The Menu Has at Most Two Levels

A controller row SHALL open one submenu, and no item of that submenu MUST open a further submenu.

#### Scenario: Controller submenu

- **WHEN** the user opens a controller's submenu
- **THEN** it holds the profile list, "Pause" or "Resume", "Test Input", "Show in Window", and, for a wireless controller, "Disconnect"
- **AND** no item in it opens a submenu

### Requirement: One Checkmarked List Chooses the Profile

The controller's submenu SHALL list the profiles that fit the controller, with a checkmark on the profile in force and a "No Profile" item. Choosing an item MUST put it in force. The menu MUST hold no separate "Activate" and "Deactivate" lists.

#### Scenario: Switch the profile

- **WHEN** the user chooses an unchecked profile in the controller's submenu
- **THEN** that profile is in force for the controller and carries the checkmark the next time the menu opens

#### Scenario: Turn the profile off

- **WHEN** the user chooses "No Profile"
- **THEN** no profile is in force for the controller

#### Scenario: Many profiles

- **WHEN** more than ten profiles fit the controller
- **THEN** the list shows ten and ends with "More Profiles", which opens the Profiles area

### Requirement: Menu Labels Follow the Platform Rules

Each menu item SHALL use title-style capitalization and a term from the glossary. An item whose action needs more input before it completes MUST end with an ellipsis, written as `LOCALIZATION.md` rules for each language; an item that only opens a window or a submenu MUST have none, except "Settings...", which keeps the form macOS uses. An item that switches a state MUST read as the action it performs.

#### Scenario: Pause label

- **WHEN** a controller is paused
- **THEN** its submenu holds "Resume" and no "Pause"

#### Scenario: Ellipsis

- **WHEN** the user reads the menu
- **THEN** "Settings..." ends with an ellipsis, and "Test Input", "Pause", and "Quit OpenJoystickDriver" do not

### Requirement: The User Decides Whether the Item Is in the Menu Bar

The user SHALL be able to remove the menu bar item by dragging it out of the menu bar while holding Command. OJD MUST store that choice as the "Show in menu bar" setting and MUST keep one way to open the app.

#### Scenario: Drag the item out

- **WHEN** the user drags the item out of the menu bar
- **THEN** "Show in menu bar" is off in Settings and the main window opens
- **AND** "Show in Dock" is on, so one of the two stays on

#### Scenario: No menu bar item and no Dock icon

- **WHEN** the settings file turns both the menu bar item and the Dock icon off and the user opens OJD from Finder or Spotlight
- **THEN** the main window opens
