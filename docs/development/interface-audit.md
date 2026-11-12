# Interface audit: 0.6.0-alpha.2

Task 10.1 of `openspec/changes/0-6-0-alpha-3/tasks.md`; decision D23 of `design.md`. Read on 2026-11-11 from the installed 0.6.0-alpha.2 (build 1.21.99) on macOS 27.2 and from the source of this branch.

## How to read it

- **Source** is a path under `Sources/OpenJoystickDriverPresentation/`. The line is omitted; the file is the unit.
- **Measured** is a size in points (width x height) from `openspec/changes/0-6-0-alpha-3/evidence/interface-reference/ojd-accessibility.txt` ("A" with its section number). "not measured" says the element was not open or was not read through Accessibility; the source size follows when the source states one.
- **Screenshots** are files under `openspec/changes/0-6-0-alpha-3/evidence/interface-reference/`, each named `ojd-alpha2/<file>.png`. A reference reading is `apple-apps-accessibility.txt` ("R" with its section number).
- **Guideline** is a page of the Human Interface Guidelines that `design.md` quotes ("Reference apps and guidelines"). Task 10.4 reads the pages again.
- **Reference** is the app the element was compared with: Notes and System Settings (R1 to R3), or an open-source app at the commit of `design.md`.
- **Decision** is `fix` with a task of groups 11 to 17, or `keep` with its reason. A fix names the task that already covers it; a defect that no task names reads `fix` with the nearest task and is listed under "Findings no task names".
- Nothing here is a reproduction. Task 10.5 reproduces each finding under "Controls that can appear to do nothing" and writes the result per control.

## Findings seen in the baseline

1. The Controllers list header reads "0 controllers connected" above a listed device (`ojd-alpha2/main-Controllers-baseline-0-connected.png`). The count is `deviceCountLabel` (`MainWindow/MainWindowSummary.swift`); the list also holds the devices OJD does not serve (`Controllers/Inventory/ControllersView.swift`). In the later reading the same header read "1 controller connected" above two rows (`ojd-alpha2/main-Controllers.png`).
2. That device shows the raw identifier `2dc8:301c` and the word "USB" as its row title (`Controllers/Inventory/ControllersView.swift`, `"\(unserved.identity)  \(unserved.connection)"`). `inclusion`: "Avoid using specialized or technical terms without defining them."

Both are rows C03 and C04 below.

## Findings no task names

- The header count and the identifier above (C03, C04). Task 12.13 shows each controller with a state and a sentence, and 17.2 gives each reason for not serving a sentence; neither names the count or the identifier. Task 12.13 should add: the count in the header and the toolbar title counts the rows the list shows, or says "1 controller, 1 device not served"; a device OJD does not serve is named by its model when the catalog knows it.
- Heights below the 20 pt minimum of `accessibility`: the two disclosure labels "Tuning" (75 x 16) and "Advanced" (94 x 16) in the controller detail (A2); the arrow buttons of the stick dead zone stepper are 20 x 12 inside a 20 x 24 stepper. Switches (36 x 16) and the window's traffic lights (16 x 16) are system controls and stay. `design.md` says the smallest hit areas are 28 x 28; the readings show these smaller ones. Task 12.14 checks them.
- Unnamed controls: three push buttons of the controller detail, the Create a token sheet's two checkboxes and two buttons, and the New profile sheet's checkbox and two buttons have no name or description in Accessibility (A2, A7). Task 12.14 covers them.
- Toolbar heights differ by window: main window 52 (Notes 52), Settings 56, Input Test 66 because its Refresh button shows a text label below the icon (A1, A4, A5).
- The word "Advanced" names three things: the Settings pane, a disclosure in the controller detail, and (after 13.2) the interface level. D21 gives the level the same word. Task 13.5 limits the developer tools to the level; the pane and the disclosure need a different word or the level needs one.

## 1. Windows

| ID | Element | Source | Measured | Term shown | Guideline | Reference | Differences | Decision |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| W01 | Main window | `MainWindow/MainWindowController.swift` | 960 x 588 frame as read; default content 1040 x 700 and minimum 960 x 560 by source (A1); `ojd-alpha2/main-Controllers.png` | area name, with the controller count in the title of Controllers | `layout`: "In general, support resizing." | System Settings 740 x 625 (R3); OpenTabletDriver 960 x 760 | the minimum width 960 exceeds the 790 its columns need (170 + 200 + 420) | fix 12.10 |
| W02 | Sidebar | `MainWindow/MainWindowContent.swift` | 170 x 536, rows 170 x 32 (A2) | Controllers, Profiles, Library, Access, Activity | `layout` | System Settings: 232 wide, rows 232 x 32 (R3) | 62 pt narrower, same row height; resizable from 170 to 260 and hidden by the toolbar button | keep: row height equals System Settings, every label fits, and the user can widen it |
| W03 | Controllers list column | `Controllers/Inventory/ControllersView.swift` | 200 x 528, rows 200 x 47 and 200 x 86 (A2) | model name and protocol ("Generic HID") | `layout` | OpenTabletDriver: device switcher above tabs | the model name is cut ("8BitDo Ultimate 2...") at the minimum width 200 | fix 12.10 (column minimums are set with the window minimum) |
| W04 | Settings window | `SettingsWindow/SettingsWindowController.swift` | 600 x 510 (General), 600 x 479 (Notifications), 600 x 438 (Advanced); toolbar 56 (A4); `ojd-alpha2/settings-General.png`, `ojd-alpha2/settings-Notifications.png`, `ojd-alpha2/settings-Advanced.png` | General, Notifications, Advanced | `layout` | System Settings 740 x 625 with a sidebar (R3) | 600 wide for every pane, height fitted, not resizable (`SettingsWindow/SettingsWindowPaneModel.swift`); toolbar of three tabs where System Settings has a sidebar of 31 rows | keep: three panes fit three tabs, and the width is the one that fits the packet table (`SettingsWindow/SettingsWindowPaneModel.swift`); only System Settings was measured, no other Apple app's settings window |
| W05 | Input Test window | `Controllers/InputTest/InputTestWindowController.swift` | 900 x 859, toolbar 66 (A5); `ojd-alpha2/input-test.png` | Input Test, Refresh | `toolbars` | Notes toolbar 52 (R1) | opened with a controller connected; with none the button that opens it is not shown; toolbar 14 pt taller than the main window's because "Refresh" has a text label | fix 12.12 |
| W06 | Menu bar item (icon) | `MenuBar/MenuBarCoordinator.swift` | 24 x 24, description "OpenJoystickDriver status" (A6) | symbol `gamecontroller` | `the-menu-bar`: "Avoid relying on the presence of menu bar extras." | Rectangle, MonitorControl: removable item | the symbol never changes; a problem and "no controller" look the same; the item cannot be removed by the user | fix 11.4, 11.6 |
| W07 | Alert: disconnect a wireless link | `MenuBar/MenuBarCoordinator+StatusMenu.swift` | not measured (not opened) | `ui.controllers.disconnectWirelessConfirmTitle` | `buttons` | none | not read beyond its title | keep: it confirms a command that drops a connection; 10.5 reads it |
| W08 | Alert: activate a profile | `MenuBar/MenuBarCoordinator+StatusMenu.swift` | not measured (not opened) | `ui.profiles.activationTitle`, `ui.profiles.emptyActivationTitle` | `menus`: "Consider using a checkmark to show that an attribute is currently in effect." | Karabiner-Elements: checkmark list | the status menu opens an alert to choose a profile | fix 11.2 |
| W09 | Alert: action failed | `MenuBar/MenuBarCoordinator+StatusMenu.swift` | not measured (not opened) | `ui.extra.actionFailedTitle` | `buttons` | none | one of the seven places a failure shows | fix 12.7 |
| W10 | Alert: settings file unreadable | `MenuBar/SettingsFileStartup.swift` | not measured (not opened) | `ui.settings.advanced.unreadableTitle` | `buttons` | none | offers a reset or a migration | keep: it offers the only two ways out; 10.5 reads it |
| W11 | Alert: confirmation and notice | `MenuBar/MenuBarCoordinator+ApplicationMenu.swift` | not measured (not opened) | the title the caller passes | `buttons` | none | one alert type for every confirmation | fix 12.7 (failures shown beside the control) |

