# Profile file reference

OpenJoystickDriver stores each profile in its own JSON file, and this page describes their location, shape, and limits.

## File location

Profiles and the active profile selections are in this folder:

```text
~/Library/Application Support/OpenJoystickDriver/
  Profiles/<UUID>.json
  ActiveProfiles.json
```

Each profile file is named after the profile's `id`, in uppercase, such as `Profiles/0F8C2A4E-6B1D-4E7A-9C3F-2D5B8A1E7C40.json`. OJD writes the files with mode `0600` in folders with mode `0700`. OJD replaces each file in one atomic write. For more information, see [Importing and exporting profiles](Remapping-Profiles.md#importing-and-exporting-profiles).

OJD watches the folder. When you add, change, or remove a profile file while OJD runs, OJD reads the folder again and applies the change to connected controllers.

Earlier versions stored all profiles in one file, `RemappingProfiles.json`. OJD does not read that file, and it deletes the file when the service starts. Recreate those profiles.

## Damaged files

OJD skips a profile file that it cannot read, that fails validation, or whose name does not match its `id`. OJD drops an active selection that names a missing or skipped profile. The other profiles stay available. If OJD cannot read `ActiveProfiles.json`, no profile is active.

OJD reports each damaged file in Settings and in `ojd profile list`. You cannot create, change, or activate profiles until every damaged file is resolved. When you remove a damaged profile file, OJD saves a backup named `<file>.backup-<time>-<UUID>` beside it and then deletes the file. When you reset damaged selections, OJD saves a backup of `ActiveProfiles.json` the same way and replaces it with an empty list. Your profiles are kept.

## File shape

A profile file contains one profile object. An exported profile file has the same shape.

`ActiveProfiles.json` contains a list. Each entry has a controller `model` with `vendorID` and `productID`, a `profileID`, and an optional `applicationScope`.

```json
[
  {
    "model": { "productID": 654, "vendorID": 1118 },
    "profileID": "0F8C2A4E-6B1D-4E7A-9C3F-2D5B8A1E7C40"
  }
]
```

## Profile fields

| Field | Required | Meaning |
| --- | --- | --- |
| `id` | Yes | UUID of the profile |
| `name` | Yes | 1 to 80 printable characters |
| `device` | Yes | `vendorID` and `productID` of the controller model, and an optional `unit`: a unit ID from `ojd controller list` that limits the profile to that one controller |
| `applicationScope` | Yes | `{"type":"global"}` or `{"type":"application","bundleIdentifier":"ID"}` |
| `bindings` | Yes | The assignments |
| `outputPolicy` | No | `virtualGamepad` and `physicalInput` |
| `physicalColor` | No | Lighting color |
| `motionTuning`, `gyroOutput`, `joyConPair` | No | Motion settings |
| `stickMappings`, `triggerMappings`, `touchMappings` | No | Analog and touch settings |
| `chords`, `sequences`, `layers` | No | Combinations and layers |

A profile with `device.unit` applies only to the controller with that unit ID, and wins over an active profile for the whole model in the same application scope. Activating it replaces only the active profile of that unit and scope.

OJD rejects unknown keys anywhere in a profile. The file has no schema version field. [`profile.schema.json`](../Resources/Schemas/profile.schema.json) describes the file. Rules that span fields, such as a source used twice, are not in the schema. Check a file against both with `ojd profile validate FILE`.

## Limits

| Item | Limit |
| --- | --- |
| Assignments in one profile | 512 |
| Profiles | 128 |
| Size of one profile file or `ActiveProfiles.json` | 4 MiB |
| Profile name length | 1 to 80 characters |
| Layer name length | 1 to 40 characters |
| Bundle identifier length | 3 to 255 characters |

Profile names must be unique. OJD compares names without regard to case.

## Controller catalog data

You cannot edit the controller catalog. It lives inside the OpenJoystickDriver app. To add a controller or change how OJD drives one, write a controller record. For more information, see [Adding or changing a controller record](Controller-Records.md).

## Scripting

To read and change profiles from scripts, use `ojd profile get`, `ojd profile set`, and `ojd profile validate`. For more information, see [Automating OpenJoystickDriver](Automating-OpenJoystickDriver.md#change-profiles).

## Further reading

- [Remapping profiles](Remapping-Profiles.md)
- [Bindings and actions](Bindings-and-Actions.md)
- [Automating OpenJoystickDriver](Automating-OpenJoystickDriver.md)
- [Updating and uninstalling](Updating-and-Uninstalling.md)
