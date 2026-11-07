# Wii Remote

This page explains how to connect a Wii Remote to OpenJoystickDriver (OJD), what OJD reads from it, and which parts of the remote OJD does not drive.

## Contents

- [What OJD Drives](#what-ojd-drives)
- [Pair the Remote](#pair-the-remote)
- [Reconnect the Remote](#reconnect-the-remote)
- [Buttons, Motion, and Battery](#buttons-motion-and-battery)
- [Extensions](#extensions)
- [LEDs and Rumble](#leds-and-rumble)
- [IR Pointer](#ir-pointer)
- [Speaker](#speaker)
- [Disconnect the Remote](#disconnect-the-remote)
- [Turn the Remote Off](#turn-the-remote-off)
- [Further Reading](#further-reading)

## What OJD Drives

OJD has two Wii Remote records: `057E:0306` with the product string `Nintendo RVL-CNT-01`, and `057E:0330` with the product string `Nintendo RVL-CNT-01-TR`. Both use the `NintendoWii` protocol.

A record matches by product string. The Wii Balance Board (`057E:0306`, `Nintendo RVL-WBC-01`) and the Wii U Pro Controller (`057E:0330`, `Nintendo RVL-CNT-01-UC`) share a VID:PID with a remote, but they match no record. OJD does not drive them.

Nobody confirmed these records on real hardware. The tier is Unverified. For the tiers, see [Supported controllers](Supported-Controllers.md).

## Pair the Remote

OJD does not pair the remote. macOS Bluetooth pairs it, and OJD reads the remote once macOS lists it as a connected device.

1. Open **System Settings** > **Bluetooth**.
2. Press the 1 and 2 buttons on the remote together, or press the red SYNC button in the battery compartment.
3. Select the remote in the list of nearby devices when it appears.

Which of the two ways works on which macOS version, and whether macOS asks for a PIN, is not verified. If the remote does not pair, see [Known issues](Known-Issues.md#a-wii-remote-may-not-pair-with-macos).

## Reconnect the Remote

OJD never reconnects a Bluetooth controller by itself. Press a button on a paired remote to connect it again. Whether a button press reconnects the remote after the Mac sleeps is not verified.

OJD starts a new session each time the remote connects. It asks the remote for its status, sets the report mode, and reads the accelerometer calibration again.

## Buttons, Motion, and Battery

OJD maps the remote's buttons to these controls:

| Remote button | Control |
| --- | --- |
| A | `South` |
| B | `East` |
| 1 | `North` |
| 2 | `West` |
| Minus | `Back` |
| Plus | `Start` |
| Home | `Guide` |
| D-pad | `DpadUp`, `DpadDown`, `DpadLeft`, `DpadRight` |

The accelerometer reaches OJD as motion samples. OJD has no gyroscope data from the remote alone, because the gyroscope sits in the Motion Plus extension, which OJD does not read.

The remote reports its battery level in each status report. OJD shows it as a percentage.

## Extensions

The remote tells OJD when an extension is plugged in or removed. OJD reads the extension type and decodes the extension data. When you unplug an extension, its controls return to neutral.

| Extension | What OJD reads |
| --- | --- |
| Nunchuk | Stick as `LeftStickX` and `LeftStickY`, C as `LeftShoulder`, Z as `LeftTrigger`, and the Nunchuk accelerometer |
| Classic Controller and Classic Controller Pro | Both sticks, the buttons, and the D-pad |

OJD takes the center of each extension stick from the first sample after it identifies the extension. Keep the sticks at rest when you plug the extension in.

The Motion Plus extension is not driven: OJD reads no gyroscope data from it. An extension with an unknown ID is reported with its ID and is not decoded.

## LEDs and Rumble

OJD does not set the remote's player LEDs and does not drive its rumble motor. The remote shows whatever LEDs it shows after it connects.

## IR Pointer

OJD does not read the remote's IR camera. The controls `PointerX`, `PointerY`, and `PointerTracking` exist in the control vocabulary, but the Wii Remote driver sends no value for them. A profile cannot move the mouse with the remote.

The virtual controllers that OJD publishes carry no pointer controls in any case. Only a profile or an SDK client can use them. For the list of controls, see [Controller records](Controller-Records.md).

## Speaker

OJD does not play sound on the remote's speaker. `ojd controller speaker` does not exist.

## Disconnect the Remote

To close the Bluetooth connection, run this command:

```shell
ojd controller disconnect CONTROLLER
```

The command closes the classic Bluetooth connection. The remote stays paired and reconnects when you press a button. You can also select **Disconnect Wireless Controller...** in the controller detail. To remove the pairing, use **System Settings** > **Bluetooth**.

## Turn the Remote Off

OJD has no command that turns the remote off, because no public report does it. To close the connection, see [Disconnect the remote](#disconnect-the-remote). How long the remote stays on when idle is not verified.

## Further Reading

- [Connecting controllers](Connecting-Controllers.md)
- [Supported controllers](Supported-Controllers.md)
- [Known issues](Known-Issues.md)
- [Controller records](Controller-Records.md)
