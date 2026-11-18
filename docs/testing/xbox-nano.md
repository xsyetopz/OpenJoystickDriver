# Xbox Nano Controller Test Record

One hardware test of the Xbox Nano Controller over Bluetooth.

## Test Setup

| Item | Value |
| --- | --- |
| Controller | Xbox Nano Controller, `045E:0B4F`, firmware `6.9.444.0` |
| Connection | Bluetooth Low Energy |
| OpenJoystickDriver | `0.6.0-alpha.1+build.1.19.64.sha.3552be925d7d (1.19.64)`, GitHub release |
| macOS | 26.5.2 (25F84) |
| Mac | MacBook Pro, Apple M3 Pro |
| Virtual gamepad | `ojd virtual set game-controller-compatible 045E:0B4F` |

Without OJD, `GCController` did not list the controller. OJD has no record for this model (`Record: none`) and reads it through its HID descriptor.

## Results

A guided test read each control through Apple's GameController framework.

| Control | Result |
| --- | --- |
| A, B, X, Y | Works |
| LB, RB, LT, RT | Works |
| D-pad | Works |
| View, Menu | Works |
| Both sticks, L3, R3 | Works |
| Xbox button | Not working in GameController |
| Share | Not working |
| Rumble | Not tested |
| Steam and `sdl-compatible` | Not tested |

In Assassin's Creed Shadows, everything worked except the Xbox button and Share.

## Xbox Button

`ojd controller watch` shows `Guide`; `ojd controller capture` shows byte 15 of report 1 change to `0x10`. The GameController test missed the press, matching the limit in [Playing games](../../wiki/Playing-Games.md).

## Share

`ojd controller show` lists the `capture` control. On a Share press, `ojd controller watch` showed no control and `ojd controller capture` no button bit.

With the OJD service stopped, an `IOHIDManager` test app read the controller: A logged three times; Share logged no value and no report other than report 1. The controller does not send Share to macOS. Not verified: the cause.
