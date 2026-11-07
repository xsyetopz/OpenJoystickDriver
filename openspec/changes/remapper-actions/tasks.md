# Tasks: Remapper Actions

Each group owns its tests and documentation. Order follows dependencies: tests first, then schema and model, then engine, then CLI, GUI, localization and docs.

## Working Agreements

- Ships in `0.6.0-alpha.2`. The `CHANGELOG.md` entry names the **BREAKING** `doubleTap` removal; no other file names history.
- No compatibility: `doubleTap` and `--double-tap` are removed everywhere in group 4 (`rg -n "doubleTap|double-tap|DoubleTap" Sources Tests Resources wiki docs Scripts` is empty at its end, apart from `CHANGELOG.md`).
- The limits in the specs are the user's (2026-10-25, `design.md` "Decisions of the User"). The tap count range and the pointer scale range are open there and block no task.
- Do not hand-edit generated files. After `Resources/ErrorCodes.json` changes run `./Scripts/ojd errors regenerate --write`. After `Resources/Schemas/profile.schema.json` changes run `./Scripts/ojd check schemas`.
- Localization: each new string is a key in `en-US` with one translator comment, then in all 22 bundles; review each translation against `LOCALIZATION.md` (Meaning, Punctuation). Permission and OS words go under `platform.macos.`.
- Build once per group, test the changed area, run `just check` once at the end of the group; rerun only failures.
- A task is done only after its Verify command ran in the session that closes it.

## 1. Baseline and Gyro-to-Stick Confirmation

- [x] 1.1 Run the existing gyro stick tests and list which of rotation, activation, deadzone and virtual-gamepad requirements they cover. Verify: `swift test --filter OpenJoystickDriverKitTests.GyroRoutingTests` passes, and the listing is added to this task's closing note.
  - Closing note: `swift test --filter OpenJoystickDriverKitTests.GyroRoutingTests` passed, 8 tests in 1 suite. Rotation: `gyroStickUsesAngularSpeedAndNeutralizesAtSampleTimeout`, `mouseUsesSampleTimeAndDoesNotReplayBaselineOrDuplicateSamples`. Activation: `activationWaitsForFreshBaselineAndDeactivationClearsStick`, `layerTuningNeutralizesStickAndResumesAfterFreshBaseline`, `calibrationResetImmediatelyNeutralizesGyroStick`. Virtual gamepad: `activationConsumptionControlsOriginalVirtualButton`, `gyroTimeoutPreservesOtherBindingsOnTheSameStick`. Deadzone: not covered; the one `deadzone: 0` sets a stick binding, not the gyro. The spec has no gyro deadzone requirement (only REQ-48 and REQ-49), so REQ-48 tests in 9.1 cover the template.
- [x] 1.2 Confirm each Apple API of design D5 against Apple's documentation: system-defined `CGEvent` key events, `NSWorkspace` open for an application and a URL, the Mission Control application path, `/usr/bin/shortcuts run`, `CGEventKeyboardSetUnicodeString`, `IsSecureEventInputEnabled`. Correct the table in `design.md` where it differs. Verify: every row of the D5 table carries a documentation URL or the word `unconfirmed`, and each `unconfirmed` row is moved to Open Questions.
- [ ] 1.3 Record the permission each D5 API needs on this Mac with a throwaway program outside the repository (not committed). Verify: a table of API, permission prompt seen or not, macOS version from `sw_vers`, is pasted into the closing note.

## 2. Permissions Foundation (REQ-50 to REQ-52)