## 2. Sheets

Twenty-four sheet views. Source widths are the `.frame(width:)` of the view: 420, 430, 440, 470, 480, 500, and 520, with two paddings, 20 and 28; `ProfileSheetScaffold` sets 390 to 520. Two were opened and measured (A7); the rest are "not measured": each needs a profile, a binding, a record, a controller state, or the developer switch that this Mac did not have in a state to open it. Every sheet takes task 12.12 (three widths, one spacing scale).

| ID | Element | Source | Measured | Term shown | Guideline | Reference | Differences | Decision |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| S01 | Create a token | `Access/AccessSheets.swift` | 440 x 307 (A7); `ojd-alpha2/sheet-access-create-token.png` | "Create a token", "Token name" | `layout`: "Use consistent spacing." | System Settings push buttons 80 x 24 (R3) | two checkboxes and two buttons have no accessibility name; padding 20 | fix 12.12, 12.14 |
| S02 | Access confirmation | `Access/AccessSheets.swift` | not measured; source 440 | not read | `layout` | none | width 440, padding 20 | fix 12.12 |
| S03 | Issued token | `Access/AccessSheets.swift` | not measured; source 440 | not read | `layout` | none | width 440, padding 20 | fix 12.12 |
| S04 | Library confirmation | `Library/LibraryAreaView.swift` | not measured; source 420 | the confirmation's title | `layout` | none | width 420, padding 20 | fix 12.12 |
| S05 | Explain Error Code | `Activity/ErrorCodeExplainerView.swift` | not measured; source 420 | "Explain Error Code" | `layout` | none | width 420, padding 20 | fix 12.12 |
| S06 | Soak Test | `Settings/Developer/SoakTestSheet.swift` | not measured; source 440 | "Soak Test" | `layout` | none | developer switch; width 440, padding 20 | fix 12.12 |
| S07 | Controller timed action | `Controllers/Actions/ControllerActionViews.swift` | not measured; source 420 | "Duration", "Start capture", "Cancel" | `layout` | none | width 420, padding 20 | fix 12.12 |
| S08 | New profile | `Profiles/Editor/ProfileCreationSheet.swift` | 420 x 286 (A7); `ojd-alpha2/sheet-profiles-new-profile.png` | "Profile name", "Controller", "Target", "Template", "Virtual gamepad" | `pop-up-buttons`: "Provide a useful default selection." | System Settings pop-ups | the checkbox and two buttons have no accessibility name; "Virtual gamepad" pop-up of four items; the identifier text field of an app is replaced by a chooser in 15.2 | fix 12.12, 12.14, 15.2 |
| S09 | Duplicate profile | `Profiles/Editor/ProfileCreationSheet.swift` | not measured; source 420 | "Duplicate" | `layout` | none | width 420, padding 20 | fix 12.12 |
| S10 | Profile details | `Profiles/Editor/ProfileEditingSheets.swift` | not measured; source 440 | not read | `layout` | none | width 440, padding 28 | fix 12.12 |
| S11 | Binding behavior | `Profiles/Editor/ProfileEditingSheets.swift` | not measured; source 470 | not read | `layout` | none | width 470, padding 28 | fix 12.12 |
| S12 | Macro editor | `Profiles/Editor/MacroEditorSheet.swift` | not measured; source 520 | "Steps" | `layout` | none | width 520, padding 28 | fix 12.12 |
| S13 | Axis adjustment | `Profiles/Editor/MappingCaptureViews.swift` | not measured; source 430 | "Dead zone", "Gain", "Digital threshold" | `layout`, `typography` | none | width 430, padding 28; the label "Dead zone" here and "Stick deadzone" in the controller detail differ | fix 12.12, 14.2 |
| S14 | Capture an assignment | `Profiles/Bindings/CaptureAssignmentSheet.swift` | not measured; source 470 | not read | `game-controls`: "Prefer using symbols, not text, to refer to game controller elements." | none | width 470, padding 28 | fix 12.12 |
| S15 | Chord and sequence | `Profiles/Bindings/ProfileCombinationSheets.swift` | not measured; source 480 | "Press window", "Completion window" | `inclusion`: "Avoid using specialized or technical terms without defining them." | none | width 480; the two window terms are not defined | fix 12.12, 14.2 |
| S16 | Layer | `Profiles/Bindings/ProfileCombinationSheets.swift` | not measured; scaffold 390 to 520 | "Add layer" | `layout` | none | the only sheets with a range of widths instead of one | fix 12.12 |
| S17 | Layer binding | `Profiles/Bindings/ProfileCombinationSheets.swift` | not measured; scaffold 390 to 520 | not read | `layout` | none | as S16 | fix 12.12 |
| S18 | Stick modes | `Profiles/AnalogSheets/ProfileStickSheet.swift` | not measured; source 500 wide, height by state | "Stick modes" | `layout` | none | width 500, height changes with the enabled state | fix 12.12 |
| S19 | Trigger modes | `Profiles/AnalogSheets/ProfileTriggerSheet.swift` | not measured; source 500 wide, height by state | not read | `layout` | none | as S18 | fix 12.12 |
| S20 | Touch modes | `Profiles/AnalogSheets/ProfileTouchSheet.swift` | not measured; source 500 wide, height by state | not read | `layout` | none | as S18 | fix 12.12 |
| S21 | Pointer speed | `Profiles/AnalogSheets/ProfilePointerSpeedSheet.swift` | not measured; source 440 | not read | `layout` | none | width 440, padding 28 | fix 12.12 |
| S22 | Motion | `Profiles/AnalogSheets/ProfileMotionSheet.swift` | not measured; source 500 x 600 | not read | `layout` | none | a fixed height as well as a width | fix 12.12 |
| S23 | Regions | `Profiles/AnalogSheets/ProfileRegionSheet.swift` | not measured; source 500 x 640 | not read | `layout` | none | a fixed height as well as a width | fix 12.12 |
| S24 | Pair Joy-Cons | `Profiles/List/ProfileJoyConPairSheet.swift` | not measured; source 480 | not read | `layout` | none | width 480, padding 28 | fix 12.12 |

