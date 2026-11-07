## Context

Facts read from the repository on 2026-10-25:

- Destinations in `Sources/OpenJoystickDriverKit/Remapping/Profile/Controls/Destination.swift`: Keyboard, GamepadButton, GamepadDpad, GamepadAxis, MouseButton, MouseMovement, Scroll, Physical. An action (`Action.swift`) has a destination, a behavior, `pulseDurationMs`, `turbo`, `longHold`, `doubleTap`.
- Engine output goes through `RemappingEngineAction` (`Engine/Core/Sink.swift:374`): `system`, `gamepad`, `physical`. The `system` case carries `RemappingSystemInputAction` (keys, pointer buttons, pointer and scroll deltas), posted by `Sources/OpenJoystickDriverService/Remapping/SystemEvents/CoreGraphicsSystemInputSink+Posting.swift`.
- Post Event access is checked with `CGPreflightPostEventAccess()` (`Sources/OpenJoystickDriverMacOSPlatform/Permissions/MacOSAccessControlSystem.swift:24`). `requiresSystemInputAccess` (`Profile/Output/OutputPolicy.swift:126`) decides whether a profile needs it, through `containsDestination(where: \.isSystemInput)`.
- `sequence` (`Engine/Chords/SequenceHistory.swift`) recognizes inputs; there is no output macro.
- Timed output exists for turbo and pulse (`Engine/Actions/TurboOutput.swift`, tests `PulseTests.swift`, `ScheduleTests.swift`).
- Gyro to stick exists: `RemappingGyroOutputMode` has `leftStick` and `rightStick` (`Profile/Motion/GyroOutput.swift`), routed by `Engine/Motion/GyroRouting.swift` through `updateGyroStick`; validation requires the virtual gamepad (`Profile/Validation/Profile+Validation.swift:53`); tests with `rightStick` are in `Tests/OpenJoystickDriverKitTests/Remapping/Engine/Motion/GyroRoutingTests+Activation.swift` and `+SampleTiming.swift`. Hardware behavior is not verified (the wiki says so). No profile template or preset mechanism exists in the repository.
- Sources: `touch:SURFACE:grid` and `axis:NAME:negative|positive` exist (`wiki/Bindings-and-Actions.md`); stick rings, N pressure bands and free rectangles do not.
- The core must not import AppKit (`docs/development/source-topology.md` lists the imports Kit may use); macOS code lives in `OpenJoystickDriverMacOSPlatform`.
- Three repository rules shape every decision: no compatibility before v1.0.0, no hidden behavior (a failure is named, tested and shown), and no history words in docs or comments.
- Decisions of the user on 2026-10-25: OJD moves to PolyForm Noncommercial 1.0.0 plus a commercial license; this change ships in `0.6.0-alpha.2`.

## Goals / Non-goals

Goals: the scope in `proposal.md`, each action complete across schema, engine, GUI, CLI, localization, docs and tests, in `0.6.0-alpha.2`.

Non-goals: private APIs, stick gestures, keyboard or mouse as input, InputConfig file import.

## Decisions

### D1. New Destinations, Not a New Layer

Macro, SystemKey, SystemAction, OpenApplication, OpenURL, RunShortcut, TypeText, ProfileSwitch, LayerSet and Pause are new `RemappingDestination` cases. An action keeps its shape, so behaviors, layers, chords and sequences work with them unchanged. Reason: one place to validate, to edit and to document. Cost: the destination `Kind` and coding switch grow; each case keeps the strict `fields` check.

Trigger-only destinations (all but SystemKey) take exactly `Hold`, `TapOnPress`, `TapOnRelease` and `Press`; `Toggle`, `Release` and `Pulse` fail validation with `bindingBehaviorConflict`. They act once on the press, and the release does nothing. Profile control destinations are stricter and take only `Hold` and `TapOnPress`. `SystemKey` sends key down on the press and key up on the release, takes every behavior, and does not take turbo. Validation names the rejected behavior.

### D2. Macros Are Profile Data, Scheduled by the Engine

