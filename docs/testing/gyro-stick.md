# Gyro-to-Stick Hardware Check

This page is the hardware check of the `gyro-stick` profile template. For the user-facing steps, see [Create a Gyro to Stick Profile](../../wiki/Sticks-Triggers-Touchpad-and-Motion.md#create-a-gyro-to-stick-profile).

## Status

Not checked. Constructed tests cover gyro output to the left and right stick; no controller has run this check. Fill in the record below and change the wiki line from `Not checked` only with that record.

## Test setup

Use a controller with a motion sensor, for example a DualSense `054C:0CE6`. Run the service and keep the app open.

## Steps

1. Run `ojd controller list` and note the controller, its `VVVV:PPPP`, and the connection (USB or Bluetooth).
2. Run `ojd profile create Gyro --controller VVVV:PPPP --template gyro-stick --activation button:left-shoulder`. The command prints the new profile. If it fails with a message that names the model and says it has no motion sensor, stop: the model cannot run this check.
3. Run `ojd profile activate Gyro`.
4. Run `swift run OpenJoystickDriverGameControllerViewer`. It lists the virtual gamepad and prints each change as a JSON line.
5. Hold the left shoulder button and tilt the controller to the left, right, up, and down. Read the `x` and `y` of the right stick in the viewer.
6. Release the left shoulder button and tilt again. The right stick must stay at rest.
7. Run `ojd profile create GyroLeft --controller VVVV:PPPP --template gyro-stick --stick left`, then `ojd profile activate GyroLeft`. Tilt the controller without holding any button. The left stick must move.
8. Run `ojd profile deactivate GyroLeft` and `ojd profile deactivate Gyro`.

## Record

| Field | Value |
| --- | --- |
| Controller | |
| VID:PID | |
| Connection | |
| OJD version | |
| macOS version | |
| Right stick moved while the shoulder button was held (step 5) | |
| Right stick stayed at rest after release (step 6) | |
| Left stick moved with no activation control (step 7) | |
| Notes | |