## 3. Menus

The main menu reads were `get name of menu items` of each menu (A3). The main menu shows only while a window of the app is active (`MenuBar/MenuBarCoordinator+Lifecycle.swift`).

| ID | Element | Source | Measured | Term shown | Guideline | Reference | Differences | Decision |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| M01 | Menu bar item menu | `MenuBar/StatusItemModel.swift` | 373 wide, rows 24, separators 11 (A6); `ojd-alpha2/menu-bar-item-menu.png` | "Ready · 1 controller connected · No active profile" | `the-menu-bar`: "Display a menu — not a popover"; `menus` | LinearMouse, MonitorControl, Karabiner-Elements: device or profile at the top level | the menu has no stated purpose in the app; its first row joins three values and cannot be activated | fix 11.1, 11.2 |
| M02 | Status line | `MenuBar/StatusItemModel.swift` | 373 x 24, unavailable (A6) | `"%1$@ · %2$@ · %3$@"` | `menus`: "Show people when a menu item is unavailable." | MonitorControl: the display's name as a header | no string says the service is stopped: "Needs attention" with 0 controllers | fix 11.2, 11.3 |
| M03 | Controllers submenu | `MenuBar/StatusItemModel.swift` | 373 x 24 (A6) | "Controllers" | `menus`: "Use submenus sparingly." | LinearMouse: battery rows at the top level | one submenu level above the controllers; the row shows a name only | fix 11.2 |
| M04 | Controller submenu | `MenuBar/StatusItemModel.swift` | items read, sizes 0 x 0 (not shown) (A6) | "Suspend", "Test Input", "Active Profile", "Disconnect Wireless Link", "Show in Window" | `menus`: "Limit the depth and length of submenus." | Karabiner-Elements: checkmarked profiles | "Active Profile" opens a third level; "Disconnect Wireless Link" is unavailable and no reason shows | fix 11.1, 11.2 |
| M05 | Profiles submenu (Activate, Deactivate) | `MenuBar/StatusItemModel.swift` | items read, sizes 0 x 0 (A6) | "Profiles", "Activate", "Deactivate", "No Profiles" | `menus`: "Consider using a checkmark to show that an attribute is currently in effect." | Karabiner-Elements | two lists where one checkmarked list serves | fix 11.2 |
| M06 | Grant Access row | `MenuBar/StatusItemModel.swift` | not measured (shown only while a permission is missing) | "Grant Access" | `inclusion`: "Present a clear, straightforward interface." | none | does not name the permission | fix 11.3 |
| M07 | Open Window, Settings... | `MenuBar/StatusItemModel.swift` | 373 x 24 each (A6) | "Open Window", "Settings..." | `menus`: "Append an ellipsis to a menu item's label when the action requires more information before it can complete." | LinearMouse, Rectangle: "Settings…" | "Settings..." opens a window and needs no more input; the ellipsis follows the convention of a window opener | keep: the macOS convention for a settings command, as the five utilities |
| M08 | Help submenu | `MenuBar/StatusItemModel.swift` | items read, sizes 0 x 0 (A6) | "Activity Log", "Explain Error Code...", "Report Problem...", "Project Website" | `menus` | none of the five utilities has one; `docs/development/menu-bar-settings-architecture.md:78` rules logs and reports out | four commands the main menu's Help already holds (A3) | fix 11.2, 11.5 |
| M09 | Quit row | `MenuBar/StatusItemModel.swift` | 373 x 24 (A6) | "Quit OpenJoystickDriver" | `menus` | every reference utility ends with Quit | none | keep: it matches the five utilities |
| M10 | App menu | `MainMenu/MainMenuModel.swift` | not measured (names only, A3) | "About OpenJoystickDriver", "Settings...", "Services", "Hide", "Quit OpenJoystickDriver" | `menus` | Notes: same standard menu | none | keep: the standard app menu |
| M11 | File menu | `MainMenu/MainMenuModel.swift` | not measured (names only, A3) | "Import Profile...", "Install Record or Mod...", "Close", "Close All", "Export Profile...", "Save Support Report...", "Save Activity Log..." | `toolbars`: "Make every toolbar item available as a command in the menu bar." | Notes: "New Note", "Share" in File | only 5 of the 15 toolbar actions are here; "New Note" has a counterpart in Notes, "New profile" has none | fix 12.8 |
| M12 | Edit menu | `MainMenu/MainMenuModel.swift` | not measured (names only, A3) | "Undo" ... "Emoji & Symbols" | `toolbars` | Notes: Find | no Find; the Library and Activity toolbars hold search fields | fix 12.9 |
| M13 | View menu | `MainMenu/MainMenuModel.swift` | not measured (names only, A3) | "Controllers", "Profiles", "Library", "Access", "Activity", "Show Toolbar", "Hide Sidebar", "Enter Full Screen" | `toolbars` | Notes: "Hide Toolbar", "Customize Toolbar…" | no "Customize Toolbar..."; no Simple and Advanced choice | fix 12.8, 13.2 |
| M14 | Controller menu | `MainMenu/MainMenuModel.swift` | not measured (names only, A3) | the controller's name, "Suspend", "Test Input", "Disconnect Wireless Link", "Show in Window" | `menus` | none | the controller is the first item with no header | keep: it carries the same commands as the status item, and 11.2 changes the status item only |
| M15 | Profile menu | `MainMenu/MainMenuModel.swift` | not measured (names only, A3) | "Activate Profile", "Deactivate Profile" | `menus` | Karabiner-Elements: checkmarked profiles | two commands where the status item will hold a checkmarked list | keep: the window's Profile menu acts on the selected profile; 11.2 changes the status item only |
| M16 | Window menu | `MainWindow/MainWindowController.swift` | not measured (names only, A3) | system items and "Controllers (1 controller connected)" | `menus` | Notes | none | keep: the standard Window menu |
| M17 | Help menu | `MainMenu/MainMenuModel.swift` | not measured (names only, A3) | "Activity Log", "Explain Error Code...", "Copy Support Report", "Report Problem...", "Project Website" | `inclusion`: "Build in ways to learn how to use your app or game." | none | no in-app help, no tour, no page for the area in view | fix 11.5, 12.16 |