- [x] 2.1 Write failing tests first: a stub `RemappingSystemActionPerforming` that reports missing Post Event or Automation access produces a named coded error and no output; `requiresSystemInputAccess` and a new needed-permission list include destinations in layers and macros. Verify: `swift test --filter OpenJoystickDriverKitTests.ActionPermissionTests` fails for the stated reason.
- [x] 2.2 Add the permission list type and the `RemappingSystemActionPerforming` protocol to the core (no AppKit import), add the error codes to `Resources/ErrorCodes.json` in domain `Remapping`, and regenerate. Verify: `./Scripts/ojd errors regenerate --check` passes, `rg -n "import (AppKit|SwiftUI|Cocoa)" Sources/OpenJoystickDriverKit` is empty, and 2.1 passes.
- [ ] 2.3 Show the missing permissions in the activation alert and `ojd profile activate`; add the `--confirm-actions` flag and the confirmation for launching actions (REQ-51). Verify: `swift test --filter OpenJoystickDriverKitTests.CommandLine` and `swift test --filter OpenJoystickDriverPresentationTests` pass with a test per scenario of REQ-51.
- [ ] 2.4 Add the `platform.macos.` keys for permission names with comments in all 22 bundles; review against `LOCALIZATION.md`. Document in `wiki/Permissions-and-Security.md` which process holds each permission (result of 1.3). Verify: `python3 Scripts/Quality/check_localization_keys.py` and `swift test --filter OpenJoystickDriverKitTests.LocalizationTests` pass; `git diff --check` passes.

## 3. Output Macros (REQ-27 to REQ-31)

- [x] 3.1 Write failing tests first in `Tests/OpenJoystickDriverKitTests/Remapping/Engine/Actions/MacroScheduleTests.swift` and `.../Profile/Validation/MacroValidationTests.swift`: ordered steps with waits on the fake clock, chord hold and reverse release, repeat count, `WhileHeld`, `Ignore` and `Restart`, interrupt on release, every stop path of REQ-29 leaves nothing down, run-time bound of REQ-30, nesting rejected, unknown macro rejected. Verify: `swift test --filter OpenJoystickDriverKitTests.MacroScheduleTests` and `swift test --filter OpenJoystickDriverKitTests.MacroValidationTests` pass (the tests landed with the code, so no run shows them failing first).
- [x] 3.2 Add `macros` and the `Macro` destination to the Swift model, strict coding, validation (limits from REQ-27 and REQ-30) and `profile.schema.json`. Verify: `swift test --filter OpenJoystickDriverKitTests.MacroValidationTests` and `./Scripts/ojd check schemas` pass.
- [x] 3.3 Implement the macro state machine in `Engine/Actions` on the engine clock, with one release function for every stop path; fail-closed releases macro outputs through the reference-counted held outputs. Verify: `swift test --filter OpenJoystickDriverKitTests.MacroScheduleTests` passes, including the stop-path cases.
- [x] 3.4 Add `ojd macro list|show|set|remove` and the `macro:NAME` target to `ojd binding set`. Verify: `swift test --filter OpenJoystickDriverCLITests.MacroCommandTests` passes; `ojd binding set PROFILE button:south macro:Combo` on a temporary profile saves, and with a missing macro fails with the named error.
- [ ] 3.5 Add the macro editor (list, steps, reorder, repeat, interrupt, whileRunning) and the Macro destination to the assignment editor. Verify: `swift test --filter OpenJoystickDriverPresentationTests` passes with tests for add, reorder and remove; the editor opens in the built app (screenshot-free check: list the accessibility labels with the existing GUI script in `Scripts/GUI`).
- [x] 3.6 Add localization keys and comments for the editor and CLI in all 22 bundles; review them. Verify: `python3 Scripts/Quality/check_localization_keys.py` passes.
- [x] 3.7 Document macros in `wiki/Bindings-and-Actions.md`, `wiki/Profile-File-Reference.md` and `wiki/Command-Reference.md` in present tense, with the hardware status as `Not checked`. Verify: `git diff --check` over the three files passes, and `rg -n "\bnow\b|\bnew\b|\bold\b|legacy|renamed"` on the added lines finds nothing.

## 4. Tap Counts and Repeat with Delay (REQ-32 to REQ-35)

