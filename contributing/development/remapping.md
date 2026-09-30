# Remapping

Use this overview for profile actions and chord timing. Open the focused page for the input or processing feature you are changing.

- [Input samples and controller pairing](remapping-input-samples.md)
- [Calibration and fusion foundations](remapping-calibration.md)
- [Motion processing](remapping-motion.md)
- [Advanced stick, trigger, and physical-output controls](remapping-advanced-controls.md)

## `0.5.0-beta.5` Design

Advanced remapping extends the existing OJD profile library, deterministic Kit engine, app output router, and profile editor. The software scope below is implemented; external runtime and hardware validation are not claimed.

Physical input flows through normalization and remapping to virtual-controller and/or keyboard, pointer, and scroll output. OJD owns the complete session. There is no JSM process, JSM configuration interpreter, SDL dependency, or third-party state-injection endpoint.

| Capability | Existing foundation | Extension |
| --- | --- | --- |
| Output | Exclusive selection of virtual-gamepad or system-event remapping | Mixed output, virtual destinations, per-control consumption and passthrough |
| Bindings | Long hold, double tap, turbo, sequences | Separate activation actions, toggles, pulses, explicit release, multiple actions |
| Combinations | Simultaneous active-source chords and layers | Timed combinations, modifier chords, buffered consumption, binding and tuning overrides |
| Physical input | Buttons, D-pad, sticks, triggers | Timestamped motion, touch contacts, distinct extra buttons |
| Motion | No normalized motion event | Calibration, fusion, coordinate spaces, gyro mouse/stick |
| Stick and trigger processing | Scalar deadzone, gain, inversion, curves, digital threshold | Aim, flick, hybrid, area/ring, scroll, steering, lean, dual-stage triggers |
| Touch | Touchpad click button | Touch/click, grids, pointer, touch sticks, swipe directions |
| Multiple controllers | Exact runtime device identity | Explicit paired Joy-Con sessions and gyro selection |
| Physical output | Protocol-owned rumble and indicator capabilities | Mapping actions and channel ownership, supported adaptive-trigger effects |
| Authoring | Shared profiles, authenticated RPC, native CLI and editor | Native UI and CLI coverage for every supported capability |

Mapped controls replace their original virtual contribution unless passthrough is explicitly selected. Current system-event profiles retain their behavior. Profile and layer transitions, disconnect, permission loss, suspension, and shutdown release owned output and cancel scheduled actions. A failed mapping must not silently restore consumed input.

Filtering OJD's virtual reports does not hide the physical controller from another application. Isolation-dependent profiles require exclusive physical ownership, with acquisition failure reported separately from permissions and virtual publication. The IOKit HID backend requests ownership by opening each matched device with `kIOHIDOptionsTypeSeizeDevice`; closing it with the same option releases it.

## Status

Software scope implemented and covered by constructed tests: the schema-3 profile and action contract, deterministic combinations, consumption, replay, scheduling and cleanup, typed touch input and mappings, exact-identity paired Joy-Con sessions, calibrated motion processing, advanced stick, motion-steering, lean, and dual-stage trigger modes, capability-gated mapping-owned physical output, and one validated mutation path shared by the editor and CLI.

Not yet validated, because constructed tests cannot establish them:

- signed-runtime controller and virtual-device behavior
- physical controller isolation, motion direction and scale, touch, haptics, lighting, and adaptive triggers across supported USB and Bluetooth transports
- native visual, keyboard-only, VoiceOver, and localization review
- consumer recognition and end-to-end latency on supported macOS releases

## Native Action Collections

Only schema 3 profiles are accepted. The decoder rejects any other version immediately, before decoding profile fields; OJD does not migrate, reinterpret, or reset older profiles. Schema 3 assignments retain their primary destination and can contain an ordered `additional_actions` array. Each additional action has its own UUID, destination, behavior, and optional turbo, long-hold, double-tap, or pulse settings. Action IDs share the profile-wide uniqueness requirement. Additional actions count toward the 512-item mapping limit. Continuous actions use the assignment's axis tuning. Permission requirements include every action and its alternate destinations, including actions in inactive layers.

The assignment behavior sheet supports adding, removing, reordering, and editing additional actions. CLI `bind` and `layer bind` accept `--actions-json <JSON-array>` in the native action format. An omitted option preserves the collection; `[]` removes all additional actions. Nested CLI commands put the operation before the profile, for example `map layer bind <profile> --layer <uuid> --source button:south --target key:a`.

Implemented behaviors:

