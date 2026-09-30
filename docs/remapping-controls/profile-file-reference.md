# Profile file reference

OpenJoystickDriver stores all profiles in one JSON file, and this page describes its location, shape, and limits.

## File location

The profile library is this file:

```text
~/Library/Application Support/OpenJoystickDriver/RemappingProfiles.json
```

OJD writes the file with mode `0600` in a folder with mode `0700`. OJD replaces the file in one atomic write. Before it removes damaged data, it saves a backup beside the file. For more information, see [Importing and exporting profiles](importing-and-exporting-profiles.md).

Do not edit the library file while OJD runs. To share one profile, export it instead.

## Top-level shape

```json
{
  "profiles": [],
  "activeProfiles": []
}
```

- `profiles`: The list of profiles.
- `activeProfiles`: Optional. The list of active profiles. Each entry has a controller model, a profile `id`, and an optional application scope.

An exported profile file contains one profile object.

## Profile fields

| Field | Required | Meaning |
| --- | --- | --- |
| `id` | Yes | UUID of the profile |
| `name` | Yes | 1 to 80 printable characters |
| `device` | Yes | `vendorID` and `productID` of the controller model |
| `applicationScope` | Yes | `{"type":"global"}` or `{"type":"application","bundleIdentifier":"ID"}` |
| `bindings` | Yes | The assignments |
| `outputPolicy` | No | `virtualGamepad` and `physicalInput` |
| `physicalColor` | No | Lighting color |
| `motionTuning`, `gyroOutput`, `joyConPair` | No | Motion settings |
| `stickMappings`, `triggerMappings`, `touchMappings` | No | Analog and touch settings |
| `chords`, `sequences`, `layers` | No | Combinations and layers |

OJD rejects unknown keys anywhere in a profile. The file has no schema version field. The repository has no JSON schema for profiles.

## Limits

| Item | Limit |
| --- | --- |
| Assignments in one profile | 512 |
| Profiles in the library | 128 |
| Size of the library or one profile | 4 MiB |
| Profile name length | 1 to 80 characters |
| Layer name length | 1 to 40 characters |
| Bundle identifier length | 3 to 255 characters |

Profile names must be unique in the library. OJD compares names without regard to case.

## Controller catalog data

You cannot edit the controller catalog. It lives inside the OpenJoystickDriver app. A scripting API is planned for a later beta.

## Further reading

- [About profiles](about-profiles.md)
- [Assigning buttons and actions](assigning-buttons-and-actions.md)
- [Uninstalling OpenJoystickDriver](../updating-and-uninstalling/uninstalling-openjoystickdriver.md)
