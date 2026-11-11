## ADDED Requirements

### Requirement: A Control Acts When Used or States Why It Cannot

Every control the user can operate SHALL change what it controls or show a result. A control that cannot act MUST be unavailable and MUST show its reason as text beside it, not only in a tooltip. A control's title MUST name everything the control governs.

#### Scenario: Switch that governs two notifications

- **WHEN** one switch governs the notification for a connected controller and the notification for a controller that needs attention
- **THEN** the switch's title or its row names both

#### Scenario: Setting that cannot change

- **WHEN** "Start at login" cannot be changed
- **THEN** the switch is unavailable and the row holds a sentence with the reason

#### Scenario: Last way to open the app

- **WHEN** "Show in menu bar" is on and "Show in Dock" is off
- **THEN** the "Show in menu bar" switch is unavailable and the row says that one of the two stays on

#### Scenario: Pop-up button with no options

- **WHEN** a pop-up button has no option to offer
- **THEN** it is unavailable and the row says what is missing

#### Scenario: Notification permission denied

- **WHEN** macOS has denied notifications and the user turns a notification switch on
- **THEN** the switch returns to off and the pane says that macOS blocks notifications, with a button that opens the Notifications pane of System Settings

### Requirement: A Choice Applies When Chosen or the View Shows It as Pending

A control's value SHALL take effect when the user chooses it. Where a view collects several values before it applies them, the view MUST show that changes are pending and MUST show the button that applies them.

#### Scenario: Player indicator in Input Test

- **WHEN** the user chooses a player number in Input Test
- **THEN** the controller's indicator changes with no second click

#### Scenario: Profile editor

- **WHEN** the user changes a value in the profile editor
- **THEN** the editor shows that the profile has unsaved changes and its Save button is available

#### Scenario: Scope of a virtual gamepad choice

- **WHEN** the user chooses "This controller" and then a virtual gamepad kind
- **THEN** the kind is stored for that controller only

### Requirement: A Refused or Failed Request Shows Its Reason Beside the Control

OJD SHALL show the reason of a refused or failed request beside the control that started it, and the control MUST show the value in force. No action MUST end without a visible result.

#### Scenario: Controller that macOS cannot serve

- **WHEN** the user chooses macOS for a controller on the direct USB route and the service refuses
- **THEN** the control shows OpenJoystickDriver again and the reason appears directly below it

#### Scenario: Action that a condition blocks

- **WHEN** the user starts an action whose condition is not met
- **THEN** the view states the condition, or the control was unavailable with that reason

#### Scenario: App-wide problem

- **WHEN** a problem concerns no single control, such as a missing permission
- **THEN** the banner of the main window shows it

### Requirement: A Control Offers Only Choices the Service Accepts

A control SHALL offer a choice only when the service accepts it for the item in view. A choice that does not apply MUST be absent, or unavailable with its reason.

#### Scenario: Who serves a controller

- **WHEN** a controller is on the direct USB route
- **THEN** the macOS choice is unavailable and the row says why

#### Scenario: Virtual gamepad kinds

- **WHEN** a controller cannot use a virtual gamepad kind
- **THEN** the pop-up button does not offer that kind for it

### Requirement: A Control Shows the Value in Force

A control SHALL show the value in force. When a stored value differs from the value in force, the row MUST show both and say when the stored value applies.

#### Scenario: Stored kind while virtual output is off

- **WHEN** a controller has a stored virtual gamepad kind and virtual output is off
- **THEN** the row shows the stored kind and says that it applies once virtual output is on

### Requirement: A Control Is Busy While Its Request Runs

A control SHALL be unavailable and show progress while its request runs, and a change the user makes to a continuous control during a write MUST be written after that write ends.

#### Scenario: Second click

- **WHEN** the user clicks a second choice while the first request runs
- **THEN** OJD sends no second request

#### Scenario: Dead zone slider during a write

- **WHEN** the user moves the dead zone slider while an earlier value is being written
- **THEN** the last position is written after the first write ends

### Requirement: A Setting Applies at Once

A setting SHALL take effect when the user changes it, without a restart of the app.

#### Scenario: Automatic update check

- **WHEN** the user turns the automatic update check off
- **THEN** OJD starts no automatic check in that session

### Requirement: Toolbar Buttons Stay and Each Has a Menu Command

The main window SHALL keep its toolbar buttons. Every toolbar item MUST also be a command in the menu bar with the same title and the same availability.

#### Scenario: Toolbar action in the menu

- **WHEN** the user opens the menus of the main menu
- **THEN** each of the toolbar's actions appears as a menu command

#### Scenario: Unavailable action

- **WHEN** a toolbar button is unavailable
- **THEN** its menu command is unavailable

#### Scenario: Toolbar kept

- **WHEN** the main window opens after the update
- **THEN** its toolbar shows the same buttons as before

### Requirement: The Main Window Has a Find Command

