## Why

A profile can send one key, button, pointer or gamepad output per assignment, and `sequence` only recognizes an input combo. Users who want a timed series of outputs, a triple tap, a volume key, a stick ring as a button, a profile switch from the controller, or a pointer that slows down as a trigger is pulled cannot express it.
The user asked on 2026-10-25 to give OJD the ultimate remapper. InputConfig (MIT, <https://github.com/ryleighnewman/InputConfig>) has these advances; this change borrows its ideas and no code.
InputConfig issue #11 asks for gyro-to-stick, which InputConfig cannot do because it has no virtual controller. OJD has `gyroOutput` `LeftStick` and `RightStick` and a virtual gamepad, so the work there is a guided template, docs and a hardware check.

## What Changes

- Output macros: a profile holds named macros of timed steps, chord steps, a repeat count and an interrupt-on-release rule. A new `Macro` destination runs one.
- Tap counts: **BREAKING** `doubleTap` is replaced by `multiTap` (2 to 5 taps) in the schema, engine, CLI (`--double-tap` becomes `--multi-tap`), GUI and docs. `turbo` gains `initialDelayMs` and `maxRepeats` for repeat with delay.
- System actions, through public macOS APIs only: media, volume, brightness and keyboard-illumination keys (system-defined key events), Mission Control (NSWorkspace opens the Mission Control app), open an application or URL (NSWorkspace), run a Shortcut (`/usr/bin/shortcuts run`), and type text (Core Graphics Unicode key events).
- Profile control actions: switch profile, set a layer, pause and resume remapping, from a controller control.
- Analog regions as discrete sources: stick rings and sectors, trigger pressure bands, and touchpad rectangles.
- Variable pointer speed: a profile-level `pointerSpeed` scales pointer movement by trigger pressure or stick depth.
- Gyro-to-stick: a `gyro-stick` profile template, a wiki section, and a hardware check document. Code confirmed first (see design.md, D9).
- Missing permissions are named: every action that needs Accessibility (Post Event) access or Automation access reports which one is missing, with an error code; none fails silently.
- MIDI output: `MidiNote` and `MidiControlChange` destinations, sent through a virtual CoreMIDI source named `OpenJoystickDriver` while a profile uses them.
- Spoken phrases: a `Speak` destination that speaks a short text through `AVSpeechSynthesizer`.
- Each action lands with its schema, Swift engine, GUI editor, CLI grammar, localization keys, wiki text and tests.

Out of scope:

- Private or undocumented APIs: DisplayServices brightness, CoreDock calls, SkyLight/CGS, MediaRemote, and any "show desktop", "App Exposé" or "Launchpad" action that needs them. A user can bind a keyboard destination to the shortcut the user has set in System Settings.
- Stick gestures, keyboard or mouse as input, importing InputConfig files, and InputConfig's 46 presets. App-scoped profiles already exist.
- Copying InputConfig code is not planned. OJD moves to PolyForm Noncommercial 1.0.0 plus a commercial license (decision of the user, 2026-10-25). InputConfig is MIT, so its code may be used if its notice is kept in `THIRD_PARTY_NOTICES.md` in the same commit. GPL code may not be used.

Release: the user decided on 2026-10-25 that this change ships in `0.6.0-alpha.2` (the latest tag is `0.6.0-alpha.1`), not in a later release. The `CHANGELOG.md` entry goes in that section.

## Capabilities

### New Capabilities

No spec under `openspec/specs/` covers profiles or remapping, and `platform-neutral-redesign` has no delta for them. Each capability below is a new spec.

- `output-macros`: macro document, timing, repeat, interrupt, and runaway limits.
- `tap-and-repeat`: tap counts from two to five, and repeat with initial delay and count.
- `system-actions`: media, volume, brightness and illumination keys, Mission Control, open application, open URL, run Shortcut, type text.
- `profile-control-actions`: switch profile, set layer, pause and resume.
- `analog-regions`: stick ring and sector, trigger band and touch area sources.
- `pointer-speed`: pointer speed scaled by trigger pressure or stick depth.
- `gyro-stick-output`: gyro to virtual stick template and hardware check.
- `action-permissions`: how a missing permission is detected, named and reported.
- `midi-output`: MIDI note and control-change destinations and the virtual MIDI source.
- `spoken-phrases`: the `Speak` destination.

### Modified Capabilities

None. `release-readiness` lists the check commands; this change adds no command to that list.

## Impact

- `Sources/OpenJoystickDriverKit/Remapping` (`Profile/Controls`, `Profile/Validation`, `Engine/Actions`, `Engine/Chords`, `Engine/Analog`, `Engine/Core/Sink.swift`), a system-action boundary protocol in the core, and its macOS implementation in `Sources/OpenJoystickDriverMacOSPlatform` (the core stays free of AppKit; `docs/development/source-topology.md` enforces it).
- `Sources/OpenJoystickDriverService/Remapping` (routing, profile switch), `Sources/OpenJoystickDriverCLI/Commands/Binding` and `Profile`, `Sources/OpenJoystickDriverPresentation/Profiles` (behavior sheet, assignment editor, analog sheets, Access area).
- `Resources/Schemas/profile.schema.json`, `Resources/ErrorCodes.json` (then `./Scripts/ojd errors regenerate --write`), 22 localization bundles, `wiki/Bindings-and-Actions.md`, `wiki/Sticks-Triggers-Touchpad-and-Motion.md`, `wiki/Profile-File-Reference.md`, `wiki/Permissions-and-Security.md`, `wiki/Command-Reference.md`, `docs/testing/gyro-stick.md`, `CHANGELOG.md`.
- Profile files that use `doubleTap` are rejected like any invalid input; there is no reader for them.
