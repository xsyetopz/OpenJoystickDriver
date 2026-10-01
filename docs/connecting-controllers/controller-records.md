# Adding or changing a controller record

This article explains how to add a controller that OpenJoystickDriver does not know, or change how it drives a known one, with your own controller record.

A controller record tells OpenJoystickDriver which protocol family drives one controller model, identified by its VID:PID. The app contains a bundled record for each supported model. Your records are JSON files in `~/Library/Application Support/OpenJoystickDriver/Controllers`. Each file is named after its model in lowercase hexadecimal, for example `045e-028e.json`.

A record has one of two operations:

- `add`: a complete record for a model that has no bundled record.
- `patch`: new values for the `protocol`, `usb`, `ownership`, or `output` fields of a bundled record. The other fields stay bundled.

A record for a model that uses raw USB works only when macOS lets OpenJoystickDriver open the device directly. The [Xbox USB driver extension](xbox-usb-driver-extension.md) claims only the Xbox models in its signed product list, and your record cannot add a model to that list. `ojd record validate` says when this applies.

## Choose who drives the controller

macOS serves some controllers natively through the Game Controller framework. OpenJoystickDriver leaves those to macOS by default and only reads their input. The record's `ownership` field changes this:

- `macos`: macOS drives the controller when it can. This is the default.
- `ojd`: OpenJoystickDriver opens the controller exclusively even when macOS supports it, and drives it like a controller macOS does not know.

A raw-USB family, such as `xbox.gip`, has no `ownership` field, because macOS cannot serve those controllers. A new `ownership` value applies the next time the controller connects, so unplug it and plug it in again.

## Add rumble to a controller

A `vendor.ps3-third-party` controller is input-only unless its record names its rumble report in `output.rumble`:

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
