# Start: Add Support for a Controller

Teach OJD a controller it does not know.

## Before You Begin

Install OJD and connect the controller. See [Start: Play a Game with a Controller](Start-Play-a-Game.md). Check [Supported Controllers](Supported-Controllers.md) first. This page uses Terminal. A record is a small file that describes what a controller sends.

## Add a Record

1. Run `ojd service start`.
2. Run `ojd controller list` to find the controller's ID. See [Finding Your Controller ID](Connecting-Controllers.md#finding-your-controller-id).
3. Run `ojd record draft CONTROLLER > record.plist`, then press every button and move every stick, trigger, and the D-pad for 10 seconds. If the controller is in the SDL database, add `--from-sdl`.
4. Correct `record.plist`. See [Draft a Record from a Connected Controller](Controller-Records.md#draft-a-record-from-a-connected-controller).
5. Run `ojd record validate record.plist`, then `ojd record install record.plist`.
6. Click **Controllers**, select the controller, and click **Open Input Test**.

Run `ojd record list` to see which records apply. Run `ojd record remove VVVV:PPPP` to remove yours.

## Share the Result

See [Reporting a Bug](Reporting-a-Bug.md) and [Writing Controller Mods](Writing-Controller-Mods.md).

## Further Reading

- [Controller Records](Controller-Records.md)
- [Testing a Controller](Testing-a-Controller.md)
- [Supported Controllers](Supported-Controllers.md)
