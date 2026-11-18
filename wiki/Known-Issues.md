# Known Issues

Current OpenJoystickDriver (OJD) bugs and limits, with a workaround for each.

## Rumble Does Not Reach Two Identical Controllers

Two controllers with the same ID get no rumble from games or **System Settings**. Rumble from **Input Test** works. The cause is unknown.

## Two Controllers With One USB Serial Number

Two pads may share an ID and serial, such as `057E:2009` with `000000000001`. OJD gives each its own [virtual gamepad](Glossary.md#terms). The first pad to connect keeps the plain identity. The second pad's identity includes its USB port, so another port may look like a different controller. Pads may swap identities after a replug.

## A Pad Shows the Identity of a Switch Pro Controller

Some pads in Switch mode report the identity of a Switch Pro Controller: `057E:2009` and serial `000000000001`. OJD binds every `057E:2009` pad as a Pro Controller. `ojd diagnose` names each such pad in its `switch-placeholder-serial` check, which doesn't change the binding. The serial alone doesn't identify a model. These pads report at their own interval, which OJD doesn't change.

## A Wii Remote May Not Pair With macOS

macOS pairs the Wii Remote, not OJD. If the remote doesn't appear in **System Settings** > **Bluetooth**, OJD can't see it. Which macOS versions pair it with the 1 and 2 buttons or the SYNC button is untested. See [Pair the Remote](Wii-Remote.md#pair-the-remote).

## Virtual Gamepads Carry No Pointer

The Wii Remote pointer reaches a profile, not a game. The default and Generic [virtual gamepad kinds](Glossary.md#terms) carry gamepad controls only. To move the mouse with the pointer, bind it in a profile. This is untested on a real remote. See [IR Pointer](Wii-Remote.md#ir-pointer).

## Unplugging a USB Controller Can Crash the App

Unplugging a USB controller or dongle while OJD runs may crash it. Reports come from macOS 27.0, when every controller behind one USB hub disconnected at once. OJD keeps loaded the macOS plug-in that each controller uses, which removes the suspected cause. Whether that stops the crash is unconfirmed. If it crashes, open the app again. If stale virtual gamepads stay in **System Settings**, restart OJD. See [Crash When You Unplug a Controller](Troubleshooting.md#crash-when-you-unplug-a-controller).

## The Xbox USB Driver Reads Only Seven Xbox Controllers

The [Xbox USB driver](Glossary.md#terms) matches only the seven USB IDs in Apple's grant, listed in [Building from Source](Building-from-Source.md). OJD reaches other wired Xbox controllers through raw USB access, or macOS handles them.

## Another App Reads a USB Controller Directly

Steam, GOG Galaxy, Chrome, or another app can open a controller's USB interface exclusively. Quit the app to give the controller to OJD. While the app holds it, OJD does not serve the controller, so `ojd controller list` leaves it out. `ojd status` lists it under unserved devices with **Used by** and the app name, as do the Controllers page and the device's details in the app, and `ojd controller show VVVV:PPPP` prints the same sentence. When the host names no app, they say another program is using the controller. That is not an error. OJD takes the controller back when the app lets go.

## Some Apps Don't Read the Virtual Gamepad

CrossOver and older SDL2 or IOHIDManager games may not read the virtual gamepad. Steam reads it, in a test with a GameSir G7 SE. See [Game and App Compatibility](Playing-Games.md#game-and-app-compatibility).

## macOS Still Lists Its Own Pad for a DualShock 3

OJD holds a USB DualShock 3 exclusively, but macOS still lists a second, synthetic "PLAYSTATION(R)3 Controller". Steam shows it beside the OJD virtual gamepad, with no input. macOS won't hand a HID controller from its own driver to an app.

In the game, choose OJD's virtual gamepad and ignore the other. The controller's details show **Also listed by the system**.

If another app holds the pad, the details show "Owned by another app", and OJD reads no input until it lets go. `ojd diagnose` reports `hid-input-drops`. A warning means the system dropped input reports.

## The OJD Menu Closes While Steam Is Open

Steam brings its window forward while controllers send input, which closes the menu. Click the OJD icon again, or switch to another app first.

## Further Reading

- [Game Does Not See the Controller](Troubleshooting.md#game-does-not-see-the-controller)
- [Reporting a Bug](Reporting-a-Bug.md)
