# Gyro-to-Stick Hardware Check

Hardware check of the `gyro-stick` profile template. User steps: [Create a Gyro to Stick Profile](../../wiki/Sticks-Triggers-Touchpad-and-Motion.md#create-a-gyro-to-stick-profile).

## Status

Not checked. Constructed tests cover gyro output to both sticks; no controller has run this check. Change the wiki line from `Not checked` only with the record below.

## Test Setup

Use a controller with a motion sensor, such as a DualSense 054C:0CE6. Run the service; keep the app open.

## Steps

1. Run `ojd controller list`. Note the controller, `VVVV:PPPP`, and connection.
2. Run `ojd profile create Gyro --controller VVVV:PPPP --template gyro-stick --activation button:left-shoulder`. If it reports no motion sensor, stop.
3. Run `ojd profile activate Gyro`.
4. Run `swift run OpenJoystickDriverGameControllerViewer`. It prints each virtual gamepad change as JSON.
5. Hold the left shoulder button and tilt left, right, up, down. Read the right stick `x` and `y`.
6. Release the button and tilt again. The right stick must stay at rest.
7. Run `ojd profile create GyroLeft --controller VVVV:PPPP --template gyro-stick --stick left`, then `ojd profile activate GyroLeft`. Tilt with no button. The left stick must move.
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
