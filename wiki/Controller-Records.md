# Adding Or Changing a Controller Record

This page explains how to add a controller that OpenJoystickDriver does not know, or change how it drives a known one, with your own controller record.

> **Note:** This page applies to OpenJoystickDriver 0.5.0-beta.5 and later. Version 0.5.0-beta.4 and earlier do not have all of the features on this page.

## Contents

- [How Records Work](#how-records-work)
- [Choose Who Drives the Controller](#choose-who-drives-the-controller)
- [Describe a Controller's Input Reports](#describe-a-controllers-input-reports)
- [Add Rumble To a Controller](#add-rumble-to-a-controller)
- [Send Fixed Reports At Startup](#send-fixed-reports-at-startup)
- [Tune Timings and the Stick Deadzone](#tune-timings-and-the-stick-deadzone)
- [Select a Model With a Quirk](#select-a-model-with-a-quirk)
- [Connect a Switch 2 Controller Over Bluetooth LE][toc-2]
- [Draft a Record From a Connected Controller][toc-1]
- [Install a Record](#install-a-record)
- [Check Which Records Apply](#check-which-records-apply)
- [Remove a Record](#remove-a-record)
- [Further Reading](#further-reading)

[toc-1]: #draft-a-record-from-a-connected-controller
[toc-2]: #connect-a-switch-2-controller-over-bluetooth-le

## How Records Work

A controller record tells OpenJoystickDriver which protocol family drives one controller model, identified by its VID:PID. The app contains a bundled record for each supported model. Your records are JSON files in `~/Library/Application Support/OpenJoystickDriver/Controllers`. Each file is named after its model in lowercase hexadecimal, for example `045e-028e.json`.

A record has one of two operations:

- `add`: a complete record for a model that has no bundled record.
- `patch`: new values for the `protocol`, `usb`, `ownership`, `output`, `input`, `tuning`, or `bluetoothLE` fields of a bundled record. The other fields stay bundled. A field you set replaces the bundled field whole, except `protocol`: when it names the bundled family, OJD keeps the bundled protocol values you leave out, and the `quirks` you list are added to the bundled quirks. A patch cannot remove a bundled quirk. A `protocol` with a different family replaces the bundled one whole, with its quirks.

A record for a model that uses raw USB works only when macOS lets OpenJoystickDriver open the device directly. The Xbox USB part of the [OJD driver extension](Connecting-Controllers.md#xbox-usb-driver-extension) claims only the Xbox models in its signed product list, and your record cannot add a model to that list. `ojd record validate` says when this applies.

## Choose Who Drives the Controller

macOS serves some controllers natively through the Game Controller framework. OpenJoystickDriver leaves those to macOS by default and only reads their input. The record's `ownership` field changes this:

- `macos`: macOS drives the controller when it can. This is the default.
- `ojd`: OpenJoystickDriver opens the controller exclusively even when macOS supports it, and drives it like a controller macOS does not know.

A raw-USB family, such as `xbox.gip`, has no `ownership` field, because macOS cannot serve those controllers. A new `ownership` value applies when the running service connects the controller again after the record changes. You do not need to unplug it.

## Describe a Controller's Input Reports

Some controllers send fixed input reports that their HID descriptor describes wrongly. A record with the protocol family `hid.report-layout` names where each control sits in the report, in its `input` field. The family requires `input`, and no other family takes it.

```json
"protocol": { "family": "hid.report-layout" },
"input": {
  "report": { "length": 19 },
  "buttons": [
    { "control": "face-south", "byte": 13, "mask": 128 },
    { "control": "view", "byte": 1, "mask": 1 }
  ],
  "axes": [
    { "control": "left-stick-x", "byte": 3 },
    { "control": "left-stick-y", "byte": 4 }
  ],
  "hat": [
    {
      "encoding": "directions",
      "up": { "byte": 9, "mask": 128 },
      "right": { "byte": 7, "mask": 128 },
      "down": { "byte": 10, "mask": 128 },
      "left": { "byte": 8, "mask": 128 }
    }
  ],
  "leftTrigger": { "byte": 17 },
  "rightTrigger": { "byte": 18 }
}
```

Offsets count from the first byte of the report as macOS delivers it.

- `report`: `length` is the shortest report OpenJoystickDriver reads, from 1 to 64 bytes. With `id`, from 1 to 255, byte 0 must hold that report ID, and `length` counts it. OpenJoystickDriver ignores shorter reports and reports with another ID.
- `buttons`: each entry names a control, a `byte`, and a `mask`. The button is pressed while any masked bit is set. Repeat a control to read it from several places. A button cannot be `dpad`, a stick axis, `left-trigger`, or `right-trigger`.
- `axes`: each entry names a stick axis and its `byte`. `bits` is 8, the default, or 16 for a little-endian value in `byte` and the next byte. `signed` reads the value as two's complement. `min` and `max` set the raw range, which defaults to the full range of the width. `inverted` flips the direction. X grows right and Y grows down, as in HID.
- `hat`: a list of sources; the first that reads a direction wins. An `8-way` source reads the masked bits as 0 for north, clockwise to 7 for north-west, and any other value as centered. With `neutralUntilNonzero`, 0 also reads centered until the bits have been nonzero once, for a controller that sends 0 before its hat is live. A `directions` source names one bit for each direction; opposing directions cancel.
- `leftTrigger` and `rightTrigger`: a `byte` read from 0 to 255, a `button` that reads as fully pulled, or both.

Name at least one control. `ojd record validate` checks that every field lies inside the report.

## Add Rumble To a Controller

A `hid.report-layout` or `vendor.ps3-third-party` controller is input-only unless its record names its rumble report in `output.rumble`:

```json
"output": {
  "rumble": {
    "report": { "kind": "output", "id": 2, "length": 8 },
    "leftMain": { "byte": 3 },
    "rightMain": { "byte": 2 }
  }
}
```

- `report` names the HID report: `kind` is `output` or `feature`, `id` is the report ID, and `length` counts every byte, including the report ID.
- `leftMain`, `rightMain`, `leftTrigger`, and `rightTrigger` each give the byte offset of that motor's intensity, from 0 to 255. Name at least one.

OpenJoystickDriver sets the report ID in byte 0 when the ID is not 0, writes each motor's intensity, and sends 0 in every other byte. It sends this report even when macOS drives the controller, because macOS does not drive these motors.

## Send Fixed Reports At Startup

A HID controller that needs a fixed report before it sends input can name it in `output.startup`. The Sixaxis records use one to enable a DualShock 3 over Bluetooth:

```json
"output": {
  "startup": [
    {
      "report": { "kind": "feature", "id": 244, "length": 5 },
      "bytes": [66, 3, 0, 0],
      "transport": "bluetooth-classic"
    }
  ]
}
```

- `report` names the HID report as in `output.rumble`. `length` is 2 to 64 bytes.
- `bytes` lists every byte after the report ID, or every byte of the report when `id` is 0, from 0 to 255.
- `delayMilliseconds` waits before this write, from 0, the default, to 1000.
- `transport` limits the write to `usb`, `bluetooth-classic`, or `bluetooth-le`. Without it, OpenJoystickDriver sends the write on every transport.

List 1 to 16 writes. OpenJoystickDriver sends them in order after the protocol driver's own startup, only when it opens the controller. A failed write is logged and the next one is still sent. Raw-USB families do not take `output.startup`.

## Tune Timings and the Stick Deadzone

A record's `tuning` field changes a value that the protocol driver otherwise sets. Name at least one value. A value you leave out keeps the driver's default.

```json
"tuning": {
  "stickDeadzone": 0.02,
  "hidStartupRecoveryRounds": 3
}
```

| Field | Range | Applies to | What it sets |
| --- | --- | --- | --- |
| `stickDeadzone` | more than 0, less than 1 | every family | The radial deadzone of both sticks on the virtual gamepad, as a fraction of full deflection. Movement past the deadzone is rescaled to the full range. |
| `inputLivenessTimeoutMs` | 1 to 60000 | `sony.dualshock4` | How long the controller can send no input before OpenJoystickDriver releases its held controls. The default is 1000. |
| `hidStartupIntervalMs` | 0 to 60000 | HID families | The gap between the startup writes. |
| `minimumHIDOutputIntervalMs` | 0 to 60000 | HID families | The shortest gap between rumble and lighting reports. 0 sends them without a limit. |
| `hidStartupRecoveryIntervalMs` | 1 to 60000 | `nintendo.switch1` | The gap between startup recovery rounds. The default is 200. |
| `hidStartupRecoveryRounds` | 1 to 10 | `nintendo.switch1` | The startup recovery rounds before OpenJoystickDriver gives up. The default is 2. |

Raw-USB families, such as `xbox.gip`, do not take the two HID timings. The two recovery values apply only to a Switch 1 controller without the `switch-2` or `input-only` quirk, because those controllers have no startup recovery. `ojd record validate` rejects a value outside its range or its families.

A `tuning` in a `patch` replaces the bundled `tuning` whole, so repeat a bundled value that you want to keep. Timings apply when the running service connects the controller again after the record changes.

## Select a Model With a Quirk

Some families drive several models that differ in one detail. A quirk in the record's `protocol.quirks` selects the detail:

- `factory-calibration` (`sony.dualshock4`): read the motion calibration from the controller. Without it, OpenJoystickDriver uses nominal calibration, as for third-party DualShock 4 controllers.
- `wireless-adapter` (`sony.dualshock4`): the Sony DUALSHOCK 4 USB wireless adapter. Output waits until a controller connects to the adapter.
- `strikepad` (`sony.dualshock4`): a controller whose motion reports half the acceleration in the opposite direction on all axes.
- `shield-2015` (`vendor.nvidia-shield`): the 2015 SHIELD controller, which has rumble. Without it, the driver treats the controller as the 2017 model, which is input-only on macOS.
- `wr007` (`hid.descriptor`): Z and Rz are the right stick, Accelerator is LT and Brake is RT, with the WR007 button order.
- `scuf-envision` (`hid.descriptor`): input comes only from report 6, buttons 1 to 10 are mapped, and Z and Rz swap with Rx and Ry.
- `z-rz-brake-left` (`hid.descriptor`): Z and Rz are the right stick, Brake is LT and Accelerator is RT, and button 13 is Home. A controller without a record gets this layout when its report descriptor has Z, Rz, a Brake or Accelerator, and no Rx or Ry.
- `dragonrise` (`hid.descriptor`): Z and Rz are the right stick, buttons follow the DirectInput order (1 to 4 are Y, B, A, X), and buttons 7 and 8 are digital L2 and R2.
- `unprobed-sensors` and `unprobed-touchpad` (`sony.dualsense`): a third-party DualSense that does not answer the capability probe still has motion sensors or a touchpad, and either quirk reads its input in the alternate report layout.
- `forced-vibration` (`sony.dualsense`): a third-party DualSense keeps vibration when its probe reply omits it.
- `receiver` (`sony.dualsense`): a third-party DualSense wireless receiver, which reports with no controller paired. OJD treats the controller as connected only while the packet sequence advances.

A DualShock 4 record takes at most one of `wireless-adapter` and `strikepad`, and a `hid.descriptor` record takes at most one layout quirk. A `sony.dualsense` record with a vendor ID other than Sony's (`054C`) runs as a third-party controller, and its quirks describe that model; a Sony record takes no quirks. Because a `patch` adds quirks and cannot remove them, a patch cannot change a bundled model or layout quirk to another one.

## Connect a Switch 2 Controller Over Bluetooth LE

OpenJoystickDriver connects a Nintendo Switch 2 controller over Bluetooth LE only when its record names the GATT characteristic that carries vibration:

```json
"bluetoothLE": {
  "vibrationCharacteristic": "FA19B0FB-CD1F-46A7-84A1-BBB09E00C149"
}
```

Write the UUID in uppercase. Only a `nintendo.switch1` record with the `switch-2` quirk takes `bluetoothLE`. The service looks for Switch 2 advertisements with the Nintendo vendor ID (`057E`) only.

A Switch 2 record without `bluetoothLE` connects over USB only, and `ojd record validate` and `ojd record show` say so. The bundled Switch 2 records have the section, and a `patch` that leaves `bluetoothLE` out keeps the bundled value. An `add` for a new Switch 2 model needs its own `bluetoothLE`.

## Draft a Record From a Connected Controller

`ojd record draft CONTROLLER` builds a starting record for a connected controller. The service must be running.

1. Run `ojd record draft CONTROLLER > record.json`, where `CONTROLLER` is an ID from `ojd controller list` or the controller's VID:PID.
1. For 10 seconds, press every button and move each stick, trigger, and the D-pad. `--duration SECONDS` changes the time.
1. Read the bytes that changed. For each report byte that took more than one value, the command prints its offset and its lowest and highest value on stderr.

The record maps what the HID report descriptor states plainly: buttons 1 to 11 in the order the `hid.descriptor` family reads them, X, Y, Rx, and Ry sticks, Z and Rz triggers, and the hat, with the `hid.report-layout` family. When nothing maps, it names `hid.descriptor` instead. Check every control against the changed bytes and correct the record before you install it. The record is a `patch` for a model with a bundled record and an `add` otherwise.

## Install a Record

1. Find the VID:PID of your controller. For more information, see [Finding your controller ID](Connecting-Controllers.md#finding-your-controller-id).
1. Write the record file. Set `$schema` to `https://raw.githubusercontent.com/xsyetopz/OpenJoystickDriver/main/Resources/Schemas/controller-override.schema.json`.
1. Check the file. Run `ojd record validate FILE`.
1. Install the file. Run `ojd record install FILE`.

The running service applies the record when the folder changes. It connects each connected controller of that model again with the new record, and leaves other controllers connected. A controller that you disconnected stays disconnected. You do not need to restart the service or unplug the controller.

## Check Which Records Apply

Run `ojd record list`. Each line shows a model, its protocol family, and its layer: `bundled` or `user`.

Run `ojd record show VVVV:PPPP` to see one model's effective record and the layer of each field.

OpenJoystickDriver skips a file that is not valid and uses the bundled record for that model. `ojd record list`, `ojd status`, and `ojd diagnose` name each skipped file and the reason.

## Remove a Record

1. Run `ojd record remove VVVV:PPPP`.
1. Confirm the deletion.

A bundled model then goes back to its bundled record.

## Further Reading

- [Command reference](Command-Reference.md)
- [Supported controllers](Supported-Controllers.md)
- [Generic HID controllers](Supported-Controllers.md#generic-hid-controllers)