`macros` is a top-level profile array; a `Macro` destination holds the macro id. The engine runs a macro as a per-controller state machine on the monotonic clock it already uses for turbo and pulse; the macro adds no thread or timer of its own. Reason: the engine is tested with a fake clock (`ScheduleTests`), and a macro that sleeps on its own thread could be neither tested nor stopped on a profile change. Steps send the same `RemappingSystemInputAction` and gamepad updates that bindings do, so output ownership and the emission barrier (`Sink.swift`) apply to macros too.

### D3. Runaway Control

Risk: a macro keeps keys down or never ends. Controls, all visible: nesting is forbidden (no recursion); steps, run time and repeat are bounded at load (REQ-30) so a bad macro fails validation instead of being cut short; every stop path releases held outputs through one function (REQ-29); macro outputs are reference counted with all other held outputs, so the existing fail-closed path (`Engine/Core/Engine+FailClosed.swift`) releases them without a macro-specific call; `whileRunning` has two named values; `WhileHeld` ends only on release, disconnect, pause, profile change, permission loss or shutdown. A test per stop path asserts that no output stays down. All numeric limits are proposed.

### D4. `doubleTap` Becomes `multiTap`

One concept (tap count) instead of `doubleTap` plus a second key. Under the no-compatibility rule the old key fails like any invalid input, and the schema, engine (`State+OutputDispatch.swift`, `ActionBindings.swift`), CLI, GUI, docs and tests change together. Cost: alpha profiles with `doubleTap` stop loading. Veto-able: the alternative is to keep `doubleTap` and add `tapCount`, which leaves two ways to say the same thing.

Latency: with entries for counts above one, the base destination waits for the longest window to know that no further tap follows. Double tap has the same wait today, and REQ-33 shows it in the editor and CLI.

Repeat with delay extends `turbo` (`initialDelayMs`, `maxRepeats`) instead of adding `repeat`, since turbo already is repeat-while-held.

### D4 Localization Review (CLI Keys)

The CLI help and error keys for `--multi-tap`, `--turbo-delay` and `--turbo-max` (`cli.binding.group.optionMultiTap`, `optionTurboDelay`, `optionTurboMax`, `multiTapFormat`) are in all 22 bundles with a translator comment each; `optionDoubleTap` is gone and the comment of `alternateFormat` names only `--long-hold`. Each value was read back against `en-US`, its call site and LOCALIZATION.md:

- Meaning: `COUNT` and `MS` stay as written in every language, because the user types them; a tap is a touch or press of the control, not a double of anything, so the verbs follow the neighbouring `optionLongHold` and `optionTurboRate` values of each language (for example `Needs` becomes the verb that file already uses). `--turbo-delay` says the time before the first repeat, `--turbo-max` says the number of repeats after the first press.
- Punctuation: native full stops (`。`, `।`) and spacing rules per file, `’` in French and Italian, no ASCII quotes, ranges as words or the native range sign (`0~2500` in Korean, `0 〜 2500` in Japanese), and `ms` kept as the unit symbol except in Russian (`мс`). `fr-CA` and `fr-FR` take the same text because it has no `; ? !`.
- Not confirmed by a native speaker: every translation is a reviewed machine translation, as for the rest of the catalog. Thai and Arabic wording of `multiTap` (touch versus press) most needs one.
- `turboPair` still says that `--turbo-rate` and `--turbo-duty` go together; it also covers `--turbo-delay` and `--turbo-max` given alone, since those two need both.

### D4 Localization Review (Behavior Sheet Keys)

The behavior sheet keys `ui.profiles.addMultiTap`, `multiTap`, `tapCount`, `tapDelay`, `turboDelay`, `turboLimit` and `turboMax` are in all 22 bundles with a translator comment each; `ui.profiles.doubleTap` is gone, the comment of `ui.profiles.tapWindow` now says that the window runs from one tap's release to the next press, and the Remove button reuses `action.remove`. Each value was read back against `en-US`, its call site in `BindingBehaviorSheet+MultiTap.swift` and `BindingBehaviorSheet+Body.swift`, and LOCALIZATION.md:

