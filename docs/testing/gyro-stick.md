# Gyro-to-Stick Hardware Check

The `gyro-stick` profile template turns tilting the controller into stick movement, like steering by tipping a tray. This page checks it on real hardware. User steps: [Create a Gyro to Stick Profile](../../wiki/Sticks-Triggers-Touchpad-and-Motion.md#create-a-gyro-to-stick-profile).

## Status

Not checked. Tests on made-up input cover gyro output to both sticks, but no real controller has run this check. Change the wiki line from `Not checked` only with the filled-in table below.

## Setup

Use a controller with a motion sensor, such as a DualSense 054C:0CE6. Run the service and keep the app open.

## Steps

1. Run `ojd controller list`. Write down the controller, its `VVVV:PPPP`, and how it's connected.
2. Run `ojd profile create Gyro --controller VVVV:PPPP --template gyro-stick --activation button:left-shoulder`. If it says there's no motion sensor, stop.
3. Run `ojd profile activate Gyro`.
4. Run `swift run OpenJoystickDriverGameControllerViewer`. It prints each change of the virtual gamepad as JSON.
5. Hold the left shoulder button and tilt left, right, up, and down. Read the right stick's `x` and `y`.
6. Let go of the button and tilt again. The right stick must stay still.
7. Run `ojd profile create GyroLeft --controller VVVV:PPPP --template gyro-stick --stick left`, then `ojd profile activate GyroLeft`. Tilt without holding any button. The left stick must move.
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
