# Profile File Reference

OpenJoystickDriver stores each profile in its own XML property list file, and this page describes their location, shape, and limits.

## File Location

Profiles and the active profile selections are in this folder:

```text
~/Library/Application Support/OpenJoystickDriver/
  Profiles/<UUID>.plist
  ActiveProfiles.plist
```

Each profile file is named after the profile's `id`, in uppercase, such as `Profiles/0F8C2A4E-6B1D-4E7A-9C3F-2D5B8A1E7C40.plist`. OJD writes the files with mode `0600` in folders with mode `0700`. OJD replaces each file in one atomic write. For more information, see [Importing and exporting profiles](Remapping-Profiles.md#importing-and-exporting-profiles).

OJD watches the folder. When you add, change, or remove a profile file while OJD runs, OJD reads the folder again and applies the change to connected controllers.

## Damaged Files

OJD skips a profile file that it cannot read, that fails validation, or whose name does not match its `id`. OJD drops an active selection that names a missing or skipped profile. The other profiles stay available. If OJD cannot read `ActiveProfiles.plist`, no profile is active.

OJD reports each damaged file in Settings and in `ojd profile list`. You cannot create, change, or activate profiles until every damaged file is resolved. When you remove a damaged profile file, OJD saves a backup named `<file>.backup-<time>-<UUID>` beside it and then deletes the file. When you reset damaged selections, OJD saves a backup of `ActiveProfiles.plist` the same way and replaces it with an empty list. Your profiles are kept.

## Error Codes

A profile that cannot be used gets the same code wherever OJD reads it: `ojd profile import`, `edit`, `set`, and `validate`, the damaged-file report of `ojd profile list` and `ojd profile recover`, the service requests that carry a profile, and `Scripts/Quality/validate_schemas.py`.

- `E5001`: `apiVersion` is missing or not supported.
- `E3008`: the file is too large, is not an XML property list, or does not decode or validate as a profile. This includes a `kind` other than `Profile`, an unknown field, and an unknown control name.
- `E3006`: another profile already uses the name.
- `E3005`: the file name does not match the profile `id`, or a selection cannot be used.

## File Shape

A profile file contains one profile dictionary. An exported profile file has the same shape.

`ActiveProfiles.plist` contains an array. Each entry is a dictionary with a controller `model` with `vendorID` and `productID`, a `profileID`, and an optional `applicationScope`.

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<array>
 <dict>
  <key>model</key>
  <dict>
   <key>productID</key>
   <integer>654</integer>
   <key>vendorID</key>
   <integer>1118</integer>
  </dict>
  <key>profileID</key>
  <string>0F8C2A4E-6B1D-4E7A-9C3F-2D5B8A1E7C40</string>
 </dict>
