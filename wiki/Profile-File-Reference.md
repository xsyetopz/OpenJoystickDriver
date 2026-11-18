# Profile File Reference

This page lists the location, fields, values, and limits of a profile file. OpenJoystickDriver (OJD) stores each [profile](Glossary.md#terms) in its own XML property list.

## Contents

- [File Location](#file-location)
- [Damaged Files](#damaged-files)
- [Error Codes](#error-codes)
- [File Shape](#file-shape)
- [Profile Fields](#profile-fields)
- [Binding Fields](#binding-fields)
- [Output Policy Fields](#output-policy-fields)
- [Source Types](#source-types)
- [Destination Types](#destination-types)
- [Rules Across Fields](#rules-across-fields)
- [Turbo and Multi-Tap Fields](#turbo-and-multi-tap-fields)
- [Analog, Touch, and Motion Fields](#analog-touch-and-motion-fields)
- [Pointer Speed Fields](#pointer-speed-fields)
- [Macro Fields](#macro-fields)
- [Limits](#limits)
- [Further Reading](#further-reading)

## File Location

Profiles and the active profile selections are in this folder:

```text
~/Library/Application Support/OpenJoystickDriver/
  Profiles/<UUID>.plist
  ActiveProfiles.plist
```

Each file is named after the profile `id` in uppercase. OJD writes files with mode `0600` in folders with mode `0700`, replacing each in one atomic write. OJD applies a file change while it runs. See [Importing and exporting profiles](Remapping-Profiles.md#importing-and-exporting-profiles).

## Damaged Files

OJD skips a profile file that it cannot read, that fails validation, or whose name does not match its `id`, and drops an active selection that names it. Other profiles stay available. If OJD cannot read `ActiveProfiles.plist`, no profile is active.

OJD reports each damaged file in Settings and in `ojd profile list`. You cannot create, change, or activate profiles until each is resolved. Removing a file, or resetting `ActiveProfiles.plist` to an empty list, first saves a backup named `<file>.backup-<time>-<UUID>` beside it.

## Error Codes

`ojd profile` commands report these codes.

- `E5001`: `apiVersion` is missing or unsupported.
- `E3008`: the file is too large, is not an XML property list, or fails to decode or validate, such as a wrong `kind` or an unknown field.
- `E3006`: another profile uses the name.
- `E3005`: the file name does not match the profile `id`, or a selection cannot be used.

## File Shape

A profile file, exported or not, holds one profile dictionary. `ActiveProfiles.plist` holds an array of dictionaries, each with a controller `model` (`vendorID`, `productID`), a `profileID`, and an optional `applicationScope`.

## Profile Fields

| Field | Required | Meaning |
| --- | --- | --- |
| `apiVersion` | Yes | `openjoystickdriver/v1alpha3` |
| `kind` | Yes | `Profile` |
| `id` | Yes | UUID |
| `name` | Yes | 1 to 80 characters |
| `device` | Yes | `vendorID`, `productID`, and optional `unit` (from `ojd controller list`) to limit the profile to one controller |
| `applicationScope` | Yes | `type` `Global`, or `type` `Application` with `appIDs`, a list of distinct application IDs; any one in front applies it. A file with `appID` is refused; `ojd migrate` converts it |
| `bindings` | Yes | Assignments |
| `outputPolicy` | No | `virtualGamepad` and `physicalInput`; see [Output policy fields](#output-policy-fields) |
| `physicalColor` | No | Lighting color |
| `motionTuning`, `gyroOutput`, `joyConPair`, `stickMappings`, `triggerMappings`, `touchMappings` | No | See [Analog, touch, and motion fields](#analog-touch-and-motion-fields) |
| `pointerSpeed` | No | See [Pointer speed fields](#pointer-speed-fields) |
| `chords`, `sequences`, `layers`, `macros` | No | Combinations, layers, and named macros |

A profile with `device.unit` wins over an active profile for the whole model in the same scope. Activating it replaces only that unit and scope.

OJD rejects unknown keys and any `date` or `data` value. [`profile.schema.json`](../Resources/Schemas/profile.schema.json) describes the file but not rules that span fields, such as a source used twice. Check both with `ojd profile validate FILE`.

## Binding Fields

A binding has `id`, `source`, `destination`, and these optional keys:

| Key | Values | Default |
| --- | --- | --- |
| `behavior` | `Hold`, `Toggle`, `TapOnPress`, `TapOnRelease`, `Pulse`, `Press`, `Release` | `Hold` |
| `pulseDurationMs` | 1 to 5000 | 100 |
| `axisTuning` | Dictionary; see below | None |
| `turbo`, `longHold`, `multiTap` | See [Turbo and multi-tap fields](#turbo-and-multi-tap-fields) | None |
| `additionalActions` | Actions with `id`, `destination`, and the binding's `behavior`, `pulseDurationMs`, `turbo`, `longHold`, and `multiTap` | None |
| `remark` | A note; see [Rules across fields](#rules-across-fields) | None |

`axisTuning` requires `deadzone` (0 to 0.95), `digitalActivationThreshold` (0.01 to 1), `gain` (0.1 to 10), `inverted`, and `responseCurve` (`Linear`, `EaseIn`, `EaseOut`, or `SmoothStep`). `longHold` has `destination` and `durationMs` (100 to 5000).

A chord has `id`, `sources` (two or more), `destination`, `mode` (`Modifier` or `Simultaneous`; default `Modifier`), and `windowMs` (1 to 1000; default 50). A sequence has the same keys except `mode`, with `windowMs` 200 to 10000. A layer has `id`, `name`, `activator`, `activationMode` (`Hold` or `Toggle`), `bindings`, `chords`, `sequences`, and optional `motionTuning`.

## Output Policy Fields

`outputPolicy` has two keys, and both are required when `outputPolicy` is present.

| Key | Values | Meaning |
| --- | --- | --- |
| `virtualGamepad` | `Disabled`, `Mapped`, `Passthrough` | No [virtual gamepad](Glossary.md#terms); assigned destinations only; also unassigned controls |
| `physicalInput` | `Shared`, `Exclusive` | `Shared` lets macOS still see the controller. `Exclusive` makes OJD take it. |

For the app labels, see [Output policy](Remapping-Profiles.md#output-policy).

## Source Types

A `source` is a dictionary with a `type`. The other keys depend on the type.

| `type` | Other keys |
| --- | --- |
| `Button` | `button`: a button name from the schema |
| `Dpad` | `direction`: `DpadUp`, `DpadDown`, `DpadLeft`, or `DpadRight` |
| `Axis` | `axis`: an axis name from the schema |
| `AxisDirection` | `axis` and `direction` (`Negative` or `Positive`) |
| `TriggerStage` | `trigger` (`Left` or `Right`) and `stage` (`Soft` or `Full`) |
| `MotionLean` | `direction` (`Left` or `Right`) |
| `TouchContact` | `surface` (`Primary`, `Left`, or `Right`) |
| `TouchGrid` | `surface`, `columns` and `rows` (1 to 16), `column` and `row` (0 to 15) |
| `TouchSwipe` | `surface`, `direction` (`Up`, `Down`, `Left`, or `Right`), `minimumDistance` (0.01 to 1) |
| `StickRegion` | `stick` (`Left` or `Right`), `innerRadius`, `outerRadius`, `hysteresis` (0 to 0.25), and optionally `fromDegrees` and `toDegrees` (0 to 360) |
| `TriggerBand` | `trigger` (`Left` or `Right`), `from`, `to`, `hysteresis` (0 to 0.25) |
| `TouchArea` | `surface`, `x`, `y`, `width`, `height` |

Button and axis names are in [`profile.schema.json`](../Resources/Schemas/profile.schema.json) and [`vocabulary.schema.json`](../Resources/Schemas/vocabulary.schema.json). Gamepad axis names are `LeftStickX`, `LeftStickY`, `RightStickX`, `RightStickY`, `LeftTrigger`, and `RightTrigger`.

## Destination Types

A `destination` is a dictionary with a `type`. The other keys depend on the type.

| `type` | Other keys |
| --- | --- |
| `Keyboard` | `key` (a key name such as `KeyA`, `Digit1`, `Space`, or `ArrowUp`) and `modifiers`, a list of `Alt`, `Control`, `Meta`, and `Shift` |
| `MouseButton` | `button`: `Left`, `Right`, `Middle`, `Back`, or `Forward` |
| `MouseMovement` | `axis`: `X` or `Y` |
| `PointerPosition` | `axis`: `X` or `Y`. Only an axis source drives it, with an `axisTuning` like `MouseMovement`. The value from -1 to 1 maps across the main display. |
| `Scroll` | `axis`: `X` or `Y` |
| `GamepadButton` | `button` |
| `GamepadDpad` | `direction`: `DpadUp`, `DpadDown`, `DpadLeft`, or `DpadRight` |
| `GamepadAxis` | `axis` |
| `Physical` | `physical`: a physical output (see below) |
| `Macro` | `macro`: the `id` of a macro |
| `SystemKey` | `systemKey`: `PlayPause`, `NextTrack`, `PreviousTrack`, `FastForward`, `Rewind`, `VolumeUp`, `VolumeDown`, `Mute`, `BrightnessUp`, `BrightnessDown`, `KeyboardIlluminationUp`, or `KeyboardIlluminationDown`. On the command line, use lowercase hyphenated names such as `volume-up`. |
| `SystemAction` | `action`: `MissionControl`, `Launchpad`, `Screenshot`, `LockScreen`, or `ShowDesktop` |
| `OpenApplication` | `bundleIdentifier` |
| `OpenURL` | `url` |
| `RunShortcut` | `name` |
| `TypeText` | `text` (1 to 128 characters) |
| `ProfileSwitch` | `profile`: a profile `id`, `Next`, or `Previous` |
| `LayerSet` | `layer` (the layer name) and `mode` (`On`, `Off`, or `Toggle`) |
| `Pause` | `mode`: `On`, `Off`, or `Toggle` |
| `Speak` | `text` (1 to 128 characters) and optionally `voice` (a voice identifier) |
| `MidiNote` | `channel` (1 to 16), `note` (0 to 127), `velocity` (1 to 127) |
| `MidiControlChange` | `channel` (1 to 16), `controller` (0 to 127) |

A `Physical` destination has its own `type`:

| `type` | Other keys |
| --- | --- |
| `Rumble` | `motor` (`LowFrequency`, `HighFrequency`, `LeftTrigger`, `RightTrigger`, `LeftHaptic`, or `RightHaptic`) and `intensity` (0 to 1) |
| `PlayerIndicator` | `indicator`: 0, 1, 2, 3, or 4 |
| `Color` | `red`, `green`, `blue` (each 0 to 255) |
| `Brightness` | `intensity` (0 to 1) |
| `AdaptiveTrigger` | `trigger` (`Left` or `Right`) and `effect`: a dictionary with `kind` (`Off` or `Resistance`), `startPosition`, and `strength` (each 0 to 1) |

## Rules Across Fields

Beyond the schema, OJD requires these rules and refuses a profile with `E3008` that breaks one:

- `OpenURL` holds an absolute URL that is not `file`. `ProfileSwitch` holds a profile of the same model, `Next`, or `Previous`. `Speak` holds a voice the Mac has.
- `pulseDurationMs` is other than 100 only with the `Pulse` behavior.
- An adaptive trigger effect of kind `Off` has `startPosition` and `strength` 0.
- Chord, sequence, gyro activation, gyro trackball, and layer activator sources are never a whole axis.
- `gyroOutput` sets `activationSource` exactly when `activationMode` is not `Always`.
- `lean.hysteresisDegrees` is below `thresholdDegrees`. `steering.deadzoneDegrees` is below `fullScaleDegrees`.
- `stickMapping.flickHysteresis` is below `flickThreshold`. `stickTuning.innerDeadzone` plus `outerDeadzone` is below 1.
- `triggerMapping.softThreshold` is below `fullThreshold`, and `hysteresis` is below `softThreshold`.
- A touch grid has `column` below `columns` and `row` below `rows`. A touch area has `x` plus `width` and `y` plus `height` of at most 1.
- A stick region has `innerRadius` below `outerRadius` and `fromDegrees` different from `toDegrees`; it runs clockwise from up, past 0 when `toDegrees` is lower. Regions of one stick do not overlap.
- A trigger band has `from` below `to`. Bands of one trigger do not overlap, and a trigger with a `triggerMappings` entry has no bands.
- A profile name has at most 80 characters, and a layer name at most 40, with no space at either end and no control character. The schema counts code points and OJD counts characters, so a name with combining marks can pass OJD and fail the schema.
- A `remark` is a note of 1 to 200 characters, counted and trimmed like a name. An empty `remark` is refused; omit the key instead.

`Keyboard` `modifiers` are a set: OJD merges repeats and writes them sorted.

## Turbo and Multi-Tap Fields

`turbo` has `repeatRateHz` and `dutyCycle`, and optionally `initialDelayMs` and `maxRepeats`. `initialDelayMs` is 0 to 2500, the time from the first press to the first repeat; omitted means 0. `maxRepeats` is 1 to 500; omitted means repeat while held.

`multiTap` is a list of entries with `count` (2 to 5, unique), `windowMs` (50 to 1000, from one release to the next press), and `destination`.

## Analog, Touch, and Motion Fields

Edit these with `ojd profile edit PROFILE` or `ojd profile set`, such as `ojd profile set Racing triggerMappings.0.mode PreferFull`.

- `stickMappings`: modes `Aim` (default), `Flick`, `FlickOnly`, `RotateOnly`, `PointerArea`, `PointerRing`, `ScrollWheel`, `Steering`. Aim speed 0 to 10000 degrees/s (360). Pointer radius 1 to 10000 points (128). Inner and outer deadzone 0 to 0.95 each, sum below 1 (0.1 and 0). Response exponent 0.1 to 10 (1).
- `triggerMappings`: interaction `Simultaneous`, `Exclusive`, `PreferFull`, `PreferFullCombined`, `ResponsivePreferFull`, or `ResponsivePreferFullCombined`. Soft threshold 0.01 to 0.95 (0.1), full threshold 0.05 to 1 (0.95), quick-pull window 1 to 1000 ms (150).
- `touchMappings`: pointer points per surface 1 to 5000 (1000), stick radius 0.01 to 1 (0.25), deadzone 0 to 0.95 (0.1). Swipe minimum distance default 0.2. Region hysteresis 0 to 0.25 (0.05).
- `motionTuning`: space `Local`, `Player` (default), or `World`. Pitch and yaw sensitivity 0 to 100 (1). Smoothing half-time 0 to 1000 ms (0). Rate threshold 0 to 1000 degrees/s (0). Stillness calibration is on by default.
- `gyroOutput`: `Disabled` (default), `Mouse`, `LeftStick`, or `RightStick`. Trackball velocity halvings per second is 0 to 1000.

## Pointer Speed Fields

`pointerSpeed` requires `driver`, `minScale`, `maxScale`, and `curve`, and no other key. `driver` has `type` (`Trigger` or `StickDepth`) and `side` (`Left` or `Right`). `minScale` applies at driver value 0 and `maxScale` at 1, both 0 to 10. `curve` is `Linear`, `EaseIn`, `EaseOut`, or `SmoothStep`.

OJD rejects a driver the controller does not report. The scale multiplies pointer movement, not scrolling. See [Set pointer speed](Sticks-Triggers-Touchpad-and-Motion.md#set-pointer-speed). This slows the pointer to a quarter while the left trigger is fully pulled:

```sh
ojd profile set Racing pointerSpeed '{"driver":{"type":"Trigger","side":"Left"},"minScale":1,"maxScale":0.25,"curve":"Linear"}'
```

## Macro Fields

A macro has `id`, `name`, `steps`, `repeat`, `whileRunning`, and `interruptOnRelease`, and no other key. A `Macro` destination runs it by `id`.

- `repeat` is 1 to 500, or `WhileHeld`. `whileRunning` is `Ignore` or `Restart`. `interruptOnRelease` is `true` or `false`.
- A step has `type` `Tap`, `Press`, or `Release` with a `destination` `D`; `Chord` with `destinations` (an array of `D`) and `holdMs`; or `Wait` with `durationMs`. `holdMs` and `durationMs` are 0 to 5000. `D` is a keyboard, mouse button, gamepad button, or D-pad destination. OJD rejects `Macro`, `MidiNote`, and `MidiControlChange` in a step.

OJD rejects a macro name that repeats another without regard to case, a `Macro` ID not in `macros`, a pass over 30 seconds (waits plus chord holds), and a counted macro over 5 minutes. Macros are untested on real hardware.

## Limits

| Item | Limit |
| --- | --- |
| Assignments per profile | 512 |
| Profiles | 128 |
| One profile file or `ActiveProfiles.plist` | 4 MiB |
| Macros per profile, steps per macro | 16, 32 |
| Macro name | 1 to 40 characters |
| Bundle identifier | 3 to 255 characters |

Swift enforces the first two (`maximumBindingCount` and `maximumProfileCount` in `Sources/OpenJoystickDriverKit/Remapping/Profile/Document/Profile.swift`); the schema omits them. Profile names are unique without regard to case.

## Further Reading

- [Profiles](Remapping-Profiles.md)
- [Bindings and actions](Bindings-and-Actions.md)
- [Automating OpenJoystickDriver](Automating-OpenJoystickDriver.md#change-profiles)
- [Adding or changing a controller record](Controller-Records.md)
- [Updating and uninstalling](Updating-and-Uninstalling.md)