- [x] 4.1 Write failing tests first: triple tap, count not reached, window from release to press, base destination wait, `doubleTap` rejected, turbo `initialDelayMs` and `maxRepeats`. Verify: `swift test --filter OpenJoystickDriverKitTests.MultiTapTests` fails for the stated reason.
- [x] 4.2 Replace `doubleTap` by `multiTap` in the model, coding, validation, `profile.schema.json`, `State+OutputDispatch.swift` and `ActionBindings.swift`; extend `turbo`. Verify: `swift test --filter OpenJoystickDriverKitTests.MultiTapTests` passes and the existing `ActionCollectionTests` and `MixedOutputTests` pass.
- [x] 4.3 Replace `--double-tap` by `--multi-tap` and add `--turbo-delay`, `--turbo-max`; show the added delay in `ojd binding list`. Verify: `swift test --filter OpenJoystickDriverCLITests` passes, including the test that `ojd binding set ... --double-tap 300:key:key-b` fails as an unknown option.
- [x] 4.4 Update the behavior sheet (`Sources/OpenJoystickDriverPresentation/Profiles/Editor/BindingBehaviorSheet+Body.swift`) for tap entries, delay display and turbo fields. Verify: `swift test --filter OpenJoystickDriverPresentationTests` passes.
- [x] 4.5 CLI localization keys in 22 bundles (replace `optionDoubleTap` in one commit; the GUI keys belong to 4.4); update `wiki/Bindings-and-Actions.md` and `wiki/Profile-File-Reference.md`; record the translation review in `design.md`. Verify: `python3 Scripts/Quality/check_localization_keys.py` passes and `rg -n "doubleTap|double-tap|DoubleTap" Sources/OpenJoystickDriverCLI Resources wiki docs Scripts` prints nothing; after 4.4 the same search over `Sources Tests` prints only the rejection tests.

## 5. System Actions (REQ-36 to REQ-39)

- [ ] 5.1 Write failing tests first with the stub performer: each `SystemKey` name sends down and up; Mission Control, open app, open URL and run Shortcut call the performer once with the right argument; a failing performer yields a named error and an Activity entry; `file:` URL rejected; secure input yields the named error; `TypeText` rejects non-press behaviors. Verify: `swift test --filter OpenJoystickDriverKitTests.SystemActionTests` fails for the stated reason.
- [ ] 5.2 Add the destinations, coding, validation and schema. Verify: the validation half of `SystemActionTests` passes and `./Scripts/ojd check schemas` passes.
- [ ] 5.3 Implement the engine path and the macOS performer in `Sources/OpenJoystickDriverMacOSPlatform` (event posting, `NSWorkspace`, `Process`). Verify: `swift test --filter OpenJoystickDriverKitTests.SystemActionTests` passes and `python3 Scripts/Quality/check_neutral_core_imports.py` passes.
- [ ] 5.4 Hardware check on this Mac: volume, mute, brightness, play/pause, Mission Control, open TextEdit, run an existing Shortcut, type `hello` into TextEdit, type into a password field. Verify: the operator's results are written in `docs/testing/system-actions.md` with macOS version from `sw_vers`; any failure is reported, not hidden, and the wiki says `Not checked` for each line without a result.
- [ ] 5.5 Add CLI targets (`system-key:`, `system:`, `open-app:`, `open-url:`, `shortcut:`, `text:`) and the editor destinations. Verify: `swift test --filter OpenJoystickDriverKitTests.CommandLine` and `swift test --filter OpenJoystickDriverPresentationTests` pass.
- [ ] 5.6 Localization keys in 22 bundles; document actions, permissions and the out-of-scope private-API list in `wiki/Bindings-and-Actions.md` and `wiki/Permissions-and-Security.md`. Verify: `python3 Scripts/Quality/check_localization_keys.py` and `git diff --check` over the two pages pass.

## 6. Profile Control Actions (REQ-40 to REQ-42)

