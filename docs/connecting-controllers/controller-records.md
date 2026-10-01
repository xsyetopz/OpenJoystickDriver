# Adding or changing a controller record

This article explains how to add a controller that OpenJoystickDriver does not know, or change how it drives a known one, with your own controller record.

A controller record tells OpenJoystickDriver which protocol family drives one controller model, identified by its VID:PID. The app contains a bundled record for each supported model. Your records are JSON files in `~/Library/Application Support/OpenJoystickDriver/Controllers`. Each file is named after its model in lowercase hexadecimal, for example `045e-028e.json`.

A record has one of two operations:

- `add`: a complete record for a model that has no bundled record.
- `patch`: new values for the `protocol`, `usb`, `ownership`, `output`, or `input` fields of a bundled record. The other fields stay bundled.

A record for a model that uses raw USB works only when macOS lets OpenJoystickDriver open the device directly. The [Xbox USB driver extension](xbox-usb-driver-extension.md) claims only the Xbox models in its signed product list, and your record cannot add a model to that list. `ojd record validate` says when this applies.

## Choose who drives the controller

macOS serves some controllers natively through the Game Controller framework. OpenJoystickDriver leaves those to macOS by default and only reads their input. The record's `ownership` field changes this:

- `macos`: macOS drives the controller when it can. This is the default.
- `ojd`: OpenJoystickDriver opens the controller exclusively even when macOS supports it, and drives it like a controller macOS does not know.

A raw-USB family, such as `xbox.gip`, has no `ownership` field, because macOS cannot serve those controllers. A new `ownership` value applies the next time the controller connects, so unplug it and plug it in again.

## Describe a controller's input reports

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

## Add rumble to a controller

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

## Install a record

1. Find the VID:PID of your controller. For more information, see [Finding your controller ID](finding-your-controller-id.md).
1. Write the record file. Set `$schema` to `https://raw.githubusercontent.com/xsyetopz/OpenJoystickDriver/main/Resources/Schemas/controller-override.schema.json`.
1. Check the file. Run `ojd record validate FILE`.
1. Install the file. Run `ojd record install FILE`.

The running service applies the record when the folder changes. You do not need to restart it.

## Check which records apply

Run `ojd record list`. Each line shows a model, its protocol family, and its layer: `bundled` or `user`.

Run `ojd record show VVVV:PPPP` to see one model's effective record and the layer of each field.

OpenJoystickDriver skips a file that is not valid and uses the bundled record for that model. `ojd record list`, `ojd status`, and `ojd diagnose` name each skipped file and the reason.

## Remove a record

1. Run `ojd record remove VVVV:PPPP`.
1. Confirm the deletion.

A bundled model then goes back to its bundled record.

## Further reading

- [Command reference](../command-line/command-reference.md)
- [Supported controllers](supported-controllers.md)
- [Generic HID controllers](generic-hid-controllers.md)