- Meaning: `multiTap` is a heading and `addMultiTap` a button, so they stay a noun phrase and a verb phrase; "tap" follows the verb already used for `tapWindow` in each language (press in French and Russian, touch in Spanish, Italian and Turkish), so one file keeps one term. `tapDelay` is a note, not a label: it says the base destination can wait the given time, and `%@` carries the number with `ms` from `String(format:)`, so a translation may move it. `turboDelay` is the time from the press to the first repeat, `turboLimit` a switch that turns the cap on, and `turboMax` the cap itself.
- Punctuation: native ellipsis not needed (no value opens a further step), no ASCII quotes, `ms` kept as the unit symbol in the argument.
- Not confirmed by a native speaker: every translation is a reviewed machine translation, as for the rest of the catalog. `tapDelay` in Arabic, Hindi, Thai and Korean (word order around `%@`) most needs one.
- Placement: each key sits at its alphabetical spot in the `ui.profiles` run that starts at `addChord`; the run is not sorted across the whole file.
- The tap count picker shows the digits 2 to 5 as numbers, which need no key.

### D5. System Actions Use Public APIs Only

| Action | API | Documentation | Permission to expect (the task records the result) | Out of scope |
| --- | --- | --- | --- | --- |
| Media, volume, brightness, keyboard illumination keys: event | `NSEvent.otherEvent(with: .systemDefined, ..., subtype:data1:data2:)`, then `NSEvent.cgEvent`, then `CGEvent.post(tap:)` (the documented CGEvent initializers cover keyboard, mouse and scroll events, not system-defined ones) | [otherEvent](https://developer.apple.com/documentation/appkit/nsevent/otherevent(with:location:modifierflags:timestamp:windownumber:context:subtype:data1:data2:)) (macOS), [cgEvent](https://developer.apple.com/documentation/appkit/nsevent/cgevent) (macOS 10.5), [post(tap:)](https://developer.apple.com/documentation/coregraphics/cgevent/post(tap:)) (macOS 10.4) | Post Event | DisplayServices and IODisplay brightness calls |
| Media, volume, brightness, keyboard illumination keys: codes | `NX_KEYTYPE_*` from `IOKit/hidsystem/ev_keymap.h`; `NX_SUBTYPE_AUX_CONTROL_BUTTONS` (8) from `IOKit/hidsystem/IOLLEvent.h` | unconfirmed: both are in the macOS SDK headers (read on this Mac), with no documentation page found | Post Event | |
| System-defined event `data1` layout | key code and key-down state packed in `data1` | unconfirmed: no documentation found for the layout | Post Event | |
| Mission Control: launch | `NSWorkspace.openApplication(at:configuration:completionHandler:)` | [openApplication](https://developer.apple.com/documentation/appkit/nsworkspace/openapplication(at:configuration:completionhandler:)) (macOS 10.15) | none expected | `CoreDockSendNotification`, SkyLight, CGS; Launchpad, App Exposé and Show Desktop actions that need them |
| Mission Control: path | `/System/Applications/Mission Control.app` | unconfirmed: the path exists on this Mac (macOS 27.2); no documentation page found | none expected | |
| Open application | `NSWorkspace.openApplication(at:configuration:completionHandler:)` | [openApplication](https://developer.apple.com/documentation/appkit/nsworkspace/openapplication(at:configuration:completionhandler:)) (macOS 10.15) | none expected | |
| Open URL | `NSWorkspace.open(_:configuration:completionHandler:)` | [open](https://developer.apple.com/documentation/appkit/nsworkspace/open(_:configuration:completionhandler:)) (macOS 10.15) | none expected | URLs that do not parse |
| Run Shortcut | `Process` runs `/usr/bin/shortcuts run NAME`; exit status 0 on success, 1 on error; a shortcut that asks for input pauses the process | [Shortcuts User Guide](https://support.apple.com/guide/shortcuts-mac/apd455c82f02/mac); `/usr/bin/shortcuts --help` on this Mac lists `run` | none expected; Shortcuts may ask its own question | AppleScript to Shortcuts Events (would need Automation) unless the task finds `shortcuts run` insufficient |
| Type text: events | `CGEvent(keyboardEventSource:virtualKey:keyDown:)`, then `keyboardSetUnicodeString(stringLength:unicodeString:)` | [init](https://developer.apple.com/documentation/coregraphics/cgevent/init(keyboardeventsource:virtualkey:keydown:)) (macOS 10.4), [keyboardSetUnicodeString](https://developer.apple.com/documentation/coregraphics/cgevent/keyboardsetunicodestring(stringlength:unicodestring:)) (macOS 10.4) | Post Event | none |
| Type text: secure input | `IsSecureEventInputEnabled()` | unconfirmed: [TN2150](https://developer.apple.com/library/mac/technotes/tn2150/_index.html) names the function without a signature, and states that secure input stops keyboard events reaching event taps, HID seizing and `GetKeys`; its effect on posted events is not documented | Post Event | |

The `data1` layout of the system-defined event is a convention rather than a documented contract. The task for REQ-36 therefore ends with a hardware check on this Mac, and the wiki says `Not checked` until it passes. If a named API behaves differently on macOS 27, the task changes this table first. Every row above carries a documentation URL or `unconfirmed`; each `unconfirmed` row is an open question below.

Boundary: the core declares `RemappingSystemActionPerforming` (one async method per action kind that returns a typed result or a named error). `OpenJoystickDriverMacOSPlatform` implements it with AppKit and Core Graphics. Reason: the neutral-core import check forbids AppKit in the core, and a test double lets engine tests run without macOS services.

### D6. Permissions: Name Them, Never Swallow Them

`action-permissions` defines one preflight and one error shape. The service checks before acting and reports a coded error (added to `Resources/ErrorCodes.json`, then regenerated) that carries the permission and action names. `requiresSystemInputAccess` is extended so the needed-permission list is computed from destinations, including layers, as it is today. Risk: TCC attributes a permission to the responsible process; the service that posts events may not be the app the user sees in System Settings. The task for REQ-50 records which process holds each permission on a clean macOS 27 user and writes it in `wiki/Permissions-and-Security.md`.

### D7. Launching Actions Need a Confirmation at Activation

A profile is a shareable file. An imported profile that opens URLs, runs a Shortcut or types text is an attack surface. REQ-51 requires an explicit confirmation listing those actions at activation, and no action runs from a profile the user did not activate. Any URL scheme is allowed, so app schemes such as `steam:` work; the confirmation lists each URL in full, so the user sees every scheme before the first activation (the user, 2026-10-25). This follows the pattern of `--allow-empty`.

### D8. Regions Are Sources

`StickRegion`, `TriggerBand` and `TouchArea` are `RemappingSource` cases that become active or inactive like a button, so every behavior, macro, layer and chord works with them. Non-overlap is validated, so the active region is unique and release-before-press ordering is simple. Hysteresis is explicit and stored in the profile. Reuse: the stick deadzone path (`Engine/Analog/StickTransform.swift`) and the trigger hysteresis (`Engine/Analog/TriggerRuntime.swift`).

### D9. Pointer Speed Is One Profile-Level Modifier

`pointerSpeed` multiplies all pointer movement at one point in the engine (before the system sink), so stick pointer modes, touch pointer, gyro mouse and `MouseMovement` destinations all obey it. A per-mode setting would repeat the same fields in four places. Layers do not override it; see the open questions.

The scale reads the driver from each device's own profile and live axis, and the engine multiplies the scales of all devices that set a `pointerSpeed`. A product, not per-controller scaling, because a `.system` pointer action carries no controller, and `MouseMovement` totals add the contributions of every controller before they reach the sink. With one controller, which is the common case, the product is that controller's scale.

The controller does not report a driver when its capabilities (`ProtocolDriverRegistry().profileCapabilities(for:)`) lack the trigger or stick. The model cannot check this, because it has no capability data, so `ojd profile set`, `ojd profile import` and the editor's save check it where the controller model is known. A model with no catalog entry is not checked.

### D10. Gyro-to-Stick: Confirm, Template, Hardware Check

Read in code (see Context): the engine and validation already support `gyroOutput` stick modes with a virtual gamepad, and tests cover right-stick output. Missing: a guided way to set it up, wiki text that finds it, and a hardware result. The change adds a `gyro-stick` template (a profile-creation option, not a new document kind), a wiki section, and `docs/testing/gyro-stick.md`. It does not change gyro math. Until an operator runs the check, no text says the output works on hardware.

### D11. License and Attribution

OJD moves to PolyForm Noncommercial 1.0.0 plus a commercial license (the user, 2026-10-25). InputConfig is MIT, so its code may be used with its notice kept in `THIRD_PARTY_NOTICES.md`; GPL code may not be used. This change takes ideas, not code. Any copied code and its notice go in together in one commit, and the commercial license must not conflict with that notice.

### D12. MIDI and Speech Are Output Kinds Behind Core Protocols

`MidiNote`, `MidiControlChange` and `Speak` are destinations like `Keyboard`. The core declares `RemappingMIDIOutput` and `RemappingSpeechOutput` protocols, because `Sources/OpenJoystickDriverKit` may not import CoreMIDI or AVFoundation (`docs/development/source-topology.md` lists the imports Kit may use); `OpenJoystickDriverMacOSPlatform` implements them with a virtual CoreMIDI source and `AVSpeechSynthesizer`. The MIDI source exists only while an active profile uses it, so a Mac without such a profile shows no extra MIDI device. Neither needs Accessibility access. Speech uses `RestartOnPress` so a repeated press never queues phrases.

## Risks and Trade-Offs

| Risk | Effect | Mitigation |
| --- | --- | --- |
| Macro runaway | Stuck keys, flood of events | D3: validated bounds, one release path, a test per stop path |
| Permission lost or never granted | Action does nothing | D6: preflight and named coded errors in four places; no silent fallback |
| Latency | Multi-tap delays the base destination; macro steps jitter | REQ-33 shows the delay; macros promise order and minimum delay only, and the hardware check records measured jitter |
| Private-API pressure | Users ask for brightness, Show Desktop | Out of scope; the proposal names it and the wiki says to bind a keyboard shortcut |
| Shared profiles run actions | Launch or typing from a file | D7 confirmation listing each URL |
| Event-layout convention for system keys | A macOS update changes it | Hardware check per macOS release |
| Schema churn | `doubleTap` profiles stop loading | Stated as **BREAKING**; CHANGELOG entry in `0.6.0-alpha.2` |
| Localization volume | Many keys in 22 bundles | Each task adds keys, comments and a review against LOCALIZATION.md before the next task |

## Decisions of the User (2026-10-25)

- `multiTap` replaces `doubleTap` (D4).
- The limits are half of the first draft: 16 macros per profile, 32 steps, a repeat count of 1 to 500, waits of 0 to 5000 ms, one pass at most 30 s, a counted run at most 5 min, turbo `initialDelayMs` 0 to 2500 and `maxRepeats` 1 to 500, `TypeText` 1 to 128 characters, Shortcut names 1 to 50 characters.
- Any URL scheme is allowed, and the activation confirmation stays (D7).
- MIDI output and spoken phrases are in scope (D12).

## Open Questions

1. Should a layer be able to override `pointerSpeed`?
2. Should `Next` and `Previous` profile switching use name order, or a user-defined cycle list in the profile?
3. The tap count range 2 to 5 and the pointer scale range 0 to 10 are not yet confirmed.
4. Which documentation defines the `NX_KEYTYPE_*` codes, `NX_SUBTYPE_AUX_CONTROL_BUTTONS` and the `data1` layout of a system-defined key event? Only SDK headers were found; the REQ-36 hardware check decides.
5. Which documentation names the Mission Control application path? Only its presence on this Mac was read.
6. What is the signature of `IsSecureEventInputEnabled`, and does secure event input block posted keyboard events? TN2150 covers event taps only; the REQ-36 hardware check decides.

None of these blocks a task.
