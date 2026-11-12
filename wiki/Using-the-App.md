# Using the App

Learn the menu-bar item, the main menu, the five areas of the app window, and the Settings window.

## Contents

- [Menu-bar item](#menu-bar-item)
- [Main window](#main-window)
- [Controllers area](#controllers-area)
- [Profiles area](#profiles-area)
- [Library area](#library-area)
- [Access area](#access-area)
- [Activity area](#activity-area)
- [Settings window](#settings-window)
- [Testing a controller](#testing-a-controller)
- [Further reading](#further-reading)

## Menu-Bar Item

![The menu-bar item menu with one controller row, Open OpenJoystickDriver, Settings, and Quit](../docs/screenshots/menu-bar-item.png)

The menu-bar item does five things: it shows the state of each connected controller, chooses a controller's [profile](Glossary.md#terms), pauses or resumes a controller, opens the app window or **Settings**, and quits OJD.
It holds nothing else.
The logs, the error explanations, the support report and the project links are in the **Help** menu of the main menu.

**Show in menu bar** and **Show in Dock** in **Settings** > **General** choose where the app shows its icon.
At least one of them stays on.
To remove the item, hold Command and drag it out of the menu bar.
OJD then stores **Show in menu bar** as off, turns **Show in Dock** on, and opens the app window.
Turn **Show in menu bar** on again in **Settings** > **General**.

### Menu Items

The menu contains these items, from top to bottom:

- A row for each problem that needs you, before everything else.
  **Permission Missing: ...** names a permission OJD lacks and opens the **Access** area at it.
  **Service Not Running: Start It** appears when the app cannot reach its service, and starts the service.
  With no problem, the menu has no such row.
- A row for each connected controller.
  It shows the name with the battery level, the active profile and **Paused** when they apply, and opens the controller's submenu.
  **No Controller Connected** is one dimmed row that appears when the list is empty; it is not a problem.
- **Open OpenJoystickDriver** opens the app window on the area you used last.
- **Settings...** opens the **Settings** window.
- **Quit OpenJoystickDriver** stops OJD.

While a problem row is in the menu, the icon is a warning triangle instead of the controller symbol.
The icon with no controller connected is the controller symbol.
VoiceOver reads the first problem, **no controller connected**, or **ready**.

### Controller Entries

Each controller row has its own submenu:

- A list of the controller's profiles with a checkmark on the active one, ending in **No Profile**.
  Choosing a profile activates it, and choosing **No Profile** deactivates the active one.
  After ten profiles the list ends with **More Profiles**, which opens the **Profiles** area.
- **Pause** pauses input, physical effects, and virtual output for this controller.
  While the controller is paused, the item reads **Resume**.
- **Test Input** opens the Input Test window.
- **Show in Window** opens the controller in the **Controllers** area.
- **Disconnect Bluetooth Connection** is on only for a controller that connects by Bluetooth.
  OJD shows a **Disconnect Wireless Controller?** alert to confirm.
  The controller stays disconnected until you connect it again by hand.
  OJD cannot disconnect a Bluetooth Low Energy controller: turn it off or disconnect it in **System Settings** > **Bluetooth**.

### Quit and Reopen

Quit stops the runtime.
OJD does not start again by itself unless **Start at login** is on.
Start it from the Applications folder or Spotlight; opening it again while it runs shows the app window.
If a settings file turns **Show in menu bar** and **Show in Dock** both off, OJD keeps the menu bar item, opens the app window at launch, and offers to reset the settings.
Closing the window with the red button only hides it.

## Main Window

The app window has a sidebar with five areas.
Press <kbd>Command</kbd>+<kbd>1</kbd> to <kbd>Command</kbd>+<kbd>5</kbd> to select them in this order:

| Area | Use it to |
| --- | --- |
| **Controllers** | See each connected controller, choose who handles it, and test it. |
| **Profiles** | Edit profiles. |
| **Library** | Install, test, and remove controller records and mods. |
| **Access** | Check permissions, and manage the local endpoint for other programs. |
| **Activity** | Read the log, run checks, and explain an error code. |

The window opens on **Controllers** until you choose another area.
**View** > **Hide Sidebar** hides the sidebar.

A banner below the toolbar shows a problem that stops OJD from working:

- **OpenJoystickDriver cannot reach its service**.
- **Xbox USB Driver**, when the [Xbox USB driver](Glossary.md#terms) needs approval, repair, or reinstalling.
- **Permission needed**, with a button that opens **Access**.
- **Live updates unavailable**, when the app cannot receive changes from the service.
  The app then reads the controller list from the service instead, and tries to receive changes again.
  The banner disappears when live updates work again.

### Main Menu

The main menu follows the macOS layout:

- **File** has **Import Profile...**, **Install Record or Mod...**, **Validate...**, **Test Record...**, **Remove**, **Grant a Program...**, **Create a Token...**, **Close**, **Export Profile...**, **Save Support Report...**, **Save Activity Log...**, and **Show in Finder**.
  In the Simple interface the menu holds only **Import Profile...**, **Close**, **Export Profile...**, and **Save Support Report...**.
  **Install Record or Mod...**, **Validate...**, **Test Record...**, **Remove**, **Save Activity Log...**, and **Show in Finder** need the **All Controls** interface; **Grant a Program...** and **Create a Token...** need the **All Controls** interface and **Enable Developer Tools**.
- **Edit** has **Undo**, **Redo**, **Cut**, **Copy**, **Copy All** (needs the **All Controls** interface), **Paste**, **Delete**, **Select All**, and **Find**.
  **Find** (Command-F) moves the keyboard focus to the search field of the list in view: the Library list, or the Activity log.
  It is unavailable in the other areas, in Activity's diagnostics view, and while the toolbar is hidden.
- **View** selects the five areas, switches the Activity view (**Activity**), sets the log filter and line count (**Filter**), runs the diagnostic checks (**Run Checks**), and shows or hides the sidebar and the toolbar.
  **Activity**, **Filter**, and **Run Checks** need the **All Controls** interface.
- **Controller** has **Suspend**, **Resume**, **Test Input**, **Disconnect Bluetooth Connection**, and **Show in Window** for the selected controller.
- **Profile** has **Activate Profile**, **Deactivate Profile**, **New profile**, **Duplicate**, **Delete**, and **Validate profile file**.
  While no profile exists, the **Activate Profile** submenu shows **No Profiles**; while the profile list is loading or cannot be read, it shows **Profiles Unavailable**.
- The commands from **Validate...** to **Create a Token...**, **Show in Finder**, **Copy All**, **Activity**, **Filter**, **Run Checks**, **New profile**, **Duplicate**, **Delete**, and **Validate profile file** do what the toolbar button of the same name does, and are available while that button is shown and enabled.
  The main menu changes with the interface: choose **View** > **Simple** or **All Controls**, and the menus drop or add these commands at once.
- **Help** has **Activity Log** (needs the **All Controls** interface), **Explain Error Code...** (needs the **All Controls** interface), **Copy Support Report**, **Report Problem...**, and **Project Website**.
  For more information, see [Reporting a bug](Reporting-a-Bug.md).

## Controllers Area

![The Controllers area with a DualShock 3 selected and its details](../docs/screenshots/main-controllers.png)

The **Controllers** area lists connected controllers and shows details for the selected controller.
The list updates by itself when a controller connects or disconnects.
If no controller appears, the area shows **No controller connected**.
For more information, see [Controller not detected](Troubleshooting.md).

### Controller Details

The details include these fields when the controller reports them:

- **Active profile**.
- **Publication** (needs the **All Controls** interface): whether OJD publishes a [virtual gamepad](Glossary.md#terms) for the controller.
  A controller that is [handled by macOS](Glossary.md#terms) shows **Native macOS gamepad, not published**.
- **Serving route** (needs the **All Controls** interface): how the input reaches games, for example **OpenJoystickDriver, virtual gamepad** or **macOS, passed through**.
- **Protocol** (needs the **All Controls** interface).
- **Serial number** (needs the **All Controls** interface), blurred until you click its eye button.
- **Battery**, **Charging state**, and **Cable state**.

A **Suspended** row with a **Resume** button appears while the controller is suspended.
**Open Input Test...** opens the test window.
For more information, see [Testing a controller](Testing-a-Controller.md).

### Who Handles the Controller

The **Handled by** picker (needs the **All Controls** interface) appears for a controller that macOS can handle, or whose record gives it to OpenJoystickDriver.
It never appears for a controller that uses raw USB or the Xbox USB driver.
The choices are **macOS** and **OpenJoystickDriver**.
**Set by** names the record layer that holds the choice.
The change takes effect at once and stays after a restart.
The command line does the same with `ojd controller claim` and `ojd controller release`.
For more information, see [Choose who drives the controller](Controller-Records.md#choose-who-drives-the-controller).

A controller that Apple's driver holds also has a section with **Handled by macOS** and a **Claim** button (needs the **All Controls** interface).

### Virtual Gamepad Kind

The **Virtual gamepad kind** menu (needs the **All Controls** interface) appears for controllers that macOS does not handle:

- **Automatic (`<product name>`)** lets OJD choose the [virtual gamepad kind](Glossary.md#terms) and shows the product name games see for it.
- **For Steam and SDL games** forces the Xbox kind for SDL games and Steam.
- **Generic HID gamepad** forces the generic kind.
- **For Apple Game Controller games** forces the Xbox kind for Apple's Game Controller framework.

In **All Controls**, each choice also shows its identifier, as in **For Steam and SDL games (SDLCompatible)**. The command line takes that identifier.

**Apply to** (needs the **All Controls** interface) chooses whether the override applies to every connected controller of the same model or to this controller only.
**Reset all overrides** clears every override.

The change takes effect at once.
**Updating virtual gamepad kind...** shows while it applies.
If activation fails, OJD restores the previous kind and shows a message.
For more information, see [How games see your controller](Playing-Games.md).

### Virtual Gamepad Actions

The detail also has (needs the **All Controls** interface) **Export mapping**, which saves the SDL mapping or the W3C Gamepad description of the virtual gamepad, and **Launch game with virtual gamepad**, which starts a program with the mapping set.

### Advanced Section

The **Advanced** section (needs the **All Controls** interface) holds the identifiers, the input and output endpoints, **Draft Record...**, and **Capture Packets...**.
**Draft Record...**, **Draft Record from SDL...**, and **Capture Packets...** also need **Enable Developer Tools**.
The **Stick deadzone** stepper, the calibration readouts of each stick and trigger, and the **Tuning** group also need the **All Controls** interface.
**USB VID/PID** is the vendor and product ID.
For more information, see [Finding your controller ID](Connecting-Controllers.md).

## Profiles Area

The **Profiles** area lists the profiles and opens the editor for the selected profile.
For more information, see [Profiles](Remapping-Profiles.md).

## Library Area

![The Library area with one installed controller record](../docs/screenshots/main-library.png)

The **Library** area lists the **Controller records** and the **Mods** that are installed (needs the **All Controls** interface).
Select an item to see its fields and files.

- **Install** adds a controller record file or a mod folder.
  **Validate...** checks it first.
  **Replace** overwrites an installed item with the same name.
  **Remove** deletes it after you confirm.
- **Test Record...** replays a packet capture through a record and compares the result with the state you expect.
- **Search** filters the list.

For more information, see [Writing controller mods](Writing-Controller-Mods.md) and [Controller records](Controller-Records.md).

## Access Area

![The Access area with the permission rows and the local endpoint switches](../docs/screenshots/main-access.png)

The **Access** area shows what OJD is allowed to do, and which programs may read your controllers.

### Permissions

Rows show **Input Monitoring**, **Accessibility**, and **Notifications**.
A **Keyboard & pointer** row appears between **Accessibility** and **Notifications** while an active profile posts keyboard, pointer, or scroll events.
Each row shows one value:

- **Allowed**
- **Needs attention**
- **Checking...**
- **Not requested**, **Banners off**, or **Sound off** (only for **Notifications**)

A row that needs attention has a **Request...** button, or **Open System Settings** when macOS already knows the request.
If **Input Monitoring** or **Accessibility** is not allowed, **Restart OpenJoystickDriver** appears.
For more information, see [Permissions](Permissions-and-Security.md#permissions).

### Local Endpoint

The local endpoint lets other programs read controller state.
It shows the socket path with **Copy Socket Path**, and the **WebSocket** with its **Port** and pages folder.
Turning on **Local endpoint** or **WebSocket** asks you to confirm with **Turn On**.
The two switches, **Port**, the lists below, **Grant a Program...**, and **Create a Token...** (needs the **All Controls** interface and **Enable Developer Tools**).
The permission rows above show in both interfaces.

- **Programs with access** lists each granted program with its scopes, **Read** and **Control**, and **Revoke**.
  **Grant a Program...** adds one.
  OJD refuses a program that is not signed.
- **Tokens** lists the tokens.
  **Create a Token...** asks for a name, the scopes, and the web origins that may use the token.
  OJD shows the token once; copy it then.
- **Refused recently** lists the programs and tokens that the endpoint turned away in the last 24 hours.
- **Connected now** lists the open connections.

For more information, see [Automating OpenJoystickDriver](Automating-OpenJoystickDriver.md).

## Activity Area

![The Activity area showing the log with the newest line at the top](../docs/screenshots/main-activity.png)

The **Activity** area has two modes (needs the **All Controls** interface).

- **Log** shows the OpenJoystickDriver log.
  **Stream** selects **All**, **Output**, or **Errors**.
  **Lines** sets how many lines show, **Search** and **Filter** narrow them, and **Show in Finder** opens the log folder.
  If there are no lines, the area shows **No log entries.**
- **Diagnostics** shows the result of **Run Checks** (needs the **All Controls** interface): one row per check with **Passed**, **Warning**, or **Skipped**, and its details.

**Explain Error Code...** in the **Help** menu shows what an error code means (needs the **All Controls** interface).
For more information, see [Reporting a bug](Reporting-a-Bug.md).

## Settings Window

Open **Settings** from the app menu or press <kbd>Command</kbd>+<kbd>,</kbd>.
The window has three panes.

### General

![The General pane of the Settings window](../docs/screenshots/settings-general.png)

**Start at login** opens OJD in the menu bar when you log in.
It needs macOS 13 or later.
If macOS needs approval, allow OJD in **System Settings** > **General** > **Login Items**.

The switch shows what macOS reports, so a change made in **System Settings** appears here.
Turning the switch off here, or running `ojd setting set launchAtLogin false`, also records that you opted out, so OJD does not register itself again at the next start.
A change made only in **System Settings** records nothing.
For more information, see [Command reference](Command-Reference.md).

**Show in menu bar** and **Show in Dock** choose where the icon shows.
When **Show in Dock** is off, the Dock icon shows only while a window is open.

**Pause shortcut** is a keyboard shortcut that pauses every controller, or resumes them when all are paused, from any app (needs the **All Controls** interface).
It is unset until you click **Record Shortcut** and press a key with Control, Option, or Command; Escape cancels, and **Clear** removes it.
Another app that uses the same combination makes the shortcut fail with an error here; record a different one.
`ojd setting set pauseShortcut` sets it too.

**Disconnect idle Bluetooth controllers** disconnects a Bluetooth controller whose input has not changed for the time you choose: 5, 10, 15, 30, or 60 minutes (needs the **All Controls** interface).
It is **Off** until you change it.
It disconnects the way **Disconnect** in the menu does.
A controller that stays on the same input, such as a stick held still, counts as idle.
A controller on a cable or a receiver is never disconnected.
`ojd setting set idleDisconnectMinutes` sets it too, to any whole number of minutes from 1 to 480.

**Interface** chooses how much of the app shows: **Simple** or **All Controls**.
It is **Simple** until you change it.
The **View** menu has the same two items, **Simple** and **All Controls**, with a checkmark on the current one.
`ojd setting set interfaceLevel Simple` or `ojd setting set interfaceLevel Advanced` sets it from a terminal.
For more information, see [Command reference](Command-Reference.md).

At **All Controls**, the developer tools show in **Settings** > **Advanced** while **Enable Developer Tools** is on.
At **Simple**, they stay hidden even with **Enable Developer Tools** on.
Wiki pages mark a control that needs **Advanced** with "(needs the **All Controls** interface)".

At **Simple**, a row tells you when a hidden setting holds a value other than its default.
In a controller detail it counts the virtual gamepad kind you set and a stick dead zone from your own record.
In the profile editor it counts the output policy, axis adjustments, stick, trigger and touch mappings, pointer speed, motion settings and regions that differ from a new profile.
The row reads, for example, "1 hidden setting is changed", and its **Show All Controls** button switches **Interface** to **All Controls**.
With every hidden setting at its default, no row shows.
The Library and Activity areas hold only controls that need the **All Controls** interface, so at **Simple** they show a row that says the area needs the **All Controls** interface, with the same button.

Under **Updates**, **Check for updates automatically** looks for a newer version when the app starts.
Click **Check Now** to look at once.
OJD contacts GitHub only for these checks.
The result is **Up to date**, **Update available**, or **Newer than the latest release**.
Click **View Update** to open the release page.
OJD does not download or install anything.
Select **Include prerelease updates** to include beta versions.

The first time you open the app window after an update, a **What's New** sheet shows the changes of the installed version from the changelog, once.
Click **Done** to close it.

### Notifications

![The Notifications pane of the Settings window](../docs/screenshots/settings-notifications.png)

Turn notifications on for these events:

- **Controllers**: **Connected** and **Disconnected**.
- **Profiles**: **Activated or switched** and **Deactivated**.
- **Play a sound**.

Click **Send Test Notification** to test delivery.
The app asks the service, which announces the test notification back to the app, and shows the result in the window: a denied permission, a failed delivery or no answer. `ojd setting test-notification` does the same from a terminal.
If macOS denies notifications, OJD turns the toggles off.
Click **Open Notification Settings** to fix this.

### Advanced

![The Advanced pane of the Settings window](../docs/screenshots/settings-advanced.png)

- At **Simple**, this pane holds only **Xbox USB Driver**, and a settings error when one shows; the **Command-Line Tool** section and the developer switch need the **All Controls** interface.
- **Command-Line Tool** links `ojd` to this app so that you can run it in Terminal.
  **Install Command-Line Tool** (needs the **All Controls** interface) asks for an administrator password.
- **Xbox USB Driver** shows the state of the Xbox USB driver.
  Only some Xbox One and Xbox Series controllers on USB need it.
  **Uninstall** appears while the driver is active; it asks you to approve and then deactivates the driver.
  For more information, see [Xbox USB driver](Connecting-Controllers.md#xbox-usb-driver).
- **Enable Developer Tools** (needs the **All Controls** interface) shows controller input and USB packet tools in this pane, together with a soak test section.
  At **Simple**, the switch and the tools are both hidden; at **All Controls**, the tools show while the switch is on.
  For more information, see [Finding your controller ID](Connecting-Controllers.md).

If the settings file cannot be read, the app shows **Settings can't be read** with **Reset Settings**. `ojd setting reset` does the same from a terminal.

## Testing a Controller

The Input Test window shows live input, rumble, and lighting.
For more information, see [Testing a controller](Testing-a-Controller.md).

## Further Reading

- [Testing a controller](Testing-a-Controller.md)
- [Permissions](Permissions-and-Security.md#permissions)
- [Controller not detected](Troubleshooting.md)
- [Connection types](Connecting-Controllers.md)
- [Known issues](Known-Issues.md)
- [Updating OpenJoystickDriver](Updating-and-Uninstalling.md)
