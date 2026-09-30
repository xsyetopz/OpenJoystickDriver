# Menu-bar item

The menu-bar item shows OpenJoystickDriver status and opens the app window.

## About the icon

OJD has no Dock icon. The app runs from the menu bar. The icon does not change with status. To read status, open the menu. Click the icon to open it.

## Menu items

The menu contains these items, from top to bottom:

- A summary row that you cannot click. It shows readiness, the number of controllers, and the active profile, for example `Ready · 1 controller connected · My controller`. If no profile is active, it shows **No active profile**.
- **Request Access...** appears only when a permission is missing. It starts the macOS permission requests and opens the matching **System Settings** pane.
- **Controllers** lists each connected controller. **No controller connected** appears when the list is empty.
- **Show OpenJoystickDriver** opens the app window on the last pane you used.
- **Settings...** (<kbd>Command</kbd>+<kbd>,</kbd>) opens the **Settings** pane.
- **Help** contains **Open Console...** and **GitHub**.
- **About OpenJoystickDriver** shows the version.
- **Quit OpenJoystickDriver** (<kbd>Command</kbd>+<kbd>Q</kbd>) stops OJD.

## Controller entries

Each controller in the **Controllers** submenu has its own submenu:

- **Controllers...** opens the **Controllers** pane.
- **Disconnect Wireless Controller...** appears only for Bluetooth controllers. OJD shows a **Disconnect Wireless Controller?** alert to confirm. The controller stays disconnected until you connect it again by hand.

## Quit and reopen

Quit stops the runtime. OJD does not start again by itself. Start it from the Applications folder. Opening the app again while it runs shows the window on the **Overview** pane. Closing the window with the red button only hides it.

## Further reading

- [Overview pane](overview-pane.md)
- [Controllers pane](controllers-pane.md)
- [Permissions](../permissions-and-security/permissions.md)
