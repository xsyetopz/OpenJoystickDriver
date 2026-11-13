# Wii Remote

Connect a Wii Remote to OpenJoystickDriver (OJD), and see what OJD reads from it, what OJD sets on it, and which parts of the remote OJD does not drive. Nothing on this page is verified on a real Wii Remote unless the text says so.

## Contents

- [What OJD drives](#what-ojd-drives)
- [Pair the remote](#pair-the-remote)
- [Reconnect the remote](#reconnect-the-remote)
- [Buttons, motion, and battery](#buttons-motion-and-battery)
- [Extensions](#extensions)
- [LEDs and rumble](#leds-and-rumble)
- [IR pointer](#ir-pointer)
- [Speaker](#speaker)
- [Disconnect the remote](#disconnect-the-remote)
- [Turn the remote off](#turn-the-remote-off)
- [Further reading](#further-reading)

## What OJD drives

OJD has two Wii Remote records: `057E:0306` with the product string `Nintendo RVL-CNT-01`, and `057E:0330` with the product string `Nintendo RVL-CNT-01-TR`. Both use the `NintendoWii` protocol.

A record matches by product string. The Wii Balance Board (`057E:0306`, `Nintendo RVL-WBC-01`) and the Wii U Pro Controller (`057E:0330`, `Nintendo RVL-CNT-01-UC`) share a VID:PID with a remote, but they match no record. OJD does not drive them.

Nobody confirmed these records on real hardware. The tier is Unverified. For the tiers, see [Supported controllers](Supported-Controllers.md).

## Pair the remote

OJD does not pair the remote. macOS Bluetooth pairs it, and OJD reads the remote once macOS lists it as a connected device.

1. Open **System Settings** > **Bluetooth**.
2. Press the 1 and 2 buttons on the remote together, or press the red SYNC button in the battery compartment.
3. Select the remote in the list of nearby devices when it appears.

Which of the two ways works on which macOS version, and whether macOS asks for a PIN, is not verified. If the remote does not pair, see [Known issues](Known-Issues.md#a-wii-remote-may-not-pair-with-macos).

## Reconnect the remote

OJD never reconnects a Bluetooth controller by itself. Press a button on a paired remote to connect it again. Whether a button press reconnects the remote after the Mac sleeps is not verified.

OJD starts a new session each time the remote connects. It asks the remote for its status, sets the report mode, and reads the accelerometer calibration again. It turns the IR camera on again when the active [profile](Glossary.md#terms) binds the pointer.

## Buttons, motion, and battery

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

The accelerometer reaches OJD as motion samples. The remote alone has no gyroscope, because the gyroscope sits in the Motion Plus extension.

The remote reports its battery level in each status report. OJD shows it as a percentage.

## Extensions

The remote tells OJD when an extension is plugged in or removed. OJD reads the extension type and decodes the extension data. When you unplug an extension, its controls return to neutral.

| Extension | What OJD reads |
| --- | --- |
| Nunchuk | Stick as `LeftStickX` and `LeftStickY`, C as `LeftShoulder`, Z as `LeftTrigger`, and the Nunchuk accelerometer |
| Classic Controller and Classic Controller Pro | Both sticks, the buttons, and the D-pad |

OJD takes the center of each extension stick from the first sample after it identifies the extension. Keep the sticks at rest when you plug the extension in.

OJD also activates a Motion Plus extension, decodes its gyroscope frames in the slow and the fast scale, and decodes the Nunchuk or Classic Controller data that passes through it. OJD measures a rest offset from the first still frames, so keep the remote still after the extension connects. The Motion Plus path is not verified. An extension with an unknown ID is reported with its ID and is not decoded. If OJD cannot read an extension, it reports the error `ExtensionHandshakeFailed` and does not try again. Unplug the extension and plug it in again.

## LEDs and rumble

OJD sets the four player LEDs of the remote, and each report that OJD sends carries the current rumble state. The LED and rumble commands are not verified on a real remote. To set the LEDs, run this command:

```shell
ojd controller player CONTROLLER 1|2|3|4|off
```

Player 1 lights the first LED, player 2 the second, and so on. `off` turns all four LEDs off. A profile can do the same with the target `physical:player:1`.

The rumble motor has two states. Any intensity above 0 turns it on. `ojd controller rumble CONTROLLER` runs it for a duration, and a `physical:rumble` target runs it while a control is held. The remote has no motor strength.

## IR pointer

The remote has an IR camera that sees the two points of a sensor bar. The driver runs the camera only while the active profile of the remote binds `PointerX` or `PointerY` as a source: in a binding, a combo, a sequence, a layer, or as the activation or trackball source of the gyro. Without such a binding the remote reports buttons and the accelerometer only (report mode `0x31`) and the camera stays off. When a profile that binds the pointer becomes active, the driver runs the IR camera setup in the basic format, seven register writes with at least 50 ms between them, set by the tuning key `irWriteIntervalMs`, and switches to the report mode `0x37` (button, accelerometer and IR data, with room for an extension). No IR point appears before the seventh step is acknowledged. When no active profile binds the pointer any more, the driver turns the camera off, goes back to `0x31`, and the pointer returns to neutral. A reconnect starts without the camera, and the first status report turns it on again while the profile still binds the pointer. The extended and full formats are decoded, but nothing selects them.

The IR points are touch contacts on the camera's 1024 by 768 grid, up to four. The driver also computes a pointer: the midpoint of the two largest points, turned by the roll of the remote and mirrored. The pointer is two axes, `PointerX` and `PointerY`, from -1 to 1 with Y positive down, plus the control `PointerTracking`, which is on while two points are visible. With fewer than two points, `PointerTracking` is off and `PointerX` and `PointerY` keep their last values.

The pointer is raw geometry, without smoothing or screen calibration. A profile binds `PointerX` or `PointerY` as a source, and the position of the pointer sets the speed of the mouse: the further from the center, the faster the mouse moves. `PointerX` and `PointerY` are sources only. A binding that sends them to a `gamepad:axis:` target is rejected, because the [virtual gamepads](Glossary.md#terms) that OJD publishes carry no pointer controls. For the list of controls, see [Controller records](Controller-Records.md).

The IR setup, the pointer signs and the sensitivity level are not verified on a real remote. These commands send the pointer to the mouse. A test verified that they bind and that the engine moves the mouse. They are not verified on hardware:

```shell
ojd binding set PROFILE axis:pointer-x move:x
ojd binding set PROFILE axis:pointer-y move:y
```

To place the cursor where the remote points, bind the pointer to the absolute destination instead. `position:x` and `position:y` map the pointer from -1 to 1 across the main display, and the other coordinate keeps its value. The destination has no smoothing and no dead zone, and when the camera loses the sensor bar the pointer keeps its last value, so the cursor stays where it was. These commands are verified by tests only, not on hardware:

```shell
ojd binding set PROFILE axis:pointer-x position:x
ojd binding set PROFILE axis:pointer-y position:y
```

Any other axis can drive the mouse the same way. For example, these commands move the mouse with the stick of a Nunchuk:

```shell
ojd binding set PROFILE axis:left-stick-x move:x
ojd binding set PROFILE axis:left-stick-y move:y
```

For the sources and targets, see [Bindings and actions](Bindings-and-Actions.md).

## Speaker

OJD plays a sound file on the speaker of the remote. The speaker plays mono 4-bit ADPCM at 6000 samples per second, so the sound quality is low. The speaker is not verified on a real remote.

To play a file, run this command:

```shell
ojd controller speaker play CONTROLLER FILE [--volume 0-1]
```

`FILE` must be an uncompressed PCM WAV file with 8, 16, 24, or 32 bits per sample. OJD mixes the channels to mono and converts the rate. `--volume` is a number from 0 to 1, and the default is 1. OJD cuts a clip after `speakerMaxSeconds` seconds (default 10, range 1 to 60) and writes a warning. The command returns when the clip ends.

To stop a clip, run this command:

```shell
ojd controller speaker stop CONTROLLER
```

If the controller has no speaker, the command fails with `E2038` (`speakerUnavailable`). If the file is not a supported WAV file, the command fails with `E2039` (`unsupportedAudioFile`).

## Disconnect the remote

To close the Bluetooth connection, run this command:

```shell
ojd controller disconnect CONTROLLER
```

The command closes the classic Bluetooth connection. The remote stays paired and reconnects when you press a button. You can also select **Disconnect Wireless Controller...** in the controller detail. To remove the pairing, use **System Settings** > **Bluetooth**.

## Turn the remote off

OJD has no command that turns the remote off, because OJD found no public report that does it. To close the connection, see [Disconnect the remote](#disconnect-the-remote). How long the remote stays on when idle is not verified.

## Further reading

- [Connecting controllers](Connecting-Controllers.md)
- [Supported controllers](Supported-Controllers.md)
- [Known issues](Known-Issues.md)
- [Controller records](Controller-Records.md)
- [Bindings and actions](Bindings-and-Actions.md)