## 4. Main window toolbar

Every item is read in A1 and shown in `ojd-alpha2/main-<Area>.png`. All keep the Notes form: the toolbar is 52 pt high and holds icon-only buttons with no text label, 36 to 44 pt wide, with a 38 pt high control inside each group (R1: Notes toolbar 52, buttons 36 to 44, 38 x 38 inside groups). The maintainer chose this form (D20). The menu command each lacks is task 12.8, which changes no toolbar item.

| ID | Element | Source | Measured | Term shown | Guideline | Reference | Differences | Decision |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| T01 | Sidebar button | `MainWindow/MainWindowToolbar.swift` | 44 x 52 (A1) | "Sidebar" | `toolbars` | Notes: "View Options" 44 x 52 (R1) | none; "Hide Sidebar" is in the View menu | keep: same size as Notes, Notes measurement in `apple-apps-accessibility.txt` section 1 |
| T02 | New profile | `MainWindow/MainWindowToolbar.swift` | 36 x 52 | "New profile" | `toolbars`: "Make every toolbar item available as a command in the menu bar." | Notes: "New Note" 40 x 52 | no menu command | keep: icon-only 36 to 44 pt as Notes (section 1); the menu command is 12.8 |
| T03 | Import profile | `MainWindow/MainWindowToolbar.swift` | 36 x 52 | "Import profile" | `toolbars` | Notes | the File menu holds "Import Profile..." | keep: as T02, Notes section 1 |
| T04 | Validate profile file | `MainWindow/MainWindowToolbar.swift` | 37 x 52 | "Validate profile file" | `toolbars` | Notes | no menu command | keep: as T02, Notes section 1 |
| T05 | Duplicate | `MainWindow/MainWindowToolbar.swift` | 37 x 52 | "Duplicate" | `toolbars` | Notes | no menu command | keep: as T02, Notes section 1 |
| T06 | Export profile | `MainWindow/MainWindowToolbar.swift` | 36 x 52 | "Export profile" | `toolbars` | Notes: "Share" | the File menu holds "Export Profile..." | keep: as T02, Notes section 1 |
| T07 | Delete | `MainWindow/MainWindowToolbar.swift` | 41 x 52 | "Delete" | `toolbars` | Notes | no menu command | keep: as T02, Notes section 1 |
| T08 | Install (Library) | `MainWindow/MainWindowToolbar.swift` | 39 x 52 | "Install" | `toolbars` | Notes | the File menu holds "Install Record or Mod..." | keep: as T02, Notes section 1 |
| T09 | Validate... (Library) | `MainWindow/MainWindowToolbar.swift` | 36 x 52 | "Validate..." | `toolbars` | Notes | no menu command | keep: as T02, Notes section 1 |
| T10 | Test Record... | `MainWindow/MainWindowToolbar.swift` | 36 x 52 | "Test Record..." | `toolbars` | Notes | no menu command | keep: as T02, Notes section 1 |
| T11 | Remove (Library) | `MainWindow/MainWindowToolbar.swift` | 41 x 52 | "Remove" | `toolbars` | Notes | no menu command | keep: as T02, Notes section 1 |
| T12 | Library search | `MainWindow/MainWindowToolbar.swift` | group 228 x 52, field 222 x 38 | "Search" | `toolbars` | Notes: "Search" 38 x 38 | no Find command | keep: as T02, Notes section 1; Find is 12.9 |
| T13 | Grant a Program... | `MainWindow/MainWindowToolbar.swift` | 36 x 52 | "Grant a Program..." | `inclusion`: "Avoid using specialized or technical terms without defining them." | Notes | "Program" for what the service calls a client | keep: the size and form as Notes, section 1; the term is 14.2 |
| T14 | Create a Token... | `MainWindow/MainWindowToolbar.swift` | 41 x 52 | "Create a Token..." | `inclusion` | Notes | "Token" is not defined where it shows | keep: the size and form as Notes, section 1; the term is 14.2 |
| T15 | Activity view switch | `MainWindow/MainWindowToolbar.swift` | group 192 x 52, radio group 190 x 38 | "Log", "Diagnostics" | `toolbars` | Notes | no menu command | keep: as T02, Notes section 1 |
| T16 | Activity filter | `MainWindow/MainWindowToolbar.swift` | menu button 53 x 52 | "Filter" | `pop-up-buttons` | Notes: "Media" menu button 36 x 52 | no menu command | keep: as T02, Notes section 1 |
| T17 | Activity search | `MainWindow/MainWindowToolbar.swift` | group 168 x 52, field 162 x 38 | "Search" | `toolbars` | Notes | no Find command | keep: as T02, Notes section 1 |
| T18 | Copy All | `MainWindow/MainWindowToolbar.swift` | 41 x 52 | "Copy All" | `toolbars` | Notes | no menu command | keep: as T02, Notes section 1 |
| T19 | Save Activity Log... | `MainWindow/MainWindowToolbar.swift` | 36 x 52 | "Save Activity Log..." | `toolbars` | Notes | the File menu holds "Save Activity Log..." | keep: as T02, Notes section 1 |
| T20 | Show in Finder | `MainWindow/MainWindowToolbar.swift` | 44 x 52 | "Show in Finder" | `toolbars` | Notes | no menu command | keep: as T02, Notes section 1 |
| T21 | Run diagnostics | `MainWindow/MainWindowToolbar.swift` | not measured (shown with the Diagnostics view only) | "Run diagnostics" | `toolbars` | Notes | no menu command | keep: as T02, Notes section 1 |