The main window SHALL offer Find in the Edit menu with Command-F, which moves the keyboard focus to the search field of the list in view.

#### Scenario: Find in the controller list

- **WHEN** the user presses Command-F in the Controllers area
- **THEN** the search field of the list has the keyboard focus

### Requirement: The Window Minimum Fits Its Columns

The minimum width of the main window SHALL equal the sum of the minimum widths of the columns it shows.

#### Scenario: Three columns

- **WHEN** the user drags the main window to its minimum width with the sidebar shown
- **THEN** each column is at its minimum width and no column is clipped

#### Scenario: Sidebar hidden

- **WHEN** the user hides the sidebar
- **THEN** the window can become narrower by the sidebar's minimum width

### Requirement: Text Uses the System Text Styles

Every text in the app SHALL use a system text style, and none MUST set a fixed point size. A label, a value, and an error the user must read MUST use the body style or a larger one; the caption style is for secondary text.

#### Scenario: Error message

- **WHEN** a view shows an error
- **THEN** the error uses the body style

#### Scenario: Fixed size

- **WHEN** a view under `Sources/OpenJoystickDriverPresentation` sets a font by point size
- **THEN** the repository check fails and names the file and line

### Requirement: Sheets and Spacing Come From One Scale

Sheets SHALL use one of three widths, and views MUST take their spacing from one shared scale.

#### Scenario: Two confirmation sheets

- **WHEN** the user opens two sheets of the same kind
- **THEN** both have the same width and the same padding

### Requirement: A State Is Shown With Words and a Symbol

OJD SHALL show each state of a controller, a permission, and the service with a sentence and a symbol, and MUST NOT rely on color alone.

#### Scenario: Controller that needs a step

- **WHEN** a controller needs a step from the user
- **THEN** its row shows a symbol that differs in shape from the ready symbol, and a sentence

### Requirement: Every Control Works With the Keyboard and VoiceOver

Every control SHALL be reachable with the keyboard, and every control with no visible title MUST carry an accessibility label.

#### Scenario: Toolbar button

- **WHEN** VoiceOver focuses an icon-only toolbar button
- **THEN** it speaks the button's title

#### Scenario: Controller detail by keyboard

- **WHEN** the user turns on keyboard navigation and presses Tab through a controller's detail
- **THEN** the focus reaches every control

### Requirement: A Controller Is in One of Three States

The controller list and the controller detail SHALL show each connected controller in one of three states: "Working", "Needs a step from you", or "Not supported yet". Each state other than "Working" MUST show one sentence and one button for the next step.

#### Scenario: Missing permission

- **WHEN** a controller cannot be read because a permission is missing
- **THEN** it shows "Needs a step from you", names the permission, and offers the button that opens the permission

#### Scenario: Controller OJD cannot serve

- **WHEN** a connected controller matches no protocol and has no record
- **THEN** it shows "Not supported yet" and offers the button that drafts a record or prepares a report

### Requirement: The First Start Guides Setup

On a start with a setup step open, the main window SHALL show the steps in order, each with one sentence that says what the step is for and one button. OJD MUST ask for a permission only when the user chooses that step.

#### Scenario: First start

- **WHEN** the user opens OJD for the first time
- **THEN** the window shows the setup steps and macOS shows no permission request until the user chooses a step

#### Scenario: Setup done

- **WHEN** every step is done
- **THEN** the window shows the Controllers area

### Requirement: Help Is in the App

The Help menu SHALL hold a command that opens the help page of the area in view, and the app MUST offer a short tour of the main window that the user can start from the Help menu.

#### Scenario: Help for the area in view

- **WHEN** the user chooses the help command in the Profiles area
- **THEN** the page about remapping profiles opens

#### Scenario: Tour

- **WHEN** the user chooses the tour from the Help menu
- **THEN** the app shows each area of the main window with one sentence

### Requirement: The Interface Is Measured Before It Changes

`docs/development/interface-audit.md` SHALL list each window, sheet, and menu of the app with the Human Interface Guidelines page it answers to, the Apple app it was measured against, each difference found, and the decision for it. An intentional difference MUST carry its reason.

#### Scenario: View with a difference

- **WHEN** a view differs from its guideline page or its reference app
- **THEN** the audit lists the difference with "fix" and a task number, or "keep" and a reason

#### Scenario: Toolbar buttons

- **WHEN** a reader looks up the main window's toolbar in the audit
- **THEN** it reads "keep", with the Notes measurement as the reference

### Requirement: The Wiki Starts From the Reader's Goal

`wiki/Home.md` SHALL offer one start page for each goal: play a game with a controller, control the Mac with a controller, set up OJD on several Macs, and add support for a controller. Each start page MUST reach its goal without a term the glossary does not define.

#### Scenario: Reader who wants to play

- **WHEN** a reader follows the start page for playing a game
- **THEN** the reader reaches a working controller in a game without opening a reference page