</array>
</plist>
```

## Profile Fields

| Field | Required | Meaning |
| --- | --- | --- |
| `apiVersion` | Yes | `openjoystickdriver/v1alpha3` |
| `kind` | Yes | `Profile` |
| `id` | Yes | UUID of the profile |
| `name` | Yes | 1 to 80 printable characters |
| `device` | Yes | `vendorID` and `productID` of the controller model, and an optional `unit`: a unit ID from `ojd controller list` that limits the profile to that one controller |
| `applicationScope` | Yes | a dictionary with `type` `Global`, or with `type` `Application` and `appIDs` set to a list of one or more distinct application IDs; the profile is in force while any one of them is in front. The profile editor writes `appIDs` from its app chooser, which lists running and installed apps and **Other...**, and shows an ID that no installed app has as the ID with **Not installed**. A file with `appID` is refused; `ojd migrate` converts it |
| `bindings` | Yes | The assignments |
| `outputPolicy` | No | `virtualGamepad` and `physicalInput` |
| `physicalColor` | No | Lighting color |
| `motionTuning`, `gyroOutput`, `joyConPair` | No | Motion settings |
| `stickMappings`, `triggerMappings`, `touchMappings` | No | Analog and touch settings |
| `pointerSpeed` | No | Scale of all pointer movement; see [Pointer speed fields](#pointer-speed-fields) |
| `chords`, `sequences`, `layers` | No | Combinations and layers |
| `macros` | No | Named macros that a `Macro` destination runs |

A profile with `device.unit` applies only to the controller with that unit ID, and wins over an active profile for the whole model in the same application scope. Activating it replaces only the active profile of that unit and scope.

OJD rejects unknown keys anywhere in a profile, and a file that holds a `date` or `data` value. The file declares `apiVersion: openjoystickdriver/v1alpha3` and `kind: Profile`, and OJD rejects a file without them. [`profile.schema.json`](../Resources/Schemas/profile.schema.json) describes the file. Rules that span fields, such as a source used twice, are not in the schema. Check a file against both with `ojd profile validate FILE`.

## Rules Across Fields

The schema checks the shape and range of each field. OJD also refuses a profile that breaks one of these rules, with `E3008`:

- An `OpenURL` destination holds an absolute URL whose scheme is not `file`. A `ProfileSwitch` destination holds a profile of the same model, `Next`, or `Previous`. A `Speak` destination holds a voice that the Mac has.
- A binding sets `pulseDurationMs` to a value other than 100 only with the `Pulse` behavior.
- A chord matches its sources in any order. An adaptive trigger effect with kind `Off` has `startPosition` and `strength` 0.
- A chord, a sequence, a gyro activation source, a gyro trackball source, and a layer activator take any source except a whole axis.
- `gyroOutput` sets `activationSource` exactly when `activationMode` is not `Always`.
- `lean.hysteresisDegrees` is less than `thresholdDegrees`. `steering.deadzoneDegrees` is less than `fullScaleDegrees`.
- `stickMapping.flickHysteresis` is less than `flickThreshold`. `stickTuning.innerDeadzone` plus `outerDeadzone` is less than 1.
- `triggerMapping.softThreshold` is less than `fullThreshold`, and `hysteresis` is less than `softThreshold`.
- A touch grid source has `column` less than `columns` and `row` less than `rows`. A touch region has `x` plus `width` and `y` plus `height` of at most 1.
- A stick region has `innerRadius` less than `outerRadius` and `fromDegrees` different from `toDegrees`. A region runs clockwise from up, past 0 when `toDegrees` is below `fromDegrees`. Regions of one stick do not overlap.
- A trigger band has `from` less than `to`. Bands of one trigger do not overlap, and a trigger with a `triggerMappings` entry has no bands.
- A profile name has no space at either end and no control character, at most 80 characters. A layer name follows the same rule with at most 40. The schema counts the length in Unicode code points, and OJD counts characters, so a name with combining marks can pass OJD and fail the schema.
- A binding `remark` is a note of 1 to 200 characters with no space at either end and no control character. It has no effect on the output. Omit the key for no note; an empty `remark` is refused. The length is counted as for a name.

A `Keyboard` destination's `modifiers` are a set. OJD reads them in any order, merges repeats, and writes them sorted.

## Turbo and Multi-Tap Fields

A binding's `turbo` object has `repeatRateHz` and `dutyCycle`, and optionally `initialDelayMs` (0 to 2500, the time from the first press to the first repeat; 0 when omitted) and `maxRepeats` (1 to 500; omitted repeats while held).

A binding's `multiTap` list has entries with `count` (2 to 5, unique in the list), `windowMs` (50 to 1000, from one tap's release to the next press), and `destination`.

## Pointer Speed Fields

`pointerSpeed` has `driver`, `minScale`, `maxScale`, and `curve`, and no other key. All four are required.

- `driver` is a dictionary with `type` `Trigger` or `StickDepth` and `side` `Left` or `Right`.
- `minScale` applies at driver value 0 and `maxScale` at 1. Both are numbers from 0 to 10.
- `curve` is `Linear`, `EaseIn`, `EaseOut`, or `SmoothStep`.

`ojd profile set`, `ojd profile import`, and the profile editor reject a driver that the profile's controller does not report, such as a trigger that only sends a button press. The scale multiplies pointer movement, not scrolling. For more information, see [Set pointer speed](Sticks-Triggers-Touchpad-and-Motion.md#set-pointer-speed).

## Pointer Position Destination

A destination with `type` `PointerPosition` and `axis` `X` or `Y` places the cursor along one axis. It has no other key. Only an axis source can drive it, with an `axisTuning` like `MouseMovement`. The axis value from -1 to 1 maps linearly across the main display, and the other coordinate keeps its value. `pointerSpeed` does not scale it.

## Macro Fields

A macro in `macros` has `id` (UUID), `name`, `steps`, `repeat`, `whileRunning`, and `interruptOnRelease`, and no other key. A binding runs it with a destination that has `type` `Macro` and `macro` set to the macro `id`.

- `repeat` is a count from 1 to 500, or the string `WhileHeld`.
- `whileRunning` is `Ignore` or `Restart`.
- `interruptOnRelease` is `true` or `false`.
- A step is a dictionary with `type` `Tap`, `Press` or `Release` and a `destination` `D`; with `type` `Chord`, a `destinations` array of `D` and `holdMs`; or with `type` `Wait` and `durationMs`. `D` is a keyboard, mouse button, gamepad button, or gamepad D-pad destination. A `Macro` destination in a step is rejected.
- `holdMs` and `durationMs` are 0 to 5000.
- A `MidiNote` or `MidiControlChange` destination in a step is rejected.

OJD rejects a macro name that is not unique without regard to case, a `Macro` destination whose ID is not in `macros`, a pass longer than 30 seconds (the sum of its waits and chord holds), and a counted macro longer than 5 minutes in total. Hardware status: Not checked.

## Limits

| Item | Limit |
| --- | --- |
| Assignments in one profile | 512 |
| Profiles | 128 |
| Size of one profile file or `ActiveProfiles.plist` | 4 MiB |
| Profile name length | 1 to 80 characters |
| Layer name length | 1 to 40 characters |
| Macros in one profile | 16 |
| Steps in one macro | 32 |
| Macro name length | 1 to 40 characters |
| Bundle identifier length | 3 to 255 characters |

Profile names must be unique. OJD compares names without regard to case.

## Controller Catalog Data

You cannot edit the controller catalog. It lives inside the OpenJoystickDriver app. To add a controller or change how OJD drives one, write a controller record. For more information, see [Adding or changing a controller record](Controller-Records.md).

## Scripting

To read and change profiles from scripts, use `ojd profile get`, `ojd profile set`, and `ojd profile validate`. For more information, see [Automating OpenJoystickDriver](Automating-OpenJoystickDriver.md#change-profiles).

## Further Reading

- [Remapping profiles](Remapping-Profiles.md)
- [Bindings and actions](Bindings-and-Actions.md)
- [Automating OpenJoystickDriver](Automating-OpenJoystickDriver.md)
- [Updating and uninstalling](Updating-and-Uninstalling.md)