## 5. Main window: areas and controls

| ID | Element | Source | Measured | Term shown | Guideline | Reference | Differences | Decision |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| C01 | Controllers area | `Controllers/Inventory/ControllersView.swift` | 790 x 536 content; `ojd-alpha2/main-Controllers.png` | "Controllers" | `layout` | OpenTabletDriver: device switcher | list, detail, and an empty state "No controller connected" / "Connect a controller." | fix 12.13 |
| C02 | Controller row | `Controllers/Inventory/ControllersView.swift` | 200 x 47 (A2) | model name, protocol ("Generic HID") | `game-controls`; `inclusion` | LinearMouse: battery at the top | the row shows a name and a protocol, no state and no battery; the model name is cut | fix 12.13 |
| C03 | List header count | `MainWindow/MainWindowSummary.swift` | 774 x 52 title text (A2); `ojd-alpha2/main-Controllers-baseline-0-connected.png` | "0 controllers connected" above a listed device | `inclusion`: "Present a clear, straightforward interface." | MonitorControl: one block per display | the count and the list disagree (baseline: 0 and one row; later: 1 and two rows) | fix 12.13 (not named by the task; see "Findings no task names") |
| C04 | Unserved device row | `Controllers/Inventory/ControllersView.swift` | 200 x 86 (A2) | `2dc8:301c  USB` and "This device serves no controls, such as a receiver with no controller connected. OJD sends it no data." | `inclusion`: "Avoid using specialized or technical terms without defining them." | MonitorControl: the display's name | the raw identifier and "USB" are the title; the sentence says "OJD" and "controls" | fix 12.13, 17.2 (not named by the tasks; see "Findings no task names") |
| C05 | Controller header | `Controllers/Inventory/ControllerDetailView+Facts.swift` | 549 x 55 (A2) | name, "Bluetooth Low Energy" | `layout` | System Settings | connection shown by transport name | fix 14.2 ("connection": cable, receiver, Bluetooth) |
| C06 | Facts group | `Controllers/Inventory/ControllerDetailView+Facts.swift` | 549 x 221, rows 16 (A2) | "Active profile", "Publication", "Serving route", "Protocol", "Serial number", "Input" | `inclusion` | none | "Publication" and "Serving route" are not defined; "Not published (The system serves it as a gamepad)" | fix 14.2, 12.13 |
| C07 | Input Test row | `Controllers/Inventory/ControllerDetailView+Facts.swift` | button 132 x 24 (A2) | "Input Test", "Open Input Test..." | `buttons` | System Settings push buttons 80 x 24 | none | keep: 24 high as System Settings and the label states its purpose |
| C08 | Served by | `Controllers/Inventory/ControllerServerPicker.swift` | radio group 388 x 24, segments 194 x 24 (A2) | "Served by", "macOS (native)", "OpenJoystickDriver (virtual)", "Set by", "Default" | `pop-up-buttons`: "Use a pop-up button to present a flat list of mutually exclusive options or states." | System Settings | both segments stay enabled while the request runs; a refusal shows in another section; the service can refuse an option the control offers | fix 12.2, 14.2 |
| C09 | Virtual HID profile | `Controllers/Inventory/VirtualHIDProfileOverrideView.swift` | not measured (shown only for a controller OJD serves) | "Virtual HID profile", raw identifiers as options | `pop-up-buttons`: "Provide a useful default selection."; `inclusion` | OBS Output Mode: "Simple", "Advanced" | drops two results without a message; shows the stored value, not the one in force; offers all kinds to every controller | fix 12.3, 14.4 |
| C10 | Apply to (scope) | `Controllers/Inventory/VirtualHIDProfileOverrideView.swift` | not measured | "Apply to" | `pop-up-buttons` | none | view state only; writes nothing | fix 12.3 |
| C11 | Stick deadzone | `Controllers/Inventory/StickDeadzoneEditor.swift` | stepper 20 x 24, arrows 20 x 12 (A2) | "Stick deadzone", "Not set" | `accessibility`: 20 x 20 pt at minimum | System Settings small buttons 17 x 17, 16 x 16 | a change made during a write is dropped; the arrows are 12 high | fix 12.4, 12.14 |
| C12 | Tuning disclosure | `Controllers/Inventory/ControllerDetailView+Facts.swift` | 75 x 16 (A2) | "Tuning" | `disclosure-controls`: "Use a disclosure control to hide details until they're relevant." | none | 16 high, below the 20 pt minimum of `accessibility`; the whole row toggles by source | fix 12.14 |
| C13 | Advanced disclosure | `Controllers/Inventory/ControllerDetailView+Facts.swift` | 94 x 16 (A2) | "Advanced", then "Unit ID", "Parser", "Ownership", "Duplicate exposure risk", "Record", "Output owner", "Controls", "Input mapping", "USB VID/PID", "Input endpoint", "Output endpoint" | `disclosure-controls`; `inclusion` | OBS: "Adv" under "Output Mode" | raw identifiers and endpoints (`2DC8:301B`, `0x82`, `0x02`, `hid-descriptor`) in an opened group; 16 high | fix 13.3, 14.4, 12.14 |
| C14 | Packet capture, draft record, draft from SDL | `Controllers/Actions/ControllerActionViews.swift` | buttons 135 x 24, 113 x 24, 173 x 24, no name (A2) | "Capture packets", "Draft record", "Draft record from SDL" | `buttons`: "Ensure that each button clearly communicates its purpose." | none | developer actions shown to every user; no accessibility name | fix 13.5, 12.14 |
| C15 | Suspended row and failure | `Controllers/Inventory/ControllerDetailView+Facts.swift` | not measured (shown only while suspended or after a failure) | "Suspended", "Resume" | `menus`: "Show people when a menu item is unavailable." | none | a failure is one of the seven places | fix 12.7 |
| C16 | Serial number row | `Controllers/Inventory/SerialNumberVisibility.swift` | 529 x 16 (A2) | "Serial number", "None" | `inclusion` | none | none | keep: it hides a value by default and the user reveals it |
| C17 | Profiles area | `Profiles/List/ProfilesView.swift` | 790 x 536; `ojd-alpha2/main-Profiles.png` | "No profiles", "Create a profile to start assigning controls." | `inclusion`: "Build in ways to learn how to use your app or game." | OpenTabletDriver: presets | an empty state with a sentence and no button | fix 12.15 |
| C18 | Profile list and editor | `Profiles/List/ProfilesView+Body.swift` | not measured (no profile exists) | "Profile", "Virtual output" | `layout` | none | silent guards in the list actions and the editor | fix 12.5 |
| C19 | Profile output policy | `Profiles/Editor/ProfileOutputPolicyView.swift` | not measured | "Virtual output" | `pop-up-buttons` | none | edits a draft until Save, resets `physicalInput` to `.shared` without a message | fix 12.5 |
| C20 | App identifier field | `Profiles/Editor/ProfileCreationSheet.swift` | not measured | the bundle identifier as text | `inclusion` | none | the user types an identifier | fix 15.2 |
| C21 | Library area | `Library/LibraryAreaView.swift` | 790 x 536; `ojd-alpha2/main-Library.png` | "Installed", "Built-in", "No installed records", "No installed mods", "Select a record or mod." | `inclusion` | none | "record" and "mod" are not defined where they show | fix 14.2 |
| C22 | Library scope switch | `Library/LibraryAreaView.swift` | segments 75 x 24 (A2) | "Installed", "Built-in" | `pop-up-buttons`: "Use a pop-up button to present a flat list of mutually exclusive options or states." | System Settings | two states as a segmented control, not a pop-up | keep: two options fit segments; the quote calls for a pop-up for a flat list of more |
| C23 | Library detail | `Library/LibraryDetailView.swift` | not measured (no item selected) | "Select a record or mod." | `inclusion` | none | the detail was not read with an item | fix 10.5 (read the Library area) |
| C24 | Access area | `Access/AccessAreaView.swift` | 790 x 536; `ojd-alpha2/main-Access.png` | "Access & readiness", "Input Monitoring", "Accessibility", "Notifications", "Allowed" | `accessibility`: "Convey information with more than color alone." | System Settings Privacy | the value is the word "Allowed"; a missing permission shows a button per row | fix 12.15 |
| C25 | Local endpoint, WebSocket switches | `Access/AccessAreaView.swift` | 36 x 16 (A2) | "Local endpoint", "WebSocket" | `inclusion` | none | technical terms; no description | fix 14.2, 13.3 |
| C26 | Port field | `Access/AccessAreaView.swift` | 120 x 24 (A2) | "Port", "Automatic" | `inclusion` | System Settings | a technical control for a developer | fix 13.3 |
| C27 | Clients and tokens lists | `Access/AccessAreaView+Lists.swift` | not measured (no client or token present) | "Grant", "Revoke", "Revoke all" | `inclusion` | none | "Grant", "Program" and "Token" are not defined | fix 14.2 |
| C28 | Activity area (Log) | `Activity/ActivityLogView.swift` | outline 790 x 536, rows 773 x 24; `ojd-alpha2/main-Activity.png` | "Stream", "Message", "Output" | `inclusion` | none | the log shows raw identifiers (`VID:0x2DC8 PID:0x301B loc=`) | fix 13.3 |
| C29 | Activity diagnostics | `Activity/ActivityDiagnosticsView.swift` | not measured (Diagnostics view not opened) | the fix buttons' titles | `buttons` | none | not read | fix 10.5 (read the diagnostics) |

