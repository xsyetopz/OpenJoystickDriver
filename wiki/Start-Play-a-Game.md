# Start: Play a Game with a Controller

Install OpenJoystickDriver (OJD), connect a controller, and play.

## Set Up Your Controller

1. Open the disk image, drag **OpenJoystickDriver.app** onto **Applications**, and open it. Keep it in `/Applications`.
2. Click the menu-bar icon and choose **Open OpenJoystickDriver**.
3. Click **Request...** next to each permission (or **Grant Access**), then allow OpenJoystickDriver when macOS asks.
4. In the **Access** area, click **Restart OpenJoystickDriver** if it appears.
5. Connect the controller by USB cable, Bluetooth, or dongle.
6. Click **Controllers**, select it, and click **Open Input Test**.
7. Press buttons and move the sticks. If nothing shows, see [Controller Is Not Detected](Troubleshooting.md#if-a-controller-isnt-detected).
8. Start the game. It reads the [virtual gamepad](Glossary.md#terms) that OJD shows.

To check from Terminal, run `ojd status` and `ojd controller list`. See [Command Line](Command-Line.md#run-a-command).

## If the Game Shows No Input

Steam and SDL games work with the default [virtual gamepad kind](Glossary.md#terms). A game that uses Apple's Game Controller framework, such as Safari, needs another:

1. Run `ojd controller list` and copy your controller's ID.
2. Run `ojd virtual set game-controller-compatible CONTROLLER`.

To undo it, run `ojd virtual reset CONTROLLER`. Some games read neither kind. See [Game and App Compatibility](Playing-Games.md#game-and-app-compatibility).

## Further Reading

- [Playing Games](Playing-Games.md)
- [Supported Controllers](Supported-Controllers.md)
- [Permissions and Security](Permissions-and-Security.md#grant-input-monitoring-and-accessibility)
- [Game Does Not See the Controller](Troubleshooting.md#game-does-not-see-the-controller)