- [ ] 6.1 Write failing tests first: switch by id, wrong model rejected, `Next` and `Previous` order and wrap, layer on, off and toggle, pause passes through and keeps the pause binding, pause releases macros, pause state clears on profile change and disconnect, Activity entry. Verify: `swift test --filter OpenJoystickDriverKitTests.ProfileControlActionTests` fails for the stated reason.
- [ ] 6.2 Add the three destinations to model, validation and schema; route `ProfileSwitch` to the existing activation path (`activateRemappingProfile` in `Sources/OpenJoystickDriverService`). Verify: `swift test --filter OpenJoystickDriverKitTests.ProfileControlActionTests` and `swift test --filter OpenJoystickDriverServiceTests` pass.
- [ ] 6.3 Show pause in the Controllers area, `ojd status` and the status item; add CLI targets and editor destinations. Verify: `swift test --filter OpenJoystickDriverPresentationTests` and `swift test --filter OpenJoystickDriverKitTests.CommandLine` pass.
- [ ] 6.4 Localization keys in 22 bundles; document in `wiki/Bindings-and-Actions.md` and `wiki/Remapping-Profiles.md`. Verify: `python3 Scripts/Quality/check_localization_keys.py` and `git diff --check` over the two pages pass.

## 7. Analog Regions (REQ-43 to REQ-45)

- [x] 7.1 Write failing tests first: ring edges with hysteresis, eight sectors, overlap rejected, release-before-press on a region change, three trigger bands, dual-stage plus bands rejected, touch rectangle contact. Verify: `swift test --filter OpenJoystickDriverKitTests.RegionSourceTests` fails for the stated reason.
- [x] 7.2 Add the three source cases to model, validation, schema and the source parser used by `ojd binding set`. Verify: the validation cases of `RegionSourceTests` and `./Scripts/ojd check schemas` pass.
- [x] 7.3 Implement activation in `Engine/Analog` reusing the stick deadzone and trigger hysteresis paths. Verify: `swift test --filter OpenJoystickDriverKitTests.RegionSourceTests` and `swift test --filter OpenJoystickDriverKitTests.StickRoutingTests` pass.
- [ ] 7.4 Add the region editor with a live position view in the Controller section. Verify: `swift test --filter OpenJoystickDriverPresentationTests` passes.
- [ ] 7.5 Localization keys in 22 bundles; document in `wiki/Sticks-Triggers-Touchpad-and-Motion.md` and `wiki/Bindings-and-Actions.md`. Verify: `python3 Scripts/Quality/check_localization_keys.py` and `git diff --check` pass.

## 8. Variable Pointer Speed (REQ-46, REQ-47)

- [ ] 8.1 Write failing tests first: trigger driver slows the stick pointer, stick-depth driver scale on each curve, gyro mouse and touch pointer obey it, scroll unchanged, unsupported driver rejected. Verify: `swift test --filter OpenJoystickDriverKitTests.PointerSpeedTests` fails for the stated reason.
- [ ] 8.2 Add `pointerSpeed` to model, validation and schema; apply it at the one engine point before the system sink. Verify: `swift test --filter OpenJoystickDriverKitTests.PointerSpeedTests` and `swift test --filter OpenJoystickDriverKitTests.TouchRoutingTests` pass.
- [ ] 8.3 Add the editor with the live scale and the `ojd profile set PROFILE pointerSpeed JSON` example. Verify: `swift test --filter OpenJoystickDriverPresentationTests` passes; the command in REQ-47 validates a temporary profile.
- [ ] 8.4 Localization keys in 22 bundles; document in `wiki/Sticks-Triggers-Touchpad-and-Motion.md` and `wiki/Profile-File-Reference.md`. Verify: `python3 Scripts/Quality/check_localization_keys.py` and `git diff --check` pass.

## 9. Gyro-to-Stick Template and Hardware Check (REQ-48, REQ-49)