## 6. Settings window

| ID | Element | Source | Measured | Term shown | Guideline | Reference | Differences | Decision |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| P01 | Pane tabs | `SettingsWindow/SettingsWindow.swift` | toolbar 600 x 56; General 55 x 56, Notifications 79 x 56, Advanced 64 x 56 (A4) | "General", "Notifications", "Advanced" | `toolbars` | System Settings: sidebar (R3) | tabs with text labels, 56 high where the main toolbar is icon-only and 52 | keep: a settings window with a few panes takes tabs; the term "Advanced" is fix 13.2 |
| P02 | Start at login | `SettingsWindow/GeneralPaneView.swift` | switch 36 x 16; `ojd-alpha2/settings-General.png` | "Start at login", "Open OpenJoystickDriver in the menu bar when you log in." | `menus`: "Show people when a menu item is unavailable." | none | can be unavailable with no reason shown | fix 12.6 |
| P03 | Show in menu bar | `SettingsWindow/SettingsPaneComponents.swift` | switch 36 x 16 | "Show in menu bar", "Keep at least one of Show in menu bar and Show in Dock on." | `the-menu-bar`: "Let people — not your app — decide whether to put your menu bar extra in the menu bar." | Rectangle, MonitorControl: removal by the user | the lock reason is a tooltip (`.help`) and a text line | fix 12.6, 11.6 |
| P04 | Show in Dock | `SettingsWindow/SettingsPaneComponents.swift` | switch 36 x 16 | "Show in Dock" | `the-menu-bar` | none | locked with "Show in menu bar" | fix 12.6, 11.6 |
| P05 | Version and Check Now | `SettingsWindow/GeneralPaneView.swift` | button 93 x 24 | "Version", "0.6.0-alpha.2", "Check Now" | `buttons` | System Settings push buttons 80 x 24 | none | keep: 24 high as System Settings |
| P06 | Check for updates automatically | `SettingsWindow/GeneralPaneView.swift` | switch 36 x 16 | "Check for updates automatically", "Check for a newer version when the app starts." | `inclusion` | none | read only at launch; a change does not apply in the session | fix 12.6 |
| P07 | Include prerelease updates | `SettingsWindow/GeneralPaneView.swift` | switch 36 x 16 | "Include prerelease updates" | `inclusion` | none | no description under it; "prerelease" is not defined | fix 17.5 |
| P08 | Controller connected and disconnected | `SettingsWindow/NotificationsPaneView.swift` | switches 36 x 16; `ojd-alpha2/settings-Notifications.png` | "Connected", "Disconnected" under "Controllers" | `inclusion` | none | "Controller connected" also governs the notification for a controller that needs attention | fix 12.6 |
| P09 | Profile activated and deactivated | `SettingsWindow/NotificationsPaneView.swift` | switches 36 x 16 | "Activated or switched", "Deactivated" under "Profiles" | `inclusion` | none | none | keep: each states what it governs under its heading |
| P10 | Play a sound | `SettingsWindow/NotificationsPaneView.swift` | switch 36 x 16 | "Play a sound" | `layout` | none | none | keep: states its action |
| P11 | Notification permission row | `SettingsWindow/NotificationsPaneView.swift` | button 158 x 24 ("Send Test Notification") | "Banners, Notification Center, and sounds are enabled." | `menus`: "Show people when a menu item is unavailable." | none | a switch returns to off with no message when macOS has denied the permission | fix 12.6 |
| P12 | Install Command-Line Tool | `SettingsWindow/CommandLineToolSection.swift` | button 185 x 24; `ojd-alpha2/settings-Advanced.png` | "Command-Line Tool", "Install Command-Line Tool" | `inclusion` | none | text of 48 pt for one sentence | keep: the sentence states what it links and that macOS asks for a password |
| P13 | Xbox USB Driver | `SettingsWindow/DriverExtensionSection.swift` | button 76 x 24 | "Xbox USB Driver", "Uninstall" | `inclusion` | none | the term "driver" vs "extension" | fix 14.2 |
| P14 | Enable Developer Tools | `SettingsWindow/AdvancedPaneView.swift` | switch 36 x 16 | "Developer Tools", "Show controller input and USB packet tools." | `disclosure-controls`: "Use a disclosure control to hide details until they're relevant." | MonitorControl: "Show advanced settings" | the Developer pane is not opened (it shows only with the switch on) | fix 13.5 |
| P15 | Developer controller pop-up | `Settings/Developer/DeveloperControllerSummaryView.swift` | not measured (Developer pane not opened) | "No controllers connected" | `pop-up-buttons` | none | stays enabled with no option | fix 12.6 |
| P16 | Settings error section | `SettingsWindow/SettingsPaneComponents.swift` | not measured (shown on an error) | "Open System Settings", "Dismiss", "Reset settings" | `buttons` | none | one of the seven places a failure shows | fix 12.7 |

