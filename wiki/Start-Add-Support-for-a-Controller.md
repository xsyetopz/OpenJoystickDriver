# Start: add support for a controller

Teach OJD a controller that it does not know, and install the result.

## Before you begin

Install OJD, grant access, and connect the controller. See [Start: play a game with a controller](Start-Play-a-Game.md). Check [Supported controllers](Supported-Controllers.md) first: your controller may already work.

## Steps

1. Start the service: run `ojd service start`.
2. Find the controller: run `ojd controller list`. The controller shows with its VID:PID. See [Finding your controller ID](Connecting-Controllers.md#finding-your-controller-id).
3. Capture a draft. Run `ojd record draft CONTROLLER > record.plist`, and for 10 seconds press every button and move each stick, trigger, and the D-pad. If the controller is in the SDL database, run `ojd record draft CONTROLLER --from-sdl > record.plist` instead.
4. Open `record.plist`. Check each control against the bytes that the command printed, and correct the file. See [Draft a record from a connected controller](Controller-Records.md#draft-a-record-from-a-connected-controller).
5. Check the file: run `ojd record validate record.plist`.
6. Install it: run `ojd record install record.plist`. The running service applies it. You do not need to unplug the controller.
7. In the **Controllers** area, select the controller and click **Open Input Test...** to see each control.
8. Check which records apply: run `ojd record list`.

To remove your record, run `ojd record remove VVVV:PPPP`. In the app, **Install Record or Mod...** in the **File** menu installs a file too.

## Share the result

[Reporting a bug](Reporting-a-Bug.md) lists what to include. To pack records into one folder, see [Writing controller mods](Writing-Controller-Mods.md).

## Further reading

- [Controller records](Controller-Records.md)
- [Testing a controller](Testing-a-Controller.md)
- [Supported controllers](Supported-Controllers.md)
