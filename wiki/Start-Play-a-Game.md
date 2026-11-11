# Start: play a game with a controller

Install OpenJoystickDriver (OJD), connect a controller, and see it work in a game.

## Steps

1. Open the OpenJoystickDriver disk image, drag **OpenJoystickDriver.app** onto the **Applications** shortcut, and open it from the Applications folder. Keep the app in `/Applications`.
2. Click the controller icon in the menu bar. If the menu shows **Grant Access**, click it. In **System Settings** > **Privacy & Security**, allow **OpenJoystickDriver** in **Input Monitoring** and in **Accessibility**. Without the first, OJD cannot read your controller. Without the second, the virtual controller does not work.
3. In the app window, open the **Access** area. If the button **Restart OpenJoystickDriver** shows, click it.
4. Connect the controller with USB, Bluetooth, or a 2.4 GHz dongle.
5. Open the **Controllers** area, select your controller, and click **Open Input Test...**. Press buttons and move sticks. The window shows each control. If it shows nothing, see [Controller not detected](Troubleshooting.md).
6. Start the game. The game reads the virtual controller that OJD publishes.

To check from Terminal, run `ojd status` and `ojd controller list`. The [command line page](Command-Line.md#run-a-command) shows how to get `ojd`.

## If the game shows no input

- Games made with SDL, and Steam, read the virtual controller that OJD chooses for you. Do nothing.
- A game that uses Apple's GameController framework, such as Safari, needs another virtual controller. Run `ojd virtual set game-controller-compatible CONTROLLER`, where `CONTROLLER` is an ID from `ojd controller list`. Run `ojd virtual reset CONTROLLER` to go back to the automatic choice.
- Some games read neither. [Playing games](Playing-Games.md#game-and-app-compatibility) lists what testers found.

## Further reading

- [Playing games](Playing-Games.md)
- [Supported controllers](Supported-Controllers.md)
- [Permissions and security](Permissions-and-Security.md#grant-input-monitoring-and-accessibility)
- [Game does not see the controller](Troubleshooting.md)