- [ ] 9.1 Write failing tests first: the template output validates and equals the expected profile; a model without a motion sensor fails with the named error; other profiles are unchanged. Verify: `swift test --filter OpenJoystickDriverKitTests.GyroStickTemplateTests` fails for the stated reason.
- [ ] 9.2 Add `--template gyro-stick`, `--stick` and `--activation` to `ojd profile create`, and the template choice to the New profile sheet. Verify: `swift test --filter OpenJoystickDriverKitTests.GyroStickTemplateTests` and `swift test --filter OpenJoystickDriverPresentationTests` pass.
- [ ] 9.3 Write `docs/testing/gyro-stick.md` in the format of the files in `docs/testing/`, and the wiki section in `wiki/Sticks-Triggers-Touchpad-and-Motion.md` with `Not checked` for hardware. Verify: `git diff --check` passes.
- [ ] 9.4 Localization keys in 22 bundles. Verify: `python3 Scripts/Quality/check_localization_keys.py` passes.
- [ ] 9.5 Run the hardware check with a controller that has motion sensors (operator step). Verify: the operator's result is recorded in `docs/testing/gyro-stick.md` with controller, VID:PID, connection, OJD version and macOS version; the wiki line changes from `Not checked` only with that record.

## 10. MIDI Output (REQ-53, REQ-54)

- [ ] 10.1 Write failing tests first: schema rejections for a channel of 0 and 17, a note of 128 and a velocity of 0; engine tests with a fake `RemappingMIDIOutput` that assert the bytes of note-on, note-off and control change for a button and a trigger, no repeated value, and note-off before the source is removed on deactivation. Verify: `swift test --filter MIDIOutput` fails on each new test.
- [ ] 10.2 Add `MidiNote` and `MidiControlChange` to `Resources/Schemas/profile.schema.json` and the Swift model, the `RemappingMIDIOutput` protocol in the core, and the CoreMIDI implementation in `OpenJoystickDriverMacOSPlatform`; add the error code for a refused source and run `./Scripts/ojd errors regenerate --write`. Verify: the 10.1 tests pass, `./Scripts/ojd check schemas` passes and `python3 Scripts/Quality/check_neutral_core_imports.py` passes.
- [ ] 10.3 Editor, `ojd binding set` targets `midi-note:CHANNEL:NOTE[:VELOCITY]` and `midi-cc:CHANNEL:CONTROLLER`, localization keys in 22 bundles reviewed against `LOCALIZATION.md`, and a wiki section in `wiki/Bindings-and-Actions.md`. Verify: CLI tests for both targets pass and `python3 Scripts/Quality/check_localization_keys.py` passes.
- [ ] 10.4 Hardware check (operator or tester): a note and a control change reach a music app, and the source disappears when the profile is deactivated. Verify: the result is appended to `docs/testing/system-actions.md` with the OJD and macOS versions.

## 11. Spoken Phrases (REQ-55, REQ-56)

- [ ] 11.1 Write failing tests first: schema rejections for an empty text, 129 characters and an unknown voice; engine tests with a fake `RemappingSpeechOutput` for one press, `RestartOnPress` and stop on pause and deactivation. Verify: `swift test --filter SpeechOutput` fails on each new test.
- [ ] 11.2 Add `Speak` to the schema and model, the `RemappingSpeechOutput` protocol in the core and the `AVSpeechSynthesizer` implementation in `OpenJoystickDriverMacOSPlatform`. Verify: the 11.1 tests pass, `./Scripts/ojd check schemas` passes and `python3 Scripts/Quality/check_neutral_core_imports.py` passes.
- [ ] 11.3 Editor, `ojd binding set` target `speak:TEXT` with `--voice`, localization keys in 22 bundles reviewed against `LOCALIZATION.md`, and a wiki section. Verify: CLI tests pass and `python3 Scripts/Quality/check_localization_keys.py` passes.

## 12. Integration

- [ ] 12.1 Add the `CHANGELOG.md` entry under `0.6.0-alpha.2` (this is the only place for history words). Verify: `git diff --check` passes.
- [ ] 12.2 Run the full check list from the repository `CLAUDE.md`. The parser check `./Scripts/ojd test parsers-macos14` is not needed because no parser changes. Verify: `just check` exits 0; `openspec validate remapper-actions --strict` passes.
- [ ] 12.3 Run an end-to-end profile on the controller: a macro on a button, a triple tap, a trigger band, pointer speed on the left trigger, a profile switch, a pause, a MIDI note and a spoken phrase. Verify: the operator's result is appended to `docs/testing/system-actions.md` and reported with the OJD and macOS versions.