- `hold`: follow the physical control's press and release.
- `toggle`: alternate the owned output between pressed and released on each new press.
- `tap_on_press` and `tap_on_release`: emit a press/release pair on the selected edge. A release tap requires a matching press and is canceled when its assignment loses ownership.
- `pulse`: press for `pulse_duration_ms` (1...5000 ms, default 100). Physical release does not shorten the pulse. A new press extends the same action's deadline.
- `press`: press until an explicit release or lifecycle cleanup.
- `release`: release matching held destinations owned by the same controller and cancel their pulse/turbo timers. Contributions from other controllers remain owned by those controllers.

Collections dispatch in profile order. Independent actions retain separate activation timers; shared keyboard/modifier outputs use reference counts, and virtual contributions use the gamepad aggregator. Combination, motion, touch, and paired-controller behavior follows below.

## Reference Sources

The behavioral reference is [JoyShockMapper at bb69784488937e0a5e21988b966eccd9f04d504e][1] and the contributor's `JoyShockMapper-macos.zip`, SHA-256 `5f56191598774fa907f1b22aacc85bf46967a6159ed1b1933de258c2d816fb33`.

The archive differs from that revision in platform/build adaptations: macOS input posting, window/tray integration, platform definitions, build configuration, an additional C++ include, and an atomic quit flag with a main-thread AppKit loop. The digital-button, stick, motion, and SDL input implementations are unchanged. The port's virtual-gamepad and device-whitelisting factories return null. Its build artifacts and handoff notes are not OJD hardware evidence.

The port pins [GamepadMotionHelpers at 39b578aacf34c3a1c584d8f7f194adc776f88055][2]. Adapted code must retain the applicable copyright and license notices. JSM's license credits Julian "Jibb" Smart and Nicolas Lessard; dependent algorithms retain their own attribution.

Upstream reports guide regression tests, not automatic feature additions or accepted patches:

- [Simultaneous presses, #157](https://github.com/Electronicks/JoyShockMapper/issues/157).
- [Held output after a stick-mode change,
  #89](https://github.com/Electronicks/JoyShockMapper/issues/89).
- [Paired Joy-Con stick input, #188](https://github.com/Electronicks/JoyShockMapper/issues/188).
- [Motion deadzone units, PR #194](https://github.com/Electronicks/JoyShockMapper/pull/194).
- [Edge extra buttons and touch grids, PR
  #187](https://github.com/Electronicks/JoyShockMapper/pull/187).

[1]: https://github.com/Electronicks/JoyShockMapper/tree/bb69784488937e0a5e21988b966eccd9f04d504e
[2]: https://github.com/JibbSmart/GamepadMotionHelpers/tree/39b578aacf34c3a1c584d8f7f194adc776f88055

## Chord Timing

Native schema-3 chords accept `mode: "simultaneous"` and `window_ms` from 1 to 1000 (default 50). All constituent presses must fall within that inclusive window. Releasing and pressing a source again replaces its press timestamp. Omitted mode retains the legacy `modifier` behavior, which requires held sources without a simultaneous-press deadline.

Modifier-chord sources are owned by the modifier recognizer while that chord is effective. Their individual assignments, additional actions, and raw passthrough contributions stay suppressed. When the chord completes, it consumes its constituent presses and any sequence completion that depends on them. Releasing a constituent retires the chord without replaying the suppressed source action.

The CLI accepts `map chord add <profile> --sources button:south,button:east --target key:space --mode simultaneous --window-ms 75` (on one command line). Invalid timing is rejected before profile mutation. The native combination sheet exposes the same mode and simultaneous window.

Simultaneous chords buffer constituent presses until resolution. A match consumes those presses; an unmatched timeout replays a held action once, and an early release replays a press/release pair. Passthrough replay uses the virtual-state aggregator, including a retained axis sample for a quick direction release. A completed smaller chord waits while a higher-priority overlapping chord can still complete. Higher source count wins, then profile order. Releasing a completed smaller chord commits it before its release; releasing a larger chord does not activate a smaller chord from its already-consumed controls. Disjoint chords can remain active together. Layer transitions and controller teardown cancel pending presses.

The engine uses a nondecreasing clock for each controller session. Backward input and tick timestamps clamp to that controller’s latest evaluated time; release edges are still processed. This prevents reversed turbo phases or shortened new pulses; controllers' input clocks remain independent.

Sequence history records buffered presses in their original input order and matches the original first-to-last press interval. Retain a completed sequence that depends on unresolved presses separately so later input cannot displace it. Replaying its required presses commits it once; chord consumption or a layer transition cancels it. Completing a sequence clears its history, so each deferred completion owns at least one distinct pending press. History remains bounded by the longest configured sequence plus the number of pending chord presses.

Focused tests cover modifier consumption, additional-action suppression, passthrough ownership, sequence/chord interaction, bounded history, controller teardown, and layer-transition cleanup. Native controls compile and draft persistence is tested; visual and VoiceOver validation remain pending.
