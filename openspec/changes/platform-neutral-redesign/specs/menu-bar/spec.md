## ADDED Requirements

### Requirement: Menu bar is a subset of the GUI

Every status-item and main-menu action SHALL exist in the main window or Settings window.

#### Scenario: Menu action

- **WHEN** the user chooses Disconnect Wireless Link from the status item
- **THEN** the same action is available in the Controller menu and in the context menu of the controller's row in the Controllers list, and a suspended controller's detail offers Resume

### Requirement: Fixed status-item layout

The status item SHALL show, in order: status line; Controllers submenu; Profiles submenu (Activate, Deactivate); Grant Access; Open Window; Settings; Help submenu (Activity Log, Explain Error Code, Report Problem, Project Website); Quit. Items SHALL be disabled when not applicable and SHALL NOT be hidden, except Grant Access, which SHALL be hidden while every permission is granted.

#### Scenario: Every permission granted

- **WHEN** every permission is granted
- **THEN** Grant Access is not in the menu

#### Scenario: Permission missing

- **WHEN** a permission is missing
- **THEN** Grant Access is visible and enabled

#### Scenario: Two controllers

- **WHEN** two controllers are connected
- **THEN** the Controllers submenu lists both, each with its own five actions, and choosing Suspend under one acts only on that controller

#### Scenario: No controller

- **WHEN** no controller is connected
- **THEN** the Controllers submenu holds one disabled row that says no controller is connected

#### Scenario: No profile

- **WHEN** no profile exists
- **THEN** Profiles > Activate stays enabled and its submenu holds one disabled No Profiles row, the same row as Profile > Activate Profile in the main menu, and Profiles > Deactivate stays enabled with one disabled No Active Profile row

#### Scenario: Profile list not read

- **WHEN** the profile list is loading or the service cannot report it
- **THEN** Profiles > Activate, Profiles > Deactivate and each controller's Active Profile submenu stay enabled and each holds one disabled Profiles Unavailable row

#### Scenario: No profile active

- **WHEN** profiles exist and none is active
- **THEN** Profiles > Deactivate stays enabled and its submenu holds one disabled No Active Profile row, and Profiles > Activate lists every profile

#### Scenario: Profile already active

- **WHEN** a profile is active
- **THEN** Profiles > Activate lists it with a checkmark and disabled, and Profiles > Deactivate lists it enabled

#### Scenario: Controller without an applicable profile

- **WHEN** the profile list is read and no profile applies to a connected controller
- **THEN** that controller's Active Profile submenu stays enabled and holds one disabled No Profiles row

### Requirement: Status-item submenus stay enabled when empty

A submenu SHALL stay enabled when it holds no available item: it holds one disabled row that says why, so people can open it (Apple HIG, Menus: "Make sure a submenu remains available even when its nested menu items are unavailable", <https://developer.apple.com/design/human-interface-guidelines/menus>).

#### Scenario: Submenu with no available item

- **WHEN** a status item submenu has no available item
- **THEN** the submenu stays enabled and holds one disabled row that says why

### Requirement: Status-item empty profile rows

The Activate and per-controller Active Profile submenus SHALL take their empty row from the same model function and strings as the main menu's Activate Profile submenu. The empty row is No Profiles, or Profiles Unavailable while the profile list is loading or cannot be read. The Deactivate submenu's empty row SHALL be No Active Profile, or Profiles Unavailable while the list is not read.

#### Scenario: Shared empty row

- **WHEN** no profile exists
- **THEN** Profiles > Activate holds the same No Profiles row as Profile > Activate Profile in the main menu

#### Scenario: Deactivate with the list not read

- **WHEN** the profile list is not read
- **THEN** Profiles > Deactivate holds one disabled Profiles Unavailable row

### Requirement: Status-item entry identifiers

Each status item entry SHALL carry its model id as its menu item identifier and accessibility identifier, so automation finds it in every UI language.

#### Scenario: Entry identifiers

- **WHEN** automation reads a status item entry in any UI language
- **THEN** the entry's menu item identifier and accessibility identifier are its model id

### Requirement: Status-item controller submenus

The Controllers submenu SHALL hold one submenu per connected controller, named for it, and each SHALL hold Suspend/Resume, Test Input, Active Profile, Disconnect Wireless Link and Show in Window, acting on that controller. With no controller connected, the Controllers submenu SHALL hold one disabled row that says no controller is connected.

#### Scenario: No wireless controller

- **WHEN** a controller is connected over a wired link
- **THEN** its Disconnect Wireless Link item is visible and disabled

#### Scenario: No controller connected

- **WHEN** no controller is connected
- **THEN** the Controllers submenu holds one disabled row that says no controller is connected

### Requirement: Template icon and push updates

The status item icon SHALL be a template image. State SHALL update from service notifications; polling MAY serve only as a fallback.

#### Scenario: Controller attaches

- **WHEN** a controller attaches
- **THEN** the status line updates within one second without a poll interval

### Requirement: Localized status line

The status line SHALL be built from one localized format string with positional arguments, not by joining fragments.

#### Scenario: Arabic

- **WHEN** the language is `ar-SA`
- **THEN** the status line reads right to left as one phrase

### Requirement: Status-item Active Profile submenu

Active Profile SHALL list only the profiles that apply to that controller (its model, and its unit when the profile names one) and check the one active for it; choosing a profile activates it through the service, which scopes it by the profile's own device.

#### Scenario: Profiles for one controller

- **WHEN** a profile names another model than the controller's
- **THEN** that profile is not listed in the controller's Active Profile submenu

### Requirement: Main menu set

The main menu SHALL have App, File, Edit, View, Controller, Profile, Window and Help menus. File SHALL hold Import/Export Profile, Install Record or Mod, Save Support Report and Save Activity Log. View SHALL hold the five areas (Controllers, Profiles, Library, Access and Activity) with `Command-1` to `Command-5`, and Full Screen. Every item SHALL have an action, except the first row of the Controller menu.

#### Scenario: Save support report

- **WHEN** the user chooses File > Save Support Report
- **THEN** a save panel opens and the report writes on confirm

#### Scenario: No profile

- **WHEN** no profile exists
- **THEN** Profile > Activate Profile stays enabled and its submenu holds one disabled No Profiles row

#### Scenario: Profile list not read

- **WHEN** the profile list is loading or the service cannot report it
- **THEN** Profile > Activate Profile stays enabled and its submenu holds one disabled Profiles Unavailable row

### Requirement: Main menu controller target

The first row of the Controller menu SHALL be one disabled informational row that names the controller the Controller and Profile menus act on (the controller selected in the Controllers area), or says that no controller is connected or none is selected. The Controller and Profile items that act on a controller SHALL be disabled without such a controller.

#### Scenario: Controller menu target

- **WHEN** two controllers are connected and one is selected in the Controllers area
- **THEN** the Controller menu's first row shows that controller's name and Suspend, Test Input, Disconnect Wireless Link and Deactivate Profile act on it

#### Scenario: No controller selected

- **WHEN** controllers are connected but none is selected, or the selected one has disconnected
- **THEN** the first row says no controller is selected and the controller items are disabled
