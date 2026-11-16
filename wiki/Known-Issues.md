# Known Issues

This page lists current OpenJoystickDriver (OJD) bugs and limits, with a workaround for each.

## Two Global Profiles For One Controller Model Crash the App

If two [profiles](Glossary.md#terms) with global scope are active for the same controller model, OJD crashes at every start.

To recover:

1. Quit OJD.
2. Move `~/Library/Application Support/OpenJoystickDriver/ActiveProfiles.plist` to another folder.
3. Open OJD.

OJD then opens with your profiles and none of them active. Do not activate a second global profile for a model that already has one. For more information, see [App crashes or does not start](Troubleshooting.md#app-crashes-or-does-not-start).

## Rumble Does Not Reach Two Identical Controllers

When two controllers have the same VID:PID, rumble from games and from **System Settings** does not reach either controller. Rumble from the **Input Test** window works.

## Two Controllers With One USB Serial Number

Some controllers report the same VID:PID and the same USB serial number, such as two `057E:2009` pads that both report `000000000001`. OJD gives each one its own [virtual gamepad](Glossary.md#terms). The first pad to connect keeps the identity that its serial gives. The second pad's identity includes its USB port, so apps may treat it as a new controller after you move it to another port. The two pads may swap virtual identities after a replug or a restart, because the first pad to connect keeps the plain identity.

## A Pad Shows the Identity of a Switch Pro Controller

Some pads report `057E:2009` and the USB serial `000000000001`, the identity and serial of a Nintendo Switch Pro Controller, while in their Switch mode. OJD binds every `057E:2009` pad as a Pro Controller, so such a pad gets that driver. `ojd diagnose` names each one in its `switch-placeholder-serial` check, and the check does not change the binding. Other pads can report the same serial, so the serial alone does not identify a model. The pad reports at its own interval in this mode, which OJD does not change.

## A Wii Remote May Not Pair With macOS

OJD does not pair a Wii Remote. macOS Bluetooth pairs it, and OJD reads the remote after macOS connects it. Which macOS versions pair the remote, with the 1 and 2 buttons or with the SYNC button, and whether macOS asks for a PIN, is not verified. If the remote does not appear in **System Settings** > **Bluetooth**, OJD cannot see it. For the steps, see [Pair the remote](Wii-Remote.md#pair-the-remote).

## The Virtual Gamepads Carry No Pointer

The controls `PointerX`, `PointerY`, and `PointerTracking` are in the control vocabulary, but the `SDLCompatible` and `Generic` [virtual gamepad kinds](Glossary.md#terms) publish gamepad controls only. A pointer reaches a profile or an SDK client, not a game that reads the virtual gamepad. The Wii Remote driver sends only `PointerTracking`, and only while the IR camera runs. Nothing switches the camera on yet, and the driver sends no `PointerX` or `PointerY` value. See [IR pointer](Wii-Remote.md#ir-pointer).

## Unplugging a USB Controller Can Crash the App

If you unplug a USB controller or dongle while OJD runs, OJD may crash. It may also leave stale virtual gamepads in **System Settings**. Restart OJD to clear them.

## A Controller With No Location Takes Only a Model Override

**Apply to** in the controller detail offers **This controller** only when macOS reports the controller's location, because the controller's unit ID comes from its location. Without one, the override applies to every controller with the same VID:PID.

## The Xbox USB Driver Reads Only Seven Xbox Controllers

The `com.openjoystickdriver.XboxUSBDevice` driver can only match the seven Microsoft USB IDs in Apple's grant: `045E:02D1`, `045E:02DD`, `045E:02E3`, `045E:02EA`, `045E:0B00`, `045E:0B0A`, and `045E:0B12`. OJD reaches every other wired Xbox controller through raw USB access or lets macOS handle it. Adding an ID to the driver needs a new request to Apple, so the list stays as it is until Apple grants more.

## Another App Reads a USB Controller Directly

Steam or another app can open the USB interface of a controller exclusively. OJD never requests or seizes that interface. The controller detail and `ojd controller list` show **Used by** with the app name and process ID, as the USB host reports them. The state is informational, not an error. OJD opens the controller when the app releases it. Whether the host announces every release has not been confirmed on hardware.

## Some Apps Do Not Read the Virtual Gamepad

CrossOver and older games that use SDL2 or IOHIDManager may not read the virtual Xbox controller. SDL names the `SDLCompatible` virtual gamepad kind "Xbox Adaptive Controller". macOS reports its transport as `Virtual`, so SDL reads its reports as USB Xbox One packets, and the profile sends and takes those packets. Steam reads input and rumble of that profile in a test with a GameSir G7 SE. For more information, see [Game and app compatibility](Playing-Games.md).

## macOS Still Lists Its Own Pad For a DualShock 3

While OJD handles a DualShock 3 over USB, it holds the pad exclusively, so other apps cannot open it and macOS delivers the pad's input only to OJD. macOS still binds `AppleGCHIDUserEventDriver` to the pad and GameController still lists a second, synthetic "PLAYSTATION(R)3 Controller" (`05AC:0004`). Steam lists that pad as a "PLAYSTATION(R)3 Controller" over Bluetooth beside OJD's virtual gamepad, and it gives no input, because OJD holds the real pad. macOS refuses to hand a HID controller from its own driver to an app, so only an [Xbox USB driver](Glossary.md#terms) that Apple grants for the DualShock 3's USB ID could keep macOS off the pad. Choose OJD's virtual gamepad in the game and ignore the other one. The controller's detail shows **Also listed by the system**, and `ojd controller list` names the same state, for every controller that OJD handles while macOS also lists it. When another app already holds the pad exclusively, the controller's detail and `ojd controller list` show "Owned by another app" and OJD reads no input until that app lets go. `ojd diagnose` reports `hid-input-drops`: a warning means the system dropped input reports before OJD read them.

## The OJD Menu Closes While Steam Is Open

Steam brings its window to the front again while connected controllers send input, and macOS closes an open menu of another app when that happens.
Click the OJD icon in the menu bar again, or switch to another app first.

## Further Reading

- [Game does not see the controller](Troubleshooting.md#game-does-not-see-the-controller)
- [Reporting a bug](Reporting-a-Bug.md)
