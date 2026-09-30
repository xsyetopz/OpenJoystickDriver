# Adding or changing a controller record

This article explains how to add a controller that OpenJoystickDriver does not know, or change how it drives a known one, with your own controller record.

A controller record tells OpenJoystickDriver which protocol family drives one controller model, identified by its VID:PID. The app contains a bundled record for each supported model. Your records are JSON files in `~/Library/Application Support/OpenJoystickDriver/Controllers`. Each file is named after its model in lowercase hexadecimal, for example `045e-028e.json`.

A record has one of two operations:

- `add`: a complete record for a model that has no bundled record.
- `patch`: new values for the `protocol` or `usb` fields of a bundled record. The other fields stay bundled.

A record for a model that uses raw USB works only when macOS lets OpenJoystickDriver open the device directly. The [Xbox USB driver extension](xbox-usb-driver-extension.md) claims only the Xbox models in its signed product list, and your record cannot add a model to that list. `ojd record validate` says when this applies.

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