## 7. Input Test

| ID | Element | Source | Measured | Term shown | Guideline | Reference | Differences | Decision |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| I01 | Status row | `Controllers/InputTest/InputTestView+StatusLabels.swift` | group 704 x 36 (A5) | "Input active", "Bluetooth Low Energy · Generic HID · 2DC8:301B" | `accessibility`: "Convey information with more than color alone." | none | "Input active" shows with every control at rest except one (#19); a raw identifier | fix 17.1, 14.2 |
| I02 | Control diagram | `Controllers/InputTest/InputTestLiveViews.swift` | group 704 x 350; images 213 x 27, 104 x 27, 67 x 27, 68 x 27, 325 x 27; sticks 87 x 87 (A5) | "LB / L1", "LT / L2 0,020", "RT / R2 1,000", "Left stick", "Right stick" | `game-controls`: "Prefer using symbols, not text, to refer to game controller elements." | none | mixed symbols and letters; the right trigger read 1,000 at rest | keep: it draws the standard control names and symbols; the 1,000 reading is the controller's report, not a view defect, and is open in 17.1 |
| I03 | Refresh button | `Controllers/InputTest/InputTestWindowController.swift` | 58 x 66 (A5) | "Refresh" | `toolbars` | Notes: 52 high icon-only (R1) | has a text label under the icon | fix 12.12 |
| I04 | Rumble section | `Controllers/InputTest/InputTestView+Body.swift` | heading 48 x 16; text 257 x 16 | "Rumble", "Rumble is not supported by this controller." | `menus`: "Show people when a menu item is unavailable." | none | the section states why it is unavailable (the reason is text, as D20 asks) | keep: it already says why |
| I05 | Rumble switch and Test Rumble | `Controllers/InputTest/InputTestView+Body.swift` | not measured (this controller reports no rumble) | "Test Rumble", "Stop" | `buttons` | none | the switch takes effect only on "Test Rumble" | fix 12.1 |
| I06 | Player indicator and Apply | `Controllers/InputTest/InputTestView+Body.swift` | not measured (this controller shows no player indicator) | "Player indicator", "Apply" | `pop-up-buttons` | none | the choice changes nothing until a separate Apply; nothing says so | fix 12.1 |
| I07 | Color and brightness Apply | `Controllers/InputTest/InputTestView+Body.swift` | not measured (not shown for this controller) | "Apply" | `pop-up-buttons` | none | the same two-click pattern | fix 12.1 |

## Failure stores

Task 12.7. A failed request shows beside the control that started it; the banner holds only problems that concern no single control. Each row names a store, what it holds, and the one place each view keeps it.

| Store | Setter | Shown by now | Keep |
| --- | --- | --- | --- |
| Shared banner (`MainWindow/MainWindowProblems.swift`) | `MainWindowProblem.current` (`:111`), called from `MainWindow/MainWindowContent.swift:141` | `MainWindow/MainWindowProblemBanner.swift:20`, above every area; a service row draws `ServiceReadinessRow` (`Runtime/ServiceReadinessViews.swift`) | banner: the service state (`ServiceReadiness`, including the stopped listener), the driver extension is inactive, a permission is missing, change notifications fall back to polling, the override store cannot be read (`MainWindowProblem.virtualProfileStore`); no single control started these |
| `controllerActionFailures` (`Runtime/RuntimeViewModel.swift:52`) | `Runtime/RuntimeViewModel+ControllerActions.swift:336` through `runControllerAction` (`:342-343`) | Suspended row of the controller detail (`Controllers/Inventory/ControllerDetailView+Facts.swift:24`, `:157`); alert of the status menu (`MenuBar/MenuBarCoordinator+StatusMenu.swift:148`) | beside the control: the Suspended row; the alert stays because the status menu item has closed |
| `problems` of the override view (`Controllers/Inventory/VirtualHIDProfileOverrideView.swift:133`) | override failure `Runtime/RuntimeViewModel+ControllerActions.swift:161-165`, reset failure `:178-180`; store messages `Runtime/RuntimeStatusPresentation+Messages.swift:96` | override and reset failures at `VirtualHIDProfileOverrideView.swift:84` under the pop-up; store messages in the banner (`MainWindowProblem.virtualProfileStore`) | beside the control for the override failure; the store messages concern no control and stay in the banner |
| `SettingsErrorSection` (`SettingsWindow/SettingsPaneComponents.swift:63`) and `SettingsPreferencesModel.controlFailure` | `report(_:beside:)` and `failControl` (`Settings/Preferences/SettingsPreferencesModel.swift:520-533`) | the login item, pause shortcut and test notification failures under their controls through `failure(beside:)` (`:515`); every other error in the section at `GeneralPaneView.swift:16`, `NotificationsPaneView.swift:16`, `AdvancedPaneView.swift:24` | beside the control: the login item and the pause shortcut in General, Send Test Notification in Notifications; the unreadable settings file (`:491`) concerns no control and keeps its section at the top of Advanced |
| `ProfileLibraryModel.lastError` (`Profiles/List/ProfileLibraryModel.swift:25`) | `:252, :258, :293, :310, :332`, and `profileActionError` in `Profiles/List/ProfileListActions.swift:36-53, 208, 274-286, 378, 388`, `ProfilesViewModel.swift:159, 218, 235` | strip above the profile detail (`Profiles/List/ProfilesView+Body.swift:87`), editor footer (`Profiles/Editor/ProfileEditorView+Sections.swift:106`) | beside the control: Delete damaged, Reset Library, Migrate, Pair and Unpair Joy-Cons (done, see below); a request of a toolbar or menu command keeps the strip; the editor's `localError` stays in the footer by the Save button |
| `outputError` of Input Test (`Controllers/InputTest/InputTestState.swift:96`) | `Controllers/InputTest/InputTestViewModel+SessionAndOutputState.swift:457, 470, 499` | `Controllers/InputTest/InputTestView+Body.swift:109, 116` under the section of the control | beside the control: already kept |
| `ActivityActionFailure` (`Activity/ActivityModel.swift:36`) | `MainWindow/MainWindowController+ActivityToolbar.swift:195, 208` | row with Dismiss at the top of the Activity area (`ActivityModel.swift:96`) | the toolbar commands (Save Logs, Show in Finder) have no room for text, so the area row stays; the fix button of a diagnostic check shows its failure on its own check row (`ActivityModel.fixFailures`, `ActivityDiagnosticsView.swift`) |

Profiles area (task 12.7, first slice): `ProfilesViewModel.profileActionFailure` holds the message with a `ProfileActionOrigin` (`Profiles/List/ProfilesViewModel.swift`). A failure of Delete damaged or Reset Library, Migrate, and Pair or Unpair Joy-Cons shows in red under that control (`Profiles/List/ProfilesView+Detail.swift`, `besideError`); only a command of the toolbar or a menu, which has no room for text, still shows in the strip. The import and export file panels and Validate Profile File report to the strip, because their controls are toolbar items and menu items; the editor's footer `localError` sits by the Save button that starts it.

Failures with no store of their own, each shown by the view that owns the control: `DeveloperToolsViewModel.exportError` under the packet capture buttons, `CommandLineToolModel.errorMessage` in the `ojd` link section. Alerts that stay, because the control that started them is a menu item or a toolbar command that has closed or has no room for text: the failed command of the status menu (W09) and the confirmation or notice of the application menu (W11), the refused navigation while a profile change runs, and the failed System Settings open of the driver banner row.

## 12.12 comparison

Each sheet was opened in the installed app and the app window was captured with the sheet attached: `openspec/changes/0-6-0-alpha-3/evidence/sheet-layout/<row>.png`. Width is the `OJDSheetWidth` of the sheet (compact 420, regular 480, wide 520), with the 24 pt padding of `OJDSpacing.sheetPadding`. Hardware: 8BitDo Ultimate 2C (2DC8:301C), which has no motion or touch support.

| Row | Sheet | Width | Result |
| --- | --- | --- | --- |
| S01 | Create a token | compact | no clipped text, no cut-off control, even padding |
| S02 | Access confirmation | compact | same |
| S03 | Issued token | compact | not captured: it opens only after a real token is issued; read at `Access/AccessSheets.swift:82-107` (the monospaced token is not fixed to one line) |
| S04 | Library confirmation | compact | not captured: it opens only to confirm a library install or removal; read at `Library/LibraryAreaView.swift:165-180`, the same layout as S02 |
| S05 | Explain Error Code | compact | no defect |
| S06 | Soak Test | compact | no defect |
| S07 | Controller timed action | compact | no defect (Capture Packets) |
| S08 | New profile | regular, was compact | defect: the Controller pop-up and the explanation text were wider than the 372 pt inside the 420 pt sheet, so the padding was uneven; fixed with `.ojdSheet(.regular)` in `ProfileNameSheet`, recaptured, padding even |
| S09 | Duplicate profile | compact | no defect |
| S10 | Profile details | compact | no defect |
| S11 | Binding behavior | regular | no defect |
| S12 | Macro editor | wide | no defect |
| S13 | Axis adjustment | compact | no defect; the label "Dead zone" and "Stick deadzone" still differ (task 14.2) |
| S14 | Capture an assignment | regular | no defect |
| S15 | Chord and sequence | regular | no defect |
| S16 | Layer | compact | no defect |
| S17 | Layer binding | compact | no defect |
| S18 | Stick modes | regular | no defect |
| S19 | Trigger modes | regular | no defect |
| S20 | Touch modes | regular | not captured: the controller has no touch support, so the section is disabled |
| S21 | Pointer speed | compact | no defect |
| S22 | Motion | regular, height 600 | not captured: the controller has no motion support, so the section is disabled; the fixed height is larger than the default 588 pt window, as in S23 |
| S23 | Regions | regular, height 640 | width has no defect; the fixed height of 640 pt is taller than the default 588 pt window, so the sheet hangs below it (kept: the content scrolls and the audit lists the fixed height) |
| S24 | Pair Joy-Cons | regular | not captured: the button is disabled without two connected Joy-Con halves; no such hardware here |
